local P = WhowhoPreview
local L=P.L
local S = {}
P.Shell = S
local C = P.colors
local D = P.LayoutMetrics
local caseMargins={8,72,8,40}
local roleNames=P.roleNames
local roster,rows=P.RosterModel,P.RosterRows
local paintRevision=0
local guildScope,guildWriteToken
local function guildPage() return S.section=="guildBlacklist" end
local function blacklistPage() return P.manual and (S.section=="blacklist" or guildPage()) end
local function displayText(text) return (text:gsub("|","||")) end
local function guildContext()
    local backend=P.GuildBlacklist
    if backend then return backend.context() end
end
local function guildRecords()
    local token,status,scope=guildContext()
    if not scope then return {},nil,status end

    local backend=P.GuildBlacklist
    local entries=backend.list()
    local peers=token and backend.peerCount and backend.peerCount(token)
    local records={}
    for i,entry in ipairs(entries) do
        local key=P.GuildBlacklistName.Key(entry.name)
        records[i]={id=scope.."\0"..key,scope=scope,searchKey=key,fullName=entry.name,membership="guildBlacklist",
            class=entry.class,reasonIds=entry.reasonIds,note=entry.note and backend.canShareNote(entry.note) and entry.note or nil}
    end
    local checked,checkedStatus,checkedScope=guildContext()
    if checkedScope~=scope then return {},nil,checkedStatus end
    return records,scope,checkedStatus,checked==token and peers or nil,checked
end
local function placeLabel(parent, text, x, y, font, color)
    local label = P.Label(parent, L(text), font, color)
    label:SetPoint("TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    return label
end
local edit=P.Field
local function fieldText(field)
    local value=field:GetText()
    if P.manual then value=P.manual.text(value) end
    return value or ""
end
-- Title and note keep their full text in the existing record. Overflow can be
-- read with the wheel while Back and Edit keep their own places.
local function readable(parent,role,color)
    local view=CreateFrame("ScrollFrame",nil,parent)
    local content=CreateFrame("Frame",nil,view)
    view:SetScrollChild(content)
    local label=placeLabel(content,"",0,0,role,color)
    label:SetWordWrap(true); label:SetNonSpaceWrap(true); label:SetJustifyV("TOP")
    view:SetScript("OnMouseWheel",function(self,delta)
        local limit=math.max(0,content:GetHeight()-self:GetHeight())
        local offset=math.min(limit,math.max(0,self:GetVerticalScroll()-delta*32))
        self:SetVerticalScroll(offset)
        if self.scrollbar then self.scrollbar:SetValue(offset) end
    end)
    view.content=content
    return view,label
end
local function rosterPointerBlocked()
    return S.scrim:IsShown() or (S.filterMenu:IsShown() and S.filterMenu:IsMouseOver())
end
local function selectRow(row)
    local record=row.record
    if not record or not row:IsVisible() or rosterPointerBlocked() then return end
    if guildPage() then
        local revision=paintRevision
        if S.searchBox:HasFocus() then S.searchBox:ClearFocus() end
        local _,_,scope=guildContext()
        if revision~=paintRevision or row.record~=record or not guildPage() or not row:IsVisible()
            or rosterPointerBlocked() then return end
        if scope~=record.scope then S.Refresh(); return end
    end
    S.compactDetail=true
    S.Select(record)
end
local function disabled(parent, text, x, y, width, help)
    local button=P.Button(parent,text,width,34)
    button:SetPoint("TOPLEFT",x,y); P.SetEnabled(button,false)
    P.Tooltip(button, help or "Unavailable in UI Preview / Sample data")
    return button
end
local function colorName(label,record,whiteRosterName,verifiedClass)
    label:SetTextColor(P.NameColor(record,whiteRosterName,verifiedClass))
end
-- A peer can delete and re-add the entry, so its open confirmation closes once it is unlisted.
local function closeStaleGuildDelete()
    local target=S.deleteTarget
    if not (target and target.guild) then return end
    local records,scope,status=guildRecords()
    -- Unsettled membership lists nothing and says nothing about the entry.
    if not scope and status~="no_guild" then return end
    local key=P.GuildBlacklistName.Key(target.name)
    for _,record in ipairs(records) do
        if record.searchKey==key then return end
    end
    S.deleteDialog:Hide()
end
function S.RefreshGuildBlacklist()
    closeStaleGuildDelete()
    if S.editor then S.editor.RefreshGuildShare() end
    if guildPage() and S.window and S.window:IsVisible() then S.Refresh() end
    if S.settings and S.settings.RefreshGuildAvailability then S.settings:RefreshGuildAvailability() end
end
local function requestGuildSync()
    local backend=P.GuildBlacklist
    if guildPage() and S.window:IsVisible() and backend and backend.requestSync then
        backend.requestSync()
        S.RefreshGuildBlacklist()
    end
end
function S.RefreshBlacklistMetadata()
    if S.window and S.window:IsVisible() and S.section=="blacklist" then S.Refresh() end
end
local deleteBusy = false
local function showDeleteError(issue)
    S.deleteDialog:SetHeight(137+S.deleteNameHeight)
    S.deleteError:ClearAllPoints()
    S.deleteError:SetPoint("TOP",0,-(55+S.deleteNameHeight))
    S.deleteError:SetText(L(issue))
end
local function showDeleteDialog(record, target, issue)
    S.deleteTarget=target
    local guild=record.membership=="guildBlacklist"
    S.deleteHeading:SetText(L(issue and "Could not delete entry"
        or guild and "Delete for the whole guild?" or "Are you sure to delete?"))
    S.deleteMessage:SetText(guild and displayText(record.fullName) or record.fullName)
    if guild then
        colorName(S.deleteMessage,nil,true,roster.DisplayClass(record,false))
    else
        local blacklist=record.membership=="blacklist"
        colorName(S.deleteMessage,record,nil,blacklist and roster.DisplayClass(record,true) or nil)
    end
    S.deleteNameHeight=math.max(48,math.ceil(S.deleteMessage:GetStringHeight()))
    S.deleteMessage:SetHeight(S.deleteNameHeight)
    S.deleteDialog:SetHeight(112+S.deleteNameHeight)
    S.deleteError:SetText("")
    S.deleteConfirm:SetShown(not issue)
    P.SetEnabled(S.deleteConfirm,not issue)
    S.deleteCancel.label:SetText(L(issue and "Close" or "Cancel"))
    S.deleteCancel:ClearAllPoints()
    S.deleteCancel:SetPoint("BOTTOM",issue and 0 or -56,12)
    if issue then showDeleteError(issue) end
    S.deleteDialog:Show()
    S.deleteDialog:Raise()
end
local function deleteRecord(target)
    local ok, issue
    if target.guild then
        local called,result=pcall(P.GuildBlacklist.remove,target.name,target.token)
        ok=called and (result=="removed" or result=="missing")
        issue="Deleting is unavailable."
    else
        ok,issue=P.manual.delete(target)
    end
    if ok then S.deleteDialog:Hide(); S.Select(nil) end
    return ok,issue
end
local function quickDeleteTime()
    local now=P.manual.nativeRead.read(GetTime)
    if type(now)=="number" and now==now and now>=0 and now<math.huge then return now end
end
local function renderBlacklistLastSeen(record)
    local A=P.manual
    local ledger=A.encounterLedger
    local store,revision=A.store,ledger.revision()
    local at,zone=ledger.latestBlacklistObservation(record)
    local text=at and P.FormatDate(at)
    if text and zone then text=text.." · "..zone:gsub("|","||") end
    if not text and record and record.source and record.observed then text=P.FormatDate(record.observed) end
    if S.section~="blacklist" or S.selected~=record or A.store~=store or ledger.revision()~=revision then return end
    local d=S.detail
    local shown,value=text~=nil,text or ""
    local changed=d.observation:IsShown()~=shown or d.observation:GetText()~=value
    d.observationLabel:SetText(L("Last seen"))
    d.observationLabel:SetShown(shown)
    d.observation:SetShown(shown)
    d.observation:SetText(value)
    return changed
end
function S.RefreshBlacklistLastSeen()
    if S.section~="blacklist" or not S.details or not S.details:IsVisible() then return end
    if renderBlacklistLastSeen(S.selected) then S.ArrangeRecordText() end
end
local function renderRecord(record, resetScroll)
    local d=S.detail
    if resetScroll then
        d.nameView:SetVerticalScroll(0); d.reasonView:SetVerticalScroll(0); d.noteView:SetVerticalScroll(0)
    end
    local guild,blacklist=guildPage(),blacklistPage()
    P.SetEnabled(S.editButton,not guild and record~=nil and (not P.manual or P.manual.store~=nil))
    S.editButton:SetShown(not guild)
    local draft=record and record.identityState=="unresolved"
    S.checkStatus:SetShown(not blacklist and (not P.manual or record~=nil))
    if P.manual then
        P.SetEnabled(S.checkStatus,P.manual.store~=nil and record~=nil and record.membership=="friend" and not draft)
        S.checkStatus.icon:SetVertexColor(unpack(S.checkStatus:IsEnabled() and C.muted or C.disabled))
    end
    if S.moveButton then
        P.SetEnabled(S.moveButton,not guild and record~=nil and not draft and P.manual.store~=nil)
        S.moveButton:SetShown(not guild)
        S.moveButton.label:SetText(L(record and (record.membership=="friend" and "Blacklist" or "Make friend") or "Move"))
    end
    local attemptWarning=P.manual and record and record.membership=="friend" and not draft and record.attemptWarning
    d.attempt:SetTextColor(unpack(attemptWarning and C.warning or C.body))
    for _,field in ipairs({d.role,d.heading,d.current,d.attemptLabel,d.attempt}) do
        field:SetShown(not blacklist)
    end
    d.meta:SetShown(not blacklist or record~=nil)
    d.rule2:SetShown(not blacklist or record~=nil)
    d.observationLabel:SetShown(not blacklist)
    d.observation:SetShown(not blacklist)
    d.reasonLabel:SetShown(blacklist and record~=nil or false)
    d.reasonView:SetShown(blacklist and record~=nil or false)
    d.reasonLabel:SetText(L(guild and "Shared reasons" or "Reasons"))
    d.noteLabel:SetShown(not blacklist or record~=nil)
    d.noteView:SetShown(not blacklist or record~=nil)
    d.noteLabel:SetText(L(guild and "Shared note" or "Personal note"))
    d.reasons:SetText("")
    if d.affiliation then
        local affiliation=not blacklist and record and (record.faction or record.quickAddFaction) or nil
        if affiliation and record.localChecksOnly then affiliation=affiliation.." · "..L("Local checks only") end
        if blacklist and not guild and record then affiliation=L(record.blacklistFaction or "Unknown") end
        if not blacklist and record and record.ruleset then
            local ruleset=L(record.ruleset)
            affiliation=affiliation and affiliation.." · "..ruleset or ruleset
        end
        d.factionLabel:SetShown(blacklist and not guild and record~=nil or false)
        d.affiliation:SetText(affiliation or "")
        d.affiliation:SetShown(affiliation~=nil)
    end
    if not record then
        rows.BindPresenceHover(d.statusHover,d.statusIcon,d.current,nil,nil)
        d.name:SetText(L(P.manual and "Select a record" or "Select a sample record")); colorName(d.name,nil); d.meta:SetText(""); d.role:SetText(""); d.note:SetText(""); d.current:SetText(""); d.observation:SetText(""); d.attempt:SetText(""); d.icon:Hide(); d.statusIcon:Hide()
        if blacklist and not guild then renderBlacklistLastSeen(nil) end
    else
        local class=roster.DisplayClass(record,blacklist and not guild)
        d.name:SetText(guild and displayText(record.fullName) or record.fullName)
        -- Guild colors rely only on the shared class, while personal rows keep the established white fallback.
        colorName(d.name,not guild and record or nil,true,blacklist and class or nil)
        d.meta:SetText(blacklist and rows.ClassName(class) or L("%s  ·  Level %s",rows.ClassName(class),tostring(record.level or "?")))
        d.role:SetText(blacklist and "" or L(roleNames[record.role] or "No role"))
        local note=record.note and record.note~="" and record.note or L(guild and "No shared note." or "No note")
        d.note:SetText(guild and displayText(note) or note)
        if blacklist then
            local reasons=P.manual.reasonText(record.reasonIds)
            if reasons=="" then
                if guild then reasons=L("No shared reasons.")
                elseif record.reasonIds==nil or (type(record.reasonIds)=="table" and next(record.reasonIds)==nil) then
                    reasons=L("No reason recorded. Edit to choose one.")
                else reasons=L("Edit to choose a valid reason.") end
            end
            d.reasons:SetText(reasons)
            d.icon:Hide(); d.statusIcon:Hide()
            rows.BindPresenceHover(d.statusHover,d.statusIcon,d.current,nil,nil)
            if not guild then renderBlacklistLastSeen(record) end
            return
        end
        local state,caption=roster.Presence(record)
        local observation=record.observed and P.FormatDate(record.observed) or L("No observation")
        d.observationLabel:SetText(L("Last seen"))
        local attempt=P.FormatDate(L(record.attempt or "Not checked"))
        local color,glyph=rows.PresenceStyle(record,state)
        d.current:SetText(L(caption))
        d.current:SetTextColor(unpack(color)); d.observation:SetText(observation); d.attempt:SetText(draft and L("Edit to add the full name.") or attempt)
        if glyph then P.SetGlyph(d.statusIcon,glyph,state=="Online" and C.online or C.muted) end
        d.statusIcon:SetShown(glyph~=nil)
        rows.BindPresenceHover(d.statusHover,d.statusIcon,d.current,record,glyph)
        P.ShowRoleIcon(d.icon,record.role)
    end
end
function S.Select(record)
    P.ClearTooltip()
    S.selected=record; S.selectedId=record and record.id or nil
    S.Refresh(true)
end
local friendsChangedWhileHidden=false
function S.RefreshFriends()
    if not S.window or S.section~="friend" then return end
    if S.window:IsVisible() then S.Refresh() else friendsChangedWhileHidden=true end
end
local function refreshAgedRecords()
    if P.manual.refreshSightingAge() then
        S.RefreshFriends()
        S.RefreshBlacklistMetadata()
    end
end
function S.Refresh(resetSelectionScroll)
    if not S.window then return end
    local guild,blacklist=guildPage(),blacklistPage()
    local personal=blacklist and not guild
    paintRevision=paintRevision+1
    local revision=paintRevision
    local inviteContext=P.manual and S.section=="friend" and P.manual.invite.context()
    local records,scope,status,peers,writeToken=S.records
    if guild then records,scope,status,peers,writeToken=guildRecords() end
    if revision~=paintRevision then return end
    if guild and not scope and S.searchBox:HasFocus() then
        S.searchBox:ClearFocus()
        if revision~=paintRevision then return end
    end
    if guild and scope~=guildScope then
        guildScope=scope
        S.offset=0; S.selected=nil; S.selectedId=nil; S.compactDetail=false
    end
    guildWriteToken=writeToken
    friendsChangedWhileHidden=false
    P.ClearTooltip()
    local query=fieldText(S.searchBox)
    local searchKey
    if guild then
        searchKey=function(text)
            return P.CharacterName.CountScalars(text) and P.GuildBlacklistName.Key(text)
        end
    else
        -- Identity assignment belongs to the mutable fixture collection.
        for i,record in ipairs(records) do if not record.id then record.id="generated-" .. i end end
    end
    local favoriteCount
    S.filtered,favoriteCount=roster.Filter(records,{
        section=S.section, query=query, searchKey=searchKey, roleFilter=not blacklist and S.roleFilter,
        statusFilter=not blacklist and S.statusFilter, classFilter=S.classFilter,
        sortByName=true, descending=not S.sortByName,
        favoritesFirst=P.manual and S.section=="friend", personalBlacklist=personal,
    })
    local anyBlacklist=S.section=="blacklist" or guild
    S.pageTitle:SetText(L(guild and "Guild Blacklist" or personal and "Personal Blacklist" or anyBlacklist and "Blacklist" or "Friends"))
    S.addButton.label:SetText(L(anyBlacklist and (P.manual and "Add entry" or "Add sample") or "Add friend"))
    if P.manual then S.addButton:SetSize(math.max(112,math.ceil(S.addButton.label:GetUnboundedStringWidth())+45),34) end
    if S.guildPeers then
        local showPeers=guild and scope~=nil
        if S.guildPeers:IsShown()~=showPeers then S.facetLayoutDirty=true end
        S.guildPeers:SetText(showPeers and L("WhoWho guildmates detected: %s",type(peers)=="number" and peers or "—") or "")
        S.guildPeers:SetShown(showPeers)
    end
    local active=not guild and S.RefreshFilterMenu(blacklist) or 0
    local inline=P.manual and (S.section=="friend" or S.section=="blacklist")
    for key,link in pairs(S.facetLinks or {}) do
        link:SetShown(inline and (S.section=="friend" or key=="classFilter") or false)
    end
    if inline and not (S.layoutMode=="compact" and S.compactDetail) and not S.list:IsShown() then
        S.list:Show()
        S.facetLayoutDirty=true
    end
    if revision~=paintRevision then return end
    local visibleRows=S.RosterRowCount(); S.visibleRows=visibleRows
    if favoriteCount>0 then visibleRows=math.max(1,visibleRows-1) end
    local state=P.RosterModel.Reconcile(S.filtered,{
        selected=S.selected, selectedId=S.selectedId, revealSaved=S.revealSaved, savedOutside=S.savedOutside,
        offset=S.offset, visibleRows=visibleRows, compactDetail=S.compactDetail,
    })
    local selectionChanged=state.selected~=S.selected
    S.selected=state.selected; S.selectedId=state.selectedId; S.offset=state.offset
    S.revealSaved=state.revealSaved; S.savedOutside=state.savedOutside; S.compactDetail=state.compactDetail
    -- A guild snapshot can replace the selected row while preserving its scoped identity.
    local resetScroll=resetSelectionScroll or (not guild and selectionChanged and S.selected~=nil)
    if resetSelectionScroll or selectionChanged or guild then renderRecord(S.selected,resetScroll) end
    if revision~=paintRevision then return end
    for i,row in ipairs(S.rows) do
        local record=i<=visibleRows and S.filtered[S.offset+i] or nil
        local available,inviteIssue,muted
        if guild then
            available=writeToken~=nil
        elseif personal then
            local mute=P.manual.chatMute
            available=mute.available() and mute.canMute(record)
            muted=available and mute.muted(record)
        elseif inviteContext then
            inviteIssue=P.manual.invite.issue(record,inviteContext)
            available=inviteIssue==nil
        end
        if revision~=paintRevision then return end
        rows.Bind(row,record,S.section,S.selectedId,available,inviteIssue,muted)
    end
    local _,compactCount=S.ArrangeRoster()
    S.ArrangeFavoriteRows(favoriteCount,visibleRows)
    for _,row in ipairs(S.rows) do
        rows.FitName(row,row.note:GetWidth(),not blacklist)
    end
    local total=#S.filtered
    if (compactCount or guild) and total>visibleRows then
        S.count:SetText(L("%d–%d of %d",S.offset+1,math.min(S.offset+visibleRows,total),total))
    elseif P.manual and S.section=="friend" then
        local all=0
        for _,record in ipairs(records) do if record.membership=="friend" then all=all+1 end end
        S.count:SetText(L(all==1 and "%d of %d friend" or "%d of %d friends",total,all))
    else
        S.count:SetText(L(total==1 and "%d character" or "%d characters",total))
    end
    local rosterPage=S.section=="friend" or S.section=="blacklist" or guild
    local noResults=total==0 and rosterPage
    local empty=P.manual and "No matching records" or "No matching sample records"
    if guild then
        if status=="no_guild" then empty="You’re not in a guild. Guild sync is unavailable."
        elseif not scope then empty="Guild Blacklist is unavailable."
        elseif #records==0 then empty="No shared entries from your guild yet." end
    end
    S.emptyLabel:SetText(L(empty)); S.emptyLabel:SetShown(noResults)
    local canSearch=not guild or scope~=nil
    S.searchBox:SetShown(canSearch); S.filterToggle:SetShown(not guild and not inline); S.sortButton:SetShown(canSearch)
    if S.resetFacets then S.resetFacets:SetShown(inline and active>0 or false) end
    if not canSearch then S.filterMenu:Hide() end
    S.clearSearch:SetShown(noResults and canSearch and query~="")
    S.searchClear:SetShown(blacklist and canSearch and not noResults and query~="" or false)
    S.clearFilters:SetShown(noResults and canSearch and active>0)
    if S.guildPeers then
        P.SetEnabled(S.addButton,guild and writeToken~=nil and type(P.GuildBlacklist.add)=="function"
            or (not guild and P.manual.store~=nil))
    end
    S.savedNotice:SetText(L(S.revealReason or "Saved outside current results")); S.savedNotice:SetShown(S.savedOutside==true); S.returnResults:SetShown(S.savedOutside==true)
    S.ArrangeRecordText()
    local compact=S.layoutMode=="compact"
    S.list:SetShown(rosterPage and not (compact and S.compactDetail))
    S.details:SetShown(rosterPage and (not compact or S.compactDetail))
    S.settings:SetShown(S.section=="settings"); S.encounters:SetShown(S.section=="encounters")
    S.backButton:SetShown(rosterPage and compact and S.compactDetail)
    S.addButton:SetShown(rosterPage)
    if S.UpdateBatchRefresh then S.UpdateBatchRefresh() end
    S.searchLabel:SetText(L(anyBlacklist and "Search blacklist" or "Search friends"))
    S.columnInvite:SetText(L(anyBlacklist and "Mute" or "Invite"))
    S.backButton.label:SetText(L(guild and "Back to list" or anyBlacklist and "Back to blacklist" or "Back to friends"))
    S.editButton.label:SetText(L(anyBlacklist and "Edit entry" or "Edit friend"))
    if P.manual then
        S.editButton:SetWidth(math.ceil(S.editButton.label:GetUnboundedStringWidth())+44)
        S.moveButton:SetWidth(math.ceil(S.moveButton.label:GetUnboundedStringWidth())+26)
    end
    S.sortButton.label:SetText(L(S.sortByName and "Character · A–Z" or "Character · Z–A"))
    for key,button in pairs(S.nav) do
        button.selected=key==S.section; P.UpdateButton(button)
        P.Type(button.label,S.navFrame:GetWidth()==D.compactNavWidth and (button.selected and "compactSelected" or "compactNav") or (button.selected and "section" or "nav"))
        button.label:SetTextColor(unpack(button.selected and C.text or C.body))
        P.SetPaletteTint(button.icon,button.selected and C.teal or C.muted)
    end
    if P.manual and S.editor then S.editor.RefreshNameColor() end
end
function S.SetSection(section)
    if S.scrim and S.scrim:IsShown() then return end
    if section==S.section then
        if S.compactDetail and S.layoutMode=="compact" then
            S.compactDetail=false; if S.savedOutside then S.revealSaved=false; S.savedOutside=false; S.Select(nil) else S.Refresh() end
        end
        return
    end
    P.ClearTooltip()
    if S.editor then S.editor.Hide(); S.copyDialog:Hide(); S.filterMenu:Hide() end
    local previous=S.section
    if S.searchBox:HasFocus() then S.searchBox:ClearFocus() end
    if S.section~=previous then return end
    S.pageFilters[S.section]={role=S.roleFilter,class=S.classFilter,status=S.statusFilter,facet=S.filterFacet,
        query=fieldText(S.searchBox),offset=S.offset,selected=not S.savedOutside and S.selected or nil,
        sorted=S.sortByName}
    local filters=S.pageFilters[section] or {}
    S.roleFilter=filters.role; S.classFilter=filters.class; S.statusFilter=filters.status
    S.sortByName=filters.sorted~=false
    S.filterFacet=filters.facet or (section=="friend" and "roleFilter" or "classFilter")
    S.section=section; S.compactDetail=false; S.revealSaved=false; S.savedOutside=false
    S.switchingPage=true
    S.searchBox:SetText(filters.query or "")
    S.switchingPage=false
    S.offset=filters.offset or 0
    S.Select(filters.selected)
    if section=="guildBlacklist" then requestGuildSync() end
end
function S.OpenEncounter(episode,ownsBanner)
    local A=P.manual
    local ledger,store,region=A.encounterLedger,A.store,A.region
    local id,key=episode.id,episode.key
    local function owns()
        return A.nativeRead.read(GetCurrentRegion)==region and A.store==store and A.region==region and ownsBanner()
    end
    if not ownsBanner() then return end
    local now=ledger.now()
    if not owns() or not ledger.matchesGroup(region,now,id,key) then return end
    S.Open()
    if S.scrim:IsShown() or not owns() or not ledger.matchesGroup(region,now,id,key) then return end
    S.SetSection("encounters")
    if S.section=="encounters" and ownsBanner() then S.encounters:Refresh(id,episode,owns) end
end
local function openEncounterBlacklist(row,ownsSelection)
    local ledger=P.manual.encounterLedger
    if not ledger.blacklistRecord(row) or not ownsSelection() or S.scrim:IsShown() then return end
    S.SetSection("blacklist")
    local record=ledger.blacklistRecord(row)
    if not record or not ownsSelection() or S.section~="blacklist" or S.scrim:IsShown() then return end
    S.revealReason="Entry outside current results"
    S.revealSaved,S.savedOutside,S.compactDetail=true,false,true
    S.Select(record)
end
local function createBatchRefreshControls(w,list)
    local help="Checks your group, guild, and Recent Allies. Check status can also try Who for an eligible Friend."
    if P.manual then
        local batch=P.manual.batchRefresh
        S.refreshStatus=placeLabel(w,"",24,-689,"meta",C.warning)
        S.refreshStatus:SetWordWrap(false)
        S.refreshButton=P.Button(list,L("Refresh rosters"),152,34,function(button)
            if S.section~="friend" or not button:IsVisible() or rosterPointerBlocked() then return end
            P.SetEnabled(button,false)
            batch.run()
            S.Refresh()
        end)
        S.refreshNow=S.refreshButton
        P.Tooltip(S.refreshButton,L(help))
        local elapsed=0
        local function tick(_,delta)
            elapsed=elapsed+delta
            if elapsed>=0.25 then
                elapsed=0
                S.UpdateBatchRefresh()
            end
        end
        function S.UpdateBatchRefresh()
            local button=S.refreshButton
            button:SetShown(S.section=="friend")
            if not button:IsVisible() then
                button:SetScript("OnUpdate",nil)
                elapsed=0
                S.refreshStatus:Hide()
                S.footer:Show()
                return
            end
            local busy,seconds,message=batch.state()
            local cooling=seconds and seconds>0
            local caption=busy and L("Refreshing…") or cooling and L("Refresh in %ds",seconds) or L("Refresh rosters")
            if button.label:GetText()~=caption then button.label:SetText(caption) end
            button:SetWidth(math.max(128,math.ceil(button.label:GetUnboundedStringWidth())+42))
            local enabled=seconds~=nil and not busy and not cooling
            if button:IsEnabled()~=enabled then P.SetEnabled(button,enabled) end
            button:SetScript("OnUpdate",cooling and tick or nil)
            local status=L(message or "")
            if S.refreshStatus:GetText()~=status then S.refreshStatus:SetText(status) end
            S.refreshStatus:SetShown(message~=nil)
            S.footer:SetShown(message==nil)
        end
        w:HookScript("OnShow",S.UpdateBatchRefresh)
        w:HookScript("OnShow",function()
            local needsVisibleLayout=S.facetLayoutHidden and S.list:IsVisible()
                and (S.section=="friend" or S.section=="blacklist")
            if needsVisibleLayout then S.facetLayoutDirty=true end
            if needsVisibleLayout or friendsChangedWhileHidden then S.Refresh() end
        end)
        w:HookScript("OnHide",S.UpdateBatchRefresh)
    else
        S.refreshLabel=P.Label(list,L("Manual refresh"),"small",C.muted)
        S.refreshButton=disabled(list,"Refresh rosters",0,0,152,help.." Unavailable in UI Preview / Sample data")
    end
    P.ButtonIcon(S.refreshButton,"refresh")
end
local guildShareNotice
function S.ResetFooter()
    local width=S.window:GetWidth()
    S.footer:SetText(P.manual and L(P.manual.error or "Manual checks use target, group, guild and Recent Allies.")
        or (width<768 and "Sample data · Edits reset on reload. Live actions disabled." or "Sample data · Edits reset on reload. Invitations and status checks are disabled."))
    S.footer:SetTextColor(unpack(P.manual and P.manual.error and C.warning or C.muted))
    guildShareNotice=nil
end
local function showFooter(message)
    local text=L(message)
    S.footer:SetText(text); S.footer:SetTextColor(unpack(C.warning)); S.footer:Show()
    return text
end
local function copyRosterRow(row)
    if not guildPage() and row.record and not rosterPointerBlocked() then S.Copy(row.record) end
end
local favoriting,muting=false,false
local function favoriteRosterRow(row,_,_,press)
    local record=row.record
    if not record or record.membership~="friend" or favoriting or rosterPointerBlocked() then return end
    if press and press.record.favorite~=record.favorite then return end
    favoriting=true
    local saved,issue=P.manual.setFavorite(record,not record.favorite)
    favoriting=false
    if saved then S.Refresh()
    else showFooter(issue) end
end
local function inviteOrMuteRosterRow(row,button,key,press)
    local record=row.record
    if guildPage() or not record then return end
    if S.section=="blacklist" then
        local binding,muted=row.binding,row.chatMuted
        if key~="LeftButton" or muting or (press and (press.binding~=binding or press.muted~=muted)) then return end
        muting=true
        local saved,issue=P.manual.setChatMuted(record,muted,function()
            return button:IsVisible() and not rosterPointerBlocked()
        end,function()
            return S.section=="blacklist" and row.binding==binding and row.chatMuted==muted
        end)
        muting=false
        if saved then S.Refresh(); return end
        showFooter(issue)
        return
    end
    if rosterPointerBlocked() then return end
    local _,message=P.manual.invite.request(record)
    showFooter(message)
end
local function requestGuildDelete(row,record)
    local owner=row.inputOwner
    local token,_,scope=guildContext()
    if row.inputOwner~=owner or not guildPage() or not row:IsVisible() or rosterPointerBlocked() then return end
    if not token or scope~=record.scope then S.Refresh(); return end
    showDeleteDialog(record,{guild=true,name=record.fullName,token=token})
    -- Can refresh and rebind rows at once, so the dialog target is captured first.
    requestGuildSync()
end
local function deleteRosterRow(row,_,_,press)
    local record=row.record
    local guild=guildPage()
    -- Guild records are rebuilt on refresh; bindClick already rejects a press whose row changed entry.
    if not record or (not guild and press and press.record~=record) or deleteBusy or rosterPointerBlocked() then return end
    if guild then
        deleteBusy=true
        requestGuildDelete(row,record)
        deleteBusy=false
        return
    end
    local target={id=record.id,region=record.region,fullName=record.fullName,guid=record.guid,membership=record.membership}
    deleteBusy=true
    if P.db.skipDeleteConfirmation then
        local now=quickDeleteTime()
        if row.record==record and not rosterPointerBlocked() then
            local last=row.lastQuickDelete
            if not now then
                showDeleteDialog(record,target)
            elseif last==true or (last and now<last) then
                row.lastQuickDelete=now
            elseif not last or now-last>=0.5 then
                -- A second click on this button can hit a different entry after the row rebinds.
                local ok,issue=deleteRecord(target)
                if ok then row.lastQuickDelete=quickDeleteTime() or true else showDeleteDialog(record,nil,issue) end
            end
        end
    else
        showDeleteDialog(record,target)
    end
    deleteBusy=false
end
local function lookupSavedBlacklistClass(record)
    if not P.manual.whoLookup.canCheckBlacklist(record) then return end
    local notified, previousText
    local function notify(subject,message)
        notified=true
        if S.window:IsVisible() and S.section=="blacklist" and S.selected and roster.SameIdentity(S.selected,subject)
            and S.selected.updatedAt==subject.updatedAt and (not previousText or S.footer:GetText()==previousText) then
            previousText=showFooter(message)
        end
    end
    local message=P.manual.whoLookup.requestBlacklist(record,notify)
    S.RefreshBlacklistMetadata()
    if message or not notified then notify(record,message or "Who check unavailable.") end
end
local function shareGuildBlacklist(saved,scope,approval)
    local backend=P.GuildBlacklist
    if not approval or not backend or not P.manual.store then return "unavailable" end
    local record=P.manual.store.get(saved.id)
    if not record or record.region~=saved.region or record.fullName~=saved.fullName
        or record.guid~=saved.guid or record.membership~="blacklist" then return "unavailable" end
    local ok,result=pcall(backend.share,record,scope,approval)
    return ok and result or "unavailable"
end
local guildAddErrors={
    limit="Guild Blacklist is full.",
    invalid_name="Enter two name parts separated by a space.",
    invalid_reasons="Select at least one reason before saving.",
    invalid_note="This note cannot be shared with your guild.",
    self="You can't add your current character.",
}
local function saveGuildBlacklist(name,reasons,sharedNote,scope,alsoPersonal,note,ownsSave)
    local backend=P.GuildBlacklist
    local A=P.manual
    local region=A.region
    local unavailable="Guild Blacklist is unavailable."
    if not backend or not backend.add then return nil,unavailable end
    local personal
    local function ownsPersonal()
        if not personal then return true end
        local current=A.store and A.store.get(personal.id)
        return current and current.region==personal.region and current.fullName==personal.fullName
            and current.guid==personal.guid and current.membership=="blacklist"
    end
    local function ownsGuild()
        if ownsSave and not ownsSave() then return false end
        local current,status=backend.context()
        local nativeRegion=A.nativeRead.read(GetCurrentRegion)
        return nativeRegion==region and A.region==region and (not ownsSave or ownsSave())
            and current==scope and status=="ready" and guildPage() and S.editor.IsShown()
            and S.list:IsVisible() and ownsPersonal()
    end
    if not ownsGuild() then return nil,unavailable end
    local personalSaved=false
    if alsoPersonal then
        local existing=A.store and A.store.find(A.region,name)
        if existing and existing.membership~="blacklist" then return nil,"Uncheck personal Blacklist or remove the Friends entry first." end
        personal=existing
        if not ownsGuild() then return nil,unavailable end
        if not existing then
            local saved,issue=A.save(nil,"blacklist",name,note,nil,reasons,nil,nil,ownsGuild)
            if not saved then return nil,issue end
            personal=saved
        end
        personalSaved=true
    end
    local ok,result
    if ownsGuild() then ok,result=pcall(backend.add,name,reasons,sharedNote,scope,ownsGuild) end
    if ok and (result=="shared" or result=="unchanged") then
        S.RefreshGuildBlacklist()
        return true
    end
    if personalSaved and ownsPersonal() then
        return nil,result=="limit" and "Saved to your Blacklist. Guild list full."
            or "Saved to your Blacklist. Guild sharing unavailable."
    end
    return nil,guildAddErrors[result] or unavailable
end
function S.Create()
    if S.window then return end
    S.records = P.manual and P.manual.records or P.NewFixtures(); local classEvidence={}; S.pageFilters={}; S.section = "friend"; S.offset = 0; S.sortByName=true; S.rows = {}; S.nav = {}
    if not P.manual then
        for _, record in ipairs(S.records) do
            if record.class and record.evidenceName then classEvidence[record.evidenceName]={class=record.class,level=record.level} end
        end
    end
    local w = CreateFrame("Frame", "WhowhoPreviewWindow", UIParent)
    S.window = w; w:SetSize(D.windowWidth,D.windowHeight); w:SetPoint("CENTER"); w:SetFrameStrata("DIALOG"); w:SetToplevel(true); w:SetMovable(true); w:SetClampedToScreen(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", function(self) self:StartMoving() end)
    w:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); local point, _, relativePoint, x, y = self:GetPoint(); P.db.position={point=point, relativePoint=relativePoint, x=x, y=y} end)
    w:SetScript("OnMouseDown", function(self) self:Raise() end)
    if P.manual then
        local ageElapsed=0
        w:HookScript("OnUpdate",function(_,elapsed)
            ageElapsed=ageElapsed+elapsed
            if ageElapsed<1 then return end
            ageElapsed=0
            refreshAgedRecords()
        end)
    end
    w:SetScript("OnHide", function() P.ClearTooltip(); if S.editor then S.editor.Hide(); S.copyDialog:Hide(); if S.deleteDialog then S.deleteDialog:Hide() end; S.filterMenu:Hide(); S.settings:CancelScale() end end)
    P.TintCaseMaterial(P.Material(w,"Case",caseMargins))
    local rim=CreateFrame("Frame",nil,w); rim:SetAllPoints(w); rim:SetFrameLevel(w:GetFrameLevel()+3)
    P.Material(rim,"Rim",{16,10,8,8})
    if P.db.position then local p=P.db.position; w:ClearAllPoints(); w:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y) end
    w:SetScale(P.db.scale or 1); w:Hide()
    table.insert(UISpecialFrames, "WhowhoPreviewWindow")
    local badge = w:CreateTexture(nil, "ARTWORK"); badge:SetSize(58,58); badge:SetPoint("TOPLEFT",24,-7); badge:SetTexture(P.media.."MascotBadge.tga")
    local brand=P.Label(w,"WhoWho","brand",C.gold); brand:SetPoint("LEFT",badge,"RIGHT",12,0)
    S.revision=P.Label(w,P.version,"meta",C.muted); S.revision:SetPoint("LEFT",brand,"RIGHT",12,0)
    local headerRule=w:CreateTexture(nil,"BORDER"); headerRule:SetPoint("TOPRIGHT",-57,-21); headerRule:SetSize(1,30); headerRule:SetColorTexture(unpack(C.line))
    S.closeButton=P.Button(w,"",36,36,function() w:Hide() end,"action"); S.closeButton:SetPoint("TOPRIGHT",-12,-18); P.ButtonIcon(S.closeButton,"close",25)
    local nav=CreateFrame("Frame",nil,w); S.navFrame=nav
    P.Material(nav,"Rail")
    local railTint=nav:CreateTexture(nil,"BACKGROUND",nil,1)
    railTint:SetAllPoints(nav); railTint:SetAlpha(.62)
    P.SetPaletteFill(railTint,C.railTint)
    P.PaneEdge(nav,"RIGHT")
    local sections={{"friend","Friends","friends"},{"blacklist","Blacklist","blacklist"},{"encounters","Encounters","encounters"},{"settings","Settings","settings"}}
    if P.manual then table.insert(sections,3,{"guildBlacklist","Guild Blacklist","blacklist","Guild\nBlacklist"}) end
    for i,item in ipairs(sections) do
        local button=P.Button(nav,L(item[2]),140,38,function() S.SetSection(item[1]) end,"nav")
        button.caption=item[2]; button.compactCaption=item[4]
        button.icon=P.Glyph(button,item[3],22,C.muted); button.index=i
        S.nav[item[1]]=button
    end
    local list=CreateFrame("Frame",nil,w); S.list=list; list:SetPoint("TOPLEFT",D.wideNavWidth,-D.headerHeight); list:SetSize(D.windowWidth-D.wideNavWidth-D.wideDetailWidth,D.paneHeight); P.Paint(list,C.panel)
    S.rosterHeader=P.PageHeader(list,65)
    S.pageTitle=placeLabel(list,"Friends",24,-23,"page",C.text)
    S.count=P.Label(list,"","small",C.muted); S.count:SetHeight(34); S.count:SetJustifyV("MIDDLE"); S.count:SetWordWrap(false)
    if P.manual then
        S.guildPeers=placeLabel(list,"",24,-64,"meta",C.muted)
        S.guildPeers:Hide()
    end
    S.searchBox=edit(list,310,36); S.searchBox:SetPoint("TOPLEFT",24,-78)
    S.searchBox:SetScript("OnTextChanged",function(self)
        if S.searchLabel then S.searchLabel:SetShown(fieldText(self)=="" and not self:HasFocus()) end
        if S.switchingPage then return end
        S.offset=0; S.revealSaved=false; S.savedOutside=false; S.Refresh()
    end)
    S.searchBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    S.searchBox:SetTextInsets(36,12,4,4); S.searchIcon=P.Glyph(S.searchBox,"search",20,C.muted); S.searchIcon:SetPoint("LEFT",10,0)
    S.searchLabel=placeLabel(S.searchBox,"Search friends",36,-10,"small",C.muted)
    S.searchClear=P.Button(S.searchBox,"",28,28,function()
        if not rosterPointerBlocked() then S.searchBox:SetText("") end
    end,"action")
    S.searchClear:SetPoint("RIGHT",-4,0); P.ButtonIcon(S.searchClear,"close",16)
    P.Tooltip(S.searchClear,L("Clear search")); S.searchClear:Hide()
    S.searchBox:HookScript("OnEditFocusGained",function() S.searchLabel:Hide() end)
    S.searchBox:HookScript("OnEditFocusLost",function(self) S.searchLabel:SetShown(fieldText(self)=="") end)
    S.addButton=P.Button(list,L("Add friend"),136,P.manual and 34 or 36,function(self)
        if not self:IsVisible() or rosterPointerBlocked() then return end
        if guildPage() then
            local expected,revision=guildWriteToken,paintRevision
            if S.searchBox:HasFocus() then S.searchBox:ClearFocus() end
            local token,status=guildContext()
            if not expected or token~=expected or status~="ready" then S.Refresh(); return end
            if revision==paintRevision and guildPage() and self:IsVisible() and not rosterPointerBlocked() then
                S.editor.Open(nil,"blacklist",nil,nil,nil,token)
            end
            return
        end
        if P.manual and S.section=="blacklist" then
            local A = P.manual
            local store,region=A.store,A.region
            local name,guid=A.playerAddIdentity("target",store,region)
            local evidence,changed
            if name then evidence,changed=A.captureBlacklistMetadata("target",store,region,name,guid,"Target") end
            if S.scrim:IsShown() or S.section~="blacklist" then return end
            if name and not changed then S.editor.OpenForPlayer("blacklist",name,evidence); return end
        end
        S.editor.Open(nil,S.section,fieldText(S.searchBox),#S.filtered==0)
    end,"Primary"); S.addButton:SetPoint("TOPRIGHT",-24,-25); P.ButtonIcon(S.addButton,"plus")
    P.CreateRosterFilters(list,S)
    S.emptyLabel=placeLabel(list,P.manual and "No matching records" or "No matching sample records",40,-175,"body",C.muted)
    S.clearSearch=P.Button(list,L("Clear search"),120,30,function() S.searchBox:SetText("") end); S.clearSearch:SetPoint("TOPLEFT",40,-205)
    S.sortButton=P.Button(list,L("Character · A–Z"),190,30,function()
        if S.scrim:IsShown() or S.filterMenu:IsShown() then return end
        S.sortByName=not S.sortByName
        S.offset=0
        S.Refresh()
    end,"action")
    S.sortButton:SetPoint("TOPLEFT",32,-118)
    P.Type(S.sortButton.label,"column")
    S.sortButton.label:ClearAllPoints()
    S.sortButton.label:SetPoint("LEFT",8,0)
    S.sortCaret=P.ActionGlyph(S.sortButton,"caret",14,C.muted)
    S.sortCaret:SetPoint("LEFT",S.sortButton.label,"RIGHT",6,0)
    S.columnPresence=placeLabel(list,"Presence",369,-123,"column",C.muted)
    S.columnCopy=P.Label(list,L("Copy"),"column",C.muted); S.columnCopy:SetPoint("TOP",list,"TOPRIGHT",-87,-123)
    S.columnInvite=P.Label(list,L("Invite"),"column",C.muted); S.columnInvite:SetPoint("TOP",list,"TOPRIGHT",-43,-123)
    if P.manual then S.columnCopy:Hide(); S.columnInvite:Hide() end
    S.rosterRule=P.Rule(list,24,149,24); P.Rule(list,24,556,24)
    if P.manual then
        S.favoriteHeading=P.Label(list,L("Favorites"),"section",C.gold)
        S.otherFriendsHeading=P.Label(list,L("Other Friends"),"section",C.muted)
        S.favoriteHeading:Hide(); S.otherFriendsHeading:Hide()
    end
    S.rows=rows.Create(list,{
        blocked=rosterPointerBlocked, select=selectRow, copy=copyRosterRow,
        favorite=favoriteRosterRow, inviteOrMute=inviteOrMuteRosterRow, delete=deleteRosterRow,
    })
    list:EnableMouseWheel(true); list:SetScript("OnMouseWheel",function(_, delta) if not rosterPointerBlocked() then S.offset=S.offset-delta; S.Refresh() end end)
    S.footer=placeLabel(w,"Sample edits reset on reload. Invitations and status checks are disabled.",24,-689,"meta",C.muted)
    createBatchRefreshControls(w,list)
    local details=CreateFrame("Frame",nil,w); S.details=details; details:SetPoint("TOPLEFT",D.windowWidth-D.wideDetailWidth,-D.headerHeight); details:SetSize(D.wideDetailWidth,D.paneHeight); S.detailsPaper=P.Material(details,"Paper"); S.blacklistDetailsBackground=P.Paint(details,C.raised)
    S.blacklistDetailsBackground:Hide(); P.PaneEdge(details,"LEFT")
    S.backButton=P.Button(details,L("Back"),90,32,function() S.compactDetail=false; if S.savedOutside then S.revealSaved=false; S.savedOutside=false; S.Select(nil) else S.Refresh() end end)
    P.ButtonIcon(S.backButton,"back"); S.backButton:Hide()
    S.savedNotice=placeLabel(details,"Saved outside current results",24,-485,"small",C.muted)
    S.returnResults=P.Button(details,L("Return to results"),138,34,function() S.revealSaved=false; S.savedOutside=false; S.compactDetail=false; S.Select(nil) end); S.returnResults:SetPoint("BOTTOMLEFT",24,70)
    local d={}; S.detail=d
    d.noteEdge,d.noteFill=P.NoteInset(details)
    d.nameView,d.name=readable(details,"record",C.text)
    d.meta=placeLabel(details,"",25,-64,"body",C.body)
    if P.manual then
        d.affiliation=placeLabel(details,"",25,-88,"small",C.muted)
        d.affiliation:Hide()
        d.factionLabel=placeLabel(details,"Faction",25,0,"small",C.muted); d.factionLabel:Hide()
    end
    d.role=P.Label(details,"","body",C.body); d.role:SetHeight(24); d.role:SetPoint("LEFT",d.meta,"RIGHT",32,0); d.role:SetJustifyH("LEFT")
    d.icon=P.RoleIcon(details,d.role,18,4)
    d.reasonLabel=placeLabel(details,"Reasons",25,0,P.manual and "small" or "section",P.manual and C.muted or C.text)
    d.reasonView,d.reasons=readable(details,"body",C.body)
    d.noteView,d.note=readable(details,"body",C.body)
    if P.manual then
        local bar=CreateFrame("Slider",nil,details)
        bar:SetOrientation("VERTICAL"); bar:SetWidth(12)
        bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        P.SetPaletteTint(bar:GetThumbTexture(),C.controlBorder)
        bar:SetScript("OnValueChanged",function(_,value) d.noteView:SetVerticalScroll(value) end)
        bar:Hide(); d.noteView.scrollbar=bar
    end
    d.heading=placeLabel(details,"Presence",25,-177,P.manual and "small" or "section",P.manual and C.muted or C.text)
    d.statusIcon=P.Glyph(details,"unknown",20,C.muted); d.statusIcon:Hide()
    if P.manual then
        d.statusHover=CreateFrame("Frame",nil,details); d.statusHover:SetSize(28,28); d.statusHover:SetPoint("CENTER",d.statusIcon,"CENTER"); d.statusHover:EnableMouse(true)
        d.statusHover:SetScript("OnEnter",function(self) local hint=S.selected and rows.PresenceHint(S.selected); if hint and not rosterPointerBlocked() then P.ShowTooltip(self,hint) end end)
        d.statusHover:SetScript("OnLeave",function(self) P.HideTooltip(self) end)
    end
    d.current=placeLabel(details,"",49,-215,P.manual and "body" or "presence",C.body)
    d.current:SetHeight(24); d.current:SetJustifyV("MIDDLE")
    d.statusIcon:SetPoint("RIGHT",d.current,"LEFT",-4,0)
    d.observationLabel=placeLabel(details,"Last seen",25,-248,"small",C.muted)
    d.observation=placeLabel(details,"",116,-247,"body",C.body)
    d.attemptLabel=placeLabel(details,"Last check",25,-274,"small",C.muted)
    d.attempt=placeLabel(details,"",116,-273,"body",C.body)
    d.noteLabel=placeLabel(details,"Personal note",25,-336,P.manual and "small" or "section",P.manual and C.muted or C.text)
    d.rule1=P.Rule(details,25,160,25); d.rule2=P.Rule(details,25,319,25)
    S.editButton=P.Button(details,L("Edit friend"),126,34,function() if S.selected and not guildPage() and not rosterPointerBlocked() then S.editor.Open(S.selected,S.section,fieldText(S.searchBox),#S.filtered==0) end end)
    S.editButton:SetPoint("BOTTOMLEFT",25,23); P.ButtonIcon(S.editButton,"edit")
    if P.manual then
        S.moveButton=P.Button(details,L("Move"),112,34,function()
            if not S.selected or guildPage() or rosterPointerBlocked() then return end
            if S.selected.membership=="friend" then S.editor.Open(S.selected,"blacklist",fieldText(S.searchBox),false,true); return end
            local moved, issue=P.manual.move(S.selected)
            if not moved then showFooter(issue); return end
            S.SetSection(moved.membership); S.revealSaved=true; S.Select(moved)
        end)
        S.moveButton:SetPoint("BOTTOMRIGHT",-25,23)
        P.SetEnabled(S.addButton,P.manual.store~=nil)
    end
    if P.manual then
        S.checkStatus=P.Button(details,L("Check status"),32,32,function()
            local record=S.selected
            if not record or record.membership~="friend" then return end
            local message=P.manual.checkFriend(record)
            S.Refresh(); renderRecord(S.selected,false); S.ArrangeRecordText(); showFooter(message)
        end,"action")
        S.checkStatus.label:Hide()
        local icon=S.checkStatus:CreateTexture(nil,"ARTWORK")
        icon:SetTexture(P.media.."LedgerStatusRefresh.tga","CLAMP","CLAMP","LINEAR")
        icon:SetSize(22,22); icon:SetPoint("CENTER")
        S.checkStatus.icon=icon
        S.checkStatus:HookScript("OnEnter",function(self)
            if S.selected and S.selected.localChecksOnly then
                P.ShowTooltip(self,L("Who can't look up this player from your faction. Target them to check what's visible."))
            else
                P.ShowTooltip(self,L("Checks local sources, then tries Who for this saved Friend."))
            end
        end)
        S.checkStatus:HookScript("OnLeave",function(self) P.HideTooltip(self) end)
    else
        S.checkStatus=disabled(details,"Check status",0,0,132)
        S.checkStatus:SetHeight(32)
        P.ButtonIcon(S.checkStatus,"refresh")
    end
    if P.manual then
        P.RoundButton(S.addButton,true)
        P.RoundButton(S.refreshButton)
        P.RoundButton(S.editButton)
        P.RoundButton(S.moveButton)
    end
    S.settings=P.CreateSettings(w,S)
    if P.manual then
        S.encounters=P.CreateEncounterLedger(w,openEncounterBlacklist,rosterPointerBlocked)
    else
        S.encounters=P.CreateEncounters(w,S.records)
    end
    S.scrim=CreateFrame("Frame",nil,w)
    S.scrim:SetAllPoints(w)
    -- Keep the scrim above the filter menu's child choices as well as its triggers.
    S.scrim:SetFrameLevel(S.filterMenu:GetFrameLevel()+2)
    S.scrim:EnableMouse(true); S.scrim:EnableMouseWheel(true)
    S.scrim:SetScript("OnMouseWheel",function() end)
    local dim=P.Material(S.scrim,"Case",caseMargins)
    dim:SetVertexColor(0,0,0,.70)
    S.scrim:Hide()
    S.copyDialog=P.CreateDialog(w,"WhowhoPreviewCopyDialog",S.scrim); S.copyDialog:SetSize(456,184)
    placeLabel(S.copyDialog,"Copy name",24,-16,"record",C.text)
    S.copyBox=edit(S.copyDialog,408,36); S.copyBox:SetPoint("TOPLEFT",24,-58)
    P.BindPalette(S.copyBox,function(box) box:SetHighlightColor(unpack(C.selection)) end)
    placeLabel(S.copyDialog,"Press Ctrl+C to copy the selected name.",24,-111,"small",C.muted)
    S.copyDialog:SetScript("OnShow",function() P.ClearTooltip(); S.filterMenu:Hide(); S.scrim:Show() end)
    S.copyDialog:SetScript("OnHide",function() S.copyBox:ClearFocus(); if not S.editor or not S.editor.IsShown() then S.scrim:Hide() end end); S.copyBox:SetScript("OnEscapePressed",function() S.copyDialog:Hide() end); S.copyBox:SetScript("OnEnterPressed",function() S.copyDialog:Hide() end)
    if P.manual then
        S.deleteDialog=P.CreateDialog(w,"WhowhoPreviewDeleteDialog",S.scrim); S.deleteDialog:SetSize(384,160)
        S.deleteHeading=P.Label(S.deleteDialog,L("Are you sure to delete?"),"record",C.text); P.FontSize(S.deleteHeading,16); S.deleteHeading:SetPoint("TOP",0,-14); S.deleteHeading:SetSize(284,24); S.deleteHeading:SetJustifyH("CENTER")
        S.deleteMessage=P.Label(S.deleteDialog,"","record",C.text); S.deleteMessage:SetPoint("TOP",0,-52); S.deleteMessage:SetSize(336,48); S.deleteMessage:SetJustifyH("CENTER"); S.deleteMessage:SetJustifyV("MIDDLE"); S.deleteMessage:SetWordWrap(true); S.deleteMessage:SetNonSpaceWrap(true)
        S.deleteError=P.Label(S.deleteDialog,"","action",C.warning); S.deleteError:SetSize(336,25); S.deleteError:SetJustifyH("CENTER"); S.deleteError:SetWordWrap(true)
        S.deleteDialog:SetScript("OnShow",function() P.ClearTooltip(); S.filterMenu:Hide(); S.scrim:Show() end)
        S.deleteDialog:SetScript("OnHide",function() S.deleteTarget=nil; if not S.editor or not S.editor.IsShown() then S.scrim:Hide() end end)
        S.deleteConfirm=P.Button(S.deleteDialog,L("Delete"),100,34,function()
            local target=S.deleteTarget; if not target or deleteBusy then return end
            S.deleteTarget=nil
            P.SetEnabled(S.deleteConfirm,false)
            deleteBusy=true
            local ok, issue=deleteRecord(target)
            if not ok then showDeleteError(issue) end
            deleteBusy=false
        end,"Destructive"); S.deleteConfirm:SetPoint("BOTTOM",56,12)
        S.deleteCancel=P.Button(S.deleteDialog,L("Cancel"),100,34,function() S.deleteDialog:Hide() end); S.deleteCancel:SetPoint("BOTTOM",-56,12)
        P.RoundButton(S.deleteConfirm,true); P.RoundButton(S.deleteCancel)
        local close=P.Button(S.deleteDialog,"",34,34,function() S.deleteDialog:Hide() end,"action"); close:SetPoint("TOPRIGHT",-10,-10); P.ButtonIcon(close,"close",20)
    end
    local copyClose=P.Button(S.copyDialog,L("Close"),100,30,function() S.copyDialog:Hide() end); copyClose:SetPoint("BOTTOMRIGHT",-24,12)
    if P.manual then P.RoundButton(copyClose) end
    S.editor=P.EditorDialog.Create(w,{
        backdrop=S.scrim,
        records=S.records, classEvidence=classEvidence, save=P.manual and P.manual.save,
        saveGuild=P.manual and saveGuildBlacklist,
        onShow=function()
            if guildShareNotice and S.footer:GetText()==guildShareNotice then S.ResetFooter() end
            P.ClearTooltip(); S.filterMenu:Hide(); S.scrim:Show()
        end,
        onHide=function() if not S.copyDialog:IsShown() then S.scrim:Hide() end end,
        onSaved=function(record,guildScope,approval,lookupClass)
            local result=guildScope and shareGuildBlacklist(record,guildScope,approval)
            if S.section~=record.membership then S.SetSection(record.membership) end
            S.revealReason="Saved outside current results"; S.revealSaved=true; S.savedOutside=false; S.Select(record)
            if lookupClass then S.ResetFooter(); lookupSavedBlacklistClass(record) end
            if result and result~="shared" and result~="unchanged" then
                local message=result=="limit" and "Saved to your Blacklist. Guild list full."
                    or result=="deleted" and "Saved to your Blacklist. Deleted from guild list."
                    or "Saved to your Blacklist. Guild sharing unavailable."
                guildShareNotice=showFooter(message)
            end
        end,
        onOpenDuplicate=function(target)
            if S.section~=target.membership then S.SetSection(target.membership) end
            S.revealReason="Existing record outside current results"; S.revealSaved=true; S.savedOutside=false; S.compactDetail=true; S.Select(target)
        end,
    })
    S.Layout(); S.Select(S.records[1])
end
function S.Open()
    S.Create()
    local reopening=not S.window:IsShown()
    S.window:Show(); S.window:Raise()
    if P.manual then refreshAgedRecords() end
    if P.manual then S.RefreshBlacklistMetadata(); S.RefreshBlacklistLastSeen() end
    if P.manual and S.section=="encounters" then S.encounters:Refresh() end
    S.RefreshGuildBlacklist()
    if reopening then requestGuildSync() end
end
function S.OpenPlayerAdd(section, name, evidence, owns)
    S.Open()
    if (owns and not owns()) or S.scrim:IsShown() then return end
    S.SetSection(section)
    if owns and (not owns() or S.section~=section or S.scrim:IsShown()) then return end
    S.editor.OpenForPlayer(section,name,evidence,true)
end
function S.Toggle() S.Create(); if S.window:IsShown() then S.window:Hide() else S.Open() end end
function S.Copy(record)
    if not record or record.membership=="guildBlacklist" or record.identityState=="unresolved" or S.scrim:IsShown() then return end
    S.copyBox:SetText(record.fullName); S.copyDialog:Show(); S.copyDialog:Raise(); S.copyBox:SetFocus(); S.copyBox:HighlightText(0,-1)
end
