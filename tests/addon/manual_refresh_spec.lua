-- Simulated manual TOC only; no native capability is established.
local root=arg[1] or "."; local H=dofile(root.."/tests/addon/harness.lua")
local function seed(count)
    local p,s=H.fresh(root,nil,nil,{region=3,time=100}); s:event("ADDON_LOADED","WhoWho")
    local ids={}
    for i=1,count do
        local name="Person"..i.." North"
        ids[i]=assert(p.manual.store.add({fullName=name,region=3,identityState="resolved",membership="friend",note=""},100)).id
    end
    return p.manual.store.export(),ids
end
local function setup(db,clock,prefs)
    local config={region=3,time=clock or 100,db=db}
    local p,s,e=H.fresh(root,prefs,nil,config)
    local t={group=0,guild=0,members=0,recent=0,order={},rows={},allies={},units={}}
    e.InCombatLockdown=function() return false end
    e.C_Secrets={ShouldUnitIdentityBeSecret=function() return false end}
    e.IsInRaid=function() return false end
    e.GetNumSubgroupMembers=function() t.group=t.group+1; if t.group==1 then t.order[#t.order+1]="group" end; return t.unitCount or 0 end
    e.UnitExists=function(unit) return t.units[unit]~=nil end
    e.UnitIsUnit=function() return false end
    e.GetUnitName=function(unit) return t.units[unit].name end
    e.UnitGUID=function(unit) return t.units[unit].guid end
    e.UnitClass=function() return "Mage","MAGE" end
    e.UnitLevel=function() return 42 end
    e.UnitIsConnected=function(unit) return t.units[unit].online end
    e.C_Club={GetGuildClubId=function() return 5 end,AreMembersReady=function() return true end,
        GetClubMembers=function() t.guild=t.guild+1; t.order[#t.order+1]="guild"; local ids={}; for i in ipairs(t.rows) do ids[i]=i end; return ids end,
        GetMemberInfo=function(_,id) t.members=t.members+1; return t.rows[id] end}
    e.Enum={ClubMemberPresence={Online=1,Away=2,Busy=3,Offline=4}}
    e.C_RecentAllies={IsSystemSupported=function() return true end,IsSystemEnabled=function() return true end,
        IsRecentAllyDataReady=function() return true end,
        GetRecentAllies=function() t.recent=t.recent+1; t.order[#t.order+1]="recent"; return t.allies end,
        GetRecentAllyByFullName=function() error("per-Friend lookup forbidden") end,
        TryRequestRecentAlliesData=function() error("request forbidden") end}
    e.C_CreatureInfo={GetClassInfo=function() return {classFile="MAGE"} end}
    s:event("ADDON_LOADED","WhoWho")
    return p,s,e,t,config
end
local function guild(name,guid,online) return {name=name,guid=guid,presence=online and 1 or 4} end
local function ally(name,guid,online) return {characterData={fullName=name,guid=guid},stateData={isOnline=online}} end
local function row(p,id)
    p.manual.refresh()
    for _,r in ipairs(p.manual.records) do if r.id==id then return r end end
end
local function status(p) return p.manual.batchRefresh.state() end
local function copy(value)
    if type(value)~="table" then return value end
    local result={}; for k,v in pairs(value) do result[k]=copy(v) end; return result
end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local db,ids=seed(4)
local before=copy(db)
local p,s,e,t,config=setup(db)
t.units.party1={name="Person1 North",guid="g1",online=true}; t.unitCount=1
t.rows={guild("Person1 North","g1",false),guild("Person2 North","g2",false)}
t.allies={ally("Person1 North","g1",false),ally("Person2 North","g2",true),ally("Person3 North","g3",true)}
p.Toggle(); assert(p.Shell.refreshNow and p.Shell.refreshStatus)
assert(p.Shell.refreshNow.label:GetText()=="Refresh rosters")
assert(p.Shell.refreshNow.label:GetStringWidth()+p.Shell.refreshNow.icon:GetWidth()+7<=p.Shell.refreshNow:GetWidth())
s:fire(p.Shell.refreshNow,"OnEnter")
assert(e.GameTooltip:GetText()=="Checks your group, guild, and Recent Allies. Check status can also try Who for an eligible Friend.")
s:fire(p.Shell.refreshNow,"OnLeave"); assert(not e.GameTooltip:IsShown())
p.Shell.refreshNow:Click()
assert(t.group>=1 and t.group<=3 and t.guild==1 and t.recent==1 and table.concat(t.order,",")=="group,guild,recent")
assert(row(p,ids[1]).presenceReport.source=="Party" and row(p,ids[1]).presenceReport.online==true)
assert(row(p,ids[2]).presenceReport.source=="Guild" and row(p,ids[2]).presenceReport.online==false)
assert(row(p,ids[3]).presenceReport.source=="Recent Allies" and row(p,ids[3]).presenceReport.online==true)
assert(not row(p,ids[4]).presenceReport)
-- Direct observations and explicit checks retain their stronger session evidence.
local raw=p.manual.store.get(ids[1])
for _,existing in ipairs({{presence="Seen"},{presenceReport={source="Manual",online=false}}}) do
    local item={id=ids[1],region=3,fullName="Person1 North",membership="friend"}
    for k,v in pairs(existing) do item[k]=v end
    p.manual.relogRefresh.apply(item,raw)
    for k,v in pairs(existing) do assert(item[k]==v) end
    if not existing.presenceReport then assert(not item.presenceReport) end
end
local busy,remaining,text=status(p)
assert(not busy and remaining and remaining>=30 and text=="Roster status found for 3 of 4 Friends.")
assert(s.forbiddenCalls==0 and equal(e.WhowhoAddressBookDB,before))
-- Final Group identity validation can invalidate a staged Guild report.
do
    local initial, ids = seed(2)
    local app, sim, env, data = setup(initial)
    local ready, guidReads = true, 0
    data.unitCount = 1
    data.units.party1 = {name="Person1 North",guid="g1",online=true}
    data.rows = {guild("Person2 North","g2",true)}
    data.allies = {ally("Person2 North","g2",false)}
    env.C_Club.AreMembersReady = function() return ready end
    env.UnitGUID = function(unit)
        guidReads = guidReads + 1
        if guidReads == 2 then ready = false end
        return data.units[unit].guid
    end
    local before = env.WhowhoAddressBookDB
    app.manual.batchRefresh.run()
    assert(guidReads==2 and not ready, "the final Group identity read must invalidate Guild readiness")
    assert(row(app,ids[1]).presenceReport.source=="Party")
    local report = row(app,ids[2]).presenceReport
    assert(report and report.source=="Recent Allies" and report.online==false,
        "an unready Guild result must yield to the still-ready Recent Allies result")
    assert(env.WhowhoAddressBookDB==before and sim.forbiddenCalls==0)
end
-- A roster readiness check can also recycle a staged Group token.
do
    local initial, ids = seed(1)
    local app, sim, env, data = setup(initial)
    data.unitCount = 1
    data.units.party1 = {name="Person1 North",guid="g1",online=true}
    data.allies = {ally("Person1 North","g1",false)}
    local checks = 0
    env.C_Club.AreMembersReady = function()
        checks = checks + 1
        if checks == 4 then data.units.party1 = {name="Other North",guid="other",online=true} end
        return true
    end
    app.manual.batchRefresh.run()
    local report = row(app,ids[1]).presenceReport
    assert(checks==4 and report and report.source=="Recent Allies" and report.online==false,
        "a Group token recycled during readiness must yield to the still-valid roster result")
    assert(sim.forbiddenCalls==0)
end
-- The cooldown blocks duplicates, survives navigation and reload, and expires by server time.
p.Shell.refreshNow:Click(); p.Shell.nav.settings:Click(); p.Toggle(); p.Toggle()
assert(t.group<=3 and t.guild==1 and t.recent==1)
local q,qs,qe,qt,qconfig=setup(e.WhowhoAddressBookDB,101,e.WhowhoPreviewDB)
local _,left=status(q); assert(left and left>=29)
q.manual.batchRefresh.run(); assert(qt.group==0 and qt.guild==0 and qt.recent==0)
qconfig.time=131; q.manual.batchRefresh.run(); assert(qt.group>=1 and qt.group<=3 and qt.guild==1 and qt.recent==1)
assert(qs.forbiddenCalls==0)
-- Visible countdown updates from persisted server time, and stops offscreen.
local timed=seed(1); local v,vs,ve,vt,vc=setup(timed)
v.Toggle(); local button=v.Shell.refreshNow
button:Click(); assert(button.label:GetText()=="Refresh in 30s" and not button:IsEnabled())
assert(button:GetScript("OnUpdate"))
v.Shell.nav.settings:Click(); assert(not button:GetScript("OnUpdate"))
vc.time=110; v.Shell.nav.friend:Click()
assert(button.label:GetText()=="Refresh in 20s" and button:GetScript("OnUpdate"))
v.Shell.window:Hide(); assert(not button:GetScript("OnUpdate"))
vc.time=129; v.Shell.Open()
assert(button.label:GetText()=="Refresh in 1s" and not button:IsEnabled())
vs:fire(button,"OnUpdate",.25); assert(button.label:GetText()=="Refresh in 1s")
vc.time=130; vs:fire(button,"OnUpdate",.25)
assert(button.label:GetText()=="Refresh rosters" and button:IsEnabled() and not button:GetScript("OnUpdate"))
assert(ve.WhowhoPreviewDB.refreshReadyAt==130 and vs.forbiddenCalls==0)
-- A corrupt or rolled-back future deadline is rebased once and survives reconnect.
local skew=seed(1); local skewed,skews,skewenv=setup(skew,1000,{refreshReadyAt=90000})
local _,skewLeft=status(skewed)
assert(skewLeft==30 and skewenv.WhowhoPreviewDB.refreshReadyAt==1030)
local skewReload,skewReloadS,_,skewT,skewClock=setup(skew,1001,skewenv.WhowhoPreviewDB)
local _,reloadedLeft=status(skewReload); assert(reloadedLeft==29)
skewReload.manual.batchRefresh.run(); assert(skewT.group==0 and skewT.guild==0 and skewT.recent==0)
skewClock.time=1030; local _,expired=status(skewReload); assert(expired==0)
skewReload.manual.batchRefresh.run(); assert(skewT.guild==1 and skewT.recent==1)
assert(skews.forbiddenCalls==0 and skewReloadS.forbiddenCalls==0)
-- Reentrant activation during the first read cannot start a second batch.
local rd,ri=seed(1); local r,rs,re,rt=setup(rd)
rt.rows={guild("Person1 North","g1",true)}
local members=re.C_Club.GetClubMembers
re.C_Club.GetClubMembers=function() assert(re.WhowhoPreviewDB.refreshReadyAt>=130); r.manual.batchRefresh.run(); return members() end
r.manual.batchRefresh.run(); assert(rt.group>=1 and rt.group<=3 and rt.guild==1 and rt.recent==1)
local _,_,single=status(r); assert(single=="Roster status found for 1 of 1 Friend.")
assert(rs.forbiddenCalls==0)
-- An earlier failed Check status keeps its Last check text while batch supplies status.
local failed,di=seed(1); local d,ds,de,dt=setup(failed)
de.UnitIsPlayer=function() return false end
d.manual.targetCheck.check(d.manual.store.get(di[1]))
assert(row(d,di[1]).attempt and not row(d,di[1]).presenceReport)
dt.allies={ally("Person1 North","g1",true)}; d.manual.batchRefresh.run()
assert(row(d,di[1]).attempt and row(d,di[1]).presenceReport.source=="Recent Allies" and row(d,di[1]).presenceReport.online==true)
assert(ds.forbiddenCalls==0)
-- A later batch supersedes an older individual roster report, but a newer check wins.
local explicit,ei=seed(1); local k,ks,ke,kt=setup(explicit)
ke.UnitIsPlayer=function() return false end
kt.unitCount=1; kt.units.party1={name="Person1 North",guid="g1",online=false}
k.manual.targetCheck.check(k.manual.store.get(ei[1]))
assert(row(k,ei[1]).presenceReport.source=="Party" and row(k,ei[1]).presenceReport.online==false)
kt.unitCount=0; kt.allies={ally("Person1 North","g1",true)}
k.manual.batchRefresh.run()
assert(row(k,ei[1]).presenceReport.source=="Recent Allies" and row(k,ei[1]).presenceReport.online==true)
kt.unitCount=1; kt.units.party1.online=false
k.manual.targetCheck.check(k.manual.store.get(ei[1]))
assert(row(k,ei[1]).presenceReport.source=="Party" and row(k,ei[1]).presenceReport.online==false)
assert(ks.forbiddenCalls==0)
local concurrent,oi=seed(1); local o,os,oe,ot=setup(concurrent)
oe.UnitIsPlayer=function() return false end
assert(o.manual.store.observe(oi[1],3,"Person1 North","g1","Party",100,"MAGE",42))
ot.unitCount=1; ot.units.party1={name="Person1 North",guid="g1",online=true}
ot.allies={ally("Person1 North","g1",true)}
local recentRead=oe.C_RecentAllies.GetRecentAllies
oe.C_RecentAllies.GetRecentAllies=function()
    local result=recentRead(); ot.units.party1.online=false
    o.manual.targetCheck.check(o.manual.store.get(oi[1]))
    return result
end
o.manual.batchRefresh.run()
assert(row(o,oi[1]).presenceReport.source=="Party" and row(o,oi[1]).presenceReport.online==false)
local _,_,concurrentText=status(o); assert(concurrentText=="Roster status found for 1 of 1 Friend.",tostring(concurrentText))
assert(os.forbiddenCalls==0)
-- Without an eligible current-region Friend, no snapshot or cooldown is consumed.
local empty=seed(0); local n,ns,ne,nt=setup(empty)
assert(n.manual.store.add({fullName="Else North",region=4,identityState="resolved",membership="friend",note=""},100))
n.manual.batchRefresh.run(); assert(nt.group==0 and nt.guild==0 and nt.recent==0)
local _,emptyLeft=status(n); assert(not emptyLeft or emptyLeft==0)
assert(ns.forbiddenCalls==0)
-- A wrong readable GUID, incomplete name, unreadable status or another region cannot publish.
local identity,ii=seed(4); local a,as,ae,at=setup(identity)
assert(a.manual.store.observe(ii[1],3,"Person1 North","expected","Guild",100,nil,nil,5))
at.rows={guild("Person1 North","wrong",true),guild("Person2","g2",true),{name="Person3 North",guid="g3",presence=as.secret}}
at.allies={ally("Person4 North","g4",as.secret)}
a.manual.batchRefresh.run()
for _,id in ipairs(ii) do assert(not row(a,id).presenceReport) end
assert(as.forbiddenCalls==0)
-- An unbound GUID cannot publish for two names across different sources.
local conflictDB,conflictIds=seed(3)
local u,us,ue,ut=setup(conflictDB)
ut.rows={guild("Person1 North","shared",true)}
ut.allies={ally("Person2 North","shared",false),ally("Person3 North","distinct",true)}
u.manual.batchRefresh.run()
assert(not row(u,conflictIds[1]).presenceReport and not row(u,conflictIds[2]).presenceReport)
assert(row(u,conflictIds[3]).presenceReport.online and select(3,status(u))=="Roster status found for 1 of 3 Friends.")
assert(us.forbiddenCalls==0)
-- A failed source is contained; later sources still supply status.
local fail,fi=seed(1); local f,fs,fe,ft=setup(fail)
fe.C_Club.GetClubMembers=function() error("unavailable") end
ft.allies={ally("Person1 North","g1",true)}
f.manual.batchRefresh.run(); assert(row(f,fi[1]).presenceReport.online==true and ft.recent==1 and fs.forbiddenCalls==0)
-- A recycled group token loses only its own group report; other sources still answer.
local recycled,xi=seed(3); local x,xs,xe,xt=setup(recycled)
xt.unitCount=2
xt.units.party1={name="Person1 North",guid="g1",online=true}
xt.units.party2={name="Person2 North",guid="g2",online=true}
xt.rows={guild("Person1 North","g1",false)}
xt.allies={ally("Person3 North","g3",true)}
local names,guids,connections={},{},{}
xe.GetUnitName=function(unit)
    names[unit]=(names[unit] or 0)+1
    if unit=="party1" and names[unit]>1 then return "Recycled North" end
    return xt.units[unit].name
end
xe.UnitGUID=function(unit) guids[unit]=(guids[unit] or 0)+1; return xt.units[unit].guid end
xe.UnitIsConnected=function(unit) connections[unit]=(connections[unit] or 0)+1; return true end
x.manual.batchRefresh.run()
assert(row(x,xi[1]).presenceReport.source=="Guild" and row(x,xi[1]).presenceReport.online==false)
assert(row(x,xi[2]).presenceReport.source=="Party" and row(x,xi[3]).presenceReport.source=="Recent Allies")
assert(names.party1<=2 and names.party2<=2 and guids.party1<=2 and guids.party2<=2)
assert(connections.party1==1 and connections.party2==1 and xs.forbiddenCalls==0)
-- Unreadable identity during validation falls back without losing another Raid result.
local raid,ai=seed(2); local z,zs,ze,zt=setup(raid)
zt.units.raid1={name="Person1 North",guid="g1",online=true}
zt.units.raid2={name="Person2 North",guid="g2",online=true}
ze.IsInRaid=function() return true end; ze.GetNumGroupMembers=function() return 2 end
zt.allies={ally("Person1 North","g1",false)}
local raidNames={}
ze.GetUnitName=function(unit)
    raidNames[unit]=(raidNames[unit] or 0)+1
    if unit=="raid1" and raidNames[unit]>1 then return zs.secret end
    return zt.units[unit].name
end
z.manual.batchRefresh.run()
assert(row(z,ai[1]).presenceReport.source=="Recent Allies" and row(z,ai[1]).presenceReport.online==false)
assert(row(z,ai[2]).presenceReport.source=="Raid" and raidNames.raid1<=2 and raidNames.raid2<=2)
assert(zs.forbiddenCalls==0)
-- If Guild becomes unready during the later snapshot, Recent Allies supplies its answer.
local changing,ci=seed(2); local y,ys,ye,yt=setup(changing)
local guildReady=true
ye.C_Club.AreMembersReady=function() return guildReady end
yt.rows={guild("Person1 North","g1",false)}
yt.allies={ally("Person1 North","g1",true),ally("Person2 North","g2",false)}
local getAllies=ye.C_RecentAllies.GetRecentAllies
ye.C_RecentAllies.GetRecentAllies=function() local result=getAllies(); guildReady=false; return result end
y.manual.batchRefresh.run()
assert(row(y,ci[1]).presenceReport.source=="Recent Allies" and row(y,ci[1]).presenceReport.online==true)
assert(row(y,ci[2]).presenceReport.source=="Recent Allies" and row(y,ci[2]).presenceReport.online==false)
assert(yt.guild==1 and yt.recent==1 and ys.forbiddenCalls==0)
-- A nested ready event starts a newer relog Guild snapshot during the batch read.
local nested,ni=seed(2); local initial,initialS=setup(nested)
assert(initial.manual.store.observe(ni[1],3,"Person1 North","g1","Guild",100,nil,nil,5))
initial.manual.setRelogRefresh(true)
local j,js,je,jt=setup(initial.manual.store.export(),101,initialS and initial.db)
local ready=false
je.C_Club.AreMembersReady=function() return ready end
jt.rows={guild("Person1 North","g1",true)}
jt.allies={ally("Person2 North","g2",true)}
js:event("PLAYER_ENTERING_WORLD",false,true)
ready=true
local getMember=je.C_Club.GetMemberInfo; local triggered=false
je.C_Club.GetMemberInfo=function(...)
    local old=getMember(...)
    if not triggered then
        triggered=true; jt.rows[1]=guild("Person1 North","g1",false)
        js:event("CLUB_MEMBERS_UPDATED",5)
    end
    return old
end
j.manual.batchRefresh.run()
assert(triggered and row(j,ni[1]).presenceReport.source=="Guild" and row(j,ni[1]).presenceReport.online==false)
assert(row(j,ni[2]).presenceReport.source=="Recent Allies")
assert(jt.guild==2 and jt.recent>=1 and jt.recent<=2 and js.forbiddenCalls==0)
-- A newer exact relog report also supersedes a previous batch report from the same source.
local late,lateS,lateE,lateT=setup(initial.manual.store.export(),101,initial.db)
local lateReady=false
lateE.C_Club.AreMembersReady=function() return lateReady end
lateT.rows={guild("Person1 North","g1",true)}
lateS:event("PLAYER_ENTERING_WORLD",false,true)
lateReady=true
late.manual.batchRefresh.run()
assert(row(late,ni[1]).presenceReport.online==true and lateT.guild==1)
lateT.rows[1]=guild("Person1 North","g1",false)
lateS:event("CLUB_MEMBERS_UPDATED",5)
assert(row(late,ni[1]).presenceReport.online==false and lateT.guild==2 and lateS.forbiddenCalls==0)
-- A metadata-less individual report binds identity even without a durable GUID.
local identityOnly,bi=seed(1); local b1,b1s,b1e,b1t=setup(identityOnly)
b1e.UnitIsPlayer=function() return false end; b1e.UnitClass=function() return nil end; b1e.UnitLevel=function() return nil end
b1t.unitCount=1; b1t.units.party1={name="Person1 North",guid="old-guid",online=false}
b1.manual.targetCheck.check(b1.manual.store.get(bi[1]))
assert(row(b1,bi[1]).presenceReport.source=="Party" and row(b1,bi[1]).presenceReport.online==false)
local saved=b1.manual.store.get(bi[1]); assert(not saved.lastKnown or not saved.lastKnown.guid)
b1t.unitCount=0; b1t.rows={guild("Person1 North","new-guid",true)}
b1.manual.batchRefresh.run()
assert(row(b1,bi[1]).presenceReport.source=="Party" and row(b1,bi[1]).presenceReport.online==false and b1s.forbiddenCalls==0)
-- Conflicting unbound identities across sources cannot publish; an independent match can.
local conflict,ci2=seed(2); local cf,cfs,cfe,cft=setup(conflict)
cft.rows={guild("Person1 North","guild-guid",true),guild("Person2 North","g2",false)}
cft.allies={ally("Person1 North","ally-guid",false)}
cf.manual.batchRefresh.run()
assert(not row(cf,ci2[1]).presenceReport)
assert(row(cf,ci2[2]).presenceReport.source=="Guild" and row(cf,ci2[2]).presenceReport.online==false)
assert(cfs.forbiddenCalls==0)
-- Missing status can still provide readable identity evidence for or against a match.
local partial,partialIds=seed(3); local ps,pss,_,pst=setup(partial)
pst.unitCount=1; pst.units.party1={name="Person3 North",guid="g3"}
pst.rows={guild("Person1 North","guild-guid",true),guild("Person2 North","g2",false),guild("Person3 North","g3",true)}
pst.allies={ally("Person1 North","ally-guid",nil),ally("Person2 North","g2",nil)}
ps.manual.batchRefresh.run()
assert(not row(ps,partialIds[1]).presenceReport)
assert(row(ps,partialIds[2]).presenceReport.online==false)
assert(row(ps,partialIds[3]).presenceReport.source=="Guild" and row(ps,partialIds[3]).presenceReport.online==true)
assert(select(3,status(ps))=="Roster status found for 2 of 3 Friends." and pss.forbiddenCalls==0)
-- Only a verified individual Guild absence retires the batch report.
do
    local initial, ids=seed(2)
    local app, sim, env, data, clock=setup(initial)
    local A=app.manual
    local function check()
        return A.targetCheck.check(A.store.get(ids[1]))
    end
    env.UnitIsPlayer=function() return false end
    data.rows={guild("Person1 North","g1",true)}
    check()
    data.allies={ally("Person2 North","g2",false)}
    A.batchRefresh.run()
    local prior=A.relogRefresh.reports[ids[1]].manual
    assert(prior.source=="Guild" and prior.online==true)
    clock.time=101
    data.rows={}
    check()
    assert(A.relogRefresh.reports[ids[1]].manual==prior and row(app,ids[1]).presenceReport.online)
    data.rows={guild("Other North","other",true)}
    assert(check():find("no longer lists",1,true))
    assert(A.store.get(ids[1]).lastKnown.sources.guild.absentAt==101)
    assert(not row(app,ids[1]).presenceReport)
    assert(row(app,ids[2]).presenceReport.source=="Recent Allies")
    -- A batch match after the absence is fresh evidence, even while the hint is inactive.
    data.rows={guild("Person1 North","g1",false)}
    assert(A.relogRefresh.manual(function() return true end)==2)
    assert(row(app,ids[1]).presenceReport.online==false)
    data.rows={guild("Other North","other",true)}
    assert(check():find("no longer lists",1,true))
    assert(not row(app,ids[1]).presenceReport and sim.forbiddenCalls==0)
    -- The absence's own view rebuild can publish a newer batch match for the same Friend.
    clock.time=102
    data.rows={guild("Person1 North","g1",true)}
    check()
    A.relogRefresh.manual(function() return true end)
    data.rows={guild("Other North","other",true)}
    clock.time=103
    local apply, reentered, sawRetired=A.relogRefresh.apply,false,false
    A.relogRefresh.apply=function(item, raw, context)
        if not reentered and item.id==ids[1] and raw.lastKnown.sources.guild.absentAt then
            reentered=true
            sawRetired=not item.presenceReport and not A.relogRefresh.reports[item.id].manual
            data.rows={guild("Person1 North","g1",false)}
            A.relogRefresh.manual(function() return true end)
        end
        apply(item,raw,context)
    end
    assert(check():find("no longer lists",1,true))
    assert(reentered and sawRetired and row(app,ids[1]).presenceReport.online==false)
    assert(sim.forbiddenCalls==0)
end
-- Permanent deletion releases every session source before rebuilding the surviving records.
do
    local initial, ids=seed(2)
    local app, sim, env, data, clock=setup(initial)
    local A=app.manual
    local check=A.targetCheck
    local id,other=ids[1],ids[2]
    env.UnitIsPlayer=function() return false end
    data.rows={guild("Person1 North","g1",true),guild("Person2 North","g2",false)}
    for _,key in ipairs(ids) do check.check(A.store.get(key)) end
    A.batchRefresh.run()
    data.rows={}
    env.C_RecentAllies.GetRecentAllyByFullName=function() return ally("Person1 North","g1",false) end
    check.check(A.store.get(id))
    data.units.target={name="Person1 North",guid="g1",online=true}
    env.UnitIsPlayer=function() return true end
    env.date=function() return "2026-11-18 12:30" end
    check.check(A.store.get(id))
    local maps={check.observations,check.cached,check.roster,check.latest,check.attempts,A.relogRefresh.reports}
    local stale=A.store.get(id); stale.fullName="Different North"
    assert(not A.delete(stale))
    for _,map in ipairs(maps) do assert(map[id]) end
    assert(A.save(A.store.get(id),"blacklist","Person1 North","",nil,{"other"},true))
    for _,map in ipairs(maps) do assert(map[id]) end
    assert(A.move(A.store.get(id)))
    local apply=check.apply
    local cleared
    check.apply=function(item,at)
        cleared=true
        for _,map in ipairs(maps) do if map[id] then cleared=false end end
        return apply(item,at)
    end
    assert(A.delete(A.store.get(id)) and cleared)
    assert(A.relogRefresh.reports[other].manual and check.attempts[other] and check.roster[other])
    -- Delete during a direct observation's rebuild. The returning scan cannot restore the ID.
    local during=false
    check.apply=function(item,at)
        if not during then
            during=true
            assert(A.delete(A.store.get(other)))
        end
        return apply(item,at)
    end
    clock.time=101
    data.units.target={name="Person2 North",guid="g2",online=true}
    check.check(A.store.get(other))
    assert(during and #A.records==0)
    for _,map in ipairs(maps) do assert(next(map)==nil) end
    assert(sim.forbiddenCalls==0)
end
-- A later empty snapshot retains the earlier report.
local preserve,pi=seed(1); local b,bs,be,bt,bc=setup(preserve)
bt.allies={ally("Person1 North","g1",true)}; b.manual.batchRefresh.run()
assert(row(b,pi[1]).presenceReport.online==true)
bc.time=131; bt.allies={}; b.manual.batchRefresh.run()
assert(row(b,pi[1]).presenceReport.online==true and bs.forbiddenCalls==0)
-- An unavailable clock or combat rejects the batch before any native snapshot.
local guards=seed(1); local g,gs,ge,gt=setup(guards)
ge.GetServerTime=function() error("unavailable") end
g.manual.batchRefresh.run(); assert(gt.group==0 and gt.guild==0 and gt.recent==0)
local _,missing=status(g); assert(missing==nil)
ge.GetServerTime=function() return 100 end; ge.InCombatLockdown=function() return true end
g.manual.batchRefresh.run(); assert(gt.group==0 and gt.guild==0 and gt.recent==0)
assert(not ge.WhowhoPreviewDB.refreshReadyAt and gs.forbiddenCalls==0)
-- Scaling is bounded by snapshots, rather than one lookup per saved Friend.
local large,li=seed(100); local m,ms,me,mt=setup(large)
for i=1,100 do mt.rows[i]=guild("Person"..i.." North","g"..i,true); mt.allies[i]=ally("Person"..i.." North","g"..i,false) end
m.manual.batchRefresh.run(); assert(mt.group>=1 and mt.group<=3 and mt.guild==1 and mt.recent==1 and mt.members<=200 and ms.forbiddenCalls==0)
local _,_,many=status(m); assert(many=="Roster status found for 100 of 100 Friends.")
print("RESULT manual-refresh simulated passed; no client capability established")
