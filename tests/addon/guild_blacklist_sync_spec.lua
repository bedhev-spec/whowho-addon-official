-- Simulated Forever transport only. Load every module through the production TOC.
local root=arg[1] or "."
local H=dofile(root.."/tests/addon/harness.lua")
local PREFIX="WhowhoGuildBL1"
local count=0
local function check(condition, message)
    assert(condition,message)
    count=count+1
end

local function bus()
    local b={time=100, clients={}, pending={}, packets={}}
    function b:advance(elapsed)
        local deadline = self.time+elapsed
        while true do
            local index, time
            for i, pending in ipairs(self.pending) do
                if pending.time<=deadline and (not time or pending.time<time) then index,time=i,pending.time end
            end
            if not index then break end
            self.time=time
            table.remove(self.pending,index).fn()
        end
        self.time=deadline
    end
    function b:client(name, settings)
        settings=settings or {}
        local c={name=name, region=3, guild=101, online=true,legacy=settings.legacy,
            character=settings.character or "Current Character", inGuild=settings.inGuild}
        if settings.guild ~= nil then c.guild=settings.guild end
        local config={region=3,time=100,db=settings.personal}
        local p,s,e=H.fresh(root,settings.prefs,nil,config)
        c.p,c.s,c.e,c.g,c.a=p,s,e,p.GuildBlacklist,p.manual
        e.WhowhoGuildBlacklistDB=settings.shared
        e.GetCurrentRegion=function() return c.region end
        e.GetServerTime=function() return math.floor(self.time)+(settings.clockOffset or 0) end
        e.GetTime=function() return self.time end
        e.IsInGuild=function()
            if c.inGuild ~= nil then return c.inGuild end
            return c.guild ~= false
        end
        e.UnitNameUnmodified=function() return c.character:match("^(%S+) (.+)$") end
        e.C_Club={GetGuildClubId=function() return c.guild end}
        e.C_Timer={After=function(elapsed, fn)
            if c.timerThrows then error("virtual timer failure") end
            self.pending[#self.pending+1]={time=self.time+elapsed, fn=function() if c.online then fn() end end}
        end}
        e.C_ChatInfo={
            InChatMessagingLockdown=function() return c.locked == true end,
            RegisterAddonMessagePrefix=function(prefix)
                assert(prefix==PREFIX)
                return settings.registerResult or 0
            end,
            SendAddonMessage=function(prefix, message, channel, target)
                assert(prefix==PREFIX and channel=="GUILD" and target==nil and #message<=240)
                self.packets[#self.packets+1]={client=c, message=message,time=self.time}
                if c.sendResult then
                    local result=c.sendResult
                    if type(result)=="function" then result=result(message) end
                    if result~=0 then return result end
                end
                for _, peer in ipairs(self.clients) do
                    if peer.online and (peer==c and not c.noEcho or peer~=c and not self.partitioned)
                        and peer.region==c.region and peer.guild==c.guild
                        and (not peer.legacy or message:match("^[HQE]|")) then
                        -- Older peers use marked Q as ordinary catch-up and neither send nor receive A.
                        local seen=peer.legacy and message:gsub("^(Q|[^|]+|)0(%d+%.)","%1%2") or message
                        peer.s:event("CHAT_MSG_ADDON",prefix,seen,channel,name,"",0,0,"",0)
                    end
                end
                return 0
            end,
        }
        self.clients[#self.clients+1]=c
        s:event("ADDON_LOADED","WhoWho")
        s:event("PLAYER_ENTERING_WORLD",true,false)
        return c
    end
    return b
end

local function add(c, name, class, note, reasons)
    local a=c.a
    local evidence=class and {store=a.store, region=c.region, name=name, guid="private-guid", class=class,
        faction="Alliance", source="Target", at=math.floor(c.e.GetServerTime())}
    local saved=assert(a.save(nil,"blacklist",name,note or "private note",nil,reasons or {"spam"},false,evidence))
    return assert(a.store.get(saved.id))
end

local function rows(c)
    local result={}
    for _, row in ipairs(c.g.list()) do result[row.name]=row end
    return result
end

do
    local b=bus()
    local a=b:client("Cancelled Writer")
    b:advance(5)
    local scope=assert(a.g.context())
    local before=#b.packets
    local active=true
    a.e.GetServerTime=function() active=false; return math.floor(b.time) end
    check(a.g.add("Cancelled Guild",{"other"},"Approved note",scope,function() return active end)=="unavailable",
        "native clock reentrancy invalidates direct Add ownership before publication")
    check(not rows(a)["Cancelled Guild"] and not a.e.WhowhoGuildBlacklistDB,
        "a cancelled direct Add leaves no durable Guild row")
    b:advance(5)
    check(#b.packets==before,"cancelled direct Add queues no transport work")
end

local function share(c, record, scope, shareNote)
    return c.g.share(record,scope,{reasonIds=record.reasonIds,note=shareNote == true and record.note or nil})
end

local function event(c, payload, prefix, channel, sender)
    c.s:event("CHAT_MSG_ADDON",prefix or PREFIX,payload,channel or "GUILD",sender or "Fake Peer")
end

local function detailPackets(key, token, body)
    local encoded=body:gsub(".",function(byte) return string.format("%02x",byte:byte()) end)
    local packets, count={},math.ceil(#encoded/160)
    for index=1,count do
        packets[index]=string.format("D|%s|%s|%d|%d|%s",key,token,index,count,
            encoded:sub((index-1)*160+1,index*160))
    end
    return packets
end

do
    local b=bus()
    local a=b:client("Count Requester")
    local first=b:client("First Respondent")
    local second=b:client("Second Respondent")
    local legacy=b:client("Older Client",{legacy=true})
    local other=b:client("Other Guild")
    other.guild=202
    second.sendResult=function(message)
        if message:match("^A|") and not second.throttled then second.throttled=true; return 8 end
        return 0
    end
    local scope=a.g.context()
    local refreshes={}
    a.p.Shell.RefreshGuildBlacklist=function()
        refreshes[#refreshes+1]=a.g.peerCount(scope) or "unavailable"
    end
    b:advance(5)
    check(a.g.peerCount(scope)==nil and a.g.requestSync() and not a.g.requestSync(),
        "opening during ordinary startup cooldown queues one count sample")
    b:advance(26)
    local nonce, queryAt
    for _, packet in ipairs(b.packets) do
        if packet.client==a then
            local marked=packet.message:match("^Q|3:101|(0%d+%.%d+)$")
            if marked then nonce,queryAt=marked,packet.time end
        end
    end
    check(nonce and queryAt==130 and a.g.peerCount(scope)==nil and #refreshes==0,
        "the count uses one paced legacy-compatible query and stays pending")
    b:advance(9)
    local acknowledgements={}
    for _, packet in ipairs(b.packets) do
        if packet.message:match("^A|") then
            check(packet.message=="A|3:101|"..nonce,"acknowledgement carries only scope and nonce")
            acknowledgements[packet.client]=(acknowledgements[packet.client] or 0)+1
        end
    end
    check(not acknowledgements[a] and not acknowledgements[legacy] and not acknowledgements[other] and acknowledgements[first]==1
        and acknowledgements[second]==2 and a.g.peerCount(scope)==nil,
        "hidden empty peers reply, throttling retries once, and the own echo cannot reply")
    event(a,"A|3:101|"..nonce,nil,nil,first.name)
    event(a,"A|3:202|"..nonce,nil,nil,"Wrong Guild")
    event(a,"A|3:101|01.99999",nil,nil,"Wrong Nonce")
    event(a,"A|3:101|"..nonce,nil,"PARTY","Wrong Channel")
    event(a,"A|3:101|"..nonce,nil,nil,a.s.secret)
    b:advance(2)
    check(a.g.peerCount(scope)==2 and refreshes[1]==2 and #refreshes==1
        and not a.e.WhowhoGuildBlacklistDB and not first.e.WhowhoGuildBlacklistDB,
        "settlement counts unique valid respondents without writing guild storage")
    event(a,"A|3:101|"..nonce,nil,nil,"Too Late")
    check(a.g.peerCount(scope)==2,"a late response cannot change a settled sample")
    b:advance(60)
    check(a.g.peerCount(scope)==nil and refreshes[2]=="unavailable" and #refreshes==2,
        "expiry clears the count with one repaint and no replacement query")
end

do
    local b=bus()
    local a=b:client("Retry Requester")
    b:advance(5)
    local scope=a.g.context()
    local nonces={}
    a.sendResult=function(message)
        local nonce=message:match("^Q|3:101|(0%d+%.%d+)$")
        if nonce then
            nonces[#nonces+1]=nonce
            if #nonces==1 then
                event(a,"A|3:101|"..nonce,nil,nil,"Revoked Response")
                return 3
            end
            event(a,"A|3:101|"..nonces[1],nil,nil,"Old Response")
        end
        return 0
    end
    check(a.g.requestSync(),"explicit sync queues a sampled retry when open during cooldown")
    b:advance(42)
    check(#nonces==2 and nonces[1]~=nonces[2] and a.g.peerCount(scope)==0,
        "a successful retry settles to zero and discards synchronous replies from its failed request")
    a.region=4
    local moved=a.g.context()
    check(moved~=scope and a.g.peerCount(scope)==nil and a.g.peerCount(moved)==nil,
        "changing region invalidates the former sample")
end

do
    local b=bus()
    local a=b:client("Bounded Respondent")
    b:advance(4)
    for index=1,15 do
        local sender="Requester "..index
        local query="Q|3:101|01."..index
        event(a,query,nil,nil,sender)
        event(a,query,nil,nil,sender)
    end
    local count, seen=0,{}
    b:advance(20)
    for _, packet in ipairs(b.packets) do
        if packet.message:match("^A|") then
            assert(not seen[packet.message] and packet.time > 104 and packet.time < 116,
                "acknowledgements must be jittered, within deadline and deduplicated")
            seen[packet.message]=true
            count=count+1
        end
    end
    check(count>=1 and count<=8,"there are at most eight queued acknowledgements under a burst")
    event(a,"Q|3:101|02.29",nil,nil,"Departed Requester")
    a.guild=202
    a.s:event("PLAYER_GUILD_UPDATE","player")
    local before=#b.packets
    b:advance(12)
    for index=before+1,#b.packets do
        check(not b.packets[index].message:match("^A|3:101|"),"a scope change cannot send a former guild acknowledgement")
    end
end

do
    local b=bus()
    local a=b:client("Guild Only Author")
    local peer=b:client("Guild Only Receiver")
    b:advance(5)
    local scope=a.g.context()
    local personal, db=a.a.store,a.e.WhowhoAddressBookDB
    local name, note="Guild Only","Exact public note"
    check(a.g.add(name,{"fraud","spam"},note,scope)=="shared","a validated direct entry needs no personal record")
    b:advance(5)
    local row=rows(peer)[name]
    check(row and not row.class and row.note==note and table.concat(row.reasonIds,",")=="fraud,spam",
        "direct share broadcasts explicit reasons and note through the existing row and detail queues")
    check(a.a.store==personal and a.e.WhowhoAddressBookDB==db and not a.a.store.find(3,name)
        and not peer.a.store.find(3,name),"Guild-only Add leaves both personal addresses untouched")
    check(a.g.add(name,{"fraud"},"",scope)=="unchanged" and rows(a)[name].note==note,
        "the direct duplicate is idempotent and an empty note preserves the existing shared note")
    check(a.g.add("One",{"fraud"},nil,scope)=="invalid_name"
        and a.g.add("Two Parts",{"madeup"},nil,scope)=="invalid_reasons"
        and a.g.add("Two Parts",{"fraud"},"\t",scope)=="invalid_note"
        and a.g.add("CURRENT Character",{"fraud"},nil,scope)=="self",
        "direct Add requires a complete nonself identity, reason, and shareable note")
    local readSelf=a.e.UnitNameUnmodified
    a.e.UnitNameUnmodified=function() error("identity failed") end
    check(a.g.add("Unreadable Self",{"fraud"},nil,scope)=="unavailable","direct Add fails closed on an unreadable self")
    a.e.UnitNameUnmodified=function()
        a.guild=404
        return readSelf()
    end
    check(a.g.add("Changed Scope",{"fraud"},nil,scope)=="unavailable"
        and a.g.add("Stale Form",{"fraud"},nil,scope)=="unavailable"
        and not rows(a)["Changed Scope"] and not rows(peer)["Stale Form"],
        "direct Add revalidates scope after self evidence and rejects old forms")
end

do
    local b=bus()
    local a=b:client("First Sender")
    local peer=b:client("Second Sender",{registerResult=1})
    local scope, status=a.g.context()
    check(scope and status=="ready" and peer.g.context(),"native numeric prefix results register both clients")
    b:advance(5)
    local start=#b.packets
    local own=add(a,"Ámie Moon",nil)
    local passive=add(a,"Local Only","PRIEST")
    local untouched, personal, encounter=peer.a.store,peer.e.WhowhoAddressBookDB,peer.e.WhowhoEncounterDB
    check(#a.g.list()==0 and #peer.g.list()==0,"personal saves stay private without explicit share")
    check(share(a,own,scope)=="shared" and share(a,own,scope)=="unchanged","duplicate own share coalesces silently")
    b:advance(4)
    check(#b.packets==start+2 and rows(peer)[own.fullName] and not rows(peer)[passive.fullName],
        "explicit share sends the legacy row and its details")
    local content=b.packets[start+1].message
    check(content:find(own.fullName,1,true) and not content:find("private",1,true)
        and not content:find("spam",1,true),"legacy update carries only the exact UTF-8 name and class")
    check(rows(peer)[own.fullName].reasonIds[1]=="spam" and rows(peer)[own.fullName].note==nil,
        "stable reason ID is shared while the note stays private")
    check(peer.a.store==untouched and peer.e.WhowhoAddressBookDB==personal and peer.e.WhowhoEncounterDB==encounter,
        "received rows have no personal AddressBook or encounter side effects")
    local same=peer.e.WhowhoGuildBlacklistDB.scopes["3:101"][own.fullName]
    event(peer, content)
    event(peer, b.packets[start+2].message)
    b:advance(4)
    check(peer.e.WhowhoGuildBlacklistDB.scopes["3:101"][own.fullName]==same and #b.packets==start+2,
        "identical packet is neither republished nor echoed")

    local verified=add(peer,own.fullName,"MAGE")
    check(share(peer,verified,peer.g.context())=="shared","verified own evidence upgrades an existing shared row")
    b:advance(4)
    check(rows(a)[own.fullName].class=="MAGE" and rows(peer)[own.fullName].class=="MAGE","updated class converges")
    local before=#b.packets
    check(share(a,own,scope)=="unchanged","unverified own record cannot clear a known guild class")
    event(a,content)
    b:advance(4)
    check(rows(a)[own.fullName].class=="MAGE" and #b.packets==before,"old unknown update cannot overwrite known color")

    check(a.a.store.observeBlacklist(own.id,{region=3,name=own.fullName,guid="verified-local",source="Target",
        class="DRUID",at=a.e.GetServerTime()}),"local store verifies new own evidence")
    event(a,"E|3:101|ROGUE,549755813887,"..own.fullName)
    check(rows(a)[own.fullName].class=="MAGE","untrusted future revision cannot poison existing class")
    check(share(a,own,scope)=="shared","share reads current verified class from exact saved record")
    b:advance(4)
    check(rows(peer)[own.fullName].class=="DRUID","different locally verified class converges")

    local reload=b:client("Fresh Guildmate")
    b:advance(8)
    check(rows(reload)[own.fullName].class=="DRUID" and not rows(reload)[passive.fullName],
        "fresh guildmate catches up via bounded peer snapshot")
    local cache=reload.e.WhowhoGuildBlacklistDB
    reload.online=false
    peer.online=false
    a.online=false
    local restored=b:client("Fresh Guildmate",{shared=cache})
    check(rows(restored)[own.fullName].class=="DRUID","the separate guild cache survives reload without another peer")
    check(not restored.a.store.find(3,own.fullName),"reloaded guild row never becomes a personal entry")
    for i, packet in ipairs(b.packets) do
        for j=i-1,1,-1 do
            if b.packets[j].client==packet.client then
                -- Match the absolute send deadline across floating-point rounding boundaries.
                check(packet.time>=b.packets[j].time+1.25,"per-client packet rate is bounded")
                break
            end
        end
    end
end

do
    local b=bus()
    local a=b:client("Scope Tester",{shared={version=1,scopes={},members={["3:Current Character"]="3:101"}}})
    local scope=a.g.context()
    local record=add(a,"Delayed Subject","WARLOCK")
    check(share(a,record,scope)=="shared","save initial scoped entry before asynchronous send")
    a.guild=202
    a.s:event("PLAYER_GUILD_UPDATE","player")
    b:advance(0.8)
    local newScope=a.g.context()
    check(newScope and newScope~=scope and #a.g.list()==0 and share(a,record,scope)=="unavailable",
        "guild change hides prior rows and rejects the old dialog scope")
    event(a,"E|3:101|,0,Delayed Subject")
    b:advance(5)
    check(#a.g.list()==0 and #b.packets==1 and b.packets[1].message:find("^Q|3:202|"),
        "old packet and timers cannot mutate or transmit into a later guild")
    a.guild=101
    a.s:event("PLAYER_GUILD_UPDATE","player")
    b:advance(0.8)
    local restored=a.g.context()
    check(restored~=scope and not rows(a)[record.fullName] and not a.e.WhowhoGuildBlacklistDB.scopes["3:101"]
        and share(a,record,scope)=="unavailable",
        "returning to a left guild finds its saved rows erased and does not revive previous ownership")
    a.region=5
    a.s:event("PLAYER_ENTERING_WORLD",false,false)
    check(#a.g.list()==0 and share(a,record,a.g.context())=="invalid_record","region change cannot expose or share another region's record")
    a.guild=false
    a.s:event("PLAYER_GUILD_UPDATE","player")
    b:advance(0.8)
    local none, status=a.g.context()
    check(none==nil and status=="no_guild" and #a.g.list()==0,"confirmed guild absence is distinct from missing capability")
end

do
    local b=bus()
    local a=b:client("Input Guard")
    b:advance(2)
    local bad={
        {"E|3:101|,0,Valid Name",nil,"OFFICER"},
        {"E|3:101|,0,Valid Name","WrongPrefix"},
        {"E|3:101|,0,Same|cffff0000 Name"},
        {"E|3:101|,0,Onlyone"},
        {"E|3:101|,0,Valid  Name"},
        {"E|3:101|,1,Valid Name"},
        {"E|3:101|UNKNOWN,1,Valid Name"},
        {"E|3:101|MAGE,0,Valid Name"},
        {"E|3:101|,0,Valid Name|,0,Malformed"},
        {"E|3:101|,0,Valid Name|,0,Valid Name"},
        {"E|3:101|,0,Valid Name|"},
        {"E|3:101|,0,"..string.rep("x",240).." Name"},
        {a.s.secret},
        {"E|3:101|,0,Valid Name",a.s.secret},
        {"E|3:101|,0,Valid Name",nil,a.s.secret},
    }
    for _, args in ipairs(bad) do event(a,args[1],args[2],args[3]) end
    check(#a.g.list()==0 and a.e.WhowhoGuildBlacklistDB==nil,"malformed, secret and unrelated packets never write or partially apply")
    local scope=a.g.context()
    local saved=add(a,"Exact Subject")
    check(a.g.share({id=saved.id,fullName="Other Subject"},scope)=="invalid_record"
        and a.g.share({id=saved.id,fullName=saved.fullName,guid=a.s.secret},scope)=="invalid_record",
        "stale or prohibited caller fields cannot share a different record")
    a.locked=true
    local none,status=a.g.context()
    event(a,"E|3:101|,0,Valid Name")
    check(none==nil and status=="unavailable" and share(a,saved,scope)=="unavailable" and #a.g.list()==0,
        "chat lockdown suppresses incoming writes and outgoing share")
    a.locked=false
    check(a.g.context()~=scope,"returning to a ready transport gets fresh form ownership")
    local unsupported=b:client("Unsupported",{registerResult=3})
    local unavailable, unavailableStatus=unsupported.g.context()
    check(unavailable==nil and unavailableStatus=="unavailable","failed prefix registration leaves feature unavailable")
    local corrupt={version=2,scopes={}}
    local invalidCache=b:client("Bad Cache",{shared=corrupt})
    check(invalidCache.g.context()==nil and invalidCache.e.WhowhoGuildBlacklistDB==corrupt,"unknown storage version is preserved")
end

do
    local b=bus()
    local a=b:client("Throttled Sender")
    b:advance(2)
    local peer=b:client("Receiving Peer")
    b:advance(5)
    local saved=add(a,"Retry Subject")
    local attempts=0
    a.sendResult=function(message)
        if message:match("^D|") then return 0 end
        attempts=attempts+1
        if attempts==1 then return 3 end
        if attempts==2 then return 8 end
        return 0
    end
    check(share(a,saved,a.g.context())=="shared","temporary native throttle permits a local queued save")
    b:advance(12)
    check(attempts==3 and rows(peer)[saved.fullName],"both native throttle values back off then retry successfully")
    local limited=add(a,"Limited Subject")
    local before=attempts
    a.sendResult=function(message)
        if not message:match("^D|") then attempts=attempts+1 end
        return 11
    end
    check(share(a,limited,a.g.context())=="shared","accepted local share has independent delivery")
    b:advance(24)
    check(attempts==before+3 and rows(a)[limited.fullName] and not rows(peer)[limited.fullName],"lockdown retries stop after a bounded count")
    a.sendResult=nil
    check(peer.g.requestSync(),"explicit catch-up is available following cooldown")
    b:advance(100)
    check(rows(peer)[limited.fullName],"peer catch-up recovers a previously undelivered local share")
end

do
    local b=bus()
    local a=b:client("Initially Alone")
    b:advance(5)
    local seeded={version=1,scopes={["3:101"]={["Cached Subject"]={class="MAGE",rev=12801}}}}
    local cacheHolder=b:client("Late Cached Peer",{shared=seeded})
    b:advance(5)
    check(#a.g.list()==0 and #cacheHolder.g.list()==1,"late cache announcement respects the empty client's pull cooldown")
    b:advance(31)
    check(rows(a)["Cached Subject"].class=="MAGE","empty client catches up when the only cached peer logs in later")
    a.online=false
    local newcomer=b:client("During Cooldown")
    b:advance(8)
    check(#newcomer.g.list()==0,"snapshot response cooldown bounds repeat traffic")
    b:advance(90)
    check(rows(newcomer)["Cached Subject"],"deferred reply lets a guildmate arriving during cooldown catch up")
end

do
    local b=bus()
    local a=b:client("Initially Ready")
    local peer=b:client("Listening Peer")
    b:advance(4)
    local saved=add(a,"Paused Subject")
    check(share(a,saved,a.g.context())=="shared","queued share attaches to proven membership")
    a.locked=true
    b:advance(1)
    check(a.g.context()==nil and not rows(peer)[saved.fullName],"pending send waits during same-guild lockdown")
    a.locked=false
    b:advance(3)
    check(rows(peer)[saved.fullName],"bounded readiness checks resume the explicitly queued share when unlocked")
end

do
    local b=bus()
    local a=b:client("Guild Transition")
    local scope=a.g.context()
    local own=add(a,"Prior Guild")
    check(share(a,own,scope)=="shared","own row queued before a membership signal")
    a.s:event("PLAYER_GUILD_UPDATE","player")
    check(a.g.context()==nil and share(a,own,scope)=="unavailable","same stale native club is disabled immediately")
    b:advance(0.5)
    check(#b.packets==0,"previous ticket cannot transmit while club data settles")
    a.guild=202
    b:advance(2)
    check(#b.packets==1 and b.packets[1].message:find("^Q|3:202|")
        and #a.g.list()==0,"new guild becomes ready without the previous guild's queued row")
end
do
    local b=bus()
    local a=b:client("Restriction Events")
    local peer=b:client("Restriction Peer")
    b:advance(5)
    local saved=add(a,"Activating Subject")
    local scope=a.g.context()
    check(share(a,saved,scope)=="shared","share queues before the activation signal")
    a.s:event("ADDON_RESTRICTION_STATE_CHANGED",5,1)
    check(a.g.context()==nil and share(a,saved,scope)=="unavailable","Chat Activating invalidates before native lockdown applies")
    a.s:event("ADDON_RESTRICTION_STATE_CHANGED",0,0)
    b:advance(1)
    check(not rows(peer)[saved.fullName],"unrelated restriction cannot clear paused Chat work")
    a.s:event("ADDON_RESTRICTION_STATE_CHANGED",5,0)
    b:advance(4)
    check(rows(peer)[saved.fullName],"Chat Inactive resumes the scoped pending push")
end

local function seededCache(count)
    local seeded={version=1,scopes={["3:101"]={}}}
    for index=1,count do seeded.scopes["3:101"]["Seed"..index.." Subject"]={rev=0} end
    return seeded
end

do
    local b=bus()
    local a=b:client("Full Cache",{shared=seededCache(512)})
    local saved=add(a,"Zulu Subject")
    check(#a.g.list()==512 and share(a,saved,a.g.context())=="limit"
        and a.a.store.get(saved.id),"a later local key reports the Guild cap after the personal save")
    event(a,"E|3:101|,0,Zzz Subject")
    check(#a.g.list()==512 and not rows(a)["Zzz Subject"],"incoming later keys respect the same capacity")
    local earlier=add(a,"Earlier Subject","DRUID","Public note",{"fraud"})
    check(share(a,earlier,a.g.context(),true)=="shared" and #a.g.list()==512
        and rows(a)[earlier.fullName].note=="Public note" and not rows(a)["Seed99 Subject"],
        "a locally shared earlier key displaces the last retained key at capacity")
end

for _, reverse in ipairs({false,true}) do
    local b=bus()
    b.partitioned=true
    local a=b:client("First Full Peer",{shared=seededCache(511)})
    local peer=b:client("Second Full Peer",{shared=seededCache(511)})
    local winner, loser=a,peer
    if reverse then winner,loser=peer,a end
    local first=add(winner,"Zebra Subject","MAGE","Shared winner",{"fraud","spam"})
    local second=add(loser,"Élan Subject","ROGUE","Shared displaced",{"camping"})
    check(share(winner,first,winner.g.context(),true)=="shared"
        and share(loser,second,loser.g.context(),true)=="shared","both isolated shares fill the final slot")
    b:advance(35)
    check(#a.g.list()==512 and #peer.g.list()==512 and not rows(loser)[first.fullName]
        and not rows(winner)[second.fullName],"isolated full peers initially retain different rows")

    b.partitioned=false
    check(a.g.requestSync() and peer.g.requestSync(),"both full peers can request explicit catch-up")
    b:advance(240)
    for _, client in ipairs({a,peer}) do
        local entries=rows(client)
        local row=entries[first.fullName]
        check(#client.g.list()==512 and row and row.class=="MAGE" and row.note=="Shared winner"
            and table.concat(row.reasonIds,",")=="fraud,spam" and not entries[second.fullName],
            "explicit catch-up retains the same canonical keys and the winner's details on both full peers")
        for index=1,511 do assert(entries["Seed"..index.." Subject"],"catch-up lost a common row") end
    end
    local cache=loser.e.WhowhoGuildBlacklistDB
    check(not cache.scopes["3:101"][second.fullName] and loser.a.store.get(second.id).note=="Shared displaced",
        "eviction removes the guild cache row while preserving the displaced personal entry")
    a.online,peer.online=false,false
    local restored=b:client("Reloaded Full Peer",{shared=cache})
    event(restored,"E|3:101|ROGUE,12799,ÉLAN SUBJECT")
    for _, packet in ipairs(detailPackets("3:101","9.1","1|camping|"..second.fullName.."|Stale note")) do
        event(restored,packet)
    end
    check(#restored.g.list()==512 and rows(restored)[first.fullName].note=="Shared winner"
        and not rows(restored)[second.fullName] and not rows(restored)["ÉLAN SUBJECT"],
        "reloading the full cache cannot resurrect a displaced identity through stale class or details")
end

do
    local b=bus()
    local a=b:client("Reentrant Displacement",{shared=seededCache(511)})
    b:advance(2)
    local displaced=add(a,"Zulu Subject","ROGUE",string.rep("shared ",30),{"fraud"})
    a.noEcho=true
    local sends=0
    a.sendResult=function(message)
        sends=sends+1
        if message:match("^E|") then
            -- The class packet loses ownership during native dispatch.
            local packet=detailPackets("3:101","9.2","1|spam|Yellow Subject|Peer note")[1]
            event(a,packet)
            return 3
        end
        return 0
    end
    check(share(a,displaced,a.g.context(),true)=="shared","local class and details queue before dispatch")
    b:advance(10)
    event(a,"E|3:101|MAGE,12799,YELLOW SUBJECT")
    local row=rows(a)["YELLOW SUBJECT"]
    check(sends==1 and #a.g.list()==512 and not rows(a)[displaced.fullName]
        and row and row.class=="MAGE" and row.note=="Peer note" and row.reasonIds[1]=="spam",
        "earlier details arriving first displace the losing class retry and details queue")
end

do
    local b=bus()
    local a=b:client("Partial Detail Displacement",{shared=seededCache(511)})
    b:advance(2)
    local displaced=add(a,"Zulu Subject",nil,string.rep("shared ",30),{"fraud"})
    local detailSends=0
    a.sendResult=function(message)
        if message:match("^D|") then
            detailSends=detailSends+1
            if detailSends==2 then return 8 end
        end
        return 0
    end
    check(share(a,displaced,a.g.context(),true)=="shared","multi-fragment details are queued for the last row")
    b:advance(3)
    check(detailSends==2,"partial detail transfer reaches its retry before displacement")
    event(a,"E|3:101|,0,Yellow Subject")
    event(a,"Q|3:101|9.3")
    b:advance(120)
    check(detailSends==2 and not rows(a)[displaced.fullName] and rows(a)["Yellow Subject"],
        "an evicted partial transfer is not retried or included in a subsequent snapshot")
end
do
    local b=bus()
    local first={version=1,scopes={["3:101"]={["First Subject"]={rev=0}}}}
    local second={version=1,scopes={["3:101"]={["Second Subject"]={rev=0}}}}
    local a=b:client("First Cache",{shared=first})
    b:advance(5)
    local peer=b:client("Second Cache",{shared=second})
    b:advance(35)
    check(rows(a)["Second Subject"] and rows(peer)["First Subject"],"nonempty disjoint caches converge in either login order")
    local before=#b.packets
    b:advance(100)
    check(#b.packets==before,"reactive query does not trigger any more queries or snapshots")
end
do
    local b=bus()
    local a=b:client("Faulty Timer")
    a.locked=true
    check(a.g.context()==nil,"locked context hides pending startup")
    a.locked=false
    a.timerThrows=true
    local token,state=a.g.context()
    check(token==nil and state=="unavailable","a failed timer cannot expose stale ready consent")
end

for _, failure in ipairs({"throw","missing"}) do
    local b=bus()
    local shared={version=1,scopes={
        ["3:101"]={["Prior Member"]={rev=0}}, ["3:202"]={["New Member"]={rev=0}},
    }}
    local a=b:client("Membership Timer",{shared=shared})
    b:advance(5)
    local oldToken,_,oldRead=a.g.context()
    local after=a.e.C_Timer.After
    if failure=="throw" then a.timerThrows=true else a.e.C_Timer.After=nil end
    a.s:event("PLAYER_GUILD_UPDATE","player")
    a.timerThrows=false
    a.e.C_Timer.After=after
    local baseline=#b.packets
    b:advance(5)
    a.s:event("INITIAL_CLUBS_LOADED")
    a.s:event("PLAYER_GUILD_UPDATE","player")
    b:advance(1)
    local token,status,readScope=a.g.context()
    check(oldToken and oldRead and not token and status=="unavailable" and not readScope and not next(rows(a)),
        "a readiness signal cannot reopen the stale guild after a "..failure.." timer")
    event(a,"E|3:101|,0,Unverified Subject")
    check(#b.packets==baseline and not shared.scopes["3:101"]["Unverified Subject"],
        "failed settlement accepts neither old-scope transport nor writes")
    a.guild=202
    a.s:event("INITIAL_CLUBS_LOADED")
    local newToken,_,newRead=a.g.context()
    check(newToken and newToken~=oldToken and newRead~=oldRead and rows(a)["New Member"] and not rows(a)["Prior Member"],
        "the readiness signal restores only the newly confirmed guild")
    b:advance(5)
    check(#b.packets==baseline+1 and b.packets[#b.packets].message:match("^H|3:202|"),
        "recovery schedules only the new guild's startup work")
end

do
    local b=bus()
    local a=b:client("Membership Without Guild",{shared={version=1,scopes={["3:101"]={["Former Member"]={rev=0}}}}})
    a.timerThrows=true
    a.s:event("PLAYER_GUILD_UPDATE","player")
    a.guild=false
    a.s:event("INITIAL_CLUBS_LOADED")
    local token,status,scope=a.g.context()
    check(not token and status=="no_guild" and not scope and not next(rows(a)),
        "confirmed guild absence resolves a failed settlement without exposing cached rows")
end

for _, failure in ipairs({"throw","unreadable","unexpected"}) do
    local b=bus()
    local a=b:client("Paused Sender")
    local peer=b:client("Paused Receiver")
    b:advance(5)
    local saved=add(a,"Retry Subject","MAGE","Shared note")
    local oldToken,_,oldRead=a.g.context()
    check(oldRead and a.g.add("Blocked Add",{"other"},nil,oldRead)=="unavailable",
        "the verified read scope never authorizes writes")
    local attempts=0
    a.sendResult=function(message)
        if not message:match("^E|") then return 0 end
        attempts=attempts+1
        if failure=="throw" then error("temporary transport exception") end
        if failure=="unreadable" then return a.s.secret end
        return 99
    end
    check(share(a,saved,oldToken,true)=="shared","local queued share precedes the simulated send failure")
    b:advance(0)
    local token,status,readScope=a.g.context()
    check(attempts==1 and not token and status=="unavailable" and readScope==oldRead
        and rows(a)[saved.fullName] and not rows(peer)[saved.fullName],
        "a "..failure.." send leaves verified rows readable without claiming delivery")
    check(not a.g.requestSync() and a.g.add("Blocked Add",{"other"},nil,oldToken)=="unavailable",
        "the readable scope cannot authorize outgoing work while transport is paused")
    if failure=="throw" then a.sendResult=nil end
    b:advance(16)
    local newToken,_,newRead=a.g.context()
    check(newToken and newToken~=oldToken and newRead==oldRead and rows(a)[saved.fullName],
        "send recovery rotates the write token and keeps roster identity")
    if failure=="throw" then
        check(rows(peer)[saved.fullName] and rows(peer)[saved.fullName].note=="Shared note",
            "eligible class and detail work retries and delivers after the exception clears")
    else
        local received=rows(peer)[saved.fullName]
        check(attempts==3 and (not received or received.class==nil),
            "persistent failures exhaust their own budget without falsely transferring class evidence")
        a.sendResult=nil
        check(a.g.requestSync(),"sender can start another explicit sync after retry exhaustion")
        b:advance(35)
        check(peer.g.requestSync(),"peer can request catch-up after the transient fault clears")
        b:advance(100)
        check(rows(peer)[saved.fullName].class=="MAGE","fresh peer catch-up can deliver the retained cache")
    end
end

do
    local b=bus()
    local a=b:client("Failed Sample")
    b:advance(5)
    local attempts=0
    a.sendResult=function(message)
        local nonce=message:match("^Q|3:101|(0%d+%.%d+)$")
        if not nonce then return 0 end
        attempts=attempts+1
        event(a,"A|3:101|"..nonce,nil,nil,"Premature Response")
        return a.s.secret
    end
    check(a.g.requestSync(),"an explicit request can fail after a synchronous response")
    b:advance(55)
    local token=assert(a.g.context())
    check(attempts==3 and a.g.peerCount(token)==nil,"three unreadable native results cannot produce a peer count")
end

do
    local b=bus()
    local a=b:client("Interrupted Sample")
    b:advance(5)
    local scope=a.g.context()
    check(a.g.requestSync(),"the marked query starts during the startup cooldown")
    b:advance(25)
    local nonce=b.packets[#b.packets].message:match("^Q|3:101|(0%d+%.%d+)$")
    check(nonce and a.g.peerCount(scope)==nil,"the sent query awaits acknowledgments")

    local saved=add(a,"Sample Subject","MAGE")
    a.sendResult=function(message) return message:match("^E|") and 99 or 0 end
    check(share(a,saved,scope)=="shared","a share can send during the observation window")
    b:advance(1.25)
    check(not a.g.context(),"the unexpected share result pauses transport")
    event(a,"A|3:101|"..nonce,nil,nil,"Interrupted Response")
    a.sendResult=nil
    b:advance(16)
    local recovered=assert(a.g.context())
    check(recovered~=scope and a.g.peerCount(recovered)==nil,
        "an observation interrupted by transport recovery cannot report a zero count")

    check(a.g.requestSync(),"the recovered transport can queue a fresh observation")
    b:advance(14)
    local fresh=b.packets[#b.packets].message:match("^Q|3:101|(0%d+%.%d+)$")
    check(fresh and fresh~=nonce,"the new observation owns a fresh nonce")
    event(a,"A|3:101|"..nonce,nil,nil,"Late Interrupted Response")
    event(a,"A|3:101|"..fresh,nil,nil,"Current Response")
    b:advance(12)
    check(a.g.peerCount(recovered)==1,"only acknowledgments for the new observation count")
    b:advance(60)
    check(a.g.peerCount(recovered)==nil,"the fresh observation expires normally")
end

do
    local b=bus()
    local a=b:client("Reentrant Failed Sender")
    b:advance(5)
    local oldToken,_,oldRead=a.g.context()
    local saved=add(a,"Prior Retry")
    check(share(a,saved,oldToken)=="shared","send work starts in the original guild")
    local attempts=0
    a.sendResult=function(message)
        if message:match("^E|3:101|") then
            attempts=attempts+1
            a.guild=202
            a.s:event("PLAYER_GUILD_UPDATE","player")
            error("failed send after reassignment")
        end
        return 0
    end
    b:advance(12)
    local newToken,_,newRead=a.g.context()
    check(attempts==1 and newToken and newToken~=oldToken and newRead~=oldRead and not next(rows(a)),
        "reentrant scope loss discards stale failure ownership and never retries the old guild send")
    check(b.packets[#b.packets].message:match("^Q|3:202|"),"the replacement scope can still start sync")
end

for _, work in ipairs({"snapshot","followup","deferred followup"}) do
    local b=bus()
    local a=b:client("Pending Cache Holder",{shared={version=1,scopes={["3:101"]={["Cached Subject"]={rev=0}}}}})
    b:advance(5)
    event(a,"Q|3:101|42.1")
    if work~="snapshot" then
        b:advance(8)
        event(a,"Q|3:101|42.2")
        if work=="followup" then b:advance(81) end
    end
    local before=#b.packets
    a.locked=true
    if work=="deferred followup" then
        check(not a.g.context(),"early lockdown suspends a scheduled followup")
        b:advance(20)
    else
        b:advance(7)
    end
    check(#b.packets==before,"temporary chat lockdown suppresses pending "..work.." traffic")
    a.locked=false
    b:advance(work=="deferred followup" and 100 or 16)
    check(#b.packets==before+1 and b.packets[#b.packets].message=="E|3:101|,0,Cached Subject",
        work.."-only work resumes from a bounded readiness timer without an external refresh")
    b:advance(120)
    check(#b.packets==before+1,"readiness recovery does not start an extra query or periodic snapshot")
end
do
    local b=bus()
    local a=b:client("First Sender")
    local peer=b:client("Listening Peer")
    local pulls, pushes=0,0
    a.sendResult=function(message)
        if message:sub(1,1) == "Q" then
            pulls=pulls+1
            return pulls==1 and 3 or 0
        end
        if message:match("^D|") then return 0 end
        pushes=pushes+1
        return pushes<3 and 3 or 0
    end
    b:advance(0)
    check(pulls==1 and pushes==0,"startup pull enters backoff")
    local saved=add(a,"Independent Subject")
    check(share(a,saved,a.g.context())=="shared","live share queues during pull backoff")
    b:advance(14)
    check(pushes==3 and rows(peer)[saved.fullName],"a throttled pull cannot consume a live packet's last retry")
    check(pulls==2,"interleaved work resumes the throttled pull with its own budget")
end

do
    local b=bus()
    local a=b:client("Opt In Sender")
    local peer=b:client("Current Client")
    local legacy=b:client("Legacy Client",{legacy=true})
    b:advance(5)
    local saved=add(a,"Shared Subject","DRUID","Guild note",{"other","camping"})
    local scope=a.g.context()
    local approvedReasons=saved.reasonIds
    saved.note,saved.reasonIds="Forged caller note",{"harassment"}
    check(a.g.share(saved,scope,{reasonIds=approvedReasons,note=saved.note})=="shared",
        "an explicit guild save accepts the verified record")
    b:advance(4)
    local current, previous=rows(peer)[saved.fullName],rows(legacy)[saved.fullName]
    check(current.note==nil and table.concat(current.reasonIds,",")=="camping,other",
        "a mismatched note is omitted and matching reasons use catalog order")
    check(previous.class=="DRUID" and #previous.reasonIds==0 and previous.note==nil,"R50 E processing still receives name and class")
    current.reasonIds[1]="mutated"
    check(rows(peer)[saved.fullName].reasonIds[1]=="camping","returned reason arrays are detached from the cache")

    local start=#b.packets
    check(a.g.share(saved,scope,true)=="unchanged","a bare boolean never approves a note")
    check(a.g.share(saved,scope,{reasonIds=approvedReasons,note="Guild note"})=="shared",
        "later explicit note consent can update an existing row")
    b:advance(4)
    check(#b.packets==start+1 and b.packets[start+1].message:match("^D|")
        and rows(peer)[saved.fullName].note=="Guild note","adding a note sends one details frame without redundant legacy row")
    local personal=assert(a.a.save(saved,"blacklist",saved.fullName,"New private text",nil,{"spam","griefing"}))
    check(share(a,personal,scope,false)=="shared","new explicit reasons extend the guild row")
    b:advance(4)
    current=rows(peer)[saved.fullName]
    check(current.note=="Guild note" and table.concat(current.reasonIds,",")=="griefing,camping,spam,other",
        "an unchecked save unions reasons and keeps the existing opt-in note")
    local privateReceiver=b:client("Details Check")
    event(privateReceiver,b.packets[#b.packets].message)
    check(rows(privateReceiver)[saved.fullName].note==nil,"reason-only live update does not resend an earlier guild note")
    privateReceiver.online=false
    check(share(a,personal,scope,true)=="shared","explicit consent can replace the prior note")
    b:advance(5)
    local public=rows(peer)[saved.fullName]
    check(public.note=="New private text" and public.class=="DRUID"
        and #public.reasonIds==4,"note replacement leaves class and accumulated reasons intact")
    event(peer,"E|3:101|MAGE,1,"..saved.fullName)
    b:advance(2)
    check(rows(peer)[saved.fullName].note==public.note,"legacy packets cannot clear the note")
    for _, packet in ipairs(detailPackets("3:101","1.1","1|fraud|"..saved.fullName.."|Earlier note")) do
        event(peer,packet)
    end
    check(rows(peer)[saved.fullName].note==public.note and rows(peer)[saved.fullName].reasonIds[3]=="fraud",
        "an older note loses independently and its valid reason still merges")
end

do
    local b=bus()
    local a=b:client("Long Note Sender")
    local peer=b:client("Long Note Peer")
    b:advance(5)
    local markup="\n|Tfoo|t\r\t"
    local note=string.rep("🌙",256-#markup)..markup
    local longest=string.rep("🌙",256)
    local name=string.rep("é",78).." Fox"
    local reasons={}
    for _, reason in ipairs(a.a.reasons) do reasons[#reasons+1]=reason.id end
    local saved=add(a,name,"MAGE",note,reasons)
    check(a.g.canShareNote(note) and a.g.canShareNote(longest) and not a.g.canShareNote(longest.."x")
        and not a.g.canShareNote("a\000b") and not a.g.canShareNote("a\194\128b")
        and not a.g.canShareNote("a\128") and not a.g.canShareNote(" \r\n\t\194\160"),
        "note validator accepts literal markup and whitespace within the UTF-8 size bound")
    local detailSends, attempts={},0
    local last
    a.sendResult=function(message)
        if not message:match("^D|") then return 0 end
        if message ~= last then
            last,attempts=message,0
            detailSends[#detailSends+1]=message
        end
        attempts=attempts+1
        return attempts==1 and 3 or 0
    end
    check(share(a,saved,a.g.context(),true)=="shared","long note shares without truncation")
    b:advance(3)
    check(rows(peer)[name].class=="MAGE" and rows(peer)[name].note==nil,"incomplete note transfer leaves the legacy row available")
    b:advance(120)
    check(#detailSends > 2 and rows(peer)[name].note==note and #rows(peer)[name].reasonIds==#reasons,
        "all fragments retry independently and converge to exact full UTF-8 note and catalog")
    local reordered=b:client("Reordered Receiver")
    for i=#detailSends,1,-1 do
        event(reordered,detailSends[i])
        if i==#detailSends then event(reordered,detailSends[i]) end
    end
    check(rows(reordered)[name].note==note and rows(reordered)[name].class==nil,
        "reordered and duplicated details converge even before the legacy row")
    event(reordered,"E|3:101|MAGE,1,"..name)
    check(rows(reordered)[name].class=="MAGE" and rows(reordered)[name].note==note,
        "later legacy class evidence preserves and upgrades an earlier details row")
    a.sendResult=nil
    local full=assert(a.a.save(saved,"blacklist",name,longest,nil,reasons))
    check(share(a,full,a.g.context(),true)=="shared","full 1024-byte note replaces the previous note")
    b:advance(35)
    check(rows(peer)[name].note==longest,"all 256 four-byte scalars are delivered")
    a.online,peer.online,reordered.online=false,false,false
    local reloaded=b:client("Relogged Holder",{shared=peer.e.WhowhoGuildBlacklistDB})
    check(rows(reloaded)[name].note==longest,"guild details survive reload")
    b:advance(5)
    local fresh=b:client("Fresh After Reload")
    b:advance(30)
    check(rows(fresh)[name].note==longest and rows(fresh)[name].class=="MAGE"
        and not fresh.a.store.find(3,name),"a relogged peer catches up a new client without a personal side effect")
end

do
    local b=bus()
    local a=b:client("Detail Guard")
    b:advance(2)
    local invalid={
        "0|unknown|Bad Subject|", "0|spam,spam|Bad Subject|", "0|spam,|Bad Subject|",
        "0|spam|Onepart|", "0|spam|Bad Subject|No revision", "1|spam|Bad Subject|",
        "999999999999||Bad Subject|Future note", "1|spam|Bad Subject|Bad\000note",
        "1|spam|Bad Subject|"..string.rep("x",257),
    }
    for i, body in ipairs(invalid) do
        for _, packet in ipairs(detailPackets("3:101","1."..i,body)) do event(a,packet) end
    end
    local body="1|spam|Guarded Subject|"..string.rep("x",150)
    local frames=detailPackets("3:101","2.1",body)
    event(a,frames[1])
    event(a,frames[2],nil,nil,"Different Sender")
    event(a,frames[3])
    check(#a.g.list()==0 and a.e.WhowhoGuildBlacklistDB==nil,"malformed bodies and cross-sender fragments do not write")
    local replacement=frames[1]:gsub("..$","ff")
    event(a,replacement)
    event(a,frames[2])
    check(#a.g.list()==0,"conflicting fragments invalidate this transfer token")
    b:advance(241)
    event(a,frames[2])
    event(a,frames[3])
    check(#a.g.list()==0,"expired first fragment cannot complete a later transfer")
    event(a,(frames[1]:gsub("3:101","3:202")))
    check(#a.g.list()==0,"fragments from another guild are ignored")
    event(a,frames[1])
    check(rows(a)["Guarded Subject"].note==string.rep("x",150),"a complete transfer with one live sender and scope can be replayed")

    local olderTie=detailPackets("3:101","2.2","2|spam|Guarded Subject|Alpha")[1]
    local newerTie=detailPackets("3:101","2.3","2|spam|Guarded Subject|Zeta")[1]
    event(a,newerTie)
    event(a,olderTie)
    check(rows(a)["Guarded Subject"].note=="Zeta","same-revision notes resolve to the bytewise greater value regardless of order")
end

do
    local b=bus()
    local a=b:client("Concurrent Local Edit")
    local peer=b:client("Concurrent Edit Peer")
    b:advance(5)
    local saved=add(a,"Edited Subject","MAGE","Approved draft",{"other"})
    local approved={reasonIds=saved.reasonIds,note=saved.note}
    local scope=a.g.context()
    local getServerTime=a.e.GetServerTime
    local changed
    a.e.GetServerTime=function()
        a.e.GetServerTime=getServerTime
        changed=assert(a.a.save(saved,"blacklist",saved.fullName,"Private replacement",nil,{"spam"}))
        return getServerTime()
    end
    check(a.g.share(saved,scope,approved)=="shared","reentrant edit still allows exact verified name and class")
    b:advance(5)
    local row=rows(peer)[saved.fullName]
    check(row.class=="MAGE" and row.note==nil and #row.reasonIds==0,
        "reentrant same-ID edit cannot replace the approved reason IDs or note")
    check(a.a.store.get(saved.id).note==changed.note,"reentrant local edit stays personal")
    check(share(a,changed,scope,true)=="shared","matching consent for the edited draft can add details later")
    b:advance(5)
    row=rows(peer)[saved.fullName]
    check(row.note==changed.note and row.reasonIds[1]=="spam","fresh consent publishes precisely its approved saved details")
end

do
    local b=bus()
    local a=b:client("Queued Note Sender")
    local peer=b:client("Queued Note Peer")
    b:advance(5)
    local allowed=add(a,"Queued Subject",nil,string.rep("Allowed ",40):sub(1,250),{"other"})
    local scope=a.g.context()
    check(share(a,allowed,scope,true)=="shared","explicit note is queued for a scoped fragmented send")
    b:advance(1.3)
    a.locked=true
    check(a.g.context()==nil,"sender observes lockdown partway through a transfer")
    b:advance(245)
    a.locked=false
    scope=a.g.context()
    local personal=assert(a.a.save(allowed,"blacklist",allowed.fullName,"Unshared replacement",nil,{"spam"}))
    check(share(a,personal,scope)=="shared","unchecked update replaces the queued reasons under fresh scope")
    b:advance(10)
    local row=rows(peer)[allowed.fullName]
    check(row.note==allowed.note and table.concat(row.reasonIds,",")=="spam,other",
        "resuming sends the captured opted-in note from its first fragment and the additional reason")
end

do
    local b=bus()
    local note=string.rep("Shared ",33)
    local seeded={version=1,scopes={[ "3:101" ]={
        ["Cached Note"]={class="MAGE",rev=12799,reasonIds={"other"},note=note,noteRev=12799},
    }}}
    local a=b:client("First Equivalent Cache",{shared=seeded})
    local peer=b:client("Second Equivalent Cache",{shared=seeded})
    b:advance(200)
    local start=#b.packets
    local newcomer=b:client("Equivalent Cache Requester")
    b:advance(16)
    local completed=0
    for index=start+1,#b.packets do
        local packet=b.packets[index]
        if packet.client==a or packet.client==peer then
            local part, total=packet.message:match("^D|[^|]+|[^|]+|(%d+)|(%d+)|")
            if part and part==total then completed=completed+1 end
        end
    end
    check(completed==1 and rows(newcomer)["Cached Note"].note==note,
        "one equivalent cached peer completes the snapshot while the other drops its redundant queued details")
end

for _, reverse in ipairs({false,true}) do
    local b=bus()
    local lower, preferred="élodie moon7","Élodie Moon7"
    local a=b:client("First Spelling")
    local peer=b:client("Second Spelling")
    local observer=b:client("Case Observer")
    b:advance(5)
    local records={
        add(a,lower,"MAGE","Alpha note",{"spam"}),
        add(peer,preferred,"ROGUE","Zeta note",{"fraud"}),
    }
    local forged={}
    for key, value in pairs(records[1]) do forged[key]=value end
    forged.fullName=preferred
    check(share(a,forged,a.g.context(),true)=="invalid_record",
        "guild case equality cannot authorize a mismatched personal record")
    local clients={a,peer}
    for _, index in ipairs(reverse and {2,1} or {1,2}) do
        local sender=clients[index]
        check(share(sender,records[index],sender.g.context(),true)=="shared",
            "both spellings queue independently before any network arrival")
    end
    b:advance(8)
    for _, client in ipairs({a,peer,observer}) do
        local entry=client.g.list()[1]
        check(#client.g.list()==1 and entry.name==preferred and entry.class=="ROGUE"
            and entry.note=="Zeta note" and table.concat(entry.reasonIds,",")=="fraud,spam",
            "concurrent aliases converge to one row with deterministic display, class, note, and reason union")
        local persisted=client.e.WhowhoGuildBlacklistDB.scopes["3:101"]
        check(persisted[preferred] and not persisted[lower],"saved keys use the selected original spelling")
    end
    check(a.a.store.get(records[1].id).fullName==lower and a.a.store.get(records[1].id).note=="Alpha note"
        and peer.a.store.get(records[2].id).fullName==preferred and #records[2].reasonIds==1
        and not observer.a.store.find(3,preferred),
        "case convergence leaves exact personal records and a passive observer's address book alone")
    event(observer,"E|3:101|,0,Elodie Moon7|,0,Élodie Moon8")
    check(#observer.g.list()==3 and rows(observer)["Elodie Moon7"] and rows(observer)["Élodie Moon8"],
        "distinct accents and digits retain separate guild identities")
end

do
    local b=bus()
    local preferred, alias="Élodie Moon","élodie moon"
    local first={class="DRUID",rev=12797,reasonIds={"fraud"},note="Newer note",noteRev=12798}
    local second={class="ROGUE",rev=12799,reasonIds={"spam"},note="Older note",noteRev=12796}
    for _, reverse in ipairs({false,true}) do
        local cache={version=1,scopes={["3:101"]={}}}
        local raw=cache.scopes["3:101"]
        if reverse then raw[alias],raw[preferred]=second,first
        else raw[preferred],raw[alias]=first,second end
        local client=b:client("Reloaded Alias",{shared=cache})
        local entry=client.g.list()[1]
        local persisted=cache.scopes["3:101"]
        check(#client.g.list()==1 and entry.name==preferred and entry.class=="ROGUE"
            and entry.note=="Newer note" and table.concat(entry.reasonIds,",")=="fraud,spam"
            and persisted[preferred] and not persisted[alias] and not client.a.store.find(3,preferred),
            "the v1 cache upgrade merges class, reasons and note independently in either label order")
        client.online=false
    end
    local firstWire, secondWire="MAGE,12798,"..preferred,"ROGUE,12799,"..alias
    for _, payload in ipairs({firstWire.."|"..secondWire,secondWire.."|"..firstWire}) do
        local client=b:client("Batched Alias")
        event(client,"E|3:101|"..payload)
        check(#client.g.list()==1 and rows(client)[preferred].class=="ROGUE",
            "one legacy E packet merges two case variants regardless of order")
        client.online=false
    end
end

do
    local b=bus()
    local sender=b:client("Case Only Sender")
    local observer=b:client("Case Only Observer")
    local lower, preferred="élodie moon","Élodie Moon"
    b:advance(5)
    local record=add(sender,preferred,"MAGE","Private text")
    local initial="E|3:101|MAGE,12799,"..lower
    event(sender,initial)
    event(observer,initial)
    local knownReasons=detailPackets("3:101","6.1","0|spam|"..lower.."|")[1]
    event(sender,knownReasons)
    event(observer,knownReasons)
    local before=#b.packets
    check(share(sender,record,sender.g.context(),false)=="shared",
        "a case-only share queues the preferred spelling with no class or consented detail change")
    b:advance(4)
    check(rows(observer)[preferred].class=="MAGE" and not rows(observer)[lower]
        and #b.packets==before+1 and b.packets[before+1].message=="E|3:101|MAGE,12799,"..preferred,
        "an unchanged class and private note still propagate the preferred label in an E row")
end

do
    local b=bus()
    local name="Clock Subject"
    local function cache()
        return {version=1,scopes={["3:101"]={[name]={class="MAGE",rev=12798,note="Old",noteRev=12798}}}}
    end
    local ahead=b:client("Clock Ahead",{shared=cache(),clockOffset=1})
    local behind=b:client("Clock Behind",{shared=cache()})
    local observer=b:client("Clock Observer",{shared=cache()})
    b:advance(120)
    local own=add(ahead,name,"MAGE","Latest approved note",{"spam"})
    local other=add(behind,name,"MAGE","Concurrent note",{"fraud"})
    check(share(ahead,own,ahead.g.context(),true)=="shared"
        and share(behind,other,behind.g.context(),true)=="shared",
        "one-second-skewed peers can both approve note and reason updates on an existing row")
    b:advance(0)
    for _, client in ipairs({ahead,behind,observer}) do
        local entry=rows(client)[name]
        check(entry.note==own.note and table.concat(entry.reasonIds,",")=="fraud,spam",
            "immediate details propagate both reasons and the valid one-second-ahead note")
    end
    local later=assert(behind.a.save(other,"blacklist",name,"Replacement while still behind",nil,{"other"}))
    check(share(behind,later,behind.g.context(),true)=="shared",
        "receiving an ahead note still allows a local approved save in the same clock second")
    b:advance(4)
    check(ahead.a.store.observeBlacklist(own.id,{region=3,name=name,guid=own.lastKnown.guid,source="Target",
        class="DRUID",at=ahead.e.GetServerTime()}),"ahead peer refreshes its verified class")
    check(share(ahead,own,ahead.g.context(),false)=="shared","one-second-ahead peer shares its updated class")
    b:advance(0)
    for _, client in ipairs({ahead,behind,observer}) do
        local entry=rows(client)[name]
        check(entry.class=="DRUID" and entry.note==later.note and table.concat(entry.reasonIds,",")=="fraud,spam,other",
            "immediate ahead class and monotonic local note updates converge under bounded clock skew")
    end
    check(share(behind,later,behind.g.context(),false)=="shared",
        "one-second-behind local class evidence can supersede an accepted newer tick")
    b:advance(0)
    check(rows(ahead)[name].class=="MAGE" and rows(observer)[name].class=="MAGE",
        "monotonic local class evidence is broadcast without waiting for the clock to catch up")
end

do
    local b=bus()
    local name="Future Guard"
    local holder=b:client("Snapshot Holder",{shared={version=1,scopes={["3:101"]={
        [name]={class="MAGE",rev=12798,reasonIds={"spam"},note="Current note",noteRev=12798},
    }}}})
    b:advance(120)
    local observer=b:client("Snapshot Requester")
    b:advance(0)
    event(holder,"E|3:101|ROGUE,549755813887,"..name.."|DRUID,12799,Unrelated Subject|ROGUE,549755813887,Empty Alias")
    local forgedNote=detailPackets("3:101","7.1","999999999999|fraud,spam|"..name.."|Far future")[1]
    event(holder,forgedNote)
    local oversized=detailPackets("3:101","7.2","99999999999999999999|other|"..name.."|Oversized")[1]
    event(holder,oversized)
    local row=rows(holder)[name]
    check(row.class=="MAGE" and row.note=="Current note" and table.concat(row.reasonIds,",")=="fraud,spam,other"
        and rows(holder)["Unrelated Subject"].class=="DRUID" and not rows(holder)["Empty Alias"],
        "far-future metadata leaves valid details and unrelated records intact")
    b:advance(15)
    local snapshot=rows(observer)[name]
    check(snapshot and snapshot.class=="MAGE" and snapshot.note=="Current note",
        "discarded future metadata cannot suppress a queued valid class or note snapshot")
end

local function rotateScope(client)
    local before=client.g.context()
    client.s:event("ADDON_RESTRICTION_STATE_CHANGED",5,2)
    client.s:event("ADDON_RESTRICTION_STATE_CHANGED",5,0)
    local after=client.g.context()
    check(after and before~=after,"same-guild restriction events rotate the ready scope token")
end

do
    local b=bus()
    local client=b:client("Synchronous Scope")
    client.noEcho=true
    local sends=0
    client.sendResult=function(message)
        if message:match("^Q|") then
            sends=sends+1
            if sends==1 then rotateScope(client) end
        end
        return 0
    end
    b:advance(4)
    check(sends==2,"a consumed pull is restored after a stale send result and runs once for the new token")

    local subject=add(client,"Reentrant Class","ROGUE")
    sends=0
    client.sendResult=function(message)
        if message:match("^E|") then
            sends=sends+1
            if sends==1 then rotateScope(client) end
        end
        return 0
    end
    check(share(client,subject,client.g.context())=="shared","class share queues before synchronous rotation")
    b:advance(5)
    check(sends==2,"a stale successful E result cannot discard queued work now owned by a new token")
end

do
    local b=bus()
    local client=b:client("Receive Scope")
    b:advance(5)
    local originalRevision=client.e.GetServerTime
    local reads=0
    client.e.GetServerTime=function()
        reads=reads+1
        if reads==2 then rotateScope(client) end
        return originalRevision()
    end
    event(client,"E|3:101|MAGE,12799,Discarded Class")
    check(not rows(client)["Discarded Class"],"an E received before the ready token rotates cannot write afterward")
    client.e.GetServerTime=originalRevision
    local cached="Retained Subject"
    event(client,"E|3:101|MAGE,12799,"..cached)
    local originalClock=client.e.GetTime
    local start=#b.packets
    reads=0
    client.e.GetTime=function()
        reads=reads+1
        if reads==2 then rotateScope(client) end
        return originalClock()
    end
    event(client,"Q|3:101|8.1")
    b:advance(6)
    check(#b.packets==start and rows(client)[cached],"a stale Q does not enqueue a same-guild snapshot for the new token")
end

local function removed(c, name)
    local db=c.e.WhowhoGuildBlacklistDB
    local records=db and db.removed and db.removed["3:101"]
    return records and records[name]
end

local function sentBy(b, c, start, pattern)
    local found=0
    for index=start+1,#b.packets do
        local packet=b.packets[index]
        if packet.client==c and packet.message:match(pattern) then found=found+1 end
    end
    return found
end

do
    local b=bus()
    local a=b:client("Deleting Member")
    local peer=b:client("Online Member")
    b:advance(5)
    local name="Gone Subject"
    local scope=a.g.context()
    check(a.g.add(name,{"fraud"},"Shared note",scope)=="shared","a row exists before deletion")
    b:advance(5)
    check(rows(peer)[name] and not a.e.WhowhoGuildBlacklistDB.removed,"no removal key exists before a deletion")
    local refreshes, again=0
    a.p.Shell.RefreshGuildBlacklist=function()
        refreshes=refreshes+1
        again=a.g.remove(name,scope)
    end
    local start=#b.packets
    check(a.g.remove("GONE subject",scope)=="removed" and again=="missing" and refreshes==1,
        "case-insensitive remove notifies once and a reentrant duplicate finds nothing")
    a.p.Shell.RefreshGuildBlacklist=nil
    local saved=a.e.WhowhoGuildBlacklistDB
    check(#a.g.list()==0 and not saved.scopes["3:101"][name] and next(saved.scopes["3:101"])==nil
        and removed(a,name).gone==true and saved.version==1,"removal persists beside an empty scope")
    b:advance(0)
    check(b.packets[start+1].message==string.format("X|3:101|%.0f,1,%s",removed(a,name).rev,name)
        and not next(rows(peer)) and removed(peer,name).gone==true,
        "the removal is pushed at once and an online peer applies and saves it")
    local record=removed(peer,name)
    event(peer,"E|3:101|MAGE,12799,"..name)
    event(peer,"E|3:101|,0,GONE SUBJECT")
    for _, packet in ipairs(detailPackets("3:101","3.1","12799|spam|"..name.."|Stale note")) do event(peer,packet) end
    check(not next(rows(peer)) and not next(peer.e.WhowhoGuildBlacklistDB.scopes["3:101"])
        and removed(peer,name).rev==record.rev,"stale class and detail packets cannot recreate a removed name")

    a.online,peer.online=false,false
    local reloaded=b:client("Reloaded Deleter",{shared=saved})
    start=#b.packets
    event(reloaded,"E|3:101|,0,"..name)
    b:advance(0)
    check(not next(rows(reloaded)) and removed(reloaded,name).gone,"a removal survives reload")
    check(sentBy(b,reloaded,start,"^H|")==1,"a client holding only removals announces itself")
    local stale={version=1,scopes={["3:101"]={[name]={class="MAGE",rev=12799}}}}
    b:advance(100)
    local returning=b:client("Offline Member",{shared=stale})
    b:advance(20)
    check(not rows(returning)[name] and removed(returning,name).gone and not rows(reloaded)[name],
        "an offline holder catches up from a peer that has no rows left")
    local empty=b:client("Brand New Member")
    b:advance(120)
    check(removed(empty,name) and removed(empty,name).gone,"a client with no data receives removals too")

    local old=removed(reloaded,name).rev
    local personal=add(reloaded,name,"MAGE","Personal note")
    local records=reloaded.e.WhowhoGuildBlacklistDB.removed
    b:advance(5)
    start=#b.packets
    check(share(reloaded,personal,"stale",true)=="unavailable"
        and share(reloaded,personal,(reloaded.g.context()),true)=="deleted",
        "sharing a personal entry cannot restore a removed name")
    b:advance(5)
    check(not next(rows(reloaded)) and reloaded.e.WhowhoGuildBlacklistDB.removed==records
        and removed(reloaded,name).gone and removed(reloaded,name).rev==old and #b.packets==start
        and next(reloaded.e.WhowhoGuildBlacklistDB.scopes["3:101"])==nil,
        "a refused share leaves rows and records untouched and sends nothing")
    check(reloaded.g.add(name,{"spam"},nil,(reloaded.g.context()))=="shared","adding again restores the name")
    start=#b.packets
    b:advance(5)
    check(removed(reloaded,name).gone==false and removed(reloaded,name).rev>old
        and rows(returning)[name] and rows(returning)[name].reasonIds[1]=="spam" and removed(returning,name).gone==false,
        "the restore reaches a peer that had applied the removal")
    event(returning,string.format("X|3:101|%.0f,1,%s",old,name))
    event(returning,string.format("X|3:101|%.0f,0,%s",old,name))
    check(rows(returning)[name] and removed(returning,name).gone==false,"an older removal cannot override a restore")
    local tie=removed(returning,name).rev
    event(returning,string.format("X|3:101|%.0f,1,%s",tie,name))
    event(returning,string.format("X|3:101|%.0f,0,%s",tie,name))
    check(not rows(returning)[name] and removed(returning,name).gone==true,"equal revisions resolve to removal")
end

do
    local b=bus()
    local name="Catch Up"
    local seeded={version=1,scopes={["3:101"]={["Kept Subject"]={rev=0}}},
        removed={["3:101"]={[name]={rev=12800,gone=false}}}}
    local holder=b:client("Restored Holder",{shared=seeded})
    holder.g.add(name,{"spam"},nil,(holder.g.context()))
    b:advance(100)
    local late=b:client("Late Member",{shared={version=1,scopes={["3:101"]={}},
        removed={["3:101"]={[name]={rev=12799,gone=true}}}}})
    local start=#b.packets
    b:advance(120)
    local first
    for index=start+1,#b.packets do
        local packet=b.packets[index]
        local command=packet.message:sub(1,1)
        if packet.client==holder and (command=="X" or command=="E") then first=first or command end
    end
    check(first=="X" and rows(late)[name] and removed(late,name).gone==false,
        "a snapshot sends removal records ahead of rows so a restore arrives first")
end

do
    local b=bus()
    local function cache()
        return {version=1,scopes={["3:101"]={}},removed={["3:101"]={["Same Removal"]={rev=12799,gone=true}}}}
    end
    local a=b:client("First Record Holder",{shared=cache()})
    local peer=b:client("Second Record Holder",{shared=cache()})
    b:advance(200)
    local start=#b.packets
    b:client("Record Requester")
    b:advance(16)
    check(sentBy(b,a,start,"^X|")+sentBy(b,peer,start,"^X|")==1,
        "an equivalent holder drops its redundant queued record")
end

do
    local b=bus()
    local a=b:client("Record Guard")
    b:advance(5)
    event(a,"E|3:101|,0,Valid Name")
    local saved=a.e.WhowhoGuildBlacklistDB
    for _, payload in ipairs({
        "12800,2,Valid Name","12800,1,Onlyone","x,1,Valid Name","12800,1,Valid Name|broken",
        "12800,1,Valid Name|12800,1,Valid Name","12800,1,Valid Name|","0,1,Valid Name",
        "549755813887,1,Valid Name","99999999999999999999,1,Valid Name",
        "12800,1,"..string.rep("x",240).." Name",
    }) do event(a,"X|3:101|"..payload) end
    event(a,"X|3:202|12800,1,Valid Name")
    event(a,"X|3:101|12800,1,Valid Name",nil,"OFFICER")
    event(a,a.s.secret)
    check(rows(a)["Valid Name"] and not saved.removed,"invalid, future and foreign removals are ignored")
    a.locked=true
    event(a,"X|3:101|12800,1,Valid Name")
    a.locked=false
    check(rows(a)["Valid Name"] and not saved.removed,"an unready client ignores removals")
    event(a,"X|3:101|12800,1,Never Seen")
    check(removed(a,"Never Seen").gone,"a removal is saved even without a row")

    local scope=a.g.context()
    check(a.g.remove("One",scope)=="invalid_name" and a.g.remove(a.s.secret,scope)=="invalid_name"
        and a.g.remove("Absent Name",scope)=="missing" and a.g.remove("Valid Name","stale")=="unavailable"
        and a.g.remove("Valid Name",a.s.secret)=="unavailable","remove validates its inputs")
    a.locked=true
    check(a.g.remove("Valid Name",scope)=="unavailable","an unready transport cannot delete")
    a.locked=false
    scope=a.g.context()
    local serverTime=a.e.GetServerTime
    local reads=0
    a.e.GetServerTime=function()
        reads=reads+1
        if reads==2 then rotateScope(a) end
        return serverTime()
    end
    check(a.g.remove("Valid Name",scope)=="unavailable" and rows(a)["Valid Name"] and not removed(a,"Valid Name"),
        "a scope rotating during a native read changes nothing")
    a.e.GetServerTime=serverTime
    scope=a.g.context()
    a.guild=202
    check(a.g.remove("Valid Name",scope)=="unavailable" and not removed(a,"Valid Name"),
        "a stale guild scope changes nothing")
end

do
    local b=bus()
    local a=b:client("Queue Dropper")
    local peer=b:client("Queue Watcher")
    b:advance(5)
    local name="Queued Victim"
    local scope=a.g.context()
    check(a.g.add(name,{"fraud"},string.rep("long note ",20),scope)=="shared"
        and a.g.remove(name,scope)=="removed","remove before the queued row is sent")
    local start=#b.packets
    b:advance(40)
    check(sentBy(b,a,start,"^[ED]|")==0 and sentBy(b,a,start,"^X|")==1 and not rows(peer)[name],
        "queued class and detail packets of a removed name are never sent")

    a.sendResult=function(message) return message:match("^E|") and 3 or 0 end
    check(a.g.add("Retry Victim",{"fraud"},nil,scope)=="shared","a row enters retry backoff")
    b:advance(1.3)
    a.sendResult=nil
    start=#b.packets
    check(a.g.remove("Retry Victim",scope)=="removed","remove during the row retry")
    b:advance(40)
    check(sentBy(b,a,start,"^[ED]|")==0 and not rows(peer)["Retry Victim"],"the removed row retry is discarded")

    check(a.g.add("Throttled Removal",{"fraud"},nil,scope)=="shared","a delivered row precedes a throttled removal")
    b:advance(5)
    local attempts=0
    a.sendResult=function(message)
        if message:match("^X|") then attempts=attempts+1; if attempts<3 then return 8 end end
        return 0
    end
    check(a.g.remove("Throttled Removal",scope)=="removed","the removal is queued")
    b:advance(15)
    check(attempts==3 and not rows(peer)["Throttled Removal"],"a throttled removal retries until delivered")

    check(a.g.add("Paused Removal",{"fraud"},nil,scope)=="shared","a row precedes a paused removal")
    b:advance(5)
    check(a.g.remove("Paused Removal",scope)=="removed","the removal is queued before lockdown")
    a.locked=true
    b:advance(1)
    check(rows(peer)["Paused Removal"],"lockdown holds the queued removal")
    a.locked=false
    b:advance(20)
    check(not rows(peer)["Paused Removal"],"a readiness timer alone resumes a queued removal")
end

do
    local b=bus()
    local name="Downgraded Return"
    local cache={version=1,scopes={["3:101"]={[name]={class="MAGE",rev=12799},["Other Subject"]={rev=0}}},
        removed={["3:101"]={[name]={rev=12799,gone=true}}}}
    local a=b:client("Upgraded Again",{shared=cache})
    check(not rows(a)[name] and rows(a)["Other Subject"] and not cache.scopes["3:101"][name]
        and cache.removed["3:101"][name].gone,"a loaded row with a removal record is dropped and persisted")
    local plain={version=1,scopes={["3:101"]={["Old Save"]={rev=0}}}}
    local older=b:client("Older Save",{shared=plain})
    check(rows(older)["Old Save"] and plain.removed==nil,"a save without removals loads unchanged")
    for _, bad in ipairs({
        5, {["3:101"]=5}, {["3:202"]={}}, {["3:101"]={Onlyone={rev=1,gone=true}}},
        {["3:101"]={[name]={rev=0,gone=true}}}, {["3:101"]={[name]={rev=1,gone=1}}},
        {["3:101"]={[name]=true}},
    }) do
        local corrupt={version=1,scopes={["3:101"]={}},removed=bad}
        local client=b:client("Bad Removal Cache",{shared=corrupt})
        check(client.g.context()==nil and corrupt.removed==bad,"an invalid removal cache is preserved and unused")
        client.online=false
    end
end

do
    local b=bus()
    local seeded=seededCache(2)
    local records={}
    for index=1,512 do records["Record"..index.." Subject"]={rev=1000+index,gone=true} end
    seeded.removed={["3:101"]=records}
    local a=b:client("Capped Records",{shared=seeded})
    b:advance(2)
    check(a.g.remove("Seed1 Subject",a.g.context())=="removed","remove at the record cap")
    local function size()
        local total=0
        for _ in pairs(a.e.WhowhoGuildBlacklistDB.removed["3:101"]) do total=total+1 end
        return total
    end
    check(size()==512 and not removed(a,"Record1 Subject") and removed(a,"Record2 Subject")
        and removed(a,"Seed1 Subject").gone,"a local removal drops the oldest record")
    event(a,"X|3:101|12800,1,Incoming Subject")
    check(size()==512 and not removed(a,"Record2 Subject") and removed(a,"Incoming Subject"),
        "a received removal respects the same cap")
end

do
    local b=bus()
    local seeded=seededCache(512)
    seeded.removed={["3:101"]={["Zzz Subject"]={rev=12799,gone=true}}}
    local a=b:client("Full Restore",{shared=seeded})
    b:advance(2)
    local start=#b.packets
    check(a.g.add("Zzz Subject",{"fraud"},nil,(a.g.context()))=="limit" and removed(a,"Zzz Subject").gone
        and removed(a,"Zzz Subject").rev==12799,"a restore that cannot be stored keeps the removal")
    check(a.g.add("Zzz Subject",{"fraud"},"\t",a.g.context())=="invalid_note","an invalid restore is refused")
    b:advance(5)
    check(sentBy(b,a,start,"^[XED]|")==0,"a refused restore queues nothing")
    check(a.g.remove("Seed1 Subject",(a.g.context()))=="removed" and removed(a,"Zzz Subject").gone
        and removed(a,"Zzz Subject").rev==12799,"a later write still saves the refused name as removed")
end

do
    local b=bus()
    local a=b:client("Cutoff Remover",{shared=seededCache(512)})
    b:advance(2)
    local scope=a.g.context()
    check(a.g.remove("Seed99 Subject",scope)=="removed" and a.g.add("Alpha Subject",{"fraud"},nil,scope)=="shared"
        and a.g.add("Beta Subject",{"fraud"},nil,scope)=="shared","removing the byte-last row keeps the cap usable")
    local entries=rows(a)
    check(#a.g.list()==512 and entries["Alpha Subject"] and entries["Beta Subject"] and not entries["Seed98 Subject"],
        "the next addition at capacity displaces the new byte-last row")
end

do
    local b=bus()
    local shared={version=1,scopes={}}
    for club=1,32 do shared.scopes["3:"..(500+club)]={} end
    local a=b:client("Scope Limited",{shared=shared})
    event(a,"X|3:101|12800,1,Valid Name")
    check(not shared.scopes["3:101"] and not shared.removed,"removals cannot exceed the scope limit")
end

for _, outcome in ipairs({"sent","dropped"}) do
    local b=bus()
    local a=b:client("Quick Remover")
    local peer=b:client("Watching Member")
    b:advance(5)
    local name="Quick Return"
    local scope=a.g.context()
    check(a.g.add(name,{"spam"},"Old note",scope)=="shared","a row precedes a quick re-add")
    b:advance(10)
    check(rows(peer)[name] and rows(peer)[name].note=="Old note","the peer holds the old details")
    a.sendResult=function(message) return message:match("^X|") and 8 or 0 end
    check(a.g.remove(name,scope)=="removed","the removal is queued behind a throttle")
    b:advance(1)
    local record=removed(a,name)
    local rev,start=record.rev,#b.packets
    check(a.g.add(name,{"fraud"},nil,scope)=="unavailable","a re-add waits for the unsent removal")
    check(not rows(a)[name] and removed(a,name)==record and record.gone and record.rev==rev,
        "a refused re-add changes no row or record")
    if outcome=="sent" then a.sendResult=nil end
    b:advance(30)
    check(sentBy(b,a,start,"^[ED]|")==0 and sentBy(b,a,start,"^X|")>=1,"a refused re-add queues nothing")
    check((rows(peer)[name]==nil)==(outcome=="sent"),"the queued removal still reaches the peer unless dropped")
    a.sendResult=nil
    check(a.g.add(name,{"fraud"},nil,scope)=="shared","a re-add restores once the removal left the queue: "..outcome)
    b:advance(15)
    if outcome=="sent" then
        local entry=rows(peer)[name]
        check(entry and #entry.reasonIds==1 and entry.reasonIds[1]=="fraud" and not entry.note
            and removed(peer,name).gone==false,"the peer ends without the old reasons and note")
    end
end

-- Every way a queued removal can stall ends, and the refused re-add works again.
for _, path in ipairs({"throttled","failing","lockdown","timer fault","guild change","missed timer"}) do
    local b=bus()
    local a=b:client("Stalled Remover")
    b:advance(5)
    local name="Stalled Return"
    check(a.g.add(name,{"spam"},nil,(a.g.context()))=="shared","a row precedes the stalled removal")
    b:advance(10)
    local attempts=0
    if path=="throttled" or path=="failing" then
        a.sendResult=function(message)
            if message:match("^X|") then attempts=attempts+1; return path=="throttled" and 8 or 9 end
            return 0
        end
    elseif path=="timer fault" then a.timerThrows=true end
    check(a.g.remove(name,(a.g.context()))=="removed","the removal is accepted without waiting for a send: "..path)
    local start=#b.packets
    if path=="lockdown" then a.locked=true
    elseif path=="guild change" then
        a.guild=202; a.s:event("PLAYER_GUILD_UPDATE","player")
    elseif path=="missed timer" then
        local calls=0
        a.e.GetTime=function()
            calls=calls+1
            if calls==2 then return nil end
            return b.time
        end
    end
    b:advance(120)
    if path=="throttled" or path=="failing" then
        check(attempts==3,"retries are exhausted: "..path)
        a.sendResult=nil
    elseif path=="lockdown" then
        check(a.g.add(name,{"fraud"},nil,"stale")=="unavailable","a locked transport refuses the re-add")
        a.locked=false
    elseif path=="timer fault" then
        check(a.g.context()==nil,"a timer fault leaves the whole transport unavailable")
        a.timerThrows=false
        a.s:event("PLAYER_ENTERING_WORLD",false,false)
    elseif path=="guild change" then
        a.guild=101; a.s:event("PLAYER_GUILD_UPDATE","player")
        b:advance(5)
    end
    local result=a.g.add(name,{"fraud"},nil,(a.g.context()))
    if path=="lockdown" or path=="timer fault" or path=="missed timer" then
        check(result=="unavailable" and sentBy(b,a,start,"^X|")==0,"the removal is still queued: "..path)
        b:advance(20)
        check(sentBy(b,a,start,"^X|")>=1,"the queued removal is sent: "..path)
        result=a.g.add(name,{"fraud"},nil,(a.g.context()))
    end
    check(result=="shared" and rows(a)[name],"the re-add works once the transport is usable: "..path)
end

-- Deletion never waits for the sync request or for its own send.
do
    local b=bus()
    local a=b:client("Lonely Deleter")
    b:advance(5)
    check(a.g.add("Unanswered Subject",{"spam"},nil,(a.g.context()))=="shared","a row exists to delete")
    b:advance(10)
    a.sendResult=9
    a.noEcho=true
    a.p.Toggle()
    local S=a.p.Shell
    S.nav.guildBlacklist:Click()
    b:advance(40)
    a.sendResult=nil
    S.RefreshGuildBlacklist()
    b:advance(40)
    a.sendResult=9
    S.rows[1].deleteButton:Click()
    check(S.deleteDialog:IsShown() and S.deleteConfirm:IsEnabled(),"the dialog does not wait for a sync reply")
    S.deleteConfirm:Click()
    check(not S.deleteDialog:IsShown() and not S.scrim:IsShown() and not rows(a)["Unanswered Subject"],
        "confirm gives its result at once, with no reply and a failing send")
end

-- The open dialog survives a transport pause, but not new or unsettled membership.
for _, change in ipairs({"restriction toggled","still paused","membership resettled","membership settling","guild change"}) do
    local b=bus()
    local a=b:client("Dialog Deleter")
    local peer=b:client("Dialog Watcher")
    b:advance(5)
    local name="Dialog Subject"
    check(a.g.add(name,{"spam"},nil,(a.g.context()))=="shared","a row exists for the dialog")
    b:advance(10)
    a.p.Toggle()
    local S=a.p.Shell
    S.nav.guildBlacklist:Click()
    S.rows[1].deleteButton:Click()
    check(S.deleteDialog:IsShown(),"the dialog opens: "..change)
    local token=a.g.context()
    if change=="restriction toggled" then
        a.s:event("ADDON_RESTRICTION_STATE_CHANGED",5,2)
        a.s:event("ADDON_RESTRICTION_STATE_CHANGED",5,0)
        check(a.g.context() and a.g.context()~=token,"the toggle issues a new write token")
    elseif change=="still paused" then
        a.s:event("ADDON_RESTRICTION_STATE_CHANGED",5,2)
    else
        if change=="guild change" then a.guild=202 end
        a.s:event("PLAYER_GUILD_UPDATE","player")
        if change=="membership resettled" then b:advance(5) end
        if change=="guild change" then b:advance(5) end
    end
    -- A guild change closes the dialog itself; a click on its hidden button must still delete nothing.
    S.deleteConfirm:Click()
    b:advance(10)
    if change=="restriction toggled" then
        check(not S.deleteDialog:IsShown() and not rows(a)[name] and not rows(peer)[name],
            "confirm after a toggle deletes for the guild")
    else
        check(not a.e.WhowhoGuildBlacklistDB.removed and rows(peer)[name],"nothing is deleted: "..change)
        check(change=="guild change" and not S.deleteDialog:IsShown()
            or S.deleteError:GetText()=="Deleting is unavailable.","the dialog reports or has closed: "..change)
    end
end

-- At the record cap, a removal older than every held record is ignored whole.
do
    local b=bus()
    local seeded=seededCache(2)
    local records={}
    for index=1,512 do records["Record"..index.." Subject"]={rev=1000+index,gone=true} end
    seeded.removed={["3:101"]=records}
    local a=b:client("Capped Receiver",{shared=seeded})
    b:advance(2)
    local function held()
        local total=0
        for _ in pairs(a.e.WhowhoGuildBlacklistDB.removed["3:101"]) do total=total+1 end
        return total
    end
    local refreshes=0
    a.p.Shell.RefreshGuildBlacklist=function() refreshes=refreshes+1 end
    event(a,"X|3:101|1000,1,Seed1 Subject")
    check(rows(a)["Seed1 Subject"] and refreshes==0 and held()==512 and not removed(a,"Seed1 Subject")
        and removed(a,"Record1 Subject"),"an older removal at the cap changes nothing")
    event(a,"E|3:101|,0,Seed1 Subject")
    check(rows(a)["Seed1 Subject"] and refreshes==0,"a stale row packet has nothing to bring back")
    event(a,"X|3:101|12800,1,Seed1 Subject")
    check(not rows(a)["Seed1 Subject"] and removed(a,"Seed1 Subject").gone and held()==512
        and not removed(a,"Record1 Subject") and refreshes==1,"a newer removal at the cap still applies")
end

-- Leaving a guild erases its saved list; every assertion reads the saved table.
local ME="3:Current Character"
local function guildCache(members)
    return {version=1,scopes={["3:101"]={["Listed Subject"]={rev=0}},["3:303"]={["Other Guild"]={rev=0}}},
        removed={["3:101"]={["Gone Subject"]={rev=12799,gone=true}}},members=members}
end
local function kept(db) return db.scopes["3:101"] ~= nil and db.removed["3:101"] ~= nil end
local function erased(db)
    return db.scopes["3:101"]==nil and db.removed["3:101"]==nil and db.scopes["3:303"] ~= nil and db.version==1
end
local function member(db, key) return db.members and db.members[key or ME] end
local function recorded()
    local b=bus()
    local db=guildCache()
    local a=b:client("Guild Member",{shared=db})
    b:advance(5)
    assert(member(db)=="3:101","setup: membership recorded")
    return b,a,db
end
local function guildEvent(c, guild)
    c.guild=guild
    c.s:event("PLAYER_GUILD_UPDATE","player")
end
local function relog(b, old, db, settings)
    old.online=false
    settings=settings or {}
    settings.shared=db
    return b:client("Guild Member",settings)
end

do
    local b=bus()
    local db=guildCache()
    local a=b:client("Guild Member",{shared=db})
    check(db.members==nil,"a single reading records no membership")
    b:advance(2)
    a.g.context()
    check(db.members==nil,"two readings under three seconds apart record nothing")
    b:advance(3)
    check(member(db)=="3:101" and db.version==1,"a second reading with no event between records membership")

    local fresh={version=1,scopes={}}
    local c=b:client("List Later",{shared=fresh,character="Late Lister",guild=404})
    b:advance(5)
    check(fresh.members==nil,"a guild without a saved list records nothing")
    event(c,"E|3:404|,0,Valid Name")
    check(member(fresh,"3:Late Lister")=="3:404","the first saved list records an already confirmed membership")

    local settled=guildCache()
    local d=b:client("Event Member",{shared=settled})
    guildEvent(d,101)
    b:advance(0.8)
    check(member(settled)=="3:101","a settled reading after a guild event records at once")
end

do
    local b,a,db=recorded()
    local start=#b.packets
    guildEvent(a,false)
    b:advance(59)
    check(kept(db) and member(db)=="3:101","no guild keeps the list for the first minute")
    b:advance(2)
    check(erased(db) and member(db)==nil,"leaving while playing erases rows, removal records and membership")
    b:advance(120)
    check(#b.packets==start,"the erase sends nothing")
    local again=relog(b,a,db,{guild=101})
    check(again.g.context() and not next(rows(again)) and erased(db),"the erased save loads in a fresh client")
    check(again.g.add("Listed Subject",{"spam"},nil,(again.g.context()))=="shared","a rejoin starts a new list")
    b:advance(5)
    check(db.scopes["3:101"]["Listed Subject"] and member(db)=="3:101","the rejoined guild is recorded again")
end

do
    local b,a,db=recorded()
    guildEvent(a,false)
    b:advance(30)
    guildEvent(a,101)
    b:advance(120)
    check(kept(db) and member(db)=="3:101","a momentary no guild keeps the list")

    local login=relog(b,a,db,{guild=false})
    b:advance(30)
    login.guild=101
    b:advance(120)
    check(kept(db),"no guild at login keeps the list when the guild reads back, with no event")
    relog(b,login,db,{inGuild=false})
    b:advance(120)
    check(kept(db),"IsInGuild false with a usable club ID is not no guild")
end

for _, away in ipairs({false,202}) do
    local b,a,db=recorded()
    relog(b,a,db,{guild=away})
    b:advance(59)
    check(kept(db),"an offline change keeps the list for a minute: "..tostring(away))
    b:advance(2)
    check(erased(db) and member(db)==nil,"an offline leave or guild change erases after a minute: "..tostring(away))
end

do
    local b,a,db=recorded()
    local start=#b.packets
    guildEvent(a,202)
    check(kept(db),"an unsettled guild change keeps the list")
    b:advance(0.8)
    check(erased(db) and member(db)==nil,"joining another guild while playing erases at once")
    b:advance(120)
    check(#b.packets==start+1 and b.packets[#b.packets].message:match("^Q|3:202|"),
        "the erase sends nothing beyond the new guild's startup query")

    local quiet,silent,quietDB=recorded()
    silent.guild=202
    silent.g.context()
    check(kept(quietDB),"a guild change with no event is not conclusive")
    quiet:advance(61)
    check(erased(quietDB),"a guild change with no event erases after a minute")

    local late,stale,staleDB=recorded()
    stale.inGuild=true
    guildEvent(stale,nil)
    late:advance(61)
    stale.inGuild,stale.guild=nil,202
    stale.g.context()
    check(kept(staleDB),"the follow-up reading ends the immediate window")

    local again,home,homeDB=recorded()
    guildEvent(home,101)
    again:advance(30)
    home.guild=202
    home.g.context()
    check(kept(homeDB),"a settled reading of the recorded guild ends the immediate window")

    local switch,online,onlineDB=recorded()
    guildEvent(online,false)
    switch:advance(5)
    guildEvent(online,202)
    switch:advance(0.8)
    check(erased(onlineDB),"a leave then a join while playing erases the old list at once")
end

do
    local b,a,db=recorded()
    local login=relog(b,a,db,{guild=202})
    login.s:event("PLAYER_GUILD_UPDATE","player")
    b:advance(0.8)
    check(kept(db),"a guild event at login does not trust one other guild reading")
    b:advance(58)
    check(kept(db),"the login mismatch keeps the list for a minute")
    b:advance(2)
    check(erased(db),"the login mismatch erases after a matching reading")

    local world,c,cache=recorded()
    c.s:event("PLAYER_LEAVING_WORLD")
    c.guild=202
    c.s:event("PLAYER_ENTERING_WORLD",false,false)
    c.s:event("PLAYER_GUILD_UPDATE","player")
    world:advance(0.8)
    check(kept(cache),"a loading screen forgets that the recorded guild was read")
    world:advance(62)
    check(erased(cache),"the mismatch after a loading screen erases after a minute")

    local first=bus()
    local fresh=guildCache()
    local d=first:client("Event Recorded",{shared=fresh})
    -- Hold back send timers: their own readings would also close the window.
    local after=d.e.C_Timer.After
    d.e.C_Timer.After=function(delay,fn) if delay>=0.75 then after(delay,fn) end end
    guildEvent(d,101)
    first:advance(0.8)
    d.guild=202
    d.g.context()
    check(kept(fresh) and member(fresh)=="3:101","the reading that first records a guild ends the window")
    guildEvent(d,202)
    first:advance(0.8)
    check(erased(fresh),"the reading that first records a guild counts as read in it")
end

do
    local b,a,db=recorded()
    local readName=a.e.UnitNameUnmodified
    a.guild=202
    a.e.UnitNameUnmodified=function()
        a.e.UnitNameUnmodified=readName
        guildEvent(a,202)
        return readName()
    end
    a.g.context()
    check(kept(db) and member(db)=="3:101","an event during the name read neither erases nor records")
    b:advance(0.8)
    check(erased(db),"the interrupted reading leaves the event to its own settlement")

    local fresh=guildCache()
    local c=b:client("Unrecorded Member",{shared=fresh})
    local read=c.e.UnitNameUnmodified
    c.e.UnitNameUnmodified=function()
        c.e.UnitNameUnmodified=read
        guildEvent(c,303)
        return read()
    end
    c.g.context()
    check(fresh.members==nil,"an interrupted name read records nothing")
    b:advance(0.8)
    check(member(fresh)=="3:303","the settlement of that event records the new guild")
end

do
    local b,a,db=recorded()
    guildEvent(a,false)
    b:advance(20)
    guildEvent(a,101)
    b:advance(20)
    guildEvent(a,false)
    b:advance(30)
    check(kept(db),"a rejoin drops the first leave timer")
    b:advance(32)
    check(erased(db),"the second leave has its own minute")
end

do
    local b,a,db=recorded()
    guildEvent(a,false)
    b:advance(30)
    a.s:event("PLAYER_LEAVING_WORLD")
    b:advance(60)
    check(kept(db),"nothing is erased during a loading screen")
    a.s:event("PLAYER_ENTERING_WORLD",false,false)
    b:advance(59)
    check(kept(db),"a loading screen restarts the minute")
    b:advance(2)
    check(erased(db),"the leave is still found after the loading screen")
end

for _, away in ipairs({false,202}) do
    local b,a,db=recorded()
    guildEvent(a,101)
    b:advance(10)
    a.guild=away
    b:advance(49)
    check(kept(db),"the old guild still read after the event keeps the list: "..tostring(away))
    b:advance(62)
    check(erased(db),"the follow-up reading finds a lagging leave: "..tostring(away))
end

local function longTimers(c)
    local found={}
    local after=c.e.C_Timer.After
    c.e.C_Timer.After=function(delay,fn)
        if delay>=30 then found[#found+1]=delay end
        return after(delay,fn)
    end
    return found
end

do
    local b,a=recorded()
    local timers=longTimers(a)
    guildEvent(a,101)
    b:advance(1)
    check(#timers==1 and timers[1]==59.25,"a recorded guild gets one follow-up reading a minute after the event")

    local db=guildCache()
    local c=b:client("Unlisted Member",{shared=db,character="Unlisted Member",guild=404})
    b:advance(5)
    local none=longTimers(c)
    guildEvent(c,404)
    b:advance(1)
    check(#none==0 and member(db,"3:Unlisted Member")==nil,"without a recorded guild no follow-up is scheduled")
    c.guild=303
    c.g.context()
    check(member(db,"3:Unlisted Member")==nil,"with no follow-up one later reading records nothing")
end

do
    local b,a,db=recorded()
    guildEvent(a,false)
    b:advance(30)
    a.s:event("PLAYER_LEAVING_WORLD")
    b:advance(10)
    a.s:event("PLAYER_ENTERING_WORLD",false,false)
    b:advance(21)
    check(kept(db),"a loading screen drops the pending leave timer")

    local late,c,cache=recorded()
    guildEvent(c,101)
    late:advance(1)
    c.s:event("PLAYER_LEAVING_WORLD")
    c.s:event("PLAYER_ENTERING_WORLD",false,false)
    c.guild=202
    c.g.context()
    check(kept(cache),"one other guild reading after a loading screen keeps the list")

    local relogged,d,saved=recorded()
    local login=relog(relogged,d,saved,{guild=false})
    relogged:advance(59)
    login.guild=202
    relogged:advance(2)
    check(kept(saved),"a timer reading that differs from the first mismatch erases nothing")
end

do
    local b=bus()
    local db=guildCache()
    local first=b:client("First Alt",{shared=db,character="First Alt"})
    b:advance(5)
    first.online=false
    local second=b:client("Second Alt",{shared=db,character="Second Alt"})
    b:advance(5)
    check(member(db,"3:First Alt")=="3:101" and member(db,"3:Second Alt")=="3:101","both alts are recorded")
    guildEvent(second,202)
    b:advance(120)
    check(kept(db) and member(db,"3:Second Alt")==nil and member(db,"3:First Alt")=="3:101",
        "an alt still recorded in the guild keeps its list")
    second.online=false
    b:client("First Alt",{shared=db,character="First Alt",guild=false})
    b:advance(61)
    check(erased(db) and member(db,"3:First Alt")==nil,"the last recorded character erases the list")
end

do
    local b=bus()
    local db=guildCache()
    b:client("Never Recorded",{shared=db,guild=false})
    b:advance(120)
    check(kept(db) and db.members==nil,"an rc.2 save loses nothing for a guild never seen")

    for _, bad in ipairs({5,"text",{[ME]="4:101"},{[ME]="3:101x"},{[ME]=true},{["4:Current Character"]="4:101"},
        {["3:Onlyone"]="3:101",[7]="3:101"}}) do
        local cache=guildCache(bad)
        local c=b:client("Bad Members",{shared=cache,guild=false})
        b:advance(120)
        check(kept(cache) and cache.members==bad,"bad membership entries erase nothing")
        c.online=false
    end
    local replaced=guildCache(5)
    local c=b:client("Replaced Members",{shared=replaced})
    check(c.g.context() and replaced.members==5,"a non-table membership value does not reject the store")
    b:advance(5)
    check(member(replaced)=="3:101","the next write replaces a non-table membership value")
    c.online=false
    local junk=guildCache({[ME]="junk",["3:Bad Alt"]="4:101"})
    local d=b:client("Junk Members",{shared=junk})
    b:advance(5)
    guildEvent(d,202)
    b:advance(0.8)
    check(erased(junk),"bad entries neither block recording nor protect a list")
end

for _, failure in ipairs({"throw","missing"}) do
    for _, away in ipairs({false,202}) do
        local b,a,db=recorded()
        if failure=="throw" then a.timerThrows=true else a.e.C_Timer.After=nil end
        guildEvent(a,away)
        a.s:event("INITIAL_CLUBS_LOADED")
        a.g.context()
        b:advance(120)
        a.g.context()
        check(kept(db),"a "..failure.." timer never erases: "..tostring(away))
    end
end

for _, unknown in ipairs({"name","guild","region","secret club","failing club","no club"}) do
    local b,a,db=recorded()
    a.guild=false
    if unknown=="name" then a.e.UnitNameUnmodified=function() error("unreadable") end
    elseif unknown=="guild" then a.e.IsInGuild=function() return a.s.secret end
    elseif unknown=="region" then a.e.GetCurrentRegion=function() return a.s.secret end
    elseif unknown=="secret club" then a.e.C_Club.GetGuildClubId=function() return a.s.secret end
    elseif unknown=="failing club" then a.e.C_Club.GetGuildClubId=function() error("unreadable") end
    else a.inGuild,a.guild=true,nil end
    a.s:event("PLAYER_GUILD_UPDATE","player")
    b:advance(70)
    a.g.context()
    b:advance(70)
    check(kept(db) and member(db)=="3:101","unknown membership keeps the list: "..unknown)
end

do
    local b,a,db=recorded()
    guildEvent(a,false)
    b:advance(30)
    a.character="Other Person"
    b:advance(40)
    check(kept(db),"a leave timer cannot erase for another character name")
end

do
    local b=bus()
    local db={version=1,scopes={},members={[ME]="3:101"}}
    for club=101,132 do db.scopes["3:"..club]={} end
    local a=b:client("Scope Slot",{shared=db})
    b:advance(2)
    guildEvent(a,202)
    b:advance(0.8)
    check(db.scopes["3:101"]==nil and a.g.add("New Subject",{"spam"},nil,(a.g.context()))=="shared"
        and db.scopes["3:202"],"the erased list frees its scope slot")
end

check(H.forbiddenCalls==0,"the fake bus never invokes real native actions")
print(string.format("RESULT guild-blacklist-sync %d passed",count))
