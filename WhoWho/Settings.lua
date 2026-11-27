local P=WhowhoPreview
local C=P.colors
local L=P.L

local defaultRow={padding=8,lineGap=3,minHeight=56}
local generalRow={padding=6,lineGap=3,minHeight=52,singleLineHeight=44,center=true,
    scaleGap=42,titleGap=26,sectionGap=16,rowGap=5}
local compactGeneralRow={padding=3,lineGap=1,minHeight=44,center=true,compact=true,
    scaleGap=34,titleGap=24,sectionGap=10,rowGap=2}

local function position(widget,x,y)
    widget:ClearAllPoints(); widget:SetPoint("TOPLEFT",x,-y)
end

local contentTop=112
local function scrollPage(parent)
    local view=CreateFrame("ScrollFrame",nil,parent)
    view:SetPoint("TOPLEFT",0,-contentTop)
    view:SetClipsChildren(true)
    local content=CreateFrame("Frame",nil,view)
    view:SetScrollChild(content)
    view:SetScript("OnMouseWheel",function(self,delta)
        self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-32*delta)))
    end)
    return view,content
end

local function arrangeScroll(view,content,width,viewHeight,bodyHeight)
    content:SetSize(width,bodyHeight)
    view:SetSize(width,viewHeight)
    local limit=math.max(0,bodyHeight-viewHeight)
    view:EnableMouseWheel(limit>0)
    view:SetVerticalScroll(math.min(view:GetVerticalScroll(),limit))
end

local function paintSwatch(button)
    local checked=not not button:GetChecked()
    button.mark:SetShown(checked)
    button.ring:SetShown(checked or button.hovered==true)
    button.ring:SetVertexColor(unpack(checked and C.text or C.muted))
end

local swatchHitSize,swatchGap=30,8
local function interfaceSwatch(parent,preset)
    local button=CreateFrame("CheckButton",nil,parent)
    button:SetSize(swatchHitSize,swatchHitSize)
    local circle=CreateFrame("Frame",nil,button)
    circle:SetSize(20,20); circle:SetPoint("CENTER")
    local fill=P.Material(circle,"RoundFill")
    fill:SetVertexColor(unpack(preset.swatch))
    button.ring=P.Material(circle,"RoundEdge",nil,"ARTWORK")
    -- Outside the circle, so a pale swatch cannot swallow the ring.
    button.ring:ClearAllPoints(); button.ring:SetSize(26,26); button.ring:SetPoint("CENTER")
    button.mark=P.Glyph(circle,"online",12,preset.swatchInk)
    button.mark:SetPoint("CENTER")
    button:SetScript("OnClick",function(self)
        P.SetInterfaceColor(preset.id)
        self:SetChecked(true)
    end)
    P.BindButtonFeedback(button,paintSwatch)
    P.Tooltip(button,L(preset.label))
    button:HookScript("OnHide",P.HideTooltip)
    P.BindPalette(button,function(self,id)
        self:SetChecked(id==preset.id)
        paintSwatch(self)
    end)
    return button
end

function P.CreateSettings(window,S)
    local pane=CreateFrame("Frame",nil,window)
    P.Paint(pane,C.panel)
    local selected="alerts"
    local tabs={{"alerts","Alerts"},{"friends","Friends"},{"general","General"}}
    local pages={}
    S.settingsTabs={}
    local function label(text,role,color,parent)
        local f=P.Label(parent or pane,L(text),role,color)
        f:SetJustifyH("LEFT")
        return f
    end
    local function slider(parent,enabled)
        local control=CreateFrame("Slider",nil,parent)
        control:SetSize(142,24); control:SetOrientation("HORIZONTAL")
        local track=control:CreateTexture(nil,"BACKGROUND")
        track:SetPoint("LEFT",0,0); track:SetPoint("RIGHT",0,0); track:SetHeight(3)
        P.SetPaletteFill(track,enabled and C.controlTrack or C.line)
        control:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local thumb=control:GetThumbTexture(); thumb:SetSize(10,16); P.SetPaletteTint(thumb,enabled and C.teal or C.disabled)
        if not enabled then control:Disable() end
        return control
    end

    P.PageHeader(pane,60)
    local title=label("Settings","page")
    local tabRule=pane:CreateTexture(nil,"BORDER")
    tabRule:SetHeight(1); tabRule:SetColorTexture(unpack(C.line))
    local function selectPage(key)
        selected=key
        for _,tab in ipairs(tabs) do
            local id=tab[1]
            local button=S.settingsTabs[id]
            button.selected=id==selected
            button.label:SetTextColor(unpack(button.selected and C.teal or C.body))
            P.ResetButtonFeedback(button)
            pages[id]:SetShown(button.selected)
        end
        if key=="general" and pane.RefreshGuildAvailability then pane:RefreshGuildAvailability() end
    end
    for _,tab in ipairs(tabs) do
        local key,caption=unpack(tab)
        local page=CreateFrame("Frame",nil,pane)
        page:SetAllPoints(pane)
        pages[key]=page
        S.settingsTabs[key]=P.TextTab(pane,L(caption),40,function()
            if selected==key then return end
            pane:CancelScale()
            P.ClearTooltip()
            selectPage(key)
        end)
    end
    selectPage(selected)

    local friends=pages.friends
    local alertView,alerts=scrollPage(pages.alerts)
    local generalView,general=scrollPage(pages.general)
    local windowTitle=label("Window","section",nil,general)
    local scaleTitle=label("Window scale","body",C.body,general)
    S.scaleSlider=slider(general,true); S.scaleLabel=label("","body",C.body,general)
    S.scaleSlider:SetMinMaxValues(P.ScaleLimits()); S.scaleSlider:SetValueStep(.05); S.scaleSlider:SetObeyStepOnDrag(true)
    local control=S.scaleSlider
    local dragging,released,syncing,cancelled=false,false,false,false
    local function display(value)
        S.scaleLabel:SetText(string.format("%d%%",math.floor(value*100+.5)))
    end
    function pane:SyncScale(value)
        dragging=false; released=false; control:SetScript("OnUpdate",nil)
        syncing=true
        control:SetMinMaxValues(P.ScaleLimits())
        if control:GetValue()~=value then control:SetValue(value) end
        syncing=false
        display(value)
    end
    function pane:CancelScale()
        if dragging then cancelled=true; self:SyncScale(P.db.scale) end
    end
    local function finishGesture()
        if dragging then
            dragging=false; released=false; control:SetScript("OnUpdate",nil)
            P.SetScale(control:GetValue())
        end
    end
    local function afterPointerEvents()
        -- Release can occur outside the track. Read the slider after native
        -- mouse-up/value callbacks have finished, with its parent still stable.
        if released or not IsMouseButtonDown("LeftButton") then finishGesture() end
    end
    local function beginGesture()
        cancelled=false
        if not dragging then dragging=true; control:SetScript("OnUpdate",afterPointerEvents) end
    end
    pane:SyncScale(P.db.scale)
    control:SetScript("OnMouseDown",function(_,button)
        if button=="LeftButton" then
            if released then finishGesture() end
            beginGesture()
        end
    end)
    control:SetScript("OnMouseUp",function(_,button)
        if button=="LeftButton" and dragging then released=true end
    end)
    control:SetScript("OnValueChanged",function(self,value)
        if syncing then return end
        if cancelled and not self:IsVisible() then pane:SyncScale(P.db.scale); return end
        -- A native track click may change the value before OnMouseDown.
        if IsMouseButtonDown("LeftButton") and (self:IsMouseOver() or self:IsDraggingThumb()) then beginGesture() end
        if dragging then display(value) else P.SetScale(value) end
    end)
    pane:SetScript("OnHide",function(self) self:CancelScale() end)
    local B=P.BlacklistBanner
    local function syncBannerButton()
        S.testBannerButton.label:SetText(L(B.testShown() and "Hide test banner" or "Test banner"))
    end
    pane:SetScript("OnShow",function()
        cancelled=false
        syncBannerButton()
        if pane.RefreshGuildAvailability then pane:RefreshGuildAvailability() end
    end)
    local preview=CreateFrame("Frame",nil,alerts)
    P.Paint(preview,C.raised)
    local previewTitle=label("Alert preview","section",nil,preview)
    local sample=B.createPreview(preview)
    local bannerTitle=label("Blacklist banner","section",nil,alerts)
    local bannerHelp=label("Drag the test banner to set its position. Live alerts are click-through.","small",C.muted,alerts)
    bannerHelp:SetWordWrap(true)
    S.testBannerButton=P.Button(alerts,L("Hide test banner"),140,34,B.toggleTest)
    P.RoundButton(S.testBannerButton)
    local hideBannerWidth=S.testBannerButton.label:GetUnboundedStringWidth()
    syncBannerButton()
    S.testBannerButton:SetWidth(math.max(140,math.ceil(math.max(hideBannerWidth,S.testBannerButton.label:GetUnboundedStringWidth()))+16))
    B.settingsTestChanged=syncBannerButton
    local opacityTitle=label("Banner opacity","body",C.body,alerts)
    S.bannerOpacitySlider=slider(alerts,true)
    S.bannerOpacitySlider:SetMinMaxValues(B.opacityRange())
    S.bannerOpacitySlider:SetValueStep(1); S.bannerOpacitySlider:SetObeyStepOnDrag(true)
    S.bannerOpacitySlider:SetValue(P.db.bannerOpacity)
    S.bannerOpacityLabel=label(P.db.bannerOpacity.."%","body",C.body,alerts)
    S.bannerOpacitySlider:SetScript("OnValueChanged",function(_,value)
        S.bannerOpacityLabel:SetText(B.setOpacity(value).."%")
    end)
    local audioTitle=label("Sound","section",nil,alerts)
    local volume=label("Volume","body",C.body,alerts)
    local refreshTitle=label("Automatic Friends refresh","section",nil,friends)
    local tooltipTitle,tooltipRow,audioRow,bookTitle,deleteRow,colorTitle
    local muteTitle,muteRows,guildBlacklistRow,guildStatusNotice,worldSightingsTitle,nameplateRow
    local refreshRows={}
    do
        local A=P.manual
        colorTitle=label("Interface color","section",nil,general)
        S.interfaceColorChoices={}
        for _,preset in ipairs(P.interfaceColors) do
            S.interfaceColorChoices[preset.id]=interfaceSwatch(general,preset)
        end
        local function toggleRow(parent,caption,description,unavailable,get,set,available,onChanged)
            local control=CreateFrame("CheckButton",nil,parent)
            local edge=P.Paint(control,C.line)
            local surface=control:CreateTexture(nil,"BACKGROUND",nil,1)
            surface:SetPoint("TOPLEFT",edge,"TOPLEFT",1,-1)
            surface:SetPoint("BOTTOMRIGHT",edge,"BOTTOMRIGHT",-1,1)
            P.SetPaletteFill(surface,C.raised)
            control:SetScript("OnEnter",function(self)
                if self:IsEnabled() then P.SetPaletteFill(surface,C.hover) end
            end)
            local function clearHover() P.SetPaletteFill(surface,C.raised) end
            control:SetScript("OnLeave",clearHover)
            control:SetScript("OnHide",clearHover)
            local heading=label(caption,"body",C.text,control)
            local help=label("","small",C.muted,control)
            local checkBox=CreateFrame("Frame",nil,control)
            checkBox:SetSize(20,20)
            P.Paint(checkBox,C.controlTrack)
            local inset=checkBox:CreateTexture(nil,"BACKGROUND",nil,1)
            inset:SetPoint("TOPLEFT",1,-1); inset:SetPoint("BOTTOMRIGHT",-1,1); P.SetPaletteFill(inset,C.panel)
            local mark=P.Glyph(checkBox,"online",16,C.teal); mark:SetPoint("CENTER")
            control.state=label("Off","body",C.body,control); control.state:SetPoint("RIGHT",-14,0)
            local offWidth=control.state:GetUnboundedStringWidth()
            control.state:SetText(L("On"))
            local stateWidth=math.max(22,math.ceil(math.max(offWidth,control.state:GetUnboundedStringWidth())))
            local function sync(canToggle)
                canToggle=canToggle==true
                local on=get()
                control:SetChecked(canToggle and on)
                checkBox:SetShown(canToggle)
                mark:SetShown(canToggle and on)
                control.state:SetShown(canToggle)
                control.state:SetText(L(on and "On" or "Off"))
                P.SetPaletteText(control.state,on and C.teal or C.body)
                local detail
                if canToggle then detail=description else detail=unavailable end
                help:SetText(detail and L(detail) or "")
                help:SetShown(detail~=nil)
            end
            control:SetScript("OnClick",function()
                local before=get()
                local changed=set(not before)
                sync(changed)
                pane:Arrange(pane:GetWidth())
                local after=get()
                if changed and before~=after and onChanged then onChanged(after) end
            end)
            control:SetEnabled(available)
            sync(available)
            return {control=control,heading=heading,help=help,checkBox=checkBox,stateWidth=stateWidth}
        end
        local function refreshRow(...)
            local row=toggleRow(friends,...)
            refreshRows[#refreshRows+1]=row
            return row.control
        end
        local storeReady=A.store~=nil
        local tooltip=A.playerTooltip
        tooltipTitle=label("Mouseover tooltip","section",nil,alerts)
        tooltipRow=toggleRow(alerts,"Show Friend and Blacklisted labels","Adds a colored membership line to the player tooltip.",
            "Membership labels are unavailable.",tooltip.enabled,tooltip.setEnabled,tooltip.available())
        S.tooltipMembership=tooltipRow.control
        local sound=A.alertSound
        local soundAvailable=sound.available()
        audioRow=toggleRow(alerts,soundAvailable and "Play sound with alerts" or "Alert sound is unavailable.",
            nil,nil,sound.enabled,sound.setEnabled,soundAvailable)
        S.liveSoundToggle=audioRow.control
        S.volumeSlider=slider(alerts,soundAvailable)
        S.volumeSlider:SetMinMaxValues(0,100)
        S.volumeSlider:SetValueStep(1); S.volumeSlider:SetObeyStepOnDrag(true)
        S.volumeSlider:SetValue(sound.volume())
        S.volumeLabel=label(sound.volume().."%","body",C.body,alerts)
        S.volumeSlider:SetScript("OnValueChanged",function(_,value)
            S.volumeLabel:SetText(sound.setVolume(value).."%")
        end)
        S.testSoundButton=P.Button(alerts,L("Test sound"),108,32,sound.preview,"action")
        local playMark=S.testSoundButton:CreateTexture(nil,"ARTWORK")
        playMark:SetSize(12,12); playMark:SetTexture(P.media.."LedgerPlay.tga","CLAMP","CLAMP","LINEAR")
        playMark:SetVertexColor(unpack(soundAvailable and C.body or C.disabled))
        S.testSoundButton.label:ClearAllPoints()
        S.testSoundButton.label:SetPoint("CENTER",8,0)
        playMark:SetPoint("RIGHT",S.testSoundButton.label,"LEFT",-6,0)
        S.testSoundButton.label:SetTextColor(unpack(soundAvailable and C.body or C.disabled))
        S.testSoundButton:SetWidth(math.max(108,math.ceil(S.testSoundButton.label:GetUnboundedStringWidth())+16))
        P.SetEnabled(S.testSoundButton,soundAvailable)
        S.automaticTarget=refreshRow("Check targeted Friends","Blacklist sightings run separately.",
            "Target scan unavailable.",A.automaticTargetEnabled,A.setAutomaticTarget,storeReady)
        S.automaticMouseover=refreshRow("Check Friends on hover","Updates after a short pause.",
            "Hover scan unavailable.",A.automaticMouseoverEnabled,A.setAutomaticMouseover,
            storeReady and A.targetCheck.mouseoverAvailable())
        S.relogRefresh=refreshRow("Refresh Friends after relog","Uses guild and Recent Allies.",
            "Relog refresh unavailable.",A.relogRefreshEnabled,A.setRelogRefresh,storeReady)
        worldSightingsTitle=label("World sightings","section",nil,general)
        nameplateRow=toggleRow(general,"Use visible player nameplates",
            "Updates Friends and can trigger Blacklist alerts for either faction.",
            "Nameplates unavailable.",A.automaticNameplatesEnabled,A.setAutomaticNameplates,
            storeReady and A.nameplateCheck.available())
        S.automaticNameplates=nameplateRow.control
        bookTitle=label("Address book","section",nil,general)
        guildBlacklistRow=toggleRow(general,"Add to Guild Blacklist by default",
            "Name, class, reasons and note.",nil,
            function() return P.db.guildBlacklistDefaultWithNote==true end,
            function(value) P.db.guildBlacklistDefaultWithNote=value; return true end,true)
        S.guildBlacklistDefault=guildBlacklistRow.control
        guildStatusNotice=label("You’re not in a guild. Guild sync is unavailable.","small",C.muted,general)
        guildStatusNotice:SetWordWrap(true)
        guildStatusNotice:Hide()
        local checkingGuild=false
        function pane:RefreshGuildAvailability()
            if checkingGuild or not general:IsVisible() or not P.GuildBlacklist then return end
            checkingGuild=true
            local _, status=P.GuildBlacklist.context()
            checkingGuild=false
            local noGuild=status=="no_guild"
            if noGuild==guildStatusNotice:IsShown() then return end
            guildStatusNotice:SetShown(noGuild)
            guildBlacklistRow.control:SetShown(not noGuild)
            if self:GetWidth()>0 then self:Arrange(self:GetWidth()) end
        end
        muteTitle=label("Mute Chat","section",nil,general)
        local mute=A.chatMute
        local muteDescription=mute.baselineComplete()
            and "Whispers, Say and Yell. Individual choices take priority."
            or "Some chat types unavailable. Individual choices take priority."
        local muteRow=toggleRow(general,"Mute Blacklist chat by default",
            muteDescription,
            "Chat muting is unavailable.",mute.defaultEnabled,mute.setDefault,mute.available(),S.Refresh)
        S.muteBlacklistWhispers=muteRow.control
        local partyRaidRow=toggleRow(general,"Include Party and Raid",
            "Includes messages from group leaders.","Party and Raid unavailable.",
            mute.partyRaidEnabled,mute.setPartyRaid,mute.partyRaidAvailable())
        S.muteBlacklistPartyRaid=partyRaidRow.control
        local channelDescription=mute.tradeSupported()
            and "Built-in channels only, for muted players."
            or "Built-in General only. Trade is unavailable."
        local cityTradeRow=toggleRow(general,"Include General and Trade",channelDescription,
            "General and Trade unavailable.",
            mute.cityTradeEnabled,mute.setCityTrade,mute.cityTradeAvailable())
        S.muteBlacklistCityTrade=cityTradeRow.control
        local guildRow=toggleRow(general,"Include Guild chat","Applies to muted players.",
            "Guild chat unavailable.",mute.guildEnabled,mute.setGuild,mute.guildAvailable())
        S.muteBlacklistGuild=guildRow.control
        P.Tooltip(guildRow.control,L("If you feel comfortable, consider talking with the player or a guild officer first."))
        guildRow.control:HookScript("OnHide",P.HideTooltip)
        muteRows={muteRow,partyRaidRow,cityTradeRow,guildRow}
        deleteRow=toggleRow(general,"Skip delete confirmation","Applies to Friends and Personal Blacklist.",
            "Deleting is unavailable.",function() return P.db.skipDeleteConfirmation end,
            function(value) P.db.skipDeleteConfirmation=value; return true end,storeReady)
        S.skipDeleteConfirmation=deleteRow.control
        P.Tooltip(deleteRow.control,L("Guild Blacklist deletion is always confirmed."))
        deleteRow.control:HookScript("OnHide",P.HideTooltip)
    end

    function pane:Arrange(width)
        local x=24
        local content=math.min(width-2*x,640)
        local right=x+content
        position(title,x,23)
        local tabX=x
        for _,tab in ipairs(tabs) do
            local button=S.settingsTabs[tab[1]]
            position(button,tabX,60)
            tabX=tabX+button:GetWidth()+6
        end
        position(tabRule,x,99); tabRule:SetWidth(width-2*x)

        local groupY, rowY=124,154
        local function arrangeSlider(caption,control,percent,y,limit,maxWidth)
            local gap,percentWidth=8,40
            local sliderX=x+math.ceil(caption:GetUnboundedStringWidth())+gap
            local sliderWidth=math.max(1,math.min(maxWidth or 240,limit-sliderX-percentWidth-gap))
            position(caption,x,y)
            caption:SetHeight(32); caption:SetJustifyV("MIDDLE")
            position(control,sliderX,y+4); control:SetWidth(sliderWidth)
            position(percent,sliderX+sliderWidth+gap,y)
            percent:SetHeight(32); percent:SetJustifyV("MIDDLE")
            percent:SetWidth(percentWidth); percent:SetJustifyH("RIGHT")
            return sliderX+sliderWidth+gap+percentWidth
        end
        local function arrangeToggle(row,y,layout)
            layout=layout or defaultRow
            local showState=not layout.compact or content>=450
            local textWidth=content-(showState and 74+row.stateWidth or 54)
            row.checkBox:ClearAllPoints()
            row.checkBox:SetPoint("RIGHT",showState and -26-row.stateWidth or -14,0)
            row.control.state:SetShown(row.checkBox:IsShown() and showState)
            row.heading:SetWidth(textWidth); row.heading:SetWordWrap(true)
            row.help:SetWidth(textWidth); row.help:SetWordWrap(true)
            local headingHeight=math.ceil(row.heading:GetStringHeight())
            local hasHelp=row.help:IsShown()
            local helpOffset=headingHeight+layout.lineGap
            local textHeight=hasHelp and helpOffset+math.ceil(row.help:GetStringHeight()) or headingHeight
            local minHeight=hasHelp and layout.minHeight or layout.singleLineHeight or layout.minHeight
            local height=math.max(minHeight,textHeight+2*layout.padding)
            local headingY=(layout.center or not hasHelp) and math.floor((height-textHeight)/2) or layout.padding
            position(row.control,x,y); row.control:SetSize(content,height)
            position(row.heading,14,headingY)
            position(row.help,14,headingY+helpOffset)
            return y+height
        end

        local fullContent=content
        local splitPreview=width>=780
        if splitPreview then content=math.min(content,math.floor(width*.49)); right=x+content end
        local alertStart=groupY-contentTop
        local bannerY=alertStart
        if tooltipRow then
            position(tooltipTitle,x,alertStart)
            bannerY=arrangeToggle(tooltipRow,rowY-contentTop)+24
        end
        position(bannerTitle,x,bannerY)
        local bannerButtonX=right-S.testBannerButton:GetWidth()
        local helpY=bannerY+math.ceil(bannerTitle:GetStringHeight())+10
        local stacked=bannerButtonX-x-16<220
        bannerHelp:SetWidth(stacked and content or bannerButtonX-x-16)
        local helpHeight=math.ceil(bannerHelp:GetStringHeight())
        bannerHelp:SetHeight(helpHeight)
        local buttonHeight=S.testBannerButton:GetHeight()
        position(bannerHelp,x,helpY)
        local textBottom=helpY+helpHeight
        local bannerButtonY=stacked and textBottom+8 or (bannerY+textBottom-buttonHeight)/2
        position(S.testBannerButton,bannerButtonX,bannerButtonY)
        local opacityY=math.max(textBottom,bannerButtonY+buttonHeight)+8
        arrangeSlider(opacityTitle,S.bannerOpacitySlider,S.bannerOpacityLabel,opacityY,right)
        local audioY=opacityY+46
        position(audioTitle,x,audioY)
        local audioBottom
        do
            local volumeY=arrangeToggle(audioRow,audioY+30)+8
            local buttonX=right-S.testSoundButton:GetWidth()
            local volumeEnd=arrangeSlider(volume,S.volumeSlider,S.volumeLabel,volumeY,buttonX-8)
            position(S.testSoundButton,volumeEnd+8,volumeY)
            audioBottom=volumeY+34
        end

        local previewX=splitPreview and right+20 or x
        local previewY=splitPreview and alertStart or audioBottom+10
        local previewWidth=math.max(1,splitPreview and width-previewX-x or content)
        position(preview,previewX,previewY)
        position(previewTitle,12,8)
        previewTitle:SetWidth(math.max(1,previewWidth-24))
        local sampleHeight=sample:SizeForWidth(math.max(1,math.min(310,previewWidth-24)))
        local titleBottom=8+math.ceil(previewTitle:GetStringHeight())
        local previewHeight=math.max(splitPreview and 230 or 126,titleBottom+10+sampleHeight+12)
        preview:SetSize(previewWidth,previewHeight)
        local sampleTop=titleBottom+math.floor((previewHeight-titleBottom-sampleHeight)/2)
        sample:ClearAllPoints(); sample:SetPoint("TOP",preview,"TOP",0,-sampleTop)
        local viewHeight=math.max(1,self:GetHeight()-contentTop-6)
        arrangeScroll(alertView,alerts,width,viewHeight,math.max(audioBottom,previewY+previewHeight)+6)
        content=fullContent; right=x+content
        position(refreshTitle,x,groupY)
        local refreshY=rowY
        for _,row in ipairs(refreshRows) do refreshY=arrangeToggle(row,refreshY)+4 end

        local windowY,scaleY=groupY-contentTop,rowY-contentTop
        local generalBottom=scaleY+32
        if deleteRow then
            local function arrangeGeneralRows(layout,sliderY)
                local colorY=sliderY+layout.scaleGap
                position(colorTitle,x,colorY)
                local swatchY=colorY+layout.titleGap
                for index,preset in ipairs(P.interfaceColors) do
                    local swatch=S.interfaceColorChoices[preset.id]
                    position(swatch,x+(index-1)*(swatchHitSize+swatchGap),swatchY)
                end
                local worldY=swatchY+swatchHitSize+layout.sectionGap
                position(worldSightingsTitle,x,worldY)
                local bookY=arrangeToggle(nameplateRow,worldY+layout.titleGap,layout)+layout.sectionGap
                position(bookTitle,x,bookY)
                local guildY=arrangeToggle(deleteRow,bookY+layout.titleGap,layout)+layout.rowGap
                local guildBottom
                if guildStatusNotice:IsShown() then
                    guildStatusNotice:SetWidth(content-28)
                    local statusHeight=math.ceil(guildStatusNotice:GetStringHeight())
                    guildBottom=guildY+math.max(layout.singleLineHeight or layout.minHeight,statusHeight+8)
                    position(guildStatusNotice,x+14,guildY+math.floor((guildBottom-guildY-statusHeight)/2))
                else
                    guildBottom=arrangeToggle(guildBlacklistRow,guildY,compactGeneralRow)
                end
                local muteY=guildBottom+layout.sectionGap
                position(muteTitle,x,muteY)
                local y=muteY+layout.titleGap
                for _,row in ipairs(muteRows) do y=arrangeToggle(row,y,layout)+layout.rowGap end
                return y-layout.rowGap
            end
            local layout=generalRow
            if content<450 then
                windowY,scaleY=windowY-8,scaleY-8
                layout=compactGeneralRow
            end
            generalBottom=arrangeGeneralRows(layout,scaleY)
        end
        position(windowTitle,x,windowY)
        arrangeSlider(scaleTitle,S.scaleSlider,S.scaleLabel,scaleY,right,math.min(480,math.floor(content*.70)))
        arrangeScroll(generalView,general,width,viewHeight,generalBottom+8)
    end
    return pane
end
