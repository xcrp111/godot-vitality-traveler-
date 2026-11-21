-- DevFarmServer.lua — 农场服务端模块回归（不依赖真实网络/服务器）
local FarmStore = require "FarmStore"
local FarmServer = require "network.FarmServer"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Srv] OK   " .. name)
    else
        fails = fails + 1
        print("[Srv] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

local function sync(fn)
    local done, result = false, nil
    fn(function(v) done, result = true, v end)
    local guard = 0
    while not done and guard < 100 do guard = guard + 1 end
    return result
end

function Start()
    FarmServer.Reset()

    -- 1) 无 serverCloud 时走内存兜底
    local doc = sync(function(cb) FarmServer.LoadDoc("u1", cb) end)
    check("取到文档", doc ~= nil and doc.uid == "u1", doc and doc.uid)
    check("默认 4 块地", doc.landCount == 4, doc.landCount)

    -- 2) 同一 uid 复用缓存
    local again = sync(function(cb) FarmServer.LoadDoc("u1", cb) end)
    check("同 uid 复用同一份文档", again == doc)

    -- 3) 种地 + 同步包
    doc.name = "阿茶"
    doc.seeds.fire = 2
    FarmStore.Plant(doc, 1, "fire", os.time())
    FarmServer.SaveDoc(doc)
    local payload = FarmServer.SyncPayload(doc)
    check("同步包含 uid/名字", payload.uid == "u1" and payload.name == "阿茶")
    check("同步包带地块", payload.plots and payload.plots[1] and payload.plots[1].crop == "fire",
        payload.plots and payload.plots[1] and payload.plots[1].crop)
    check("同步包带种子/果实", payload.seeds ~= nil and payload.fruits ~= nil)
    check("同步包带好友列表", type(payload.friends) == "table")

    -- 4) 好友 + 未读事件进同步包
    local other = sync(function(cb) FarmServer.LoadDoc("u2", cb) end)
    other.name = "白露"
    FarmStore.RequestFriend(doc, other, os.time())
    FarmStore.AcceptFriend(other, doc, os.time())
    check("成为好友", doc.friends["u2"] ~= nil and other.friends["u1"] ~= nil)
    local ts = os.time()
    other.seeds.ice = 1
    FarmStore.Plant(other, 2, "ice", ts)
    local okW, errW = FarmStore.Water(other, 2, ts + 30, { uid = "u1", name = "阿茶" })
    check("好友浇水成功", okW == true, errW)
    local payload2 = FarmServer.SyncPayload(other)
    check("同步包带未读事件", #(payload2.events or {}) >= 1, #(payload2.events or {}))
    check("事件里有浇水", (function()
        for _, e in ipairs(payload2.events or {}) do
            if e.kind == "water" then return true end
        end
        return false
    end)())
    local payload3 = FarmServer.SyncPayload(doc)
    check("同步包好友列表有对方名字", (function()
        for _, f in ipairs(payload3.friends or {}) do
            if f.uid == "u2" then return true end
        end
        return false
    end)())

    print(string.format("[Srv] done, failures = %d", fails))
end
