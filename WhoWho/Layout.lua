local P=WhowhoPreview
local L=P.L
local S=P.Shell
local D=P.LayoutMetrics
local function at(widget,x,y)
    widget:ClearAllPoints(); widget:SetPoint("TOPLEFT",x,-y)
end
local headerTop,headerHeight,actionInset=23,36,12
local rowTop,rowPitch=150,D.rowHeight
local arrangedWidth,arrangedStacked,arrangedFavoriteInset,arrangedSection
local headerWidth,headerSection
local function arrangeFacetLinks(top)
    S.facetLayoutHidden=not S.list:IsVisible()
    local x=0
    local available=S.list:GetWidth()-48
    local keys=S.section=="blacklist" and {"classFilter"} or {"roleFilter","classFilter","statusFilter"}
    for _,key in ipairs(keys) do
        local link=S.facetLinks[key]
        local width=math.min(available-30,math.ceil(link.label:GetUnboundedStringWidth())+25)
        if x+width+(key=="statusFilter" and 30 or 0)>available then x=0; top=top+26 end
        link:SetWidth(width); link.facetOffset=x
        at(link,24+x,top); x=x+width
    end
    at(S.resetFacets,24+x,top)
    return top+28
end
function S.RosterRowCount()
    local width=S.list:GetWidth()
    local guild=S.section=="guildBlacklist"
    local blacklist=P.manual and (guild or S.section=="blacklist")
    if width~=headerWidth or S.section~=headerSection or S.facetLayoutDirty then
        headerWidth,headerSection=width,S.section
        S.facetLayoutDirty=false
        arrangedWidth=nil
        local titleWidth=math.ceil(S.pageTitle:GetUnboundedStringWidth())+2
        S.pageTitle:SetWidth(blacklist and math.min(titleWidth,width-200) or 0)
        S.pageTitle:SetWordWrap(blacklist==true)
        S.pageTitle:SetHeight(0)
        local titleHeight=math.max(headerHeight,math.ceil(S.pageTitle:GetStringHeight()))
        S.pageTitle:SetHeight(titleHeight)
        S.pageTitle:SetJustifyV("MIDDLE")
        local rowInset=P.manual and 15 or headerTop
        at(S.pageTitle,24,rowInset)
        S.addButton:ClearAllPoints()
        S.addButton:SetPoint("TOPRIGHT",-24,-rowInset-(titleHeight-S.addButton:GetHeight())/2)
        local bandHeight=titleHeight+2*rowInset
        local searchTop=P.manual and bandHeight+14 or math.max(78,headerTop+titleHeight+10)
        local inline=S.facetLinks and (S.section=="friend" or S.section=="blacklist")
        if inline and S.section=="friend" then
            S.refreshButton:ClearAllPoints()
            if width>=590 then
                S.refreshButton:SetPoint("RIGHT",S.addButton,"LEFT",-8,0)
            else
                at(S.refreshButton,24,rowInset+titleHeight+6)
                bandHeight=rowInset+titleHeight+6+S.refreshButton:GetHeight()+4
                searchTop=bandHeight+14
            end
        end
        if guild and S.guildPeers:IsShown() then
            at(S.guildPeers,24,searchTop)
            searchTop=searchTop+math.max(16,math.ceil(S.guildPeers:GetStringHeight()))+10
        end
        S.rosterHeader:SetHeight(P.manual and bandHeight or searchTop-13)
        at(S.searchBox,24,searchTop)
        S.filterToggle:ClearAllPoints(); S.filterToggle:SetPoint("TOPRIGHT",-24,-searchTop)
        local sortTop=searchTop+40
        S.filterMenu:ClearAllPoints()
        if inline then
            sortTop=arrangeFacetLinks(searchTop+38)
            local link=S.facetLinks[S.section=="blacklist" and "classFilter" or S.filterFacet]
            S.ArrangeFilterChoices()
            S.filterMenu:SetPoint("TOPLEFT",link,"BOTTOMLEFT",-link.facetOffset,0)
        else
            S.filterMenu:SetPoint("TOPRIGHT",S.filterToggle,"BOTTOMRIGHT",0,0)
        end
        at(S.sortButton,32,sortTop)
        rowTop=sortTop+32
        S.rosterRule:ClearAllPoints()
        S.rosterRule:SetPoint("TOPLEFT",24,-rowTop+1)
        S.rosterRule:SetPoint("TOPRIGHT",-24,-rowTop+1)
        at(S.emptyLabel,40,rowTop+25)
        at(S.clearSearch,40,rowTop+65)
        at(S.clearFilters,170,rowTop+65)
    end
    local bottomInset=52
    if S.facetLinks then
        if S.section=="friend" then bottomInset=1
        elseif S.section=="blacklist" then bottomInset=49 end
    end
    return math.min(#S.rows,math.floor((S.list:GetHeight()-bottomInset-rowTop)/rowPitch))
end

function S.ArrangeRoster()
    local width=S.list:GetWidth()
    local cramped=width<535
    local guild=S.section=="guildBlacklist"
    local blacklist=P.manual~=nil and (guild or S.section=="blacklist")
    local compactCount=width<490 or (blacklist and width-200-S.pageTitle:GetWidth()<144)
    local favoriteInset=P.manual and S.section=="friend" and 30 or 0
    local presenceX=math.min(math.floor((width-48)*0.542)+24,width-309)
    if not cramped and not blacklist then
        for _,row in ipairs(S.rows) do
            if row.record then
                local _,_,_,gap=row.role:GetPoint()
                local endX=22+favoriteInset+row.meta:GetStringWidth()+gap+row.role:GetStringWidth()
                if endX+8>presenceX-18 then cramped=true; break end
            end
        end
    end
    local glyphsChanged=false
    for _,row in ipairs(S.rows) do
        if row.arrangedStatusGlyph~=row.statusIcon:IsShown() then glyphsChanged=true; break end
    end
    if width==arrangedWidth and cramped==arrangedStacked and favoriteInset==arrangedFavoriteInset
        and S.section==arrangedSection and not glyphsChanged then
        return cramped,compactCount
    end
    arrangedWidth,arrangedStacked,arrangedFavoriteInset=width,cramped,favoriteInset
    arrangedSection=S.section
    S.searchBox:SetWidth(width-((guild or S.facetLinks) and 48 or 184))
    S.searchBox:SetTextInsets(36,blacklist and 34 or 12,4,4)
    S.emptyLabel:SetWidth(width-80); S.emptyLabel:SetWordWrap(true)
    at(S.columnPresence,presenceX,rowTop-27); S.columnPresence:SetShown(not cramped and not blacklist)
    S.count:ClearAllPoints()
    if compactCount and not (S.facetLinks and S.section=="friend") then S.count:SetPoint("BOTTOMLEFT",24,actionInset)
    elseif S.facetLinks and S.section=="friend" and width<590 then S.count:SetPoint("LEFT",S.refreshButton,"RIGHT",10,0)
    else S.count:SetPoint("LEFT",S.pageTitle,"RIGHT",16,0) end
    if S.refreshLabel then S.refreshLabel:SetShown(not compactCount) end
    for i,row in ipairs(S.rows) do
        if not P.manual then at(row,18,rowTop+(i-1)*rowPitch) end
        row:SetSize(width-36,rowPitch)
        local nameWidth=(cramped and width-(P.manual and 172 or 144) or presenceX-54)-favoriteInset
        if blacklist then nameWidth=width-(guild and 108 or 180) end
        row.name:SetWidth(nameWidth); row.note:SetWidth(nameWidth)
        if P.manual then
            at(row.name,22+favoriteInset,blacklist and 15 or 9)
            at(row.note,22+favoriteInset,blacklist and 44 or 54)
            row.meta:ClearAllPoints(); row.meta:SetPoint("LEFT",22+favoriteInset,0)
        end
        row.note:SetShown(blacklist or not cramped)
        row.status:SetShown(not blacklist)
        row.role:SetShown(true)
        row.status:ClearAllPoints()
        local presenceY=cramped and -24 or 0
        local hasGlyph=row.statusIcon:IsShown()
        row.arrangedStatusGlyph=hasGlyph
        local glyphSpace=20+(cramped and 3 or 2)
        row.status:SetPoint("LEFT",(cramped and 45 or presenceX+4)-(hasGlyph and 0 or glyphSpace),presenceY)
        row.status:SetPoint("RIGHT",P.manual and row.inviteButton or row.copyButton,"LEFT",-16,presenceY)
        row.statusIcon:ClearAllPoints()
        row.statusIcon:SetPoint("RIGHT",row.status,"LEFT",cramped and -3 or -2,0)
        P.Type(row.status,cramped and "meta" or "body")
    end
    return cramped,compactCount
end

function S.ArrangeFavoriteRows(count, visibleRows)
    if not S.favoriteHeading then return end
    local y=rowTop
    S.otherFriendsHeading:Hide()
    S.favoriteHeading:SetShown(count>0)
    local boundary=count-S.offset
    if count>0 then
        S.favoriteHeading:SetText(L(boundary>0 and "Favorites" or "Other Friends"))
        at(S.favoriteHeading,40,y+3)
        y=y+23
    end
    for i,row in ipairs(S.rows) do
        if count>0 and i==boundary+1 and i>1 and i<=visibleRows and S.filtered[S.offset+i] then
            at(S.otherFriendsHeading,40,y+3)
            S.otherFriendsHeading:Show()
            y=y+23
        end
        at(row,18,y)
        y=y+rowPitch
    end
end

local function textViewport(view,label,width,height)
    local textHeight=math.max(1,math.ceil(label:GetStringHeight()))
    view:SetSize(width,height)
    view.content:SetSize(width,math.max(textHeight,height))
    local limit=math.max(0,textHeight-height)
    view:EnableMouseWheel(limit>0)
    if view:GetVerticalScroll()>limit then view:SetVerticalScroll(limit) end
end

local function detailRule(line,y)
    line:ClearAllPoints(); line:SetPoint("TOPLEFT",25,-y); line:SetPoint("TOPRIGHT",-25,-y)
end

local function arrangeManualDetail(d,width,nameY,nameHeight,nameWidth)
    local friends=S.section=="friend"
    local guild=S.section=="guildBlacklist"
    local y=nameY+nameHeight+6
    at(d.meta,25,y)
    y=y+math.max(d.meta:GetStringHeight(),friends and d.role:GetStringHeight() or 0)+6
    if friends and d.affiliation:IsShown() then
        d.affiliation:SetWidth(width); d.affiliation:SetWordWrap(true)
        at(d.affiliation,25,y)
        y=y+d.affiliation:GetStringHeight()+5
    end
    detailRule(d.rule1,y+5)
    y=y+18
    if friends then
        S.checkStatus:ClearAllPoints()
        -- Keep the action centered beside the first line, including names with descenders.
        if d.name:GetUnboundedStringWidth()<=nameWidth then
            d.name:SetWidth(0)
            S.checkStatus:SetPoint("LEFT",d.name,"RIGHT",1,0)
        else
            local _,fontSize=d.name:GetFont()
            at(S.checkStatus,26+nameWidth+1,nameY+(fontSize-S.checkStatus:GetHeight())/2+2)
        end
        local valueX=25+math.max(72,math.ceil(d.observationLabel:GetUnboundedStringWidth())+10,
            math.ceil(d.attemptLabel:GetUnboundedStringWidth())+10,math.ceil(d.heading:GetUnboundedStringWidth())+10)
        local valueWidth=width-valueX+25
        at(d.heading,25,y+4)
        at(d.current,valueX+(d.statusIcon:IsShown() and 24 or 0),y-2)
        y=y+26
        d.observation:SetWidth(valueWidth); d.observation:SetWordWrap(true)
        at(d.observationLabel,25,y+1); at(d.observation,valueX,y)
        y=y+math.max(21,math.ceil(d.observation:GetStringHeight()))+4
        d.attempt:SetWidth(valueWidth); d.attempt:SetWordWrap(true)
        at(d.attemptLabel,25,y+1); at(d.attempt,valueX,y)
        y=y+math.ceil(d.attempt:GetStringHeight())+14
    else
        at(d.reasonLabel,25,y)
        y=y+d.reasonLabel:GetStringHeight()+5
        d.reasons:SetWidth(width)
        local height=math.max(1,math.min(80,math.ceil(d.reasons:GetStringHeight())))
        at(d.reasonView,25,y); textViewport(d.reasonView,d.reasons,width,height)
        y=y+height+14
    end
    local inset=S.selected~=nil
    d.noteEdge:SetShown(inset); d.noteFill:SetShown(inset)
    local bar=d.noteView.scrollbar
    local footer=S.savedOutside and 479 or D.paneHeight-actionInset-44
    detailRule(d.rule2,footer); d.rule2:SetShown(inset and not guild)
    if not inset then d.noteLabel:Hide(); d.noteView:Hide(); bar:Hide(); return end
    d.noteLabel:Show(); d.noteView:Show()
    local noteWidth=width-26
    local noteY=y+12+d.noteLabel:GetStringHeight()+7
    local remaining=footer-noteY-17
    if not friends then
        d.affiliation:SetWidth(width); d.affiliation:SetWordWrap(true)
        d.observation:SetWidth(width); d.observation:SetWordWrap(true)
        if d.observation:IsShown() then remaining=remaining-d.observation:GetStringHeight()-d.observationLabel:GetStringHeight()-18 end
        if d.affiliation:IsShown() then remaining=remaining-d.affiliation:GetStringHeight()-d.factionLabel:GetStringHeight()-18 end
    end
    d.note:SetWidth(noteWidth)
    local height=math.max(20,math.min(96,remaining,math.ceil(d.note:GetStringHeight())+2))
    local overflow=math.ceil(d.note:GetStringHeight())>height
    if overflow then noteWidth=noteWidth-14; d.note:SetWidth(noteWidth) end
    at(d.noteLabel,38,y+12); at(d.noteView,38,noteY)
    textViewport(d.noteView,d.note,noteWidth,height)
    at(d.noteEdge,25,y); d.noteEdge:SetSize(width,noteY-y+height+10)
    if overflow then
        local contentHeight=math.ceil(d.note:GetStringHeight())
        at(bar,25+width-17,noteY); bar:SetHeight(height)
        bar:GetThumbTexture():SetSize(6,math.max(12,height*height/contentHeight))
        local offset=d.noteView:GetVerticalScroll()
        bar:SetMinMaxValues(0,contentHeight-height); bar:SetValue(offset)
    end
    bar:SetShown(overflow)
    if not friends then
        y=noteY+height+22
        if d.observation:IsShown() then
            at(d.observationLabel,25,y); y=y+d.observationLabel:GetStringHeight()+4
            at(d.observation,25,y); y=y+d.observation:GetStringHeight()+12
        end
        if d.affiliation:IsShown() then
            at(d.factionLabel,25,y); at(d.affiliation,25,y+d.factionLabel:GetStringHeight()+4)
        end
    end
end

function S.ArrangeRecordText()
    local d=S.detail
    local width=S.details:GetWidth()-50
    local shift=S.layoutMode=="compact" and 53 or 0
    local slim=S.details:GetWidth()<350
    local friends=P.manual and S.section=="friend"
    local nameWidth=friends and width-38 or width
    local nameInset=friends and 26 or 25
    nameWidth=nameWidth-(nameInset-25)
    d.name:SetWidth(nameWidth)
    local nameHeight=math.max(1,math.min(57,math.ceil(d.name:GetStringHeight())))
    local nameY=headerTop+shift+math.max(0,(headerHeight-nameHeight)/2)
    at(d.nameView,nameInset,nameY); textViewport(d.nameView,d.name,nameWidth,nameHeight)
    S.blacklistDetailsBackground:SetShown(P.manual~=nil); S.detailsPaper:SetShown(P.manual==nil)
    if P.manual then arrangeManualDetail(d,width,nameY,nameHeight,nameWidth); return end
    local divider,notesDivider
    local values=S.layoutMode=="compact" and 136 or 116
    local valueWidth=S.details:GetWidth()-values-18
    d.observation:SetWidth(valueWidth); d.observation:SetWordWrap(slim)
    d.note:SetWidth(width)
    local metaY=math.max(63+shift,nameY+nameHeight+3)
    at(d.meta,25,metaY)
    divider=metaY+math.max(18,d.meta:GetStringHeight(),d.role:GetStringHeight())+18
    if d.affiliation and d.affiliation:IsShown() then
        d.affiliation:SetWidth(width); d.affiliation:SetWordWrap(true)
        at(d.affiliation,25,divider-11)
        divider=divider+math.ceil(d.affiliation:GetStringHeight())+5
    end
    local extra=slim and 23 or 0
    at(d.heading,25,divider+17)
    S.checkStatus:ClearAllPoints(); S.checkStatus:SetPoint("TOPRIGHT",-25,-divider-(slim and 49 or 14))
    at(d.current,d.statusIcon:IsShown() and 49 or 25,divider+52)
    at(d.observationLabel,25,divider+88); at(d.observation,values,divider+87)
    local attemptY=divider+113+extra
    at(d.attemptLabel,25,attemptY+1); at(d.attempt,values,attemptY)
    d.attempt:SetWidth(valueWidth); d.attempt:SetWordWrap(true)
    notesDivider=attemptY+math.max(46,math.ceil(d.attempt:GetStringHeight())+12)

    detailRule(d.rule1,divider); detailRule(d.rule2,notesDivider)
    at(d.noteLabel,25,notesDivider+16)
    local noteY=notesDivider+46
    local noteBottom=S.savedOutside and 479 or D.paneHeight-actionInset-46
    at(d.noteView,25,noteY); textViewport(d.noteView,d.note,width,math.max(1,noteBottom-noteY))
    d.noteEdge:Hide(); d.noteFill:Hide()
end

function S.Layout()
    if not S.window then return end
    S.layoutViewportWidth,S.layoutViewportHeight=UIParent:GetWidth(),UIParent:GetHeight()
    local width=math.max(D.minimumWidth,math.min(D.windowWidth,(UIParent:GetWidth()-D.viewportMargin)/(P.db.scale or 1)))
    local navWidth=width<1120 and D.compactNavWidth or D.wideNavWidth
    local available=width-navWidth
    S.layoutMode=width<940 and "compact" or width<1120 and "intermediate" or "wide"
    local compact=S.layoutMode=="compact"
    S.window:SetSize(width,D.windowHeight); at(S.navFrame,0,D.headerHeight); S.navFrame:SetSize(navWidth,D.paneHeight)
    S.ResetFooter()
    S.footer:SetWidth(width-48); S.footer:SetWordWrap(false)
    at(S.footer,24,689)
    if S.refreshStatus then S.refreshStatus:SetWidth(width-48) end
    local narrow=navWidth==D.compactNavWidth
    local guildNav=S.nav.guildBlacklist
    local defaultHeight=narrow and 48 or 40
    local guildHeight=defaultHeight
    if guildNav then
        guildNav.label:SetText(L(narrow and guildNav.compactCaption or guildNav.caption))
        guildNav.label:SetWidth(narrow and 72 or 105)
        guildNav.label:SetWordWrap(true)
        local role=narrow and (guildNav.selected and "compactSelected" or "compactNav")
            or (guildNav.selected and "section" or "nav")
        P.Type(guildNav.label,role)
        local padding=narrow and 27 or 4
        guildHeight=math.max(narrow and 60 or defaultHeight,padding+math.ceil(guildNav.label:GetStringHeight()))
    end
    for _,button in pairs(S.nav) do
        local isGuild=button==guildNav
        local extraSpace=guildNav and button.index>guildNav.index and guildHeight-defaultHeight or 0
        button:SetSize(narrow and 72 or 160,isGuild and guildHeight or defaultHeight)
        at(button,narrow and 4 or 12,32+(button.index-1)*(narrow and 52 or 50)+extraSpace)
        if not isGuild then
            button.label:SetWidth(narrow and navWidth or 105)
            button.label:SetWordWrap(true)
        end
        button.icon:ClearAllPoints(); button.label:ClearAllPoints()
        if narrow then
            button.icon:SetPoint("TOP",0,-2); button.label:SetPoint("BOTTOM",0,3); button.label:SetJustifyH("CENTER")
        else
            button.icon:SetPoint("LEFT",15,0); button.label:SetPoint("LEFT",48,0); button.label:SetJustifyH("LEFT")
        end
    end
    local detailWidth=S.layoutMode=="wide" and D.wideDetailWidth or 300
    local listWidth=compact and available or available-detailWidth
    at(S.list,navWidth,D.headerHeight); S.list:SetSize(listWidth,D.paneHeight)

    if not S.facetLinks then
        S.refreshButton:ClearAllPoints(); S.refreshButton:SetPoint("BOTTOMRIGHT",-24,actionInset)
    end
    if S.refreshLabel then
        S.refreshLabel:ClearAllPoints(); S.refreshLabel:SetPoint("BOTTOMLEFT",24,actionInset)
        S.refreshLabel:SetHeight(34); S.refreshLabel:SetJustifyV("MIDDLE")
    end
    S.editButton:ClearAllPoints(); S.editButton:SetPoint("BOTTOMLEFT",25,actionInset)
    if S.moveButton then
        S.moveButton:ClearAllPoints(); S.moveButton:SetPoint("LEFT",S.editButton,"RIGHT",6,0)
    end
    at(S.details,compact and navWidth or navWidth+listWidth,D.headerHeight)
    S.details:SetSize(compact and available or detailWidth,D.paneHeight); S.ArrangeRecordText()
    at(S.backButton,24,24); S.backButton:SetSize(154,34)
    for _,pane in ipairs({S.settings,S.encounters}) do
        at(pane,navWidth,D.headerHeight); pane:SetSize(available,D.paneHeight); pane:Arrange(available)
    end
    if S.filtered then S.Refresh() end
end
