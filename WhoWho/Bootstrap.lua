local addonName = ...
local P = WhowhoPreview
local D = P.LayoutMetrics
local loader
local inviteEvents = {}
local nameplateDispatch = {}
local relogCycle
local whoEnteringWorld
local relogSources={"Guild","Recent Allies"}
local relogEvents={
    INITIAL_CLUBS_LOADED="Guild", CLUB_MEMBERS_UPDATED="Guild",
    RECENT_ALLIES_DATA_READY="Recent Allies", RECENT_ALLIES_CACHE_UPDATE="Recent Allies",
}
local function register(event)
    local ok, registered=pcall(loader.RegisterEvent,loader,event)
    if not ok then return false end
    local checked, secret=pcall(issecretvalue,registered)
    return checked and secret==false and registered==true
end
local function unregister(event)
    pcall(loader.UnregisterEvent,loader,event)
end
local function stopRelog()
    if not relogCycle then return end
    relogCycle=nil
    if not whoEnteringWorld then unregister("PLAYER_ENTERING_WORLD") end
    unregister("PLAYER_REGEN_ENABLED")
    for event in pairs(relogEvents) do unregister(event) end
end
if P.manual then
    local A = P.manual
    local function automaticSetting(key,events,available,onChanged)
        local enabled, generation, changing = false, 0, false
        local function get()
            return enabled, generation
        end
        local function set(value)
            if not A.store or changing then return false end
            if value == enabled then return true end
            if value and available and not available() then return false end
            changing = true
            if value then
                for _, event in ipairs(events) do
                    if not inviteEvents[event] and not register(event) then
                        for _, registeredEvent in ipairs(events) do
                            if not inviteEvents[registeredEvent] then unregister(registeredEvent) end
                        end
                        changing = false
                        return false
                    end
                end
            end
            enabled, generation = value, generation + 1
            P.db[key] = enabled
            if not enabled then
                for _, event in ipairs(events) do
                    if not inviteEvents[event] then unregister(event) end
                end
            end
            if onChanged then onChanged(enabled) end
            changing = false
            return true
        end
        return get,set
    end
    A.automaticTargetEnabled,A.setAutomaticTarget=automaticSetting("automaticTarget",{"PLAYER_TARGET_CHANGED"})
    A.automaticMouseoverEnabled,A.setAutomaticMouseover=automaticSetting("automaticMouseover",{"UPDATE_MOUSEOVER_UNIT"},
        A.targetCheck.mouseoverAvailable,function(enabled)
            if not enabled then A.targetCheck.cancelMouseover() end
        end)
    A.automaticNameplatesEnabled,A.setAutomaticNameplates=automaticSetting("automaticNameplates",
        {"NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED"},A.nameplateCheck.available,function(enabled)
            local B=P.BlacklistBanner
            if B.sightingsNameplatesChanged then B.sightingsNameplatesChanged(enabled) end
            local changed
            if enabled then changed=A.nameplateCheck.seed()
            else changed=A.nameplateCheck.cancel() end
            if changed then P.Shell.RefreshFriends() end
        end)
    function A.relogRefreshEnabled()
        return P.db.relogRefresh==true
    end
    function A.setRelogRefresh(value)
        if not A.store then return false end
        P.db.relogRefresh=value
        if not value then stopRelog() end
        return true
    end
end
local function finite(value)
    return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge
end
local points={CENTER=true,TOP=true,BOTTOM=true,LEFT=true,RIGHT=true,TOPLEFT=true,TOPRIGHT=true,BOTTOMLEFT=true,BOTTOMRIGHT=true}
function P.ScaleLimits()
    local maximum=1.5
    local width,height=UIParent:GetWidth(),UIParent:GetHeight()
    if finite(width) and finite(height) and width>0 and height>0 then
        maximum=math.max(0.1,math.min(maximum,(width-D.viewportMargin)/D.minimumWidth,(height-D.viewportMargin)/D.windowHeight))
    end
    return math.min(0.5,maximum),maximum
end
local function clampScale(value)
    local low,high=P.ScaleLimits()
    return math.max(low,math.min(high,finite(value) and value or 1))
end
function P.SetScale(value)
    value=clampScale(value)
    local changed=P.db.scale~=value
    if changed then P.db.scale=value end
    local S=P.Shell
    if S.window then
        if changed then S.window:SetScale(value) end
        if changed or S.layoutViewportWidth~=UIParent:GetWidth() or S.layoutViewportHeight~=UIParent:GetHeight() then S.Layout() end
        S.settings:SyncScale(value)
    end
end
function P.SetInterfaceColor(value)
    P.db.interfaceColor=P.ApplyInterfaceColor(value)
end
function P.Init()
    if P.initialized then return end
    if P.manual and not P.addonLoaded then return end
    if type(WhowhoPreviewDB) ~= "table" then WhowhoPreviewDB={} end
    local old=WhowhoPreviewDB
    local scale=clampScale(old.scale)
    local angle=finite(old.minimapAngle) and old.minimapAngle % 360 or 225
    local automaticTarget=P.manual and old.automaticTarget~=false
    local automaticMouseover=P.manual and old.automaticMouseover~=false
    local automaticNameplates=P.manual and old.automaticNameplates~=false
    local relogRefresh=P.manual and old.relogRefresh~=false
    local skipDeleteConfirmation=P.manual and old.skipDeleteConfirmation==true
    local position=old.position
    if type(position)~="table" or not points[position.point] or not points[position.relativePoint] or not finite(position.x) or not finite(position.y) then position=nil end
    WhowhoPreviewDB={scale=scale,minimapAngle=angle,position=position}; P.db=WhowhoPreviewDB
    P.SetInterfaceColor(old.interfaceColor)
    P.InitLanguage()
    P.BlacklistBanner.setOpacity(old.bannerOpacity)
    P.db.bannerPosition=P.BlacklistBanner.savedPosition(old.bannerPosition)
    UIParent:HookScript("OnSizeChanged",P.BlacklistBanner.resize)
    if P.manual then
        for _,key in ipairs({"automaticTarget","automaticMouseover","relogRefresh"}) do
            if old[key]==false then P.db[key]=false end
        end
        if type(old.automaticNameplates)=="boolean" then P.db.automaticNameplates=old.automaticNameplates end
        P.db.skipDeleteConfirmation=skipDeleteConfirmation
        P.db.guildBlacklistDefaultWithNote=old.guildBlacklistDefaultWithNote==true
        -- Retain the R48 key for saves that already have a default mute preference.
        P.db.muteBlacklistWhispers=old.muteBlacklistWhispers==true
        P.db.muteBlacklistPartyRaid=old.muteBlacklistPartyRaid==true
        P.db.muteBlacklistCityTrade=old.muteBlacklistCityTrade==true
        P.db.muteBlacklistGuild=old.muteBlacklistGuild==true
        P.db.tooltipMembership=old.tooltipMembership~=false
        P.manual.alertSound.setVolume(old.alertSoundVolume==nil and 100 or old.alertSoundVolume)
        P.manual.alertSound.setEnabled(old.alertSoundEnabled==nil or old.alertSoundEnabled==true)
        P.manual.batchRefresh.restore(old.refreshReadyAt)
        P.manual.init()
        P.manual.encounterLedger.init(WhowhoEncounterDB)
    end
    P.initialized=true
    if P.manual then
        P.BlacklistBanner.installSightings()
        P.manual.playerEvidence.install()
        P.manual.playerMenu.install()
        P.manual.playerTooltip.install()
        P.manual.chatMute.install()
        P.GuildBlacklist.install()
        if P.manual.store then
            local canMonitor=register("PLAYER_LEAVING_WORLD") and register("PLAYER_REGEN_DISABLED")
            local enteringWorld=canMonitor and register("PLAYER_ENTERING_WORLD")
            if canMonitor and P.manual.whoLookup.install(enteringWorld) then
                whoEnteringWorld=enteringWorld
            else
                unregister("PLAYER_LEAVING_WORLD")
                unregister("PLAYER_REGEN_DISABLED")
                unregister("PLAYER_ENTERING_WORLD")
            end
        end
        if P.manual.invite.install(P.Shell.RefreshFriends) then
            for _, event in ipairs({"PLAYER_TARGET_CHANGED","UPDATE_MOUSEOVER_UNIT"}) do
                inviteEvents[event]=register(event)
            end
        end
    end
    if automaticTarget then P.manual.setAutomaticTarget(true) end
    if automaticMouseover then P.manual.setAutomaticMouseover(true) end
    if automaticNameplates then P.manual.setAutomaticNameplates(true) end
    if relogRefresh and P.manual.setRelogRefresh(true) and (whoEnteringWorld or register("PLAYER_ENTERING_WORLD")) then
        relogCycle={pending={Guild=true,["Recent Allies"]=true}, revision={Guild=0,["Recent Allies"]=0}}
    end
    P.Launcher.Create()
end
function P.Toggle()
    -- A user-invoked slash command can expose the read-only error even when
    -- the secret checker is absent and the event's addon name cannot be read.
    if P.manual and not P.addonLoaded and type(issecretvalue)~="function" then P.addonLoaded=true end
    P.Init(); if P.initialized then P.Shell.Toggle() end
end
SLASH_WHOWHOPREVIEW1="/wwpreview"
SlashCmdList.WHOWHOPREVIEW=function() P.Toggle() end
local function finishRelog(run,source)
    run.pending[source]=nil
    for event,provider in pairs(relogEvents) do
        if provider==source then unregister(event) end
    end
end
local function scanRelog(run)
    if run.scanning then run.wake=true; return end
    run.scanning=true
    local changed=false
    -- A nested signal can wake the other provider once. A consumed snapshot is never retried.
    for _=1,2 do
        run.wake=false
        for _,source in ipairs(relogSources) do
            if relogCycle~=run then break end
            if run.pending[source] then
                local revision=run.revision[source]
                local ok,done,applied=pcall(P.manual.relogRefresh.attempt,source,function()
                    return relogCycle==run and run.revision[source]==revision
                end)
                if ok and applied then changed=true end
                if relogCycle==run and (not ok or done) then finishRelog(run,source) end
            end
        end
        if not run.wake or relogCycle~=run then break end
    end
    run.scanning=false
    if relogCycle==run and not next(run.pending) then stopRelog() end
    if changed then
        P.manual.refresh()
        P.Shell.RefreshFriends()
    end
end
local function onRelogEvent(event,initialLogin,reloadingUI)
    local run=relogCycle
    if not run then return end
    if event=="PLAYER_ENTERING_WORLD" then
        local readable=P.manual.nativeRead.readable
        if run.started or not (readable(initialLogin) and initialLogin==true
            or readable(reloadingUI) and reloadingUI==true) then return end
        if not whoEnteringWorld then unregister(event) end
        for name in pairs(relogEvents) do
            if relogCycle~=run then return end
            register(name)
        end
        if relogCycle~=run then return end
        register("PLAYER_REGEN_ENABLED")
        if relogCycle~=run then return end
        run.started=true
    elseif run.started then
        -- A guildless character never becomes ready. IsInGuild is trusted only once clubs have loaded.
        if event=="INITIAL_CLUBS_LOADED" and P.manual.nativeRead.read(IsInGuild)==false then
            if relogCycle~=run then return end
            finishRelog(run,"Guild")
        end
        local source=relogEvents[event]
        for _,provider in ipairs(relogSources) do
            if run.pending[provider] and (not source or source==provider) then
                run.revision[provider]=run.revision[provider]+1
            end
        end
    else return end
    scanRelog(run)
end
loader=CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent",function(self,event,addon,extra)
    if P.manual and (event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_REGEN_DISABLED") then
        P.manual.whoLookup.cancel(event=="PLAYER_REGEN_DISABLED")
        return
    end
    if P.manual and event=="PLAYER_TARGET_CHANGED" then
        if inviteEvents[event] then P.manual.invite.invalidate() end
        if P.manual.targetCheck.onTargetChanged() or inviteEvents[event] then P.Shell.RefreshFriends() end
        return
    end
    if P.manual and event=="UPDATE_MOUSEOVER_UNIT" then
        if inviteEvents[event] then P.manual.invite.invalidate(); P.Shell.RefreshFriends() end
        P.manual.targetCheck.onMouseoverChanged(P.Shell.RefreshFriends)
        return
    end
    if P.manual and (event=="NAME_PLATE_UNIT_ADDED" or event=="NAME_PLATE_UNIT_REMOVED") then
        local A,B=P.manual,P.BlacklistBanner
        local active,generation=A.automaticNameplatesEnabled()
        if not active then return end
        local token=A.unitReader.nameplateToken(addon) and addon
        if not token then nameplateDispatch={} end
        local owner={}
        nameplateDispatch[token]=owner
        -- A nested removal or reuse retires this event before the second observer reads it.
        local changed=A.nameplateCheck.onEvent(event,addon)
        local enabled,currentGeneration=A.automaticNameplatesEnabled()
        if enabled and generation==currentGeneration and nameplateDispatch[token]==owner and B.sightingsNameplateEvent then
            B.sightingsNameplateEvent(event,addon)
        end
        if nameplateDispatch[token]==owner then nameplateDispatch[token]=nil end
        if changed then P.Shell.RefreshFriends() end
        return
    end
    if P.manual and (event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_REGEN_ENABLED" or relogEvents[event]) then
        if event=="PLAYER_ENTERING_WORLD" then P.manual.whoLookup.enterWorld() end
        onRelogEvent(event,addon,extra)
        return
    end
    if P.manual then addon=P.manual.text(addon) end
    if addon==addonName then P.addonLoaded=true; P.Init(); self:UnregisterEvent("ADDON_LOADED") end
end)
