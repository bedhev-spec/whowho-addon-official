-- Simulated Who and widget APIs. These cases do not establish native routing.
local root = arg[1] or "."
local H = dofile(root .. "/tests/addon/harness.lua")
local config = {region=3, time=100}
local p, s, e = H.fresh(root, nil, nil, config)
local sends, timers, deferred = {}, {}, {}
local firstFrame, secondFrame = {}, {}
local filter, target, rows = nil, nil, {}
local duringSend
local targetUnreadable, unreadableIdentityReads = true, 0
e.InCombatLockdown = function() return false end
e.UnitExists = function(unit)
    if unit == "target" and targetUnreadable then return s.secret end
    return unit == "player" or unit == "target" and target ~= nil
end
e.UnitIsPlayer = e.UnitExists
e.GetUnitName = function()
    if targetUnreadable then unreadableIdentityReads=unreadableIdentityReads+1 end
    return target and target.fullName
end
e.UnitGUID = function()
    if targetUnreadable then unreadableIdentityReads=unreadableIdentityReads+1 end
    return target and target.guid
end
e.UnitClass = function() return "Mage", "MAGE" end
e.UnitLevel = function() return 42 end
e.Enum = { SocialWhoOrigin={Chat=2}, GameRule={IngameWhoListDisabled=5} }
e.C_GameRules = { IsGameRuleActive=function() return false end }
e.GetTime = function() return config.time end
e.date = function() return "2026-11-19 12:30" end
e.WHO_NUM_RESULTS = "%d players total"
e.RAID_CLASS_COLORS = { SHAMAN={} }
e.C_FriendList = {
    SendWho=function(name, origin)
        sends[#sends+1] = {name=name, origin=origin}
        if duringSend then duringSend(name, origin) end
    end,
    GetNumWhoResults=function() return #rows, #rows end,
    GetWhoInfo=function(i) return rows[i] end,
}
e.hooksecurefunc = function(api, key, callback)
    local original = api[key]
    api[key] = function(...)
        original(...)
        callback(...)
    end
end
e.ChatFrameUtil = {
    AddMessageEventFilter=function(event, callback) assert(event == "CHAT_MSG_SYSTEM" and not filter); filter=callback end,
    RemoveMessageEventFilter=function(event, callback) assert(event == "CHAT_MSG_SYSTEM" and filter == callback); filter=nil end,
}
e.C_Timer = {
    NewTimer=function(delay, callback)
        assert(delay == 15)
        local handle = { callback=callback, Cancel=function(self) self.cancelled=true end }
        timers[#timers+1] = handle
        return handle
    end,
    After=function(delay, callback) assert(delay == 0); deferred[#deferred+1]=callback end,
}
local function flush()
    local callbacks = deferred
    deferred = {}
    for _, callback in ipairs(callbacks) do callback() end
end
local function chat(frame, text)
    return filter and filter(frame, "CHAT_MSG_SYSTEM", text) or false
end
local function lookupRow(name)
    return { fullName=name, level=41, raceStr="Tauren", classStr="Shaman", area="Stranglethorn Vale",
        fullGuildName="", filename="SHAMAN" }
end

s:event("ADDON_LOADED", "WhoWho"); p.Toggle()
local A, S = p.manual, p.Shell
local function attemptColor(color)
    for i, component in ipairs(color) do assert(S.detail.attempt.textColor[i]==component) end
end
assert(#sends == 0 and not filter)
local form = S.editor.controls
S.addButton:Click(); form.formName:SetText("Ornek Val"); form.formSave:Click()
local id = S.selectedId
assert(#sends == 1 and sends[1].name == "Ornek Val" and sends[1].origin == 2 and filter,
    "an unreadable target must not prevent Add Friend from reaching Who")
assert(unreadableIdentityReads == 0)
assert(S.detail.attempt:GetText() == "Checking Who…")
attemptColor(p.colors.body)
S.checkStatus:Click(); assert(#sends == 1)

rows = { lookupRow("Ornek Val") }
local line = "[41:Ornek Val]: Level 41 Tauren Shaman - Stranglethorn Vale"
assert(not chat(firstFrame, "1 players total"))
assert(not chat(firstFrame, "Ornek Val completed a quest"))
assert(chat(firstFrame, line) and chat(secondFrame, line))
assert(chat(firstFrame, "1 players total") and chat(secondFrame, "1 players total"))
assert(not chat(firstFrame, "1 players total"))
flush()
assert(not filter and timers[1].cancelled and S.selectedId == id)
assert(S.detail.current:GetText() == "Online" and S.selected.presenceReport.source == "Who")
assert(S.detail.attempt:GetText()=="Exact Who result found.")
attemptColor(p.colors.body)
assert(S.selected.class == "SHAMAN" and S.selected.level == 41 and A.store.get(id).lastKnown == nil)
e.IsInRaid=function() return false end
e.GetNumSubgroupMembers=function() return 0 end
S.refreshNow:Click()
assert(S.refreshStatus:GetText()=="Roster status found for 0 of 1 Friend.")
assert(#sends==1 and S.selectedId==id and S.detail.current:GetText()=="Online" and S.selected.presenceReport.source=="Who",
    "a roster miss keeps the Who result and sends no additional Who request")

config.time=120
local attempt=A.targetCheck.attempts[id]
A.targetCheck.attempts[id]=nil
assert(not A.whoLookup.request(S.selected) and #sends==1, "Who cannot start without a current Friend attempt")
A.targetCheck.attempts[id]=attempt
S.checkStatus:Click(); assert(#sends == 2 and S.detail.current:GetText() == "Unknown")
assert(unreadableIdentityReads == 0)
targetUnreadable=false
-- A previously populated global result and an update event alone establish no new observation.
s:event("WHO_LIST_UPDATE")
timers[#timers].callback(); assert(S.detail.current:GetText() == "Unknown" and not filter)
assert(S.detail.attempt:GetText()=="No fresh exact Who result.")
attemptColor(p.colors.warning)

config.time=140
S.checkStatus:Click(); assert(#sends == 3)
rows = {}
assert(chat(firstFrame, "0 players total") and chat(secondFrame, "0 players total"))
flush()
assert(not filter and S.detail.current:GetText() == "Unknown" and S.detail.attempt:GetText() == "No exact Who result.")
attemptColor(p.colors.body)

config.time=160
S.checkStatus:Click(); assert(#sends == 4)
rows = {lookupRow("Ornek Val")}
assert(chat(firstFrame, line) and chat(firstFrame, "1 players total"))
e.C_FriendList.SendWho("Second Person", 2)
assert(not chat(secondFrame, line) and not chat(secondFrame, "1 players total"))
flush()
assert(not filter and S.detail.current:GetText() == "Unknown")
assert(S.detail.attempt:GetText() == "Who check yielded to another search.")

config.time=180
S.checkStatus:Click(); assert(#sends == 6 and filter)
assert(A.delete(S.selected)); S.Refresh()
local replacement = assert(A.save(nil, "friend", "Ornek Val", "", nil))
assert(replacement.id ~= id and #sends == 6)
assert(chat(firstFrame, line) and chat(firstFrame, "1 players total"))
flush()
assert(not filter and not A.whoLookup.hasReports())

config.time=200
target = {fullName="Ornek Val", guid="different-source"}
S.Select(A.records[1]); S.checkStatus:Click()
assert(S.detail.current:GetText() == "Unknown" and #sends == 6 and not filter)
target = nil
config.time=520
s:fire(S.window,"OnUpdate",1)
S.checkStatus:Click(); assert(#sends == 7 and filter)
assert(chat(firstFrame,line) and chat(firstFrame,"1 players total"))
flush()
assert(S.detail.current:GetText() == "Online")
config.time=820
s:fire(S.window,"OnUpdate",1)
assert(S.detail.current:GetText() == "Unknown" and not A.whoLookup.hasReports())

config.time=840
e.LFGWhoListFrame={IsForbidden=function() return false end, IsVisible=function() return true end}
S.checkStatus:Click(); assert(#sends == 7 and not filter)
assert(S.detail.attempt:GetText() == "Close the Who tab before checking this Friend.")
attemptColor(p.colors.warning)
e.LFGWhoListFrame=nil
S.checkStatus:Click(); assert(#sends == 8 and filter)
s:event("PLAYER_LEAVING_WORLD")
assert(not filter and S.detail.current:GetText() == "Unknown")

config.time=860
e.ChatFrameUtil.AddMessageEventFilter=function(_, callback)
    s:event("PLAYER_LEAVING_WORLD")
    filter=callback
end
e.ChatFrameUtil.RemoveMessageEventFilter=function(_, callback)
    if filter == callback then filter=nil end
end
S.checkStatus:Click(); assert(#sends == 8 and not filter)
e.ChatFrameUtil.AddMessageEventFilter=function(_, callback) filter=callback end
config.time=880
S.checkStatus:Click(); assert(#sends == 9 and filter)
-- The same row remains in the global list. Only the new pair can satisfy the check.
assert(chat(firstFrame, line) and chat(firstFrame, "1 players total"))
flush()
assert(S.detail.current:GetText() == "Online" and not filter)

config.time=900
local nestedRowHidden, nestedTotalHidden
duringSend=function(name, origin)
    duringSend=nil
    e.C_FriendList.SendWho(name, origin)
    nestedRowHidden=chat(firstFrame, line)
    nestedTotalHidden=chat(firstFrame, "1 players total")
end
S.checkStatus:Click()
flush()
assert(#sends == 11 and nestedRowHidden == false and nestedTotalHidden == false)
assert(not filter and S.detail.current:GetText() == "Unknown")
assert(S.detail.attempt:GetText() == "Who check yielded to another search.")

config.time=905
S.addButton:Click(); form.formName:SetText("New Friend"); form.formSave:Click()
assert(S.selected.fullName == "New Friend" and #sends == 11 and not filter)
local cooldownRecord=S.selected
assert(S.detail.attempt:GetText()==p.L(A.whoLookup.cooldownMessage),
    "Add Friend must surface the localized Who cooldown in Last check")
attemptColor(p.colors.warning)
assert(S.detail.attemptLabel.textColor[1]==p.colors.muted[1])
S.Select(replacement)
assert(S.detail.attempt:GetText()=="Who check yielded to another search.")
attemptColor(p.colors.warning)
S.Select(cooldownRecord)
attemptColor(p.colors.warning)
S.Select(nil)
assert(S.detail.attempt:GetText()=="")
attemptColor(p.colors.body)
S.Select(cooldownRecord)
config.time=920
S.checkStatus:Click(); assert(#sends == 12 and sends[12].name == "New Friend" and filter)
assert(S.detail.attempt:GetText()=="Checking Who…")
attemptColor(p.colors.body)
s:event("PLAYER_LEAVING_WORLD")

config.time=940
local playerFaction="Alliance"
target={fullName="Opposing Friend",guid="opposing-friend",faction="Horde"}
e.UnitFactionGroup=function(unit)
    if unit=="player" then return playerFaction end
    return target and target.faction
end
e.UnitClass=function() return "Priest","PRIEST" end
S.addButton:Click(); form.formName:SetText("Opposing Friend"); form.formSave:Click()
assert(S.selected.fullName=="Opposing Friend" and S.detail.current:GetText()=="Unknown")
assert(S.detail.affiliation:GetText()=="Horde · Local checks only")
assert(S.selected.class=="PRIEST" and S.selected.level==42)
assert(S.checkStatus:IsEnabled() and #sends==12 and not filter)
s:fire(S.checkStatus,"OnEnter")
assert(e.GameTooltip:GetText():find("Who can't look up this player",1,true))
s:fire(S.checkStatus,"OnLeave"); assert(not e.GameTooltip:IsShown())
target.faction=nil
config.time=950
S.checkStatus:Click()
assert(S.detail.current:GetText()=="Unknown" and S.selected.faction=="Horde" and #sends==12)
target=nil
config.time=1250
s:fire(S.window,"OnUpdate",1)
S.checkStatus:Click()
assert(S.detail.current:GetText()=="Unknown" and S.selected.class=="PRIEST" and S.selected.observed)
assert(S.detail.attempt:GetText()=="Who unavailable for the other faction." and #sends==12 and not filter)
attemptColor(p.colors.warning)
playerFaction=s.secret
S.checkStatus:Click()
assert(#sends==13 and sends[13].name=="Opposing Friend" and filter)
assert(S.detail.affiliation:GetText()=="Horde","unreadable player faction should keep normal lookup")
s:event("PLAYER_LEAVING_WORLD")

local inCombat=false
e.InCombatLockdown=function() return inCombat end
local opposingLine="[41:Opposing Friend]: Level 41 Tauren Shaman - Stranglethorn Vale"
rows={lookupRow("Opposing Friend")}
for _,completedPair in ipairs({false,true}) do
    config.time=config.time+20
    local previousSends=#sends
    S.checkStatus:Click()
    assert(#sends==previousSends+1 and filter and A.whoLookup.running(S.selectedId))
    local oldFilter, timer=filter, timers[#timers]
    if completedPair then
        assert(chat(firstFrame,opposingLine) and chat(firstFrame,"1 players total") and #deferred==1)
    end
    inCombat=true
    s:event("PLAYER_REGEN_DISABLED")
    assert(not filter and timer.cancelled and not A.whoLookup.running(S.selectedId),
        "combat entry immediately closes the active Who request")
    inCombat=false
    s:event("PLAYER_REGEN_ENABLED")
    assert(not chat(secondFrame,opposingLine) and not chat(secondFrame,"1 players total")
        and not oldFilter(secondFrame,"CHAT_MSG_SYSTEM",opposingLine),
        "late Who chat is visible after combat")
    flush()
    timer.callback()
    assert(#sends==previousSends+1 and not A.whoLookup.hasReports() and S.detail.current:GetText()=="Unknown"
        and S.detail.attempt:GetText()=="Who check unavailable.",
        "leaving combat cannot retry a cancelled Who request or publish a previously completed pair")
    attemptColor(p.colors.warning)
end

local function checkFailure(owner,key,override,caption)
    config.time=config.time+16
    local original,previousSends=owner[key],#sends
    owner[key]=override
    S.checkStatus:Click()
    owner[key]=original
    assert(#sends==previousSends and not filter and not A.whoLookup.running(S.selectedId))
    assert(S.detail.attempt:GetText()==caption)
    attemptColor(p.colors.warning)
end
checkFailure(e.C_FriendList,"SendWho",function() error("simulated rejection") end,"No fresh exact Who result.")
checkFailure(e.C_FriendList,"SendWho",function() end,"No fresh exact Who result.")
checkFailure(e.C_Timer,"NewTimer",function() end,"Who could not start its timer.")
inCombat=true
S.checkStatus:Click()
assert(S.detail.attempt:GetText()=="Checks paused during combat.")
attemptColor(p.colors.warning)
inCombat=false

for _,unavailableEvent in ipairs({"PLAYER_REGEN_DISABLED","PLAYER_LEAVING_WORLD","PLAYER_ENTERING_WORLD"}) do
    local p2,s2,e2=H.fresh(root,nil,nil,{region=3,time=100})
    local loader
    for _,node in ipairs(s2.nodes) do
        if node.events.ADDON_LOADED then loader=node; break end
    end
    assert(loader)
    local register=loader.RegisterEvent
    loader.RegisterEvent=function(self,event)
        local registered=register(self,event)
        if event==unavailableEvent then return false end
        return registered
    end
    e2.InCombatLockdown=function() return false end
    e2.C_FriendList={SendWho=function() error("unexpected Who send") end}
    local hooked=false
    e2.hooksecurefunc=function() hooked=true end
    s2:event("ADDON_LOADED","WhoWho")
    if unavailableEvent=="PLAYER_ENTERING_WORLD" then
        assert(p2.initialized and hooked and loader.events.PLAYER_REGEN_DISABLED and loader.events.PLAYER_LEAVING_WORLD,
            "a failed world-entry listener preserves monitoring for Friends")
        local entry=assert(p2.manual.save(nil,"blacklist","Blocked Character","",nil,{"other"}))
        assert(p2.manual.whoLookup.requestBlacklist(entry,function() end)=="Who request monitoring is unavailable.")
    else
        assert(p2.initialized and not hooked and not loader.events.PLAYER_REGEN_DISABLED
            and not loader.events.PLAYER_LEAVING_WORLD and loader.events.PLAYER_TARGET_CHANGED,
            "failed cancellation prerequisites roll back only Who events and never install its send hook")
    end
    assert(s2.forbiddenCalls==0)
end

local function addBlacklist(name)
    S.SetSection("blacklist")
    S.addButton:Click()
    form.formName:SetText(name)
    form.reasonOptions.other:Click()
    form.formSave:Click()
end
local function saveBlacklistEdit(note)
    S.editButton:Click()
    assert(S.editor.IsShown())
    if note then form.formNote:SetText(note) end
    form.formSave:Click()
    assert(not S.editor.IsShown())
end
local function exactBlacklist(name, file)
    rows={lookupRow(name)}
    rows[1].filename=file
    local line=("[41:%s]: Level 41 Tauren Shaman - Stranglethorn Vale"):format(name)
    assert(chat(firstFrame,line) and chat(firstFrame,"1 players total"))
end

assert(A.relogRefreshEnabled(), "coverage uses the default relog refresh setting")
s:event("PLAYER_ENTERING_WORLD",true,false)
S.SetSection("blacklist")
S.ResetFooter()
assert(S.footer.textColor[1]==p.colors.muted[1])
e.C_ClassColor={GetClassColor=function(token)
    return token=="SHAMAN" and {r=.15,g=.25,b=.95} or {r=.35,g=.65,b=.95}
end}
playerFaction="Alliance"
config.time=1350
local before=#sends
addBlacklist("Pasted Character")
local pasted=S.selectedId
assert(#sends==before+1 and sends[#sends].name=="Pasted Character" and S.selected.blacklistWhoClass==nil)
assert(S.footer:GetText()=="Checking Who…" and S.footer.textColor[1]==p.colors.warning[1])
assert(S.checkStatus.label:GetText()=="Check status" and not S.checkStatus:IsShown() and not S.checkStatus:IsEnabled())
assert(S.detail.name.textColor[1]==1)
S.editButton:Click()
form.formCancel:Click()
assert(#sends==before+1 and filter and S.footer:GetText()=="Checking Who…")
rows={lookupRow("Different Character")}
assert(not chat(firstFrame,"[41:Different Character]: Level 41 Tauren Shaman - Stranglethorn Vale"))
assert(not chat(firstFrame,"1 players total"))
timers[#timers].callback()
assert(not filter and not S.selected.blacklistWhoClass)

config.time=1355
saveBlacklistEdit()
assert(#sends==before+1 and S.footer:GetText()=="Who is cooling down. Try again shortly.")
assert(S.footer.textColor[1]==p.colors.warning[1])
config.time=1370
saveBlacklistEdit()
assert(#sends==before+2 and sends[#sends].name=="Pasted Character")
exactBlacklist("Pasted Character","SHAMAN")
flush()
assert(S.selectedId==pasted and S.selected.blacklistWhoClass=="SHAMAN" and S.detail.name.textColor[1]==.15)
assert(S.rows[1].name.textColor[1]==.15 and not S.checkStatus:IsShown())
assert(S.selected.blacklistFaction==nil and S.selected.presenceReport==nil and A.store.get(pasted).lastKnown==nil)
assert(S.footer:GetText()=="Class found through Who.")
S.rows[1].deleteButton:Click()
assert(S.deleteDialog:IsShown() and S.deleteMessage.textColor[1]==.15 and #sends==before+2,
    "Delete uses the displayed temporary Who class without starting another lookup")
S.deleteCancel:Click()
S.facetLinks.classFilter:Click()
local classes=S.filterChoices.classFilter
assert(not S.filterToggle:IsVisible() and classes.ALL:IsVisible() and S.sortButton:GetParent()==S.list)
assert(not S.filters.roleFilter:IsVisible() and not S.filters.statusFilter:IsVisible())
assert(not S.filterChoices.roleFilter.TANK:IsVisible() and not S.filterChoices.statusFilter.Online:IsVisible())
classes.SHAMAN:Click()
assert(S.filtered[1].id==pasted and S.rows[1].name.textColor[1]==.15)
assert(not S.filterMenu:IsShown() and S.facetLinks.classFilter.label:GetText()=="Shaman")
S.facetLinks.classFilter:Click()
classes.UNASSIGNED:Click()
assert(#S.filtered==0)
S.facetLinks.classFilter:Click(); classes.ALL:Click()

addBlacklist("Pasted Character")
assert(form.formSave.label:GetText()=="Open existing" and #sends==before+2)
form.formSave:Click()
assert(S.selectedId==pasted and #sends==before+2)
config.time=1670
s:fire(S.window,"OnUpdate",1)
assert(S.selectedId==pasted and S.detail.name.textColor[1]==1 and S.rows[1].name.textColor[1]==1 and not S.checkStatus:IsShown())
S.rows[1].deleteButton:Click()
assert(S.deleteDialog:IsShown() and S.deleteMessage.textColor[1]==p.colors.text[1] and #sends==before+2,
    "Delete stays neutral after the Who class expires")
S.deleteCancel:Click()

saveBlacklistEdit()
assert(#sends==before+3 and filter)
exactBlacklist("Pasted Character",nil)
flush()
assert(not S.selected.blacklistWhoClass and S.footer:GetText()=="Who result has no class.")

config.time=1690
saveBlacklistEdit()
assert(#sends==before+4 and filter)
exactBlacklist("Pasted Character","SHAMAN")
e.C_FriendList.SendWho("Native Search",2)
flush()
assert(#sends==before+5 and not filter and not S.selected.blacklistWhoClass)
assert(S.footer:GetText()=="Who check yielded to another search.")

config.time=1710
saveBlacklistEdit()
local getServerTime=e.GetServerTime
exactBlacklist("Pasted Character","SHAMAN")
e.GetServerTime=function()
    e.GetServerTime=getServerTime
    e.C_FriendList.SendWho("Native During Settle",2)
    return getServerTime()
end
flush()
assert(not filter and not S.selected.blacklistWhoClass and S.footer:GetText()=="Who check yielded to another search.")

for _,event in ipairs({"PLAYER_REGEN_DISABLED","PLAYER_LEAVING_WORLD"}) do
    config.time=config.time+20
    saveBlacklistEdit()
    local timer, oldFilter = timers[#timers], filter
    assert(oldFilter)
    exactBlacklist("Pasted Character","SHAMAN")
    s:event(event)
    assert(not filter and timer.cancelled)
    flush(); timer.callback()
    assert(not S.selected.blacklistWhoClass and A.store.get(pasted).lastKnown==nil)
end
config.time=1770
before=#sends
saveBlacklistEdit()
assert(#sends==before and not filter and S.footer:GetText()=="Who is unavailable outside the world.",
    "world exit blocks a new Blacklist request until entry")
s:event("PLAYER_ENTERING_WORLD",false,false)
saveBlacklistEdit()
assert(#sends==before+1 and filter, "Who retains world-entry events after default relog refresh starts at login")
exactBlacklist("Pasted Character","SHAMAN")
saveBlacklistEdit("Edited during Who")
assert(S.footer:GetText()=="Who is cooling down. Try again shortly.")
flush()
assert(#sends==before+1 and not S.selected.blacklistWhoClass and A.store.get(pasted).note=="Edited during Who"
    and S.footer:GetText()=="Who is cooling down. Try again shortly.")

config.time=1790
saveBlacklistEdit()
assert(#sends==before+2 and filter)
exactBlacklist("Pasted Character","SHAMAN")
target={fullName="Pasted Character",guid="verified-guid",faction="Alliance"}
local store=A.store
local evidence=A.captureBlacklistMetadata("target",store,3,target.fullName,target.guid,"Target")
assert(A.saveBlacklistObservations(store,3,{{id=pasted,evidence=evidence}},function() return A.store==store end))
flush(); S.RefreshBlacklistMetadata()
assert(S.selected.blacklistSavedClass=="PRIEST" and not S.selected.blacklistWhoClass and not S.checkStatus:IsShown())
S.facetLinks.classFilter:Click(); classes.PRIEST:Click()
assert(S.filtered[1].id==pasted and S.rows[1].name.textColor[1]==1)
S.nav.friend:Click()
assert(not S.filterMenu:IsShown() and S.filterToggle.label:GetText()=="Filters")
S.nav.blacklist:Click()
assert(S.classFilter=="PRIEST" and S.filtered[1].id==pasted and S.filterToggle.label:GetText()=="Filters (1)")
S.facetLinks.classFilter:Click(); classes.ALL:Click()
config.time=1810
target=nil
saveBlacklistEdit("Persistent class")
assert(#sends==before+2 and not filter and S.selected.blacklistSavedClass=="PRIEST")

target={fullName="Other Faction",guid="other-faction",faction="Horde"}
e.UnitClass=function() return nil end
addBlacklist("Other Faction")
assert(#sends==before+2 and S.selected.blacklistFaction=="Horde" and not S.selected.blacklistWhoClass)
assert(S.footer:GetText()=="Who unavailable for the other faction.")
target=nil
saveBlacklistEdit()
assert(#sends==before+2 and not filter)

config.time=1830
target={fullName="Seen Locally",guid="seen-locally",faction="Alliance"}
e.UnitClass=function() return "Priest","PRIEST" end
addBlacklist("Seen Locally")
assert(#sends==before+2 and S.selected.blacklistSavedClass=="PRIEST" and not S.checkStatus:IsShown())
assert(S.footer:GetText()=="Class found locally." or S.footer.textColor[1]==p.colors.muted[1])
target=nil

local function refusedBeforeSend(owner, key, replacement, message)
    local original, sent = owner[key], #sends
    owner[key]=replacement
    saveBlacklistEdit()
    owner[key]=original
    assert(#sends==sent and not filter and S.footer:GetText()==message, S.footer:GetText())
    assert(S.footer.textColor[1]==p.colors.warning[1] and not S.selected.blacklistWhoClass)
end
config.time=1850
for _, record in ipairs(A.records) do
    if record.fullName=="Other Faction" then S.Select(record); break end
end
assert(S.selected.fullName=="Other Faction")
playerFaction="Horde"
refusedBeforeSend(e, "InCombatLockdown", function() return true end, "Who is unavailable during combat.")
refusedBeforeSend(e, "InCombatLockdown", function() return s.secret end, "Who could not verify combat state.")
local getCurrentRegion=e.GetCurrentRegion
e.GetCurrentRegion=function() return 1 end
assert(A.whoLookup.requestBlacklist(S.selected,function() end)=="Who could not verify your current region.")
e.GetCurrentRegion=getCurrentRegion
refusedBeforeSend(A, "tryBlacklistMetadata", function() end, "The Blacklist entry or local match changed. Try again.")
refusedBeforeSend(e, "GetTime", function() return s.secret end, "Who could not read the session clock.")
refusedBeforeSend(e.C_GameRules, "IsGameRuleActive", function() return s.secret end, "Who could not verify the game rules.")
refusedBeforeSend(e.C_GameRules, "IsGameRuleActive", function() return true end, "Who is disabled in this game mode.")
refusedBeforeSend(e.C_FriendList, "GetWhoInfo", nil, "Who search is unavailable in this client.")
refusedBeforeSend(e.ChatFrameUtil, "AddMessageEventFilter", nil, "Who chat filtering is unavailable.")
refusedBeforeSend(e, "WHO_NUM_RESULTS", "Unformatted total", "Who could not read your client's result format.")
local timerCount=#timers
refusedBeforeSend(e.ChatFrameUtil, "AddMessageEventFilter", function(_, callback)
    filter=callback
    error("simulated filter error after registration")
end, "Who could not register its chat filter.")
assert(#timers==timerCount, "failure to register chat must not start a Who timer")
refusedBeforeSend(e.C_Timer, "NewTimer", function() return s.secret end, "Who could not start its timer.")
refusedBeforeSend(e.C_FriendList, "SendWho", function() error("simulated native rejection") end, "The client refused the Who search.")
config.time=1870
refusedBeforeSend(e.C_FriendList, "SendWho", function() end, "Who could not confirm the search started.")

config.time=1890
local beforeMove=#sends
S.SetSection("friend")
for _, record in ipairs(A.records) do
    if record.fullName=="New Friend" then S.Select(record); break end
end
assert(S.selected.fullName=="New Friend" and S.checkStatus:IsShown() and S.checkStatus:IsEnabled())
S.moveButton:Click()
form.reasonOptions.other:Click()
form.formSave:Click()
assert(S.section=="blacklist" and S.selected.fullName=="New Friend" and not S.checkStatus:IsShown())
assert(#sends==beforeMove and not filter, "moving a Friend does not request Who during Save")

config.time=1910
saveBlacklistEdit()
assert(#sends==beforeMove+1 and filter)
exactBlacklist("New Friend","SHAMAN")
flush()
assert(S.selected.blacklistWhoClass=="SHAMAN" and not S.selected.blacklistSavedClass)
config.time=1930
saveBlacklistEdit("Who class already known")
assert(#sends==beforeMove+1 and not filter and S.selected.note=="Who class already known",
    "editing a row that already showed a Who class does not start another search")

config.time=1950
saveBlacklistEdit()
assert(#sends==beforeMove+2 and filter and not S.selected.blacklistWhoClass)
S.editButton:Click()
assert(S.editor.IsShown())
exactBlacklist("New Friend","SHAMAN")
flush()
assert(S.editor.IsShown() and S.selected.blacklistWhoClass=="SHAMAN" and form.formName.textColor[1]==.15,
    "an exact Who result received after opening Edit updates the name color")
config.time=1970
form.formNote:SetText("Who completed while editing")
form.formSave:Click()
assert(#sends==beforeMove+2 and not filter and S.selected.note=="Who completed while editing",
    "a Who result received during editing avoids another search after the cooldown")

S.nav.settings:Click()
S.settingsTabs.friends:Click()
local toggle=S.automaticTarget
local function toggleColor(color)
    for i,component in ipairs(color) do assert(toggle.children[2].color[i]==component) end
end
assert(not toggle.scripts.OnMouseDown and not toggle.scripts.OnMouseUp)
local initial=p.manual.automaticTargetEnabled()
s:fire(toggle,"OnEnter"); toggleColor(p.colors.hover)
for _,checked in ipairs({not initial,initial}) do
    toggle:Click()
    assert(toggle:GetChecked()==checked and p.manual.automaticTargetEnabled()==checked)
    assert(toggle.state:GetText()==p.L(checked and "On" or "Off"))
    toggleColor(p.colors.hover)
end
s:fire(toggle,"OnLeave"); toggleColor(p.colors.raised)
s:fire(toggle,"OnEnter"); toggleColor(p.colors.hover)
toggle:Hide(); toggleColor(p.colors.raised)
toggle:Show(); toggleColor(p.colors.raised)
toggle:Disable()
s:fire(toggle,"OnEnter"); toggleColor(p.colors.raised)
toggle:Click(); assert(toggle:GetChecked()==initial)
toggle:Enable()
S.SetSection("friend")
S.searchBox:SetText("Ornek Val")
S.rows[1]:Click()
assert(S.selected.fullName=="Ornek Val")
config.time=config.time+20
local refresh=A.refresh
local cancelled,previousSends=false,#sends
A.refresh=function(...)
    if not cancelled and A.whoLookup.running(S.selectedId) then
        cancelled=true
        A.whoLookup.cancel(true)
    end
    return refresh(...)
end
S.checkStatus:Click()
A.refresh=refresh
assert(cancelled and #sends==previousSends+1 and not filter and timers[#timers].cancelled)
assert(S.detail.attempt:GetText()=="Who check unavailable.")
attemptColor(p.colors.warning)

assert(s.forbiddenCalls == 0)
print("RESULT Friends and Blacklist Who fallback, exact pairing, cancellation, expiry, faction checks and toggle feedback passed in simulation")
