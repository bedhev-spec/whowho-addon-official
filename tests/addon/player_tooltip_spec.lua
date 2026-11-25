-- Exercise native tooltip callback ownership against the manual TOC and real address book.
local root = arg[1] or "."
local H = dofile(root .. "/tests/addon/harness.lua")
local config = {region=3, time=100}
local p, s, e = H.fresh(root, nil, nil, config)
local name, guid, isPlayer, safe, combat = "Élodie Pâlemont", "g1", true, true, false
local callback, primary, forbidden
local lines, registrations, nameReads = {}, 0, 0
e.Enum = {TooltipDataType={Unit=2}}
e.TooltipDataProcessor = {AddTooltipPostCall=function(kind, handler)
    assert(kind == 2)
    registrations = registrations + 1
    callback = handler
end}
e.UnitExists = function(token) return token == "mouseover" end
e.UnitIsPlayer = function() return isPlayer end
e.InCombatLockdown = function() return combat end
e.C_Secrets = {ShouldUnitIdentityBeSecret=function() return not safe end}
e.GetUnitName = function(token, complete)
    assert(token == "mouseover" and complete and safe and isPlayer and not combat)
    nameReads = nameReads + 1
    return name
end
e.UnitGUID = function() return guid end
local tooltip = e.GameTooltip
local nativeHook = tooltip.HookScript
tooltip.IsForbidden = function() return forbidden or false end
tooltip.GetPrimaryTooltipData = function() return primary end
local chromeCalls = 0
local function chrome() chromeCalls = chromeCalls+1 end
tooltip.GetPrimaryTooltipInfo = function() end
tooltip.IsAnchoringRestricted = function() return false end
tooltip.IsAnchoringSecret = function() return false end
tooltip.HookScript = chrome
tooltip.AddLine = function(self, label, r, g, b)
    assert(self == e.GameTooltip)
    lines[#lines+1] = {label, r, g, b}
    callback(self, primary)
end
e.hooksecurefunc = function(target)
    if target == tooltip then chrome() end
end

s:event("ADDON_LOADED", "WhoWho")
p.manual.playerTooltip.install()
assert(registrations == 1)
local preference = p.manual.playerTooltip
assert(preference.available() and preference.enabled() and p.db.tooltipMembership == true)
local store = p.manual.store
local function add(fullName, membership, resolved, savedGuid, region)
    return assert(store.add({
        fullName=fullName, membership=membership,
        identityState=resolved and "resolved" or "unresolved",
        region=resolved and (region or 3) or nil, guid=savedGuid,
        reasonIds=membership=="blacklist" and {"griefing"} or nil,
    }, 100))
end
local friend = add(name, "friend", true, guid)
local blacklisted = add("Alden Vale", "blacklist", true, "g2")
add("Far North", "friend", true, "g9", 4)
add("Élodie", "friend", false)

local function show(data, frame, usePrimary)
    lines = {}
    primary = data
    callback(frame or tooltip, usePrimary == false and {guid=data.guid} or data)
    return lines[1]
end
local function expect(label, color)
    local line = show({guid=guid})
    assert(line and #lines == 1 and line[1] == label)
    for index=1,3 do assert(line[index+1] == color[index]) end
end
expect("Friend", p.colors.online)
assert(#tooltip.children == 0)
expect("Friend", p.colors.online) -- native rebuild starts with a fresh set of lines
assert(not show({guid="g2"})) -- a different tooltip cannot borrow mouseover identity
assert(not show({guid=guid}, {}))
assert(not show({guid=guid}, tooltip, false))
assert(not show({guid=s.secret}))
assert(not show(s.secret))
assert(not show({})) -- primary data without a unit identity
name, guid = "Alden Vale", "g2"
expect("Blacklisted · Griefing", p.colors.deleteGlyph)
assert(store.edit(blacklisted.id, {reasonIds={"ninja_looting", "griefing", "other"}}, 100))
expect("Blacklisted · Ninja looting (+2)", p.colors.deleteGlyph)
local find = store.find
store.find = function(...)
    local record = find(...)
    if record then record.reasonIds = nil end
    return record
end
expect("Blacklisted", p.colors.deleteGlyph) -- older entries may lack reasons
store.find = find
name, guid = "Unknown Person", "g2"
assert(not show({guid=guid})) -- saved GUID alone cannot resolve a different name
name, guid = "Alden Vale", "different"
assert(not show({guid=guid})) -- same name with conflicting GUID
name, guid = "Name Only", "first"
local nameOnly = add(name, "blacklist", true)
expect("Blacklisted · Griefing", p.colors.deleteGlyph)
local ledger = p.manual.encounterLedger
local observation = assert(ledger.start({id=nameOnly.id,name=name,guid=guid},3,100))
ledger.observe(observation,true,false,0,"Durotar")
guid="replacement"
assert(not show({guid=guid}),"a different GUID cannot inherit the tooltip from an active observation")
ledger.stop(observation,0)
assert(not show({guid=guid}),"a different GUID cannot inherit the tooltip from retained history")
guid="first"
expect("Blacklisted · Griefing", p.colors.deleteGlyph)
guid="replacement"
local serverTime=e.GetServerTime
config.time=100+30*86400
e.GetServerTime=function() return nil end
assert(not show({guid=guid}),"unreadable current time keeps existing GUID evidence")
e.GetServerTime=serverTime
expect("Blacklisted · Griefing", p.colors.deleteGlyph)
assert(#e.WhowhoEncounterDB.regions[3]==1,"the expiry cutoff applies before the tooltip archive is physically trimmed")
config.time=100
name, guid = "Alden Vale", "g2"
forbidden = true; assert(not show({guid=guid})); forbidden = false
local before = nameReads
combat = true; assert(not show({guid=guid})); combat = false
safe = false; assert(not show({guid=guid})); safe = true
isPlayer = false; assert(not show({guid=guid})); isPlayer = true
assert(nameReads == before)
name, guid = "Élodie", "g1"; assert(not show({guid=guid}))
name, guid = "Far North", "g9"; assert(not show({guid=guid}))
name, guid = "Élodie Pâlemont", "g1"
assert(store.move(friend.id, "blacklist", 100, {"griefing"}))
expect("Blacklisted · Griefing", p.colors.deleteGlyph)
assert(store.delete(friend.id, 3, name, guid))
assert(not show({guid=guid}))
name, guid = "Alden Vale", "g2"
local addLine = tooltip.AddLine
tooltip.AddLine = function() error("unavailable") end
assert(not show({guid=guid}))
tooltip.AddLine = addLine
expect("Blacklisted · Ninja looting (+2)", p.colors.deleteGlyph)
local reads = 0
e.UnitGUID = function()
    reads = reads + 1
    return reads == 3 and "replaced" or guid
end
assert(not show({guid=guid}))
e.UnitGUID = function() return guid end
reads = 0
e.UnitGUID = function()
    reads = reads + 1
    if reads == 3 then primary = {guid="unrelated-tooltip"} end
    return guid
end
assert(not show({guid=guid})) -- tooltip replacement during final identity read
e.UnitGUID = function() return guid end
config.region = 4
assert(not show({guid=guid}))
config.region = 3

expect("Blacklisted · Ninja looting (+2)", p.colors.deleteGlyph)
callback(tooltip, {guid="appended"})
assert(#lines == 1 and chromeCalls == 0 and #tooltip.children == 0)
assert(store.move(blacklisted.id, "friend", 100))
expect("Friend", p.colors.online)

e.SlashCmdList.WHOWHOPREVIEW()
local shell = p.Shell
shell.nav.settings:Click()
local toggle = shell.tooltipMembership
assert(shell.settingsTabs.alerts.selected and toggle:IsVisible() and toggle:IsEnabled() and toggle:GetChecked())
assert(shell.testBannerButton:IsVisible() and not shell.automaticTarget:IsVisible() and not shell.scaleSlider:IsVisible())
shell.settingsTabs.friends:Click()
assert(shell.automaticTarget:IsVisible() and shell.automaticMouseover:IsVisible()
    and not shell.automaticNameplates:IsVisible() and shell.relogRefresh:IsVisible())
assert(not toggle:IsVisible() and not shell.testBannerButton:IsVisible() and not shell.scaleSlider:IsVisible())
shell.settingsTabs.general:Click()
assert(shell.scaleSlider:IsVisible() and shell.skipDeleteConfirmation:IsVisible()
    and shell.automaticNameplates:IsVisible())
assert(not shell.automaticTarget:IsVisible() and not toggle:IsVisible())
shell.settingsTabs.alerts:Click()
expect("Friend", p.colors.online)
toggle:Click()
before = nameReads
assert(not toggle:GetChecked() and toggle.state:GetText() == "Off" and p.db.tooltipMembership == false)
assert(not show({guid=guid}) and nameReads == before)
assert(chromeCalls == 0 and #tooltip.children == 0)

local slice = e.CreateFrame("Frame", nil, tooltip)
local nativeEdge = slice:CreateTexture()
local nativeStatusBar = e.CreateFrame("StatusBar", nil, tooltip)
nativeEdge:SetVertexColor(.8,.7,.6,1)
tooltip.NineSlice = slice
slice:SetFrameLevel(3)
local layout, getter = "TooltipDefaultLayout", "GetWorldCursor"
local anchorSecret, clearHandler, reanchor
slice.GetFrameLayoutType = function() return layout end
slice.IsAnchoringRestricted = function() return false end
slice.IsAnchoringSecret = function() return anchorSecret == true end
tooltip.GetPrimaryTooltipInfo = function() return {getterName=getter,tooltipData=primary} end
tooltip.HookScript = nativeHook
tooltip.ClearHandlerInfo = function() end
e.hooksecurefunc = function(target, method, fn)
    assert(target==tooltip and method=="ClearHandlerInfo" and clearHandler==nil)
    clearHandler=fn
end
local owned
local function applyLayout(frame, layoutName)
    assert(frame~=slice and layoutName==layout)
    owned=frame
    for _,pieceName in ipairs({"TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
        "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center"}) do
        local piece=frame[pieceName] or frame:CreateTexture()
        piece.GetAtlas=function() return pieceName end
        piece.SetDesaturated=function(self,value) self.desaturated=value end
        frame[pieceName]=piece
    end
    if reanchor then reanchor() end
end
local function expectRim(r,g,b)
    assert(owned:IsShown() and owned:GetParent()==tooltip and owned.allPoints==slice and owned:GetFrameLevel()==4)
    assert(not owned.EnableMouseArgs[1] and not owned.EnableMouseWheelArgs[1] and not owned.Center:IsShown())
    assert(#owned.children==9)
    for _,piece in ipairs(owned.children) do
        if piece~=owned.Center then
            local color=piece.vertexColor
            assert(piece.desaturated and color[1]==r/255 and color[2]==g/255 and color[3]==b/255 and color[4]==1)
        end
    end
    assert(nativeEdge.vertexColor[1]==.8 and nativeStatusBar:GetParent()==tooltip and chromeCalls==0)
end

toggle:Click()
expect("Friend", p.colors.online) -- no NineSliceUtil: line fallback
assert(not owned)
e.NineSliceUtil = {ApplyLayoutByName=applyLayout}
anchorSecret=true; expect("Friend", p.colors.online); assert(not owned); anchorSecret=false
getter="GetUnit"; expect("Friend", p.colors.online); assert(not owned); getter="GetWorldCursor"
expect("Friend", p.colors.online); expectRim(142,230,155)
callback(tooltip, {guid="appended"})
assert(owned:IsShown() and #lines==1)
config.region=4
callback(tooltip, {guid="appended"})
assert(not owned:IsShown(), "the rim must clear when the native region changes")
config.region=3
expect("Friend", p.colors.online); expectRim(142,230,155)
guid="stale"
callback(tooltip, {guid="appended"})
assert(not owned:IsShown())
guid="g2"
expect("Friend", p.colors.online)
primary={guid="replacement"}
callback(tooltip, {guid="appended"})
assert(not owned:IsShown())
expect("Friend", p.colors.online); expectRim(142,230,155)
assert(store.move(blacklisted.id, "blacklist", 100, {"griefing"}))
callback(tooltip, {guid="appended"})
assert(not owned:IsShown(), "the old rim color must clear when the saved membership changes")
expect("Blacklisted · Griefing", p.colors.deleteGlyph); expectRim(255,149,138)
forbidden=true; assert(not show({guid=guid}) and not owned:IsShown()); forbidden=false
expect("Blacklisted · Griefing", p.colors.deleteGlyph); expectRim(255,149,138)
isPlayer=false; assert(not show({guid=guid}) and not owned:IsShown()); isPlayer=true
expect("Blacklisted · Griefing", p.colors.deleteGlyph)
assert(not show({}) and not owned:IsShown())
for _,event in ipairs({"OnHide", "OnTooltipCleared", "PLAYER_REGEN_DISABLED", "ClearHandlerInfo"}) do
    expect("Blacklisted · Griefing", p.colors.deleteGlyph); expectRim(255,149,138)
    if event=="ClearHandlerInfo" then clearHandler()
    elseif event=="PLAYER_REGEN_DISABLED" then s:event(event)
    else s:fire(tooltip,event) end
    assert(not owned:IsShown(), event)
end
layout="TooltipDefaultDarkLayout"
reanchor=function() assert(store.move(blacklisted.id, "friend", 100)) end
expect("Blacklisted · Griefing", p.colors.deleteGlyph)
assert(not owned:IsShown(), "a membership change during layout prevents stale rim publication")
assert(store.move(blacklisted.id, "blacklist", 100, {"griefing"}))
layout="TooltipDefaultLayout"
reanchor=function() clearHandler(); primary={guid="replaced"} end
expect("Blacklisted · Griefing", p.colors.deleteGlyph); assert(not owned:IsShown())
reanchor=nil
expect("Blacklisted · Griefing", p.colors.deleteGlyph); expectRim(255,149,138)
owned.BottomLeftCorner.GetAtlas=function() return nil end
expect("Blacklisted · Griefing", p.colors.deleteGlyph); assert(not owned:IsShown())
owned.BottomLeftCorner.GetAtlas=function() return "valid" end
expect("Blacklisted · Griefing", p.colors.deleteGlyph); expectRim(255,149,138)
assert(store.delete(blacklisted.id, 3, name, guid))
callback(tooltip, {guid="appended"})
assert(not owned:IsShown(), "the rim must clear when its saved record is deleted")
add(name, "blacklist", true, guid)
expect("Blacklisted · Griefing", p.colors.deleteGlyph); expectRim(255,149,138)
toggle:Click()
assert(not owned:IsShown() and not show({guid=guid}))

local q, sim, env = H.fresh(root, e.WhowhoPreviewDB, nil, config)
env.Enum, env.TooltipDataProcessor = e.Enum, e.TooltipDataProcessor
sim:event("ADDON_LOADED", "WhoWho")
env.SlashCmdList.WHOWHOPREVIEW()
q.Shell.nav.settings:Click()
local restored = q.Shell.tooltipMembership
assert(restored:IsEnabled() and not restored:GetChecked() and restored.state:GetText() == "Off")
assert(q.db.tooltipMembership == false and not q.manual.playerTooltip.enabled())
restored:Click()
assert(restored:GetChecked() and restored.state:GetText() == "On" and q.db.tooltipMembership == true)

local unavailable, unsupportedSim, unsupported = H.fresh(root, nil, nil, config)
unsupported.Enum = e.Enum
unsupported.TooltipDataProcessor = {AddTooltipPostCall=function() error("registration unavailable") end}
unsupportedSim:event("ADDON_LOADED", "WhoWho")
unsupported.SlashCmdList.WHOWHOPREVIEW()
unavailable.Shell.nav.settings:Click()
local disabled = unavailable.Shell.tooltipMembership
assert(disabled:IsVisible() and not disabled:IsEnabled() and not disabled.state:IsVisible())
assert(unavailable.db.tooltipMembership == true and not unavailable.manual.playerTooltip.available())
disabled:Click()
assert(unavailable.db.tooltipMembership == true)
assert(s.forbiddenCalls + sim.forbiddenCalls + unsupportedSim.forbiddenCalls == 0)
print("RESULT world tooltip membership, native chrome and Settings tabs passed in simulation")
