local A = WhowhoPreview.manual
local function readable(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == false
end
local function read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or not readable(value) then return nil end
    return value
end
local function safeTable(value)
    if not readable(value) or type(value) ~= "table" or type(issecrettable) ~= "function" then return false end
    local ok, secret = pcall(issecrettable, value)
    return ok and readable(secret) and secret == false
end
local function member(value, key)
    if not safeTable(value) then return nil end
    local ok, result = pcall(function() return value[key] end)
    if not ok or not readable(result) then return nil end
    return result
end
A.nativeRead = {readable=readable, read=read, safeTable=safeTable, member=member}
