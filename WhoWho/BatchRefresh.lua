local P = WhowhoPreview
local A = P.manual
local read = A.nativeRead.read
local cooldown = 30
local latestEpoch = 253402300799
local active, result
local batch = {}
A.batchRefresh = batch

local function epoch(value)
    if type(value) == "number" and value >= 1 and value <= latestEpoch and value % 1 == 0 then return value end
end

function batch.restore(saved)
    P.db.refreshReadyAt = epoch(saved)
end

local function serverTime()
    return epoch(read(GetServerTime))
end

local function remaining(now)
    local deadline = P.db.refreshReadyAt or 0
    if deadline - now > cooldown then
        -- Bound a future or rolled-back saved clock without resetting valid cooldowns.
        deadline = now + cooldown
        P.db.refreshReadyAt = deadline
    end
    return math.max(0, deadline - now)
end

function batch.state()
    if active then return true, 0, "Refreshing Friends…" end
    if not A.store then return false, nil end
    local now = serverTime()
    if not now then return false, nil, "Server time unavailable. Try reopening Friends." end
    return false, remaining(now), result
end

local function refresh()
    local store, region, settings = A.store, A.region, P.db
    local function isCurrent()
        return A.store == store and A.region == region and P.db == settings
    end
    local total = 0
    for _, item in ipairs(A.records) do
        if item.membership == "friend" and item.region == region then total = total + 1 end
    end
    if total == 0 then return "Add a Friend to refresh their status." end
    local now = serverTime()
    if not now or now > latestEpoch - cooldown then return "Server time unavailable. Try again shortly." end
    if remaining(now) > 0 then return result end
    local combat = read(InCombatLockdown)
    if combat == true then return "Refresh is paused during combat." end
    if combat ~= false then return "Combat status unavailable. Try again shortly." end
    if read(GetCurrentRegion) ~= region or not isCurrent() then return "Character region unavailable. Try again shortly." end

    settings.refreshReadyAt = now + cooldown
    local matched = A.relogRefresh.manual(isCurrent)
    if not matched then return "The roster changed. Try refreshing again." end
    if matched > 0 then A.refresh() end
    return P.L(total==1 and "Roster status found for %d of %d Friend." or "Roster status found for %d of %d Friends.",matched,total)
end

function batch.run()
    if active or not A.store then return end
    active = true
    local ok, text = pcall(refresh)
    result = ok and text or "Refresh interrupted. Try again."
    active = false
end
