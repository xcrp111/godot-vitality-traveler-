-- DevReplaceView.lua — 截图验收：强化替换界面（点选查看效果 + 替换按钮）
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local UI = require "UI"
local Run = require "Run"
local Screens = require "Screens"

local frame = 0

local function CollectBuffs(n)
    local list = {}
    for _, rarity in ipairs({ "white", "blue", "purple", "gold" }) do
        for _, b in ipairs(Config.ClassBuffs.ranger[rarity] or {}) do
            list[#list + 1] = { buff = b, rarity = rarity }
        end
    end
    return list
end

function Start()
    local dpr = graphics:GetDPR(); if not dpr or dpr <= 0 then dpr = 1 end
    S.dpr = dpr
    S.W = graphics:GetWidth() / dpr
    S.H = graphics:GetHeight() / dpr
    S.scale = math.min(S.W / Config.DESIGN_W, S.H / Config.DESIGN_H)
    S.offX = (S.W - Config.DESIGN_W * S.scale) / 2
    S.offY = (S.H - Config.DESIGN_H * S.scale) / 2
    S.ctx = nvgCreate(1)
    S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Regular.ttf")
    math.randomseed(7)

    S.data = Save.Load()
    Save.SetClass(S.data, "ranger")
    Save.SetClassLevel(S.data, 10)
    Config.SetClass("ranger")
    Run.Start(3, true)
    S.run.endless = true
    S.screen = "reward"

    local all = CollectBuffs()
    for i = 1, 10 do
        local item = all[i]
        local b = item.buff
        Run.GrantBuff(S.run.player, {
            id = b.id, name = b.name, desc = b.desc,
            mod = b.mod or {}, flag = b.flag or {},
            rarity = item.rarity, classBuff = true,
        })
    end
    local pend = all[11]
    S.reward = {
        options = {}, replace = true, source = "shop", shopIndex = 1,
        pending = {
            id = pend.buff.id, name = pend.buff.name, desc = pend.buff.desc,
            mod = pend.buff.mod or {}, flag = pend.buff.flag or {},
            rarity = pend.rarity, classBuff = true,
        },
        replaceSel = 3,
    }

    SubscribeToEvent(S.ctx, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData)
    frame = frame + 1
end

function HandleRender(eventType, eventData)
    if not S.ctx then return end
    local W, H = graphics:GetWidth(), graphics:GetHeight()
    nvgBeginFrame(S.ctx, W, H, S.dpr)
    UI.BeginDesign()
    nvgBeginPath(S.ctx)
    nvgRect(S.ctx, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(S.ctx, nvgRGBA(20, 16, 26, 255))
    nvgFill(S.ctx)
    Screens.DrawReward()
    UI.EndDesign()
    nvgEndFrame(S.ctx)
end
