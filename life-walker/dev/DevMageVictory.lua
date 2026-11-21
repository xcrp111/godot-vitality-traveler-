-- DevMageVictory.lua — 排查：清空房间后法师角色消失
local Config = require "Config"
local Save = require "Save"
local S = require "State"
local Run = require "Run"
local Combat = require "Combat"
local CharArt = require "CharArt"
local UI = require "UI"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Vict] OK   " .. name)
    else
        fails = fails + 1
        print("[Vict] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
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
    S.font = nvgCreateFont(S.ctx, "sans", "Fonts/MiSans-Game.ttf")

    -- 图集信息
    local img = UI.ImageHandle("image/char/mage.png")
    local iw, ih = 0, 0
    if img then iw, ih = nvgImageSize(S.ctx, img) end
    print(string.format("[Vict] mage 图集 %dx%d，行数 %.2f", iw, ih, ih / CharArt.CELL_H))
    check("图集宽度 1280", iw == 1280, iw)
    check("图集高度 = 18 行", ih == 18 * CharArt.CELL_H, ih)

    S.data = Save.Load()
    Save.SetClass(S.data, "mage")
    Save.SetClassLevel(S.data, 12)
    Config.SetClass("mage")
    Run.Start(3, true)
    S.run.loadout = { 1, 4, 5 }
    local cs = Combat.Start(S.run, "standard", 1)
    S.combat = cs
    S.screen = "combat"
    cs.enemies, cs.walls, cs.waveIndex = {}, {}, 1
    cs.waves = { { minion = 1 } }
    Combat.SpawnWave(cs, { minion = 1 })
    local e = cs.enemies[1]
    check("刷出一只小怪", e ~= nil)

    -- 每行都画一次，确认没有越界行
    for row = 1, 18 do
        local ok = CharArt.Draw("mage", row, 1, 400, 400, false, 1)
        check("第 " .. row .. " 行能画", ok == true)
    end

    -- 打死最后一只怪
    e.hp = 1
    Combat.HitEnemy(cs, e, 9999, true, true, false, "skill")
    for _ = 1, 5 do Combat.Update(1 / 60) end
    print(string.format("[Vict] 清空后 anim=%s row=%s",
        tostring(cs.anim and cs.anim.action), tostring(cs.anim and cs.anim.row)))
    check("清空后播胜利动作", cs.anim and cs.anim.action == "victory",
        cs.anim and cs.anim.action)
    check("胜利动作落在图集内", cs.anim and cs.anim.row and cs.anim.row <= 18,
        cs.anim and cs.anim.row)

    -- 胜利期间每帧画一次，看是否画得出来
    local drawn = 0
    local frames = 0
    for _ = 1, 90 do
        CharArt.Update(cs, 1 / 60)
        Combat.Update(1 / 60)
        frames = frames + 1
        if CharArt.DrawPlayer(cs) then drawn = drawn + 1 end
        if not cs.anim then break end
    end
    check("胜利动作期间每帧都画得出来", drawn == frames,
        string.format("画出来 %d / %d 帧", drawn, frames))
    check("胜利动作会结束", cs.anim == nil or cs.anim.action ~= "victory",
        cs.anim and cs.anim.action)

    print(string.format("[Vict] done, failures = %d", fails))
end
