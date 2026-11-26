-- Simulated widgets and native reads. Real game defaults and placement need client validation.
local root=arg[1] or "."
local H=dofile(root.."/tests/addon/harness.lua")
local count=0
local function check(value,message)
    assert(value,message)
    count=count+1
end
local function visibleField(parent,match)
    for _,child in ipairs(parent.children or {}) do
        if child.kind=="FontString" and child:IsVisible() and match(child:GetText()) then return child end
        local result=visibleField(child,match)
        if result then return result end
    end
end

local function checkTabs(p,pane,captions,selected)
    local right=0
    for i,caption in ipairs(captions) do
        local field=assert(visibleField(pane,function(text) return text==caption end))
        local button=field:GetParent()
        local point,anchor,relative=field:GetPoint()
        local _,left=button:GetPoint()
        local weight=i==selected and "SemiBold" or "Regular"
        check(point=="CENTER" and anchor==button and relative=="CENTER" and not field:GetPoint(2)
            and field:GetWidth()==0 and field:GetHeight()==0 and field.SetWordWrapArgs[1]==false,
            caption.." uses a natural single-line label without a box that can clip its glyphs")
        check(button:GetWidth()>=math.ceil(field:GetUnboundedStringWidth())+16 and left>=right
            and left+button:GetWidth()<=pane:GetWidth()-24
            and field:GetFont()==p.media.."NotoSans-"..weight..".ttf"
            and button.underline:IsShown()==(i==selected),caption.." fits and reflects tab selection")
        right=left+button:GetWidth()
    end
end

local function upvalue(fn,key)
    for i=1,debug.getinfo(fn,"u").nups do
        local name,value=debug.getupvalue(fn,i)
        if name==key then return value end
    end
    error("missing upvalue: "..key)
end

local function fresh(preferences, unsupportedEvent, history, addressBook)
    local config={region=3,time=100,db=addressBook}
    local p,s,e=H.fresh(root,preferences,{484,800},config)
    e.WhowhoEncounterDB=history
    e.date=os.date
    local units, reads, combat={},0,false
    s.units=units
    s.region=function(value) config.region=value end
    s.combat=function(value) combat=value end
    s.reads=function() return reads end
    s.advance=function(elapsed) config.time=config.time+elapsed end
    e.GetTime=function() return config.time end
    e.GetServerTime=function() return math.floor(config.time) end
    e.InCombatLockdown=function() return combat end
    e.C_Timer={NewTimer=function() return {Cancel=function() end} end}
    e.UnitExists=function(unit) return units[unit]~=nil end
    e.UnitIsPlayer=function(unit) return units[unit] and units[unit].player~=false end
    e.UnitIsUnit=function(unit) return unit=="player" or units[unit] and units[unit].self==true or false end
    e.C_Secrets.ShouldUnitIdentityBeSecret=function(unit) return units[unit] and units[unit].restricted==true or false end
    e.GetUnitName=function(unit) reads=reads+1; return units[unit].name end
    e.UnitGUID=function(unit) reads=reads+1; return units[unit].guid end
    e.UnitClass=function() return nil end
    if unsupportedEvent then
        local create=e.CreateFrame
        e.CreateFrame=function(kind,name,parent,template)
            local frame=create(kind,name,parent,template)
            if kind=="Frame" and not name and parent==e.UIParent then
                local register=frame.RegisterEvent
                frame.RegisterEvent=function(self,event)
                    if event==unsupportedEvent then return false end
                    return register(self,event)
                end
            end
            return frame
        end
    end
    s:event("ADDON_LOADED","WhoWho")
    local A=p.manual
    s.observer=nil
    for _,frame in ipairs(s.nodes) do
        if frame.events.PLAYER_LEAVING_WORLD and frame.parent==e.UIParent then s.observer=frame end
    end
    function s:tick(elapsed)
        config.time=config.time+elapsed
        local fn=self.observer and self.observer:IsVisible() and self.observer:GetScript("OnUpdate")
        if fn then fn(self.observer,elapsed) end
    end
    function s:set(token,name,guid,event)
        units[token]=name and {name=name,guid=guid} or nil
        if event then self:event(token=="target" and "PLAYER_TARGET_CHANGED" or "UPDATE_MOUSEOVER_UNIT") end
    end
    function s:add(name,guid,reasons,section,region)
        local record=assert(A.store.add({
            region=region or 3,fullName=name,guid=guid,identityState="resolved",
            membership=section or "blacklist",reasonIds=reasons or {"other"},note="Private example"
        },100))
        A.refresh()
        return record
    end
    return p,s,e,A
end

local function shown(frame) return frame and frame:IsShown() end
do
    local _,s,e=fresh()
    local count=1
    e.IsInRaid=function() return false end
    e.GetNumSubgroupMembers=function() return count end
    local sounds=0
    e.C_Sound={PlaySoundWithOptions=function() sounds=sounds+1 end}
    s:add("Continuing Member","continuing")
    s:set("party1","Continuing Member","continuing")
    s:event("GROUP_ROSTER_UPDATE")
    local live=e.WhowhoBlacklistLiveBanner
    check(shown(live) and sounds==1,"the first roster sighting alerts")
    for _=1,3 do
        s:tick(31)
        s:event("PLAYER_LEAVING_WORLD")
        count=nil
        s:event("PLAYER_ENTERING_WORLD")
        s:tick(.25)
        count=1
        s:event("GROUP_ROSTER_UPDATE")
        check(not shown(live) and sounds==1,"loading and a late roster snapshot do not rearm the same member")
    end
    count=0
    s:set("party1",nil)
    s:event("GROUP_ROSTER_UPDATE")
    s:tick(6)
    count=1
    s:set("party1","Continuing Member","continuing")
    s:event("GROUP_ROSTER_UPDATE")
    check(shown(live) and sounds==2,"a confirmed departure past the grace period allows a real rejoin alert")
end

local function known(A, record)
    local current=A.store.get(record.id)
    return current and current.lastKnown or {}
end
local function knownClass(A, record)
    local class=known(A,record).class
    return class and class.value
end

do
    local p,s,e,A=fresh({automaticNameplates=false})
    local rosterSize=1
    e.IsInRaid=function() return false end
    e.GetNumSubgroupMembers=function() return rosterSize end
    s:add("Party Member","party")
    s:set("party1","Other Person","other")
    s:event("GROUP_ROSTER_UPDATE")
    check(not shown(e.WhowhoBlacklistLiveBanner),"an unlisted party member does not raise an alert")

    local sounds=0
    e.C_Sound={PlaySoundWithOptions=function() sounds=sounds+1 end}
    rosterSize=2
    s:set("party2","Party Member","party")
    s:event("GROUP_ROSTER_UPDATE")
    local live=e.WhowhoBlacklistLiveBanner
    check(shown(live) and live.character:GetText()=="Party Member" and sounds==1,
        "a blacklisted player joining an existing party raises an alert without a target or nameplate")
    s:set("target","Party Member","party",true)
    s:event("GROUP_ROSTER_UPDATE")
    check(sounds==1 and not shown(live.more),"targeting a roster sighting does not alert twice")

    rosterSize=1
    s:set("party2",nil)
    s:set("target",nil,nil,true)
    s:event("GROUP_ROSTER_UPDATE")
    s:tick(6)
    local history=e.WhowhoEncounterDB
    A.encounterLedger.init(history)
    local encounters=A.encounterLedger.groups(3,106)
    check(#encounters==1 and encounters[1].row.roster and encounters[1].row.target,
        "a combined roster and target encounter persists once")
end

do
    local p,s,e,A=fresh()
    local raidSize=0
    local instance
    e.IsInRaid=function() return raidSize>0 end
    e.GetNumSubgroupMembers=function() return 0 end
    e.GetNumGroupMembers=function() return raidSize end
    e.IsInInstance=function() return instance~=nil,instance end
    s:add("Raid Member","raid")
    s:add("Late Member","late")
    raidSize=2
    s:set("raid1","Own Player","own")
    s.units.raid1.self=true
    s:set("raid2","Raid Member","raid")
    s:event("GROUP_ROSTER_UPDATE")
    local live=e.WhowhoBlacklistLiveBanner
    check(shown(live) and live.character:GetText()=="Raid Member",
        "joining an outdoor raid with a blacklisted member raises an alert")
    s:tick(4)
    raidSize=3
    s:set("raid3","Late Member","late")
    s:event("GROUP_ROSTER_UPDATE")
    raidSize=2
    s:set("raid3",nil)
    s:event("GROUP_ROSTER_UPDATE")
    s:tick(6)
    check(not shown(live),"a roster-only queued alert is discarded when the member leaves")
    A.encounterLedger.init(e.WhowhoEncounterDB)
    local encounters=A.encounterLedger.groups(3,110)
    local found
    for _,encounter in ipairs(encounters) do
        local row=encounter.row
        if row.name=="Late Member" then found=row.roster and not row.target and not row.mouseover and not row.nameplate end
    end
    check(found,"a roster-only encounter survives reload as a roster sighting")
    for _,kind in ipairs({"party","raid"}) do
        instance=kind
        raidSize=3
        s:set("raid3","Late Member","late")
        local reads=s.reads()
        s:event("GROUP_ROSTER_UPDATE")
        check(not shown(live) and reads==s.reads(),kind.." instances suppress roster sighting reads and alerts")
    end
end

do
    local p,s,e=fresh()
    e.IsInRaid=function() return false end
    e.GetNumSubgroupMembers=function() return 1 end
    s:add("Old Member","old")
    s:add("New Member","new")
    s:set("party1","Old Member","old")
    local name=e.GetUnitName
    e.GetUnitName=function(token)
        local previous=name(token)
        if token=="party1" then
            e.GetUnitName=name
            s:set("party1","New Member","new")
            s:event("GROUP_ROSTER_UPDATE")
        end
        return previous
    end
    s:event("GROUP_ROSTER_UPDATE")
    check(not shown(e.WhowhoBlacklistLiveBanner),"a roster update invalidates a stale in-flight sample")
    s:tick(.25)
    local live=e.WhowhoBlacklistLiveBanner
    check(shown(live) and live.character:GetText()=="New Member",
        "the next scan alerts only for the replacement member")
end

do
    local _,s,e=fresh()
    local rosterSize=1
    e.IsInRaid=function() return false end
    e.GetNumSubgroupMembers=function() return rosterSize end
    s:add("Primary Member","main")
    s:add("Departing Member","departing")
    s:add("Staying Member","staying")
    s:set("party1","Primary Member","main")
    s:event("GROUP_ROSTER_UPDATE")
    local live=e.WhowhoBlacklistLiveBanner
    rosterSize=3
    s:set("party2","Staying Member","staying")
    s:set("party3","Departing Member","departing")
    s:event("GROUP_ROSTER_UPDATE")
    s:tick(.25)
    check(not live.more:IsShown(),"a roster overlap waits until the following frame to paint its count")
    rosterSize=2
    s:set("party3",nil)
    s:event("GROUP_ROSTER_UPDATE")
    s:tick(.18)
    check(live.more:IsShown() and live.more:GetText()=="+1 more",
        "a member leaving before grouped paint is dropped while the remaining member counts")
end

for _,interruption in ipairs({"roster","visibility"}) do
    local _,s,e=fresh()
    local rosterSize=1
    e.IsInRaid=function() return false end
    e.GetNumSubgroupMembers=function() return rosterSize end
    s:add("Primary Member","main")
    s:add("Departing Member","departing")
    s:set("party1","Primary Member","main")
    s:event("GROUP_ROSTER_UPDATE")
    local live=e.WhowhoBlacklistLiveBanner
    rosterSize=2
    s:set("party2","Departing Member","departing")
    s:event("GROUP_ROSTER_UPDATE")
    s:tick(.25)
    local setText=live.more.SetText
    live.more.SetText=function(self,text)
        setText(self,text)
        self.SetText=setText
        if interruption=="visibility" then
            e.UIParent:Hide()
        else
            rosterSize=1
            s:set("party2",nil)
            s:event("GROUP_ROSTER_UPDATE")
        end
    end
    if interruption=="visibility" then s.advance(1) end
    s:tick(.18)
    check(not shown(live),interruption.." changes during paint cancel the old count")
    if interruption=="visibility" then
        e.UIParent:Show()
        s:tick(.25)
    else
        rosterSize=2
        s:set("party2","Departing Member","departing")
        s:event("GROUP_ROSTER_UPDATE")
    end
    check(shown(live) and live.character:GetText()=="Departing Member",
        "a canceled grouped count does not consume the member's cooldown after "..interruption.." changes")
end

for _,unreadable in ipairs({false,true}) do
    local _,s,e=fresh()
    local rosterSize=1
    e.IsInRaid=function() return false end
    e.GetNumSubgroupMembers=function() return rosterSize end
    s:add("Retry Member","retry")
    s:set("party1","Retry Member","retry")
    e.UnitClass=function() return "Mage","MAGE" end
    e.GetServerTime=function() return nil end
    s:event("GROUP_ROSTER_UPDATE")
    check(shown(e.WhowhoBlacklistLiveBanner),"a pending metadata retry still allows the alert")
    rosterSize=0
    if unreadable then rosterSize=nil end
    s:set("party1",nil)
    s:event("GROUP_ROSTER_UPDATE")
    for _=1,60 do s:tick(.25) end
    check(not s.observer:GetScript("OnUpdate"),"a departed or unreadable roster slot cannot retain a metadata retry")
end

do
    local _,s,e=fresh()
    e.IsInRaid=function() return false end
    e.GetNumSubgroupMembers=function() return 1 end
    s:add("Late Member","late")
    s:event("GROUP_ROSTER_UPDATE")
    s:tick(.25)
    s:set("party1","Late Member","late")
    s:tick(.25)
    local live=e.WhowhoBlacklistLiveBanner
    check(shown(live) and live.character:GetText()=="Late Member",
        "the roster scan finds a late unit token without another group event")
end

do
    local _,s,e=fresh()
    e.IsInRaid=function() return false end
    e.GetNumSubgroupMembers=function() return 1 end
    s:add("Late Member","late")
    s:event("GROUP_ROSTER_UPDATE")
    for _=1,6 do s:tick(.25) end
    local reads=s.reads()
    s:set("party1","Late Member","late")
    s:tick(1)
    check(shown(e.WhowhoBlacklistLiveBanner) and s.reads()>reads,
        "an empty slot inside the group count stays under the retry")
    e.GetNumSubgroupMembers=function() return 0 end
    s:set("party1",nil)
    s:event("GROUP_ROSTER_UPDATE")
    for _=1,40 do s:tick(.25) end
    check(not s.observer:GetScript("OnUpdate"),"polling stops once the group has no unresolved slot")
end

for _,loading in ipairs({false,true}) do
    local _,s,e=fresh()
    local rosterSize=1
    local kind
    e.IsInRaid=function() return false end
    e.GetNumSubgroupMembers=function() return rosterSize end
    e.IsInInstance=function() return kind~=nil,kind end
    s:add("Continuing Member","continuing")
    s:add("Outdoor Member","outdoor")
    s:set("party1","Continuing Member","continuing")
    s:event("GROUP_ROSTER_UPDATE")
    kind="party"
    if loading then
        s:event("PLAYER_LEAVING_WORLD")
        s:event("PLAYER_ENTERING_WORLD")
    else
        s:event("ZONE_CHANGED_NEW_AREA")
    end
    s.advance(40)
    if loading then s:event("PLAYER_LEAVING_WORLD") end
    kind=nil
    rosterSize=2
    s:set("party2","Outdoor Member","outdoor")
    s:event("GROUP_ROSTER_UPDATE")
    s:event("PLAYER_ENTERING_WORLD")
    local live=e.WhowhoBlacklistLiveBanner
    check(shown(live) and live.character:GetText()=="Outdoor Member",
        "the first outdoor roster event alerts for the new member and keeps the continuing member quiet")
end

do
    local p,s,e=fresh()
    s:add("First Person","first")
    s:add("Second Person","second")
    s:set("target","First Person","first",true)
    s:set("mouseover","Second Person","second",true)
    local live=e.WhowhoBlacklistLiveBanner
    local hooks=0
    local setText=live.more.SetText
    live.more.SetText=function(self,text)
        setText(self,text)
        hooks=hooks+1
        self.SetText=setText
        s:event("PLAYER_LEAVING_WORLD")
    end
    s:tick(.25)
    check(hooks==0 and live.transition and live:IsShown(),
        "staging a count never calls widget hooks while it owns the eligible queue")
    s:tick(.18)
    check(hooks==1 and not live:IsShown() and not live.more:IsShown()
        and not live.transition and live.content:GetScale()==1,
        "leaving the world from a count text hook stops the old paint immediately")
end

do
    local p,s,e=fresh({bannerOpacity=100,bannerPosition={x=50,y=-100}})
    local B=p.BlacklistBanner
    local sounds=0
    e.C_Sound={PlaySoundWithOptions=function() sounds=sounds+1 end}
    B.toggleTest()
    local frame=e.WhowhoBlacklistTestBanner
    local _,_,_,x,y=frame:GetPoint()
    local update=frame:GetScript("OnUpdate")
    update(frame,1.99)
    check(frame.character:GetText()=="Veyra Ashfall" and not frame.more:IsShown() and frame.content:GetScale()==1,
        "the test starts with the original single-player sample")
    update(frame,.19)
    local _,_,_,groupX,groupY=frame:GetPoint()
    check(frame.more:IsShown() and frame.more:GetText()=="+1 more" and frame.more.SetAlphaArgs[1]>.45
        and frame.more.SetAlphaArgs[1]<.55 and math.abs(frame.content:GetScale()-1.10)<.0001
        and frame:GetScale()==1 and x==50 and y==-100 and x==groupX and y==groupY,
        "the count fades in as the banner reaches a 10% pulse centered on its saved anchor")
    check(frame.character:GetText()=="Veyra Ashfall" and frame.reasons:GetText()=="Griefing · Ninja looting"
        and not frame.content.SetAlphaArgs and frame.SetAlphaArgs[1]==1,
        "the primary name and reasons remain fully readable while the count appears")
    update(frame,.19)
    check(frame.content:GetScale()==1 and frame.more.SetAlphaArgs[1]==1 and sounds==1,
        "the test group settles at full opacity without a second cue")
    B.hideTest()
    update(frame,1)
    check(not frame:IsShown() and not frame.transition and frame.content:GetScale()==1,
        "a stale test timer cannot animate after dismissal")
    B.toggleTest()
    local reopen=frame:GetScript("OnUpdate")
    reopen(frame,2.06)
    B.hideTest()
    reopen(frame,.18)
    check(not frame.more:IsVisible() and frame.content:GetScale()==1 and not frame.transition,
        "dismissing mid-transition cancels the pulse and count reveal")
    B.toggleTest()
    check(frame:IsShown() and not frame.more:IsShown() and sounds==3,
        "each new test starts with the same single-player sample and cue")
end

do
    local p,s,e=fresh()
    local B=p.BlacklistBanner
    B.toggleTest()
    local frame=e.WhowhoBlacklistTestBanner
    local update=frame:GetScript("OnUpdate")
    update(frame,2.18)
    local change=frame.transition
    local age=change.age
    e.UIParent:SetSize(312,800)
    B.resize()
    local _,_,_,resizedX=frame:GetPoint()
    check(resizedX==0 and frame:GetWidth()==296 and math.abs(frame.content:GetWidth()*frame.content:GetScale()-312)<.0001
        and frame.transition==change,"resizing clamps the active pulse against the new viewport immediately")
    e.UIParent:SetSize(484,800)
    B.resize()
    frame.GetCenter=function() return 440,540 end
    e.UIParent.GetCenter=function() return 242,400 end
    s:fire(frame,"OnDragStart")
    update(frame,1)
    check(frame.moving and frame.content:GetScale()==1 and frame.transition==change and change.age==age,
        "dragging restores full-size bounds and pauses the active pulse")
    s:fire(frame,"OnDragStop")
    update(frame,0)
    local _,_,_,x,y=frame:GetPoint()
    local scale=frame.content:GetScale()
    check(p.db.bannerPosition.x==198 and p.db.bannerPosition.y==140 and x==79 and y==140
        and frame:GetWidth()==310 and scale>1 and scale<1.10
        and math.abs(x+frame.content:GetWidth()*scale/2-e.UIParent:GetWidth()/2)<.0001,
        "a near-edge drag keeps the saved position and caps the resumed pulse at the viewport")
    update(frame,.09)
    check(frame.content:GetScale()>1 and frame.content:GetScale()<scale,
        "the constrained pulse eases away from its reduced peak")
    update(frame,.10)
    check(frame.content:GetScale()==1 and not frame.transition,"the constrained pulse settles at the original scale")
    B.hideTest()
    B.toggleTest()
    update=frame:GetScript("OnUpdate")
    update(frame,2.18)
    local setHeight=frame.content.SetHeight
    frame.content.SetHeight=function(self,height)
        setHeight(self,height)
        self.SetHeight=setHeight
        B.hideTest()
    end
    B.resize()
    update(frame,.1)
    check(not frame:IsShown() and not frame.transition and frame.content:GetScale()==1,
        "a banner hidden during resize cannot reapply its old pulse")
end

do
    local p,s,e,A=fresh()
    local first=s:add("First Person","first",{"griefing"})
    local second=s:add("Second Person","second",{"ninja_looting"})
    local third=s:add("Third Person","third")
    local fourth=s:add("Fourth Person","fourth")
    local sounds,control=0,true
    e.C_Sound={PlaySoundWithOptions=function() sounds=sounds+1 end}
    e.IsControlKeyDown=function() return control end
    s:set("target",first.fullName,first.guid,true)
    local live=e.WhowhoBlacklistLiveBanner
    s:set("mouseover",first.fullName,first.guid,true)
    s:tick(.25)
    check(not live.transition and not live.more:IsShown() and sounds==1,
        "a duplicate live identity across two sources never enters a transition")

    s:set("mouseover",second.fullName,second.guid,true)
    s:tick(.25)
    check(live.transition and not live.more:IsShown() and sounds==1,
        "a verified overlap stages one silent live transition")
    s:routePointer({live},"OnMouseDown","LeftButton")
    s:tick(.18)
    check(live.character:GetText()==first.fullName and live.reasons:GetText()=="Griefing" and live.more:GetText()=="+1 more"
        and live.more.SetAlphaArgs[1]>.45 and live.more.SetAlphaArgs[1]<.55 and not live.content.SetAlphaArgs
        and math.abs(live.content:GetScale()-1.10)<.0001 and live:GetScale()==1,
        "the live 10% pulse and count fade keep primary text fully readable")
    s:tick(.19)
    check(live.content:GetScale()==1 and live.more.SetAlphaArgs[1]==1 and not live.transition,
        "live motion settles without repeating")

    local episodes=A.encounterLedger.snapshot(3,101).Now
    local displayed={}
    for _,episode in ipairs(episodes) do displayed[episode.playerId]=episode end
    local selected={}
    p.Shell.OpenEncounter=function(encounter,owns)
        assert(owns())
        selected[#selected+1]=encounter.id
    end
    s:routePointer({live},"OnMouseUp","LeftButton")
    check(#selected==1 and selected[1]==displayed[first.id].id and displayed[second.id],
        "the existing Ctrl-click still opens the primary while the additional player has an independent encounter")
    control=false
    s:event("MODIFIER_STATE_CHANGED","LCTRL",0)
    s:routePointer({live},"OnMouseDown","LeftButton")
    s:routePointer({live},"OnMouseUp","LeftButton")
    check(#selected==1 and live.EnableMouseArgs[1]==false,
        "a grouped banner remains click-through without Ctrl")

    s:set("mouseover",third.fullName,third.guid,true)
    s:tick(.25)
    s:tick(.36)
    check(live.more:GetText()=="+2 more" and live.character:GetText()==first.fullName
        and live.reasons:GetText()=="Griefing" and sounds==1 and not live.transition,
        "another qualifying distinct sighting increments the count without showing its name or reason")
    s:set("mouseover",third.fullName,third.guid,true)
    s:tick(2)
    check(live.more:GetText()=="+2 more" and sounds==1 and not live.transition,
        "repeated detection cannot increment the live count or replay motion")
    s:set("mouseover",fourth.fullName,fourth.guid,true)
    s:tick(.25)
    check(live.more:GetText()=="+2 more" and sounds==1 and not live.transition,
        "extending the hold does not extend the initial grouping window")
    s:tick(8.5)
    check(live:IsShown() and not live.more:IsShown() and live.character:GetText()==fourth.fullName and sounds==2,
        "a later sighting uses the normal queued alert after the group expires")
end

do
    local _,s,e=fresh()
    s:add("First Person","first")
    s:add("Second Person","second")
    s:add("Third Person","third")
    s:set("target","First Person","first",true)
    s:set("mouseover","Second Person","second",true)
    s:tick(.25)
    s:tick(.06)
    local live=e.WhowhoBlacklistLiveBanner
    local pulse=live.transition
    local firstAlpha=live.more.SetAlphaArgs[1]
    check(live.more:GetText()=="+1 more" and pulse and firstAlpha>0 and firstAlpha<.2,
        "the original count has begun one pulse")
    s:set("mouseover","Third Person","third",true)
    s:tick(.25)
    check(live.more:GetText()=="+2 more" and live.transition==pulse and live.more.SetAlphaArgs[1]>.9,
        "a new arrival retargets the visible count and continues the same easing")
    s:tick(.06)
    check(live.more:GetText()=="+2 more" and not live.transition and live.content:GetScale()==1,
        "the existing pulse settles with the newest count")
end

for _,interruption in ipairs({"new-target","test","instance","render-reentry","alpha-reentry"}) do
    local p,s,e=fresh()
    local B=p.BlacklistBanner
    s:add("First Person","first")
    s:add("Second Person","second")
    s:set("target","First Person","first",true)
    s:set("mouseover","Second Person","second",true)
    local live=e.WhowhoBlacklistLiveBanner
    local addLive=B.addLive
    if interruption=="new-target" then
        B.addLive=function(...)
            B.addLive=addLive
            s:set("target",nil,nil,true)
            return addLive(...)
        end
        s:tick(.25)
        s:tick(.4)
        check(live:IsShown() and not live.more:IsShown() and not live.transition,
            "a reentrant target replacement cannot commit a stale group")
        s:tick(8)
        check(live:IsShown() and live.character:GetText()=="Second Person",
            "the second sighting remains queued after a rejected group")
    else
        s:tick(.25)
        s:tick(.06)
        assert(live.transition)
        if interruption=="test" then B.toggleTest()
        elseif interruption=="alpha-reentry" then
            local setAlpha=live.more.SetAlpha
            live.more.SetAlpha=function(self,alpha)
                setAlpha(self,alpha)
                self.SetAlpha=setAlpha
                B.toggleTest()
            end
        elseif interruption=="render-reentry" then
            local getWidth=e.UIParent.GetWidth
            e.UIParent.GetWidth=function(self)
                self.GetWidth=getWidth
                B.toggleTest()
                return getWidth(self)
            end
        else
            e.IsInInstance=function() return true,"party" end
            s:event("ZONE_CHANGED_NEW_AREA")
        end
        s:tick(.1)
        check(not live:IsShown() and not live.more:IsVisible() and not live.transition and live.content:GetScale()==1,
            "a live motion cancelled by "..interruption.." cannot swap or pulse later")
    end
end

do
    local p,s,e=fresh({scale=.9,skipDeleteConfirmation=true,alertSoundEnabled=false})
    local calls={}
    e.C_Sound={PlaySoundWithOptions=function(options)
        local test=e.WhowhoBlacklistTestBanner
        calls[#calls+1]={options=options,visible=test and test:IsVisible()}
        if #calls==1 then return false end
    end}
    check(type(p.version)=="string"
        and os.getenv("WHOWHO_PREVIEW_TOC"):match("## Version:%s*(%S+)")==p.version,
        "runtime and installed TOC identify the same version")
    p.Toggle()
    local S=p.Shell
    S.nav.settings:Click()
    check(S.testSoundButton.label:GetText()=="Test sound" and not S.liveSoundToggle.checked
        and S.volumeLabel:GetText()=="100%","upgrading preserves a saved sound-off preference")
    check(#calls==0,"opening Settings is silent")
    S.testBannerButton:Click(); S.testBannerButton:Click()
    check(#calls==0,"the test banner respects the saved sound-off preference")
    S.testSoundButton:Click()
    local options=calls[1] and calls[1].options
    check(#calls==1 and options.soundKitID==416 and options.forceNoDuplicates==true
        and options.uiSoundSubType==nil and options.volumeOverride==1.2,
        "explicit preview works with live sound off and sends the 120% cap once without retry")
    S.volumeSlider:SetValue(25)
    check(#calls==1 and S.volumeLabel:GetText()=="25%","volume changes update the percentage silently")
    S.testSoundButton:Click()
    check(#calls==2 and calls[2].options.volumeOverride==.30,"25% auditions at 30% of native volume")
    S.volumeSlider:SetValue(75)
    S.liveSoundToggle:Click()
    check(S.liveSoundToggle.checked and #calls==2,"enabling live sound is silent")
    local reloaded=fresh(p.db)
    check(reloaded.db.alertSoundEnabled and reloaded.db.alertSoundVolume==75 and reloaded.db.skipDeleteConfirmation,
        "volume and enabled state survive reload with existing preferences")
    S.testBannerButton:Click()
    check(#calls==3 and calls[3].visible and calls[3].options.volumeOverride==.90,
        "showing the test banner plays once at the current volume after it becomes visible")
    local banner=e.WhowhoBlacklistTestBanner
    p.BlacklistBanner.resize()
    s:fire(banner,"OnDragStart"); s:fire(banner,"OnDragStop")
    s:fire(banner,"OnUpdate",8.25)
    S.testBannerButton:Click()
    check(#calls==3 and not shown(banner),"resizing, dragging, fading and hiding the test banner are silent")
    S.volumeSlider:SetValue(50); S.testBannerButton:Click()
    check(#calls==4 and calls[4].options.volumeOverride==.60,"reopening the test banner uses the new volume")
    s:fire(banner,"OnUpdate",8.5)
    S.volumeSlider:SetValue(0); S.testSoundButton:Click(); S.testBannerButton:Click()
    check(#calls==4 and shown(banner),"0% silences both auditions and visible test banners")
    S.testBannerButton:Click()
    S.volumeSlider:SetValue(75)
    S.liveSoundToggle:Click()
    reloaded=fresh(p.db)
    check(not S.liveSoundToggle.checked and not reloaded.db.alertSoundEnabled and reloaded.db.alertSoundVolume==75
        and #calls==4 and s.forbiddenCalls==0,"muting is silent and retains volume through reload")
    local new=fresh()
    local unset=fresh({scale=.9})
    local low=fresh({alertSoundVolume=-20,alertSoundEnabled="yes"})
    local high=fresh({alertSoundVolume=140})
    local malformed=fresh({alertSoundVolume="75"})
    local nonfinite=fresh({alertSoundVolume=math.huge})
    check(new.db.alertSoundEnabled and new.db.alertSoundVolume==100
        and unset.db.alertSoundEnabled and unset.db.alertSoundVolume==100,
        "new and unset preferences enable banner sound at 100%")
    check(low.db.alertSoundVolume==0 and not low.db.alertSoundEnabled and high.db.alertSoundVolume==100,
        "finite saved volumes clamp and malformed enabled settings fail closed")
    check(malformed.db.alertSoundVolume==0 and nonfinite.db.alertSoundVolume==0,
        "malformed explicit volumes fail closed")
end

do
    local p,s,e=fresh({alertSoundVolume=40})
    local calls={}
    e.C_Sound={PlaySoundWithOptions=function(options)
        local live=e.WhowhoBlacklistLiveBanner
        calls[#calls+1]={name=live.character:GetText(),visible=shown(live),volume=options.volumeOverride}
        s:event("PLAYER_TARGET_CHANGED")
    end}
    s:add("First Person","one")
    s:add("Second Person","two")
    s:set("target","First Person","one",true)
    check(#calls==1 and calls[1].name=="First Person" and calls[1].visible and calls[1].volume==.48,
        "default-on live sound follows a committed visible banner once when playback reenters the observer")
    s:set("mouseover","Second Person","two",true)
    check(#calls==1,"a queued banner is silent")
    s:tick(8.5)
    check(#calls==2 and calls[2].name=="Second Person","the queued banner plays only when its own display commits")
    s:set("target",nil,nil,true)
    s:set("mouseover",nil,nil,true)
    s:tick(8.5)
    s:set("target","First Person","one",true)
    check(#calls==2 and not shown(e.WhowhoBlacklistLiveBanner),"a new episode during cooldown remains silent")
    s:set("target",nil,nil,true)
    s:tick(31)
    p.manual.alertSound.setEnabled(false)
    s:set("target","First Person","one",true)
    check(#calls==2 and shown(e.WhowhoBlacklistLiveBanner),"muting leaves eligible banners visible")
    check(s.forbiddenCalls==0,"manual alert sound leaves global settings and alternate sound routes untouched")
end

for _,case in ipairs({"hidden-parent","hidden-during-show","expired"}) do
    local p,s,e=fresh()
    local calls=0
    e.C_Sound={PlaySoundWithOptions=function(options)
        local live=e.WhowhoBlacklistLiveBanner
        assert(live:IsVisible() and live.character:GetText()=="First Person" and options.volumeOverride==1.2)
        calls=calls+1
    end}
    local B=p.BlacklistBanner
    if case=="hidden-during-show" then
        local show=B.showLive
        B.showLive=function(...)
            local ownsAppearance=show(...)
            B.showLive=show
            e.UIParent:Hide()
            return ownsAppearance
        end
    else
        e.UIParent:Hide()
    end
    s:add("First Person","first")
    s:set("target","First Person","first",true)
    check(calls==0 and not shown(e.WhowhoBlacklistLiveBanner),
        "a live alert never commits a child hidden by its ancestor: "..case)
    local reads=s.reads()
    s:tick(case=="expired" and 13 or 2)
    check(s.reads()==reads,"a hidden observer does not poll: "..case)
    e.UIParent:Show()
    check(calls==0 and not shown(e.WhowhoBlacklistLiveBanner),"restoring the UI does not uncover a stale paint: "..case)
    s:tick(.25)
    local live=e.WhowhoBlacklistLiveBanner
    check(calls==1 and live:IsVisible(),"a current sighting plays once when it visibly appears: "..case)
    s:tick(.25)
    check(calls==1,"subsequent visible updates do not repeat the cue: "..case)
end

for _,case in ipairs({"world","region","store","visible","hidden-parent","replaced","fade","test","instance","muted","zero","restricted","error","missing"}) do
    local p,s,e,A=fresh({alertSoundEnabled=true})
    local calls,lookups=0,0
    local function play()
        calls=calls+1
        if case=="error" then error("simulated sound failure") end
    end
    e.C_Sound=setmetatable({}, {__index=function()
        lookups=lookups+1
        if case=="world" then s:event("PLAYER_LEAVING_WORLD")
        elseif case=="region" then s.region(4)
        elseif case=="store" then A.store={}
        elseif case=="visible" then p.BlacklistBanner.hideLive()
        elseif case=="hidden-parent" then e.UIParent:Hide()
        elseif case=="replaced" then p.BlacklistBanner.showLive("Replacement Name","Other")
        elseif case=="fade" then p.BlacklistBanner.fade(.5)
        elseif case=="test" then p.BlacklistBanner.toggleTest()
        elseif case=="instance" then e.IsInInstance=function() return true,"raid" end
        elseif case=="muted" then A.alertSound.setEnabled(false)
        elseif case=="zero" then A.alertSound.setVolume(0)
        elseif case=="restricted" then return s.secret
        elseif case=="missing" then return nil end
        return play
    end})
    s:add("First Person","one")
    s:set("target","First Person","one",true)
    check(lookups==1 and calls==(case=="error" and 1 or 0),"sound lookup fails closed or makes one safe attempt: "..case)
end

for _,case in ipairs({"hidden","hidden-parent","replaced","fade","muted","zero","protected-table","restricted","owner-error","error","missing"}) do
    local p,s,e,A=fresh()
    local calls, lookups=0,0
    local B=p.BlacklistBanner
    local api=setmetatable({}, {__index=function()
        lookups=lookups+1
        local banner=e.WhowhoBlacklistTestBanner
        if case=="hidden" then B.hideTest()
        elseif case=="hidden-parent" then e.UIParent:Hide()
        elseif case=="replaced" then B.hideTest(); B.toggleTest()
        elseif case=="fade" then s:fire(banner,"OnUpdate",8.25)
        elseif case=="muted" then A.alertSound.setEnabled(false)
        elseif case=="zero" then A.alertSound.setVolume(0)
        elseif case=="restricted" then return s.secret
        elseif case=="missing" then return nil
        elseif case=="owner-error" and lookups==1 then
            local getScript=banner.GetScript
            banner.GetScript=function(self)
                self.GetScript=getScript
                error("simulated appearance check failure")
            end
        end
        return function()
            calls=calls+1
            if case=="error" then error("simulated sound failure") end
        end
    end})
    e.C_Sound=api
    local protectedChecks=0
    e.issecrettable=function(value)
        if case=="protected-table" and value==api then protectedChecks=protectedChecks+1; return true end
        return false
    end
    B.toggleTest()
    check(calls==(case=="error" and 1 or 0)
        and (case~="protected-table" or protectedChecks==1 and lookups==0),
        "test banner sound fails closed or attempts playback once: "..case)
    if case=="error" or case=="owner-error" then
        B.hideTest(); B.toggleTest()
        check(calls==(case=="error" and 2 or 1),"a failed sound attempt leaves the next appearance able to play: "..case)
    end
end

do
    local p,s,e,A=fresh()
    local player=s:add("Original Name",nil)
    local ledger=A.encounterLedger
    local function record(id,region,name,guid)
        A.region=region
        local observation=assert(ledger.start({id=id,name=name,guid=guid},region,99))
        ledger.observe(observation,true,false,0,"Elsewhere")
        ledger.stop(observation,0)
        A.region=3
    end
    record(player.id,4,player.fullName,"other-region")
    record(player.id,3,"Another Name","other-name")
    record(player.id+10,3,player.fullName,"other-record")
    e.GetRealZoneText=function() return "Durotar" end
    e.UnitClass=function(token)
        return s.units[token].guid=="first" and "Mage" or "Priest",
            s.units[token].guid=="first" and "MAGE" or "PRIEST"
    end
    s:set("target",player.fullName,"first",true)
    local live=e.WhowhoBlacklistLiveBanner
    local original=ledger.snapshot(3,100).Now[1]
    check(shown(live) and original.guid=="first" and knownClass(p.manual,player)=="MAGE",
        "encounters with another record ID, region or exact name leave the name fallback available")
    s:set("mouseover",player.fullName,"replacement",true)
    check(shown(live) and ledger.snapshot(3,100).Now[1]==original and not original.mouseover,
        "a conflicting mouseover cannot displace an exact active target")
    s:set("target",nil,nil,true)
    s:set("mouseover",nil,nil,true)
    s:tick(31)
    s:set("target",player.fullName,"replacement",true)
    local current=ledger.snapshot(3,131).Now
    local _,zone=ledger.latestBlacklistObservation(player)
    check(not shown(live) and #current==3 and current[1]==original and zone=="Durotar"
        and knownClass(p.manual,player)=="MAGE",
        "a different GUID cannot inherit the alert, observation or class after the original episode ends")

    local _,rs,re,RA=fresh(nil,nil,e.WhowhoEncounterDB,A.store.export())
    local rledger=RA.encounterLedger
    rs:set("target",player.fullName,"replacement",true)
    check(not shown(re.WhowhoBlacklistLiveBanner) and rledger.blacklistRecord(original).id==player.id,
        "retained exact GUID ownership survives reload")
    assert(RA.delete(RA.records[1]))
    local replacement=rs:add(player.fullName,nil)
    check(replacement.id~=player.id and not rledger.blacklistRecord(original)
        and not rledger.latestBlacklistObservation(replacement),"re-adding creates an independent record with no inherited history")
    rs:set("target",nil,nil,true)
    rs:set("target",replacement.fullName,"replacement",true)
    check(shown(re.WhowhoBlacklistLiveBanner),"the new record can match its own verified character")
end

do
    local _,s,e,A=fresh()
    local player=s:add("Legacy Name",nil)
    local ledger=A.encounterLedger
    local legacy={}
    for i,guid in ipairs({"first","replacement"}) do
        local id=assert(ledger.start({id=player.id,name=player.fullName,guid=guid},3,97+i))
        ledger.observe(id,true,false,0,"Durotar")
        ledger.stop(id,0)
        legacy[i]=e.WhowhoEncounterDB.regions[3][1]
    end
    for _,row in ipairs(legacy) do
        s:set("target",player.fullName,row.guid,true)
        check(not shown(e.WhowhoBlacklistLiveBanner) and not ledger.blacklistRecord(row),
            "conflicting legacy GUIDs leave both historical rows without automatic membership links")
    end
    check(#ledger.groups(3,100)==2 and not ledger.latestBlacklistObservation(player),
        "legacy conflicts preserve the history and suppress ambiguous Blacklist Last seen")
end

do
    local _,s,e,A=fresh()
    local player=s:add("Retained Name",nil)
    local ledger=A.encounterLedger
    local id=assert(ledger.start({id=player.id,name=player.fullName,guid="old"},3,100))
    ledger.observe(id,true,false,0,"Durotar")
    ledger.stop(id,0)
    s.advance(30*86400-1)
    s:set("target",player.fullName,"new",true)
    check(not shown(e.WhowhoBlacklistLiveBanner),"known GUID evidence still applies before the age cutoff")
    local serverTime=e.GetServerTime
    e.GetServerTime=function() return nil end
    s.advance(1)
    s:event("PLAYER_TARGET_CHANGED")
    check(not shown(e.WhowhoBlacklistLiveBanner),"unreadable time keeps the retained GUID evidence in force")
    e.GetServerTime=serverTime
    check(not ledger.latestBlacklistObservation(player) and #e.WhowhoEncounterDB.regions[3]==1,
        "expired observation evidence is ignored before physically trimming its row")
    s:event("PLAYER_TARGET_CHANGED")
    check(shown(e.WhowhoBlacklistLiveBanner) and #e.WhowhoEncounterDB.regions[3]==1,
        "matching uses the retention cutoff without depending on the ledger pane")
end

do
    local p,s,e=fresh()
    s:add("First Person","first")
    p.BlacklistBanner.toggleTest()
    s:set("target","First Person","first",true)
    s:tick(13)
    p.BlacklistBanner.toggleTest()
    s:tick(.25)
    check(shown(e.WhowhoBlacklistLiveBanner) and e.WhowhoBlacklistLiveBanner.character:GetText()=="First Person",
        "test closure retries an expired pending sighting when its observed target remains readable")
end

do
    local p,s,e=fresh()
    s:add("First Person","first")
    p.BlacklistBanner.toggleTest()
    s:set("target","First Person","first",true)
    s:set("target",nil,nil,true)
    s:tick(13)
    p.BlacklistBanner.toggleTest()
    s:tick(.25)
    check(not shown(e.WhowhoBlacklistLiveBanner),"test closure does not replay an expired cleared target")
end

do
    local p,s,e,A=fresh()
    s:add("First Person","first")
    s:add("Second Person","second")
    s:set("target","First Person","first",true)
    s:set("mouseover","Second Person","second",true)
    s.units.mouseover.restricted=true
    s:event("UPDATE_MOUSEOVER_UNIT")
    s:tick(8.5)
    check(not shown(e.WhowhoBlacklistLiveBanner),"restricted queued identity is discarded")
    s.units.mouseover.restricted=false
    s:event("UPDATE_MOUSEOVER_UNIT")
    check(shown(e.WhowhoBlacklistLiveBanner) and e.WhowhoBlacklistLiveBanner.character:GetText()=="Second Person",
        "fresh readable evidence can enqueue a previously discarded episode")
end

do
    local p,s,e,A=fresh()
    s:add("First Person","first")
    s:add("Second Person","second")
    s:set("target","First Person","first",true)
    s:set("mouseover","Second Person","second",true)
    s:set("mouseover",nil,nil,true)
    local replacement={}
    for key,value in pairs(A.store) do replacement[key]=value end
    A.store=replacement
    s:tick(8.5)
    check(shown(e.WhowhoBlacklistLiveBanner) and e.WhowhoBlacklistLiveBanner.character:GetText()=="Second Person",
        "replacing the store preserves an unchanged exact queued sighting")
end

do
    local p,s,e=fresh()
    s:add("First Person","first")
    e.GetTime=function() return nil end
    p.BlacklistBanner.toggleTest()
    s:set("target","First Person","first",true)
    s:set("target",nil,nil,true)
    check(s.observer:GetScript("OnUpdate")~=nil,"pending sighting keeps its expiry clock running during the test")
    s:tick(13)
    p.BlacklistBanner.toggleTest()
    s:tick(.25)
    check(not shown(e.WhowhoBlacklistLiveBanner),"expired sighting does not appear after the test with an unavailable clock")
end

do
    local p,s,e,A=fresh()
    s:add("First Person","first")
    local second=s:add("Second Person","second")
    s:set("target","First Person","first",true)
    s:tick(.25)
    s:set("mouseover","Second Person","second",true)
    s:set("mouseover",nil,nil,true)
    s:tick(8.25)
    local live=e.WhowhoBlacklistLiveBanner
    check(live.backing.texture==p.media.."LedgerBanner.tga" and table.concat(live.backing.sliceMargins,",")=="16,10,8,8"
        and live.backing:GetParent()==live.character:GetParent(),"live banner uses one sliced texture for the rim and backing")
    check(shown(live) and live.character:GetText()=="Second Person","transient distinct sighting displays after the first banner")
    s:tick(8.5)
    check(not shown(live),"transient sighting is displayed only once")
    s:set("target",nil,nil,true)
    s:tick(5)
    s.advance(17)
    s:set("target","First Person","first",true)
    s:set("mouseover","Second Person","second",true)
    s:set("mouseover",nil,nil,true)
    assert(A.store.delete(second.id,second.region,second.fullName,second.guid))
    A.refresh()
    s:tick(8.5)
    check(not shown(live),"removed pending member is discarded")
    second=s:add("Second Person","second")
    s:set("target",nil,nil,true)
    s:tick(5)
    s.advance(17)
    s:set("target","First Person","first",true)
    s:set("mouseover","Second Person","second",true)
    s:set("mouseover",nil,nil,true)
    s:event("PLAYER_LEAVING_WORLD")
    s:set("target",nil,nil)
    s:event("PLAYER_ENTERING_WORLD")
    s:tick(9)
    check(not shown(live),"world change discards pending sightings")
end

do
    local p,s,e=fresh()
    s:add("First Person","first")
    s:set("mouseover","First Person","first",true)
    s:set("mouseover",nil,nil,true)
    s:tick(8.5)
    s:tick(5)
    -- The unit event and observer callback occur in the same delayed frame.
    s.advance(17)
    s:set("target","First Person","first",true)
    local live=e.WhowhoBlacklistLiveBanner
    local update=s.observer:GetScript("OnUpdate")
    update(s.observer,2)
    s:tick(8)
    check(shown(live) and live.SetAlphaArgs[1]==1,"event-before-observer hitch preserves the full live hold")
end

do
    local p,s,e,A=fresh()
    s:add("Veyra Ashfall","first",{"griefing","ninja_looting"})
    s:add("Álora Winter","second",{"other"})
    s:set("mouseover","Álora Winter","second")
    s:set("target","Veyra Ashfall","first",true)
    local live=e.WhowhoBlacklistLiveBanner
    check(shown(live) and live.character:GetText()=="Veyra Ashfall","real default binding shows an exact target match")
    check(live.reasons:GetText()=="Griefing · Ninja looting","only catalog reason labels are rendered")
    check(live.character.justifyH=="CENTER" and live.reasons.justifyH=="CENTER","both lines are centered")
    check(live.parent==e.UIParent and live.EnableMouseArgs[1]==false and not live.RegisterForDragArgs,
        "the live frame is click-through without Ctrl")
    s:tick(8)
    check(live.SetAlphaArgs[1]==1,"live banner stays fully opaque for eight seconds")
    s:tick(.25)
    check(live.SetAlphaArgs[1]==.5,"live banner fades after its eight-second hold")
    s:tick(.25)
    check(shown(live) and live.character:GetText()=="Álora Winter" and live.SetAlphaArgs[1]==1,"second distinct current match uses its own full display interval")
    s:tick(8.5)
    check(not shown(live),"continuous matches never re-alert when the display expires")
    s:set("mouseover","Veyra Ashfall","first",true)
    check(not shown(live),"overlapping sources coalesce the same identity")
    s:set("target",nil,nil,true)
    s:tick(6)
    check(not shown(live),"mouseover keeps the encounter active after target clears")
    s:set("mouseover",nil,nil)
    s:tick(.25)
    s:tick(4.75)
    s:set("target","Veyra Ashfall","first",true)
    check(not shown(live),"silent hover clearance starts a five-second observed absence grace")
    s:set("target",nil,nil,true)
    s:tick(5)
    s:set("target","Veyra Ashfall","first",true)
    check(shown(live) and live.character:GetText()=="Veyra Ashfall","a new encounter alerts after both the absence grace and cooldown")
    s:tick(8.5)
    check(not s.observer:GetScript("OnUpdate"),"a stationary target does not keep polling after its alert")
    check(not next(A.targetCheck.observations) and not e.WhowhoAddressBookDB and s.forbiddenCalls==0,
        "passive warnings neither publish Friends status nor persist or send anything")
end

do
    local p,s,e=fresh({automaticTarget=false,automaticMouseover=false,bannerPosition={x=math.huge,y=5}})
    s:add("Veyra Ashfall","first",{"griefing"})
    p.Toggle()
    p.Shell.nav.settings:Click()
    local S=p.Shell
    local button=S.testBannerButton
    local _,x,y=button:GetPoint()
    check(button:IsVisible() and x+button:GetWidth()<S.settings:GetWidth()
        and -y+button:GetHeight()<S.settings:GetHeight(),"Settings exposes the test button within compact layout bounds")
    local function verifyScaleRow(minTrackWidth)
        S.settingsTabs.general:Click()
        checkTabs(p,S.settings,{"Alerts","Friends","General"},3)
        local _,sliderX,sliderY=S.scaleSlider:GetPoint()
        local _,percentX,percentY=S.scaleLabel:GetPoint()
        check(S.scaleSlider:IsVisible() and not button:IsVisible()
            and percentY-S.scaleLabel:GetHeight()/2==sliderY-S.scaleSlider:GetHeight()/2
            and S.scaleSlider:GetWidth()>=minTrackWidth,"slider and percentage stay on one usable row")
        check(sliderX+S.scaleSlider:GetWidth()<percentX and percentX+S.scaleLabel:GetWidth()<S.settings:GetWidth(),
            "scale controls have a gap and keep the percentage in bounds")
        S.settingsTabs.alerts:Click()
    end
    verifyScaleRow(48)
    e.UIParent:SetSize(1360,832); p.SetScale(1)
    verifyScaleRow(200)
    e.UIParent:SetSize(484,800); p.SetScale(1)
    check(p.db.bannerPosition==nil,"invalid saved coordinates use the default anchor")
    s:set("target","Veyra Ashfall","first")
    local before=s.reads()
    button:Click()
    local test=e.WhowhoBlacklistTestBanner
    check(shown(test) and button.label:GetText()=="Hide test banner" and test.EnableMouseArgs[1]
        and test:GetFrameStrata()=="FULLSCREEN_DIALOG" and p.Shell.window:GetFrameStrata()=="DIALOG",
        "Settings opens a draggable full-size test above the addon window")
    check(test.character:GetText()=="Veyra Ashfall" and test.reasons:GetText()=="Griefing · Ninja looting","test uses its fixed sample")
    check(test.backing.texture==p.media.."LedgerBanner.tga" and table.concat(test.backing.sliceMargins,",")=="16,10,8,8"
        and test.backing:GetParent()==test.character:GetParent(),"test banner uses one sliced texture for the rim and backing")
    local dismissedUpdate=test:GetScript("OnUpdate")
    button:Click()
    check(not test:GetScript("OnUpdate"),"manual dismissal relinquishes the test timer")
    dismissedUpdate(test,20)
    check(not shown(test) and button.label:GetText()=="Test banner" and s.reads()==before
        and not shown(e.WhowhoBlacklistLiveBanner),"toggling the test alone never samples units or creates a live alert")
    button:Click()
    local function tickTest(elapsed)
        local update=test:GetScript("OnUpdate")
        if update then update(test,elapsed) end
    end
    tickTest(8)
    check(shown(test) and test.SetAlphaArgs[1]==1,"reopened test stays fully opaque for eight seconds")
    tickTest(.25)
    check(test.SetAlphaArgs[1]==.5,"test fades over half a second after its hold")
    tickTest(.25)
    check(not shown(test) and not test:GetScript("OnUpdate") and button.label:GetText()=="Test banner",
        "test expiry clears its timer and refreshes the Settings label")
    button:Click()
    tickTest(7)
    test.GetCenter=function() return 440,260 end
    e.UIParent.GetCenter=function() return 242,400 end
    s.combat(true)
    s:fire(test,"OnDragStart")
    check(not test.moving,"combat prevents test drag from starting")
    s.combat(false)
    s:fire(test,"OnDragStart")
    tickTest(20)
    check(shown(test) and test.SetAlphaArgs[1]==1,"active drag pauses the test timer")
    s:fire(test,"OnDragStop")
    tickTest(1)
    check(shown(test) and test.SetAlphaArgs[1]==1,"test timer resumes after drag release")
    local position=p.db.bannerPosition
    check(position.x==198 and position.y==-140 and not test.moving,"drag release saves a center-relative position")
    local _,_,_,clampedX,clampedY=test:GetPoint()
    check(clampedX==79 and clampedY==-140,"saved position is clamped to the viewport")
    s:fire(test,"OnDragStart")
    button:Click()
    check(not test.moving and p.db.bannerPosition==position,"hiding the test cancels an unfinished drag")
    button:Click()
    s:event("PLAYER_TARGET_CHANGED")
    check(not shown(e.WhowhoBlacklistLiveBanner),"a real sighting leaves the test undisturbed")
    tickTest(8.5)
    check(not shown(e.WhowhoBlacklistLiveBanner),"closing the test defers the live alert to the observer tick")
    s:tick(2)
    local live=e.WhowhoBlacklistLiveBanner
    check(shown(live) and live.reasons:GetText()=="Griefing","an already observed live sighting can display when the test closes")
    s:tick(8)
    check(shown(live) and live.SetAlphaArgs[1]==1,"test-first frame hitch does not shorten the live hold")
    local _,_,_,liveX,liveY=live:GetPoint()
    check(liveX==clampedX and liveY==clampedY and test:GetWidth()==live:GetWidth(),"live and test use the same saved anchor and full size")
    local reloaded,sim,env=fresh(p.db)
    reloaded.Toggle()
    reloaded.Shell.nav.settings:Click()
    reloaded.Shell.testBannerButton:Click()
    local _,_,_,restoredX,restoredY=env.WhowhoBlacklistTestBanner:GetPoint()
    check(restoredX==liveX and restoredY==liveY and sim.forbiddenCalls==0,"drag position survives reload")
end

do
    local p,s,e,A=fresh({automaticTarget=false,automaticMouseover=false})
    s:add("Veyra Ashfall","saved",{"griefing"})
    s:add("Another Person","other")
    s:add("Remote Person","remote",nil,nil,4)
    s:add("Friendly Person","friendly",{},"friend")
    for _,unit in ipairs({
        {name="Veyra"}, {name="veyra Ashfall"}, {name="Veyra Ashfall",guid="other"},
        {name="Veyra Ashfall",guid="saved",self=true}, {name="Veyra Ashfall",guid="saved",player=false},
        {name="Remote Person",guid="remote"}, {name="Friendly Person",guid="friendly"},
        {name="Veyra Ashfall",guid="saved",restricted=true}, {name="Veyra Ashfall",guid=s.secret}
    }) do
        s.units.target=unit
        s:event("PLAYER_TARGET_CHANGED")
        check(not shown(e.WhowhoBlacklistLiveBanner),"partial, unrelated, conflicting or restricted identities do not alert")
    end
    local reads=s.reads()
    s.units.target={name="Veyra Ashfall",guid="saved",restricted=true}
    s:event("PLAYER_TARGET_CHANGED")
    check(s.reads()==reads,"a restricted identity is skipped before name or GUID access")
    local lookup=A.store.find
    A.store.find=function(...)
        local record=lookup(...)
        if record then record.reasonIds={} end
        return record
    end
    s:set("target","Veyra Ashfall","saved",true)
    check(not shown(e.WhowhoBlacklistLiveBanner),"a match requires explicit catalog reasons")
    A.store.find=lookup
    s.region(4)
    s:event("PLAYER_TARGET_CHANGED")
    check(not shown(e.WhowhoBlacklistLiveBanner),"changing native region prevents stale matches")
    s.region(3)
    local nativeName=e.GetUnitName
    local nested=false
    e.GetUnitName=function(token)
        if not nested then
            nested=true
            s:set("target","Another Person","other",true)
        end
        return nativeName(token)
    end
    s:event("PLAYER_TARGET_CHANGED")
    check(not shown(e.WhowhoBlacklistLiveBanner),"a nested signal invalidates the prior sample")
    s:tick(.25)
    local live=e.WhowhoBlacklistLiveBanner
    check(shown(live) and live.character:GetText()=="Another Person","only the current nested identity can alert")
    local oldUpdate=s.observer:GetScript("OnUpdate")
    s:event("PLAYER_LEAVING_WORLD")
    s:set("target","Veyra Ashfall","saved",true)
    oldUpdate(s.observer,10)
    check(not shown(live),"leaving the world cancels active display and suppresses late signals")
    s:event("PLAYER_ENTERING_WORLD",false,false)
    check(shown(live) and live.character:GetText()=="Veyra Ashfall","new world samples its own context")
    s.units.target.restricted=true
    s:tick(.25)
    check(not shown(live),"loss of identity readability cancels the display")
    s:tick(6)
    s.units.target.restricted=false
    s:event("PLAYER_TARGET_CHANGED")
    check(not shown(live),"unreadable gaps never rearm a continuous target")
end

do
    local p,s,e,A=fresh()
    local original=s:add("First Person","first")
    s:set("mouseover","First Person","first",true)
    local live=e.WhowhoBlacklistLiveBanner
    s:set("mouseover",nil,nil,true)
    s:tick(8.5)
    assert(A.store.delete(original.id,original.region,original.fullName,original.guid))
    check(s:add("First Person","first").id~=original.id,"re-adding assigns a new record ID")
    s.advance(21.25)
    s:set("target","First Person","first",true)
    check(not shown(live),"delete and re-add plus switching sources still respects the name cooldown")
    s:tick(.5)
    p.BlacklistBanner.toggleTest()
    p.BlacklistBanner.toggleTest()
    s:tick(.25)
    check(not shown(live),"expiry or Test banner closure does not revive a suppressed encounter")
    s:set("target",nil,nil,true)
    s:tick(5)
    s:set("mouseover","First Person","first",true)
    check(shown(live),"a fresh hover after both deadlines shows again")
end

do
    local p,s,e=fresh()
    s:add("First Person","first")
    p.BlacklistBanner.toggleTest()
    s:set("target","First Person","first",true)
    s:tick(10)
    p.BlacklistBanner.toggleTest()
    s:tick(.25)
    local live=e.WhowhoBlacklistLiveBanner
    check(shown(live),"a live alert displays after the Test banner")
    s:set("target",nil,nil,true)
    s:tick(8.5)
    s.advance(11.25)
    s:set("target","First Person","first",true)
    check(not shown(live),"queue time does not start the thirty-second cooldown")
    s:set("target",nil,nil,true)
    s:tick(5)
    s.advance(5.25)
    s:set("target","First Person","first",true)
    check(shown(live),"a fresh encounter is eligible at exactly thirty seconds after display")
end

do
    local p,s,e=fresh()
    s:add("First Person","first")
    s:set("target","First Person","first",true)
    local live=e.WhowhoBlacklistLiveBanner
    s:set("target",nil,nil,true)
    s:tick(8.5)
    check(not s.observer:GetScript("OnUpdate"),"cooldowns alone do not keep the observer ticking")
    local time=e.GetTime
    e.GetTime=function() return nil end
    s.advance(25)
    s:set("target","First Person","first",true)
    check(not shown(live),"an unreadable clock after idle does not expire cooldown early")
    e.GetTime=time
    s:event("PLAYER_TARGET_CHANGED")
    check(not shown(live),"clock recovery does not revive the encounter skipped during cooldown")
    s:set("target",nil,nil,true)
    s:tick(5)
    s:set("target","First Person","first",true)
    check(shown(live),"a fresh encounter can alert after the clock recovers")
end

do
    local p,s,e,A=fresh()
    s:add("First Person","first")
    s:add("First Person","elsewhere",nil,nil,4)
    s:set("target","First Person","first",true)
    local live=e.WhowhoBlacklistLiveBanner
    s:event("PLAYER_LEAVING_WORLD")
    A.region=4; s.region(4)
    s:set("target","First Person","elsewhere")
    s:event("PLAYER_ENTERING_WORLD")
    check(shown(live),"the same name in a different validated region has its own cooldown")
    s:event("PLAYER_LEAVING_WORLD")
    A.region=3; s.region(3)
    s:set("target","First Person","first")
    s:event("PLAYER_ENTERING_WORLD")
    check(not shown(live),"the original region cooldown survives a world transition")
end

do
    local p,s,e=fresh({automaticTarget=false,automaticMouseover=false})
    s:add("First Person","first")
    s:add("Second Person","second")
    local inside,kind=false,"none"
    e.IsInInstance=function() return inside,kind end
    s:set("target","First Person","first",true)
    local live=e.WhowhoBlacklistLiveBanner
    s:set("mouseover","Second Person","second",true)
    inside,kind=true,"party"
    local before=s.reads()
    s:event("ZONE_CHANGED_NEW_AREA")
    check(not shown(live) and s.reads()==before,"dungeon entry hides the live banner before reading players")
    p.BlacklistBanner.toggleTest()
    check(p.BlacklistBanner.testShown(),"Test banner is available in a dungeon")
    kind="raid"
    s:event("PLAYER_LEAVING_WORLD")
    s:event("PLAYER_ENTERING_WORLD")
    check(p.BlacklistBanner.testShown() and not shown(live),"raid transition keeps the Test banner and suppresses live banners")
    p.BlacklistBanner.toggleTest()
    s:set("target",nil,nil,true)
    s:set("target","First Person","first",true)
    s:tick(9)
    check(not shown(live),"target and hover events in a raid never display")
    inside,kind=false,"none"
    s.region(4)
    s:event("ZONE_CHANGED_NEW_AREA")
    s.region(3)
    s:event("ZONE_CHANGED_NEW_AREA")
    check(shown(live) and live.character:GetText()=="Second Person",
        "leaving an instance shows a never-shown alert and does not replay a shown one")
    s:tick(9)
    s:set("target",nil,nil,true)
    s:set("mouseover",nil,nil,true)
    s:tick(5)
    s:set("target","First Person","first",true)
    check(not shown(live),"leaving an instance preserves a cooldown started outside")
    s:tick(20)
    s:set("mouseover","Second Person","second",true)
    check(shown(live) and live.character:GetText()=="Second Person","a new sighting outside can alert normally")
end

do
    local p,s,e=fresh({automaticTarget=false,automaticMouseover=false})
    s:add("First Person","first")
    e.IsInInstance=function() return true,s.secret end
    local before=s.reads()
    s:set("target","First Person","first",true)
    check(not shown(e.WhowhoBlacklistLiveBanner) and s.reads()==before,
        "an unreadable instance type prevents live alerts without reading identity")
    e.IsInInstance=function() return true,"pvp" end
    s:set("target",nil,nil,true)
    s:set("target","First Person","first",true)
    check(shown(e.WhowhoBlacklistLiveBanner),"readable non-dungeon and non-raid contexts can show a new alert")
end

do
    local p,s,e=fresh()
    s:add("First Person","first")
    s:add("Second Person","second")
    local show=p.BlacklistBanner.showLive
    p.BlacklistBanner.showLive=function(name,reasons)
        local displayed=show(name,reasons)
        s:event("PLAYER_LEAVING_WORLD")
        s:set("target","Second Person","second")
        s:event("PLAYER_ENTERING_WORLD")
        p.BlacklistBanner.showLive=show
        return displayed
    end
    s:set("target","First Person","first",true)
    local live=e.WhowhoBlacklistLiveBanner
    check(not shown(live),"a synchronous world transition during Show abandons the old display")
    s:tick(.25)
    check(shown(live) and live.character:GetText()=="Second Person","the next scan owns the new world's alert")
end

do
    local p,s,e=fresh()
    p.Toggle()
    p.Shell.SetSection("settings")
    local pane=p.Shell.settings
    for _,bounds in ipairs({{1360,832},{484,600}}) do
        e.UIParent:SetSize(bounds[1],bounds[2])
        p.Shell.Layout()
        local title=assert(visibleField(pane,function(t) return t=="Alert preview" end))
        local sample=assert(visibleField(title:GetParent(),function(t) return t=="Veyra Ashfall" end)):GetParent()
        local _,_,_,_,sampleY=sample:GetPoint()
        local _,_,titleY=title:GetPoint()
        local _,relative,anchor,_,gap=sample.reasons:GetPoint()
        check(-sampleY>=-titleY+title:GetStringHeight()+4
            and -sampleY+sample:GetHeight()<=title:GetParent():GetHeight()-4
            and relative==sample.character and anchor=="BOTTOM" and gap<=-4,
            "the framed Settings sample clears its own heading and separates the two text blocks")
        local body=sample:GetParent():GetParent()
        local view=body:GetParent()
        local slider,percent=p.Shell.bannerOpacitySlider,p.Shell.bannerOpacityLabel
        local caption=assert(visibleField(body,function(t) return t=="Banner opacity" end))
        local _,captionX,captionY=caption:GetPoint()
        local _,sliderX,sliderY=slider:GetPoint()
        local _,percentX,percentY=percent:GetPoint()
        check(slider:IsVisible() and captionY==percentY and sliderY==captionY-4
            and sliderX>=captionX+caption:GetUnboundedStringWidth()+8 and slider:GetWidth()>=48
            and sliderX+slider:GetWidth()<percentX and percentX+percent:GetWidth()<body:GetWidth(),
            "the opacity caption, track and percentage fit in wide and compact Alerts")
        check(view:GetHeight()+view:GetVerticalScrollRange()>=body:GetHeight(),
            "the entire Alerts preview remains reachable at each width")
        if bounds[1]==484 then
            check(view:GetVerticalScrollRange()>0,"short compact Alerts can scroll to the preview")
            s:fire(view,"OnMouseWheel",-100)
            check(view:GetVerticalScroll()==view:GetVerticalScrollRange(),"scroll reaches the complete banner frame")
        end
    end
end

do
    local p,s,e=fresh({alertSoundEnabled=false})
    p.Toggle()
    local S,B=p.Shell,p.BlacklistBanner
    S.SetSection("settings")
    local slider,percent=S.bannerOpacitySlider,S.bannerOpacityLabel
    local sample=assert(visibleField(S.settings,function(t) return t=="Veyra Ashfall" end)):GetParent()
    B.showLive("Example Person","Griefing")
    local live=e.WhowhoBlacklistLiveBanner
    local first,last=table.unpack(slider.SetMinMaxValuesArgs)
    check(first==50 and last==100 and slider.SetValueStepArgs[1]==1
        and p.db.bannerOpacity==72 and slider:GetValue()==72 and percent:GetText()=="72%",
        "the 50–100 percent slider defaults old saves to 72%")
    local function shadow(frame,opacity,x,y)
        for _,label in ipairs({frame.character,frame.reasons}) do
            if label.shadowColor[4]~=opacity or label.shadowOffset[1]~=x or label.shadowOffset[2]~=y then
                return false
            end
        end
        return true
    end
    check(sample.backing:IsShown() and live.backing:IsShown() and not sample.interior and not live.interior
        and sample.backing.texture==p.media.."LedgerBanner.tga" and shadow(sample,0,0,0),
        "the default uses the original artwork and lettering")
    local function adjusted(frame,alpha)
        return not frame.backing:IsShown() and frame.interior:IsShown() and frame.rim:IsShown()
            and frame.interior.texture==p.media.."LedgerBannerInterior.tga"
            and frame.rim.texture==p.media.."LedgerBannerRim.tga"
            and frame.interior.SetAlphaArgs[1]==alpha and not frame.rim.SetAlphaArgs
            and not frame.character.SetAlphaArgs and not frame.reasons.SetAlphaArgs
            and table.concat(frame.interior.sliceMargins,",")=="16,10,8,8"
            and table.concat(frame.rim.sliceMargins,",")=="16,10,8,8"
    end
    slider:SetValue(50)
    check(adjusted(sample,.5) and adjusted(live,.5) and live.SetAlphaArgs[1]==1
        and shadow(sample,.8,1,-1) and shadow(live,.8,1,-1)
        and e.WhowhoPreviewDB.bannerOpacity==50 and percent:GetText()=="50%",
        "50% updates preview and live interiors and adds a dark shadow without dimming text")
    B.fade(.5)
    slider:SetValue(100)
    check(adjusted(sample,1) and adjusted(live,1) and live.SetAlphaArgs[1]==.5 and shadow(live,0,0,0)
        and percent:GetText()=="100%",
        "100% makes the background fully opaque before fade and preserves a live fade in progress")
    S.testBannerButton:Click()
    local test=e.WhowhoBlacklistTestBanner
    check(adjusted(test,1) and test:IsShown() and test.SetAlphaArgs[1]==1,
        "the movable test opens with the current setting and starts its own hold")
    p.SetInterfaceColor("forestGreen")
    for _,frame in ipairs({sample,live,test}) do
        check(adjusted(frame,1) and frame.interior.desaturated and frame.rim.desaturated
            and frame.interior.vertexColor[2]==p.colors.teal[2] and frame.rim.vertexColor[2]==p.colors.teal[2],
            "changing interface color repaints both visible materials without affecting opacity")
    end
    s:fire(test,"OnUpdate",8.25)
    slider:SetValue(50)
    check(adjusted(test,.5) and test.SetAlphaArgs[1]==.5 and shadow(test,.8,1,-1),
        "drag-preview opacity updates without restarting the test fade")
    s:fire(test,"OnUpdate",.25)
    check(not test:IsShown(),"the test expires on schedule after an opacity change")
    slider:SetValue(72)
    check(sample.backing:IsShown() and not sample.interior:IsShown() and not sample.rim:IsShown()
        and sample.backing.desaturated and shadow(sample,0,0,0),
        "returning to the default restores original artwork with the selected tint and clears the shadow")
    slider:SetValue(85)
    local reloaded=fresh(e.WhowhoPreviewDB)
    reloaded.Toggle()
    local restored=reloaded.Shell
    restored.SetSection("settings")
    local restoredSample=assert(visibleField(restored.settings,function(t) return t=="Veyra Ashfall" end)):GetParent()
    check(reloaded.db.bannerOpacity==85 and reloaded.db.interfaceColor=="forestGreen"
        and restored.bannerOpacitySlider:GetValue()==85 and restored.bannerOpacityLabel:GetText()=="85%"
        and adjusted(restoredSample,.85) and restoredSample.rim.desaturated,
        "reload applies both saved preferences to the control and sample")
    check(fresh({bannerOpacity=math.huge}).db.bannerOpacity==72,"invalid saved opacity falls back to the legacy default")
    check(fresh({bannerOpacity=5}).db.bannerOpacity==50,"saved opacity below the range clamps to 50%")
    check(fresh({bannerOpacity=101}).db.bannerOpacity==100,"saved opacity above the range clamps to 100%")
end

do
    local p,s,e=H.fresh(root,nil,{484,800},{region=3,time=100})
    e.GetLocale=function() return "frFR" end
    s:event("ADDON_LOADED","WhoWho")
    p.Toggle()
    local S=p.Shell
    S.SetSection("settings")
    local caption=assert(visibleField(S.settings,function(t) return t=="Opacité de la bannière" end))
    local _,captionX=caption:GetPoint()
    local _,sliderX=S.bannerOpacitySlider:GetPoint()
    check(sliderX>=captionX+caption:GetUnboundedStringWidth()+8 and S.bannerOpacitySlider:GetWidth()>=48
        and S.bannerOpacityLabel:GetText()=="72%","compact French Alerts keeps a usable localized opacity row")
    local settingsTabs={"Alertes","Amis","Général"}
    checkTabs(p,S.settings,settingsTabs,1)
    S.settingsTabs.general:Click()
    checkTabs(p,S.settings,settingsTabs,3)
    S.SetSection("encounters")
    local encounterTabs={"Dernière heure","Récentes","Antérieures"}
    local final=visibleField(S.encounters,function(text) return text==encounterTabs[3] end):GetParent()
    final:Click()
    checkTabs(p,S.encounters,encounterTabs,3)
    local finalWidth=final:GetWidth()
    e.GetServerTime=function() return nil end
    S.encounters:Refresh()
    encounterTabs[3]="Terminées"
    checkTabs(p,S.encounters,encounterTabs,3)
    check(final:GetWidth()==finalWidth,"changing Antérieures to Terminées keeps the tab strip stable")
    e.UIParent:SetSize(1280,800)
    S.Layout()
    checkTabs(p,S.encounters,encounterTabs,3)
    S.SetSection("settings")
    checkTabs(p,S.settings,settingsTabs,3)
end

do
    local p,s,e,A=fresh({automaticTarget=false,automaticMouseover=false},"PLAYER_TARGET_CHANGED")
    local name=string.rep("Winter",20).." "..string.rep("Silver",20)
    local record=s:add(name,"match",{"griefing","sabotage","ninja_looting","camping","harassment","fraud","spam","other"})
    s:set("target",name,"match",true)
    check(not shown(e.WhowhoBlacklistLiveBanner),"unsupported target binding does not infer a target")
    s:set("mouseover",name,"match",true)
    local live=e.WhowhoBlacklistLiveBanner
    check(shown(live) and live.character:GetText()==name,"supported hover binding works independently")
    e.UIParent:SetSize(220,450)
    s:fire(e.UIParent,"OnSizeChanged")
    check(live:GetWidth()==204 and live:GetHeight()<=434 and live.character:GetStringHeight()>30
        and live.reasons:GetStringHeight()>20,"long names and reasons wrap within a narrow viewport")
    local edge,relative,anchor,_,offset=live.reasons:GetPoint()
    check(edge=="TOP" and relative==live.character and anchor=="BOTTOM" and offset<=-4
        and live.character:GetHeight()>=live.character:GetStringHeight()
        and live.reasons:GetHeight()>=live.reasons:GetStringHeight(),
        "live reasons begin below the full wrapped name at a narrow width")
    assert(A.store.delete(record.id,record.region,record.fullName,record.guid))
    A.refresh()
    s:tick(.25)
    check(not shown(live),"removing an active Blacklist member cancels the live alert")
end

do
    local p,s,e,A=fresh({automaticTarget=false,automaticMouseover=false})
    local first=s:add("First Person","first")
    local second=s:add("Second Person","second")
    local former=s:add("Former Friend","former",nil,"friend")
    assert(A.store.observe(former.id,3,former.fullName,former.guid,"Target",100,"WARLOCK",nil))
    assert(A.store.move(former.id,"blacklist",100,{"other"}))
    A.refresh()
    e.C_ClassColor={GetClassColor=function(class)
        return class=="MAGE" and {r=.2,g=.6,b=.9} or class=="WARLOCK" and {r=.6,g=.4,b=.8} or nil
    end}
    p.Toggle()
    p.Shell.SetSection("blacklist")
    local function row(id)
        for _,candidate in ipairs(p.Shell.rows) do
            if candidate.record and candidate.record.id==id then return candidate end
        end
    end
    check(row(former.id).name.textColor[1]==.6,"Blacklist colors a former Friend from existing saved class evidence")
    local firstRow=row(first.id)
    check(firstRow.name.textColor[1]==1 and not firstRow.classMarker:IsShown(),
        "an unread Blacklist class leaves the name plain without a marker")

    local calls=0
    e.UnitClass=function(token)
        calls=calls+1
        check(token=="mouseover" and s.units[token].guid=="first","optional class read stays on the validated hover")
        return "Mage","MAGE"
    end
    s:set("mouseover","First Person","first",true)
    check(firstRow.name.textColor[1]==.2 and firstRow.name.textColor[3]==.9,
        "an exact readable sighting repaints the Blacklist name in its class color")
    s:tick(.5)
    check(calls==1,"polling a known class does not repeat the optional read")
    s:set("mouseover",nil,nil,true)
    p.Shell.Refresh()
    check(firstRow.name.textColor[1]==.2 and e.WhowhoAddressBookDB.regions[3][first.id].lastKnown.class.value=="MAGE",
        "the verified class is persisted after the unit clears")
    p.Toggle()
    e.UnitClass=function() return "Warlock","WARLOCK" end
    s:set("target","Second Person","second",true)
    check(row(second.id).name.textColor[1]==1,"hidden Blacklist leaves the rendered row alone")
    p.Toggle()
    check(row(second.id).name.textColor[1]==.6,
        "reopening Blacklist paints a verified class learned while the window was hidden")
end

do
    local p,s,e=fresh({automaticTarget=false,automaticMouseover=false})
    local first=s:add("First Person","first")
    local second=s:add("Second Person","second")
    local changed=false
    e.UnitClass=function()
        if not changed then
            changed=true
            s:set("mouseover","Second Person","second",true)
            return "Mage","MAGE"
        end
        return "Warlock","WARLOCK"
    end
    s:set("mouseover","First Person","first",true)
    check(not knownClass(p.manual,first),"a hover replaced during class sampling cannot color the departed player")
    s:tick(.25)
    check(knownClass(p.manual,second)=="WARLOCK","the new exact hover owns its readable class")
    e.UnitClass=function() return "Mage",s.secret end
    s:set("mouseover","First Person","first",true)
    check(not knownClass(p.manual,first),"an unreadable class never colors the name")
end

do
    local p,s,e,A=fresh({automaticTarget=false,automaticMouseover=false})

    local first=s:add("First Person","first")
    local second=s:add("Second Person","second")
    e.UnitClass=function(token)
        if token=="target" then return "Mage","MAGE" end
        return "Warlock","WARLOCK"
    end
    s:set("target",first.fullName,first.guid,true)
    s:set("mouseover",second.fullName,second.guid,true)
    check(knownClass(A,first)=="MAGE" and knownClass(A,second)=="WARLOCK",
        "both saved IDs have independent class evidence")
    s:set("target",nil,nil,true)

    local stale={id=first.id,region=first.region,fullName=first.fullName,guid="stale",membership="blacklist"}
    check(not A.delete(stale) and knownClass(A,first)=="MAGE",
        "a rejected deletion keeps class evidence for the live record")
    local friend=assert(A.move(first))
    check(friend.id==first.id and friend.class=="MAGE",
        "moving a Blacklist entry to Friends preserves its verified class")

    check(A.delete(friend) and not e.WhowhoAddressBookDB.archived[first.id].lastKnown and knownClass(A,second)=="WARLOCK",
        "successful deletion excludes metadata from the archived ID and keeps other evidence")
    local replacement=assert(A.save(nil,"blacklist",first.fullName,"",nil,{"other"}))
    check(replacement.id~=first.id and not knownClass(A,replacement),
        "adding the same name again starts with no class evidence")
    local deletedDuringRead
    e.UnitClass=function()
        deletedDuringRead=A.delete(replacement)
        return "Mage","MAGE"
    end
    s:set("target",replacement.fullName,"replacement",true)
    check(deletedDuringRead and not A.store.get(replacement.id) and not knownClass(A,replacement),
        "an in-flight class read cannot restore metadata after deletion")
end

do
    local p,s,e,A=fresh({automaticTarget=false,automaticMouseover=false})
    local saved=assert(A.save(nil,"blacklist","Saved Person","",nil,{"other"}))
    s:set("target","Other Person","other",true)
    local sample=upvalue(s.observer:GetScript("OnEvent"),"sample")
    local owner=upvalue(sample,"sampledOwner")
    local original=A.store
    check(owner.store==original and upvalue(sample,"sampled").target==false
        and not s.observer:GetScript("OnUpdate"),
        "the idle observer memoizes a confirmed non-match for the current book")
    assert(A.delete(saved))
    check(A.store~=original and #A.records==0 and not s.observer:GetScript("OnUpdate")
        and not upvalue(sample,"sampled").store and getmetatable(owner).__mode=="v",
        "deleting the last entry leaves the idle observer with only weak book ownership")
end

do
    local p,s,e,A=fresh({automaticTarget=false,automaticMouseover=false})
    -- Inspect the cache directly because a sighting would prune it before checking eligibility.
    local cooldowns=upvalue(upvalue(p.BlacklistBanner.deferNewBlacklist,"startCooldown"),"cooldowns")
    for i=1,40 do
        local name="Churn "..string.char(65+math.floor(i/26),65+i%26)
        local saved=assert(A.save(nil,"blacklist",name,"",nil,{"other"}))
        assert(A.delete(saved))
        local names=cooldowns[3]
        local first=next(names)
        check(first==name and next(names,first)==nil,
            "manual save and delete churn keeps only the unexpired deadline")
        s.advance(300)
    end
    check(#A.records==0 and not s.observer:GetScript("OnUpdate"),
        "manual cooldown pruning needs no sightings or idle observer updates")

    local saved=assert(A.save(nil,"blacklist","Repeat Person","",nil,{"other"}))
    assert(A.delete(saved))
    s.advance(1)
    assert(A.save(nil,"blacklist","Other Person","",nil,{"other"}))
    s:add(saved.fullName,"repeat")
    s:set("target",saved.fullName,"repeat",true)
    check(not shown(e.WhowhoBlacklistLiveBanner),
        "a readable save preserves an unexpired deadline across delete and re-add by exact name")
end

do
    local p,s,e,A=fresh({automaticTarget=false,automaticMouseover=false})
    s:add("Other Person","other")
    s:set("target","New Person","new",true)
    local apply=A.targetCheck.apply
    local reportedDuringSave=false
    A.targetCheck.apply=function(record,...)
        if record.fullName=="New Person" and not reportedDuringSave then
            reportedDuringSave=true
            s:event("PLAYER_TARGET_CHANGED")
        end
        return apply(record,...)
    end
    local saved=assert(A.save(nil,"blacklist","New Person","",nil,{"other"}))
    check(reportedDuringSave and not shown(e.WhowhoBlacklistLiveBanner),
        "the new-entry cooldown is armed before a publication callback can display a banner")
    s:set("target","Other Person","other",true)
    local live=e.WhowhoBlacklistLiveBanner
    check(shown(live) and live.character:GetText()=="Other Person","new-entry cooldown is per character")
    s:set("target",nil,nil,true)
    s:tick(100)
    saved=assert(A.save(saved,"blacklist",saved.fullName,"edited note",nil,{"other"}))
    s:tick(199.75)
    s:set("target","New Person","new",true)
    check(not shown(live),"the new entry stays quiet just before five minutes")
    s:tick(.25)
    check(not shown(live),"deadline expiry does not reopen an active suppressed encounter")
    s:set("target",nil,nil,true)
    s:tick(5)
    s:set("target","New Person","new",true)
    check(shown(live) and live.character:GetText()=="New Person","editing does not restart the new-entry cooldown")
end

do
    local p,s,e,A=fresh({automaticTarget=false,automaticMouseover=false})
    local friend=s:add("Former Friend","former",nil,"friend")
    assert(A.save(friend,"blacklist",friend.fullName,"",nil,{"other"},true))
    s.advance(300)
    s:set("target",friend.fullName,friend.guid,true)
    check(shown(e.WhowhoBlacklistLiveBanner),"a fresh encounter is eligible at the exact new-entry deadline")
end

do
    local p,s,e,A=fresh({automaticTarget=false,automaticMouseover=false})
    local friend=s:add("Former Friend","former",nil,"friend")
    s:set("mouseover",friend.fullName,friend.guid,true)
    assert(A.save(friend,"blacklist",friend.fullName,"",nil,{"other"},true))
    s:event("UPDATE_MOUSEOVER_UNIT")
    check(not shown(e.WhowhoBlacklistLiveBanner),"moving a Friend into Blacklist starts the same five-minute cooldown")
end

do
    local p,s,e,A=fresh({automaticTarget=false,automaticMouseover=false})
    local store=A.store
    e.GetTime=function()
        A.store={}
        return 100
    end
    local saved,issue=A.save(nil,"blacklist","Changed Person","",nil,{"other"})
    check(not saved and issue and A.store~=store and not e.WhowhoAddressBookDB,
        "a store replacement during cooldown arming cannot publish a stale candidate")
    A.store=store
    e.GetTime=function() return 100 end
    s:add("Changed Person","changed")
    s:set("target","Changed Person","changed",true)
    check(shown(e.WhowhoBlacklistLiveBanner),"a rejected save leaves no cooldown behind")
end

do
    local p,s,e,A=fresh({automaticTarget=false,automaticMouseover=false})
    s:add("Other Person","other")
    s:set("target","Other Person","other",true)
    s:set("target",nil,nil,true)
    s:tick(8.5)
    s.advance(600)
    local getTime=e.GetTime
    e.GetTime=function() return nil end
    assert(A.save(nil,"blacklist","New Person","",nil,{"other"}))
    e.GetTime=getTime
    local other=assert(A.save(nil,"blacklist","Quiet Person","",nil,{"other"}))
    assert(A.delete(other))
    s.advance(301)
    s:set("target","New Person","new",true)
    local live=e.WhowhoBlacklistLiveBanner
    check(not shown(live),"a readable save before a sighting leaves the earlier untimed deadline deferred")
    s:set("target",nil,nil,true)
    s:tick(300)
    s:set("target","New Person","new",true)
    check(shown(live),"the deferred deadline starts when the native clock becomes readable")
end

do
    local p,s,e=fresh()
    local faction, reads="Alliance",0
    e.UnitFactionGroup=function(token)
        check(token=="player","the Test sample checks only the current player's faction")
        reads=reads+1
        return faction
    end
    for _,example in ipairs({{"Alliance","Warchief Thrall"},{"Horde","Anduin Wrynn"},
        {s.secret,"Veyra Ashfall"}}) do
        faction=example[1]
        p.BlacklistBanner.toggleTest()
        local test=e.WhowhoBlacklistTestBanner
        check(test.character:GetText()==example[2] and test.reasons:GetText()=="Griefing · Ninja looting",
            "Test sample uses the faction variant or the fallback without changing the reasons")
        p.BlacklistBanner.toggleTest()
    end
    check(reads==3,"closing Test does not resample faction")
end

do
    local p,s,e,A=fresh()
    local first=s:add("First Person","first")
    local zone,zoneReads=s.secret,0
    e.GetRealZoneText=function() zoneReads=zoneReads+1; return zone end
    s:set("target","First Person","wrong",true)
    local ledger=A.encounterLedger
    check(#ledger.snapshot(3,100).Now==0 and zoneReads==0,"an incompatible GUID cannot create or sample an encounter")
    s:set("target","First Person","first",true)
    local a=ledger.snapshot(3,100).Now[1]
    check(a and a.playerId==first.id and a.startedAt==100 and a.target and not a.endedAt and not a.zone,
        "the exact observed player owns one active encounter")
    check(not e.WhowhoEncounterDB.regions[3],"active encounter data stays outside SavedVariables")
    s:tick(2)
    zone="Cité Écarlate"
    s:set("mouseover","First Person","first",true)
    check(a.lastObservedAt==102 and a.zone=="Cité Écarlate","a readable localized zone belongs to the qualified sighting")
    zone="Orgrimmar"
    s:set("target",nil,nil,true)
    s:tick(6.5)
    check(not shown(e.WhowhoBlacklistLiveBanner) and not a.endedAt and a.target and a.mouseover,
        "one row merges both sources and stays active after its banner fades")
    s:set("mouseover",nil,nil,true)
    s:tick(4)
    s:set("target","First Person","first",true)
    check(#ledger.snapshot(3,112).Now==1 and not a.endedAt,"a verified return within the grace keeps the original ID")
    s:tick(2.5)
    s:set("target",nil,nil,true)
    s:tick(4.75)
    check(not a.endedAt,"absence grace is still active before five seconds")
    s:tick(.25)
    check(a.lastObservedAt==112 and a.endedAt==115 and e.WhowhoEncounterDB.regions[3][1]==a,
        "history uses the actual clear timestamp, excluding the grace")
    check(a.zone=="Orgrimmar","history keeps the zone from the latest verified observation")
    check(#ledger.snapshot(3,3714).Now==1 and #ledger.snapshot(3,3715).Recent==1
        and #ledger.snapshot(3,86514).Recent==1 and #ledger.snapshot(3,86515).Earlier==1,
        "rolling hour and day boundaries use encounter ends")
    check(#ledger.snapshot(4,120).Now==0,"history is scoped to the validated region")

    s:set("target","First Person","first",true)
    local b=ledger.snapshot(3,120).Now[1]
    check(b.id>a.id and not b.endedAt and not shown(e.WhowhoBlacklistLiveBanner),
        "an encounter starting during cooldown has a distinct ID and no alert")
    s:tick(2)
    s:event("PLAYER_LOGOUT")
    check(b.endedAt==122 and #e.WhowhoEncounterDB.regions[3]==1,
        "logout persists a short repeat into its existing counted encounter")
    s:event("PLAYER_LEAVING_WORLD")
    check(#e.WhowhoEncounterDB.regions[3]==1,"world exit after logout cannot duplicate history")
    local _,_,restored,restoredA=fresh(nil,nil,e.WhowhoEncounterDB)
    local history=restoredA.encounterLedger.snapshot(3,122).Now
    check(#history==1 and history[1].id==a.id and history[1].startedAt==100 and history[1].endedAt==122
        and history[1].lastObservedAt==b.lastObservedAt and history[1].zone=="Orgrimmar"
        and restored.WhowhoEncounterDB.nextId>b.id,"reload restores the counted start and latest verified place")
end

do
    local _,_,e,A=fresh()
    local player={id=1,name="First Person",guid="first"}
    local function record(ledger,at,place,lastObserved,elapsed)
        local id=assert(ledger.start(player,3,at))
        ledger.observe(id,true,false,lastObserved or 0,place)
        ledger.stop(id,elapsed or 0)
        return id
    end
    local first=record(A.encounterLedger,100,"Durotar")
    record(A.encounterLedger,300,"Durotar",10,20)
    local _,_,restored,restoredA=fresh(nil,nil,e.WhowhoEncounterDB)
    local ledger=restoredA.encounterLedger
    local shorter=record(ledger,699,"Orgrimmar")
    local groups,_,byId=ledger.groups(3,699)
    local rows=restored.WhowhoEncounterDB.regions[3]
    check(#rows==1 and rows[1].startedAt==100 and rows[1].lastObservedAt==699 and rows[1].zone=="Orgrimmar",
        "a repeat after reload inherits the last counted start and advances its verified Last seen time and place")
    check(#groups==1 and groups[1].count==1 and byId[shorter]==byId[first],
        "the short-repeat ID and canonical ID resolve to exactly the same display row")
    local boundary=record(ledger,700,"Orgrimmar")
    groups,_,byId=ledger.groups(3,700)
    check(#rows==2 and #groups==1 and groups[1].count==2 and byId[first]==byId[boundary],
        "an episode exactly ten minutes from the counted start is counted and grouped in the same zone")
    local otherZone=record(ledger,1300,"Durotar")
    local other=assert(ledger.start({id=2,name=player.name,guid="other"},3,1301))
    ledger.observe(other,true,false,0,"Orgrimmar")
    local renamed=assert(ledger.start({id=1,name="Different Person",guid=player.guid},3,1302))
    ledger.observe(renamed,true,false,0,"Orgrimmar")
    groups,_,byId=ledger.groups(3,1302)
    check(#groups==3 and byId[other]~=byId[first] and byId[renamed]~=byId[first] and byId[otherZone]==byId[first],
        "only matching verified identities group across zones")
    check(#ledger.groups(4,1302)==0,"grouped rows and aliases are confined to the active region")
    groups,_,byId=ledger.groups(3,4300)
    check(byId[first].section=="Now" and byId[first].row.lastObservedAt==1300 and byId[first].count==3
        and byId[first].recent[1].zone=="Durotar" and byId[first].recent[2].zone=="Orgrimmar",
        "the latest counted encounter supplies tab and zone while earlier encounters retain their places")
end

do
    local saved={id=1,playerId=1,region=3,name="First Person",guid="first",zone="Durotar",
        startedAt=100,lastObservedAt=120,endedAt=125,target=true}
    local p,_,e,A=fresh(nil,nil,{version=1,nextId=2,regions={[3]={saved}}})
    local player={id=1,name=saved.name,guid=saved.guid}
    local ledger=A.encounterLedger
    e.GetServerTime=function() return 110 end
    p.Toggle()
    p.Shell.SetSection("encounters")
    local pane=p.Shell.encounters
    local stale=assert(ledger.start(player,3,110))
    ledger.observe(stale,false,true,0,"Orgrimmar")
    local groups,_,byId=ledger.groups(3,110)
    check(#groups==1 and groups[1].row==saved and not byId[stale] and not pane:Refresh(stale),
        "a stale active episode cannot select the retained row from another place")
    ledger.stop(stale,20)
    groups,_,byId=ledger.groups(3,110)
    check(#groups==1 and groups[1].count==1 and not byId[stale] and not pane:Refresh(stale)
        and saved.zone=="Durotar" and saved.lastObservedAt==120 and saved.endedAt==125 and not saved.mouseover,
        "stale observation data stays out of storage and never aliases to the retained row")

    local catchesUp=assert(ledger.start(player,3,110))
    ledger.observe(catchesUp,true,false,10,"Orgrimmar")
    groups,_,byId=ledger.groups(3,120)
    check(#groups==1 and groups[1].count==1 and byId[catchesUp].row.zone=="Orgrimmar" and pane:Refresh(catchesUp),
        "equally recent verified evidence can select its actual place")
    ledger.stop(catchesUp,10)
    check(pane:Refresh(catchesUp) and saved.zone=="Orgrimmar","an accepted repeat resolves after stopping")
    local moved=assert(ledger.start(player,3,126))
    ledger.observe(moved,true,false,0,"Silvermoon City")
    ledger.stop(moved,0)
    groups,_,byId=ledger.groups(3,126)
    check(#groups==1 and groups[1].count==1 and byId[moved].row.zone=="Silvermoon City"
        and not byId[catchesUp] and not pane:Refresh(catchesUp),
        "a later place change cannot redirect the earlier episode's alias")
end

do
    local function historic(id,region,name,guid,zone,at)
        return {id=id,playerId=1,region=region,name=name,guid=guid,zone=zone,
            startedAt=at,lastObservedAt=at,endedAt=at,target=true}
    end
    local a=historic(1,3,"First Person","first","Durotar",100)
    local b=historic(2,3,"First Person","first","Durotar",120)
    local c=historic(3,3,"First Person","first",nil,140)
    local d=historic(4,4,"First Person","first","Durotar",115)
    local p,_,e,A=fresh(nil,nil,{version=1,nextId=5,regions={[3]={a,b,c},[4]={d}}})
    local ledger=A.encounterLedger
    local entries,_,byId=ledger.groups(3,140)
    check(#e.WhowhoEncounterDB.regions[3]==3 and #entries==1 and byId[1]==byId[2] and byId[1].count==3
        and byId[1].row==c and byId[3]==byId[1],"legacy records project into one character row without a migration")
    check(#ledger.groups(4,140)==1,"legacy history with the same identity and place in another region stays independent")
    p.Toggle()
    p.Shell.SetSection("encounters")
    check(p.Shell.encounters:Refresh(1),"an older historical ID can select its newer grouped representative")
    local selected
    for _,child in ipairs(p.Shell.encounters.children) do if child.entry and child.selected then selected=child end end
    check(selected and selected.count:GetText()=="3 encounters","a repeated group shows its count in the selected row")
end

do
    local p,s,e,A=fresh()
    local now=100000
    e.GetServerTime=function() return now end
    local ledger=A.encounterLedger
    local player=s:add("First Person","first")
    local function record(id,at,active)
        local episode=assert(ledger.start({id=id,name=player.fullName,guid=id==player.id and player.guid or "test"..id},3,at))
        ledger.observe(episode,true,false,0,"Durotar")
        if not active then ledger.stop(episode,0) end
        return episode
    end
    local hourId=record(player.id,now-3599)
    local recentId=record(2,now-86399)
    local earlyId=record(3,now-86400)
    record(4,now-3600)
    local activeId=record(5,now-86401,true)
    p.Toggle()
    p.Shell.SetSection("encounters")
    local pane=p.Shell.encounters
    local function button(text)
        for _,child in ipairs(pane.children) do
            if child.kind=="Button" and child.label:GetText()==text then return child end
        end
    end
    local function rows()
        local visible={}
        for _,child in ipairs(pane.children) do
            if child.entry and child:IsVisible() then visible[#visible+1]=child end
        end
        return visible
    end
    local function visibleId(id)
        for _,row in ipairs(rows()) do if row.entry.row.id==id then return row end end
    end
    local hour,recent,earlier=button("Last hour"),button("Recent"),button("Earlier")
    local action,prev,nextPage=button("View Blacklist entry"),button("Previous"),button("Next")
    local function checkFits(expectedRows,footer)
        local visible=rows()
        local last=visible[#visible]
        local _,_,y=last:GetPoint()
        local _,_,footerInset=footer:GetPoint()
        check(#visible==expectedRows and pane:GetHeight()-footerInset-footer:GetHeight()+y-last:GetHeight()>=8,
            "the requested number of full rows fits above the reserved footer")
    end
    check(hour.selected and visibleId(activeId) and visibleId(hourId) and #rows()==2,
        "the initial newest tab shows active and under-one-hour groups")
    checkTabs(p,pane,{"Last hour","Recent","Earlier"},1)
    recent:Click()
    check(recent.selected and #rows()==2 and visibleId(recentId),"exactly one hour is Recent")
    earlier:Click()
    check(earlier.selected and #rows()==1 and visibleId(earlyId),"exactly twenty-four hours is Earlier")
    for _,example in ipairs({
        {hour,"The player is currently targeted or under your cursor, or the encounter ended less than 1 hour ago."},
        {recent,"The encounter ended at least 1 hour ago and less than 24 hours ago."},
        {earlier,"The encounter ended at least 24 hours ago."},
    }) do
        local tab=example[1]
        check(s:routePointer({tab},"OnEnter")==tab and e.GameTooltip:GetOwner()==tab
            and e.GameTooltip:GetText()==example[2],"hover explains the English tab range")
        s:fire(tab,"OnLeave")
        check(not e.GameTooltip:IsShown(),"leaving a tab clears its tooltip")
    end

    assert(pane:Refresh(hourId))
    local selected=assert(visibleId(hourId))
    check(selected.selected and action:IsVisible() and action:IsEnabled(),"an exact saved group enables its detail action")
    s:fire(action,"OnMouseDown","LeftButton")
    now=now+1
    pane:Refresh()
    check(recent.selected and visibleId(hourId).selected and not visibleId(recentId),"a visible exact selection follows the hour boundary")
    action:Click()
    check(p.Shell.section=="encounters","an action pressed in the previous time tab expires when the selection moves")
    assert(pane:Refresh(recentId))
    check(earlier.selected and visibleId(recentId).selected,"the previous Recent group crosses into Earlier at 24 hours")

    s:routePointer({earlier},"OnEnter")
    e.GetServerTime=function() return nil end
    pane:Refresh()
    check(earlier.selected and earlier.label:GetText()=="Ended" and visibleId(recentId).selected
        and not e.GameTooltip:IsShown(),"the third tab retains the selected completed group and clears old help when the clock is lost")
    checkTabs(p,pane,{"Last hour","Recent","Ended"},3)
    s:routePointer({earlier},"OnEnter")
    check(e.GameTooltip:GetText()=="The current time is unavailable. This tab shows completed encounters of unknown age.",
        "the Ended tab explains unavailable ages")
    recent:Click()
    check(recent.selected and #rows()==0 and not action:IsVisible(),"manual selection keeps an empty tab and clears previous details")
    pane:Refresh()
    check(recent.selected,"an unchanged refresh preserves an empty manual tab")
    hour:Click()
    check(#rows()==1 and visibleId(activeId),"active groups stay accessible without a clock")
    e.GetServerTime=function() return now end
    pane:Refresh()
    check(hour.selected and earlier.label:GetText()=="Earlier","clock recovery restores Earlier and keeps the manual tab")

    local oldest=record(60,now-8000)
    for i=61,70 do record(i,now-3600-i) end
    local _,_,byId=ledger.groups(3,now)
    p.Shell.SetSection("friend")
    p.Shell.OpenEncounter({id=oldest,key=byId[hourId].episodeKeys[hourId]},function() return true end)
    check(p.Shell.section=="friend","a mismatched place/identity cannot route a hidden pane")
    p.Shell.OpenEncounter({id=oldest,key=byId[oldest].episodeKeys[oldest]},function() return false end)
    check(p.Shell.section=="friend","a lost banner owner cannot route a hidden pane")
    p.Shell.OpenEncounter({id=oldest,key=byId[oldest].episodeKeys[oldest]},function() return true end)
    check(recent.selected and visibleId(oldest).selected and prev:IsEnabled(),
        "exact navigation opens a hidden pane on the requested tab and later page")
    s:routePointer({recent,pane},"OnMouseWheel",1)
    check(recent.selected and not visibleId(oldest) and not action:IsVisible(),
        "wheel paging stays in the same tab and clears the off-page selection")
    while prev:IsEnabled() do prev:Click() end
    check(recent.selected and not prev:IsEnabled(),"Previous stops at the tab's first page")
    checkFits(3,nextPage)

    local first=rows()[1]
    first.time.IsTruncated=function() return true end
    s:fire(first,"OnEnter")
    s:fire(first,"OnMouseDown","LeftButton")
    assert(e.GameTooltip:GetOwner()==first)
    nextPage:Click()
    first:Click()
    check(not first.selected and not e.GameTooltip:IsShown() and rows()[1]==first,
        "paging reuses a row and cancels its old press and owned tooltip")
    local anchor=rows()[1].entry.row.id
    record(71,now-3600)
    pane:Refresh()
    check(visibleId(anchor),"passive insertion keeps the previous first visible group in view")
    hour:Click()
    recent:Click()
    check(visibleId(anchor) and rows()[1].entry.key~=nil,"switching tabs retains the page cursor for each tab")

    first=rows()[1]
    anchor=first.entry.row.id
    s:fire(first,"OnMouseDown","LeftButton")
    p.ShowTooltip(e.UIParent,"Other tooltip")
    pane:SetSize(380,500)
    pane:Arrange(380)
    first:Click()
    check(not first.selected and e.GameTooltip:GetOwner()==e.UIParent and e.GameTooltip:IsShown()
        and visibleId(anchor),"resizing cancels an old press, preserves another tooltip and keeps the leading group visible")
    -- The compact and wide layouts both reserve footer space even when no row is selected.
    prev:Click()
    prev:Click()
    checkFits(2,nextPage)
    pane:SetSize(380,730)
    pane:Arrange(380)
    checkFits(5,nextPage)
    pane:SetSize(1040,608)
    pane:Arrange(1040)
    checkFits(8,nextPage)
    first=rows()[1]
    s:fire(first,"OnEnter")
    s:fire(first,"OnMouseDown","LeftButton")
    pane:Hide()
    pane:Show()
    first:Click()
    check(not first.selected and not e.GameTooltip:IsShown(),"hiding Encounters clears pending row input")

    s.region(4); A.region=4
    pane:Refresh()
    check(hour.selected and #rows()==0 and not prev:IsVisible() and not action:IsVisible(),
        "an empty new region starts in Last hour with cleared paging and selection")
    s.region(3); A.region=3
    pane:Refresh()
    check(hour.selected and visibleId(activeId),"returning to a region chooses its newest populated tab")
end

do
    local p,s,e,A=fresh()
    local now=100000
    e.GetServerTime=function() return now end
    local saved=s:add("First Person","first")
    local former=s:add("Former Friend","former",nil,"friend")
    assert(A.store.observe(former.id,3,former.fullName,former.guid,"Target",now,"WARLOCK",nil))
    assert(A.store.move(former.id,"blacklist",now,{"other"}))
    A.refresh()
    assert(A.store.observeBlacklist(saved.id,{region=3,name=saved.fullName,guid=saved.guid,class="MAGE",faction="Horde",
        source="Target",at=100}))
    A.refresh()
    local ledger=A.encounterLedger
    local function record(player,guid,at)
        local id=assert(ledger.start({id=player.id,name=player.fullName,guid=guid},3,at))
        ledger.observe(id,true,false,0,"Durotar")
        ledger.stop(id,0)
        return id
    end
    local unknown=record(saved,"wrong-guid",now-86400)
    local oldClass=record(former,former.guid,now-10)
    local exact=record(saved,saved.guid,now-5)
    e.UnitClass=function() error("rendering encounters must not scan units") end
    local colors={MAGE={r=.2,g=.6,b=.9},WARLOCK={r=.6,g=.4,b=.8}}
    e.C_ClassColor={GetClassColor=function(class) return colors[class] end}
    p.Toggle()
    p.Shell.SetSection("encounters")
    local pane=p.Shell.encounters
    local function row(id)
        for _,child in ipairs(pane.children) do
            if child.entry and child:IsVisible() and child.entry.row.id==id then return child end
        end
    end
    local hour,earlier
    for _,child in ipairs(pane.children) do
        if child.kind=="Button" and child.label:GetText()=="Last hour" then hour=child end
        if child.kind=="Button" and child.label:GetText()=="Earlier" then earlier=child end
    end
    local neutral=p.colors.text[1]
    local slot=row(exact)
    local function selectedName()
        local caption=assert(visibleField(pane,function(text) return text=="Last 3 Encounters" end))
        return assert(visibleField(caption:GetParent(),function(text) return text==saved.fullName end))
    end
    check(slot.name.textColor[1]==.2 and row(oldClass).name.textColor[1]==.6,
        "Encounters uses exact durable class evidence from Blacklist sightings and former Friends")
    local colorReads=0
    e.C_ClassColor.GetClassColor=function(class) colorReads=colorReads+1; return colors[class] end
    assert(pane:Refresh(exact))
    check(selectedName().textColor[1]==.2 and colorReads==2,
        "the selected Encounter title uses its row's validated color without another native color read")
    earlier:Click()
    check(row(unknown)==slot and slot.name.textColor[1]==neutral and slot.time:GetText():match("^Unknown · "),
        "a reused row with the same name but a conflicting GUID cannot inherit class or faction")
    hour:Click()
    assert(pane:Refresh(exact))
    colors.MAGE=setmetatable(s.secret,{__index=function() error("protected color accessed") end})
    pane:Refresh()
    check(slot.name.textColor[1]==neutral and selectedName().textColor[1]==neutral,
        "restricted native class colors restore readable name ink in the row and selected title")
    colors.MAGE={r=.2,g=.6,b=.9}
    pane:Refresh()
    check(slot.name.textColor[1]==.2 and selectedName().textColor[1]==.2,
        "readable verified color can return on refresh without changing selection")
    assert(A.store.observeBlacklist(saved.id,{region=3,name=saved.fullName,guid=saved.guid,class="WARLOCK",
        source="Target",at=101}))
    A.refresh()
    pane:Refresh()
    check(slot.name.textColor[1]==.6 and selectedName().textColor[1]==.6,
        "replacing saved class evidence repaints the selected title without changing its layout")
    assert(A.store.observeBlacklist(saved.id,{region=3,name=saved.fullName,guid=saved.guid,class="MAGE",
        source="Target",at=102}))
    A.refresh()
    e.C_ClassColor.GetClassColor=function(class)
        if class=="MAGE" then earlier:Click(); assert(pane:Refresh(unknown)) end
        return colors[class]
    end
    pane:Refresh()
    check(earlier.selected and row(unknown)==slot and slot.name.textColor[1]==neutral
        and selectedName().textColor[1]==neutral and slot.time:GetText():match("^Unknown · "),
        "a native color returned after tab navigation cannot repaint a rebound row or title")
    e.C_ClassColor.GetClassColor=function(class) return colors[class] end
    hour:Click()
    assert(pane:Refresh(exact))
    local removed
    e.C_ClassColor.GetClassColor=function(class)
        if class=="MAGE" then removed=A.store.delete(saved.id,3,saved.fullName,saved.guid) end
        return colors[class]
    end
    pane:Refresh()
    check(removed and row(exact)==slot and slot.name.textColor[1]==neutral and selectedName().textColor[1]==neutral,
        "losing the saved record during a native color read clears both the retained row and title")
    e.C_ClassColor.GetClassColor=function(class) return colors[class] end
    local replacement=s:add(saved.fullName,"replacement")
    assert(A.store.observeBlacklist(replacement.id,{region=3,name=replacement.fullName,guid=replacement.guid,class="MAGE",
        source="Target",at=100}))
    A.refresh()
    pane:Refresh()
    check(row(exact)==slot and slot.name.textColor[1]==neutral and selectedName().textColor[1]==neutral,
        "a newly saved matching name with a different ID and GUID cannot color retained history")
end

do
    local recent={id=1,playerId=1,region=3,name="First Person",guid="first",zone="Durotar",
        startedAt=100,lastObservedAt=100,endedAt=100,target=true}
    local p,s,e=fresh(nil,nil,{version=1,nextId=2,regions={[3]={recent}}})
    e.GetServerTime=function() return 3700 end
    p.Toggle()
    p.Shell.SetSection("encounters")
    local pane=p.Shell.encounters
    local chosen
    for _,child in ipairs(pane.children) do
        if child.kind=="Button" and child.selected and child.label:IsShown() then chosen=child.label:GetText() end
    end
    check(chosen=="Recent","the initial tab skips a newer window with no rows")
end

for _,unavailable in ipairs({false,function() error("input setter unavailable") end}) do
    local p,s,e=fresh()
    local create=e.CreateFrame
    e.CreateFrame=function(kind,...)
        local frame=create(kind,...)
        if kind=="Button" then frame.SetMouseMotionEnabled=unavailable end
        return frame
    end
    p.Toggle()
    p.Shell.SetSection("encounters")
    local pane=p.Shell.encounters
    local hour,recent
    for _,child in ipairs(pane.children) do
        if child.kind=="Button" and child.label:GetText()=="Last hour" then hour=child end
        if child.kind=="Button" and child.label:GetText()=="Recent" then recent=child end
    end
    check(hour and recent and hour:IsVisible() and hour.selected,"tabs and defaults work without mouse-motion help")
    s:routePointer({recent},"OnEnter")
    recent:Click()
    check(recent.selected and not e.GameTooltip:IsShown(),"a missing or denied motion setter keeps tab clicks available")
end

for _,initialClockAvailable in ipairs({true,false}) do
    local p,s,e,A=fresh()
    local first=s:add("First Person","first")
    local second=s:add("Second Person","second")
    e.GetRealZoneText=function() return "Durotar" end
    e.IsControlKeyDown=function() return true end
    s:set("target",first.fullName,first.guid,true)
    s.advance(1)
    local wallClock=e.GetServerTime
    if not initialClockAvailable then e.GetServerTime=function() return nil end end
    s:set("target",second.fullName,second.guid,true)
    e.GetServerTime=wallClock
    if not initialClockAvailable then s:event("PLAYER_TARGET_CHANGED") end
    local active=A.encounterLedger.snapshot(3,101).Now
    local episode=assert(active[1])
    assert(episode.playerId==second.id and not episode.endedAt)
    s:set("target",nil,nil,true)
    s:tick(5)
    check(episode.endedAt==101,"the queued target is persisted before the first banner fades")
    s:tick(2.5)
    local live=e.WhowhoBlacklistLiveBanner
    check(shown(live) and live.character:GetText()==second.fullName,"the ended sighting still displays within the queue lifetime")
    local function clickBanner()
        s:routePointer({live},"OnMouseDown","LeftButton")
        s:routePointer({live},"OnMouseUp","LeftButton")
    end
    s.region(e.secret)
    clickBanner()
    check(not p.Shell.window,"an unavailable region blocks encounter navigation")
    s.region(3)
    e.GetServerTime=function() return nil end
    clickBanner()
    local selected
    for _,row in ipairs(p.Shell.encounters.children) do
        if row.entry and row.selected and row:IsShown() then selected=row.entry end
    end
    check(selected and selected.row==episode and selected.section=="Ended",
        "a queued alert opens its exact ended row even with the current wall clock unavailable")
end

do
    local p,s,e=fresh()
    local first=s:add("First Person","first")
    local second=s:add("Second Person","second")
    e.IsControlKeyDown=function() return true end
    s:set("target",first.fullName,first.guid,true)
    local wallClock=e.GetServerTime
    e.GetServerTime=function() return nil end
    s.advance(1)
    s:set("target",second.fullName,second.guid,true)
    s:set("target",nil,nil,true)
    s:tick(5)
    e.GetServerTime=wallClock
    s:set("target",second.fullName,second.guid,true)
    s:tick(2.5)
    local live=e.WhowhoBlacklistLiveBanner
    check(shown(live) and live.character:GetText()==second.fullName
        and not s:routePointer({live},"OnMouseDown","LeftButton"),
        "an unrecorded queued warning still displays without borrowing a later episode's navigation")
end

for _,isRepeat in ipairs({false,true}) do
    local p,s,e,A=fresh()
    local player=s:add("First Person","first")
    local zone="Durotar"
    e.GetRealZoneText=function() return zone end
    e.IsControlKeyDown=function() return true end
    s:set("target",player.fullName,player.guid,true)
    if isRepeat then
        s:set("target",nil,nil,true)
        s:tick(33)
        zone="Orgrimmar"
        s:set("target",player.fullName,player.guid,true)
    end
    local live=e.WhowhoBlacklistLiveBanner
    local episode=assert(A.encounterLedger.snapshot(3,100).Now[1])
    s:set("target",nil,nil,true)
    s:tick(5.5)
    check(shown(live) and s:routePointer({live},"OnMouseDown","LeftButton")==live,
        "a displayed warning remains clickable after its exact episode ends in the same place")
    zone="The Barrens"
    s:event("ZONE_CHANGED_NEW_AREA")
    s:set("target",player.fullName,player.guid,true)
    local _,_,byId=A.encounterLedger.groups(3,e.GetServerTime())
    check((isRepeat and not byId[episode.id]) or (not isRepeat and byId[episode.id].row.zone==zone),
        "the short repeat either loses the old alias or remaps the counted ID to the new place")
    s:fire(live,"OnMouseUp","LeftButton")
    check(shown(live) and not p.Shell.window and not s:routePointer({live},"OnMouseDown","LeftButton"),
        "the old warning remains visible while its invalidated click passes through")
    s:set("target",nil,nil,true)
    s:tick(5)
    s:set("target",player.fullName,player.guid,true)
    check(not shown(live),"the warning fades normally and losing navigation does not reset cooldown")
end

for _,oldGroupSurvives in ipairs({false,true}) do
    local p,s,e=fresh()
    local player=s:add("First Person","first")
    local zone="Durotar"
    e.GetRealZoneText=function() return zone end
    e.IsControlKeyDown=function() return true end
    if oldGroupSurvives then
        s:set("target",player.fullName,player.guid,true)
        s:set("target",nil,nil,true)
        s:tick(601)
    end
    zone="The Barrens"
    s:set("target",player.fullName,player.guid,true)
    local live=e.WhowhoBlacklistLiveBanner
    s:routePointer({live},"OnMouseDown","LeftButton")
    s:routePointer({live},"OnMouseUp","LeftButton")
    local pane=p.Shell.encounters
    local function selected()
        for _,row in ipairs(pane.children) do
            if row.entry and row.selected and row:IsShown() then return row.entry end
        end
    end
    assert(selected().row.zone==zone)
    zone="Durotar"
    s:event("ZONE_CHANGED_NEW_AREA")
    pane:Refresh()
    check(selected().row.zone==zone,"the open selection follows the same physical episode's verified place")
    s:set("target",nil,nil,true)
    s:tick(5.5)
    zone="Orgrimmar"
    s:event("ZONE_CHANGED_NEW_AREA")
    s:set("target",player.fullName,player.guid,true)
    pane:Refresh()
    local group=selected()
    check(not group,"an invalidated warning releases its selection even when older encounters exist")
end

for _,worldExit in ipairs({false,true}) do
    local p,s,e=fresh()
    local player=s:add("First Person","first")
    local zone="Durotar"
    e.GetRealZoneText=function() return zone end
    e.IsControlKeyDown=function() return true end
    s:set("target",player.fullName,player.guid,true)
    local live=e.WhowhoBlacklistLiveBanner
    s:routePointer({live},"OnMouseDown","LeftButton")
    s:routePointer({live},"OnMouseUp","LeftButton")
    local pane=p.Shell.encounters
    local function selected()
        for _,row in ipairs(pane.children) do
            if row.entry and row.selected and row:IsShown() then return row.entry.row end
        end
    end
    local original=assert(selected())
    assert(original.zone==zone and not original.endedAt)
    if not worldExit then p.Toggle() end
    zone="Orgrimmar"
    s.advance(1)
    s:event("ZONE_CHANGED_NEW_AREA")
    if worldExit then
        s:event("PLAYER_LEAVING_WORLD")
        pane:Refresh()
    else
        s:set("target",nil,nil,true)
        s:tick(5.5)
        p.Toggle()
    end
    local row=selected()
    check(row and row.id==original.id and row.zone==zone and row.endedAt==101,
        "selection keeps the same episode when its place changes and it ends before repaint")
end

do
    local p,s,e,A=fresh()
    local player=s:add("First Person","first")
    local zone="Durotar"
    e.GetRealZoneText=function() return zone end
    e.IsControlKeyDown=function() return true end
    s:set("target",player.fullName,player.guid,true)
    s:set("target",nil,nil,true)
    s:tick(33)
    zone="Orgrimmar"
    s:set("target",player.fullName,player.guid,true)
    local live=e.WhowhoBlacklistLiveBanner
    check(shown(live),"the history throttle does not suppress an otherwise eligible fresh banner")
    local function clickBanner()
        s:routePointer({live},"OnMouseDown","LeftButton")
        s:routePointer({live},"OnMouseUp","LeftButton")
    end
    local function selectedRow()
        for _,child in ipairs(p.Shell.encounters.children) do if child.entry and child.selected then return child end end
    end
    clickBanner()
    local row=selectedRow()
    check(row and row.entry.row.playerId==player.id and row.entry.row.zone==zone
        and not row.entry.row.endedAt and row.count:GetText()=="1 encounter",
        "Ctrl-click opens the moved group of the exact active, uncounted episode")
    s:set("target",nil,nil,true)
    s:tick(5)
    check(shown(live),"the qualifying banner can outlive the physical episode's absence grace")
    clickBanner()
    row=selectedRow()
    check(row and row.entry.row.playerId==player.id and row.entry.row.zone==zone and row.entry.row.endedAt==133
        and #e.WhowhoEncounterDB.regions[3]==1,"Ctrl-click still resolves the exact episode after it is coalesced into storage")
    local groups=A.encounterLedger.groups(3,138)
    check(#groups==1 and groups[1].count==1,"the coalesced zone change leaves no stale-place display row")
end

do
    local p,s,e,A=fresh()
    p.Toggle()
    p.Shell.SetSection("encounters")
    local ledger,pane=A.encounterLedger,p.Shell.encounters
    local player={id=1,name="Élodie Pâlemont",guid="one"}
    local zone="The Royal Exchange of the Silvermoon City Guard"
    local first=ledger.start(player,3,100)
    ledger.observe(first,true,false,0,zone)
    ledger.stop(first,0)
    local later=ledger.start(player,3,700)
    ledger.observe(later,true,false,0,zone)
    assert(pane:Refresh(later))
    local function verifyCells(expectHeader)
        local selected,header
        for _,child in ipairs(pane.children) do
            if child.entry and child.selected then selected=child end
            if not child.entry and child.count and child.count:GetText()=="Count" then header=child end
        end
        local name,time,count=selected.name,selected.time,selected.count
        check(header and header:IsShown()==expectHeader and name:GetStringHeight()<=name:GetHeight()
            and count:GetStringWidth()<=count:GetWidth()
            and count:GetText()==(expectHeader and "2" or "2 encounters")
            and time:GetText()==(expectHeader and "" or "Unknown · ")..e.date("%d/%m/%Y %H:%M",700).." · "..zone
            and selected:GetWidth()==(expectHeader and header:GetWidth() or pane:GetWidth()-48),
            "the grouped row fits its list and preserves full names, places and counts")
        local rulePoint,ruleLeft=selected.rule:GetPoint()
        local ruleEnd,ruleRight=selected.rule:GetPoint(2)
        local fillPoint,fillLeft,fillTop=selected.background:GetPoint()
        local fillEnd,fillRight,fillBottom=selected.background:GetPoint(2)
        local edgePoint,edgeFill,edgeTop=selected.leadingEdge:GetPoint()
        local edgeEnd,edgeEndFill,edgeBottom=selected.leadingEdge:GetPoint(2)
        check(selected.rule:GetParent()==selected and rulePoint=="TOPLEFT" and ruleLeft==6
            and ruleEnd=="TOPRIGHT" and ruleRight==-6
            and fillPoint=="TOPLEFT" and fillLeft==6 and fillTop==-4
            and fillEnd=="BOTTOMRIGHT" and fillRight==-6 and fillBottom==4,
            "row divider and fill use the roster insets")
        check(selected.leadingEdge:IsShown() and selected.leadingEdge:GetWidth()==3
            and edgePoint=="TOPLEFT" and edgeFill==selected.background and edgeTop=="TOPLEFT"
            and edgeEnd=="BOTTOMLEFT" and edgeEndFill==edgeFill and edgeBottom=="BOTTOMLEFT",
            "the selection mark shares the fill's left edge and height")
        local namePoint,nameX,nameY=name:GetPoint()
        local timePoint,timeX,timeY=time:GetPoint()
        local countPoint,countX,countY=count:GetPoint()
        if expectHeader then
            check(namePoint=="LEFT" and timePoint=="LEFT" and countPoint=="LEFT" and nameX==22
                and nameY==0 and timeY==0 and countY==0
                and timeX==nameX+name:GetWidth()+12 and countX==timeX+time:GetWidth()+12
                and header.name:GetWidth()==name:GetWidth() and header.time:GetWidth()==time:GetWidth()
                and header.count:GetWidth()==count:GetWidth() and header.count.justifyH=="CENTER" and count.justifyH=="CENTER"
                and select(2,header.name:GetPoint())==nameX and select(2,header.time:GetPoint())==timeX
                and header.faction:GetText()=="Faction" and selected.faction:GetText()=="Unknown"
                and selected.faction:GetWidth()==header.faction:GetWidth()
                and select(2,selected.faction:GetPoint())==countX+count:GetWidth()+12
                and select(2,selected.faction:GetPoint())+selected.faction:GetWidth()<=selected:GetWidth(),
                "wide headers align four bounded columns and center the count")
        else
            check(namePoint=="TOPLEFT" and timePoint=="TOPLEFT" and countPoint=="TOPRIGHT" and nameX==22 and nameX==timeX and countX==-12
                and countY==nameY and -timeY>=name:GetHeight() and -timeY+time:GetHeight()<=selected:GetHeight()
                and name:GetWidth()+count:GetWidth()<selected:GetWidth() and count.justifyH=="RIGHT",
                "compact Last seen wraps beneath the name and right-aligned count")
        end
        e.GameTooltip:Hide()
        s:fire(selected,"OnEnter")
        check(e.GameTooltip:IsShown()==(time:GetStringHeight()>time:GetHeight()),
            "only overflowing date and place text needs a hover tooltip")
        s:fire(selected,"OnLeave")
        name.IsTruncated=function() return true end
        s:fire(selected,"OnEnter")
        check(e.GameTooltip:IsShown() and e.GameTooltip:GetText():find(player.name,1,true),
            "hover recovers the exact text when the native widget reports clipping")
        s:fire(selected,"OnLeave")
        name.IsTruncated=nil
    end
    verifyCells(false)
    e.UIParent:SetSize(1280,800)
    p.Shell.Layout()
    verifyCells(true)
end

do
    local p,s,e,A=fresh()
    local zone,raid,group="Durotar"
    e.GetRealZoneText=function() return zone end
    e.UnitInRaid=function() return raid end
    e.UnitInParty=function() return group end
    s:add("Border Person","border")
    s:set("target","Border Person","border",true)
    local ledger=A.encounterLedger
    local row=ledger.snapshot(3,100).Now[1]
    check(row.lastObservedAt==100 and row.zone=="Durotar","the initial time and zone describe one observation")
    s:tick(70)
    zone,raid="Orgrimmar",1
    s:event("ZONE_CHANGED_NEW_AREA")
    check(ledger.snapshot(3,170).Now[1]==row and row.lastObservedAt==170 and row.zone=="Orgrimmar"
        and not row.groupContext,"a continuous target gets the new zone on the zone event, even within the same second")

    zone=s.secret
    s.advance(1)
    local getTime=e.GetTime
    e.GetTime=function() return nil end
    s:event("ZONE_CHANGED_NEW_AREA")
    check(row.lastObservedAt==170 and row.zone=="Orgrimmar","an unstamped event keeps the previous observation pair")
    e.GetTime=getTime
    s:event("ZONE_CHANGED_NEW_AREA")
    check(row.lastObservedAt==171 and not row.zone and row.groupContext=="Raid",
        "an unavailable zone falls back to exact raid membership at the same timestamp")
    zone,raid,group="  ",nil,true
    s.advance(1)
    s:event("ZONE_CHANGED_NEW_AREA")
    check(row.lastObservedAt==172 and not row.zone and row.groupContext=="Group",
        "the next observation replaces raid context with exact group membership")
    zone,group=nil,s.secret
    s.advance(1)
    s:event("ZONE_CHANGED_NEW_AREA")
    check(row.lastObservedAt==173 and not row.zone and not row.groupContext,
        "an observation without a readable place clears the previous fallback")
    ledger.observe(row.id,true,false,72,"Durotar")
    check(row.lastObservedAt==173 and not row.zone,"older evidence cannot overwrite the paired observation")

    zone="Caverns of Time"
    s.advance(1)
    s:event("ZONE_CHANGED_NEW_AREA")
    s.advance(66)
    s:set("target",nil,nil,true)
    s:tick(5)
    p.Toggle()
    p.Shell.SetSection("encounters")
    check(p.Shell.encounters:Refresh(row.id) and row.endedAt==240,
        "the inactive row still opens by ID and records its actual end")
    local pane=p.Shell.encounters
    local caption=assert(visibleField(pane,function(text) return text=="Last 3 Encounters" end))
    local function fact(text)
        return visibleField(caption:GetParent(),function(value) return value==text end)
    end
    check(not fact("Sources") and not fact("Mouseover") and not fact("Target"),"detection methods stay out of encounter details")
    local displayed=fact(e.date("%d/%m/%Y %H:%M",100).." · Physical encounter")
    check(displayed and fact(e.date("%H:%M",174)) and fact("Caverns of Time")
        and fact("Ended "..e.date("%d/%m/%Y %H:%M",240).." · Faction: Unknown"),
        "the detail grid and footer distinguish observed time, place, and end time")
    check(p.Shell.encounters:GetWidth()==380 and displayed:GetStringHeight()<=displayed:GetHeight(),
        "the selected detail fits all timestamps at the minimum pane width")
end

do
    local p,s,e=fresh()
    local player=s:add("First Person","first")
    e.GetRealZoneText=function() return "Durotar" end
    s:set("target",player.fullName,player.guid,true)
    p.Toggle()
    p.Shell.SetSection("encounters")
    local pane=p.Shell.encounters
    local row
    for _,child in ipairs(pane.children) do
        if child.entry then row=child; break end
    end
    assert(row)
    row.time.IsTruncated=function() return true end
    s:fire(row,"OnEnter")
    local old=row.time:GetText()
    assert(e.GameTooltip:IsShown() and e.GameTooltip:GetOwner()==row and e.GameTooltip:GetText()==old)
    s:fire(row,"OnMouseDown","LeftButton")
    s.advance(65)
    s:event("ZONE_CHANGED_NEW_AREA")
    pane:Refresh()
    check(row.time:GetText()~=old and not e.GameTooltip:IsShown(),
        "a same-place repaint dismisses the owned tooltip when its clipped Last seen changes")
    row:Click()
    check(row.selected,"the same-place repaint preserves a pending row click")
    s:fire(row,"OnEnter")
    check(e.GameTooltip:GetText()==row.time:GetText(),"hovering again shows the current Last seen")
    p.ShowTooltip(e.UIParent,"Other tooltip")
    s.advance(65)
    s:event("ZONE_CHANGED_NEW_AREA")
    pane:Refresh()
    check(e.GameTooltip:IsShown() and e.GameTooltip:GetOwner()==e.UIParent,
        "a same-place repaint preserves another tooltip owner's content")
end

do
    local zone="The Caverns of Time | South Entrance"
    local function observation(id,at,place)
        return {id=id,region=3,playerId=1,name="First Person",guid="first",target=true,
            startedAt=at,lastObservedAt=at,endedAt=at,zone=place}
    end
    local older=observation(1,30,"Orgrimmar")
    older.endedAt=96
    local exact=observation(2,60,zone)
    local badGuid=observation(3,70,"Durotar")
    badGuid.guid="wrong"
    local badName=observation(4,71,"Mulgore")
    badName.name="First Other"
    local badId=observation(5,72,"Feralas")
    badId.playerId=42
    local badRegion=observation(6,73,"Tanaris")
    badRegion.region=4
    local history={version=1,nextId=7,regions={[3]={older,exact,badGuid,badName,badId},[4]={badRegion}}}
    local p,s,e,A=fresh(nil,nil,history)
    local saved=s:add("First Person","first")
    local function dateText(at) return e.date("%d/%m/%Y %H:%M",at) end
    p.Toggle()
    local S=p.Shell
    S.SetSection("blacklist")
    local before=s.reads()
    S.rows[1]:Click()
    local field=S.detail.observation
    check(S.layoutMode=="compact" and S.selectedId==saved.id and S.details:IsVisible()
        and not S.checkStatus:IsShown() and not S.checkStatus:IsEnabled(),
        "compact Blacklist detail hides the Friend status action")
    check(S.detail.observationLabel:GetText()=="Last seen" and field:IsVisible()
        and field:GetText()==dateText(60).." · The Caverns of Time || South Entrance" and s.reads()==before,
        "selecting a saved entry uses its latest retained observation time and zone without a unit search")
    local _,_,fieldY=field:GetPoint()
    local _,_,notesY=S.detail.noteEdge:GetPoint()
    local _,_,factionY=S.detail.factionLabel:GetPoint()
    check(field.SetWordWrapArgs[1] and fieldY<notesY-S.detail.noteEdge:GetHeight()
        and factionY<fieldY-field:GetStringHeight(),
        "compact Blacklist positions Last seen between the note and faction without overlap")

    e.GetRealZoneText=function() return "Ashenvale" end
    s.advance(22)
    s:set("target","First Person","first",true)
    check(field:GetText()==dateText(122).." · Ashenvale",
        "the visible detail updates on a newer physical observation")
    p.Toggle()
    e.GetRealZoneText=function() return nil end
    e.UnitInParty=function() return true end
    s.advance(60)
    s:event("ZONE_CHANGED_NEW_AREA")
    before=s.reads()
    p.Toggle()
    check(field:GetText()==dateText(182) and s.reads()==before,
        "reopening shows the latest time alone when its observation lacks a zone")
    s:event("PLAYER_LOGOUT")
    local restored,rs,re=fresh(nil,nil,e.WhowhoEncounterDB)
    rs:add("First Person","first")
    re.UIParent:SetSize(1280,800)
    restored.Toggle()
    local R=restored.Shell
    R.SetSection("blacklist"); R.rows[1]:Click()
    check(R.layoutMode~="compact" and R.detail.observation:IsVisible()
        and R.detail.observation:GetText()==re.date("%d/%m/%Y %H:%M",182)
        and not R.checkStatus:IsVisible(),
        "wide Blacklist keeps the date of a persisted zone-less observation")

    assert(A.delete(saved))
    local replacement=s:add("First Person","first")
    check(replacement.id~=saved.id,"re-add has a fresh record ID")
    S.backButton:Click()
    S.rows[1]:Click()
    check(S.selectedId==replacement.id and not field:IsShown() and field:GetText()=="",
        "a re-added exact name and GUID cannot inherit the deleted entry's observation")
end

do
    local p,s,e,A=fresh()
    s:add("First Person","first")
    s:set("target","First Person","first",true)
    local ledger=A.encounterLedger
    local first=ledger.snapshot(3,100).Now[1]
    s.units.target.restricted=true
    s:event("PLAYER_TARGET_CHANGED")
    s:tick(5)
    check(first.endedAt==100,"an unavailable sole source cannot assert an ongoing encounter indefinitely")
    s.units.target.restricted=false
    s:event("PLAYER_TARGET_CHANGED")
    check(not ledger.snapshot(3,105).Now[1].endedAt and not shown(e.WhowhoBlacklistLiveBanner),
        "fresh exact evidence can start history without rearming a continuous alert")
    s:tick(1)
    e.IsInInstance=function() return true,"party" end
    s:event("ZONE_CHANGED_NEW_AREA")
    check(ledger.snapshot(3,106).Now[1].endedAt==106,"instance suspension closes active evidence")
    s:tick(20)
    s:event("PLAYER_TARGET_CHANGED")
    check(#e.WhowhoEncounterDB.regions[3]==1,"short repeats and suspended events add no count")
end

do
    local p,s,e,A=fresh()
    local first=s:add("First Person","first")
    local second=s:add("Second Person","second")
    local ctrl=false
    e.IsControlKeyDown=function() return ctrl end
    e.GetRealZoneText=function() return "Orgrimmar" end
    s:set("target","First Person","first",true)
    local live=e.WhowhoBlacklistLiveBanner
    local function modifier(value)
        ctrl=value
        s:event("MODIFIER_STATE_CHANGED","LCTRL",value and 1 or 0)
    end
    local function press(widgetEvent,button)
        return s:routePointer({live},widgetEvent,button or "LeftButton")
    end
    check(not press("OnMouseDown"),"ordinary pointer input passes through a visible alert")
    modifier(true)
    check(press("OnMouseDown")==live,"holding Ctrl enables the live alert hit target")
    modifier(false)
    modifier(true)
    press("OnMouseUp")
    check(not p.Shell.window,"releasing Ctrl cancels a pending alert click")

    press("OnMouseDown")
    s:set("mouseover","Second Person","second",true)
    s:tick(8.5)
    press("OnMouseUp")
    check(not p.Shell.window and live.character:GetText()=="Second Person",
        "mouse-up cannot activate a replacement banner")
    press("OnMouseDown","RightButton")
    press("OnMouseUp","RightButton")
    check(not p.Shell.window,"a right click does not navigate")
    press("OnMouseDown")
    press("OnMouseUp")
    check(p.Shell.section=="encounters" and p.Shell.window:IsShown(),
        "Ctrl plus a complete left click opens the Encounters pane")
    local action,selected
    for _,child in ipairs(p.Shell.encounters.children) do
        if child.label and child.label:GetText()=="View Blacklist entry" then action=child end
        if child.entry and child.selected then selected=child end
    end
    check(action and action:IsEnabled() and selected.name:GetText()=="Second Person"
        and selected.time:GetText()=="Unknown · "..e.date("%d/%m/%Y %H:%M",108).." · Orgrimmar"
        and not selected.source and not selected.zone,
        "the pane selection binds to the exact clicked encounter")
    s:fire(action,"OnMouseDown","LeftButton"); action:Click()
    check(p.Shell.section=="blacklist" and p.Shell.selected.id==second.id and #p.Shell.filtered==2,
        "View Blacklist entry reveals the exact current entry in the ordinary list")

    p.Shell.SetSection("encounters")
    assert(A.store.delete(second.id,3,second.fullName,second.guid))
    s:add("Second Person","replacement")
    s:fire(action,"OnMouseDown","LeftButton"); action:Click()
    check(p.Shell.section=="encounters","an old encounter cannot open a newly added same-name entry")
    p.Shell.encounters:Refresh()
    check(not action:IsEnabled() and A.store.get(first.id)~=nil,"the stale action visibly disables without altering other entries")
    s:event("PLAYER_LEAVING_WORLD")
    p.Shell.encounters:Refresh()
    check(selected.time:GetText()=="Unknown · "..e.date("%d/%m/%Y %H:%M",108).." · Orgrimmar",
        "the completed observation shows its date and zone in the same field")
end

do
    local p,s,e,A=fresh()
    local cases={{"Zone Person","zone","Orgrimmar"},{"Raid Person","raid","Raid"},
        {"Group Person","group","Group"},{"Unknown Person","unknown","Unknown"}}
    local reads=0
    e.GetRealZoneText=function()
        return s.units.target.guid=="zone" and "Orgrimmar" or s.secret
    end
    e.UnitInRaid=function(unit)
        check(unit=="target","raid context is checked only for the observed unit")
        reads=reads+1
        local guid=s.units[unit].guid
        return (guid=="zone" or guid=="raid") and 1 or nil
    end
    e.UnitInParty=function(unit)
        check(unit=="target","party context is checked only for the observed unit")
        local guid=s.units[unit].guid
        return guid=="group" and true or s.secret
    end
    for _,example in ipairs(cases) do s:add(example[1],example[2]) end
    for i,example in ipairs(cases) do
        s:set("target",example[1],example[2],true)
        if i==1 then check(reads==0,"a known zone takes precedence over group checks") end
    end
    p.Toggle()
    p.Shell.SetSection("encounters")
    local displayed={}
    local pane=p.Shell.encounters
    local more
    repeat
        for _,child in ipairs(pane.children) do
            if child.kind=="Button" and child.entry and child:IsShown() then
                displayed[child.entry.row.name]=child.time:GetText():gsub("^Unknown · ","")
            elseif child.label and child.label:GetText()=="Next" then
                more=child
            end
        end
        if not more or not more:IsEnabled() then break end
        more:Click()
    until false
    for _,example in ipairs(cases) do
        check(displayed[example[1]]==e.date("%d/%m/%Y %H:%M",100).." · "..example[3],
            "Last seen displays the exact fallback for "..example[1])
    end
    s:event("PLAYER_LEAVING_WORLD")
    local _,_,_,restoredA=fresh(nil,nil,e.WhowhoEncounterDB)
    local history=restoredA.encounterLedger.snapshot(3,100).Now
    check(#history==4 and history[1].groupContext==nil and history[2].groupContext=="Group"
        and history[3].groupContext=="Raid" and history[4].zone=="Orgrimmar",
        "all verified Last seen locations survive reload without guessing missing evidence")
end

do
    local _,s,e,A=fresh()
    s:add("Original Person","original")
    s:add("Replacement Person","replacement")
    e.UnitInRaid=function()
        if s.units.target.guid=="original" then
            s:set("target","Replacement Person","replacement",true)
            return 1
        end
    end
    s:set("target","Original Person","original",true)
    s:tick(.25)
    local rows=A.encounterLedger.snapshot(3,100).Now
    check(#rows==1 and rows[1].name=="Replacement Person" and not rows[1].groupContext,
        "nested target replacement cannot attach a stale raid result to either encounter")
end

do
    local _,s,e,A=fresh()
    s:add("Original Person","original")
    s:add("Replacement Person","replacement")
    e.GetRealZoneText=function() return "Durotar" end
    s:set("target","Original Person","original",true)
    local original=A.encounterLedger.snapshot(3,100).Now[1]
    e.GetRealZoneText=function()
        if s.units.target.guid=="original" then s:set("target","Replacement Person","replacement",true) end
        return "Orgrimmar"
    end
    s.advance(3)
    s:event("ZONE_CHANGED_NEW_AREA")
    s:tick(.25)
    local rows=A.encounterLedger.snapshot(3,103).Now
    check(#rows==2 and rows[1].name=="Replacement Person" and rows[1].zone=="Orgrimmar"
        and original.lastObservedAt==100 and original.zone=="Durotar",
        "a nested target change during the zone read leaves the prior observation intact")
end

do
    local p,s,e,A=fresh()
    p.Toggle()
    p.Shell.SetSection("encounters")
    local ledger,pane=A.encounterLedger,p.Shell.encounters
    for i,name in ipairs({"One","Two","Three","Four","Five","Six","Seven"}) do
        local id=ledger.start({id=i,name=name.." Person",guid="g"..i},3,90+i)
        ledger.observe(id,true,false,0,"Durotar")
        ledger.stop(id,0)
    end
    check(pane:Refresh(7),"the selected row opens on the first page")
    local nextPage,pageLabel
    for _,child in ipairs(pane.children) do
        if child.label and child.label:GetText()=="Next" then nextPage=child end
        if child.kind=="FontString" and child:GetText()=="1 of 3" then pageLabel=child end
    end
    assert(nextPage and pageLabel)
    nextPage:Click()
    check(pageLabel:GetText()=="2 of 3","paging can move away from a selected row")

    local newest=ledger.start({id=8,name="Eight Person",guid="g8"},3,100)
    ledger.observe(newest,true,false,0,"Orgrimmar")
    s:fire(pane,"OnUpdate",1)
    check(pageLabel:GetText()=="2 of 3","a background encounter update preserves the current page")
    local _,_,byId=ledger.groups(3,100)
    p.Shell.OpenEncounter({id=newest,key=byId[newest].episodeKeys[newest]},function() return true end)
    local function visibleSelection(id)
        for _,child in ipairs(pane.children) do
            if child.selected and child.entry and child.entry.row.id==id and child:IsShown() then return true end
        end
    end
    check(pageLabel:GetText()=="1 of 3" and visibleSelection(newest),
        "explicit encounter navigation reveals the exact requested row")
    check(pane:Refresh(1) and pageLabel:GetText()=="3 of 3" and visibleSelection(1),
        "an explicit refresh with an ID can reveal a row on another page")
    e.GetServerTime=function() return 30*86400+96 end
    s:fire(pane,"OnUpdate",1)
    check(pageLabel:GetText()=="" and not nextPage:IsShown() and pane:Refresh(newest),
        "background retention clamps the page when the page count shrinks")
end

do
    local p,s,e,A=fresh()
    local ledger=A.encounterLedger
    for i=1,502 do
        local id=ledger.start({id=i,name="First Person",guid="test"..i},3,i)
        ledger.observe(id,true,false,0)
        ledger.stop(id,0)
    end
    local rows=e.WhowhoEncounterDB.regions[3]
    check(#rows==500 and rows[1].id==502 and rows[500].id==3,"count retention keeps the 500 newest rows")
    ledger.snapshot(3,30*86400+3)
    check(#rows==499 and rows[499].id==4,"age retention drops the entry at exactly 30 days")
    local row=rows[1]
    check(ledger.snapshot(3,nil).Ended[1]==row and not row.zone,
        "older rows without a zone remain available without guessing the current time")
    local damaged={version=1,nextId=503,regions={[3]={row,row}}}
    local _,_,restored,A2=fresh(nil,nil,damaged)
    check(not A2.encounterLedger.available() and restored.WhowhoEncounterDB==damaged,
        "duplicate persisted IDs fail closed while preserving their original saved data")

    local noncanonical={}
    for key,value in pairs(row) do noncanonical[key]=value end
    local nameWithNbsp="First\194\160Person"
    noncanonical.name=nameWithNbsp
    local history={version=1,nextId=503,regions={[3]={noncanonical}}}
    local _,_,saved,restoredA=fresh(nil,nil,history)
    check(not restoredA.encounterLedger.available() and saved.WhowhoEncounterDB==history
        and noncanonical.name==nameWithNbsp,"persisted encounter names require the exact separator")
end

do
    local p,s,e,A=fresh()
    local first=s:add("First Person","first")
    local other=s:add("Other Person","other")
    local calls=0
    e.UnitFactionGroup=function(token)
        calls=calls+1
        assert(token=="target" or token=="mouseover","metadata only reads the observed unit")
        return token=="target" and "Horde" or "Alliance"
    end
    e.UnitClass=function() return "Mage","MAGE" end
    e.GetRealZoneText=function() return "Durotar" end
    e.C_ClassColor={GetClassColor=function(class) return class=="MAGE" and {r=.2,g=.6,b=.9} end}
    p.Toggle()
    p.Shell.SetSection("blacklist")
    p.Shell.Select(first)
    local store=A.store
    s:set("target",first.fullName,"different-guid",true)
    s:set("mouseover","Different Name",first.guid,true)
    check(calls==0 and A.store==store,"exact saved name and GUID conflicts never read or save faction")
    s:set("target",first.fullName,first.guid,true)
    local saved=e.WhowhoAddressBookDB
    local evidence=assert(saved.regions[3][first.id].lastKnown)
    check(evidence.guid==first.guid and evidence.class.value=="MAGE" and evidence.faction.value=="Horde"
        and evidence.faction.source=="Target","the exact target persists its class and unlocalized faction together")
    s:tick(.5)
    s:set("target",nil,nil,true)
    s:set("target",first.fullName,first.guid,true)
    check(calls==2 and e.WhowhoAddressBookDB==saved and known(A,first).faction.at==100,
        "polling and repeated identical metadata perform no new SavedVariables writes")
    check(p.Shell.detail.factionLabel:IsShown() and p.Shell.detail.affiliation:GetText()=="Horde",
        "selected Blacklist entry displays verified faction under its own label")
    s:event("PLAYER_LOGOUT")
    local previous=e.WhowhoEncounterDB
    local restored,_,re,A2=fresh(nil,nil,previous,saved)
    re.UnitFactionGroup=function() error("rendering must not read a native unit") end
    re.C_ClassColor=e.C_ClassColor
    restored.Toggle()
    restored.Shell.SetSection("blacklist")
    for _,record in ipairs(A2.records) do
        if record.id==first.id then restored.Shell.Select(record) end
    end
    local restoredRow
    for _,row in ipairs(restored.Shell.rows) do
        if row.record and row.record.id==first.id then restoredRow=row end
    end
    check(restoredRow and restoredRow.name.textColor[1]==.2
        and restored.Shell.detail.factionLabel:IsShown() and restored.Shell.detail.affiliation:GetText()=="Horde",
        "Blacklist restores color and faction without retargeting after reload")
    local shell=restored.Shell
    restoredRow.deleteButton:Click()
    check(shell.deleteDialog:IsShown() and shell.deleteMessage.textColor[1]==.2,
        "the delete confirmation also restores the exact saved class color")
    shell.deleteCancel:Click()
    shell.SetSection("encounters")
    local pane=shell.encounters
    local row
    for _,child in ipairs(pane.children) do if child.entry and child.entry.row.playerId==first.id then row=child end end
    check(row and row.name.textColor[1]==.2 and row.count:GetText()=="1 encounter"
        and row.time:GetText():match("^Horde · .+Durotar$"),
        "compact Encounters shows the same verified class and faction beside the unchanged place and count")
    re.UIParent:SetSize(1280,800)
    shell.Layout()
    check(row.faction:IsShown() and row.faction:GetText()=="Horde" and row.count:GetText()=="1"
        and row.time:GetText():match("Durotar$"),"wide Encounters shows faction in its own column")
    local historyId=row.entry.row.id
    assert(pane:Refresh(historyId))
    local detail=visibleField(pane,function(text) return text:match("Faction: Horde$") end)
    check(detail and detail:GetStringHeight()<=detail:GetHeight(),"selected encounter details include the verified faction")
    assert(A2.delete(assert(A2.store.get(first.id))))
    local replacement=assert(A2.save(nil,"blacklist",first.fullName,"",nil,{"other"}))
    assert(pane:Refresh(historyId))
    check(replacement.id~=first.id and row.faction:GetText()=="Unknown" and row.name.textColor[1]==restored.colors.text[1]
        and not known(A2,replacement).faction and not known(A2,other).faction,
        "deleted and pooled rows cannot borrow metadata from a new same-name record")
end

do
    local p,s,e,A=fresh()
    local first=s:add("First Person","first")
    local second=s:add("Second Person","second")
    local replaced=false
    e.UnitFactionGroup=function()
        if not replaced then
            replaced=true
            s:set("mouseover",second.fullName,second.guid,true)
            return "Horde"
        end
        return "Alliance"
    end
    s:set("mouseover",first.fullName,first.guid,true)
    check(not known(A,first).faction and not known(A,second).faction,"nested replacement invalidates the entire faction sample")
    s:tick(.25)
    check(known(A,second).faction.value=="Alliance","only the new exact hover's readable faction is persisted")
    e.UnitFactionGroup=function(token)
        s.units[token].restricted=true
        return "Horde"
    end
    s:set("target",first.fullName,first.guid,true)
    check(not known(A,first).faction,"a unit that becomes restricted during the native read does not write faction")
    e.UnitFactionGroup=function() return s.secret end
    s:set("target",first.fullName,first.guid,true)
    check(not known(A,first).faction and known(A,second).faction.value=="Alliance",
        "unreadable faction leaves both records' existing metadata intact")
end

do
    local p,s,e,A=fresh()
    local target=s:add("First Person","first")
    local sounds, reads=0,0
    e.UnitClass=function()
        reads=reads+1
        return "Mage","MAGE"
    end
    e.UnitFactionGroup=function() return "Horde" end
    e.C_Sound={PlaySoundWithOptions=function()
        sounds=sounds+1
        s:event("PLAYER_TARGET_CHANGED")
        return true
    end}
    s:set("target",target.fullName,target.guid,true)
    check(sounds==1 and not known(A,target).faction,"a reentrant live cue interrupts the first metadata save")
    local bookChanged=p.BlacklistBanner.sightingsBookChanged
    local refreshed=false
    p.BlacklistBanner.sightingsBookChanged=function()
        if not refreshed then
            refreshed=true
            s:event("PLAYER_TARGET_CHANGED")
        end
        bookChanged()
    end
    s:tick(.25)
    local saved=e.WhowhoAddressBookDB
    check(refreshed and saved and knownClass(A,target)=="MAGE" and known(A,target).faction.value=="Horde"
        and sounds==1 and reads==2,"the next owned scan saves the same target without replaying the cue")
    s:tick(.5)
    check(e.WhowhoAddressBookDB==saved and sounds==1 and reads==2,
        "successful retry consumes the metadata sample without polling or another write")
end

for _,change in ipairs({"target","store","region"}) do
    local p,s,e,A=fresh()
    local first=s:add("First Person","first")
    local second=change=="region" and s:add(first.fullName,first.guid,nil,nil,4) or s:add("Second Person","second")
    local sounds=0
    e.UnitFactionGroup=function() return sounds==0 and "Horde" or "Alliance" end
    e.C_Sound={PlaySoundWithOptions=function()
        sounds=sounds+1
        if sounds~=1 then return true end
        if change=="target" then
            s:set("target",second.fullName,second.guid,true)
        else
            if change=="region" then
                s.region(4)
                A.region=4
                A.refresh()
            else
                assert(A.save(nil,"blacklist","Other Entry","",nil,{"other"}))
            end
            s:event("PLAYER_TARGET_CHANGED")
        end
        return true
    end}
    s:set("target",first.fullName,first.guid,true)
    check(not known(A,first).faction,"interrupted faction never crosses a "..change.." change")
    s:tick(.25)
    local current=change=="store" and first or second
    check(known(A,current).faction and known(A,current).faction.value=="Alliance"
        and (change=="store" or not known(A,first).faction),
        "the retry independently verifies the current identity after a "..change.." change")
end

for _,requireEvent in ipairs({false,true}) do
    local _,s,e,A=fresh()
    local target=assert(A.save(nil,"blacklist","Quiet Person","",nil,{"other"}))
    local classReads,factionReads,sounds=0,0,0
    local faction
    e.UnitClass=function() classReads=classReads+1; return "Mage","MAGE" end
    e.UnitFactionGroup=function() factionReads=factionReads+1; return faction end
    e.C_Sound={PlaySoundWithOptions=function() sounds=sounds+1; return true end}
    s:set("target",target.fullName,"quiet",true)
    local classOnly=e.WhowhoAddressBookDB
    check(knownClass(A,target)=="MAGE" and not known(A,target).faction and s.observer:GetScript("OnUpdate"),
        "a partially readable exact target saves the class and schedules one retry")
    if not requireEvent then faction="Horde" end
    e.UnitClass=function() classReads=classReads+1; return nil end
    s:tick(.25)
    check(classReads==1 and factionReads==2 and not s.observer:GetScript("OnUpdate"),
        "the quiet target retries the missing field once and stops updating")
    if requireEvent then
        s:tick(1)
        check(factionReads==2 and e.WhowhoAddressBookDB==classOnly,
            "an empty retry does not poll indefinitely or republish the class")
        faction="Horde"
        s:event("PLAYER_TARGET_CHANGED")
    end
    local evidence=known(A,target)
    check(classReads==1 and evidence.class.value=="MAGE" and evidence.class.at==100
        and evidence.faction.value=="Horde" and sounds==0,
        "the unchanged quiet target can save a later faction without replaying cues or replacing the class")
end

do
    local _,s,e,A=fresh()
    local first=assert(A.save(nil,"blacklist","First Person","",nil,{"other"}))
    local second=assert(A.save(nil,"blacklist","Second Person","",nil,{"other"}))
    local faction
    e.UnitClass=function() return "Mage","MAGE" end
    e.UnitFactionGroup=function() return faction end
    s:set("target",first.fullName,"first",true)
    s:set("target",second.fullName,"second",true)
    faction="Horde"
    s:tick(.25)
    local knownFirst,knownSecond=known(A,first),known(A,second)
    check(not knownFirst.faction and knownSecond.faction and knownSecond.faction.value=="Horde",
        "a fresh exact target replaces the earlier automatic retry with its own")
end

do
    local _,s,e,A=fresh()
    local target=s:add("First Person","first")
    local reads,faction=0,s.secret
    e.UnitFactionGroup=function() reads=reads+1; return faction end
    s:set("mouseover",target.fullName,target.guid,true)
    s:tick(.5)
    s:tick(.5)
    check(reads==1 and not known(A,target).faction and not e.WhowhoAddressBookDB,
        "an entirely unavailable optional result does not trigger automatic metadata retries")
    faction="Horde"
    s:event("UPDATE_MOUSEOVER_UNIT")
    check(reads==2 and known(A,target).faction.value=="Horde",
        "a new mouseover event can verify a field for the same exact unit after an empty sample")
end

for _,blocked in ipairs({"clock","combat"}) do
    local _,s,e,A=fresh()
    local target=assert(A.save(nil,"blacklist","Quiet Person","",nil,{"other"}))
    local reads=0
    local now=e.GetServerTime
    e.UnitClass=function() reads=reads+1; return "Mage","MAGE" end
    e.UnitFactionGroup=function() return "Horde" end
    if blocked=="clock" then e.GetServerTime=function() return nil end else s.combat(true) end
    s:set("target",target.fullName,"quiet",true)
    check(not known(A,target).faction and reads==(blocked=="clock" and 1 or 0),
        "a missing "..blocked.." prerequisite prevents an unverified save")
    e.GetServerTime=now
    s.combat(false)
    s:tick(.25)
    if blocked=="combat" then
        check(reads==0,"combat-blocked metadata does not start automatic native reads")
        s:event("PLAYER_TARGET_CHANGED")
    end
    check(knownClass(A,target)=="MAGE" and known(A,target).faction.value=="Horde",
        "the unchanged exact target can acquire metadata after "..blocked.." becomes ready")
end

for _,interruptRetry in ipairs({false,true}) do
    local p,s,e,A=fresh()
    local target=assert(A.save(nil,"blacklist","Quiet Person","",nil,{"other"}))
    local checks, reads, sounds=0,0,0
    local saving=false
    local saveObservations=A.saveBlacklistObservations
    A.saveBlacklistObservations=function(...)
        saving=true
        local settled=saveObservations(...)
        saving=false
        return settled
    end
    e.UnitFactionGroup=function() reads=reads+1; return "Horde" end
    e.C_Sound={PlaySoundWithOptions=function() sounds=sounds+1; return true end}
    e.InCombatLockdown=function()
        if saving then
            checks=checks+1
            if checks==1 then
                assert(A.save(nil,"blacklist","Other Entry","",nil,{"other"}))
            elseif checks==2 and interruptRetry then
                assert(A.save(nil,"blacklist","Another Entry","",nil,{"other"}))
            end
        end
        return false
    end
    s:set("target",target.fullName,"quiet",true)
    check(reads==1 and sounds==0 and not known(A,target).faction and s.observer:GetScript("OnUpdate"),
        "store replacement during a quiet target revalidation schedules one retry without a cue")
    s:tick(.25)
    local faction=known(A,target).faction
    check(checks==2 and reads==2 and sounds==0 and not s.observer:GetScript("OnUpdate")
        and (interruptRetry and not faction or not interruptRetry and faction and faction.value=="Horde"),
        "quiet retry records current evidence once or stops if ownership is interrupted again")
    s:tick(.5)
    check(reads==2 and sounds==0,"repeated store replacement cannot start a metadata polling loop")
end

do
    local p,s,e,A=fresh()
    local person=s:add("Ivory Lakeshire","ivory",{"other"})
    local ledger=A.encounterLedger
    local zones={"Elwynn","Westfall","Ashenvale","Durotar"}
    local latest
    for i,zone in ipairs(zones) do
        latest=ledger.start({id=person.id,name=person.fullName,guid=person.guid},3,i*600)
        ledger.observe(latest,true,false,0,zone)
        ledger.stop(latest,0)
    end
    e.GetServerTime=function() return 2401 end
    p.Toggle()
    p.Shell.SetSection("encounters")
    local pane=p.Shell.encounters
    local search
    for _,child in ipairs(pane.children) do
        if child.kind=="EditBox" then search=child end
    end
    assert(pane:Refresh(latest))
    local caption=assert(visibleField(pane,function(t) return t=="Last 3 Encounters" end))
    local reason=assert(visibleField(caption:GetParent(),function(t) return t==A.reasonText(person.reasonIds) end))
    check(select(3,reason:GetPoint())>select(3,caption:GetPoint()),"the linked reason precedes the recent history")
    for i=2,4 do
        local when=visibleField(caption:GetParent(),function(t) return t==e.date("%H:%M",i*600).."\n"..e.date("%d/%m/%Y",i*600) end)
        local paired=false
        for _,field in ipairs(caption:GetParent().children) do
            if when and field.kind=="FontString" and field:IsShown() and field:GetText()==zones[i]
                and select(3,field:GetPoint())==select(3,when:GetPoint()) then paired=true end
        end
        check(paired,"each recent encounter displays its own date and zone on the same row")
    end
    check(not visibleField(caption:GetParent(),function(t) return t:find("Elwynn",1,true) end),
        "the fourth encounter stays outside the detail history")
    local copy
    for _,child in ipairs(caption:GetParent().children) do
        if child.label and child.label:GetText()=="Copy name" then copy=child end
    end
    assert(copy)
    local point,anchor,edge,gap,lift=copy:GetPoint()
    local rosterCopy=p.Shell.rows[1].copyButton
    check(point=="LEFT" and anchor:GetText()==person.fullName and edge=="RIGHT" and gap==1 and lift==4
        and copy:GetWidth()==rosterCopy:GetWidth() and copy.icon:GetWidth()==rosterCopy.icon:GetWidth(),
        "Encounter copy aligns to the name and matches the roster control")
    s:fire(copy,"OnMouseDown","LeftButton")
    copy:Click()
    check(p.Shell.copyDialog:IsVisible() and p.Shell.copyBox:GetText()==person.fullName,
        "the copy icon beside the identity selects the validated displayed name")
    p.Shell.copyDialog:Hide()
    search:SetText("durot")
    check(visibleField(pane,function(t) return t=="4 encounters" end),"the search matches the latest zone")
    search:SetText("Westfall")
    check(visibleField(pane,function(t) return t=="No matching encounters." end),"older zones do not override the current list place")
    check(pane:Refresh(latest) and search:GetText()=="","explicit navigation restores a filtered-out character")
    e.UIParent:SetSize(1280,800)
    p.Shell.Layout()
    checkTabs(p,pane,{"Last hour","Recent","Earlier"},1)
end

print("RESULT blacklist-banner and encounters simulated "..count.." passed; no client capability established")
