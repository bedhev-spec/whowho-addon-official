local P = WhowhoPreview
local A = P.manual
local read, readable, member = A.nativeRead.read, A.nativeRead.readable, A.nativeRead.member
local isComplete = P.CharacterName.IsComplete
local ledger = A.encounterLedger
local unit = A.unitReader
local whisper = "CHAT_MSG_WHISPER"
local baseline = {whisper, "CHAT_MSG_SAY", "CHAT_MSG_YELL"}
local partyRaid = {"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER"}
local cityTrade = {"CHAT_MSG_CHANNEL"}
local guild = {"CHAT_MSG_GUILD"}
local scopes = {baseline, partyRaid, cityTrade, guild}
partyRaid.preference = "muteBlacklistPartyRaid"
cityTrade.preference = "muteBlacklistCityTrade"
guild.preference = "muteBlacklistGuild"
local tradeNames = {enUS="Trade", enGB="Trade", frFR="Commerce"}
local M = {}
A.chatMute = M

local attempted, installed, filtering = false, false, false
local eventScopes = {}
local generalAvailable
local tradeName
local revision = 0

function M.available()
    return installed and A.store ~= nil
end
function M.baselineComplete()
    return baseline.installed == true
end
function M.defaultEnabled()
    return P.db.muteBlacklistWhispers == true
end
local function setPreference(key, value, available)
    if not available or type(value) ~= "boolean" then return false end
    P.db[key] = value
    revision = revision + 1
    return true
end
function M.setDefault(value)
    return setPreference("muteBlacklistWhispers", value, M.available())
end
function M.partyRaidAvailable()
    return M.available() and partyRaid.installed == true
end
function M.partyRaidEnabled()
    return P.db[partyRaid.preference] == true
end
function M.setPartyRaid(value)
    return setPreference(partyRaid.preference, value, M.partyRaidAvailable())
end
function M.cityTradeAvailable()
    return M.available() and cityTrade.installed == true and generalAvailable == true
end
function M.tradeSupported()
    return tradeName ~= nil
end
function M.cityTradeEnabled()
    return P.db[cityTrade.preference] == true
end
function M.setCityTrade(value)
    return setPreference(cityTrade.preference, value, M.cityTradeAvailable())
end
function M.guildAvailable()
    return M.available() and guild.installed == true
end
function M.guildEnabled()
    return P.db[guild.preference] == true
end
function M.setGuild(value)
    return setPreference(guild.preference, value, M.guildAvailable())
end

local function completeName(name)
    return isComplete(name) and not name:find("-", 1, true)
end
local function playerGuid(guid)
    return type(guid) == "string" and guid:match("^Player%-%d+%-%x+$") ~= nil
end
local function positiveID(id)
    return type(id) == "number" and id > 0 and id % 1 == 0
end
local function zoneType()
    return member(member(Enum, "PermanentChatChannelType"), "Zone")
end
local function publicChannel(zoneID, localID)
    if not generalAvailable or not readable(zoneID) or not positiveID(zoneID) then return false end
    local general = read(member(C_ChatInfo, "GetGeneralChannelID"))
    if not positiveID(general) then return false end
    if zoneID == general then return true end
    if not tradeName or not readable(localID) or not positiveID(localID) then return false end
    local zone = zoneType()
    if type(zone) ~= "number" then return false end
    -- Resolve the exact native Trade name. The zone ID classifies the built-in
    -- channel; the local ID only corroborates the joined channel instance.
    local info = read(member(C_ChatInfo, "GetChannelInfoFromIdentifier"), tradeName)
    return member(info, "channelType") == zone
        and (member(info, "name") == tradeName or member(info, "shortcut") == tradeName)
        and member(info, "zoneChannelID") == zoneID and member(info, "localID") == localID
end
function M.canMute(record)
    return record ~= nil and record.membership == "blacklist" and record.identityState == "resolved"
        and record.region == A.region and completeName(record.fullName)
end
function M.muted(record)
    if type(record.whisperMuted) == "boolean" then return record.whisperMuted end
    return M.defaultEnabled()
end

local function matches(event, author, zoneChannelID, channelIndex, guid)
    local store, region, started = A.store, A.region, revision
    if not region or not readable(event) or type(event) ~= "string" then return false end
    local scope = eventScopes[event]
    if not scope or (scope.preference and (not scope.installed or P.db[scope.preference] ~= true))
        or not readable(author) or not completeName(author)
        or not readable(guid) or not playerGuid(guid) then return false end
    local record = store.find(region, author, guid)
    if not M.canMute(record) or not M.muted(record) then return false end
    if event ~= whisper then
        local selfGuid = unit.identitySafe("player") and unit.guid("player")
        if not playerGuid(selfGuid) or selfGuid == guid then return false end
    end
    if scope == cityTrade and not publicChannel(zoneChannelID, channelIndex) then return false end
    local now = not record.guid and not (record.lastKnown and record.lastKnown.guid) and ledger.now() or nil
    if read(GetCurrentRegion) ~= region or A.store ~= store or A.region ~= region or revision ~= started then return false end
    -- Native reads can dispatch other callbacks; use the current indexed record afterwards.
    record = store.find(region, author, guid)
    return M.canMute(record) and record.fullName == author and M.muted(record)
        and ledger.matchesChatGuid(store, record, guid, now) and revision == started
end

-- Forever's fields are sender name (2), zone ID (7), local slot (8), and GUID (12).
local function filter(_, event, _, author, _, _, _, _, zoneChannelID, channelIndex, _, _, _, guid)
    if not M.available() then return false end
    if filtering then
        revision = revision + 1
        return false
    end
    filtering = true
    local ok, discard = pcall(matches, event, author, zoneChannelID, channelIndex, guid)
    filtering = false
    return ok and discard == true
end

function M.install()
    if attempted or not A.store then return end
    attempted = true
    local add = member(ChatFrameUtil, "AddMessageEventFilter")
    if type(add) ~= "function" then return end
    generalAvailable = type(member(C_ChatInfo, "GetGeneralChannelID")) == "function"
    local locale = read(GetLocale)
    if type(locale) == "string"
        and type(member(C_ChatInfo, "GetChannelInfoFromIdentifier")) == "function"
        and type(zoneType()) == "number" then
        tradeName = tradeNames[locale]
    end
    for _, scope in ipairs(scopes) do
        scope.installed = true
        for _, event in ipairs(scope) do
            local ok, result = pcall(add, event, filter)
            if ok and readable(result) and result ~= false then
                eventScopes[event] = scope
            else
                scope.installed = false
            end
        end
    end
    installed = eventScopes[whisper] ~= nil or eventScopes.CHAT_MSG_SAY ~= nil or eventScopes.CHAT_MSG_YELL ~= nil
end
