-- DevWalls.lua — 墙体数量与最小缝隙检查
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local VirtualControls = require "urhox-libs.UI.VirtualControls"

function Start()
    local dpr = graphics:GetDPR()
    if not dpr or dpr <= 0 then dpr = 1 end
    S.dpr = dpr
    S.W = graphics:GetWidth() / dpr
    S.H = graphics:GetHeight() / dpr
    S.scale = math.min(S.W / Config.DESIGN_W, S.H / Config.DESIGN_H)
    S.offX = (S.W - Config.DESIGN_W * S.scale) / 2
    S.offY = (S.H - Config.DESIGN_H * S.scale) / 2
    VirtualControls.Initialize(Config.DESIGN_W, Config.DESIGN_H)
    S.data = Save.Load()
    Save.SetClassLevel(S.data, 5)
    for run = 1, 12 do
        Run.Start(1)
        local cs = Combat.Start(S.run, "standard", run)
        local walls = cs.walls
        local minGap = 9999
        for i = 1, #walls do
            for j = i + 1, #walls do
                local a, b = walls[i], walls[j]
                local dx = math.max(0, math.max(a.x - (b.x + b.w), b.x - (a.x + a.w)))
                local dy = math.max(0, math.max(a.y - (b.y + b.h), b.y - (a.y + a.h)))
                local gap = math.sqrt(dx * dx + dy * dy)
                if gap < minGap then minGap = gap end
            end
        end
        print(string.format("[Walls] run=%d count=%d minGap=%s", run, #walls,
            minGap > 9000 and "-" or string.format("%.0f", minGap)))
    end
end
