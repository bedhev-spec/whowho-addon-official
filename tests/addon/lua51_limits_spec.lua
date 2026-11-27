-- Simulated with the installed TOC. Guards Lua 5.1 compile limits that the Fengari runner would accept.
local root=arg[1] or "."
local H=dofile(root.."/tests/addon/harness.lua")
local count=0
local function check(cond,msg)
    count=count+1
    if not cond then print("FAIL "..msg); os.exit(1) end
end

local p,s,e=H.fresh(root,nil,nil,{region=3,time=100})
e.GetLocale=function() return "enUS" end
e.IsInGuild=function() return true end
e.C_Club={GetGuildClubId=function() return 101 end}
e.C_ChatInfo={RegisterAddonMessagePrefix=function() return 0 end,InChatMessagingLockdown=function() return false end,
    SendAddonMessage=function() return 0 end}
e.C_Timer={After=function() end}
s:event("ADDON_LOADED","WhoWho")
p.Toggle()
local S=p.Shell
S.window:Show()
S.nav.settings:Click()
for _,tab in pairs(S.settingsTabs) do tab:Click() end
S.editor.Open({fullName="Former Friend",note=""},"blacklist")

-- Lua 5.1 allows 60 upvalues per function; _ENV is not an upvalue there.
local function upvalues(fn)
    local n=0
    for i=1,255 do
        local name=debug.getupvalue(fn,i)
        if not name then break end
        if name~="_ENV" then n=n+1 end
    end
    return n
end

local seen,found,files={},{},{}
local function walk(v)
    local kind=type(v)
    if kind~="table" and kind~="function" then return end
    if seen[v] then return end
    seen[v]=true
    if kind=="table" then
        for k,x in next,v do walk(k); walk(x) end
        return
    end
    local info=debug.getinfo(v,"S")
    if info.what~="Lua" then return end
    local file=info.short_src:gsub(string.char(92),"/"):match("[^/]*$")
    found[#found+1]={n=upvalues(v),where=file..":"..info.linedefined}
    files[file]=true
    for i=1,255 do
        local name,value=debug.getupvalue(v,i)
        if not name then break end
        walk(value)
    end
end
walk(p)
walk(s.nodes)

table.sort(found,function(a,b) return a.n>b.n end)
print("functions walked "..#found)
for i=1,math.min(5,#found) do print(("upvalues %d %s"):format(found[i].n,found[i].where)) end
check(#found>1000,"walker reaches a meaningful number of functions")
for _,file in ipairs({"Shell.lua","Settings.lua","EditorDialog.lua","GuildBlacklist.lua"}) do
    check(files[file],"walker reaches "..file)
end
check(found[1].n<=60,"no addon function exceeds the Lua 5.1 upvalue limit")

local names,lines={},{}
for i=1,61 do names[i]="v"..i; lines[i]="local v"..i.."="..i end
local chunk=table.concat(lines," ").." return function() return "..table.concat(names,"+").." end"
check(upvalues(assert(load(chunk))())==61,"walker counts 61 upvalues of a synthetic function")

print(("RESULT lua51 limits %d checks passed"):format(count))
