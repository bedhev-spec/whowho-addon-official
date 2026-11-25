-- Simulated manual TOC only; never a native capability claim.
local root=arg[1] or "."; local H=dofile(root.."/tests/addon/harness.lua")
local config={region=3,time=100}; local p,s,e=H.fresh(root,{automaticTarget=false},nil,config)
local calls=0; local target=nil; local online=true; local guid="guid-a"; local returnedName="Ari North"
e.issecrettable=function() return false end
e.InCombatLockdown=function() return false end
e.UnitExists=function() return target~=nil end
e.UnitIsPlayer=function() return true end
e.C_Secrets={ShouldUnitIdentityBeSecret=function() return false end}
e.GetUnitName=function() return target.name end; e.UnitGUID=function() return target.guid end
e.UnitClass=function() return "Mage","MAGE" end; e.UnitLevel=function() return 55 end
e.date=function() return "2026-11-18 12:30" end
e.C_RecentAllies={IsSystemSupported=function() return true end,IsSystemEnabled=function() return true end,
    IsRecentAllyDataReady=function() return true end, GetRecentAllyByFullName=function(name)
        calls=calls+1; return {characterData={fullName=returnedName,guid=guid,level=42,classID=8},stateData={isOnline=online}}
    end, TryRequestRecentAlliesData=function() error("request forbidden") end}
e.C_CreatureInfo={GetClassInfo=function(id) assert(id==8); return {classFile="MAGE"} end}
local friendsLoader
for _,frame in ipairs(s.nodes) do if frame.events.ADDON_LOADED then friendsLoader=frame end end
s:event("ADDON_LOADED","WhoWho"); p.Toggle(); local A,S=p.manual,p.Shell
assert(not friendsLoader.events.PLAYER_TARGET_CHANGED)
s:event("PLAYER_TARGET_CHANGED"); assert(calls==0)
S.addButton:Click(); local form=S.editor.controls; form.formName:SetText("Ari North"); form.formSave:Click()
local id=S.selected.id; assert(calls==2 and S.selected.presenceReport and S.selected.presenceReport.online==true)
assert(e.WhowhoAddressBookDB.regions[3][id].lastKnown.sources.recentAlliesAt==100)
assert(S.rows[1].status:GetText()=="Online" and S.detail.current:GetText()=="Online" and (S.detail.observation:GetText()==(S.selected.observed and p.FormatDate(S.selected.observed) or p.L("No observation"))))
assert(S.selected.observed==nil and S.selected.class=="MAGE" and S.selected.level==42)
assert(e.WhowhoAddressBookDB.regions[3][id].guid==nil and e.WhowhoAddressBookDB.regions[3][id].class==nil)
local savedDB=e.WhowhoAddressBookDB
local p2,s2,e2=H.fresh(root,nil,nil,{region=3,time=101,db=savedDB})
s2:event("ADDON_LOADED","WhoWho"); p2.Toggle()
assert(s2.forbiddenCalls==0 and #p2.manual.records==1)
local restored=p2.manual.records[1]
assert(restored.id==id and restored.class=="MAGE" and restored.level==42 and not restored.presence and not restored.presenceReport)
assert(p2.Shell.rows[1].meta:GetText()=="Mage · 42" and p2.Shell.rows[1].status:GetText()=="Unknown")
p2.Shell.rows[1]:Click(); assert(p2.Shell.detail.current:GetText()=="Unknown")
assert(savedDB.regions[3][id].lastKnown.class.source=="Recent Allies" and savedDB.regions[3][id].lastKnown.level.at==100)
assert(not p2.manual.store.find(3,"Ari North","wrong"))
assert(not p2.manual.store.find(3,"Another North","guid-a"))
local db=e.WhowhoAddressBookDB; online=false; S.checkStatus:Click()
assert(S.selected.presenceReport and S.selected.presenceReport.online==false and S.rows[1].status:GetText()=="Offline")
assert(S.detail.current:GetText()=="Offline" and (S.detail.observation:GetText()==(S.selected.observed and p.FormatDate(S.selected.observed) or p.L("No observation"))))
assert(e.WhowhoAddressBookDB==db and S.selected.observed==nil)
config.time=95
e.UnitClass=function() return "Priest","PRIEST" end
target={name="Ari North",guid="guid-a"}; S.checkStatus:Click(); assert(S.selected.presence=="Seen")
assert(S.selected.class=="PRIEST" and S.selected.level==55)
assert(S.detail.current:GetText()=="Unknown" and (S.detail.observation:GetText()==(S.selected.observed and p.FormatDate(S.selected.observed) or p.L("No observation"))))
local stamp=S.selected.observed; target=nil; online=true; S.checkStatus:Click()
assert(S.selected.presence=="Seen" and S.selected.observed==stamp and (S.detail.observation:GetText()==(S.selected.observed and p.FormatDate(S.selected.observed) or p.L("No observation"))))
assert(S.detail.current:GetText()=="Online")
local known=e.WhowhoAddressBookDB.regions[3][id].lastKnown
assert(known.class.source=="Target" and known.class.value=="PRIEST" and known.class.at==95 and known.level.source=="Target" and known.level.value==55)
local p3,s3=H.fresh(root,nil,nil,{region=3,time=102,db=e.WhowhoAddressBookDB})
s3:event("ADDON_LOADED","WhoWho"); p3.Toggle()
assert(p3.manual.records[1].class=="PRIEST" and p3.manual.records[1].level==55 and not p3.manual.records[1].presence)
local saved=S.selected; local snapshot=A.targetCheck.cached[id]
guid="wrong"; S.checkStatus:Click(); assert(A.targetCheck.cached[id]==snapshot)
guid="guid-a"; returnedName="Ari South"; S.checkStatus:Click(); assert(A.targetCheck.cached[id]==snapshot)
returnedName="Ari North"; config.region=4; local before=calls; S.checkStatus:Click(); assert(calls==before); config.region=3
e.C_RecentAllies.IsRecentAllyDataReady=function() return false end; S.checkStatus:Click(); assert(calls==before)
e.C_RecentAllies.IsRecentAllyDataReady=function() error("unavailable") end; S.checkStatus:Click(); assert(calls==before)
e.C_RecentAllies.IsRecentAllyDataReady=function() return true end
e.C_RecentAllies.IsSystemEnabled=nil; S.checkStatus:Click(); assert(calls==before)
e.C_RecentAllies.IsSystemEnabled=function() return true end
local flagged=setmetatable({}, {__index=function() error("secret table indexed") end})
e.issecrettable=function(v) return rawequal(v,flagged) end
e.C_RecentAllies.GetRecentAllyByFullName=function() calls=calls+1; return flagged end
S.checkStatus:Click(); assert(A.targetCheck.cached[id]==snapshot and S.selected.note==saved.note)
e.C_RecentAllies.GetRecentAllyByFullName=function() calls=calls+1; return {characterData=flagged} end
S.checkStatus:Click(); assert(A.targetCheck.cached[id]==snapshot)
e.issecrettable=nil; before=calls; S.checkStatus:Click(); assert(calls==before)
e.issecrettable=function() return false end
returnedName="Ari South"; guid="guid-b"; online=true
e.C_RecentAllies.GetRecentAllyByFullName=function() calls=calls+1; return {characterData={fullName=returnedName,guid=guid},stateData={isOnline=online}} end
target={name="Ari North",guid="guid-a"}
S.addButton:Click(); form.formName:SetText("Ari South"); form.formSave:Click()
assert(S.selected.fullName=="Ari South" and S.selected.presenceReport and S.selected.presenceReport.online==true)
local id2=S.selected.id; local seen2=A.targetCheck.cached[id2]
target=nil; guid="guid-a"; S.checkStatus:Click(); assert(A.targetCheck.cached[id2]==seen2)
guid="guid-b"; online=nil; S.checkStatus:Click(); assert(A.targetCheck.cached[id2]==seen2)
-- A ready exact identity is a historical hint even without a readable status or metadata.
e.C_RecentAllies.GetRecentAllyByFullName=function() return {characterData={fullName="Hint North",guid="hint"},stateData={}} end
S.addButton:Click(); form.formName:SetText("Hint North"); form.formSave:Click()
local hint=e.WhowhoAddressBookDB.regions[3][S.selected.id].lastKnown
assert(hint.guid=="hint" and hint.sources.recentAlliesAt==95 and not hint.class and not hint.level and not S.selected.presenceReport)
-- Final re-fetch must reject an identity that changes during the check.
local n=0
e.C_RecentAllies.GetRecentAllyByFullName=function()
 n=n+1; return {characterData={fullName="Race North",guid=n==1 and "race" or "changed"},stateData={}}
end
S.addButton:Click(); form.formName:SetText("Race North"); form.formSave:Click()
assert(not e.WhowhoAddressBookDB.regions[3][S.selected.id].lastKnown)
-- A final exact lookup can invalidate readiness without changing the returned identity.
do
    local ready, lookups = true, 0
    local readiness = e.C_RecentAllies.IsRecentAllyDataReady
    e.C_RecentAllies.IsRecentAllyDataReady = function() return ready end
    e.C_RecentAllies.GetRecentAllyByFullName = function()
        lookups = lookups + 1
        if lookups == 2 then ready = false end
        return {characterData={fullName="Race North",guid="race",level=42},stateData={isOnline=true}}
    end
    local before = e.WhowhoAddressBookDB
    S.checkStatus:Click()
    assert(lookups==2 and not ready, "the final lookup must invalidate readiness")
    assert(not S.selected.presenceReport and not A.targetCheck.cached[S.selected.id],
        "an unready Recent Allies result must not publish a session report")
    assert(e.WhowhoAddressBookDB==before, "an unready Recent Allies result must not write durable evidence")
    e.C_RecentAllies.IsRecentAllyDataReady = readiness
end
-- An unreadable clock still requires final identity validation for session status.
config.time=nil
e.C_RecentAllies.GetRecentAllyByFullName=function()
 return {characterData={fullName="Race North",guid="race"},stateData={isOnline=true}}
end
local dbBefore=e.WhowhoAddressBookDB
S.checkStatus:Click(); assert(S.selected.presenceReport and S.selected.presenceReport.online==true and e.WhowhoAddressBookDB==dbBefore)
local raceId=S.selected.id; local raceSnapshot=A.targetCheck.cached[raceId]
n=0
e.C_RecentAllies.GetRecentAllyByFullName=function()
 n=n+1; return {characterData={fullName="Race North",guid=n==1 and "race" or "changed"},stateData={isOnline=false}}
end
S.checkStatus:Click(); assert(A.targetCheck.cached[raceId]==raceSnapshot and S.selected.presenceReport and S.selected.presenceReport.online==true and e.WhowhoAddressBookDB==dbBefore)
print("RESULT recent-ally simulated passed; no client capability established")
