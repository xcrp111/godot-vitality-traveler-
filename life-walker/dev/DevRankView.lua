-- DevRankView.lua — 截图验收：排行榜界面（假云数据）
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local UI = require "UI"
local Cloud = require "Cloud"
local RankUI = require "RankUI"

local frame = 0

local NAMES = {
    "步数达人", "深夜剑客", "农场主老张", "半途行者", "血尘收藏家",
    "无尽挑战者", "医学生小林", "早八人", "百步穿杨", "夜跑阿杰",
    "隐者", "路人甲", "枪客阿七", "法师学徒", "游侠小鹿",
    "养生派", "健步如飞", "岁月静好", "不眠之眼", "最后一位行者",
}

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
    math.randomseed(11)

    S.data = Save.Load()
    S.data.endlessBest = 17
    S.data.stageCleared = 12
    S.rank = true
    S.rankTab = 1

    -- 假云变量：直接写榜单缓存，不走网络
    clientCloud = {
        userId = 2001,
        BatchSet = function(self)
            local b = {}
            function b:SetInt() return self end
            function b:Set() return self end
            function b:Add() return self end
            function b:Delete() return self end
            function b:Save() end
            return b
        end,
        GetRankList = function(self, key, start, count, events)
            local list = {}
            for i = 1, 20 do
                list[i] = { userId = 3000 + i, iscore = { [key] = 30 - i } }
            end
            list[9] = { userId = 2001, iscore = { [key] = 17 } }
            events.ok(list)
        end,
        GetUserRank = function(self, uid, key, events) events.ok(9, 17) end,
        GetRankTotal = function(self, key, events) events.ok(128) end,
    }
    GetUserNickname = function(opts)
        local out = {}
        for _, uid in ipairs(opts.userIds) do
            local n = NAMES[(uid - 3000) % #NAMES + 1]
            out[#out + 1] = { userId = uid, nickname = (uid == 2001) and "我自己" or n }
        end
        opts.onSuccess(out)
    end
    Cloud._avail = nil
    Cloud._state = {}
    Cloud._names = {}
    Cloud.Refresh("endless", true)

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
    nvgFillColor(S.ctx, nvgRGBA(18, 20, 18, 255))
    nvgFill(S.ctx)
    RankUI.Draw()
    UI.EndDesign()
    nvgEndFrame(S.ctx)
end
