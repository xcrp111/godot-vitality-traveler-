-- server_main.lua — 服务端入口（构建时用 entry_server 指到这里）
--
-- 为什么单独一个文件：
--   main.lua 在加载阶段会 require 一堆渲染相关的模块（UI / SceneUI / FarmArt / Combat…），
--   服务端是无渲染的 headless 进程，这些模块很可能在加载期就报错，
--   导致整个服务端脚本加载失败、客户端永远等不到回包。
--   服务端只需要「农场数据服务」，所以单独给一个极简入口，只加载纯逻辑模块。

local function Boot()
    print("[server] 服务端脚本加载开始")
    local ok, err = xpcall(function()
        local FarmServer = require "network.FarmServer"
        FarmServer.Start()
    end, function(e)
        local okTb, trace = pcall(function() return debug.traceback("", 2) end)
        return tostring(e) .. (okTb and trace and ("\n" .. trace) or "")
    end)
    if not ok then
        print("[server] 启动失败: " .. tostring(err))
    else
        print("[server] 服务端已就绪（等待客户端同步请求）")
    end
end

--- 引擎每帧调用：驱动云变量轮询（服务端没有远程事件也能收到请求）
function FarmServerOnUpdate()
    local okPoll, err = pcall(function()
        local FarmServer = require "network.FarmServer"
        FarmServer.Poll()
    end)
    if not okPoll then print("[server] poll 出错: " .. tostring(err)) end
end

function Start()
    Boot()
end

function Stop()
    local ok = pcall(function()
        local FarmServer = require "network.FarmServer"
        FarmServer.Stop()
    end)
    if not ok then print("[server] 停止时出错") end
end
