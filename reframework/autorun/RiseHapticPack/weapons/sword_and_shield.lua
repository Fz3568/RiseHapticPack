-- Sword & Shield (snow.player.ShortSword). R2 = guard: light shield weight while guarding, vibrating wall on a
-- blocked hit. Shoryugeki counter rumble.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")
local Common = require("RiseHapticPack.weapons.common")

local AdaptiveTrigger = Drivers.AdaptiveTrigger
local LOW, HIGH = Patterns.LOW, Patterns.HIGH
local FREE = Patterns.TRIGGER.FREE

local SwordAndShield = { label = "Sword & Shield" }

SwordAndShield.TUNING = Common.hit_tuning({
    gain = 1.0,
    trigger_enabled = true,
    guard_trigger_force = 0.6,
    guard_raise_enabled = true,
}, 0.30, 0.08)

-- stylua: ignore
SwordAndShield.PATTERN = {
    guard_raise = { { 0.25, 0.06, LOW, 0.00 }, { 0.12, 0.04, HIGH, 0.00 } },
    shoryugeki = { { 1.00, 0.08, HIGH, 0.00 }, { 0.80, 0.16, LOW, 0.04 }, { 0.35, 0.18, LOW, 0.20 } },
}

local GUARD_TRIGGER = { 0.6, 0.0, 0.0, 1.0 }
local GUARD_IMPACT_TRIGGER = { 1.0, 0.18, 0.0, 1.0 }

local state = Patterns.new_state({ is_guarding = false })
local steps = Patterns.TriggerSteps.new()

function SwordAndShield.status()
    return "guarding " .. tostring(state.is_guarding)
end

function SwordAndShield.update(context)
    local tuning, player = SwordAndShield.TUNING, context.player
    Patterns.begin(state, context)
    local was_guarding = state.is_guarding
    local effect = Common.shield(state, context, steps, GUARD_TRIGGER, GUARD_IMPACT_TRIGGER, 0.08)
    if state.is_guarding and not was_guarding and tuning.guard_raise_enabled then
        Patterns.play(SwordAndShield.PATTERN.guard_raise, tuning.gain)
    end
    if Patterns.rose(state, "shoryugeki", Core.num(player, "_IsShouryuCounter")) then
        Patterns.play(SwordAndShield.PATTERN.shoryugeki, tuning.gain)
    end
    Common.hit(state, context, tuning)
    AdaptiveTrigger.sync(GUARD_TRIGGER, 1, tuning.guard_trigger_force)
    AdaptiveTrigger.set("R", tuning.trigger_enabled and effect or FREE)
end

return SwordAndShield
