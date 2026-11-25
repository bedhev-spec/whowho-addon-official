local P = WhowhoPreview
local L = {}
P.Launcher = L
local function position()
    local angle = math.rad(P.db.minimapAngle or 225)
    L.button:ClearAllPoints()
    L.button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle)*Minimap:GetWidth()/2, math.sin(angle)*Minimap:GetHeight()/2)
end
function L.Create()
    if L.button then return end
    local b = CreateFrame("Button", "WhowhoPreviewMinimapButton", Minimap)
    L.button=b; b:SetSize(32,32); b:SetFrameStrata("MEDIUM"); b:RegisterForDrag("LeftButton")
    local icon=b:CreateTexture(nil,"ARTWORK"); icon:SetAllPoints(b); icon:SetTexture(P.media .. "MinimapIcon.tga")
    P.BindButtonFeedback(b,function(self)
        local tint=self.pressed and .72 or self.hovered and .9 or 1
        icon:SetVertexColor(tint,tint,tint,1)
    end)
    b:SetScript("OnClick",function() P.Init(); P.Shell.Open() end)
    b:SetScript("OnEnter",function(self) P.ShowTooltip(self,P.L("WhoWho Preview"),"ANCHOR_LEFT"); GameTooltip:AddLine(P.L("Click to open or raise · Drag to move"),1,1,1); GameTooltip:Show() end)
    b:SetScript("OnLeave",function(self) P.HideTooltip(self) end)
    b:SetScript("OnDragStart",function(self)
        P.ResetButtonFeedback(self)
        self:SetScript("OnUpdate",function()
            local x,y=GetCursorPosition(); local scale=Minimap:GetEffectiveScale(); local cx,cy=Minimap:GetCenter()
            if cx and cy and scale and scale > 0 then P.db.minimapAngle=math.deg(math.atan2(y/scale-cy,x/scale-cx)); position() end
        end)
    end)
    b:SetScript("OnDragStop",function(self) self:SetScript("OnUpdate",nil) end)
    Minimap:HookScript("OnSizeChanged",position)
    position(); b:Show()
end
