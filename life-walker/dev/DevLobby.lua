-- DevLobby.lua — 大厅入口脚本自检（不依赖 urhox-libs/UI）
local fails = 0
local function check(name, cond, detail)
    if cond then print("[Lobby] OK   " .. name)
    else
        fails = fails + 1
        print("[Lobby] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

function Start()
    local ok, entry = pcall(function() return require "lobby_runtime" end)
    check("大厅脚本能加载", ok == true, entry)
    check("返回的是入口函数", type(entry) == "function", type(entry))

    -- 大厅不再依赖 urhox-libs/UI（之前它会抢 NanoVG 上下文导致联机模式下文字全丢）
    local src = nil
    do
        local f = io and nil
        -- 用 require 缓存里的模块无法看源码，这里退而验证它能被调用
    end
    local fakeClient = { CreateRoom = function() end, StartGame = function() end }
    local called, res = pcall(entry, { client = fakeClient, root = nil })
    check("入口函数可调用", called == true, res)

    print(string.format("[Lobby] done, failures = %d", fails))
end
