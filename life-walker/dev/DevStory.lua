-- DevStory.lua — 剧情节点回归：触发一次 / 翻页 / 跳过 / 存档记录
local Save = require "Save"
local S = require "State"
local Story = require "Story"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Story] OK   " .. name)
    else
        fails = fails + 1
        print("[Story] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

-- 剧情节点覆盖：开场 + 几个关卡
for _, lv in ipairs({ 1, 2, 3, 4, 5, 6 }) do
    local seg = Story.Levels[lv]
    check("有第 " .. lv .. " 关剧情", seg ~= nil and seg.pages and #seg.pages > 0)
end
check("开场对白不少于 10 页", Story.Levels[1] and #Story.Levels[1].pages >= 10, Story.Levels[1] and #Story.Levels[1].pages)
check("开场有章节标题卡", Story.Levels[1].title ~= nil, Story.Levels[1].title)
check("剧情里不出现「病死」字样", (function()
    for _, seg in pairs(Story.Levels) do
        for _, pg in ipairs(seg.pages) do
            if pg.text:find("病死", 1, true) or pg.text:find("昏迷", 1, true) then return false end
        end
    end
    return true
end)())

-- 昵称替换
S.data = Save.Load()
S.data.playerName = "阿岚"
check("剧情里的 {name} 会换成昵称",
    Story.FormatText("跟我来，{name}。") == "跟我来，阿岚。",
    Story.FormatText("跟我来，{name}。"))
check("没昵称时回退成「主角」", (function()
    S.data.playerName = ""
    return Story.FormatText("{name}") == "主角"
end)())

-- 第一次进入第 1 关：应弹出
S.data = Save.Load()
S.data.storySeen = {}
local data = S.data
check("初始没有剧情弹层", Story.IsOpen() == false)
check("第 1 关触发剧情", Story.MaybeShowLevel(1, data) == true)
check("触发后处于打开状态", Story.IsOpen() == true)
check("先播章节标题卡", Story.Phase() == "title", Story.Phase())
check("未看完时存档没有记录", data.storySeen["1"] ~= true)

-- 逐页翻到结束
local guard = 0
while Story.IsOpen() and guard < 200 do
    Story.Advance()   -- 补全当前页
    Story.Advance()   -- 翻页
    guard = guard + 1
end
check("翻页能走到结束", Story.IsOpen() == false, guard)
check("看完后写入存档", data.storySeen["1"] == true)

-- 第二次进入不再弹
check("同一关不会重复触发", Story.MaybeShowLevel(1, data) == false)

-- 跳过
check("第 2 关触发", Story.MaybeShowLevel(2, data) == true)
Story.Skip()
check("跳过会关闭", Story.IsOpen() == false)
check("跳过也算看过", data.storySeen["2"] == true)

-- 没配剧情的关卡不触发
check("第 7 关没有剧情", Story.MaybeShowLevel(7, data) == false)
check("无剧情数据时安全", Story.IsOpen() == false)

print(string.format("[Story] done, failures = %d", fails))
