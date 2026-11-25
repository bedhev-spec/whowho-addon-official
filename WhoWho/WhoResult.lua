local A = WhowhoPreview.manual
local read, readable, member = A.nativeRead.read, A.nativeRead.readable, A.nativeRead.member
local result = {}
A.whoResult = result

local function plain(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", "")
        :gsub("|Hplayer:[^|]+|h([^|]+)|h", "%1"):gsub("|Hguild:[^|]+|h([^|]+)|h", "%1")
        :gsub("\194\160", " "):gsub("\226\128\175", " "))
end

local function textField(row, key)
    local value = member(row, key)
    if type(value) == "string" then return plain(value) end
end

function result.count(api)
    local count = member(api, "GetNumWhoResults")
    if type(count) ~= "function" then return end
    local ok, returned, total = pcall(count)
    if not ok or not readable(returned) or not readable(total) then return end
    if type(returned) == "number" and type(total) == "number" then return returned, total end
end

function result.totalText(count)
    local template = read(GetText, "WHO_NUM_RESULTS", nil, count)
    if type(template) ~= "string" and readable(WHO_NUM_RESULTS) then template = WHO_NUM_RESULTS end
    if type(template) ~= "string" or template == "" then return end
    local ok, text = pcall(string.format, template, count)
    if ok then return plain(text) end
end

local function exactRow(api, name)
    local row = read(member(api, "GetWhoInfo"), 1)
    if member(row, "fullName") ~= name then return end
    local level = member(row, "level")
    local race, class, guild, area = textField(row, "raceStr"), textField(row, "classStr"), textField(row, "fullGuildName"), textField(row, "area")
    if type(level) ~= "number" or level < 1 or level % 1 ~= 0
        or not race or race == "" or not class or class == "" or not guild or not area or area == "" then return end
    local file = member(row, "filename")
    local token = type(file) == "string" and file:match("^[A-Z]+$") and member(RAID_CLASS_COLORS, file) and file or nil
    local guildText = guild ~= "" and " <" .. guild .. ">" or ""
    local details = ("%d %s %s%s - %s"):format(level, race, class, guildText, area)
    return { level=level, class=token, details=details }
end

local function matchesPlayer(text, name, row)
    local prefix = ("[%d:%s]"):format(row.level, name)
    if text:sub(1, #prefix) ~= prefix then prefix = "[" .. name .. "]" end
    if text:sub(1, #prefix) == prefix then text = name .. text:sub(#prefix + 1) end
    -- French, English and German share this field order. The level label is localized.
    local player, details = text:match("^(.-) *: [^%s%d<>|%c:][^%d<>|%c:]* (%d.+)$")
    return player == name and details == row.details
end

function result.classify(api, name, message, singleTotal, emptyTotal)
    if not readable(message) or type(message) ~= "string" then return end
    local text = plain(message)
    local isSingle, isEmpty = text == singleTotal, text == emptyTotal
    if not isSingle and not isEmpty and not text:find(name, 1, true) then return end
    local returned, total = result.count(api)
    if isEmpty and returned == 0 and total == 0 then return "empty" end
    if returned ~= 1 or total ~= 1 then return end
    local row = exactRow(api, name)
    if not row then return end
    if isSingle then return "total", row end
    if matchesPlayer(text, name, row) then return "row", row end
end
