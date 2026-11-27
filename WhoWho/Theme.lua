local addonName = ...
WhowhoPreview = WhowhoPreview or {}
local P = WhowhoPreview
P.version = "WW05-preview-r6"
P.media = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

local function rgb(hex)
    return {tonumber(hex:sub(1,2),16)/255, tonumber(hex:sub(3,4),16)/255, tonumber(hex:sub(5,6),16)/255, 1}
end
P.colors = {
    background=rgb("111619"), panel=rgb("171D20"), header=rgb("20282B"), raised=rgb("242C30"), railTint={0,0,0,0},
    selected=rgb("18292D"), friendSelected=rgb("23363A"), hover=rgb("2A3439"), pressed=rgb("121C20"),
    selectedHover=rgb("21383E"), selectedPressed=rgb("142226"),
    line=rgb("465055"), rowRule=rgb("343F44"), selectedRule=rgb("79BCC1"),
    bronze=rgb("9E7860"), copper=rgb("E7AB75"), copperHover=rgb("EFBB8C"), copperPressed=rgb("C99367"),
    danger=rgb("8C3D36"), dangerHover=rgb("A84C43"), dangerPressed=rgb("6F302B"),
    noteInset=rgb("1C2428"), controlBorder=rgb("68777C"), controlTrack=rgb("465055"), gold=rgb("F2EEE5"), ink=rgb("281B14"), warning=rgb("F4CB7B"),
    text=rgb("F2EEE5"), priest=rgb("FFF1CE"), body=rgb("D5DBD9"), muted=rgb("B0BCBC"), disabled=rgb("889396"),
    selection=rgb("345863"), teal=rgb("9CDCE0"), online=rgb("B7D58D"), listedOffline=rgb("B0BCBC"), deleteGlyph=rgb("C98279"),
    tooltipFriendRim=rgb("8EE69B"), tooltipBlacklistRim=rgb("FF958A"),
    clear={0,0,0,0}, actionHover={1,1,1,.075}, actionPressed={.61,.86,.88,.24}
}
local C = P.colors
local defaultPalette="default"
local cyanSlate="cyanSlate"
P.interfaceColors = {
    {id=defaultPalette,label="Default",swatch=rgb("7C9A9E")},
    {id=cyanSlate,label="Cyan Slate",swatch=rgb("86CCD1"),colors={
        background="131A1D",panel="131A1D",header="202A2E",raised="202A2E",noteInset="1B2428",
        selected="1A3035",friendSelected="1A3035",hover="223136",selectedHover="223136",
        selectedRule="86CCD1",teal="86CCD1",controlBorder="64777D",controlTrack="64777D",
        copper="F0AE78",copperHover="F5BC90",copperPressed="D99868",ink="201710"
    }},
    {id="slateBlue",label="Harbor Blue",colors={
        background="131B25",panel="131B25",header="1D2938",raised="1D2938",noteInset="192332",railTint="1D2938",
        selected="233349",friendSelected="233349",hover="26374B",pressed="141E2C",selectedHover="2A3C53",selectedPressed="192738",
        selectedRule="91C2E8",selection="3A5578",teal="91C2E8",controlBorder="687D97",controlTrack="687D97",
        copper="B0CEF0",copperHover="C3DBF5",copperPressed="94B4D9",ink="141E2C"
    }},
    {id="forestGreen",label="Moss Green",colors={
        background="171D18",panel="171D18",header="242D25",raised="242D25",noteInset="1F2820",railTint="242D25",
        selected="27362C",friendSelected="27362C",hover="2B382E",pressed="182218",selectedHover="2E3F33",selectedPressed="1F2D23",
        selectedRule="ABD2B1",selection="3D5A47",teal="ABD2B1",controlBorder="718275",controlTrack="718275",
        copper="C0D8AE",copperHover="D0E4C0",copperPressed="A9C499",ink="182218"
    }},
    {id="beige",label="Beige",colors={
        background="171613",panel="201E1A",header="28241F",raised="28241F",noteInset="211E19",railTint="28241F",
        selected="27231D",friendSelected="27231D",hover="29261F",pressed="151410",selectedHover="312B22",selectedPressed="211E17",
        selectedRule="D8C198",selection="554934",teal="D8C198",controlBorder="8F816A",controlTrack="8F816A",
        copper="DCC7A4",copperHover="E8D4B3",copperPressed="C7B08A",ink="241D14"
    }},
    {id="graphite",label="Graphite",colors={
        background="18191A",panel="18191A",header="26282A",raised="26282A",noteInset="202223",railTint="26282A",
        selected="2F3235",friendSelected="2F3235",hover="2D2F32",pressed="151617",selectedHover="373B3F",selectedPressed="222426",
        selectedRule="C5CCD3",selection="4A5057",teal="C5CCD3",controlBorder="777D83",controlTrack="777D83",
        copper="D5D9DD",copperHover="E3E6E9",copperPressed="BCC1C6",ink="1B1D1F"
    }},
    {id="umber",label="Umber",colors={
        background="1A1714",panel="1A1714",header="2A241F",raised="2A241F",noteInset="221D19",railTint="2A241F",
        selected="352A22",friendSelected="352A22",hover="312923",pressed="151210",selectedHover="3E3128",selectedPressed="271F19",
        selectedRule="C29A7C",selection="5A4334",teal="C29A7C",controlBorder="857264",controlTrack="857264",
        copper="C9A183",copperHover="D7B398",copperPressed="AF8A6F",ink="221810"
    }}
}
local retiredPresets={copper=cyanSlate,copperTheme=cyanSlate}
local defaults,presets,themeColors={},{},{}
for _,preset in ipairs(P.interfaceColors) do
    local colors={}
    for role,hex in pairs(preset.colors or {}) do
        colors[role]=rgb(hex)
        defaults[role]={unpack(C[role])}
        themeColors[C[role]]=true
    end
    presets[preset.id]=colors
    preset.swatch=preset.swatch or colors.copper
    preset.swatchInk=colors.ink or {unpack(C.background)}
end
presets[defaultPalette]=defaults

local activePalette=defaultPalette
local repaint=setmetatable({}, {__mode="k"})
function P.BindPalette(widget,apply)
    repaint[widget]=apply
    if apply then apply(widget,activePalette) end
end
function P.ApplyInterfaceColor(id)
    if type(id)~="string" then id=defaultPalette end
    id=retiredPresets[id] or id
    if not presets[id] then id=defaultPalette end
    if id~=activePalette then
        activePalette=id
        -- Preserve references already held by selection and pointer feedback.
        for role,default in pairs(defaults) do
            local color=presets[id][role] or default
            for channel,value in ipairs(color) do C[role][channel]=value end
        end
        for widget,apply in pairs(repaint) do apply(widget,id) end
    end
    return id
end
local function bindColor(widget,method,color)
    if themeColors[color] then
        P.BindPalette(widget,function(self) method(self,unpack(color)) end)
    else
        repaint[widget]=nil
        method(widget,unpack(color))
    end
end
function P.SetPaletteFill(texture,color)
    bindColor(texture,texture.SetColorTexture,color)
end
function P.SetPaletteTint(texture,color)
    bindColor(texture,texture.SetVertexColor,color)
end
function P.SetPaletteText(label,color)
    bindColor(label,label.SetTextColor,color)
end
function P.PageHeader(parent,height)
    local band=parent:CreateTexture(nil,"BORDER",nil,-2)
    band:SetPoint("TOPLEFT"); band:SetPoint("TOPRIGHT"); band:SetHeight(height)
    P.SetPaletteFill(band,C.header)
    local rule=parent:CreateTexture(nil,"BORDER")
    rule:SetHeight(1); rule:SetColorTexture(unpack(C.line))
    rule:SetPoint("BOTTOMLEFT",band,"BOTTOMLEFT",0,0)
    rule:SetPoint("BOTTOMRIGHT",band,"BOTTOMRIGHT",0,0)
    return band
end
-- Text and scroll frames stay with their owning pane. The two textures never receive input.
function P.NoteInset(parent)
    local edge=parent:CreateTexture(nil,"BORDER",nil,-2)
    edge:SetColorTexture(unpack(C.line))
    local fill=parent:CreateTexture(nil,"BORDER",nil,-1)
    fill:SetPoint("TOPLEFT",edge,"TOPLEFT",1,-1)
    fill:SetPoint("BOTTOMRIGHT",edge,"BOTTOMRIGHT",-1,1)
    P.SetPaletteFill(fill,C.noteInset)
    return edge,fill
end
local white={1,1,1,1}
function P.NameColor(record, whiteRosterName, verifiedClass)
    local class=verifiedClass or (record and record.class)
    local trusted=verifiedClass~=nil or (record and record.evidenceName==record.fullName)
    if (trusted and class=="PRIEST") or (whiteRosterName and record and not class) then
        return unpack(whiteRosterName and white or C.priest)
    end
    local r,g,b = C.text[1],C.text[2],C.text[3]
    local function safeTable(value)
        if type(issecretvalue)~="function" then return false end
        local ok, secret=pcall(issecretvalue,value)
        if not ok or secret~=false or type(value)~="table" then return false end
        if not P.manual then return true end
        if type(issecrettable)~="function" then return false end
        local checked, hidden=pcall(issecrettable,value)
        if not checked then return false end
        local valid, restricted=pcall(issecretvalue,hidden)
        return valid and restricted==false and hidden==false
    end
    if trusted and class and safeTable(C_ClassColor) then
        local accessed, fn=pcall(function() return C_ClassColor.GetClassColor end)
        local checked, secret=pcall(issecretvalue,fn)
        local ok, color=false,nil
        if accessed and checked and secret==false and type(fn)=="function" then ok,color=pcall(fn,class) end
        if ok and safeTable(color) then
            local read,cr,cg,cb=pcall(function() return color.r,color.g,color.b end)
            if read then
                local a,ar=pcall(issecretvalue,cr); local b2,br=pcall(issecretvalue,cg); local c,cr2=pcall(issecretvalue,cb)
                if a and b2 and c and ar==false and br==false and cr2==false and type(cr)=="number" and type(cg)=="number" and type(cb)=="number" then r,g,b=cr,cg,cb end
            end
        end
    end
    return r,g,b,1
end
function P.FormatDate(text)
    if type(text)=="number" then
        local A=P.manual
        return A.text(A.nativeRead.read(date,"%d/%m/%Y %H:%M",text))
    end
    -- Observations and check summaries keep their raw ISO dates in the fixtures.
    return (text:gsub("(%d%d%d%d)%-(%d%d)%-(%d%d)", "%3/%2/%1"))
end
function P.Paint(frame, color)
    local texture = frame:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(frame)
    P.SetPaletteFill(texture,color)
    return texture
end
function P.Material(frame, name, slice, layer)
    local texture=frame:CreateTexture(nil,layer or "BACKGROUND")
    texture:SetAllPoints(frame)
    texture:SetTexture(P.media.."Ledger"..name..".tga")
    if slice then texture:SetTextureSliceMargins(unpack(slice)) end
    return texture
end
function P.TintMaterial(texture,alternateTint)
    P.BindPalette(texture,function(self,id)
        local alternate=id~=defaultPalette and id~=cyanSlate
        self:SetDesaturated(alternate)
        self:SetVertexColor(unpack(alternate and alternateTint or white))
    end)
end
-- Match a reference pixel by channel while retaining the material's texture and alpha.
local function tintToReference(texture,color,reference)
    -- A tint cannot add red to the cool art, so warmer colors start from its gray.
    local warmer=color[1]>reference[1]
    texture:SetDesaturated(warmer)
    if warmer then
        local gray=.3*reference[1]+.59*reference[2]+.11*reference[3]
        reference={gray,gray,gray}
    end
    texture:SetVertexColor(math.min(1,color[1]/reference[1]),math.min(1,color[2]/reference[2]),math.min(1,color[3]/reference[3]),1)
end
local function clearTint(texture)
    texture:SetDesaturated(false)
    texture:SetVertexColor(unpack(white))
end
local caseReference=rgb("1C2225")
function P.TintCaseMaterial(texture)
    P.BindPalette(texture,function(self,id)
        if id==defaultPalette then clearTint(self)
        else tintToReference(self,C.background,caseReference) end
    end)
end
function P.PopupMaterial(frame, name)
    return P.Material(frame,name or "Sheet",{8,8,8,8})
end
function P.Rule(frame,x,y,right,color)
    local line=frame:CreateTexture(nil,"BORDER")
    line:SetHeight(1); line:SetPoint("TOPLEFT",x,-y); line:SetPoint("TOPRIGHT",-right,-y)
    P.SetPaletteFill(line,color or C.line)
    return line
end
function P.RosterRowChrome(row)
    local fill=row.background
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT",6,-4); fill:SetPoint("BOTTOMRIGHT",-6,4)
    row.rule=P.Rule(row,6,0,6,C.rowRule)
    local edge=row:CreateTexture(nil,"BORDER")
    edge:SetPoint("TOPLEFT",fill,"TOPLEFT"); edge:SetPoint("BOTTOMLEFT",fill,"BOTTOMLEFT")
    edge:SetWidth(3); P.SetPaletteFill(edge,C.selectedRule); edge:Hide()
    row.leadingEdge=edge
end
function P.PaneEdge(frame,side)
    local line=frame:CreateTexture(nil,"BORDER")
    line:SetWidth(1); line:SetPoint("TOP"..side); line:SetPoint("BOTTOM"..side)
    line:SetColorTexture(unpack(C.line))
end
local typeRoles={
    brand={27,"brand"}, page={26,"brand"}, record={22,"brand"}, name={15,"semi"},
    presence={14}, section={16,"semi"}, nav={14}, body={14}, action={14,"semi"},
    small={13}, meta={12}, column={12,"semi"}, compactNav={12}, compactSelected={12,"semi"}
}
function P.FontSize(label,size,weight)
    local path=label:GetFont()
    local locale=P.clientLocale or "enUS"
    local latin=locale=="enUS" or locale=="enGB" or locale=="frFR" or locale=="deDE" or locale=="esES" or locale=="esMX" or locale=="ptBR" or locale=="itIT"
    local preferred=path
    if weight=="brand" and latin then preferred=P.media.."Gelasio-Regular.ttf"
    elseif latin then preferred=P.media..(weight=="semi" and "NotoSans-SemiBold.ttf" or "NotoSans-Regular.ttf") end
    local ok,result=pcall(label.SetFont,label,preferred,size,"")
    if (not ok or result==false) and path then pcall(label.SetFont,label,path,size,"") end
    label:SetShadowColor(0,0,0,0); label:SetShadowOffset(0,0)
end
function P.Type(label,role)
    P.FontSize(label,unpack(typeRoles[role]))
end
function P.Label(parent,text,role,color)
    local label=parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    P.Type(label,role or "body")
    P.SetPaletteText(label,color or C.text); label:SetText(text or "")
    return label
end
local glyphIndices={friends=0,blacklist=1,encounters=2,settings=3,search=4,filter=5,online=6,unknown=7,seen=8,tank=11,healer=12,dps=13,copy=14,refresh=15}
function P.Glyph(parent, name, size, color)
    local icon=parent:CreateTexture(nil,"ARTWORK")
    icon:SetSize(size,size); icon:SetTexture(P.media .. "LedgerGlyphs.tga")
    P.SetGlyph(icon,name,color)
    return icon
end
function P.SetGlyph(icon, name, color)
    local index=glyphIndices[name] or glyphIndices.unknown
    local col=index%4; local row=math.floor(index/4)
    icon:SetTexCoord((col*32+4)/128,(col*32+28)/128,(row*32+4)/128,(row*32+28)/128)
    P.SetPaletteTint(icon,color or C.muted)
end

local actions={plus=0,edit=1,mute=2,close=3,down=4,warning=5,back=6,caret=7}
function P.ActionGlyph(parent,name,size,color)
    if not actions[name] then return P.Glyph(parent,name,size,color) end
    local icon=parent:CreateTexture(nil,"ARTWORK")
    local x=(actions[name]%4)*32+6; local y=math.floor(actions[name]/4)*32+6
    icon:SetSize(size,size); icon:SetTexture(P.media.."LedgerActions.tga")
    icon:SetTexCoord(x/128,(x+20)/128,y/64,(y+20)/64); icon:SetVertexColor(unpack(color))
    return icon
end
local function updateButton(b)
    local enabled=b:IsEnabled()
    local hovered=enabled and b.hovered
    local pressed=hovered and b.pressed
    if b.underline then
        local selected=b.selected==true
        if b.tabSelected~=selected then
            b.tabSelected=selected
            P.FontSize(b.label,13,selected and "semi" or nil)
        end
        b.underline:SetShown(selected)
        b.label:SetTextColor(unpack(pressed and C.teal or (hovered or selected) and C.text or C.body))
        return
    end
    if b.rounded then
        local fill=C.line
        if enabled then
            if b.rounded=="primary" then
                if b.destructive then fill=pressed and C.dangerPressed or hovered and C.dangerHover or C.danger
                else fill=pressed and C.copperPressed or hovered and C.copperHover or C.copper end
            else fill=pressed and C.body or hovered and C.teal or C.controlBorder end
        end
        local surface=fill
        if b.roundEdge then
            surface=pressed and C.pressed or hovered and C.hover or {.615,.753,.761,.07}
            for _,part in ipairs(b.roundEdge) do part:SetVertexColor(unpack(fill)) end
        end
        for _,part in ipairs(b.roundFill) do part:SetVertexColor(unpack(surface)) end
        local ink=not enabled and C.muted or b.destructive and C.text or b.rounded=="primary" and C.ink or C.body
        b.label:SetTextColor(unpack(ink))
        if b.icon then b.icon:SetVertexColor(unpack(ink)) end
        return
    end
    if not b.skin then
        local color=b.baseColor
        if b.iconOnly then
            color=pressed and C.actionPressed or hovered and C.actionHover or color
        elseif b.selected then
            color=pressed and C.selectedPressed or hovered and C.selectedHover or b.selectedColor or C.selected
        else
            color=pressed and C.pressed or hovered and C.hover or color
        end
        b.background:SetColorTexture(unpack(color))
        return
    end
    b.skin:SetTexture(P.media.."Ledger"..(enabled and b.skinName or "Disabled")..".tga")
    local color=not enabled and C.disabled or b.destructive and {1,1,1,1} or b.skinName=="Primary" and C.ink or C.body
    b.label:SetTextColor(unpack(color)); if b.icon then b.icon:SetVertexColor(unpack(color)) end
    local tint=pressed and .76 or hovered and .92 or 1
    b.skin:SetVertexColor(tint,tint,tint,1)
    b.pressEdge:SetShown(pressed==true)
end
P.UpdateButton=updateButton
-- Only the middle strip stretches horizontally. Each cap is a semicircle whose
-- radius follows the widget height, independent of the client's texture slicing.
local function capsuleParts(button,file,layer)
    local parts={}
    for index=1,3 do
        local part=button:CreateTexture(nil,layer)
        part:SetTexture(P.media..file)
        parts[index]=part
    end
    local left,middle,right=unpack(parts)
    left:SetTexCoord(0,.5,0,1); right:SetTexCoord(.5,1,0,1)
    middle:SetTexCoord(.49,.51,0,1)
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT")
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT")
    middle:SetPoint("TOPLEFT",left,"TOPRIGHT"); middle:SetPoint("BOTTOMRIGHT",right,"BOTTOMLEFT")
    return parts
end
function P.RoundButton(button,primary)
    button.rounded=primary and "primary" or "quiet"
    P.FontSize(button.label,14,primary and "semi" or nil)
    button.skin:Hide()
    button.roundFill=capsuleParts(button,"LedgerRoundFill.tga","BACKGROUND")
    if not primary then button.roundEdge=capsuleParts(button,"LedgerRoundEdge.tga","BORDER") end
    local function sizeCaps(self)
        local radius=self:GetHeight()/2
        self.roundFill[1]:SetWidth(radius); self.roundFill[3]:SetWidth(radius)
        if self.roundEdge then
            self.roundEdge[1]:SetWidth(radius); self.roundEdge[3]:SetWidth(radius)
        end
    end
    sizeCaps(button)
    button:HookScript("OnSizeChanged",sizeCaps)
    button.pressEdge:Hide()
    P.BindPalette(button,updateButton)
end
function P.ResetButtonFeedback(button)
    button.hovered,button.pressed=false,false
    button.paintFeedback(button)
end
function P.BindButtonFeedback(button,paint)
    button.paintFeedback=paint
    button:HookScript("OnEnter",function(self)
        self.hovered=self:IsEnabled()
        paint(self)
    end)
    button:HookScript("OnLeave",P.ResetButtonFeedback)
    button:HookScript("OnHide",P.ResetButtonFeedback)
    button:HookScript("OnMouseDown",function(self,mouseButton)
        if mouseButton~="LeftButton" or not self:IsEnabled() then return end
        self.hovered,self.pressed=true,true
        paint(self)
    end)
    button:HookScript("OnMouseUp",function(self,mouseButton)
        if mouseButton~="LeftButton" or not self.pressed then return end
        self.pressed=false
        paint(self)
    end)
end
-- Both the text region and the icon use the full button's vertical center.
function P.ButtonContent(button,left,right,justify)
    local label=button.label
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT",button,"TOPLEFT",left or 0,0)
    label:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-(right or 0),0)
    label:SetJustifyV("MIDDLE"); label:SetJustifyH(justify or "CENTER")
    label:SetWordWrap(false)
end
function P.Button(parent,text,width,height,click,style)
    local b=CreateFrame("Button",nil,parent)
    b.iconOnly=style=="action"
    b:SetSize(width,height)
    b.label=P.Label(b,text,"action"); P.ButtonContent(b)
    if style=="row" or style=="nav" or style=="action" then
        b.baseColor=C.clear; b.background=P.Paint(b,C.clear)
    else
        b.destructive=style=="Destructive"
        b.skinName=b.destructive and "Danger" or style or "Button"
        b.skin=P.Material(b,b.skinName,{4,4,4,4})
        b.pressEdge=b:CreateTexture(nil,"BORDER")
        b.pressEdge:SetPoint("TOPLEFT",b,"TOPLEFT",4,-2)
        b.pressEdge:SetPoint("TOPRIGHT",b,"TOPRIGHT",-4,-2)
        b.pressEdge:SetHeight(1)
        b.pressEdge:SetColorTexture(0,0,0,.4)
    end
    P.BindButtonFeedback(b,updateButton)
    if click then b:SetScript("OnClick",click) end
    if style=="row" or style=="nav" then P.BindPalette(b,updateButton) else updateButton(b) end
    return b
end
function P.TextTab(parent,caption,height,onClick,alternate)
    local b=P.Button(parent,caption,1,height,onClick,"nav")
    local label=b.label
    -- Keep the centered caption at its native size. Only the hit box and underline are sized.
    label:ClearAllPoints(); label:SetPoint("CENTER",b,"CENTER")
    local function measure(weight)
        P.FontSize(label,13,weight)
        local width=label:GetUnboundedStringWidth()
        if alternate then
            label:SetText(alternate)
            width=math.max(width,label:GetUnboundedStringWidth())
            label:SetText(caption)
        end
        return width
    end
    local normalWidth=measure()
    b:SetWidth(math.ceil(math.max(normalWidth,measure("semi")))+16)
    b.underline=b:CreateTexture(nil,"ARTWORK")
    b.underline:SetPoint("BOTTOMLEFT"); b.underline:SetPoint("BOTTOMRIGHT")
    b.underline:SetHeight(2); P.SetPaletteFill(b.underline,C.teal)
    updateButton(b)
    return b
end
function P.ButtonIcon(button,glyph,size)
    button.icon=P.ActionGlyph(button,glyph,size or 16,C.body)
    if button.iconOnly then
        button.icon:SetPoint("CENTER",button,"CENTER",0,0)
    else
        -- One natural-width caption anchor centers the whole icon + gap + text group.
        -- Its native width follows later caption changes, including Filters (3) and Mute chat.
        local gap=7
        button.label:ClearAllPoints()
        button.label:SetPoint("CENTER",button,"CENTER",(button.icon:GetWidth()+gap)/2,0)
        button.icon:SetPoint("RIGHT",button.label,"LEFT",-gap,0)
    end
    updateButton(button)
    return button.icon
end
function P.SetEnabled(button,enabled)
    button:SetEnabled(enabled)
    if enabled then updateButton(button) else P.ResetButtonFeedback(button) end
end
function P.CopyNameButton(parent,caption,onClick)
    local button=P.Button(parent,caption,34,34,onClick,"action")
    button.label:Hide()
    P.ButtonIcon(button,"copy",22)
    return button
end
local fieldReference,focusReference=rgb("718086"),rgb("9CDCE0")
local function setFieldSkin(box,focused)
    local skin=box.fieldSkin
    local enabled=box:IsEnabled()
    skin:SetTexture(P.media..(not enabled and "LedgerDisabled.tga" or focused and "LedgerFocus.tga" or "LedgerField.tga"))
    if enabled then
        local color,reference=C.controlBorder,fieldReference
        if focused then color,reference=C.teal,focusReference end
        P.BindPalette(skin,function(self,id)
            if id==defaultPalette then clearTint(self)
            else tintToReference(self,color,reference) end
        end)
    else
        repaint[skin]=nil
        clearTint(skin)
    end
end
function P.SetFieldEnabled(box,enabled)
    box:SetEnabled(enabled)
    setFieldSkin(box,box:HasFocus())
end
function P.Field(parent,width,height,multiline)
    local box=CreateFrame("EditBox",nil,parent)
    box:SetFontObject("GameFontHighlight"); P.Type(box,"body")
    box:SetSize(width,height); box:SetAutoFocus(false)
    box:SetTextColor(unpack(C.text)); box:SetTextInsets(12,12,4,4)
    box.fieldSkin=P.Material(multiline and parent or box,"Field",{4,4,4,4})
    setFieldSkin(box,false)
    box:SetScript("OnEditFocusGained",function(self) setFieldSkin(self,true) end)
    box:SetScript("OnEditFocusLost",function(self) setFieldSkin(self,false) end)
    if multiline then box:SetMultiLine(true) end
    return box
end
local tooltipOwner
function P.HideTooltip(owner)
    if owner and GameTooltip:GetOwner() == owner then GameTooltip:Hide() end
    if tooltipOwner == owner then tooltipOwner = nil end
end
function P.ClearTooltip()
    P.HideTooltip(tooltipOwner)
end
function P.ShowTooltip(owner, text, anchor)
    P.ClearTooltip()
    tooltipOwner = owner
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 0.9, 0.7, 1, true)
    GameTooltip:Show()
end
function P.Tooltip(frame, text)
    frame:HookScript("OnEnter", function(self) P.ShowTooltip(self, text) end)
    frame:HookScript("OnLeave", function(self) P.HideTooltip(self) end)
end

local roleSuffix = {TANK="tank", HEALER="heal", DAMAGER="dps"}
local roleAtlasPrefixes = {"groupfinder-icon-role-micro-", "groupfinder-icon-role-large-"}
P.roleNames = { TANK="Tank", HEALER="Healer", DAMAGER="DPS" }
function P.RoleIcon(parent, label, size, gap, role)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetVertexColor(1,1,1,1)
    label:SetJustifyV("MIDDLE")
    icon:SetPoint("RIGHT", label, "LEFT", -gap, 0)
    P.ShowRoleIcon(icon, role)
    return icon
end
local function bindRoleAtlas(icon, atlas)
    if icon:SetAtlas(atlas, false) == false then return false end
    return icon:GetAtlas() == atlas
end
function P.ShowRoleIcon(icon, role)
    icon:Hide()
    local suffix = roleSuffix[role]
    if not suffix or not icon.SetAtlas or not icon.GetAtlas then return end
    for _, prefix in ipairs(roleAtlasPrefixes) do
        local ok, bound = pcall(bindRoleAtlas, icon, prefix .. suffix)
        if ok and bound then icon:Show(); return end
    end
end
-- Keep the outside press owned until release so it cannot activate another control.
function P.DismissOutside(menu, owner)
    local shield=CreateFrame("Frame",nil,owner)
    shield:SetAllPoints(UIParent); shield:SetFrameLevel(menu:GetFrameLevel()-1)
    shield:EnableMouse(true); shield:EnableMouseWheel(true); shield:Hide()
    shield:SetScript("OnMouseUp",function() menu:Hide() end)
    shield:SetScript("OnMouseWheel",function() end)
    menu:EnableMouse(true)
    menu:HookScript("OnShow",function() shield:Show() end)
    menu:HookScript("OnHide",function() shield:Hide() end)
    return shield
end

function P.CreateDialog(parent, name, backdrop)
    local f = CreateFrame("Frame", name, parent)
    f:SetSize(460, 260); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(backdrop and backdrop:GetFrameLevel()+1 or parent:GetFrameLevel()+10)
    f:SetToplevel(true); P.PopupMaterial(f); f:Hide()
    table.insert(UISpecialFrames, name)
    return f
end
