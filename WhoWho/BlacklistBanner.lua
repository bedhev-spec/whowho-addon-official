local P=WhowhoPreview
local C=P.colors
local B={}
P.BlacklistBanner=B

local margin=8
local holdSeconds, fadeSeconds=8,.5
local minOpacity, maxOpacity, defaultOpacity=50,100,72
local bannerMargins={16,10,8,8}
local sampleName, sampleReasons="Veyra Ashfall", "Griefing · Ninja looting"
local sampleSwapAt, transitionTime, pulseZoom=2,.36,.10
local factionSample={Alliance="Warchief Thrall",Horde="Anduin Wrynn"}
local live, livePaint, test, dragging, openingTest
local banners=setmetatable({}, {__mode="k"})

function B.alphaAt(age)
    return math.max(0,math.min(1,1-(age-holdSeconds)/fadeSeconds))
end

local function finite(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end

local function bannerMaterial(frame,name,layer)
    local texture=P.Material(frame,name,bannerMargins,layer)
    P.TintMaterial(texture,C.teal)
    return texture
end

local function applyOpacity(frame,value)
    local legacy=value==defaultOpacity
    frame.backing:SetShown(legacy)
    if not legacy and not frame.interior then
        frame.interior=bannerMaterial(frame.content,"BannerInterior")
        frame.rim=bannerMaterial(frame.content,"BannerRim","BORDER")
    end
    if frame.interior then
        frame.interior:SetAlpha(value/100)
        frame.interior:SetShown(not legacy)
        frame.rim:SetShown(not legacy)
    end
    local shadowed=value<defaultOpacity
    if frame.shadowed~=shadowed then
        frame.shadowed=shadowed
        for _,label in ipairs(frame.labels) do
            label:SetShadowColor(0,0,0,shadowed and .8 or 0)
            label:SetShadowOffset(shadowed and 1 or 0,shadowed and -1 or 0)
        end
    end
end

function B.opacityRange()
    return minOpacity,maxOpacity
end

function B.setOpacity(value)
    value=math.floor(math.max(minOpacity,math.min(maxOpacity,finite(value) and value or defaultOpacity))+.5)
    if P.db.bannerOpacity~=value then
        P.db.bannerOpacity=value
        for frame in pairs(banners) do applyOpacity(frame,value) end
    end
    return value
end

function B.savedPosition(value)
    if type(value)=="table" and finite(value.x) and finite(value.y) then
        return {x=value.x,y=value.y}
    end
end

-- Both native banners and the Settings sample reserve real, wrapped text boxes.
local function sizeBanner(frame,width,owns)
    local textWidth=math.max(1,width-32)
    frame.character:SetWidth(textWidth)
    frame.reasons:SetWidth(textWidth)
    local nameHeight=math.ceil(frame.character:GetStringHeight())
    local reasonHeight=math.ceil(frame.reasons:GetStringHeight())
    frame.character:SetHeight(nameHeight)
    frame.reasons:SetHeight(reasonHeight)
    local textHeight=nameHeight+6+reasonHeight
    if frame.groupProgress then
        local more=frame.more
        more:SetWidth(textWidth)
        local moreHeight=math.ceil(more:GetStringHeight())
        more:SetHeight(moreHeight)
        textHeight=textHeight+frame.groupProgress*(6+moreHeight)
    end
    local height=math.max(80,24+textHeight)
    frame:SetSize(width,height)
    if owns and not owns() then return end
    if frame.content~=frame then frame.content:SetSize(width,height) end
    if owns and not owns() then return end
    frame.character:ClearAllPoints()
    frame.character:SetPoint("TOP",frame.content,"TOP",0,-(height-textHeight)/2)
    return height
end

local function arrange(frame,owns)
    local width,height=UIParent:GetWidth(),UIParent:GetHeight()
    if not finite(width) or not finite(height) or width<=0 or height<=0 or owns and not owns() then return end
    local bannerWidth=math.max(1,math.min(310,width-margin*2))
    local measuredHeight=sizeBanner(frame,bannerWidth,owns)
    if not measuredHeight or owns and not owns() then return end
    local bannerHeight=math.max(1,math.min(height-margin*2,measuredHeight))
    frame:SetHeight(bannerHeight)
    if owns and not owns() then return end
    frame.content:SetHeight(bannerHeight)
    if owns and not owns() then return end
    local maxX=math.max(0,(width-bannerWidth)*.5-margin)
    local maxY=math.max(0,(height-bannerHeight)*.5-margin)
    local saved=P.db.bannerPosition
    local x=saved and saved.x or 0
    local y=saved and saved.y or height*.5-136
    x=math.max(-maxX,math.min(maxX,x))
    y=math.max(-maxY,math.min(maxY,y))
    -- The content zooms around the clamped center without moving the input frame.
    frame.pulseLimit=math.max(1,math.min((width-2*math.abs(x))/bannerWidth,(height-2*math.abs(y))/bannerHeight))
    frame:ClearAllPoints()
    frame:SetPoint("CENTER",UIParent,"CENTER",x,y)
end

local function readable(value)
    return P.manual.nativeRead.readable(value)
end

local function center(frame)
    local ok,x,y=pcall(frame.GetCenter,frame)
    if ok and readable(x) and readable(y) and finite(x) and finite(y) then return x,y end
end

local function dragAllowed()
    local A=P.manual
    return A.nativeRead.read(InCombatLockdown)==false
end

local function stopDrag(frame, save)
    if not dragging then return end
    dragging=false
    local stopped=pcall(frame.StopMovingOrSizing,frame)
    if save and stopped then
        local x,y=center(frame)
        local rootX,rootY=center(UIParent)
        if x and rootX then P.db.bannerPosition=B.savedPosition({x=x-rootX,y=y-rootY}) end
    end
    arrange(frame)
end

local function testChanged()
    if B.settingsTestChanged then B.settingsTestChanged() end
    if B.sightingsTestChanged then B.sightingsTestChanged() end
end

local function resetTransition(frame)
    frame.transition=nil
    frame.content:SetScale(1)
end

local function testHidden(frame)
    stopDrag(frame,false)
    if frame:IsShown() or not frame:GetScript("OnUpdate") then return end
    frame:SetScript("OnUpdate",nil)
    resetTransition(frame)
    testChanged()
end

local function visibleForSound(frame)
    return P.manual.nativeRead.read(frame.IsVisible,frame)==true
end

local function startTransition(frame,count)
    local change=frame.transition
    if change then
        change.count=count
    else
        frame.transition={count=count,age=0,from=frame.groupProgress or 0}
    end
end

local function applyPulse(frame,progress)
    local zoom=math.min(pulseZoom,(frame.pulseLimit or 1)-1)
    frame.content:SetScale(1+zoom*math.sin(math.pi*progress))
end

local function advanceTransition(frame,elapsed,stillOwns)
    local change=frame.transition
    if not change then return end
    local count=change.count
    local function owns()
        return (not stillOwns or stillOwns()) and frame.transition==change and change.count==count
    end
    if not owns() then return end
    change.age=change.age+elapsed
    local progress=math.min(1,change.age/transitionTime)
    local eased=progress*progress*(3-2*progress)
    local newText=change.paintedCount~=count
    if newText then
        frame.more:SetText(P.L("+%d more"):format(count))
        if not owns() then return end
    end
    if frame.groupProgress~=1 then
        frame.groupProgress=change.from+(1-change.from)*eased
        arrange(frame,owns)
        if not owns() then return end
    end
    frame.more:SetAlpha(eased)
    if not owns() then return end
    if newText then
        frame.more:Show()
        if not owns() then return end
        change.paintedCount=count
    end
    if progress==1 then
        resetTransition(frame)
    else
        applyPulse(frame,progress)
    end
    return true
end

local function startTestTimer(frame)
    local age=0
    local pending=true
    local function update(self,elapsed)
        if dragging or self:GetScript("OnUpdate")~=update then return end
        age=age+elapsed
        local alpha=B.alphaAt(age)
        if alpha==0 then self:Hide(); return end
        if pending and age>=sampleSwapAt then
            pending=false
            startTransition(self,1)
            elapsed=age-sampleSwapAt
        end
        advanceTransition(self,elapsed)
        if alpha<1 and self:GetScript("OnUpdate")==update then self:SetAlpha(alpha) end
    end
    frame:SetScript("OnUpdate",update)
    return function()
        return visibleForSound(frame) and frame:GetScript("OnUpdate")==update and age<=holdSeconds
    end
end

local function installEncounterClick(frame)
    local A=P.manual
    frame:EnableMouse(false)
    if A.nativeRead.read(frame.RegisterEvent,frame,"MODIFIER_STATE_CHANGED")~=true then return end
    local read=A.nativeRead.read
    local encounter, pressed, enabled, binding=nil,nil,false,0
    local function sync()
        local control=encounter and frame:IsVisible() and read(IsControlKeyDown)==true
        local wanted=control==true and not not frame:IsVisible() and encounter~=nil
        if wanted~=enabled then enabled=wanted; frame:EnableMouse(wanted) end
        if not wanted then pressed=nil end
    end
    function frame:bindEncounter(owner)
        binding=binding+1
        pressed=nil
        encounter=owner
        sync()
    end
    frame:SetScript("OnEvent",sync)
    frame:SetScript("OnShow",sync)
    frame:SetScript("OnHide",sync)
    frame:SetScript("OnLeave",function() pressed=nil end)
    frame:SetScript("OnMouseDown",function(self,button)
        if A.text(button)=="LeftButton" then pressed=enabled and binding or nil end
    end)
    frame:SetScript("OnMouseUp",function(self,button)
        if A.text(button)~="LeftButton" then return end
        local owner, episode=pressed, encounter
        local key=episode and episode.key
        pressed=nil
        local function owns()
            return self:IsVisible() and binding==owner and episode.key==key
        end
        if owner and key and enabled and read(self.IsMouseOver,self)==true
            and read(IsControlKeyDown)==true and owns() then
            P.Shell.OpenEncounter(episode,owns)
        end
    end)
end

local function styleBanner(frame,allowGroup)
    local content=frame
    if allowGroup then
        content=CreateFrame("Frame",nil,frame)
        content:SetPoint("CENTER",frame,"CENTER")
    end
    content:SetClipsChildren(true)
    frame.content=content
    frame.backing=bannerMaterial(content,"Banner")
    frame.character=P.Label(content,"","record",C.text)
    frame.reasons=P.Label(content,"","body",C.gold)
    frame.labels={frame.character,frame.reasons}
    frame.reasons:SetPoint("TOP",frame.character,"BOTTOM",0,-6)
    if allowGroup then
        frame.more=P.Label(content,"","body",C.text)
        frame.more:SetPoint("TOP",frame.reasons,"BOTTOM",0,-6)
        frame.more:Hide()
        frame.labels[#frame.labels+1]=frame.more
    end
    for _,label in ipairs(frame.labels) do
        label:SetJustifyH("CENTER")
        label:SetWordWrap(true)
        label:SetNonSpaceWrap(true)
    end
    banners[frame]=true
    applyOpacity(frame,P.db.bannerOpacity)
end

function B.createPreview(parent)
    local frame=CreateFrame("Frame",nil,parent)
    styleBanner(frame)
    frame.character:SetText(sampleName)
    frame.reasons:SetText(P.L(sampleReasons))
    frame.SizeForWidth=sizeBanner
    return frame
end

local function frameForTest(isTest)
    local frame=CreateFrame("Frame",isTest and "WhowhoBlacklistTestBanner" or "WhowhoBlacklistLiveBanner",UIParent)
    frame:Hide()
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    styleBanner(frame,true)
    if isTest then
        frame:SetScript("OnDragStart",function(self)
            if not dragging and dragAllowed() then
                dragging=pcall(self.StartMoving,self)
                if dragging and self.transition then self.content:SetScale(1) end
            end
        end)
        frame:SetScript("OnDragStop",function(self) stopDrag(self,true) end)
        frame:SetScript("OnHide",testHidden)
    else
        installEncounterClick(frame)
    end
    return frame
end

local function paint(frame,name,reasons)
    resetTransition(frame)
    frame.groupProgress=nil
    frame.more:Hide()
    frame.character:SetText((name:gsub("|","||")))
    frame.reasons:SetText(reasons)
    frame:SetAlpha(1)
    arrange(frame)
end

function B.testShown()
    return test~=nil and test:IsShown()
end

function B.hideTest()
    if not B.testShown() then return end
    test:Hide()
    -- A hidden ancestor can prevent the native OnHide callback.
    if not test:IsShown() and test:GetScript("OnUpdate") then testHidden(test) end
end

function B.toggleTest()
    if openingTest then return end
    if B.testShown() then B.hideTest(); return end
    openingTest=true
    local A=P.manual
    local faction=A.playerFaction(A.region)
    local name=faction and factionSample[faction] or sampleName
    if not test then test=frameForTest(true) end
    if dragAllowed() and not test.dragReady then
        test.dragReady=pcall(function()
            test:SetMovable(true)
            test:SetClampedToScreen(true)
            test:RegisterForDrag("LeftButton")
            test:EnableMouse(true)
        end)
    end
    B.hideLive()
    paint(test,name,P.L(sampleReasons))
    local ownsAppearance=startTestTimer(test)
    test:Show()
    openingTest=false
    testChanged()
    A.alertSound.playBanner(ownsAppearance)
end

function B.showLive(name,reasons,encounter)
    if B.testShown() then return false end
    if not live then live=frameForTest(false) end
    local owner={}
    livePaint=owner
    paint(live,name,reasons)
    if live.bindEncounter then live:bindEncounter(encounter) end
    live:Show()
    return function()
        return visibleForSound(live) and livePaint==owner
    end
end

function B.addLive(count,owns)
    local owner=livePaint
    if not owner or not visibleForSound(live) or not owns() or owner~=livePaint then return false end
    -- The observer still owns its queue here. Widget calls run next update.
    startTransition(live,count)
    return true
end

function B.advanceLive(elapsed,justAdded,owns)
    local owner=livePaint
    local change=owner and live.transition
    if change and (not justAdded or change.age>0) and live:IsVisible()
        and owner==livePaint and live.transition==change then return advanceTransition(live,elapsed,owns) end
end

function B.clearLiveEncounter()
    if live and live.bindEncounter then live:bindEncounter(nil) end
end

function B.hideLive()
    if not live then return end
    livePaint=nil
    B.clearLiveEncounter()
    resetTransition(live)
    live:Hide()
end

function B.fade(alpha)
    if alpha<1 then
        livePaint=nil
        if live and live.transition then resetTransition(live) end
    end
    if live and live:IsShown() then live:SetAlpha(alpha) end
end

local function resizeBanner(frame)
    local change=frame.transition
    arrange(frame)
    if change and frame.transition==change then applyPulse(frame,math.min(1,change.age/transitionTime)) end
end

function B.resize()
    if live and live:IsShown() then resizeBanner(live) end
    if B.testShown() and not dragging then resizeBanner(test) end
end
