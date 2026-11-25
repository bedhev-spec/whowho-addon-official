local P = WhowhoPreview
local A = P.manual
local D = {}
P.GuildBlacklistDetails = D

local MAX_NOTE = 256
local CHUNK, MAX_PENDING, MAX_PER_SENDER, TIMEOUT = 160, 32, 8, 240
local MAX_BODY = 160 + 12 + 3 + 4*MAX_NOTE
for _, reason in ipairs(A.reasons) do MAX_BODY=MAX_BODY+#reason.id+1 end
local MAX_CHUNKS = math.ceil(MAX_BODY*2/CHUNK)
local serial = 0
-- Unicode spaces outside the ordinary ASCII whitespace handled by %S.
local unicodeWhitespace={"\194\160","\225\154\128","\226\128[\128-\138\168\169\175]",
    "\226\129\159","\227\128\128"}

function D.mergeReasons(old, incoming)
    if not incoming then return old end
    local seen, added, merged = {}, false, {}
    for _, id in ipairs(old or {}) do seen[id]=true end
    for _, id in ipairs(incoming) do
        if not seen[id] then seen[id],added=true,true end
    end
    if not added then return old end
    for _, reason in ipairs(A.reasons) do
        if seen[reason.id] then merged[#merged+1]=reason.id end
    end
    return merged
end

function D.validNote(note)
    if type(note) ~= "string" or #note > MAX_NOTE*4
        or note:find("%z") or note:find("[\001-\008\011\012\014-\031\127]")
        or note:find("\194[\128-\159]") then return false end
    local count = P.CharacterName.CountScalars(note)
    if not count or count > MAX_NOTE then return false end
    for _, whitespace in ipairs(unicodeWhitespace) do note=note:gsub(whitespace,"") end
    return note:find("%S") ~= nil
end

function D.newerNote(note, rev, old, oldRev)
    if not note then return false end
    if not old or rev ~= oldRev then return not old or rev > oldRev end
    -- Compare bytes independently of the client's collation locale.
    for index=1,math.min(#note,#old) do
        local left, right=note:byte(index),old:byte(index)
        if left ~= right then return left > right end
    end
    return #note > #old
end

local function hex(byte)
    return string.format("%02x",byte:byte())
end

local function unhex(pair)
    return string.char(tonumber(pair,16))
end

function D.transfer(name, row)
    serial=serial%999999999+1
    local body=string.format("%.0f|%s|%s|%s",row.noteRev or 0,
        table.concat(row.reasonIds or {},","),name,row.note or "")
    -- ASCII framing keeps whitespace and multibyte text intact across packet boundaries.
    local encoded=body:gsub(".",hex)
    return {id=string.format("%d.%d",serial,math.random(1,2147483646)),
        encoded=encoded,index=1,count=math.ceil(#encoded/CHUNK)}
end

function D.packet(scope, transfer)
    local start=(transfer.index-1)*CHUNK+1
    return string.format("D|%s|%s|%d|%d|%s",scope,transfer.id,transfer.index,transfer.count,
        transfer.encoded:sub(start,start+CHUNK-1))
end

function D.receive(pending, sender, payload, at, lastRevision, validName)
    local token, index, total, part=payload:match("^(%d+%.%d+)|(%d+)|(%d+)|([0-9a-f]+)$")
    if not token or #token > 20 or #index > 2 or #total > 2 or #part > CHUNK or #part%2 ~= 0 then return end
    index,total=tonumber(index),tonumber(total)
    if index < 1 or index > total or total > MAX_CHUNKS or index < total and #part ~= CHUNK then return end

    local key, active, owned=sender.."\000"..token, 0, 0
    for id, transfer in pairs(pending) do
        if at >= transfer.expires then
            pending[id]=nil
        else
            active=active+1
            if transfer.sender == sender then owned=owned+1 end
        end
    end
    local transfer=pending[key]
    if transfer and (transfer.total ~= total or transfer[index] and transfer[index] ~= part) then
        -- Keep a conflicting token unusable until it expires.
        transfer.invalid=true
    end
    if not transfer then
        if total > 1 and (active >= MAX_PENDING or owned >= MAX_PER_SENDER) then return end
        transfer={expires=at+TIMEOUT,total=total,received=0,sender=sender}
        pending[key]=transfer
    end
    if transfer.invalid or transfer[index] then return end
    transfer[index],transfer.received=part,transfer.received+1
    if transfer.received ~= total then return end
    pending[key]=nil
    local encoded=table.concat(transfer)
    if #encoded > MAX_BODY*2 then return end

    local body=encoded:gsub("..",unhex)
    local digits, reasonText, name, note=body:match("^(%d+)|([^|]*)|([^|]+)|(.*)$")
    if not digits or not validName(name) then return end
    local rev=#digits <= 12 and tonumber(digits) or math.huge
    if note == "" then
        if digits ~= "0" then return end
        note,rev=nil,nil
    elseif rev < 1 or not D.validNote(note) then
        return
    elseif rev > lastRevision then
        note,rev=nil,nil
    end
    local reasons
    if reasonText ~= "" then
        reasons={}
        for item in (reasonText..","):gmatch("([^,]*),") do reasons[#reasons+1]=item end
        if not A.validReasons(reasons) then return end
    elseif not note then
        return
    end
    return name, reasons, note, rev
end
