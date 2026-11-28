local P = WhowhoPreview
local L=P.L
local C = P.colors
local Name = P.CharacterName
P.EditorDialog = {}
local roles={"TANK","HEALER","DAMAGER"}
local function placeLabel(parent, text, x, y, font, color)
    local label = P.Label(parent, L(text), font, color)
    label:SetPoint("TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    return label
end
local edit=P.Field
local function noteField(parent, width, height)
    local view=CreateFrame("ScrollFrame",nil,parent)
    view:SetSize(width,height); view:EnableMouse(true); view:EnableMouseWheel(true)
    local box=edit(view,width,1,true)
    view:SetScrollChild(box)
    view:SetScript("OnMouseDown",function(_,button) if button=="LeftButton" then box:SetFocus() end end)
    local function wheel(_,delta)
        local limit=view:GetVerticalScrollRange()
        view:SetVerticalScroll(math.max(0,math.min(limit,view:GetVerticalScroll()-delta*24)))
    end
    view:SetScript("OnMouseWheel",wheel); box:EnableMouseWheel(true); box:SetScript("OnMouseWheel",wheel)
    box:SetScript("OnCursorChanged",function(self,_,y,_,lineHeight)
        if not self:HasFocus() then return end
        local top=-y
        local offset=view:GetVerticalScroll()
        local height=view:GetHeight()
        if top<offset then view:SetVerticalScroll(math.max(0,top))
        elseif top+lineHeight>offset+height then view:SetVerticalScroll(top+lineHeight-height) end
    end)
    view:SetScript("OnScrollRangeChanged",function(self,_,limit)
        if self:GetVerticalScroll()>limit then self:SetVerticalScroll(limit) end
    end)
    return box,view
end

local function choiceHelp(parent, heading, text)
    local help=P.Label(parent,L(text),"small",C.muted)
    help:SetPoint("LEFT",heading,"RIGHT",10,0)
    return help
end

local function paintChoice(button)
    local active=button:IsEnabled() and button.hovered
    button.background:SetColorTexture(unpack(C.clear))
    button.label:SetTextColor(unpack(active and C.text or button:IsEnabled() and C.body or C.muted))
    if button.indicator then
        button.indicator:SetVertexColor(unpack(button.selected and C.warning or active and C.body or C.muted))
    elseif button.box then
        local tint=active and 1 or button:IsEnabled() and .9 or .6
        button.box:SetVertexColor(tint,tint,tint,1)
    end
end

local function bindChoiceFeedback(button)
    button.paintFeedback=paintChoice
    for _, event in ipairs({"OnEnter","OnLeave","OnHide","OnMouseDown","OnMouseUp"}) do
        button:HookScript(event,paintChoice)
    end
    paintChoice(button)
end

-- Owns the draft and widgets; the shell coordinates the dialog and its selection.
function P.EditorDialog.Create(parent, options)
    local editor={controls={}}
    local controls=editor.controls
    local draft={}
    local savingGuild=false
    local savingForm=false
    local formRevision=0
    local w=parent
    local nameColorRevision,paintingName=0,false
    local function currentRecord(target)
        for _, current in ipairs(options.records) do
            if current.id==target.id and current.fullName==target.fullName and current.region==target.region and current.guid==target.guid then
                return current
            end
        end
    end
    local function nameClass(name,store,region)
        local A=P.manual
        if not store or region~=draft.region or not Name.IsComplete(name) then return end
        local evidence=draft.addEvidence
        if evidence and (evidence.name~=name or evidence.region~=region) then evidence=nil end
        local saved,issue=store.find(region,name,evidence and evidence.guid)
        if issue=="conflict" then return end
        if saved and draft.formRecord then
            local original=draft.formRecord
            if saved.id~=original.id or saved.guid~=original.guid or saved.membership~=original.membership then return end
        end
        local observed=evidence and (evidence.observation or evidence)
        if observed and observed.class then
            if observed.source=="chat" or observed.source=="Chat menu" then
                local current=A.playerEvidence.refreshChat(observed,store,region)
                if current then return current.class,observed end
            elseif A.playerEvidence.refreshCaptured(observed,name,store,region) then
                return observed.class,observed
            elseif evidence.store==store and (not observed.current or observed.current()) then
                return observed.class,observed
            end
        end
        if A.recordsStore~=store then return end
        local current=saved and currentRecord(saved)
        if not current or current.identityState~="resolved" or current.membership~=saved.membership then return end
        local blacklist=current.membership=="blacklist"
        if blacklist or current.evidenceName==name then
            return P.RosterModel.DisplayClass(current,blacklist),current
        end
    end
    local function paintName()
        nameColorRevision=nameColorRevision+1
        local pass=nameColorRevision
        local wasPainting=paintingName
        paintingName=true
        local A,field=P.manual,controls.formName
        local store,region=A.store,A.region
        local name=field:GetText()
        name=A.text(name)
        local class,owner=nameClass(name,store,region)
        local r,g,b,a=P.NameColor(nil,nil,class)
        if class then
            local currentRegion=A.nativeRead.read(GetCurrentRegion)
            local checkedClass,checkedOwner=nameClass(name,A.store,A.region)
            if currentRegion~=region or A.store~=store or A.region~=region or checkedClass~=class or checkedOwner~=owner then
                r,g,b,a=P.NameColor()
            end
        end
        paintingName=wasPainting
        if nameColorRevision==pass then field:SetTextColor(r,g,b,a) end
    end
    local function clearDuplicate()
        draft.duplicateTarget=nil
        if controls.formSave then controls.formSave.label:SetText(L("Save")); controls.formSave:SetWidth(94) end
        if controls.formCancel then controls.formCancel:ClearAllPoints(); controls.formCancel:SetPoint("BOTTOMRIGHT",-130,24) end
    end
    controls.form=P.CreateDialog(w,"WhowhoPreviewForm",options.backdrop); controls.form:SetSize(440,570); controls.formTitle=placeLabel(controls.form,"",24,-19,"record",C.text)
    local actionRule=P.Rule(controls.form,24,497,24)
    controls.formHint=placeLabel(controls.form,"Manual address book.",24,-52,"small",C.muted)
    controls.nameLabel=placeLabel(controls.form,"Full character name (required)",24,-80,"section",C.text)
    controls.formName=edit(controls.form,392,38); controls.formName:SetPoint("TOPLEFT",24,-104)
    controls.formName:SetScript("OnTextChanged",function()
        formRevision=formRevision+1
        if draft.nameLoading then return end
        if draft.nameError then draft.nameError=false; clearDuplicate(); controls.formError:SetText("") end
        paintName()
    end)
    local roleGroup=CreateFrame("Frame",nil,controls.form)
    roleGroup:SetSize(392,70)
    roleGroup:SetPoint("TOPLEFT",24,-154)
    controls.roleLabel=placeLabel(roleGroup,"Role",0,0,"section")
    choiceHelp(roleGroup,controls.roleLabel,"Optional. Select again to clear.")
    controls.roleOptions={}
    local function updateRoles()
        for role, button in pairs(controls.roleOptions) do
            local selected=draft.formRoleValue==role
            button.selected=selected
            button.indicator:SetTexCoord(selected and .5 or 0,selected and 1 or .5,0,1)
            paintChoice(button)
        end
    end
    for i, role in ipairs(roles) do
        local button=P.Button(roleGroup,L(P.roleNames[role]),108,30,function(self)
            if not self:IsVisible() then return end
            formRevision=formRevision+1
            if draft.formRoleValue==role then draft.formRoleValue=nil else draft.formRoleValue=role end
            updateRoles()
        end,"row")
        button:SetPoint("TOPLEFT",(i-1)*122,-25)
        P.ButtonContent(button,26,0,"LEFT")
        P.Type(button.label,"body")
        local indicator=button:CreateTexture(nil,"ARTWORK")
        indicator:SetTexture(P.media.."LedgerRadio.tga")
        indicator:SetSize(19,19)
        indicator:SetPoint("LEFT",1,0)
        button.indicator=indicator
        bindChoiceFeedback(button)
        controls.roleOptions[role]=button
    end
    local reasonGroup
    local reasonPrompt="Select one or more"
    local function updateReasonHelp(missing)
        controls.reasonHelp:SetText(L(missing and "Select at least one reason before saving." or reasonPrompt))
        controls.reasonHelp:SetTextColor(unpack(missing and C.warning or C.muted))
    end
    local function updateReason(button, selected)
        button.mark:SetShown(selected)
        button.box:SetTexture(P.media..(selected and "LedgerPrimary.tga" or "LedgerField.tga"))
    end
    local function styleCheckbox(button)
        local box=CreateFrame("Frame",nil,button)
        box:SetSize(17,17)
        box:SetPoint("LEFT",1,0)
        button.box=P.Material(box,"Field",{4,4,4,4})
        button.mark=P.Glyph(box,"online",16,C.text)
        button.mark:SetPoint("CENTER")
    end
    do
        reasonGroup=CreateFrame("Frame",nil,controls.form)
        reasonGroup:SetSize(392,128)
        reasonGroup:SetPoint("TOPLEFT",24,-154)
        controls.reasonLabel=placeLabel(reasonGroup,"Reasons",0,0,"section")
        controls.reasonHelp=choiceHelp(reasonGroup,controls.reasonLabel,reasonPrompt)
        controls.reasonOptions={}
        for i, reason in ipairs(P.manual.reasons) do
            local button=P.Button(reasonGroup,L(reason.label),190,24,function(self)
                if not self:IsVisible() then return end
                formRevision=formRevision+1
                local selected=not draft.selectedReasons[reason.id]
                draft.selectedReasons[reason.id]=selected
                updateReason(self,selected)
                updateReasonHelp(false)
            end,"row")
            button:SetPoint("TOPLEFT",((i-1)%2)*202,-25-math.floor((i-1)/2)*25)
            P.ButtonContent(button,23,1,"LEFT")
            P.Type(button.label,"small")
            styleCheckbox(button)
            bindChoiceFeedback(button)
            controls.reasonOptions[reason.id]=button
        end
    end
    local noteLabel=placeLabel(controls.form,"Personal note (optional)",24,-222,"section")
    controls.formCounter=P.Label(controls.form,"0 / 256","meta",C.muted)
    controls.formNote,controls.noteView=noteField(controls.form,392,196)
    controls.formError=placeLabel(controls.form,"",24,-453,"action",C.warning); controls.formError:SetWidth(392); controls.formError:SetWordWrap(true)
    local guildChoice,guildHelp,guildNoteHelp
    local function guildContext()
        if not P.GuildBlacklist then return end
        local scope,status=P.GuildBlacklist.context()
        if status=="ready" then return scope end
    end
    local function noteShareable(note)
        local backend=P.GuildBlacklist
        return backend and backend.canShareNote and backend.canShareNote(note)==true
    end
    local function arrangeGuildChoice()
        if not guildChoice then return end
        local note=draft.noteAccepted or ""
        local visible=guildChoice:IsShown()
        local unavailable=draft.shareGuild and note:find("%S")~=nil and not noteShareable(note)
        local helpHeight=visible and math.ceil(guildHelp:GetStringHeight()) or 0
        guildNoteHelp:ClearAllPoints()
        guildNoteHelp:SetPoint("TOPLEFT",47,-(483+helpHeight))
        guildNoteHelp:SetShown(unavailable==true)
        local extra=visible and 34+helpHeight or 0
        if unavailable then extra=extra+math.ceil(guildNoteHelp:GetStringHeight())+4 end
        controls.form:SetHeight(570+extra)
        controls.formError:ClearAllPoints()
        controls.formError:SetPoint("TOPLEFT",24,-453-extra)
        actionRule:ClearAllPoints()
        actionRule:SetPoint("TOPLEFT",24,-497-extra)
        actionRule:SetPoint("TOPRIGHT",-24,-497-extra)
    end
    local function setGuildShare(scope,checked)
        if not guildChoice then return end
        draft.guildScope,draft.shareGuild=scope,scope~=nil and checked==true
        local direct=draft.directGuildScope~=nil
        local visible=direct or scope~=nil
        local selected=direct and draft.alsoPersonal==true or draft.shareGuild
        guildChoice.label:SetText(L(direct and "Also add to personal Blacklist" or "Also add to Guild Blacklist"))
        guildHelp:SetText(L(direct and "Saves name, reasons and note to Guild Blacklist." or "Shares name, class, reasons and note with your guild."))
        guildChoice:SetEnabled(not direct or P.manual.store~=nil)
        guildChoice:SetShown(visible)
        guildHelp:SetShown(visible)
        guildChoice:SetChecked(selected)
        updateReason(guildChoice,selected)
        paintChoice(guildChoice)
        arrangeGuildChoice()
    end
    do
        local function checkbox(caption,x,y,width)
            local choice=CreateFrame("CheckButton",nil,controls.form)
            choice:SetSize(width,25)
            choice:SetPoint("TOPLEFT",x,y)
            choice.label=P.Label(choice,L(caption),"small",C.body)
            choice.background=P.Paint(choice,C.clear)
            P.ButtonContent(choice,23,1,"LEFT")
            styleCheckbox(choice)
            P.BindButtonFeedback(choice,paintChoice)
            return choice
        end
        guildChoice=checkbox("Also add to Guild Blacklist",24,-453,392)
        controls.guildShare=guildChoice
        guildHelp=placeLabel(controls.form,"",47,-480,"small",C.muted)
        guildNoteHelp=placeLabel(controls.form,"This note can only be saved privately.",47,-498,"small",C.muted)
        for _,label in ipairs({guildHelp,guildNoteHelp}) do label:SetWidth(369); label:SetWordWrap(true) end
        guildChoice:SetScript("OnClick",function(self)
            if not self:IsVisible() or not self:IsEnabled() then return end
            formRevision=formRevision+1
            if draft.directGuildScope then
                draft.alsoPersonal=not draft.alsoPersonal
                setGuildShare(nil)
                return
            end
            local scope=guildContext()
            setGuildShare(scope,scope==draft.guildScope and not draft.shareGuild)
        end)
        setGuildShare(nil)
    end
    function editor.RefreshGuildShare()
        if not controls.form:IsVisible() or not draft.canShareGuild then return end
        local scope=guildContext()
        if scope~=draft.guildScope then setGuildShare(scope,false) end
    end
    local errorHover=CreateFrame("Frame",nil,controls.form); errorHover:SetAllPoints(controls.formError); errorHover:EnableMouse(true)
    errorHover:SetScript("OnEnter",function(self) if draft.duplicateTarget then P.ShowTooltip(self,controls.formError:GetText()) end end); errorHover:SetScript("OnLeave",function(self) P.HideTooltip(self) end)
    controls.formNote:SetScript("OnTextChanged",function(self)
        formRevision=formRevision+1
        if draft.noteLoading then return end
        local value=self:GetText(); value=P.manual.text(value); value=value or ""; local count=Name.CountScalars(value)
        if not count or (count>256 and value~=draft.noteOriginal) then
            draft.noteLoading=true; self:SetText(draft.noteAccepted or ""); draft.noteLoading=false
            self:SetCursorPosition(draft.noteCursor or 0)
            local accepted=Name.CountScalars(draft.noteAccepted or "") or 0
            draft.nameError=false; clearDuplicate()
            controls.formError:SetText(L("Note unchanged; %d characters fit.",math.max(0,256-accepted)))
        else
            draft.noteAccepted=value; draft.noteCursor=self:GetCursorPosition()
            controls.formCounter:SetText(tostring(count) .. " / 256")
            if not draft.nameError then controls.formError:SetText("") end
            arrangeGuildChoice()
        end
    end)
    controls.form:SetScript("OnShow",function() formRevision=formRevision+1; options.onShow() end)
    controls.form:SetScript("OnHide",function()
        formRevision=formRevision+1
        nameColorRevision=nameColorRevision+1
        draft.addEvidence=nil
        draft.playerMenuName=nil
        draft.canShareGuild=nil
        draft.directGuildScope,draft.alsoPersonal=nil,nil
        setGuildShare(nil)
        controls.formName:ClearFocus(); controls.formNote:ClearFocus(); clearDuplicate(); options.onHide()
    end)
    local function escapeForm() controls.form:Hide() end
    controls.formName:SetScript("OnEscapePressed",escapeForm); controls.formNote:SetScript("OnEscapePressed",escapeForm)
    local function readForm()
        local name=controls.formName:GetText(); local note=controls.formNote:GetText()
        name=P.manual.text(name); note=P.manual.text(note)
        if not name or not note then controls.formError:SetText(L("Text unavailable; no changes saved.")); return end
        local enteredName=name
        local count=Name.CountScalars(note)
        local mayDraft=draft.formSection=="friend" and not draft.moving
        if draft.formRecord and draft.formRecord.identityState~="unresolved" then
            if name~=draft.formRecord.fullName then controls.formError:SetText(L("Name is fixed for this saved character.")); return end
        else name=Name.NormalizeManual(name,mayDraft) end
        if not name then draft.nameError=true; controls.formError:SetText(L("Enter two name parts separated by a space.")); controls.formName:SetFocus(); return end
        if not count or (count>256 and note~=draft.noteOriginal) then controls.formError:SetText(L("Note must be valid text of at most 256 characters.")); return end
        local reasons
        if draft.formSection=="blacklist" then
            reasons={}; for _, reason in ipairs(P.manual.reasons) do if draft.selectedReasons[reason.id] then reasons[#reasons+1]=reason.id end end
            if not P.manual.validReasons(reasons) then
                controls.formError:SetText("")
                updateReasonHelp(true)
                controls.formName:ClearFocus(); controls.formNote:ClearFocus()
                return
            end
        end
        return name,note,enteredName,reasons
    end
    local function showDuplicate(name)
        local complete=Name.IsComplete(name)
        local editingId=draft.formRecord and draft.formRecord.id
        for _, existing in ipairs(options.records) do if complete and existing.identityState~="unresolved"
            and existing~=draft.formRecord and (not editingId or existing.id~=editingId) and existing.fullName==name then
            draft.nameError=true; draft.duplicateTarget={id=existing.id,fullName=existing.fullName,region=existing.region,guid=existing.guid}
            controls.formError:SetText(L(existing.membership=="blacklist" and "Already in Blacklist: %s" or "Already in Friends: %s",existing.fullName))
            controls.formSave.label:SetText(L("Open existing"))
            local actionWidth=math.max(112,math.ceil(controls.formSave.label:GetUnboundedStringWidth())+16)
            controls.formSave:SetWidth(actionWidth)
            controls.formCancel:ClearAllPoints(); controls.formCancel:SetPoint("BOTTOMRIGHT",-(actionWidth+36),24)
            controls.formName:SetFocus(); return true
        end end
        return false
    end
    local function saveForm()
        local inputRevision=formRevision
        if savingGuild or not controls.form:IsShown() then return end
        if draft.duplicateTarget then
            local target=draft.duplicateTarget
            local currentName=controls.formName:GetText()
            currentName=P.manual.text(currentName); if currentName then currentName=Name.NormalizeManual(currentName) end
            if currentName==target.fullName then
                local current=currentRecord(target)
                if current then controls.form:Hide(); options.onOpenDuplicate(current); return end
            end
            clearDuplicate(); draft.nameError=true; controls.formError:SetText(L("Entry changed; search again.")); return
        end
        local evidence=draft.addEvidence
        local name,note,enteredName,reasons=readForm()
        if not name then return end
        local original=draft.formRecord
        local section,role,moving,formRegion=draft.formSection,draft.formRoleValue,draft.moving,draft.region
        local guildScope=draft.shareGuild and draft.guildScope or nil
        local directScope,alsoPersonal=draft.directGuildScope,draft.alsoPersonal
        local function ownsSave()
            if not controls.form:IsShown() or formRevision~=inputRevision or draft.addEvidence~=evidence
                or draft.region~=formRegion or P.manual.region~=formRegion or draft.formSection~=section
                or draft.formRecord~=original or draft.formRoleValue~=role or draft.moving~=moving
                or (draft.shareGuild and draft.guildScope or nil)~=guildScope or draft.directGuildScope~=directScope or draft.alsoPersonal~=alsoPersonal or draft.duplicateTarget then return false end
            if reasons then
                local index=1
                for _, reason in ipairs(P.manual.reasons) do
                    if draft.selectedReasons[reason.id] then
                        if reasons[index]~=reason.id then return false end
                        index=index+1
                    end
                end
                if index~=#reasons+1 then return false end
            end
            return true
        end
        if draft.directGuildScope then
            local sharedNote=note:find("%S") and note or nil
            if sharedNote and not noteShareable(sharedNote) then
                controls.formError:SetText(L("This note cannot be shared with your guild.")); return
            end
            local scope=draft.directGuildScope
            savingGuild=true
            local saved, issue=options.saveGuild(name,reasons,sharedNote,scope,alsoPersonal,note,ownsSave)
            savingGuild=false
            if not ownsSave() then return end
            if saved then controls.form:Hide(); return end
            controls.formError:SetText(L(issue)); return
        end
        if showDuplicate(name) then return end
        do
            local quickAdd=evidence and evidence.quickAdd
            local lookupClass=draft.formSection=="blacklist" and not draft.moving and draft.playerMenuName~=name and not quickAdd
            if lookupClass and original then
                local current=currentRecord(original)
                lookupClass=not (original.blacklistSavedClass or original.blacklistWhoClass
                    or current and current.membership=="blacklist" and (current.blacklistSavedClass or current.blacklistWhoClass))
            end
            local saveEvidence=evidence
            if quickAdd and enteredName~=evidence.name then saveEvidence={quickAdd=true,source=evidence.source} end
            local approval
            if guildScope and guildContext()==guildScope and draft.shareGuild and draft.guildScope==guildScope then
                approval={reasonIds={}}
                for i,id in ipairs(reasons) do approval.reasonIds[i]=id end
                if noteShareable(note) then approval.note=note end
            end
            local saved, issue=options.save(original,section,name,note,role,reasons,moving,saveEvidence,ownsSave)
            if ownsSave and not ownsSave() then return end
            if not saved then controls.formError:SetText(L(issue)); return end
            controls.form:Hide(); options.onSaved(saved,guildScope,approval,lookupClass); return
        end
    end
    controls.formSave=P.Button(controls.form,L("Save"),94,34,function()
        if savingForm then return end
        savingForm=true
        local wasSavingGuild=savingGuild
        local ok, issue=pcall(saveForm)
        savingForm=false
        if not ok then
            if not wasSavingGuild then savingGuild=false end
            error(issue,0)
        end
    end,"Primary"); controls.formSave:SetPoint("BOTTOMRIGHT",-24,24)
    controls.formName:SetScript("OnEnterPressed",function()
        if draft.formSection~="blacklist" then controls.formSave:Click() end
    end)
    controls.formCancel=P.Button(controls.form,L("Cancel"),86,34,function() controls.form:Hide() end); controls.formCancel:SetPoint("BOTTOMRIGHT",-130,24)
    P.RoundButton(controls.formSave,true); P.RoundButton(controls.formCancel)

    local function open(record, section, query, noResults, moving, directGuildScope, name, evidence, fromPlayerMenu)
        if savingGuild then return end
        if directGuildScope and (controls.form:IsShown() or guildContext()~=directGuildScope or controls.form:IsShown()) then return end
        formRevision=formRevision+1
        draft.formRecord = record; draft.formSection=section; draft.formRoleValue=record and record.role or nil; draft.moving=moving
        draft.region=P.manual.region
        draft.addEvidence=evidence
        draft.playerMenuName=fromPlayerMenu and name or nil
        local blacklist=section=="blacklist"
        draft.directGuildScope,draft.alsoPersonal=directGuildScope,false
        draft.canShareGuild=blacklist and not directGuildScope and (not record or moving)
        roleGroup:SetShown(not blacklist)
        updateRoles()
        local hasReasons=blacklist
        local noteY=hasReasons and -290 or -222
        noteLabel:SetText(L(directGuildScope and "Shared note (optional)" or "Personal note (optional)"))
        noteLabel:ClearAllPoints(); noteLabel:SetPoint("TOPLEFT",24,noteY)
        controls.formCounter:ClearAllPoints(); controls.formCounter:SetPoint("TOPRIGHT",-24,noteY-3)
        controls.noteView:ClearAllPoints(); controls.noteView:SetPoint("TOPLEFT",24,hasReasons and -316 or -250)
        controls.noteView:SetHeight(hasReasons and 130 or 196)
        do
            reasonGroup:SetShown(blacklist)
            draft.selectedReasons={}
            if blacklist and record and not moving and P.manual.validReasons(record.reasonIds) then
                for _, id in ipairs(record.reasonIds) do draft.selectedReasons[id]=true end
            end
            for id, button in pairs(controls.reasonOptions) do
                updateReason(button,draft.selectedReasons[id]==true)
            end
            updateReasonHelp(false)
            local editable=not record or record.identityState=="unresolved"
            controls.nameLabel:SetText(L(blacklist and "Full character name (required)" or "Character name (required)"))
            if not editable then controls.formName:ClearFocus() end
            P.SetFieldEnabled(controls.formName,editable)
            local hint="Name is fixed for this saved character."
            if moving then hint="Choose reasons to move this friend to Blacklist."
            elseif blacklist and record and not P.manual.validReasons(record.reasonIds) then
                hint="Select reasons to replace missing or unrecognized values."
            elseif editable then hint=blacklist and "Manual address book." or "One name part saves an unresolved draft." end
            controls.formHint:SetText(L(hint))
        end
        draft.noteLoading=true
        controls.formTitle:SetText(L(directGuildScope and "Add Guild Blacklist entry" or moving and "Move to Blacklist" or (section=="blacklist" and (record and "Edit entry" or "Add entry") or (record and "Edit friend" or "Add friend"))))
        local candidate=name or ""
        if not record and noResults then
            local full=Name.NormalizeManual(query)
            if full then
                local exists=false; for _, existing in ipairs(options.records) do if existing.fullName==full then exists=true; break end end
                if not exists then candidate=full end
            end
        end
        draft.nameError=false; clearDuplicate()
        draft.nameLoading=true
        controls.formName:SetText(record and record.fullName or candidate)
        draft.nameLoading=false
        controls.formNote:SetText(record and (record.note or "") or ""); controls.noteView:SetVerticalScroll(0)
        local initialNote=P.manual.text(controls.formNote:GetText())
        draft.noteAccepted=initialNote or ""; draft.noteOriginal=draft.noteAccepted; draft.noteCursor=controls.formNote:GetCursorPosition(); draft.noteLoading=false
        controls.formCounter:SetText(tostring(Name.CountScalars(draft.noteAccepted) or 0) .. " / 256")
        setGuildShare(draft.canShareGuild and guildContext() or nil,P.db.guildBlacklistDefaultWithNote)
        controls.formError:SetText(""); controls.form:Show(); controls.form:Raise()
        if record and record.identityState~="unresolved" then controls.formNote:SetFocus() else controls.formName:SetFocus() end
        if name then controls.formName:SetCursorPosition(#name) end
        paintName()
    end
    function editor.Open(record,section,query,noResults,moving,directGuildScope)
        open(record,section,query,noResults,moving,directGuildScope)
    end
    function editor.OpenForPlayer(section, name, evidence, fromPlayerMenu)
        if not Name.IsComplete(name) then return end
        open(nil,section,nil,nil,nil,nil,name,evidence,fromPlayerMenu)
    end
    function editor.RefreshNameColor()
        if not paintingName and controls.form:IsVisible() then paintName() end
    end
    function editor.Hide() controls.form:Hide() end
    function editor.IsShown() return controls.form:IsShown() end
    return editor
end
