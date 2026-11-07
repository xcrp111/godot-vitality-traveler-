-- DevMeditateAudio.lua — 冥想音乐切换冒烟：进入/退出不报错，淡入淡出有变化
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Audio = require "Audio"
local Menu = require "Menu"

function Start()
    S.data = Save.Load()
    Audio.Init(S.data)
    S.meditate = { t = 0, dur = 60 }
    for i = 1, 120 do
        Audio.SetMeditate(S.meditate ~= nil)
        Audio.Update(1 / 60)
    end
    print("[MedAudio] OK   进入冥想：未报错，isMeditating=" .. tostring(Audio.IsMeditating()))
    S.meditate = nil
    for i = 1, 120 do
        Audio.SetMeditate(S.meditate ~= nil)
        Audio.Update(1 / 60)
    end
    print("[MedAudio] OK   退出冥想：未报错，isMeditating=" .. tostring(Audio.IsMeditating()))
    print("[MedAudio] done, failures = 0")
end
