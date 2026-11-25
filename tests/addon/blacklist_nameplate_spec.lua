-- Simulated Forever units, frames and ordinary plate events.
local root=arg[1] or "."
local H=dofile(root.."/tests/addon/harness.lua")
local unpack=table.unpack or unpack
local count=0
local function check(value,message)
    assert(value,message)
    count=count+1
end

local ally,hostile="Ari Creek","Bram Valley"
local allyGuid,hostileGuid="Player-701-00000001","Player-701-00000002"
local addEvent,removeEvent="NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED"

local function fresh(options)
    options=options or {}
    local config={region=3,time=100,db=options.db}
    local p,s,e=H.fresh(root,options.preferences,{484,800},config)
    local A,B=p.manual,p.BlacklistBanner
    local units,frames={},{}
    local sounds,reads=0,0
    local restrictedTable,instance
    e.WhowhoEncounterDB=options.history
    e.GetTime=function() return config.time end
    e.GetServerTime=function() return math.floor(config.time) end
    e.GetRealZoneText=function() return "The Barrens" end
    e.IsInInstance=function() return instance~=nil,instance end
    e.UnitExists=function(unit) return units[unit]~=nil end
    e.UnitIsPlayer=function(unit) return units[unit]~=nil and units[unit].player~=false end
    e.UnitIsUnit=function(unit) return unit=="player" end
    e.GetUnitName=function(unit) reads=reads+1; return units[unit].name end
    e.UnitGUID=function(unit) reads=reads+1; return units[unit].guid end
    e.UnitClass=function() return nil,"MAGE" end
    e.UnitFactionGroup=function(unit) return units[unit] and units[unit].faction end
    e.InCombatLockdown=function() return false end
    e.C_Secrets.ShouldUnitIdentityBeSecret=function(unit) return units[unit] and units[unit].restricted==true or false end
    e.C_Sound={PlaySoundWithOptions=function() sounds=sounds+1; return true end}
    e.C_NamePlate={
        GetNamePlateForUnit=function(unit,includeForbidden)
            assert(includeForbidden==false)
            return frames[unit]
        end,
        GetNamePlates=function() return frames end,
    }
    function s:plate(token,name,guid,faction,flags)
        flags=flags or {}
        units[token]={name=name,guid=guid,faction=faction,player=flags.player,restricted=flags.restricted}
        local frame={
            IsVisible=function() return not flags.hidden end,
            IsForbidden=function() return flags.forbidden==true end,
            GetUnit=function() return token end,
        }
        if flags.secretFrame then
            frame=setmetatable({}, {__index=function() error("restricted nameplate indexed") end})
            restrictedTable=frame
        end
        frames[token]=frame
        if not flags.noEvent then self:event(addEvent,token) end
        return frame
    end
    function s:removePlate(token)
        units[token],frames[token]=nil,nil
        self:event(removeEvent,token)
    end
    function s:unit(token,name,guid,faction)
        units[token]=name and {name=name,guid=guid,faction=faction} or nil
        self:event(token=="target" and "PLAYER_TARGET_CHANGED" or "UPDATE_MOUSEOVER_UNIT")
    end
    function s:add(name,guid)
        local record=assert(A.store.add({fullName=name,guid=guid,region=3,identityState="resolved",
            membership="blacklist",reasonIds={"other"}},100))
        A.refresh()
        return record
    end
    function s:tick(seconds)
        config.time=config.time+seconds
        local onUpdate=self.observer:GetScript("OnUpdate")
        if onUpdate then onUpdate(self.observer,seconds) end
    end
    function s:groups()
        return A.encounterLedger.groups(3,config.time)
    end
    function s:live()
        return e.WhowhoBlacklistLiveBanner and e.WhowhoBlacklistLiveBanner:IsShown()
    end
    local secretTable=e.issecrettable
    e.issecrettable=function(value) return rawequal(value,restrictedTable) or secretTable(value) end
    if options.unsupportedEvent then
        for _,frame in ipairs(s.nodes) do
            if frame.events.ADDON_LOADED then
                local register=frame.RegisterEvent
                frame.RegisterEvent=function(self,event)
                    if event==options.unsupportedEvent then return false end
                    return register(self,event)
                end
            end
        end
    end
    for _,plate in ipairs(options.plates or {}) do s:plate(unpack(plate)) end
    s:event("ADDON_LOADED","WhoWho")
    for _,frame in ipairs(s.nodes) do
        if frame.events.PLAYER_LEAVING_WORLD and frame.parent==e.UIParent then s.observer=frame end
    end
    s.B,s.A,s.e=B,A,e
    s.sounds=function() return sounds end
    s.reads=function() return reads end
    s.region=function(region) config.region=region end
    s.instance=function(kind) instance=kind end
    s.units=units
    return s
end

do
    local s=fresh()
    local opposite=s:add(hostile,hostileGuid)
    local friendly=s:add(ally,allyGuid)
    s:plate("nameplate1",hostile,hostileGuid,"Horde")
    check(s:live() and s.sounds()==1,"ordinary opposite-faction plate warns with no target or mouseover")
    s:plate("nameplate2",ally,allyGuid,"Alliance")
    s:tick(8.5)
    check(s:live() and s.sounds()==2,"ordinary same-faction plate follows the same warning path")
    check(#s:groups()==2 and s:groups()[1].row.nameplate==true and not s:groups()[1].row.target
        and not s:groups()[1].row.mouseover,"the ledger preserves nameplate-only provenance")
    local known=s.A.store.get(opposite.id).lastKnown
    check(known.class.source=="Nameplate" and known.faction.value=="Horde"
        and s.A.store.get(friendly.id).lastKnown.faction.value=="Alliance","both factions save exact metadata")
    s:event("PLAYER_LEAVING_WORLD")
    local reopened=fresh({db=s.A.store.export(),history=s.e.WhowhoEncounterDB})
    check(#reopened:groups()==2 and reopened:groups()[1].row.nameplate
        and reopened.A.store.get(opposite.id).lastKnown.class.source=="Nameplate",
        "plate-only encounters and metadata reopen")
end

do
    local s=fresh()
    local primary=s:add(ally,allyGuid)
    local second=s:add(hostile,hostileGuid)
    local thirdName,thirdGuid="Cora Grove","Player-701-00000003"
    local third=s:add(thirdName,thirdGuid)
    s:unit("target",ally,allyGuid,"Alliance")
    s:plate("nameplate1",ally,allyGuid,"Alliance")
    s:plate("nameplate2",hostile,hostileGuid,"Horde")
    s:plate("nameplate3",thirdName,thirdGuid,"Alliance")
    s:tick(.25)
    local live=s.e.WhowhoBlacklistLiveBanner
    check(live.transition and not live.more:IsShown(),
        "same-poll plate arrivals are accepted together before painting")
    s:tick(.18)
    check(live.more:GetText()=="+2 more" and live.character:GetText()==ally and s.sounds()==1,
        "the first painted count includes both new plates and skips the duplicate target plate")
    local found={}
    for _,group in ipairs(s:groups()) do found[group.row.playerId]=group.row end
    check(#s:groups()==3 and found[primary.id].target and found[primary.id].nameplate
        and found[second.id].nameplate and found[third.id].nameplate,
        "batched arrivals retain their three independent encounter ledgers")
end

do
    local s=fresh()
    s:add(ally,allyGuid)
    s:plate("nameplate1",ally,allyGuid,"Alliance")
    s:unit("target",ally,allyGuid,"Alliance")
    s:unit("mouseover",ally,allyGuid,"Alliance")
    s:plate("nameplate2",ally,allyGuid,"Alliance")
    s:removePlate("nameplate1")
    s:unit("target")
    s:unit("mouseover")
    s:tick(31)
    local row=s:groups()[1].row
    check(s.sounds()==1 and row.target and row.mouseover and row.nameplate
        and s.e.WhowhoEncounterDB.nextId==2,"overlapping and multiple plates preserve one physical episode")
    s:removePlate("nameplate2")
    s:tick(4)
    s:plate("nameplate2",ally,allyGuid,"Alliance")
    check(s.sounds()==1 and s.e.WhowhoEncounterDB.nextId==2,"short plate loss does not rearm a warning")
    s:removePlate("nameplate2")
    s:tick(5)
    s:plate("nameplate3",ally,allyGuid,"Alliance")
    check(s.sounds()==2 and s.e.WhowhoEncounterDB.nextId==3,"complete absence past cooldown permits a new episode")
    s:removePlate("nameplate3")
    s:tick(5)
    s:plate("nameplate4",ally,allyGuid,"Alliance")
    check(s.sounds()==2,"the same cooldown applies to a returning nameplate")
end

do
    local s=fresh()
    s:plate("nameplate1",ally,allyGuid,"Alliance")
    check(not s.observer:GetScript("OnUpdate") and not s:live(),"unmatched plates leave the observer idle")
    local before=s.reads()
    s:tick(10)
    check(s.reads()==before,"unmatched plates never poll identities")
    local record=s:add(ally,allyGuid)
    check(s:live() and s.A.store.get(record.id).lastKnown.guid==allyGuid,"a later matching book entry sees the owned plate")
end

do
    local s=fresh()
    s:add(ally,allyGuid)
    local reopened=fresh({db=s.A.store.export(),plates={{"nameplate1",ally,allyGuid,"Alliance"}}})
    check(reopened:live(),"enabling the default setting seeds a currently visible ordinary plate")
    local disabled=fresh({db=s.A.store.export(),preferences={automaticNameplates=false},
        plates={{"nameplate1",ally,allyGuid,"Alliance"}}})
    check(not disabled:live(),"the saved off setting leaves existing plates alone")
    disabled.A.setAutomaticNameplates(true)
    check(disabled:live(),"turning the setting on seeds currently visible plates")
    disabled.A.setAutomaticNameplates(false)
    disabled:tick(10)
    disabled:plate("nameplate2",ally,allyGuid,"Alliance")
    disabled:unit("target",ally,allyGuid,"Alliance")
    check(disabled.sounds()==1 and disabled:groups()[1].row.target,"turning it off preserves target observations")
end

do
    local s=fresh()
    s:add(ally,allyGuid)
    local before=s.reads()
    s:plate("nameplate1",ally,allyGuid,"Alliance",{forbidden=true})
    s:plate("nameplate2",ally,allyGuid,"Alliance",{restricted=true})
    s:plate("nameplate3",ally,allyGuid,"Alliance",{secretFrame=true})
    s:plate("nameplate4",ally,allyGuid,"Alliance",{player=false})
    s:plate("nameplate5",ally,allyGuid,"Alliance",{hidden=true})
    s:plate("nameplate0",ally,allyGuid,"Alliance")
    s:plate("nameplatejunk",ally,allyGuid,"Alliance")
    s:event("FORBIDDEN_NAME_PLATE_UNIT_ADDED","nameplate5")
    check(s.reads()==before and not s:live(),"forbidden, restricted, NPC, hidden or malformed plates skip identity reads")
    s:plate("nameplate6","Ari",allyGuid,"Alliance")
    s:plate("nameplate7",ally,"Creature-701-00000001","Alliance")
    check(#s:groups()==0,"one-part names and malformed player GUIDs do not resolve")
    s:region(2)
    s:plate("nameplate9",ally,allyGuid,"Alliance")
    check(#s:groups()==0,"a plate cannot create a sighting outside the validated region")
end

do
    local s=fresh()
    s:add(ally,allyGuid)
    s:add(hostile,hostileGuid)
    local flags={}
    s:plate("nameplate1",ally,allyGuid,"Alliance",flags)
    flags.forbidden=true
    s:tick(31)
    flags.forbidden=false
    s:tick(1)
    check(s.sounds()==1,"a temporary forbidden frame never rearms a continuous plate warning")
    s.units.nameplate1={name=hostile,guid=hostileGuid,faction="Horde"}
    s:tick(1)
    check(s.sounds()==1 and #s:groups()==1,"silent token recycling cannot introduce a different saved player")
    s.units.nameplate1={name=ally,guid=allyGuid,faction="Alliance"}
    s:tick(5)
    s:unit("target")
    check(s.sounds()==1 and s.e.WhowhoEncounterDB.nextId==2,
        "a recycled token cannot restore its old lease without a fresh entrance")
    s:plate("nameplate1",ally,hostileGuid,"Horde")
    check(s.sounds()==1 and #s:groups()==1,"a fresh token with the same name and another GUID cannot match")
    s:plate("nameplate1",hostile,hostileGuid,"Horde")
    check(s.sounds()==2 and #s:groups()==2,"a valid later entrance owns its new token generation")
end

do
    local s=fresh()
    s:add(ally,allyGuid)
    local hostileRecord=s:add(hostile,hostileGuid)
    s:plate("nameplate1",ally,allyGuid,"Alliance")
    s:plate("nameplate2",hostile,hostileGuid,"Horde")
    s:removePlate("nameplate2")
    s:tick(8.5)
    check(s.sounds()==1 and not s:live(),"a removed plate cannot appear from the pending warning queue")
    local zone=s.e.GetRealZoneText
    s.e.GetRealZoneText=function()
        s.e.GetRealZoneText=zone
        s:removePlate("nameplate3")
        return zone()
    end
    local nextID=s.e.WhowhoEncounterDB.nextId
    s:plate("nameplate3",hostile,hostileGuid,"Horde")
    s:tick(1)
    check(s.e.WhowhoEncounterDB.nextId==nextID and s.sounds()==1,
        "an ordinary removal during zone lookup cancels the stale sighting")
    check(s.A.store.get(hostileRecord.id).lastKnown.guid==hostileGuid,
        "the first valid observation retained correct metadata")
end

do
    local s=fresh()
    local record=s:add(ally,allyGuid)
    local show=s.B.showLive
    s.B.showLive=function(...)
        s.B.showLive=show
        s:removePlate("nameplate1")
        return show(...)
    end
    s:plate("nameplate1",ally,allyGuid,"Alliance")
    check(not s:live() and s.sounds()==0 and not s.A.store.get(record.id).lastKnown,
        "removal during presentation cancels stale warning, audio and metadata")
end

do
    local s=fresh({unsupportedEvent=removeEvent})
    s:add(ally,allyGuid)
    s:plate("nameplate1",ally,allyGuid,"Alliance")
    check(not s:live(),"a missing removal subscription disables the plate source")
    s:unit("target",ally,allyGuid,"Alliance")
    check(s:live() and s.sounds()==1,"partial plate registration leaves target warnings available")
end

do
    local s=fresh()
    local record=s:add(hostile,hostileGuid)
    local friend=assert(s.A.store.add({fullName=ally,guid=allyGuid,region=3,identityState="resolved",
        membership="friend"},100))
    s.A.refresh()
    local candidateReads=0
    local exists=s.e.UnitExists
    s.e.UnitExists=function(token)
        if token=="targettarget" then candidateReads=candidateReads+1 end
        return exists(token)
    end
    s.e.UnitTokenFromGUID=function()
        candidateReads=candidateReads+1
        return "targettarget"
    end
    s.e.C_AutoComplete={GetAutoCompleteResults=function()
        candidateReads=candidateReads+1
        return {{name=hostile}}
    end}
    s.units.targettarget={name=hostile,guid=hostileGuid,faction="Horde"}
    s:unit("target","Other North","Player-701-00000003","Alliance")
    s:event("UNIT_TARGET","target")
    s.units.targettarget={name=ally,guid=allyGuid,faction="Alliance"}
    s:event("UNIT_TARGET","target")
    s:tick(1)
    check(candidateReads==0 and not s:live() and s.sounds()==0 and #s:groups()==0
        and not s.A.store.get(record.id).lastKnown and not s.A.targetCheck.observations[friend.id],
        "unverified candidate sources stay out of live Friends and Blacklist sightings")
end

do
    local s=fresh()
    s:add(hostile,hostileGuid)
    s.instance("party")
    s:event("ZONE_CHANGED_NEW_AREA")
    local before=s.reads()
    s:plate("nameplate1",hostile,hostileGuid,"Horde",{noEvent=true})
    s.B.sightingsNameplateEvent(addEvent,"nameplate1")
    check(s.reads()==before and not s:live(),"dungeon suppression prevents plate identity reads")
    s.instance(nil)
    s:event("ZONE_CHANGED_NEW_AREA")
    check(s.sounds()==0 and #s:groups()==1,"leaving a dungeon quietly seeds an already present plate")
    s:event("PLAYER_LEAVING_WORLD")
    s:plate("nameplate2",hostile,hostileGuid,"Horde")
    check(s.sounds()==0 and not s:live(),"events during world departure cannot warn")
end

print(("RESULT simulated Blacklist nameplate %d checks passed"):format(count))
