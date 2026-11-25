-- SIMULATED widgets only; deliberately no unknown-method catch-all.
local H = {forbiddenCalls=0}
function H.fresh(_, preferences, viewport, manual)
    local s = {nodes={}, forbiddenCalls=0,loadedFiles={}}
    local e = setmetatable({}, {__index=_G}); e._G=e
    e.unpack=table.unpack or unpack; e.SlashCmdList={}; e.UISpecialFrames={}
    e.WhowhoPreviewDB=preferences
    if manual then
        e.WhowhoAddressBookDB=manual.db
        e.GetCurrentRegion=function() return manual.region end
        e.GetServerTime=function() return manual.time end
        e.UnitNameUnmodified=function() return "Current","Character" end
        e.UnitIsUnit=function(unit,other) return unit==other end
        e.C_Secrets={ShouldUnitIdentityBeSecret=function() return false end}
        e.strcmputf8i=function(a,b) return a:lower()==b:lower() and 0 or 1 end
    end
    e.IsInInstance=function() return false,"none" end
    local function poison() s.forbiddenCalls=s.forbiddenCalls+1; H.forbiddenCalls=H.forbiddenCalls+1; error("native action/observation forbidden in UI preview") end
    for _,n in ipairs({"SendWho","InviteUnit","Screenshot","PlaySound","PlaySoundFile","UnitName","GetUnitName","UnitGUID","UnitClass","UnitLevel","GetNumGroupMembers","GetFriendInfo","GetNumFriends","SendAddonMessage","GetTime","ChatFrame_AddMessageEventFilter","ChatFrame_RemoveMessageEventFilter","CastSpellByName","UseItemByName","SendChatMessage"}) do e[n]=poison end
    if manual then e.GetTime=function() return manual.time end end
    s.secret={}; e.issecretvalue=function(v) return rawequal(v,s.secret) end
    e.issecrettable=function() return false end
    local guarded=setmetatable({}, {__index=function() return poison end})
    e.SetCVar=poison; e.C_CVar=guarded
    e.C_FriendList=manual and setmetatable({IsLegacyFriendSystemEnabled=false}, getmetatable(guarded)) or guarded
    e.C_PartyInfo=manual and {InviteUnit=poison} or guarded
    e.C_Timer=guarded; e.C_Sound=manual and {} or guarded; e.C_NamePlate=manual and {} or guarded; e.C_ChatInfo=guarded; e.ChatFrameUtil=manual and {} or guarded
    local methods={}
    local function node(kind,name,parent)
        local f=setmetatable({id=#s.nodes+1,kind=kind,name=name,parent=parent,scripts={},events={},points={},shown=true,enabled=true,width=0,height=0,children={}}, {__index=methods})
        s.nodes[#s.nodes+1]=f; if parent then parent.children[#parent.children+1]=f end
        if name then e[name]=f end
        return f
    end
    function methods:SetSize(w,h) self.width=w; self.height=h end
    function methods:SetWidth(w) self.width=w end
    function methods:SetHeight(h) self.height=h end
    function methods:GetWidth() return self.width end
    function methods:GetHeight() return self.height end
    function methods:SetPoint(...) self.points[#self.points+1]={...} end
    function methods:GetPoint(i) return e.unpack(self.points[i or 1] or {}) end
    function methods:ClearAllPoints() self.points={}; self.allPoints=nil end
    function methods:SetAllPoints(target) self.allPoints=target or self.parent end
    function methods:SetParent(p) self.parent=p end
    function methods:GetParent() return self.parent end
    function methods:SetScript(k,fn)
        self.handlers=self.handlers or {}
        self.handlers[k]=fn
        local hooks=self.hooks and self.hooks[k]
        if not hooks then self.scripts[k]=fn; return end
        self.scripts[k]=function(...)
            if fn then fn(...) end
            for _,hook in ipairs(hooks) do hook(...) end
        end
    end
    function methods:GetScript(k) return self.handlers and self.handlers[k] end
    function methods:HookScript(k,fn)
        self.hooks=self.hooks or {}
        self.hooks[k]=self.hooks[k] or {}
        table.insert(self.hooks[k],fn)
        self:SetScript(k,self:GetScript(k))
        return true
    end
    function methods:RegisterEvent(k) self.events[k]=true; return true end
    function methods:UnregisterEvent(k) self.events[k]=nil end
    function methods:SetText(v,r,g,b,alpha,wrap)
        if self.kind=="GameTooltip" then
            assert(type(v)=="string","GameTooltip text must be string")
            for i,x in pairs({r=r,g=g,b=b,alpha=alpha}) do assert(type(x)=="number","GameTooltip "..i.." must be number") end
            assert(wrap==nil or type(wrap)=="boolean","GameTooltip wrap must be boolean")
            self.tooltipArgs={r=r,g=g,b=b,alpha=alpha,wrap=wrap}
        end
        self.text=tostring(v or ""); self.highlight=nil; self.cursor=#self.text
        if self.SetMultiLineArgs and self.SetMultiLineArgs[1] then
            local inset=self.SetTextInsetsArgs
            self:SetHeight(self:GetStringHeight()+inset[3]+inset[4])
            local view=self.parent
            if view.scrollChild==self and view.scripts.OnScrollRangeChanged then
                view.scripts.OnScrollRangeChanged(view,0,view:GetVerticalScrollRange())
            end
        end
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self,false) end
    end
    function methods:GetText() return self.text or "" end
    -- Conservative synthetic layout metrics. The client measures native glyphs.
    function methods:GetStringWidth()
        local _,size=self:GetFont()
        local _,count=self:GetText():gsub("[^\128-\191]","")
        return count*size*.56
    end
    methods.GetUnboundedStringWidth=methods.GetStringWidth
    function methods:GetStringHeight()
        local _,size=self:GetFont()
        local cols=self:GetWidth()>0 and math.max(1,math.floor(self:GetWidth()/math.max(1,size*.56))) or math.huge
        local lines=0
        for line in (self:GetText().."\n"):gmatch("(.-)\n") do
            local count=0
            for _ in line:gmatch("[^\128-\191]") do count=count+1 end
            lines=lines+math.max(1,math.ceil(count/cols))
        end
        return math.ceil(size*1.3)*lines
    end
    function methods:IsMouseOver() return self.pointerOver==true end
    function methods:IsDraggingThumb() return self.draggingThumb==true end
    function methods:SetFocus()
        if not self.enabled then return end
        for _,other in ipairs(s.nodes) do if other~=self and other.focused then other:ClearFocus() end end
        self.focused=true; if self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self) end
    end
    function methods:ClearFocus() self.focused=false; if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end end
    function methods:HasFocus() return self.focused or false end
    function methods:SetHighlightColor(...) self.highlightColor={...} end
    function methods:HighlightText(a,b) self.highlight={a or 0,b or -1} end
    function methods:GetCursorPosition() return self.cursor or 0 end
    function methods:SetCursorPosition(v) self.cursor=math.max(0,math.min(#self:GetText(),v)) end
    function methods:Insert(value)
        local text=self:GetText(); local a,b=self.cursor or #text,self.cursor or #text
        if self.highlight then a,b=self.highlight[1],self.highlight[2]; if b<0 then b=#text end end
        self.text=text:sub(1,a)..value..text:sub(b+1); self.cursor=a+#value; self.highlight=nil
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self,true) end
    end
    function methods:Show() local old=self.shown; self.shown=true; if not old and self.scripts.OnShow then self.scripts.OnShow(self) end end
    function methods:Hide() local old=self.shown; self.shown=false; if old and self.scripts.OnHide then self.scripts.OnHide(self) end end
    function methods:IsShown() return self.shown end
    function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function methods:SetShown(v) if v then self:Show() else self:Hide() end end
    function methods:Enable() self.enabled=true end
    function methods:Disable() self.enabled=false end
    function methods:SetEnabled(v) self.enabled=not not v end
    function methods:IsEnabled() return self.enabled end
    function methods:Click(button) if self.enabled and self.scripts.OnClick then self.scripts.OnClick(self,button or "LeftButton") end end
    function methods:CreateLine(name,layer) local v=node("Line",name,self); v.layer=layer; return v end
    function methods:SetStartPoint(...) self.startPoint={...} end
    function methods:SetEndPoint(...) self.endPoint={...} end
    function methods:SetThickness(value) self.thickness=value end
    function methods:CreateTexture(name,layer) local v=node("Texture",name,self); v.layer=layer; return v end
    function methods:CreateFontString(name,layer,font) local v=node("FontString",name,self); v.layer=layer; v.font=font; return v end
    function methods:SetColorTexture(...) self.color={...} end
    function methods:SetTextColor(...) self.textColor={...} end
    function methods:SetVertexColor(...) self.vertexColor={...} end
    function methods:SetDesaturated(value) self.desaturated=value end
    function methods:SetTexture(v) self.texture=v; self.color=nil end
    function methods:SetTextureSliceMargins(...) self.sliceMargins={...} end
    function methods:SetAtlas(v,useAtlasSize) self.atlas=v; self.useAtlasSize=useAtlasSize end
    function methods:GetAtlas() return self.atlas end
    function methods:SetTexCoord(...) self.texCoord={...} end
    function methods:SetRotation(v) self.rotation=v end
    function methods:SetOrientation(v) self.orientation=v end
    function methods:SetShadowColor(...) self.shadowColor={...} end
    function methods:SetShadowOffset(...) self.shadowOffset={...} end
    function methods:SetSpacing(v) self.spacing=v end
    function methods:SetThumbTexture(v) self.thumbAsset=v; self.thumb=node("Texture",nil,self) end
    function methods:GetThumbTexture() return self.thumb end
    function methods:SetFontObject(v) self.font=v end
    function methods:SetFont(...) self.fontStyle={...} end
    function methods:GetFont()
        if self.fontStyle then return e.unpack(self.fontStyle) end
        -- Deterministic stand-ins, not measured Forever font paths or metrics.
        local object=tostring(self.font or "GameFontNormal")
        local size=object:find("Large",1,true) and 16 or (object:find("Small",1,true) and 10 or 12)
        return "SIMULATED_NATIVE_FONT",size,""
    end
    function methods:SetJustifyH(v) self.justifyH=v end
    function methods:SetJustifyV(v) self.justifyV=v end
    function methods:SetFrameStrata(v) self.strata=v end
    function methods:GetFrameStrata() return self.strata or (self.parent and self.parent:GetFrameStrata()) or "MEDIUM" end
    function methods:SetFrameLevel(v) self.level=v end
    function methods:GetFrameLevel() return self.level or (self.parent and self.parent:GetFrameLevel()+1) or 0 end
    function methods:SetToplevel(v) self.topLevel=v end
    function methods:Raise() self.raises=(self.raises or 0)+1 end
    function methods:SetScale(v) self.scale=v end
    function methods:GetScale() return self.scale or 1 end
    function methods:GetEffectiveScale() return self:GetScale()*(self.parent and self.parent:GetEffectiveScale() or 1) end
    function methods:GetCenter() return 1190,90 end -- deterministic drag fixture, not native coordinates
    function methods:SetChecked(v) self.checked=v end
    function methods:GetChecked() return self.checked end
    function methods:SetOwner(owner,anchor) self.owner=owner; self.ownerAnchor=anchor end
    function methods:GetOwner() return self.owner end
    function methods:AddLine(v) self.text=(self.text or "").."\n"..v end
    function methods:SetScrollChild(v) self.scrollChild=v end
    function methods:SetVerticalScroll(v) self.verticalScroll=v; if self.scripts.OnVerticalScroll then self.scripts.OnVerticalScroll(self,v) end end
    function methods:GetVerticalScroll() return self.verticalScroll or 0 end
    function methods:GetVerticalScrollRange() return math.max(0,self.scrollChild:GetHeight()-self:GetHeight()) end
    -- Known input configuration methods: retained for contract inspection.
    for _,k in ipairs({"SetMovable","SetClampedToScreen","EnableMouse","EnableMouseWheel","SetMouseClickEnabled","SetMouseMotionEnabled","SetPropagateMouseClicks","SetPropagateMouseMotion","RegisterForDrag","RegisterForClicks","SetAutoFocus","SetMultiLine","SetMaxLetters","SetTextInsets","SetNumeric","SetObeyStepOnDrag","SetMinMaxValues","SetValueStep","SetHitRectInsets","SetAlpha","SetWordWrap","SetNonSpaceWrap","SetClipsChildren"}) do
        methods[k]=function(self,...) self[k.."Args"]={...} end
    end
    function methods:StartMoving() self.moving=true end
    function methods:StopMovingOrSizing() self.moving=false end
    function methods:SetValue(v) self.value=v; if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,v) end end
    function methods:GetValue() return self.value or 0 end
    e.CreateFrame=function(kind,name,parent,template) local f=node(kind,name,parent); f.template=template; return f end
    e.GetCursorPosition=function() return 1210,110 end
    e.IsMouseButtonDown=function(button) return button=="LeftButton" and s.leftDown==true end
    -- Forever exposes this extension; Fengari's standard math library does not.
    e.math=setmetatable({atan2=math.atan2 or function(y,x) return math.atan(y,x) end},{__index=math})
    e.UIParent=node("Frame","UIParent"); e.UIParent:SetSize(viewport and viewport[1] or 1280,viewport and viewport[2] or 800)
    e.Minimap=node("Frame","Minimap",e.UIParent); e.Minimap:SetSize(140,140); e.Minimap:SetPoint("TOPRIGHT",e.UIParent,"TOPRIGHT",-20,-20)
    e.GameTooltip=node("GameTooltip","GameTooltip",e.UIParent); e.GameTooltip:Hide()
    s.env=e
    local namespace={}
    -- Load the runnable package's real entry order, including future small modules.
    -- Fengari intentionally has no io.open; the Python/scene caller provides the TOC text.
    local addon=assert(os.getenv("WHOWHO_ADDON_ROOT"),"set WHOWHO_ADDON_ROOT to the addon directory")
    local tocText=assert(os.getenv("WHOWHO_PREVIEW_TOC"),"set WHOWHO_PREVIEW_TOC to the actual addon TOC contents")
    for line in (tocText.."\n"):gmatch("([^\n]*)\n") do
        local file=line:match("^%s*(.-)%s*$")
        if file~="" and file:sub(1,1)~="#" then
            assert(file:match("^[A-Za-z][A-Za-z0-9]*%.lua$"),"invalid Lua entry in TOC")
            local path=addon.."/"..file
            local chunk
            if _VERSION=="Lua 5.1" then chunk=assert(loadfile(path)); setfenv(chunk,e) else chunk=assert(loadfile(path,"t",e)) end
            chunk("WhoWho",namespace)
            s.loadedFiles[#s.loadedFiles+1]=file
        end
    end
    function s:event(event,...)
        local limit=#self.nodes
        for i=1,limit do local f=self.nodes[i]; if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f,event,...) end end
    end
    function s:fire(f,event,...) assert(f and f.scripts[event],"missing widget handler "..event); return f.scripts[event](f,...) end
    -- Tests supply the rectangles hit by one synthetic pointer. This models
    -- input ownership only; native frame hit testing is a client check.
    function s:routePointer(candidates,event,...)
        local hits={}
        for _,node in ipairs(self.nodes) do node.pointerOver=false end
        for _,target in ipairs(candidates) do
            if target:IsVisible() then
                local depth,ancestor=0,target
                while ancestor do ancestor.pointerOver=true; depth=depth+1; ancestor=ancestor.parent end
                local mouse=target.EnableMouseArgs
                local enabled=mouse and mouse[1] or (not mouse and (target.kind=="Button" or target.kind=="Slider"))
                if event=="OnMouseWheel" then
                    enabled=target.EnableMouseWheelArgs and target.EnableMouseWheelArgs[1]
                elseif event=="OnEnter" or event=="OnLeave" then
                    if target.SetMouseMotionEnabledArgs then enabled=target.SetMouseMotionEnabledArgs[1] end
                elseif target.SetMouseClickEnabledArgs then
                    enabled=target.SetMouseClickEnabledArgs[1]
                end
                if enabled then hits[#hits+1]={frame=target,depth=depth,level=target:GetFrameLevel()} end
            end
        end
        table.sort(hits,function(a,b)
            if a.level~=b.level then return a.level>b.level end
            if a.depth~=b.depth then return a.depth>b.depth end
            return a.frame.id>b.frame.id
        end)
        local owner=hits[1] and hits[1].frame
        if event=="OnEnter" and self.hoverOwner~=owner then
            local old=self.hoverOwner
            if old and old.scripts.OnLeave then old.scripts.OnLeave(old) end
            self.hoverOwner=owner
        end
        for _,hit in ipairs(hits) do
            local frame=hit.frame
            if event=="OnClick" then frame:Click(...)
            elseif frame.scripts[event] then frame.scripts[event](frame,...) end
            local pass=frame.SetPropagateMouseClicksArgs
            if event=="OnEnter" then pass=frame.SetPropagateMouseMotionArgs end
            if event=="OnMouseWheel" or not (pass and pass[1]) then break end
        end
        return owner
    end
    return e.WhowhoPreview,s,e
end
return H
