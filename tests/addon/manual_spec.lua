-- Offline widget and SavedVariables simulation; not a native-client test.
local root=arg[1] or "."
local H=dofile(root.."/tests/addon/harness.lua")
local count=0
local function check(value, label) count=count+1; assert(value,label) end
local function fresh(config,viewport)
    local p,s,e=H.fresh(root,nil,viewport,config)
    p.Toggle(); check(not p.initialized,"no initialization before own ADDON_LOADED")
    s:event("ADDON_LOADED","OtherAddon"); check(not p.initialized,"foreign load ignored")
    s:event("ADDON_LOADED","WhoWho"); check(p.initialized,"own load initializes")
    local nodes=#s.nodes; s:event("ADDON_LOADED","WhoWho"); check(#s.nodes==nodes,"repeated load ignored")
    p.Toggle(); return p,s,e,p.Shell
end
local config={region=3,time=100}
do
    local app,sim,env=H.fresh(root,nil,nil,{region=3,time=100})
    sim:event("ADDON_LOADED","WhowhoPreview")
    check(not app.initialized,"development folder name cannot initialize the shipped addon")
    check(app.media=="Interface\\AddOns\\WhoWho\\Media\\","shipped media uses the actual addon folder")
    sim:event("ADDON_LOADED","WhoWho")
    check(app.initialized and app.db==env.WhowhoPreviewDB,"shipped addon initializes with existing SavedVariables names")
    local nodes=#sim.nodes
    sim:event("ADDON_LOADED","WhoWho")
    check(#sim.nodes==nodes,"shipped addon initializes once")
    env.SlashCmdList.WHOWHOPREVIEW()
    check(app.Shell.window:IsShown() and env.SLASH_WHOWHOPREVIEW1=="/wwpreview","existing slash command opens shipped addon")
    check(sim.forbiddenCalls==0,"shipped startup performs no forbidden actions")
end
local p,s,e,S=fresh(config)
local tocVersion=assert(os.getenv("WHOWHO_PREVIEW_TOC"):match("## Version:%s*(%S+)"))
check(p.version==tocVersion and S.revision:GetText()==tocVersion,"runtime and window versions match the manual TOC")
local recordsReference=p.manual.records
S.nav.encounters:Click()
local empty=false
for _,child in ipairs(S.encounters.children) do
    if child.kind=="FontString" and child:GetText()=="No encounters in the last hour." and child:IsShown() then empty=true end
end
check(#S.records==0 and S.encounters:IsVisible() and empty,"empty real data has no fictional history")
S.nav.friend:Click()
check(S.sortButton:GetParent()==S.list and S.sortButton.label:GetText()=="Character · A–Z","character heading owns the A–Z sort control")
S.addButton:Click(); local form=S.editor.controls
check(form.formName:IsEnabled() and form.formName:HasFocus(),"Add keeps name editable and focused")
form.formName:SetText("Élan Amber"); form.roleOptions.HEALER:Click(); form.formNote:SetText("private note"); form.formSave:Click()
check(#S.records==1 and S.records[1].fullName=="Élan Amber", "add saved")
check(p.manual.records==recordsReference and S.records==recordsReference, "save retains shared records table")
check(not S.columnCopy:IsShown() and not S.columnInvite:IsShown(),"manual action headings hidden")
check(S.rows[1].copyButton:IsEnabled() and not S.rows[1].inviteButton:IsEnabled() and S.rows[1].deleteButton:IsEnabled(),"row actions retain their enabled states")
s:fire(S.rows[1].copyButton,"OnEnter"); check(e.GameTooltip:IsShown(),"copy tooltip retained"); s:fire(S.rows[1].copyButton,"OnLeave")
s:fire(S.rows[1].inviteButton,"OnEnter"); check(e.GameTooltip:GetText():find("unavailable",1,true)~=nil,"disabled invite tooltip retained"); s:fire(S.rows[1].inviteButton,"OnLeave")
check(e.WhowhoAddressBookDB.regions[3][1].note=="private note", "saved variable bound on change")
check(S.records[1].class==nil and S.records[1].observed==nil,"no invented observation")
local id=S.records[1].id
local hint="No verified online/offline information is available for this player."
s:fire(S.rows[1].statusHover,"OnEnter"); check(e.GameTooltip:IsShown() and e.GameTooltip:GetText()==hint,"unknown roster text explains unavailable presence")
local other=e.CreateFrame("Frame",nil,e.UIParent); e.GameTooltip:SetOwner(other,"ANCHOR_RIGHT"); e.GameTooltip:SetText("Other addon",1,1,1,1,true); e.GameTooltip:Show()
s:fire(S.rows[1].statusHover,"OnLeave"); check(e.GameTooltip:IsShown() and e.GameTooltip:GetOwner()==other,"leaving presence icon preserves another addon's tooltip"); e.GameTooltip:Hide()
s:fire(S.rows[1].statusHover,"OnEnter")
s:routePointer({S.rows[1].statusHover,S.rows[1]},"OnClick"); check(S.selectedId==id and not e.GameTooltip:IsShown(),"hover hit area selects the same row and clears tooltip")
s:fire(S.detail.statusHover,"OnEnter"); check(e.GameTooltip:IsShown() and e.GameTooltip:GetText()==hint,"unknown detail text explains unavailable presence"); s:fire(S.detail.statusHover,"OnLeave")
for _,case in ipairs({{"listed","Guild","report"},{"listed","Recent Allies","report"},{"checked","Party","check"},{"checked","Raid","check"}}) do
    local record=S.rows[1].record
    record.presenceReport={kind=case[1],online=true,source=case[2]}; S.Select(record); S.Refresh()
    local expected="Last known status. It may have changed."
    for _,hover in ipairs({S.rows[1].statusHover,S.detail.statusHover}) do
        check(hover:IsShown(),"report label exposes hover")
        s:fire(hover,"OnEnter"); check(e.GameTooltip:GetText()==expected,"report tooltip explains freshness")
        s:fire(hover,"OnLeave"); check(not e.GameTooltip:IsShown(),"report tooltip closes")
    end
    s:fire(S.rows[1].statusHover,"OnEnter")
    S.addButton:Click(); check(not e.GameTooltip:IsShown(),"modal clears report tooltip"); form.formCancel:Click()
    s:fire(S.rows[1].statusHover,"OnEnter")
    record.presenceReport=nil; S.Refresh(); check(not e.GameTooltip:IsShown(),"changing status clears old report tooltip")
end
S.rows[1].record.presence="Online"; S.rows[1].record.connectionEvidence="test"; S.Refresh()
s:fire(S.rows[1].statusHover,"OnEnter"); check(not e.GameTooltip:IsShown(),"known presence does not show the Unknown explanation")
S.rows[1].record.presence=nil; S.rows[1].record.connectionEvidence=nil; S.Refresh()
s:fire(S.rows[1].statusHover,"OnEnter"); S.addButton:Click(); check(not e.GameTooltip:IsShown(),"modal opening clears presence tooltip")
s:fire(S.rows[1].statusHover,"OnEnter"); check(not e.GameTooltip:IsShown(),"modal blocks presence hover")
local detailBefore=S.compactDetail; s:fire(S.rows[1].statusHover,"OnClick"); check(S.selectedId==id and S.compactDetail==detailBefore,"modal blocks presence hit selection"); form.formCancel:Click()
S.editButton:Click(); form.formNote:SetText("cancelled"); form.form:Hide()
check(e.WhowhoAddressBookDB.regions[3][id].note=="private note","cancel retains record")
S.editButton:Click(); form.formNote:SetText("edited"); config.time=110; form.formSave:Click()
check(e.WhowhoAddressBookDB.regions[3][id].note=="edited","edit persisted")
local beforeRename=e.WhowhoAddressBookDB
S.editButton:Click(); check(not form.formName:IsEnabled() and not form.formName:HasFocus() and form.formNote:HasFocus() and form.formHint:GetText()=="Name is fixed for this saved character." and form.formName.fieldSkin.texture==p.media.."LedgerDisabled.tga","Edit makes name read-only with explanation")
form.formName:SetFocus(); check(not form.formName:HasFocus(),"disabled name cannot receive focus")
form.formName:SetText("Élan Copper"); form.formSave:Click()
check(form.form:IsShown() and e.WhowhoAddressBookDB==beforeRename,"rename remains unresolved and atomic")
form.form:Hide()
S.addButton:Click(); check(form.formName:IsEnabled() and form.formName:HasFocus() and form.formName.fieldSkin.texture==p.media.."LedgerFocus.tga","Add restores editable name after Edit"); form.formCancel:Click()
config.time=90; S.moveButton:Click()
check(form.form:IsShown() and not form.roleLabel:IsVisible() and not form.roleOptions.HEALER:IsVisible()
    and form.reasonLabel:IsVisible(), "move shows only the inline reasons")
for i,reason in ipairs(p.manual.reasons) do
    local option=form.reasonOptions[reason.id]
    local _,x,y=option:GetPoint()
    check(option:IsVisible() and option.label:GetText()==reason.label and not option.mark:IsShown()
        and option.label:GetUnboundedStringWidth()<option:GetWidth()-24
        and x==((i-1)%2)*202 and y==-25-math.floor((i-1)/2)*25,
        "reason labels fit their inline columns with no initial selection")
end
local beforeMove=e.WhowhoAddressBookDB; form.formSave:Click()
check(form.form:IsShown() and e.WhowhoAddressBookDB==beforeMove, "move without reason cannot commit")
check(form.reasonHelp:IsVisible() and form.reasonHelp:GetText()=="Select at least one reason before saving."
    and form.formError:GetText()=="" and not form.formNote:HasFocus(), "missing reason shows inline validation")
for _,reason in ipairs(p.manual.reasons) do form.reasonOptions[reason.id]:Click() end
for _,reason in ipairs(p.manual.reasons) do
    check(form.reasonOptions[reason.id].mark:IsVisible(), "all eight reasons can be selected together")
end
check(form.form:IsVisible() and e.WhowhoAddressBookDB==beforeMove, "reason selection does not save the move")
for _,reason in ipairs(p.manual.reasons) do
    if reason.id~="griefing" and reason.id~="other" then form.reasonOptions[reason.id]:Click() end
end
check(form.reasonOptions.griefing.mark:IsVisible() and form.reasonOptions.other.mark:IsVisible()
    and not form.reasonOptions.spam.mark:IsVisible() and form.reasonHelp:GetText()=="Select one or more",
    "marks reflect the current draft and selecting a reason clears inline validation")
form.formSave:Click()
check(S.selected.reasonIds[1]=="griefing" and S.selected.reasonIds[2]=="other" and S.selected.note=="edited" and S.selected.role=="HEALER", "move persists multiple reasons, role and note")
check(S.detail.reasons:GetText():find("Griefing, Other",1,true)~=nil, "detail shows persisted reasons")
S.editButton:Click()
check(form.reasonOptions.griefing.mark:IsVisible() and form.reasonOptions.other.mark:IsVisible(),
    "editing loads saved reasons")
form.reasonOptions.griefing:Click(); form.formSave:Click()
check(S.selected.reasonIds[1]=="other" and S.selected.note=="edited", "reason-only edit preserves note")
check(S.section=="blacklist" and e.WhowhoAddressBookDB.regions[3][id].updatedAt==110,"move and clock regression clamp")
check(p.manual.records==recordsReference and S.records==recordsReference, "move retains shared records table")
local old=e.WhowhoAddressBookDB
config.region=4; S.editButton:Click(); form.formNote:SetText("must not save"); form.formSave:Click()
check(form.form:IsShown() and e.WhowhoAddressBookDB==old and old.regions[3][id].note=="edited","region failure atomic and draft retained")
form.form:Hide(); config.region=3
S.rows[1].deleteButton:Click(); check(S.deleteDialog:IsShown(),"confirmation opened")
check(S.deleteHeading:GetText()=="Are you sure to delete?" and S.deleteHeading.justifyH=="CENTER" and S.deleteHeading.fontStyle[2]==16 and S.deleteHeading:GetWidth()==284, "centered delete confirmation heading has room before close")
check(S.deleteMessage:GetText()=="Élan Amber" and S.deleteMessage.justifyH=="CENTER", "centered exact recipient")
local _,nameX,nameY=S.deleteMessage:GetPoint()
check(S.deleteMessage.fontStyle[2]>S.deleteHeading.fontStyle[2] and S.deleteMessage.justifyV=="MIDDLE" and nameX==0 and nameY==-52 and S.deleteMessage:GetHeight()==48, "name leads and is centered between heading and actions")
check(S.deleteMessage.textColor[1]==p.colors.text[1],"unknown class remains neutral")
check(S.deleteDialog:GetWidth()==384 and S.deleteDialog:GetHeight()==160, "compact confirmation dimensions")
local cancelPoint,cancelX,cancelY=S.deleteCancel:GetPoint(); local deletePoint,deleteX,deleteY=S.deleteConfirm:GetPoint()
check(cancelPoint=="BOTTOM" and deletePoint=="BOTTOM" and cancelX==-56 and deleteX==56 and cancelY==deleteY and S.deleteCancel:GetWidth()==100 and S.deleteConfirm:GetWidth()==100, "confirmation actions centered as a group with full targets")
s:fire(S.deleteConfirm,"OnEnter")
check(S.deleteConfirm.rounded=="primary" and not S.deleteConfirm.skin:IsShown()
    and S.deleteConfirm.roundFill[2].vertexColor[1]==p.colors.dangerHover[1]
    and S.deleteConfirm.label.textColor[1]==p.colors.text[1],"destructive capsule keeps readable hover feedback")
s:fire(S.deleteConfirm,"OnLeave"); check(S.deleteConfirm.roundFill[2].vertexColor[1]==p.colors.danger[1],"destructive capsule restores its resting color")
S.deleteCancel:Click(); check(e.WhowhoAddressBookDB.regions[3][id]~=nil,"cancel preserves record")
e.C_ClassColor={GetClassColor=function() return {r=0.2,g=0.3,b=0.4} end}
S.rows[1].record.class="MAGE"; S.rows[1].record.evidenceName="Élan Amber"
S.rows[1].deleteButton:Click(); check(S.deleteMessage.textColor[1]==0.2,"matching verified class uses class color")
S.rows[1].record={id=999,fullName="Other Person",class="MAGE",evidenceName="Other Person"}
check(S.deleteMessage.textColor[1]==0.2 and S.deleteMessage:GetText()=="Élan Amber","rebinding cannot change displayed identity or color")
S.deleteCancel:Click(); S.Refresh()
S.rows[1].record.evidenceName="Different Person"; S.rows[1].deleteButton:Click()
check(S.deleteMessage.textColor[1]==p.colors.text[1],"mismatched class evidence stays neutral"); S.deleteCancel:Click()
S.rows[1].record.evidenceName="Élan Amber"; e.C_ClassColor.GetClassColor=function() return s.secret end
S.rows[1].deleteButton:Click(); check(S.deleteMessage.textColor[1]==p.colors.text[1],"unreadable class color stays neutral"); S.deleteCancel:Click()
S.rows[1].record.class=nil; S.rows[1].record.evidenceName=nil
S.rows[1].deleteButton:Click(); S.deleteDialog:Hide(); check(e.WhowhoAddressBookDB.regions[3][id]~=nil,"escape/close preserves record")
S.rows[1].deleteButton:Click(); S.deleteTarget.fullName="Changed Name"; S.deleteConfirm:Click()
check(not S.deleteConfirm:IsEnabled() and e.WhowhoAddressBookDB.regions[3][id]~=nil,"failed confirmation disables retry and preserves record")
local _,errorX,errorY=S.deleteError:GetPoint()
check(S.deleteDialog:GetHeight()==185 and errorX==0 and errorY==-103 and S.deleteMessage:GetText()=="Élan Amber", "failure has separate room for name, message and actions")
check(S.deleteError.textColor[1]==p.colors.warning[1] and S.deleteError.fontStyle[1]:find("SemiBold",1,true)~=nil
    and not S.deleteConfirm:IsEnabled() and S.deleteConfirm.roundFill[2].vertexColor[1]==p.colors.line[1]
    and S.deleteConfirm.label.textColor[1]==p.colors.muted[1], "failure copy uses warm gold and keeps the destructive action visibly disabled")
S.deleteDialog:Hide()
S.rows[1].deleteButton:Click(); local captured=S.deleteTarget; S.rows[1].record={id=999,fullName="Other Person"}
S.deleteConfirm:Click(); check(e.WhowhoAddressBookDB.regions[3][id]==nil and e.WhowhoAddressBookDB.archived[id].fullName=="Élan Amber","row recycling cannot redirect deletion")
check(p.manual.records==recordsReference and S.records==recordsReference and #recordsReference==0, "delete refreshes shared records table in place")
S.deleteConfirm:Click(); check(e.WhowhoAddressBookDB.archived[id]~=nil,"double confirmation harmless")
local replacement=assert(p.manual.save(nil,"blacklist","Élan Amber","new",nil,{"other"}))
local deleted,issue=p.manual.delete(captured)
check(not deleted and issue and e.WhowhoAddressBookDB.regions[3][replacement.id].note=="new","stale confirmation cannot remove replacement")
local saved=e.WhowhoAddressBookDB
local legacyDB=p.manual.store.export(); legacyDB.regions[3][replacement.id].reasonIds=nil
local lp,ls,le,LS=fresh({region=3,time=120,db=legacyDB}); LS.SetSection("blacklist"); LS.Select(LS.records[1])
check(LS.detail.reasons:GetText():find("No reason recorded. Edit to choose one.",1,true)~=nil and LS.detail.note:GetText():find("new",1,true)~=nil, "legacy reasonless entry and note remain visible")
check(LS.rows[1].note:GetText()=="", "legacy reasonless roster summary is blank")
local invalidDB=p.manual.store.export(); invalidDB.regions[3][replacement.id].reasonIds={"unknown"}
local _,_,_,IS=fresh({region=3,time=120,db=invalidDB}); IS.SetSection("blacklist"); IS.Select(IS.records[1])
check(IS.rows[1].note:GetText()=="" and IS.detail.reasons:GetText():find("Edit to choose a valid reason.",1,true)~=nil, "invalid legacy reasons explain recovery")
local lc=LS.editor.controls; LS.editButton:Click(); lc.formSave:Click()
check(lc.form:IsShown() and le.WhowhoAddressBookDB==legacyDB, "legacy save requires selection")
lc.reasonOptions.other:Click(); lc.formCancel:Click()
check(le.WhowhoAddressBookDB==legacyDB and legacyDB.regions[3][replacement.id].reasonIds==nil, "legacy cancel retains data")
LS.editButton:Click(); lc.reasonOptions.other:Click(); lc.formSave:Click()
check(LS.selected.reasonIds[1]=="other" and LS.selected.note=="new", "legacy recovery uses explicit selection and retains note")
LS.addButton:Click(); lc.formName:SetText("New Person"); local prior=le.WhowhoAddressBookDB; lc.formSave:Click()
check(lc.form:IsShown() and le.WhowhoAddressBookDB==prior, "blacklist Add requires reason")
check(lc.reasonOptions.spam:IsVisible() and not lc.formName:HasFocus(), "missing reason releases name focus with choices visible")
lc.reasonOptions.spam:Click(); lc.formSave:Click()
check(LS.selected.reasonIds[1]=="spam" and LS.detail.reasons:GetText():find("Spam / advertising",1,true)~=nil, "blacklist Add displays persisted reason")
local p2,s2,e2,S2=fresh({region=3,time=120,db=saved})
check(#S2.records==1 and S2.records[1].id==replacement.id,"same-region alt reload")
check(e2.WhowhoAddressBookDB.archived[id].fullName=="Élan Amber","archived identity survives reload")
local p3,s3,e3,S3=fresh({region=4,time=120,db=saved})
check(#S3.records==0,"other region isolated")
do
    local function legacyRecord(id, name, region, membership)
        return {id=id, schemaVersion=1, fullName=name, region=region, membership=membership,
            identityState=region and "resolved" or "unresolved", createdAt=100, updatedAt=100}
    end
    local archiveEnd=1028
    local db={schemaVersion=1, nextId=archiveEnd+1, drafts={[4]=legacyRecord(4,"Unresolved",nil,"friend")},
        regions={
            [3]={[1]=legacyRecord(1,"Alice North",3,"friend"), [2]=legacyRecord(2,"Bea North",3,"blacklist")},
            [4]={[3]=legacyRecord(3,"Carlos North",4,"friend")},
        }, archived={}}
    for i=5,archiveEnd do
        db.archived[i]={id=i, region=3, fullName="Archived "..i, incidentRefs={"incident-"..i}}
    end
    local app,sim,env,shell=fresh({region=3,time=120,db=db})
    local addressBook=app.manual
    local export=addressBook.store.export
    addressBook.store.export=function() error("view refresh exported all SavedVariables") end
    addressBook.refresh(); shell.Refresh()
    addressBook.store.export=export
    check(#shell.records==3 and #shell.filtered==2 and shell.rows[1].record.id==1 and shell.rows[2].record.id==4,
        "refresh renders the current region and global draft without exporting the large archive")
    check(env.WhowhoAddressBookDB==db,"opening and refreshing legacy data leave SavedVariables bound")
    shell.SetSection("blacklist"); shell.rows[1]:Click()
    check(shell.selected.id==2 and shell.detail.reasons:GetText():find("No reason recorded.",1,true),
        "refresh renders the legacy reasonless Blacklist entry")
    local friend=assert(addressBook.store.get(1))
    assert(addressBook.save(friend,"friend",friend.fullName,"updated",nil))
    local published=env.WhowhoAddressBookDB
    check(published~=db and published.schemaVersion==1 and published.nextId==db.nextId
        and published.regions[3][1].note=="updated" and published.regions[3][2].reasonIds==nil,
        "a normal write keeps the legacy schema and format")
    local reopened,reloadSim,_,reloadShell=fresh({region=4,time=121,db=published})
    check(#reloadShell.records==2 and reloadShell.rows[1].record.id==3 and reloadShell.rows[2].record.id==4,
        "after reload another region sees its own character and the same draft")
    local roundTrip=reopened.manual.store.export()
    for i=5,archiveEnd do
        local record=roundTrip.archived[i]
        assert(record.id==i and record.region==3 and record.fullName=="Archived "..i
            and record.incidentRefs[1]=="incident-"..i,"archived record changed after save and reload")
    end
    check(roundTrip.regions[3][1].note=="updated" and sim.forbiddenCalls+reloadSim.forbiddenCalls==0,
        "the other region, archive and current-region edit survive save and reload")
end
local future={schemaVersion=99,marker="keep"}
local p4,s4,e4,S4=fresh({region=3,time=120,db=future})
check(e4.WhowhoAddressBookDB==future and future.marker=="keep" and not S4.addButton:IsEnabled(),"future data preserved and writes disabled")
local p5,s5,e5,S5=fresh({region=nil,time=120,db=saved})
check(not S5.addButton:IsEnabled() and e5.WhowhoAddressBookDB==saved,"unknown region disables writes")
local bad={schemaVersion=1,marker="recover me"}
local p6,s6,e6,S6=fresh({region=3,time=120,db=bad})
check(e6.WhowhoAddressBookDB==bad and bad.marker=="recover me" and not S6.addButton:IsEnabled(),"malformed data retained")
local guardConfig={region=3,time=100}
local p7,s7,e7,S7=fresh(guardConfig)
S7.addButton:Click(); S7.editor.controls.formName:SetText("Test Person"); e7.issecretvalue=function() return true end
S7.editor.controls.formSave:Click()
check(e7.WhowhoAddressBookDB==nil and S7.editor.controls.form:IsShown(),"restricted text or native context cannot save")
e7.issecretvalue=function() return false end; guardConfig.time=nil
S7.editor.controls.formSave:Click()
check(e7.WhowhoAddressBookDB==nil and S7.editor.controls.form:IsShown(),"unavailable clock cannot save")
s:event("PLAYER_LOGOUT"); check(e.WhowhoAddressBookDB==saved,"logout leaves latest committed table bound")
local p8,s8,e8=H.fresh(root,nil,nil,{region=3,time=100,db=saved})
local regionReads=0
e8.GetCurrentRegion=function() regionReads=regionReads+1; error("region read without checker") end
e8.issecretvalue=nil; s8:event("ADDON_LOADED","WhoWho"); check(not p8.initialized,"unreadable event name not inspected")
p8.Toggle(); check(p8.initialized and not p8.Shell.addButton:IsEnabled() and e8.WhowhoAddressBookDB==saved,"slash exposes read-only state without checker")
check(regionReads==0,"missing value checker prevents the region getter call")
e8.issecretvalue=function() error("checker unavailable") end
check(p8.manual.text("Readable spelling")==nil,"throwing value checker rejects text")
local p9,s9,e9,S9=fresh({region=3,time=100},{484,800})
assert(p9.manual.save(nil,"friend","Élan Amber","",nil)); S9.Refresh()
local row=S9.rows[1]
s9:fire(row.statusHover,"OnEnter"); check(e9.GameTooltip:IsShown(),"presence tooltip opens before rebind")
for i=1,6 do assert(p9.manual.save(nil,"friend",("Person%02d Linden"):format(i),"",nil)) end
S9.Refresh()
check(S9.count:IsVisible() and S9.count:GetText()=="1–5 of 7" and S9.refreshNow:IsVisible(), "minimum-width roster shows the visible range beside Refresh rosters")
local function press(widget) s9:fire(widget,"OnMouseDown","LeftButton") end
local function release(widget) s9:fire(widget,"OnMouseUp","LeftButton"); widget:Click() end
local beforeScroll=row.record.id
press(row.statusHover)
s9:fire(S9.list,"OnMouseWheel",-1); check(not e9.GameTooltip:IsShown(),"scroll and row rebinding clear presence tooltip")
check(row.record.id~=beforeScroll,"the scroll rebound the original row")
release(row.statusHover)
check(not S9.selected,"a Presence press cannot select the Friend rebound into the same row")
press(row.statusHover); release(row.statusHover)
check(S9.selectedId==row.record.id,"a new Presence gesture selects the visible Friend")
S9.Select(nil)
s9:fire(S9.list,"OnMouseWheel",1)
check(row.record.id==beforeScroll,"scrolling back restores the first Friend")
press(row.copyButton)
s9:fire(S9.list,"OnMouseWheel",-1)
release(row.copyButton)
check(not S9.copyDialog:IsVisible(),"a Copy press cannot use the Friend rebound into the same row")
press(row.copyButton); release(row.copyButton)
check(S9.copyDialog:IsVisible() and S9.copyBox:GetText()==row.record.fullName,"a new Copy gesture uses the visible Friend")
S9.copyDialog:Hide()
check(S9.count:GetText()=="2–6 of 7", "mouse wheel updates the visible range")
s9:fire(S9.list,"OnMouseWheel",-5); check(S9.count:GetText()=="3–7 of 7", "roster range stops at the final entry")
S9.searchBox:SetText("Élan Amber"); row=S9.rows[1]
check(S9.count:GetText()=="1 of 7 friends", "filtering shows matching and total friends")
local _,copyX=row.copyButton:GetPoint(); local _,inviteX=row.inviteButton:GetPoint(); local _,deleteX=row.deleteButton:GetPoint()
check(copyX-inviteX==36 and deleteX-copyX==36 and row.copyButton:GetWidth()==34 and row.inviteButton:GetWidth()==34 and row.deleteButton:GetWidth()==34,"compact invite, copy, delete actions have separate full hit targets")
local _,statusAnchor,statusEdge,statusGap=row.status:GetPoint(2)
check(statusAnchor==row.inviteButton and statusEdge=="LEFT" and statusGap==-16,"presence clears leftmost action")
row.copyButton:Click(); check(S9.copyBox:GetText()=="Élan Amber","compact Copy retains exact recipient"); S9.copyDialog:Hide()
row.deleteButton:Click(); check(S9.deleteMessage:GetText()=="Élan Amber" and S9.deleteTarget.id==row.record.id,"compact Delete retains exact recipient"); S9.deleteCancel:Click()
row.record.fullName="Alexandrianna Winterweaverton"; row.deleteButton:Click()
check(S9.deleteMessage:GetText()==row.record.fullName and S9.deleteMessage:GetHeight()>48 and S9.deleteDialog:GetHeight()==112+S9.deleteMessage:GetHeight(),"wrapped name receives its full measured height")
S9.deleteTarget.fullName="Stale Name"; S9.deleteConfirm:Click()
local _,_,wrappedErrorY=S9.deleteError:GetPoint()
check(S9.deleteDialog:GetHeight()==137+S9.deleteMessage:GetHeight() and wrappedErrorY==-(55+S9.deleteMessage:GetHeight()),"wrapped name and failure occupy separate space"); S9.deleteCancel:Click()
assert(p9.manual.save(nil,"blacklist","Joan North","Private note",nil,{"spam","other"}))
S9.SetSection("blacklist"); row=S9.rows[1]
check(row.note:IsVisible() and row.note:GetText()=="Spam / advertising, Other" and row.meta:GetText()=="",
    "compact Blacklist lists the saved reasons beneath the name")
check(not row.classMarker:IsShown() and not row.status:IsShown() and not row.statusIcon:IsShown()
    and not row.statusHover:IsShown() and not S9.columnPresence:IsShown(),
    "compact Blacklist omits unsupported class and presence labels")
check(22+row.note:GetWidth()+8==row:GetWidth()+inviteX-row.inviteButton:GetWidth(),
    "Blacklist text leaves a gap before the first row action")
e9.UIParent:SetSize(1920,1200); S9.Layout()
check(row.meta:GetText()=="" and row.note:IsVisible() and row.note:GetText()=="Spam / advertising, Other"
    and not S9.columnPresence:IsShown() and not row.classMarker:IsShown() and not row.status:IsShown(),
    "wide Blacklist shows the same name and reasons without placeholder columns")
check(S9.count:GetPoint()=="LEFT" and not S9.refreshNow:IsVisible(), "wide count returns beside the heading and Blacklist hides Refresh rosters")
row:Click()
local details=S9.detail
check(not S9.checkStatus:IsShown() and not S9.checkStatus:IsEnabled()
    and details.meta:IsShown() and details.meta:GetText()=="Class unknown" and not details.attemptLabel:IsShown()
    and not details.heading:IsShown() and not details.observationLabel:IsShown(),
    "Blacklist details omit Friend status fields and actions")
check(details.reasons:IsVisible() and details.reasons:GetText()=="Spam / advertising, Other"
    and details.note:IsVisible() and details.note:GetText()=="Private note",
    "Blacklist details retain the record reasons")
row.record.source,row.record.observed="Target","2026-11-21 18:20"
S9.Select(row.record)
check(details.observationLabel:IsVisible() and details.observationLabel:GetText()=="Last seen"
    and details.observation:GetText()=="21/11/2026 18:20",
    "Blacklist details retain a dated observation when available")
S9.SetSection("friend")
check(S9.columnPresence:IsShown() and S9.rows[1].status:IsShown() and not S9.checkStatus:IsShown(),
    "returning to the Friends list shows presence and clears the previous record action")
S9.rows[1]:Click()
check(S9.checkStatus:IsShown() and details.meta:IsShown(),"selecting a Friend restores its status control")
e9.UIParent:SetSize(484,800); S9.Layout(); S9.SetSection("friend"); row=S9.rows[1]
check(row.meta:GetText()=="Class unknown" and row.meta:GetWidth()==0, "recycled Friends row keeps its original metadata")
local p10,s10,e10,S10=fresh({region=3,time=100})
e10.UIParent:SetSize(484,800); S10.Layout()
local _,brand,_,gap=S10.revision:GetPoint()
check(24+58+12+brand:GetStringWidth()+gap+S10.revision:GetStringWidth()<=S10.window:GetWidth()-48,"compact header title and revision clear the close button in simulated metrics")
e10.UIParent:SetSize(1920,1200); S10.Layout()
local c=S10.editor.controls
S10.addButton:Click()
local tank, healer=c.roleOptions.TANK,c.roleOptions.HEALER
s10:fire(tank,"OnEnter"); s10:fire(tank,"OnMouseDown","LeftButton")
check(tank.background.color[4]==0 and tank.label.textColor[1]==p10.colors.text[1] and tank.indicator.vertexColor[1]==p10.colors.body[1],"role hover and press brighten content without a row block")
s10:fire(tank,"OnMouseUp","LeftButton"); tank:Click(); healer:Click()
check(not tank.selected and healer.selected and healer.indicator.vertexColor[1]==p10.colors.warning[1],"roles remain exclusive with a visible selected ring")
s10:fire(healer,"OnEnter"); s10:fire(healer,"OnMouseDown","LeftButton")
check(healer.background.color[4]==0 and healer.indicator.vertexColor[1]==p10.colors.warning[1],"selected role keeps its gold ring without a row fill while pressed")
s10:fire(healer,"OnMouseUp","LeftButton"); s10:fire(healer,"OnLeave")
check(healer.background.color[4]==0 and tank.background.color[4]==0,"selected and unselected roles stay clear")
healer:Click(); check(not healer.selected,"clicking the selected role clears it")
s10:fire(tank,"OnLeave"); check(tank.background.color[4]==0 and tank.indicator.vertexColor[1]==p10.colors.muted[1],"role leave restores its resting feedback")
c.formCancel:Click()
S10.addButton:Click(); c.formName:SetText(" \tÉlodie\194\160O'Brie-Mont\r\n"); c.roleOptions.DAMAGER:Click(); c.formNote:SetText("note"); c.formSave:Click()
check(S10.selected.fullName=="Élodie O'Brie-Mont" and S10.selected.role=="DAMAGER" and S10.selected.note=="note","pasted NBSP and outer whitespace save exact token spelling")
check(S10.rows[1].name:GetText()==S10.selected.fullName and S10.rows[1].name:GetWidth()>0 and S10.rows[1].name:GetHeight()==24 and S10.rows[1].name.justifyV=="MIDDLE", "saved row binds visible-sized name")
check(S10.rows[1].name.fontStyle[1]==p10.media.."NotoSans-SemiBold.ttf" and S10.rows[1].name.fontStyle[2]==15 and S10.rows[1].name.textColor[4]==1, "saved name uses the normal readable font and opaque ink")
check(S10.rows[1].role:GetText()=="DPS" and S10.rows[1].note:GetText()=="note", "row retains the chosen role and note")
S10.editButton:Click()
c.formNote:SetText("First paragraph\n\nSecond paragraph"); c.formSave:Click()
check(S10.rows[1].note:GetText()=="First paragraph" and S10.detail.note:GetText()=="First paragraph\n\nSecond paragraph",
    "multiline writing stays complete in detail and fits a single roster line")
S10.rows[1].copyButton:Click(); check(S10.copyBox:GetText()=="Élodie O'Brie-Mont","copy matches normalized saved name"); S10.copyDialog:Hide()
S10.addButton:Click(); c.formName:SetText("Élodie\226\128\175O'Brie-Mont"); local snapshot=e10.WhowhoAddressBookDB; c.formSave:Click()
check(c.form:IsShown() and c.formSave.label:GetText()=="Open existing" and e10.WhowhoAddressBookDB==snapshot,"narrow NBSP duplicate cannot change store")
for _,name in ipairs({"One Two Three", "One\tTwo", "One\nTwo", "One\226\128\139 Two", "One\194\173 Two", "One "..string.char(255).."Two"}) do
    c.formName:SetText(name); c.formSave:Click()
    check(c.form:IsShown() and c.formName:GetText()==name and e10.WhowhoAddressBookDB==snapshot,"invalid name preserves draft and store")
end
c.formName:SetText("  Maëlle\226\128\175D'Arcy  "); c.formSave:Click()
check(S10.selected.fullName=="Maëlle D'Arcy","narrow NBSP accepts another exact two-part name")
S10.addButton:Click(); c.formName:Insert("Ana"); c.formName:Insert(" "); c.formName:Insert("Lune"); c.formSave:Click()
check(S10.selected.fullName=="Ana Lune","simulated typing preserves a normal separator")
S10.addButton:Click(); c.formName:SetText("Élodie O'Brie-Mont"); c.formNote:SetText("not a replacement"); c.formSave:Click()
local beforeOpen=e10.WhowhoAddressBookDB; c.formSave:Click()
check(not c.form:IsShown() and S10.selected.fullName=="Élodie O'Brie-Mont" and S10.selected.note=="First paragraph\n\nSecond paragraph" and e10.WhowhoAddressBookDB==beforeOpen,"Open existing selects exact stored record without overwriting")
S10.addButton:Click(); c.formName:SetText("Élodie O'Brie-Mont"); c.formSave:Click(); c.formCancel:Click()
check(not c.form:IsShown() and e10.WhowhoAddressBookDB==beforeOpen,"Cancel dismisses duplicate without mutation")
S10.addButton:Click(); c.formName:SetText("Élodie O'Brie-Mont"); c.formSave:Click()
for i,record in ipairs(S10.records) do if record.fullName=="Élodie O'Brie-Mont" then S10.records[i]={id=record.id,fullName="Changed Name",region=record.region,guid=record.guid,membership=record.membership}; break end end
c.formSave:Click(); check(c.form:IsShown() and c.formError:GetText()=="Entry changed; search again." and e10.WhowhoAddressBookDB==beforeOpen,"stale duplicate cannot open replacement")
local rp,rs,re,RS=fresh({region=3,time=100},{640,800}); RS.SetSection("blacklist"); RS.addButton:Click()
local rc=RS.editor.controls
local other, spam=rc.reasonOptions.other,rc.reasonOptions.spam
rs:fire(other,"OnEnter"); rs:fire(other,"OnMouseDown","LeftButton")
check(other.background.color[4]==0 and other.label.textColor[1]==rp.colors.text[1] and other.box.vertexColor[1]==1,"reason hover and press brighten content without a row block")
rs:fire(other,"OnMouseUp","LeftButton"); other:Click(); spam:Click()
check(other.mark:IsShown() and spam.mark:IsShown() and re.WhowhoAddressBookDB==nil,"reason choices remain multi-select and unsaved")
other:Click(); spam:Click(); rs:fire(other,"OnLeave")
check(other.background.color[4]==0 and other.box.vertexColor[1]==.9,"reason leave restores its resting feedback")
rc.formNote:SetText(string.rep("Line\n",14))
rc.formNote:SetFocus()
rs:fire(rc.formNote,"OnCursorChanged",0,-180,1,18)
check(rc.noteView:GetVerticalScroll()==198-rc.noteView:GetHeight() and rc.noteView:GetHeight()==130,
    "the enlarged Blacklist writing area follows its caret past the bottom edge")
rc.formName:SetText("Reason Person"); rc.formNote:SetText("keep draft")
local beforeReason=re.WhowhoAddressBookDB
check(rs:routePointer({rc.reasonOptions.other,RS.scrim},"OnClick")==rc.reasonOptions.other,
    "inline reason button owns its click above the modal scrim")
rs:fire(rc.formName,"OnEnterPressed")
check(rc.form:IsShown() and rc.formNote:GetText()=="keep draft" and rc.reasonOptions.other.mark:IsVisible()
    and re.WhowhoAddressBookDB==beforeReason,"name Enter retains the Blacklist draft for explicit Save")
rc.reasonOptions.other:Click(); rc.formSave:Click()
check(rc.form:IsShown() and not rc.reasonOptions.other.mark:IsShown() and re.WhowhoAddressBookDB==beforeReason,
    "deselecting the last reason blocks Save")
rc.reasonOptions.other:Click(); rc.formSave:Click()
check(RS.selected.reasonIds[1]=="other" and RS.selected.note=="keep draft","Save commits the chosen reason and note")
RS.editButton:Click(); rc.reasonOptions.spam:Click(); RS.window:Hide()
check(not rc.reasonOptions.spam:IsVisible() and #RS.selected.reasonIds==1,"window hide discards the unsaved reason")
do
    local config={region=3,time=100}
    local app,sim,env=H.fresh(root,{skipDeleteConfirmation="true"},{484,800},config)
    sim:event("ADDON_LOADED","WhoWho"); app.Toggle()
    local shell,A=app.Shell,app.manual
    local time=100
    env.GetTime=function() return time end
    local first=assert(A.save(nil,"friend","Ari North","private",nil))
    local second=assert(A.save(nil,"friend","Bea North","",nil))
    local blacklist=assert(A.save(nil,"blacklist","Cia North","private",nil,{"other"}))
    shell.Refresh()
    local button=shell.rows[1].deleteButton
    button:Click()
    check(shell.deleteDialog:IsShown() and shell.deleteTarget.id==first.id,"non-boolean preference keeps confirmation")
    shell.deleteCancel:Click()
    check(A.store.get(first.id)~=nil,"cancel preserves the exact entry")
    shell.nav.settings:Click()
    shell.settingsTabs.general:Click()
    local toggle=shell.skipDeleteConfirmation
    local _,x,y=toggle:GetPoint()
    check(toggle:IsVisible() and not toggle:GetChecked() and toggle.state:GetText()=="Off","skip confirmation defaults Off")
    check(x+toggle:GetWidth()<shell.settings:GetWidth() and -y+toggle:GetHeight()<shell.settings:GetHeight(),
        "delete toggle fits the minimum-width Settings panel")
    toggle:Click()
    check(toggle:GetChecked() and toggle.state:GetText()=="On" and env.WhowhoPreviewDB.skipDeleteConfirmation==true,
        "Skip delete confirmation saves the explicit opt-in")
    shell.nav.friend:Click()
    sim:fire(button,"OnMouseDown","LeftButton")
    shell.searchBox:SetText("Bea North")
    button:Click()
    check(A.store.get(first.id) and A.store.get(second.id) and not shell.deleteDialog:IsShown(),
        "a click released on a rebound row removes neither entry")
    shell.searchBox:SetText("")
    local serverTime=env.GetServerTime
    local nested=false
    env.GetServerTime=function()
        if not nested then
            nested=true
            shell.rows[2].deleteButton:Click()
            time=101
        end
        return serverTime()
    end
    A.targetCheck.attempts[first.id]={}
    button:Click()
    env.GetServerTime=serverTime
    check(nested and not A.store.get(first.id) and A.store.get(second.id) and not shell.deleteDialog:IsShown(),
        "one-click deletion removes the pressed Friend and rejects a reentrant click")
    check(not A.targetCheck.attempts[first.id] and env.WhowhoAddressBookDB.archived[first.id].fullName=="Ari North",
        "one-click deletion clears session data and archives the exact identity")
    sim:fire(button,"OnMouseDown","LeftButton"); button:Click()
    check(A.store.get(second.id) and not shell.deleteDialog:IsShown(),
        "a queued second press after a slow delete cannot remove the next Friend")
    time=102
    config.time=nil
    button:Click()
    check(shell.deleteDialog:IsShown() and shell.deleteHeading:GetText()=="Could not delete entry"
        and not shell.deleteConfirm:IsShown() and shell.deleteError:GetText():find("Time unavailable",1,true)
        and shell.deleteMessage:GetText()=="Bea North" and A.store.get(second.id),
        "failed immediate deletion names the entry, shows the error, and offers no destructive action")
    shell.deleteCancel:Click()
    config.time=101
    assert(A.save(A.store.get(second.id),"blacklist","Bea North","",nil,{"other"},true))
    button:Click()
    check(A.store.get(second.id).membership=="blacklist" and shell.deleteError:GetText():find("Record changed",1,true),
        "stale row cannot delete an entry moved to another list")
    shell.deleteCancel:Click(); shell.Refresh()
    local reopened,sim2,env2=H.fresh(root,env.WhowhoPreviewDB,nil,{region=3,time=102,db=env.WhowhoAddressBookDB})
    env2.GetTime=function() return 102 end
    sim2:event("ADDON_LOADED","WhoWho"); reopened.Toggle()
    local view=reopened.Shell
    view.nav.settings:Click()
    view.settingsTabs.general:Click()
    check(view.skipDeleteConfirmation:GetChecked(),"opt-in survives reload")
    view.nav.blacklist:Click()
    view.rows[2].deleteButton:Click()
    check(not reopened.manual.store.get(blacklist.id) and reopened.manual.store.get(second.id)
        and not view.deleteDialog:IsShown(),"reloaded opt-in immediately deletes the exact Blacklist entry")
    view.nav.settings:Click(); view.skipDeleteConfirmation:Click(); view.nav.blacklist:Click()
    view.rows[1].deleteButton:Click()
    check(view.deleteDialog:IsShown() and view.deleteConfirm:IsShown() and view.deleteCancel.label:GetText()=="Cancel",
        "turning the preference Off restores the standard confirmation")
    view.deleteCancel:Click()
    check(env2.WhowhoPreviewDB.skipDeleteConfirmation==false and sim.forbiddenCalls+sim2.forbiddenCalls==0,
        "opt-out persists and neither delete path uses forbidden APIs")
end
check(s.forbiddenCalls+s2.forbiddenCalls+s3.forbiddenCalls+s4.forbiddenCalls+s5.forbiddenCalls+s6.forbiddenCalls+s7.forbiddenCalls+s8.forbiddenCalls+s9.forbiddenCalls+s10.forbiddenCalls+rs.forbiddenCalls==0,"zero forbidden actions")
print("manual address book: "..count.." checks passed")
