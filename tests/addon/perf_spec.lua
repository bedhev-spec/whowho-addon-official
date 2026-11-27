-- Simulated CPU hot paths. Counts only: Fengari timing says nothing about the client.
local root=arg[1] or "."
local H=dofile(root.."/tests/addon/harness.lua")
local count=0
local function check(value,message)
    assert(value,message)
    count=count+1
end
local function bound(label,value,limit)
    print(string.format("COUNT %s = %d (limit %d)",label,value,limit))
    check(value<=limit,label.." exceeded "..limit..": "..value)
end

local function upvalue(fn,key)
    for i=1,debug.getinfo(fn,"u").nups do
        local name,value=debug.getupvalue(fn,i)
        if name==key then return value end
    end
    error("missing upvalue: "..key)
end

local function fresh(db)
    local config={region=3,time=100,db=db}
    local p,s,e=H.fresh(root,nil,{484,800},config)
    local units,frames,n={},{},{reads=0}
    s.units=units
    e.date=os.date
    e.GetTime=function() return config.time end
    e.GetServerTime=function() return math.floor(config.time) end
    e.GetRealZoneText=function() return "The Barrens" end
    e.InCombatLockdown=function() return false end
    e.C_Timer={NewTimer=function() return {Cancel=function() end} end,After=function() end}
    e.UnitExists=function(unit) return units[unit]~=nil end
    e.UnitIsPlayer=function(unit) return units[unit]~=nil end
    e.UnitIsUnit=function(unit) return unit=="player" end
    e.GetUnitName=function(unit) n.reads=n.reads+1; return units[unit].name end
    e.UnitGUID=function(unit) n.reads=n.reads+1; return units[unit] and units[unit].guid end
    e.UnitClass=function() return nil end
    e.C_NamePlate={
        GetNamePlateForUnit=function(unit) return frames[unit] end,
        GetNamePlates=function() return frames end,
    }
    s:event("ADDON_LOADED","WhoWho")
    local A=p.manual
    for _,frame in ipairs(s.nodes) do
        if frame.events.PLAYER_LEAVING_WORLD and frame.parent==e.UIParent then s.observer=frame end
    end
    function s:tick(elapsed)
        config.time=config.time+elapsed
        local fn=self.observer:IsVisible() and self.observer:GetScript("OnUpdate")
        if fn then fn(self.observer,elapsed) end
    end
    function s:add(name,guid,section)
        assert(A.store.add({region=3,fullName=name,guid=guid,identityState="resolved",
            membership=section or "blacklist",reasonIds={"other"}},100))
        A.refresh()
    end
    function s:plate(token,name,guid)
        units[token]={name=name,guid=guid}
        frames[token]={IsVisible=function() return true end,IsForbidden=function() return false end,
            GetUnit=function() return token end}
        self:event("NAME_PLATE_UNIT_ADDED",token)
    end
    return p,s,e,A,n
end

local function pad(i) return string.format("%08d",i) end
local letters="abcdefghij"
local function word(i)
    return (string.format("%04d",i):gsub("%d",function(d) return letters:sub(d+1,d+1) end))
end
local function person(i) return "Player N"..word(i),"Player-1-"..pad(i) end

local function raid()
    local _,s,e,_,n=fresh()
    e.IsInRaid=function() return true end
    e.GetNumGroupMembers=function() return 40 end
    for i=1,40 do
        local name,guid=person(i)
        s.units["raid"..i]={name=name,guid=guid}
    end
    s:add(person(1))
    s:event("GROUP_ROSTER_UPDATE")
    for _=1,40 do s:tick(.5) end
    return s,n
end

-- The first event of a burst must scan at once; its reads are the cost of one scan.
-- The window outlasts the roster settle time, so deferred work cannot look like a saving.
local function burst(event)
    local s,n=raid()
    local function settle() for _=1,8 do s:tick(.2) end end
    s:tick(1)
    local before=n.reads
    s:event(event)
    local single=n.reads-before
    check(single>0,"one "..event.." scans at once")
    settle()
    before=n.reads
    for _=1,20 do s:event(event) end
    settle()
    local reads=n.reads-before
    check(reads>=single,event.." burst is scanned")
    return reads,single
end

for _,case in ipairs({{"mouseover","UPDATE_MOUSEOVER_UNIT",3280,20},{"roster","GROUP_ROSTER_UPDATE",4692,23}}) do
    local reads,single=burst(case[2])
    bound(case[1].." burst name/GUID reads",reads,case[3])
    bound(case[1].." burst full scans",math.floor(reads/single+.5),case[4])
end

-- Each observer that reads a listed membership costs its own reads per plate.
for _,case in ipairs({{"empty book",{},0,0},{"unmatched Blacklist only",{"blacklist"},1,1024},
    {"unmatched Friend only",{"friend"},1,512},{"unmatched book",{"blacklist","friend"},1025,1536}}) do
    local p,s,_,A,n=fresh()
    local seen={check=0,sightings=0}
    local function counted(target,key,name)
        local original=target[key]
        target[key]=function(...) seen[name]=seen[name]+1; return original(...) end
    end
    counted(A.nameplateCheck,"onEvent","check")
    counted(p.BlacklistBanner,"sightingsNameplateEvent","sightings")
    for i,section in ipairs(case[2]) do s:add("Nobody "..(i==1 and "Here" or "There"),"Player-9-0000000"..i,section) end
    local before=n.reads
    for i=1,256 do s:plate("nameplate"..i,person(i)) end
    check(A.automaticNameplatesEnabled() and seen.check==256 and seen.sightings==256,"both observers see every plate")
    check(n.reads-before>=case[3],"listed memberships read plates")
    bound("256 plates, "..case[1]..", name/GUID reads",n.reads-before,case[4])
end

-- Cached name checks answer exactly as the first, uncached, call did.
do
    local p=fresh()
    local Name=p.CharacterName
    local nbsp,zeroWidth,invalid=string.char(194,160),string.char(226,128,139),string.char(255)
    local newline=string.char(10)
    for _,case in ipairs({{"Ari North","Ari North","Ari North"},{"  Ari   North ","Ari North","Ari North"},
        {"Ari","nil","Ari"},{"Ari North Star","nil","nil"},{"","nil","nil"},{"Élan Amber","Élan Amber","Élan Amber"},
        {"Ari"..nbsp.."North","Ari North","Ari North"},{"Ari"..zeroWidth.." North","nil","nil"},
        {"Ari "..invalid.."North","nil","nil"},{"Ari"..newline.."North","nil","nil"},
        {"Ari North"..newline,"Ari North","Ari North"}}) do
        for _=1,2 do
            check(tostring(Name.NormalizeManual(case[1]))==case[2],"full name: "..case[1])
            check(tostring(Name.NormalizeManual(case[1],true))==case[3],"draft name: "..case[1])
        end
    end
    local normalized=0
    local scalars=Name.CountScalars
    Name.CountScalars=function(text) normalized=normalized+1; return scalars(text) end
    for i=1,1100 do assert(Name.IsComplete((person(i)))) end
    check(normalized==1100,"distinct names are each normalized")
    check(Name.IsComplete((person(1100))) and normalized==1100,"a recent name is cached")
    check(Name.IsComplete((person(1))) and normalized==1101,"a full cache starts over")
end

do
    local p,s,e,A=fresh()
    local classReads,normalized,published=0,0,0
    e.RAID_CLASS_COLORS={MAGE={}}
    local publish=A.publishPlayerEvidence
    A.publishPlayerEvidence=function(...) published=published+1; return publish(...) end
    e.C_ChatInfo={InChatMessagingLockdown=function() return false end}
    e.GetPlayerInfoByGUID=function() classReads=classReads+1; return nil,"MAGE" end
    s.units.player={name="Current Character",guid="Player-1-99999999"}
    local scalars=p.CharacterName.CountScalars
    p.CharacterName.CountScalars=function(text) normalized=normalized+1; return scalars(text) end
    local function lines()
        normalized,classReads=0,0
        for i=1,100 do
            local name,guid=person(i)
            s:event("CHAT_MSG_CHANNEL","line",name,"","","","","","","","","",guid)
        end
    end
    lines()
    check(published==100 and normalized>0 and classReads>0,"chat lines pass through the evidence cache")
    bound("100 chat lines, name normalizations",normalized,100)
    bound("100 chat lines, class reads",classReads,100)
    lines()
    bound("same 100 authors again, name normalizations",normalized,0)
    bound("same 100 authors again, class reads",classReads,100)
end

do
    local book=assert(loadfile(root.."/WhoWho/AddressBook.lua"))()
    local store=assert(book.open())
    for i=1,1000 do
        local name,guid=person(i)
        assert(store.add({region=3,fullName=name,guid=guid,identityState="resolved",
            membership=i<=500 and "friend" or "blacklist",reasonIds={"other"}},100))
    end
    local _,s,e,A,n=fresh(store.export())
    e.UnitClass=function() return "Mage","MAGE" end
    e.UnitLevel=function() return 42 end
    local namespace=upvalue(A.init,"namespace")
    local calls={open=0,export=0,activeRecords=0}
    local function wrap(target)
        for _,key in ipairs({"export","activeRecords"}) do
            local original=target[key]
            target[key]=function(...) calls[key]=calls[key]+1; return original(...) end
        end
        return target
    end
    local open=namespace.AddressBook.open
    namespace.AddressBook.open=function(input)
        calls.open=calls.open+1
        local opened,issue=open(input)
        return opened and wrap(opened),issue
    end
    wrap(A.store)
    local name,guid=person(1)
    s.units.target={name=name,guid=guid}
    local before=A.store
    s:event("PLAYER_TARGET_CHANGED")
    local known=A.store.get(1).lastKnown
    check(A.store~=before and n.reads>0 and known and known.class.value=="MAGE","the targeted Friend observation is saved")
    check(calls.open>0 and calls.export>0,"the save is counted")
    bound("1000 records, store opens",calls.open,1)
    bound("1000 records, store exports",calls.export,2)
    bound("1000 records, activeRecords copies",calls.activeRecords,1)
end

print("RESULT perf "..count.." passed 0 failed")
