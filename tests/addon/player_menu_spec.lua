-- Simulated menu descriptions and units; no native client access.
local root = arg[1] or "."
local H = dofile(root .. "/tests/addon/harness.lua")
local p, s, e = H.fresh(root, nil, nil, {region=3, time=100})
e.InCombatLockdown = function() return false end
e.UnitClass = function() return nil end
e.UnitLevel = function() return nil end
local fullName = "Élodie Pâlemont"
local unit = {exists=true, player=true, name=fullName, guid="g1", safe=true}
e.UnitExists = function() return unit.exists end
e.UnitIsPlayer = function() return unit.player end
e.GetUnitName = function() return unit.name end
e.UnitGUID = function() return unit.guid end
e.C_Secrets = {ShouldUnitIdentityBeSecret=function() return not unit.safe end}
local tags, registrations = {}, 0
e.Menu = {ModifyMenu=function(tag, callback) registrations=registrations+1; tags[tag]=callback end}
s:event("ADDON_LOADED", "WhoWho")
p.manual.playerMenu.install()
assert(registrations == 7 and not tags.MENU_UNIT_BN_FRIEND)
local missing,m = H.fresh(root, nil, nil, {region=3, time=100})
m:event("ADDON_LOADED", "WhoWho")
assert(missing.initialized and missing.manual.playerMenu)
for _, suffix in ipairs({"PLAYER", "ENEMY_PLAYER", "PARTY", "RAID", "RAID_PLAYER", "FOCUS", "FRIEND"}) do
    assert(type(tags["MENU_UNIT_" .. suffix]) == "function")
end
local function build(context, tag)
    local buttons = {}
    local function description()
        local entries = {}
        return {entries=entries, CreateButton=function(_, title, callback)
            local child = description()
            entries[#entries+1] = {title=title, callback=callback, child=child}
            return child
        end}
    end
    local rootDescription = description()
    tags[tag or "MENU_UNIT_PLAYER"](nil, rootDescription, context)
    local entries = rootDescription.entries
    if #entries > 0 then
        assert(#entries == 1 and entries[1].title == "WhoWho Add" and entries[1].callback == nil)
        local children = entries[1].child.entries
        assert(#children == 2 and children[1].title == "Friends" and children[2].title == "Blacklist")
        for _, child in ipairs(children) do buttons[child.title] = child.callback end
    end
    return buttons
end
local opened = {}
local original = p.Shell.OpenPlayerAdd
p.Shell.OpenPlayerAdd = function(section, name) opened[#opened+1] = {section, name} end
local buttons = build({unit="target"})
assert(buttons.Friends and buttons.Blacklist)
buttons.Friends(); buttons.Blacklist()
assert(#opened == 2 and opened[1][1] == "friend" and opened[2][1] == "blacklist" and opened[1][2] == unit.name)
unit.guid = "g2"; buttons.Friends(); assert(#opened == 2)
unit.guid = "g1"; unit.name = "Other North"; buttons.Friends(); assert(#opened == 2)
unit.name = fullName; unit.player = false; assert(next(build({unit="target"})) == nil)
unit.player = true; unit.exists = false; assert(next(build({unit="target"})) == nil)
unit.exists = true; unit.safe = false; assert(next(build({unit="target"})) == nil)
unit.safe = true; unit.name = "Incomplete"; assert(next(build({unit="target"})) == nil)
unit.name = "Extra  Gap"; assert(next(build({unit="target"})) == nil)
unit.name = fullName; unit.guid = s.secret; assert(next(build({unit="target"})) == nil)
unit.guid = "g1"; assert(next(build(s.secret)) == nil); assert(next(build({})) == nil)
local protected = {unit="target"}
e.issecrettable = function(value) return value == protected end
assert(next(build(protected)) == nil)
e.issecrettable = function() return false end
tags.MENU_UNIT_PLAYER(nil, {}, {unit="target"})
tags.MENU_UNIT_PLAYER(nil, {CreateButton=function() error("unavailable") end}, {unit="target"})
tags.MENU_UNIT_PLAYER(nil, {CreateButton=function() return {} end}, {unit="target"})
local priorRegion = p.manual.region; p.manual.region = 4; buttons.Friends(); assert(#opened == 2); p.manual.region = priorRegion
p.Shell.OpenPlayerAdd = original
assert(type(original) == "function")
buttons = build({unit="target"}); buttons.Friends()
local form = p.Shell.editor.controls
assert(form.formName:GetText() == fullName and form.form:IsShown() and p.Shell.section == "friend")
form.formName:SetText("Draft North"); form.formNote:SetText("keep this draft")
buttons.Blacklist()
assert(form.form:IsShown() and form.formName:GetText() == "Draft North"
    and form.formNote:GetText() == "keep this draft" and p.Shell.section == "friend")
form.formCancel:Click()
buttons.Blacklist()
assert(form.form:IsShown() and form.formName:GetText() == fullName and p.Shell.section == "blacklist"
    and form.reasonLabel:IsShown())
assert(next(p.manual.store.export().regions[3] or {}) == nil)
form.formCancel:Click()

-- The Blacklist toolbar reads the current target on click using the same identity gates.
local shell = p.Shell
e.Menu = nil
e.GetUnitName = function(token, includeSurname)
    assert(token == "target" and includeSurname == true)
    return unit.name
end
assert(shell.searchBox:GetText() == "")
local originalDb = e.WhowhoAddressBookDB
shell.addButton:Click()
assert(form.form:IsShown() and form.formName:GetText() == fullName and form.formName:IsEnabled()
    and form.formName:HasFocus() and form.reasonLabel:IsShown())
assert(e.WhowhoAddressBookDB == originalDb)
form.formName:SetText("Edited Candidate")
form.formNote:SetText("unsaved note")
shell.addButton:Click()
assert(form.formName:GetText() == "Edited Candidate" and form.formNote:GetText() == "unsaved note")
form.formSave:Click()
assert(form.form:IsShown() and form.reasonHelp:GetText() == "Select at least one reason before saving." and e.WhowhoAddressBookDB == originalDb
    and next(p.manual.store.export().regions[3] or {}) == nil)
form.formCancel:Click()

local function blankBlacklistAdd()
    shell.addButton:Click()
    assert(form.form:IsShown() and form.formName:IsEnabled() and form.formName:GetText() == ""
        and form.formNote:GetText() == "" and form.reasonHelp:GetText() == "Select one or more")
    for _, option in pairs(form.reasonOptions) do assert(option:IsVisible() and not option.mark:IsShown()) end
    form.formCancel:Click()
end
unit.exists = false; blankBlacklistAdd(); unit.exists = true
unit.player = false; blankBlacklistAdd(); unit.player = true
unit.name = "Incomplete"; blankBlacklistAdd(); unit.name = fullName
unit.guid = s.secret; blankBlacklistAdd(); unit.guid = "g1"
local readName, readGuid = e.GetUnitName, e.UnitGUID
local reads = 0
e.GetUnitName = function() reads=reads+1; return fullName end
e.UnitGUID = function() reads=reads+1; return unit.guid end
unit.safe = false; blankBlacklistAdd(); unit.safe = true
local secrets = e.C_Secrets
e.C_Secrets = nil; blankBlacklistAdd(); e.C_Secrets = secrets
e.GetCurrentRegion = function() return 4 end; blankBlacklistAdd()
assert(reads == 0)
e.GetCurrentRegion = function() return 3 end
e.UnitGUID = function() return "stale" .. tostring(reads) end
blankBlacklistAdd()
e.GetUnitName, e.UnitGUID = readName, readGuid

shell.searchBox:SetText("Search Candidate")
unit.exists = false
shell.addButton:Click()
assert(form.form:IsShown() and form.formName:GetText() == "Search Candidate" and form.reasonLabel:IsShown())
form.formCancel:Click()
unit.exists = true

shell.nav.friend:Click()
shell.searchBox:SetText("Search Candidate")
shell.addButton:Click()
assert(form.form:IsShown() and form.formName:GetText() == "Search Candidate" and not form.reasonLabel:IsVisible())
form.formCancel:Click()

e.C_ClassColor = {GetClassColor=function(class)
    return class=="MAGE" and {r=.2,g=.6,b=.9} or nil
end}
e.UnitClassBase = function() return "MAGE" end
e.UnitFactionGroup = function() return "Alliance" end
local function finishBlacklistAdd()
    form.reasonOptions.other:Click()
    form.formSave:Click()
    assert(not form.form:IsShown())
    return assert(shell.selected)
end
local function checkColor(record, expected)
    for _,row in ipairs(shell.rows) do
        if row.record and row.record.id==record.id then
            assert(row.name.textColor[1]==expected and not row.classMarker:IsShown())
            return
        end
    end
    error("Expected saved Blacklist row")
end

shell.nav.blacklist:Click()
shell.searchBox:SetText("")
unit.name, unit.guid = "Panel Person","panel"
shell.addButton:Click()
assert(form.formName:GetText()==unit.name)
assert(form.formName.textColor[1]==.2,"Blacklist Add colors an exact captured target")
assert(p.manual.save(nil,"blacklist","Toolbar Background","",nil,{"other"}))
shell.Refresh()
assert(form.formName.textColor[1]==.2,"toolbar class survives an unrelated store replacement")
unit.exists = false
local panel = finishBlacklistAdd()
assert(panel.blacklistSavedClass=="MAGE" and panel.blacklistFaction=="Alliance")
checkColor(panel,.2)

unit.exists, unit.name, unit.guid = true,"Menu Person","menu"
e.GetUnitName = function(token, includeSurname)
    assert(token=="mouseover" and includeSurname==true)
    return unit.name
end
build({unit="mouseover"}).Blacklist()
assert(form.formName:GetText()==unit.name)
unit.exists = false
local menu = finishBlacklistAdd()
assert(menu.blacklistSavedClass=="MAGE" and menu.blacklistFaction=="Alliance")
checkColor(menu,.2)

unit.exists, unit.name, unit.guid = true,"Different Character","different"
build({unit="mouseover"}).Blacklist()
form.formName:SetText("Edited Name")
assert(form.formName.textColor[1]==p.colors.text[1],"a different name cannot inherit the captured class")
unit.exists = false
local edited = finishBlacklistAdd()
assert(not edited.blacklistSavedClass and not edited.blacklistFaction)
unit.exists,unit.name,unit.guid=true,"Pending Character","pending"
build({unit="mouseover"}).Blacklist()
assert(form.formName:GetText()==unit.name)
assert(form.formName.textColor[1]==.2)
assert(p.manual.save(nil,"blacklist","Other Character","",nil,{"other"}))
shell.Refresh()
assert(form.formName.textColor[1]==.2,"an unrelated store snapshot preserves verified target metadata")
unit.exists = false
local pending=finishBlacklistAdd()
assert(pending.blacklistSavedClass=="MAGE" and pending.blacklistFaction=="Alliance")

local restored,restoredState=H.fresh(root,nil,nil,{region=3,db=e.WhowhoAddressBookDB})
restoredState:event("ADDON_LOADED","WhoWho")
for id,guid in pairs({[menu.id]="menu",[panel.id]="panel"}) do
    local saved=restored.manual.store.get(id)
    assert(saved.lastKnown.guid==guid and saved.lastKnown.class.value=="MAGE" and saved.lastKnown.faction.value=="Alliance")
end
-- Other saves may place this older record on a different page.
shell.searchBox:SetText(edited.fullName)
checkColor(edited,1)
shell.searchBox:SetText("")

do
    local classBase, faction = e.UnitClassBase, e.UnitFactionGroup
    e.UnitClassBase = function() return s.secret end
    e.UnitFactionGroup = function() return s.secret end
    local request, classRequests = p.manual.whoLookup.requestBlacklist, {}
    p.manual.whoLookup.requestBlacklist = function(record, notify)
        classRequests[#classRequests+1] = record.fullName
        return request(record, notify)
    end
    unit.exists,unit.name,unit.guid = true,"Unreadable Metadata","unreadable-metadata"
    build({unit="mouseover"}).Blacklist()
    assert(form.form:IsShown() and form.formName:GetText()==unit.name)
    form.formName:SetText("Temporary Replacement")
    form.formName:SetText(unit.name)
    local exact = finishBlacklistAdd()
    assert(exact.fullName==unit.name and not p.manual.store.get(exact.id).lastKnown and #classRequests==0,
        "an exact player-menu save remains local when selected metadata is unreadable")

    unit.name,unit.guid = "Original Recipient","original-recipient"
    build({unit="mouseover"}).Blacklist()
    assert(form.form:IsShown() and form.formName:GetText()==unit.name)
    form.formName:SetText("Pasted Replacement")
    unit.exists=false
    local replacement=finishBlacklistAdd()
    assert(replacement.fullName=="Pasted Replacement" and not p.manual.store.get(replacement.id).lastKnown
        and #classRequests==0, "changing a Quick Add name cannot start a Who lookup")
    p.manual.whoLookup.requestBlacklist = request
    e.UnitClassBase, e.UnitFactionGroup = classBase, faction
end

-- The exact party-menu selection stays with the Friend draft after the unit leaves and an unrelated save.
local units = {party1={name="Party Friend", guid="party-friend", class="MAGE", level=42, faction="Horde"}}
local function field(token, key) return units[token] and units[token][key] end
e.UnitExists = function(token) return units[token] ~= nil end
e.UnitIsPlayer = function(token) return units[token] ~= nil end
e.GetUnitName = function(token) return field(token, "name") end
e.UnitGUID = function(token) return field(token, "guid") end
e.UnitClassBase = function(token) return field(token, "class") end
e.UnitLevel = function(token) return field(token, "level") end
e.UnitFactionGroup = function(token) return token=="player" and "Alliance" or field(token, "faction") end
e.date = function() return "2026-11-23 13:00" end
local whoRequests = 0
p.manual.whoLookup.request = function() whoRequests = whoRequests+1 end
build({unit="party1"}, "MENU_UNIT_PARTY").Friends()
assert(form.formName:GetText()=="Party Friend")
form.roleOptions.HEALER:Click()
form.formNote:SetText("keep my note")
units.party1 = nil
assert(p.manual.save(nil,"blacklist","New Block","",nil,{"other"}))
form.formSave:Click()
assert(not form.form:IsShown())
local friend = assert(shell.selected)
local known = assert(p.manual.store.get(friend.id).lastKnown)
assert(friend.fullName=="Party Friend" and friend.class=="MAGE" and friend.level==42
    and friend.note=="keep my note" and friend.role=="HEALER")
assert(known.guid=="party-friend" and known.class.source=="Player menu" and known.level.value==42)
assert(shell.detail.name.textColor[1]==.2 and shell.detail.affiliation:GetText()=="Horde")
assert(not friend.presence and not friend.presenceReport and not friend.localChecksOnly and whoRequests==0)
shell.searchBox:SetText("Party Friend")
assert(shell.rows[1].record.id==friend.id and shell.rows[1].name.textColor[1]==.2)
shell.searchBox:SetText("")
local reloaded,reloadState=H.fresh(root,nil,nil,{region=3,db=e.WhowhoAddressBookDB})
reloadState:event("ADDON_LOADED","WhoWho")
local loadedFriend
for _, item in ipairs(reloaded.manual.records) do
    if item.id==friend.id then loadedFriend = item end
end
assert(loadedFriend and loadedFriend.class=="MAGE" and loadedFriend.level==42
    and not loadedFriend.quickAddFaction and not loadedFriend.presence)

units.party1 = {name="Selected Friend", guid="selected-friend", class="MAGE", level=42}
build({unit="party1"}, "MENU_UNIT_PARTY").Friends()
form.formName:SetText("Edited Friend")
units.party1 = nil
form.formSave:Click()
assert(shell.selected.fullName=="Edited Friend" and not shell.selected.class and not shell.selected.level)

units.party1 = {name="Changed Friend", guid="changed-friend", class="MAGE", level=42}
local readClass = e.UnitClassBase
e.UnitClassBase = function(token)
    units.party1.guid = "replacement"
    return readClass(token)
end
build({unit="party1"}, "MENU_UNIT_PARTY").Friends()
assert(not form.form:IsShown())
e.UnitClassBase = readClass

-- A typed Friend keeps the direct target status and can fill missing class from the same group GUID.
e.IsInRaid = function() return false end
e.GetNumSubgroupMembers = function() return 1 end
units.target = {name="Typed Friend", guid="typed-friend", level=31}
units.party1 = {name="Typed Friend", guid="typed-friend", class="MAGE", level=32}
shell.addButton:Click()
assert(form.formName:GetText()=="")
form.formName:SetText("Typed Friend")
form.formSave:Click()
local typed = assert(shell.selected)
local typedKnown = assert(p.manual.store.get(typed.id).lastKnown)
assert(typed.class=="MAGE" and typed.level==31 and typed.presence=="Seen" and typed.source=="Target")
assert(typedKnown.class.source=="Party" and typedKnown.level.source=="Target")

units.target = {name="Conflicting Friend", guid="target-guid"}
units.party1 = {name="Conflicting Friend", guid="party-guid", class="MAGE"}
shell.addButton:Click()
form.formName:SetText("Conflicting Friend")
form.formSave:Click()
assert(shell.selected.presence=="Seen" and not shell.selected.class)

do
    local chatFrame, chatName = {}, "Étienne Clairval"
    e.C_ChatInfo = {}
    -- The native handler parses CHANNEL and the numbered channel target from
    -- a player link. ShowDropdown then supplies the clicked name as chatTarget.
    local function chatContext(name, line)
        return {which="FRIEND", name=name, chatTarget=name, lineID=line or "142", chatType="CHANNEL",
            chatFrame=chatFrame, ownerFrame=chatFrame}
    end
    local function buildChat(context) return build(context, "MENU_UNIT_FRIEND") end
    local whoLookup, playerAddIdentity = p.manual.whoLookup, p.manual.playerAddIdentity
    local requestBlacklist, requestFriend = whoLookup.requestBlacklist, whoLookup.request
    local targetCheck, classRequests, statusRequests, localChecks = p.manual.targetCheck.check, 0, 0, 0
    whoLookup.requestBlacklist = function() classRequests=classRequests+1 end
    whoLookup.request = function() statusRequests=statusRequests+1 end
    p.manual.targetCheck.check = function() localChecks=localChecks+1; return nil,true end
    p.manual.playerAddIdentity = function() error("chat menu must not read a target or mouseover") end

    assert(not next(buildChat({name=chatName, chatTarget=chatName, friendsList=1})))
    local friendsRow=chatContext(chatName); friendsRow.friendsList=1
    assert(not next(buildChat(friendsRow)))
    assert(not next(buildChat(chatContext("Étienne"))))
    assert(not next(buildChat(chatContext("Etienne-Server"))))
    assert(not next(buildChat(chatContext(s.secret))))
    local bnet=chatContext(chatName); bnet.bnetIDAccount=12
    assert(not next(buildChat(bnet)))
    buildChat(chatContext(chatName)).Blacklist()
    assert(form.form:IsShown() and form.formName:GetText()==chatName and classRequests==0)
    form.formCancel:Click()

    -- A unitless regional menu retains the raw player-link spelling. Split
    -- name and surname can be legacy server data and cannot authorize an add.
    local encodedName="Étienne-Clairval"
    local split=chatContext("Étienne"); split.surname="Clairval"
    local context=chatContext(encodedName)
    e.RegionalUniqueNamesEnabled = function() return false end
    e.C_NameUtil = {ReplaceSurnameSeparatorWithLinkSeparator=function(name)
        return name == chatName and encodedName or name
    end}
    assert(not next(buildChat(split)) and not next(buildChat(context)))
    e.RegionalUniqueNamesEnabled = function() return true end
    assert(not next(buildChat(split)))
    assert(not next(buildChat(chatContext("Etienne-Server"))))
    buildChat(context).Blacklist()
    assert(form.form:IsShown() and form.formName:GetText()==chatName and classRequests==0)
    form.formCancel:Click()

    context.lineID, context.chatType, context.ownerFrame = s.secret, nil, nil
    local chatButtons=buildChat(context)
    assert(chatButtons.Blacklist and chatButtons.Friends)
    context.name="Other"
    chatButtons.Blacklist()
    assert(not form.form:IsShown())
    context.name=encodedName
    local currentRegion=e.GetCurrentRegion
    e.GetCurrentRegion=function() return 4 end
    chatButtons.Blacklist()
    assert(not form.form:IsShown())
    e.GetCurrentRegion=currentRegion
    local db=e.WhowhoAddressBookDB
    local currentName=e.UnitNameUnmodified
    e.UnitNameUnmodified=function() return s.secret end
    chatButtons.Blacklist()
    assert(form.form:IsShown() and form.formName:GetText()==chatName and form.reasonLabel:IsShown()
        and shell.section=="blacklist" and e.WhowhoAddressBookDB==db and classRequests==0)
    form.formSave:Click()
    assert(form.form:IsShown() and form.reasonHelp:GetText()=="Select at least one reason before saving.")
    form.formCancel:Click()
    assert(e.WhowhoAddressBookDB==db and classRequests==0)
    e.UnitNameUnmodified=currentName

    local selfButtons=buildChat(chatContext("Current Character"))
    selfButtons.Blacklist()
    form.reasonOptions.other:Click()
    form.formSave:Click()
    assert(form.form:IsShown() and form.formError:GetText()=="You can't add your current character."
        and e.WhowhoAddressBookDB==db and classRequests==0)
    form.formCancel:Click()

    chatButtons=buildChat(context)
    chatButtons.Blacklist()
    form.formNote:SetText("From chat")
    local chatRecord=finishBlacklistAdd()
    local stored=p.manual.store.get(chatRecord.id)
    assert(stored.fullName==chatName and stored.note=="From chat" and stored.reasonIds[1]=="other"
        and stored.membership=="blacklist" and not stored.lastKnown and classRequests==0)
    chatButtons.Blacklist()
    assert(not form.form:IsShown(), "a closed native menu context cannot survive an address-book mutation")

    buildChat(chatContext("Unknown Friend")).Friends()
    assert(form.form:IsShown() and shell.section=="friend" and not form.reasonLabel:IsVisible())
    form.formSave:Click()
    local unknownFriend=assert(shell.selected)
    assert(unknownFriend.fullName=="Unknown Friend" and not unknownFriend.class and not unknownFriend.presence)

    local nativeName, nativeGuid, nativeClass, locked = "Known Friend", "Player-1-00000001", "MAGE", false
    local expectedLine, guidCalls, playerCalls = 142, 0, 0
    e.RAID_CLASS_COLORS={MAGE={}}
    e.C_ChatInfo={
        InChatMessagingLockdown=function() return locked end,
        GetChatLineSenderName=function(line) assert(line==expectedLine); return nativeName end,
        GetChatLineSenderGUID=function(line) assert(line==expectedLine); guidCalls=guidCalls+1; return nativeGuid end,
    }
    e.GetPlayerInfoByGUID=function(guid)
        assert(guid==nativeGuid); playerCalls=playerCalls+1; return "localized name",nativeClass
    end
    db=e.WhowhoAddressBookDB
    buildChat(chatContext(nativeName)).Friends()
    assert(form.form:IsShown() and form.formName:GetText()==nativeName and playerCalls==1 and guidCalls==2)
    assert(form.formName.textColor[1]==.2,"Chat Quick Add colors an exact captured sender")
    form.formName:SetText("Another Person")
    assert(form.formName.textColor[1]==p.colors.text[1])
    form.formName:SetText(nativeName)
    assert(form.formName.textColor[1]==.2 and playerCalls==1 and guidCalls==2,"coloring never rereads chat evidence")
    local color=e.C_ClassColor.GetClassColor
    e.C_ClassColor.GetClassColor=function(class)
        shell.editor.RefreshNameColor()
        form.formName:SetText("Changed Person")
        return color(class)
    end
    form.formName:SetText(nativeName)
    assert(form.formName:GetText()=="Changed Person" and form.formName.textColor[1]==p.colors.text[1],
        "reentrant color reads cannot repaint changed input")
    e.C_ClassColor.GetClassColor=color
    form.formCancel:Click()
    assert(e.WhowhoAddressBookDB==db and not p.manual.store.find(3,nativeName))
    buildChat(chatContext(nativeName)).Friends()
    form.formSave:Click()
    local knownFriend=assert(shell.selected)
    local function assertClass(record, guid, source)
        local known=assert(p.manual.store.get(record.id).lastKnown)
        assert(known.guid==guid and known.class.value=="MAGE" and known.class.source==source)
        local level = source=="Guild" and record.membership=="friend" and 57 or nil
        assert((known.level and known.level.value)==level and not known.faction and not record.presence)
        checkColor(record,.2)
    end
    assert(knownFriend.class=="MAGE" and knownFriend.membership=="friend")
    assertClass(knownFriend,nativeGuid,"Chat menu")
    -- A clicked line can lack metadata while the passive cache refreshes during the form.
    do
        local oldName, oldGuid = nativeName, nativeGuid
        nativeName = nil
        units.player = {name="Current Character", guid="Player-1-00000098"}
        for index, membership in ipairs({"friend", "blacklist"}) do
            local sender = membership=="friend" and "Repeat Friend" or "Repeat Blacklist"
            nativeGuid = "Player-1-0000009" .. index
            local function speak()
                s:event(index==1 and "CHAT_MSG_SAY" or "CHAT_MSG_YELL", s.secret, sender,
                    nil,nil,nil,nil,nil,nil,nil,nil,nil,nativeGuid)
            end
            nativeClass = nil
            speak()
            nativeClass = "MAGE"
            local actions=buildChat(chatContext(sender))
            if membership=="friend" then actions.Friends() else actions.Blacklist() end
            assert(form.form:IsShown() and form.formName.textColor[1]==.2)
            speak()
            if membership=="friend" then form.formSave:Click() else finishBlacklistAdd() end
            local saved=assert(p.manual.store.find(3,sender))
            assert(saved.membership==membership)
            assertClass(saved,nativeGuid,"Chat")
        end
        local sender="Conflicting Repeat"
        nativeGuid="Player-1-00000093"
        s:event("CHAT_MSG_SAY", s.secret,sender,nil,nil,nil,nil,nil,nil,nil,nil,nil,nativeGuid)
        buildChat(chatContext(sender)).Friends()
        assert(form.formName.textColor[1]==.2)
        nativeGuid="Player-1-00000094"
        s:event("CHAT_MSG_SAY", s.secret,sender,nil,nil,nil,nil,nil,nil,nil,nil,nil,nativeGuid)
        form.formSave:Click()
        assert(not assert(p.manual.store.find(3,sender)).lastKnown,
            "a refreshed sender cannot replace the captured GUID")
        units.player=nil
        nativeName,nativeGuid=oldName,oldGuid
    end
    shell.section="friend"
    shell.Select(knownFriend)
    shell.editButton:Click()
    assert(form.form:IsShown() and form.formName.textColor[1]==.2,"Edit uses evidence saved after Shell creation")
    local store=p.manual.store
    p.manual.store=setmetatable({},{__index=store})
    shell.editor.RefreshNameColor()
    assert(form.formName.textColor[1]==p.colors.text[1],"an Edit cannot color from the previous store's roster during rebuild")
    p.manual.refresh()
    shell.editor.RefreshNameColor()
    assert(form.formName.textColor[1]==.2,"rebuilt exact records can color the current Edit")
    p.manual.store=store
    p.manual.refresh()
    form.formCancel:Click()
    shell.moveButton:Click()
    assert(form.form:IsShown() and form.formName.textColor[1]==.2,"Move uses class evidence from the current Friend")
    form.formCancel:Click()

    -- A saved exact name retains its membership and metadata when the other menu choice is used.
    local knownGuid=nativeGuid
    nativeGuid="Player-1-00000003"
    buildChat(chatContext(nativeName)).Friends()
    assert(form.formName.textColor[1]==p.colors.text[1],"a conflicting sender GUID cannot color the saved name")
    form.formCancel:Click()
    nativeGuid=knownGuid
    buildChat(chatContext(nativeName)).Blacklist()
    form.reasonOptions.other:Click()
    form.formSave:Click()
    assert(form.form:IsShown() and form.formSave.label:GetText()=="Open existing")
    form.formSave:Click()
    assert(not form.form:IsShown() and shell.selected.id==knownFriend.id and shell.section=="friend")
    assertClass(shell.selected,nativeGuid,"Chat menu")

    nativeName="Alias Friend"
    db=e.WhowhoAddressBookDB
    buildChat(chatContext(nativeName)).Friends()
    form.formSave:Click()
    assert(form.form:IsShown() and form.formError:GetText()=="Record changed; no changes saved." and e.WhowhoAddressBookDB==db)
    form.formCancel:Click()

    -- The GUID lookup can follow a separately verified Forever link spelling.
    nativeName, nativeGuid, expectedLine="Known-Blocked","Player-1-00000002",143
    e.C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator=function(name)
        return name=="Known Blocked" and nativeName or name
    end
    buildChat(chatContext("Known Blocked",expectedLine)).Blacklist()
    assert(form.form:IsShown() and form.formName:GetText()=="Known Blocked")
    local knownBlacklist=finishBlacklistAdd()
    assert(knownBlacklist.blacklistSavedClass=="MAGE" and knownBlacklist.membership=="blacklist")
    assertClass(knownBlacklist,nativeGuid,"Chat menu")
    assert(p.manual.store.get(knownFriend.id).lastKnown.class.source=="Chat menu", "a later save must retain chat evidence")

    nativeName, nativeGuid, expectedLine="Edited Source","Player-1-00000003",142
    buildChat(chatContext(nativeName)).Blacklist()
    form.formName:SetText("Edited Destination")
    local editedBlacklist=finishBlacklistAdd()
    assert(editedBlacklist.fullName=="Edited Destination" and not p.manual.store.get(editedBlacklist.id).lastKnown)
    buildChat(chatContext(nativeName)).Friends()
    form.formName:SetText("Another Destination")
    form.formSave:Click()
    assert(not form.form:IsShown() and not p.manual.store.get(shell.selected.id).lastKnown)

    local function saveUnknown(name)
        buildChat(chatContext(name)).Blacklist()
        assert(form.form:IsShown() and form.formName:GetText()==name)
        local record=finishBlacklistAdd()
        assert(record.fullName==name and not p.manual.store.get(record.id).lastKnown)
    end
    local beforePlayer=playerCalls
    nativeName="Different Sender"; saveUnknown("Name Mismatch")
    nativeName=s.secret; saveUnknown("Protected Sender")
    nativeName,nativeGuid="Protected Guid",s.secret; saveUnknown(nativeName)
    nativeName,nativeGuid,locked="Locked Source","Player-1-00000004",true; saveUnknown(nativeName)
    assert(playerCalls==beforePlayer)
    nativeName,locked,nativeClass="Protected Class",false,s.secret; saveUnknown(nativeName)
    nativeName,nativeClass="Unrecognized Class","UNRECOGNIZED"; saveUnknown(nativeName)
    nativeName,nativeClass="No Cachedclass",nil; saveUnknown(nativeName)

    -- A system line has no matching sender. An exact, ready Guild row can
    -- supply the class without requesting Guild, Who, or target data.
    local rows, ids, club, ready = {}, {11,22}, 8, true
    local guildReads, guildRequests = 0, 0
    local guildGuid = "Player-1-00000006"
    local function guildRows(name, guid)
        rows[11] = {name=name, guid=guid or guildGuid, classID=8, level=57, presence=1}
        rows[22] = {name="Another Member", guid="Player-1-00000007", classID=1, presence=4}
    end
    e.C_Club={GetGuildClubId=function() return club end, AreMembersReady=function(id) return id==club and ready end,
        GetClubMembers=function(id) assert(id==club); guildReads=guildReads+1; return ids end,
        GetMemberInfo=function(id,member) assert(id==club); return rows[member] end,
        RequestMembers=function() guildRequests=guildRequests+1 end}
    e.C_CreatureInfo={GetClassInfo=function(id) assert(id==8); return {classFile="MAGE"} end}
    nativeName,nativeClass=nil,nil
    local guildFriend="Sélène Longpré"
    guildRows(guildFriend)
    rows[22].guid=nil -- An unrelated offline member need not expose a GUID.
    buildChat(chatContext(guildFriend)).Friends()
    assert(form.form:IsShown() and form.formName.textColor[1]==.2)
    form.formName:SetText("Other Name")
    assert(form.formName.textColor[1]==p.colors.text[1])
    form.formName:SetText(guildFriend)
    assert(form.formName.textColor[1]==.2)
    form.formSave:Click()
    assert(shell.selected.fullName==guildFriend and shell.selected.class=="MAGE")
    assertClass(shell.selected,guildGuid,"Guild")

    local guildBlacklisted="Guild Blocked"
    guildGuid="Player-1-00000008"
    guildRows(guildBlacklisted)
    buildChat(chatContext(guildBlacklisted)).Blacklist()
    assert(form.formName.textColor[1]==.2)
    local guildBlacklistRecord=finishBlacklistAdd()
    assert(guildBlacklistRecord.blacklistSavedClass=="MAGE")
    assertClass(guildBlacklistRecord,guildGuid,"Guild")

    guildGuid="Player-1-00000020"
    guildRows("Unit Guildmember")
    local chatOnlyIdentity=p.manual.playerAddIdentity
    p.manual.playerAddIdentity=playerAddIdentity
    units.focus={name="Unit Guildmember",guid=guildGuid}
    build({unit="focus"},"MENU_UNIT_FOCUS").Blacklist()
    assert(form.form:IsShown() and form.formName.textColor[1]==.2)
    units.focus=nil
    local unitWithGuild=finishBlacklistAdd()
    assertClass(unitWithGuild,guildGuid,"Guild")
    p.manual.playerAddIdentity=chatOnlyIdentity

    guildGuid="Player-1-00000021"
    guildRows("Different Guildmember")
    buildChat(chatContext("Late Profile")).Friends()
    assert(form.form:IsShown() and form.formName.textColor[1]==p.colors.text[1])
    guildRows("Late Profile")
    form.formSave:Click()
    assert(shell.selected.fullName=="Late Profile")
    assertClass(shell.selected,guildGuid,"Guild")

    guildGuid="Player-1-00000009"
    nativeName,nativeGuid="Guild Conflict","Player-1-00000010"
    guildRows(nativeName)
    saveUnknown(nativeName)
    nativeName=nil
    guildRows("Duplicate Member"); rows[22].name=rows[11].name
    saveUnknown("Duplicate Member")
    guildRows("Duplicate Guid"); rows[22].guid=rows[11].guid
    saveUnknown("Duplicate Guid")
    guildRows("Incomplete Roster"); rows[22].name=s.secret
    saveUnknown("Incomplete Roster")
    guildRows("Incomplete Match"); rows[11].guid=s.secret
    saveUnknown("Incomplete Match")
    guildRows("Roster Unready"); ready=false
    local unread=guildReads
    saveUnknown("Roster Unready")
    assert(guildReads==unread)
    ready=true

    guildRows("Stale Guild")
    buildChat(chatContext("Stale Guild")).Friends()
    assert(form.formName.textColor[1]==.2)
    club=9
    shell.editor.RefreshNameColor()
    assert(form.formName.textColor[1]==p.colors.text[1])
    form.formSave:Click()
    assert(shell.selected.fullName=="Stale Guild")
    assertClass(shell.selected,guildGuid,"Guild") -- Reacquire the exact identity from the current ready roster.
    guildGuid="Player-1-00000095"
    guildRows("Roster Changed")
    buildChat(chatContext("Roster Changed")).Blacklist()
    assert(form.formName.textColor[1]==.2)
    rows[22].name=rows[11].name
    local changed=finishBlacklistAdd()
    assert(changed.fullName=="Roster Changed" and not p.manual.store.get(changed.id).lastKnown)

    guildRows("Late Guildchange")
    buildChat(chatContext("Late Guildchange")).Friends()
    assert(form.formName.textColor[1]==.2)
    local playerName=e.UnitNameUnmodified
    e.UnitNameUnmodified=function(...)
        rows[11].guid="Player-1-00000011"
        return playerName(...)
    end
    form.formSave:Click()
    e.UnitNameUnmodified=playerName
    assert(shell.selected.fullName=="Late Guildchange" and not p.manual.store.get(shell.selected.id).lastKnown,
        "Guild evidence changed by the self-name read is discarded at commit")

    guildRows("Region Switch")
    buildChat(chatContext("Region Switch")).Friends()
    assert(form.formName.textColor[1]==.2)
    local nativeRegion, guildMembers=e.GetCurrentRegion,e.C_Club.GetClubMembers
    local regionDuringSave=3
    e.GetCurrentRegion=function() return regionDuringSave end
    e.C_Club.GetClubMembers=function(...)
        regionDuringSave=2
        return guildMembers(...)
    end
    form.formSave:Click()
    e.GetCurrentRegion,e.C_Club.GetClubMembers=nativeRegion,guildMembers
    assert(regionDuringSave==2 and form.form:IsShown() and not p.manual.store.find(3,"Region Switch"),
        "a native region change during final Guild validation cancels the ordinary save")
    form.formCancel:Click()

    local defer=p.BlacklistBanner.deferNewBlacklist
    local function reenterDuringDeferral(change)
        p.BlacklistBanner.deferNewBlacklist=function(...)
            local nativeRegion=e.GetCurrentRegion
            e.GetCurrentRegion=function()
                e.GetCurrentRegion=nativeRegion
                change()
                return nativeRegion()
            end
            local valid=defer(...)
            e.GetCurrentRegion=nativeRegion
            return valid
        end
    end
    guildRows("Late Blacklist")
    buildChat(chatContext("Late Blacklist")).Blacklist()
    assert(form.formName.textColor[1]==.2)
    reenterDuringDeferral(function() rows[11].guid="Player-1-00000012" end)
    local lateBlacklist=finishBlacklistAdd()
    p.BlacklistBanner.deferNewBlacklist=defer
    assert(lateBlacklist.fullName=="Late Blacklist" and not p.manual.store.get(lateBlacklist.id).lastKnown,
        "Guild evidence changed by the Blacklist cooldown region read is discarded at commit")

    guildRows("Canceled Blacklist")
    buildChat(chatContext("Canceled Blacklist")).Blacklist()
    assert(form.formName.textColor[1]==.2)
    form.reasonOptions.other:Click()
    reenterDuringDeferral(function() form.formName:SetText("New Blacklist") end)
    form.formSave:Click()
    p.BlacklistBanner.deferNewBlacklist=defer
    assert(form.form:IsShown() and form.formName:GetText()=="New Blacklist"
        and not p.manual.store.find(3,"Canceled Blacklist") and not p.manual.store.find(3,"New Blacklist"),
        "a save that loses its form during Blacklist cooldown preparation publishes neither name")
    form.formCancel:Click()

    guildRows("Reentrant Save")
    buildChat(chatContext("Reentrant Save")).Friends()
    local members=e.C_Club.GetClubMembers
    e.C_Club.GetClubMembers=function(id)
        form.formSave:Click()
        form.formName:SetText("New Name")
        return members(id)
    end
    form.formSave:Click()
    assert(form.form:IsShown() and form.formName:GetText()=="New Name" and not p.manual.store.find(3,"Reentrant Save"))
    e.C_Club.GetClubMembers=members
    form.formSave:Click()
    assert(shell.selected.fullName=="New Name" and not p.manual.store.get(shell.selected.id).lastKnown)

    guildRows("Reentrant Roster")
    local memberInfo=e.C_Club.GetMemberInfo
    e.C_Club.GetMemberInfo=function(id,key)
        buildChat(chatContext("New Menu"))
        return memberInfo(id,key)
    end
    buildChat(chatContext("Reentrant Roster")).Friends()
    assert(not form.form:IsShown() and guildReads>0 and guildRequests==0)
    e.C_Club.GetMemberInfo=memberInfo

    nativeName,nativeClass="Reused Line","MAGE"
    guildRows(nativeName,"Player-1-00000005")
    local getProfile=e.GetPlayerInfoByGUID
    e.GetPlayerInfoByGUID=function(guid)
        local localized,class=getProfile(guid)
        nativeGuid="Player-1-00000005"
        return localized,class
    end
    saveUnknown(nativeName)
    e.GetPlayerInfoByGUID=getProfile
    e.C_Club=nil

    local staleContext=chatContext("Stale Context")
    local stale=buildChat(staleContext)
    staleContext.lineID="143"
    stale.Blacklist()
    assert(not form.form:IsShown())
    staleContext.lineID="142"
    buildChat(chatContext("Latest Context"))
    stale.Friends()
    assert(not form.form:IsShown())

    local shellOpen=shell.Open
    shell.Open=function()
        shellOpen()
        buildChat(chatContext("Menu Replaced"))
    end
    buildChat(chatContext("Opening Context")).Friends()
    assert(not form.form:IsShown())
    shell.Open=shellOpen

    local reentrantContext=chatContext("Reentrant Context")
    nativeName=reentrantContext.name
    e.GetPlayerInfoByGUID=function(guid)
        local localized,class=getProfile(guid)
        buildChat(chatContext("Replaced Context"))
        return localized,class
    end
    buildChat(reentrantContext).Friends()
    assert(not form.form:IsShown() and classRequests==0 and statusRequests==0 and localChecks==0)

    local function publishClass(name, guid, class, region, validate)
        return p.manual.publishPlayerEvidence({name=name,guid=guid,class=class,at=100,region=region,
            source="chat",validate=validate})
    end
    local friendGuid, blacklistGuid="Player-1-00000022","Player-1-00000023"
    local sightingsChanged=p.BlacklistBanner.sightingsBookChanged
    p.BlacklistBanner.sightingsBookChanged=function() error("chat metadata must not resample physical sightings") end
    assert(publishClass(unknownFriend.fullName,friendGuid,"MAGE",3))
    assert(publishClass(chatRecord.fullName,blacklistGuid,"MAGE",3))
    p.BlacklistBanner.sightingsBookChanged=sightingsChanged
    for _, item in ipairs(p.manual.records) do
        if item.id==unknownFriend.id or item.id==chatRecord.id then
            local known=p.manual.store.get(item.id).lastKnown
            local expected=item.id==unknownFriend.id and friendGuid or blacklistGuid
            assert(known.guid==expected and known.class.value=="MAGE" and known.class.source=="Chat"
                and not item.presence and not item.observed and not item.presenceReport)
        end
    end
    assert(p.manual.store.get(chatRecord.id).note=="From chat")
    db=e.WhowhoAddressBookDB
    assert(not publishClass(unknownFriend.fullName,friendGuid,"PRIEST",3)
        and not publishClass("Other Player",friendGuid,"MAGE",3)
        and not publishClass(chatRecord.fullName,blacklistGuid,"MAGE",4)
        and e.WhowhoAddressBookDB==db)

    local race=assert(p.manual.save(nil,"blacklist","Concurrent Candidate","",nil,{"other"}))
    assert(not publishClass(race.fullName,"Player-1-00000024","MAGE",3,function()
        assert(p.manual.save(nil,"blacklist","Concurrent Save","",nil,{"other"}))
        return true
    end))
    assert(not p.manual.store.get(race.id).lastKnown and p.manual.store.find(3,"Concurrent Save"))

    -- A dependency exception releases the guard and retains the original diagnostic.
    do
        local target="Retry Error"
        buildChat(chatContext(target)).Blacklist()
        form.reasonOptions.other:Click()
        local defer=p.BlacklistBanner.deferNewBlacklist
        p.BlacklistBanner.deferNewBlacklist=function() error("simulated save dependency error") end
        local ok,issue=pcall(form.formSave.Click,form.formSave)
        assert(not ok and tostring(issue):find("simulated save dependency error",1,true))
        assert(form.form:IsShown() and not p.manual.store.find(3,target))
        p.BlacklistBanner.deferNewBlacklist=defer
        form.formSave:Click()
        assert(not form.form:IsShown() and p.manual.store.find(3,target),"the same form can retry")
        buildChat(chatContext("Different Retry")).Friends()
        form.formSave:Click()
        assert(not form.form:IsShown() and p.manual.store.find(3,"Different Retry"),"new forms remain saveable")
    end
    -- Same-region publication retires old leases, not the picked chat identity.
    e.GetPlayerInfoByGUID=getProfile
    nativeClass,locked,expectedLine="MAGE",false,142
    for index, membership in ipairs({"friend","blacklist"}) do
        local target="Snapshot Direct"..index
        nativeName,nativeGuid=target,"Player-71-"..index
        buildChat(chatContext(target))[membership=="friend" and "Friends" or "Blacklist"]()
        assert(form.formName.textColor[1]==.2)
        assert(p.manual.save(nil,"blacklist","Snapshot Other"..index,"",nil,{"other"}))
        shell.editor.RefreshNameColor()
        assert(form.formName.textColor[1]==.2,"direct chat color survives unrelated publication on either page")
        if membership=="blacklist" then form.reasonOptions.other:Click() end
        form.formSave:Click()
        assert(not form.form:IsShown())
        assertClass(shell.selected,nativeGuid,"Chat menu")
    end
    -- Passive cache refreshes are cheap and can reacquire the exact immutable identity.
    units.player={name="Current Character",guid="Player-1-00000098"}
    for index, membership in ipairs({"friend","blacklist"}) do
        local target, guid="Snapshot Passive"..index,"Player-72-"..index
        nativeName,nativeGuid=nil,guid
        s:event("CHAT_MSG_SAY","message",target,nil,nil,nil,nil,nil,nil,nil,nil,nil,guid)
        buildChat(chatContext(target))[membership=="friend" and "Friends" or "Blacklist"]()
        assert(form.formName.textColor[1]==.2)
        s:event("CHAT_MSG_SAY","repeat",target,nil,nil,nil,nil,nil,nil,nil,nil,nil,guid)
        shell.editor.RefreshNameColor()
        assert(form.formName.textColor[1]==.2,"harmless repeat keeps the exact cached class")
        assert(p.manual.save(nil,"blacklist","Passive Other"..index,"",nil,{"other"}))
        shell.editor.RefreshNameColor()
        assert(form.formName.textColor[1]==.2,"passive class rebinds after unrelated publication")
        if membership=="blacklist" then form.reasonOptions.other:Click() end
        form.formSave:Click()
        assert(not form.form:IsShown())
        assertClass(shell.selected,guid,"Chat")
        local conflict="Passive Conflict"..index
        nativeGuid="Player-73-"..index
        s:event("CHAT_MSG_SAY","message",conflict,nil,nil,nil,nil,nil,nil,nil,nil,nil,nativeGuid)
        buildChat(chatContext(conflict))[membership=="friend" and "Friends" or "Blacklist"]()
        assert(form.formName.textColor[1]==.2)
        nativeGuid="Player-74-"..index
        s:event("CHAT_MSG_SAY","conflict",conflict,nil,nil,nil,nil,nil,nil,nil,nil,nil,nativeGuid)
        shell.editor.RefreshNameColor()
        assert(form.formName.textColor[1]==p.colors.text[1],"ambiguous passive sender clears class on repaint")
        form.formCancel:Click()
    end
    -- A newer store during Save is a conflicting transaction, even in one region.
    for index, membership in ipairs({"friend","blacklist"}) do
        local target="Transaction Target"..index
        nativeName,nativeGuid=target,"Player-75-"..index
        buildChat(chatContext(target))[membership=="friend" and "Friends" or "Blacklist"]()
        if membership=="blacklist" then form.reasonOptions.other:Click() end
        local clock=e.GetServerTime
        local background="Transaction Other"..index
        e.GetServerTime=function()
            e.GetServerTime=clock
            assert(p.manual.save(nil,"blacklist",background,"",nil,{"other"}))
            return clock()
        end
        form.formSave:Click()
        e.GetServerTime=clock
        assert(form.form:IsShown() and not p.manual.store.find(3,target) and p.manual.store.find(3,background),
            "concurrent snapshot publication cancels the original chat transaction")
        form.formCancel:Click()
    end
    -- Every ordinary form owns its final publication, including drafts and edits.
    local serverTime=e.GetServerTime
    for index, membership in ipairs({"friend","blacklist"}) do
        for _, mode in ipairs({"complete","draft","edit","changed","cooldown"}) do
            if membership=="blacklist" and mode=="draft" or membership=="friend" and mode=="cooldown" then
                -- These form types do not exist for this destination.
            else
                local target="Ordinary Guard"..index..mode
                local old
                if mode=="edit" then old=assert(p.manual.save(nil,membership,target,"old",nil,membership=="blacklist" and {"other"} or nil)) end
                shell.editor.Open(old,membership)
                if not old then form.formName:SetText(mode=="draft" and "Guarddraft" or target) end
                if membership=="blacklist" then
                    if mode~="edit" then form.reasonOptions.other:Click() end
                end
                form.formNote:SetText("new")
                local originalDb=e.WhowhoAddressBookDB
                local fired=false
                local function interrupt()
                    if not fired then
                        fired=true
                        if mode=="changed" then form.formNote:SetText("later") else form.formCancel:Click() end
                    end
                end
                if mode=="cooldown" then
                    p.BlacklistBanner.deferNewBlacklist=function(...)
                        e.GetCurrentRegion=function() interrupt(); return nativeRegion() end
                        local valid=defer(...)
                        e.GetCurrentRegion=nativeRegion
                        return valid
                    end
                else
                    e.GetServerTime=function() interrupt(); return serverTime() end
                end
                form.formSave:Click()
                e.GetServerTime=serverTime
                p.BlacklistBanner.deferNewBlacklist=defer
                assert(fired and e.WhowhoAddressBookDB==originalDb,"ordinary "..membership.." "..mode.." must not publish after losing ownership")
                if old then assert(p.manual.store.get(old.id).note=="old") end
                form.formCancel:Click()
            end
        end
    end
    p.manual.playerAddIdentity, p.manual.targetCheck.check = playerAddIdentity, targetCheck
    whoLookup.requestBlacklist, whoLookup.request = requestBlacklist, requestFriend
end

assert(s.forbiddenCalls == 0 and m.forbiddenCalls == 0)

-- Typed Friends and completed one-part drafts consume the same exact cached
-- profile before commit, while retaining their ordinary local/Who status flow.
do
    local P, sim, env = H.fresh(root,nil,nil,{region=3,time=100})
    env.InCombatLockdown=function() return false end
    env.C_ChatInfo={InChatMessagingLockdown=function() return false end}
    env.GetUnitName=function(token) return token=="player" and "Current Character" or nil end
    env.UnitGUID=function(token) return token=="player" and "Player-1-00000001" or nil end
    env.UnitExists=function(token) return token=="player" end
    env.UnitIsPlayer=env.UnitExists
    env.GetPlayerInfoByGUID=function() return "Mage","MAGE" end
    env.RAID_CLASS_COLORS={MAGE={r=.2,g=.6,b=.9}}
    sim:event("ADDON_LOADED","WhoWho")
    local A, S = P.manual, P.Shell
    S.Open()
    local checks, requests = 0, 0
    A.targetCheck.check=function() checks=checks+1; return nil,true end
    A.whoLookup.request=function() requests=requests+1 end
    local function chat(name,guid)
        sim:event("CHAT_MSG_GUILD","",name,"","","","","","","","","",guid)
    end
    chat("Typed Cached","Player-1-00000002")
    S.nav.friend:Click(); S.searchBox:SetText(""); S.addButton:Click()
    local controls=S.editor.controls
    controls.formName:SetText("Typed Cached"); controls.formSave:Click()
    local typed=assert(A.store.find(3,"Typed Cached"))
    assert(typed.lastKnown.class.value=="MAGE" and typed.lastKnown.guid=="Player-1-00000002")
    assert(checks==1 and requests==1,"typed class lookup retains the eligible ordinary Who flow")
    local draft=assert(A.save(nil,"friend","Draft","",nil,nil))
    chat("Draft Cached","Player-1-00000003")
    assert(A.save(nil,"blacklist","Cache Background","",nil,{"other"}))
    S.editor.Open(draft,"friend")
    controls.formName:SetText("Draft Cached"); controls.formSave:Click()
    local completed=assert(A.store.find(3,"Draft Cached"))
    assert(completed.id==draft.id and completed.lastKnown.class.value=="MAGE"
        and completed.lastKnown.guid=="Player-1-00000003")
    assert(checks==2 and requests==2,"completing a draft retains ordinary status checks")
    assert(sim.forbiddenCalls==0,"typed and draft fixture uses no forbidden APIs")
    chat("Ambiguous Cached","Player-1-00000004")
    chat("Ambiguous Cached","Player-1-00000005")
    local ambiguous=assert(A.save(nil,"friend","Ambiguous Cached","",nil,nil))
    assert(not A.store.get(ambiguous.id).lastKnown,"conflicting cached identities cannot supply class")
    local partial=assert(A.save(nil,"friend","Typed","",nil,nil))
    assert(partial.identityState=="unresolved" and not A.store.get(partial.id).lastKnown,
        "one displayed name part cannot consume complete-name metadata")
    assert(sim.forbiddenCalls==0,"ambiguity fixture uses no forbidden APIs")

    -- The toolbar keeps historical target class across an unrelated save, but
    -- refuses it if the current book binds that GUID to another exact name.
    local target={name="Conflicted Target",guid="Player-1-00000006"}
    env.UnitExists=function(token) return token=="target" or token=="player" end
    env.UnitIsPlayer=env.UnitExists
    env.GetUnitName=function(token) return token=="target" and target.name or "Current Character" end
    env.UnitGUID=function(token) return token=="target" and target.guid or "Player-1-00000001" end
    env.UnitClassBase=function() return "MAGE" end
    env.UnitClass=function() return nil end
    env.UnitLevel=function() return nil end
    S.nav.blacklist:Click(); S.addButton:Click()
    assert(controls.formName:GetText()==target.name)
    assert(sim.forbiddenCalls==0,"toolbar fixture uses no forbidden APIs")
    local otherName="Conflicting Binding"
    assert(A.save(nil,"blacklist",otherName,"",nil,{"other"},nil,
        {store=A.store,region=3,name=otherName,guid=target.guid,class="MAGE",at=100,source="Target"}))
    controls.reasonOptions.other:Click(); controls.formSave:Click()
    assert(controls.form:IsShown() and not A.store.find(3,target.name),
        "a conflicting current GUID binding cannot commit target evidence")
    controls.formCancel:Click()
    for _, item in ipairs(A.records) do
        assert(not item.presence and not item.sightedAt,"cached class alone creates no sighting")
    end
    assert(sim.forbiddenCalls==0)
end
print("RESULT player-menu simulated passed; no client capability established")
