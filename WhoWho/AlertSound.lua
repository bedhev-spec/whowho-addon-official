local P=WhowhoPreview
local A=P.manual
local S={}
A.alertSound=S
local murlocAggro=416
local playing=false

local function playFunction()
    local play=A.nativeRead.member(C_Sound,"PlaySoundWithOptions")
    if type(play)=="function" then return play end
end

function S.available()
    return playFunction()~=nil
end

function S.volume()
    return P.db.alertSoundVolume
end

function S.setVolume(value)
    if type(value)~="number" or value~=value or math.abs(value)==math.huge then value=0 end
    value=math.floor(math.max(0,math.min(100,value))+.5)
    P.db.alertSoundVolume=value
    return value
end

function S.enabled()
    return P.db.alertSoundEnabled==true
end

function S.setEnabled(value)
    P.db.alertSoundEnabled=value==true
    return true
end

local function bannerReady(ownsBanner)
    local ok,owns=pcall(ownsBanner)
    return ok and owns==true and S.enabled()
end

local function play(ownsBanner)
    if playing or S.volume()==0 or ownsBanner and not S.enabled() then return end
    playing=true
    local fn=playFunction()
    if fn and (not ownsBanner or bannerReady(ownsBanner)) then
        local volume=S.volume()
        if volume>0 then
            pcall(fn,{
                soundKitID=murlocAggro,
                forceNoDuplicates=true,
                volumeOverride=volume*1.2/100,
            })
        end
    end
    playing=false
end

function S.preview()
    play()
end

function S.playBanner(ownsBanner)
    play(ownsBanner)
end
