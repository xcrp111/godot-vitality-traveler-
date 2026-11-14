-- DevCloud.lua — 排行榜逻辑回归（用假 clientCloud 模拟平台云变量）
local S = require "State"
local Save = require "Save"
local Cloud = require "Cloud"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Cloud] OK   " .. name)
    else
        fails = fails + 1
        print("[Cloud] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

-- 假云变量：同步回调，记录写入内容
local submitted = {}
local fakeCloud
function Start()
    S.data = Save.Fresh()
    local d = S.data
    d.endlessBest = 13
    d.stageCleared = 7
    d.farm = d.farm or {}
    d.farm.harvestCount = 21
    d.guild = d.guild or {}
    d.guild.total = 640   -- 榜单取「累计获得的贡献币」

    -- 1) 无云变量环境（例如纯离线运行时）应安全降级
    local realCloud = rawget(_G, "clientCloud")
    _G.clientCloud = nil
    Cloud._avail = nil
    check("无云变量时 Available=false", Cloud.Available() == false)
    check("无云变量时 MaybeSubmit 不报错", Cloud.MaybeSubmit(d) == false)
    local st0 = Cloud.State("endless")
    check("无云变量时 Refresh 返回 false", Cloud.Refresh("endless", true) == false)
    check("状态标记 unsupported", st0.status == "unsupported", st0.status)
    _G.clientCloud = realCloud
    Cloud._avail = nil

    -- 2) 注入假云变量
    fakeCloud = {
        userId = 1001,
        BatchSet = function(self)
            local batch = { ops = {} }
            function batch:SetInt(key, value)
                self.ops[#self.ops + 1] = { key = key, value = value }
                return self
            end
            function batch:Set(key, value)
                self.ops[#self.ops + 1] = { key = key, value = value }
                return self
            end
            function batch:Add(key, value)
                self.ops[#self.ops + 1] = { key = key, value = value }
                return self
            end
            function batch:Delete(key) return self end
            function batch:Save(desc, events)
                submitted[#submitted + 1] = self.ops
                if events and events.ok then events.ok() end
            end
            return batch
        end,
        GetRankList = function(self, key, start, count, events)
            events.ok({
                { userId = 1001, iscore = { [key] = 13 } },
                { userId = 1002, iscore = { [key] = 9 } },
            })
        end,
        GetUserRank = function(self, uid, key, events)
            events.ok(1, 13)
        end,
        GetRankTotal = function(self, key, events)
            events.ok(2)
        end,
    }
    clientCloud = fakeCloud
    GetUserNickname = function(opts)
        local list = {}
        for _, uid in ipairs(opts.userIds) do
            list[#list + 1] = { userId = uid, nickname = "行者" .. uid }
        end
        opts.onSuccess(list)
    end

    Cloud._avail = nil
    Cloud._lastAt = nil
    Cloud._lastSig = nil
    Cloud._names = {}
    Cloud._state = {}
    check("注入后 Available=true", Cloud.Available() == true)
    check("取得 userId", Cloud.UserId() == 1001)

    -- 3) 上传：四个榜单都写到对应 key
    submitted = {}
    check("MaybeSubmit 成功", Cloud.MaybeSubmit(d) == true)
    local ops = submitted[1] or {}
    local map = {}
    for _, op in ipairs(ops) do map[op.key] = op.value end
    check("上传 4 个榜单", #ops == 4, #ops)
    check("无尽层数 = 13", map.lh_endless == 13, map.lh_endless)
    check("关卡进度 = 7", map.lh_stage == 7, map.lh_stage)
    check("农场收获 = 21", map.lh_farm == 21, map.lh_farm)
    check("公会贡献 = 640", map.lh_guild == 640, map.lh_guild)

    -- 4) 同一份数据不重复上传
    Cloud._lastAt = nil   -- 跳过时间节流，只看内容签名
    submitted = {}
    check("数值没变不重复上传", Cloud.MaybeSubmit(d) == false)
    check("没有新的上传请求", #submitted == 0, #submitted)

    -- 5) 数值变化后才再次上传
    d.endlessBest = 20
    submitted = {}
    check("数值变化后重新上传", Cloud.MaybeSubmit(d) == true)
    check("上传内容已更新", submitted[1] and submitted[1][1].value == 20,
        submitted[1] and submitted[1][1].value)

    -- 6) 拉榜单
    Cloud.Refresh("endless", true)
    local st = Cloud.State("endless")
    check("榜单状态 ok", st.status == "ok", st.status)
    check("榜单 2 条", #st.list == 2, #st.list)
    check("第 1 名分数 13", st.list[1] and st.list[1].score == 13, st.list[1] and st.list[1].score)
    check("昵称已回填", st.list[1] and st.list[1].nickname == "行者1001",
        st.list[1] and st.list[1].nickname)
    check("我的排名 = 1", st.myRank == 1, st.myRank)
    check("总人数 = 2", st.total == 2, st.total)
    check("IsMe 命中自己", Cloud.IsMe(1001) == true)
    check("IsMe 不误判他人", Cloud.IsMe(1002) == false)

    -- 7) 未知榜单回退到第一个
    check("未知榜单回退", Cloud.Board("nope").id == "endless", Cloud.Board("nope").id)

    print(string.format("[Cloud] done, failures = %d", fails))
end
