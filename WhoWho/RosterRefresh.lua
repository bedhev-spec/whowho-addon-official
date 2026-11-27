-- Read-only, session-local positive roster reports.
local A = WhowhoPreview.manual
local read, safeTable, member, readable = A.nativeRead.read, A.nativeRead.safeTable, A.nativeRead.member, A.nativeRead.readable
local guildRead = A.guildRosterRead
local refresh = { reports = {} }
A.relogRefresh = refresh
local generations = { Guild=0, ["Recent Allies"]=0 }

function refresh.forget(id)
    refresh.reports[id] = nil
end

function refresh.guildRetirement(record, guid, club)
    local reports = refresh.reports[record.id]
    if not reports then return end
    local function matching(report)
        return report and report.source == "Guild" and report.club == club and report.guid == guid
            and report.name == record.fullName and report.region == record.region and report
    end
    local manual, guild = matching(reports.manual), matching(reports.Guild)
    if not manual and not guild then return end
    return function()
        if manual and reports.manual == manual then reports.manual = nil end
        if guild and reports.Guild == guild then reports.Guild = nil end
    end
end

local function hint(record, source, club)
    local known = record and record.lastKnown
    local sources = known and known.sources
    if not known or type(known.guid) ~= "string" or known.guid == "" or not sources then return nil end
    if source == "Guild" then
        local guild = sources.guild
        if not guild or guild.absentAt or guild.clubId ~= club then return nil end
    elseif not sources.recentAlliesAt then return nil end
    return known.guid
end
local function ready(source, club)
    if source == "Guild" then
        return club ~= nil and read(member(C_Club, "GetGuildClubId")) == club
            and read(member(C_Club, "AreMembersReady"), club) == true
    end
    return read(member(C_RecentAllies, "IsSystemSupported")) == true
        and read(member(C_RecentAllies, "IsSystemEnabled")) == true
        and read(member(C_RecentAllies, "IsRecentAllyDataReady")) == true
end
local function context(store, region, source, club, isCurrent)
    return A.store == store and A.region == region and read(GetCurrentRegion) == region
        and read(InCombatLockdown) == false and type(isCurrent) == "function" and isCurrent()
        and ready(source, club) and isCurrent() and A.store == store and A.region == region
end
local function length(rows)
    if not safeTable(rows) then return nil end
    local ok, n = pcall(function() return #rows end)
    if not ok or not readable(n) or type(n) ~= "number" or n < 0 or n > 1000 or n % 1 ~= 0 then return nil end
    local valid, count = pcall(function()
        local total = 0
        for key in pairs(rows) do
            if not readable(key) or type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > n then return nil end
            total = total + 1
        end
        return total
    end)
    if not valid or count ~= n then return nil end
    return n
end
local statusSources = {"Group", "Guild", "Recent Allies"}
local function firstStatus(sources)
    for _, source in ipairs(statusSources) do
        local report = sources[source]
        if report and type(report.online) == "boolean" then return report end
    end
end
local function attempt(source, isCurrent, started, manual, staged)
    if source ~= "Guild" and source ~= "Recent Allies" then return true, false end
    local store, region = A.store, A.region
    if not store or read(GetCurrentRegion) ~= region or read(InCombatLockdown) ~= false
        or type(isCurrent) ~= "function" or not isCurrent() then return false, false end
    local club = source == "Guild" and read(member(C_Club, "GetGuildClubId")) or nil
    if not ready(source, club) or not isCurrent() then return manual and isCurrent() or false, false end
    started.value = true
    generations[source] = generations[source] + 1
    local generation = generations[source]
    local rows
    if source == "Guild" then rows = read(member(C_Club, "GetClubMembers"), club)
    else rows = read(member(C_RecentAllies, "GetRecentAllies")) end
    local count = length(rows)
    if not count then return true, false end
    local names, guids, candidates, ids = {}, {}, {}, {}
    for i=1,count do
        local row = member(rows, i)
        if source == "Guild" then
            if not ((type(row) == "string" and row ~= "") or (type(row) == "number" and row == row and row > 0 and row < math.huge and row % 1 == 0)) or ids[row] then return true, false end
            ids[row] = true
            row = read(member(C_Club, "GetMemberInfo"), club, row)
        end
        local identity = source == "Guild" and row or member(row, "characterData")
        local name = member(identity, source == "Guild" and "name" or "fullName")
        local guid = member(identity, "guid")
        local validName = type(name) == "string" and name:match("^%S+%s+%S+$") ~= nil
        local validGuid = type(guid) == "string" and guid ~= ""
        if validName then names[name] = (names[name] or 0) + 1 end
        if validGuid then guids[guid] = (guids[guid] or 0) + 1 end
        local online
        if source == "Guild" then online = guildRead.online(row)
        else online = member(member(row, "stateData"), "isOnline") end
        if validName and validGuid and (manual or type(online) == "boolean") then
            candidates[#candidates + 1] = {name=name, guid=guid, online=online}
        end
    end
    local pending = {}
    for _, candidate in ipairs(candidates) do
        local record
        if names[candidate.name] == 1 and guids[candidate.guid] == 1 then
            record = store.find(region, candidate.name, candidate.guid)
        end
        if record and record.membership == "friend" and record.region == region and record.fullName == candidate.name
            and (manual or hint(record, source, club) == candidate.guid) then
            pending[record.id] = {id=record.id, region=region, name=candidate.name, guid=candidate.guid,
                online=candidate.online, source=source, club=club, generation=generation}
        end
    end
    if generations[source] ~= generation or not context(store, region, source, club, isCurrent) then return true, false end
    for id, report in pairs(pending) do
        local current = store.get(id)
        local found = manual and store.find(region, report.name, report.guid)
        if not current or current.membership ~= "friend" or current.region ~= region or current.fullName ~= report.name
            or (manual and (not found or found.id ~= id))
            or (not manual and hint(current, source, club) ~= report.guid) then return true, false end
    end
    if generations[source] ~= generation or not context(store, region, source, club, isCurrent)
        or generations[source] ~= generation then return true, false end
    if manual then
        for id, report in pairs(pending) do
            staged[id] = staged[id] or {}
            staged[id][source] = report
        end
        return true, next(pending) ~= nil
    end
    local changed = false
    for id, report in pairs(pending) do
        local existing = refresh.reports[id] or {}
        existing[source] = report
        refresh.reports[id] = existing
        changed = true
    end
    return true, changed
end
function refresh.attempt(source, isCurrent)
    local started = {value=false}
    local ok, done, changed = pcall(attempt, source, isCurrent, started)
    if not ok then return started.value, false end
    return done, changed
end
local function selectManualReports(store, region, guildClub, staged)
    local byId, byGuid, conflicts = {}, {}, {}
    local function index(id, guid)
        if not id or type(guid) ~= "string" or guid == "" then return end
        if byId[id] and byId[id] ~= guid then conflicts[id] = true end
        if byGuid[guid] and byGuid[guid] ~= id then conflicts[id], conflicts[byGuid[guid]] = true, true end
        byId[id], byGuid[guid] = guid, id
    end
    for _, seen in ipairs(A.targetCheck.identities()) do
        if seen.region == region then index(seen.id, seen.guid) end
    end
    for id, reports in pairs(refresh.reports) do
        local report = reports.manual
        if report and report.region == region and (report.source ~= "Guild" or report.club == guildClub) then
            local found = store.find(region, report.name, report.guid)
            if found and found.id == id and found.membership == "friend" then index(id, report.guid) end
        end
    end
    for id, sources in pairs(staged) do
        for _, report in pairs(sources) do index(id, report.guid) end
    end
    local selected = {}
    for id, sources in pairs(staged) do
        if not conflicts[id] then selected[id] = firstStatus(sources) end
    end
    return selected
end

local manualBusy = false
local function manualSnapshot(isCurrent)
    local store, region = A.store, A.region
    if not store then return nil end
    local tokens = A.targetCheck.reportTokens()
    local function valid()
        return A.store == store and A.region == region and read(GetCurrentRegion) == region
            and read(InCombatLockdown) == false and type(isCurrent) == "function" and isCurrent()
            and A.store == store and A.region == region
    end
    if not valid() then return nil end
    local staged, units, names, guids = {}, {}, {}, {}
    local reader = A.unitReader
    local prefix, count, groupSource = reader.groupRoster()
    if prefix then
        for i=1,count do
            local token = prefix .. i
            if read(UnitExists, token) == true and read(UnitIsUnit, token, "player") == false and reader.identitySafe(token) then
                local name, guid, online = reader.name(token), reader.guid(token), read(UnitIsConnected, token)
                if type(name) == "string" and name:match("^%S+%s+%S+$") and type(guid) == "string" and guid ~= "" then
                    names[name], guids[guid] = (names[name] or 0) + 1, (guids[guid] or 0) + 1
                    units[#units + 1] = {token=token, name=name, guid=guid, online=online}
                end
            end
        end
        for _, row in ipairs(units) do
            if names[row.name] == 1 and guids[row.guid] == 1 then
                local record = store.find(region, row.name, row.guid)
                if record and record.membership == "friend" and record.region == region and record.fullName == row.name then
                    staged[record.id] = {Group={id=record.id, region=region, name=row.name, guid=row.guid,
                        online=row.online, source=groupSource, kind="checked", token=row.token}}
                end
            end
        end
    end
    for _, source in ipairs({"Guild", "Recent Allies"}) do
        if not valid() then return nil end
        local ok = attempt(source, isCurrent, {value=false}, true, staged)
        if not ok then return nil end
    end
    if not valid() then return nil end
    local livePrefix, liveCount = reader.groupRoster()
    local groupReady = #units > 0 and livePrefix == prefix and liveCount == count
    local guildClub = read(member(C_Club, "GetGuildClubId"))
    local guildReady, recentReady = ready("Guild", guildClub), ready("Recent Allies")
    local groupRead, recheckGuild, recheckRecent = false, false, false
    for _, sources in pairs(staged) do
        local group = sources.Group
        if group then
            groupRead = groupRead or groupReady
            if not groupReady or read(UnitExists, group.token) ~= true
                or read(UnitIsUnit, group.token, "player") ~= false or not A.unitReader.identitySafe(group.token)
                or A.unitReader.name(group.token) ~= group.name or A.unitReader.guid(group.token) ~= group.guid then
                sources.Group = nil
            end
        end
        recheckGuild = recheckGuild or sources.Guild ~= nil
        recheckRecent = recheckRecent or sources["Recent Allies"] ~= nil
    end
    if not valid() then return nil end
    -- Group identity reads can invalidate a roster whose reports are already staged.
    if groupRead and recheckGuild and guildReady then guildReady = ready("Guild", guildClub) end
    if groupRead and recheckRecent and recentReady then recentReady = ready("Recent Allies") end
    if not valid() then return nil end
    for _, sources in pairs(staged) do
        if not guildReady or (sources.Guild and (sources.Guild.club ~= guildClub
            or sources.Guild.generation ~= generations.Guild)) then sources.Guild = nil end
        if not recentReady or (sources["Recent Allies"] and sources["Recent Allies"].generation ~= generations["Recent Allies"]) then
            sources["Recent Allies"] = nil
        end
    end
    local selected = selectManualReports(store, region, guildClub, staged)
    local matched = 0
    for id, report in pairs(selected) do
        local found = store.find(region, report.name, report.guid)
        if not found or found.id ~= id or found.membership ~= "friend" then return nil end
    end
    for id, report in pairs(selected) do
        report.kind = report.kind or "listed"
        report.reportToken = tokens[id]
        local existing = refresh.reports[id] or {}
        existing.manual = report
        refresh.reports[id] = existing
        matched = matched + 1
    end
    return matched
end
function refresh.manual(isCurrent)
    if manualBusy then return nil end
    manualBusy = true
    local ok, matched = pcall(manualSnapshot, isCurrent)
    manualBusy = false
    if ok then return matched end
end
local function renderGuild(context)
    if context and context.guildChecked then return context.guild end
    local guild = read(member(C_Club, "GetGuildClubId"))
    if context then context.guild, context.guildChecked = guild, true end
    return guild
end
local function validRelog(report, item, rawRecord, context)
    return report and item.region == report.region and item.fullName == report.name
        and (not item.guid or item.guid == report.guid)
        and hint(rawRecord, report.source, report.club) == report.guid
        and (report.source ~= "Guild" or renderGuild(context) == report.club)
end
function refresh.apply(item, rawRecord, context)
    local reports = refresh.reports[item.id]
    if not reports or item.membership ~= "friend" or item.presence then return end
    local manual = reports.manual
    local found = manual and A.store.find(manual.region, manual.name, manual.guid)
    if manual and found and found.id == item.id and item.region == manual.region and item.fullName == manual.name
        and (not item.guid or item.guid == manual.guid)
        and (not item.presenceReport or (manual.reportToken ~= nil
            and A.targetCheck.reportToken(item.id) == manual.reportToken))
        and (manual.source ~= "Guild" or renderGuild(context) == manual.club) then
        local newer = reports[manual.source]
        if newer and newer.guid == manual.guid and newer.generation > manual.generation
            and validRelog(newer, item, rawRecord, context) then manual = newer end
        item.presenceReport = {kind=manual.kind or "listed", online=manual.online, source=manual.source}
        return
    end
    if item.presenceReport or (item.attempt and not item.attemptObserved) then return end
    for _, source in ipairs({"Guild", "Recent Allies"}) do
        local report = reports[source]
        if validRelog(report, item, rawRecord, context) then
            item.presenceReport = {kind="listed", online=report.online, source=source}
            return
        end
    end
end
