-- DevFormatGuard.lua — 验证 string.format 的整型占位符兜底（设备端 i18n hook + Lua 5.4 的坑）
-- 背景：设备日志
--   [urhox-libs/Engine/i18n]:848: bad argument #3 to '_orig_string_format'
--       (number has no integer representation)
--   [string "main"]:118: in function 'Start'
-- 原因是 %d 收到带小数的浮点（逻辑分辨率 = 物理宽度 / dpr，手机 dpr 非整数比时带小数）。

local rawFormat = string.format   -- 安装兜底之前的原始实现

require "main"                    -- main.lua 顶层会安装 formatIntSafe

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Fmt] OK   " .. name)
    else
        fails = fails + 1
        print("[Fmt] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

function Start()
    -- 1. 先证明这个坑是真的：原始 string.format 收到 989.53 就抛错
    local okRaw, errRaw = pcall(rawFormat, "%d", 989.53)
    check("原始 %d 收到小数会抛错", okRaw == false, tostring(errRaw))
    check("错误信息是 no integer representation",
        not okRaw and string.find(tostring(errRaw), "integer representation") ~= nil,
        tostring(errRaw))

    -- 2. 兜底生效后不再抛错
    local ok1, r1 = pcall(string.format, "%d", 989.53)
    check("兜底后 %d 不抛错", ok1, tostring(r1))
    check("兜底后取整", r1 == "989", tostring(r1))

    -- 3. 各种正常写法不能被我改坏
    check("%d 整数不变", string.format("%d", 42) == "42", string.format("%d", 42))
    check("%d 整数值浮点不变", string.format("%d", 42.0) == "42", string.format("%d", 42.0))
    check("%.2f 小数不受影响", string.format("%.2f", 1.234) == "1.23", string.format("%.2f", 1.234))
    check("%s 不受影响", string.format("%s", "hp") == "hp")
    check("%% 转义正确", string.format("%d%%", 42.7) == "42%", string.format("%d%%", 42.7))
    check("%s 与 %d 混排", string.format("%s=%d", "hp", 5.9) == "hp=5",
        string.format("%s=%d", "hp", 5.9))
    check("带标志位 %+05d", string.format("%+05d", 7.2) == "+0007",
        string.format("%+05d", 7.2))
    check("两个 %d", string.format("%d / %d", 1.2, 3.9) == "1 / 3",
        string.format("%d / %d", 1.2, 3.9))
    check("%.1f%% 与 %d 混排", string.format("%.1f%%  +%d", 12.34, 5.6) == "12.3%  +5",
        string.format("%.1f%%  +%d", 12.34, 5.6))
    check("%5.2f|%d", string.format("%5.2f|%d", 1.239, 2.9) == " 1.24|2",
        string.format("%5.2f|%d", 1.239, 2.9))
    check("多余参数被忽略", string.format("%d", 1.1, "x") == "1")

    -- 4. 复刻设备上真正炸掉的那一行（逻辑分辨率带小数）
    local W, H, dpr, scale = 989.5294117647059, 450.7352941176471, 3.4, 1.06
    local okLine, line = pcall(string.format,
        "[main] 生命行者 v%s started, logical=%dx%d dpr=%.2f scale=%.3f",
        "0.1.0", W, H, dpr, scale)
    check("启动日志行不再抛错", okLine, tostring(line))
    check("启动日志行取整正确", line == "[main] 生命行者 v0.1.0 started, logical=989x450 dpr=3.40 scale=1.060",
        tostring(line))

    print("[Fmt] done, failures = " .. fails)
end
