local S = require "State"
function Start()
    local sound = GetCache():GetResource("Sound", "audio/mage/character_feedback/B12_ui_click.wav")
    print("[Probe] sound=" .. tostring(sound ~= nil))
    if sound then
        local ok, f = pcall(function() return sound:GetFrequency() end)
        print("[Probe] GetFrequency ok=" .. tostring(ok) .. " freq=" .. tostring(f)
            .. " length=" .. tostring(sound.length))
        local ok2, fi = pcall(function() return sound.intFrequency end)
        print("[Probe] intFrequency ok=" .. tostring(ok2) .. " v=" .. tostring(fi))
    end
    local ogg = GetCache():GetResource("Sound", "audio/mage/music/M03_combat.ogg")
    if ogg then
        local ok, f = pcall(function() return ogg:GetFrequency() end)
        print("[Probe] ogg freq=" .. tostring(f) .. " length=" .. tostring(ogg.length))
    end
end
