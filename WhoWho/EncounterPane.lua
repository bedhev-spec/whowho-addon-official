local P=WhowhoPreview
local L=P.L
local A=P.manual
local E=A.encounterLedger
local C=P.colors
local tabsBySection={Now=1,Recent=2,Earlier=3,Ended=3}
local tabLabels={"Last hour","Recent","Earlier"}
local tabHelp={
    "The player is currently targeted or under your cursor, or the encounter ended less than 1 hour ago.",
    "The encounter ended at least 1 hour ago and less than 24 hours ago.",
    "The encounter ended at least 24 hours ago.",
}
local tabEmpty={"No encounters in the last hour.","No recent encounters.","No earlier encounters."}
local endedHelp="The current time is unavailable. This tab shows completed encounters of unknown age."
local inset=24
local cellInset,cellRight=22,12
local pagerHeight,footerGap=30,8
local read,member=A.nativeRead.read,A.nativeRead.member

local function label(parent,text,role,color)
    local field=P.Label(parent,L(text),role,color)
    field:SetJustifyH("LEFT")
    field:SetWordWrap(false)
    return field
end

local function dateText(at)
    return P.FormatDate(at) or L("Time unavailable")
end

local function placeName(row)
    local place=row.zone or L(row.groupContext or "Unknown")
    return (place:gsub("|","||"))
end

local function lastSeen(row)
    return dateText(row.lastObservedAt).." · "..placeName(row)
end

local function factionName(known)
    return L(known and known.faction and known.faction.value or "Unknown")
end

local function clipped(field,singleLine)
    local truncated=read(member(field,"IsTruncated"),field)
    if type(truncated)=="boolean" then return truncated end
    if singleLine then return field:GetUnboundedStringWidth()>field:GetWidth() end
    return field:GetStringHeight()>field:GetHeight()
end

-- The scroll area owns its text; the record action remains accessible below it.
local function createDetail(pane,copyRecord)
    local panel=CreateFrame("Frame",nil,pane)
    P.Paint(panel,C.raised)
    local view=CreateFrame("ScrollFrame",nil,panel)
    local content=CreateFrame("Frame",nil,view)
    view:SetScrollChild(content)
    view:SetPoint("TOPLEFT",18,-18)
    view:SetScript("OnMouseWheel",function(self,delta)
        self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-delta*32)))
    end)
    local name=label(content,"","record",C.text)
    local reasonLabel=label(content,"Blacklist","small",C.muted)
    local reason=label(content,"","section",C.text)
    local identityRule=P.Rule(content,0,0,0)
    local subtitle=label(content,"","small",C.muted)
    local fields={}
    for i,key in ipairs({"First seen","Last seen","Zone"}) do
        fields[i]={title=label(content,key,"meta",C.muted),value=label(content,"","body",C.text)}
    end
    local footer=label(content,"","small",C.muted)
    local edge=P.NoteInset(content)
    local caption=label(content,"Last 3 Encounters","column",C.muted)
    local lines,separators={},{}
    for i=1,3 do
        lines[i]={when=label(content,"","small",C.muted),where=label(content,"","body",C.text)}
        if i>1 then separators[i]=P.Rule(content,10,0,10,C.rowRule) end
    end
    local copy=P.CopyNameButton(content,L("Copy name"),copyRecord)
    P.Tooltip(copy,L("Copy name"))
    local bound,paintedGroup,paintedReason,paintedFaction
    local function place(field,x,y,w)
        field:ClearAllPoints(); field:SetPoint("TOPLEFT",x,-y)
        field:SetWidth(w); field:SetWordWrap(true); field:SetNonSpaceWrap(true)
        field:SetJustifyV("TOP")
        local h=math.max(1,math.ceil(field:GetStringHeight()))
        field:SetHeight(h)
        return y+h
    end
    function panel:Arrange(x,y,w,h)
        paintedGroup=nil
        self:ClearAllPoints(); self:SetPoint("TOPLEFT",x,-y); self:SetSize(w,h)
        view:SetSize(w-36,math.max(1,h-70))
    end
    function panel:SetNameColor(r,g,b,a)
        name:SetTextColor(r,g,b,a)
    end
    function panel:Display(group,reasons,affiliation)
        self:SetShown(group~=nil)
        if not group then
            bound,paintedGroup=nil,nil
            return
        end
        if group==paintedGroup and reasons==paintedReason and affiliation==paintedFaction then return end
        if group~=paintedGroup then name:SetTextColor(unpack(C.text)) end
        paintedGroup,paintedReason,paintedFaction=group,reasons,affiliation
        local row=group.row
        local w=view:GetWidth()
        name:SetText((group.row.name:gsub("|","||")))
        local nameWidth=w-copy:GetWidth()-1
        local y=place(name,0,0,nameWidth)
        copy:ClearAllPoints()
        if name:GetUnboundedStringWidth()<=nameWidth then
            name:SetWidth(0)
            copy:SetPoint("LEFT",name,"RIGHT",1,4)
        else
            local _,fontSize=name:GetFont()
            copy:SetPoint("LEFT",name,"TOPRIGHT",1,-fontSize/2+2)
        end
        y=math.max(y,30)+4
        local reasonX=math.ceil(reasonLabel:GetUnboundedStringWidth())
        place(reasonLabel,0,y+2,reasonX)
        reasonX=reasonX+10
        reason:SetText(reasons~="" and reasons or L("Unknown"))
        y=place(reason,reasonX,y,w-reasonX)+6
        local started=dateText(row.startedAt)
        subtitle:SetText(started.." · "..L("Physical encounter"))
        y=place(subtitle,0,y,w)+12
        identityRule:ClearAllPoints(); identityRule:SetPoint("TOPLEFT",0,-y); identityRule:SetWidth(w)
        y=y+14
        -- The heading supplies the date for same-day times.
        local last=dateText(row.lastObservedAt)
        local day,firstTime=started:match("^(%S+) (%d%d:%d%d)$")
        local lastDay,lastTime=last:match("^(%S+) (%d%d:%d%d)$")
        local function fact(i,value,x,top,width)
            local cell=fields[i]
            cell.value:SetText(value)
            return place(cell.value,x,place(cell.title,x,top,width)+4,width)
        end
        local cellWidth=math.floor((w-16)/2)
        local firstBottom=fact(1,firstTime or started,0,y,cellWidth)
        local lastBottom=fact(2,day and day==lastDay and lastTime or last,cellWidth+16,y,cellWidth)
        y=fact(3,placeName(row),0,math.max(firstBottom,lastBottom)+12,w)+12
        local top=y
        y=place(caption,12,y+12,w-24)+10
        local whenWidth=math.min(86,math.floor(w*.35))
        for i,line in ipairs(lines) do
            local entry=group.recent[i]
            line.when:SetShown(entry~=nil)
            line.where:SetShown(entry~=nil)
            local rule=separators[i]
            if rule then
                rule:SetShown(entry~=nil)
                rule:ClearAllPoints(); rule:SetPoint("TOPLEFT",10,-y); rule:SetWidth(w-20)
            end
            if entry then
                if rule then y=y+7 end
                local stamp=dateText(entry.lastObservedAt)
                local datePart,timePart=stamp:match("^(%S+) (%d%d:%d%d)$")
                line.when:SetText(timePart and (timePart.."\n"..datePart) or stamp)
                line.where:SetText(placeName(entry))
                y=math.max(place(line.when,12,y,whenWidth),place(line.where,24+whenWidth,y,w-36-whenWidth))+9
            end
        end
        edge:ClearAllPoints(); edge:SetPoint("TOPLEFT",0,-top); edge:SetSize(w,y-top+3)
        footer:SetText((row.endedAt and L("Ended %s",dateText(row.endedAt)).." · " or "")..L("Faction: %s",affiliation))
        y=place(footer,0,y+15,w)
        content:SetSize(w,math.max(view:GetHeight(),y+6))
        local scroll=bound==group.key and view:GetVerticalScroll() or 0
        local limit=math.max(0,content:GetHeight()-view:GetHeight())
        view:SetVerticalScroll(math.min(scroll,limit))
        view:EnableMouseWheel(limit>0)
        bound=group.key
    end
    panel:Hide()
    return panel,copy
end

function P.CreateEncounterLedger(parent,openBlacklist,blocked)
    local pane=CreateFrame("Frame",nil,parent)
    P.Paint(pane,C.panel)
    P.PageHeader(pane,55)
    label(pane,"Encounters","page"):SetPoint("TOPLEFT",inset,-23)

    local search=P.Field(pane,160,30)
    local hint=label(search,"Search encounters","small",C.muted)
    hint:SetPoint("LEFT",12,0)
    local query=""
    local function matches(group)
        if query=="" then return true end
        local row=group.row
        local place=row.zone or L(row.groupContext or "Unknown")
        return row.name:lower():find(query,1,true) or place:lower():find(query,1,true)
    end
    local empty=label(pane,"","small",C.muted)
    empty:SetPoint("TOPLEFT",inset,-105)
    empty:SetWordWrap(true)
    P.Rule(pane,inset,90,inset)
    local header=CreateFrame("Frame",nil,pane)
    header.name=label(header,"Name","column",C.muted)
    header.time=label(header,"Last seen","column",C.muted)
    header.count=label(header,"Count","column",C.muted)
    header.faction=label(header,"Faction","column",C.muted)

    local tabs,rows={},{}
    local current,paintedTab=1,nil
    local selected,selectedEpisode,selectedSlot
    local lastRevision,lastRegion,lastTime,nextBoundary
    local width,height,stacked,rowTop,rowHeight,paneWidth
    local pageSize=0
    local viewPress
    local paintPass,colorPass=0,0
    local viewEntry=P.Button(pane,L("View Blacklist entry"),174,34,function(button)
        local key=viewPress
        viewPress=nil
        if key and selected and selected.key==key and button:IsVisible() and not blocked() then
            openBlacklist(selected.row,function() return selected and selected.key==key end)
        end
    end)
    P.RoundButton(viewEntry)
    viewEntry:HookScript("OnMouseDown",function(button,key)
        if A.text(key)=="LeftButton" then
            viewPress=button:IsEnabled() and button:IsVisible() and selectedSlot and selected.key or nil
        end
    end)
    viewEntry:HookScript("OnHide",function() viewPress=nil end)
    viewEntry:HookScript("OnLeave",function() viewPress=nil end)
    local copyPress
    local detail,copy=createDetail(pane,function(button)
        local key=copyPress
        copyPress=nil
        if key and selected and selectedSlot and selected.key==key and button:IsVisible() and not blocked() then
            P.Shell.Copy({fullName=selected.row.name})
        end
    end)
    viewEntry:SetFrameLevel(detail:GetFrameLevel()+2)
    copy:HookScript("OnMouseDown",function(button,key)
        copyPress=key=="LeftButton" and selectedSlot and selected and selected.key or nil
    end)
    copy:HookScript("OnLeave",function() copyPress=nil end)
    copy:HookScript("OnHide",function() copyPress=nil end)
    local pageLabel=label(pane,"","small",C.muted)

    local function setSelection(group,episode)
        if (selected and selected.key)~=(group and group.key) then
            viewPress=nil
            copyPress=nil
        end
        selected,selectedEpisode=group,episode
    end

    local function pageCount(tab)
        return pageSize>0 and math.max(1,math.ceil(#tab.entries/pageSize)) or 1
    end

    local function reveal(tab,key)
        if not key or pageSize==0 then return end
        for index,entry in ipairs(tab.entries) do
            if entry.key==key then
                tab.page=math.ceil(index/pageSize)
                return
            end
        end
    end

    local function firstVisible(tab)
        return pageSize>0 and tab.entries[(tab.page-1)*pageSize+1] or nil
    end

    local function pageBy(pages)
        if not pane:IsVisible() or blocked() then return end
        local tab=tabs[current]
        local page=math.max(1,math.min(pageCount(tab),tab.page+pages))
        if page==tab.page then return end
        tab.page=page
        setSelection(nil)
        pane:PaintPage()
    end

    local prev=P.Button(pane,L("Previous"),91,pagerHeight,function() pageBy(-1) end)
    local nextPage=P.Button(pane,L("Next"),91,pagerHeight,function() pageBy(1) end)
    P.RoundButton(prev)
    P.RoundButton(nextPage)
    pane:EnableMouseWheel(true)
    pane:SetScript("OnMouseWheel",function(_,delta)
        if delta~=0 then pageBy(delta>0 and -1 or 1) end
    end)

    for index,caption in ipairs(tabLabels) do
        local button=P.TextTab(pane,L(caption),36,function(self)
            if current==index or not self:IsVisible() or blocked() then return end
            current=index
            setSelection(nil)
            pane:PaintPage()
        end,index==3 and L("Ended") or nil)
        button.entries,button.page,button.help={},1,tabHelp[index]
        if type(button.SetMouseMotionEnabled)=="function" and pcall(button.SetMouseMotionEnabled,button,true) then
            button:HookScript("OnEnter",function(self)
                if self:IsVisible() and not blocked() then P.ShowTooltip(self,L(self.help)) end
            end)
            button:HookScript("OnLeave",P.HideTooltip)
            button:HookScript("OnHide",P.HideTooltip)
        end
        tabs[index]=button
    end

    local function renderSelection()
        local group,slot=selected,selectedSlot
        viewEntry:SetShown(slot~=nil and group~=nil)
        if not slot or not group then detail:Display(nil);return end
        if not pane:IsVisible() then return end
        local row=group.row
        local store=A.store
        -- Resolve metadata against the selected episode's identity.
        local record,known=E.blacklistRecord(row)
        if selected~=group or selectedSlot~=slot or not pane:IsVisible() or A.store~=store then return end
        detail:Display(group,record and A.reasonText(record.reasonIds) or "",factionName(known))
        P.SetEnabled(viewEntry,record~=nil)
    end

    local function clearRowInput(row)
        row.encounterPress=nil
        P.ResetButtonFeedback(row)
        P.HideTooltip(row)
    end

    local function cells(frame,isHeader)
        local gap,countWidth,factionWidth=12,stacked and 122 or 80,88
        local contentWidth=width-cellInset-cellRight
        local nameWidth=stacked and contentWidth-countWidth-gap or math.min(264,math.floor(contentWidth/3))
        local dateWidth=stacked and contentWidth or math.min(380,contentWidth-nameWidth-countWidth-factionWidth-3*gap)
        frame.name:ClearAllPoints()
        frame.time:ClearAllPoints()
        frame.count:ClearAllPoints()
        frame.faction:ClearAllPoints()
        frame.faction:SetSize(factionWidth,24)
        frame.faction:SetShown(not stacked)
        frame.time:SetSize(dateWidth,stacked and 38 or (isHeader and 22 or 46))
        frame.count:SetJustifyH(stacked and "RIGHT" or "CENTER")
        frame.count:SetSize(countWidth,24)
        if stacked then
            frame.name:SetPoint("TOPLEFT",cellInset,0)
            P.Type(frame.name,"presence")
            frame.name:SetSize(nameWidth,24)
            frame.name:SetWordWrap(false)
            frame.time:SetPoint("TOPLEFT",cellInset,-24)
            frame.count:SetPoint("TOPRIGHT",-cellRight,0)
        else
            frame.name:SetPoint("LEFT",cellInset,0)
            if not isHeader then P.Type(frame.name,"name") end
            frame.name:SetSize(nameWidth,isHeader and 22 or 48)
            frame.name:SetWordWrap(not isHeader)
            local dateX=cellInset+nameWidth+gap
            local countX=dateX+dateWidth+gap
            frame.time:SetPoint("LEFT",dateX,0)
            frame.count:SetPoint("LEFT",countX,0)
            frame.faction:SetPoint("LEFT",countX+countWidth+gap,0)
        end
    end

    local function arrangeRow(row,index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",inset,-rowTop-(index-1)*rowHeight)
        row:SetSize(width,rowHeight)
        cells(row,false)
    end

    local function createRow(index)
        local row=P.Button(pane,"",1,1,function(button)
            local pressed=button.encounterPress
            button.encounterPress=nil
            if pressed and button.entry and button.entry.key==pressed and button:IsVisible() and not blocked() then
                setSelection(button.entry)
                pane:PaintPage()
            end
        end,"row")
        row:HookScript("OnMouseDown",function(button,key)
            if A.text(key)=="LeftButton" then
                button.encounterPress=button:IsVisible() and button.entry and button.entry.key or nil
            end
        end)
        row:HookScript("OnLeave",clearRowInput)
        row:HookScript("OnHide",clearRowInput)
        row:HookScript("OnEnter",function(button)
            if button.entry and not blocked() then
                local name=clipped(button.name,stacked) and button.name:GetText()
                local time=clipped(button.time,false) and button.time:GetText()
                if name or time then P.ShowTooltip(button,name and time and (name.."\n"..time) or name or time) end
            end
        end)
        row.label:Hide()
        row.name=label(row,"","name",C.text)
        row.name:SetNonSpaceWrap(true)
        row.time=label(row,"","small",C.muted)
        row.time:SetWordWrap(true)
        row.time:SetNonSpaceWrap(true)
        row.count=label(row,"","small",C.muted)
        row.faction=label(row,"","small",C.muted)
        P.RosterRowChrome(row)
        row.selectedColor=C.friendSelected
        rows[index]=row
        arrangeRow(row,index)
    end

    local function renderMetadata()
        colorPass=colorPass+1
        local pass,store,region=colorPass,A.store,A.region
        for _,slot in ipairs(rows) do
            local entry=slot.entry
            if entry and slot:IsVisible() then
                local record,known=E.blacklistRecord(entry.row)
                local class=known and known.class and known.class.value
                local r,g,b,a=P.NameColor(nil,true,class)
                if colorPass~=pass or slot.entry~=entry or not slot:IsVisible() then return end
                local checked,checkedKnown
                if known and A.store==store and A.region==region then checked,checkedKnown=E.blacklistRecord(entry.row) end
                if colorPass~=pass or slot.entry~=entry or not slot:IsVisible() then return end
                if A.store~=store or A.region~=region then
                    -- No newer pass has painted this scope yet.
                    for _,row in ipairs(rows) do row.name:SetTextColor(unpack(C.text)) end
                    detail:SetNameColor(unpack(C.text))
                    return
                end
                local checkedClass=checkedKnown and checkedKnown.class and checkedKnown.class.value
                if not class or checked~=record or checkedClass~=class then r,g,b,a=unpack(C.text) end
                slot.name:SetTextColor(r,g,b,a)
                if selectedSlot==slot and selected==entry then detail:SetNameColor(r,g,b,a) end
                local faction=factionName(checked==record and checkedKnown)
                slot.faction:SetText(faction)
                local time=slot.lastSeen
                if stacked then time=faction.." · "..time end
                if slot.time:GetText()~=time then
                    P.HideTooltip(slot)
                    slot.time:SetText(time)
                end
            end
        end
    end

    function pane:PaintPage()
        if not width then return end
        paintPass=paintPass+1
        local pass=paintPass
        local tab=tabs[current]
        local pages=pageCount(tab)
        local tabChanged=paintedTab~=tab
        if tabChanged then viewPress=nil end
        paintedTab=tab
        tab.page=math.min(tab.page,pages)
        local first=(tab.page-1)*pageSize
        local visible=math.min(pageSize,#tab.entries-first)
        for index=#rows+1,visible do createRow(index) end
        local slot
        for index,row in ipairs(rows) do
            local entry=index<=visible and tab.entries[first+index] or nil
            local rebound=tabChanged or (row.entry and row.entry.key)~=(entry and entry.key)
            if rebound then
                clearRowInput(row)
                row.name:SetTextColor(unpack(C.text))
                row.faction:SetText("")
            end
            row.entry=entry
            row.selected=entry~=nil and selected==entry
            if row.selected then slot=row end
            row:SetShown(entry~=nil)
            if entry then
                local name,time=entry.row.name:gsub("|","||"),lastSeen(entry.row)
                if paintPass~=pass then return end
                if not rebound and row.name:GetText()~=name then P.HideTooltip(row) end
                row.name:SetText(name)
                row.lastSeen=time
                if rebound then
                    row.time:SetText(stacked and (L("Unknown").." · "..time) or time)
                end
                row.count:SetText(stacked and L(entry.count==1 and "%d encounter" or "%d encounters",entry.count)
                    or tostring(entry.count))
                row.leadingEdge:SetShown(row.selected)
                P.UpdateButton(row)
            end
        end
        if selectedSlot~=slot then viewPress=nil;copyPress=nil end
        selectedSlot=slot
        for _,button in ipairs(tabs) do
            button.selected=button==tab
            button.label:SetTextColor(unpack(button.selected and C.teal or C.body))
            P.UpdateButton(button)
        end
        prev:SetShown(pages>1)
        nextPage:SetShown(pages>1)
        pageLabel:SetText(pages>1 and L("%d of %d",tab.page,pages) or "")
        P.SetEnabled(prev,tab.page>1)
        P.SetEnabled(nextPage,tab.page<pages)
        local emptyText=not E.available() and "Encounter history is unavailable."
            or (query~="" and "No matching encounters.")
            or (current==3 and not lastTime and "No completed encounters.")
            or tabEmpty[current]
        empty:SetText(L(emptyText))
        empty:SetShown(#tab.entries==0)
        header:SetShown(visible>0 and not stacked)
        local priorColorPass=colorPass
        renderSelection()
        if paintPass==pass and colorPass==priorColorPass then renderMetadata() end
    end

    function pane:Refresh(id,episode,owns)
        local now=E.now()
        if owns and not owns() then return end
        local region,revision=A.region,E.revision()
        local regionChanged=lastRegion~=region
        local clockChanged=(now==nil)~=(lastTime==nil) or (now and lastTime and now<lastTime)
        if not id and not (regionChanged or lastRevision~=revision or clockChanged
            or (now and nextBoundary and now>=nextBoundary)) then
            lastTime=now
            local pass,priorColorPass=paintPass,colorPass
            if selected then renderSelection() end
            if paintPass==pass and colorPass==priorColorPass then renderMetadata() end
            return
        end
        local groups,boundary,byId,byKey=E.groups(region,now)
        local group=byId[id]
        if id and (not group or (episode and group.episodeKeys[id]~=episode.key)) then return false end

        if group and not matches(group) then
            query=""
            search:SetText("")
        end
        local anchor=not regionChanged and firstVisible(tabs[current])
        for _,tab in ipairs(tabs) do
            tab.entries={}
            if regionChanged then tab.page=1 end
        end
        for _,entry in ipairs(groups) do
            if matches(entry) then
                local bucket=tabs[tabsBySection[entry.section]].entries
                bucket[#bucket+1]=entry
            end
        end
        if regionChanged then
            current=1
            for index,tab in ipairs(tabs) do
                if #tab.entries>0 then current=index; break end
            end
        elseif not id and selected then
            group=byKey[selected.key]
            episode=selectedEpisode
            if episode and (not group or group.episodeKeys[episode.id]~=episode.key) then group=nil end
        end
        setSelection(group,group and episode)
        if group then current=tabsBySection[group.section] end
        reveal(tabs[current],group and group.key or (anchor and anchor.key))

        local finalTab=tabs[3]
        local help=now and tabHelp[3] or endedHelp
        if finalTab.help~=help then
            P.HideTooltip(finalTab)
            finalTab.help=help
            finalTab.label:SetText(L(now and tabLabels[3] or "Ended"))
        end
        lastRegion,lastRevision,lastTime,nextBoundary=region,revision,now,boundary
        self:PaintPage()
        return group~=nil
    end

    search:SetScript("OnTextChanged",function(self)
        local value=(A.text(self:GetText()) or ""):lower()
        hint:SetShown(value=="")
        if value==query then return end
        query=value
        lastRevision=nil
        for _,tab in ipairs(tabs) do tab.page=1 end
        setSelection(nil)
        pane:Refresh()
    end)
    search:SetScript("OnEscapePressed",function(self) self:SetText("");self:ClearFocus() end)
    search:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)

    function pane:Arrange(available)
        local paneHeight=self:GetHeight()
        if paneWidth==available and height==paneHeight then return end
        local tab=tabs[current]
        local anchor=firstVisible(tab)
        paneWidth,height=available,paneHeight
        local split=available>=830
        local detailWidth=split and math.min(385,math.floor(available*.38)) or available-2*inset
        local detailHeight=split and height-110 or math.min(245,math.floor(height*.40))
        width=available-2*inset-(split and detailWidth+16 or 0)
        stacked=not split
        search:SetWidth(math.min(222,math.floor(width*.51)))
        search:ClearAllPoints()
        search:SetPoint("TOPRIGHT",pane,"TOPLEFT",inset+width,-18)
        rowTop,rowHeight=stacked and 105 or 120,stacked and 62 or 50
        local pagerBottom=split and 16 or detailHeight+16
        local footerTop=pagerBottom+pagerHeight
        detail:Arrange(split and available-detailWidth-inset or inset,split and 94 or height-detailHeight-6,detailWidth,detailHeight)
        viewEntry:ClearAllPoints();viewEntry:SetPoint("BOTTOMRIGHT",detail,"BOTTOMRIGHT",-10,8)
        pageSize=math.max(0,math.floor((height-footerTop-footerGap-rowTop)/rowHeight))
        reveal(tab,selected and selected.key or (anchor and anchor.key))

        viewPress=nil
        copyPress=nil
        for index,row in ipairs(rows) do
            clearRowInput(row)
            arrangeRow(row,index)
        end
        local tabX=inset
        for _,button in ipairs(tabs) do
            P.HideTooltip(button)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT",tabX,-55)
            tabX=tabX+button:GetWidth()+6
        end
        prev:ClearAllPoints()
        prev:SetPoint("BOTTOMLEFT",inset,pagerBottom)
        nextPage:ClearAllPoints()
        nextPage:SetPoint("BOTTOMLEFT",121,pagerBottom)
        pageLabel:ClearAllPoints()
        pageLabel:SetPoint("BOTTOMLEFT",220,pagerBottom+6)
        empty:SetWidth(width)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT",inset,-94)
        header:SetSize(width,22)
        if not stacked then cells(header,true) end
        self:PaintPage()
    end

    local elapsed=0
    pane:SetScript("OnUpdate",function(self,delta)
        elapsed=elapsed+delta
        if elapsed>=1 then elapsed=0; self:Refresh() end
    end)
    pane:SetScript("OnShow",function(self) self:Refresh() end)
    pane:SetScript("OnHide",function()
        paintPass=paintPass+1
        colorPass=colorPass+1
        search:ClearFocus()
        viewPress=nil
        copyPress=nil
        for _,tab in ipairs(tabs) do P.HideTooltip(tab) end
        for _,row in ipairs(rows) do clearRowInput(row) end
    end)
    return pane
end
