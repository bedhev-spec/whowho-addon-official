-- Offline widget simulation of editor save validation; not a native-client test.
local root=arg[1] or "."
local H=dofile(root.."/tests/addon/harness.lua")
local count=0
local function check(value, label) count=count+1; assert(value,label) end
local p,s,e=H.fresh(root,nil,nil,{region=3,time=100})
local saveCalls,saveManual=0,p.manual.save
p.manual.save=function(...) saveCalls=saveCalls+1; return saveManual(...) end
s:event("ADDON_LOADED","WhoWho"); p.Toggle()
local S=p.Shell
local form
local function addFriend(name,note)
    S.addButton:Click(); form=S.editor.controls
    form.formName:SetText(name); form.formNote:SetText(note); form.formSave:Click()
end
local function snapshot()
    local out={#S.records}
    for _,r in ipairs(S.records) do out[#out+1]=r.id.."|"..r.fullName.."|"..tostring(r.note) end
    return table.concat(out,";")
end
S.nav.friend:Click()
addFriend("Élan Amber","kept note")
check(#S.records==1 and not form.form:IsShown() and saveCalls==1,"seed record saved")
local before=snapshot()

S.editButton:Click()
-- The note box trims over-long input as you type; drop the handler to reach the save-time length check.
form.formNote:SetScript("OnTextChanged",nil)
form.formNote:SetText(("x"):rep(257)); form.formSave:Click()
check(form.formError:GetText()=="Note must be valid text of at most 256 characters."
    and form.form:IsShown() and snapshot()==before,"overlong note is rejected and nothing is saved")
form.form:Hide()

S.editButton:Click()
form.formName:SetText("Élan Copper"); form.formSave:Click()
check(form.formError:GetText()=="Name is fixed for this saved character."
    and form.form:IsShown() and snapshot()==before,"saved name cannot change and nothing is saved")
form.form:Hide()

S.editButton:Click()
local realSecret=e.issecretvalue
form.formNote:SetText("changed"); e.issecretvalue=function() return true end
form.formSave:Click(); e.issecretvalue=realSecret
check(form.formError:GetText()=="Text unavailable; no changes saved."
    and form.form:IsShown() and snapshot()==before,"unreadable text is rejected and nothing is saved")
form.form:Hide()

S.addButton:Click(); form=S.editor.controls
form.formName:SetText("Élan Amber"); form.formNote:SetText("other note"); form.formSave:Click()
check(form.formError:GetText()=="Already in Friends: Élan Amber" and form.formSave.label:GetText()=="Open existing"
    and form.form:IsShown() and snapshot()==before and saveCalls==1,"duplicate offers the existing entry and nothing is saved")
check(s.forbiddenCalls==0,"zero forbidden actions")
print(("RESULT editor form %d checks passed"):format(count))
