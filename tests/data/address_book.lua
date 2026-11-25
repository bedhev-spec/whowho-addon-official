local book = assert(loadfile("WhoWho/AddressBook.lua"))()
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function reject(operation, expected) local value, errorValue = operation(); check(value == nil and errorValue == expected, expected) end
local store = assert(book.open())
local function add(name, region, guid, extra)
    local input = extra or {}
    input.fullName, input.region, input.guid = name, region, guid
    input.identityState, input.membership = "resolved", input.membership or "friend"
    return store.add(input, 100)
end
local first = assert(add("Élan Amber", 3, "guid-a", { note = "original", reasonIds = { "r1" }, incidentRefs = { "i1" } }))
local other = assert(add("Élan Silver", 3, "guid-b"))
local cross = assert(add("Élan Amber", 4, "guid-a"))
local external = { fullName = "Alias Cedar", region = 3, identityState = "resolved", membership = "friend", reasonIds = { "safe" } }
local isolated = assert(store.add(external, 100))
external.reasonIds[1] = "changed"
check(assert(store.get(isolated.id)).reasonIds[1] == "safe", "add input isolation")
check(first.id ~= other.id and other.id ~= cross.id, "stable unique ids")
check(assert(store.find(3, "Élan Amber")).id == first.id, "same region shared lookup")
check(assert(store.find(4, "Élan Amber")).id == cross.id, "separate region")
reject(function() return store.find(3, "élan Amber") end, "not_found")
reject(function() return add("Élan Amber", 3, "guid-a", { note = "overwrite", membership = "blacklist", reasonIds = { "other" } }) end, "duplicate")
reject(function() return add("Élan Amber", 3, "guid-new") end, "conflict")
reject(function() return add("New Cedar", 3, "guid-a") end, "conflict")
reject(function() return store.find(3, "Élan Amber", "guid-b") end, "conflict")
local unchanged = assert(store.get(first.id))
check(unchanged.note == "original" and unchanged.membership == "friend", "duplicates cannot edit or move")
local draft = assert(store.add({ fullName = "Élan", identityState = "unresolved", membership = "friend" }, 100))
local active = assert(store.activeRecords(3))
check(active[first.id].region == 3 and active[draft.id].identityState == "unresolved" and active[cross.id] == nil,
    "active snapshot includes only the selected region and global drafts")
active[first.id].reasonIds[1], active[draft.id].fullName = "mutated", "Changed"
active[other.id] = nil
check(store.get(first.id).reasonIds[1] == "r1" and store.get(draft.id).fullName == "Élan" and store.get(other.id),
    "active snapshot changes cannot mutate saved records")
local unused = assert(store.activeRecords("unused"))
check(unused[draft.id] and next(unused, draft.id) == nil and next(unused) == draft.id, "unused region has only global drafts")
reject(function() return store.activeRecords(nil) end, "invalid_region")
reject(function() return store.activeRecords(0/0) end, "invalid_region")
reject(function() return store.find(3, "Élan") end, "not_found")
reject(function() return store.resolve(draft.id, 3, "Élan Amber", "guid-new", 110) end, "conflict")
check(assert(store.get(draft.id)).identityState == "unresolved", "failed resolution atomic")
check(assert(store.resolve(draft.id, 3, "Élan Copper", "guid-c", 110)).id == draft.id, "explicit resolution preserves id")
check(assert(store.find(3, "Élan Copper", "guid-c")).updatedAt == 110, "resolved index and timestamp")
reject(function() return store.move(first.id, "blacklist", 120) end, "invalid_reasons")
check(assert(store.get(first.id)).membership == "friend", "failed move leaves record unchanged")
reject(function() return add("Invalid Cedar", 3, nil, { membership = "blacklist", reasonIds = { "unknown" } }) end, "invalid_reasons")
local sparse = { [2]="sabotage", [3]="ninja_looting", [4]="camping" }
reject(function() return add("Sparse Cedar", 3, nil, { membership = "blacklist", reasonIds = sparse }) end, "invalid_reasons")
reject(function() return store.move(first.id, "blacklist", 120, sparse) end, "invalid_reasons")
check(assert(store.get(first.id)).membership == "friend", "sparse move cannot mutate entry")
local moved = assert(store.move(first.id, "blacklist", 120, { "other" }))
check(moved.createdAt == 100 and moved.updatedAt == 120, "move timestamps")
check(moved.note == "original" and moved.reasonIds[1] == "other" and moved.incidentRefs[1] == "i1", "move preserves metadata")
moved.reasonIds[1] = "mutated"
check(assert(store.get(first.id)).reasonIds[1] == "other", "output isolation")
reject(function() return store.edit(first.id, { note = "lost", reasonIds = {} }, 125) end, "invalid_reasons")
check(assert(store.get(first.id)).note == "original", "invalid reason edit rolls back note")
local updated = assert(store.edit(first.id, { reasonIds = { "griefing", "other" } }, 125))
check(updated.note == "original" and updated.incidentRefs[1] == "i1" and #updated.reasonIds == 2, "reason-only edit preserves note and history")
assert(store.edit(first.id, { reasonIds = { "other" } }, 126))
local changes = { role = "HEALER", note = string.rep("é", 256) }
check(assert(store.edit(first.id, changes, 130)).role == "HEALER", "valid scalar note")
reject(function() return store.edit(first.id, { role = "TANK", note = string.rep("a", 257) }, 140) end, "invalid_edit")
reject(function() return store.edit(first.id, { note = string.char(0xED, 0xA0, 0x80) }, 140) end, "invalid_edit")
reject(function() return store.move(first.id, "friend", 129) end, "invalid_timestamp")
reject(function() return store.edit(first.id, { role = "TANK" }, 0/0) end, "invalid_timestamp")
check(assert(store.get(first.id)).role == "HEALER", "edit failure atomic")
check(assert(store.get(first.id)).updatedAt == 130, "failed timestamp operations atomic")
check(assert(store.edit(first.id, { role = false, note = false }, 140)).note == nil, "clear optional fields")
local exported = store.export()
exported.regions[3][first.id].reasonIds[1] = "outside"
check(assert(store.get(first.id)).reasonIds[1] == "other", "export isolation")
local saved = store.export()
check(saved.byId == nil and saved.byName == nil and saved.byGuid == nil, "indexes excluded from export")
local reopened = assert(book.open(saved))
check(assert(reopened.find(3, "Élan Copper", "guid-c")).id == draft.id, "indexes rebuilt on open")
reject(function() return reopened.find(3, "Élan Copper", "guid-a") end, "conflict")
saved.regions[3][first.id].reasonIds[1] = "changed after open"
check(assert(reopened.get(first.id)).reasonIds[1] == "other", "input isolation")
check(assert(book.open(reopened.export())).get(first.id).membership == "blacklist", "repeated roundtrip")
local legacy = reopened.export(); legacy.regions[3][first.id].reasonIds = { "unknown" }
local legacyStore = assert(book.open(legacy))
reject(function() return legacyStore.edit(first.id, { note = "changed" }, 140) end, "invalid_reasons")
check(assert(legacyStore.get(first.id)).reasonIds[1] == "unknown", "unknown legacy reason preserved")
check(assert(legacyStore.edit(first.id, { reasonIds = { "other" } }, 140)).reasonIds[1] == "other", "explicit recovery")
legacy.regions[3][first.id].reasonIds = sparse
local sparseLegacy = assert(book.open(legacy))
reject(function() return sparseLegacy.edit(first.id, { note = "changed" }, 140) end, "invalid_reasons")
check(assert(sparseLegacy.get(first.id)).reasonIds[2] == "sabotage", "sparse legacy data retained on failure")
check(assert(sparseLegacy.edit(first.id, { reasonIds = { "other" } }, 140)).reasonIds[1] == "other", "sparse legacy data recovered explicitly")
local future = { schemaVersion = 999, regions = { preserved = true } }
reject(function() return book.open(future) end, "unsupported_version")
check(future.regions.preserved, "future input retained")
local invalid = { schemaVersion = 1, nextId = 1, regions = {}, drafts = { broken = true } }
reject(function() return book.open(invalid) end, "invalid_data")
check(invalid.drafts.broken, "invalid input retained")
local missingTime = store.export(); missingTime.regions[3][first.id].createdAt = nil
missingTime.regions[3][first.id].note = "recoverable sentinel"
reject(function() return book.open(missingTime) end, "invalid_data")
check(missingTime.regions[3][first.id].note == "recoverable sentinel", "invalid current data preserved")
local cyclic = {}; cyclic.self = cyclic
reject(function() return store.add({ fullName = "Example Cedar", identityState = "resolved", region = 3, membership = "friend", extra = cyclic }, 100) end, "invalid_record")
reject(function() return store.add({ fullName = "Example Cedar", identityState = "resolved", region = 3, membership = "friend", extra = function() end }, 100) end, "invalid_record")
reject(function() return store.add({ fullName = "Example Cedar", identityState = "resolved", region = 3, membership = "friend", extra = coroutine.create(function() end) }, 100) end, "invalid_record")
reject(function() return store.add({ fullName = "Example Cedar", identityState = "resolved", region = 3, membership = "friend" }, math.huge) end, "invalid_record")
reject(function() return book.open({ schemaVersion = 1, nextId = 1, regions = {}, drafts = {}, bad = 0/0 }) end, "invalid_data")
reject(function() return book.open(setmetatable({}, {})) end, "invalid_data")
reject(function() return store.delete(first.id, 3, "Wrong Name", "guid-a") end, "stale_identity")
check(store.delete(first.id, 3, "Élan Amber", "guid-a"), "explicit delete")
reject(function() return store.find(3, "Élan Amber", "guid-a") end, "not_found")
local archived = store.export().archived[first.id]
check(archived.fullName == "Élan Amber" and archived.reasonIds[1] == "other" and archived.incidentRefs[1] == "i1", "history identity and references retained")
check(archived.note == nil and archived.role == nil and archived.membership == nil, "active details removed")
local restored = assert(book.open(store.export()))
check(restored.export().archived[first.id].incidentRefs[1] == "i1", "archive survives reopen")
local replacement = assert(add("Élan Amber", 3, "guid-a"))
check(replacement.id ~= first.id and replacement.note == nil, "re-add is new identity without old note")
reject(function() return store.delete(first.id, 3, "Élan Amber", "guid-a") end, "stale_identity")
check(assert(store.find(3, "Élan Amber")).id == replacement.id, "stale delete cannot remove replacement")
local badArchive = store.export(); badArchive.archived[first.id].note = "bad"
reject(function() return book.open(badArchive) end, "invalid_data")
check(badArchive.archived[first.id].note == "bad", "malformed archive retained for recovery")
local evidence = assert(book.open())
local hintFriend = assert(evidence.add({fullName="Hint North",region=3,identityState="resolved",membership="friend"},100))
check(evidence.observe(hintFriend.id,3,hintFriend.fullName,"hint-guid","Recent Allies",101,nil,nil,true), "hint-only cache evidence saved")
check(evidence.observe(hintFriend.id,3,hintFriend.fullName,"hint-guid","Guild",102,nil,nil,5), "hint-only guild evidence saved")
check(evidence.observe(hintFriend.id,3,hintFriend.fullName,"hint-guid","Guild",103,nil,nil,6), "new guild scope replaces old")
local hints=assert(assert(book.open(evidence.export())).get(hintFriend.id)).lastKnown
check(hints.guid=="hint-guid" and hints.sources.guild.clubId==6 and hints.sources.guild.at==103 and hints.sources.recentAlliesAt==101, "hints survive reload with identity")
reject(function() return evidence.observe(hintFriend.id,3,hintFriend.fullName,"wrong","Guild",104,nil,nil,6) end, "conflict")
reject(function() return evidence.observe(hintFriend.id,3,hintFriend.fullName,"hint-guid","Party",104,nil,nil,6) end, "invalid_observation")
reject(function() return evidence.guildAbsent(hintFriend.id,3,hintFriend.fullName,"hint-guid",5,104) end, "stale_identity")
reject(function() return evidence.guildAbsent(hintFriend.id,3,hintFriend.fullName,"hint-guid",6,103) end, "stale_observation")
check(evidence.guildAbsent(hintFriend.id,3,hintFriend.fullName,"hint-guid",6,104), "guild absence saved")
hints=assert(assert(book.open(evidence.export())).get(hintFriend.id)).lastKnown
check(hints.guid=="hint-guid" and hints.sources.guild.at==103 and hints.sources.guild.absentAt==104 and hints.sources.recentAlliesAt==101, "absence survives reload without discarding hints or binding")
reject(function() return evidence.observe(hintFriend.id,3,hintFriend.fullName,"hint-guid","Guild",103,nil,nil,6) end, "unchanged")
check(evidence.observe(hintFriend.id,3,hintFriend.fullName,"hint-guid","Guild",104,nil,nil,6), "same-second guild match restores hint")
check(not assert(evidence.get(hintFriend.id)).lastKnown.sources.guild.absentAt, "restored membership clears absence")
local badHints=evidence.export(); badHints.regions[3][hintFriend.id].lastKnown.name="Wrong North"
check(not assert(assert(book.open(badHints)).get(hintFriend.id)).lastKnown, "mismatched identity discards hints")
local friend = assert(evidence.add({fullName="Sample North",region=3,identityState="resolved",membership="friend",note="keep"}, 100))
check(evidence.observe(friend.id,3,friend.fullName,"observed-guid","Recent Allies",101,"MAGE",42), "cache evidence saved")
check(evidence.observe(friend.id,3,friend.fullName,"observed-guid","Target",102,nil,55), "partial target saved")
check(evidence.observe(friend.id,3,friend.fullName,"observed-guid","Recent Allies",103,"PRIEST",60), "new cache fills only eligible fields")
reject(function() return evidence.observe(friend.id,3,friend.fullName,"observed-guid","Recent Allies",104,nil,60) end, "unchanged")
local known = assert(evidence.get(friend.id)).lastKnown
check(known.class.value=="PRIEST" and known.class.source=="Recent Allies" and known.level.value==55 and known.level.source=="Target", "field source priority")
check(assert(evidence.get(friend.id)).updatedAt==100 and assert(evidence.get(friend.id)).note=="keep", "evidence preserves edited fields")
reject(function() return evidence.observe(friend.id,3,friend.fullName,"wrong","Target",104,"MAGE",60) end, "conflict")
reject(function() return evidence.add({fullName="Other North",region=3,identityState="resolved",membership="friend",guid="observed-guid"}, 104) end, "conflict")
local corrupt=evidence.export(); corrupt.regions[3][friend.id].lastKnown.class={value="bad-token",source="Target",at=104}
local sanitized=assert(book.open(corrupt)); known=assert(sanitized.get(friend.id)).lastKnown
check(not known.class and known.level.value==55, "invalid optional field discarded")
local cyclicEvidence=evidence.export(); local loop={}; loop.self=loop
cyclicEvidence.regions[3][friend.id].lastKnown=loop
check(not assert(assert(book.open(cyclicEvidence)).get(friend.id)).lastKnown, "cyclic optional evidence discarded")
check(sanitized.delete(friend.id,3,friend.fullName,nil), "delete with original identity handle")
local again=assert(sanitized.add({fullName=friend.fullName,region=3,identityState="resolved",membership="friend"},105))
check(again.id~=friend.id and not again.lastKnown, "re-add does not inherit evidence")
local hoverFriend=assert(evidence.add({fullName="Hover North",region=3,identityState="resolved",membership="friend"},100))
check(evidence.observe(hoverFriend.id,3,hoverFriend.fullName,"hover-guid","Mouseover",101,"MAGE",50), "mouseover metadata saved")
reject(function() return evidence.observe(hoverFriend.id,3,hoverFriend.fullName,"hover-guid","Recent Allies",102,"PRIEST",60) end, "unchanged")
local hoverKnown=assert(assert(book.open(evidence.export())).get(hoverFriend.id)).lastKnown
check(hoverKnown.class.value=="MAGE" and hoverKnown.level.value==50 and hoverKnown.class.source=="Mouseover" and hoverKnown.level.source=="Mouseover", "mouseover direct metadata survives reload and cache")
local blocked=assert(evidence.add({fullName="Blocked North",region=3,identityState="resolved",
    membership="blacklist",reasonIds={"other"},note="keep blocked"},100))
local observed={region=3,name=blocked.fullName,guid="blacklist-guid",source="Player menu",at=101,class="MAGE",faction="Horde"}
check(evidence.needsBlacklistObservation(blocked.id,observed) and evidence.observeBlacklist(blocked.id,observed),
    "new verified Blacklist fields persist in the existing evidence")
observed.at=102
check(not evidence.needsBlacklistObservation(blocked.id,observed) and not evidence.observeBlacklist(blocked.id,observed),
    "unchanged class and faction do not update the store or timestamps")
observed.source,observed.class,observed.faction="Mouseover",nil,"Alliance"
check(evidence.observeBlacklist(blocked.id,observed),"a newer physical source updates only its readable faction")
observed.at,observed.faction=101,"Horde"
check(not evidence.observeBlacklist(blocked.id,observed),"older conflicting metadata cannot replace newer evidence")
observed.at,observed.guid=103,"wrong"
check(not evidence.observeBlacklist(blocked.id,observed),"verified metadata cannot change a saved GUID binding")
observed.guid,observed.region="blacklist-guid",4
check(not evidence.observeBlacklist(blocked.id,observed),"verified metadata cannot cross regions")
observed.region,observed.name=3,"Different Name"
check(not evidence.observeBlacklist(blocked.id,observed),"verified metadata cannot cross names")
local persisted=evidence.export()
local blockedKnown=assert(assert(book.open(persisted)).get(blocked.id)).lastKnown
check(blockedKnown.class.value=="MAGE" and blockedKnown.class.source=="Player menu"
    and blockedKnown.faction.value=="Alliance" and blockedKnown.faction.at==102,"class and faction roundtrip independently")
persisted.regions[3][blocked.id].lastKnown.faction={value="Neutral",source="Target",at=104}
local cleaned=assert(assert(book.open(persisted)).get(blocked.id))
check(cleaned.lastKnown.class.value=="MAGE" and not cleaned.lastKnown.faction
    and cleaned.updatedAt==100 and cleaned.note=="keep blocked","invalid faction preserves the old record and class")
persisted.regions[3][blocked.id].lastKnown.faction={value=loop,source="Target",at=104}
cleaned=assert(assert(book.open(persisted)).get(blocked.id))
check(cleaned.lastKnown.class.value=="MAGE" and not cleaned.lastKnown.faction,"damaged faction is dropped independently")
print("address book: " .. checks .. " checks passed")
