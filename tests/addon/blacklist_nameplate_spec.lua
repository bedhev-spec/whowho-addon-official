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
    local guild=101
    if options.guildRows then
        local scopes=options.guildScopes or {}
        scopes["3:101"]=options.guildRows
        e.WhowhoGuildBlacklistDB={version=1,scopes=scopes}
        e.IsInGuild=function() return guild~=false end
        e.C_Club={GetGuildClubId=function() return guild end}
        e.C_ChatInfo={}
        e.C_Timer={}
    end
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
    if options.guildRows then s:event("PLAYER_ENTERING_WORLD") end
    for _,frame in ipairs(s.nodes) do
        if frame.events.PLAYER_LEAVING_WORLD and frame.parent==e.UIParent then s.observer=frame end
    end
    s.B,s.A,s.e=B,A,e
    s.sounds=function() return sounds end
    s.reads=function() return reads end
    s.region=function(region) config.region=region end
    s.instance=function(kind) instance=kind end
    s.guild=function(club)
        guild=club
        s:event("PLAYER_GUILD_UPDATE","player")
    end
    s.units=units
    return s
end

for _,source in ipairs({"target","mouseover","nameplate","party","raid"}) do
    local s=fresh({guildRows={["ari creek"]={rev=0,reasonIds={"griefing"}}}})
    local e=s.e
    if source=="nameplate" then
        s:plate("nameplate1",ally,allyGuid,"Alliance")
    elseif source=="party" or source=="raid" then
        e.IsInRaid=function() return source=="raid" end
        e.GetNumGroupMembers=function() return 1 end
        e.GetNumSubgroupMembers=function() return 1 end
        s.units[source.."1"]={name=ally,guid=allyGuid,faction="Alliance"}
        s:event("GROUP_ROSTER_UPDATE")
    else
        s:unit(source,ally,allyGuid,"Alliance")
    end
    local live=e.WhowhoBlacklistLiveBanner
    check(s:live() and live.character:GetText()==ally and live.reasons:GetText()=="Guild Blacklist · Griefing"
        and s.sounds()==1,source.." uses a guild-only match and shows its source and reasons")
    s:unit("target",ally,allyGuid,"Alliance")
    check(s.sounds()==1 and not live.more:IsShown() and #s:groups()==0,
        source.." deduplicates and keeps guild-only alerts out of personal history")
end

do
    local s=fresh({guildRows={[ally]={rev=0,reasonIds={"griefing"}}}})
    s:add(ally,allyGuid)
    s:plate("nameplate1",ally,allyGuid,"Alliance")
    s:unit("mouseover",ally,allyGuid,"Alliance")
    local live=s.e.WhowhoBlacklistLiveBanner
    check(s:live() and live.reasons:GetText()=="Other" and s.sounds()==1,
        "a personal match wins over the guild reason and alerts once")
    check(#s:groups()==1,"the personal encounter is recorded when both lists match")
end

do
    local s=fresh({guildRows={[ally]={rev=0},[hostile]={rev=0}}})
    s:unit("target",ally,allyGuid,"Alliance")
    local live=s.e.WhowhoBlacklistLiveBanner
    check(s:live() and live.reasons:GetText()=="Guild Blacklist","older guild rows without reasons still alert")
    s:unit("mouseover",hostile,hostileGuid,"Horde")
    s:tick(.25)
    s.guild(false)
    s:tick(.25)
    check(not s:live() and s.sounds()==1,"leaving the guild cancels live and queued guild alerts")
end

do
    local s=fresh({guildRows={},guildScopes={["3:102"]={[ally]={rev=0}}}})
    s:plate("nameplate1",ally,allyGuid,"Alliance")
    check(not s:live(),"a cached row from another guild cannot alert")
    s.guild(102)
    check(s:live() and s.sounds()==1,"a settled guild switch reevaluates a visible plate in the new guild")
end

do
    local s=fresh({guildRows={[hostile]={rev=0}}})
    s:add(ally,allyGuid)
    s:unit("target",ally,allyGuid,"Alliance")
    s:unit("mouseover",hostile,hostileGuid,"Horde")
    local live=s.e.WhowhoBlacklistLiveBanner
    s:tick(.25)
    s.guild(false)
    s:tick(.18)
    check(s:live() and live.character:GetText()==ally and not live.more:IsShown(),
        "losing guild access before paint drops the guild-only count from a personal banner")
end

for _,source in ipairs({"target","nameplate"}) do
    local s=fresh({guildRows={[ally]={rev=0}}})
    local function seePlayer()
        if source=="target" then s:unit("target",ally,allyGuid,"Alliance")
        else s:plate("nameplate1",ally,allyGuid,"Alliance") end
    end
    seePlayer()
    check(s:live() and s.sounds()==1,source.." alerts once for the guild member's first sighting")
    for _=1,3 do
        s:tick(31)
        local nativeClub=s.e.C_Club.GetGuildClubId
        s.e.C_Club.GetGuildClubId=function() return nil end
        s:event("INITIAL_CLUBS_LOADED")
        s:tick(6)
        s.e.C_Club.GetGuildClubId=nativeClub
        s:event("INITIAL_CLUBS_LOADED")
        check(not s:live() and s.sounds()==1,
            source.." keeps a handled sighting across unavailable guild data and a new read lease")
    end
    if source=="target" then s:unit("target",nil)
    else s:removePlate("nameplate1") end
    s:tick(6)
    seePlayer()
    check(s:live() and s.sounds()==2,source.." alerts again after a confirmed new sighting")
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

-- Plates are not read while nothing is listed, and must not be lost by that.
do
    local s=fresh({plates={{"nameplate1",ally,allyGuid,"Alliance"}}})
    check(s.reads()==0 and not s:live(),"a seeded plate is not read while nothing is listed")
    s:add(ally,allyGuid)
    check(s:live() and s.sounds()==1,"a plate on screen at login alerts once its player is listed")
end

for _,list in ipairs({"missing","unreadable"}) do
    local s=fresh()
    local frames=s.e.C_NamePlate.GetNamePlates
    s.e.C_NamePlate.GetNamePlates=list=="unreadable" and function() return nil end or nil
    s:plate("nameplate1",ally,allyGuid,"Alliance")
    s:add(ally,allyGuid)
    check(s:live() and s.sounds()==1,"a plate seen by its event needs no plate list: "..list)
    s.e.C_NamePlate.GetNamePlates=frames
end

do
    local s=fresh()
    s:plate("nameplate1",ally,allyGuid,"Alliance")
    s:removePlate("nameplate1")
    local before=s.reads()
    s:add(ally,allyGuid)
    check(s.reads()==before and not s:live(),"a removed plate is not read once its player is listed")
end

do
    local s=fresh()
    local record=s:add(hostile,hostileGuid)
    s:unit("target",nil)
    assert(s.A.delete(record))
    s:plate("nameplate1",ally,allyGuid,"Alliance",{restricted=true})
    s:add(ally,allyGuid)
    s.units.nameplate1.restricted=false
    for _=1,20 do s:tick(1) end
    check(s.sounds()==1,"a skipped plate that cannot be read yet is retried")
end

-- Unsettled guild membership cannot show that no list needs the plates.
do
    local s=fresh()
    s.e.IsInGuild=function() return true end
    s:plate("nameplate1",ally,allyGuid,"Alliance")
    check(s.reads()>0,"plates are read while guild membership is unsettled")
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
    check(s.sounds()==1 and #s:groups()==1,"leaving a dungeon alerts for a plate never alerted before")
    s:event("PLAYER_LEAVING_WORLD")
    s:plate("nameplate2",hostile,hostileGuid,"Horde")
    check(s.sounds()==1 and not s:live(),"events during world departure cannot warn")
end

local function polling(s) return s.observer:GetScript("OnUpdate")~=nil end

local function grouped(s)
    s.e.IsInRaid=function() return false end
    s.e.GetNumSubgroupMembers=function() return 1 end
end

for _,case in ipairs({
    {source="party",late="name"},
    {source="party",late="secrecy"},
    {source="target",late="secrecy"},
    {source="nameplate",late="name"},
    {source="nameplate",late="secrecy"},
}) do
    local s=fresh()
    s:add(hostile,hostileGuid)
    local label=case.source.." late "..case.late
    local unit={name=case.late=="name" and "Bram" or hostile,guid=hostileGuid,faction="Horde",
        restricted=case.late=="secrecy"}
    local token=case.source=="party" and "party1" or case.source=="nameplate" and "nameplate1" or "target"
    if case.source=="nameplate" then
        s:plate(token,unit.name,hostileGuid,"Horde",{restricted=unit.restricted})
        unit=s.units[token]
    else
        s.units[token]=unit
        if case.source=="party" then grouped(s) end
        s:event(case.source=="party" and "GROUP_ROSTER_UPDATE" or "PLAYER_TARGET_CHANGED")
    end
    for _=1,5 do s:tick(1) end
    check(not s:live() and polling(s),label..": the unreadable unit stays under observation")
    unit.name,unit.restricted=hostile,false
    s:tick(10)
    check(s:live() and s.sounds()==1,label..": alerts without another event")
end

do
    local s=fresh()
    s:add(hostile,hostileGuid)
    s:plate("nameplate1","Bram",hostileGuid,"Horde")
    check(polling(s),"an unreadable plate is retried")
    s:removePlate("nameplate1")
    s:tick(1)
    check(not polling(s) and not s:live(),"removing the unreadable plate stops the retry")
    s:plate("nameplate1","A Boar","Creature-1","Horde",{player=false})
    check(not polling(s),"a non-player plate is never retried")
    s:unit("target",ally,allyGuid,"Alliance")
    check(not polling(s),"a readable unlisted unit needs no retry")
end

do
    local s=fresh()
    s:add(hostile,hostileGuid)
    s:plate("nameplate1","Bram",hostileGuid,"Horde")
    s.instance("party")
    s:event("ZONE_CHANGED_NEW_AREA")
    s:tick(1)
    check(not polling(s),"a dungeon stops the retry")
end

-- Group joins are tracked by GUID, independently of the Blacklist.
local function party()
    local s=fresh()
    local size=0
    s.e.IsInRaid=function() return false end
    s.e.GetNumSubgroupMembers=function() return size end
    function s:members(...)
        size=select("#",...)
        for i=1,4 do self.units["party"..i]=nil end
        for i=1,size do
            local name=select(i,...)
            self.units["party"..i]={name=name,guid=name==hostile and hostileGuid or allyGuid,faction="Horde"}
        end
        self:event("GROUP_ROSTER_UPDATE")
    end
    function s:wait(seconds) for _=1,seconds do self:tick(1) end end
    return s
end

do
    local s=party()
    s:add(hostile,hostileGuid)
    s:members()
    s:unit("target",hostile,hostileGuid,"Horde")
    s:unit("target")
    s:wait(10)
    s:members(hostile)
    s:wait(1)
    check(s.sounds()==2,"joining during the cooldown alerts again")
    s:wait(10)
    s:members()
    s:wait(6)
    s:members(hostile)
    s:wait(2)
    check(s.sounds()==2,"only one join bypasses the cooldown per 30 seconds")
    s:members()
    s:wait(40)
    s:members(hostile)
    check(s.sounds()==3,"a later rejoin alerts")
    s:wait(10)
    s.units.party1.name="Bram"
    s:event("GROUP_ROSTER_UPDATE")
    s:wait(40)
    s.units.party1.name=hostile
    s:wait(2)
    check(s.sounds()==3,"an unreadable member has not left")
end

do
    local s=party()
    s:members(hostile)
    assert(s.B.deferNewBlacklist(s:add(hostile,hostileGuid),s.A.store))
    s:event("GROUP_ROSTER_UPDATE")
    s:wait(2)
    check(s.sounds()==0,"blacklisting a current member is not a join")
end

do
    local s=party()
    s:members()
    assert(s.B.deferNewBlacklist(s:add(hostile,hostileGuid),s.A.store))
    s:members(hostile)
    check(s.sounds()==1,"a join inside the new-entry cooldown alerts")
end

do
    local s=party()
    s:add(hostile,hostileGuid)
    s:members(hostile)
    s:wait(40)
    s.instance("party")
    s:event("PLAYER_LEAVING_WORLD")
    s:event("PLAYER_ENTERING_WORLD")
    s:wait(40)
    s.instance(nil)
    s.units.party1.name="Bram"
    s:event("PLAYER_LEAVING_WORLD")
    s:event("PLAYER_ENTERING_WORLD")
    s:wait(2)
    s.units.party1.name=hostile
    s:wait(2)
    check(s.sounds()==1,"a late-readable member is not alerted again after an instance")
end

do
    local s=fresh()
    s:add(hostile,hostileGuid)
    s:unit("target",hostile,hostileGuid,"Horde")
    s:event("PLAYER_LEAVING_WORLD")
    s.units.target=nil
    s:event("PLAYER_ENTERING_WORLD")
    for _=1,40 do s:tick(1) end
    s:unit("target",hostile,hostileGuid,"Horde")
    check(s.sounds()==2,"an ordinary loading screen does not mute a later sighting")
end

do
    local s=party()
    s:add(hostile,hostileGuid)
    s:members()
    s:members(hostile)
    s:wait(10)
    s:members()
    s:wait(6)
    s:members(hostile)
    check(s.sounds()==2,"a join without a cooldown keeps the bypass for the rejoin")
end

do
    local s=party()
    s:members(ally)
    local before=s.reads()
    s:unit("target")
    check(s.reads()==before,"a target change does not re-read the group")
end

do
    local s=fresh()
    s:plate("nameplate1","Bram",hostileGuid,"Horde")
    s:add(hostile,hostileGuid)
    check(polling(s),"the first list entry starts retrying an unreadable plate")
    s.units.nameplate1.name=hostile
    s:tick(3)
    check(s.sounds()==1,"the retried plate alerts")
end

do
    local s=fresh()
    s.B.sightingsNameplatesChanged(false)
    s:add(hostile,hostileGuid)
    s:plate("nameplate1","Bram",hostileGuid,"Horde",{noEvent=true})
    s:tick(1)
    s.B.sightingsNameplatesChanged(true)
    check(polling(s),"enabling nameplates starts retrying an unreadable plate")
    s.units.nameplate1.name=hostile
    s:tick(3)
    check(s.sounds()==1,"a plate retried after enabling alerts")
end

-- A member without a readable name must not hide other members' leaves.
for _,hiding in ipairs({"name","secrecy"}) do
    local s=party()
    s:members()
    assert(s.B.deferNewBlacklist(s:add(hostile,hostileGuid),s.A.store))
    s:members(ally,hostile)
    s:wait(40)
    if hiding=="name" then s.units.party1.name="Ari" else s.units.party1.restricted=true end
    s:event("GROUP_ROSTER_UPDATE")
    s.units.party2=nil
    s.e.GetNumSubgroupMembers=function() return 1 end
    s:event("GROUP_ROSTER_UPDATE")
    s:wait(40)
    s.units.party2={name=hostile,guid=hostileGuid,faction="Horde"}
    s.e.GetNumSubgroupMembers=function() return 2 end
    s:event("GROUP_ROSTER_UPDATE")
    check(s.sounds()==2,"a rejoin alerts while another member hides its "..hiding)
end

do
    local s=party()
    assert(s.B.deferNewBlacklist(s:add(hostile,hostileGuid),s.A.store))
    s.units.party1={name="Ari",guid=allyGuid}
    s.e.GetNumSubgroupMembers=function() return 1 end
    s:event("GROUP_ROSTER_UPDATE")
    s.units.party2={name=hostile,guid=hostileGuid}
    s.e.GetNumSubgroupMembers=function() return 2 end
    s:event("GROUP_ROSTER_UPDATE")
    check(s.sounds()==1,"a join is seen although the first roster had an unreadable name")
end

do
    local s=party()
    s:members()
    s.units.party1={name="Bram",guid=hostileGuid}
    s.e.GetNumSubgroupMembers=function() return 1 end
    s:event("GROUP_ROSTER_UPDATE")
    assert(s.B.deferNewBlacklist(s:add(hostile,hostileGuid),s.A.store))
    s.units.party1.name=hostile
    s:event("GROUP_ROSTER_UPDATE")
    s:wait(2)
    check(s.sounds()==0,"a member who joined before any list entry is not a join when blacklisted")
end

do
    local s=party()
    s:members()
    assert(s.B.deferNewBlacklist(s:add(hostile,hostileGuid),s.A.store))
    s.e.UIParent:Hide()
    s:members(hostile)
    s:event("PLAYER_LEAVING_WORLD")
    s.e.UIParent:Show()
    s:event("PLAYER_ENTERING_WORLD")
    s:wait(2)
    check(s.sounds()==1,"an unshown join alert survives a loading screen")
end

do
    local s=party()
    s:add(ally,allyGuid)
    s:members()
    s:members(hostile)
    assert(s.B.deferNewBlacklist(s:add(hostile,hostileGuid),s.A.store))
    s:event("GROUP_ROSTER_UPDATE")
    s:wait(2)
    check(s.sounds()==0,"an unlisted member's join is dismissed before they are listed")
end

do
    local s=party()
    s:members()
    assert(s.B.deferNewBlacklist(s:add(hostile,hostileGuid),s.A.store))
    s.units.party1={name=hostile,guid=hostileGuid,player=false}
    s.e.GetNumSubgroupMembers=function() return 1 end
    s:event("GROUP_ROSTER_UPDATE")
    s.units.party1.player=true
    s:wait(2)
    check(s.sounds()==1,"a join is kept until the member reads as a player")
end

do
    local s=party()
    s:members()
    assert(s.B.deferNewBlacklist(s:add(hostile,hostileGuid),s.A.store))
    s.e.UIParent:Hide()
    s:members(hostile)
    s:members()
    s:wait(6)
    s.e.UIParent:Show()
    s:members(hostile)
    s:wait(2)
    check(s.sounds()==1,"an unshown join does not spend the bypass")
end

do
    local s=party()
    s:add(hostile,hostileGuid)
    s:members()
    s.units.party1={name=hostile,guid=hostileGuid,faction="Horde"}
    s.e.GetNumSubgroupMembers=function() return 1 end
    s:event("PLAYER_TARGET_CHANGED")
    s:event("GROUP_ROSTER_UPDATE")
    s:wait(10)
    check(s.sounds()==1,"a roster read before its event does not alert twice")
end

do
    local s=fresh()
    s:add(hostile,hostileGuid)
    local later=0
    local now=s.e.GetTime
    s.e.GetTime=function() return now()+later end
    s.e.UIParent:Hide()
    s:unit("target",hostile,hostileGuid,"Horde")
    later=13
    s:event("UPDATE_MOUSEOVER_UNIT")
    s.e.UIParent:Show()
    s:tick(.25)
    s:tick(.25)
    check(s.sounds()==1,"an alert expired by a hidden event is queued again")
end

do
    local s=fresh()
    s:add(hostile,hostileGuid)
    local shows=0
    s.B.showLive=function() shows=shows+1; return function() return false end end
    s:unit("target",hostile,hostileGuid,"Horde")
    for _=1,100 do s:tick(.01) end
    check(shows<=6,"a banner that never becomes visible is not retried every frame")
end

local function guilded()
    local s=fresh({guildRows={["ari creek"]={rev=0,reasonIds={"griefing"}}}})
    local timers={}
    s.e.C_Timer.After=function(_,fn) timers[#timers+1]=fn end
    function s:settle() local due=timers; timers={}; for _,fn in ipairs(due) do fn() end end
    return s
end

do
    local s=guilded()
    s:unit("target",ally,allyGuid,"Alliance")
    s:unit("target")
    s:event("PLAYER_GUILD_UPDATE","player")
    check(s:live(),"an unsettled guild membership keeps the visible Guild banner")
    s:settle()
    s:tick(1)
    check(s:live() and s.sounds()==1,"the same Guild keeps its banner without a replay")
    s.guild(false)
    s:settle()
    check(not s:live(),"leaving the guild removes its banner")
end

do
    local s=guilded()
    local club=s.e.C_Club.GetGuildClubId
    s.e.C_Club.GetGuildClubId=function() return nil end
    s:event("PLAYER_GUILD_UPDATE","player")
    s:settle()
    s.e.IsInRaid=function() return false end
    s.e.GetNumSubgroupMembers=function() return 1 end
    s.units.party1={name=ally,guid=allyGuid}
    s:event("GROUP_ROSTER_UPDATE")
    s:settle()
    check(not s:live(),"an unreadable guild cannot alert")
    s.e.C_Club.GetGuildClubId=club
    s:settle()
    check(s:live() and s.sounds()==1,"a late guild ID alerts a listed member without another event")
end

-- A member already grouped when listed has not joined.
do
    local s=party()
    s:members()
    s.instance("party")
    s:event("ZONE_CHANGED_NEW_AREA")
    s:members(hostile)
    assert(s.B.deferNewBlacklist(s:add(hostile,hostileGuid),s.A.store))
    s.instance(nil)
    s:event("ZONE_CHANGED_NEW_AREA")
    s:wait(2)
    check(s.sounds()==0,"a member who joined inside an instance before being listed is not a join")
end

do
    local s=party()
    s:add(ally,allyGuid)
    s:members()
    s.units.party1={name="Bram",guid=hostileGuid}
    s.e.GetNumSubgroupMembers=function() return 1 end
    s:event("GROUP_ROSTER_UPDATE")
    local record=s:add(hostile,hostileGuid)
    record.guid=nil
    assert(s.B.deferNewBlacklist(record,s.A.store))
    s.units.party1.name=hostile
    s:wait(2)
    check(s.sounds()==0,"an unreadable member listed before the name resolves is not a join")
end

do
    local s=party()
    s:members(hostile)
    assert(s.B.deferNewBlacklist(s:add(hostile,hostileGuid),s.A.store))
    s:members()
    s:wait(2)
    s:members(hostile)
    check(s.sounds()==0,"a leave shorter than the grace is not a rejoin")
end

do
    local s=party()
    s:members()
    assert(s.B.deferNewBlacklist(s:add(hostile,hostileGuid),s.A.store))
    s.units.party1={name="Bram",guid=hostileGuid}
    s.e.GetNumSubgroupMembers=function() return 1 end
    s:event("GROUP_ROSTER_UPDATE")
    s.units.party1=nil
    s.e.GetNumSubgroupMembers=function() return 0 end
    s:event("GROUP_ROSTER_UPDATE")
    s:wait(2)
    s.units.party1={name=hostile,guid=hostileGuid}
    s.e.GetNumSubgroupMembers=function() return 1 end
    s:event("GROUP_ROSTER_UPDATE")
    check(s.sounds()==0,"leaving drops a pending join")
end

do
    local s=party()
    s:members()
    assert(s.B.deferNewBlacklist(s:add(hostile,hostileGuid),s.A.store))
    s.units.party1={name=hostile}
    s.e.GetNumSubgroupMembers=function() return 1 end
    s:event("GROUP_ROSTER_UPDATE")
    s:wait(3)
    s.units.party1.guid=hostileGuid
    s:wait(7)
    check(s.sounds()==1,"a GUID read by a retry is still a join")
end

do
    local s=party()
    s:members(hostile)
    assert(s.B.deferNewBlacklist(s:add(hostile,hostileGuid),s.A.store))
    s.units.party1.restricted=true
    s:event("GROUP_ROSTER_UPDATE")
    s:wait(6)
    s.units.party1.restricted=false
    s:event("GROUP_ROSTER_UPDATE")
    s:wait(2)
    check(s.sounds()==0,"a hidden member has not left")
end

do
    local s=party()
    s:members()
    assert(s.B.deferNewBlacklist(s:add(hostile,hostileGuid),s.A.store))
    s:members(hostile)
    s:wait(31)
    s:event("PLAYER_LEAVING_WORLD")
    s:event("PLAYER_ENTERING_WORLD")
    s:wait(2)
    check(s.sounds()==1,"a shown join is not restored by a loading screen")
end

do
    local s=party()
    s:members()
    assert(s.B.deferNewBlacklist(s:add(hostile,hostileGuid),s.A.store))
    assert(s.B.deferNewBlacklist(s:add(ally,allyGuid),s.A.store))
    s:members(hostile,ally)
    s:wait(1)
    s:wait(1)
    check(s.sounds()==1 and s.e.WhowhoBlacklistLiveBanner.more:IsShown(),"joins inside a cooldown share one banner")
    s:members()
    s:wait(6)
    s:members(ally)
    s:wait(12)
    check(s.sounds()==1,"a grouped join banner spends the bypass")
end

do
    local s=fresh()
    s:add(hostile,hostileGuid)
    local flags={hidden=true}
    s:plate("nameplate1",hostile,hostileGuid,"Horde",flags)
    flags.hidden=false
    s:tick(3)
    check(s.sounds()==1,"a plate whose frame appears late alerts")
end

do
    local s=guilded()
    local club=s.e.C_Club.GetGuildClubId
    s.e.C_Club.GetGuildClubId=function() return nil end
    s:event("PLAYER_GUILD_UPDATE","player")
    s:settle()
    s.e.IsInRaid=function() return false end
    s.e.GetNumSubgroupMembers=function() return 1 end
    s.units.party1={name=ally,guid=allyGuid}
    s:event("GROUP_ROSTER_UPDATE")
    s:settle()
    s.e.C_Club.GetGuildClubId=club
    s.e.WhowhoPreview.GuildBlacklist.context()
    s:settle()
    check(s:live() and s.sounds()==1,"a UI read before the retry does not swallow the alert")
end

-- A personal entry keeps the scan running while guild membership is unsettled.
for _,personal in ipairs({false,true}) do
    local s=guilded()
    if personal then s:add(hostile,hostileGuid) end
    local size=0
    s.e.IsInRaid=function() return false end
    s.e.GetNumSubgroupMembers=function() return size end
    s:event("GROUP_ROSTER_UPDATE")
    s:unit("target",ally,allyGuid,"Alliance")
    s:unit("target")
    for _=1,10 do s:tick(1) end
    s:event("PLAYER_GUILD_UPDATE","player")
    size=1
    s.units.party1={name=ally,guid=allyGuid}
    s:event("GROUP_ROSTER_UPDATE")
    s:settle()
    for _=1,2 do s:tick(1) end
    check(s.sounds()==2,"a Guild-listed join survives unsettled membership")
end

-- An unreadable unit is retried after 3, 6, 12, 24, 48 and 84 seconds, then left to events.
do
    local s=party()
    s:add(hostile,hostileGuid)
    s.units.party1={name="Bram",guid=hostileGuid}
    s.e.GetNumSubgroupMembers=function() return 1 end
    s:event("GROUP_ROSTER_UPDATE")
    s:wait(1)
    local times,reads={},s.reads()
    for second=2,400 do
        s:tick(1)
        if s.reads()>reads then times[#times+1]=second; reads=s.reads() end
    end
    check(table.concat(times,",")=="3,9,21,45,93,177","the retry follows its six waits")
    check(not polling(s),"the retry stops after the sixth wait")
    s.units.party1.name=hostile
    s:event("PLAYER_TARGET_CHANGED")
    check(s.sounds()==1,"a later event still reads a unit that used up its retries")
end

do
    local s=party()
    s:add(hostile,hostileGuid)
    s.units.party1={name="Ari",guid=allyGuid}
    s.e.GetNumSubgroupMembers=function() return 1 end
    s:event("GROUP_ROSTER_UPDATE")
    s:wait(200)
    s.units.party2={name="Bram",guid=hostileGuid}
    s.e.GetNumSubgroupMembers=function() return 2 end
    s:event("GROUP_ROSTER_UPDATE")
    s:wait(2)
    s.units.party2.name=hostile
    s:wait(1)
    check(s.sounds()==1,"a new unreadable member has its own retries")
end

do
    local s=fresh()
    s:add(hostile,hostileGuid)
    s:plate("nameplate1","Bram",hostileGuid,"Horde")
    for _=1,200 do s:tick(1) end
    check(not polling(s),"an unreadable plate stops being retried")
    s:removePlate("nameplate1")
    s:plate("nameplate1","Bram",hostileGuid,"Horde")
    s.units.nameplate1.name=hostile
    s:tick(3)
    check(s.sounds()==1,"a plate added again has its retries back")
end

do
    local s=guilded()
    local waits={}
    local capture=s.e.C_Timer.After
    s.e.C_Timer.After=function(delay,fn) if delay>=3 then waits[#waits+1]=delay end; capture(delay,fn) end
    s.e.C_Club.GetGuildClubId=function() return nil end
    s:event("PLAYER_GUILD_UPDATE","player")
    for _=1,20 do s:settle() end
    check(table.concat(waits,",")=="3,6,12,24,48,84","the guild ID retry follows the same waits and stops")
    s:event("PLAYER_GUILD_UPDATE","player")
    for _=1,3 do s:settle() end
    check(#waits>6,"a guild event restarts the guild ID retry")
end

do
    local s=fresh()
    s:add(hostile,hostileGuid)
    local shows=0
    s.B.showLive=function() shows=shows+1; return function() return false end end
    s:unit("target",hostile,hostileGuid,"Horde")
    for _=1,1000 do s:tick(.25) end
    check(shows<=60,"a banner that never becomes visible stops being retried")
end

for _,leave in ipairs({"emptying the list","an instance"}) do
    local s=fresh()
    local record=s:add(hostile,hostileGuid)
    s:unit("target","Bram",hostileGuid,"Horde")
    s:tick(1)
    if leave=="an instance" then
        s.instance("party")
        s:event("ZONE_CHANGED_NEW_AREA")
    else
        assert(s.A.store.delete(record.id,3,record.fullName,record.guid))
        s.A.refresh()
    end
    for _=1,40 do s:tick(.1) end
    check(not polling(s),leave.." before a retry is due stops the retry")
end

do
    local s=fresh()
    s:add(hostile,hostileGuid)
    s:add(ally,allyGuid)
    s:plate("nameplate1",hostile,hostileGuid,"Horde")
    s:plate("nameplate2","Ari",allyGuid,"Alliance")
    s:tick(.25)
    s.units.nameplate2.name=ally
    for _=1,4 do s:tick(.25) end
    local live=s.e.WhowhoBlacklistLiveBanner
    check(live.more:IsShown() and live.more:GetText()=="+1 more","a plate read inside the group window joins the banner")
    for _=1,60 do s:tick(.25) end
    check(s.sounds()==1,"a plate read inside the group window does not alert again")
end

do
    local s=party()
    s:add(hostile,hostileGuid)
    s:add(ally,allyGuid)
    s:members()
    s:unit("target",hostile,hostileGuid,"Horde")
    s:unit("mouseover",ally,allyGuid,"Horde")
    s:tick(.25)
    s:tick(.25)
    s:members(ally)
    for _=1,4 do s:tick(.25) end
    local live=s.e.WhowhoBlacklistLiveBanner
    check(live.more:GetText()=="+1 more","a counted player who joins is not counted twice")
    for _=1,120 do s:tick(.25) end
    check(s.sounds()==2,"the join of a counted player gets its own banner")
end

do
    local s=fresh()
    s:add(hostile,hostileGuid)
    s:unit("target",ally,allyGuid,"Alliance")
    s:tick(100)
    s:plate("nameplate1","Bram",hostileGuid,"Horde")
    local times,reads={},s.reads()
    for second=1,10 do
        s:tick(1)
        if s.reads()>reads then times[#times+1]=second; reads=s.reads() end
    end
    check(table.concat(times,",")=="3,9","the first plate wait after an idle period is 3 seconds")
end

do
    local s=guilded()
    local timers={}
    s.e.C_Timer.After=function(delay,fn) timers[#timers+1]={delay=delay,fn=fn} end
    local function run(short)
        local due=timers
        timers={}
        for _,timer in ipairs(due) do
            if short and timer.delay>=3 then timers[#timers+1]=timer else timer.fn() end
        end
    end
    local function waits()
        local delays={}
        for _,timer in ipairs(timers) do delays[#delays+1]=timer.delay end
        return table.concat(delays,",")
    end
    s.e.C_Club.GetGuildClubId=function() return nil end
    s:event("PLAYER_GUILD_UPDATE","player")
    for _=1,6 do run() end
    s:event("PLAYER_GUILD_UPDATE","player")
    run(true)
    check(waits()=="84,3","a guild event restarts the guild ID waits while a long wait is pending")
    run()
    check(waits()=="6","the retired long wait does not read the guild ID again")
end

do
    local s=fresh()
    s:plate("nameplate1",hostile,hostileGuid,"Horde")
    s.units.nameplate1.restricted=true
    s:add(hostile,hostileGuid)
    s.units.nameplate1.restricted=false
    s:tick(3)
    check(s.sounds()==1,"a stored plate that cannot be read during a scan is retried")
end

for _,source in ipairs({"target","mouseover","nameplate"}) do
    local s=fresh()
    s:add(hostile,hostileGuid)
    local show=s.B.showLive
    local shows=0
    s.B.showLive=function() shows=shows+1; return function() return false end end
    if source=="nameplate" then s:plate("nameplate1",hostile,hostileGuid,"Horde")
    else s:unit(source,hostile,hostileGuid,"Horde") end
    for _=1,400 do s:tick(.25) end
    local settled=shows
    for _=1,800 do s:tick(.25) end
    check(settled<=48 and shows==settled,source..": an invisible banner stops being retried")
    s:event("PLAYER_TARGET_CHANGED")
    for _=1,100 do s:tick(.25) end
    check(shows==settled+1,source..": a game event gives one more attempt")
    s.B.showLive=show
    s:event("PLAYER_TARGET_CHANGED")
    s:tick(.25)
    check(s.sounds()==1,source..": the alert shows once the banner can appear")
end

do
    local s=party()
    s:add(hostile,hostileGuid)
    s.units.party1={name="Ari",guid=allyGuid}
    s.e.GetNumSubgroupMembers=function() return 1 end
    s:event("GROUP_ROSTER_UPDATE")
    s:wait(200)
    s.units.party1={name="Bram",guid=hostileGuid}
    s:event("GROUP_ROSTER_UPDATE")
    s:wait(2)
    s.units.party1.name=hostile
    s:wait(1)
    check(s.sounds()==1,"another member in the same slot has its own retries")
end

do
    local s=fresh()
    s:add(hostile,hostileGuid)
    s:unit("target","Ari",allyGuid,"Horde")
    for _=1,200 do s:tick(1) end
    s:unit("target","Bram",hostileGuid,"Horde")
    s:tick(2)
    s.units.target.name=hostile
    s:tick(1)
    check(s.sounds()==1,"a new target has its own retries")
end

do
    local s=guilded()
    s.e.C_Club.GetGuildClubId=function() return nil end
    s:event("PLAYER_GUILD_UPDATE","player")
    for _=1,20 do s:settle() end
    local added=0
    local capture=s.e.C_Timer.After
    s.e.C_Timer.After=function(delay,fn) if delay>=3 then added=added+1 end; capture(delay,fn) end
    s:event("PLAYER_ENTERING_WORLD")
    check(added==1,"entering the world restarts the used-up guild ID waits")
end

do
    local s=party()
    s:add(hostile,hostileGuid)
    s:members(hostile)
    s.units.party1=nil
    s:event("GROUP_ROSTER_UPDATE")
    s:tick(.25)
    check(s:live(),"a briefly empty group slot keeps the visible banner")
end

do
    local s=party()
    s:add(hostile,hostileGuid)
    s:members(ally,ally,ally,ally)
    local reads=s.reads()
    s:plate("nameplate1","Bram",hostileGuid,"Horde")
    check(s.reads()-reads<=6,"an unreadable plate does not read the whole group again")
    s.units.nameplate1.name=hostile
    s:tick(3)
    check(s.sounds()==1,"that plate is still retried")
end

do
    -- Forever runs Lua 5.1 (60 upvalues per function); the Fengari runner would accept more.
    local s=fresh()
    local seen,worst={},0
    local function walk(fn)
        if seen[fn] then return end
        seen[fn]=true
        local n=0
        for i=1,255 do
            local name,value=debug.getupvalue(fn,i)
            if not name then break end
            if name~="_ENV" then
                n=n+1
                if type(value)=="function" and debug.getinfo(value,"S").what=="Lua" then walk(value) end
            end
        end
        worst=math.max(worst,n)
    end
    walk(s.observer.scripts.OnEvent)
    walk(s.B.sightingsBookChanged)
    print("largest sighting upvalue count "..worst)
    check(worst<=52,"sighting functions keep headroom under the Lua 5.1 upvalue limit")
end

print(("RESULT simulated Blacklist nameplate %d checks passed"):format(count))
