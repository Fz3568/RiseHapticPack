-- Insect Glaive (snow.player.InsectGlaive). R2 is the Kinsect button: it stays free, with one R2 click on Triple Up.
-- Each extract gained taps the grips.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")
local Common = require("RiseHapticPack.weapons.common")

local AdaptiveTrigger = Drivers.AdaptiveTrigger
local LOW, HIGH = Patterns.LOW, Patterns.HIGH
local FREE = Patterns.TRIGGER.FREE

local InsectGlaive = { label = "Insect Glaive" }

InsectGlaive.TUNING = Common.hit_tuning({
    gain = 1.0,
    trigger_enabled = true,
    notch_force = 1.0,
}, 0.25, 0.07)

-- stylua: ignore
InsectGlaive.PATTERN = {
    extract = { { 0.30, 0.06, HIGH, 0.00 } },
    triple_up = { { 0.40, 0.08, HIGH, 0.00 }, { 0.50, 0.08, HIGH, 0.10 }, { 0.60, 0.14, LOW, 0.20 } },
}

local NOTCH_TRIGGER = { 1.0, 0.0, 0.0, 1.0 }

local state = Patterns.new_state({})
local steps = Patterns.TriggerSteps.new()

function InsectGlaive.status()
    return string.format("extracts %d  triple up %s", state.extracts or 0, tostring(state.triple))
end

function InsectGlaive.update(context)
    local tuning, player, now = InsectGlaive.TUNING, context.player, context.now
    Patterns.begin(state, context)
    local extracts = 0
    for _, name in ipairs({ "_RedExtractiveTime", "_WhiteExtractiveTime", "_OrangeExtractiveTime" }) do
        if (Core.num(player, name) or 0) > 0 then
            extracts = extracts + 1
        end
    end
    state.extracts = extracts
    state.triple = Core.call(player, "isGetAllExtractive") == true
    local extract_rose = Patterns.rose(state, "extracts", extracts)
    if Patterns.rose(state, "triple", state.triple and 1 or 0) then
        Patterns.play(InsectGlaive.PATTERN.triple_up, tuning.gain)
        steps:notch(now, NOTCH_TRIGGER)
    elseif extract_rose then
        Patterns.play(InsectGlaive.PATTERN.extract, tuning.gain)
    end
    Common.hit(state, context, tuning, state.triple and 1.2 or 1.0)
    AdaptiveTrigger.sync(NOTCH_TRIGGER, 1, tuning.notch_force)
    AdaptiveTrigger.set("R", tuning.trigger_enabled and steps:effect(now) or FREE)
end

return InsectGlaive
