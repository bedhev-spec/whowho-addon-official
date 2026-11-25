local M = {}
WhowhoPreview.RosterModel = M

M.presenceChoices={"Online","Offline","Unknown"}

function M.SameIdentity(a,b)
    return a.id==b.id and a.region==b.region and a.fullName==b.fullName
        and a.guid==b.guid and a.membership==b.membership
end

-- Return the evidence kind, the roster caption key, and the validated date for Seen.
function M.Presence(record)
    if record.identityState=="unresolved" then return "Unknown","Unknown" end
    if (record.presence=="Online" or record.presence=="Offline") and record.connectionEvidence then return record.presence,record.presence end
    local report=record.presenceReport
    if report and (report.kind=="listed" or report.kind=="checked") then
        if report.online==true or report.online==false then
            return report.kind=="listed" and "Listed" or "Checked",report.online and "Online" or "Offline"
        end
        return "Unknown","Unknown"
    end
    if record.presence=="Seen" and record.source and type(record.observed)=="string" then
        local date,month=record.observed:match("^(%d%d%d%d%-(%d%d)%-%d%d)")
        if date and tonumber(month)>=1 and tonumber(month)<=12 then return "Seen","Unknown",date end
    end
    return "Unknown","Unknown"
end

local function matchesPresence(record, filter)
    local _,caption=M.Presence(record)
    return caption==filter
end

function M.DisplayClass(record, personalBlacklist)
    if personalBlacklist then return record.blacklistSavedClass or record.blacklistWhoClass end
    return record.class
end

local function matchesClass(record, filter, personalBlacklist)
    local class=M.DisplayClass(record,personalBlacklist)
    return class==filter or (filter=="UNASSIGNED" and not class)
end

function M.Filter(records, criteria)
    local filtered = {}
    local favorites = criteria.favoritesFirst and {}
    local key=criteria.searchKey or string.lower
    local query=key(criteria.query or "")
    local roleFilter=not criteria.personalBlacklist and criteria.roleFilter
    local statusFilter=not criteria.personalBlacklist and criteria.statusFilter
    if query and (criteria.section=="friend" or criteria.section=="blacklist" or criteria.section=="guildBlacklist") then
        for _, record in ipairs(records) do
            if record.membership == criteria.section and string.find(record.searchKey or key(record.fullName),query,1,true)
                and (not roleFilter or (roleFilter=="UNASSIGNED" and not record.role) or record.role==roleFilter)
                and (not criteria.classFilter or matchesClass(record,criteria.classFilter,criteria.personalBlacklist))
                and (not statusFilter or matchesPresence(record,statusFilter)) then
                local group = favorites and record.favorite==true and favorites or filtered
                group[#group+1] = record
            end
        end
        if criteria.sortByName then
            local function byName(a,b)
                if criteria.descending then return a.fullName>b.fullName end
                return a.fullName<b.fullName
            end
            table.sort(filtered,byName)
            if favorites then table.sort(favorites,byName) end
        end
    end
    if favorites and #favorites>0 then
        local count = #favorites
        for _,record in ipairs(filtered) do favorites[#favorites+1] = record end
        return favorites,count
    end
    return filtered,0
end

-- Return the next selection and viewport without mutating records or caller state.
-- A just-saved excluded record remains readable until its reveal is dismissed.
function M.Reconcile(filtered, state)
    local result = {
        selected=state.selected, selectedId=state.selectedId,
        revealSaved=state.revealSaved, savedOutside=state.savedOutside,
        compactDetail=state.compactDetail, offset=state.offset or 0,
    }
    local visibleRows=state.visibleRows
    if result.selected then
        local found=false
        for index,record in ipairs(filtered) do
            if record.id==result.selectedId then
                result.selected=record
                if result.revealSaved then
                    if index<=result.offset then result.offset=index-1
                    elseif index>result.offset+visibleRows then result.offset=index-visibleRows end
                    result.revealSaved=false; result.savedOutside=false
                end
                found=true; break
            end
        end
        if not found and result.revealSaved then result.savedOutside=true; result.compactDetail=true
        elseif not found then
            result.selected=nil; result.selectedId=nil; result.compactDetail=false
        end
    end
    result.offset=math.min(math.max(0,result.offset),math.max(0,#filtered-visibleRows))
    return result
end
