-- R49 candidate against the real product TOC with a simulated chat filter registry.
local root=arg[1] or "."
local H=dofile(root.."/tests/addon/harness.lua")
local WHISPER="CHAT_MSG_WHISPER"
local SAY,YELL,CHANNEL,GUILD="CHAT_MSG_SAY","CHAT_MSG_YELL","CHAT_MSG_CHANNEL","CHAT_MSG_GUILD"
local groupEvents={"CHAT_MSG_PARTY","CHAT_MSG_PARTY_LEADER","CHAT_MSG_RAID","CHAT_MSG_RAID_LEADER"}
local events={[WHISPER]=true,[SAY]=true,[YELL]=true,[CHANNEL]=true,[GUILD]=true}
for _,event in ipairs(groupEvents) do events[event]=true end
local GENERAL,TRADE,TRADE_SLOT=59,61,7
local primaryName, adjacentName, inheritedName="Élan North","Élan South","Orel West"
local primaryGuid, adjacentGuid, inheritedGuid="Player-1234-000000AB","Player-1234-000000AC","Player-1234-000000AD"
local selfGuid="Player-1234-000000AA"
local function incoming(callback,name,guid,event,body,zoneID,slot,untrustedBaseName)
    local payload={[1]=body,[2]=name,[7]=zoneID,[8]=slot,[9]=untrustedBaseName,[12]=guid}
    return callback({},event or WHISPER,table.unpack(payload,1,12))
end

local function fresh(preferences,db,options)
    options=options or {}
    local p,s,e=H.fresh(root,preferences,{484,800},{region=3,time=110,db=db})
    local callbacks={}
    local seen={}
    local A=p.manual
    e.WhowhoEncounterDB=options.history
    local locale=options.locale or (options.french and "frFR" or "enUS")
    local tradeName=locale=="frFR" and "Commerce" or "Trade"
    e.GetLocale=function() return locale end
    e.UnitGUID=function(token) assert(token=="player"); return selfGuid end
    e.Enum={PermanentChatChannelType={Zone=1,Custom=3}}
    e.C_ChatInfo={
        GetGeneralChannelID=function() return GENERAL end,
        GetChannelInfoFromIdentifier=function(identifier)
            assert(identifier==tradeName)
            return {name=tradeName,zoneChannelID=TRADE,localID=TRADE_SLOT,channelType=e.Enum.PermanentChatChannelType.Zone}
        end,
    }
    if options.missingChannelAPI then e.C_ChatInfo.GetChannelInfoFromIdentifier=nil end
    if options.registry~=false then
        e.ChatFrameUtil.AddMessageEventFilter=function(event,callback)
            assert(events[event] and not seen[event] and A.store and p.initialized and not A.chatMute.available())
            assert(not callbacks[1] or callback==callbacks[1])
            seen[event]=true
            callbacks[#callbacks+1]=callback
            local result,replacement=incoming(callback,primaryName,primaryGuid,event)
            assert(not result and replacement==nil)
            if options.failAdd or options.failEvent==event then error("registration failed") end
            if options.rejectAdd then return false end
            if options.secretResult then return s.secret end
        end
    end
    if options.protectNamespace then e.ChatFrameUtil=s.secret end
    if options.protectAdd then e.ChatFrameUtil.AddMessageEventFilter=s.secret end
    if options.invalidBook then e.WhowhoAddressBookDB={schemaVersion=99} end
    s:event("ADDON_LOADED","AnotherAddon")
    assert(#callbacks==0 and not p.initialized)
    s:event("ADDON_LOADED","WhoWho")
    assert(p.initialized)
    local expected=(options.registry~=false and not options.invalidBook
        and not options.protectNamespace and not options.protectAdd) and 9 or 0
    assert(#callbacks==expected)
    if expected>0 then for event in pairs(events) do assert(seen[event]) end end
    s:event("ADDON_LOADED","WhoWho")
    p.Init(); A.chatMute.install()
    assert(#callbacks==expected)
    p.Toggle()
    return p,s,e,callbacks[1]
end

local function add(A,name,guid)
    local record=assert(A.store.add({region=3,fullName=name,identityState="resolved",membership="blacklist",
        guid=guid,reasonIds={"other"},note="retain note"},100))
    A.refresh()
    return record
end
local function rowFor(S,name)
    S.searchBox:SetText(name)
    assert(S.rows[1].record and S.rows[1].record.fullName==name)
    return S.rows[1]
end

local p,s,e,callback=fresh(nil,nil,{french=true})
local A,S=p.manual,p.Shell
assert(A.chatMute.available() and p.db.muteBlacklistWhispers==false
    and p.db.muteBlacklistPartyRaid==false and p.db.muteBlacklistCityTrade==false and p.db.muteBlacklistGuild==false)
local primary=add(A,primaryName,primaryGuid)
local adjacent=add(A,adjacentName,adjacentGuid)
local legacy=A.store.export()
legacy.regions[3][primary.id].reasonIds=nil
local q,sim,env,filter=fresh(e.WhowhoPreviewDB,legacy,{french=true})
local B,V=q.manual,q.Shell
V.SetSection("blacklist")
local row=rowFor(V,primaryName)
local button=row.inviteButton
assert(button:IsEnabled() and not row.muteSlash:IsShown())
sim:fire(button,"OnEnter")
assert(env.GameTooltip:GetText()=="Masquer les messages de "..primaryName)
sim:fire(button,"OnLeave")
assert(not incoming(filter,primaryName,primaryGuid))
button:Click("RightButton")
assert(B.store.get(primary.id).whisperMuted==nil)
button:Click()
assert(B.store.get(primary.id).whisperMuted==true and row.muteSlash:IsShown())
local slash=row.muteSlash
assert(slash.kind=="Line" and slash.layer=="OVERLAY" and slash.thickness==2)
assert(slash.startPoint[2]==button and slash.startPoint[3]<0 and slash.startPoint[4]<0)
assert(slash.endPoint[2]==button and slash.endPoint[3]>0 and slash.endPoint[4]>0)
for _,scale in ipairs({0.5,1,select(2,q.ScaleLimits())}) do
    q.SetScale(scale)
    assert(row.record.id==primary.id and row.muteIcon:IsVisible() and slash:IsVisible())
    local _,actionX=button:GetPoint()
    local _,copyX=row.copyButton:GetPoint()
    assert(actionX+button:GetWidth()<=copyX and slash.endPoint[3]<button:GetWidth()/2)
end
q.SetScale(1)
assert(B.store.get(primary.id).reasonIds==nil and B.store.get(primary.id).note=="retain note")
sim:fire(button,"OnEnter")
assert(env.GameTooltip:GetText()=="Messages masqués · Réafficher ceux de "..primaryName)
sim:fire(button,"OnLeave")

local check=env.issecretvalue
local unusedBody={}
env.issecretvalue=function(value)
    assert(not rawequal(value,unusedBody),"filter inspected the message body")
    return check(value)
end
local discarded,replacement=incoming(filter,primaryName,primaryGuid,nil,unusedBody)
assert(discarded and replacement==nil)
assert(incoming(filter,primaryName,primaryGuid,nil,unusedBody),"one whisper may surface in two chat frames")
for _,case in ipairs({
    {"Élan",primaryGuid},
    {"élan North",primaryGuid},
    {"Elan North",primaryGuid},
    {"Élan  North",primaryGuid},
    {"Élan North-Realm",primaryGuid},
    {adjacentName,primaryGuid},
    {primaryName,adjacentGuid},
    {primaryName,""},
    {primaryName,"Creature-0-0-0-0-1-1"},
    {primaryName,"Player-"},
    {primaryName,sim.secret},
    {sim.secret,primaryGuid},
    {primaryName,primaryGuid,"CHAT_MSG_WHISPER_INFORM"},
    {primaryName,primaryGuid,"CHAT_MSG_BN_WHISPER"},
    {primaryName,primaryGuid,"CHAT_MSG_RAID_WARNING"},
    {primaryName,primaryGuid,"CHAT_MSG_INSTANCE_CHAT"},
    {primaryName,primaryGuid,"CHAT_MSG_INSTANCE_CHAT_LEADER"},
    {primaryName,primaryGuid,"CHAT_MSG_GUILD"},
    {primaryName,primaryGuid,"CHAT_MSG_COMMUNITIES_CHANNEL"},
    {primaryName,primaryGuid,"CHAT_MSG_CHANNEL_NOTICE"},
    {primaryName,primaryGuid,"CHAT_MSG_CHANNEL_JOIN"},
}) do
    local result,rewritten=incoming(filter,case[1],case[2],case[3],unusedBody)
    assert(not result and rewritten==nil)
end
assert(incoming(filter,primaryName,primaryGuid,SAY,unusedBody))
assert(incoming(filter,primaryName,primaryGuid,YELL,unusedBody))
for _,event in ipairs(groupEvents) do assert(not incoming(filter,primaryName,primaryGuid,event,unusedBody)) end
assert(not incoming(filter,primaryName,primaryGuid,CHANNEL,unusedBody,GENERAL,3))
assert(not incoming(filter,nil,primaryGuid) and not incoming(filter,primaryName,nil))
env.GetCurrentRegion=function() return 4 end
assert(not incoming(filter,primaryName,primaryGuid))
env.GetCurrentRegion=function() return sim.secret end
assert(not incoming(filter,primaryName,primaryGuid))
env.GetCurrentRegion=function() error("region unavailable") end
assert(not incoming(filter,primaryName,primaryGuid))
env.GetCurrentRegion=function() return 3 end

-- The row must keep its recipient and action through a press, even after cycling
-- the same frame back to the first record or rebinding during guarded native reads.
sim:fire(button,"OnMouseDown","LeftButton")
rowFor(V,adjacentName)
button:Click()
assert(B.store.get(adjacent.id).whisperMuted==nil and B.store.get(primary.id).whisperMuted)
rowFor(V,primaryName)
sim:fire(button,"OnMouseDown","LeftButton")
rowFor(V,adjacentName)
rowFor(V,primaryName)
button:Click()
assert(B.store.get(primary.id).whisperMuted)
local clock=env.GetServerTime
env.GetServerTime=function()
    env.GetServerTime=clock
    rowFor(V,adjacentName)
    rowFor(V,primaryName)
    return clock()
end
button:Click()
assert(B.store.get(primary.id).whisperMuted)
local isVisible=button.IsVisible
button.IsVisible=function(self)
    button.IsVisible=isVisible
    assert(B.save(nil,"blacklist","Concurrent Save","",nil,{"other"}))
    return isVisible(self)
end
button:Click()
assert(B.store.find(3,"Concurrent Save") and B.store.get(primary.id).whisperMuted)
local reachabilityReads=0
button.IsVisible=function(self)
    reachabilityReads=reachabilityReads+1
    if reachabilityReads==2 then
        button.IsVisible=isVisible
        assert(B.save(nil,"blacklist","Final Save","",nil,{"other"}))
    end
    return isVisible(self)
end
button:Click()
assert(reachabilityReads==2 and B.store.find(3,"Final Save") and B.store.get(primary.id).whisperMuted)

local readRegion=env.GetCurrentRegion
env.GetCurrentRegion=function()
    env.GetCurrentRegion=readRegion
    row.deleteButton:Click()
    assert(V.deleteDialog:IsVisible() and V.scrim:IsShown())
    return readRegion()
end
button:Click()
assert(V.deleteDialog:IsVisible() and B.store.get(primary.id).whisperMuted)
V.deleteCancel:Click()

-- The Settings switch controls existing and new entries without touching overrides.
V.SetSection("settings")
V.settingsTabs.general:Click()
local default=V.muteBlacklistWhispers
local partyRaid,cityTrade,guild=V.muteBlacklistPartyRaid,V.muteBlacklistCityTrade,V.muteBlacklistGuild
local function channel(name,guid,zoneID,slot,baseName)
    return incoming(filter,name,guid,CHANNEL,unusedBody,zoneID,slot,baseName)
end
local function visibleText(parent,text)
    for _,child in ipairs(parent.children) do
        if child.kind=="FontString" and child:IsVisible() and child:GetText()==text then return child end
    end
    error("missing visible text: "..text)
end
local function top(widget)
    local _,_,y=widget:GetPoint()
    return -y
end
local function checkMuteSettings(addon,simulator,client,muteTitle,descriptions,tip)
    local shell=addon.Shell
    shell.SetSection("settings")
    shell.settingsTabs.general:Click()
    local controls={shell.muteBlacklistWhispers,shell.muteBlacklistPartyRaid,shell.muteBlacklistCityTrade,shell.muteBlacklistGuild}
    local page=controls[1]:GetParent()
    local scroll=page:GetParent()
    local title=visibleText(page,muteTitle)
    local bookTitle=visibleText(page,addon.L("Address book"))
    local guildContext=addon.GuildBlacklist.context
    local viewportWidth,viewportHeight=client.UIParent:GetWidth(),client.UIParent:GetHeight()
    for _,noGuild in ipairs({true,false}) do
        addon.GuildBlacklist.context=function() return nil,noGuild and "no_guild" or "unavailable" end
        shell.settings:RefreshGuildAvailability()
        for _,layout in ipairs({{484,0.5},{484,0.7},{484,1},{460,1}}) do
            local width,scale=table.unpack(layout)
            client.UIParent:SetSize(width,900)
            addon.SetScale(scale)
            scroll:SetVerticalScroll(0)
            local delete,guildDefault=shell.skipDeleteConfirmation,shell.guildBlacklistDefault
            local scaleBottom=top(shell.scaleSlider)+shell.scaleSlider:GetHeight()
            local roomy=scale==0.5
            assert(top(bookTitle)-scaleBottom>=(roomy and 14 or 6))
            assert(top(delete)>=top(bookTitle)+bookTitle:GetStringHeight())
            local addressBottom
            if noGuild then
                local notice=visibleText(page,addon.L("You’re not in a guild. Guild sync is unavailable."))
                assert(not guildDefault:IsShown() and top(notice)>=top(delete)+delete:GetHeight())
                addressBottom=top(notice)+notice:GetStringHeight()
            else
                assert(guildDefault:IsVisible() and top(guildDefault)>top(delete)+delete:GetHeight())
                addressBottom=top(guildDefault)+guildDefault:GetHeight()
            end
            assert(top(title)-addressBottom>=(roomy and 16 or 10))
            local bottom=top(title)+title:GetStringHeight()
            for i,setting in ipairs(controls) do
                assert(setting:IsVisible() and setting:IsEnabled() and not setting:GetChecked())
                assert(top(setting)>=bottom and top(setting)+setting:GetHeight()<=page:GetHeight()-8,
                    string.format("%s setting %d at scale %.2f starts at %d, previous ends at %d, content ends at %.0f",
                        muteTitle,i,scale,top(setting),bottom,page:GetHeight()))
                assert(setting.state:IsVisible()==(scale<=0.7))
                if roomy then
                    assert(setting:GetHeight()>=50 and (i==1 or top(setting)-bottom>=4))
                end
                bottom=top(setting)+setting:GetHeight()
                local heading,help=visibleText(setting,descriptions[i][1]),visibleText(setting,descriptions[i][2])
                local helpBottom=top(help)+help:GetStringHeight()
                assert(help.SetWordWrapArgs[1] and help:GetWidth()<setting:GetWidth())
                assert(top(heading)+heading:GetStringHeight()<=top(help) and helpBottom<setting:GetHeight())
                assert(math.abs(top(heading)-(setting:GetHeight()-helpBottom))<=1)
            end
            if bottom>scroll:GetHeight() then
                assert(scroll.EnableMouseWheelArgs[1])
                simulator:fire(scroll,"OnMouseWheel",-100)
                assert(bottom<=scroll:GetHeight()+scroll:GetVerticalScroll())
            end
        end
    end
    addon.GuildBlacklist.context=guildContext
    client.UIParent:SetSize(viewportWidth,viewportHeight)
    addon.SetScale(1)
    assert(not controls[4].state:IsShown())
    simulator:fire(controls[4],"OnEnter")
    assert(client.GameTooltip:GetOwner()==controls[4] and client.GameTooltip:IsShown() and client.GameTooltip:GetText()==tip)
    simulator:fire(controls[4],"OnLeave")
    assert(not client.GameTooltip:IsShown())
    controls[4]:Click()
    assert(controls[4]:GetChecked())
    addon.SetScale(0.5)
    assert(controls[4]:GetChecked() and controls[4].state:IsVisible() and controls[4].state:GetText()==addon.L("On"))
    controls[4]:Click()
    assert(not controls[4]:GetChecked() and controls[4].state:IsVisible() and controls[4].state:GetText()==addon.L("Off"))
end
checkMuteSettings(q,sim,env,"Masquage des messages",{
    {"Masquer par défaut les messages de la liste noire","Chuchoter, Dire et Crier. Priorité aux choix individuels."},
    {"Inclure Groupe et Raid","Inclut les messages des chefs."},
    {"Inclure Général et Commerce","Canaux intégrés, pour les joueurs masqués."},
    {"Inclure le canal Guilde","Pour les joueurs masqués."},
},"Si vous vous sentez à l’aise, parlez-en d’abord avec la personne ou un responsable de guilde.")
local english,englishSim,englishEnv=fresh()
checkMuteSettings(english,englishSim,englishEnv,"Mute Chat",{
    {"Mute Blacklist chat by default","Whispers, Say and Yell. Individual choices take priority."},
    {"Include Party and Raid","Includes messages from group leaders."},
    {"Include General and Trade","Built-in channels only, for muted players."},
    {"Include Guild chat","Applies to muted players."},
},"If you feel comfortable, consider talking with the player or a guild officer first.")
partyRaid:Click()
assert(q.db.muteBlacklistPartyRaid and not q.db.muteBlacklistCityTrade)
for _,event in ipairs(groupEvents) do
    assert(incoming(filter,primaryName,primaryGuid,event,unusedBody))
    assert(not incoming(filter,adjacentName,adjacentGuid,event,unusedBody))
end
assert(not channel(primaryName,primaryGuid,GENERAL,3))
cityTrade:Click()
partyRaid:Click()
assert(not q.db.muteBlacklistPartyRaid and q.db.muteBlacklistCityTrade)
for _,event in ipairs(groupEvents) do assert(not incoming(filter,primaryName,primaryGuid,event,unusedBody)) end
assert(channel(primaryName,primaryGuid,GENERAL,27,"Général - Ironforge"))
assert(channel(primaryName,primaryGuid,TRADE,TRADE_SLOT,"Commerce"))
assert(not channel(adjacentName,adjacentGuid,GENERAL,3))
assert(not channel(primaryName,primaryGuid,0,TRADE_SLOT,"Commerce"),"custom channel in the slot stays visible")
assert(not channel(primaryName,primaryGuid,0,GENERAL,"Général"),"General slot alone does not classify")
assert(not channel(primaryName,primaryGuid,TRADE,TRADE_SLOT+1,"Commerce"),"stale Trade slot stays visible")
assert(not channel(primaryName,primaryGuid,TRADE,sim.secret,"Commerce"))
assert(not channel(primaryName,primaryGuid,sim.secret,TRADE_SLOT,"Commerce"))
assert(not channel(primaryName,primaryGuid,tostring(TRADE),TRADE_SLOT,"Commerce"))
assert(not channel(primaryName,primaryGuid,nil,TRADE_SLOT,"Commerce"))
for _,otherID in ipairs({22,26,42}) do
    assert(not channel(primaryName,primaryGuid,otherID,TRADE_SLOT,"Commerce"),"another native zone channel stays visible")
end
local nativeTrade=env.C_ChatInfo.GetChannelInfoFromIdentifier
env.C_ChatInfo.GetChannelInfoFromIdentifier=function(identifier)
    local info=nativeTrade(identifier)
    info.name,info.shortcut="Commerce - Ville","Commerce"
    return info
end
assert(channel(primaryName,primaryGuid,TRADE,TRADE_SLOT,"Commerce"))
for _,invalidInfo in ipairs({
    sim.secret,
    {name="Commerce",zoneChannelID=TRADE,localID=TRADE_SLOT,channelType=3},
    {name="Services",shortcut="Services",zoneChannelID=TRADE,localID=TRADE_SLOT,channelType=1},
    {name="Commerce",zoneChannelID=sim.secret,localID=TRADE_SLOT,channelType=1},
}) do
    env.C_ChatInfo.GetChannelInfoFromIdentifier=function() return invalidInfo end
    assert(not channel(primaryName,primaryGuid,TRADE,TRADE_SLOT,"Commerce"))
    assert(channel(primaryName,primaryGuid,GENERAL,8),"General is independent of a joined Trade channel")
end
env.C_ChatInfo.GetChannelInfoFromIdentifier=function() error("channel unavailable") end
assert(not channel(primaryName,primaryGuid,TRADE,TRADE_SLOT))
env.C_ChatInfo.GetChannelInfoFromIdentifier=nativeTrade
partyRaid:Click()
assert(q.db.muteBlacklistPartyRaid and q.db.muteBlacklistCityTrade)
assert(not incoming(filter,primaryName,primaryGuid,GUILD))
guild:Click()
assert(q.db.muteBlacklistGuild and guild:GetChecked() and not q.db.muteBlacklistWhispers)
assert(incoming(filter,primaryName,primaryGuid,GUILD) and not incoming(filter,adjacentName,adjacentGuid,GUILD))
assert(not incoming(filter,primaryName,adjacentGuid,GUILD) and not incoming(filter,"Élan",primaryGuid,GUILD))
assert(not incoming(filter,sim.secret,primaryGuid,GUILD) and not incoming(filter,primaryName,sim.secret,GUILD))
guild:Click()
assert(not q.db.muteBlacklistGuild and not incoming(filter,primaryName,primaryGuid,GUILD))
assert(q.db.muteBlacklistPartyRaid and q.db.muteBlacklistCityTrade)
guild:Click()
for _,event in ipairs({"CHAT_MSG_OFFICER","CHAT_MSG_GUILD_ACHIEVEMENT","CHAT_MSG_SYSTEM","CHAT_MSG_RAID_WARNING","CHAT_MSG_INSTANCE_CHAT","CHAT_MSG_WHISPER_INFORM"}) do
    assert(not incoming(filter,primaryName,primaryGuid,event,unusedBody,TRADE,TRADE_SLOT))
end

-- Say/Yell/group/channel events also carry our own messages. Unknown self
-- identity lets the line stand without reaching through native restrictions.
local playerGUID=env.UnitGUID
env.UnitGUID=function() return primaryGuid end
for _,event in ipairs({SAY,YELL,groupEvents[1],CHANNEL,GUILD}) do
    assert(not incoming(filter,primaryName,primaryGuid,event,unusedBody,GENERAL,3))
end
env.UnitGUID=function() return sim.secret end
assert(not incoming(filter,primaryName,primaryGuid,SAY))
assert(not incoming(filter,primaryName,primaryGuid,GUILD))
env.C_Secrets.ShouldUnitIdentityBeSecret=function() return true end
local restrictedGuidReads=0
env.UnitGUID=function() restrictedGuidReads=restrictedGuidReads+1; return primaryGuid end
assert(not incoming(filter,primaryName,primaryGuid,SAY))
assert(not incoming(filter,primaryName,primaryGuid,GUILD))
assert(restrictedGuidReads==0)
env.C_Secrets.ShouldUnitIdentityBeSecret=function() return false end
env.UnitGUID=playerGUID
default:Click()
assert(q.db.muteBlacklistWhispers and default:GetChecked())
assert(incoming(filter,adjacentName,adjacentGuid) and incoming(filter,adjacentName,adjacentGuid,GUILD))
local inherited=assert(B.save(nil,"blacklist",inheritedName,"",nil,{"other"}))
assert(B.store.get(inherited.id).whisperMuted==nil and incoming(filter,inheritedName,inheritedGuid))
V.SetSection("blacklist"); row=rowFor(V,adjacentName)
assert(row.muteSlash:IsShown())
row.inviteButton:Click()
assert(B.store.get(adjacent.id).whisperMuted==false and not row.muteSlash:IsShown())
assert(not incoming(filter,adjacentName,adjacentGuid))
assert(not incoming(filter,adjacentName,adjacentGuid,groupEvents[1]))
assert(not incoming(filter,adjacentName,adjacentGuid,GUILD))
assert(not channel(adjacentName,adjacentGuid,GENERAL,3))
V.SetSection("settings")
default:Click()
assert(not q.db.muteBlacklistWhispers and not incoming(filter,inheritedName,inheritedGuid))
assert(incoming(filter,primaryName,primaryGuid))
default:Click()
assert(incoming(filter,inheritedName,inheritedGuid) and not incoming(filter,adjacentName,adjacentGuid))

local reopened,_,_,reloaded=fresh(env.WhowhoPreviewDB,env.WhowhoAddressBookDB)
local C=reopened.manual
assert(C.chatMute.defaultEnabled() and C.store.get(primary.id).whisperMuted==true
    and C.store.get(adjacent.id).whisperMuted==false)
assert(incoming(reloaded,primaryName,primaryGuid) and not incoming(reloaded,adjacentName,adjacentGuid))
assert(C.chatMute.partyRaidEnabled() and C.chatMute.cityTradeEnabled() and C.chatMute.guildEnabled())
assert(incoming(reloaded,primaryName,primaryGuid,GUILD) and not incoming(reloaded,adjacentName,adjacentGuid,GUILD))
assert(incoming(reloaded,primaryName,primaryGuid,groupEvents[2]))
assert(incoming(reloaded,primaryName,primaryGuid,CHANNEL,nil,TRADE,TRADE_SLOT))

-- Deletion or a move during the native region read must beat a prior mute match.
local function onRegion(action)
    local ro,_,native,chat=fresh(env.WhowhoPreviewDB,env.WhowhoAddressBookDB)
    native.GetCurrentRegion=function()
        native.GetCurrentRegion=function() return 3 end
        action(ro.manual)
        return 3
    end
    assert(not incoming(chat,primaryName,primaryGuid))
    assert(not incoming(chat,primaryName,primaryGuid))
    return ro.manual,chat
end
onRegion(function(manual) assert(manual.delete(manual.store.get(primary.id))) end)
local moved,movedFilter=onRegion(function(manual)
    assert(manual.store.move(primary.id,"friend",111))
end)
assert(moved.store.get(primary.id).whisperMuted==nil)
assert(moved.save(moved.store.get(primary.id),"blacklist",primaryName,"",nil,{"other"},true))
assert(moved.store.get(primary.id).whisperMuted==nil and incoming(movedFilter,primaryName,primaryGuid))
assert(moved.delete(moved.store.get(primary.id)) and not incoming(movedFilter,primaryName,primaryGuid))

-- Reentrant registry dispatch and toggling cannot suppress on the outer callback.
local reentered=false
env.GetCurrentRegion=function()
    reentered=true
    assert(not incoming(filter,primaryName,primaryGuid))
    return 3
end
assert(not incoming(filter,primaryName,primaryGuid) and reentered)
env.GetCurrentRegion=function() return 3 end
env.GetCurrentRegion=function()
    assert(B.chatMute.setPartyRaid(false) and B.chatMute.setPartyRaid(true))
    return 3
end
assert(not incoming(filter,primaryName,primaryGuid,groupEvents[1]))
env.GetCurrentRegion=function()
    assert(B.chatMute.setGuild(false) and B.chatMute.setGuild(true))
    return 3
end
assert(not incoming(filter,primaryName,primaryGuid,GUILD))
env.GetCurrentRegion=function() return 3 end
env.C_ChatInfo.GetChannelInfoFromIdentifier=function(identifier)
    assert(B.chatMute.setCityTrade(false) and B.chatMute.setCityTrade(true))
    assert(not incoming(filter,primaryName,primaryGuid,SAY))
    return nativeTrade(identifier)
end
assert(not channel(primaryName,primaryGuid,TRADE,TRADE_SLOT))
env.C_ChatInfo.GetChannelInfoFromIdentifier=nativeTrade
assert(channel(primaryName,primaryGuid,TRADE,TRADE_SLOT))
assert(incoming(filter,primaryName,primaryGuid))
env.GetCurrentRegion=function()
    assert(B.chatMute.setDefault(false) and B.chatMute.setDefault(true))
    return 3
end
assert(not incoming(filter,primaryName,primaryGuid))
env.GetCurrentRegion=function() return 3 end

-- A name-only record can inherit a mute, but existing exact sighting evidence
-- vetoes conflicting GUIDs and ambiguous sightings.
local history={version=1,nextId=2,regions={[3]={{
    id=1,region=3,playerId=inherited.id,name=inheritedName,guid=inheritedGuid,target=true,
    startedAt=90,lastObservedAt=95,endedAt=100,
}}}}
local withHistory,_,_,seen=fresh(env.WhowhoPreviewDB,env.WhowhoAddressBookDB,{history=history})
assert(incoming(seen,inheritedName,inheritedGuid))
local conflicting="Player-1234-000000AE"
assert(not incoming(seen,inheritedName,conflicting))
assert(not incoming(seen,inheritedName,primaryGuid),"GUID belongs to another indexed record")
local ledger=withHistory.manual.encounterLedger
local episode=assert(ledger.start({id=inherited.id,name=inheritedName,guid=conflicting},3,110))
ledger.observe(episode,true,false,0)
assert(not incoming(seen,inheritedName,inheritedGuid) and not incoming(seen,inheritedName,conflicting))

-- A competing known name also matters when the GUID is known only to the
-- encounter ledger. Old names, removed records and expired episodes carry no
-- veto. A fresh active encounter restores the veto for the exact saved owner.
local belle=assert(B.save(nil,"blacklist","Belle South","",nil,{"other"}))
local belleGuid,oldNameGuid="Player-1234-000000BB","Player-1234-000000BC"
local function retainedEpisode(id,name,guid)
    return {id=id,region=3,playerId=belle.id,name=name,guid=guid,target=true,
        startedAt=90,lastObservedAt=95,endedAt=100}
end
local cross,_,crossEnv,crossFilter=fresh(env.WhowhoPreviewDB,env.WhowhoAddressBookDB,{history={
    version=1,nextId=3,regions={[3]={
        retainedEpisode(1,belle.fullName,belleGuid),
        retainedEpisode(2,"Former Name",oldNameGuid),
    }},
}})
local crossBook,crossLedger=cross.manual,cross.manual.encounterLedger
assert(not incoming(crossFilter,inheritedName,belleGuid))
assert(incoming(crossFilter,belle.fullName,belleGuid) and incoming(crossFilter,inheritedName,oldNameGuid))
local expiry=100+30*86400
crossEnv.GetServerTime=function() return expiry end
assert(incoming(crossFilter,inheritedName,belleGuid))
local active=assert(crossLedger.start({id=belle.id,name=belle.fullName,guid=belleGuid},3,expiry))
crossLedger.observe(active,true,false,0)
assert(not incoming(crossFilter,inheritedName,belleGuid))
assert(crossBook.move(crossBook.store.get(belle.id)))
assert(incoming(crossFilter,inheritedName,belleGuid))
assert(crossBook.delete(crossBook.store.get(belle.id)))
local laterBelle=assert(crossBook.save(nil,"blacklist",belle.fullName,"",nil,{"other"}))
assert(laterBelle.id~=belle.id and incoming(crossFilter,inheritedName,belleGuid))

for _,option in ipairs({
    {registry=false}, {protectNamespace=true}, {protectAdd=true}, {failAdd=true},
    {rejectAdd=true}, {secretResult=true}, {invalidBook=true},
}) do
    local unavailable,_,_,partial=fresh(env.WhowhoPreviewDB,env.WhowhoAddressBookDB,option)
    local view=unavailable.Shell
    assert(not unavailable.manual.chatMute.available())
    assert(not view.muteBlacklistWhispers:IsEnabled())
    if not option.invalidBook then
        view.SetSection("blacklist")
        local disabled=rowFor(view,primaryName)
        assert(not disabled.inviteButton:IsEnabled() and not disabled.muteSlash:IsShown())
    end
    if partial then assert(not incoming(partial,primaryName,primaryGuid)) end
end
local partial,_,_,limited=fresh(env.WhowhoPreviewDB,env.WhowhoAddressBookDB,{failEvent=SAY})
assert(partial.manual.chatMute.available() and not partial.manual.chatMute.baselineComplete())
assert(incoming(limited,primaryName,primaryGuid) and incoming(limited,primaryName,primaryGuid,YELL))
assert(not incoming(limited,primaryName,primaryGuid,SAY))
local missingRaid,_,_,limitedGroup=fresh(env.WhowhoPreviewDB,env.WhowhoAddressBookDB,{failEvent=groupEvents[4]})
assert(not missingRaid.Shell.muteBlacklistPartyRaid:IsEnabled() and missingRaid.Shell.muteBlacklistCityTrade:IsEnabled())
assert(missingRaid.db.muteBlacklistPartyRaid and not missingRaid.manual.chatMute.setPartyRaid(false))
for _,event in ipairs(groupEvents) do assert(not incoming(limitedGroup,primaryName,primaryGuid,event)) end
assert(incoming(limitedGroup,primaryName,primaryGuid,CHANNEL,nil,TRADE,TRADE_SLOT))
local missingChannel,_,_,limitedChannel=fresh(env.WhowhoPreviewDB,env.WhowhoAddressBookDB,{failEvent=CHANNEL})
assert(not missingChannel.Shell.muteBlacklistCityTrade:IsEnabled() and missingChannel.Shell.muteBlacklistPartyRaid:IsEnabled())
assert(missingChannel.db.muteBlacklistCityTrade and not missingChannel.manual.chatMute.setCityTrade(false))
assert(not incoming(limitedChannel,primaryName,primaryGuid,CHANNEL,nil,GENERAL,3))
assert(incoming(limitedChannel,primaryName,primaryGuid,groupEvents[1]))
local missingGuild,_,_,limitedGuild=fresh(env.WhowhoPreviewDB,env.WhowhoAddressBookDB,{failEvent=GUILD})
local guildView=missingGuild.Shell
guildView.SetSection("settings")
guildView.settingsTabs.general:Click()
assert(not guildView.muteBlacklistGuild:IsEnabled() and guildView.muteBlacklistPartyRaid:IsEnabled())
assert(missingGuild.db.muteBlacklistGuild and not missingGuild.manual.chatMute.setGuild(false))
visibleText(guildView.muteBlacklistGuild,"Guild chat unavailable.")
assert(not incoming(limitedGuild,primaryName,primaryGuid,GUILD) and incoming(limitedGuild,primaryName,primaryGuid,groupEvents[1]))
for _,option in ipairs({{missingChannelAPI=true},{locale="deDE"}}) do
    local generalOnly,_,_,filterGeneral=fresh(env.WhowhoPreviewDB,env.WhowhoAddressBookDB,option)
    assert(generalOnly.Shell.muteBlacklistCityTrade:IsEnabled() and not generalOnly.manual.chatMute.tradeSupported())
    generalOnly.Shell.SetSection("settings")
    generalOnly.Shell.settingsTabs.general:Click()
    visibleText(generalOnly.Shell.muteBlacklistCityTrade,"Built-in General only. Trade is unavailable.")
    assert(incoming(filterGeneral,primaryName,primaryGuid,CHANNEL,nil,GENERAL,3))
    assert(not incoming(filterGeneral,primaryName,primaryGuid,CHANNEL,nil,TRADE,TRADE_SLOT))
end
local migrated=fresh({muteBlacklistWhispers=true,muteBlacklistPartyRaid=1,muteBlacklistCityTrade="true",muteBlacklistGuild="true"},env.WhowhoAddressBookDB)
assert(migrated.db.muteBlacklistWhispers and not migrated.db.muteBlacklistPartyRaid and not migrated.db.muteBlacklistCityTrade
    and not migrated.db.muteBlacklistGuild)
assert(migrated.manual.store.get(primary.id).whisperMuted==true and migrated.manual.store.get(adjacent.id).whisperMuted==false)
assert(H.forbiddenCalls==0)
print("RESULT Blacklist chat mute coverage, persistence, attribution, lifecycle and compact layout passed in simulation")
