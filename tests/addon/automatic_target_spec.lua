-- Simulated event-driven target scans; this does not establish native capability.
local root=arg[1] or "."; local H=dofile(root.."/tests/addon/harness.lua")
local config={region=3,time=100}; local p,s,e=H.fresh(root,{automaticTarget=false},nil,config)
local target,reads,clock,fallbackCalls=nil,0,0,0
e.issecrettable=function() return false end
e.InCombatLockdown=function() return false end
e.C_Secrets={ShouldUnitIdentityBeSecret=function() return false end}
e.GetTime=function() return clock end
e.IsInRaid=function() fallbackCalls=fallbackCalls+1; return false end
e.C_Club={GetGuildClubId=function() fallbackCalls=fallbackCalls+1 end}
e.C_RecentAllies={IsSystemSupported=function() fallbackCalls=fallbackCalls+1; return false end}
e.UnitExists=function(unit) assert(unit=="target"); reads=reads+1; return target~=nil end
e.UnitIsPlayer=function() return true end
e.GetUnitName=function() return target.name end
e.UnitGUID=function() return target.guid end
e.UnitClass=function() return "Mage",target.class end
e.UnitLevel=function() return target.level end
e.date=function() return "2026-11-18 12:30" end
s:event("ADDON_LOADED","WhoWho")
local A=p.manual; local check=A.targetCheck
local function save(name,membership)
    return assert(A.store.add({fullName=name,region=3,identityState="resolved",membership=membership or "friend",note="",reasonIds=membership=="blacklist" and {"other"} or nil},100))
end
local a=save("Ari North"); local b=save("Bea North"); local bad=save("Bad North","blacklist")
local c=save("Cia North"); local d=save("Dia North"); local f=save("Fia North")
A.refresh()
local function set(name,guid,level,class) target={name=name,guid=guid,level=level,class=class} end
local function event() return check.onTargetChanged() end
-- Disabled events do no unit reads. Exact Friends alone may publish.
set("Ari North","a",42,"MAGE"); assert(not event() and reads==0)
assert(A.setAutomaticTarget(true)); assert(event() and check.observations[a.id].level==42)
clock=1; set("Bad North","bad",40,"MAGE"); assert(not event() and not check.observations[bad.id])
clock=2; set("Other North","other",40,"MAGE"); assert(not event())
clock=3; set("Ari South","a",40,"MAGE"); assert(not event())
-- A new current token cannot publish stale data from an earlier token.
clock=6; set("Bea North","b",51,"MAGE")
e.UnitLevel=function() set("Cia North","c",52,"MAGE"); return 51 end
assert(not event() and not check.observations[b.id] and not check.observations[c.id])
e.UnitLevel=function() return target.level end
clock=7; assert(event() and check.observations[c.id].level==52)
-- Optional unreadable metadata must not erase earlier validated fields.
clock=12; set("Ari North","a",nil,nil); assert(event())
assert(check.observations[a.id].level==42 and check.observations[a.id].class=="MAGE")
-- A cleared token does not invoke any fallback or schedule deferred work.
clock=13; target=nil; assert(not event())
local previous=reads; clock=20; assert(reads==previous)
-- Four attempts in a rolling second, including misses; excess work is dropped.
set("Ari North","a",42,"MAGE"); assert(event())
clock=20.1; set("Bea North","b",43,"MAGE"); assert(event())
clock=20.2; set("Dia North","d",44,"MAGE"); assert(event())
clock=20.3; set("Fia North","f",45,"MAGE"); assert(event())
clock=20.4; set("Cia North","c",46,"MAGE"); previous=reads; assert(not event() and reads==previous)
clock=21.01; assert(event() and reads>previous)
-- Per-character repeats are dropped for five seconds, but other Friends proceed.
clock=22; set("Ari North","a",50,"MAGE"); previous=reads; assert(not event())
local getRecord, repeatReads=A.store.get,0
A.store.get=function(id) repeatReads=repeatReads+1; return getRecord(id) end
clock=22.1; assert(not event() and repeatReads==0)
A.store.get=getRecord
clock=25; assert(event() and check.observations[a.id].level==50)
-- Reusing the same full name with a different GUID invalidates the snapshot.
clock=30; set("Bea North","b",60,"MAGE")
local priorObservation=check.observations[b.id]; local priorDB=e.WhowhoAddressBookDB
e.UnitLevel=function() target.guid="replacement"; return 60 end
assert(not event() and check.observations[b.id]==priorObservation and e.WhowhoAddressBookDB==priorDB)
e.UnitLevel=function() return target.level end
-- A nested target event invalidates the in-progress attempt without replay.
clock=36; set("Bea North","b",61,"MAGE"); local nested
e.UnitLevel=function() nested=event(); return 61 end
priorObservation=check.observations[b.id]; priorDB=e.WhowhoAddressBookDB
assert(not event() and nested==false and check.observations[b.id]==priorObservation and e.WhowhoAddressBookDB==priorDB)
e.UnitLevel=function() return target.level end
-- Disabling and re-enabling during a read also invalidates its ownership.
clock=42; set("Bea North","b",62,"MAGE")
e.UnitLevel=function() assert(A.setAutomaticTarget(false)); assert(A.setAutomaticTarget(true)); return 62 end
priorObservation=check.observations[b.id]; priorDB=e.WhowhoAddressBookDB
assert(not event() and check.observations[b.id]==priorObservation and e.WhowhoAddressBookDB==priorDB)
e.UnitLevel=function() return target.level end
-- A replacement on the final publication validation must not commit either.
clock=48; set("Bea North","b",63,"MAGE"); local guidReads=0
e.UnitGUID=function()
    guidReads=guidReads+1
    if guidReads==3 then target.guid="replacement" end
    return target.guid
end
priorObservation=check.observations[b.id]; priorDB=e.WhowhoAddressBookDB
assert(not event() and guidReads==3 and check.observations[b.id]==priorObservation and e.WhowhoAddressBookDB==priorDB)
e.UnitGUID=function() return target.guid end
-- Combat can start inside the last identity read while the token still matches.
do
    clock=54; set("Bea North","b",64,"MAGE")
    local combat, nameReads = false, 0
    e.InCombatLockdown = function() return combat end
    e.GetUnitName = function()
        nameReads = nameReads + 1
        if nameReads == 3 then combat = true end
        return target.name
    end
    local published = event()
    assert(nameReads==3 and combat, "the final automatic identity read must enter combat")
    assert(not published and check.observations[b.id]==priorObservation and e.WhowhoAddressBookDB==priorDB,
        "an automatic result invalidated by combat must preserve prior session and durable evidence")
    e.InCombatLockdown = function() return false end
    e.GetUnitName = function() return target.name end
end
assert(s.forbiddenCalls==0 and fallbackCalls==0)
-- Runtime registration follows the opt-in setting and survives reload.
local friendDB=A.store.export()
friendDB.regions[3][bad.id]=nil
local p2,s2,e2=H.fresh(root,{automaticTarget=false},nil,{region=3,time=100,db=friendDB})
local eventReads=0
local function unitStubs(env)
    env.issecrettable=function() return false end
    env.InCombatLockdown=function() return false end
    env.C_Secrets={ShouldUnitIdentityBeSecret=function() return false end}
    env.GetTime=function() return 100 end
    env.UnitExists=function(unit) assert(unit=="target"); eventReads=eventReads+1; return true end
    env.UnitIsPlayer=function() return true end
    env.GetUnitName=function() return "Ari North" end
    env.UnitGUID=function() return "a" end
    env.UnitClass=function() return "Mage","MAGE" end
    env.UnitLevel=function() return 42 end
    env.date=function() return "2026-11-18 12:30" end
end
unitStubs(e2); s2:event("ADDON_LOADED","WhoWho"); p2.Toggle()
assert(not p2.manual.automaticTargetEnabled())
s2:event("PLAYER_TARGET_CHANGED"); assert(eventReads==0)
p2.Shell.nav.settings:Click()
p2.Shell.settingsTabs.friends:Click()
local toggle=p2.Shell.automaticTarget
assert(toggle:IsVisible() and toggle:GetChecked()==false and toggle.state:GetText()=="Off")
e2.UIParent:SetSize(484,800); p2.SetScale(1)
local _,rowLeft,rowTop=toggle:GetPoint()
assert(rowLeft+toggle:GetWidth()<p2.Shell.settings:GetWidth() and -rowTop+toggle:GetHeight()<p2.Shell.settings:GetHeight())
e2.UIParent:SetSize(1360,832); p2.SetScale(1)
toggle:Click()
assert(toggle:GetChecked() and toggle.state:GetText()=="On" and e2.WhowhoPreviewDB.automaticTarget==true)
p2.Shell.nav.friend:Click()
s2:event("PLAYER_TARGET_CHANGED"); assert(eventReads>0 and p2.manual.targetCheck.observations[a.id])
local visible
for _,row in ipairs(p2.Shell.rows) do if row.record and row.record.id==a.id then visible=row end end
assert(visible and visible.record.presence=="Seen" and visible.record.level==42)
do
    local shell,manual=p2.Shell,p2.manual
    local stable=manual.records
    local apply,paint=manual.targetCheck.apply,shell.Refresh
    local applications,paints=0,0
    manual.targetCheck.apply=function(item,at) applications=applications+1; return apply(item,at) end
    shell.Refresh=function() paints=paints+1; paint() end
    shell.window:Hide()
    -- Durable change, unchanged metadata, and a session-only observation each rebuild once.
    e2.UnitLevel=function() return 53 end
    for _,now in ipairs({106,112,118}) do
        e2.GetTime=function() return now end
        if now==118 then e2.UnitLevel=function() end; e2.UnitClass=function() end end
        applications=0
        s2:event("PLAYER_TARGET_CHANGED")
        assert(manual.records==stable and applications==#stable and paints==0)
    end
    assert(visible.record.level==42)
    shell.Open()
    assert(paints==1 and visible.record.level==53 and visible.record.presence=="Seen")
    manual.targetCheck.apply,shell.Refresh=apply,paint
end
local firstReads=eventReads
local p3,s3,e3=H.fresh(root,e2.WhowhoPreviewDB,nil,{region=3,time=100,db=e2.WhowhoAddressBookDB})
unitStubs(e3); s3:event("ADDON_LOADED","WhoWho"); assert(p3.manual.automaticTargetEnabled())
for _,record in ipairs(p3.manual.records) do
    if record.id==a.id then assert(record.presence==nil and record.level==53) end
end
s3:event("PLAYER_TARGET_CHANGED"); assert(eventReads>firstReads and p3.manual.targetCheck.observations[a.id]); local secondReads=eventReads
p3.Toggle(); p3.Shell.nav.settings:Click(); p3.Shell.settingsTabs.friends:Click()
local restored=p3.Shell.automaticTarget
assert(restored:GetChecked() and restored.state:GetText()=="On")
restored:Click()
assert(not p3.manual.automaticTargetEnabled() and not restored:GetChecked() and restored.state:GetText()=="Off")
s3:event("PLAYER_TARGET_CHANGED"); assert(eventReads==secondReads)
local p4,s4,e4=H.fresh(root,e3.WhowhoPreviewDB,nil,{region=3,time=100,db=e3.WhowhoAddressBookDB})
unitStubs(e4); s4:event("ADDON_LOADED","WhoWho"); s4:event("PLAYER_TARGET_CHANGED"); assert(eventReads==secondReads)
assert(s2.forbiddenCalls==0 and s3.forbiddenCalls==0 and s4.forbiddenCalls==0)
local p5,s5=H.fresh(root,{automaticTarget=false},nil,{region=3,time=100,db=A.store.export()})
local loader
for _,frame in ipairs(s5.nodes) do if frame.events.ADDON_LOADED then loader=frame end end
s5:event("ADDON_LOADED","WhoWho")
assert(loader); loader.RegisterEvent=function() return false end
p5.Toggle(); p5.Shell.nav.settings:Click(); p5.Shell.settingsTabs.friends:Click()
p5.Shell.automaticTarget:Click()
assert(not p5.manual.automaticTargetEnabled() and not p5.db.automaticTarget)
assert(not p5.Shell.automaticTarget:GetChecked() and p5.Shell.automaticTarget.state:GetText()=="Off")
print("RESULT automatic-target simulated passed; no client capability established")
