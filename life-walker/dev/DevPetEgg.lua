-- DevPetEgg.lua — 孵化队列排序回归
local Save = require "Save"
local S = require "State"
local Pet = require "Pet"

local fails = 0
local function check(name, cond, detail)
    if cond then
        print("[Egg] OK   " .. name)
    else
        fails = fails + 1
        print("[Egg] FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    end
end

S.data = Save.Load()
local p = Pet.Ensure(S.data)
p.eggs = {
    { id = "a", state = "waiting" },
    { id = "b", state = "hatching", endAt = os.time() + 3600 },
    { id = "c", state = "waiting" },
    { id = "d", state = "waiting" },
}

check("初始顺序 a,h,c,d", p.eggs[1].id == "a" and p.eggs[3].id == "c" and p.eggs[4].id == "d")

-- 把第 4 个（d）往上提前
check("d 能上移", Pet.MoveEgg(S.data, 4, -1) == true)
check("上移后顺序 a,h,d,c", p.eggs[1].id == "a" and p.eggs[3].id == "d" and p.eggs[4].id == "c")

-- 再往上：应跳过正在孵化的 b
check("能跨过正在孵化的蛋继续上移", Pet.MoveEgg(S.data, 3, -1) == true)
check("跨过后顺序 d,h,a,c", p.eggs[1].id == "d" and p.eggs[3].id == "a" and p.eggs[4].id == "c")

-- 已经在最前，再上移无效
check("第一位不能再上移", Pet.MoveEgg(S.data, 1, -1) == false)

-- 正在孵化的蛋不能被移动
check("孵化中的蛋不能移动", Pet.MoveEgg(S.data, 2, 1) == false)

-- AutoIncubate 按数组顺序拿 waiting
p.slots = 1
p.eggs = { { id = "x", state = "waiting" }, { id = "y", state = "waiting" } }
Pet.AutoIncubate(S.data)
check("空槽优先孵排在最前的蛋", p.eggs[1].state == "hatching" and p.eggs[2].state == "waiting",
    p.eggs[1].state .. "/" .. p.eggs[2].state)

print(string.format("[Egg] done, failures = %d", fails))
