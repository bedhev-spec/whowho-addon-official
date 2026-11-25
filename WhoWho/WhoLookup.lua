local P = WhowhoPreview
local A = P.manual
local read, readable, member = A.nativeRead.read, A.nativeRead.readable, A.nativeRead.member
local result = A.whoResult
local lookup = {cooldownMessage = "Who is cooling down. Try again shortly."}
A.whoLookup = lookup

local window, lifetime = 15, 300
local otherFactionMessage = "Who unavailable for the other faction."
local combatMessage = "Who is unavailable during combat."
local identityMessage = "The Blacklist entry or local match changed. Try again."
local api, pending, lastSend, blacklistWork
local contextRevision = 0
local blacklistInWorld = true
local blacklistWorldEvents
local reports = {}

local function number(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function same(record, subject)
    return record and record.membership == subject.membership and record.identityState ~= "unresolved"
        and record.id == subject.id and record.region == subject.region
        and record.fullName == subject.fullName and record.guid == subject.guid
end

local function blacklistGuid(record)
    return record.blacklistGuid or (record.lastKnown and record.lastKnown.guid)
end

local function sameBlacklist(record, subject)
    return same(record, subject) and record.createdAt == subject.createdAt and record.updatedAt == subject.updatedAt
        and blacklistGuid(record) == subject.blacklistGuid
end

local function blacklistRecord(subject)
    local record = A.store and A.store.get(subject.id)
    if sameBlacklist(record, subject) then return record end
end

function lookup.canCheckBlacklist(item)
    return item and item.membership == "blacklist" and item.identityState == "resolved"
        and not item.blacklistSavedClass and not item.blacklistWhoClass
        and P.CharacterName.IsComplete(item.fullName)
end

local function currentView(subject)
    for _, item in ipairs(A.records) do
        if same(item, subject) then return item end
    end
end

local function otherFaction(subject)
    if subject.membership == "blacklist" then
        local item = blacklistRecord(subject)
        local faction = item and item.lastKnown and item.lastKnown.faction
        if not faction then return false end
        local player = A.playerFaction(subject.region)
        return player ~= nil and player ~= faction.value
    end
    local item = currentView(subject)
    if not item or not item.faction then return false end
    local player = A.playerFaction(subject.region)
    item = currentView(subject)
    return player ~= nil and item and item.faction and player ~= item.faction
end

local function context(region)
    return A.region == region and read(GetCurrentRegion) == region and read(InCombatLockdown) == false
end

local function timerCancel(timer)
    if not readable(timer) then return end
    local ok, cancel = pcall(function() return timer.Cancel end)
    if ok and readable(cancel) and type(cancel) == "function" then return cancel end
end

local function repaint()
    A.refresh()
    P.Shell.RefreshFriends()
end

local function ownsSubject(work)
    local subject = work.subject
    if work.blacklist then return subject and blacklistRecord(subject) ~= nil end
    return subject and A.store and same(A.store.get(subject.id), subject)
        and A.targetCheck.attempts[subject.id] == work.attempt
end

local function blacklistEligible(work)
    if work.revision ~= contextRevision or not blacklistInWorld or not work.subject then return false end
    local record = blacklistRecord(work.subject)
    return record and not (record.lastKnown and record.lastKnown.class) and not reports[record.id]
end

local function blacklistIssue(work)
    if not blacklistInWorld then return "Who is unavailable outside the world." end
    local region = work.subject and work.subject.region
    if not region then return identityMessage end
    if A.region ~= region or read(GetCurrentRegion) ~= region then return "Who could not verify your current region." end
    local combat = read(InCombatLockdown)
    if combat == true then return combatMessage end
    if combat ~= false then return "Who could not verify combat state." end
    if not blacklistEligible(work) then return identityMessage end
end

local function finishBlacklist(work, message, accept)
    local subject = work.subject
    if accept and work.row and blacklistEligible(work) and context(subject.region) then
        local at = read(GetServerTime)
        local opposing = otherFaction(subject)
        if number(at) and not opposing and context(subject.region) and blacklistEligible(work) and not work.interrupted then
            if work.row.class then
                reports[subject.id] = {subject=subject, at=at, class=work.row.class}
                message = "Class found through Who."
            else
                message = "Who result has no class."
            end
        end
        if work.interrupted then message = "Who check yielded to another search." end
    end
    A.refresh()
    P.Shell.RefreshBlacklistMetadata()
    if ownsSubject(work) then work.notify(subject, message) end
end

local function finish(work, message, accept, validNoMatch)
    if pending ~= work then return end
    pending = nil
    if work.filter then pcall(work.remove, "CHAT_MSG_SYSTEM", work.filter) end
    if work.cancel then pcall(work.cancel, work.timer) end
    if work.blacklist then
        if ownsSubject(work) then finishBlacklist(work, message, accept) end
        if blacklistWork == work then blacklistWork = nil end
        return
    end
    if not ownsSubject(work) then return end
    local subject = work.subject
    local row
    if accept and work.row and context(subject.region) then
        local at = read(GetServerTime)
        local stamp = number(at) and read(date, "%Y-%m-%d %H:%M", at)
        if type(stamp) == "string" and stamp:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d$") then
            row = { subject=subject, at=at, stamp=stamp, class=work.row.class, level=work.row.level }
        end
    end
    if row and not context(subject.region) then row = nil end
    if not ownsSubject(work) then return end
    reports[subject.id] = row
    work.attempt.message = row and "Exact Who result found." or message
    work.attempt.observed = row ~= nil
    work.attempt.warning = not row and not validNoMatch
    repaint()
end

local function settle(work)
    if work.interrupted then finish(work, "Who check yielded to another search."); return end
    if work.conflicted then finish(work, "No fresh exact Who result."); return end
    if work.row then finish(work, "Who result became unavailable.", true)
    elseif work.empty then finish(work, "No exact Who result.", false, true)
    else finish(work, "No fresh exact Who result.") end
end

local function defer(work)
    if work.queued then return end
    work.queued = true
    -- Keep filtering the current event on the other chat frames before closing the request.
    pcall(work.after, 0, function() settle(work) end)
end

function lookup.install(enteringWorld)
    if api then return true end
    local native = C_FriendList
    if type(member(native, "SendWho")) ~= "function" or type(hooksecurefunc) ~= "function" then return false end
    local ok = pcall(hooksecurefunc, native, "SendWho", function(name, origin)
        if blacklistWork and blacklistWork.confirmed and pending ~= blacklistWork then
            blacklistWork.interrupted = true
        end
        local at = read(GetTime)
        lastSend = number(at) and at or math.huge
        local work = pending
        if not work then return end
        if work.calling and not work.confirmed and readable(name) and readable(origin)
            and name == work.name and origin == work.origin then
            work.confirmed = true
        else
            work.interrupted = true
            defer(work)
        end
    end)
    if ok then
        api = native
        blacklistWorldEvents = enteringWorld
    end
    return ok
end

local function nativeWhoClosed()
    if not readable(LFGWhoListFrame) then return false end
    local frame = LFGWhoListFrame
    if frame == nil then return true end
    return read(function() return frame:IsForbidden() end) == false
        and read(function() return frame:IsVisible() end) == false
end

local function filter(work, chatFrame, event, message)
    if pending ~= work or work.calling or not work.confirmed or work.interrupted or work.conflicted or not readable(event) or event ~= "CHAT_MSG_SYSTEM"
        or not readable(chatFrame) or (type(chatFrame) ~= "table" and type(chatFrame) ~= "userdata") then return false end
    local at = read(GetTime)
    if not number(at) or at < work.started or at >= work.started + window or not context(work.region) then return false end
    local stage = work.sequences[chatFrame]
    if stage == "closed" then return false end
    local kind, row = result.classify(api, work.name, message, work.singleTotal, work.emptyTotal)
    if not context(work.region) or pending ~= work or work.interrupted then return false end
    if not stage and kind == "row" and not work.empty then
        work.sequences[chatFrame] = row
        return true
    end
    if stage then
        work.sequences[chatFrame] = "closed"
        if kind == "total" and row.details == stage.details and not work.empty then
            if work.blacklist and (row.class ~= stage.class or (work.row and work.row.class ~= row.class)) then
                work.conflicted = true
                defer(work)
                return false
            end
            work.row = row
            defer(work)
            return true
        end
    elseif kind == "empty" and not work.row then
        work.sequences[chatFrame] = "closed"
        work.empty = true
        defer(work)
        return true
    end
    return false
end

local function request(work)
    local subject = work.subject
    if work.blacklist then
        local issue = blacklistIssue(work)
        if issue then return issue end
    elseif not ownsSubject(work) or not context(subject.region) then return end
    if otherFaction(subject) then return otherFactionMessage, true end
    if not api or work.blacklist and not blacklistWorldEvents then
        return work.blacklist and "Who request monitoring is unavailable." or nil
    end
    if not nativeWhoClosed() then
        return work.blacklist and "Close the Who tab before checking class."
            or "Close the Who tab before checking this Friend.", true
    end
    local item = not work.blacklist and currentView(subject)
    if item and (item.presence == "Seen" or item.presenceReport and item.presenceReport.source ~= "Who") then return end
    if not subject.fullName:match("^[^%s\"|%c]+ [^%s\"|%c]+$") then
        return work.blacklist and "Who needs the exact two-part character name." or nil
    end
    local at = read(GetTime)
    if not number(at) then return work.blacklist and "Who could not read the session clock." or nil end
    if pending or (lastSend and at - lastSend < window) then return lookup.cooldownMessage, true end
    local add = member(ChatFrameUtil, "AddMessageEventFilter")
    local remove = member(ChatFrameUtil, "RemoveMessageEventFilter")
    local origin = member(member(Enum, "SocialWhoOrigin"), "Chat")
    local disabled = member(member(Enum, "GameRule"), "IngameWhoListDisabled")
    local send = member(api, "SendWho")
    local timer, after = member(C_Timer, "NewTimer"), member(C_Timer, "After")
    if type(send) ~= "function" or type(origin) ~= "number" or type(member(api, "GetNumWhoResults")) ~= "function"
        or type(member(api, "GetWhoInfo")) ~= "function" then
        return work.blacklist and "Who search is unavailable in this client." or nil
    end
    local rule
    if type(disabled) == "number" then rule = read(member(C_GameRules, "IsGameRuleActive"), disabled) end
    if rule ~= false then
        return work.blacklist and (rule == true and "Who is disabled in this game mode."
            or "Who could not verify the game rules.") or nil
    end
    if type(add) ~= "function" or type(remove) ~= "function" then
        return work.blacklist and "Who chat filtering is unavailable." or nil
    end
    if type(timer) ~= "function" or type(after) ~= "function" then
        return work.blacklist and "Who timers are unavailable." or nil
    end
    local singleTotal, emptyTotal = result.totalText(1), result.totalText(0)
    if not singleTotal or not emptyTotal or singleTotal == emptyTotal then
        return work.blacklist and "Who could not read your client's result format." or nil
    end
    if pending or (lastSend and at - lastSend < window) then return lookup.cooldownMessage, true end
    work.name, work.region, work.origin, work.started = subject.fullName, subject.region, origin, at
    work.remove, work.after, work.singleTotal, work.emptyTotal, work.sequences = remove, after, singleTotal, emptyTotal, {}
    pending = work
    work.filter = function(...) return filter(work, ...) end
    local registered = pcall(add, "CHAT_MSG_SYSTEM", work.filter)
    if pending ~= work then
        pcall(remove, "CHAT_MSG_SYSTEM", work.filter)
        return
    end
    if not registered then
        finish(work, "Who could not register its chat filter.")
        return
    end
    local created, handle = pcall(timer, window, function() settle(work) end)
    local cancel = created and timerCancel(handle)
    if pending ~= work then
        if cancel then pcall(cancel, handle) end
        return
    end
    work.timer, work.cancel = handle, cancel
    local blockedByFaction = otherFaction(subject)
    if not cancel then
        finish(work, "Who could not start its timer.")
        return
    end
    if not nativeWhoClosed() then
        finish(work, work.blacklist and "Close the Who tab before checking class."
            or "Close the Who tab before checking this Friend.")
        return
    end
    local issue = work.blacklist and blacklistIssue(work)
    if issue then
        finish(work, issue)
        return
    end
    local valid = context(subject.region) and ownsSubject(work) and (not work.blacklist or blacklistEligible(work))
    if pending ~= work then return end
    if work.interrupted then
        settle(work)
        return
    end
    if not valid then
        finish(work, work.blacklist and identityMessage or "Who check unavailable.")
        return
    end
    if blockedByFaction then
        finish(work, otherFactionMessage)
        return otherFactionMessage, true
    end
    if work.attempt then reports[subject.id] = nil end
    work.calling = true
    lastSend = at
    local sent = pcall(send, work.name, origin)
    work.calling = false
    if pending ~= work then return end
    if not sent or not work.confirmed or work.interrupted then
        if work.blacklist and not work.interrupted then
            finish(work, sent and "Who could not confirm the search started." or "The client refused the Who search.")
        else settle(work) end
        if work.attempt then return work.attempt.message, work.attempt.warning end
        return
    end
    if work.blacklist then return "Checking Who…" end
    work.attempt.message = "Checking Who…"
    work.attempt.warning = false
    repaint()
    return work.attempt.message, work.attempt.warning
end

function lookup.request(subject)
    if subject.membership ~= "friend" then return end
    local attempt = A.targetCheck.attempts[subject.id]
    if not attempt then return end
    return request({subject=subject, attempt=attempt})
end

function lookup.requestBlacklist(subject, notify)
    if not lookup.canCheckBlacklist(subject) then return identityMessage end
    if blacklistWork then
        if blacklistWork.subject and blacklistWork.subject.id == subject.id then return "Who check already running." end
        return lookup.cooldownMessage
    end
    local work = {subject=subject, blacklist=true, notify=notify, revision=contextRevision}
    blacklistWork = work
    local function owns()
        return blacklistWork == work and blacklistEligible(work)
    end
    local message = blacklistIssue(work)
    if not message then
        local current = A.tryBlacklistMetadata(subject, owns)
        if current and work.subject and work.revision == contextRevision then
            work.subject = current
            if current.blacklistSavedClass then message = "Class found locally."
            else message = request(work) end
        else message = blacklistIssue(work) or identityMessage
        end
    end
    if blacklistWork == work and pending ~= work then blacklistWork = nil end
    return message
end

function lookup.running(id)
    return pending and pending.subject and pending.subject.id == id and not pending.interrupted
end

function lookup.cancel(enteringCombat)
    contextRevision = contextRevision + 1
    if not enteringCombat then blacklistInWorld = false end
    if pending then
        local combat = pending.blacklist and combatMessage or "Who check unavailable."
        finish(pending, enteringCombat and combat or "Who check ended on world exit.")
    end
end

function lookup.enterWorld()
    blacklistInWorld = true
end

function lookup.forget(id)
    reports[id] = nil
    if blacklistWork and blacklistWork.subject and blacklistWork.subject.id == id then blacklistWork.subject = nil end
    if pending and pending.subject and pending.subject.id == id then pending.subject = nil end
end

function lookup.hasReports()
    return next(reports) ~= nil
end

function lookup.apply(item, at)
    local report = reports[item.id]
    if not report then return end
    if report.subject.membership == "blacklist" then
        if not sameBlacklist(item, report.subject) or item.blacklistSavedClass
            or not at or at < report.at or at - report.at >= lifetime then
            reports[item.id] = nil
            return
        end
        item.blacklistWhoClass = report.class
        return report.at + lifetime
    end
    if not same(item, report.subject) then return end
    if not at or at < report.at or at - report.at >= lifetime then
        reports[item.id] = nil
        return
    end
    if item.localChecksOnly then return report.at + lifetime end
    if not item.presence and not item.presenceReport then
        item.presenceReport = { kind="listed", online=true, source="Who", checked=report.stamp }
        item.class, item.level = item.class or report.class, item.level or report.level
        if item.class then item.evidenceName = item.fullName end
    end
    return report.at + lifetime
end
