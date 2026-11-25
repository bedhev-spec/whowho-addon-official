-- Offline data core. Native adapters must filter restricted values before entry.
local AddressBook = {}
local observationPriority = {Target=2, Mouseover=2, Party=2, Raid=2, Nameplate=2,
    ["Player menu"]=2, ["Chat menu"]=1, Chat=1, Guild=1, ["Recent Allies"]=1, ["Native Friends"]=1}
local factionSource = {Target=true, Mouseover=true, Party=true, Raid=true, Nameplate=true, ["Player menu"]=true}
local function classToken(value) return type(value) == "string" and value:match("^[A-Z]+$") end
local function factionToken(value) return value == "Alliance" or value == "Horde" end
AddressBook.reasons = {
    { id="griefing", label="Griefing" },
    { id="sabotage", label="Gameplay sabotage" },
    { id="ninja_looting", label="Ninja looting" },
    { id="camping", label="Repeated camping" },
    { id="harassment", label="Harassment / toxicity" },
    { id="fraud", label="Scam / trade fraud" },
    { id="spam", label="Spam / advertising" },
    { id="other", label="Other" },
}
local reasonLookup = {}
for _, reason in ipairs(AddressBook.reasons) do reasonLookup[reason.id] = reason.label end
function AddressBook.validReasons(ids)
    if type(ids) ~= "table" then return false end
    local count, highest, seen = 0, 0, {}
    for key, id in pairs(ids) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or not reasonLookup[id] or seen[id] then return false end
        seen[id], count, highest = true, count + 1, math.max(highest, key)
    end
    return count > 0 and count == highest
end
function AddressBook.reasonLabel(id) return reasonLookup[id] end

local function copy(value, active, lastKnown)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "string" then return value, true end
    if kind == "number" then return value, value == value and value ~= math.huge and value ~= -math.huge end
    if kind ~= "table" or getmetatable(value) ~= nil or active[value] then return nil, false end
    active[value] = true
    local result = {}
    for key, item in pairs(value) do
        local kt = type(key)
        if kt ~= "string" and kt ~= "number" then active[value] = nil; return nil, false end
        if kt == "number" and (key ~= key or key == math.huge or key == -math.huge) then
            active[value] = nil; return nil, false
        end
        local cloned, ok = copy(item, active, key == "lastKnown")
        if not ok and key ~= "lastKnown" and not (lastKnown and key == "faction") then active[value] = nil; return nil, false end
        if ok then result[key] = cloned end
    end
    active[value] = nil
    return result, true
end

local function clone(value)
    local success, result, valid = pcall(copy, value, {})
    if not success then return nil, false end
    return result, valid
end
local function text(value) return type(value) == "string" and value ~= "" end
local function region(value)
    return text(value) or (type(value) == "number" and value > 0 and value < math.huge and value % 1 == 0)
end
local function role(value)
    return value == nil or value == "TANK" or value == "HEALER" or value == "DAMAGER"
end
local function note(value)
    if value == nil then return true end
    if type(value) ~= "string" then return false end
    local i, count, length = 1, 0, #value
    while i <= length do
        local first = value:byte(i)
        local size = first < 128 and 1 or (first >= 194 and first <= 223 and 2)
            or (first >= 224 and first <= 239 and 3) or (first >= 240 and first <= 244 and 4)
        if not size or i + size - 1 > length then return false end
        local second = size > 1 and value:byte(i + 1) or 0
        for offset = 1, size - 1 do
            local byte = value:byte(i + offset)
            if byte < 128 or byte > 191 then return false end
        end
        if (first == 224 and second < 160) or (first == 237 and second > 159)
            or (first == 240 and second < 144) or (first == 244 and second > 143) then return false end
        count, i = count + 1, i + size
        if count > 256 then return false end
    end
    return true
end
local function member(value) return value == "friend" or value == "blacklist" end
local function integer(value) return type(value) == "number" and value > 0 and value < 9007199254740991 and value % 1 == 0 end
local function timestamp(value) return type(value) == "number" and value >= 0 and value < math.huge end

-- Exact names are intentionally not parsed or normalized. Completeness is an adapter decision.
local function validRecord(record, id, bucket)
    if type(record) ~= "table" or record.id ~= id or record.schemaVersion ~= 1
        or not member(record.membership) or not role(record.role)
        or not note(record.note) or not timestamp(record.createdAt) or not timestamp(record.updatedAt)
        or record.updatedAt < record.createdAt
        or (record.guid ~= nil and not text(record.guid)) then return false end
    if bucket == false then
        return record.identityState == "unresolved" and record.region == nil
            and record.guid == nil and text(record.fullName)
    end
    return record.identityState == "resolved" and record.region == bucket and text(record.fullName)
end

local function validate(data)
    if type(data) ~= "table" or data.schemaVersion ~= 1 or not integer(data.nextId)
        or type(data.regions) ~= "table" or type(data.drafts) ~= "table" then return false end
    local ids, maxId = {}, 0
    local function check(records, bucket)
        if type(records) ~= "table" then return false end
        local names, guids = {}, {}
        for id, record in pairs(records) do
            if not integer(id) or ids[id] or not validRecord(record, id, bucket) then return false end
            ids[id], maxId = true, math.max(maxId, id)
            if bucket ~= false then
                if names[record.fullName] or (record.guid and guids[record.guid]) then return false end
                names[record.fullName] = true
                if record.guid then guids[record.guid] = true end
            end
        end
        return true
    end
    if not check(data.drafts, false) then return false end
    for key, records in pairs(data.regions) do
        if not region(key) or not check(records, key) then return false end
    end
    if data.archived ~= nil then
        if type(data.archived) ~= "table" then return false end
        for id, record in pairs(data.archived) do
            if not integer(id) or ids[id] or type(record) ~= "table" or record.id ~= id
                or not region(record.region) or not text(record.fullName)
                or record.note ~= nil or record.role ~= nil or record.membership ~= nil
                or (record.guid ~= nil and not text(record.guid)) then return false end
            ids[id], maxId = true, math.max(maxId, id)
        end
    end
    return data.nextId > maxId
end

-- Optional evidence never invalidates an otherwise valid roster.
local function cleanLastKnown(data)
    for _, record in pairs(data.drafts) do record.lastKnown = nil end
    for scope, records in pairs(data.regions) do
        local owners = {}
        for _, record in pairs(records) do if record.guid then owners[record.guid] = record.id end end
        for _, record in pairs(records) do
            local k = record.lastKnown
            if type(k) == "table" and k.id == record.id and k.region == scope and k.name == record.fullName
                and text(k.guid) and (not record.guid or record.guid == k.guid) then
                local cleaned = {id=record.id, region=scope, name=record.fullName, guid=k.guid}
                for _, field in ipairs({"class", "level", "faction"}) do
                    local entry = k[field]
                    local value = type(entry) == "table" and entry.value
                    local valid = field == "class" and classToken(value) or field == "level" and integer(value)
                        or field == "faction" and factionToken(value)
                    if valid and timestamp(entry.at) and (field == "faction" and factionSource[entry.source]
                        or field ~= "faction" and observationPriority[entry.source]) then
                        cleaned[field] = {value=value, source=entry.source, at=entry.at}
                    end
                end
                local sources = type(k.sources) == "table" and k.sources or nil
                if sources then
                    local guild = sources.guild
                    local club = type(guild) == "table" and guild.clubId
                    if (integer(club) or text(club)) and timestamp(guild.at) then
                        cleaned.sources = {guild={clubId=club, at=guild.at}}
                        if timestamp(guild.absentAt) and guild.absentAt > guild.at then
                            cleaned.sources.guild.absentAt = guild.absentAt
                        end
                    end
                    if timestamp(sources.recentAlliesAt) then
                        cleaned.sources = cleaned.sources or {}
                        cleaned.sources.recentAlliesAt = sources.recentAlliesAt
                    end
                end
                record.lastKnown = (cleaned.class or cleaned.level or cleaned.faction or cleaned.sources) and cleaned or nil
            else record.lastKnown = nil end
        end
        for _, record in pairs(records) do
            local k = record.lastKnown
            if k then
                local owner = owners[k.guid]
                if owner and owner ~= record.id then owners[k.guid] = false
                elseif owner == nil then owners[k.guid] = record.id end
            end
        end
        for _, record in pairs(records) do
            if record.lastKnown and owners[record.lastKnown.guid] ~= record.id then record.lastKnown = nil end
        end
    end
end

function AddressBook.open(input)
    if input == nil then input = { schemaVersion = 1, nextId = 1, regions = {}, drafts = {} } end
    local data, ok = clone(input)
    if not ok then return nil, "invalid_data" end
    if type(data) ~= "table" then return nil, "invalid_data" end
    if data.schemaVersion ~= 1 then return nil, "unsupported_version" end
    if not validate(data) then return nil, "invalid_data" end
    cleanLastKnown(data)
    local store = {}
    local byId, byName, byGuid = {}, {}, {}
    local function index(record)
        byId[record.id] = record
        if record.identityState == "resolved" then
            local scope = record.region
            byName[scope] = byName[scope] or {}
            byGuid[scope] = byGuid[scope] or {}
            byName[scope][record.fullName] = record
            local effectiveGuid = record.guid or (record.lastKnown and record.lastKnown.guid)
            if effectiveGuid then byGuid[scope][effectiveGuid] = record end
        end
    end
    for _, record in pairs(data.drafts) do index(record) end
    for _, records in pairs(data.regions) do
        for _, record in pairs(records) do index(record) end
    end

    local function locate(id)
        return byId[id]
    end
    local function collision(scope, name, guid, except)
        local named = byName[scope] and byName[scope][name]
        local guided = guid and byGuid[scope] and byGuid[scope][guid]
        if guided and guided.id ~= except and guided ~= named then return "conflict" end
        if named and named.id ~= except then
            local effectiveGuid = named.guid or (named.lastKnown and named.lastKnown.guid)
            if guid and effectiveGuid and guid ~= effectiveGuid then return "conflict" end
            return "duplicate"
        end
    end
    function store.export() return clone(data) end
    function store.activeRecords(scope)
        if not region(scope) then return nil, "invalid_region" end
        local snapshot, ok = clone({records=data.regions[scope], drafts=data.drafts})
        if not ok then return nil, "invalid_data" end
        local records = snapshot.records or {}
        for id, draft in pairs(snapshot.drafts) do records[id] = draft end
        return records
    end
    function store.get(id)
        if not integer(id) then return nil, "invalid_id" end
        local record = locate(id)
        if not record then return nil, "not_found" end
        return clone(record)
    end
    function store.find(scope, name, guid)
        if not region(scope) or not text(name) or (guid ~= nil and not text(guid)) then return nil, "invalid_identity" end
        local match = byName[scope] and byName[scope][name]
        local guided = guid and byGuid[scope] and byGuid[scope][guid]
        if guided and guided ~= match then return nil, "conflict" end
        if not match then return nil, "not_found" end
        local effectiveGuid = match.guid or (match.lastKnown and match.lastKnown.guid)
        if guid and effectiveGuid and guid ~= effectiveGuid then return nil, "conflict" end
        return clone(match)
    end
    function store.add(inputRecord, at)
        local record, valid = clone(inputRecord)
        if not timestamp(at) or not valid or type(record) ~= "table" or not member(record.membership)
            or not role(record.role) or not note(record.note)
            or not text(record.fullName) then return nil, "invalid_record" end
        if record.membership == "blacklist" and not AddressBook.validReasons(record.reasonIds) then return nil, "invalid_reasons" end
        if record.identityState == "resolved" then
            if not region(record.region) or (record.guid ~= nil and not text(record.guid)) then return nil, "invalid_identity" end
            local issue = collision(record.region, record.fullName, record.guid)
            if issue then return nil, issue end
        elseif record.identityState ~= "unresolved" or record.region ~= nil or record.guid ~= nil then
            return nil, "invalid_identity"
        end
        record.lastKnown = nil -- Only observations may set this evidence.
        record.favorite = nil
        record.whisperMuted = nil
        -- Caller cannot choose IDs or record schema.
        if not integer(data.nextId + 1) then return nil, "id_exhausted" end
        record.id, record.schemaVersion, record.createdAt, record.updatedAt = data.nextId, 1, at, at
        data.nextId = data.nextId + 1
        if record.identityState == "unresolved" then data.drafts[record.id] = record
        else
            data.regions[record.region] = data.regions[record.region] or {}
            data.regions[record.region][record.id] = record
        end
        index(record)
        return clone(record)
    end
    function store.resolve(id, scope, name, guid, at)
        if not integer(id) or not region(scope) or not text(name) or (guid ~= nil and not text(guid)) or not timestamp(at) then return nil, "invalid_identity" end
        local record = data.drafts[id]
        if not record then return nil, "not_found" end
        if at < record.updatedAt then return nil, "invalid_timestamp" end
        local issue = collision(scope, name, guid, id)
        if issue then return nil, issue end
        data.drafts[id] = nil
        record.region, record.fullName, record.guid, record.identityState, record.updatedAt = scope, name, guid, "resolved", at
        data.regions[scope] = data.regions[scope] or {}
        data.regions[scope][id] = record
        index(record)
        return clone(record)
    end
    function store.edit(id, changes, at)
        if not integer(id) then return nil, "invalid_id" end
        if not timestamp(at) then return nil, "invalid_timestamp" end
        local patch, valid = clone(changes)
        if not valid or type(patch) ~= "table" then return nil, "invalid_edit" end
        for key, value in pairs(patch) do
            if key == "role" then
                if value ~= false and not role(value) then return nil, "invalid_edit" end
            elseif key == "note" then
                if value ~= false and not note(value) then return nil, "invalid_edit" end
            elseif key == "reasonIds" then
                if not AddressBook.validReasons(value) then return nil, "invalid_reasons" end
            elseif key == "favorite" then
                if type(value) ~= "boolean" then return nil, "invalid_edit" end
            elseif key == "fullName" then
                if not text(value) then return nil, "invalid_edit" end
            else return nil, "invalid_edit" end
        end
        local record = locate(id)
        if not record then return nil, "not_found" end
        if at < record.updatedAt then return nil, "invalid_timestamp" end
        if patch.favorite ~= nil and (record.membership ~= "friend" or record.identityState ~= "resolved") then
            return nil, "invalid_edit"
        end
        if patch.fullName and record.identityState ~= "unresolved" then return nil, "invalid_edit" end
        if record.membership == "blacklist" and not AddressBook.validReasons(patch.reasonIds or record.reasonIds) then return nil, "invalid_reasons" end
        for key, value in pairs(patch) do
            if value == false then record[key] = nil else record[key] = value end
        end
        record.updatedAt = at
        return clone(record)
    end
    function store.setChatMuted(id, value, at)
        if not integer(id) or type(value) ~= "boolean" then return nil, "invalid_edit" end
        if not timestamp(at) then return nil, "invalid_timestamp" end
        local record = locate(id)
        if not record or record.membership ~= "blacklist" or record.identityState ~= "resolved" then
            return nil, "invalid_edit"
        end
        if at < record.updatedAt then return nil, "invalid_timestamp" end
        record.whisperMuted, record.updatedAt = value, at
        return clone(record)
    end
    function store.observe(id, scope, name, guid, source, at, class, level, hint)
        if not integer(id) or not region(scope) or not text(name) or not text(guid)
            or not observationPriority[source] or not timestamp(at) then return nil, "invalid_observation" end
        if class ~= nil and not classToken(class) then return nil, "invalid_observation" end
        if level ~= nil and not integer(level) then return nil, "invalid_observation" end
        if hint ~= nil and not ((source == "Guild" and (integer(hint) or text(hint)))
            or (source == "Recent Allies" and hint == true)) then return nil, "invalid_observation" end
        if not class and not level and hint == nil then return nil, "invalid_observation" end
        local record = locate(id)
        if not record or record.identityState ~= "resolved" or record.membership ~= "friend"
            or record.region ~= scope or record.fullName ~= name then return nil, "stale_identity" end
        local found = store.find(scope, name, guid)
        if not found or found.id ~= id then return nil, "conflict" end
        local k = record.lastKnown or {id=id, region=scope, name=name, guid=guid}
        local changed = false
        for field, value in pairs({class=class, level=level}) do
            local old = k[field]
            local priority = old and (observationPriority[old.source] or 2)
            if (not old or observationPriority[source] > priority
                or (observationPriority[source] == priority and at >= old.at))
                and (not old or old.value ~= value or old.source ~= source or old.at ~= at) then
                k[field] = {value=value, source=source, at=at}
                changed = true
            end
        end
        if hint ~= nil then
            local sources = k.sources or {}
            if source == "Guild" then
                local old = sources.guild
                if not old or (at >= old.at and (not old.absentAt or at >= old.absentAt)) then
                    if not old or old.clubId ~= hint or old.at ~= at or old.absentAt then
                        sources.guild = {clubId=hint, at=at}; changed = true
                    end
                end
            elseif not sources.recentAlliesAt or at > sources.recentAlliesAt then
                sources.recentAlliesAt = at; changed = true
            end
            if changed then k.sources = sources end
        end
        if not changed then return nil, "unchanged" end
        record.lastKnown = k
        byGuid[scope][guid] = record
        return clone(record)
    end
    local function blacklistChanges(id, evidence, missingOnly)
        local scope, name, guid, source, at = evidence.region, evidence.name, evidence.guid, evidence.source, evidence.at
        if not integer(id) or not region(scope) or not text(name) or not text(guid)
            or not observationPriority[source] or not timestamp(at) then return end
        local record = locate(id)
        if not record or record.identityState ~= "resolved" or record.membership ~= "blacklist"
            or record.region ~= scope or record.fullName ~= name then return end
        local found = store.find(scope, name, guid)
        if not found or found.id ~= id then return end
        local known = record.lastKnown or {id=id, region=scope, name=name, guid=guid}
        local changes = {}
        for field, value in pairs({class=evidence.class, faction=factionSource[source] and evidence.faction or nil}) do
            local old = known[field]
            local valid = field == "class" and classToken(value) or field == "faction" and factionToken(value)
            if valid and (not old or (not missingOnly and value ~= old.value and at >= old.at)) then
                changes[field] = {value=value, source=source, at=at}
            end
        end
        if next(changes) then return record, known, changes end
    end
    function store.needsBlacklistObservation(id, evidence)
        return blacklistChanges(id, evidence) ~= nil
    end
    function store.observeBlacklist(id, evidence, missingOnly)
        local record, known, changes = blacklistChanges(id, evidence, missingOnly)
        if not record then return false end
        for field, observation in pairs(changes) do known[field] = observation end
        record.lastKnown = known
        byGuid[record.region][known.guid] = record
        return true
    end
    function store.guildAbsent(id, scope, name, guid, club, at)
        if not integer(id) or not region(scope) or not text(name) or not text(guid)
            or not (integer(club) or text(club)) or not timestamp(at) then return nil, "invalid_observation" end
        local record = locate(id)
        local known = record and record.lastKnown
        local guild = known and known.sources and known.sources.guild
        if not record or record.membership ~= "friend" or record.identityState ~= "resolved"
            or record.region ~= scope or record.fullName ~= name or not known or known.guid ~= guid
            or not guild or guild.clubId ~= club then return nil, "stale_identity" end
        local found = store.find(scope, name, guid)
        if not found or found.id ~= id then return nil, "conflict" end
        if at <= guild.at or (guild.absentAt and at < guild.absentAt) then return nil, "stale_observation" end
        if at == guild.absentAt then return nil, "unchanged" end
        guild.absentAt = at
        return clone(record)
    end
    function store.move(id, membership, at, reasonIds)
        if not integer(id) or not member(membership) then return nil, "invalid_move" end
        if not timestamp(at) then return nil, "invalid_timestamp" end
        local record = locate(id)
        if not record then return nil, "not_found" end
        if at < record.updatedAt then return nil, "invalid_timestamp" end
        if membership == "blacklist" then
            local reasons, valid = clone(reasonIds)
            if not valid or not AddressBook.validReasons(reasons) then return nil, "invalid_reasons" end
            record.reasonIds = reasons
            record.favorite = nil
        end
        if membership ~= record.membership then record.whisperMuted = nil end
        record.membership, record.updatedAt = membership, at
        return clone(record)
    end
    function store.delete(id, scope, name, guid)
        local draft = integer(id) and scope == nil and guid == nil and data.drafts[id]
        if draft and draft.fullName == name then
            data.drafts[id], byId[id] = nil, nil
            return true
        end
        if not integer(id) or not region(scope) or not text(name) or (guid ~= nil and not text(guid)) then return nil, "invalid_identity" end
        local record = locate(id)
        if not record or record.identityState ~= "resolved" or record.region ~= scope
            or record.fullName ~= name or record.guid ~= guid then return nil, "stale_identity" end
        local archived = { id=id, region=scope, fullName=name, guid=guid,
            reasonIds=record.reasonIds, incidentRefs=record.incidentRefs, encounterRefs=record.encounterRefs }
        data.archived = data.archived or {}
        data.archived[id] = archived
        data.regions[scope][id] = nil
        byId[id], byName[scope][name] = nil, nil
        local effectiveGuid = guid or (record.lastKnown and record.lastKnown.guid)
        if effectiveGuid then byGuid[scope][effectiveGuid] = nil end
        return true
    end
    return store
end

local _, namespace = ...
if type(namespace) == "table" then namespace.AddressBook = AddressBook end
return AddressBook
