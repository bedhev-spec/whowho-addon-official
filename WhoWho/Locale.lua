local P=WhowhoPreview
local french

function P.InitLanguage()
    local locale=P.manual.nativeRead.read(GetLocale)
    P.clientLocale=type(locale)=="string" and locale or "enUS"
    french=P.clientLocale=="frFR" and P.localeFr
end

function P.L(english,...)
    local text=french and french[english] or english
    if select("#",...)>0 then return string.format(text,...) end
    return text
end
