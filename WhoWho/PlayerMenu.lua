-- Open existing add forms from readable player-menu subjects.
local P, A = WhowhoPreview, WhowhoPreview.manual
local member, read = A.nativeRead.member, A.nativeRead.read
local playerMenu = {}
A.playerMenu = playerMenu

local function openAdd(section, name, evidence, owns)
    local open = member(P.Shell, "OpenPlayerAdd")
    if type(open) == "function" then pcall(open, section, name, evidence, owns) end
end

local function createSubmenu(root, blacklist, friends)
    local create = member(root, "CreateButton")
    if type(create) ~= "function" then return end
    local ok, submenu = pcall(create, root, P.L("WhoWho Add"))
    if not ok then return end
    local createChild = member(submenu, "CreateButton")
    if type(createChild) ~= "function" then return end
    pcall(createChild, submenu, P.L("Friends"), friends)
    pcall(createChild, submenu, P.L("Blacklist"), blacklist)
end

local function quickAdd(section, name, guid, source, direct, store, region, owns)
    local opening = true
    local function ownsRead() return not opening or owns() end
    local resolved = not (direct and direct.class) and A.playerEvidence.resolve(name, store, region, guid, ownsRead)
    opening = false
    if not owns() then return end
    local observation = resolved and resolved.class and resolved or direct or resolved
    openAdd(section, name, {quickAdd=true, name=name, guid=guid or (observation and observation.guid),
        source=source, store=store, region=region, observation=observation, direct=direct}, owns)
end

local activeUnitMenu
local function populateUnit(_, root, context)
    local menu = {}
    activeUnitMenu = menu
    local token = member(context, "unit")
    if type(token) ~= "string" or token == "" then return end
    local store, region = A.store, A.region
    local name, guid = A.playerAddIdentity(token, store, region)
    if not name then return end
    local function owns()
        if activeUnitMenu ~= menu or member(context, "unit") ~= token then return false end
        local currentName, currentGuid = A.playerAddIdentity(token, store, region)
        return currentName == name and currentGuid == guid and activeUnitMenu == menu
    end
    local function add(section)
        return function()
            if menu.busy then return end
            menu.busy = true
            if owns() then
                local direct, changed
                if section == "blacklist" then
                    direct, changed = A.captureBlacklistMetadata(token, store, region, name, guid, "Player menu", owns)
                else
                    direct, changed = A.captureFriendMetadata(token, store, region, name, guid)
                end
                if not changed then quickAdd(section, name, guid, "Player menu", direct, store, region, owns) end
            end
            menu.busy = false
        end
    end
    if owns() then createSubmenu(root, add("blacklist"), add("friend")) end
end

local completeChatName = A.playerEvidence.chatName

local function chatIdentity(context)
    -- FriendsFrame_ShowDropdown supplies chatFrame for a player link and
    -- friendsList for a Friends row.
    local frame = member(context, "chatFrame")
    if (type(frame) ~= "table" and type(frame) ~= "userdata") or member(context, "friendsList") ~= nil
        or member(context, "bnetIDAccount") ~= nil then return end
    local name = completeChatName(member(context, "name"))
    if not name then return end
    local line = member(context, "lineID")
    if type(line) == "string" and line:match("^%d+$") then line = tonumber(line) end
    if type(line) ~= "number" or line < 1 or line % 1 ~= 0 then line = nil end
    return name, frame, line
end

local function chatSenderGuid(name, line, owns)
    if not line or not owns() then return end
    local chat = C_ChatInfo
    local lockdown = member(chat, "InChatMessagingLockdown")
    local sender = member(chat, "GetChatLineSenderName")
    local guidForLine = member(chat, "GetChatLineSenderGUID")
    if read(lockdown) ~= false or completeChatName(read(sender, line)) ~= name
        or not owns() or read(lockdown) ~= false then return end
    local guid = read(guidForLine, line)
    if type(guid) == "string" and guid:match("^Player%-%d+%-%x+$") and owns() and read(lockdown) == false then return guid end
end

local function chatClass(guid, senderGuid)
    if not guid then return end
    local class = A.playerEvidence.classForGuid(guid)
    if not class then return end
    local at = read(GetServerTime)
    if type(at) == "number" and at >= 0 and at < math.huge and senderGuid() == guid then return class, at end
end

local activeChatMenu
local function populateChat(_, root, context)
    local menu = {}
    activeChatMenu = menu
    local store, region = A.store, A.region
    if not store or not region or read(GetCurrentRegion) ~= region then return end
    local name, frame, line = chatIdentity(context)
    if not name then return end
    local function owns()
        if activeChatMenu ~= menu then return false end
        local currentName, currentFrame, currentLine = chatIdentity(context)
        return currentName == name and rawequal(currentFrame, frame) and currentLine == line and read(GetCurrentRegion) == region
            and activeChatMenu == menu and A.store == store and A.region == region
    end
    local function add(section)
        return function()
            if menu.busy then return end
            menu.busy = true
            if owns() then
                local function senderGuid() return chatSenderGuid(name, line, owns) end
                local guid = senderGuid()
                local class, at = chatClass(guid, senderGuid)
                if guid and not class and senderGuid() ~= guid then
                    if owns() then openAdd(section, name, {quickAdd=true, source="Chat menu"}, owns) end
                else
                    local direct = class and {name=name, guid=guid, class=class, at=at, region=region, source="Chat menu"}
                    quickAdd(section, name, guid, "Chat menu", direct, store, region, owns)
                end
            end
            menu.busy = false
        end
    end
    if owns() then createSubmenu(root, add("blacklist"), add("friend")) end
end

local installed = {}
local function register(modify, tag, populate)
    if installed[tag] then return end
    installed[tag] = true
    if not pcall(modify, tag, populate) then installed[tag] = nil end
end

function playerMenu.install()
    if not A.store then return end
    local modify = member(Menu, "ModifyMenu")
    if type(modify) ~= "function" then return end
    for _, suffix in ipairs({"PLAYER", "ENEMY_PLAYER", "PARTY", "RAID", "RAID_PLAYER", "FOCUS"}) do
        register(modify, "MENU_UNIT_" .. suffix, populateUnit)
    end
    register(modify, "MENU_UNIT_FRIEND", populateChat)
end
