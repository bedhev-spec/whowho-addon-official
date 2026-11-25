-- Simulated manual TOC only; this does not establish native client capability.
local root=arg[1] or "."
local H=dofile(root.."/tests/addon/harness.lua")
local config={region=3,time=100}; local p,s,e=H.fresh(root,{automaticTarget=false},nil,config)
e.issecrettable=function() return false end
local target,reads=nil,0
e.InCombatLockdown=function() return false end
e.UnitExists=function() reads=reads+1; return target~=nil end
e.UnitIsPlayer=function() return true end
e.C_Secrets={ShouldUnitIdentityBeSecret=function() return false end}
e.GetUnitName=function() return target.name end
e.UnitGUID=function() return target.guid end
e.UnitClass=function() return "Mage",target.class end
e.UnitLevel=function() return target.level end
e.date=function() return "2026-11-18 12:30" end
s:event("ADDON_LOADED","WhoWho"); p.Toggle(); local S,A=p.Shell,p.manual
s:event("PLAYER_TARGET_CHANGED"); assert(reads==0)
local function add(name)
    S.addButton:Click(); local f=S.editor.controls; f.formName:SetText(name); f.formSave:Click()
end
target={name="Ari North",guid="A",class="MAGE",level=42}
add("Ari North"); local one=S.selected; assert(reads>0 and one.fullName=="Ari North" and one.class=="MAGE" and one.level==42)
assert(S.detail.current:GetText()=="Unknown" and (S.detail.observation:GetText()==(S.selected.observed and p.FormatDate(S.selected.observed) or p.L("No observation"))))
local db=e.WhowhoAddressBookDB; assert(db.regions[3][one.id].guid==nil and db.regions[3][one.id].class==nil)
local initialReads=reads; target={name="Ari North",guid="A",class="MAGE",level=43}; add("Ari South")
local two=S.selected; assert(reads>initialReads and two.fullName=="Ari South" and not two.presence)
assert(A.targetCheck.observations[one.id].level==42)
initialReads=reads; target=nil; add("Empty North"); assert(reads>initialReads and not S.selected.presence)
local before=reads; S.addButton:Click(); local form=S.editor.controls
form.formName:SetText("Ari North"); form.formSave:Click(); assert(reads==before); form.formCancel:Click()
S.addButton:Click(); form.formName:SetText("Incomplete"); form.formSave:Click(); assert(reads==before); form.formCancel:Click()
S.Select(one); S.editButton:Click(); form.formNote:SetText("changed"); form.formSave:Click(); assert(reads==before)
S.nav.blacklist:Click(); S.addButton:Click(); assert(reads==before+1 and form.formName:GetText()=="")
local friendObservation=A.targetCheck.observations[one.id]
local checkedUnits, unitExists={}, e.UnitExists
e.UnitExists=function(token) checkedUnits[#checkedUnits+1]=token; return unitExists(token) end
before=reads; form.formName:SetText("Bad North"); form.reasonOptions.other:Click(); form.formSave:Click()
e.UnitExists=unitExists
assert(reads==before+2 and checkedUnits[1]=="target" and checkedUnits[2]=="mouseover")
assert(S.selected.fullName=="Bad North" and not S.selected.blacklistSavedClass and not S.selected.blacklistWhoClass)
assert(A.targetCheck.observations[one.id]==friendObservation)
S.nav.friend:Click(); S.Select(A.records[1]); local record
for _,item in ipairs(A.records) do if item.id==one.id then record=item end end
assert(record.presence=="Seen" and record.class=="MAGE" and record.level==42)
S.Select(record); target={name="Ari North",guid="A",class="MAGE",level=44}
local dbBefore=e.WhowhoAddressBookDB; S.checkStatus:Click(); assert(reads>before and S.selected.level==44 and e.WhowhoAddressBookDB~=dbBefore)
target.level=nil; target.class=nil; S.checkStatus:Click(); assert(S.selected.level==44 and S.selected.class=="MAGE")
target={name="Ari South",guid="B"}; S.checkStatus:Click(); assert(S.selected.level==44 and S.footer:GetText():find("Guild data unavailable",1,true))
target={name="Ari North",guid="X"}; S.checkStatus:Click(); assert(S.selected.level==44)
e.C_Secrets.ShouldUnitIdentityBeSecret=function() return s.secret end
local protectedReads=0
e.GetUnitName=function() protectedReads=protectedReads+1; error("protected identity read") end
S.checkStatus:Click(); assert(S.selected.level==44 and protectedReads==0)
e.C_Secrets.ShouldUnitIdentityBeSecret=function() return false end
e.GetUnitName=function() return target.name end
target={name="Ari North",guid="A",class="MAGE",level=45}
e.UnitLevel=function() target.guid="X"; return 45 end
S.checkStatus:Click(); assert(S.selected.level==44)
e.UnitLevel=function() return target.level end
e.InCombatLockdown=function() return true end; before=reads; S.checkStatus:Click()
assert(reads==before and S.selected.level==44 and S.detail.attempt:GetText()=="Checks paused during combat.")
e.InCombatLockdown=function() return s.secret end; S.checkStatus:Click()
assert(reads==before and S.detail.attempt:GetText()=="Combat status unavailable.")
e.InCombatLockdown=function() return false end
local stored=assert(A.store.add({fullName="Known North",region=3,identityState="resolved",membership="friend",guid="known",note=""},100))
A.refresh(); for _,item in ipairs(A.records) do if item.id==stored.id then S.Select(item) end end
target={name="Known North",guid="other",class="MAGE",level=30}; S.checkStatus:Click(); assert(not S.selected.presence)
target={name="Known North",guid="A",class="MAGE",level=30}; S.checkStatus:Click(); assert(not S.selected.presence)
target={name="Race North",guid="race-a",class="MAGE",level=20}
e.GetUnitName=function()
    local name=target.name
    target={name="Other North",guid="race-b",class="PRIEST",level=60}
    return name
end
add("Race North"); assert(S.selected.fullName=="Race North" and not S.selected.presence and not S.selected.class and not S.selected.level)
assert(e.WhowhoAddressBookDB.regions[3][S.selected.id].fullName=="Race North")
e.GetUnitName=function() return target.name end
target={name="Ari North",guid="A",class="MAGE",level=60}
for _,item in ipairs(A.records) do if item.id==one.id then S.Select(item) end end
local oldDB=e.WhowhoAddressBookDB; local oldObservation=A.targetCheck.observations[one.id]; local guidReads=0
e.UnitGUID=function() guidReads=guidReads+1; if guidReads==3 then return "changed" end; return target.guid end
S.checkStatus:Click()
assert(e.WhowhoAddressBookDB==oldDB and A.targetCheck.observations[one.id]==oldObservation)
local npcIdentityReads=0
e.UnitIsPlayer=function() return false end
e.UnitGUID=function() npcIdentityReads=npcIdentityReads+1; return "npc-guid" end
e.GetUnitName=function() npcIdentityReads=npcIdentityReads+1; return "Training Dummy" end
S.checkStatus:Click()
assert(S.detail.attempt:GetText()=="Non-player target skipped." and S.selected.level==44)
assert(npcIdentityReads==0 and e.WhowhoAddressBookDB==oldDB and A.targetCheck.observations[one.id]==oldObservation)

-- The shared guard rejects unsafe namespaces before looking up the predicate.
local unit=A.unitReader
local tableReads, predicateReads=0,0
local function predicate() predicateReads=predicateReads+1; error("unreadable predicate called") end
local secrets=setmetatable({}, {__index=function()
    tableReads=tableReads+1
    return predicate
end})
local valueChecker, tableChecker=e.issecretvalue,e.issecrettable
e.C_Secrets=secrets
e.issecretvalue=nil
assert(not unit.identitySafe("target"))
e.issecretvalue=function() error("value checker unavailable") end
assert(not unit.identitySafe("target"))
e.issecretvalue=valueChecker
e.issecrettable=nil
assert(not unit.identitySafe("target"))
e.issecrettable=function() error("table checker unavailable") end
assert(not unit.identitySafe("target"))
e.issecrettable=function(value) return value==secrets end
assert(not unit.identitySafe("target") and tableReads==0 and predicateReads==0)
e.issecrettable=tableChecker
e.issecretvalue=function(value) return value==predicate or valueChecker(value) end
assert(not unit.identitySafe("target") and tableReads==1 and predicateReads==0)
e.issecretvalue=valueChecker
e.C_Secrets={ShouldUnitIdentityBeSecret=function(token) assert(token=="target"); return nil end}
assert(not unit.identitySafe("target"))
e.C_Secrets.ShouldUnitIdentityBeSecret=function(token) assert(token=="target"); return false end
assert(unit.identitySafe("target")==true)

target={class=nil,level=42}
local class, level=unit.metadata("target")
assert(class==nil and level==42)
target.class="MAGE"
class, level=unit.metadata("target")
assert(class=="MAGE" and level==42 and s.forbiddenCalls==0)
print("RESULT target-check simulated passed; no client capability established")
