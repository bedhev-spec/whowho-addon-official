-- SavedVariables and grouped Friends rows in the offline widget harness.
local root=arg[1] or "."
local H=dofile(root.."/tests/addon/harness.lua")
local config={region=3,time=100}
local p,s,e=H.fresh(root,nil,{484,800},config)
s:event("ADDON_LOADED","WhoWho"); p.Toggle()
local A,S=p.manual,p.Shell
local ari=assert(A.save(nil,"friend","Ari North","keep note","HEALER"))
local zen=assert(A.save(nil,"friend","Zen North","",nil))
for _,name in ipairs({"Bea North","Cal North","Dee North","Eff North","Fox North"}) do
    assert(A.save(nil,"friend",name,"",nil))
end
local blacklist=assert(A.save(nil,"blacklist","Bad North","",nil,{"other"}))
S.Refresh()
assert(not S.favoriteHeading:IsShown() and S.count:GetText()=="1–5 of 7")
S.searchBox:SetText("Zen North")
local button=S.rows[1].favoriteButton
local emptyU=S.rows[1].favoriteGlyph.texCoord[1]
assert(button:IsVisible() and S.rows[1].record.id==zen.id and not S.rows[1].record.favorite)
button:Click()
assert(A.store.get(zen.id).favorite and S.rows[1].favoriteGlyph.texCoord[1]>emptyU)
assert(S.favoriteHeading:IsShown() and S.favoriteHeading:GetText()=="Favorites" and not S.otherFriendsHeading:IsShown())
S.searchBox:SetText("")
assert(S.rows[1].record.id==zen.id and S.rows[2].record.id==ari.id and S.otherFriendsHeading:IsShown())
assert(S.count:GetText()=="1–4 of 7")
local _,_,firstY=S.rows[1]:GetPoint()
local _,_,labelY=S.otherFriendsHeading:GetPoint()
local _,_,secondY=S.rows[2]:GetPoint()
assert(firstY-S.rows[1]:GetHeight()>labelY and labelY>secondY)
local _,starX=button:GetPoint()
local _,nameX=S.rows[1].name:GetPoint()
assert(starX+button:GetWidth()<nameX)
S.rows[2].favoriteButton:Click()
assert(S.rows[1].record.id==ari.id and S.rows[2].record.id==zen.id)
assert(S.rows[3].record.fullName=="Bea North")

-- Sorting and filtering retain the exact selected record.
S.Select(S.rows[1].record)
S.sortByName=false
S.Refresh()
assert(S.selected and S.selected.id==ari.id)
local favorite=assert(A.store.get(ari.id))
assert(favorite.note=="keep note" and favorite.role=="HEALER" and favorite.favorite)
assert(A.save(favorite,"friend",favorite.fullName,"edited note",favorite.role))
assert(A.store.get(ari.id).favorite and A.store.get(ari.id).note=="edited note")
S.searchBox:SetText("Ari North")
s:fire(button,"OnMouseDown","LeftButton")
A.refresh(); S.Refresh()
button:Click()
assert(not A.store.get(ari.id).favorite)
button:Click()
assert(A.store.get(ari.id).favorite)
s:fire(button,"OnMouseDown","LeftButton")
S.searchBox:SetText("Bea North")
button:Click()
assert(not A.store.get(S.rows[1].record.id).favorite and A.store.get(ari.id).favorite)
S.searchBox:SetText("Ari North")
config.region=4
button:Click()
assert(A.store.get(ari.id).favorite and S.footer:GetText():find("Region",1,true))
config.region=3
local clock=e.GetServerTime
local before=e.WhowhoAddressBookDB
e.GetServerTime=function()
    config.region=4
    return clock()
end
button:Click()
assert(config.region==4 and e.WhowhoAddressBookDB==before and A.store.get(ari.id).favorite)
e.GetServerTime=clock; config.region=3

local reopened,sim=H.fresh(root,e.WhowhoPreviewDB,{484,800},{region=3,time=110,db=e.WhowhoAddressBookDB})
sim:event("ADDON_LOADED","WhoWho"); reopened.Toggle()
local view=reopened.Shell
assert(view.rows[1].record.id==ari.id and view.rows[2].record.id==zen.id)
view.rows[1].favoriteButton:Click()
assert(not reopened.manual.store.get(ari.id).favorite and view.rows[1].record.id==zen.id)
assert(reopened.manual.store.get(ari.id).note=="edited note")
view.SetSection("blacklist")
assert(view.rows[1].record.id==blacklist.id and not view.rows[1].favoriteButton:IsShown())
assert(not view.favoriteHeading:IsShown() and not view.otherFriendsHeading:IsShown())
assert(not reopened.manual.setFavorite(view.rows[1].record,true))
local moved=assert(reopened.manual.save(reopened.manual.store.get(zen.id),"blacklist","Zen North","",nil,{"other"},true))
assert(moved.membership=="blacklist" and not reopened.manual.store.get(zen.id).favorite)
assert(s.forbiddenCalls+sim.forbiddenCalls==0)
print("RESULT favorite Friends groups and persistent row stars passed in simulation")
