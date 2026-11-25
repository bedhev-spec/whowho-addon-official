-- Offline localization through the manual entry point and real SavedVariables shape.
local root=arg[1] or "."
local H=dofile(root.."/tests/addon/harness.lua")

local function fresh(getLocale,preferences,viewport)
    local p,s,e=H.fresh(root,preferences,viewport,{region=3,time=100})
    e.GetLocale=getLocale and function() return getLocale(s) end or nil
    s:event("ADDON_LOADED","WhoWho")
    assert(p.initialized)
    return p,s,e,p.Shell
end

for _,getLocale in ipairs({
    function() return "enUS" end,
    function() return "enGB" end,
    function() return "deDE" end,
    function() return "fr" end,
    function() return 1 end,
    function(s) return s.secret end,
    function() error("locale unavailable") end,
    false,
}) do
    local p,_,e,S=fresh(getLocale,{language="frFR"})
    p.Toggle()
    assert(S.nav.settings.label:GetText()=="Settings" and S.pageTitle:GetText()=="Friends")
    assert(e.WhowhoPreviewDB.language==nil)
end

do
    local p,_,_,S=fresh(function() return "frFR" end)
    p.Toggle()
    assert(S.refreshNow:IsEnabled())
    S.refreshNow:Click()
    assert(S.refreshStatus:IsVisible() and S.refreshStatus:GetText()=="Ajoutez un ami pour actualiser son état.")
end

local calls=0
local p,s,e,S=fresh(function()
    calls=calls+1
    return "frFR"
end,{language="enUS",position={point="TOP",relativePoint="TOP",x=14,y=-22}},{484,800})
assert(calls==1 and e.WhowhoPreviewDB.language==nil)
assert(p.L("Settings")=="Paramètres")
assert(p.L("Untranslated format %s","100% ready")=="Untranslated format 100% ready")
e.GetLocale=function() error("the UI must retain its startup locale") end

local store=p.manual.store
local friend=assert(store.add({region=3,fullName="Other Friends",membership="friend",
    identityState="resolved",note="No note",role="HEALER"},100))
local blocked=assert(store.add({region=3,fullName="Name Unknown",membership="blacklist",
    identityState="resolved",guid="blocked",note="No note",reasonIds={"griefing"}},100))
p.manual.refresh()
p.Toggle()
assert(S.nav.settings.label:GetText()=="Paramètres" and S.pageTitle:GetText()=="Amis")
local footer="Manual checks use target, group, guild and Recent Allies."
assert(S.footer:GetText()==p.L(footer) and S.footer:GetText()~=footer)
assert(S.detail.name:GetText()==friend.fullName and S.detail.note:GetText()==friend.note)
assert(S.detail.role:GetText()=="Soigneur" and S.count:GetText()=="1 ami sur 1")
assert(S.filterChoices.roleFilter.HEALER.label:GetText()=="Soigneur")
assert(not S.filterToggle:IsVisible() and S.facetLinks.roleFilter:IsVisible())
s:fire(S.facetLinks.roleFilter,"OnEnter")
assert(S.filterMenu:IsVisible() and S.filterShield:IsVisible())
S.filterChoices.roleFilter.HEALER:Click()
assert(S.roleFilter=="HEALER" and S.rows[1].record.id==friend.id and not S.filterMenu:IsShown())
assert(S.facetLinks.roleFilter.label:GetText()=="Soigneur" and S.resetFacets:IsVisible())
local choices=S.filterChoices.statusFilter
local record=S.rows[1].record
local cases={
    {"Online",true},{"Offline",true},
    {"Listed online",false,"listed",true},{"Listed offline",false,"listed",false},
    {"Was online",false,"checked",true},{"Was offline",false,"checked",false},
    {"Seen"},{"Unknown"},{"Draft"},
}
for _,case in ipairs(cases) do
    local caption=case[1]
    record.presence=caption
    record.identityState=caption=="Draft" and "unresolved" or nil
    record.connectionEvidence=case[2]
    record.presenceReport=case[3] and {kind=case[3],online=case[4],source="Guild"} or nil
    record.source="Target"; record.observed="2026-11-17 12:00"
    S.facetLinks.statusFilter:Click()
    local bucket=case[2] and caption or case[3] and (case[4] and "Online" or "Offline") or "Unknown"
    choices[bucket]:Click()
    assert(S.rows[1].record==record and S.facetLinks.statusFilter.label:GetText()==choices[bucket].label:GetText())
    assert(not S.filterMenu:IsShown())
    local rowCaption=p.L(bucket)
    assert(S.rows[1].status:GetText()==rowCaption)
    assert(S.facetLinks.statusFilter.label:GetUnboundedStringWidth()+20<=S.facetLinks.statusFilter:GetWidth())
end
assert(not choices["Listed offline"] and not choices.Seen and not choices.Draft)
for _,width in ipairs({484,1360}) do
    e.UIParent:SetSize(width,800); S.Layout()
    S.facetLinks.statusFilter:Click()
    assert(S.layoutMode==(width==484 and "compact" or "wide"))
    assert(S.filterMenu:GetWidth()+24<S.list:GetWidth() and S.filterMenu:GetHeight()+114<S.list:GetHeight())
    local firstY=select(3,choices.ALL:GetPoint())
    local secondX,secondY=select(2,choices.Online:GetPoint())
    assert(secondY==firstY and secondX>8,"choices share a horizontal row")
    for _,choice in pairs(choices) do
        local _,x,y=choice:GetPoint()
        assert(choice:IsVisible() and x+choice:GetWidth()<=S.filterMenu:GetWidth())
        assert(choice.label:GetUnboundedStringWidth()<=choice:GetWidth()-28)
        assert(-y+choice:GetHeight()<S.filterMenu:GetHeight())
    end
end
e.UIParent:SetSize(484,800); S.Layout()
record.identityState=nil; record.presence=nil; record.connectionEvidence=nil; record.presenceReport=nil; record.source=nil; record.observed=nil
choices.ALL:Click()
-- Moving away from a hover-open list should restore input to the roster.
s:fire(S.facetLinks.classFilter,"OnEnter")
s:fire(S.filterMenu,"OnUpdate",0.2)
assert(not S.filterMenu:IsShown() and not S.filterShield:IsShown())
S.facetLinks.roleFilter:Click()
s:fire(S.filterMenu,"OnUpdate",0.2)
assert(S.filterMenu:IsShown(),"clicked filters stay open until dismissed")
s:fire(S.filterShield,"OnMouseUp","LeftButton")
assert(not S.filterMenu:IsShown() and S.roleFilter=="HEALER")
assert(S.sortButton:GetParent()==S.list and S.sortButton.label:GetText()=="Personnage · A–Z")
S.sortButton:Click()
assert(S.sortButton.label:GetText()=="Personnage · Z–A" and S.sortButton.label:GetUnboundedStringWidth()+28<S.sortButton:GetWidth())
S.sortButton:Click()
local point,_,relativePoint,x,y=S.window:GetPoint()
assert(point=="TOP" and relativePoint=="TOP" and x==14 and y==-22)
s:fire(S.rows[1].copyButton,"OnEnter")
assert(e.GameTooltip:GetText()=="Copier Other Friends")
s:fire(S.rows[1].copyButton,"OnLeave")

local inviteButton=S.rows[1].inviteButton
assert(not inviteButton:IsEnabled())
s:fire(inviteButton,"OnEnter")
assert(e.GameTooltip:GetText()=="Les invitations de groupe sont indisponibles.")
s:fire(inviteButton,"OnLeave")

-- A prior observation supplies faction evidence after the live target has gone.
e.InCombatLockdown=function() return false end
e.UnitExists=function() return false end
e.UnitFactionGroup=function(unit) if unit=="player" then return "Alliance" end end
e.GetServerTime=function() return 401 end
p.manual.targetCheck.observations[friend.id]={id=friend.id,region=3,name=friend.fullName,
    faction="Horde",source="Target",observed="2026-11-21 18:20",at=100}
p.manual.refresh()
S.RefreshFriends()
S.rows[1]:Click()
assert(S.checkStatus:IsVisible() and S.checkStatus:IsEnabled())
assert(not S.checkStatus.label:IsShown() and S.checkStatus.icon:IsVisible() and S.checkStatus:GetWidth()==32)
local point,anchor,edge,gap,lift=S.checkStatus:GetPoint()
assert(S.checkStatus.icon.texture==p.media.."LedgerStatusRefresh.tga" and S.checkStatus.icon:GetWidth()==22)
assert(point=="LEFT" and anchor==S.detail.name and edge=="RIGHT" and gap==1 and lift==0,
    "refresh follows the visible end and optical center of the name")
local _,_,headingTop=S.detail.heading:GetPoint()
local _,_,presenceTop=S.detail.current:GetPoint()
assert(math.abs(headingTop-presenceTop)<10,"presence caption and value share one line")
assert(S.detail.noteEdge:IsVisible() and S.detail.noteFill:IsVisible())
local originalNote=S.detail.note:GetText()
assert(S.detail.noteView:GetHeight()<50,"short notes fit their contents")
S.detail.note:SetText(string.rep("Longue note\n",20))
S.ArrangeRecordText()
for i=1,30 do s:fire(S.detail.noteView,"OnMouseWheel",-1) end
assert(S.detail.noteView:GetVerticalScroll()>0 and S.detail.noteView:GetVerticalScroll()==S.detail.noteView:GetVerticalScrollRange())
assert(S.editButton:IsVisible() and S.moveButton:IsVisible() and S.detail.noteView:GetHeight()<=96)
local bar=S.detail.noteView.scrollbar
assert(bar:IsVisible() and bar:GetValue()==S.detail.noteView:GetVerticalScroll())
bar:SetValue(8); assert(S.detail.noteView:GetVerticalScroll()==8)
S.detail.note:SetText(originalNote); S.ArrangeRecordText()
S.checkStatus:Click()
local whoFeedback="Who est indisponible pour l'autre faction."
assert(S.footer:IsVisible() and S.footer:GetText()==whoFeedback and S.detail.attempt:GetText()==whoFeedback)
for _,width in ipairs({1000,484}) do
    e.UIParent:SetSize(width,800)
    S.Layout()
    local _,labelX=S.detail.observationLabel:GetPoint()
    local _,valueX=S.detail.observation:GetPoint()
    local _,checkX=S.detail.attempt:GetPoint()
    assert(labelX==25 and valueX==checkX and valueX<S.details:GetWidth()/2)
    assert(S.detail.observationLabel:IsVisible() and S.detail.observationLabel:GetText()=="Vu le")
    assert(labelX+S.detail.observationLabel:GetUnboundedStringWidth()<valueX)
end

S.nav.blacklist:Click()
assert(S.pageTitle:GetText()=="Liste noire personnelle")
assert(S.rows[1].name:GetText()==blocked.fullName)
assert(S.rows[1].note:GetText()==p.L("Griefing") and S.rows[1].note:GetText()~="Griefing")
S.Select(S.rows[1].record)
assert(S.detail.reasons:GetText()==p.L("Griefing") and S.detail.note:GetText()==blocked.note)
S.editor.Open(S.rows[1].record,"blacklist")
local form=S.editor.controls
assert(form.reasonOptions.griefing.mark:IsShown() and form.reasonOptions.griefing.label:GetText()==p.L("Griefing"))
assert(form.formName:GetText()==blocked.fullName and form.formNote:GetText()==blocked.note)
form.formCancel:Click()
assert(store.get(blocked.id).reasonIds[1]=="griefing")

local tooltipCallback
e.Enum={TooltipDataType={Unit=2}}
e.TooltipDataProcessor={AddTooltipPostCall=function(_,callback) tooltipCallback=callback end}
e.InCombatLockdown=function() return false end
e.UnitExists=function(token) return token=="mouseover" end
e.UnitIsPlayer=e.UnitExists
e.GetUnitName=function() return blocked.fullName end
e.UnitGUID=function() return blocked.guid end
e.GameTooltip.IsForbidden=function() return false end
local primary={guid=blocked.guid}
e.GameTooltip.GetPrimaryTooltipData=function() return primary end
p.manual.playerTooltip.install()
tooltipCallback(e.GameTooltip,primary)
assert(e.GameTooltip:GetText():find(p.L("Blacklisted").." · "..p.L("Griefing"),1,true))

S.nav.encounters:Click()
local found=false
for _,child in ipairs(S.encounters.children) do
    if child.kind=="FontString" and child:IsVisible() and child:GetText()==p.L("No encounters in the last hour.") then found=true end
end
assert(found and p.L("No encounters in the last hour.")~="No encounters in the last hour.")
local ledger=p.manual.encounterLedger
local encounterId=assert(ledger.start({id=blocked.id,name=blocked.fullName,guid=blocked.guid},3,100))
assert(p.manual.store.observeBlacklist(blocked.id,{region=3,name=blocked.fullName,guid=blocked.guid,
    source="Target",at=100,faction="Horde",class="MAGE"}))
p.manual.refresh()
e.C_ClassColor={GetClassColor=function(class) return class=="MAGE" and {r=.2,g=.6,b=.9} or nil end}
ledger.observe(encounterId,true,false,0,"Unknown")
assert(S.encounters:Refresh(encounterId))
local liveRow
for _,child in ipairs(S.encounters.children) do
    if child.entry then liveRow=child; break end
end
assert(liveRow and liveRow.name:GetText()==blocked.fullName and liveRow.name.textColor[1]==.2)
assert(not liveRow.time:GetText():find("En cours",1,true) and liveRow.time:GetText():match("^Horde · .+Unknown$"))
assert(p.L("Faction: %s",p.L("Unknown"))=="Faction : Inconnu")
assert(liveRow.count:GetText()=="1 rencontre")
ledger.stop(encounterId,0)
local laterId=assert(ledger.start({id=blocked.id,name=blocked.fullName,guid=blocked.guid},3,700))
ledger.observe(laterId,true,false,0,"Unknown")
assert(S.encounters:Refresh(laterId) and liveRow.count:GetText()=="2 rencontres" and p.L("Count")=="Total")
e.GetServerTime=function() return 100000 end
for i,at in ipairs({96400,13600}) do
    local id=assert(ledger.start({id=blocked.id+i,name="Alden Vale",guid="locale"..i},3,at))
    ledger.observe(id,true,false,0,"Durotar")
    ledger.stop(id,0)
end
S.encounters:Refresh()
local frenchHelp={
    ["Dernière heure"]="Le joueur est actuellement ciblé ou sous votre curseur, ou la rencontre s’est terminée il y a moins d’une heure.",
    ["Récentes"]="La rencontre s’est terminée il y a au moins une heure et il y a moins de 24 heures.",
    ["Antérieures"]="La rencontre s’est terminée il y a au moins 24 heures.",
}
local count=0
for _,child in ipairs(S.encounters.children) do
    if child.kind=="Button" and frenchHelp[child.label:GetText()] and child:IsVisible() then
        s:routePointer({child},"OnEnter")
        assert(e.GameTooltip:IsShown() and e.GameTooltip:GetText()==frenchHelp[child.label:GetText()])
        local _,x=child:GetPoint()
        assert(child.label:GetUnboundedStringWidth()<=child:GetWidth()-16
            and x+child:GetWidth()<=S.encounters:GetWidth()-24)
        s:fire(child,"OnLeave")
        count=count+1
    end
end
assert(count==3)
S.nav.settings:Click()
assert(S.settingsTabs.alerts.label:GetText()=="Alertes" and S.settingsTabs.general.label:GetText()=="Général")
assert(S.testSoundButton.label:GetText()=="Tester le son" and S.liveSoundToggle.state:GetText()=="Activé")
local function verifySoundControls()
    local _,sliderX,sliderY=S.volumeSlider:GetPoint()
    local _,percentX,percentY=S.volumeLabel:GetPoint()
    local _,testX,testY=S.testSoundButton:GetPoint()
    assert(S.volumeSlider:GetWidth()>=96 and sliderY-S.volumeSlider:GetHeight()/2==percentY-S.volumeLabel:GetHeight()/2)
    assert(sliderX+S.volumeSlider:GetWidth()<percentX and percentX+S.volumeLabel:GetWidth()<S.settings:GetWidth())
    assert(testX+S.testSoundButton:GetWidth()<S.settings:GetWidth(), "test sound extends past the Settings width")
    assert(-testY+S.testSoundButton:GetHeight()<S.settings:GetHeight(), ("test sound ends at %s in a %s-high pane"):format(-testY+S.testSoundButton:GetHeight(),S.settings:GetHeight()))
    assert(sliderY==testY-4 and percentX+S.volumeLabel:GetWidth()<testX)
end
verifySoundControls()
e.UIParent:SetSize(1360,832); p.SetScale(1)
verifySoundControls()
e.UIParent:SetSize(484,800); p.SetScale(1)
S.testBannerButton:Click()
local banner=e.WhowhoBlacklistTestBanner
assert(banner.character:GetText()=="Warchief Thrall" and banner.reasons:GetText()==p.L("Griefing · Ninja looting"))
assert(banner.reasons:GetText()~="Griefing · Ninja looting")
s:fire(banner,"OnUpdate",2.4)
assert(banner.more:IsShown() and banner.more:GetText()=="+1 de plus")
assert(banner.character:GetText()=="Warchief Thrall" and banner.reasons:GetText()==p.L("Griefing · Ninja looting"))
S.testBannerButton:Click()
S.settingsTabs.general:Click()
assert(S.scaleSlider:IsVisible() and S.scaleSlider:GetWidth()>=96)
assert(S.languageButtons==nil and S.resetPositionButton==nil)
assert(S.nav.settings.label:GetWidth()>=S.nav.settings.label:GetUnboundedStringWidth())

local function sameColor(actual,expected)
    assert(actual and #actual==#expected)
    for index,value in ipairs(expected) do assert(actual[index]==value) end
end
local colors=p.colors
local window=S.window
local swatches=S.interfaceColorChoices
local choices={{"default","Par défaut"},{"copperTheme","Cuivre"},{"slateBlue","Bleu ardoise"},{"beige","Beige"}}
local function checkSwatches()
    local previousX,previousY
    for _,choice in ipairs(choices) do
        local button=assert(swatches[choice[1]])
        local _,x,y=button:GetPoint()
        local circle=button.mark:GetParent()
        assert(button:IsVisible() and not button.label and button:GetWidth()==36 and button:GetHeight()==36)
        assert(circle:GetWidth()==24 and circle:GetHeight()==24 and circle:GetPoint()=="CENTER")
        assert(not previousX or (x-previousX==44 and y==previousY))
        assert(x+button:GetWidth()<S.settings:GetWidth())
        previousX,previousY=x,y
    end
end
assert(#p.interfaceColors==#choices)
checkSwatches()
for _,choice in ipairs(choices) do
    local button=swatches[choice[1]]
    s:fire(button,"OnEnter")
    assert(e.GameTooltip:GetOwner()==button and e.GameTooltip:GetText()==choice[2] and e.GameTooltip:IsShown())
    s:fire(button,"OnLeave")
    assert(not e.GameTooltip:IsShown())
end
e.UIParent:SetSize(1280,800); p.SetScale(1)
checkSwatches()
assert(e.WhowhoPreviewDB.interfaceColor=="default" and swatches.default:GetChecked() and swatches.default.mark:IsShown())
swatches.default:SetChecked(false) -- A native CheckButton toggles itself before OnClick.
swatches.default:Click()
assert(swatches.default:GetChecked() and swatches.default.mark:IsShown())

local function railColors(shell,owner)
    local material,tint
    for _,region in ipairs(shell.navFrame.children) do
        if region.texture==owner.media.."LedgerRail.tga" then material=region end
        if region.allPoints==shell.navFrame and region.color then tint=region end
    end
    assert(material and tint and tint.SetAlphaArgs[1]==.62)
    sameColor(tint.color,owner.colors.railTint)
    return tint.color
end
sameColor(railColors(S,p),{0,0,0,0})

local banners={}
for _,widget in ipairs(s.nodes) do
    if widget.texture==p.media.."LedgerBanner.tga" then banners[#banners+1]=widget end
end
assert(#banners==2) -- Existing sample and movable test banner share styling.
local originalHeader,originalPrimary=S.rosterHeader.color,S.addButton.roundFill[2].vertexColor
local originalWarning,originalOnline,originalPriest={table.unpack(colors.warning)},{table.unpack(colors.online)},{table.unpack(colors.priest)}
local previousRail
for _,id in ipairs({"copperTheme","slateBlue","beige"}) do
    local button=swatches[id]
    button:Click()
    assert(e.WhowhoPreviewDB.interfaceColor==id and S.window==window and button:IsVisible())
    for key,swatch in pairs(swatches) do
        assert(swatch:GetChecked()==(key==id) and swatch.mark:IsShown()==(key==id))
    end
    sameColor(S.rosterHeader.color,colors.header)
    sameColor(S.addButton.roundFill[2].vertexColor,colors.copper)
    sameColor(S.scaleSlider:GetThumbTexture().vertexColor,colors.teal)
    local rail=railColors(S,p)
    assert(rail[4]==1 and (not previousRail or rail[1]~=previousRail[1] or rail[2]~=previousRail[2] or rail[3]~=previousRail[3]))
    previousRail=rail
    for _,material in ipairs(banners) do
        assert(material.desaturated)
        sameColor(material.vertexColor,colors.teal)
    end
    sameColor(colors.warning,originalWarning)
    sameColor(colors.online,originalOnline)
    sameColor(colors.priest,originalPriest)
end
assert(originalHeader[1]~=S.rosterHeader.color[1] and originalPrimary[1]~=S.addButton.roundFill[2].vertexColor[1])
local restored,_,_,restoredShell=fresh(function() return "enUS" end,e.WhowhoPreviewDB)
restored.Toggle()
assert(restored.db.interfaceColor=="beige" and restoredShell.interfaceColorChoices.beige:GetChecked())
sameColor(restoredShell.rosterHeader.color,colors.header)
sameColor(railColors(restoredShell,restored),railColors(S,p))
for old,expected in pairs({copper="default",forestGreen="beige",unknown="default"}) do
    local migrated=fresh(function() return "enUS" end,{interfaceColor=old})
    assert(migrated.db.interfaceColor==expected)
end
swatches.default:Click()
sameColor(railColors(S,p),{0,0,0,0})
sameColor(S.rosterHeader.color,originalHeader)
sameColor(S.addButton.roundFill[2].vertexColor,originalPrimary)
for _,material in ipairs(banners) do
    assert(not material.desaturated)
    sameColor(material.vertexColor,{1,1,1,1})
end
assert(s.forbiddenCalls==0)
print("RESULT manual locale and interface color localization, live rendering and preference restore passed")
