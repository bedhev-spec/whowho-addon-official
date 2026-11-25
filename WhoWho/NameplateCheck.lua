local A = WhowhoPreview.manual
local check = A.targetCheck
local reader, read = A.unitReader, A.nativeRead.read
local nameplates = {}
A.nameplateCheck = nameplates

-- A token belongs to the current synchronous read. Removal or reuse retires it.
local pending
local revision = 0

function nameplates.available()
    return reader.nameplateAvailable() and type(UnitIsUnit) == "function"
end

function nameplates.cancel()
    pending = nil
    revision = revision + 1
    return check.clearNameplates()
end

local function observe(unit, frame, generation)
    if check.busy then return false end
    local owner = {unit=unit}
    pending = owner
    local function owns()
        local on, currentGeneration = A.automaticNameplatesEnabled()
        return pending == owner and on and generation == currentGeneration
    end
    check.busy = true
    local ok, published = pcall(check.observeNameplate, unit, frame, owns)
    check.busy = false
    if pending == owner then pending = nil end
    local on, currentGeneration = A.automaticNameplatesEnabled()
    return ok and published == true and on and generation == currentGeneration
end

function nameplates.onEvent(event, unit)
    local enabled, generation = A.automaticNameplatesEnabled()
    if not enabled then return false end
    revision = revision + 1
    if not reader.nameplateToken(unit) then
        pending = nil
        return false
    end
    if pending and pending.unit == unit then pending = nil end
    if event ~= "NAME_PLATE_UNIT_ADDED" then return false end
    return observe(unit, nil, generation)
end

function nameplates.seed()
    local enabled, generation = A.automaticNameplatesEnabled()
    local owned = revision
    if not enabled or check.busy or read(InCombatLockdown) ~= false then return false end
    local frames = reader.nameplateFrames()
    if not frames then return false end
    local changed, count = false, 0
    for _, frame in next, frames do
        count = count + 1
        local active, currentGeneration = A.automaticNameplatesEnabled()
        if count > 256 or owned ~= revision or not active or generation ~= currentGeneration then break end
        local unit = reader.nameplateUnit(frame)
        if unit and owned == revision and observe(unit, frame, generation) then changed = true end
    end
    return changed
end
