-- Offline event and widget fixtures for the manual candidate.
local root=arg[1] or "."
local H=dofile(root.."/tests/addon/harness.lua")
local config={region=3,time=100}
local p,s,e=H.fresh(root,nil,{484,800},config)
local units, reads, clock, combat = {}, 0, 100, false
local frames, availablePlates = {}, {}
local ariGuid,beaGuid,ciaGuid,daxGuid="Player-1-0000000A","Player-1-0000000B","Player-1-0000000C","Player-1-0000000D"
local timer
local function plateFrame(unit)
    if not units[unit] then return end
    if not frames[unit] then
        frames[unit]={
            GetUnit=function() return unit end,
            IsForbidden=function() return units[unit].forbidden==true end,
            IsVisible=function() return units[unit].hidden~=true end,
        }
    end
    return frames[unit]
end
local function stub(env)
    env.GetTime=function() return clock end
    env.InCombatLockdown=function() return combat end
    env.C_Secrets={ShouldUnitIdentityBeSecret=function(unit) return units[unit] and units[unit].restricted==true or false end}
    env.UnitExists=function(unit) reads=reads+1; return units[unit]~=nil end
    env.UnitIsPlayer=function(unit) return units[unit].player~=false end
    env.UnitIsUnit=function(unit,other) return other=="player" and (unit=="player" or units[unit] and units[unit].self==true) or false end
    env.UnitFactionGroup=function(unit) return units[unit] and units[unit].faction end
    env.GetUnitName=function(unit) return units[unit].name end
    env.UnitGUID=function(unit) return units[unit].guid end
    env.UnitClass=function() return "Mage","MAGE" end
    env.UnitLevel=function() return 42 end
    env.date=function() return "2026-11-19 12:30" end
    env.C_NamePlate={
        GetNamePlateForUnit=function(unit,includeForbidden)
            assert(includeForbidden==false)
            return plateFrame(unit)
        end,
        GetNamePlates=function() return availablePlates end,
    }
    env.C_Timer={NewTimer=function(_,callback)
        timer={run=callback,Cancel=function() end}
        return timer
    end}
end
stub(e)
e.C_ClassColor={GetClassColor=function(class)
    assert(class=="MAGE")
    return {r=0.2,g=0.6,b=0.9}
end}
units.nameplate1={name="Ari North",guid=ariGuid,faction="Alliance"}
s:event("ADDON_LOADED","WhoWho")
p.Toggle()
local A,S=p.manual,p.Shell
assert(A.automaticTargetEnabled() and A.automaticMouseoverEnabled() and A.relogRefreshEnabled())
assert(A.automaticNameplatesEnabled() and not p.db.skipDeleteConfirmation)
local routed, settings = {}, {}
-- The Blacklist observer has its own integration cases. Spy on the shared routing here.
p.BlacklistBanner.sightingsNameplateEvent=function(event,unit) routed[#routed+1]={event,unit} end
p.BlacklistBanner.sightingsNameplatesChanged=function(enabled) settings[#settings+1]=enabled end
local function save(name,membership)
    return assert(A.save(nil,membership or "friend",name,"",nil,membership=="blacklist" and {"other"} or nil)).id
end
local ari,bea,cia,dax=save("Ari North"),save("Bea North"),save("Cia North"),save("Dax South")
local blacklist=save("Bad North","blacklist")
local saved=e.WhowhoAddressBookDB
local function item(id)
    for _,record in ipairs(A.records) do if record.id==id then return record end end
end
local function enter(unit) s:event("NAME_PLATE_UNIT_ADDED",unit) end
local function leave(unit) s:event("NAME_PLATE_UNIT_REMOVED",unit) end
local function subscribed(sim,event)
    for _,frame in ipairs(sim.nodes) do if frame.events[event] then return true end end
    return false
end

S.nav.settings:Click()
S.settingsTabs.general:Click()
local toggle=S.automaticNameplates
local function hasText(parent, expected)
    for _,view in ipairs(parent.children) do
        if view:GetText()==expected and view:IsShown() then return view end
    end
    return false
end
assert(toggle:IsVisible() and toggle:IsEnabled() and toggle:GetChecked())
assert(hasText(toggle.parent,"World sightings"))
local heading=assert(hasText(toggle,"Use visible player nameplates"))
local help=assert(hasText(toggle,"Updates Friends and can trigger Blacklist alerts for either faction."))
local _,_,headingY=heading:GetPoint()
local _,_,helpY=help:GetPoint()
assert(-headingY+heading:GetStringHeight()<=-helpY and -helpY+help:GetStringHeight()<toggle:GetHeight())
assert(subscribed(s,"NAME_PLATE_UNIT_ADDED") and subscribed(s,"NAME_PLATE_UNIT_REMOVED"))
assert(not subscribed(s,"FORBIDDEN_NAME_PLATE_UNIT_ADDED"))
toggle:Click()
assert(not toggle:GetChecked() and not subscribed(s,"NAME_PLATE_UNIT_REMOVED"))
assert(p.db.automaticNameplates==false and #settings==1 and settings[1]==false)
local idleReads=reads
enter("nameplate1")
assert(reads==idleReads and not subscribed(s,"NAME_PLATE_UNIT_ADDED") and not item(ari).presence and #routed==0)
units.nameplate4={name="Dax South",guid=daxGuid,faction="Horde"}
availablePlates={[4]=plateFrame("nameplate4"),[19]={
    GetUnit=function() return "nameplate1" end,
    IsForbidden=function() return false end,
    IsVisible=function() return true end,
}}
toggle:Click()
assert(toggle:GetChecked() and not S.scrim:IsShown() and not S.nameplateNotice)
assert(#settings==2 and settings[2]==true)
assert(item(dax).source=="Nameplate" and item(dax).faction=="Horde" and not item(ari).presence)
availablePlates={}
S.nav.friend:Click()

-- Only exact saved Friends with readable player identity and ordinary frames gain presence.
units.nameplate2={name="Unknown North",guid="Player-1-0000001A"}
units.nameplate3={name="Bad North",guid="Player-1-0000001B"}
units.nameplate5={name="Bea North",guid=beaGuid,restricted=true}
units.nameplate6={name="Bea North",guid=beaGuid,self=true}
units.nameplate7={name="Bea North",guid=beaGuid,player=false}
units.nameplate10={name="Bea North",guid=beaGuid,hidden=true}
units.nameplate11={name="Bea North",guid=beaGuid,forbidden=true}
units.nameplate12={name="Bea North",guid=s.secret}
units.nameplate13={name="Bea North",guid="Creature-0-0000000B"}
units.nameplate14={name="Bea",guid=beaGuid}
for i=2,7 do enter("nameplate"..i) end
for i=10,14 do enter("nameplate"..i) end
enter("target"); enter(s.secret)
assert(not item(bea).presence and not item(blacklist).presence)
combat=true
local before=reads
enter("nameplate1")
assert(reads==before and not item(ari).presence)
combat=false
local prior={id=ari,region=3,name="Ari North",guid=ariGuid,source="Party",online=false}
A.targetCheck.roster[ari]=prior; A.targetCheck.latest[ari]="roster"; A.refresh()
assert(p.RosterModel.Presence(item(ari))=="Checked")
enter("nameplate1")
assert(item(ari).presence=="Seen" and item(ari).source=="Nameplate" and e.WhowhoAddressBookDB==saved)
assert(item(ari).faction=="Alliance")
assert(p.RosterModel.Presence(item(ari))=="Seen" and A.targetCheck.roster[ari]==prior)
assert(item(ari).class=="MAGE" and item(ari).level==42, "the nameplate sighting must supply readable class and level")
assert(S.rows[1].name.textColor[1]==0.2 and S.rows[1].meta:GetText():find("42",1,true))
local first=item(ari)
enter("nameplate1")
assert(item(ari)==first)
leave("nameplate1")
units.nameplate1={name="Ari North",guid="Player-1-000000AA"}
config.time=106
enter("nameplate1")
assert(item(ari)==first and item(ari).presence=="Seen")
units.nameplate1.guid=ariGuid
local unitClass,unitLevel=e.UnitClass,e.UnitLevel
e.UnitClass=function() return "Mage",s.secret end
e.UnitLevel=function() return 43 end
enter("nameplate1")
assert(item(ari)~=first and item(ari).source=="Nameplate")
assert(item(ari).class=="MAGE" and item(ari).level==43 and e.WhowhoAddressBookDB==saved)
e.UnitClass,e.UnitLevel=unitClass,unitLevel

-- Removal during a GUID read retires its owner before another identity read.
units.nameplate1={name="Bea North",guid=beaGuid}
local guid,name=e.UnitGUID,e.GetUnitName
local nameReads=0
local routeCount=#routed
e.GetUnitName=function(unit) nameReads=nameReads+1; return name(unit) end
e.UnitGUID=function(unit) leave(unit); return guid(unit) end
enter("nameplate1")
assert(nameReads==0 and not item(bea).presence)
assert(#routed==routeCount+1 and routed[#routed][1]=="NAME_PLATE_UNIT_REMOVED" and routed[#routed][2]=="nameplate1")
e.UnitGUID=guid; e.GetUnitName=name
-- Combat beginning in the final identity read invalidates the staged result.
e.GetUnitName=function(unit)
    nameReads=nameReads+1
    if nameReads==2 then combat=true end
    return name(unit)
end
enter("nameplate1")
assert(combat and not item(bea).presence)
combat=false; e.GetUnitName=name
e.UnitLevel=function() return s.secret end
enter("nameplate1")
assert(item(bea).source=="Nameplate" and item(bea).class=="MAGE" and not item(bea).level)
e.UnitLevel=unitLevel

-- Direct sightings retain priority and durable metadata. Subsequent plate events do no rebuild.
assert(A.setAutomaticTarget(true))
units.target={name="Ari North",guid=ariGuid}
e.UnitLevel=function(unit) if unit~="target" then return unitLevel(unit) end end
s:event("PLAYER_TARGET_CHANGED")
local targeted=item(ari)
local targetKnown=A.store.get(ari).lastKnown
assert(targeted.source=="Target" and targeted.level==43 and targetKnown.class.source=="Target" and not targetKnown.level)
e.UnitLevel=unitLevel
units.nameplate8={name="Ari North",guid=ariGuid}
enter("nameplate8")
assert(item(ari)==targeted)
assert(A.setAutomaticMouseover(true))
units.mouseover={name="Bea North",guid=beaGuid}
clock=106; s:event("UPDATE_MOUSEOVER_UNIT")
clock=106.25; timer.run()
assert(item(bea).source=="Mouseover" and A.store.get(bea).lastKnown.level.value==42)

units.nameplate9={name="Cia North",guid=ciaGuid}
-- Removal during metadata invalidates ownership before the next field read.
local levelReads=0
e.UnitClass=function(unit) leave(unit); return unitClass(unit) end
e.UnitLevel=function(unit) levelReads=levelReads+1; return unitLevel(unit) end
enter("nameplate9")
assert(levelReads==0 and not item(cia).presence)
e.UnitClass,e.UnitLevel=unitClass,unitLevel
-- Turn Off while a read is in flight, then re-enable. The old reader stays retired.
e.UnitGUID=function(unit)
    assert(A.setAutomaticNameplates(false)); assert(A.setAutomaticNameplates(true))
    return guid(unit)
end
enter("nameplate9")
assert(not item(cia).presence)
e.UnitGUID=guid
enter("nameplate9")
assert(item(cia).source=="Nameplate")
local reloadPrefs=e.WhowhoPreviewDB
local p2,s2,e2=H.fresh(root,reloadPrefs,nil,{region=3,time=108,db=e.WhowhoAddressBookDB})
stub(e2); s2:event("ADDON_LOADED","WhoWho"); p2.Toggle()
p2.Shell.nav.settings:Click()
p2.Shell.settingsTabs.general:Click()
assert(p2.Shell.automaticNameplates:GetChecked() and not p2.Shell.nameplateNotice)
assert(subscribed(s2,"NAME_PLATE_UNIT_ADDED") and subscribed(s2,"NAME_PLATE_UNIT_REMOVED"))
enter("nameplate4")
assert(item(dax).presence=="Seen")
config.time=406
assert(A.refreshSightingAge() and not item(dax).presence and item(dax).source=="Nameplate")
config.time=106
assert(A.setAutomaticNameplates(false))
assert(not item(cia).presence and item(ari).source=="Target" and item(bea).source=="Mouseover")

-- An enable failure rolls back partial event registration and preserves the saved preference.
local p3,s3,e3=H.fresh(root,e2.WhowhoPreviewDB,nil,{region=3,time=110,db=e.WhowhoAddressBookDB})
stub(e3)
local loader
for _,frame in ipairs(s3.nodes) do if frame.events.ADDON_LOADED then loader=frame end end
local register=loader.RegisterEvent
loader.RegisterEvent=function(self,event)
    if event=="NAME_PLATE_UNIT_REMOVED" then return false end
    return register(self,event)
end
s3:event("ADDON_LOADED","WhoWho"); p3.Toggle(); p3.Shell.nav.settings:Click(); p3.Shell.settingsTabs.general:Click()
assert(p3.db.automaticNameplates==true and not p3.manual.automaticNameplatesEnabled(),
    "a failed restore preserves the saved opt-in while leaving the source inactive")
p3.Shell.automaticNameplates:Click()
assert(not p3.Shell.nameplateNotice and not p3.Shell.automaticNameplates:GetChecked())
assert(not subscribed(s3,"NAME_PLATE_UNIT_ADDED") and not subscribed(s3,"NAME_PLATE_UNIT_REMOVED"))
local restored,restoredSession,restoredEnv=H.fresh(root,e3.WhowhoPreviewDB,nil,{region=3,time=112,db=e.WhowhoAddressBookDB})
stub(restoredEnv)
restoredSession:event("ADDON_LOADED","WhoWho")
assert(restored.manual.automaticNameplatesEnabled() and subscribed(restoredSession,"NAME_PLATE_UNIT_ADDED")
    and subscribed(restoredSession,"NAME_PLATE_UNIT_REMOVED"),"the next supported session restores the saved opt-in")
local off={automaticTarget=false,automaticMouseover=false,automaticNameplates=false,relogRefresh=false}
local p4,s4,e4=H.fresh(root,off,nil,{region=3,time=110})
local friendsLoader
for _,frame in ipairs(s4.nodes) do if frame.events.ADDON_LOADED then friendsLoader=frame end end
stub(e4); s4:event("ADDON_LOADED","WhoWho")
assert(p4.db.automaticTarget==false and p4.db.automaticMouseover==false and p4.db.relogRefresh==false)
assert(p4.db.automaticNameplates==false and not p4.manual.automaticNameplatesEnabled())
assert(not subscribed(s4,"NAME_PLATE_UNIT_ADDED") and not subscribed(s4,"NAME_PLATE_UNIT_REMOVED"))
-- Blacklist has its own passive observer independent of the Friends preferences.
assert(not friendsLoader.events.PLAYER_TARGET_CHANGED and not friendsLoader.events.UPDATE_MOUSEOVER_UNIT
    and not friendsLoader.events.PLAYER_ENTERING_WORLD)
local p5,s5=H.fresh(root,nil,nil,{region=3,time=114})
s5:event("ADDON_LOADED","WhoWho"); p5.Toggle(); p5.Shell.nav.settings:Click(); p5.Shell.settingsTabs.general:Click()
assert(not p5.manual.automaticNameplatesEnabled() and p5.db.automaticNameplates==nil)
assert(not p5.Shell.automaticNameplates:IsEnabled() and hasText(p5.Shell.automaticNameplates,"Nameplates unavailable."))
assert(p5.manual.automaticTargetEnabled() and p5.manual.automaticMouseoverEnabled())

-- A removal during the initial enumeration retires the staged frame.
local p6,s6,e6=H.fresh(root,nil,nil,{region=3,time=115,db=e.WhowhoAddressBookDB})
stub(e6)
local stagedFrame=plateFrame("nameplate9")
stagedFrame.GetUnit=function()
    s6:event("NAME_PLATE_UNIT_REMOVED","nameplate9")
    return "nameplate9"
end
availablePlates={stagedFrame}
s6:event("ADDON_LOADED","WhoWho")
assert(p6.manual.automaticNameplatesEnabled())
for _,record in ipairs(p6.manual.records) do
    if record.id==cia then assert(not record.presence) end
end
assert(s.forbiddenCalls+s2.forbiddenCalls+s3.forbiddenCalls+s5.forbiddenCalls+s6.forbiddenCalls==0)
print("RESULT shared visible nameplate settings and both-faction Friends sightings passed in simulation")
