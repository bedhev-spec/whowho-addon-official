-- Deterministic simulated mouseover scans; no native capability is established.
local root=arg[1] or "."; local H=dofile(root.."/tests/addon/harness.lua")
local p,s,e=H.fresh(root,{automaticTarget=false,automaticMouseover=false},nil,{region=3,time=100})
-- Isolate Friends scheduling. The independent banner uses the real binding in blacklist_banner_spec.lua.
p.BlacklistBanner.installSightings=function() end
local clock,units,reads,fallback=0,{},0,0
local timers={}
e.C_Timer={NewTimer=function(delay,fn)
    assert(delay==0.25)
    local t={due=clock+delay,fn=fn,cancelled=false}
    function t:Cancel() self.cancelled=true end
    timers[#timers+1]=t; return t
end}
local function advance(to)
    clock=to
    for _,t in ipairs(timers) do
        if not t.fired and not t.cancelled and t.due<=clock then t.fired=true; t.fn() end
    end
end
local function late(t) t.fired=true; t.fn() end
local function active()
    local n=0; for _,t in ipairs(timers) do if not t.fired and not t.cancelled then n=n+1 end end; return n
end
e.issecrettable=function() return false end
e.InCombatLockdown=function() return false end
e.C_Secrets={ShouldUnitIdentityBeSecret=function() return false end}
e.GetTime=function() return clock end
e.IsInRaid=function() fallback=fallback+1; return false end
e.C_Club={GetGuildClubId=function() fallback=fallback+1 end}
e.C_RecentAllies={IsSystemSupported=function() fallback=fallback+1; return false end}
e.UnitExists=function(unit) assert(unit=="mouseover" or unit=="target"); reads=reads+1; return units[unit]~=nil end
e.UnitIsPlayer=function(unit) return units[unit].player~=false end
e.GetUnitName=function(unit) return units[unit].name end
e.UnitGUID=function(unit) return units[unit].guid end
e.UnitClass=function(unit) return "Mage",units[unit].class end
e.UnitLevel=function(unit) return units[unit].level end
e.date=function() return "2026-11-18 12:30" end
s:event("ADDON_LOADED","WhoWho")
local A=p.manual; local check=A.targetCheck
local function save(name,membership)
    return assert(A.store.add({fullName=name,region=3,identityState="resolved",membership=membership or "friend",note="kept",reasonIds=membership=="blacklist" and {"other"} or nil},100))
end
local a=save("Ari North"); local b=save("Bea North"); local c=save("Cia North"); local d=save("Dia North"); local f=save("Fia North"); local bad=save("Bad North","blacklist")
A.refresh()
local function set(unit,name,guid,level) units[unit]=name and {name=name,guid=guid,level=level or 42,class="MAGE"} or nil end
local function hover() s:event("UPDATE_MOUSEOVER_UNIT") end
local function fireAt(t) advance(t); assert(active()==0) end
-- Defaults off, no reads or timers, and independent controls.
set("mouseover","Ari North","a"); hover(); assert(reads==0 and #timers==0)
assert(not A.automaticMouseoverEnabled() and not A.automaticTargetEnabled())
p.Toggle(); p.Shell.nav.settings:Click(); p.Shell.settingsTabs.friends:Click()
local toggle=p.Shell.automaticMouseover
assert(toggle:IsVisible() and not toggle:GetChecked() and toggle.state:GetText()=="Off")
e.UIParent:SetSize(484,800); p.SetScale(1)
local targetRow=p.Shell.automaticTarget
local _,targetX,targetY=targetRow:GetPoint(); local _,hoverX,hoverY=toggle:GetPoint()
assert(targetX==hoverX and targetRow:GetWidth()==toggle:GetWidth())
assert(-hoverY >= -targetY+targetRow:GetHeight() and hoverX+toggle:GetWidth()<p.Shell.settings:GetWidth())
e.UIParent:SetSize(1360,832); p.SetScale(1)
toggle:Click(); assert(toggle:GetChecked() and toggle.state:GetText()=="On" and A.automaticMouseoverEnabled())
assert(not A.automaticTargetEnabled() and e.WhowhoPreviewDB.automaticMouseover==true)
local apply,applied=check.apply,0
check.apply=function(item,at) applied=applied+1; return apply(item,at) end
hover(); assert(active()==1 and reads==0); advance(0.249); assert(reads==0); fireAt(0.25)
assert(applied==#A.records)
check.apply=apply
assert(check.observations[a.id] and check.observations[a.id].level==42)
local record
for _,r in ipairs(A.records) do if r.id==a.id then record=r end end
assert(record and record.source=="Mouseover" and record.note=="kept")
-- Replacing or clearing a pending hover cancels its owner; forced late callbacks are inert.
clock=6; set("mouseover","Bea North","b"); hover(); local old=timers[#timers]
clock=6.1; set("mouseover","Cia North","c"); hover(); assert(old.cancelled and active()==1)
late(old); assert(not check.observations[b.id]); fireAt(6.35); assert(check.observations[c.id])
clock=12; set("mouseover","Bea North","b"); hover(); old=timers[#timers]
clock=12.1; set("mouseover",nil); hover(); late(old); advance(13); assert(not check.observations[b.id])
clock=18; set("mouseover","Bea North","b"); hover(); old=timers[#timers]
toggle:Click(); assert(old.cancelled and not A.automaticMouseoverEnabled()); late(old); assert(not check.observations[b.id])
toggle:Click(); clock=24; set("mouseover","Bea North","b"); hover(); old=timers[#timers]; advance(30); assert(not check.observations[b.id])
-- Exact Friend only, protected context and unreadable identity are rejected.
clock=36; set("mouseover","Bad North","bad"); hover(); fireAt(36.25); assert(not check.observations[bad.id])
clock=42; set("mouseover","Ari South","other"); hover(); fireAt(42.25)
clock=48; set("mouseover","Bea North","b"); e.InCombatLockdown=function() return true end; hover(); fireAt(48.25); assert(not check.observations[b.id]); e.InCombatLockdown=function() return false end
clock=54; e.GetUnitName=function() return s.secret end; hover(); fireAt(54.25); assert(not check.observations[b.id]); e.GetUnitName=function(unit) return units[unit].name end
clock=60; units.mouseover.player=false; hover(); fireAt(60.25); assert(not check.observations[b.id]); units.mouseover.player=true
-- A pending timer cannot publish after the identity changes during metadata reading.
clock=66; hover(); e.UnitLevel=function(unit) units[unit].guid="replacement"; return 42 end; fireAt(66.25); assert(not check.observations[b.id]); e.UnitLevel=function(unit) return units[unit].level end
-- Target and mouseover share the rolling snapshot budget and Friend repeat limit.
assert(A.setAutomaticTarget(true)); clock=72; set("target","Ari North","a"); assert(check.onTargetChanged())
clock=72.1; set("target","Bea North","b"); assert(check.onTargetChanged())
clock=72.2; set("target","Cia North","c"); assert(check.onTargetChanged())
clock=72.3; set("target","Dia North","d"); assert(check.onTargetChanged())
clock=72.31; set("mouseover","Fia North","f"); hover(); local before=reads; fireAt(72.56); assert(reads==before and not check.observations[f.id])
clock=73; set("mouseover","Ari North","a",55); hover(); fireAt(73.25); assert(check.observations[a.id].level==42)
clock=77; hover(); fireAt(77.25); assert(check.observations[a.id].level==55)
-- A later automatic observation does not turn the prior manual attempt into a new check.
assert(fallback==0 and s.forbiddenCalls==0)
clock=83; set("target","Ari North","a",61); check.check(assert(A.store.get(a.id)))
local attempt=assert(check.attempts[a.id]); clock=89; set("mouseover","Ari North","a",62)
hover(); fireAt(89.25); assert(check.attempts[a.id]==attempt and check.observations[a.id].level==62)
-- Timer creation failures and malformed or synchronous handles cannot publish.
clock=95; set("mouseover","Bea North","b")
local timerAPI=e.C_Timer; local callbacks={}; local prior=check.observations[b.id]
e.C_Timer={NewTimer=function(_,fn) callbacks[#callbacks+1]=fn; error("timer unavailable") end}
hover(); callbacks[#callbacks](); assert(check.observations[b.id]==prior)
e.C_Timer={NewTimer=function(_,fn) callbacks[#callbacks+1]=fn; return {} end}
hover(); callbacks[#callbacks](); assert(check.observations[b.id]==prior)
e.C_Timer={NewTimer=function(_,fn) fn(); return {Cancel=function() end} end}
hover(); assert(check.observations[b.id]==prior); e.C_Timer=timerAPI
-- A nested event during scheduling supersedes its outer event and owns the only timer.
clock=101; set("mouseover","Bea North","b"); local nested=false
e.GetTime=function()
    if not nested then nested=true; set("mouseover","Fia North","f",64); hover() end
    return clock
end
hover(); e.GetTime=function() return clock end
assert(nested and active()==1); fireAt(101.25)
assert(check.observations[b.id]==prior and check.observations[f.id] and check.observations[f.id].level==64)
-- The owned hover callback also rejects combat started by its last identity read.
do
    clock=107; set("mouseover","Bea North","b",65)
    local combat, nameReads = false, 0
    local db = e.WhowhoAddressBookDB
    e.InCombatLockdown = function() return combat end
    e.GetUnitName = function(unit)
        nameReads = nameReads + 1
        if nameReads == 3 then combat = true end
        return units[unit].name
    end
    hover(); fireAt(107.25)
    assert(nameReads==3 and combat and check.observations[b.id]==prior and e.WhowhoAddressBookDB==db)
    e.InCombatLockdown = function() return false end
    e.GetUnitName = function(unit) return units[unit].name end
end
-- Preference survives reload; disabling mouseover does not alter target.
local p2,s2,e2=H.fresh(root,e.WhowhoPreviewDB,nil,{region=3,time=100,db=e.WhowhoAddressBookDB})
e2.C_Timer=e.C_Timer; s2:event("ADDON_LOADED","WhoWho")
assert(p2.manual.automaticMouseoverEnabled() and p2.manual.automaticTargetEnabled())
p2.Toggle(); p2.Shell.nav.settings:Click(); p2.Shell.settingsTabs.friends:Click(); local restored=p2.Shell.automaticMouseover
assert(restored:GetChecked() and restored.state:GetText()=="On"); restored:Click()
assert(not p2.manual.automaticMouseoverEnabled() and p2.manual.automaticTargetEnabled())
local p3,s3,e3=H.fresh(root,{automaticMouseover=false},nil,{region=3,time=100,db=A.store.export()})
e3.C_Timer=timerAPI
local loader; for _,frame in ipairs(s3.nodes) do if frame.events.ADDON_LOADED then loader=frame end end
s3:event("ADDON_LOADED","WhoWho"); assert(loader); loader.RegisterEvent=function() return false end
p3.Toggle(); p3.Shell.nav.settings:Click(); p3.Shell.settingsTabs.friends:Click(); p3.Shell.automaticMouseover:Click()
assert(not p3.manual.automaticMouseoverEnabled() and not p3.db.automaticMouseover and not p3.Shell.automaticMouseover:GetChecked())
print("RESULT automatic-mouseover simulated passed; no client capability established")
