-- DevServerProbe.lua — 探测"服务端到底有没有起来/回包"（只在联机模式有意义）
-- 判读：
--   FarmClient.serverDiag.boot 有值 → 服务端已启动并处理过 sync
--   guild sync resp ok=true      → 服务端路由通
local S = require "State"
local NetCore = require "network.NetCore"
local FarmClient = require "network.FarmClient"
local GuildClient = require "network.GuildClient"

local frames = 0
local lastResp = "（还没发）"

function ProbeTick()
    frames = frames + 1
    if frames % 60 == 0 then FarmClient.ReadServerDiag() end
    if frames % 120 == 1 then
        local diag = FarmClient.serverDiag
        print(string.format("[Probe] f=%d netOnline=%s farmOnline=%s tries=%s diagBoot=%s diagErr=%s",
            frames, tostring(NetCore.online), tostring(FarmClient.online),
            tostring(S.farmNetTries or 0),
            tostring(diag and diag.boot), tostring(FarmClient.serverDiagErr)))
        print("[Probe]   lastGuildResp=" .. tostring(lastResp)
            .. " uid=" .. tostring(NetCore.uid) .. " cloud=" .. tostring(clientCloud ~= nil))
    end
    if frames % 180 == 90 then
        GuildClient.online = true            -- 探测用：绕过 UI 的门槛，直测传输层
        GuildClient.Sync(function(resp)
            lastResp = string.format("ok=%s msg=%s boot=%s",
                tostring(resp and resp.ok), tostring(resp and (resp.msg or resp.code)),
                tostring(resp and resp.serverBoot))
            print("[Probe] guild sync -> " .. lastResp)
        end)
        print("[Probe] guild sync sent (available=" .. tostring(GuildClient.Available()) .. ")")
    end
end

function Start()
    SubscribeToEvent("Update", "ProbeTick")
    print("[Probe] started")
end

function Stop() end
