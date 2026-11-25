-- Mark the primary world tooltip only when it belongs to the current mouseover player.
local P = WhowhoPreview
local A = P.manual
local read, member, safeTable, readable = A.nativeRead.read, A.nativeRead.member, A.nativeRead.safeTable, A.nativeRead.readable
local playerTooltip = {}
A.playerTooltip = playerTooltip

local labels = {
    friend = {"Friend", P.colors.online, P.colors.tooltipFriendRim},
    blacklist = {"Blacklisted", P.colors.deleteGlyph, P.colors.tooltipBlacklistRim},
}
local installed, registered, rendering
local rim, rimReady, rimAttempted, rimOwner, rimLayout
local rimRevision = 0
local rimPieces = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
}

local function clearRim()
    rimRevision = rimRevision + 1
    rimOwner = nil
    if rim then pcall(rim.Hide, rim) end
end

function playerTooltip.enabled()
    return P.db.tooltipMembership == true
end

function playerTooltip.available()
    return registered == true
end

function playerTooltip.setEnabled(value)
    if type(value) ~= "boolean" or not registered then return false end
    P.db.tooltipMembership = value
    if not value then clearRim() end
    return true
end

local function blacklistText(text, ids)
    if not A.validReasons(ids) then return text end
    text = text .. " · " .. A.reasonLabel(ids[1])
    if #ids > 1 then text = text .. (" (+%d)"):format(#ids - 1) end
    return text
end

local function isPrimary(tooltip, data)
    local primary = read(member(tooltip, "GetPrimaryTooltipData"), tooltip)
    return safeTable(primary) and safeTable(data) and rawequal(primary, data)
end

local function safeTooltip(tooltip)
    return read(InCombatLockdown) == false and read(member(tooltip, "IsForbidden"), tooltip) == false
end

local function canAnchor(frame)
    return read(member(frame, "IsAnchoringRestricted"), frame) == false
        and read(member(frame, "IsAnchoringSecret"), frame) == false
end

local function rimSource(tooltip, data)
    if not safeTooltip(tooltip) or not canAnchor(tooltip) then return end
    local info = read(member(tooltip, "GetPrimaryTooltipInfo"), tooltip)
    local owner = member(info, "tooltipData")
    if member(info, "getterName") ~= "GetWorldCursor" or not safeTable(owner)
        or not safeTable(data) or not rawequal(owner, data) then return end
    local slice = member(tooltip, "NineSlice")
    if not canAnchor(slice) then return end
    local layout = read(member(slice, "GetFrameLayoutType"), slice)
    if layout == "TooltipDefaultLayout" or layout == "TooltipDefaultDarkLayout" then return slice, layout end
end

local function createRim(tooltip)
    rimAttempted = true
    local hook = member(tooltip, "HookScript")
    if not readable(hooksecurefunc) or type(hooksecurefunc) ~= "function"
        or type(member(tooltip, "ClearHandlerInfo")) ~= "function"
        or read(hook, tooltip, "OnHide", clearRim) ~= true
        or read(hook, tooltip, "OnTooltipCleared", clearRim) ~= true
        or not pcall(hooksecurefunc, tooltip, "ClearHandlerInfo", clearRim) then return end

    local frame = read(CreateFrame, "Frame", nil, tooltip)
    if not safeTable(frame) then return end
    rim = frame
    frame:Hide()
    frame:EnableMouse(false)
    frame:EnableMouseWheel(false)
    frame:SetScript("OnEvent", clearRim)
    rimReady = read(member(frame, "RegisterEvent"), frame, "PLAYER_REGEN_DISABLED") == true
end

local function ownsRim(tooltip, owner, revision)
    local store, region, data = owner.store, owner.region, owner.data
    if A.store ~= store or A.region ~= region or revision ~= rimRevision or not playerTooltip.enabled() then return false end
    local ledger = A.encounterLedger
    local now = owner.membership == "blacklist" and ledger.now() or nil
    local name, guid = A.playerAddIdentity("mouseover", store, region)
    if name ~= owner.name or guid ~= owner.guid then return false end
    local slice, layout = rimSource(tooltip, data)
    if not rawequal(slice, owner.slice) or layout ~= owner.layout or not isPrimary(tooltip, data)
        or member(data, "guid") ~= guid or read(GetCurrentRegion) ~= region then return false end
    local record = store.find(region, name, guid)
    return record and record.id == owner.id and record.membership == owner.membership
        and record.identityState == "resolved"
        and (owner.membership ~= "blacklist" or ledger.matchesBlacklistGuid(record, guid, now))
        and A.store == store and A.region == region and revision == rimRevision and playerTooltip.enabled()
end

local function showRim(tooltip, owner, color, revision)
    if revision ~= rimRevision or not playerTooltip.enabled() then return end
    local slice, layout = rimSource(tooltip, owner.data)
    if not slice then return end
    owner.slice, owner.layout = slice, layout
    local level = read(member(slice, "GetFrameLevel"), slice)
    if type(level) ~= "number" or not (level >= 0 and level < math.huge) then return end
    if rimLayout ~= layout then
        local apply = member(NineSliceUtil, "ApplyLayoutByName")
        if type(apply) ~= "function" then return end
        if not rimAttempted then createRim(tooltip) end
        if not rimReady or revision ~= rimRevision or not pcall(apply, rim, layout) then return end
        local disableSharpening = member(NineSliceUtil, "DisableSharpening")
        if type(disableSharpening) == "function" then pcall(disableSharpening, rim) end
    end
    local center = member(rim, "Center")
    local hide = member(center, "Hide")
    if type(hide) ~= "function" then return end
    hide(center)
    for _, name in ipairs(rimPieces) do
        local piece = member(rim, name)
        local atlas = read(member(piece, "GetAtlas"), piece)
        local tint, desaturate = member(piece, "SetVertexColor"), member(piece, "SetDesaturated")
        if type(atlas) ~= "string" or atlas == "" or type(tint) ~= "function" or type(desaturate) ~= "function" then return end
        desaturate(piece, true)
        tint(piece, color[1], color[2], color[3], 1)
    end
    rimLayout = layout
    rim:SetFrameLevel(level + 1)
    rim:ClearAllPoints()
    rim:SetAllPoints(slice)
    if not ownsRim(tooltip, owner, revision) then return end
    rimOwner = owner
    rim:Show()
    if revision ~= rimRevision then clearRim() end
end

local function render(tooltip, data, revision)
    if not playerTooltip.enabled() or not safeTooltip(tooltip) or not isPrimary(tooltip, data) then return end

    local store, region = A.store, A.region
    local name, guid = A.playerAddIdentity("mouseover", store, region)
    if not name or member(data, "guid") ~= guid then return end

    local record = store.find(region, name, guid)
    local label = record and record.identityState == "resolved" and labels[record.membership]
    if not label then return end
    local ledger = A.encounterLedger
    local now = record.membership == "blacklist" and ledger.now() or nil

    local addLine = member(tooltip, "AddLine")
    if type(addLine) ~= "function" or not safeTooltip(tooltip)
        or read(GetCurrentRegion) ~= region or not A.unitReader.identitySafe("mouseover")
        or A.unitReader.guid("mouseover") ~= guid
        or not isPrimary(tooltip, data) or member(data, "guid") ~= guid
        or A.store ~= store or A.region ~= region or revision ~= rimRevision or not playerTooltip.enabled() then return end
    local color = label[2]
    local text = P.L(label[1])
    if record.membership == "blacklist" then
        if not ledger.matchesBlacklistGuid(record,guid,now) then return end
        text = blacklistText(text, record.reasonIds)
    end
    local owner = {store=store, region=region, data=data, name=name, guid=guid, id=record.id, membership=record.membership}
    addLine(tooltip, text, color[1], color[2], color[3])
    showRim(tooltip, owner, label[3], revision)
end

local function annotate(tooltip, data)
    if not registered or not safeTable(tooltip) or not rawequal(tooltip, GameTooltip) or rendering then return end
    rendering = true
    local ok = pcall(function()
        local owner = rimOwner
        if owner and safeTable(data) and safeTable(owner.data) and not rawequal(owner.data, data)
            and ownsRim(tooltip, owner, rimRevision) and rimOwner == owner then return end
        clearRim()
        render(tooltip, data, rimRevision)
    end)
    rendering = false
    if not ok then clearRim() end
end

function playerTooltip.install()
    if installed or not A.store then return end
    local register = member(TooltipDataProcessor, "AddTooltipPostCall")
    local unitType = member(member(Enum, "TooltipDataType"), "Unit")
    if type(register) ~= "function" or type(unitType) ~= "number" then return end
    installed = true
    registered = pcall(register, unitType, annotate)
end
