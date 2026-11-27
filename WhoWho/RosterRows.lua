local P=WhowhoPreview
local R={}
P.RosterRows=R
local L,C=P.L,P.colors
local roster=P.RosterModel
local roleNames=P.roleNames
local rosterRoleIconGap,classMarkerGap=3,6

local classNames={DEATHKNIGHT="Death Knight",DEMONHUNTER="Demon Hunter"}
function R.ClassName(token)
    if not token then return L("Class unknown") end
    return L(classNames[token] or token:sub(1,1) .. token:sub(2):lower())
end
local function displayText(text) return (text:gsub("|","||")) end
local presence=roster.Presence

function R.PresenceStyle(record,state)
    local color=state=="Online" and C.online or C.body
    if state=="Listed" then color=record.presenceReport.online and C.online or C.listedOffline end
    local glyph=state=="Online" and "online" or state=="Seen" and "seen" or nil
    return color,glyph
end
local function placeLabel(parent, text, x, y, font, color)
    local label = P.Label(parent, L(text), font, color)
    label:SetPoint("TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    return label
end
local function sameOwner(a,b,guild)
    if a==b then return true end
    if not a or not b then return false end
    -- Guild records are rebuilt on refresh. Their IDs include the guild scope.
    if guild then return a.id==b.id end
    return roster.SameIdentity(a,b)
end
local function invalidateRowBinding(row)
    row.binding=(row.binding or 0)+1
end
function R.ClearHover(row)
    for _,button in pairs({row,row.copyButton,row.inviteButton,row.deleteButton,row.favoriteButton,row.statusHover}) do
        P.ResetButtonFeedback(button)
    end
    if row.statusHover then P.HideTooltip(row.statusHover) end
end
local unknownPresenceHint="No verified online/offline information is available for this player."
function R.PresenceHint(record)
    local state=presence(record)
    if state=="Unknown" or state=="Seen" then return L(unknownPresenceHint) end
    if state=="Listed" or state=="Checked" then return L("Last known status. It may have changed.") end
end
function R.BindPresenceHover(hover,icon,label,record,glyph)
    if not hover then return end
    local hint=record and R.PresenceHint(record)
    if hover.presenceHint~=hint then P.HideTooltip(hover) end
    hover.presenceHint=hint
    hover:ClearAllPoints()
    if glyph then
        hover:SetSize(28,28); hover:SetPoint("CENTER",icon,"CENTER")
    else
        hover:SetPoint("TOPLEFT",label,"TOPLEFT"); hover:SetPoint("BOTTOMRIGHT",label,"BOTTOMRIGHT")
    end
    hover:SetShown(hint~=nil)
end
function R.FitName(row, width, showClass)
    local unknown=showClass and row.record~=nil and not row.record.class
    row.classMarker:SetShown(unknown)
    if unknown then
        local space=width-classMarkerGap-row.classMarker:GetWidth()
        width=math.max(1,math.min(math.ceil(row.name:GetUnboundedStringWidth()),space))
    end
    row.name:SetWidth(width)
end

local function bindClick(row,button,action)
    local pressed
    button:HookScript("OnMouseDown",function(_,key)
        if key=="LeftButton" then
            pressed={record=row.record,owner=row.inputOwner,binding=row.binding,muted=row.chatMuted}
        end
    end)
    button:SetScript("OnClick",function(self,key)
        local press=pressed
        pressed=nil
        -- Keep a stale press until release so it cannot look like a direct click on the new owner.
        if press and (not press.record or press.owner~=row.inputOwner) then return end
        action(row,self,key,press)
    end)
end

function R.Bind(row,record,section,selectedId,actionAvailable,inviteIssue,chatMuted)
    local guild=section=="guildBlacklist"
    local personal=section=="blacklist"
    local blacklist=personal or guild
    local previous=row.record
    if row.section~=section or not sameOwner(previous,record,guild) then
        row.inputOwner=(row.inputOwner or 0)+1
    end
    if previous~=record then
        R.ClearHover(row)
        invalidateRowBinding(row)
    end
    row.record,row.section=record,section
    if personal then
        row.chatMuted=chatMuted
        P.SetEnabled(row.inviteButton,actionAvailable)
        row.muteIcon:SetVertexColor(unpack(actionAvailable and C.body or C.disabled))
    elseif section=="friend" then
        row.inviteIssue=inviteIssue
        P.SetEnabled(row.inviteButton,actionAvailable)
        row.inviteIcon:SetVertexColor(unpack(actionAvailable and C.body or C.disabled))
    else
        row.inviteButton:Disable()
    end
    if row.muteSlash then row.muteSlash:SetShown(personal and row.chatMuted==true or false) end
    row.copyButton:SetShown(not guild); row.inviteButton:SetShown(not guild)
    if row.deleteButton then
        local enabled=not guild or actionAvailable==true
        P.SetEnabled(row.deleteButton,enabled)
        row.deleteGlyph:SetVertexColor(unpack(enabled and C.deleteGlyph or C.disabled))
    end
    if row.favoriteButton then
        local show=record and record.membership=="friend" and record.identityState~="unresolved"
        row.favoriteButton:SetShown(show==true)
        if show then
            local x=record.favorite and 32 or 0
            row.favoriteGlyph:SetTexCoord((x+4)/64,(x+28)/64,4/32,28/32)
            row.favoriteGlyph:SetVertexColor(unpack(record.favorite and C.gold or C.muted))
        end
    end
    if record then
        row.copyButton:SetEnabled(record.identityState~="unresolved")
        row.selected=record.id==selectedId
        row.selectedColor=C.friendSelected
        P.UpdateButton(row)
        row.leadingEdge:SetShown(row.selected)
        P.SetPaletteFill(row.rule,C.rowRule)
        row.name:SetText(guild and displayText(record.fullName) or record.fullName)
        if blacklist then
            row.name:SetTextColor(P.NameColor(personal and record or nil,true,roster.DisplayClass(record,personal)))
        else
            row.name:SetTextColor(P.NameColor(record,true))
        end
        row.meta:SetWidth(0)
        row.meta:SetText(blacklist and "" or R.ClassName(record.class) .. (record.level and (" · " .. record.level) or ""))
        row.role:SetText(blacklist and "" or L(roleNames[record.role] or ""))
        P.ShowRoleIcon(row.roleIcon,not blacklist and record.role or nil)
        local roleGap=row.roleIcon:IsShown() and 8+row.roleIcon:GetWidth()+rosterRoleIconGap or 8
        row.role:ClearAllPoints()
        row.role:SetPoint("LEFT",row.meta,"RIGHT",roleGap,0)
        local summary
        if blacklist then
            summary=P.manual.reasonText(record.reasonIds)
        else
            summary=record.note and record.note:match("[^\r\n]+") or L("No note")
        end
        row.note:SetText(summary)
        local glyph
        if blacklist then
            row.status:SetText("")
        else
            local state,caption=presence(record)
            local color
            color,glyph=R.PresenceStyle(record,state)
            row.status:SetText(L(caption))
            row.status:SetTextColor(unpack(color))
            if glyph then P.SetGlyph(row.statusIcon,glyph,state=="Online" and C.online or C.muted) end
        end
        row.statusIcon:SetShown(glyph~=nil)
        R.BindPresenceHover(row.statusHover,row.statusIcon,row.status,not blacklist and record or nil,glyph)
        row.inviteIcon:SetShown(section=="friend"); row.muteIcon:SetShown(section=="blacklist")
        row:Show()
    else
        row.selected=false
        row.copyButton:Disable()
        row.name:SetText("")
        row.meta:SetText("")
        row.role:SetText("")
        row.roleIcon:Hide()
        row.note:SetText("")
        row.status:SetText("")
        row.name:SetTextColor(P.NameColor())
        row:Hide()
    end
end

local function createRow(parent,actions)
    local row=P.Button(parent,"",638,P.LayoutMetrics.rowHeight,nil,"row")
    bindClick(row,row,actions.select)
    row:HookScript("OnHide",function() row.inputOwner=(row.inputOwner or 0)+1 end)
    P.RosterRowChrome(row)
    row.name=placeLabel(row,"",22,-9,"name",C.text); row.name:SetHeight(24); row.name:SetJustifyV("MIDDLE"); row.name:SetWordWrap(false)
    row.classMarker=P.Label(row,"(?)","meta",C.muted)
    row.classMarker:SetPoint("LEFT",row.name,"RIGHT",classMarkerGap,0)
    row.classMarker:SetWidth(math.ceil(row.classMarker:GetUnboundedStringWidth()))
    row.classMarker:Hide()
    row.meta=P.Label(row,"","meta",C.body); row.meta:SetPoint("LEFT",22,0)
    row.role=P.Label(row,"","meta",C.body)
    row.roleIcon=P.RoleIcon(row,row.role,17,rosterRoleIconGap)
    row.note=placeLabel(row,"",22,-54,"meta",C.muted); row.note:SetWordWrap(false)
    row.status=P.Label(row,"","body",C.body)
    for _,caption in ipairs({row.meta,row.role,row.status}) do
        caption:SetHeight(24); caption:SetJustifyH("LEFT"); caption:SetJustifyV("MIDDLE"); caption:SetWordWrap(false)
    end
    row.statusIcon=P.Glyph(row,"unknown",20,C.muted)
    do
        row.favoriteButton=P.Button(row,"",34,34,nil,"action")
        bindClick(row,row.favoriteButton,actions.favorite)
        row.favoriteButton:SetPoint("TOPLEFT",6,-4)
        row.favoriteButton:HookScript("OnEnter",function(self)
            if row.record and not actions.blocked() then
                P.ShowTooltip(self,L(row.record.favorite and "Remove from Favorites" or "Add to Favorites"))
            end
        end)
        row.favoriteButton:HookScript("OnLeave",function(self) P.HideTooltip(self) end)
        row.favoriteGlyph=row.favoriteButton:CreateTexture(nil,"ARTWORK")
        row.favoriteGlyph:SetSize(22,22); row.favoriteGlyph:SetPoint("CENTER")
        row.favoriteGlyph:SetTexture(P.media.."LedgerFavorite.tga")
        row.statusHover=P.Button(row,"",28,28,nil,"action"); row.statusHover:SetPoint("CENTER",row.statusIcon,"CENTER")
        bindClick(row,row.statusHover,actions.select)
        row.statusHover:SetScript("OnEnter",function(self)
            local record=row.record
            local hint=record and R.PresenceHint(record)
            if hint and not actions.blocked() then P.ShowTooltip(self,hint) end
        end)
        row.statusHover:SetScript("OnLeave",function(self) P.HideTooltip(self) end)
    end
    row.copyButton=P.CopyNameButton(row,"")
    bindClick(row,row.copyButton,actions.copy)
    row.copyButton:SetPoint("RIGHT",-52,0)
    row.copyButton:HookScript("OnEnter",function(self)
        if actions.blocked() then R.ClearHover(row)
        elseif row.record then P.ShowTooltip(self,L("Copy %s",row.record.fullName)) end
    end)
    row.copyButton:HookScript("OnLeave",function(self) P.HideTooltip(self) end)
    row.inviteButton=P.Button(row,"",34,34,nil,"action"); row.inviteButton:SetPoint("RIGHT",-8,0); row.inviteButton:Disable()
    do
        bindClick(row,row.inviteButton,actions.inviteOrMute)
        row.inviteButton:HookScript("OnHide",function() invalidateRowBinding(row) end)
        row.inviteButton:ClearAllPoints(); row.inviteButton:SetPoint("RIGHT",-80,0)
        row.copyButton:ClearAllPoints(); row.copyButton:SetPoint("RIGHT",-44,0)
        row.deleteButton=P.Button(row,"",34,34,nil,"action")
        bindClick(row,row.deleteButton,actions.delete)
        row.deleteButton:SetPoint("RIGHT",-8,0)
        row.deleteGlyph=P.ActionGlyph(row.deleteButton,"close",22,C.deleteGlyph); row.deleteGlyph:SetPoint("CENTER")
        P.Tooltip(row.deleteButton,L("Delete entry"))
    end
    row.inviteIcon=P.ActionGlyph(row.inviteButton,"plus",20,C.disabled); row.inviteIcon:SetPoint("CENTER",row.inviteButton,"CENTER",0,0)
    row.muteIcon=P.ActionGlyph(row.inviteButton,"mute",18,C.disabled); row.muteIcon:SetPoint("CENTER",row.inviteButton,"CENTER",0,0)
    do
        row.muteSlash=row.inviteButton:CreateLine(nil,"OVERLAY")
        row.muteSlash:SetStartPoint("CENTER",row.inviteButton,-6,-6)
        row.muteSlash:SetEndPoint("CENTER",row.inviteButton,6,6)
        row.muteSlash:SetThickness(2)
        row.muteSlash:SetColorTexture(unpack(C.body))
        row.muteSlash:Hide()
    end
    row.inviteButton:HookScript("OnEnter",function(self)
        if not row.record or actions.blocked() then return end
        if row.section=="friend" then
            P.ShowTooltip(self,row.inviteIssue and L(row.inviteIssue) or L("Invite %s",row.record.fullName))
        else
            local caption="Chat muting unavailable for %s"
            if self:IsEnabled() then
                caption=row.chatMuted and "Chat muted · Unmute %s" or "Mute chat from %s"
            end
            P.ShowTooltip(self,L(caption,row.record.fullName))
        end
    end)
    row.inviteButton:HookScript("OnLeave",function(self) P.HideTooltip(self) end)
    row:HookScript("OnEnter",function(self) if actions.blocked() then R.ClearHover(self) end end)
    return row
end

function R.Create(parent,actions)
    local rows={}
    for i=1,10 do rows[i]=createRow(parent,actions) end
    return rows
end
