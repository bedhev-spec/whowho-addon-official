-- Read-only identity and profile evidence for the realmless Forever client.
local P, A = WhowhoPreview, WhowhoPreview.manual
local read, readable, member = A.nativeRead.read, A.nativeRead.readable, A.nativeRead.member
local reader, isComplete = A.unitReader, P.CharacterName.IsComplete
local evidence = {}
A.playerEvidence = evidence

local function positiveInteger(value)
    if type(value) == "number" and value >= 1 and value < math.huge and value % 1 == 0 then return value end
end

local function timestamp(value)
    if type(value) == "number" and value >= 0 and value < math.huge then return value end
end

local function online(value)
    if type(value) == "boolean" then return value end
end

local function classToken(value)
    if readable(value) and type(value) == "string" and value:match("^[A-Z]+$") then return value end
end

local function classForID(id)
    if positiveInteger(id) then
        return classToken(member(read(member(C_CreatureInfo, "GetClassInfo"), id), "classFile"))
    end
end

function evidence.classForGuid(guid)
    local profile = GetPlayerInfoByGUID
    if not reader.playerGuid(guid) or not readable(profile) or type(profile) ~= "function" then return end
    local ok, _, class = pcall(profile, guid)
    if ok and classToken(class) and member(RAID_CLASS_COLORS, class) then return class end
end

local function context(store, region)
    return store and readable(region) and positiveInteger(region) and A.store == store and A.region == region
        and read(InCombatLockdown) == false and read(GetCurrentRegion) == region
        and read(InCombatLockdown) == false and A.store == store and A.region == region
end

local profileFields = {class=true, level=true, faction=true}

function evidence.readUnit(token, region, source, owns, expectedName, expectedGuid)
    if not readable(token) or type(token) ~= "string" or token == "" then return end
    if expectedName ~= nil and (not readable(expectedName) or not isComplete(expectedName))
        or expectedGuid ~= nil and not reader.playerGuid(expectedGuid) then return end
    local store = A.store
    local function owned()
        return (not owns or owns()) and context(store, region) and (not owns or owns())
    end
    if not owned() then return end
    local name, guid = reader.playerIdentity(token, owned)
    if not isComplete(name) or not reader.playerGuid(guid) or expectedName and name ~= expectedName
        or expectedGuid and guid ~= expectedGuid then return end
    local function current()
        return owned() and reader.samePlayer(token, name, guid, owned) and owned()
    end
    local profile = reader.playerMetadata(token, current, profileFields)
    local at = timestamp(read(GetServerTime))
    if not profile or not at or not current() then return end
    return {name=name, guid=guid, region=region, class=classToken(profile.class),
        level=positiveInteger(profile.level), faction=profile.faction, at=at, source=source,
        current=current, validate=current}
end

local function rosterEvidence(name, region, source, owns, readRow)
    if not owns() then return end
    local guid, class, level, state = readRow()
    if not reader.playerGuid(guid) or not owns() then return end
    local at = timestamp(read(GetServerTime))
    local function validate()
        if not owns() then return false end
        local currentGuid, currentClass, currentLevel, currentState = readRow()
        return currentGuid == guid and currentClass == class and currentLevel == level and currentState == state and owns()
    end
    if at and validate() then
        return {name=name, guid=guid, region=region, class=class, level=level, online=state, at=at,
            source=source, current=validate, validate=validate}
    end
end

local function recentEvidence(name, region, owns)
    local api = C_RecentAllies
    local function ready()
        return rawequal(api, C_RecentAllies) and read(member(api, "IsSystemSupported")) == true
            and read(member(api, "IsSystemEnabled")) == true and read(member(api, "IsRecentAllyDataReady")) == true
            and rawequal(api, C_RecentAllies)
    end
    return rosterEvidence(name, region, "Recent Allies", owns, function()
        if not ready() then return end
        local row = read(member(api, "GetRecentAllyByFullName"), name)
        local character = member(row, "characterData")
        local guid = member(character, "guid")
        if member(character, "fullName") == name and reader.playerGuid(guid) then
            local class, level = classForID(member(character, "classID")), positiveInteger(member(character, "level"))
            local state = online(member(member(row, "stateData"), "isOnline"))
            if ready() then return guid, class, level, state end
        end
    end)
end

local function nativeClass(label)
    local colors = RAID_CLASS_COLORS
    if type(label) ~= "string" or label == "" or not A.nativeRead.safeTable(colors) then return end
    local match
    for token in next, colors do
        if classToken(token) and (member(LOCALIZED_CLASS_NAMES_MALE, token) == label
            or member(LOCALIZED_CLASS_NAMES_FEMALE, token) == label) then
            if match then return end
            match = token
        end
    end
    return match
end

local function nativeFriendEvidence(name, region, owns)
    local api = C_FriendList
    local function enabled()
        return rawequal(api, C_FriendList) and read(member(api, "IsLegacyFriendSystemEnabled")) == true
            and rawequal(api, C_FriendList)
    end
    return rosterEvidence(name, region, "Native Friends", owns, function()
        if not enabled() then return end
        local row = read(member(api, "GetFriendInfo"), name)
        local guid = member(row, "guid")
        if member(row, "name") == name and reader.playerGuid(guid) then
            local class = nativeClass(member(row, "className")) or evidence.classForGuid(guid)
            local level = positiveInteger(member(row, "level"))
            local state = online(member(row, "connected"))
            if enabled() then return guid, class, level, state end
        end
    end)
end

local function savedEvidence(record, owns)
    local known = record and record.lastKnown
    if record and record.identityState == "resolved" and known and known.id == record.id
        and known.name == record.fullName and known.region == record.region and reader.playerGuid(known.guid)
        and (not record.guid or record.guid == known.guid) then
        local class = known.class and classToken(known.class.value)
        local level = known.level and positiveInteger(known.level.value)
        local faction = known.faction and known.faction.value
        if faction ~= "Alliance" and faction ~= "Horde" then faction = nil end
        local at = class and timestamp(known.class.at) or level and timestamp(known.level.at)
            or faction and timestamp(known.faction.at)
        if at then
            return {name=known.name, guid=known.guid, region=known.region, class=class, level=level,
                faction=faction, at=at, source="Saved", validate=owns}
        end
    end
end

local chatCache, chatRegion = {}, nil
local chatLifetime, chatLimit = 600, 128

local function freshChat(item, now)
    return item and now and now >= item.at and now - item.at < chatLifetime
end

local function cacheChat(name, guid, class, region, at)
    if chatRegion ~= region then chatCache, chatRegion = {}, region end
    local count, oldestKey, oldestAt = 0, nil, math.huge
    for key, item in pairs(chatCache) do
        if not freshChat(item, at) then chatCache[key] = nil
        else
            count = count + 1
            if item.at < oldestAt then oldestKey, oldestAt = key, item.at end
        end
    end
    local key = name .. "\0" .. guid
    -- An unavailable profile must not erase earlier verified class metadata
    -- or renew the lifetime of that earlier observation.
    if not class and chatCache[key] and chatCache[key].class then return end
    if count >= chatLimit and not chatCache[key] then chatCache[oldestKey] = nil end
    chatCache[key] = {name=name, guid=guid, class=class, at=at}
end

local function chatEvidence(name, region, owns)
    if chatRegion ~= region or not owns() then return end
    local now = timestamp(read(GetServerTime))
    local key, item
    for candidateKey, candidate in pairs(chatCache) do
        if candidate.name == name and freshChat(candidate, now) then
            if item then return end
            key, item = candidateKey, candidate
        end
    end
    if not item then return end
    local checkedAt = now
    local function cacheValid()
        local current = chatCache[key]
        if chatRegion ~= region or not current or current.guid ~= item.guid or current.class ~= item.class
            or not freshChat(current, checkedAt) and current.at <= checkedAt then return false end
        for _, candidate in pairs(chatCache) do
            if candidate ~= current and (candidate.name == name or candidate.guid == item.guid)
                and (candidate.at > checkedAt or freshChat(candidate, checkedAt)) then return false end
        end
        return true
    end
    local function validate()
        if not owns() then return false end
        local at = timestamp(read(GetServerTime))
        if not freshChat(item, at) or chatRegion ~= region or chatCache[key] ~= item then return false end
        checkedAt = at
        return owns() and cacheValid()
    end
    if validate() and not item.class then
        -- The native profile can become readable after the chat callback.
        -- Retain the verified sender lease, then retry only that exact GUID.
        local api = C_ChatInfo
        if read(member(api, "InChatMessagingLockdown")) ~= false or not validate() then return end
        local class = evidence.classForGuid(item.guid)
        if not validate() or not rawequal(api, C_ChatInfo)
            or read(member(api, "InChatMessagingLockdown")) ~= false or not validate() then return end
        if class then
            item = {name=item.name, guid=item.guid, class=class, at=item.at}
            chatCache[key] = item
        end
    end
    if validate() then
        return {name=name, guid=item.guid, class=item.class, region=region, at=item.at,
            source="chat", validate=validate, cacheValid=cacheValid}
    end
end

-- Ordinary Add keeps its existing native status pipeline; metadata already
-- learned from chat needs no second roster or unit scan before saving.
function evidence.cachedChat(name, store, region, expectedGuid, owns)
    if chatRegion ~= region or not readable(name) or not isComplete(name) then return end
    local function owned()
        return context(store, region) and (not owns or owns())
    end
    if not owned() then return end
    local current = chatEvidence(name, region, owned)
    if not current or expectedGuid and current.guid ~= expectedGuid then return end
    local _, issue = store.find(region, name, current.guid)
    if issue ~= "conflict" and owned() and current.cacheValid() then return current end
end

-- Rebind chat leases without scanning native rosters. Direct menu metadata is
-- an immutable snapshot of a verified exact line; passive data must still exist.
function evidence.refreshChat(observation, store, region, owns)
    if not observation or observation.region ~= region or not context(store, region)
        or (owns and not owns()) then return end
    local current = observation
    if observation.source == "chat" then
        current = chatEvidence(observation.name, region, function()
            return context(store, region) and (not owns or owns())
        end)
        if not current or current.guid ~= observation.guid or current.class ~= observation.class then return end
    elseif observation.source ~= "Chat menu" then
        return
    end
    local _, issue = store.find(region, current.name, current.guid)
    if issue ~= "conflict" and context(store, region) and (not owns or owns())
        and (not current.cacheValid or current.cacheValid()) then return current end
end

-- A directly verified menu/target profile is historical metadata. Replacing an
-- unrelated store snapshot does not change its identity or require a live unit.
function evidence.refreshCaptured(observation, name, store, region, owns)
    local function owned()
        return store and A.store == store and A.region == region and read(GetCurrentRegion) == region
            and A.store == store and A.region == region and (not owns or owns())
    end
    if not observation or observation.name ~= name or observation.region ~= region
        or observation.current or observation.validate
        or (observation.source ~= "Target" and observation.source ~= "Player menu")
        or not readable(observation.guid) or type(observation.guid) ~= "string" or observation.guid == ""
        or not owned() then return end
    local _, issue = store.find(region, name, observation.guid)
    if issue == "conflict" then return nil, issue end
    if owned() then return observation end
end

local function groups(addUnit, owns)
    local prefix, count, source = reader.groupRoster()
    if not prefix then return end
    for i=1,count do
        if not owns() then return end
        if not addUnit(prefix .. i, source, owns) then return false end
    end
end

local function plates(addUnit, owns)
    if not A.automaticNameplatesEnabled then return end
    local enabled, generation = A.automaticNameplatesEnabled()
    if not enabled or not owns() then return end
    local frames = reader.nameplateFrames()
    if not frames then return end
    local bounded, count = {}, 0
    for _, frame in next, frames do
        count = count + 1
        if count > 256 then return end
        if readable(frame) then bounded[#bounded + 1] = frame end
    end
    for _, frame in ipairs(bounded) do
        if not owns() then return false end
        local token = reader.nameplateUnit(frame)
        if token then
            local matched = addUnit(token, "Nameplate", function()
                if not owns() or not rawequal(reader.nameplateFrame(token), frame) then return false end
                local active, revision = A.automaticNameplatesEnabled()
                return active and revision == generation and owns()
            end)
            if not matched then return false end
        end
    end
end

function evidence.resolve(name, store, region, expectedGuid, owns, skipDirectUnits)
    if not readable(name) or not isComplete(name) or expectedGuid ~= nil and not reader.playerGuid(expectedGuid) then return end
    local function owned()
        return (not owns or owns()) and context(store, region) and (not owns or owns())
    end
    if not owned() then return end
    local record, issue = store.find(region, name, expectedGuid)
    if issue == "conflict" then return end
    local choices, seenGuid = {}, expectedGuid
    local function add(candidate)
        if not candidate then return true end
        local _, conflict = store.find(region, name, candidate.guid)
        if conflict == "conflict" or seenGuid and seenGuid ~= candidate.guid then return false end
        seenGuid = candidate.guid
        choices[#choices + 1] = candidate
        return true
    end
    local function addUnit(token, source, sourceOwns)
        return add(evidence.readUnit(token, region, source, sourceOwns, name))
    end
    if not skipDirectUnits then
        if not addUnit("target", "Target", owned) or not addUnit("mouseover", "Mouseover", owned) then return end
    end
    if groups(addUnit, owned) == false or plates(addUnit, owned) == false or not owned() then return end
    local guild = A.guildRosterRead.capturePlayer(name, owned)
    if guild then
        guild.region, guild.source = region, "Guild"
        if not add(guild) then return end
    end
    if not add(recentEvidence(name, region, owned)) or not add(nativeFriendEvidence(name, region, owned))
        or not add(chatEvidence(name, region, owned)) or not add(savedEvidence(record, owned)) then return end

    local best
    for _, candidate in ipairs(choices) do
        if candidate.validate() then
            local _, conflict = store.find(region, name, candidate.guid)
            if conflict == "conflict" then return end
            if not best or (candidate.class and not best.class) then best = candidate end
        end
    end
    if best and best.validate() and owned() then return best end
end

-- Forever chat payload fields 2 and 12 are the author and GUID. Keep only
-- verified profile metadata from these incoming events, with no line contents.
local chatEvents = {"CHAT_MSG_GUILD", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_WHISPER", "CHAT_MSG_OFFICER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER"}
local installed, handling = false, false

function evidence.chatName(name)
    if not readable(name) then return end
    if isComplete(name) then return name end
    if not P.CharacterName.IsFriendDraft(name) or read(RegionalUniqueNamesEnabled) ~= true then return end
    -- Accept the native link spelling only if the Forever name API reproduces it exactly.
    local first, second = name:match("^([^%-]+)%-([^%-]+)$")
    if not first then return end
    local fullName = first .. " " .. second
    if isComplete(fullName)
        and read(member(C_NameUtil, "ReplaceSurnameSeparatorWithLinkSeparator"), fullName) == name then return fullName end
end

local function onChat(name, guid)
    if not reader.playerGuid(guid) then return end
    local store, region, api = A.store, A.region, C_ChatInfo
    local function owned()
        return context(store, region) and read(member(api, "InChatMessagingLockdown")) == false
            and rawequal(api, C_ChatInfo) and context(store, region)
    end
    if not owned() then return end
    name = evidence.chatName(name)
    if not name or not owned() then return end
    local ownGuid = reader.identitySafe("player") and reader.guid("player")
    if not reader.playerGuid(ownGuid) or ownGuid == guid or not owned() then return end
    local class = evidence.classForGuid(guid)
    local at = timestamp(read(GetServerTime))
    if not at or not owned() then return end
    local _, issue = store.find(region, name, guid)
    if issue == "conflict" then return end
    cacheChat(name, guid, class, region, at)
    if not class then return end
    local observation = chatEvidence(name, region, owned)
    if observation and A.publishPlayerEvidence then A.publishPlayerEvidence(observation) end
end

function evidence.install()
    if installed or not A.store or type(CreateFrame) ~= "function" then return end
    installed = true
    local frame = read(CreateFrame, "Frame")
    if not frame then return end
    local events = {}
    frame:SetScript("OnEvent", function(_, event, _, name, _, _, _, _, _, _, _, _, _, guid)
        if handling or not readable(event) or not events[event] then return end
        handling = true
        pcall(onChat, name, guid)
        handling = false
    end)
    for _, event in ipairs(chatEvents) do
        if read(frame.RegisterEvent, frame, event) == true then events[event] = true end
    end
end
