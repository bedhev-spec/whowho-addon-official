local P=WhowhoPreview
local A=P.manual
local E={}
A.encounterLedger=E

local active, updates, aliases, db={},{},{},nil
local hour, day, limit=3600,86400,500
local countInterval=600
local revision=0
local read=A.nativeRead.read

local function stamp(value)
    return type(value)=="number" and value>=0 and value<math.huge and value%1==0
end

function E.now()
    local now=read(GetServerTime)
    if stamp(now) then return now end
end

local function newer(a,b)
    local at,bt=a.endedAt or a.startedAt,b.endedAt or b.startedAt
    return at>bt or (at==bt and a.id>b.id)
end

local function seenLater(a,b)
    return a.lastObservedAt>b.lastObservedAt or (a.lastObservedAt==b.lastObservedAt and a.id>b.id)
end

local function samePlayer(a,b)
    return a.playerId==b.playerId and a.guid==b.guid and a.name==b.name
end

local function groupKey(row)
    return ("%.0f:%.0f:%d:%s%d:%s"):format(row.region,row.playerId,#row.guid,row.guid,#row.name,row.name)
end

local function episodeKey(row)
    local place=row.zone and ("zone:"..row.zone) or ("context:"..(row.groupContext or ""))
    return groupKey(row)..place
end

local function hasObservation(row)
    return row.target==true or row.mouseover==true or row.nameplate==true
end

local function valid(row,region)
    return type(row)=="table" and stamp(row.id) and row.id>0 and stamp(row.playerId) and row.playerId>0
        and row.region==region and type(row.guid)=="string" and row.guid~=""
        and P.CharacterName.IsComplete(row.name)
        and (row.zone==nil or (type(row.zone)=="string" and row.zone:find("%S")~=nil))
        and (row.groupContext==nil or row.groupContext=="Raid" or row.groupContext=="Group")
        and stamp(row.startedAt) and stamp(row.lastObservedAt) and stamp(row.endedAt)
        and row.startedAt<=row.lastObservedAt and row.lastObservedAt<=row.endedAt
        and hasObservation(row)
end

local function retained(row,now)
    return not now or not row.endedAt or now-row.endedAt<30*day
end

local function trim(rows,now)
    for i=#rows,1,-1 do
        if i>limit or not retained(rows[i],now) then rows[i]=nil
        else break end
    end
end

function E.init(saved)
    if saved==nil then saved={version=1,nextId=1,regions={}} end
    if type(saved)~="table" or saved.version~=1 or not stamp(saved.nextId) or saved.nextId<1
        or type(saved.regions)~="table" then return end
    local now=E.now()
    local regions, ids={},{}
    for region,rows in pairs(saved.regions) do
        if not stamp(region) or region==0 or type(rows)~="table" then return end
        local clean={}
        for _,row in pairs(rows) do
            if not valid(row,region) or row.id>=saved.nextId or ids[row.id] then return end
            ids[row.id]=true
            clean[#clean+1]=row
        end
        table.sort(clean,newer)
        trim(clean,now)
        regions[region]=clean
    end
    saved.regions=regions
    db=saved
    WhowhoEncounterDB=saved
end

function E.available()
    return db~=nil and A.store~=nil
end

function E.revision()
    return revision
end

function E.isActive(id)
    return active[id]~=nil
end

function E.start(sighting,region,now)
    if not db or region~=A.region or not stamp(now) then return end
    local id=db.nextId
    if id+1<=id or not stamp(id+1) then return end
    db.nextId=id+1
    local row={id=id,playerId=sighting.id,region=region,name=sighting.name,guid=sighting.guid,
        startedAt=now,lastObservedAt=now}
    active[id]=row
    local latest
    for _,saved in ipairs(db.regions[region] or {}) do
        if samePlayer(row,saved) and (not latest or saved.startedAt>latest.startedAt
            or (saved.startedAt==latest.startedAt and saved.id>latest.id)) then latest=saved end
    end
    if latest and now-latest.startedAt<countInterval then updates[id]=latest end
    revision=revision+1
    return id
end

function E.observe(id,target,mouseover,elapsed,zone,group,nameplate)
    local row=active[id]
    if not row then return end
    local at=row.startedAt+math.max(0,math.floor(elapsed))
    if at<row.lastObservedAt then return end
    if at~=row.lastObservedAt or (target and not row.target) or (mouseover and not row.mouseover)
        or (nameplate and not row.nameplate)
        or zone~=row.zone or group~=row.groupContext then
        row.lastObservedAt=at
        row.target=row.target or target==true
        row.mouseover=row.mouseover or mouseover==true
        if nameplate then row.nameplate=true end
        row.zone,row.groupContext=zone,group
        revision=revision+1
    end
    return episodeKey(row)
end

function E.stop(id,elapsed)
    local row=active[id]
    if not row then return end
    local counted=updates[id]
    active[id],updates[id]=nil,nil
    revision=revision+1
    row.endedAt=math.max(row.lastObservedAt,row.startedAt+math.max(0,math.floor(elapsed)))
    if not valid(row,row.region) or (counted and not seenLater(row,counted)) then return end
    local rows=db.regions[row.region] or {}
    db.regions[row.region]=rows
    if counted then
        counted.lastObservedAt=row.lastObservedAt
        counted.zone,counted.groupContext=row.zone,row.groupContext
        counted.endedAt=math.max(counted.endedAt,row.endedAt)
        counted.target=counted.target or row.target
        counted.mouseover=counted.mouseover or row.mouseover
        if row.nameplate then counted.nameplate=true end
        aliases[id%limit]={id=id,countedId=counted.id,key=episodeKey(row)}
        local retained=false
        for _,saved in ipairs(rows) do
            if saved==counted then retained=true; break end
        end
        if not retained then rows[#rows+1]=counted end
    else
        rows[#rows+1]=row
    end
    table.sort(rows,newer)
    trim(rows,row.endedAt)
end

function E.snapshot(region,now)
    local buckets={Now={},Recent={},Earlier={},Ended={}}
    local nextBoundary
    local function add(row,section,boundary)
        local bucket=buckets[section]
        bucket[#bucket+1]=row
        if boundary and (not nextBoundary or boundary<nextBoundary) then nextBoundary=boundary end
    end
    local rows=db and db.regions[region]
    if rows then
        trim(rows,now)
        for _,row in ipairs(rows) do
            if not now then
                add(row,"Ended")
            elseif now-row.endedAt<hour then
                add(row,"Now",row.endedAt+hour)
            elseif now-row.endedAt<day then
                add(row,"Recent",row.endedAt+day)
            else
                add(row,"Earlier",row.endedAt+30*day)
            end
        end
    end
    for _,row in pairs(active) do
        if row.region==region then add(row,"Now") end
    end
    table.sort(buckets.Now,function(a,b)
        if (a.endedAt==nil)~=(b.endedAt==nil) then return a.endedAt==nil end
        return newer(a,b)
    end)
    return buckets,nextBoundary
end

-- One display row per verified character. An active repeat replaces
-- its counted row in the projection, while the physical episode keeps its ID.
function E.groups(region,now)
    local buckets,boundary=E.snapshot(region,now)
    local replacements, entries, groups, byId={},{},{},{}
    for id,row in pairs(active) do
        local counted=updates[id]
        if row.region==region and counted and hasObservation(row) then
            local latest=replacements[counted.id] or counted
            if seenLater(row,latest) then replacements[counted.id]=row end
        end
    end
    for _,section in ipairs({"Now","Recent","Earlier","Ended"}) do
        for _,row in ipairs(buckets[section]) do
            local counted=updates[row.id]
            local duplicate=(counted and replacements[counted.id]~=row) or replacements[row.id]
            if not duplicate and hasObservation(row) then
                local key=groupKey(row)
                local group=groups[key]
                if not group then
                    group={key=key,row=row,section=section,count=0,recent={},episodeKeys={}}
                    groups[key]=group
                    entries[#entries+1]=group
                elseif seenLater(row,group.row) then
                    group.row,group.section=row,section
                end
                for i=1,3 do
                    if not group.recent[i] or seenLater(row,group.recent[i]) then
                        table.insert(group.recent,i,row)
                        group.recent[4]=nil
                        break
                    end
                end
                group.count=group.count+1
                byId[row.id]=group
                group.episodeKeys[row.id]=episodeKey(row)
                if counted then
                    byId[counted.id]=group
                    group.episodeKeys[counted.id]=group.episodeKeys[row.id]
                end
            end
        end
    end
    for _,alias in pairs(aliases) do
        local group=byId[alias.countedId]
        if group and group.episodeKeys[alias.countedId]==alias.key then
            byId[alias.id]=group
            group.episodeKeys[alias.id]=alias.key
        end
    end
    table.sort(entries,function(a,b) return seenLater(a.row,b.row) end)
    return entries,boundary,byId,groups
end

function E.matchesGroup(region,now,id,key)
    local _,_,byId=E.groups(region,now)
    local group=byId[id]
    return group and group.episodeKeys[id]==key
end

local function resolvedBlacklist(store,region,name,guid)
    local saved=store.find(region,name,guid)
    if saved and saved.membership=="blacklist" and saved.identityState=="resolved" then return saved end
end

local function observedPlayer(row,record)
    return row.region==record.region and row.playerId==record.id and row.name==record.fullName
        and hasObservation(row)
end

local function savedGuid(record)
    return record.guid or (record.lastKnown and record.lastKnown.guid)
end

local function observedGuid(rows,record,guid,now)
    if rows then
        for _,row in pairs(rows) do
            if observedPlayer(row,record) and retained(row,now) then
                if guid and guid~=row.guid then return nil,true end
                guid=row.guid
            end
        end
    end
    return guid
end

local function observedBlacklistGuid(record,now)
    local guid,conflict=observedGuid(active,record)
    if conflict then return nil,true end
    return observedGuid(db and db.regions[record.region],record,guid,now)
end

function E.matchesBlacklistGuid(record,guid,now)
    local known=savedGuid(record)
    if known then return known==guid end
    local observed,conflict=observedBlacklistGuid(record,now)
    return not conflict and (not observed or observed==guid)
end

local function observedOtherPlayer(rows,store,record,guid,now)
    for _,row in pairs(rows or {}) do
        if row.region==record.region and row.guid==guid and row.playerId~=record.id and retained(row,now) then
            local owner=resolvedBlacklist(store,record.region,row.name,guid)
            if owner and observedPlayer(row,owner) then return true end
        end
    end
    return false
end

function E.matchesChatGuid(store,record,guid,now)
    if not E.matchesBlacklistGuid(record,guid,now) then return false end
    -- The store has already checked exclusive ownership when a saved GUID exists.
    if savedGuid(record) then return true end
    return not observedOtherPlayer(active,store,record,guid,now)
        and not observedOtherPlayer(db and db.regions[record.region],store,record,guid,now)
end

function E.findBlacklist(store,region,name,guid)
    local saved=resolvedBlacklist(store,region,name,guid)
    if not saved then return end
    local rows=db and db.regions[region]
    local now=not savedGuid(saved) and rows and #rows>0 and E.now() or nil
    if E.matchesBlacklistGuid(saved,guid,now) then return saved end
end

function E.latestBlacklistObservation(record)
    local store,region=A.store,A.region
    if not db or not store or not record or record.region~=region
        or record.membership~="blacklist" or record.identityState~="resolved" then return end
    local now=E.now()
    if read(GetCurrentRegion)~=region or A.store~=store or A.region~=region then return end
    local saved=resolvedBlacklist(store,region,record.fullName,record.guid)
    if not saved or saved.id~=record.id or saved.guid~=record.guid then return end
    local guid=savedGuid(saved) or observedBlacklistGuid(saved,now)
    if not guid then return end
    if guid~=saved.guid then
        local matched=resolvedBlacklist(store,region,saved.fullName,guid)
        if not matched or matched.id~=saved.id then return end
    end
    local latest
    local function consider(row)
        if row.guid==guid and observedPlayer(row,saved) and retained(row,now)
            and (not latest or seenLater(row,latest)) then latest=row end
    end
    for _,row in pairs(active) do consider(row) end
    for _,row in ipairs(db.regions[region] or {}) do consider(row) end
    if latest then return latest.lastObservedAt,latest.zone end
end

function E.blacklistRecord(row)
    local store,region=A.store,A.region
    if not store or not row or row.region~=region then return end
    local saved=E.findBlacklist(store,region,row.name,row.guid)
    if not saved or saved.id~=row.playerId or read(GetCurrentRegion)~=region
        or A.store~=store or A.region~=region then return end
    for _,record in ipairs(A.records) do
        if record.id==saved.id and record.region==region and record.fullName==saved.fullName
            and record.guid==saved.guid and record.membership=="blacklist" then return record,saved.lastKnown end
    end
end
