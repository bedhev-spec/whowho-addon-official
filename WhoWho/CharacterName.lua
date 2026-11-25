local Name = {}
WhowhoPreview.CharacterName = Name

function Name.CountScalars(text)
    local i, count = 1, 0
    while i <= #text do
        local a = text:byte(i); local n, low, high = 1, 128, 191
        if a < 128 then n=1
        elseif a >= 194 and a <= 223 then n=2
        elseif a >= 224 and a <= 239 then n=3; if a==224 then low=160 elseif a==237 then high=159 end
        elseif a >= 240 and a <= 244 then n=4; if a==240 then low=144 elseif a==244 then high=143 end
        else return nil end
        if n>1 then
            local b=text:byte(i+1); if not b or b<low or b>high then return nil end
            for j=2,n-1 do local c=text:byte(i+j); if not c or c<128 or c>191 then return nil end end
        end
        count=count+1; i=i+n
    end
    return count
end
-- Only manual input is normalized: preserve token bytes, canonicalize separators.
function Name.NormalizeManual(text, allowDraft)
    if not Name.CountScalars(text) then return nil end
    local parts, token, i, boundaryControl = {}, {}, 1, false
    while i <= #text do
        local a=text:byte(i); local n=a<128 and 1 or a<224 and 2 or a<240 and 3 or 4
        local cp=a%(n==1 and 128 or n==2 and 32 or n==3 and 16 or 8)
        for j=1,n-1 do cp=cp*64+(text:byte(i+j)-128) end
        local space=cp==0x20 or cp==0xA0 or cp==0x1680 or (cp>=0x2000 and cp<=0x200A)
            or cp==0x202F or cp==0x205F or cp==0x3000
        local hidden=cp<0x20 or (cp>=0x7F and cp<=0x9F) or cp==0xAD or cp==0x34F
            or cp==0x61C or cp==0x180E or (cp>=0x200B and cp<=0x200F)
            or (cp>=0x2028 and cp<=0x202E) or (cp>=0x2060 and cp<=0x206F)
            or (cp>=0xFE00 and cp<=0xFE0F) or cp==0xFEFF or (cp>=0xFFF9 and cp<=0xFFFB)
            or cp==0xE0001 or (cp>=0xE0020 and cp<=0xE007F) or (cp>=0xE0100 and cp<=0xE01EF)
        local outerControl=cp>=9 and cp<=13
        if outerControl then
            if #token>0 then parts[#parts+1]=table.concat(token); token={} end
            if #parts>0 then boundaryControl=true end
        elseif hidden then return nil
        elseif space then
            if #token>0 then parts[#parts+1]=table.concat(token); token={} end
        else
            if boundaryControl then return nil end
            token[#token+1]=text:sub(i,i+n-1)
        end
        i=i+n
    end
    if #token>0 then parts[#parts+1]=table.concat(token) end
    if allowDraft and #parts==1 then return parts[1] end
    if #parts~=2 then return nil end
    return parts[1].." "..parts[2]
end
function Name.IsComplete(name)
    return type(name)=="string" and Name.NormalizeManual(name)==name
end
function Name.IsFriendDraft(name)
    return type(name)=="string" and not name:find(" ",1,true) and Name.NormalizeManual(name,true)==name
end
