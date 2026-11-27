local P=WhowhoPreview
local A=P.manual
local B=P.BlacklistBanner
local G=P.GuildBlacklist
local ledger=A.encounterLedger
local read, readable=A.nativeRead.read, A.nativeRead.readable
local reader=A.unitReader
local bannerCooldown=30
local newEntryCooldown=300
local rosterSettleTime=1
local retryWaits={3,6,12,24,48,84}
local joinBypassInterval=30
local plateLimit=256
-- One table: installSightings functions are close to the Lua 5.1 limit of 60 upvalues.
local limits={absenceGrace=5,pollInterval=.25,groupWindow=3,pendingLifetime=12,pendingLimit=8,blockedLimit=48}

local function allowsLiveBanner()
    if type(IsInInstance)~="function" then return false end
    local ok, inside, kind=pcall(IsInInstance)
    if not ok or not readable(inside) then return false end
    if inside==false then return true end
    return inside==true and readable(kind) and type(kind)=="string" and kind~=""
        and kind~="party" and kind~="raid"
end

local function guildMatch(store,region,name,guid,lookup)
    if not lookup then return end
    local personal,issue=store.find(region,name,guid)
    if issue=="conflict" or personal and personal.membership=="blacklist" then return end
    return lookup(name)
end

local function savedSighting(store,region,name,guid,guildLookup)
    local record=ledger.findBlacklist(store,region,name,guid)
    if record then
        local reasons=A.reasonText(record.reasonIds," · ")
        return {id=record.id,name=record.fullName,guid=guid,reasons=reasons},record.lastKnown
    end
    local id,reasons=guildMatch(store,region,name,guid,guildLookup)
    if not id then return false end
    local source=P.L("Guild Blacklist")
    if reasons~="" then source=source.." · "..reasons end
    return {id=id,name=name,guid=guid,reasons=source,guild=true}
end

local function same(a,b)
    return a and b and a.id==b.id and a.name==b.name and a.guid==b.guid
end

local function readSighting(token, source, store, region, sampled, metadata, owns, plate)
    local retry=metadata.retried=="incomplete" and sampled and sampled.retry
    if retry then sampled.retry=nil end
    local name,guid,state=A.playerAddIdentity(token,store,region,owns)
    -- A counted group slot that is not yet a player shows nobody now, but is read again.
    if (source=="Party" or source=="Raid") and (state=="absent" or state=="non-player") then
        return false,nil,false,false,true
    end
    if state=="absent" or state=="non-player" or state=="self" then return false,nil,false end
    if not name then return nil end
    if plate and (plate.name~=name or plate.guid~=guid) then return false,nil,false,true end
    local sighting,known=savedSighting(store,region,name,guid,metadata.guildLookup)
    if not sighting then
        local prior=metadata.previous[token]
        if metadata.guildUnavailable and prior and prior.guild and prior.name==name and prior.guid==guid then return end
        return false,nil,false
    end
    if sighting.guild then return sighting,nil,false end
    local repeated=same(sighting,sampled)
    if repeated and (not sampled.incomplete or not (retry or metadata.requested[token])) then return sighting end
    local ownedFields=repeated and known and known.guid==guid and known or nil
    if ownedFields and ownedFields.class and ownedFields.faction then return sighting,nil,sighting end
    local evidence,changed,waitingForClock=A.captureBlacklistMetadata(token,store,region,name,guid,source,owns,ownedFields)
    if not changed then
        sighting.incomplete=true
        sighting.retry=not repeated and metadata.retried~="cancelled" and (evidence~=nil or waitingForClock)
        return sighting,evidence,sighting
    end
end

local function settleSample(store,sighting)
    if sighting and sighting.incomplete then
        local record=store.get(sighting.id)
        local known=record and record.lastKnown
        if known and known.guid==sighting.guid and known.class and known.faction then
            sighting.incomplete,sighting.retry=nil,nil
        end
    end
    return sighting
end

local function readGroupContext(token)
    local raidIndex=read(UnitInRaid,token)
    if type(raidIndex)=="number" and raidIndex>=1 and raidIndex<math.huge and raidIndex%1==0 then
        return "Raid"
    elseif read(UnitInParty,token)==true then
        return "Group"
    end
end

local function hasBlacklist()
    for _,record in ipairs(A.records) do
        if record.membership=="blacklist" then return true end
    end
    return false
end

-- Group joins are tracked by GUID, which stays readable when a name is late, and apart from the Blacklist.
local function newParty()
    local party={due=true,known=nil,slots={},joins={},bypassed={},alerted={}}
    function party.track(clock,owns)
        local prefix,count=reader.groupRoster()
        if not prefix then return end
        local seen,held,complete={},{},true
        for i=1,count do
            local token=prefix..i
            local guid=reader.identitySafe(token) and reader.guid(token)
            if not owns() then return end
            if type(guid)=="string" and guid~="" then seen[guid],party.slots[token]=true,guid
            -- shortcut: a hidden GUID keeps only the member last read in its slot; slots shift on leave.
            elseif party.slots[token] then held[party.slots[token]]=true
            else complete=false end
        end
        party.due=false
        local known=party.known
        if not known then
            -- Without one complete roster nothing can be called a join.
            if complete then
                for guid in pairs(seen) do seen[guid]=false end
                party.known=seen
            end
            return
        end
        for guid in pairs(seen) do
            local left=known[guid]
            if left==nil or left and clock-left>=limits.absenceGrace then party.joins[guid]=true end
            known[guid]=false
        end
        for guid,left in pairs(known) do
            if not seen[guid] and not held[guid] and not left then known[guid],party.joins[guid]=clock,nil end
        end
    end
    function party.claim(episode,guid,clock,cooling)
        if not party.joins[guid] then return end
        party.joins[guid]=nil
        -- The roster can be read before its event: that alert already announced this join.
        local alerted=party.alerted[guid]
        if alerted and clock-alerted<limits.absenceGrace then return end
        if cooling then
            local last=party.bypassed[guid]
            if last and clock-last<joinBypassInterval then return end
            episode.join=true
        end
        episode.handled=false
    end
    function party.shown(episode,clock,inRoster)
        local guid=episode.sighting.guid
        if episode.join then party.bypassed[guid]=clock end
        if inRoster then party.alerted[guid]=clock end
    end
    -- A definitively unlisted member must not count as joining when listed later.
    function party.dismiss(units)
        for _,unit in ipairs(units) do
            if unit.roster and unit.sighting==false and not unit.vacant then
                local guid=party.slots[unit.token]
                if guid then party.joins[guid]=nil end
            end
        end
    end
    -- An unshown join alert is claimed again after a loading screen.
    function party.restore(episodes)
        for _,episode in pairs(episodes) do
            if episode.join then
                party.joins[episode.sighting.guid]=true
            end
        end
    end
    return party
end

function B.installSightings()
    if not A.store then return end
    local observer=CreateFrame("Frame",nil,UIParent)
    local function register(event)
        return read(observer.RegisterEvent,observer,event)==true
    end
    if not register("PLAYER_LEAVING_WORLD") or not register("PLAYER_ENTERING_WORLD") then return end
    register("ZONE_CHANGED_NEW_AREA")
    register("PLAYER_LOGOUT")
    local target=register("PLAYER_TARGET_CHANGED")
    local mouseover=register("UPDATE_MOUSEOVER_UNIT")
    local roster=register("GROUP_ROSTER_UPDATE")
    local episodes, previous={},{}
    local plates, plateCount, platesEnabled, plateRevision={},0,false,0
    local sampled,requested,metadataRetry={},{},false
    -- Unreadable players are polled; no event is assumed to announce them. One table limits upvalues.
    local retry={plates={},units={},pass=0,watching=false,at=nil}
    -- Memoized sightings compare book identity without retaining an obsolete snapshot.
    local sampledOwner=setmetatable({}, {__mode="v"})
    local queue, cooldowns={},{}
    local visible, shownAt
    local clock, nextPoll=0,0
    local origin
    local function advance(elapsed)
        local now=read(GetTime)
        if type(now)=="number" and now==now and math.abs(now)<math.huge then
            origin=origin or now-clock
            if now<origin then origin=now-clock end
            clock=math.max(clock,now-origin)
            return true
        elseif elapsed then
            clock=clock+elapsed
        end
    end
    local world, scanning, pending, updating, revision=true,false,false,false,0
    local guildDirty=false
    local resumeTest, suspended=false,false
    local suspendedSightings, rosterRetryUntil, resumeUntil
    local party=newParty()
    local carriedRegion
    local inUpdate, clockAvailable=false,false
    local update
    local function hide()
        visible=nil
        B.hideLive()
    end
    local function refreshNavigation()
        local display=visible
        local encounter=display and display.encounter
        if not encounter or ledger.isActive(encounter.id) then return end
        local version=ledger.revision()
        if display.ledgerRevision==version then return end
        display.ledgerRevision=version
        if not ledger.matchesGroup(display.region,nil,encounter.id,encounter.key) and visible==display then
            display.encounter=nil
            B.clearLiveEncounter()
        end
    end
    local function stopEncounter(episode,at)
        if episode.encounter then
            ledger.stop(episode.encounter.id,(episode.encounterAbsentSince or at)-episode.startedClock)
            episode.encounter,episode.encounterAbsentSince=nil,nil
        end
    end
    local function resetSightings()
        for _,episode in pairs(episodes) do stopEncounter(episode,clock) end
        episodes,previous,queue={},{},{}
        carriedRegion=nil
        sampled,metadataRetry={},false
        rosterRetryUntil=nil
        sampledOwner.store=nil
        resumeTest=false
        hide()
    end
    local function rememberSightings()
        suspendedSightings=suspendedSightings or {}
        for _,sighting in pairs(previous) do
            local episode=episodes[sighting.id]
            if episode and episode.handled and same(sighting,episode.sighting) then
                suspendedSightings[sighting.id]=sighting
            end
        end
    end
    local function carryHandledRoster()
        local seen, handled={},{}
        for token,sighting in pairs(previous) do
            local episode=episodes[sighting.id]
            if episode and episode.handled and same(sighting,episode.sighting)
                and (token:match("^party%d+$") or token:match("^raid%d+$")) then
                seen[token]=sighting
                handled[sighting.id]={sighting=sighting,handled=true}
            end
        end
        return seen,handled
    end
    local function suspend()
        rosterRetryUntil=nil
        if suspended then return end
        suspended,resumeUntil=true,nil
        rememberSightings()
        resetSightings()
    end
    local function pruneCooldowns(armDeferred)
        for scope, names in pairs(cooldowns) do
            for name, deadline in pairs(names) do
                if deadline==true then
                    if armDeferred then names[name]=clock+newEntryCooldown end
                elseif clock>=deadline then
                    names[name]=nil
                end
            end
            if not next(names) then cooldowns[scope]=nil end
        end
    end
    local function onCooldown(region, name)
        local names=cooldowns[region]
        local deadline=names and names[name]
        return deadline==true or (deadline~=nil and clock<deadline)
    end
    local function startCooldown(region,name,seconds)
        local names=cooldowns[region]
        if not names then names={}; cooldowns[region]=names end
        local previous=names[name]
        names[name]=seconds and math.max(type(previous)=="number" and previous or 0,clock+seconds) or true
    end
    function B.deferNewBlacklist(record,store,beforeCommit)
        local stamped=advance()
        -- Whoever is already grouped when listed has not joined, even if no scan has seen them yet.
        if world and roster then party.track(clock,function() return world end) end
        local region=read(GetCurrentRegion)
        if A.store~=store or A.region~=record.region or region~=record.region then return false end
        if beforeCommit and not beforeCommit() then return false end
        if stamped then pruneCooldowns(false) end
        -- A missing timestamp must not let an idle clock jump expire this entry.
        startCooldown(record.region,record.fullName,stamped and newEntryCooldown)
        -- shortcut: a record without a GUID drops every pending join; narrow it if records gain GUIDs.
        if record.guid then party.joins[record.guid]=nil else party.joins={} end
        return true
    end
    local function trackingPlate()
        for token in pairs(plates) do
            if previous[token] then return true end
        end
    end
    -- Each unreadable unit has its own six waits; a read before its wait has passed does not use one.
    function retry.mark(token,guid)
        local unit=retry.units[token]
        if not unit or guid and unit.guid and unit.guid~=guid then
            unit={tries=1,at=clock+retryWaits[1]}
            retry.units[token]=unit
        elseif unit.at and clock>=unit.at then
            unit.tries=unit.tries+1
            local wait=retryWaits[unit.tries]
            unit.at=wait and clock+wait
        end
        unit.guid,unit.pass=guid or unit.guid,retry.pass
    end
    -- A unit that was read, or left, gets fresh waits the next time it cannot be read.
    function retry.sweep()
        for token,unit in pairs(retry.units) do
            if not unit.plate and unit.pass~=retry.pass then retry.units[token]=nil end
        end
    end
    local function refreshUpdates()
        local nextRetry
        if world then
            for token,unit in pairs(retry.units) do
                if unit.at and (not unit.plate or retry.watching and retry.plates[token])
                    and (not nextRetry or unit.at<nextRetry) then nextRetry=unit.at end
            end
        end
        retry.at=nextRetry
        local retrying=nextRetry~=nil
        local needed=not not (world and (pending or rosterRetryUntil or visible or previous.mouseover
            or #queue>0 or trackingPlate() or retrying))
        if world and not needed then
            for _,episode in pairs(episodes) do
                if episode.absentSince or episode.encounterAbsentSince then needed=true; break end
            end
        end
        if updating==needed then return end
        updating=needed
        observer:SetScript("OnUpdate",needed and update or nil)
    end
    local function expireEpisodes()
        for id,episode in pairs(episodes) do
            if episode.encounterAbsentSince and clock-episode.encounterAbsentSince>=limits.absenceGrace then
                stopEncounter(episode,clock)
            end
            if episode.absentSince and clock-episode.absentSince>=limits.absenceGrace then
                episodes[id]=nil
            end
        end
    end
    local function discard(index,handled)
        local entry=table.remove(queue,index)
        entry.episode.queued=nil
        if handled then entry.episode.handled,entry.episode.join=true,nil end
        local episode=episodes[entry.sighting.id]
        if episode and same(episode.sighting,entry.sighting) then
            episode.queued=nil
            if handled then episode.handled,episode.join=true,nil end
        end
    end
    local function deferHidden()
        pending=true
    end
    local function plateRecord(store,region,plate,guildLookup)
        if not store or region~=plate.region then return end
        local record=store.find(region,plate.name,plate.guid)
        if record and record.identityState=="resolved" and record.membership=="blacklist" then return record.id end
        return guildMatch(store,region,plate.name,plate.guid,guildLookup)
    end
    local function forgetPlate(token)
        retry.plates[token]=nil
        if not plates[token] then return end
        plates[token],sampled[token],requested[token]=nil,nil,nil
        plateCount=plateCount-1
    end
    local function clearPlates()
        for token in pairs(plates) do forgetPlate(token) end
        for token in pairs(retry.plates) do retry.units[token]=nil end
        retry.plates={}
        plateRevision=plateRevision+1
    end
    local function rememberPlate(token,expectedFrame,guildLookup)
        retry.plates[token]=nil
        if plateCount>=plateLimit then return end
        local owned,store,region=plateRevision,A.store,A.region
        if not region or not allowsLiveBanner() or not world or owned~=plateRevision then return end
        local function owns()
            return world and platesEnabled and owned==plateRevision and store==A.store and region==A.region
        end
        local frame=reader.playerPlate(token,expectedFrame)
        if not owns() then return end
        local function unreadable()
            retry.plates[token]=true
            -- Plate events arrive outside a scan, when the clock may be stale.
            advance()
            retry.mark(token)
            retry.units[token].plate=true
        end
        if not frame then unreadable(); return end
        local name,guid,state=A.playerAddIdentity(token,store,region,owns)
        if not name then
            if state~="absent" and state~="non-player" and state~="self" and owns() then unreadable() end
            return
        end
        if not reader.playerGuid(guid) or not reader.playerPlate(token,frame) or not owns() then return end
        local plate={frame=frame,name=name,guid=guid,region=region}
        plate.record=plateRecord(store,region,plate,guildLookup)
        plates[token],plateCount=plate,plateCount+1
        retry.units[token]=nil
        return plate.record~=nil
    end
    local function seedPlates()
        if not world or not platesEnabled or not allowsLiveBanner() then return end
        local owned=plateRevision
        local frames=reader.nameplateFrames()
        if not frames then return end
        local guildLookup=G.bannerLookup(A.region)
        local matched,count=false,0
        for _,frame in next,frames do
            if count>=plateLimit or owned~=plateRevision then break end
            count=count+1
            local token=reader.nameplateUnit(frame)
            if owned~=plateRevision then break end
            if token and not plates[token] and rememberPlate(token,frame,guildLookup) then matched=true end
        end
        return matched
    end
    local function retryPlates()
        if not next(retry.plates) then return end
        local tokens={}
        for token in pairs(retry.plates) do tokens[#tokens+1]=token end
        local guildLookup=G.bannerLookup(A.region)
        for _,token in ipairs(tokens) do
            if platesEnabled and retry.plates[token] then rememberPlate(token,nil,guildLookup) end
        end
    end
    local function ownsPlate(token,plate)
        if plates[token]~=plate then return false end
        local frame,visible=reader.nameplateFrame(token)
        if plates[token]~=plate then return false end
        if visible==nil then return nil end
        return visible and rawequal(frame,plate.frame)
    end
    local function scan(owner, resume, metadata, groupToPaint, paintElapsed)
        local store,region=A.store,A.region
        if not world or owner~=revision then return end
        if carriedRegion and carriedRegion~=region then
            resetSightings()
            if not world or owner~=revision then return end
        end
        local guildLookup=metadata.guildLookup
        if guildDirty then
            guildDirty=false
            for _,plate in pairs(plates) do plate.record=plateRecord(store,region,plate,guildLookup) end
        end
        if party.due and roster and allowsLiveBanner() then
            party.track(clock,function() return world and owner==revision end)
        end
        if not world or owner~=revision then return end
        if not store or not (hasBlacklist() or guildLookup or metadata.guildUnavailable and (next(previous) or visible and visible.guild)) then
            if not metadata.guildUnavailable then party.joins={} end
            resetSightings()
            return
        end
        if not allowsLiveBanner() then clearPlates(); suspend(); return end
        local initialRegion=read(GetCurrentRegion)
        if not world or owner~=revision then return end
        if initialRegion~=region then
            resetSightings()
            return
        end
        local function ownsScan()
            return world and owner==revision and store==A.store and region==A.region
                and (not metadata.ownsGuild or metadata.ownsGuild())
        end
        -- Nil means an unavailable identity, and false means a confirmed
        -- non-match. A restriction must not rearm a continuous sighting.
        local units={}
        local currentSample=sampledOwner.store==store and sampled.region==region and sampled
        local function inspect(token, enabled, plate, rosterSource)
            if not ownsScan() then return end
            local sighting,evidence,memo,vacant=false,nil,false,nil
            local function ownsUnit()
                return ownsScan() and (not plate or plates[token]==plate)
            end
            if enabled==nil then
                sighting,memo=nil,nil
            elseif enabled then
                local available=not plate or ownsPlate(token,plate)
                if available and ownsUnit() then
                    local recycled
                    sighting,evidence,memo,recycled,vacant=readSighting(token,rosterSource or reader.worldSource(token),store,region,
                        currentSample and currentSample[token],metadata,ownsUnit,plate)
                    if recycled and ownsUnit() then forgetPlate(token) end
                elseif available==nil then
                    sighting,memo=nil,nil
                end
            end
            if enabled and (sighting==nil or vacant) then
                retry.mark(token,rosterSource and party.slots[token])
            end
            units[#units+1]={vacant=vacant,token=token,sighting=sighting,evidence=evidence,memo=memo,plate=plate,roster=rosterSource}
        end
        if target then inspect("target",true) end
        if mouseover then inspect("mouseover",true) end
        local prefix,count,rosterSource
        if roster then prefix,count,rosterSource=reader.groupRoster() end
        local rosterUnits={}
        for i=1,count or 0 do
            local token=prefix..i
            rosterUnits[token]=i
            inspect(token,true,nil,rosterSource)
        end
        local tokens={}
        for token,plate in pairs(plates) do
            if plate.record or previous[token] then tokens[#tokens+1]=token end
        end
        for token in pairs(previous) do
            if token~="target" and token~="mouseover" and not plates[token] and not rosterUnits[token] then
                tokens[#tokens+1]=token
            end
        end
        table.sort(tokens)
        for _,token in ipairs(tokens) do
            local plate=plates[token]
            if reader.nameplateToken(token) then
                local prior=previous[token]
                local enabled=plate and (plate.record or prior and prior.guild and (guildLookup or metadata.guildUnavailable))
                inspect(token,enabled or false,plate)
            elseif prefix then inspect(token,false,nil,rosterSource)
            else inspect(token,nil,nil,token:sub(1,4)=="raid" and "Raid" or "Party") end
        end
        if not ownsScan() then
            if world and owner==revision then pending=true end
            return
        end
        local ids,guids,conflicts={},{},{}
        for _,unit in ipairs(units) do
            local sighting=unit.sighting
            if sighting then
                local byId,byGuid=ids[sighting.id],guids[sighting.guid]
                if byId and not same(byId,sighting) then conflicts[byId.id]=true; conflicts[sighting.id]=true end
                if byGuid and not same(byGuid,sighting) then conflicts[byGuid.id]=true; conflicts[sighting.id]=true end
                ids[sighting.id],guids[sighting.guid]=sighting,sighting
            end
        end
        local function needsTimestamp(sighting)
            local episode=episodes[sighting.id]
            return not episode or not episode.encounter or (episode.encounterAbsentSince
                and clock-episode.encounterAbsentSince>=limits.absenceGrace)
        end
        local recording=ledger.available()
        local observedAt
        for _,unit in ipairs(units) do
            local sighting=unit.sighting
            if sighting and not sighting.guild and not conflicts[sighting.id] and recording and needsTimestamp(sighting) then
                observedAt=ledger.now()
                break
            end
        end
        local zone, zoneRead
        for _,unit in ipairs(units) do
            local sighting=unit.sighting
            if sighting and conflicts[sighting.id] then unit.sighting=nil
            elseif sighting and ownsScan() then
                local needsTime=needsTimestamp(sighting)
                unit.place=not sighting.guild and recording and (needsTime and observedAt~=nil
                    or not needsTime and (clockAvailable or inUpdate))
                if unit.place and not zoneRead then
                    zoneRead=true
                    zone=A.text(read(GetRealZoneText))
                    if zone and not zone:find("%S") then zone=nil end
                end
                if unit.place and not zone and ownsScan() then
                    if unit.roster then unit.group=unit.roster=="Raid" and "Raid" or "Group"
                    else unit.group=readGroupContext(unit.token) end
                end
            end
        end
        local function verifyUnit(unit,sighting)
            if not ownsScan() or unit.plate and not ownsPlate(unit.token,unit.plate) then return false end
            if unit.roster then
                local livePrefix,liveCount=reader.groupRoster()
                if livePrefix~=prefix or liveCount<rosterUnits[unit.token] or not ownsScan() then return false end
            end
            local name,guid=A.playerAddIdentity(unit.token,store,region,ownsScan)
            return name==sighting.name and guid==sighting.guid and ownsScan()
        end
        for _,unit in ipairs(units) do
            if unit.sighting and (unit.place or unit.plate or unit.roster) and not verifyUnit(unit,unit.sighting) then
                unit.sighting=nil
            end
        end
        local currentRegion=read(GetCurrentRegion)
        if not world or owner~=revision then return end
        if store~=A.store or region~=A.region then pending=true; return end
        if currentRegion~=region then
            resetSightings()
            return
        end
        local resumed=suspended
        if resumed then suspended,resumeUntil=false,clock+limits.absenceGrace
        elseif not resumeUntil or clock>=resumeUntil then suspendedSightings,resumeUntil=nil,nil end
        local present, supported, uncertain, candidates={},{},{},{}
        local observations=metadata.observations
        for _,unit in ipairs(units) do
            local token,sighting,plate=unit.token,unit.sighting,unit.plate
            metadata.rosterSamples[token]=unit.roster
            if sighting==nil then
                local prior=previous[token]
                if prior then uncertain[prior.id]=prior end
                if unit.roster then metadata.samples[token]=false end
            else
                previous[token]=sighting or nil
                metadata.samples[token]=unit.memo
                metadata.plateSamples[token]=plate
            end
            local prior=previous[token]
            if prior then present[prior.id]=prior end
            if sighting then
                local candidate=supported[sighting.id]
                if not candidate then
                    candidate={sighting=sighting,units={}}
                    supported[sighting.id]=candidate
                    candidates[#candidates+1]=candidate
                end
                candidate.units[#candidate.units+1]=unit
                if token=="target" then candidate.target=true
                elseif token=="mouseover" then candidate.mouseover=true
                elseif plate then candidate.nameplate=true
                else candidate.roster=true end
                if unit.place then
                    candidate.place=true
                    if not candidate.group or unit.group=="Raid" then candidate.group=unit.group end
                end
                if unit.evidence then
                    observations[#observations+1]={id=sighting.id,evidence=unit.evidence,
                        owns=(plate or unit.roster) and function() return verifyUnit(unit,sighting) end or nil}
                    for _,field in ipairs({"class","faction"}) do
                        local value=unit.evidence[field]
                        if value then
                            if candidate[field]==nil then candidate[field]=value
                            elseif candidate[field]~=value then candidate[field]=false end
                        end
                    end
                end
            end
        end
        for _,observation in ipairs(observations) do
            local candidate=supported[observation.id]
            for _,field in ipairs({"class","faction"}) do
                if candidate[field]==false then observation.evidence[field]=nil end
            end
        end
        if #candidates>0 or #queue>0 then pruneCooldowns(clockAvailable) end
        local function currentlySupported(sighting)
            local candidate=supported[sighting.id]
            return candidate and same(sighting,candidate.sighting)
        end
        local function ownsCurrentSighting(sighting,needsCurrent)
            local candidate=supported[sighting.id]
            if not candidate or not same(candidate.sighting,sighting) then return false end
            for _,unit in ipairs(candidate.units) do
                if (not needsCurrent or unit.plate or unit.roster) and verifyUnit(unit,sighting) then return true end
            end
            return false
        end
        -- Unsettled guild membership cannot disprove a Guild banner that is already shown.
        if visible and not (visible.guild and metadata.guildUnavailable) then
            local display=visible
            local saved=savedSighting(store,region,display.name,display.guid,guildLookup)
            if ownsScan() and visible==display
                and (not same(display,saved) or display.reasons~=saved.reasons
                    or same(display,uncertain[display.id]) and not currentlySupported(display)) then hide() end
        end
        if not world or owner~=revision then return end
        if store~=A.store or region~=A.region then pending=true; return end
        for i=#queue,1,-1 do
            local entry=queue[i]
            local sighting=entry.sighting
            if not currentlySupported(sighting)
                and (entry.needsCurrent or same(sighting,uncertain[sighting.id])) then discard(i) end
        end
        expireEpisodes()
        for _,episode in pairs(episodes) do
            local sighting=episode.sighting
            if episode.encounter then
                if currentlySupported(sighting) then episode.encounterAbsentSince=nil
                else episode.encounterAbsentSince=episode.encounterAbsentSince or clock end
            end
            if same(sighting,present[sighting.id]) then episode.absentSince=nil
            else episode.absentSince=episode.absentSince or clock end
        end
        for _,candidate in ipairs(candidates) do
            local sighting=candidate.sighting
            local episode=episodes[sighting.id]
            if not episode and (not resume or resumed) then
                -- A sighting carried out of an instance or begun during cooldown
                -- stays quiet until all of its sources clear.
                local carried=same(sighting,suspendedSightings and suspendedSightings[sighting.id])
                episode={sighting=sighting,handled=carried or onCooldown(region,sighting.name)}
                episodes[sighting.id]=episode
            end
            if candidate.roster and episode and same(sighting,episode.sighting) then
                party.claim(episode,sighting.guid,clock,onCooldown(region,sighting.name))
            end
            if episode and same(sighting,episode.sighting) then
                local needsCurrent=not (candidate.target or candidate.mouseover)
                if episode.queued and not needsCurrent then episode.queued.needsCurrent=false end
                if candidate.place then
                    if not episode.encounter then
                        local id=ledger.start(sighting,region,observedAt)
                        if id then episode.encounter={id=id} end
                        episode.startedClock=clock
                    end
                    local encounter=episode.encounter
                    if encounter then
                        encounter.key=ledger.observe(encounter.id,candidate.target,candidate.mouseover,
                            clock-episode.startedClock,zone,candidate.group,candidate.nameplate,candidate.roster) or encounter.key
                        -- Keep this physical episode's ID through grace expiry.
                        local entry=episode.queued
                        if entry and entry.episode==episode and not entry.encounter then entry.encounter=encounter end
                    end
                end
                if sighting.reasons~="" and not episode.handled and not episode.queued
                    and (episode.blocks or 0)<limits.blockedLimit then
                    local duplicate
                    for _,entry in ipairs(queue) do
                        if entry.sighting.id==sighting.id then duplicate=entry; break end
                    end
                    if not duplicate and #queue<limits.pendingLimit then
                        local entry={sighting=sighting,episode=episode,region=region,at=clock,
                            encounter=episode.encounter,needsCurrent=needsCurrent}
                        queue[#queue+1]=entry
                        episode.queued=entry
                    elseif duplicate then
                        episode.queued=duplicate
                    end
                end
            end
        end
        if not metadata.guildUnavailable then party.dismiss(units) end
        -- A new alert can join a brief overlap. A transient queued alert still
        -- gets its usual standalone display if either player is no longer observed.
        local display=visible
        local staged=display and display.stagedGroup
        if display and #queue>0 and (staged and staged==groupToPaint or not staged and clock-display.openedAt<=limits.groupWindow)
            and display.episode
            and episodes[display.id]==display.episode and currentlySupported(display) then
            local count, batch=display.count or 0,{}
            local needsPaintCheck=display.guild or supported[display.id].roster
            local function ownsGroup()
                if B.testShown() or not ownsScan() or visible~=display then return false end
                for _,item in ipairs(batch) do
                    if queue[item.index]~=item.entry then return false end
                end
                return true
            end
            for index,entry in ipairs(queue) do
                if count+#batch>=limits.pendingLimit then break end
                local sighting=entry.sighting
                local age=clock-entry.at
                if (not staged or staged[entry]) and entry.region==region and age>=limits.pollInterval and age<=limits.pendingLifetime
                    and sighting.id~=display.id and not display.batched[sighting.id] and episodes[sighting.id]==entry.episode
                    and (entry.episode.join or not onCooldown(region,sighting.name)) and currentlySupported(sighting) then
                    local saved=savedSighting(store,region,sighting.name,sighting.guid,guildLookup)
                    if same(saved,sighting) and saved.reasons==sighting.reasons and ownsCurrentSighting(saved) then
                        batch[#batch+1]={index=index,entry=entry}
                        needsPaintCheck=needsPaintCheck or sighting.guild or supported[sighting.id].roster
                    end
                    if not ownsScan() then return end
                end
            end
            if #batch>0 and ownsCurrentSighting(display) and ownsGroup() then
                if not allowsLiveBanner() then clearPlates(); suspend(); return end
                if needsPaintCheck and not staged and ownsGroup() then
                    -- Roster membership and guild access can change before the count is painted.
                    local group={}
                    for _,item in ipairs(batch) do group[item.entry]=true end
                    display.stagedGroup=group
                    return
                end
                if read(GetCurrentRegion)==region and display.appearance() and ownsGroup()
                    and B.addLive(count+#batch,ownsGroup) then
                    if staged then
                        local function ownsPaint()
                            return display.appearance() and ownsGroup()
                        end
                        if not B.advanceLive(paintElapsed,false,ownsPaint) or not ownsPaint() then
                            if visible==display then
                                hide()
                                if world and #queue>0 then pending=true end
                            end
                            return
                        end
                    end
                    display.stagedGroup=nil
                    for i=#batch,1,-1 do
                        local item=batch[i]
                        -- A counted player who joins later gets a banner of their own.
                        display.batched[item.entry.sighting.id]=true
                        startCooldown(region,item.entry.sighting.name,bannerCooldown)
                        local joined=supported[item.entry.sighting.id]
                        party.shown(item.entry.episode,clock,joined and joined.roster)
                        discard(item.index,true)
                    end
                    display.count,shownAt=count+#batch,clock
                    return
                end
            end
            if not ownsScan() then return end
        end
        if staged and staged==groupToPaint and visible==display then display.stagedGroup=nil end
        while #queue>0 and not visible and (clockAvailable or inUpdate) do
            local entry=queue[1]
            local expired=clock-entry.at>limits.pendingLifetime
            local saved=not expired and entry.region==region
                and savedSighting(store,region,entry.sighting.name,entry.sighting.guid,guildLookup)
            local stillObserved=not entry.needsCurrent or ownsCurrentSighting(entry.sighting,true)
            if not world or owner~=revision then return end
            if store~=A.store or region~=A.region then pending=true; return end
            if not stillObserved or not same(entry.sighting,saved) or entry.sighting.reasons~=saved.reasons then
                discard(1)
                if expired then pending=true end
            elseif not entry.episode.join and onCooldown(region,saved.name) then
                discard(1,true)
            elseif not allowsLiveBanner() then
                clearPlates()
                suspend()
                return
            elseif world and owner==revision and queue[1]==entry then
                if B.testShown() then break end
                local parentVisible=read(UIParent.IsVisible,UIParent)==true
                if not ownsScan() or queue[1]~=entry then
                    if world and queue[1]==entry then pending=true end
                    return
                end
                if not parentVisible then deferHidden(); return end
                local encounter=entry.encounter
                local ledgerRevision=ledger.revision()
                if encounter and not ledger.matchesGroup(region,nil,encounter.id,encounter.key) then encounter=nil end
                local ownsAppearance=B.showLive(saved.name,saved.reasons,encounter)
                if not ownsAppearance then break end
                if not allowsLiveBanner() then clearPlates(); suspend(); return end
                advance()
                local displayRegion=read(GetCurrentRegion)
                local testShown=B.testShown()
                local appeared=ownsAppearance()
                if entry.needsCurrent and not ownsCurrentSighting(entry.sighting,true) then
                    if ownsScan() and queue[1]==entry then discard(1) end
                    hide()
                    return
                end
                if not ownsScan() or queue[1]~=entry or testShown or displayRegion~=region then
                    hide()
                    if world and queue[1]==entry then pending=true end
                    return
                end
                if clock-entry.at>limits.pendingLifetime then
                    discard(1,true)
                    hide()
                    if world and #queue>0 then pending=true end
                    return
                end
                if not appeared then
                    entry.episode.blocks=(entry.episode.blocks or 0)+1
                    retry.blocked=entry.episode.blocks<limits.blockedLimit
                    if not retry.blocked then discard(1) end
                    hide()
                    return
                end
                startCooldown(region,saved.name,bannerCooldown)
                local candidate=supported[entry.sighting.id]
                party.shown(entry.episode,clock,candidate and candidate.roster)
                entry.episode.blocks=nil
                discard(1,true)
                saved.encounter,saved.region,saved.ledgerRevision=encounter,region,ledgerRevision
                saved.appearance,saved.openedAt,saved.batched=ownsAppearance,clock,{}
                if currentlySupported(saved) then saved.episode=entry.episode end
                visible,shownAt=saved,clock
                A.alertSound.playBanner(function()
                    if not ownsScan() or visible~=saved or not allowsLiveBanner() or read(GetCurrentRegion)~=region
                        or B.testShown() or not ownsAppearance()
                        or entry.needsCurrent and not ownsCurrentSighting(entry.sighting,true) then return false end
                    return ownsScan() and visible==saved
                end)
                return
            else
                break
            end
        end
    end
    local function sample(resume, rosterChanged, groupToPaint, paintElapsed)
        resumeTest=false
        revision=revision+1
        if rosterChanged then party.due=true end
        if scanning then
            if rosterChanged then rosterRetryUntil=clock+rosterSettleTime end
            pending=true
            refreshUpdates()
            return
        end
        local retried=metadataRetry
        scanning,pending,metadataRetry=true,false,false
        retry.pass,retry.blocked=retry.pass+1,false
        local owner,store,region=revision,A.store,A.region
        local guildLookup,ownsGuild,guildUnavailable
        if world then guildLookup,ownsGuild,guildUnavailable=G.bannerLookup(region) end
        retry.watching=not not (world and store and (hasBlacklist() or guildLookup or guildUnavailable))
        clockAvailable=(next(episodes) or (store and (hasBlacklist() or guildLookup))) and advance()
        if rosterChanged and owner==revision then rosterRetryUntil=clock+rosterSettleTime end
        local ledgerRevision=ledger.revision()
        local metadata={observations={},samples={},plateSamples={},rosterSamples={},requested=requested,retried=retried,
            guildLookup=guildLookup,ownsGuild=ownsGuild,guildUnavailable=guildUnavailable,previous=previous}
        requested={}
        scan(owner,resume,metadata,groupToPaint,paintElapsed)
        -- A scan that returned before reading units leaves nothing to retry; an interrupted one sets pending and keeps its waits.
        if not pending then retry.sweep() end
        local function owns()
            return world and owner==revision and A.store==store and A.region==region
        end
        local previousSamples=sampled
        local settled
        if owns() and next(metadata.samples) then
            settled=A.saveBlacklistObservations(store,region,metadata.observations,owns)
        end
        -- An interrupted sample remains eligible independently of encounter and banner state.
        -- A completed publish may dispatch an event while rebuilding the view.
        if settled and sampled==previousSamples and world and A.store==settled and A.region==region then
            if sampledOwner.store~=store or sampled.region~=region then sampled={} end
            sampledOwner.store,sampled.region=settled,region
            for token,memo in pairs(metadata.samples) do
                if token=="target" or token=="mouseover" or metadata.rosterSamples[token]
                    or plates[token] and plates[token]==metadata.plateSamples[token] then
                    sampled[token]=settleSample(settled,memo)
                end
            end
            for _,memo in pairs(sampled) do
                if type(memo)=="table" and memo.retry then pending,metadataRetry=true,"incomplete"; break end
            end
        end
        refreshNavigation()
        scanning=false
        if not settled and #metadata.observations>0 and world and not pending and not retried then
            pending,metadataRetry=true,"cancelled"
        end
        if #queue>0 and not visible and not clockAvailable and not B.testShown() then pending=true end
        nextPoll=clock+limits.pollInterval
        refreshUpdates()
        if settled and settled~=store then P.Shell.RefreshBlacklistMetadata() end
        if ledger.revision()~=ledgerRevision then P.Shell.RefreshBlacklistLastSeen() end
    end
    update=function(_,elapsed)
        if not world or not updating then return end
        advance(elapsed)
        inUpdate=true
        for i=#queue,1,-1 do
            local entry=queue[i]
            if clock-entry.at>limits.pendingLifetime then discard(i) end
        end
        local expired=visible and B.alphaAt(clock-shownAt)==0
        if expired then hide() end
        local display=visible
        local count=display and display.count
        local groupToPaint=display and display.stagedGroup
        -- WoW may clear mouseover without delivering a second unit event.
        local rosterDue=rosterRetryUntil and (clock>=nextPoll or clock>=rosterRetryUntil)
        if rosterRetryUntil and clock>=rosterRetryUntil then rosterRetryUntil=nil end
        local retryDue=retry.at and clock>=retry.at
        if retryDue then retry.at=nil end
        -- A plate read early does not spend a wait, and can still join the open banner.
        if retryDue or visible and clock-visible.openedAt<=limits.groupWindow and clock>=nextPoll then retryPlates() end
        if rosterDue or retryDue then party.due=true end
        if pending or expired or groupToPaint or rosterDue or retryDue
            or ((retry.blocked or visible or previous.mouseover or trackingPlate()) and clock>=nextPoll) then
            sample(resumeTest,nil,groupToPaint,elapsed)
        end
        expireEpisodes()
        refreshNavigation()
        if visible then
            local alpha=B.alphaAt(clock-shownAt)
            if alpha<1 then B.fade(alpha)
            elseif visible==display and (not groupToPaint or visible.count==count) then
                B.advanceLive(elapsed,visible.count~=count)
            end
        end
        inUpdate=false
        refreshUpdates()
    end
    function B.sightingsTestChanged()
        if B.testShown() then hide()
        elseif world then
            -- Advance the observer clock before starting a live display: the
            -- test frame can finish earlier in the same frame after a hitch.
            local again=#queue>0
            if not again then
                for _,episode in pairs(episodes) do
                    if not episode.handled then again=true; break end
                end
            end
            if again then pending,resumeTest=true,true end
        end
        refreshUpdates()
    end
    function B.sightingsBookChanged()
        if not world then return end
        local changed
        local guildLookup=G.bannerLookup(A.region)
        for _,plate in pairs(plates) do
            local record=plateRecord(A.store,A.region,plate,guildLookup)
            if plate.record~=record then plate.record,changed=record,true end
        end
        if changed or not retry.watching and next(retry.plates) then sample(); return end
        for _,episode in pairs(episodes) do
            local sighting=episode.sighting
            local saved=A.store and savedSighting(A.store,A.region,sighting.name,sighting.guid,guildLookup)
            if not same(sighting,saved) then
                sample()
                return
            end
        end
    end
    function B.sightingsGuildChanged()
        if not world then return end
        guildDirty=true
        sample()
    end
    function B.sightingsNameplatesChanged(enabled)
        enabled=enabled==true
        if platesEnabled==enabled then return end
        platesEnabled=enabled
        if enabled then
            if seedPlates() or next(retry.plates) then sample() end
        else
            local hadPlates=next(plates)
            clearPlates()
            if world and hadPlates then sample() end
        end
    end
    function B.sightingsNameplateEvent(event,token)
        if not world or not platesEnabled or not reader.nameplateToken(token)
            or event~="NAME_PLATE_UNIT_ADDED" and event~="NAME_PLATE_UNIT_REMOVED" then return end
        local prior=previous[token]
        local old=plates[token]
        plateRevision=plateRevision+1
        forgetPlate(token)
        retry.units[token]=nil
        local matched=event=="NAME_PLATE_UNIT_ADDED" and rememberPlate(token,nil,G.bannerLookup(A.region))
        if matched or prior or old and old.record or retry.plates[token] and not retry.watching then sample()
        elseif retry.plates[token] then refreshUpdates() end
    end
    observer:SetScript("OnEvent",function(_,event)
        if event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_LOGOUT" then
            local seen,handled={},{}
            carriedRegion=nil
            if event=="PLAYER_LEAVING_WORLD" then
                rememberSightings()
                seen,handled=carryHandledRoster()
                if next(seen) then carriedRegion=A.region end
            end
            world,pending,revision=false,false,revision+1
            local oldEpisodes=episodes
            party.restore(oldEpisodes)
            retry.units={}
            episodes,previous,queue=handled,seen,{}
            clearPlates()
            sampled,requested,metadataRetry={},{},false
            sampledOwner.store=nil
            resumeTest,rosterRetryUntil=false,nil
            hide()
            if next(oldEpisodes) then advance() end
            for _,episode in pairs(oldEpisodes) do stopEncounter(episode,clock) end
            refreshUpdates()
        elseif event=="PLAYER_ENTERING_WORLD" then
            world=true
            seedPlates()
            sample(nil,roster)
        elseif world then
            for _,episode in pairs(episodes) do
                if episode.blocks then episode.blocks=math.min(episode.blocks,limits.blockedLimit-1) end
            end
            -- Another unit took the token, so its waits start again.
            if event=="PLAYER_TARGET_CHANGED" then requested.target,retry.units.target=true,nil end
            if event=="UPDATE_MOUSEOVER_UNIT" then requested.mouseover,retry.units.mouseover=true,nil end
            if event=="ZONE_CHANGED_NEW_AREA" then seedPlates() end
            sample(nil,event=="GROUP_ROSTER_UPDATE")
        end
    end)
end
