-- Guarded Guild reads shared by individual checks and roster refresh.
local A = WhowhoPreview.manual
local read, readable, safeTable, member = A.nativeRead.read, A.nativeRead.readable, A.nativeRead.safeTable, A.nativeRead.member

local function online(row)
    local presence, enums = member(row, "presence"), member(Enum, "ClubMemberPresence")
    if presence == nil then return nil end
    local on, away, busy, off = member(enums, "Online"), member(enums, "Away"), member(enums, "Busy"), member(enums, "Offline")
    if on ~= nil and presence == on or away ~= nil and presence == away or busy ~= nil and presence == busy then return true end
    if off ~= nil and presence == off then return false end
end

local function memberIds(api, club)
    local ids = read(member(api, "GetClubMembers"), club)
    if not safeTable(ids) then return nil end
    local ok, count = pcall(function() return #ids end)
    if not ok or not readable(count) or type(count) ~= "number" or count < 1 or count >= math.huge or count % 1 ~= 0 then return nil end
    local keysOK, keys = pcall(function()
        local n = 0
        for key in pairs(ids) do
            if not readable(key) or type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > count then return nil end
            n = n + 1
        end
        return n
    end)
    if not keysOK or keys ~= count then return nil end
    return ids, count
end

local function validId(id)
    return (type(id) == "number" and id > 0 and id < math.huge and id % 1 == 0)
        or (type(id) == "string" and id ~= "")
end

local function absenceSnapshot(api, club, name, guid)
    local ids, count = memberIds(api, club)
    if not ids then return end
    local rows, names, guids = {}, {}, {}
    for i=1,count do
        local id = member(ids, i)
        if not validId(id) or rows[id] then return nil end
        local row = read(member(api, "GetMemberInfo"), club, id)
        local rowName, rowGuid = member(row, "name"), member(row, "guid")
        if type(rowName) ~= "string" or not rowName:match("^%S+%s+%S+$") or type(rowGuid) ~= "string" or rowGuid == ""
            or rowName == name or rowGuid == guid or names[rowName] or guids[rowGuid] then return nil end
        rows[id] = {name=rowName, guid=rowGuid}
        names[rowName], guids[rowGuid] = true, true
    end
    return {count=count, rows=rows}
end

local function captureAbsence(api, club, name, guid)
    local first = absenceSnapshot(api, club, name, guid)
    if not first then return nil end
    return function()
        local current = absenceSnapshot(api, club, name, guid)
        if not current or current.count ~= first.count then return false end
        for id, row in pairs(first.rows) do
            local other = current.rows[id]
            if not other or other.name ~= row.name or other.guid ~= row.guid then return false end
        end
        return true
    end
end

local function capturePlayer(name, owns)
    if not WhowhoPreview.CharacterName.IsComplete(name) then return end
    local playerGuid = A.unitReader.playerGuid
    local api = C_Club
    local club = read(member(api, "GetGuildClubId"))
    if not validId(club) then return end
    local function ready()
        local lockdown = member(C_ChatInfo, "InChatMessagingLockdown")
        return owns() and read(InCombatLockdown) == false and (not lockdown or read(lockdown) == false)
            and read(member(api, "AreMembersReady"), club) == true
            and read(member(api, "GetGuildClubId")) == club and owns()
            and safeTable(C_Club) and rawequal(C_Club, api)
    end
    local function row(id)
        return read(member(api, "GetMemberInfo"), club, id)
    end
    local function match()
        if not ready() then return end
        local ids, count = memberIds(api, club)
        if not ids then return end
        local selected, guid, classID, level, state
        local seenIds, guidCounts = {}, {}
        for i=1,count do
            local id = member(ids, i)
            if not validId(id) or seenIds[id] then return end
            seenIds[id] = true
            local entry = row(id)
            local rowName, rowGuid = member(entry, "name"), member(entry, "guid")
            if type(rowName) ~= "string" or rowName == "" then return end
            if playerGuid(rowGuid) then guidCounts[rowGuid] = (guidCounts[rowGuid] or 0) + 1 end
            if rowName == name then
                if selected or not playerGuid(rowGuid) then return end
                selected, guid, classID, level = id, rowGuid, member(entry, "classID"), member(entry, "level")
                state = online(entry)
            end
        end
        if selected and guidCounts[guid] == 1 and ready() then return selected, guid, classID, level, state end
    end
    local id, guid, classID, level, state = match()
    if not id then return end
    local class
    if type(classID) == "number" and classID >= 1 and classID < math.huge and classID % 1 == 0 then
        local token = member(read(member(C_CreatureInfo, "GetClassInfo"), classID), "classFile")
        if type(token) == "string" and token:match("^[A-Z]+$") and member(RAID_CLASS_COLORS, token) then class = token end
    end
    local function positiveLevel(value)
        if type(value) == "number" and value >= 1 and value < math.huge and value % 1 == 0 then return value end
    end
    level = positiveLevel(level)
    local at = read(GetServerTime)
    if type(at) ~= "number" or not (at >= 0 and at < math.huge) then return end
    local function current()
        if not ready() then return false end
        local entry = row(id)
        return member(entry, "name") == name and member(entry, "guid") == guid
            and (not class or member(entry, "classID") == classID)
            and (not level or member(entry, "level") == level) and online(entry) == state and ready()
    end
    local function validate()
        local checkedId, checkedGuid, checkedClass, checkedLevel, checkedState = match()
        return checkedId == id and checkedGuid == guid and (not class or checkedClass == classID)
            and (not level or checkedLevel == level) and checkedState == state and current()
    end
    if current() then
        return {name=name, class=class, level=level, online=state, guid=guid, at=at, current=current, validate=validate}
    end
end

A.guildRosterRead = {online=online, captureAbsence=captureAbsence, capturePlayer=capturePlayer}
