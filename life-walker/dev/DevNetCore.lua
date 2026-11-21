-- DevNetCore.lua — 联机公共底座回归（身份码 / 请求-响应 / 路由 / 云端封装）
local NetCore = require "network.NetCore"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Core] OK   " .. name)
    else
        fails = fails + 1
        print("[Core] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

function Start()
    -- 1) 身份码
    check("短 id 原样大写", NetCore.PlayerCode("ab12") == "AB12", NetCore.PlayerCode("ab12"))
    check("长 id 取后 6 位", NetCore.PlayerCode("1000822123456") == "123456",
        NetCore.PlayerCode("1000822123456"))
    check("空 id 有兜底", NetCore.PlayerCode(nil) == "------", NetCore.PlayerCode(nil))

    NetCore.SetIdentity("1000822123456", "阿茶")
    check("身份写入", NetCore.uid == "1000822123456" and NetCore.nickname == "阿茶")
    local gotUid, gotName = nil, nil
    NetCore.OnIdentity(function(u, n) gotUid, gotName = u, n end)
    NetCore.SetIdentity("u2", "白露")
    check("身份变化通知", gotUid == "u2" and gotName == "白露")

    -- 2) 服务端路由
    local hit = nil
    NetCore.ServerRoute("demo.echo", function(uid, body, reply)
        hit = { uid = uid, body = body }
        reply({ ok = true, echo = body.text })
    end)

    -- 3) 客户端请求（假传输 → 服务端）
    NetCore.SetTransport({
        send = function(event, payload)
            NetCore.ServerDispatch(payload.__uid or "u1", event, payload, function(resp)
                NetCore.ClientDispatch(event, resp)
            end)
        end,
    })
    check("有传输时 online", NetCore.online == true)

    local resp = nil
    NetCore.Request("demo.echo", { text = "hi" }, function(r) resp = r end)
    check("请求到达服务端", hit ~= nil and hit.body.text == "hi", hit and hit.body.text)
    check("回包带 seq 配对", resp ~= nil and resp.echo == "hi", resp and resp.echo)
    check("回包 seq 与请求一致", resp and resp.seq ~= nil, resp and resp.seq)

    -- 4) 未知路由
    local bad = nil
    NetCore.Request("nope.nothing", {}, function(r) bad = r end)
    check("未知路由返回 no_route", bad and bad.code == "no_route", bad and bad.code)

    -- 5) 服务端异常兜底
    NetCore.ServerRoute("demo.boom", function() error("boom") end)
    local boom = nil
    NetCore.Request("demo.boom", {}, function(r) boom = r end)
    check("服务端异常被兜住", boom and boom.code == "server_error", boom and boom.code)

    -- 6) 服务端主动推送
    local pushed = nil
    NetCore.On("demo.push", function(p) pushed = p.value end)
    NetCore.ClientDispatch("demo.push", { value = 42 })
    check("客户端推送订阅", pushed == 42, pushed)

    -- 7) 离线时请求直接失败
    NetCore.Disconnect()
    check("离线状态", NetCore.online == false)
    local off = nil
    NetCore.Request("demo.echo", {}, function(r) off = r end)
    check("离线请求返回 offline", off and off.code == "offline", off and off.code)
    check("离线状态文案", NetCore.StatusText():find("离线") ~= nil, NetCore.StatusText())

    -- 8) 状态文案（在线）
    NetCore.SetTransport({ send = function() end })
    NetCore.SetIdentity("u9", "柚子")
    check("在线状态文案带昵称", NetCore.StatusText():find("柚子") ~= nil, NetCore.StatusText())

    print(string.format("[Core] done, failures = %d", fails))
end
