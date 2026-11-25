-- Simulated manual sources; no native capability is established.
local root=arg[1] or "."; local H=dofile(root.."/tests/addon/harness.lua")
local p,s,e=H.fresh(root,nil,nil,{region=3,time=100})
e.issecrettable=function() return false end
e.InCombatLockdown=function() return false end
e.C_Secrets={ShouldUnitIdentityBeSecret=function() return false end}
e.IsInRaid=function() return false end; e.GetNumSubgroupMembers=function() return 1 end
local guid="g1"; local connected=true
e.UnitExists=function(unit) return unit=="party1" end
e.UnitIsUnit=function() return false end
e.GetUnitName=function() return "Ari North" end; e.UnitGUID=function() return guid end
e.UnitClass=function() return "Mage","MAGE" end; e.UnitLevel=function() return 42 end
e.UnitIsConnected=function() return connected end
s:event("ADDON_LOADED","WhoWho"); p.Toggle(); local S=p.Shell
S.addButton:Click(); local f=S.editor.controls; f.formName:SetText("Ari North"); f.formSave:Click()
assert(S.selected.presenceReport and S.selected.presenceReport.online==true and S.selected.level==42)
assert((S.detail.observation:GetText()==(S.selected.observed and p.FormatDate(S.selected.observed) or p.L("No observation"))))
local existsWithoutTarget=e.UnitExists
e.UnitExists=function(unit) return unit=="target" or existsWithoutTarget(unit) end
e.UnitIsPlayer=function() return false end
connected=false; S.checkStatus:Click()
assert(S.selected.presenceReport and S.selected.presenceReport.online==false and S.detail.attempt:GetText():find("Party",1,true))
e.UnitExists=existsWithoutTarget
local id=S.selected.id; local db=e.WhowhoAddressBookDB
assert(db.regions[3][id].lastKnown.class.source=="Party")
do
    local combat, guidReads = false, 0
    local previous = p.manual.targetCheck.roster[id]
    e.InCombatLockdown = function() return combat end
    e.UnitGUID = function()
        guidReads = guidReads + 1
        if guidReads == 3 then combat = true end
        return guid
    end
    connected = true
    e.UnitLevel = function() return 60 end
    S.checkStatus:Click()
    assert(guidReads==3 and combat, "the final Party identity read must enter combat")
    assert(p.manual.targetCheck.roster[id]==previous and e.WhowhoAddressBookDB==db,
        "a Party result invalidated by combat must preserve prior session and durable evidence")
    e.InCombatLockdown = function() return false end
    e.UnitGUID = function() return guid end
    e.UnitLevel = function() return 42 end
end
local p2,s2=H.fresh(root,nil,nil,{region=3,time=101,db=db})
s2:event("ADDON_LOADED","WhoWho"); p2.Toggle()
assert(p2.manual.records[1].class=="MAGE" and p2.manual.records[1].level==42 and not p2.manual.records[1].presenceReport)
e.GetNumSubgroupMembers=function() return 0 end
e.C_Club={GetGuildClubId=function() return 5 end, AreMembersReady=function() return true end,
 GetClubMembers=function() return {1} end, GetMemberInfo=function() return {name="Ari North",guid="g1",presence=2,classID=8,level=60} end}
e.C_CreatureInfo={GetClassInfo=function() return {classFile="MAGE"} end}
e.Enum={ClubMemberPresence={Online=1,Away=2,Busy=3,Offline=4}}
S.checkStatus:Click(); assert(S.selected.presenceReport and S.selected.presenceReport.online==true and S.selected.level==42)
assert((S.detail.observation:GetText()==(S.selected.observed and p.FormatDate(S.selected.observed) or p.L("No observation"))))
assert(S.detail.attempt:GetText()=="Guild report found." and S.detail.attempt:GetStringWidth()<=S.detail.attempt:GetWidth())
e.C_Club.GetMemberInfo=function() return {name="Ari North",guid="wrong",presence=4} end
S.checkStatus:Click(); assert(S.selected.presenceReport and S.selected.presenceReport.online==true)
-- Guild also enriches a newly added Friend and ignores unrelated missing GUIDs.
e.C_Club.GetClubMembers=function() return {2,3} end
e.C_Club.GetMemberInfo=function(_,id)
 if id==2 then return {name="Other North"} end
 return {name="Bea North",guid="g2",presence=4,classID=8,level=32}
end
S.addButton:Click(); f.formName:SetText("Bea North"); f.formSave:Click()
assert(S.selected.presenceReport and S.selected.presenceReport.online==false and S.selected.level==32)
-- A raid excludes the player and reads the matched unit only after preflight.
e.IsInRaid=function() return true end; e.GetNumGroupMembers=function() return 2 end
e.UnitExists=function(unit) return unit~="target" end
e.UnitIsUnit=function(unit) return unit=="raid1" end
e.GetUnitName=function(unit) assert(unit=="raid2"); return "Bea North" end
e.UnitGUID=function(unit) assert(unit=="raid2"); return "g2" end
e.UnitLevel=function() return 45 end; connected=true
S.checkStatus:Click(); assert(S.selected.presenceReport and S.selected.presenceReport.online==true and S.selected.level==45)
assert((S.detail.observation:GetText()==(S.selected.observed and p.FormatDate(S.selected.observed) or p.L("No observation"))))
-- Changed token during metadata is never published.
local before=e.WhowhoAddressBookDB
e.UnitLevel=function() e.UnitGUID=function() return "changed" end; return 60 end
S.checkStatus:Click(); assert(e.WhowhoAddressBookDB==before and S.selected.level==45)
-- Unready guild and hidden group identities fall through without reading them.
e.IsInRaid=function() return false end; e.GetNumSubgroupMembers=function() return 1 end
e.C_Secrets.ShouldUnitIdentityBeSecret=function() return true end
e.GetUnitName=function() error("hidden identity read") end
e.C_Club.AreMembersReady=function() return false end
S.checkStatus:Click(); assert(S.selected.level==45)
-- A matching target wins and no roster is consulted.
e.C_Secrets.ShouldUnitIdentityBeSecret=function() return false end
e.UnitExists=function(unit) return unit=="target" end; e.UnitIsPlayer=function() return true end
e.GetUnitName=function() return "Bea North" end; e.UnitGUID=function() return "g2" end
e.UnitLevel=function() return 50 end; e.date=function() return "2026-11-18 12:30" end
e.IsInRaid=function() error("group should not be read") end
S.checkStatus:Click(); assert(S.selected.presence=="Seen" and S.selected.level==50)
-- A guild record changing during metadata cannot publish.
e.UnitExists=function() return false end; e.IsInRaid=function() return false end
e.GetNumSubgroupMembers=function() return 0 end; e.C_Club.AreMembersReady=function() return true end
local guildGuid="g2"
e.C_Club.GetClubMembers=function() return {3} end
e.C_Club.GetMemberInfo=function() return {name="Bea North",guid=guildGuid,presence=1,classID=8,level=60} end
e.C_CreatureInfo.GetClassInfo=function() guildGuid="changed"; return {classFile="MAGE"} end
before=e.WhowhoAddressBookDB; S.checkStatus:Click(); assert(e.WhowhoAddressBookDB==before and S.selected.level==50)
-- Another member can acquire the same name during the metadata lookup.
local duplicate=false
e.C_Club.GetClubMembers=function() return {3,4} end
e.C_Club.GetMemberInfo=function(_,memberId)
 if memberId==4 then return {name=duplicate and "Bea North" or "Other North",guid="g4"} end
 return {name="Bea North",guid="g2",presence=1,classID=8,level=60}
end
e.C_CreatureInfo.GetClassInfo=function() duplicate=true; return {classFile="MAGE"} end
before=e.WhowhoAddressBookDB; S.checkStatus:Click(); assert(e.WhowhoAddressBookDB==before and S.selected.level==50)
-- A direct observation retains its display while recording an identity-only guild hint.
duplicate=false
e.UnitExists=function(unit) return unit=="target" end
e.C_Club.GetMemberInfo=function(_,memberId)
 if memberId==4 then return {name="Other North"} end
 return {name="Bea North",guid="g2"}
end
local recentReads=0
e.C_RecentAllies={IsSystemSupported=function() return true end,IsSystemEnabled=function() return true end,
 IsRecentAllyDataReady=function() return true end,GetRecentAllyByFullName=function()
  recentReads=recentReads+1; return {characterData={fullName="Bea North",guid="g2"}}
 end}
S.checkStatus:Click(); assert(S.selected.presence=="Seen")
local hint=e.WhowhoAddressBookDB.regions[3][S.selected.id].lastKnown.sources.guild
assert(hint.clubId==5 and hint.at==100 and recentReads==0)
e.C_Club.AreMembersReady=function() return false end
S.checkStatus:Click(); assert(S.selected.presence=="Seen" and recentReads==2)
assert(e.WhowhoAddressBookDB.regions[3][S.selected.id].lastKnown.sources.recentAlliesAt==100)
S.checkStatus:Click(); assert(S.selected.presence=="Seen" and recentReads==2)
e.C_Club.AreMembersReady=function() return true end
-- A source match without status or metadata still records its historical hint.
e.UnitExists=function() return false end
S.addButton:Click(); f.formName:SetText("Hint North")
e.C_Club.GetClubMembers=function() return {9} end
e.C_Club.GetMemberInfo=function() return {name="Hint North",guid="h9"} end
f.formSave:Click()
local only=e.WhowhoAddressBookDB.regions[3][S.selected.id].lastKnown
assert(only.guid=="h9" and only.sources.guild.clubId==5 and not only.class and not only.level and not S.selected.presenceReport)
-- A ready no-match and an unreadable roster produce different outcomes.
e.GetNumSubgroupMembers=function() return 0 end
e.C_Club.GetClubMembers=function() return {9} end
e.C_Club.GetMemberInfo=function() return {name="Other North"} end
e.C_RecentAllies.IsRecentAllyDataReady=function() return false end
S.checkStatus:Click(); assert(S.footer:GetText():find("Recent Allies data unavailable",1,true))
e.C_Club.GetMemberInfo=function() return nil end
S.checkStatus:Click(); assert(S.footer:GetText():find("Guild data unavailable",1,true))
-- A changed guild identity is retained if the later source fails.
local reads=0
e.C_Club.GetMemberInfo=function() reads=reads+1; return {name="Hint North",guid=reads==1 and "h9" or "changed",presence=1} end
S.checkStatus:Click(); assert(S.footer:GetText():find("Guild changed",1,true))
-- A usable lower-priority source still wins after an unreadable guild.
e.C_Club.GetMemberInfo=function() return nil end
e.C_RecentAllies.IsRecentAllyDataReady=function() return true end
e.C_RecentAllies.GetRecentAllyByFullName=function() return {characterData={fullName="Hint North",guid="h9"},stateData={isOnline=true}} end
S.checkStatus:Click(); assert(S.selected.presenceReport and S.selected.presenceReport.source=="Recent Allies" and S.selected.presenceReport.online==true)
-- Missing group APIs do not hide a guild readiness or row failure.
e.IsInRaid=nil
e.C_Club.AreMembersReady=function() return false end
e.C_RecentAllies.IsRecentAllyDataReady=function() return false end
S.checkStatus:Click(); assert(S.footer:GetText():find("Guild data not ready",1,true))
e.C_Club.AreMembersReady=function() return true end
S.checkStatus:Click(); assert(S.footer:GetText():find("Guild data unavailable",1,true))
-- An exact guild match with metadata and no readable status stays unknown.
e.C_Club.GetMemberInfo=function() return {name="Hint North",guid="h9",classID=8,level=33} end
S.checkStatus:Click(); assert(S.selected.presenceReport and S.selected.presenceReport.source=="Guild" and S.selected.presenceReport.online==nil and S.selected.level==33)
-- A recognized explicit offline status remains distinct from absent presence.
e.C_Club.GetMemberInfo=function() return {name="Hint North",guid="h9",presence=4,classID=8,level=33} end
S.checkStatus:Click(); assert(S.selected.presenceReport and S.selected.presenceReport.source=="Guild" and S.selected.presenceReport.online==false)
-- Busy is online. Unknown and unreadable presence leave a metadata-only report.
for _,case in ipairs({{3,true},{99},{s.secret}}) do
    e.C_Club.GetMemberInfo=function() return {name="Hint North",guid="h9",presence=case[1],classID=8,level=33} end
    S.checkStatus:Click()
    assert(S.selected.presenceReport.source=="Guild" and S.selected.presenceReport.online==case[2] and S.selected.level==33)
end
-- An incomplete Guild report keeps its metadata while Recent Allies fills status.
local q,t,v=H.fresh(root,nil,nil,{region=3,time=100})
v.issecrettable=function() return false end; v.InCombatLockdown=function() return false end
v.UnitExists=function() return false end; v.IsInRaid=function() return false end; v.GetNumSubgroupMembers=function() return 0 end
v.C_Club={GetGuildClubId=function() return 5 end,AreMembersReady=function() return true end,
 GetClubMembers=function() return {1} end,GetMemberInfo=function() return {name="Partial North",guid="partial",classID=1,level=32} end}
v.Enum={ClubMemberPresence={Online=1,Away=2,Busy=3,Offline=4}}
v.C_CreatureInfo={GetClassInfo=function(id) return {classFile=id==1 and "WARRIOR" or "MAGE"} end}
local recentCount=0
v.C_RecentAllies={IsSystemSupported=function() return true end,IsSystemEnabled=function() return true end,IsRecentAllyDataReady=function() return true end,
 GetRecentAllyByFullName=function() recentCount=recentCount+1; return {characterData={fullName="Partial North",guid="partial",classID=8,level=60},stateData={isOnline=true}} end}
t:event("ADDON_LOADED","WhoWho"); q.Toggle(); local U=q.Shell
U.addButton:Click(); U.editor.controls.formName:SetText("Partial North"); U.editor.controls.formSave:Click()
assert(recentCount==2 and U.selected.class=="WARRIOR" and U.selected.level==32)
assert(U.selected.presenceReport.source=="Recent Allies" and U.selected.presenceReport.online==true)
local last=v.WhowhoAddressBookDB.regions[3][U.selected.id].lastKnown
assert(last.class.source=="Guild" and last.level.source=="Guild" and last.sources.guild and last.sources.recentAlliesAt)
-- Explicit Guild offline stops the chain, including on Check.
v.C_Club.GetMemberInfo=function() return {name="Partial North",guid="partial",presence=4,classID=1,level=32} end
U.checkStatus:Click(); assert(recentCount==2 and U.selected.presenceReport.source=="Guild" and U.selected.presenceReport.online==false)
-- A partial report remains the latest report when no lower source is ready.
v.C_Club.GetMemberInfo=function() return {name="Partial North",guid="partial",classID=1,level=32} end
v.C_RecentAllies.IsRecentAllyDataReady=function() return false end
U.checkStatus:Click(); assert(recentCount==2 and U.selected.presenceReport.source=="Guild" and U.selected.presenceReport.online==nil)
assert(U.selected.class=="WARRIOR" and U.selected.level==32 and U.footer:GetText():find("Guild report",1,true))
-- Without a readable clock, session reports still retain the stronger source's fields.
v.GetServerTime=function() return nil end
v.C_RecentAllies.IsRecentAllyDataReady=function() return true end
local beforeClockless=v.WhowhoAddressBookDB
U.checkStatus:Click(); assert(U.selected.class=="WARRIOR" and U.selected.level==32 and U.selected.presenceReport.source=="Recent Allies")
assert(v.WhowhoAddressBookDB==beforeClockless)
-- A conflicting lower identity cannot replace the partial report.
v.C_RecentAllies.GetRecentAllyByFullName=function() return {characterData={fullName="Partial North",guid="different",classID=8,level=60},stateData={isOnline=true}} end
U.checkStatus:Click(); assert(U.selected.presenceReport.source=="Guild" and U.selected.presenceReport.online==nil and U.selected.class=="WARRIOR")
-- Lower sources can fill missing metadata without replacing the stronger field.
v.GetServerTime=function() return 101 end
v.C_Club.GetMemberInfo=function() return {name="Missing North",guid="missing",classID=1} end
v.C_RecentAllies.GetRecentAllyByFullName=function() return {characterData={fullName="Missing North",guid="missing",classID=8,level=60},stateData={isOnline=true}} end
U.addButton:Click(); U.editor.controls.formName:SetText("Missing North"); U.editor.controls.formSave:Click()
assert(U.selected.class=="WARRIOR" and U.selected.level==60 and U.selected.presenceReport.source=="Recent Allies")
last=v.WhowhoAddressBookDB.regions[3][U.selected.id].lastKnown
assert(last.class.source=="Guild" and last.level.source=="Recent Allies")
-- Group metadata takes precedence when the Guild supplies the missing status.
v.GetNumSubgroupMembers=function() return 1 end
v.UnitExists=function(unit) return unit=="party1" end; v.UnitIsUnit=function() return false end
v.C_Secrets={ShouldUnitIdentityBeSecret=function() return false end}
v.GetUnitName=function() return "Missing North" end; v.UnitGUID=function() return "missing" end
v.UnitIsConnected=function() return nil end; v.UnitClass=function() return "Warrior","WARRIOR" end; v.UnitLevel=function() return 25 end
v.C_Club.GetMemberInfo=function() return {name="Missing North",guid="missing",presence=1,classID=8,level=60} end
U.checkStatus:Click(); assert(U.selected.presenceReport.source=="Guild" and U.selected.presenceReport.online==true and U.selected.class=="WARRIOR" and U.selected.level==25)
last=v.WhowhoAddressBookDB.regions[3][U.selected.id].lastKnown
assert(last.class.source=="Party" and last.level.source=="Party")
-- Ambiguous Group identities stop before a ready Guild can claim either GUID.
local a,b,c=H.fresh(root,nil,nil,{region=3,time=200})
c.issecrettable=function() return false end; c.InCombatLockdown=function() return false end
c.IsInRaid=function() return false end; c.GetNumSubgroupMembers=function() return 2 end
c.UnitExists=function(unit) return unit=="party1" or unit=="party2" end
c.UnitIsUnit=function() return false end; c.C_Secrets={ShouldUnitIdentityBeSecret=function() return false end}
c.GetUnitName=function() return "Ambiguous North" end
c.UnitGUID=function(unit) return unit=="party1" and "first" or "second" end
local guildReads,allyReads=0,0
c.C_Club={GetGuildClubId=function() guildReads=guildReads+1; return 5 end,AreMembersReady=function() return true end,
 GetClubMembers=function() return {1} end,GetMemberInfo=function() return {name="Ambiguous North",guid="first",presence=1} end}
c.C_RecentAllies={IsSystemSupported=function() allyReads=allyReads+1; return true end,IsSystemEnabled=function() return true end,
 IsRecentAllyDataReady=function() return true end,GetRecentAllyByFullName=function() return {characterData={fullName="Ambiguous North",guid="first"},stateData={isOnline=true}} end}
b:event("ADDON_LOADED","WhoWho"); a.Toggle(); local V=a.Shell
V.addButton:Click(); V.editor.controls.formName:SetText("Ambiguous North"); V.editor.controls.formSave:Click()
assert(guildReads==0 and allyReads==0 and V.selected.attempt:find("Group identity is ambiguous",1,true))
assert(not c.WhowhoAddressBookDB.regions[3][V.selected.id].lastKnown)
-- A verified Group partial survives a changed Guild identity; Recent Allies is not read.
c.GetNumSubgroupMembers=function() return 1 end; c.GetUnitName=function() return "Change North" end
c.UnitGUID=function() return "stable" end; c.UnitIsConnected=function() return nil end
c.UnitClass=function() return "Warrior","WARRIOR" end; c.UnitLevel=function() return 32 end
local guildRows=0
c.C_Club.GetMemberInfo=function()
 guildRows=guildRows+1; return {name="Change North",guid=guildRows==1 and "stable" or "changed",presence=1}
end
V.addButton:Click(); V.editor.controls.formName:SetText("Change North"); V.editor.controls.formSave:Click()
assert(guildReads>0 and allyReads==0 and V.selected.attempt:find("Guild changed",1,true))
local retained=c.WhowhoAddressBookDB.regions[3][V.selected.id].lastKnown
assert(retained.guid=="stable" and retained.class.source=="Party" and retained.level.source=="Party")
assert(V.selected.class=="WARRIOR" and V.selected.level==32 and V.selected.presenceReport.source=="Party" and V.selected.presenceReport.online==nil)
-- The final matching member read can invalidate an otherwise exact Guild proof.
c.GetNumSubgroupMembers=function() return 0 end
local positiveReady, positiveScans=true,0
c.C_Club.AreMembersReady=function() return positiveReady end
c.C_Club.GetClubMembers=function() positiveScans=positiveScans+1; return {1} end
c.Enum={ClubMemberPresence={Online=1,Offline=4}}
c.C_Club.GetMemberInfo=function()
 if positiveScans==2 then positiveReady=false end
 return {name="Late North",guid="late",presence=4}
end
V.addButton:Click(); V.editor.controls.formName:SetText("Late North"); V.editor.controls.formSave:Click()
assert(positiveScans==2 and not positiveReady and V.selected.attempt:find("Guild changed",1,true))
assert(not V.selected.presenceReport and not c.WhowhoAddressBookDB.regions[3][V.selected.id].lastKnown)
-- Guild absence requires a prior bound same-club hint and stable, fully readable membership.
local cfg={region=3,time=100}; local ap,as,ae=H.fresh(root,nil,nil,cfg)
ae.issecrettable=function() return false end; ae.InCombatLockdown=function() return false end
ae.UnitExists=function() return false end; ae.IsInRaid=function() return false end; ae.GetNumSubgroupMembers=function() return 0 end
local ids={1}; local members={[1]={name="Former North",guid="former",presence=1,classID=1,level=32}}
local club,ready=7,true
ae.C_Club={GetGuildClubId=function() return club end,AreMembersReady=function() return ready end,
 GetClubMembers=function() return ids end,GetMemberInfo=function(_,id) return members[id] end}
ae.Enum={ClubMemberPresence={Online=1,Away=2,Busy=3,Offline=4}}
ae.C_CreatureInfo={GetClassInfo=function() return {classFile="WARRIOR"} end}
local recentReady=false
ae.C_RecentAllies={IsSystemSupported=function() return true end,IsSystemEnabled=function() return true end,
 IsRecentAllyDataReady=function() return recentReady end,GetRecentAllyByFullName=function() return {characterData={fullName="Former North",guid="former"},stateData={isOnline=true}} end}
as:event("ADDON_LOADED","WhoWho"); ap.Toggle(); local W=ap.Shell
W.addButton:Click(); local af=W.editor.controls; af.formName:SetText("Former North"); af.roleOptions.HEALER:Click(); af.formNote:SetText("keep"); af.formSave:Click()
members[1].presence=nil; recentReady=true; cfg.time=101; W.checkStatus:Click()
members[1].presence=1; cfg.time=102; W.checkStatus:Click(); recentReady=false
assert(W.selected.presenceReport.source=="Guild")
local original=ae.WhowhoAddressBookDB
ids={}; cfg.time=103; W.checkStatus:Click(); assert(ae.WhowhoAddressBookDB==original)
ids={[1]=1,[3]=3}; members[1]={name="Other North",guid="other"}; members[3]={name="Third North",guid="third"}; W.checkStatus:Click(); assert(ae.WhowhoAddressBookDB==original)
ids={1,1}; W.checkStatus:Click(); assert(ae.WhowhoAddressBookDB==original)
ids={1,3}; members[3].name="Other North"; W.checkStatus:Click(); assert(ae.WhowhoAddressBookDB==original)
members[3].name="Third North"; members[3].guid="other"; W.checkStatus:Click(); assert(ae.WhowhoAddressBookDB==original)
ids={1}; members[1]={name="Other North"}; W.checkStatus:Click(); assert(ae.WhowhoAddressBookDB==original)
members[1]={name="Renamed North",guid="former"}; W.checkStatus:Click(); assert(ae.WhowhoAddressBookDB==original)
members[1]={name="Former North",guid="wrong"}; W.checkStatus:Click(); assert(ae.WhowhoAddressBookDB==original)
members[1]={name="Other North",guid="other"}; club=8; W.checkStatus:Click(); assert(ae.WhowhoAddressBookDB==original)
club=7; ready=false; W.checkStatus:Click(); assert(ae.WhowhoAddressBookDB==original)
ready=true; cfg.time=102; W.checkStatus:Click(); assert(ae.WhowhoAddressBookDB==original)
cfg.time=103; local scans=0
ae.C_Club.GetClubMembers=function() scans=scans+1; if scans==3 then return {2} end; return ids end
members[2]={name="Third North",guid="third"}; W.checkStatus:Click(); assert(scans==3 and ae.WhowhoAddressBookDB==original)
scans=0
ae.C_Club.GetClubMembers=function() scans=scans+1; return ids end
local memberInfo=ae.C_Club.GetMemberInfo
ae.C_Club.GetMemberInfo=function(_,id)
    if scans==3 then ready=false end
    return members[id]
end
W.checkStatus:Click(); assert(scans==3 and not ready and ae.WhowhoAddressBookDB==original)
ae.C_Club.GetMemberInfo=memberInfo
ready=true
scans=0; local initialStore=ap.manual.store
ae.C_Club.GetClubMembers=function()
 scans=scans+1
 if scans==3 then ap.manual.store=setmetatable({}, {__index=initialStore}) end
 return ids
end
W.checkStatus:Click(); assert(ae.WhowhoAddressBookDB==original)
ap.manual.store=initialStore
-- Neither roster refresh path deactivates a hint when the Friend is missing.
ids={1,2}; scans=0
ae.C_Club.GetClubMembers=function() scans=scans+1; return ids end
ap.manual.batchRefresh.run()
local _,_,batchResult=ap.manual.batchRefresh.state()
assert(scans==1 and batchResult=="Roster status found for 0 of 1 Friend." and ae.WhowhoAddressBookDB==original)
local done,changed=ap.manual.relogRefresh.attempt("Guild",function() return true end)
assert(done and not changed and scans==2 and ae.WhowhoAddressBookDB==original)
-- The proof compares ID-to-identity mappings using the captured API, even if native reads reorder the list.
scans=0
local api,unexpected=ae.C_Club,0
local replacement=setmetatable({}, {__index=function()
    unexpected=unexpected+1
    error("unexpected replacement API read")
end})
api.GetClubMembers=function()
    scans=scans+1
    if scans==2 then ae.C_Club=replacement end
    if scans==3 then return {2,1} end
    return ids
end
W.checkStatus:Click(); local saved=ae.WhowhoAddressBookDB.regions[3][W.selected.id]
assert(scans==3 and unexpected==0)
ids={1}; ae.C_Club=api; api.GetClubMembers=function() return ids end
assert(saved.lastKnown.guid=="former" and saved.lastKnown.sources.guild.absentAt==103 and saved.lastKnown.sources.guild.at==102)
assert(saved.lastKnown.sources.recentAlliesAt==101 and saved.lastKnown.class.value=="WARRIOR" and saved.lastKnown.level.value==32 and saved.note=="keep" and saved.role=="HEALER")
assert(not W.selected.presenceReport and W.selected.attempt:find("Guild roster no longer lists",1,true))
local reload,rs=H.fresh(root,nil,nil,{region=3,time=104,db=ae.WhowhoAddressBookDB}); rs:event("ADDON_LOADED","WhoWho")
assert(reload.manual.store.get(W.selected.id).lastKnown.sources.guild.absentAt==103)
-- A later verified match restores the hint; another absence permits Recent Allies status.
members[1]={name="Former North",guid="former",presence=1,classID=1,level=32}; cfg.time=104; W.checkStatus:Click()
assert(not ae.WhowhoAddressBookDB.regions[3][W.selected.id].lastKnown.sources.guild.absentAt and W.selected.presenceReport.source=="Guild")
members[1]={name="Other North",guid="other"}; recentReady=true; cfg.time=105; W.checkStatus:Click()
assert(ae.WhowhoAddressBookDB.regions[3][W.selected.id].lastKnown.sources.guild.absentAt==105 and W.selected.presenceReport.source=="Recent Allies")
-- A same-second return restores the hint, allowing a later absence to clear the session.
recentReady=false; members[1]={name="Former North",guid="former",presence=1,classID=1,level=32}
W.checkStatus:Click(); assert(W.selected.presenceReport.source=="Guild" and not ae.WhowhoAddressBookDB.regions[3][W.selected.id].lastKnown.sources.guild.absentAt)
members[1]={name="Other North",guid="other"}; cfg.time=106; W.checkStatus:Click()
assert(not W.selected.presenceReport and ae.WhowhoAddressBookDB.regions[3][W.selected.id].lastKnown.sources.guild.absentAt==106)
-- A clockless return cannot update the hint, but a fresh same-second absence still clears its session status.
members[1]={name="Former North",guid="former",presence=1,classID=1,level=32}; cfg.time=nil; W.checkStatus:Click()
assert(W.selected.presenceReport.source=="Guild" and ae.WhowhoAddressBookDB.regions[3][W.selected.id].lastKnown.sources.guild.absentAt==106)
members[1]={name="Other North",guid="other"}; cfg.time=106; W.checkStatus:Click()
assert(not W.selected.presenceReport and ae.WhowhoAddressBookDB.regions[3][W.selected.id].lastKnown.sources.guild.absentAt==106)
print("RESULT roster simulated passed; no client capability established")
