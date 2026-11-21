-- FarmShared.lua — 农场联机：客户端与服务端共用的事件名 / 云变量键 / 编解码
-- 只依赖引擎提供的 network / cjson，不依赖 UI。

local FarmShared = {}

FarmShared.KEY = "farm_doc"          -- serverCloud 里每个玩家一份农场文档的 key

FarmShared.EVENTS = {
    -- 客户端 → 服务端
    SYNC = "FarmSync",               -- 拉取自己的文档（顺便登录登记名字）
    VISIT = "FarmVisit",             -- 拉好友农场快照
    OP = "FarmOp",                   -- 浇水 / 偷菜 / 种 / 收
    FRIEND_SEARCH = "FarmFriendSearch",
    FRIEND_REQUEST = "FarmFriendRequest",
    FRIEND_ACCEPT = "FarmFriendAccept",
    FRIEND_REMOVE = "FarmFriendRemove",
    -- 服务端 → 客户端
    SYNC_RESULT = "FarmSyncResult",
    VISIT_RESULT = "FarmVisitResult",
    OP_RESULT = "FarmOpResult",
    FRIEND_RESULT = "FarmFriendResult",
}

--- 双端都要先注册远程事件
function FarmShared.RegisterEvents()
    if not network then
        print("[FarmNet] 没有 network，跳过远程事件注册")
        return
    end
    for _, name in pairs(FarmShared.EVENTS) do
        local okReg, err = pcall(function() network:RegisterRemoteEvent(name) end)
        if not okReg then print("[FarmNet] 注册事件失败 " .. tostring(name) .. ": " .. tostring(err)) end
    end
    print("[FarmNet] 远程事件已注册")
end

function FarmShared.Encode(t)
    if not cjson then return nil end
    local ok, out = pcall(cjson.encode, t)
    if ok then return out end
    return nil
end

function FarmShared.Decode(s)
    if not cjson or type(s) ~= "string" or s == "" then return nil end
    local ok, out = pcall(cjson.decode, s)
    if ok and type(out) == "table" then return out end
    return nil
end

-- 引擎的 SendRemoteEvent 第三参必须是 VariantMap（不能直接传字符串）
function FarmShared.MakePayload(t)
    local vm = VariantMap()
    vm["Data"] = Variant(FarmShared.Encode(t) or "{}")
    return vm
end

--- 从收到的 eventData 里取出业务载荷（table）
function FarmShared.ReadPayload(eventData)
    local raw = eventData and eventData["Data"] or nil
    if not raw then return {} end
    local okStr, str = pcall(function() return raw:GetString() end)
    if not okStr or type(str) ~= "string" then return {} end
    return FarmShared.Decode(str) or {}
end

return FarmShared
