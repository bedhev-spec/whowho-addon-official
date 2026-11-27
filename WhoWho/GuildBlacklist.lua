local P = WhowhoPreview
local A = P.manual
local D, N = P.GuildBlacklistDetails, P.GuildBlacklistName
local read, readable, safeTable, member = A.nativeRead.read, A.nativeRead.readable, A.nativeRead.safeTable, A.nativeRead.member
local G = {}
P.GuildBlacklist = G

local PREFIX, CHANNEL = "WhowhoGuildBL1", "GUILD"
local MAX_PACKET, MAX_NAME, MAX_ROWS, MAX_SCOPES = 240, 160, 512, 32
local REVISION_TICKS, MAX_SERVER_TIME, CLOCK_SKEW = 128.0, 4294967295, 5
local MAX_REVISION = (MAX_SERVER_TIME+1)*REVISION_TICKS-1
local SEND_INTERVAL, SYNC_INTERVAL, REPLY_INTERVAL, MEMBERSHIP_SETTLE = 1.25, 30, 90, 0.75
local SCOPE_WAITS = {3, 6, 12, 24, 48, 84}
local MAX_MEMBERS, CONFIRM_DELAY, LEAVE_DELAY = 256, 3, 60
local SAMPLE_WINDOW, SAMPLE_LIFETIME, MAX_ACKS, MAX_RESPONDERS = 12, 60, 8, 1024
-- ChatConstantsDocumentation.lua for the pinned Forever build.
local SUCCESS, DUPLICATE_PREFIX, ADDON_THROTTLE, CHANNEL_THROTTLE, LOCKDOWN = 0, 1, 3, 8, 11
local CHAT_RESTRICTION, INACTIVE, ACTIVATING, ACTIVE = 5, 0, 1, 2
local classes = {
    WARRIOR=true, PALADIN=true, HUNTER=true, ROGUE=true, PRIEST=true, DEATHKNIGHT=true, SHAMAN=true,
    MAGE=true, WARLOCK=true, MONK=true, DRUID=true, DEMONHUNTER=true, EVOKER=true,
}
local installed, inWorld, registered, storageReady, chatRestricted
local state, status, generation, eventVersion = nil, "unavailable", 0, 0
local db, scopeCount, checking, settling, lastMembershipKey
local sighting, guildEvent, leaving, due, lastCharacter, homeRead
local nextSend = 0
local schedule, currentState

local function plain(value)
    return safeTable(value) and getmetatable(value) == nil
end

local function integer(value, max)
    return type(value) == "number" and value >= 1 and value <= max and value % 1 == 0
end

local function validName(name)
    return type(name) == "string" and #name <= MAX_NAME and not name:find("|",1,true)
        and P.CharacterName.IsComplete(name)
end

local function validRow(row)
    if not plain(row) or not readable(row.class) or not readable(row.rev) then return false end
    return row.class == nil and row.rev == 0
        or (type(row.class) == "string" and classes[row.class] and integer(row.rev,MAX_REVISION))
end

local function validReasons(ids)
    if not plain(ids) then return false end
    for key, id in pairs(ids) do
        if not readable(key) or not readable(id) then return false end
    end
    return A.validReasons(ids)
end

local function loadDetails(name, row)
    local ids, note, rev=row.reasonIds,row.note,row.noteRev
    if not readable(ids) or not readable(note) or not readable(rev) then return end
    if ids ~= nil and not validReasons(ids) then return end
    if note ~= nil or rev ~= nil then
        if not D.validNote(note) or not integer(rev,MAX_REVISION) then return end
    end
    return {name=name,class=row.class,rev=row.rev,reasonIds=D.mergeReasons(nil,ids),note=note,noteRev=rev}
end

local function scopeKey(region, club)
    if not integer(region, 2147483647) then return end
    if integer(club, 9007199254740991) then club=string.format("%.0f",club) end
    if type(club) ~= "string" or #club > 20 or not club:match("^[1-9]%d*$") then return end
    return string.format("%d:%s",region,club)
end

local function clock()
    local t=read(GetTime)
    if type(t) == "number" and t >= 0 and t < math.huge then return t end
end

-- Admit small clock differences without letting a peer outrank later evidence indefinitely.
local function revisionWindow()
    local at=read(GetServerTime)
    if integer(at,MAX_SERVER_TIME) then
        return at*REVISION_TICKS, math.min(MAX_REVISION,(at+CLOCK_SKEW+1)*REVISION_TICKS-1)
    end
end

local function nextRevision(first, last, previous)
    local revision=math.max(first,(previous or 0)+1)
    if revision <= last then return revision end
end

local function newer(incoming, old)
    return not old or incoming.rev > old.rev
        or (incoming.rev > 0 and incoming.rev == old.rev and incoming.class > old.class)
end

local function combine(old, name, classUpdate, reasonIds, note, noteRev)
    local base=old or {rev=0}
    local display=N.PreferDisplay(base.name,name)
    local classChanged=classUpdate and newer(classUpdate,old)
    local reasons=D.mergeReasons(base.reasonIds,reasonIds)
    local noteChanged=D.newerNote(note,noteRev,base.note,base.noteRev)
    if old and display == old.name and not classChanged and reasons == base.reasonIds and not noteChanged then
        return old
    end
    local evidence=classChanged and classUpdate or base
    return {name=display,class=evidence.class,rev=evidence.rev,reasonIds=reasons,
        note=noteChanged and note or base.note,noteRev=noteChanged and noteRev or base.noteRev}
end

local function putRow(data, identity, old, row)
    if not old then
        data.count=data.count+1
    elseif old.name ~= row.name then
        data.saved[old.name]=nil
    end
    data.rows[identity]=row
    data.saved[row.name]={class=row.class,rev=row.rev,reasonIds=row.reasonIds,note=row.note,noteRev=row.noteRev}
end

local function retainRow(data, identity, old, row)
    local displaced
    if not old then
        local last=data.lastIdentity
        if data.count == MAX_ROWS then
            -- Keep the first canonical keys in byte order. Once full, the cutoff can only move earlier.
            if N.PreferDisplay(identity,last) ~= identity then return false end
            displaced=last
            data.saved[data.rows[last].name]=nil
            data.rows[last]=nil
            data.count=data.count-1
            last=identity
            for key in pairs(data.rows) do
                if N.PreferDisplay(last,key) == last then last=key end
            end
        elseif not last or N.PreferDisplay(last,identity) == last then
            last=identity
        end
        data.lastIdentity=last
    end
    putRow(data,identity,old,row)
    return true, displaced
end

-- Newer revision wins; a tie goes to the removal.
local function supersedes(incoming, old)
    return not old or incoming.rev > old.rev
        or incoming.rev == old.rev and incoming.gone and not old.gone
end

local function putRecord(data, identity, record)
    data.removed[identity]=record
    local size, oldest, best=0
    for key, held in pairs(data.removed) do
        size=size+1
        if not best or held.rev < best.rev or held.rev == best.rev and N.PreferDisplay(key,oldest) == key then
            oldest,best=key,held
        end
    end
    -- shortcut: MAX_ROWS records per scope; a name whose record is dropped can return from a stale peer.
    if size > MAX_ROWS then data.removed[oldest]=nil end
end

local function dropRow(data, identity)
    local row=data.rows[identity]
    if not row then return end
    data.saved[row.name]=nil
    data.rows[identity]=nil
    data.count=data.count-1
    if data.lastIdentity == identity then
        local last
        for key in pairs(data.rows) do
            if not last or N.PreferDisplay(last,key) == last then last=key end
        end
        data.lastIdentity=last
    end
end

local function loadRecords(data, records)
    if not plain(records) then return end
    local size=0
    for name, record in pairs(records) do
        size=size+1
        if size > MAX_ROWS or not readable(name) or not validName(name) or not plain(record) then return end
        local rev, gone=record.rev, record.gone
        if not readable(rev) or not readable(gone) or not integer(rev,MAX_REVISION) or type(gone) ~= "boolean" then return end
        local identity=N.Key(name)
        local loaded={name=name,rev=rev,gone=gone}
        if supersedes(loaded,data.removed[identity]) then data.removed[identity]=loaded end
    end
    return true
end

local function loadStore(saved)
    if not readable(saved) then return end
    if saved == nil then return {}, 0 end
    if not plain(saved) or member(saved,"version") ~= 1 or not plain(saved.scopes) then return end
    local removed=saved.removed
    if not readable(removed) or removed ~= nil and not plain(removed) then return end
    local scopes, migrated, count = {}, {}, 0
    for key, rows in pairs(saved.scopes) do
        count=count+1
        if count > MAX_SCOPES or not readable(key) or type(key) ~= "string" or #key > 31 or not plain(rows) then return end
        local region, club = key:match("^(%d+):(%d+)$")
        if scopeKey(tonumber(region),club) ~= key then return end
        local data, size = {rows={},saved={},count=0,removed={}}, 0
        for name, row in pairs(rows) do
            size=size+1
            if size > MAX_ROWS or not readable(name) or not validName(name) or not validRow(row) then return end
            local clean=loadDetails(name,row)
            if not clean then return end
            local identity=N.Key(name)
            local old=data.rows[identity]
            local merged=combine(old,name,clean,clean.reasonIds,clean.note,clean.noteRev)
            retainRow(data,identity,old,merged)
        end
        scopes[key]=data
        local records
        if removed then records=removed[key] end
        if records ~= nil then
            if not loadRecords(data,records) then return end
            -- A downgraded client can have re-added a removed name.
            for identity, record in pairs(data.removed) do
                if record.gone then dropRow(data,identity) end
            end
        end
        if size ~= data.count then migrated[key]=data.saved end
    end
    for key in pairs(removed or {}) do
        if not readable(key) or not scopes[key] then return end
    end
    return scopes, count, migrated
end

local function validMember(character, key)
    if not readable(character) or not readable(key) or type(character) ~= "string" or type(key) ~= "string" then return end
    local region, name=character:match("^(%d+):(.+)$")
    local guildRegion, club=key:match("^(%d+):(%d+)$")
    if region and region == guildRegion and validName(name) and scopeKey(tonumber(region),club) == key then return key end
end

local function recordedGuild(character)
    local members=WhowhoGuildBlacklistDB and WhowhoGuildBlacklistDB.members
    if plain(members) then return validMember(character,members[character]) end
end

-- A guild event can meet a stale club ID, so only a guild already read this world session is left at once.
-- Reading it again also ends the window: a later other club ID is then unproven.
local function atHome(character, key)
    homeRead,guildEvent=character.."="..key,nil
end

local function recordMember(seen)
    if not seen.confirmed or not db[seen.key] or recordedGuild(seen.character) then return end
    local members=WhowhoGuildBlacklistDB.members
    if not plain(members) then
        members={}
        WhowhoGuildBlacklistDB.members=members
    end
    local size=0
    for _ in pairs(members) do size=size+1 end
    -- shortcut: past the cap a new character is not recorded, so it cannot keep a list that another one leaves.
    if size < MAX_MEMBERS or members[seen.character] ~= nil then
        members[seen.character]=seen.key
        atHome(seen.character,seen.key)
    end
end

local function dropScope(key)
    if db[key] then
        db[key]=nil
        scopeCount=scopeCount-1
    end
    -- The loader rejects removal records without their scope.
    WhowhoGuildBlacklistDB.scopes[key]=nil
    if WhowhoGuildBlacklistDB.removed then WhowhoGuildBlacklistDB.removed[key]=nil end
end

-- A saved list no recorded character points to, fewest entries first.
-- shortcut: a list waiting for the leave erase still counts as claimed, so a second list can go; erasing it sooner would trust one guild reading.
local function spareScope()
    local members=WhowhoGuildBlacklistDB and WhowhoGuildBlacklistDB.members
    local claimed={}
    if plain(members) then
        for character, key in pairs(members) do
            if validMember(character,key) then claimed[key]=true end
        end
    end
    local spare
    for key, data in pairs(db) do
        if not claimed[key] and (not spare or data.count < db[spare].count
            or data.count == db[spare].count and key < spare) then spare=key end
    end
    return spare
end

local function publish(current)
    if not db[current.key] then
        -- Only a new guild's list gets here unsaved, so it is never the spare.
        if scopeCount >= MAX_SCOPES then
            local spare=spareScope()
            if spare then dropScope(spare) end
        end
        db[current.key]=current.data
        scopeCount=scopeCount+1
    end
    if WhowhoGuildBlacklistDB == nil then WhowhoGuildBlacklistDB={version=1, scopes={}} end
    WhowhoGuildBlacklistDB.scopes[current.key]=current.data.saved
    if next(current.data.removed) then
        local records={}
        for _, record in pairs(current.data.removed) do records[record.name]={rev=record.rev,gone=record.gone} end
        WhowhoGuildBlacklistDB.removed=WhowhoGuildBlacklistDB.removed or {}
        WhowhoGuildBlacklistDB.removed[current.key]=records
    end
    if sighting and sighting.key == current.key then recordMember(sighting) end
end

local function notify()
    local refresh=P.Shell.RefreshGuildBlacklist
    if refresh then refresh() end
    local sightings=P.BlacklistBanner.sightingsGuildChanged
    if sightings then sightings() end
end

local function nativeContext()
    if not inWorld then return end
    local guild=read(IsInGuild)
    if guild == false then return nil, "no_guild" end
    if guild ~= true or not storageReady then return end
    local region=read(GetCurrentRegion)
    local key=scopeKey(region,read(member(C_Club,"GetGuildClubId")))
    if not key then return end
    local at=clock()
    local ready=registered and not chatRestricted and type(member(C_ChatInfo,"SendAddonMessage")) == "function"
        and type(member(C_Timer,"After")) == "function" and at and revisionWindow()
        and read(member(C_ChatInfo,"InChatMessagingLockdown")) == false or false
    if read(IsInGuild) == true and read(GetCurrentRegion) == region
        and scopeKey(region,read(member(C_Club,"GetGuildClubId"))) == key then
        return key, ready and "ready" or "unavailable", region, at
    end
end

local function clearPeerWork(current)
    current.sample,current.acks=nil,{}
    if current.pullKind == "sample" then current.pullKind="query" end
    local retry=current.retries.pull
    if retry and retry.sample then
        current.retries.pull=nil
        if not current.pullAt then current.pullAt,current.pullKind=0,"query" end
    end
end

local function clearInterruptedWork(current)
    clearPeerWork(current)
    current.detailPending={}
    for _, queue in ipairs({current.pushDetails,current.snapshotDetails}) do
        for _, item in pairs(queue) do item.transfer=nil end
    end
    current.retries.pushDetails,current.retries.snapshotDetails=nil,nil
end

-- Membership owns rows and queued work. Ready tokens additionally require a usable transport.
local function refresh(found)
    if checking or settling and not settling.awaitingVerification then return nil, "unavailable" end
    checking=true
    local event=eventVersion
    local character=inWorld and storageReady and A.currentCharacterName()
    local key, nextStatus, region, at=nativeContext()
    local guild=key
    if character and nextStatus == "no_guild" then
        region=read(GetCurrentRegion)
        local ok, club=pcall(member(C_Club,"GetGuildClubId"))
        -- An unreadable club ID is unknown membership, not "no guild".
        if ok and readable(club) and integer(region,2147483647) and not scopeKey(region,club) then guild=false end
    end
    checking=false
    if event ~= eventVersion then return nil, "unavailable" end
    if settling then
        -- With no settlement timer, a stale previous club cannot confirm membership.
        if nextStatus ~= "no_guild" and (not key or key == settling.previous) then return nil, "unavailable" end
        settling=nil
    end
    if character and guild ~= nil then
        found.character,found.key,found.at=string.format("%d:%s",region,character),guild,at
    end
    if key or nextStatus == "no_guild" then lastMembershipKey=key end
    nextStatus=nextStatus or "unavailable"
    local nativeReady=nextStatus == "ready"
    if state and state.key == key then
        if state.sendRecoveryAt and at and at >= state.sendRecoveryAt then state.sendRecoveryAt=nil end
        if state.timerFault or state.sendRecoveryAt then nextStatus="unavailable" end
        if state.nativeReady and not nativeReady then clearInterruptedWork(state) end
        state.nativeReady=nativeReady
        if state.readToken and status == nextStatus then return state, status, false end
    elseif not state and not key and status == nextStatus then
        return nil, status, false
    end
    generation=generation+1
    status=nextStatus
    if (state and state.key) ~= key then
        state=key and {key=key, region=region, push={}, snapshot={}, requests={}, retries={}, acks={},
            pushDetails={}, snapshotDetails={}, detailPending={}, activeDetails={},
            pushRemoved={}, snapshotRemoved={},
            data=db[key] or {rows={},saved={},count=0,removed={}}, pullAt=0, pullKind="announce", nativeReady=nativeReady} or nil
    elseif state then
        state.timer=nil
    end
    if state then
        state.readToken=state.readToken or key..":read:"..generation
        state.token=status == "ready" and key..":"..generation or nil
        if state.token then state.recoveryAttempts=nil end
    end
    return state, status, true
end

local function later(delay, fn)
    local after=member(C_Timer,"After")
    return type(after) == "function" and pcall(after,delay,fn)
end

local function reread()
    if not inWorld or checking or settling or not storageReady then return end
    local _, _, changed=currentState()
    if changed then notify() end
end

local function eraseLeft(character, key)
    if state and state.key == key then return end
    local members, kept=WhowhoGuildBlacklistDB.members, false
    for other, guild in pairs(members) do
        if validMember(other,guild) == key and other ~= character then kept=true end
    end
    if not kept then
        dropScope(key)
    end
    members[character]=nil
end

local function startLeave(character, from, key)
    if leaving and leaving.character == character and leaving.from == from and leaving.key == key then return end
    local ticket={character=character,from=from,key=key}
    leaving=ticket
    if not later(LEAVE_DELAY,function()
        if leaving ~= ticket then return end
        leaving,due=nil,ticket
        reread()
        due=nil
    end) then leaving=nil end
end

-- found.key is the current guild, or false for a confirmed "no guild".
local function track(found)
    local character, key=found.character, found.key
    lastCharacter=character
    local home=recordedGuild(character)
    if home == key then
        leaving=nil
        atHome(character,key)
    end
    if home and home ~= key then
        -- One reading may be stale; only a settled guild event makes another guild conclusive.
        if key and guildEvent and homeRead == character.."="..home
            or due and due.character == character and due.from == home and due.key == key then
            leaving=nil
            eraseLeft(character,home)
        else
            startLeave(character,home,key)
        end
    end
    if not key then sighting=nil; return end
    if not sighting or sighting.character ~= character or sighting.key ~= key or sighting.event ~= eventVersion then
        sighting={character=character,key=key,event=eventVersion,at=found.at}
        -- Nothing else guarantees the second reading that confirms membership.
        if not guildEvent and home ~= key then later(CONFIRM_DELAY+1,reread) end
    end
    if guildEvent or sighting.at and found.at and found.at-sighting.at >= CONFIRM_DELAY then sighting.confirmed=true end
    recordMember(sighting)
end

local function verify()
    local found={}
    local current, currentStatus, changed=refresh(found)
    if found.character then track(found) end
    return current, currentStatus, changed
end

-- The club ID can become readable without any event, so a missing scope is read again.
-- Each event that resets the waits retires the pending timer, so its waits start again.
local awaitingScope, scopeTries=nil, 0
local function awaitScope()
    local after=member(C_Timer,"After")
    local wait=SCOPE_WAITS[scopeTries+1]
    if awaitingScope == eventVersion or not wait or type(after) ~= "function" then return end
    scopeTries=scopeTries+1
    local version=eventVersion
    awaitingScope=pcall(after,wait,function()
        if version ~= eventVersion then return end
        awaitingScope=nil
        if not inWorld or checking or settling then return end
        local _, _, changed=currentState()
        if changed or state then notify() end
    end) and version or nil
end

function currentState(allowReadOnly)
    local current, currentStatus, changed=verify()
    if state then scopeTries=0
    elseif inWorld and not settling and status == "unavailable" then awaitScope() end
    if current and changed then schedule(current) end
    if current and (current ~= state or settling) then return nil, status, changed end
    if current then currentStatus=status end
    return (allowReadOnly or currentStatus == "ready") and current or nil, currentStatus, changed
end

local function ownsReady(current, token)
    return current == state and status == "ready" and current.token == token
end

function G.context()
    local current, currentStatus=currentState(true)
    -- The third result identifies visible rows across pauses. Only the first can authorize writes.
    return current and current.token, currentStatus, current and current.readToken
end

function G.peerCount(expectedScope)
    local current=state
    if checking or settling or not current or not readable(expectedScope) or not ownsReady(current,expectedScope) then return end
    local at=clock()
    local sample=current.sample
    if at and ownsReady(current,expectedScope) and sample and sample.sent and (not sample.responders or sample.count > 0)
        and not sample.overflow and at < sample.expires then return sample.count end
end

function G.list()
    local current=currentState(true)
    local rows={}
    if current then
        for _, entry in pairs(current.data.rows) do
            local ids={}
            for index, id in ipairs(entry.reasonIds or {}) do ids[index]=id end
            rows[#rows+1]={name=entry.name,class=entry.class,reasonIds=ids,note=entry.note}
        end
        table.sort(rows,function(a,b) return a.name < b.name end)
    end
    return rows
end

function G.bannerLookup(region)
    -- Unknown membership can preserve a sighting but cannot authorize an alert.
    if type(IsInGuild)~="function" then return end
    if not inWorld or checking or settling then return nil,nil,true end
    local current=state
    local token=current and current.readToken
    local function owns()
        return token and inWorld and not checking and not settling and state==current and current.readToken==token
    end
    local guild=read(IsInGuild)
    if guild==false then return end
    if guild~=true or not owns() then return nil,nil,true end
    local nativeRegion=read(GetCurrentRegion)
    local key=scopeKey(nativeRegion,read(member(C_Club,"GetGuildClubId")))
    if not key or key~=current.key or not owns() then return nil,nil,true end
    if nativeRegion~=region or current.data.count==0 then return end
    return function(name)
        if not owns() then return end
        local identity=N.Key(name)
        local entry=current.data.rows[identity]
        if entry then return key..":"..identity, A.reasonText(entry.reasonIds," · ") end
    end, owns
end

local function forgetQueuedRow(current, identity)
    for _, route in ipairs({"push","snapshot"}) do
        current[route][identity]=nil
        local retry=current.retries[route]
        if retry then
            retry.rows[identity]=nil
            if not next(retry.rows) then current.retries[route]=nil end
        end
    end
    for _, route in ipairs({"pushDetails","snapshotDetails"}) do
        current[route][identity]=nil
        if current.activeDetails[route] == identity then current.activeDetails[route]=nil end
        local retry=current.retries[route]
        if retry and retry.identity == identity then current.retries[route]=nil end
    end
end

local function merge(current, identity, name, classUpdate, reasonIds, note, noteRev)
    local data=current.data
    local record=data.removed[identity]
    if record and record.gone then return "unchanged" end
    local old=data.rows[identity]
    local row=combine(old,name,classUpdate,reasonIds,note,noteRev)
    if row == old then return "unchanged" end
    if not old and not db[current.key] and scopeCount >= MAX_SCOPES and not spareScope() then return "limit" end
    local retained, displaced=retainRow(data,identity,old,row)
    if not retained then return "limit" end
    if displaced then forgetQueuedRow(current,displaced) end
    return "shared", row
end

local function coversClass(incoming, queued)
    return N.PreferDisplay(incoming.name,queued.name) == incoming.name and not newer(queued,incoming)
end

local function verifiedClass(saved)
    local known=saved.lastKnown
    local class=known and known.class and known.class.value
    -- AddressBook validates class evidence and its GUID, exact name and region before returning a saved record.
    if classes[class] then return class end
end

function G.canShareNote(note)
    return readable(note) and D.validNote(note)
end

local function approvedDetails(consent)
    if not plain(consent) then return end
    local ids, note=member(consent,"reasonIds"),member(consent,"note")
    return validReasons(ids) and D.mergeReasons(nil,ids) or nil, G.canShareNote(note) and note or nil
end

local function matchingReasons(approved, saved)
    if not approved or #approved ~= #saved then return end
    local ordered=D.mergeReasons(nil,saved)
    for index, id in ipairs(approved) do
        if ordered[index] ~= id then return end
    end
    return approved
end

local function publishShare(current, name, class, reasons, approvedNote, first, last)
    local identity=N.Key(name)
    local old=current.data.rows[identity]
    local classUpdate
    if not old or class and class ~= old.class then
        local revision=not class and 0 or nextRevision(first,last,old and old.rev)
        if revision then classUpdate={class=class,rev=revision} end
    end
    local note, noteRev
    if approvedNote and (not old or approvedNote ~= old.note) then
        noteRev=nextRevision(first,last,old and old.noteRev)
        if noteRev then note=approvedNote end
    end
    local record, restored=current.data.removed[identity]
    -- shortcut: a restore does not date rows, so a peer that missed the removal can merge old reasons and note back; tie a row data revision to the restore.
    if record and record.gone then
        -- Restoring now would overwrite the unsent removal, so peers would never learn of it.
        local pending=current.pushRemoved[identity]
        -- shortcut: the queue is not saved, so a reload or guild change empties it and a re-add before the next sync overwrites the removal for peers; persist pending removals if reported.
        -- A flush can end without a timer, so the refusal re-arms the send it waits for.
        if pending and pending.gone then schedule(current); return "unavailable" end
        local revision=nextRevision(first,last,record.rev)
        if not revision then return "unavailable" end
        restored={name=name,rev=revision,gone=false}
        current.data.removed[identity]=restored
    end
    local result, row=merge(current,identity,name,classUpdate,reasons,note,noteRev)
    if restored then
        if result == "shared" then
            current.pushRemoved[identity],current.snapshotRemoved[identity]=restored,nil
        else
            current.data.removed[identity]=record
        end
    end
    if result == "shared" then
        if classUpdate or old and row.name ~= old.name then current.push[identity]=row end
        local reasonsChanged=reasons and (not old or row.reasonIds ~= old.reasonIds)
        if note or reasonsChanged then
            local prior=current.pushDetails[identity]
            if not note and prior and prior.row.noteRev == row.noteRev then
                note,noteRev=prior.row.note,prior.row.noteRev
            end
            local ids=D.mergeReasons(prior and prior.row.reasonIds,reasonsChanged and reasons or nil)
            current.pushDetails[identity]={row={name=row.name,reasonIds=ids,note=note,noteRev=noteRev}}
        end
        publish(current)
        schedule(current)
        notify()
    end
    return result
end

function G.share(record, expectedScope, consent)
    local approvedReasons, approvedNote=approvedDetails(consent)
    local current=currentState()
    if not current or not readable(expectedScope) or expectedScope ~= current.token then return "unavailable" end
    if not plain(record) or not A.store then return "invalid_record" end
    local id, store=member(record,"id"), A.store
    local first, last=revisionWindow()
    if not first or currentState() ~= current or current.token ~= expectedScope or A.store ~= store then return "unavailable" end
    local saved=store.get(id)
    if not saved or saved.membership ~= "blacklist" or saved.identityState ~= "resolved" or saved.region ~= current.region
        or saved.membership ~= member(record,"membership") or saved.identityState ~= member(record,"identityState")
        or saved.region ~= member(record,"region") or saved.fullName ~= member(record,"fullName")
        or not readable(record.guid) or saved.guid ~= record.guid or not validName(saved.fullName) then return "invalid_record" end
    local removal=current.data.removed[N.Key(saved.fullName)]
    -- Only a direct Add restores a removed name.
    if removal and removal.gone then return "deleted" end
    local reasons=matchingReasons(approvedReasons,saved.reasonIds)
    local note=approvedNote == saved.note and approvedNote or nil
    return publishShare(current,saved.fullName,verifiedClass(saved),reasons,note,first,last)
end

function G.add(name, reasonIds, note, expectedScope, ownsSave)
    if not readable(name) or not validName(name) then return "invalid_name" end
    if not validReasons(reasonIds) then return "invalid_reasons" end
    local reasons=D.mergeReasons(nil,reasonIds)
    if not readable(note) or note ~= nil and note ~= "" and not D.validNote(note) then return "invalid_note" end
    local current=currentState()
    if not current or not readable(expectedScope) or expectedScope ~= current.token then return "unavailable" end
    local playerName=A.currentCharacterName()
    local first, last=revisionWindow()
    if not playerName or not first or currentState() ~= current or not ownsReady(current,expectedScope) then return "unavailable" end
    if N.Key(name) == N.Key(playerName) then return "self" end
    -- All native policy/scope reads must finish before the first durable row or queue change.
    if ownsSave and not ownsSave() or not ownsReady(current,expectedScope) then return "unavailable" end
    -- shortcut: an Add before the removal arrives writes no record, so that older removal drops its row; record every direct Add.
    return publishShare(current,name,nil,reasons,note ~= "" and note or nil,first,last)
end

function G.remove(name, expectedScope)
    if not readable(name) or not validName(name) then return "invalid_name" end
    local current=currentState()
    if not current or not readable(expectedScope) or expectedScope ~= current.token then return "unavailable" end
    local first, last=revisionWindow()
    if not first or currentState() ~= current or not ownsReady(current,expectedScope) then return "unavailable" end
    local identity=N.Key(name)
    local row=current.data.rows[identity]
    if not row then return "missing" end
    local prior=current.data.removed[identity]
    local revision=nextRevision(first,last,prior and prior.rev)
    if not revision then return "unavailable" end
    local record={name=row.name,rev=revision,gone=true}
    dropRow(current.data,identity)
    forgetQueuedRow(current,identity)
    putRecord(current.data,identity,record)
    current.pushRemoved[identity],current.snapshotRemoved[identity]=record,nil
    publish(current)
    schedule(current)
    notify()
    return "removed"
end

local function readRecords(payload, lastRevision)
    local records, seen={},{}
    for item in (payload.."|"):gmatch("([^|]*)|") do
        local digits, flag, name=item:match("^(%d+),([01]),(.+)$")
        if not digits or not validName(name) or seen[name] then return end
        seen[name]=true
        local rev=#digits <= 12 and tonumber(digits)
        if integer(rev,lastRevision) then
            local identity=N.Key(name)
            local record={name=name,rev=rev,gone=flag == "1"}
            if supersedes(record,records[identity]) then records[identity]=record end
        end
    end
    if next(records) then return records end
end

local function readEntries(payload, lastRevision)
    local entries, seen={},{}
    for item in (payload.."|"):gmatch("([^|]*)|") do
        local class, digits, name=item:match("^([A-Z]*),(%d+),(.+)$")
        if not class or not validName(name) then return end
        local rev=#digits <= 12 and tonumber(digits)
        if digits == "0" and class == "" or classes[class] and integer(rev,lastRevision) then
            if seen[name] then return end
            seen[name]=true
            local identity=N.Key(name)
            local evidence={class=classes[class] and class or nil,rev=rev}
            entries[identity]=combine(entries[identity],name,evidence)
        end
    end
    if next(entries) then return entries end
end

local function responsePacket(current, queue, removal)
    local payload, sent=(removal and "X|" or "E|")..current.key,{}
    for identity, row in pairs(queue) do
        local item=removal and string.format("|%.0f,%d,%s",row.rev,row.gone and 1 or 0,row.name)
            or string.format("|%s,%.0f,%s",row.class or "",row.rev,row.name)
        if #payload+#item > MAX_PACKET then break end
        payload=payload..item
        sent[identity]=row
    end
    return payload, sent
end

local function onlyQueuedRows(queue, rows)
    for identity, row in pairs(rows) do
        if queue[identity] ~= row then rows[identity]=nil end
    end
    return next(rows) ~= nil
end

local function startSnapshot(current, at)
    current.followupAt=nil
    current.retries.snapshot=nil
    current.retries.snapshotDetails=nil
    current.retries.snapshotRemoved=nil
    for identity, record in pairs(current.data.removed) do current.snapshotRemoved[identity]=record end
    for identity, row in pairs(current.data.rows) do
        current.snapshot[identity]=row
        if row.reasonIds or row.note then current.snapshotDetails[identity]={row=row} end
    end
    current.lastReply=at
    current.replyAt=at
end

local function hasSnapshot(current)
    return next(current.snapshotRemoved) or next(current.snapshot) or next(current.snapshotDetails)
end

local function hasPush(current)
    return next(current.pushRemoved) or next(current.push) or next(current.pushDetails)
end

local function rememberRequest(current, nonce)
    current.requests[#current.requests+1]=nonce
    if #current.requests > 32 then table.remove(current.requests,1) end
end

local function nextAck(current, at)
    local firstSender, first, size
    size=0
    for sender, ack in pairs(current.acks) do
        if at >= ack.expires then
            current.acks[sender]=nil
        else
            size=size+1
            if not first or ack.due < first.due then firstSender,first=sender,ack end
        end
    end
    return firstSender,first,size
end

local function advanceSample(current, at)
    local sample=current.sample
    if not sample or not sample.sent then return end
    if at >= sample.expires then
        current.sample=nil
    elseif sample.responders and at >= sample.settlesAt then
        sample.responders=nil
    else
        return
    end
    notify()
end

local function finishSend(current, unexpected)
    if unexpected then
        local sample=current.sample
        -- A pause can lose replies to an in-flight sample. A query awaiting retry still owns its next attempt.
        if sample and sample.sent and sample.responders then current.sample=nil end
        current.sendRecoveryAt=nextSend
        local owner, _, changed=verify()
        if owner then schedule(owner) end
        if changed then notify() end
    else
        schedule(current)
    end
end

local function flush(current)
    if state ~= current then return end
    local owner, currentStatus, changed=verify()
    if owner ~= current or currentStatus ~= "ready" then
        if owner then schedule(owner) end
        if changed then notify() end
        return
    end
    local token=current.token
    if changed then notify() end
    if not ownsReady(current,token) then return end
    local at=clock()
    local send=member(C_ChatInfo,"SendAddonMessage")
    if not at or currentState() ~= current or not ownsReady(current,token) then return end
    advanceSample(current,at)
    if not ownsReady(current,token) then return end
    if at < nextSend then schedule(current); return end
    if not hasSnapshot(current) and current.followupAt and at >= current.followupAt then startSnapshot(current,at) end
    local route, queue, payload, sent, pullKind, details, pullSample, removal
    local ackSender, ack=nextAck(current,at)
    if next(current.pushRemoved) then
        route,queue,removal="pushRemoved",current.pushRemoved,true
    elseif next(current.push) then
        route,queue="push",current.push
    elseif current.retries.pull or current.pullAt and at >= current.pullAt then
        route="pull"
        if not current.retries.pull then
            pullKind=current.pullKind
            current.pullAt,current.pullKind=nil,nil
        end
        current.lastPull=at
        if current.pullKind == "sample" then current.pullAt=math.max(current.pullAt,at+SYNC_INTERVAL) end
    elseif ack and at >= ack.due then
        route,payload="ack","A|"..current.key.."|"..ack.nonce
    elseif next(current.pushDetails) then
        route,queue,details="pushDetails",current.pushDetails,true
    elseif next(current.snapshotRemoved) and at >= current.replyAt then
        route,queue,removal="snapshotRemoved",current.snapshotRemoved,true
    elseif next(current.snapshot) and at >= current.replyAt then
        route,queue="snapshot",current.snapshot
    elseif next(current.snapshotDetails) and at >= current.replyAt then
        route,queue,details="snapshotDetails",current.snapshotDetails,true
    end
    if not route then schedule(current); return end
    local pending=current.retries[route]
    if route == "pull" and (pullKind == "sample" or pending and pending.sample == current.sample) then
        pullSample=current.sample
    end
    local identity, item
    if details then
        if pending and queue[pending.identity] ~= pending.item then pending=nil end
        identity=current.activeDetails[route]
        item=queue[identity]
        if not item then identity,item=next(queue) end
        current.activeDetails[route]=identity
        item.transfer=item.transfer or D.transfer(item.row.name,item.row)
        payload=D.packet(current.key,item.transfer)
    elseif queue then
        -- Retry only the still-owned rows from this packet. Newly queued rows have their own budget.
        if pending and not onlyQueuedRows(queue,pending.rows) then pending=nil end
        payload,sent=responsePacket(current,pending and pending.rows or queue,removal)
    elseif pending and not pullSample then
        payload=pending.payload
    elseif route == "pull" then
        local nonce=string.format("%d.%d",generation,math.random(1,2147483646))
        if pullSample then
            -- Legacy peers parse a leading zero as part of the existing Q nonce.
            nonce="0"..nonce
            pullSample.nonce,pullSample.responders,pullSample.count=nonce,{},0
            pullSample.overflow=nil
            pullSample.settlesAt=at+SAMPLE_WINDOW
            pullSample.expires=pullSample.settlesAt+SAMPLE_LIFETIME
            rememberRequest(current,nonce)
        end
        current.nonce=nonce -- Install echo ownership before the synchronous native call.
        local command=pullKind == "announce" and (current.data.count > 0 or next(current.data.removed)) and "H" or "Q"
        payload=command.."|"..current.key.."|"..nonce
    end

    nextSend=at+SEND_INTERVAL
    local result=read(send,PREFIX,payload,CHANNEL)
    if state ~= current then return end
    if not ownsReady(current,token) then
        if pullKind and not current.pullAt and not current.retries.pull then
            current.pullAt,current.pullKind=at,pullKind == "sample" and "query" or pullKind
        end
        schedule(current)
        return
    end
    if details and queue[identity] ~= item then schedule(current); return end
    local unexpected=result ~= SUCCESS and result ~= ADDON_THROTTLE and result ~= CHANNEL_THROTTLE and result ~= LOCKDOWN
    local retry=result ~= SUCCESS
    if pullSample and current.sample == pullSample then
        if result == SUCCESS then
            pullSample.sent=true
        else
            pullSample.nonce,pullSample.responders=nil,nil
        end
    end
    if route == "ack" then
        if current.acks[ackSender] == ack then
            local due=at+SEND_INTERVAL*2^(ack.attempts+1)
            if retry and ack.attempts < 2 and due < ack.expires then
                ack.attempts,ack.due=ack.attempts+1,due
                nextSend=due
            else
                current.acks[ackSender]=nil
            end
        end
    elseif retry then
        local attempts=(pending and pending.attempts or 0)+1
        if attempts <= 2 and (not sent or onlyQueuedRows(queue,sent)) then
            current.retries[route]={attempts=attempts, rows=sent, payload=payload, identity=identity, item=item, sample=pullSample}
            nextSend=at+SEND_INTERVAL*2^attempts
            finishSend(current,unexpected)
            return
        end
    end
    current.retries[route]=nil
    if pullSample and result ~= SUCCESS and current.sample == pullSample then current.sample=nil end
    if details then
        if result == SUCCESS and item.transfer.index < item.transfer.count then
            item.transfer.index=item.transfer.index+1
        else
            queue[identity]=nil
        end
    elseif queue then
        for key, row in pairs(sent) do
            if queue[key] == row then queue[key]=nil end
        end
    end
    finishSend(current,unexpected)
end

function schedule(current)
    if state ~= current or settling or not registered then return end
    local at=clock()
    local after=member(C_Timer,"After")
    if state ~= current or settling or not at or type(after) ~= "function" then return end
    local due
    local recovering=status ~= "ready"
    local pullDue=current.retries.pull and 0 or current.pullAt
    local reply=hasSnapshot(current) and current.replyAt or current.followupAt
    local replyCheckpoint
    if recovering then
        if current.timerFault then return end
        local attempts=current.recoveryAttempts or 0
        if (hasPush(current) or pullDue or reply) and attempts < 3 then
            due=at+2^(1+attempts)
        end
        if current.sendRecoveryAt and at < current.sendRecoveryAt then
            due=math.min(due or math.huge,current.sendRecoveryAt)
        end
        if not due and reply and reply > at then
            -- Preserve a deferred reply's own deadline after early readiness checks run out.
            due,replyCheckpoint=reply,true
        end
    else
        due=hasPush(current) and 0 or pullDue
        if reply then due=math.min(due or math.huge,reply) end
        local _, ack=nextAck(current,at)
        if ack then due=math.min(due or math.huge,ack.due) end
    end
    if due then due=math.max(nextSend,due) end
    local sample=current.sample
    if not recovering and sample and sample.sent then
        local deadline=sample.responders and sample.settlesAt or sample.expires
        due=math.min(due or math.huge,deadline)
    end
    if not due then return end
    if current.timer and current.timer.due <= due then return end
    local ticket={due=due}
    current.timer=ticket
    local ok=pcall(after,math.max(0,due-at),function()
        if state ~= current or settling or current.timer ~= ticket then return end
        current.timer=nil
        if replyCheckpoint then
            current.recoveryAttempts=0
        elseif recovering then
            current.recoveryAttempts=(current.recoveryAttempts or 0)+1
        end
        flush(current)
    end)
    if not ok and state == current and current.timer == ticket then
        current.timer=nil
        current.timerFault=true
        clearInterruptedWork(current)
        verify()
        notify()
    end
end

function G.requestSync()
    local current=currentState()
    local token=current and current.token
    local at=current and clock()
    if not at or not ownsReady(current,token) then return false end
    local due=math.max(at,(current.lastPull or at-SYNC_INTERVAL)+SYNC_INTERVAL)
    local sample=current.sample
    if sample and (not sample.sent or at < due) then return false end
    current.sample={}
    current.pullAt,current.pullKind=due,"sample"
    schedule(current)
    return true
end

local function receiveAck(current, token, payload, sender)
    local sample=current.sample
    if not sample or not sample.responders or payload ~= sample.nonce then return end
    local at=clock()
    if not at or at >= sample.settlesAt or currentState() ~= current or not ownsReady(current,token)
        or current.sample ~= sample or payload ~= sample.nonce or sample.overflow
        or not sample.responders or sample.responders[sender] then return end
    if sample.count >= MAX_RESPONDERS then
        sample.overflow=true
        sample.responders={}
    else
        sample.responders[sender]=true
        sample.count=sample.count+1
        -- Only the count line: notify() would rebuild the list and rescan sightings per reply.
        local refresh=P.Shell.RefreshGuildPeers
        if refresh then refresh(token) end
    end
end

local function queueAck(current, sender, nonce, at)
    local _, _, size=nextAck(current,at)
    local previous=current.acks[sender]
    if not previous and size >= MAX_ACKS then return end
    local due=previous and previous.due or at+0.5+math.random()*3
    current.acks[sender]={nonce=nonce,due=due,expires=at+SAMPLE_WINDOW,attempts=0}
    schedule(current)
end

local function receive(prefix, message, channel, sender)
    if not readable(prefix) or prefix ~= PREFIX or not readable(channel) or channel ~= CHANNEL or not readable(message)
        or type(message) ~= "string" or #message > MAX_PACKET or not readable(sender) or type(sender) ~= "string"
        or sender == "" or #sender > 256 or sender:find("\000",1,true) then return end
    local command, key, payload=message:match("^([HQEDAX])|([^|]+)|(.+)$")
    if not command then return end
    local current, _, changed=currentState()
    local token=current and current.token
    if changed then notify() end
    if not current or not ownsReady(current,token) or key ~= current.key then return end
    if command == "A" then
        receiveAck(current,token,payload,sender)
        return
    end
    if command == "D" then
        local at=clock()
        local _, last=revisionWindow()
        if not at or not last or currentState() ~= current or not ownsReady(current,token) then return end
        local name, ids, note, rev=D.receive(current.detailPending,sender,payload,at,last,validName)
        if not name then return end
        local identity=N.Key(name)
        local queued=current.snapshotDetails[identity]
        if queued and N.PreferDisplay(name,queued.row.name) == name
            and D.mergeReasons(ids,queued.row.reasonIds) == ids
            and not D.newerNote(queued.row.note,queued.row.noteRev,note,rev) then
            current.snapshotDetails[identity]=nil
        end
        if merge(current,identity,name,nil,ids,note,rev) == "shared" then
            publish(current)
            notify()
        end
        if current.followupAt then schedule(current) end
        return
    end
    if command == "X" then
        local _, last=revisionWindow()
        local records=last and readRecords(payload,last)
        if not records or currentState() ~= current or not ownsReady(current,token) then return end
        local updated=false
        for identity, record in pairs(records) do
            for _, queue in ipairs({current.pushRemoved,current.snapshotRemoved}) do
                if queue[identity] and not supersedes(queue[identity],record) then queue[identity]=nil end
            end
            if supersedes(record,current.data.removed[identity]) then
                putRecord(current.data,identity,record)
                -- At the cap an older record is evicted at once and must not drop the row, or a stale E restores it.
                if current.data.removed[identity] == record then
                    if record.gone then
                        dropRow(current.data,identity)
                        forgetQueuedRow(current,identity)
                    end
                    updated=true
                end
            end
        end
        if updated then
            -- A removal alone never takes a slot.
            -- shortcut: an unsaved list holds removals in memory only, so a reload or loading screen drops them until the next sync.
            if db[current.key] or scopeCount < MAX_SCOPES then publish(current) end
            notify()
        end
        if current.followupAt then schedule(current) end
        return
    end
    if command ~= "E" then
        if #payload > 24 or not payload:match("^%d+%.%d+$") or payload == current.nonce then return end
        for _, nonce in ipairs(current.requests) do if nonce == payload then return end end
        local at=clock()
        if not at or currentState() ~= current or not ownsReady(current,token) then return end
        rememberRequest(current,payload)
        if command == "Q" and payload:sub(1,1) == "0" then
            queueAck(current,sender,payload,at)
        end
        -- A late cache holder triggers a query once per cooldown. Queries never announce or trigger other queries.
        if command == "H" and not current.pullAt then
            current.pullAt=math.max(at,(current.lastPull or 0)+SYNC_INTERVAL)
            current.pullKind="query"
            schedule(current)
        end
        if current.data.count == 0 and not next(current.data.removed) or not ownsReady(current,token) then return end
        local stagger=0.5+math.random()*3
        if hasSnapshot(current) or current.lastReply and at-current.lastReply < REPLY_INTERVAL then
            current.followupAt=current.followupAt or current.lastReply+REPLY_INTERVAL+stagger
        else
            startSnapshot(current,at)
            current.replyAt=at+stagger
        end
        schedule(current)
        return
    end
    local _, last=revisionWindow()
    local entries=last and readEntries(payload,last)
    if not entries or currentState() ~= current or not ownsReady(current,token) then return end
    local updated=false
    for identity, row in pairs(entries) do
        local snapshot, push=current.snapshot[identity],current.push[identity]
        if snapshot and coversClass(row,snapshot) then current.snapshot[identity]=nil end
        if push and coversClass(row,push) then current.push[identity]=nil end
        if merge(current,identity,row.name,row) == "shared" then updated=true end
    end
    if updated then
        publish(current)
        notify()
    end
    if current.followupAt then schedule(current) end
end

local function confirmMembership(ticket, requireNewScope)
    if settling ~= ticket or ticket.awaitingVerification then return end
    if requireNewScope then
        ticket.awaitingVerification=true
    else
        settling=nil
        guildEvent=ticket
    end
    local _, _, changed=currentState()
    -- The settled reading can still show the old guild with no later event. The follow-up also ends the window.
    if not (lastCharacter and recordedGuild(lastCharacter) and later(LEAVE_DELAY-MEMBERSHIP_SETTLE,function()
        reread()
        if guildEvent == ticket then guildEvent=nil end
    end)) and guildEvent == ticket then guildEvent=nil end
    if state then schedule(state) end
    if changed then notify() end
end

local function membershipChanged()
    scopeTries=0
    eventVersion=eventVersion+1
    local requireNewScope=settling and (settling.awaitingVerification or settling.requireNewScope)
    local ticket={previous=lastMembershipKey, requireNewScope=requireNewScope}
    settling=ticket
    guildEvent,sighting=nil,nil
    local changed=status ~= "unavailable" or state and state.readToken ~= nil
    status="unavailable"
    if state then
        state.timer,state.token,state.readToken,state.timerFault=nil,nil,nil,nil
        clearInterruptedWork(state)
    end
    if changed then notify() end
    local after=member(C_Timer,"After")
    local ok=type(after) == "function" and pcall(after,MEMBERSHIP_SETTLE,function()
        confirmMembership(ticket,requireNewScope)
    end)
    if not ok then confirmMembership(ticket,true) end
end

function G.install()
    if installed then return end
    installed=true
    if type(IsInGuild) ~= "function" or type(member(C_Club,"GetGuildClubId")) ~= "function" then return end
    local result=read(member(C_ChatInfo,"RegisterAddonMessagePrefix"),PREFIX)
    registered=result == SUCCESS or result == DUPLICATE_PREFIX
    local migrated
    db, scopeCount, migrated=loadStore(WhowhoGuildBlacklistDB)
    storageReady=db ~= nil
    if not storageReady then return end
    local frame=CreateFrame("Frame")
    local events={"CHAT_MSG_ADDON","PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","PLAYER_GUILD_UPDATE",
        "INITIAL_CLUBS_LOADED","ADDON_RESTRICTION_STATE_CHANGED"}
    for _, event in ipairs(events) do
        if read(frame.RegisterEvent,frame,event) ~= true then
            for _, subscribed in ipairs(events) do pcall(frame.UnregisterEvent,frame,subscribed) end
            registered=false
            return
        end
    end
    for key, rows in pairs(migrated or {}) do WhowhoGuildBlacklistDB.scopes[key]=rows end
    frame:SetScript("OnEvent",function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then receive(...); return end
        if event == "PLAYER_GUILD_UPDATE" then
            local unit=...
            if readable(unit) and unit == "player" then membershipChanged() end
            return
        end
        if event == "ADDON_RESTRICTION_STATE_CHANGED" then
            local kind, value=...
            if not readable(kind) or kind ~= CHAT_RESTRICTION or not readable(value)
                or (value ~= INACTIVE and value ~= ACTIVATING and value ~= ACTIVE) then return end
            chatRestricted=value ~= INACTIVE
        elseif event == "PLAYER_ENTERING_WORLD" then
            inWorld=true
        elseif event == "PLAYER_LEAVING_WORLD" then
            inWorld=false
            settling=nil
            lastMembershipKey=nil
            chatRestricted=nil
            guildEvent,sighting,leaving,homeRead=nil,nil,nil,nil
        end
        eventVersion,scopeTries=eventVersion+1,0
        if checking and not inWorld then
            state=nil
            status="unavailable"
            return
        end
        if state then state.recoveryAttempts,state.timerFault=nil,nil end
        local _, _, changed=currentState()
        if state then schedule(state) end
        if changed then notify() end
    end)
    inWorld=read(IsLoggedIn) == true
    local _, _, changed=currentState()
    if changed then notify() end
end
