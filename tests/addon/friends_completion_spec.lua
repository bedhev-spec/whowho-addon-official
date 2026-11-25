-- Simulated invites, draft resolution, and time-based Friends presence.
local root=arg[1] or "."
local H=dofile(root.."/tests/addon/harness.lua")
local config={region=3,time=100}
local p,s,e=H.fresh(root,nil,{484,800},config)
local units, invites = {}, {}
local combat, canInvite = false, true
local function field(unit,key)
    if units[unit] then return units[unit][key] end
end
e.UnitExists=function(unit) return units[unit]~=nil end
e.UnitIsPlayer=function(unit) return units[unit]~=nil end
e.GetUnitName=function(unit) return field(unit,"name") end
e.UnitGUID=function(unit) return field(unit,"guid") end
e.UnitClass=function() return "Mage","MAGE" end
e.UnitLevel=function() return 22 end
e.UnitFactionGroup=function(unit) return unit=="player" and "Alliance" or field(unit,"faction") end
e.UnitPhaseReason=function(unit) return field(unit,"phase") end
e.Enum={PhaseReason={RuleSet=5}}
e.IsInRaid=function() return false end
e.GetNumSubgroupMembers=function() return units.party1 and 1 or 0 end
e.InCombatLockdown=function() return combat end
e.date=function() return "2026-11-19 12:30" end
e.C_PartyInfo={CanInvite=function() return canInvite end,InviteUnit=function(name) invites[#invites+1]=name end}
s:event("ADDON_LOADED","WhoWho"); p.Toggle()
local A,S=p.manual,p.Shell
local ari=assert(A.save(nil,"friend","Ari North","keep","HEALER"))
local bea=assert(A.save(nil,"friend","Bea North","",nil))
local form=S.editor.controls
S.addButton:Click(); form.formName:SetText("Ari"); form.formNote:SetText("draft note")
form.roleOptions.HEALER:Click(); form.formSave:Click()
local draft=S.selected
assert(draft.identityState=="unresolved" and draft.region==nil and draft.note=="draft note")
assert(not A.store.find(3,"Ari") and not A.store.find(3,"Ari","ari"))
S.searchBox:SetText("Ari")
for _,row in ipairs(S.rows) do
    if row.record and row.record.id==draft.id then
        assert(row.status:GetText()=="Unknown" and not row.copyButton:IsEnabled())
        assert(not row.inviteButton:IsEnabled() and not row.favoriteButton:IsShown())
    end
end
assert(not S.checkStatus:IsEnabled() and not S.moveButton:IsEnabled())
assert(A.targetCheck.check(A.store.get(draft.id)):find("Resolve the draft",1,true))
local reloaded,sim=H.fresh(root,nil,nil,{region=3,time=100,db=e.WhowhoAddressBookDB})
sim:event("ADDON_LOADED","WhoWho")
assert(reloaded.manual.store.get(draft.id).identityState=="unresolved")
S.editButton:Click()
assert(form.formName:IsEnabled() and form.formName:HasFocus() and form.roleOptions.HEALER.selected)
form.formName:SetText("Ari North"); form.formSave:Click()
assert(form.form:IsShown() and form.formSave.label:GetText()=="Open existing")
assert(A.store.get(draft.id).identityState=="unresolved")
form.formName:SetText("Ari South"); form.formSave:Click()
assert(S.selected.id==draft.id and S.selected.region==3 and S.selected.fullName=="Ari South")
assert(S.selected.note=="draft note" and S.selected.role=="HEALER" and A.store.get(ari.id).note=="keep")
local discard=assert(A.save(nil,"friend","Bea","unfinished",nil))
assert(A.delete(discard) and not A.store.get(discard.id) and not A.store.export().archived)

-- Readable unit observations keep faction and a known ruleset mismatch with the exact identity.
S.searchBox:SetText("Ari North")
assert(A.store.observe(ari.id,3,ari.fullName,"ari","Recent Allies",99,nil,nil,true))
e.C_RecentAllies={
    IsSystemSupported=function() return true end,
    IsSystemEnabled=function() return true end,
    IsRecentAllyDataReady=function() return true end,
    GetRecentAllies=function()
        return {{characterData={fullName="Ari North",guid="ari"},stateData={isOnline=true}}}
    end,
}
local done, changed=A.relogRefresh.attempt("Recent Allies",function() return true end)
assert(done and changed)
units.target={name="Ari North",guid="ari",faction="Horde",phase=5}
assert(A.targetCheck.check(A.store.get(ari.id))=="Target observed.")
S.Refresh(); S.Select(S.rows[1].record)
assert(S.detail.affiliation:GetText()=="Horde · Local checks only · Different ruleset")
assert(S.detail.current:GetText()=="Unknown")
local button=S.rows[1].inviteButton
assert(not button:IsEnabled() and S.rows[1].inviteIssue:find("other faction",1,true))
units.target.faction="Alliance"
S.Refresh()
assert(not button:IsEnabled() and S.rows[1].inviteIssue:find("another ruleset",1,true))
assert(A.setAutomaticTarget(false)); assert(A.setAutomaticMouseover(false))
local originalTarget=units.target
units.target=nil
s:event("PLAYER_TARGET_CHANGED")
assert(button:IsEnabled() and not A.automaticTargetEnabled() and not A.automaticMouseoverEnabled())
units.target=originalTarget
s:event("PLAYER_TARGET_CHANGED")
assert(not button:IsEnabled() and S.rows[1].inviteIssue:find("another ruleset",1,true))
units.target.phase=nil
units.party1=units.target
s:event("GROUP_ROSTER_UPDATE")
assert(not button:IsEnabled() and S.rows[1].inviteIssue:find("already in",1,true))
units.party1=nil
s:event("GROUP_ROSTER_UPDATE")
assert(button:IsEnabled() and #invites==0)
button:Click()
assert(#invites==1 and invites[1]=="Ari North" and S.footer:GetText():find("Invitation requested",1,true))
-- A rebound row and a live permission change must never dispatch a different recipient.
s:fire(button,"OnMouseDown","LeftButton")
S.searchBox:SetText("Bea North")
button:Click()
assert(#invites==1)
canInvite=false
button:Click()
assert(#invites==1)
canInvite=true; S.Refresh()
combat=true; button:Click()
assert(#invites==1)
combat=false; S.Refresh()
local region,regionReads=e.GetCurrentRegion,0
e.GetCurrentRegion=function()
    regionReads=regionReads+1
    if regionReads==3 then
        units.party1={name="Bea North",guid="bea"}
        s:event("GROUP_ROSTER_UPDATE")
    end
    return region()
end
button:Click()
assert(#invites==1 and not button:IsEnabled() and S.rows[1].inviteIssue:find("already in",1,true))
e.GetCurrentRegion=region; units.party1=nil
s:event("GROUP_ROSTER_UPDATE")
button:Click()
assert(#invites==2 and invites[2]=="Bea North")

-- The visible list expires a five-minute sighting and retains its source and time in details.
S.searchBox:SetText("Ari North")
S.Select(S.rows[1].record)
S.editButton:Click()
form.formNote:SetText("edited across expiry")
config.time=399
s:fire(S.window,"OnUpdate",1)
assert(S.detail.current:GetText()=="Unknown")
config.time=400
s:fire(S.window,"OnUpdate",1)
assert(not S.selected.presence and S.selected.source=="Target" and S.selected.observed)
assert(S.detail.current:GetText()=="Online" and S.detail.observation:GetText()==p.FormatDate(S.selected.observed),
    "an expired successful Target check must yield to a valid relog report")
A.relogRefresh.forget(ari.id)
A.refresh(); S.Refresh()
assert(S.detail.current:GetText()=="Unknown" and S.detail.observationLabel:GetText()=="Last seen")
assert(S.selected.class=="MAGE" and S.selected.level==22)
assert(form.form:IsShown())
form.formSave:Click()
assert(not form.form:IsShown() and A.store.get(ari.id).note=="edited across expiry")
assert(s.forbiddenCalls+sim.forbiddenCalls==0)
print("RESULT Friends invitations, unresolved drafts, affiliations and expiry passed in simulation")
