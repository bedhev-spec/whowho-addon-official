-- A native ownership read can dispatch chat after source validation finishes.
local root=arg[1] or "."
local H=dofile(root.."/tests/addon/harness.lua")
local function run(section, quick, changeAt, update, nextTick)
    local clock={region=3,time=100}
    local P, sim, e=H.fresh(root,nil,nil,clock)
    local name,guid="Final Lease","Player-1-ABC"
    e.InCombatLockdown=function() return false end
    e.UnitExists=function(token) return token=="player" end
    e.UnitIsPlayer=e.UnitExists
    e.UnitGUID=function(token) return token=="player" and "Player-1-123" end
    e.GetUnitName=function() return "Current Character" end
    e.C_ChatInfo={InChatMessagingLockdown=function() return false end}
    e.GetPlayerInfoByGUID=function() return "Mage","MAGE" end
    e.RAID_CLASS_COLORS={MAGE={}}
    sim:event("ADDON_LOADED","WhoWho")
    local A=P.manual
    A.checkFriend=function() end
    local function chat(author, sender)
        sim:event("CHAT_MSG_SAY","unused",author,nil,nil,nil,nil,nil,nil,nil,nil,nil,sender)
    end
    chat(name,guid)
    P.Shell.Open()
    if quick then
        local observation=assert(A.playerEvidence.resolve(name,A.store,3))
        P.Shell.OpenPlayerAdd(section,name,{quickAdd=true,name=name,guid=guid,
            region=3,store=A.store,source="Chat menu",observation=observation})
    else
        P.Shell.addButton:Click()
        P.Shell.editor.controls.formName:SetText(name)
    end
    local f=P.Shell.editor.controls
    if section=="blacklist" then f.reasonOptions.other:Click() end
    local armed,calls,lastPre,fired=false,0,0,false
    local method=quick and "refreshChat" or "cachedChat"
    local resolve=A.playerEvidence[method]
    A.playerEvidence[method]=function(...)
        local observed=resolve(...)
        if observed then armed=true end
        return observed
    end
    e.GetCurrentRegion=function()
        if armed and not fired then
            calls=calls+1
            if not A.store.find(3,name) then lastPre=calls end
            if calls==changeAt then
                fired=true
                if nextTick then clock.time=clock.time+1 end
                if update=="conflict" then chat(name,"Player-1-DEF")
                elseif update=="repeat" then chat(name,guid)
                else chat("Unrelated Sender","Player-1-FFF") end
            end
        end
        return 3
    end
    f.formSave:Click()
    local saved=assert(A.store.find(3,name))
    assert(not f.form:IsShown() and sim.forbiddenCalls==0)
    return lastPre,saved.lastKnown,fired
end
for _, mode in ipairs({{"friend",false},{"friend",true},{"blacklist",true}}) do
    local boundary,known=run(mode[1],mode[2])
    assert(boundary>0 and known and known.guid=="Player-1-ABC")
    for _, nextTick in ipairs({false,true}) do
        for _, update in ipairs({"conflict","repeat","unrelated"}) do
            local _,current,fired=run(mode[1],mode[2],boundary,update,nextTick)
            assert(fired,"the update must run in the final native ownership read")
            if update=="conflict" then
                assert(not current,"a retired passive lease cannot attach metadata after final ownership reads")
            else
                assert(current and current.guid=="Player-1-ABC" and current.class.value=="MAGE",
                    "compatible or unrelated chat preserves exact cached class")
            end
        end
    end
end
print("RESULT final passive evidence leases passed in simulation")
