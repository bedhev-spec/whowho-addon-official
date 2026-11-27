-- Local Forever-shaped fixtures for guarded source resolution and passive chat.
local root = arg[1] or "."
local H = dofile(root .. "/tests/addon/harness.lua")
local environment = {region=3, time=100}
local P, sim, e = H.fresh(root, {automaticNameplates=false}, nil, environment)
local name, guid = "Élodie Pâlemont", "Player-12-ABCDEF"
local other, otherGuid = "Luc Ardent", "Player-12-FEDCBA"
local units = {player={name="Current Character", guid="Player-12-012345"}}
local function player(fullName, realGuid, class)
    return {name=fullName, guid=realGuid, class=class, level=23, faction="Horde"}
end
local combat, lockdown = false, false
e.InCombatLockdown = function() return combat end
e.C_ChatInfo = {InChatMessagingLockdown=function() return lockdown end}
e.UnitExists = function(token) return units[token] ~= nil end
e.UnitIsPlayer = function(token) return units[token] ~= nil end
e.UnitGUID = function(token) return units[token] and units[token].guid end
e.GetUnitName = function(token) return units[token] and units[token].name end
e.UnitClass = function(token) return nil, units[token] and units[token].class end
e.UnitLevel = function(token) return units[token] and units[token].level end
e.UnitFactionGroup = function(token) return units[token] and units[token].faction end
e.C_Secrets.ShouldUnitIdentityBeSecret = function(token) return units[token] and units[token].secret == true end
e.RAID_CLASS_COLORS = {MAGE={}, WARRIOR={}, DRUID={}}
e.LOCALIZED_CLASS_NAMES_MALE = {MAGE="Mage", WARRIOR="Guerrier", DRUID="Druide"}
e.LOCALIZED_CLASS_NAMES_FEMALE = {MAGE="Mage", WARRIOR="Guerrière", DRUID="Druidesse"}
e.C_CreatureInfo = {GetClassInfo=function(id) return {classFile=id == 1 and "WARRIOR" or "MAGE"} end}
e.C_FriendList = {}
sim:event("ADDON_LOADED", "WhoWho")
local A = P.manual
local find = A.playerEvidence.resolve
local function resolve(wanted, expected, owns)
    return find(wanted or name, A.store, 3, expected, owns)
end

units.target = player(name, guid, "MAGE")
units.mouseover = player(other, otherGuid, "DRUID")
local observation = assert(resolve())
assert(observation.source == "Target" and observation.name == name and observation.guid == guid
    and observation.region == 3 and observation.class == "MAGE" and observation.level == 23
    and observation.faction == "Horde" and observation.at == 100 and observation.validate())
assert(assert(resolve(other)).source == "Mouseover" and not resolve("Élodie") and not resolve("élodie Pâlemont"))
assert(not find(name, A.store, 3, guid, nil, true))
assert(not resolve(name, otherGuid) and not resolve(name, guid, function() return false end))
units.target.guid = otherGuid
assert(not observation.validate() and not resolve(name, guid))
units.target.guid = guid
combat = true
assert(not resolve() and not observation.validate())
combat = false
units.target.secret = true
assert(not resolve())
units.target.secret = false
local unitClass = e.UnitClass
e.UnitClass = function(token)
    units[token] = player(other, otherGuid, "DRUID")
    return nil, "MAGE"
end
assert(not resolve(), "a rebound token must not contribute its old class")
e.UnitClass = unitClass

units.target, units.mouseover = nil, nil
e.IsInRaid = function() return false end
e.GetNumSubgroupMembers = function() return 2 end
units.party2 = player(name, guid, "MAGE")
assert(assert(resolve()).source == "Party")
e.IsInRaid = function() return true end
e.GetNumGroupMembers = function() return 12 end
units.raid12, units.party2 = units.party2, nil
assert(assert(resolve()).source == "Raid")
units.raid12 = nil

local shown, opt, revision, frameCount = true, false, 0, 1
local frame = {IsForbidden=function() return false end, IsVisible=function() return shown end,
    GetUnit=function() return "nameplate1" end}
e.C_NamePlate = {GetNamePlates=function()
    local frames = {}
    for i=1,frameCount do frames[i] = frame end
    return frames
end,
    GetNamePlateForUnit=function(_, includeForbidden)
        assert(includeForbidden == false)
        return frame
    end}
A.automaticNameplatesEnabled = function() return opt, revision end
units.nameplate1 = player(name, guid, "MAGE")
assert(not resolve())
opt = true
local plate = assert(resolve())
assert(plate.source == "Nameplate")
revision = 1
assert(not plate.validate())
shown = false
assert(not resolve())
units.nameplate1 = nil

local guild = {name=name, guid=guid, classID=1, level=51, presence=3}
e.Enum = {ClubMemberPresence={Online=1, Offline=3}}
local guildReady, guildIds, guildReads = true, {1}, 0
e.C_Club = {GetGuildClubId=function() guildReads = guildReads + 1; return 7 end,
    AreMembersReady=function() return guildReady end,
    GetClubMembers=function() return guildIds end, GetMemberInfo=function() return guild end}
units.target = player(name, guid)
units.mouseover = player(name, otherGuid)
assert(not resolve() and guildReads == 0, "conflicting live identities stop before roster reads")
units.mouseover = nil
local fromGuild = assert(resolve())
assert(fromGuild.source == "Guild" and fromGuild.class == "WARRIOR" and fromGuild.level == 51
    and fromGuild.faction == nil and fromGuild.online == false and fromGuild.validate())
shown, frameCount = true, 257
units.nameplate1 = player(name, otherGuid, "MAGE")
assert(assert(resolve()).source == "Guild", "a plate list over the scan limit contributes no partial evidence")
shown, frameCount, units.nameplate1 = false, 1, nil
guild.level = 52
assert(not fromGuild.validate())
guild.guid = otherGuid
assert(not resolve(), "readable conflicting GUIDs must prevent enrichment")
guild.guid, guildReady, units.target = guid, false, nil

local recentReady, ally = true, {fullName=name, guid=guid, classID=2, level=36}
e.C_RecentAllies = {IsSystemSupported=function() return true end, IsSystemEnabled=function() return true end,
    IsRecentAllyDataReady=function() return recentReady end,
    GetRecentAllyByFullName=function() return {characterData=ally, stateData={isOnline=true}} end}
local recent = assert(resolve())
assert(recent.source == "Recent Allies" and recent.class == "MAGE" and recent.level == 36 and recent.online == true)
recentReady = false
assert(not recent.validate() and not resolve())

local nativeEnabled, nativeReads = false, 0
local native = {name=name, guid=guid, className="Guerrière", level=31, connected=false}
e.C_FriendList = {IsLegacyFriendSystemEnabled=function() return nativeEnabled end,
    GetFriendInfo=function(exact)
        assert(exact == name or exact == other)
        nativeReads = nativeReads + 1
        return native
    end}
assert(not resolve() and nativeReads == 0)
nativeEnabled = true
local friend = assert(resolve())
assert(friend.source == "Native Friends" and friend.class == "WARRIOR" and friend.level == 31 and friend.online == false)
native.name = "Élodie"
assert(not friend.validate() and not resolve())
native.name, native.guid = name, sim.secret
assert(not resolve())
nativeEnabled = false

local record = assert(A.store.add({fullName=name, region=3, membership="friend", identityState="resolved"}, 80))
assert(A.store.observe(record.id, 3, name, guid, "Guild", 90, "DRUID", 19))
local saved = assert(resolve())
assert(saved.source == "Saved" and saved.class == "DRUID" and saved.level == 19 and saved.at == 90)
assert(not resolve(name, otherGuid))
units.target = player(name, otherGuid, "MAGE")
assert(not resolve(), "an exact live identity cannot replace the saved GUID")
units.target = nil

local published, lookupClass, profileReads = {}, "MAGE", 0
A.publishPlayerEvidence = function(item)
    assert(item.validate() and item.source == "chat" and item.region == 3)
    assert(item.text == nil and item.message == nil and item.current == nil and item.faction == nil)
    published[#published+1] = item
end
e.GetPlayerInfoByGUID = function()
    profileReads = profileReads + 1
    return nil, lookupClass
end
local function chat(event, author, playerGUID)
    sim:event(event, sim.secret, author, nil, nil, nil, nil, nil, nil, nil, nil, nil, playerGUID)
end
chat("CHAT_MSG_GUILD", name, guid)
assert(#published == 1 and profileReads == 1 and assert(resolve()).source == "chat")
A.playerEvidence.install()
chat("CHAT_MSG_SAY", other, otherGuid)
assert(#published == 2 and profileReads == 2 and assert(resolve(other)).guid == otherGuid)
chat("CHAT_MSG_WHISPER_INFORM", other, otherGuid)
chat("CHAT_MSG_CHANNEL", "Luc", otherGuid)
chat("CHAT_MSG_RAID", sim.secret, otherGuid)
chat("CHAT_MSG_PARTY", other, sim.secret)
assert(#published == 2 and profileReads == 2)
chat("CHAT_MSG_YELL", "Current Character", units.player.guid)
lockdown = true
chat("CHAT_MSG_CHANNEL", other, otherGuid)
lockdown = false
assert(#published == 2 and profileReads == 2)
lookupClass = "UNRECOGNIZED"
chat("CHAT_MSG_CHANNEL", other, otherGuid)
assert(#published == 2 and profileReads == 3)

lookupClass = "DRUID"
e.RegionalUniqueNamesEnabled = function() return true end
e.C_NameUtil = {ReplaceSurnameSeparatorWithLinkSeparator=function(fullName) return (fullName:gsub(" ", "-")) end}
chat("CHAT_MSG_PARTY_LEADER", "Luc-Ardent", otherGuid)
assert(#published == 3 and published[3].name == other and assert(resolve(other)).class == "DRUID")
chat("CHAT_MSG_RAID_LEADER", other, "Player-12-FFFF")
assert(#published == 3 and not resolve(other) and not published[3].validate())
chat("CHAT_MSG_CHANNEL", "Changed Name", otherGuid)
assert(#published == 3 and not resolve("Changed Name"))

environment.region = 4
chat("CHAT_MSG_CHANNEL", name, guid)
assert(#published == 3 and not resolve() and not published[1].validate())
environment.region, environment.time = 3, 700
assert(not published[1].validate() and assert(resolve()).source == "Saved")
-- Inserting 129 distinct senders can retain at most 128 entries.
for i=1,129 do
    environment.time = environment.time + 1
    chat("CHAT_MSG_CHANNEL", "Sender Number" .. i, "Player-99-" .. string.format("%X", i))
end
assert(not resolve("Sender Number1") and assert(resolve("Sender Number129")).source == "chat")
-- Incoming Forever chat channels share the author/GUID fields and secrecy rules.
for index, event in ipairs({"CHAT_MSG_WHISPER", "CHAT_MSG_OFFICER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER"}) do
    local sender, senderGuid = "Channel Sender" .. index, "Player-88-" .. index
    local before, reads = #published, profileReads
    chat(event, sender, senderGuid)
    assert(#published == before + 1 and profileReads == reads + 1
        and assert(resolve(sender)).guid == senderGuid, event .. " captures exact sender metadata")
    chat(event, sim.secret, senderGuid)
    chat(event, sender, sim.secret)
    lockdown = true
    chat(event, sender, senderGuid)
    lockdown = false
    assert(#published == before + 1 and profileReads == reads + 1, event .. " rejects unsafe fields")
end
assert(sim.forbiddenCalls == 0)

-- Profiles can be unavailable at the incoming event and readable at Quick Add.
-- Retry only a fresh, unambiguous exact sender; never renew its event lifetime.
do
    local clock = {region=3, time=100}
    local Q, native, api = H.fresh(root, {automaticNameplates=false}, nil, clock)
    api.InCombatLockdown = function() return false end
    api.C_ChatInfo = {InChatMessagingLockdown=function() return false end}
    api.UnitExists = function(token) return token == "player" end
    api.UnitIsPlayer = function(token) return token == "player" end
    api.UnitGUID = function() return "Player-1-00000001" end
    api.C_Secrets.ShouldUnitIdentityBeSecret = function() return false end
    api.RAID_CLASS_COLORS = {MAGE={}}
    local class, reads, duringRead = nil, 0, nil
    api.GetPlayerInfoByGUID = function(exactGuid)
        reads = reads + 1
        if duringRead then duringRead(exactGuid) end
        return "Mage", class
    end
    native:event("ADDON_LOADED", "WhoWho")
    local B = Q.manual
    local publications = 0
    B.publishPlayerEvidence = function() publications = publications + 1 end
    local function incoming(sender, senderGuid)
        native:event("CHAT_MSG_CHANNEL", native.secret, sender,
            nil,nil,nil,nil,nil,nil,nil,nil,nil,senderGuid)
    end
    local function cached(sender, expected)
        return B.playerEvidence.cachedChat(sender, B.store, 3, expected)
    end
    incoming("Delayed Sender", "Player-1-00000002")
    assert(reads == 1 and publications == 0)
    class = "MAGE"
    local delayed = assert(cached("Delayed Sender", "Player-1-00000002"))
    assert(delayed.class == "MAGE" and delayed.at == 100 and delayed.validate() and reads == 2)
    assert(cached("Delayed Sender").class == "MAGE" and reads == 2)
    class = nil
    clock.time = 101
    incoming("Delayed Sender", "Player-1-00000002")
    assert(delayed.validate() and assert(cached("Delayed Sender")).at == 100,
        "a later unavailable profile preserves the earlier class without renewing it")
    clock.time = 700
    assert(not cached("Delayed Sender") and reads == 3, "a later profile cannot renew expired sender evidence")
    class = nil
    incoming("Ambiguous Sender", "Player-1-00000003")
    incoming("Ambiguous Sender", "Player-1-00000004")
    class = "MAGE"
    local before = reads
    assert(not cached("Ambiguous Sender") and reads == before)
    class = nil
    incoming("Reentrant Sender", "Player-1-00000005")
    class = "MAGE"
    duringRead = function()
        duringRead = nil
        incoming("Reentrant Sender", "Player-1-00000006")
    end
    assert(not cached("Reentrant Sender"), "a nested sender replacement invalidates the pending class read")
    class = nil
    incoming("Secret Profile", "Player-1-00000007")
    class = native.secret
    assert(not assert(cached("Secret Profile")).class, "unreadable native classes remain unknown")
    assert(publications == 0 and native.forbiddenCalls == 0)
end
do
    local secret, classFile = sim.secret, "MAGE"
    e.C_CreatureInfo.GetClassInfo = function() return {classFile=classFile} end
    assert(A.unitReader.classForID(8) == "MAGE" and not A.unitReader.classForID(0) and not A.unitReader.classForID(1.5))
    classFile = secret
    assert(A.unitReader.classForID(8) == nil, "hidden class token is ignored")
end
print("RESULT shared player evidence and passive chat passed in simulation")
