-- Simulated with the installed TOC. The guild API is a local fixture.
local root=arg[1] or "."
local H=dofile(root.."/tests/addon/harness.lua")

local function fresh(preferences,viewport,locale)
    local p,s,e=H.fresh(root,preferences,viewport,{region=3,time=100})
    local target={name="Élodie Brisevent",class="MAGE"}
    e.UnitClass=function() return "Mage",target.class end
    e.GetLocale=function() return locale or "enUS" end
    e.UnitExists=function() return target.name~=nil end
    e.UnitIsPlayer=function() return target.name~=nil end
    e.GetUnitName=function() return target.name end
    e.GetNumGroupMembers=function() return 0 end
    e.C_FriendList={}
    e.C_Timer={}
    e.UnitGUID=function() return "target-guid" end
    e.UnitClassBase=function() return target.class end
    e.InCombatLockdown=function() return false end
    e.UnitFactionGroup=function() return "Alliance" end
    e.C_ClassColor={GetClassColor=function(token)
        if token=="MAGE" then return {r=.2,g=.6,b=.9} end
    end}
    local menu
    e.Menu={ModifyMenu=function(tag,handler) if tag=="MENU_UNIT_PLAYER" then menu=handler end end}
    s:event("ADDON_LOADED","WhoWho")
    local state={scope="guild-a",status="ready",entries={},attempts={},guildAdds={},pulls=0}
    local function context()
        return state.status=="ready" and (state.writeToken or state.scope) or nil,state.status,
            state.scope and "read:"..state.scope
    end
    p.GuildBlacklist={
        canShareNote=assert(p.GuildBlacklist.canShareNote),
        context=context,
        list=function() return state.entries end,
        peerCount=function(scope) if scope==state.scope then return state.peers end end,
        requestSync=function() state.pulls=state.pulls+1 end,
        add=function(name,reasons,note,scope)
            assert(state.status=="ready" and state.scope==scope)
            state.guildAdds[#state.guildAdds+1]={name=name,reasons=reasons,note=note,
                personal=p.manual.store and p.manual.store.find(p.manual.region,name)}
            if state.result then return state.result end
            state.entries[#state.entries+1]={name=name,reasonIds=reasons,note=note}
            return "shared"
        end,
        share=function(record,scope,approval)
            assert(record.membership=="blacklist" and record.region==3)
            local saved=p.manual.store.get(record.id)
            assert(saved and saved.fullName==record.fullName and saved.note==record.note,"guild share preceded personal commit")
            assert(type(approval)=="table" and p.manual.validReasons(approval.reasonIds))
            state.attempts[#state.attempts+1]={record=record,scope=scope,approval=approval}
            if state.status~="ready" or state.scope~=scope then return "unavailable" end
            for _,entry in ipairs(state.entries) do
                if entry.name==record.fullName then
                    if not entry.class and record.lastKnown and record.lastKnown.class then
                        entry.class=record.lastKnown.class.value
                    end
                    if p.manual.reasonText(approval.reasonIds)==p.manual.reasonText(saved.reasonIds) then
                        entry.reasonIds=saved.reasonIds
                    end
                    if approval.note==saved.note then entry.note=saved.note end
                    return "unchanged"
                end
            end
            return state.result or "shared"
        end,
    }
    p.Toggle()
    local S=p.Shell
    local function pickBlacklist()
        local buttons={}
        local child={CreateButton=function(_,caption,action) buttons[caption]=action end}
        menu(nil,{CreateButton=function() return child end},{unit="target"})
        buttons[p.L("Blacklist")]()
    end
    return p,s,e,S,state,target,pickBlacklist
end

local function visibleText(parent,caption)
    for _,child in ipairs(parent.children) do
        if child.kind=="FontString" and child:IsVisible() and child:GetText()==caption then return child end
        local nested=visibleText(child,caption)
        if nested then return nested end
    end
end
local function button(parent,caption)
    for _,child in ipairs(parent.children) do
        if child.label and child:IsVisible() and child.label:GetText()==caption then return child end
    end
end
local function top(widget)
    local _,_,y=widget:GetPoint()
    return -y
end
local function checkHeader(S)
    local center=top(S.pageTitle)+S.pageTitle:GetHeight()/2
    assert(S.pageTitle.justifyV=="MIDDLE" and center==S.rosterHeader:GetHeight()/2)
    assert(top(S.addButton)+S.addButton:GetHeight()/2==center)
    local point,relative,edge,x,y=S.count:GetPoint()
    assert(point=="LEFT" and relative==S.pageTitle and edge=="RIGHT" and y==0)
end

-- Direct Guild Add owns the same form through both independent commits.
do
    local function run(changeAt)
        local p,s,e,S,state=fresh()
        S.nav.guildBlacklist:Click(); S.addButton:Click()
        local c=S.editor.controls
        local name="Late Region"
        c.formName:SetText(name); c.reasonOptions.other:Click(); c.guildShare:Click()
        local calls,lastPre,nativeRegion=0,0,3
        e.GetCurrentRegion=function() return nativeRegion end
        local context=p.GuildBlacklist.context
        p.GuildBlacklist.context=function()
            calls=calls+1
            if not p.manual.store.find(3,name) then lastPre=calls end
            if calls==changeAt then nativeRegion=4 end
            return context()
        end
        c.formSave:Click()
        assert(s.forbiddenCalls==0)
        return lastPre,p.manual.store.find(3,name),#state.guildAdds,nativeRegion
    end
    local finalContext,saved,adds=run()
    assert(saved and adds==1)
    local _,cancelled,dispatched,region=run(finalContext)
    assert(region==4 and not cancelled and dispatched==0,
        "a native region change inside the last precommit Guild context read saves neither destination")
end

for _,boundary in ipairs({"context","backend"}) do
    local p,s,_,S,state=fresh()
    local old=assert(p.manual.save(nil,"blacklist","Existing Personal","Old note",nil,{"other"}))
    S.nav.guildBlacklist:Click(); S.addButton:Click()
    local c=S.editor.controls
    c.formName:SetText(old.fullName); c.reasonOptions.other:Click(); c.guildShare:Click()
    local calls=0
    local context=p.GuildBlacklist.context
    p.GuildBlacklist.context=function()
        calls=calls+1
        if boundary=="context" and calls==2 then assert(p.manual.delete(old)) end
        return context()
    end
    if boundary=="backend" then
        p.GuildBlacklist.add=function(_,_,_,_,ownsSave)
            assert(p.manual.delete(old))
            assert(not ownsSave(),"backend publication must revalidate the acquired personal row")
            return "unavailable"
        end
    end
    c.formSave:Click()
    assert(not p.manual.store.find(3,old.fullName) and #state.guildAdds==0 and c.form:IsShown(),
        "a removed acquired personal row cannot authorize Guild publication: "..boundary)
    assert(c.formError:GetText()=="Guild Blacklist is unavailable." and s.forbiddenCalls==0,
        "a removed personal row must not be reported as saved")
end

for _,withPersonal in ipairs({false,true}) do
    for _,interruption in ipairs({"cancel","note","reasons","consent","scope"}) do
        local p,s,e,S,state=fresh()
        S.nav.guildBlacklist:Click(); S.addButton:Click()
        local c=S.editor.controls
        local name="Lease "..(withPersonal and "Personal" or "Guild")
        c.formName:SetText(name); c.formNote:SetText("Approved note"); c.reasonOptions.other:Click()
        if withPersonal then c.guildShare:Click() end
        local fired=false
        local function interrupt()
            if fired then return end
            fired=true
            if interruption=="cancel" then c.formCancel:Click()
            elseif interruption=="note" then c.formNote:SetText("Changed note")
            elseif interruption=="reasons" then c.reasonOptions.spam:Click()
            elseif interruption=="consent" then c.guildShare:Click()
            else state.scope="guild-b" end
        end
        if withPersonal then
            e.GetServerTime=function() interrupt(); return 100 end
        else
            local context=p.GuildBlacklist.context
            p.GuildBlacklist.context=function() interrupt(); return context() end
        end
        c.formSave:Click()
        assert(fired and #p.manual.records==0 and #state.guildAdds==0,
            "direct Guild cancellation or changed consent before commit saves neither destination: "..interruption)
        assert(s.forbiddenCalls==0)
    end
end

do
    local p,s,_,S,state=fresh()
    S.nav.guildBlacklist:Click(); S.addButton:Click()
    local c=S.editor.controls
    c.formName:SetText("Committed Personal"); c.formNote:SetText("Durable personal note")
    c.reasonOptions.other:Click(); c.guildShare:Click()
    local save=p.manual.save
    p.manual.save=function(...)
        local saved,issue=save(...)
        assert(saved)
        c.formCancel:Click()
        return saved,issue
    end
    c.formSave:Click()
    assert(#p.manual.records==1 and #state.guildAdds==0 and not c.form:IsShown(),
        "cancelling after personal commit preserves it and never dispatches Guild Add")
    assert(p.manual.records[1].note=="Durable personal note" and s.forbiddenCalls==0)
end

do
    local p,s,_,S,state=fresh()
    S.nav.guildBlacklist:Click(); S.addButton:Click()
    local c=S.editor.controls
    c.formName:SetText("Revised Personal"); c.formNote:SetText("First personal note")
    c.reasonOptions.other:Click(); c.guildShare:Click()
    local save=p.manual.save
    p.manual.save=function(...)
        local saved,issue=save(...)
        assert(saved)
        c.formNote:SetText("Revised Guild note")
        return saved,issue
    end
    c.formSave:Click()
    assert(c.form:IsShown() and #p.manual.records==1 and #state.guildAdds==0,
        "changed content after personal commit stops Guild publication and retains the draft")
    c.formSave:Click()
    assert(not c.form:IsShown() and #p.manual.records==1 and #state.guildAdds==1
        and state.guildAdds[1].note=="Revised Guild note" and p.manual.records[1].note=="First personal note",
        "retry publishes newly approved Guild content without rewriting the committed personal note")
    assert(s.forbiddenCalls==0)
end

do
    local p,s,_,S,state=fresh()
    S.nav.guildBlacklist:Click(); S.addButton:Click()
    local c=S.editor.controls
    c.formName:SetText("Policy Cancelled"); c.formNote:SetText("Approved note")
    c.reasonOptions.other:Click(); c.guildShare:Click()
    p.GuildBlacklist.canShareNote=function() c.formCancel:Click(); return true end
    c.formSave:Click()
    assert(not c.form:IsShown() and #p.manual.records==0 and #state.guildAdds==0,
        "cancelling inside note policy validation cannot save either destination")
    assert(s.forbiddenCalls==0)
end

do
    local p,s,e=H.fresh(root,nil,{484,744},{region=3,time=100})
    e.GetLocale=function() return "frFR" end
    local create=e.CreateFrame
    e.CreateFrame=function(...)
        local frame=create(...)
        local createLabel=frame.CreateFontString
        function frame:CreateFontString(...)
            local label=createLabel(self,...)
            local measure=label.GetUnboundedStringWidth
            function label:GetUnboundedStringWidth()
                if not self:IsVisible() then return 0 end
                return measure(self)
            end
            return label
        end
        return frame
    end
    s:event("ADDON_LOADED","WhoWho")
    p.Toggle()
    local S=p.Shell
    local function checkStrip(keys)
        local boundary=S.list:GetWidth()-24
        for _,key in ipairs(keys or {"roleFilter","classFilter","statusFilter"}) do
            local link=S.facetLinks[key]
            local _,x=link:GetPoint()
            assert(link:IsVisible() and link:GetWidth()-22>=math.ceil(link.label:GetUnboundedStringWidth())
                and x+link:GetWidth()<=boundary,"visible facet captions fit without touching their caret")
        end
    end
    checkStrip()
    S.facetLinks.roleFilter:Click()
    local noRole=S.filterChoices.roleFilter.UNASSIGNED
    assert(noRole:IsVisible() and noRole:GetWidth()-28>=math.ceil(noRole.label:GetUnboundedStringWidth()),
        "the first popup opening also sizes its visible localized options")
    noRole:Click()
    assert(S.facetLinks.roleFilter.label:GetText()==p.L("No role"))
    checkStrip()
    S.nav.settings:Click()
    S.nav.friend:Click()
    checkStrip()
    S.Toggle()
    e.UIParent:SetSize(440,740)
    p.SetScale(1)
    S.Toggle()
    checkStrip()
    assert(S.facetLinks.roleFilter.label:GetText()==p.L("No role"))
    S.nav.blacklist:Click()
    S.facetLinks.classFilter:Click()
    S.filterChoices.classFilter.WARLOCK:Click()
    S.Toggle()
    e.UIParent:SetSize(484,744)
    p.SetScale(1)
    S.Toggle()
    checkStrip({"classFilter"})
    assert(S.facetLinks.classFilter.label:GetText()==p.L("Warlock"))
end

do
    local p,s,_,S=fresh()
    local record=assert(p.manual.save(nil,"friend","Modal Test",""))
    S.Refresh()
    S.rows[1]:Click()
    local form=S.editor.controls.form
    local facet=S.facetLinks.statusFilter
    local function checkModal(dialog)
        assert(dialog:IsVisible() and S.scrim:IsVisible() and not S.filterMenu:IsShown()
            and not S.filterShield:IsShown())
        assert(dialog:GetFrameStrata()=="DIALOG" and S.scrim:GetFrameStrata()=="DIALOG"
            and S.scrim:GetFrameLevel()>facet:GetFrameLevel()
            and S.scrim:GetFrameLevel()>S.filterChoices.statusFilter.Unknown:GetFrameLevel()
            and dialog:GetFrameLevel()>S.scrim:GetFrameLevel(),
            "the modal stack covers the roster filters and their choices")
        assert(s:routePointer({S.scrim,facet},"OnEnter")==S.scrim
            and s:routePointer({S.scrim,S.list},"OnMouseWheel",-1)==S.scrim,
            "overlapping panel content stays behind the scrim for hover and wheel input")
    end
    facet:Click()
    assert(S.filterMenu:IsVisible())
    S.addButton:Click()
    checkModal(form)
    local role=S.editor.controls.roleOptions.HEALER
    assert(s:routePointer({S.scrim,facet,role},"OnClick")==role and role.selected,
        "choices in the Add dialog stay above the scrim")
    S.editor.controls.formCancel:Click()
    S.editButton:Click()
    checkModal(form)
    S.editor.controls.formCancel:Click()
    S.Copy(record)
    checkModal(S.copyDialog)
    local copyClose
    for _,node in ipairs(s.nodes) do
        if node.parent==S.copyDialog and node.kind=="Button" and node.label and node.label:GetText()==p.L("Close") then copyClose=node end
    end
    assert(copyClose and copyClose.rounded=="quiet" and not copyClose.skin:IsShown(),
        "Copy uses the same capsule action as the editor")
    S.copyDialog:Hide()
    S.rows[1].deleteButton:Click()
    checkModal(S.deleteDialog)
    assert(S.editor.controls.formSave.rounded=="primary" and S.editor.controls.formCancel.rounded=="quiet"
        and S.deleteConfirm.rounded=="primary" and S.deleteCancel.rounded=="quiet"
        and not S.deleteConfirm.skin:IsShown() and not S.deleteCancel.skin:IsShown(),
        "all modal actions share the capsule style")
    for _,palette in ipairs(p.interfaceColors) do
        p.SetInterfaceColor(palette.id)
        s:fire(S.deleteConfirm,"OnEnter")
        assert(S.deleteConfirm.roundFill[2].vertexColor[1]==p.colors.dangerHover[1]
            and S.deleteConfirm.label.textColor[1]==p.colors.text[1],
            "Delete keeps its destructive color and readable text in every palette")
        s:fire(S.deleteConfirm,"OnMouseDown","LeftButton")
        assert(S.deleteConfirm.roundFill[2].vertexColor[1]==p.colors.dangerPressed[1])
        s:fire(S.deleteConfirm,"OnMouseUp","LeftButton"); s:fire(S.deleteConfirm,"OnLeave")
        assert(S.deleteConfirm.roundFill[2].vertexColor[1]==p.colors.danger[1])
    end
    S.deleteCancel:Click()
    assert(not S.scrim:IsShown())
end

for _,viewport in ipairs({{1280,800},{484,744}}) do
    local p,_,_,S,state=fresh(nil,viewport)
    local name="Verin Brookhaven"
    local A=p.manual
    assert(A.store.add({fullName=name,region=3,identityState="resolved",membership="blacklist",
        reasonIds={"other"},note=""},100))
    A.refresh()
    state.entries={{name=name,class="MAGE",reasonIds={"other"}}}
    for _,section in ipairs({"blacklist","guildBlacklist"}) do
        S.nav[section]:Click()
        assert(visibleText(S.list,name)):GetParent():Click()
        local d=S.detail
        assert(S.details:IsVisible() and d.name:GetText()==name)
        local point,inset=d.nameView:GetPoint()
        local textPoint,textInset=d.name:GetPoint()
        assert(point=="TOPLEFT" and textPoint=="TOPLEFT" and textInset==0
            and inset==select(2,d.meta:GetPoint()) and inset==select(2,d.reasonLabel:GetPoint())
            and inset==select(2,d.reasonView:GetPoint()) and inset==select(2,d.rule1:GetPoint())
            and d.nameView:GetWidth()==S.details:GetWidth()-2*inset,
            "both Blacklist titles share the body column and retain its full wrapping width")
    end
end

do
    local p,s,e,S,state=fresh()
    S.searchBox:SetText("friend query")
    S.searchBox:SetFocus()
    S.nav.guildBlacklist:Click()
    local pane=S.list
    checkHeader(S)
    assert(S.addButton.skin:IsShown()==false and #S.addButton.roundFill==3)
    assert(S.addButton.roundFill[1]:GetWidth()==S.addButton:GetHeight()/2)
    assert(#S.refreshButton.roundFill==3 and #S.refreshButton.roundEdge==3)
    assert(pane:IsVisible() and S.details:IsVisible() and not S.searchBox:HasFocus() and not S.selected)
    assert(not S.filterToggle:IsVisible() and not S.editButton:IsVisible() and not S.moveButton:IsVisible())
    assert(visibleText(pane,"Guild Blacklist") and visibleText(pane,"No shared entries from your guild yet."))
    assert(state.pulls==1)
    S.nav.guildBlacklist:Click()
    S.RefreshGuildBlacklist()
    assert(state.pulls==1,"repeated clicks and repaint do not request another sync")
    assert(not visibleText(pane,"WhoWho guildmates detected: 0"))
    assert(visibleText(pane,"WhoWho guildmates detected: —"))
    state.peers=0; S.RefreshGuildBlacklist()
    assert(visibleText(pane,"WhoWho guildmates detected: 0"))
    state.peers=12; S.RefreshGuildBlacklist()
    assert(visibleText(pane,"WhoWho guildmates detected: 12"))
    assert(top(S.guildPeers)>S.rosterHeader:GetHeight() and top(S.searchBox)>top(S.guildPeers)+S.guildPeers:GetStringHeight())

    state.peers=nil; S.RefreshGuildBlacklist()
    assert(not visibleText(pane,"WhoWho guildmates detected: 12"))
    assert(visibleText(pane,"WhoWho guildmates detected: —"))
    local add=assert(button(pane,"Add entry"))
    assert(add:IsEnabled())
    S.searchBox:SetFocus()
    state.status,state.scope="no_guild",nil; S.RefreshGuildBlacklist()
    assert(not S.searchBox:HasFocus() and not S.searchBox:IsVisible())
    assert(not S.guildPeers:IsShown())
    assert(visibleText(pane,"You’re not in a guild. Guild sync is unavailable.") and S.nav.guildBlacklist:IsVisible())
    assert(add:IsVisible() and not add:IsEnabled())
    state.status="unavailable"; S.RefreshGuildBlacklist()
    assert(not S.guildPeers:IsShown())
    assert(visibleText(pane,"Guild Blacklist is unavailable.") and S.nav.guildBlacklist:IsVisible())

    state.status,state.scope="ready","guild-a"
    local note=("Read |r\n"):rep(30).."Last line"
    state.entries={{name="Élodie Brisevent",class="MAGE",reasonIds={"spam","other"},note=note},
        {name="Lune Pâle"},{name="Bad|r Style",reasonIds={"unknown","fraud"},note="Bad\1note"}}
    S.RefreshGuildBlacklist()
    assert(pane.children and visibleText(pane,"Bad||r Style"))
    local guildRow=assert(visibleText(pane,"Élodie Brisevent")):GetParent()
    assert(guildRow.name.textColor[1]==.2 and visibleText(pane,"Lune Pâle").textColor[1]==p.colors.text[1])
    assert(not guildRow.copyButton:IsVisible() and not guildRow.inviteButton:IsVisible()
        and not guildRow.deleteButton:IsVisible() and not guildRow.favoriteButton:IsVisible())
    local search=S.searchBox
    assert(search:IsVisible())
    local details=S.details
    guildRow:Click()
    assert(S.selected==guildRow.record or S.selected.id==guildRow.record.id)
    assert(guildRow.selected and guildRow.leadingEdge:IsVisible() and S.detail.noteEdge:IsVisible())
    assert(visibleText(details,"Mage") and not S.detail.affiliation:IsVisible() and not S.detail.observation:IsVisible())
    assert(not S.checkStatus:IsVisible() and not S.editButton:IsVisible() and not S.moveButton:IsVisible())
    local noteLabel=assert(visibleText(details,(note:gsub("|","||"))))
    assert(visibleText(details,"Shared reasons") and visibleText(details,"Spam / advertising, Other"))
    assert(visibleText(details,"Shared note") and not visibleText(details,"Personal note"))
    local noteView=noteLabel:GetParent():GetParent()
    for _=1,20 do s:fire(noteView,"OnMouseWheel",-1) end
    local scroll=noteView:GetVerticalScroll()
    assert(scroll>0 and scroll==noteView:GetVerticalScrollRange(),"last note line is reachable")
    table.insert(state.entries,1,{name="A new row"})
    S.RefreshGuildBlacklist()
    assert(details:IsVisible() and visibleText(details,"Élodie Brisevent") and noteView:GetVerticalScroll()==scroll)
    search:SetText("éLo")
    assert(details:IsVisible())
    state.entries[2].name="élodie brisevent"
    S.RefreshGuildBlacklist()
    assert(details:IsVisible() and visibleText(details,"élodie brisevent") and noteView:GetVerticalScroll()==scroll,
        "a case-only display spelling change preserves the selected guild row and scroll position")
    local readId=S.selected.id
    state.peers=4
    state.status="unavailable"
    S.RefreshGuildBlacklist()
    assert(S.selected.id==readId and noteView:GetVerticalScroll()==scroll and search:IsVisible()
        and not add:IsEnabled() and visibleText(pane,"WhoWho guildmates detected: —"),
        "paused transport keeps the verified roster, selection and peer placeholder while disabling Guild Add")
    S.Select(nil)
    visibleText(pane,"élodie brisevent"):GetParent():Click()
    assert(S.selected.id==readId and visibleText(details,"élodie brisevent"),"the verified cached row stays selectable")
    for _=1,20 do s:fire(noteView,"OnMouseWheel",-1) end
    state.status,state.writeToken="ready","resumed-write-token"
    S.RefreshGuildBlacklist()
    assert(S.selected.id==readId and noteView:GetVerticalScroll()==scroll and add:IsEnabled(),
        "recovering with a new write token keeps the selected readable row")
    state.writeToken=nil
    state.entries[2].name="Élodie Brisevent"
    S.RefreshGuildBlacklist()
    search:SetText("")
    visibleText(pane,"Bad||r Style"):GetParent():Click()
    assert(noteView:GetVerticalScroll()==0)
    assert(visibleText(details,"Bad||r Style") and visibleText(details,"No shared reasons.") and visibleText(details,"No shared note."))
    visibleText(pane,"Lune Pâle"):GetParent():Click()
    assert(visibleText(details,"Class unknown") and visibleText(details,"No shared reasons.")
        and visibleText(details,"No shared note."),"old name/class rows remain readable")
    search:SetText("%"); assert(visibleText(pane,"No matching records") and not visibleText(pane,"Élodie Brisevent"))
    assert(not S.selected and noteLabel:GetText()=="","a removed search result clears details")
    search:SetText("é")
    assert(visibleText(pane,"Élodie Brisevent") and not visibleText(pane,"Lune Pâle"),
        "guild search folds case and preserves accents")
    search:SetText("elo"); assert(visibleText(pane,"No matching records"),"unaccented search remains distinct")
    search:SetText("Élo"); assert(visibleText(pane,"Élodie Brisevent") and not visibleText(pane,"Lune Pâle"))
    assert(S.searchClear:IsVisible())
    S.searchClear:Click(); assert(visibleText(pane,"Lune Pâle") and not S.searchClear:IsVisible())
    visibleText(pane,"Élodie Brisevent"):GetParent():Click()
    local originalList=p.GuildBlacklist.list
    p.GuildBlacklist.list=function()
        state.scope="guild-b"
        return state.entries
    end
    S.RefreshGuildBlacklist()
    assert(not visibleText(pane,"Élodie Brisevent") and not S.selected and noteLabel:GetText()=="",
        "scope change clears rows and details")
    p.GuildBlacklist.list=originalList
    state.entries={{name="Élodie Brisevent",note="Guild B discussion"}}
    S.RefreshGuildBlacklist()
    local row=S.rows[1]
    s:fire(row,"OnMouseDown","LeftButton")
    state.scope="guild-c"
    state.entries={{name="Élodie Brisevent",note="Guild C discussion"}}
    S.RefreshGuildBlacklist()
    row:Click()
    assert(not S.selected and noteLabel:GetText()=="","same name in a new guild cannot inherit a pending click")
    s:fire(row,"OnMouseDown","LeftButton"); row:Click()
    assert(noteLabel:GetText()=="Guild C discussion")
    S.Select(nil)
    s:fire(row,"OnMouseDown","LeftButton")
    S.RefreshGuildBlacklist()
    s:fire(row,"OnMouseUp","LeftButton"); row:Click()
    assert(noteLabel:GetText()=="Guild C discussion","a refreshed snapshot of the same scoped identity keeps the press")
    S.Select(nil)
    s:fire(row,"OnMouseDown","LeftButton")
    S.nav.friend:Click()
    S.nav.guildBlacklist:Click()
    s:fire(row,"OnMouseUp","LeftButton"); row:Click()
    assert(not S.selected,"returning to the same Guild row cannot restore a press from before navigation")
    state.entries={}
    for i=25,1,-1 do state.entries[#state.entries+1]={name=string.format("Target%02d Stone",i)} end
    S.RefreshGuildBlacklist()
    local visible=S.visibleRows
    assert(visibleText(pane,"Target01 Stone") and visibleText(pane,("1–%d of 25"):format(visible)))
    local count=#s.nodes
    s:fire(pane,"OnMouseWheel",-1)
    assert(visibleText(pane,("2–%d of 25"):format(visible+1)) and visibleText(pane,"Target02 Stone"))
    for _=1,30 do s:fire(pane,"OnMouseWheel",-1) end
    assert(visibleText(pane,"Target25 Stone") and S.offset==25-visible and #s.nodes==count)
    S.sortButton:Click()
    assert(S.sortButton.label:GetText()=="Character · Z–A" and S.rows[1].record.fullName=="Target25 Stone")
    search:SetText("target2"); search:SetFocus()
    S.nav.friend:Click()
    assert(pane:IsVisible() and not search:HasFocus() and S.searchBox:GetText()=="friend query")
    assert(S.sortByName and S.facetLinks.roleFilter:IsVisible() and not S.filterToggle:IsVisible())
    S.nav.guildBlacklist:Click()
    assert(not S.sortByName and S.searchBox:GetText()=="target2" and S.rows[1].record.fullName=="Target25 Stone")
    assert(state.pulls==3,"explicit pane reentry requests sync")
    S.Open()
    assert(state.pulls==3,"raising a visible shell does not sample again")
    S.Toggle(); S.Toggle()
    assert(state.pulls==4,"reopening the selected Guild pane requests sync once")
    assert(s.forbiddenCalls==0)
end

do
    local _,_,e,S,state=fresh()
    S.nav.guildBlacklist:Click()
    local pane=S.list
    state.entries={{name="Private Stone",reasonIds={"other"},note="Guild A discussion"}}
    S.RefreshGuildBlacklist()
    local search
    for _,child in ipairs(pane.children) do if child.kind=="EditBox" then search=child end end
    search:HookScript("OnEditFocusLost",function()
        state.scope,state.entries="guild-b",{}
        S.RefreshGuildBlacklist()
    end)
    search:SetFocus()
    visibleText(pane,"Private Stone"):GetParent():Click()
    assert(not S.selected and not visibleText(pane,"Private Stone"),
        "losing focus can invalidate the row before its note is shown")
end

do
    local p,s,_,S,state=fresh()
    assert(p.manual.save(nil,"friend","Personal Stone","Private note"))
    S.Refresh()
    local row=S.rows[1]
    assert(row.record.fullName=="Personal Stone")
    s:fire(row,"OnMouseDown","LeftButton")
    state.entries={{name="Guild Stone",note="Shared note."}}
    S.nav.guildBlacklist:Click()
    row:Click()
    assert(not S.selected,"a press from Friends cannot open a rebound Guild row")
    s:fire(row,"OnMouseDown","LeftButton"); row:Click()
    assert(S.selected.fullName=="Guild Stone")
end

do
    local p,s,_,S,state=fresh({guildBlacklistDefaultWithNote=true})
    S.nav.guildBlacklist:Click()
    local pane=S.list
    local add=assert(button(pane,"Add entry"))
    local c=S.editor.controls
    local function open(name,note)
        add:Click()
        assert(c.form:IsVisible() and c.formTitle:GetText()=="Add Guild Blacklist entry")
        assert(c.guildShare.label:GetText()=="Also add to personal Blacklist" and not c.guildShare:GetChecked())
        c.formName:SetText(name)
        c.formNote:SetText(note)
        c.reasonOptions.other:Click()
    end
    open("Guild Only","Shared draft")
    add:Click()
    assert(c.formName:GetText()=="Guild Only" and c.formNote:GetText()=="Shared draft")
    c.formSave:Click()
    assert(S.section=="guildBlacklist" and not c.form:IsShown() and visibleText(pane,"Guild Only"))
    assert(#p.manual.records==0 and #state.attempts==0 and #state.guildAdds==1)
    assert(state.guildAdds[1].note=="Shared draft" and state.guildAdds[1].reasons[1]=="other"
        and not state.guildAdds[1].personal)

    open("Cancelled Stone","Do not save")
    c.guildShare:Click(); c.formCancel:Click()
    assert(S.section=="guildBlacklist" and #state.guildAdds==1 and #p.manual.records==0)

    open("Private Stone","Invalid\1note")
    c.guildShare:Click(); c.formSave:Click()
    assert(c.form:IsShown() and #state.guildAdds==1 and #p.manual.records==0)
    assert(c.formError:GetText()=="This note cannot be shared with your guild.")
    c.formCancel:Click()

    open("Guild Shift","Old guild only")
    c.guildShare:Click()
    state.scope="guild-b"
    S.RefreshGuildBlacklist()
    c.formSave:Click()
    assert(c.form:IsShown() and c.formNote:GetText()=="Old guild only" and #state.guildAdds==1 and #p.manual.records==0)
    assert(c.formError:GetText()=="Guild Blacklist is unavailable.")
    c.formCancel:Click()

    open("Both Lists","First approved note")
    c.guildShare:Click()
    state.result="limit"
    c.formSave:Click()
    assert(c.form:IsShown() and #p.manual.records==1 and #state.guildAdds==2 and state.guildAdds[2].personal)
    assert(c.formError:GetText()=="Saved to your Blacklist. Guild list full." and c.formError.textColor[1]==p.colors.warning[1])
    c.formNote:SetText("Corrected guild draft")
    state.result=nil
    c.formSave:Click()
    assert(not c.form:IsShown() and S.section=="guildBlacklist" and #p.manual.records==1)
    assert(#state.guildAdds==3 and state.guildAdds[3].note=="Corrected guild draft"
        and state.guildAdds[3].personal.note=="First approved note" and p.manual.records[1].note=="First approved note")
    assert(#state.attempts==0 and s.forbiddenCalls==0)
end

do
    local p,s,e,S,state,target,pickBlacklist=fresh()
    local c=S.editor.controls
    S.nav.blacklist:Click()
    checkHeader(S)
    S.addButton:Click()
    assert(c.guildShare:IsVisible() and not c.guildShare:GetChecked(),"default Off")
    assert(not c.guildShareNote and visibleText(c.form,"Shares name, class, reasons and note with your guild."))
    c.guildShare:Click()
    assert(c.guildShare:GetChecked())
    c.formNote:SetText("Could share this note")
    c.formName:SetText("One")
    c.formSave:Click()
    assert(c.formError:GetText()~="" and c.guildShare:GetChecked() and #state.attempts==0)
    c.formName:SetText("Ordinary Stone")
    c.formSave:Click()
    assert(c.reasonHelp:GetText()=="Select at least one reason before saving." and c.guildShare:GetChecked())
    c.formCancel:Click()
    assert(#state.attempts==0 and #p.manual.records==0 and not c.guildShare:GetChecked())

    S.nav.settings:Click()
    S.settingsTabs.general:Click()
    assert(S.guildBlacklistDefault:IsVisible() and not S.guildBlacklistDefault:GetChecked())
    S.guildBlacklistDefault:Click()
    assert(p.db.guildBlacklistDefaultWithNote and S.guildBlacklistDefault:GetChecked())
    state.entries={{name=target.name,note="Earlier shared note"}}
    pickBlacklist()
    assert(c.form:IsVisible() and c.formName:GetText()==target.name and c.guildShare:GetChecked())
    c.formNote:SetText("Personal fixture note")
    c.reasonOptions.other:Click()
    local footer=S.footer:GetText()
    c.formSave:Click()
    assert(not c.form:IsShown() and S.selected.fullName==target.name and S.selected.note=="Personal fixture note")
    assert(#state.attempts==1 and state.attempts[1].scope=="guild-a")
    assert(state.attempts[1].record.lastKnown.class.value=="MAGE" and state.entries[1].class=="MAGE")
    assert(state.attempts[1].approval.note=="Personal fixture note" and state.entries[1].note=="Personal fixture note"
        and state.entries[1].reasonIds[1]=="other")
    assert(S.footer:GetText()==footer,"guild duplicate is silent")

    S.editButton:Click()
    assert(not c.guildShare:IsVisible())
    c.formNote:SetText("Edited private note"); c.formSave:Click()
    assert(not c.form:IsShown() and #state.attempts==1)
    S.addButton:Click()
    c.reasonOptions.other:Click()
    c.formSave:Click()
    assert(c.formSave.label:GetText()=="Open existing" and #state.attempts==1)
    c.formSave:Click()
    assert(not c.form:IsShown() and #state.attempts==1)

    S.addButton:Click()
    c.formName:SetText("Switch Stone")
    c.reasonOptions.other:Click()
    c.formNote:SetText("Old guild only")
    assert(c.guildShare:GetChecked())
    state.scope="guild-b"; S.RefreshGuildBlacklist()
    assert(c.guildShare:IsVisible() and not c.guildShare:GetChecked() and c.formNote:GetText()=="Old guild only")
    c.formSave:Click()
    assert(#state.attempts==1 and S.selected.fullName=="Switch Stone")

    S.addButton:Click()
    c.formName:SetText("Detached Stone")
    c.reasonOptions.other:Click()
    c.formNote:SetText("Also old guild only")
    state.scope="guild-c"
    c.formSave:Click()
    assert(#state.attempts==1 and S.selected.fullName=="Detached Stone")
    assert(S.footer:GetText()=="Saved to your Blacklist. Guild sharing unavailable.")

    S.addButton:Click()
    c.formName:SetText("Limit Stone"); c.reasonOptions.other:Click()
    state.result="limit"
    c.formSave:Click()
    assert(#state.attempts==2 and S.selected.fullName=="Limit Stone")
    assert(S.footer:GetText()=="Saved to your Blacklist. Guild list full.")

    state.status,state.scope="unavailable",nil
    S.addButton:Click()
    assert(not c.guildShare:IsVisible())
    state.status,state.scope,state.result="ready","guild-c",nil
    S.RefreshGuildBlacklist()
    assert(c.guildShare:IsVisible() and not c.guildShare:GetChecked(),"newly available scope does not inherit consent")
    c.formName:SetText("Offline Stone"); c.reasonOptions.other:Click(); c.formSave:Click()
    assert(#state.attempts==2 and S.selected.fullName=="Offline Stone")

    S.addButton:Click()
    assert(c.guildShare:GetChecked())
    c.formNote:SetText("Revocable consent")
    c.guildShare:Click()
    assert(not c.guildShare:GetChecked())
    c.guildShare:Click()
    assert(c.guildShare:GetChecked())
    c.guildShare:Click()
    c.formName:SetText("Optout Stone"); c.reasonOptions.other:Click(); c.formSave:Click()
    assert(#state.attempts==2 and S.selected.fullName=="Optout Stone" and p.db.guildBlacklistDefaultWithNote)
    target.name=nil
    S.nav.friend:Click(); S.addButton:Click()
    assert(not c.guildShare:IsVisible())
    c.formName:SetText("Former Friend"); c.formSave:Click()
    assert(S.selected.fullName=="Former Friend" and #state.attempts==2)
    S.moveButton:Click()
    assert(c.form:IsVisible() and c.guildShare:GetChecked())
    c.reasonOptions.other:Click(); c.formSave:Click()
    assert(S.section=="blacklist" and S.selected.fullName=="Former Friend" and #state.attempts==3)
    assert(state.attempts[3].scope=="guild-c")

    S.addButton:Click()
    c.formName:SetText("Shared Stone")
    c.reasonOptions.camping:Click()
    c.formNote:SetText("Two lines\nwith |r markup")
    c.formSave:Click()
    assert(#state.attempts==4 and state.attempts[4].approval.note=="Two lines\nwith |r markup"
        and state.attempts[4].approval.reasonIds[1]=="camping")

    S.addButton:Click()
    c.formName:SetText("Private Stone")
    c.reasonOptions.other:Click()
    c.formNote:SetText("private\1note")
    assert(visibleText(c.form,"This note can only be saved privately."))
    c.formSave:Click()
    assert(not c.form:IsShown() and S.selected.note=="private\1note" and #state.attempts==5 and state.attempts[5].approval.note==nil)

    S.addButton:Click()
    c.formName:SetText("Changed Stone")
    c.formNote:SetText("Approved note")
    c.reasonOptions.other:Click()
    state.entries={{name="Changed Stone",reasonIds={"spam"},note="Previously shared"}}
    local mutateOnce=true
    c.form:HookScript("OnHide",function()
        if not mutateOnce then return end
        mutateOnce=false
        for _,record in ipairs(p.manual.records) do
            if record.fullName=="Changed Stone" then
                assert(p.manual.store.edit(record.id,{note="Private replacement",reasonIds={"griefing"}},e.GetServerTime()))
                return
            end
        end
        error("fixture edit must follow personal commit")
    end)
    c.formSave:Click()
    local attempt=state.attempts[6]
    assert(attempt and attempt.record.note=="Private replacement" and attempt.record.reasonIds[1]=="griefing")
    assert(attempt.approval.note=="Approved note" and attempt.approval.reasonIds[1]=="other")
    assert(state.entries[1].note=="Previously shared" and state.entries[1].reasonIds[1]=="spam")

    local _,_,_,reopened=fresh(e.WhowhoPreviewDB)
    reopened.nav.blacklist:Click(); reopened.addButton:Click()
    assert(reopened.editor.controls.guildShare:GetChecked(),"the new note-inclusive preference survives reload")
    local _,_,_,legacy=fresh({guildBlacklistDefault=true})
    legacy.nav.blacklist:Click(); legacy.addButton:Click()
    assert(not legacy.editor.controls.guildShare:GetChecked(),"legacy default did not authorize note sharing")
    assert(s.forbiddenCalls==0)
end

local function checkGuildHeader(p,pane)
    local add=assert(button(pane,p.L("Add entry")))
    local title=assert(visibleText(pane,p.L("Guild Blacklist")))
    local peers=assert(visibleText(pane,p.L("WhoWho guildmates detected: %s",12)))
    local search
    for _,child in ipairs(pane.children) do if child.kind=="EditBox" then search=child end end
    assert(title:GetWidth()+add:GetWidth()+48<pane:GetWidth())
    assert(top(peers)>math.max(top(title)+title:GetStringHeight(),top(add)+add:GetHeight()))
    assert(top(search)>top(peers)+peers:GetStringHeight())
    local row=assert(visibleText(pane,"Lune Pâle")):GetParent()
    assert(top(search)+search:GetHeight()<top(row))
end

for _,locale in ipairs({"enUS","frFR"}) do
    for _,viewport in ipairs({{1360,832},{484,744}}) do
        local p,s,e,S,state=fresh(nil,viewport,locale)
        state.entries={{name="Lune Pâle",reasonIds={"camping"}}}
        S.nav.guildBlacklist:Click()
        local prefix=locale=="frFR" and "Membres de guilde WhoWho détectés : " or "WhoWho guildmates detected: "
        local function geometry()
            local values={}
            for _,widget in ipairs({S.guildPeers,S.searchBox,S.sortButton,S.rows[1]}) do
                local _,x,y=widget:GetPoint()
                values[#values+1]=table.concat({x,y,widget:GetWidth(),widget:GetHeight(),widget:GetStringHeight()},",")
            end
            return table.concat(values,";")..";"..S.visibleRows
        end
        assert(visibleText(S.list,prefix.."—") and not visibleText(S.list,prefix.."0"))
        local baseline=geometry()
        for _,sample in ipairs({0,12,false}) do
            state.peers=sample~=false and sample or nil
            S.RefreshGuildBlacklist()
            assert(visibleText(S.list,prefix..(sample~=false and sample or "—")))
            assert(geometry()==baseline,"sample arrival or expiry moved the Guild header or list")
        end
        state.scope="guild-b"; state.peers=nil
        S.RefreshGuildBlacklist()
        assert(visibleText(S.list,prefix.."—") and geometry()==baseline,"a new scope must not inherit a sample or move the layout")
        p.GuildBlacklist.peerCount=nil
        S.RefreshGuildBlacklist()
        assert(visibleText(S.list,prefix.."—") and geometry()==baseline)
        S.searchBox:SetText("no matching character")
        assert(visibleText(S.list,p.L("No matching records")) and geometry()==baseline)
        S.searchBox:SetText("")
        assert(visibleText(S.list,"Lune Pâle") and geometry()==baseline)
        assert(top(S.searchBox)>top(S.guildPeers)+S.guildPeers:GetStringHeight())
        assert(state.pulls==1 and s.forbiddenCalls==0,"count rendering must not request another sync or native action")
    end
end

for _,locale in ipairs({"enUS","frFR"}) do
    local p,s,e,S,state,target=fresh({guildBlacklistDefaultWithNote=true},{484,744},locale)
    local nav=S.nav.guildBlacklist
    assert(S.layoutMode=="compact" and nav.label:GetText():find("\n",1,true))
    assert(nav.icon:GetHeight()+nav.label:GetStringHeight()+5<=nav:GetHeight())
    assert(top(nav)+nav:GetHeight()<top(S.nav.encounters))
    S.nav.guildBlacklist:Click()
    local pane=S.list
    assert(visibleText(pane,p.L("Guild Blacklist")))
    state.entries={{name="Lune Pâle",reasonIds={"camping"},note=("Ligne longue\n"):rep(15)}}
    state.peers=12
    S.RefreshGuildBlacklist()
    checkGuildHeader(p,pane)
    visibleText(pane,"Lune Pâle"):GetParent():Click()
    local details=S.details
    assert(details:IsVisible() and not pane:IsVisible() and details:GetWidth()==pane:GetWidth())
    assert(S.backButton:IsVisible() and S.backButton.label:GetText()==p.L("Back to list"))
    assert(visibleText(details,p.L("Shared reasons")) and visibleText(details,p.L("Repeated camping")))
    assert(visibleText(details,p.L("Shared note")) and visibleText(details,state.entries[1].note))
    S.backButton:Click()
    assert(not details:IsVisible() and pane:IsVisible() and S.rows[1].selected)
    button(pane,p.L("Add entry")):Click()
    local c=S.editor.controls
    assert(c.formTitle:GetUnboundedStringWidth()<c.form:GetWidth()-48)
    assert(visibleText(c.form,p.L("Shared note (optional)")) and not c.guildShare:GetChecked())
    c.formCancel:Click()
    S.nav.settings:Click(); S.settingsTabs.general:Click()
    assert(top(S.guildBlacklistDefault)+S.guildBlacklistDefault:GetHeight()<top(S.muteBlacklistWhispers))
    local guildMute=S.muteBlacklistGuild
    local content=guildMute:GetParent()
    local scroll=content:GetParent()
    local rowTop,rowBottom=top(guildMute),top(guildMute)+guildMute:GetHeight()
    assert(rowBottom<=content:GetHeight())
    if rowBottom>scroll:GetHeight() then
        assert(scroll.EnableMouseWheelArgs[1])
        s:fire(scroll,"OnMouseWheel",-100)
    end
    local offset=scroll:GetVerticalScroll()
    assert(rowTop>=offset and rowBottom<=offset+scroll:GetHeight())
    S.nav.blacklist:Click(); S.addButton:Click()
    target.name=nil
    c.formNote:SetText("Sample note")
    c.formName:SetText("Invalid"); c.formSave:Click()
    local _,_,saveBottom=c.formSave:GetPoint()
    assert(c.formError:GetText()~="" and c.formSave:IsVisible() and c.formCancel:IsVisible())
    assert(top(c.noteView)+c.noteView:GetHeight()<=top(c.guildShare))
    local disclosure=assert(visibleText(c.form,p.L("Shares name, class, reasons and note with your guild.")))
    assert(top(c.guildShare)+c.guildShare:GetHeight()<=top(disclosure))
    assert(top(disclosure)+disclosure:GetStringHeight()<top(c.formError))
    assert(top(c.formError)+c.formError:GetStringHeight()<c.form:GetHeight()-saveBottom-c.formSave:GetHeight())
    assert(c.form:GetHeight()<S.window:GetHeight() and s.forbiddenCalls==0)
    c.formCancel:Click()

    local noGuild=p.L("You’re not in a guild. Guild sync is unavailable.")
    S.nav.settings:Click()
    local general=S.guildBlacklistDefault:GetParent()
    state.status,state.scope="no_guild",nil
    S.RefreshGuildBlacklist()
    assert(not S.guildBlacklistDefault:IsShown() and p.db.guildBlacklistDefaultWithNote)
    local status=assert(visibleText(general,noGuild))
    assert(top(status)+status:GetStringHeight()<top(S.muteBlacklistWhispers) and S.muteBlacklistGuild:IsVisible())
    S.nav.guildBlacklist:Click()
    assert(S.nav.guildBlacklist:IsVisible() and visibleText(pane,noGuild))
    S.nav.blacklist:Click(); S.addButton:Click()
    assert(not c.guildShare:IsShown())
    c.formCancel:Click()
    state.status="unavailable"
    S.nav.guildBlacklist:Click()
    assert(visibleText(pane,p.L("Guild Blacklist is unavailable.")) and not visibleText(pane,noGuild))
    S.nav.settings:Click()
    assert(S.guildBlacklistDefault:IsVisible() and S.guildBlacklistDefault:GetChecked()
        and not visibleText(general,noGuild),"temporarily unavailable is not confirmed guild absence")
    state.status,state.scope="ready","guild-b"
    S.RefreshGuildBlacklist()
    S.nav.blacklist:Click(); S.addButton:Click()
    assert(c.guildShare:IsVisible() and c.guildShare:GetChecked())
    c.formCancel:Click()

    s.env.UIParent:SetSize(1360,832)
    p.SetScale(1)
    assert(S.layoutMode=="wide" and nav.label:GetText()==p.L("Guild Blacklist"))
    assert(nav.label:GetStringHeight()<=nav:GetHeight())
    assert(top(nav)+nav:GetHeight()<top(S.nav.encounters))
    S.nav.guildBlacklist:Click()
    checkGuildHeader(p,pane)
end

do
    local p,_,_,S=fresh({guildBlacklistDefaultWithNote=true})
    local original=("é"):rep(257)
    local editor=p.EditorDialog.Create(S.window,{
        records={},
        classEvidence={},
        setNameColor=function() end,
        onShow=function() end,
        onHide=function() end,
        save=function(_,_,name,note,_,reasons)
            assert(note==original,"unchanged oversized legacy note must never be truncated by the editor")
            return {fullName=name,note=note,reasonIds=reasons}
        end,
        onSaved=function(record,scope,approval)
            assert(record.note==original and scope=="guild-a" and approval.note==nil and approval.reasonIds[1]=="other")
        end,
    })
    local c=editor.controls
    editor.Open({fullName="Former Friend",note=original},"blacklist",nil,nil,true)
    assert(c.guildShare:GetChecked())
    assert(visibleText(c.form,"This note can only be saved privately."))
    c.reasonOptions.other:Click()
    c.formSave:Click()
    assert(not c.form:IsShown())
end

print("RESULT Guild Blacklist navigation, consent, personal save, sharing, and layout passed in simulation")
