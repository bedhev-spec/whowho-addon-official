-- Manual candidate only: observations are session-local and never saved.
local A = WhowhoPreview.manual
local reader = A.unitReader
local guildRead = A.guildRosterRead
local check = { observations = {}, cached = {}, roster = {}, latest = {}, attempts = {}, busy = false }
local plates = {}
local quickProfiles = {}
local collections = {check.observations, check.cached, check.roster, plates}
local seenWindow = 300
A.targetCheck = check
function check.reportToken(id)
    if check.latest[id] == "roster" then return check.roster[id] end
    if check.latest[id] == "cached" then return check.cached[id] end
end
function check.reportTokens()
    local tokens = {}
    for id in pairs(check.latest) do tokens[id] = check.reportToken(id) end
    return tokens
end
local readable, read, safeTable, member = A.nativeRead.readable, A.nativeRead.read, A.nativeRead.safeTable, A.nativeRead.member
local function same(record, snapshot)
    return snapshot and record.membership == "friend" and record.id == snapshot.id
        and record.region == snapshot.region and record.fullName == snapshot.name
        and (not record.guid or record.guid == snapshot.guid)
end
function check.identities()
    local identities, active = {}, {}
    for _, collection in ipairs(collections) do
        for id, seen in pairs(collection) do
            if active[id] == nil then active[id] = A.store.get(id) or false end
            if active[id] and same(active[id], seen) then identities[#identities + 1] = seen end
        end
    end
    return identities
end
local function fresh(sighting, at)
    return sighting and type(sighting.at)=="number" and at and at >= sighting.at and at - sighting.at < seenWindow
end
function check.rememberQuickAdd(id, profile)
    if profile.faction then
        quickProfiles[id] = {id=id, region=profile.region, name=profile.name, guid=profile.guid,
            faction=profile.faction}
    end
end
function check.hasSightings()
    return next(check.observations) ~= nil or next(plates) ~= nil
end
function check.apply(record, at)
    local direct = check.observations[record.id]
    local plate = plates[record.id]
    if not same(record, direct) then direct = nil end
    if not same(record, plate) or (direct and plate.guid ~= direct.guid) then plate = nil end
    local directFresh, plateFresh = fresh(direct, at), fresh(plate, at)
    local seen
    if directFresh then seen = direct
    elseif plateFresh or (plate and (not direct or plate.at > (direct.at or -math.huge))) then seen = plate
    else seen = direct end
    local cached = check.cached[record.id]
    local plateIsLatest = not directFresh and plateFresh
        and check.reportToken(record.id)==seen.priorReport
    if seen then
        record.class = record.class or (direct and direct.class) or (plate and plate.class)
        record.level = record.level or (direct and direct.level) or (plate and plate.level)
        record.evidenceName = seen.name
        record.faction = seen.faction or (direct and direct.faction) or (plate and plate.faction)
        record.ruleset = seen.otherRuleset and "Different ruleset" or nil
        if directFresh or plateFresh then record.presence = "Seen" end
        record.source, record.observed = seen.source or "Target", seen.observed
    end
    if not record.faction then
        local profile = quickProfiles[record.id]
        if same(record, profile) then
            local current = A.store.find(profile.region, profile.name, profile.guid)
            if current and current.id == record.id then
                record.quickAddFaction = profile.faction
            end
        end
    end
    local roster = check.roster[record.id]
    if same(record, roster) then
        if not plateIsLatest and check.latest[record.id] == "roster" then
            record.presenceReport = {kind=roster.source == "Guild" and "listed" or "checked",
                online=roster.online, source=roster.source}
        end
        if not record.class then record.class = roster.class end
        if not record.level then record.level = roster.level end
        if record.class then record.evidenceName = record.fullName end
    end
    if same(record, cached) then
        if not plateIsLatest and check.latest[record.id] == "cached" then
            record.presenceReport = {kind="listed", online=cached.online, source="Recent Allies"}
        end
        if not record.class then record.class = cached.class end
        if not record.level then record.level = cached.level end
        if record.class then record.evidenceName = record.fullName end
    end
    local attempt = check.attempts[record.id]
    if same(record, attempt) then
        record.attempt, record.attemptObserved, record.attemptWarning = attempt.message, attempt.observed, attempt.warning
    end
    if directFresh and plateFresh then return math.min(direct.at,plate.at)+seenWindow end
    if directFresh then return direct.at+seenWindow end
    if plateFresh then return plate.at+seenWindow end
end
local function conflict(record, region, name, guid)
    local match = A.store.find(region, name, guid)
    if not match or match.id ~= record.id or match.membership ~= "friend" then return true end
    for _, collection in ipairs(collections) do
        for id, seen in pairs(collection) do
            -- Only a changed GUID or a shared one can conflict; the record copy waits for that.
            if (id == record.id) ~= (seen.guid == guid) then
                local active = A.store.get(id)
                if active and same(active, seen) and seen.region == region then return true end
            end
        end
    end
    return false
end
local function outcome(kind, message) return {kind=kind, message=message} end
local function inContext(region)
    return read(GetCurrentRegion) == region and read(InCombatLockdown) == false and A.region == region
end
local function recent(record, hintOnly, stronger)
    local unavailable = "Recent Allies data unavailable for this Friend."
    local region = read(GetCurrentRegion)
    if type(region) ~= "number" or region ~= A.region or region ~= record.region then return unavailable end
    local api = C_RecentAllies
    local function ready()
        return read(member(api, "IsSystemSupported")) == true
            and read(member(api, "IsSystemEnabled")) == true
            and read(member(api, "IsRecentAllyDataReady")) == true
    end
    if not ready() then return unavailable, not hintOnly and "unready" or nil end
    local store = A.store
    local row = read(member(api, "GetRecentAllyByFullName"), record.fullName)
    local character = member(row, "characterData")
    local name, guid = member(character, "fullName"), member(character, "guid")
    if type(name) ~= "string" or name ~= record.fullName or type(guid) ~= "string" or guid == "" then return unavailable end
    if conflict(record, region, name, guid) then return "Recent Allies identity conflicts with the saved Friend.", not hintOnly and "conflict" or nil end
    local function validate()
        if not inContext(region) or not ready() then return false end
        local current = read(member(api, "GetRecentAllyByFullName"), name)
        local identity = member(current, "characterData")
        return member(identity, "fullName") == name and member(identity, "guid") == guid
            and ready() and inContext(region) and A.store == store and not conflict(record, region, name, guid)
    end
    local online
    if not hintOnly then online = member(member(row, "stateData"), "isOnline") end
    local level, classID
    if not hintOnly and type(online) == "boolean" then level, classID = member(character, "level"), member(character, "classID") end
    if type(level) ~= "number" or level ~= level or level < 1 or level == math.huge or level % 1 ~= 0 then level = nil end
    local class
    if type(classID) == "number" and classID == classID and classID > 0 and classID ~= math.huge and classID % 1 == 0 then
        local info = read(member(C_CreatureInfo, "GetClassInfo"), classID)
        local token = member(info, "classFile")
        if type(token) == "string" and token:match("^[A-Z]+$") then class = token end
    end
    local stamp = read(GetServerTime)
    if read(GetCurrentRegion) ~= region or conflict(record, region, name, guid)
        or member(character, "fullName") ~= name or member(character, "guid") ~= guid then return unavailable end
    local previous = check.cached[record.id]
    if stronger then
        if stronger.class then class = nil end
        if stronger.level then level = nil end
    end
    local function commitSession()
        if hintOnly or type(online) ~= "boolean" then return end
        check.cached[record.id] = {id=record.id, region=region, name=name, guid=guid, online=online,
            class=class or (same(record, previous) and previous.class), level=level or (same(record, previous) and previous.level)}
        check.latest[record.id] = "cached"
    end
    if type(stamp) == "number" and stamp == stamp and stamp >= 0 and stamp < math.huge then
        local safe = A.observe(record, guid, "Recent Allies", stamp, class, level, validate, true, commitSession)
        if not safe then
            if hintOnly then return unavailable end
            return "Recent Allies changed during the check; try again.", "changed"
        end
    elseif hintOnly then return nil
    elseif not validate() then return "Recent Allies changed during the check; try again.", "changed"
    else commitSession() end
    if hintOnly then return nil, true end
    if type(online) ~= "boolean" then return unavailable end
    return "Recent Allies report.", "match"
end
local function validName(name)
    return type(name) == "string" and name:match("^%S+%s+%S+$") ~= nil
end
local function recentOutcome(record, stronger)
    local message, kind = recent(record, false, stronger)
    return outcome(kind or "unavailable", message)
end
local function validLevel(level)
    if type(level) == "number" and level == level and level >= 1 and level < math.huge and level % 1 == 0 then return level end
end
local function classForID(id)
    if type(id) ~= "number" or id ~= id or id <= 0 or id >= math.huge or id % 1 ~= 0 then return nil end
    local token = member(read(member(C_CreatureInfo, "GetClassInfo"), id), "classFile")
    if type(token) == "string" and token:match("^[A-Z]+$") then return token end
end
local function publishRoster(record, source, guid, online, class, level, validate, hint, stronger)
    local observedClass, observedLevel = class, level
    if stronger and stronger.class then observedClass = nil end
    if stronger and stronger.level then observedLevel = nil end
    local function commitSession()
        local previous = check.roster[record.id]
        local savedClass, savedLevel = (stronger and stronger.class) or class, (stronger and stronger.level) or level
        if online ~= nil and same(record, previous) then
            savedClass, savedLevel = savedClass or previous.class, savedLevel or previous.level
        end
        check.roster[record.id] = {id=record.id, region=record.region, name=record.fullName, guid=guid,
            source=source, club=hint, online=online, class=savedClass, level=savedLevel}
        check.latest[record.id] = "roster"
    end
    local stamp = read(GetServerTime)
    if (observedClass or observedLevel or hint) and type(stamp) == "number" and stamp == stamp and stamp >= 0 and stamp < math.huge then
        if not A.observe(record, guid, source, stamp, observedClass, observedLevel, validate, hint, commitSession) then
            return source .. " changed during the check; try again."
        end
    elseif not validate() then
        return source .. " changed during the check; try again."
    else
        commitSession()
    end
    return source .. " report found.", true
end
local function group(record, missingMetadata)
    local store = A.store
    if missingMetadata and not inContext(record.region) then return end
    local raid = read(IsInRaid)
    if type(raid) ~= "boolean" then return outcome("group-unavailable", "Group data unavailable for this Friend.") end
    local countReader = GetNumSubgroupMembers
    if raid then countReader = GetNumGroupMembers end
    local count = read(countReader)
    if type(count) ~= "number" or count ~= count or count % 1 ~= 0 or count < 0 or count > (raid and 40 or 4) then return outcome("group-unavailable", "Group data unavailable for this Friend.") end
    local match, matchGuid, unreadable
    for i=1,count do
        local unit = (raid and "raid" or "party") .. i
        local exists = read(UnitExists, unit)
        local self = read(UnitIsUnit, unit, "player")
        if exists == nil or (exists == true and self == nil) then unreadable = true end
        local identitySafe = exists == true and self == false and reader.identitySafe(unit)
        if exists == true and self == false and not identitySafe then unreadable = true end
        if identitySafe then
            local name = reader.name(unit)
            if type(name) ~= "string" then unreadable = true end
            if name == record.fullName then
                if match then return outcome("conflict", "Group identity is ambiguous.") end
                local guid = reader.guid(unit)
                if not validName(name) or type(guid) ~= "string" or guid == "" then return outcome("unavailable", "Group identity unavailable.") end
                match, matchGuid = unit, guid
            end
        end
    end
    if not match then
        if unreadable then return outcome("unavailable", "Group data unavailable for this Friend.") end
        return outcome("absent")
    end
    local source = raid and "Raid" or "Party"
    if conflict(record, record.region, record.fullName, matchGuid) then return outcome("conflict", source .. " identity conflicts with the saved Friend.") end
    local function sameGroup()
        return read(IsInRaid) == raid and read(countReader) == count
    end
    local function validate()
        if not inContext(record.region) or not sameGroup() or A.store ~= store then return false end
        for i=1,count do
            local unit = (raid and "raid" or "party") .. i
            if unit ~= match and read(UnitExists, unit) == true and read(UnitIsUnit, unit, "player") == false
                and reader.identitySafe(unit) and reader.name(unit) == record.fullName then return false end
        end
        return read(UnitExists, match) == true and read(UnitIsUnit, match, "player") == false
            and reader.identitySafe(match) and reader.name(match) == record.fullName
            and reader.guid(match) == matchGuid and sameGroup() and inContext(record.region)
            and A.store == store and not conflict(record, record.region, record.fullName, matchGuid)
    end
    if not validate() then return outcome("changed", source .. " changed during the check; try again.") end
    if missingMetadata then
        if matchGuid ~= missingMetadata.guid then return end
        local class, level = reader.metadata(match, validate)
        class = missingMetadata.class and class or nil
        level = missingMetadata.level and level or nil
        local stamp = (class or level) and read(GetServerTime)
        if type(stamp) == "number" and stamp == stamp and stamp >= 0 and stamp < math.huge then
            A.observe(record, matchGuid, source, stamp, class, level, validate)
        end
        return
    end
    local online = read(UnitIsConnected, match)
    if type(online) ~= "boolean" then online = nil end
    local class, level = reader.metadata(match)
    if online == nil and not class and not level then return outcome("unavailable", source .. " data unavailable for this Friend.") end
    local message, published = publishRoster(record, source, matchGuid, online, class, level, validate)
    local result = outcome(published and (online == nil and "partial" or "match") or "changed", message)
    if published then result.stronger = {class=class, level=level} end
    return result
end
local function verifyGuildAbsence(record, api, club)
    local current = A.store and A.store.get(record.id)
    local known = current and current.lastKnown
    local hint = known and known.sources and known.sources.guild
    if not known or type(known.guid) ~= "string" or known.guid == "" or not hint
        or hint.clubId ~= club then return false end
    local roster = check.roster[record.id]
    local matched = same(record, roster) and roster.guid == known.guid and roster.source == "Guild" and roster.club == club
    local retireRefresh = A.relogRefresh and A.relogRefresh.guildRetirement(record, known.guid, club)
    if hint.absentAt and not matched and not retireRefresh then return false end
    local stamp = read(GetServerTime)
    if type(stamp) ~= "number" or stamp ~= stamp or stamp < 0 or stamp >= math.huge or stamp <= hint.at then return false end
    if read(InCombatLockdown) ~= false or read(GetCurrentRegion) ~= record.region
        or read(member(api, "GetGuildClubId")) ~= club or read(member(api, "AreMembersReady"), club) ~= true then return false end
    local rosterUnchanged = guildRead.captureAbsence(api, club, record.fullName, known.guid)
    if not rosterUnchanged then return false end
    local function validate()
        local function contextReady()
            local now = read(GetServerTime)
            return read(InCombatLockdown) == false and read(GetCurrentRegion) == record.region
            and read(member(api, "GetGuildClubId")) == club and read(member(api, "AreMembersReady"), club) == true
            and type(now) == "number" and now == now and now >= stamp and now < math.huge
        end
        return contextReady() and rosterUnchanged() and contextReady()
    end
    local function retire()
        if matched and check.roster[record.id] == roster then
            check.roster[record.id] = nil
            if check.latest[record.id] == "roster" then check.latest[record.id] = nil end
        end
        if retireRefresh then retireRefresh() end
    end
    return A.guildAbsent(record, known.guid, club, stamp, validate, retire)
end
local function guild(record, hintOnly, stronger)
    local api = C_Club
    local club = read(member(api, "GetGuildClubId"))
    if club == nil then return outcome("unavailable", "Guild data unavailable for this Friend.") end
    if read(member(api, "AreMembersReady"), club) ~= true then return outcome("unready", "Guild data not ready for this Friend.") end
    local ids = read(member(api, "GetClubMembers"), club)
    if not safeTable(ids) then return outcome("unavailable", "Guild data unavailable for this Friend.") end
    local ok, count = pcall(function() return #ids end)
    if not ok or not readable(count) or type(count) ~= "number" or count < 0 or count >= math.huge or count % 1 ~= 0 then return outcome("unavailable", "Guild data unavailable for this Friend.") end
    local selected, guid, unreadable
    for i=1,count do
        local id = member(ids, i)
        local row = id ~= nil and read(member(api, "GetMemberInfo"), club, id) or nil
        local name = member(row, "name")
        if type(name) ~= "string" then unreadable = true end
        if name == record.fullName then
            if selected then return outcome("conflict", "Guild identity is ambiguous.") end
            local candidate = member(row, "guid")
            if not validName(name) or type(candidate) ~= "string" or candidate == "" then return outcome("unavailable", "Guild identity unavailable.") end
            selected, guid = id, candidate
        end
    end
    if not selected then
        if unreadable then return outcome("unavailable", "Guild data unavailable for this Friend.") end
        if not hintOnly and verifyGuildAbsence(record, api, club) then
            return outcome("guild-absent", "Guild roster no longer lists the selected Friend.")
        end
        return outcome("absent")
    end
    if conflict(record, record.region, record.fullName, guid) then return outcome("conflict", "Guild identity conflicts with the saved Friend.") end
    local function rowNow() return read(member(api, "GetMemberInfo"), club, selected) end
    local function contextReady()
        return read(InCombatLockdown) == false and read(GetCurrentRegion) == record.region
            and read(member(api, "GetGuildClubId")) == club and read(member(api, "AreMembersReady"), club) == true
    end
    local function validate()
        if not contextReady() then return false end
        local current = read(member(api, "GetClubMembers"), club)
        if not safeTable(current) then return false end
        local lengthOK, length = pcall(function() return #current end)
        if not lengthOK or not readable(length) or length ~= count then return false end
        local matches = 0
        for i=1,length do
            local id = member(current, i)
            if id == selected then matches = matches + 1
            elseif id ~= nil then
                local other = read(member(api, "GetMemberInfo"), club, id)
                if member(other, "name") == record.fullName then return false end
            end
        end
        if matches ~= 1 then return false end
        local row = rowNow()
        return member(row, "name") == record.fullName and member(row, "guid") == guid
            and contextReady() and not conflict(record, record.region, record.fullName, guid)
    end
    local row = rowNow()
    if member(row, "name") ~= record.fullName or member(row, "guid") ~= guid then return outcome("changed", "Guild changed during the check; try again.") end
    if hintOnly then
        local stamp = read(GetServerTime)
        if type(stamp) ~= "number" or stamp ~= stamp or stamp < 0 or stamp >= math.huge then return nil end
        if not A.observe(record, guid, "Guild", stamp, nil, nil, validate, club) then return nil end
        return nil, true
    end
    local online = guildRead.online(row)
    local class, level = classForID(member(row, "classID")), validLevel(member(row, "level"))
    if online == nil and not class and not level then
        local stamp = read(GetServerTime)
        if type(stamp) == "number" and stamp == stamp and stamp >= 0 and stamp < math.huge then
            if not A.observe(record, guid, "Guild", stamp, nil, nil, validate, club) then return outcome("changed", "Guild changed during the check; try again.") end
        end
        return outcome("unavailable", "Guild data unavailable for this Friend.")
    end
    local message, published = publishRoster(record, "Guild", guid, online, class, level, validate, club, stronger)
    local result = outcome(published and (online == nil and "partial" or "match") or "changed", message)
    if published then result.stronger = {class=(stronger and stronger.class) or class, level=(stronger and stronger.level) or level} end
    return result
end
local function checkContext(expectedRegion)
    local combat = read(InCombatLockdown)
    if combat == true then return nil, "Checks paused during combat." end
    if combat ~= false then return nil, "Combat status unavailable." end
    local region = read(GetCurrentRegion)
    if type(region) ~= "number" or region ~= A.region or (expectedRegion and region ~= expectedRegion) then
        return nil, "Region changed or unavailable."
    end
    return region
end
local function targetIdentity(expectedRegion, unit, owns)
    unit = unit or "target"
    local region, issue = checkContext(expectedRegion)
    if not region or (owns and not owns()) then return nil, issue end
    local name, guid, state = reader.playerIdentity(unit, owns)
    if name then return {region=region, name=name, guid=guid} end
    if state == "absent" then return nil, "No target selected.", true end
    if state == "non-player" or state == "self" then return nil, "Non-player target skipped.", "non-player" end
    if state == "unsafe" then return nil, "Target identity safety unavailable.", "target-unavailable" end
    if state == "identity" then return nil, "Target identity unavailable.", "target-unavailable" end
    return nil, "Target unavailable or unreadable.", "target-unavailable"
end
local function sample(record, automaticValid, snapshot, unit)
    unit = unit or "target"
    local source = reader.worldSource(unit)
    local mismatch = "Target the selected saved Friend and check again."
    if not A.store or not record or record.membership ~= "friend" then return mismatch end
    local store = A.store
    local current = store.get(record.id)
    if not current or current.membership ~= "friend" or current.region ~= record.region
        or current.fullName ~= record.fullName or current.guid ~= record.guid then return mismatch end
    if not snapshot then
        local message, fallback
        snapshot, message, fallback = targetIdentity(record.region)
        if not snapshot then return message, fallback end
    end
    local region, name, guid = snapshot.region, snapshot.name, snapshot.guid
    if name ~= record.fullName then
        local _, issue = A.store.find(region, name, guid)
        if issue == "conflict" then return "Target identity conflicts with a saved Friend." end
        for _, collection in ipairs(collections) do
            for id, seen in pairs(collection) do
                local active = A.store.get(id)
                if active and same(active, seen) and seen.region == region and seen.guid == guid and seen.name ~= name then
                    return "Target identity conflicts with an earlier observation."
                end
            end
        end
        return mismatch, true
    end
    if conflict(record, region, name, guid) then return "Target identity conflicts with the saved Friend." end
    local previous = check.observations[record.id]
    local stamp = read(GetServerTime)
    if type(stamp) ~= "number" or stamp ~= stamp or stamp < 0 or stamp == math.huge then return "Target check unavailable: time unreadable." end
    local observed = read(date, "%Y-%m-%d %H:%M", stamp)
    if type(observed) ~= "string" or not observed:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d$") then return "Target check unavailable: time unreadable." end
    local function owns()
        return A.store == store and inContext(region) and (not automaticValid or automaticValid())
    end
    local metadata = reader.playerMetadata(unit, owns)
    if not metadata or not reader.samePlayer(unit, name, guid, owns) then
        return "Target changed during the check; try again."
    end
    local class, level, faction, otherRuleset = metadata.class, metadata.level, metadata.faction, metadata.otherRuleset
    current = A.store.find(region, name, guid)
    if not current or current.id ~= record.id or current.membership ~= "friend" then return mismatch end
    local function validate()
        return reader.samePlayer(unit, name, guid, owns) and not conflict(record, region, name, guid)
    end
    local function commitSession()
        check.observations[record.id] = { id=record.id, region=region, name=name, guid=guid,
            class=class or (previous and previous.class), level=level or (previous and previous.level),
            faction=faction or (same(record, previous) and previous.guid == guid and previous.faction or nil),
            otherRuleset=otherRuleset, observed=observed, source=source, at=stamp }
        check.latest[record.id] = "target"
    end
    local rebuilt
    if class or level then
        local safe
        safe, rebuilt = A.observe(record, guid, source, stamp, class, level, validate, nil, commitSession)
        if not safe then return "Target changed during the check; try again." end
    elseif not validate() then
        return "Target changed during the check; try again."
    else
        commitSession()
    end
    if automaticValid and not rebuilt then A.refresh() end
    return "Target observed.", false, true
end
function check.check(record)
    if record and record.identityState=="unresolved" then return "Resolve the draft before checking status." end
    if check.busy then return "Target check already in progress." end
    check.busy = true
    local ok, message, fallback, direct = pcall(sample, record)
    local remoteEligible = false
    local warning = not fallback and not direct
    if ok and fallback then
        local targetMessage = message
        local failure = type(fallback) == "string" and outcome(fallback, message) or nil
        local partial, stronger
        message = nil
        for _, source in ipairs({group, guild, recentOutcome}) do
            local _, issue = checkContext(record.region)
            if issue then
                message, warning = issue, true
                break
            end
            local result
            if source == guild then ok, result = pcall(source, record, false, stronger)
            else ok, result = pcall(source, record, stronger) end
            if not ok then break end
            if result and (result.kind == "match" or result.kind == "conflict" or result.kind == "changed") then
                message, warning = result.message, result.kind ~= "match"
                break
            end
            if result and result.kind == "partial" then
                partial, stronger = result.message, result.stronger
            elseif result and result.message and (not failure or failure.kind == "group-unavailable" or result.kind == "guild-absent") then failure = result end
        end
        if ok and not message then
            message = partial or (failure and failure.message) or targetMessage
            warning = not partial and failure ~= nil and failure.kind ~= "non-player" and failure.kind ~= "guild-absent"
            remoteEligible = true
        end
    end
    if ok and direct then
        pcall(function()
            local seen = check.observations[record.id]
            local current = A.store.get(record.id)
            local known = current and current.lastKnown
            if same(record, seen) and (not known or not known.class or not known.level) then
                group(record, {guid=seen.guid, class=not known or not known.class, level=not known or not known.level})
            end
            local _, found = guild(record, true)
            if not found then
                local current = A.store.get(record.id)
                local known = current and current.lastKnown
                if not (known and known.sources and known.sources.recentAlliesAt) then recent(record, true) end
            end
        end)
    end
    check.busy = false
    if not ok then message, warning = "Target check unavailable; try again.", true end
    if record and A.store then
        local current=A.store.get(record.id)
        if current and current.membership=="friend" and current.region==record.region and current.fullName==record.fullName and current.guid==record.guid then
            check.attempts[record.id]={id=record.id,region=record.region,name=record.fullName,guid=record.guid,
                message=message,observed=ok and direct==true,warning=warning}
            A.refresh()
        end
    end
    return message, remoteEligible
end

-- Each event owns one synchronous attempt; nested events invalidate its read.
local generation, hoverGeneration, attempts, repeats, lastClock = 0, 0, {}, {}, nil
function check.forget(id)
    check.observations[id], check.cached[id], check.roster[id] = nil, nil, nil
    check.latest[id], check.attempts[id], repeats[id] = nil, nil, nil
    plates[id] = nil
    quickProfiles[id] = nil
end
function check.clearNameplates()
    if not next(plates) then return false end
    for id in pairs(plates) do plates[id] = nil end
    A.refresh()
    return true
end
function check.observeNameplate(unit, expectedFrame, owns)
    local store, region = A.store, A.region
    if not store or not inContext(region) or not owns() or A.counts and A.counts.friend == 0 then return false end
    local frame = reader.playerPlate(unit, expectedFrame)
    if not frame then return false end
    local function playerPlate()
        return owns() and reader.playerPlate(unit, frame) and owns()
    end
    if not playerPlate() then return false end
    local snapshot = targetIdentity(region, unit, owns)
    if not snapshot or not owns() or not validName(snapshot.name) or not reader.playerGuid(snapshot.guid) then return false end
    local name, guid = snapshot.name, snapshot.guid
    local record = store.find(region, name, guid)
    if not record or record.fullName ~= name or record.membership ~= "friend" then return false end
    local stamp = read(GetServerTime)
    if not owns() or type(stamp) ~= "number" or stamp ~= stamp or stamp < 0 or stamp >= math.huge then return false end
    local direct = check.observations[record.id]
    if same(record, direct) and fresh(direct, stamp) then return false end
    local previous = plates[record.id]
    if previous and previous.guid == guid and stamp >= previous.at and stamp - previous.at < 5 then return false end
    local observed = read(date, "%Y-%m-%d %H:%M", stamp)
    if type(observed) ~= "string" or not observed:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d$") then return false end
    local function canReadMetadata()
        return inContext(region) and playerPlate()
            and A.store == store and owns()
    end
    local metadata = reader.playerMetadata(unit, canReadMetadata)
    if not metadata or not reader.samePlayer(unit, name, guid, canReadMetadata)
        or conflict(record, region, name, guid) then return false end
    local class, level = metadata.class, metadata.level
    if same(record, previous) and previous.guid == guid then
        class, level = class or previous.class, level or previous.level
    end
    plates[record.id] = {id=record.id, region=region, name=name, guid=guid,
        class=class, level=level, faction=metadata.faction, otherRuleset=metadata.otherRuleset,
        source=reader.worldSource(unit), observed=observed, at=stamp,
        priorReport=check.reportToken(record.id)}
    A.refresh()
    return true
end
local pending
local function timerCancel(timer)
    if not readable(timer) then return nil end
    local ok, cancel = pcall(function() return timer.Cancel end)
    if ok and readable(cancel) and type(cancel) == "function" then return cancel end
end
local function clock()
    local now = read(GetTime)
    if type(now) ~= "number" or now ~= now or now < 0 or now >= math.huge then return nil end
    return now
end
local function automatic(unit, valid)
    if not valid() then return false end
    local now = clock()
    if not now then return false end
    if lastClock and now < lastClock then attempts, repeats = {}, {} end
    lastClock = now
    while #attempts > 0 and now - attempts[1] >= 1 do table.remove(attempts, 1) end
    if #attempts >= 4 then return false end
    attempts[#attempts + 1] = now
    for id, at in pairs(repeats) do if now - at >= 5 then repeats[id] = nil end end
    if not valid() then return false end
    local snapshot = targetIdentity(A.region, unit, valid)
    if not snapshot then return false end
    local name, guid = snapshot.name, snapshot.guid
    local record = A.store and A.store.find(A.region, name, guid)
    if not record or record.membership ~= "friend" then return false end
    if repeats[record.id] and now - repeats[record.id] < 5 then return false end
    if not valid() or conflict(record, A.region, name, guid) then return false end
    repeats[record.id] = now
    local _, _, direct = sample(record, valid, snapshot, unit)
    return direct == true
end
function check.onTargetChanged()
    generation = generation + 1
    local mine = generation
    if check.busy or type(A.automaticTargetEnabled) ~= "function" then return false end
    check.busy = true
    local ok, published = pcall(function()
        local enabled, settingGeneration = A.automaticTargetEnabled()
        if not enabled then return false end
        local function valid()
            local active, currentGeneration = A.automaticTargetEnabled()
            return generation == mine and active and currentGeneration == settingGeneration
        end
        return automatic("target", valid)
    end)
    check.busy = false
    return ok and published == true
end
function check.cancelMouseover()
    hoverGeneration = hoverGeneration + 1
    local mine = hoverGeneration
    local old = pending
    pending = nil
    if old and old.cancel then pcall(old.cancel, old.timer) end
    return mine
end
function check.mouseoverAvailable()
    return type(member(C_Timer, "NewTimer")) == "function"
end
function check.onMouseoverChanged(onPublished)
    local mine = check.cancelMouseover()
    if hoverGeneration ~= mine then return end
    if type(A.automaticMouseoverEnabled) ~= "function" or not check.mouseoverAvailable() then return end
    local ok, enabled, settingGeneration = pcall(A.automaticMouseoverEnabled)
    if not ok or not enabled then return end
    local started = clock()
    if not started or hoverGeneration ~= mine then return end
    local work = {armed=false}
    pending = work
    local function callback()
        if pending ~= work then return end
        if not work.armed then pending = nil; return end
        pending = nil
        if check.busy then return end
        check.busy = true
        local success, published = pcall(function()
            local function valid()
                local active, currentGeneration = A.automaticMouseoverEnabled()
                local now = clock()
                return hoverGeneration == mine and active and currentGeneration == settingGeneration
                    and now and now - started >= 0.25 and now - started <= 1
            end
            return automatic("mouseover", valid)
        end)
        check.busy = false
        if success and published and type(onPublished) == "function" then pcall(onPublished) end
    end
    local created, timer = pcall(member(C_Timer, "NewTimer"), 0.25, callback)
    local cancel = created and timerCancel(timer)
    if not cancel or pending ~= work or hoverGeneration ~= mine then
        if pending == work then pending = nil end
        if cancel then pcall(cancel, timer) end
        return
    end
    work.timer, work.cancel, work.armed = timer, cancel, true
end
