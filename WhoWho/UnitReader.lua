local A = WhowhoPreview.manual
local read, readable, member = A.nativeRead.read, A.nativeRead.readable, A.nativeRead.member
local unit = {}
A.unitReader = unit
function unit.name(token)
    return read(GetUnitName, token, true)
end
function unit.guid(token)
    return read(UnitGUID, token)
end
function unit.playerGuid(guid)
    return readable(guid) and type(guid) == "string" and guid:match("^Player%-%d+%-%x+$") ~= nil
end
function unit.nameplateToken(token)
    return readable(token) and type(token) == "string" and token:match("^nameplate[1-9]%d*$") ~= nil
end
local function frameRead(frame, method)
    return read(read(function() return frame[method] end), frame)
end
local function visiblePlate(frame)
    if (A.nativeRead.safeTable(frame) or readable(frame) and type(frame) == "userdata")
        and frameRead(frame, "IsForbidden") == false then
        local visible=frameRead(frame, "IsVisible")
        if type(visible)=="boolean" then return visible end
    end
end
function unit.nameplateAvailable()
    return type(member(C_NamePlate, "GetNamePlateForUnit")) == "function"
end
function unit.nameplateFrames()
    local frames = read(member(C_NamePlate, "GetNamePlates"))
    if A.nativeRead.safeTable(frames) then return frames end
end
function unit.nameplateFrame(token)
    if not unit.nameplateToken(token) then return end
    local getFrame=member(C_NamePlate, "GetNamePlateForUnit")
    if type(getFrame)~="function" then return end
    local ok,frame=pcall(getFrame,token,false)
    if not ok or not readable(frame) then return end
    if frame==nil then return nil,false end
    local visible=visiblePlate(frame)
    if visible then return frame,true end
    return nil,visible
end
function unit.nameplateUnit(frame)
    if not visiblePlate(frame) then return end
    local token = frameRead(frame, "GetUnit")
    if unit.nameplateToken(token) then return token end
end
function unit.identitySafe(token)
    return read(member(C_Secrets, "ShouldUnitIdentityBeSecret"), token) == false
end
function unit.worldSource(token)
    if not readable(token) then return end
    if token == "target" then return "Target" end
    if token == "mouseover" then return "Mouseover" end
    if unit.nameplateToken(token) then return "Nameplate" end
end
local function playerIdentity(token, owns, rechecking)
    if not readable(token) or type(token) ~= "string" or token == "player" or (owns and not owns()) then return end
    local exists = read(UnitExists, token)
    if exists == false then return nil, nil, "absent" end
    if exists ~= true or (owns and not owns()) then return nil, nil, "unavailable" end
    local player = read(UnitIsPlayer, token)
    if player == false then return nil, nil, "non-player" end
    if player ~= true or (owns and not owns()) then return nil, nil, "unavailable" end
    local self = read(UnitIsUnit, token, "player")
    if self == true then return nil, nil, "self" end
    if self ~= false or (owns and not owns()) then return nil, nil, "unavailable" end
    if not unit.identitySafe(token) then return nil, nil, "unsafe" end
    if owns and not owns() then return end
    local first, second = unit.guid, unit.name
    if rechecking then first, second = second, first end
    local initial = first(token)
    if owns and not owns() then return end
    local final = second(token)
    if owns and not owns() then return end
    local name, guid = final, initial
    if rechecking then name, guid = initial, final end
    if not WhowhoPreview.CharacterName.IsComplete(name) or type(guid) ~= "string" or guid == "" then
        return nil, nil, "identity"
    end
    return name, guid
end
function unit.playerIdentity(token, owns)
    return playerIdentity(token, owns)
end
function unit.samePlayer(token, name, guid, owns)
    -- Read the GUID last so a token replaced during the name read cannot inherit the old identity.
    local current, currentGuid = playerIdentity(token, owns, true)
    return current ~= nil and current == name and currentGuid == guid
end
function unit.playerPlate(token, expectedFrame)
    local frame = unit.nameplateFrame(token)
    if frame and (not expectedFrame or rawequal(frame, expectedFrame)) then return frame end
end
function unit.faction(token)
    local tag = read(UnitFactionGroup, token)
    if tag == "Alliance" or tag == "Horde" then return tag end
end
function unit.otherRuleset(token)
    local rule = member(member(Enum, "PhaseReason"), "RuleSet")
    return type(rule) == "number" and read(UnitPhaseReason, token) == rule
end
local function classFilename(value)
    return readable(value) and type(value)=="string" and value:match("^[A-Z]+$") and value or nil
end
function unit.class(token)
    if type(UnitClass) == "function" then
        local ok, _, value = pcall(UnitClass, token)
        local class = ok and classFilename(value)
        if class then return class end
    end
    return classFilename(read(UnitClassBase, token))
end
local function level(token)
    local value = read(UnitLevel, token)
    if type(value) == "number" and value == value and value >= 1 and value < math.huge and value % 1 == 0 then return value end
end
function unit.metadata(token, canRead)
    if canRead and not canRead() then return nil, nil end
    local class = unit.class(token)
    if canRead and not canRead() then return nil, nil end
    return class, level(token)
end
function unit.playerMetadata(token, owns, fields)
    local function safe()
        return (not owns or owns()) and read(InCombatLockdown) == false and unit.identitySafe(token)
            and (not owns or owns())
    end
    local metadata = {}
    if (not fields or fields.class) and safe() then metadata.class = unit.class(token) end
    if (not fields or fields.level) and safe() then metadata.level = level(token) end
    if (not fields or fields.faction) and safe() then metadata.faction = unit.faction(token) end
    if (not fields or fields.otherRuleset) and safe() then metadata.otherRuleset = unit.otherRuleset(token) end
    if safe() then return metadata end
end
