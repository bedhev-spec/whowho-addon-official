-- Pure fixture decisions: no harness, widgets, client globals or TOC bootstrap.
local root=arg[1] or "."
local widgetCalls=0
local env={WhowhoPreview={},string=string,table=table,math=math,ipairs=ipairs,type=type,tonumber=tonumber}
env.CreateFrame=function() widgetCalls=widgetCalls+1; error("pure model attempted widget creation") end
local path=root.."/WhoWho/RosterModel.lua"
local chunk
if _VERSION=="Lua 5.1" then chunk=assert(loadfile(path)); setfenv(chunk,env)
else chunk=assert(loadfile(path,"t",env)) end
chunk()
local M=assert(env.WhowhoPreview.RosterModel)
local passed,failed=0,0
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed=passed+1; print("PASS pure-model "..name)
    else failed=failed+1; print("FAIL pure-model "..name..": "..tostring(err)) end
end
local records={
    {id="z",fullName="Zora Étoile",membership="friend",role="TANK",class="MAGE",presence="Online",connectionEvidence=true},
    {id="a",fullName="alice Moonbrook",membership="friend",presence="Online"},
    {id="e",fullName="Aéliane Moonbrook",membership="friend",role="HEALER",class="PRIEST",presence="Seen",source="Who",observed="2026-11-17"},
    {id="b",fullName="Bram Moonbrook",membership="blacklist",presence="Offline",connectionEvidence=true},
    {id="p",fullName="[Pattern] Percent%",membership="friend"},
}
local function filter(criteria) criteria.section=criteria.section or "friend"; return M.Filter(records,criteria) end
test("literal ASCII case search preserves accented bytes",function()
    eq(filter({query="ALICE"})[1],records[2]); eq(filter({query="Aéliane"})[1],records[3])
    eq(#filter({query="Aeliane"}),0); eq(#filter({query="Étoile"}),1)
end)
test("pattern metacharacters are literal text",function()
    for _,query in ipairs({"[", "%", "[Pattern]"}) do eq(filter({query=query})[1],records[5]) end
    for _,query in ipairs({".*", "^", "(a"}) do eq(#filter({query=query}),0) end
end)
test("section role class and verified status filters intersect",function()
    eq(filter({roleFilter="TANK",classFilter="MAGE",statusFilter="Online"})[1],records[1])
    eq(#filter({roleFilter="HEALER",classFilter="MAGE"}),0)
    eq(M.Filter(records,{section="blacklist",statusFilter="Offline"})[1],records[4])
    eq(#M.Filter(records,{section="settings"}),0)
end)
test("Unknown and unassigned include missing evidence only",function()
    local result=filter({roleFilter="UNASSIGNED",classFilter="UNASSIGNED",statusFilter="Unknown"})
    eq(#result,2); eq(result[1],records[2]); eq(result[2],records[5])
    eq(M.Presence({presence="Seen",source="Who"}),"Unknown")
    eq(M.Presence({presence="Offline"}),"Unknown")
    eq(M.Presence(records[3]),"Seen")
end)
test("each presence caption matches only its own filter",function()
    local record={id="r",fullName="Report",membership="friend",presence="Seen",source="Target",observed="2026-11-17"}
    local cases={
        {"Online","Online",true},{"Offline","Offline",true},
        {"Listed","Online",false,"listed",true},{"Listed","Offline",false,"listed",false},
        {"Checked","Online",false,"checked",true},{"Checked","Offline",false,"checked",false},
        {"Seen","Unknown"},{"Unknown","Unknown",false,"checked"},{"Unknown","Unknown",false,nil,nil,true},
    }
    eq(#M.presenceChoices,3)
    for _,case in ipairs(cases) do
        record.presence=case[3] and case[1] or "Seen"
        record.connectionEvidence=case[3]
        record.presenceReport=case[4] and {kind=case[4],online=case[5],source="Guild"} or nil
        record.identityState=case[6] and "unresolved" or nil
        local state,caption,date=M.Presence(record)
        eq(state,case[1]); eq(caption,case[2]); eq(date,state=="Seen" and "2026-11-17" or nil)
        eq(M.Filter({record},{section="friend"})[1],record)
        for _,filter in ipairs(M.presenceChoices) do
            eq(#M.Filter({record},{section="friend",statusFilter=filter}),caption==filter and 1 or 0)
        end
    end
    record.identityState=nil
    record.presenceReport={kind="checked",online=false,source="Party"}
    record.presence="Online"; record.connectionEvidence=true; eq(M.Presence(record),"Online")
    eq(#M.Filter({record},{section="friend",statusFilter="Offline"}),0)
end)
test("personal Blacklist uses the row's effective class and ignores hidden filters",function()
    local saved={fullName="Saved Class",membership="blacklist",blacklistSavedClass="MAGE",blacklistWhoClass="PRIEST"}
    local temporary={fullName="Who Class",membership="blacklist",blacklistWhoClass="PRIEST"}
    local unknown={fullName="Missing Class",membership="blacklist",class="DRUID"}
    local blacklist={saved,temporary,unknown}
    local criteria={section="blacklist",personalBlacklist=true,roleFilter="TANK",statusFilter="Online"}
    eq(#M.Filter(blacklist,criteria),3)
    for _,case in ipairs({{"MAGE",saved},{"PRIEST",temporary},{"UNASSIGNED",unknown}}) do
        criteria.classFilter=case[1]
        local result=M.Filter(blacklist,criteria)
        eq(#result,1); eq(result[1],case[2])
    end
    temporary.blacklistWhoClass=nil
    eq(#M.Filter(blacklist,criteria),2)
end)
test("sort uses existing name ordering without reordering caller data",function()
    local criteria={section="friend",sortByName=true,query=""}; local result=M.Filter(records,criteria)
    eq(result[1],records[3]); eq(result[2],records[1]); eq(result[3],records[5]); eq(result[4],records[2])
    eq(records[1].id,"z"); eq(records[2].id,"a"); eq(records[3].id,"e"); eq(criteria.query,"")
    eq(M.Filter(records,{section="friend"})[1],records[1]); assert(result~=records)
end)
test("Guild records share search and sorting without using personal entries",function()
    local records={
        {id="guild|one",fullName="Étoile Stone",searchKey="étoile stone",membership="guildBlacklist"},
        {id="guild|two",fullName="Lune Pâle",searchKey="lune pâle",membership="guildBlacklist"},
        {id="personal|one",fullName="Étoile Stone",membership="blacklist"},
    }
    local function key(text) return text:find("É",1,true) and text:gsub("É","é"):lower() or text:lower() end
    local criteria={section="guildBlacklist",query="ÉTO",searchKey=key,sortByName=true}
    eq(M.Filter(records,criteria)[1],records[1])
    criteria.query=""; eq(#M.Filter(records,criteria),2); eq(M.Filter(records,criteria)[1],records[2])
    criteria.descending=true; eq(M.Filter(records,criteria)[1],records[1])
end)
local list={}; for i=1,12 do list[i]={id="id-"..i,fullName="Name "..i} end
test("identity survives immutable record replacement",function()
    local old={id="id-4",fullName="Old name"}
    local state={selected=old,selectedId="id-4",visibleRows=3,offset=2,compactDetail=true}
    local result=M.Reconcile(list,state)
    eq(result.selected,list[4]); eq(result.selectedId,"id-4"); eq(result.offset,2)
    eq(state.selected,old); eq(state.offset,2); eq(old.fullName,"Old name"); assert(result~=state)
end)
test("selected ID owns recipient even when old object differs",function()
    local result=M.Reconcile(list,{selected=list[1],selectedId="id-8",visibleRows=3,offset=0})
    eq(result.selected,list[8]); eq(result.selectedId,"id-8")
end)
test("filtered selection clears recipient and compact record",function()
    local result=M.Reconcile({list[1]},{selected=list[8],selectedId="id-8",visibleRows=3,offset=8,compactDetail=true})
    eq(result.selected,nil); eq(result.selectedId,nil); eq(result.compactDetail,false); eq(result.offset,0)
end)
test("excluded saved identity stays exact and caller state remains unchanged",function()
    local state={selected=list[8],selectedId="id-8",revealSaved=true,savedOutside=false,visibleRows=3,offset=8,compactDetail=false}
    local result=M.Reconcile({list[1]},state)
    eq(result.selected,list[8]); eq(result.selectedId,"id-8"); eq(result.savedOutside,true)
    eq(result.revealSaved,true); eq(result.compactDetail,true); eq(result.offset,0)
    eq(state.offset,8); eq(state.savedOutside,false); eq(state.compactDetail,false)
end)
test("matching saved selection reveals above and below current viewport",function()
    for _,case in ipairs({{2,8,1},{9,1,6}}) do
        local result=M.Reconcile(list,{selected=list[case[1]],selectedId=list[case[1]].id,revealSaved=true,savedOutside=true,visibleRows=3,offset=case[2]})
        eq(result.offset,case[3]); eq(result.revealSaved,false); eq(result.savedOutside,false)
    end
end)
test("already visible save preserves offset and consumes reveal",function()
    local result=M.Reconcile(list,{selected=list[5],selectedId="id-5",revealSaved=true,visibleRows=3,offset=3})
    eq(result.offset,3); eq(result.revealSaved,false); eq(result.savedOutside,false)
end)
test("final page and oversized viewport clamp to actual range",function()
    local result=M.Reconcile(list,{selected=list[12],selectedId="id-12",revealSaved=true,visibleRows=5,offset=0})
    eq(result.offset,7)
    eq(M.Reconcile(list,{visibleRows=5,offset=999}).offset,7)
    eq(M.Reconcile(list,{visibleRows=5,offset=-3}).offset,0)
    eq(M.Reconcile(list,{visibleRows=20,offset=9}).offset,0)
    eq(M.Reconcile({},{visibleRows=5,offset=9}).offset,0)
end)
test("empty initial selection stays empty without selecting first result",function()
    local result=M.Reconcile(list,{visibleRows=3})
    eq(result.selected,nil); eq(result.selectedId,nil); eq(result.offset,0)
end)
test("pure load and all model scenarios create zero widgets",function() eq(widgetCalls,0) end)
print(string.format("RESULT pure-model %d passed %d failed",passed,failed))
if failed>0 then os.exit(1) end
