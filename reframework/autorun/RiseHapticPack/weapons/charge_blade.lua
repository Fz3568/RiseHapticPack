-- Charge Blade (snow.player.ChargeAxe). R2 = guard: shield resistance while guarding, vibrating wall on a blocked hit
-- or guard point. Phial loads click R2, morphs click R2. Sword / shield boost and Savage Axe rumble.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")
local Common = require("RiseHapticPack.weapons.common")

local AdaptiveTrigger = Drivers.AdaptiveTrigger
local LOW, HIGH = Patterns.LOW, Patterns.HIGH
local FREE = Patterns.TRIGGER.FREE

local ChargeBlade = { label = "Charge Blade" }

ChargeBlade.TUNING = Common.hit_tuning({
    gain = 1.0,
    trigger_enabled = true,
    guard_trigger_force = 0.75,
    notch_gap = 0.045,
    notch_time = 0.07,
}, 0.38, 0.09)

-- stylua: ignore
ChargeBlade.PATTERN = {
    phial = { { 0.30, 0.05, HIGH, 0.00 }, { 0.30, 0.05, HIGH, 0.08 } },
    morph = { { 0.35, 0.06, HIGH, 0.00 }, { 0.45, 0.10, LOW, 0.05 } },
    boost = { { 0.45, 0.10, HIGH, 0.00 }, { 0.55, 0.12, LOW, 0.06 } },
    guard_point = { { 0.80, 0.08, LOW, 0.00 }, { 0.60, 0.06, HIGH, 0.00 } },
}

local GUARD_TRIGGER = { 0.75, 0.0, 0.0, 1.0 }
local GUARD_IMPACT_TRIGGER = { 1.0, 0.3, 0.0, 1.0 }
local NOTCH_TRIGGER = { 1.0, 0.0, 0.0, 1.0 }

local state = Patterns.new_state({ is_guarding = false })
local steps = Patterns.TriggerSteps.new()

function ChargeBlade.status()
    return string.format("mode %s  phials %d  guarding %s  savage %s", tostring(state.mode), state.phials or 0,
        tostring(state.is_guarding), tostring(state.savage))
end

function ChargeBlade.update(context)
    local tuning, player, now = ChargeBlade.TUNING, context.player, context.now
    Patterns.begin(state, context)
    state.mode = Common.weapon_mode(player)
    if Patterns.change(state, "mode", state.mode) ~= 0 then
        Patterns.play(ChargeBlade.PATTERN.morph, tuning.gain)
        steps:notch(now, NOTCH_TRIGGER, tuning.notch_gap, tuning.notch_time)
    end
    state.phials = Core.num(player, "<ChargedBottleNum>k__BackingField") or 0
    if Patterns.rose(state, "phials", state.phials) then
        Patterns.play(ChargeBlade.PATTERN.phial, tuning.gain)
        steps:notch(now, NOTCH_TRIGGER, tuning.notch_gap, tuning.notch_time)
    end
    -- Both edges are read every frame (no short-circuit), or one compares against a stale value.
    local sword_boost = Patterns.rose(state, "sword_boost", Core.call(player, "isSwordBuff") == true and 1 or 0)
    local shield_boost = Patterns.rose(state, "shield_boost", Core.call(player, "isShieldBuff") == true and 1 or 0)
    if sword_boost or shield_boost then
        Patterns.play(ChargeBlade.PATTERN.boost, tuning.gain)
    end
    state.savage = Core.num(player, "_IsChainsawBuff") == 1
    if Patterns.rose(state, "guard_point", Core.num(player, "_GuardCounter")) then
        Patterns.play(ChargeBlade.PATTERN.guard_point, tuning.gain)
        steps:kick(now, GUARD_IMPACT_TRIGGER, 0.1)
    end
    local effect = Common.shield(state, context, steps, GUARD_TRIGGER, GUARD_IMPACT_TRIGGER, 0.1)
    Common.hit(state, context, tuning, state.savage and 1.25 or 1.0)
    AdaptiveTrigger.sync(GUARD_TRIGGER, 1, tuning.guard_trigger_force)
    AdaptiveTrigger.set("R", tuning.trigger_enabled and effect or FREE)
end

return ChargeBlade
