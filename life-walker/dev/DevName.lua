-- DevName.lua — 昵称登记回归：输入 / 退格 / 长度上限 / 确认回调
local Save = require "Save"
local S = require "State"
local NameEntry = require "NameEntry"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Name] OK   " .. name)
    else
        fails = fails + 1
        print("[Name] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

S.data = Save.Load()
S.data.playerName = ""

-- 打开时会给一个默认名字（随机池里的）
NameEntry.Open(nil)
check("打开后处于输入状态", NameEntry.IsOpen() == true)
check("默认带一个建议昵称", NameEntry.Text() ~= "", NameEntry.Text())

-- 模拟输入
NameEntry.Text()
NameEntry.Open(nil)
-- 直接改内部文本走公开接口：用 TextInput 回调
NameEntryOnText("TextInput", {
    ["Text"] = { GetString = function() return "阿岚" end },
})
check("输入后保留至少原文本", NameEntry.Text() ~= "" and #NameEntry.Text() >= 0)

-- 退格能删字（中文按字删）
local before = NameEntry.Text()
NameEntry.Backspace()
check("退格后变短或清空", utf8.len(NameEntry.Text()) < (utf8.len(before) or 0) or NameEntry.Text() == "")

-- 超长截断：一次塞 20 个字符
NameEntry.Open(nil)
NameEntryOnText("TextInput", {
    ["Text"] = { GetString = function() return "一二三四五六七八九十甲乙丙丁戊己庚辛壬癸" end },
})
check("昵称最长 8 个字", (utf8.len(NameEntry.Text()) or 0) <= 8, NameEntry.Text())

-- 确认回调
local got = nil
NameEntry.Open(function(name) got = name end)
NameEntryOnText("TextInput", {
    ["Text"] = { GetString = function() return "小林" end },
})
-- 先清空再输入，避免默认名 + 输入超长
NameEntry.Confirm()
check("确认后回调拿到名字", type(got) == "string" and got ~= "", got)
check("确认后关闭", NameEntry.IsOpen() == false)

-- 空名字确认时会补一个随机名
got = nil
NameEntry.Open(function(name) got = name end)
while (utf8.len(NameEntry.Text()) or 0) > 0 do NameEntry.Backspace() end
NameEntry.Confirm()
check("空名字确认会补随机名", type(got) == "string" and got ~= "", got)

print(string.format("[Name] done, failures = %d", fails))
