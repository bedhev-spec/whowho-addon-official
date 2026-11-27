-- Simulated manual TOC only; no native capability is established.
local root=arg[1] or "."; local H=dofile(root.."/tests/addon/harness.lua")
local seed,ss,se=H.fresh(root,nil,nil,{region=3,time=100})
ss:event("ADDON_LOADED","WhoWho")
local store=seed.manual.store
local function friend(name,source,hint,guid,region)
    local r=assert(store.add({fullName=name,region=region or 3,identityState="resolved",membership="friend",note=""},100))
    if source then assert(store.observe(r.id,r.region,name,guid or name,source,100,nil,nil,hint)) end
    return r.id
end
local guild=friend("Guild North","Guild",5,"g")
local recent=friend("Recent North","Recent Allies",true,"r")
local both=friend("Both North","Guild",5,"b")
assert(store.observe(both,3,"Both North","b","Recent Allies",100,nil,nil,true))
local noHint=friend("Unknown North")
local wrongClub=friend("Old North","Guild",6,"o")
local otherRegion=friend("Else North","Recent Allies",true,"e",4)
local database=store.export()
local function copy(value)
    if type(value)~="table" then return value end
    local result={}; for key,item in pairs(value) do result[key]=copy(item) end; return result
end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for key,value in pairs(a) do if not equal(value,b[key]) then return false end end
    for key in pairs(b) do if a[key]==nil then return false end end
    return true
end
local durableBefore=copy(database)
local function setup(preferences)
    local config={region=3,time=101,db=database}
    local p,s,e=H.fresh(root,preferences,nil,config)
    local state={guildReady=false,recentReady=false,guildCalls=0,memberReads=0,recentCalls=0,rows={},allies={}}
    e.InCombatLockdown=function() return false end
    e.C_Club={GetGuildClubId=function() return 5 end,AreMembersReady=function() return state.guildReady end,
        GetClubMembers=function() state.guildCalls=state.guildCalls+1; local ids={}; for i in ipairs(state.rows) do ids[i]=i end; return ids end,
        GetMemberInfo=function(_,id) state.memberReads=state.memberReads+1; return state.rows[id] end}
    e.Enum={ClubMemberPresence={Online=1,Away=2,Busy=3,Offline=4}}
    e.C_RecentAllies={IsSystemSupported=function() return true end,IsSystemEnabled=function() return true end,
        IsRecentAllyDataReady=function() return state.recentReady end,
        GetRecentAllies=function() state.recentCalls=state.recentCalls+1; return state.allies end,
        GetRecentAllyByFullName=function() error("per-Friend lookup forbidden") end,
        TryRequestRecentAlliesData=function() error("request forbidden") end}
    e.C_CreatureInfo={GetClassInfo=function() return {classFile="MAGE"} end}
    s:event("ADDON_LOADED","WhoWho")
    return p,s,e,state,config
end
local function row(p,id)
    p.manual.refresh()
    for _,v in ipairs(p.manual.records) do if v.id==id then return v end end
end
local function ally(name,guid,online)
    return {characterData={fullName=name,guid=guid,classID=8,level=42},stateData={isOnline=online}}
end
local function guildRow(name,guid,presence)
    return {name=name,guid=guid,presence=presence,classID=8,level=50}
end
local function assertNoRead(t) assert(t.guildCalls==0 and t.recentCalls==0 and t.memberReads==0) end
local p,s,e,t=setup({relogRefresh=false})
assert(not p.manual.relogRefreshEnabled())
s:event("PLAYER_ENTERING_WORLD",true,false); s:event("INITIAL_CLUBS_LOADED"); s:event("RECENT_ALLIES_DATA_READY"); assertNoRead(t)
p.Toggle(); p.Shell.nav.settings:Click(); p.Shell.settingsTabs.friends:Click(); local toggle=p.Shell.relogRefresh
assert(toggle and not toggle:GetChecked() and toggle.state:GetText()=="Off")
toggle:Click(); assert(toggle:GetChecked() and toggle.state:GetText()=="On" and p.manual.relogRefreshEnabled())
t.guildReady=true; t.recentReady=true
s:event("PLAYER_ENTERING_WORLD",false,false); s:event("CLUB_MEMBERS_UPDATED",5); s:event("RECENT_ALLIES_CACHE_UPDATE"); assertNoRead(t)
local prefs=e.WhowhoPreviewDB
-- A reload starts once; not-ready sources wait for their readiness events.
local q,u,v,w=setup(prefs)
w.rows={guildRow("Guild North","g",3),guildRow("Both North","b",4),guildRow("Unknown North","unknown",1),guildRow("Old North","o",1)}
w.allies={ally("Recent North","r",false),ally("Both North","b",true),ally("Else North","e",true)}
local before=v.WhowhoAddressBookDB
u:event("PLAYER_ENTERING_WORLD",false,true); assertNoRead(w)
w.recentReady=true; u:event("RECENT_ALLIES_DATA_READY")
assert(w.recentCalls==1 and row(q,recent).presenceReport.online==false)
assert(not row(q,noHint).presenceReport and not row(q,wrongClub).presenceReport and not row(q,otherRegion))
w.guildReady=true; u:event("INITIAL_CLUBS_LOADED")
assert(w.guildCalls==1 and row(q,guild).presenceReport.online==true)
assert(row(q,both).presenceReport.source=="Guild" and row(q,both).presenceReport.online==false)
u:event("PLAYER_ENTERING_WORLD",true,false); u:event("CLUB_MEMBERS_UPDATED",5); u:event("RECENT_ALLIES_CACHE_UPDATE"); u:event("PLAYER_REGEN_ENABLED")
assert(w.guildCalls==1 and w.recentCalls==1 and v.WhowhoAddressBookDB==before and u.forbiddenCalls==0)
-- Normal zone transitions never start the login job.
local z,zs,ze,zt=setup(prefs); zt.guildReady=true; zt.recentReady=true
zs:event("PLAYER_ENTERING_WORLD",false,false); zs:event("INITIAL_CLUBS_LOADED"); zs:event("RECENT_ALLIES_DATA_READY"); assertNoRead(zt)
-- No guild once clubs have loaded ends the Guild wait; earlier or unreadable answers do not.
local function listening(s,event)
    for _,frame in ipairs(s.nodes) do if frame.events[event] then return true end end
    return false
end
for _,case in ipairs({{inGuild=false,calls=0},{inGuild=true,calls=1},{secret=true,calls=1},{inGuild=false,secretClub=true,calls=1}}) do
    local g,gs,ge,gt=setup(prefs); local club
    ge.C_Club.GetGuildClubId=function() if case.secretClub and not club then return gs.secret end return club end
    ge.IsInGuild=function() if case.secret then return gs.secret end return case.inGuild end
    gs:event("PLAYER_ENTERING_WORLD",true,false); gs:event("CLUB_MEMBERS_UPDATED",5); gs:event("PLAYER_REGEN_ENABLED")
    gs:event("INITIAL_CLUBS_LOADED")
    -- GuildBlacklist keeps its own INITIAL_CLUBS_LOADED listener, so probe the relog-only event.
    assert(listening(gs,"CLUB_MEMBERS_UPDATED")==(case.calls==1))
    club=5; gt.guildReady=true; gt.rows={guildRow("Guild North","g",1)}
    gs:event("CLUB_MEMBERS_UPDATED",5)
    assert(gt.guildCalls==case.calls)
    gt.recentReady=true; gt.allies={ally("Recent North","r",true)}; gs:event("RECENT_ALLIES_DATA_READY")
    assert(gt.recentCalls==1 and row(g,recent).presenceReport.online==true)
    assert(not listening(gs,"CLUB_MEMBERS_UPDATED") and not listening(gs,"RECENT_ALLIES_CACHE_UPDATE"))
end
-- A usable club wins over a lagging IsInGuild.
local l,ls_,le,lt=setup(prefs); le.IsInGuild=function() return false end
lt.rows={guildRow("Guild North","g",1)}
ls_:event("PLAYER_ENTERING_WORLD",true,false); lt.guildReady=true; ls_:event("INITIAL_CLUBS_LOADED")
assert(lt.guildCalls==1 and row(l,guild).presenceReport.online==true)
-- IsInGuild false before clubs load is not trusted.
local o,os_,oe,ot=setup(prefs); local oclub
oe.C_Club.GetGuildClubId=function() return oclub end
oe.IsInGuild=function() return false end
os_:event("PLAYER_ENTERING_WORLD",true,false); os_:event("PLAYER_REGEN_ENABLED"); os_:event("RECENT_ALLIES_CACHE_UPDATE")
oclub=5; ot.guildReady=true; ot.rows={guildRow("Guild North","g",1)}
os_:event("CLUB_MEMBERS_UPDATED",5)
assert(ot.guildCalls==1)
-- Duplicate or conflicting identity rows cannot publish; unreadable and absent data stay Unknown.
local x,xs,xe,xt=setup(prefs); xt.guildReady=true; xt.recentReady=true
xt.rows={guildRow("Guild North","g",1),guildRow("Guild North","g",4),guildRow("Both North","wrong",1)}
xt.allies={ally("Recent North","wrong",true),ally("Both North","b",true),ally("Both North","b",false),ally("Unknown North","unknown",true)}
xs:event("PLAYER_ENTERING_WORLD",true,false)
assert(not row(x,guild).presenceReport and not row(x,recent).presenceReport and not row(x,both).presenceReport and not row(x,noHint).presenceReport)
assert(xe.WhowhoAddressBookDB==database and xs.forbiddenCalls==0)
-- Unrelated unknown identities are skipped; secret or missing status is never guessed.
local k,ks,ke,kt=setup(prefs); kt.guildReady=true; kt.recentReady=true
kt.rows={{name="Unrelated North"},guildRow("Guild North","g",1)}
kt.allies={{characterData={fullName="Other North"}},ally("Recent North","r",false),ally("Both North","b",nil)}
ks:event("PLAYER_ENTERING_WORLD",true,false)
assert(row(k,guild).presenceReport.online==true and row(k,recent).presenceReport.online==false)
assert(not row(k,both).presenceReport)
local h,hs,he,ht=setup(prefs); ht.guildReady=true; ht.recentReady=true
ht.rows={guildRow("Guild North","g",hs.secret),guildRow("Both North","b",99)}
ht.allies={ally("Recent North","r",hs.secret)}
hs:event("PLAYER_ENTERING_WORLD",true,false)
assert(not row(h,guild).presenceReport and not row(h,recent).presenceReport and not row(h,both).presenceReport)
assert(he.WhowhoAddressBookDB==database and hs.forbiddenCalls==0)
print("RESULT relog-refresh simulated passed; no client capability established")
-- A source may become ready after combat; a single later event resumes it.
local c,cs,ce,ct=setup(prefs); local combat=true
ce.InCombatLockdown=function() return combat end
ct.guildReady=true; ct.recentReady=true; ct.rows={guildRow("Guild North","g",1)}; ct.allies={ally("Recent North","r",true)}
cs:event("PLAYER_ENTERING_WORLD",true,false); assertNoRead(ct)
combat=false; cs:event("PLAYER_REGEN_ENABLED")
assert(row(c,guild).presenceReport.online and row(c,recent).presenceReport.online)
assert(ct.guildCalls==1 and ct.recentCalls==1)
-- Publication never replaces manual, target, or mouseover session results.
local raw=c.manual.store.get(guild)
for _,existing in ipairs({{presence="Seen"},{presenceReport={source="Manual",online=false}},{attempt="manual check"}}) do
    local item={id=guild,region=3,fullName="Guild North",membership="friend"}
    for k,value in pairs(existing) do item[k]=value end
    c.manual.relogRefresh.apply(item,raw)
    for k,value in pairs(existing) do assert(item[k]==value) end
    if not existing.presenceReport then assert(not item.presenceReport) end
end
-- The worker drops stale ownership when an event cancels during a native read.
local n,ns,ne,nt=setup(prefs); nt.guildReady=true; nt.recentReady=false
nt.rows={guildRow("Guild North","g",1)}
local get=ne.C_Club.GetMemberInfo
ne.C_Club.GetMemberInfo=function(...)
    local result=get(...); n.manual.setRelogRefresh(false); return result
end
ns:event("PLAYER_ENTERING_WORLD",true,false)
assert(not row(n,guild).presenceReport and ne.WhowhoAddressBookDB==database)
local j,js,je,jt,jconfig=setup(prefs); jt.guildReady=true; jt.recentReady=false
jt.rows={guildRow("Guild North","g",1)}
local memberRead=je.C_Club.GetMemberInfo
je.C_Club.GetMemberInfo=function(...)
    local result=memberRead(...); jconfig.region=4; return result
end
js:event("PLAYER_ENTERING_WORLD",true,false)
jconfig.region=3; assert(not row(j,guild).presenceReport and je.WhowhoAddressBookDB==database)
local re,rs,renv,rt=setup(prefs); rt.guildReady=true; rt.recentReady=false
rt.rows={guildRow("Guild North","g",1)}
local nestedRead=renv.C_Club.GetMemberInfo
renv.C_Club.GetMemberInfo=function(...)
    local result=nestedRead(...); rs:event("CLUB_MEMBERS_UPDATED",5); return result
end
rs:event("PLAYER_ENTERING_WORLD",true,false)
assert(rt.guildCalls==1 and rt.memberReads<=2 and renv.WhowhoAddressBookDB==database)
-- Readiness may arrive while a previously completed source is being displayed.
local a,as,ae,at=setup(prefs); at.guildReady=true
at.rows={guildRow("Both North","b",1)}
at.allies={ally("Recent North","r",true),ally("Both North","b",false)}
local apply=a.manual.relogRefresh.apply
local originalClub=ae.C_Club.GetGuildClubId
local displaying,fired=false,false
function a.manual.relogRefresh.apply(item,record)
    displaying=true
    apply(item,record)
    displaying=false
end
function ae.C_Club.GetGuildClubId()
    if displaying and not fired then
        fired=true
        at.recentReady=true
        as:event("RECENT_ALLIES_DATA_READY")
    end
    return originalClub()
end
a.Toggle()
local bound=a.Shell.records
as:event("PLAYER_ENTERING_WORLD",true,false)
assert(fired and at.guildCalls==1 and at.recentCalls==1 and bound==a.manual.records)
local seen={}
for _, item in ipairs(bound) do
    assert(not seen[item.id],"nested readiness duplicated a Friend")
    seen[item.id]=true
end
for id in pairs(a.manual.store.export().regions[3]) do assert(seen[id]) end
assert(row(a,both).presenceReport.source=="Guild" and row(a,recent).presenceReport.source=="Recent Allies")
-- The 100-Friend case takes one roster snapshot per source, not one per Friend.
local large,ls=H.fresh(root,nil,nil,{region=3,time=100}); ls:event("ADDON_LOADED","WhoWho")
for i=1,100 do
    local name="Person"..i.." North"; local id=assert(large.manual.store.add({fullName=name,region=3,identityState="resolved",membership="friend",note=""},100)).id
    assert(large.manual.store.observe(id,3,name,"guid"..i,"Guild",100,nil,nil,5))
    assert(large.manual.store.observe(id,3,name,"guid"..i,"Recent Allies",100,nil,nil,true))
end
local manyDB=large.manual.store.export()
local savedDatabase=database; database=manyDB
local many,manyS,manyE,manyT=setup(prefs); database=savedDatabase
for i=1,100 do
    manyT.rows[i]=guildRow("Person"..i.." North","guid"..i,1)
    manyT.allies[i]=ally("Person"..i.." North","guid"..i,true)
end
manyT.guildReady=true; manyT.recentReady=true
manyS:event("PLAYER_ENTERING_WORLD",true,false)
assert(manyT.guildCalls==1 and manyT.recentCalls==1 and manyT.memberReads<=200 and manyS.forbiddenCalls==0)
assert(manyE.WhowhoAddressBookDB==manyDB)
assert(equal(database,durableBefore))
print("RESULT relog-refresh extended simulated passed; no client capability established")
