local P=WhowhoPreview
local french

function P.InitLanguage()
    local locale
    if P.manual then
        locale=P.manual.nativeRead.read(GetLocale)
    elseif type(GetLocale)=="function" and type(issecretvalue)=="function" then
        local ok,value=pcall(GetLocale)
        if ok then
            local checked,secret=pcall(issecretvalue,value)
            if checked and secret==false then locale=value end
        end
    end
    P.clientLocale=type(locale)=="string" and locale or "enUS"
    french=P.manual and P.clientLocale=="frFR" and P.localeFr
end

function P.L(english,...)
    local text=french and french[english] or english
    if select("#",...)>0 then return string.format(text,...) end
    return text
end
