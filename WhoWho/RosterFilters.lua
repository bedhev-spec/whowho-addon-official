local P=WhowhoPreview
local L,C=P.L,P.colors

-- The page owns the query, selected filters, and records. These controls
-- present the choices and share dismissal with the existing roster shield.
function P.CreateRosterFilters(list,S)
    local order={}
    function S.ArrangeFilterChoices()
        local key=S.section=="blacklist" and "classFilter" or S.filterFacet
        local inline=S.facetLinks and (S.section=="friend" or S.section=="blacklist")
        local width=inline and math.max(100,list:GetWidth()-48) or 248
        local x,y=8,inline and 5 or 44
        for _,button in ipairs(order[key]) do
            local span=inline and math.min(width-16,math.ceil(button.label:GetUnboundedStringWidth())+34) or 228
            if inline and x+span>width-8 then x=8; y=y+28 end
            button:ClearAllPoints()
            button:SetWidth(span)
            button:SetPoint("TOPLEFT",x,-y)
            if inline then x=x+span+3 else y=y+27 end
        end
        S.filterMenu:SetSize(width,y+(inline and 31 or 10))
    end
    local function refreshFilterMenu(manualBlacklist)
        local shownKey=manualBlacklist and "classFilter" or S.filterFacet
        local inline=S.facetLinks and (S.section=="friend" or manualBlacklist)
        S.blacklistFilterTitle:SetShown(manualBlacklist==true and not inline)
        local active=0
        for key,options in pairs(S.filterChoices) do
            local tab=S.filters[key]
            tab:SetShown(not manualBlacklist and not inline)
            tab.selected=key==shownKey
            P.UpdateButton(tab)
            P.SetPaletteText(tab.label,tab.selected and C.teal or C.text)
            tab.indicator:SetShown(tab.selected)
            if S[key] and (not manualBlacklist or key=="classFilter") then active=active+1 end
            local trigger=S.facetLinks and S.facetLinks[key]
            if trigger then
                local selected=options[S[key]]
                local text=selected and selected.label:GetText() or trigger.caption
                if text~=trigger.label:GetText() then trigger.label:SetText(text); S.facetLayoutDirty=true end
                P.SetPaletteText(trigger.label,selected and C.teal or C.muted)
            end
            for value,button in pairs(options) do

                button:SetShown(key==shownKey)
                button.selected=(S[key] or "ALL")==value
                P.UpdateButton(button)
                P.SetPaletteText(button.label,button.selected and C.teal or C.text)
                button.indicator:SetShown(button.selected)
            end
        end
        S.ArrangeFilterChoices()
        S.filterToggle.label:SetText(active>0 and L("Filters (%d)",active) or L("Filters"))
        return active
    end
    S.RefreshFilterMenu=refreshFilterMenu
    S.filterToggle=P.Button(list,L("Filters"),124,36,function() if not S.scrim:IsShown() then S.filterMenu:SetShown(not S.filterMenu:IsShown()) end end); S.filterToggle:SetPoint("TOPRIGHT",-24,-78)
    P.ButtonIcon(S.filterToggle,"filter",20)
    S.filterMenu=CreateFrame("Frame","WhowhoPreviewFilterMenu",list); S.filterMenu:SetWidth(248); S.filterMenu:SetPoint("TOPRIGHT",S.filterToggle,"BOTTOMRIGHT",0,0); S.filterMenu:SetFrameLevel(list:GetFrameLevel()+10); P.PopupMaterial(S.filterMenu); S.filterMenu:Hide(); table.insert(UISpecialFrames,"WhowhoPreviewFilterMenu")
    if P.manual then
        local edge,fill=P.NoteInset(S.filterMenu)
        edge:SetAllPoints(S.filterMenu)
        P.SetPaletteFill(fill,C.raised)
    end
    S.filterChoices={}; S.filterChoiceCounts={}; S.filters={}; S.filterFacet="roleFilter"
    S.blacklistFilterTitle=P.Label(S.filterMenu,L("Class"),"action",C.teal)
    S.blacklistFilterTitle:SetPoint("TOPLEFT",20,-14); S.blacklistFilterTitle:SetJustifyH("LEFT")
    S.filterMenu:EnableMouse(true); S.filterMenu:EnableMouseWheel(true)
    S.filterMenu:SetPropagateMouseClicks(false); S.filterMenu:SetPropagateMouseMotion(false)
    S.filterMenu:SetScript("OnMouseWheel",function() end)
    S.filterMenu:SetScript("OnShow",function()
        if S.facetLinks then S.ArrangeFilterChoices() end
        P.ClearTooltip()
        for _,row in ipairs(S.rows) do P.RosterRows.ClearHover(row) end
    end)
    S.filterShield=P.DismissOutside(S.filterMenu,list)
    if P.manual then S.facetLinks={} end
    S.filterMenu:HookScript("OnHide",function() S.hoverFacet=nil end)
    local function openFacet(link,key,hover)
        if S.scrim:IsShown() or not (S.section=="friend" or (S.section=="blacklist" and key=="classFilter")) then return end
        S.hoverFacet=hover and link or nil
        S.filterFacet=key
        refreshFilterMenu(S.section=="blacklist")
        local x=-(link.facetOffset or 0)
        S.filterMenu:ClearAllPoints()
        S.filterMenu:SetPoint("TOPLEFT",link,"BOTTOMLEFT",x,0)
        S.filterMenu:Show()
    end
    local function choices(key,title,values,column)
        if S.facetLinks then
            local link=P.Button(list,L(title),84,26,function(self) openFacet(self,key,false) end,"action")
            link.caption=L(title)
            link:SetFrameLevel(S.filterMenu:GetFrameLevel())
            P.Type(link.label,"small")
            P.ButtonContent(link,7,15,"LEFT")
            local caret=P.ActionGlyph(link,"down",12,C.muted); caret:SetPoint("RIGHT",-1,0)
            link:HookScript("OnEnter",function(self) openFacet(self,key,true) end)
            link:Hide(); S.facetLinks[key]=link
        end
        local tab=P.Button(S.filterMenu,L(title),76,28,function()
            S.filterFacet=key
            refreshFilterMenu(false)
        end,"action")
        tab:SetPoint("TOPLEFT",10+(column-1)*76,-8)
        tab.indicator=P.Rule(tab,8,27,8,C.selectedRule)
        S.filters[key]=tab
        S.filterChoices[key]={}; S.filterChoiceCounts[key]=#values; order[key]={}
        for index, option in ipairs(values) do
            local caption,value=option[1],option[2] or option[1]
            local button=P.Button(S.filterMenu,L(caption),228,26,function()
                if value=="ALL" then S[key]=nil else S[key]=value end
                if S.facetLinks then S.filterMenu:Hide() end
                S.offset=0; S.revealSaved=false; S.savedOutside=false; S.Refresh()
            end,"row")
            order[key][index]=button
            button:SetPoint("TOPLEFT",10,-44-(index-1)*27); P.Type(button.label,"small"); P.ButtonContent(button,6,22,"LEFT")
            button.indicator=P.Glyph(button,"online",14,C.teal)
            button.indicator:SetPoint("RIGHT",-4,0)
            S.filterChoices[key][value]=button
        end
    end
    choices("roleFilter","Role",{{"All","ALL"},{"No role","UNASSIGNED"},{"Tank","TANK"},{"Healer","HEALER"},{"DPS","DAMAGER"}},1)
    choices("classFilter","Class",{{"All","ALL"},{"Warrior","WARRIOR"},{"Paladin","PALADIN"},{"Hunter","HUNTER"},{"Rogue","ROGUE"},{"Priest","PRIEST"},{"Shaman","SHAMAN"},{"Mage","MAGE"},{"Warlock","WARLOCK"},{"Druid","DRUID"},{"Unknown","UNASSIGNED"}},2)
    local statuses={{"All","ALL"}}
    for _,caption in ipairs(P.RosterModel.presenceChoices) do statuses[#statuses+1]={caption} end
    choices("statusFilter","Presence",statuses,3)
    local function clearFilters()
        S.filterMenu:Hide()
        S.roleFilter,S.classFilter,S.statusFilter=nil,nil,nil
        S.revealSaved,S.savedOutside,S.offset=false,false,0
        S.Refresh()
    end
    if S.facetLinks then
        S.filterMenu:HookScript("OnUpdate",function(self)
            if S.hoverFacet and not self:IsMouseOver() and not S.hoverFacet:IsMouseOver() then self:Hide() end
        end)
        S.resetFacets=P.Button(list,L("Clear filters"),28,26,clearFilters,"action")
        S.resetFacets.label:Hide(); P.ButtonIcon(S.resetFacets,"close",13); P.Tooltip(S.resetFacets,L("Clear filters"))
        S.resetFacets:SetFrameLevel(S.filterMenu:GetFrameLevel())
    end
    S.clearFilters=P.Button(list,L("Clear filters"),148,30,clearFilters); S.clearFilters:SetPoint("TOPLEFT",170,-205)
end
