-- Loaded only by the manual-address-book candidate, after Theme and AddressBook.
local _, namespace = ...
local P = WhowhoPreview
local A = { records = {} }
local book = namespace.AddressBook
P.manual = A
P.version = "0.0.0-dev"

function A.text(value)
    if not A.nativeRead.readable(value) or type(value) ~= "string" then return nil end
    return value
end
local function nativeNumber(fn)
    if type(issecretvalue) ~= "function" or type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn)
    if not ok or not A.nativeRead.readable(value) then return nil end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end
local function currentRegion()
    local value = nativeNumber(GetCurrentRegion)
    if value and value > 0 and value % 1 == 0 then return value end
end
function A.playerFaction(region)
    if region == nil or A.region ~= region or currentRegion() ~= region then return nil end
    local faction = A.unitReader.faction("player")
    if currentRegion() == region and A.region == region then return faction end
end
local function now()
    local value = nativeNumber(GetServerTime)
    if value and value >= 0 then return value end
end
local refreshRevision, nextSightingExpiry = 0, nil
local function refresh(at, metadataOnly)
    refreshRevision = refreshRevision + 1
    local revision = refreshRevision
    local store=A.store
    local rebuilt = {}
    local counts = {friend=0, blacklist=0}
    local rosterContext = {}
    local expiry, playerFaction, factionRead
    if not at and ((A.targetCheck and A.targetCheck.hasSightings()) or (A.whoLookup and A.whoLookup.hasReports())) then at=now() end
    if revision ~= refreshRevision then return end
    local complete = store.eachActive(A.region, function(record)
        local item = { id=record.id, region=record.region, guid=record.guid, fullName=record.fullName, membership=record.membership,
            note=record.note, role=record.role, reasonIds=book.copy(record.reasonIds), createdAt=record.createdAt, updatedAt=record.updatedAt,
            favorite=record.membership=="friend" and record.favorite==true, identityState=record.identityState,
            whisperMuted=record.whisperMuted }
        if record.lastKnown then
            local class = record.lastKnown.class and record.lastKnown.class.value
            if record.membership == "friend" then
                item.class = class
                item.level = record.lastKnown.level and record.lastKnown.level.value
                if class then item.evidenceName = item.fullName end
            elseif record.membership == "blacklist" then
                item.blacklistSavedClass = class
                item.blacklistFaction = record.lastKnown.faction and record.lastKnown.faction.value
                item.blacklistGuid = record.lastKnown.guid
            end
        end
        if A.targetCheck then
            local due = A.targetCheck.apply(item,at)
            if due and (not expiry or due<expiry) then expiry=due end
        end
        if item.membership == "friend" and item.faction then
            if not factionRead then
                playerFaction = A.playerFaction(item.region)
                factionRead = true
            end
            item.localChecksOnly = playerFaction ~= nil and item.faction ~= playerFaction
        end
        if A.relogRefresh then A.relogRefresh.apply(item, record, rosterContext) end
        if A.whoLookup then
            local due = A.whoLookup.apply(item, at)
            if due and (not expiry or due < expiry) then expiry = due end
        end
        -- A roster API can dispatch an event and rebuild the view before returning.
        if revision ~= refreshRevision then return false end
        rebuilt[#rebuilt + 1] = item
        counts[item.membership] = counts[item.membership] + 1
    end)
    if not complete then return end
    for i = #A.records, 1, -1 do A.records[i] = nil end
    for i, item in ipairs(rebuilt) do A.records[i] = item end
    A.counts=counts
    A.recordsStore=store
    nextSightingExpiry=expiry
    if not metadataOnly and P.BlacklistBanner.sightingsBookChanged then P.BlacklistBanner.sightingsBookChanged() end
end
A.refresh = refresh
function A.refreshSightingAge()
    local deadline=nextSightingExpiry
    if not deadline then return false end
    local at=now()
    if deadline~=nextSightingExpiry or not at or at<deadline then return false end
    refresh(at)
    return true
end
function A.init()
    if A.initialized then return end
    A.initialized = true
    A.region = currentRegion()
    if not A.region then A.error = "Region unavailable; address book is read-only."; return end
    local store, issue = namespace.AddressBook.open(WhowhoAddressBookDB)
    if not store then A.error = P.L("Address book cannot be opened; saved data preserved (%s).",issue); return end
    A.store = store
    refresh()
end
local function prepare(record)
    local store, region = A.store, A.region
    if not store then return nil, A.error or "Address book unavailable." end
    if currentRegion() ~= region then return nil, "Region unavailable or changed; no changes saved." end
    local at = now()
    if not at then return nil, "Time unavailable; no changes saved." end
    if currentRegion() ~= region or A.region ~= region or A.store ~= store then
        return nil, "Region or address book changed; no changes saved."
    end
    -- Never move a stored timestamp backwards if the server clock regresses.
    local current = record and store.get(record.id)
    if record and (not current or current.region ~= record.region or current.fullName ~= record.fullName
        or current.guid ~= record.guid or (record.membership and current.membership ~= record.membership)) then
        return nil, "Record changed; no changes saved."
    end
    if current and at < current.updatedAt then at = current.updatedAt end
    local candidate = namespace.AddressBook.open(store.export())
    if not candidate then return nil, "Address book unavailable; no changes saved." end
    return candidate, at
end
local function publish(candidate, metadataOnly)
    A.store = candidate
    WhowhoAddressBookDB = candidate.export()
    refresh(nil, metadataOnly)
end
local function publishObservation(record, validate, update, commitSession)
    local original = A.store
    if not original or currentRegion() ~= A.region then return false end
    local current = original.get(record.id)
    if not current or current.membership ~= "friend" or current.region ~= record.region
        or current.fullName ~= record.fullName or current.guid ~= record.guid then return false end
    local candidate = namespace.AddressBook.open(original.export())
    if not candidate then return false end
    local saved, issue = update(candidate)
    if not saved and issue ~= "unchanged" then return false end
    if currentRegion() ~= A.region or not validate() or A.store ~= original then return false end
    current = original.get(record.id)
    if not current or current.membership ~= "friend"
        or current.region ~= record.region or current.fullName ~= record.fullName or current.guid ~= record.guid then return false end
    -- The view rebuild in publish can call native readers and reenter roster refresh.
    if commitSession then commitSession() end
    if saved then publish(candidate) end
    return true, saved ~= nil
end
local function durableEvidence(evidence)
    if evidence.source == "chat" then
        return {
            region=evidence.region, name=evidence.name, guid=evidence.guid,
            source="Chat", at=evidence.at, class=evidence.class, cacheValid=evidence.cacheValid,
        }
    end
    return evidence
end
local function saveMetadata(candidate, record, evidence, missingOnly)
    evidence = durableEvidence(evidence)
    if record.membership == "blacklist" then return candidate.observeBlacklist(record.id, evidence, missingOnly) end
    local known = missingOnly and record.lastKnown or {}
    local class = not known.class and evidence.class or nil
    local level = not known.level and evidence.level or nil
    if not class and not level then return false end
    return candidate.observe(record.id, evidence.region, evidence.name, evidence.guid, evidence.source, evidence.at, class, level)
end
local function publishMetadata(store, record, evidence, owns)
    if not owns() then return false end
    local candidate = namespace.AddressBook.open(store.export())
    if not candidate or not saveMetadata(candidate, record, evidence, true)
        or (evidence.validate and not evidence.validate()) or not owns() then return false end
    if evidence.cacheValid and not evidence.cacheValid() then return false end
    publish(candidate, true)
    return true
end
function A.publishPlayerEvidence(evidence)
    local store, region = A.store, A.region
    local function owns()
        return currentRegion() == region and A.store == store and A.region == region
    end
    if evidence.source ~= "chat" or not store or evidence.region ~= region or not owns() then return false end
    local record = store.find(region, evidence.name, evidence.guid)
    if not record or (record.lastKnown and record.lastKnown.class) or not evidence.class then return false end
    if not publishMetadata(store, record, evidence, owns) then return false end
    local shell = P.Shell
    if shell then
        if record.membership == "friend" then shell.RefreshFriends() else shell.RefreshBlacklistMetadata() end
    end
    return true
end
local function effectiveGuid(record)
    return record.guid or (record.lastKnown and record.lastKnown.guid)
end
function A.observe(record, guid, source, at, class, level, validate, hint, commitSession)
    return publishObservation(record, validate, function(candidate)
        return candidate.observe(record.id, record.region, record.fullName, guid, source, at, class, level, hint)
    end, commitSession)
end
function A.guildAbsent(record, guid, club, at, validate, commitSession)
    return publishObservation(record, validate, function(candidate)
        return candidate.guildAbsent(record.id, record.region, record.fullName, guid, club, at)
    end, commitSession)
end
function A.checkFriend(record, supplement)
    if A.whoLookup.running(record.id) then return "Who check already running." end
    local previous = A.targetCheck.attempts[record.id]
    local message, remoteEligible = A.targetCheck.check(record)
    local attempt = A.targetCheck.attempts[record.id]
    local store, region = A.store, A.region
    local current = store and store.get(record.id)
    if supplement ~= false and attempt and attempt ~= previous and (attempt.observed or remoteEligible)
        and current and current.membership == "friend" and current.region == region
        and current.fullName == record.fullName and not (current.lastKnown and current.lastKnown.class) then
        local function owns()
            return currentRegion() == region and A.store == store and A.region == region
                and A.targetCheck.attempts[record.id] == attempt
        end
        local seen = attempt.observed and A.targetCheck.observations[record.id]
        local expected = seen and seen.guid or effectiveGuid(current)
        local observed = A.playerEvidence.resolve(current.fullName, store, region, expected, owns)
        if observed and observed.class then publishMetadata(store, current, observed, owns) end
        if A.targetCheck.attempts[record.id] ~= attempt then return message end
    end
    if not remoteEligible then return message end
    local whoMessage, warning = A.whoLookup.request(record)
    if whoMessage and attempt and A.targetCheck.attempts[record.id] == attempt
        and (attempt.message ~= whoMessage or attempt.warning ~= (warning == true)) then
        attempt.message, attempt.warning = whoMessage, warning == true
        A.refresh()
    end
    return whoMessage or message
end
local function commit(candidate,record,transition,beforePublish)
    local defer=P.BlacklistBanner.deferNewBlacklist
    if (transition=="add" or transition=="move") and record.membership=="blacklist" and defer then
        if not defer(record,A.store,beforePublish) then return nil,"Address book changed; try again." end
    elseif beforePublish and not beforePublish() then
        return nil,"Address book changed; try again."
    end
    if transition=="move" or transition=="blacklistEdit" then A.whoLookup.forget(record.id) end
    -- A returning Friend must not show check data from before it left.
    if transition=="move" and record.membership=="friend" then
        A.targetCheck.forget(record.id)
        A.relogRefresh.forget(record.id)
    end
    publish(candidate)
    for _, item in ipairs(A.records) do if item.id == record.id then return item end end
end
function A.setFavorite(old, favorite)
    if not old or old.membership ~= "friend" or type(favorite) ~= "boolean" then
        return nil, "Choose a saved Friend."
    end
    local candidate, at = prepare(old)
    if not candidate then return nil, at end
    local current = candidate.get(old.id)
    if not current or (current.favorite == true) ~= (old.favorite == true) then
        return nil, "Favorite changed; try again."
    end
    local record, issue = candidate.edit(old.id, {favorite=favorite}, at)
    if not record then return nil, P.L("Favorite not saved (%s).",issue) end
    local saved = commit(candidate, record)
    if not saved then return nil, "Friend changed; try again." end
    return saved
end
function A.setChatMuted(old, expected, isReachable, ownsBinding)
    local mute = A.chatMute
    if not mute.available() or not mute.canMute(old) then return nil, "Chat muting is unavailable." end
    local store, region = A.store, A.region
    if not isReachable() or A.store ~= store or A.region ~= region then
        return nil, "Record changed; no changes saved."
    end
    local candidate, at = prepare(old)
    if not candidate then return nil, at end
    local current = candidate.get(old.id)
    -- Region and clock reads may have opened a modal. Ownership checks follow
    -- the final native reachability read in case that read also reenters.
    if not isReachable() or A.store ~= store or A.region ~= region or not ownsBinding()
        or not mute.canMute(current) or current.whisperMuted ~= old.whisperMuted
        or mute.muted(current) ~= expected then return nil, "Record changed; no changes saved." end
    local record, issue = candidate.setChatMuted(old.id, not expected, at)
    if not record then return nil, P.L("Not saved (%s).",issue) end
    publish(candidate)
    return true
end
function A.playerAddIdentity(token, store, region, owns)
    local reader = A.unitReader
    local function owned()
        return A.store == store and A.region == region and (not owns or owns())
    end
    if not store or not region or not owned() or currentRegion() ~= region then return end
    local name, guid, state = reader.playerIdentity(token, owned)
    if not name then return nil, nil, state end
    if not reader.samePlayer(token, name, guid, owned) or currentRegion() ~= region or not owned() then return end
    return name, guid
end

function A.captureFriendMetadata(token, store, region, name, guid)
    local read, reader = A.nativeRead.read, A.unitReader
    local evidence = {store=store, region=region, name=name, guid=guid, source="Player menu"}
    local function safe()
        if read(InCombatLockdown) ~= false then return false end
        local currentName, currentGuid = A.playerAddIdentity(token, store, region)
        return currentName == name and currentGuid == guid
            and read(InCombatLockdown) == false and A.store == store and A.region == region
    end
    if read(InCombatLockdown) ~= false then return evidence end
    local profile = reader.playerMetadata(token, safe, {class=true, level=true, faction=true})
    if not profile then return nil, true end
    local at = (profile.class or profile.level or profile.faction) and now() or nil
    if not safe() then return nil, true end
    evidence.class, evidence.level, evidence.at = profile.class, profile.level, at
    evidence.faction = profile.faction
    return evidence
end

function A.captureBlacklistMetadata(token, store, region, name, guid, source, owns, known)
    local read, reader = A.nativeRead.read, A.unitReader
    local function owned()
        return A.store == store and A.region == region and (not owns or owns())
    end
    if not owned() then return nil, true end
    if read(InCombatLockdown) ~= false then return end
    local data = reader.playerMetadata(token, owned, {class=not known or not known.class, faction=not known or not known.faction})
    if not data then return nil, true end
    local class, faction = data.class, data.faction
    local at = (class or faction) and owned() and now() or nil
    local safe = read(InCombatLockdown) == false
    local currentName, currentGuid = A.playerAddIdentity(token, store, region, owned)
    if not owned() or not safe or currentName ~= name or currentGuid ~= guid then return nil, true end
    if at then
        return {store=store, token=token, region=region, name=name, guid=guid, class=class,
            faction=faction, source=source, at=at}
    end
    return nil, nil, class ~= nil or faction ~= nil
end

function A.saveBlacklistObservations(store, region, observations, owns, metadataOnly)
    local candidate, leases
    for _, observation in ipairs(observations) do
        local id, evidence = observation.id, observation.evidence
        if not owns() then return end
        if store.needsBlacklistObservation(id, evidence) then
            if A.nativeRead.read(InCombatLockdown) ~= false or not owns()
                or observation.owns and not observation.owns() then return end
            if observation.validate then
                if not observation.validate() or not owns() then return end
            else
                local name, guid = A.playerAddIdentity(evidence.token, store, region)
                if name ~= evidence.name or guid ~= evidence.guid or not owns() then return end
            end
            candidate = candidate or namespace.AddressBook.open(store.export())
            if not candidate then return store end
            candidate.observeBlacklist(id, evidence)
            local lease = observation.validate or observation.owns
            if lease then
                leases = leases or {}
                leases[#leases + 1] = lease
            end
        end
    end
    if not candidate then return store end
    if currentRegion() ~= region or not owns() then return end
    if leases then
        for _, ownsLease in ipairs(leases) do
            if not ownsLease() then return end
        end
        if currentRegion() ~= region or not owns() then return end
    end
    for _, observation in ipairs(observations) do
        local evidence = observation.evidence
        if evidence.cacheValid and not evidence.cacheValid() then return end
    end
    publish(candidate, metadataOnly)
    return candidate
end

function A.tryBlacklistMetadata(subject, owns)
    local store, region = A.store, subject.region
    local function owned()
        return A.store == store and A.region == region and owns()
    end
    if not owned() then return end
    local current = store.get(subject.id)
    if not current or current.region ~= region or current.fullName ~= subject.fullName or current.membership ~= "blacklist" then return end
    local observations, matchedGuid = {}, effectiveGuid(current)
    local hasClass = current.lastKnown and current.lastKnown.class
    for _, source in ipairs({"Target", "Mouseover"}) do
        if not owned() then return end
        local token = source:lower()
        local name, guid = A.playerAddIdentity(token, store, region)
        if name == subject.fullName then
            local record = store.find(region, name, guid)
            if not record or record.id ~= subject.id or (matchedGuid and matchedGuid ~= guid) then return end
            matchedGuid = guid
            local evidence, changed = A.captureBlacklistMetadata(token, store, region, name, guid, source, owned, record.lastKnown)
            if changed then return end
            if evidence then
                observations[#observations + 1] = {id=subject.id, evidence=evidence}
                hasClass = hasClass or evidence.class
            end
        end
    end
    if not hasClass and owned() then
        local evidence = A.playerEvidence.resolve(subject.fullName, store, region, matchedGuid, owned, true)
        if evidence and evidence.class and evidence.validate then
            observations[#observations + 1] = {id=subject.id, evidence=durableEvidence(evidence), validate=evidence.validate}
        end
    end
    if not owned() then return end
    local settled = A.saveBlacklistObservations(store, region, observations, owned, true)
    if not settled or A.store ~= settled or A.region ~= region then return end
    for _, item in ipairs(A.records) do
        if item.id == subject.id then return item end
    end
end

function A.currentCharacterName()
    if not A.unitReader.identitySafe("player") then return nil end
    local readable = A.nativeRead.readable
    local ok, first, surname = pcall(UnitNameUnmodified, "player")
    if not ok or not readable(first) or type(first) ~= "string"
        or not readable(surname) or type(surname) ~= "string" then return nil end
    local playerName = first .. " " .. surname
    if P.CharacterName.IsComplete(playerName) then return playerName end
end
local function addNameError(name)
    local unavailable = "Your character's name is unavailable. Try again shortly."
    local playerName = A.currentCharacterName()
    if not playerName then return unavailable end
    local comparison = A.nativeRead.read(strcmputf8i, name, playerName)
    if type(comparison) ~= "number" or comparison ~= comparison then return unavailable end
    if comparison == 0 then return "You can't add your current character." end
end
function A.save(old, section, name, note, role, reasons, moving, evidence, ownsSave)
    local store, region = A.store, A.region
    if not A.text(name) or not A.text(note) then return nil, "Text unavailable; no changes saved." end
    local draft = old and old.identityState == "unresolved"
    local partial = section=="friend" and not moving and P.CharacterName.IsFriendDraft(name)
    if draft and (section~="friend" or moving) then return nil, "Resolve the draft before moving it." end
    if old and not draft and old.fullName ~= name then return nil, "Renaming requires identity reconciliation; name unchanged." end
    if (not old or draft or moving) and not partial then
        if not P.CharacterName.IsComplete(name) then return nil, "Enter a full two-part name." end
        local issue = addNameError(name)
        if issue then return nil, issue end
    end
    local candidate, at = prepare(old)
    if not candidate then return nil, at end
    local record, issue
    local quickAdd = not old and evidence and evidence.quickAdd
    local direct = quickAdd and evidence.direct
    local sameStore = quickAdd and evidence.store == store
    local picked = quickAdd and evidence.name == name and evidence.region == region
    if moving then
        record, issue = candidate.move(old.id, "blacklist", at, reasons)
        if record then record, issue = candidate.edit(old.id, { note=note, reasonIds=reasons }, at) end
    elseif draft then
        if partial then
            record, issue = candidate.edit(old.id, {fullName=name,note=note,role=role or false}, at)
        else
            record, issue = candidate.resolve(old.id, A.region, name, nil, at)
            if record then record, issue = candidate.edit(old.id, {note=note,role=role or false}, at) end
        end
    elseif old then
        local changes = { note=note }
        if section == "blacklist" then changes.reasonIds=reasons else changes.role=role or false end
        record, issue = candidate.edit(old.id, changes, at)
    else
        local input = {fullName=name, identityState=partial and "unresolved" or "resolved",
            membership=section, note=note, role=role, reasonIds=reasons}
        if not partial then input.region=A.region end
        if picked and evidence.guid then
            local _, conflict = candidate.find(region, name, evidence.guid)
            if conflict == "conflict" then return nil, "Record changed; no changes saved." end
        end
        record, issue = candidate.add(input, at)
    end
    if not record then return nil, P.L("Not saved (%s).",issue) end
    local transition=moving and "move" or (not old and "add" or section=="blacklist" and "blacklistEdit" or nil)
    local function owned()
        return currentRegion() == region and (not ownsSave or ownsSave()) and A.store == store and A.region == region
    end
    local function beforePublish()
        if not owned() then return false end
        local ordinary = not quickAdd and not partial and not moving and (not old or draft)
            and (section == "friend" or evidence)
        if ordinary then
            local captured, conflict = A.playerEvidence.refreshCaptured(evidence, name, store, region, owned)
            if conflict then return false end
            local resolved = captured
            if not resolved or not resolved.class then
                resolved = A.playerEvidence.cachedChat(name, store, region, captured and captured.guid, owned)
                if resolved and resolved.validate and not resolved.validate() then resolved = nil end
            end
            if not owned() then return false end
            if resolved and resolved.cacheValid and not resolved.cacheValid() then resolved = nil end
            if captured then saveMetadata(candidate, record, captured) end
            if resolved and resolved ~= captured then saveMetadata(candidate, record, resolved) end
        end
        if picked then
            local resolved
            local prefill = evidence.observation
            if direct and direct.source == "Chat menu" then
                direct = A.playerEvidence.refreshChat(direct, store, region, owned)
            elseif direct then
                local conflict
                direct, conflict = A.playerEvidence.refreshCaptured(direct, name, store, region, owned)
                if conflict then return false end
            end
            if not direct or not direct.class then
                if prefill and prefill ~= evidence.direct and prefill.class then
                    if prefill.source == "chat" then
                        resolved = A.playerEvidence.refreshChat(prefill, store, region, owned)
                    elseif sameStore and prefill.validate and prefill.validate() then
                        resolved = prefill
                    end
                end
                if not resolved then
                    local expectedGuid = evidence.guid or prefill and prefill.guid
                    resolved = A.playerEvidence.resolve(name, store, region, expectedGuid, owned)
                    if resolved and resolved.validate and not resolved.validate() then resolved = nil end
                end
            end
            if not owned() then return false end
            if resolved and resolved.cacheValid and not resolved.cacheValid() then resolved = nil end
            if direct then
                saveMetadata(candidate, record, direct)
            end
            if resolved then saveMetadata(candidate, record, resolved) end
            local profile = direct and direct.faction and direct or resolved
            local match = section == "friend" and profile and candidate.find(region, name, profile.guid)
            if profile and profile.faction and match and match.id == record.id then
                A.targetCheck.rememberQuickAdd(record.id, profile)
            end
        end
        return true
    end
    local saved,commitIssue=commit(candidate,record,transition,beforePublish)
    if not saved then return nil,commitIssue end
    if not partial and (not old or draft) and section == "friend" and not moving and A.targetCheck
        and (not quickAdd or picked and evidence.source == "Player menu") then
        pcall(quickAdd and A.targetCheck.check or A.checkFriend, saved, false)
        for _, item in ipairs(A.records) do if item.id == saved.id then return item end end
    end
    return saved
end
function A.reasonText(ids, separator)
    if not book.validReasons(ids) then return "" end
    local labels = {}
    for _, id in ipairs(ids) do labels[#labels+1] = A.reasonLabel(id) end
    return table.concat(labels, separator or ", ")
end
A.reasons = book.reasons
function A.reasonLabel(id) return P.L(book.reasonLabel(id)) end
A.validReasons = book.validReasons
function A.move(old)
    if old.identityState=="unresolved" then return nil, "Resolve the draft before moving it." end
    local nameIssue = addNameError(old.fullName)
    if nameIssue then return nil, nameIssue end
    local candidate, at = prepare(old)
    if not candidate then return nil, at end
    local target = old.membership == "friend" and "blacklist" or "friend"
    local record, issue = candidate.move(old.id, target, at)
    if not record then return nil, P.L("Not moved (%s).",issue) end
    return commit(candidate,record,"move")
end
function A.delete(target)
    local candidate, issue = prepare(target)
    if not candidate then return nil, issue end
    local current = candidate.get(target.id)
    if not current or current.region ~= target.region or current.fullName ~= target.fullName or current.guid ~= target.guid then
        return nil, "Record changed; nothing deleted."
    end
    local ok, reason = candidate.delete(target.id, target.region, target.fullName, target.guid)
    if not ok then return nil, P.L("Not deleted (%s).",reason) end
    A.targetCheck.forget(target.id)
    A.relogRefresh.forget(target.id)
    A.whoLookup.forget(target.id)
    publish(candidate)
    return true
end
