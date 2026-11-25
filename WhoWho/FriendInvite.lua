local P = WhowhoPreview
local A = P.manual
local read, member = A.nativeRead.read, A.nativeRead.member
local reader = A.unitReader
local invite = {}
A.invite = invite
local revision = 0
function invite.invalidate()
    revision = revision + 1
end
local function available()
    return type(member(C_PartyInfo,"InviteUnit")) == "function"
        and type(member(C_PartyInfo,"CanInvite")) == "function"
end
function invite.install(refresh)
    if not A.store or not available() then return false end
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent",function()
        invite.invalidate()
        refresh()
    end)
    for _, event in ipairs({"GROUP_ROSTER_UPDATE","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED"}) do
        pcall(frame.RegisterEvent,frame,event)
    end
    return true
end

local function live(store, region)
    return read(GetCurrentRegion) == region and read(InCombatLockdown) == false
        and A.store == store and A.region == region
end

local function snapshotUnit(unit, grouped)
    if read(UnitExists, unit) ~= true or read(UnitIsPlayer, unit) ~= true or not reader.identitySafe(unit) then return nil end
    local name, guid = reader.name(unit), reader.guid(unit)
    if not P.CharacterName.IsComplete(name) or type(guid) ~= "string" or guid == "" then return nil end
    local faction, otherRuleset = reader.faction(unit), reader.otherRuleset(unit)
    local raidIndex = read(UnitInRaid, unit)
    grouped = grouped or read(UnitInParty, unit) == true or (type(raidIndex) == "number" and raidIndex > 0)
    if read(UnitExists, unit) ~= true or read(UnitIsPlayer, unit) ~= true or not reader.identitySafe(unit)
        or reader.name(unit) ~= name or reader.guid(unit) ~= guid then return nil end
    return {name=name, guid=guid, faction=faction, otherRuleset=otherRuleset, grouped=grouped}
end

function invite.context()
    local context = {store=A.store, region=A.region, revision=revision, units={}}
    local api = C_PartyInfo
    context.send, context.canInvite = member(api, "InviteUnit"), member(api, "CanInvite")
    if type(context.send) ~= "function" or type(context.canInvite) ~= "function" or not context.store then
        context.issue = "Group invitations are unavailable."
        return context
    end
    if not live(context.store, context.region) then
        context.issue = "Invitations require a readable region outside combat."
        return context
    end
    context.self = A.currentCharacterName()
    if not context.self then context.issue = "Your character's name is unavailable."; return context end
    if read(context.canInvite) ~= true then
        context.issue = "You cannot invite anyone right now."
        return context
    end
    context.faction = reader.faction("player")
    local function capture(unit, grouped)
        local candidate = snapshotUnit(unit, grouped)
        if not candidate then return end
        local prior = context.units[candidate.name]
        if not prior then context.units[candidate.name] = candidate
        elseif prior.guid ~= candidate.guid then prior.conflict = true
        else prior.grouped = prior.grouped or candidate.grouped end
    end
    capture("target")
    capture("mouseover")
    local raid = read(IsInRaid)
    local count
    if raid == true then count = read(GetNumGroupMembers)
    elseif raid == false then count = read(GetNumSubgroupMembers) end
    if type(count) == "number" and count >= 0 and count % 1 == 0 and count <= (raid and 40 or 4) then
        for i=1,count do capture((raid and "raid" or "party") .. i, true) end
    end
    if not live(context.store, context.region) or context.revision ~= revision then
        context.issue = "Invitation context changed. Try again."
    end
    return context
end

function invite.issue(record, context)
    if not record or record.membership ~= "friend" or record.identityState=="unresolved"
        or not P.CharacterName.IsComplete(record.fullName) then
        return "A saved Friend with a complete name is required."
    end
    if context.issue then return context.issue end
    if record.region ~= context.region or A.store ~= context.store or context.revision ~= revision then
        return "Invitation context changed. Try again."
    end
    if record.fullName == context.self then return "You cannot invite your own character." end
    local unit = context.units[record.fullName]
    if not unit then return nil end
    local match = context.store.find(context.region, record.fullName, unit.guid)
    if unit.conflict or not match or match.id ~= record.id then return "Player identity changed. Check the saved Friend." end
    if unit.grouped then return "This player is already in your group." end
    if unit.faction and context.faction and unit.faction ~= context.faction then return "This player is in the other faction." end
    if unit.otherRuleset then return "This player is in another ruleset." end
end

local busy = false
local function request(record)
    local context = invite.context()
    local issue = invite.issue(record, context)
    if issue then return nil, issue end
    local comparison = read(strcmputf8i, record.fullName, context.self)
    if type(comparison) ~= "number" or comparison ~= comparison then return nil, "Your character's name is unavailable." end
    if comparison == 0 then return nil, "You cannot invite your own character." end
    if not live(context.store, context.region) or context.revision ~= revision then
        return nil, "Invitation context changed. Try again."
    end
    local current = context.store.get(record.id)
    if not current or current.membership ~= "friend" or current.region ~= record.region
        or current.fullName ~= record.fullName or current.guid ~= record.guid then
        return nil, "Saved Friend changed. Try again."
    end
    if not pcall(context.send, current.fullName) then return nil, "The client could not request the invitation." end
    return true, P.L("Invitation requested for %s.",current.fullName)
end

function invite.request(record)
    if busy then return nil, "An invitation request is in progress." end
    busy = true
    local ok, sent, message = pcall(request, record)
    busy = false
    if not ok then return nil, "The client could not request the invitation." end
    return sent, message
end
