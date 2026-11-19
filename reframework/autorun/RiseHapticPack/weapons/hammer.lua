-- Hammer (snow.player.Hammer). R2 = charge: R2 holds a wall while charging, goes loose for a moment on each charge
-- level (a latch click). Charge hum, level and release rumble, heavy hits.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")
local Common = require("RiseHapticPack.weapons.common")

local AdaptiveTrigger = Drivers.AdaptiveTrigger
local ActionRumble = Patterns.ActionRumble
local LOW, HIGH = Patterns.LOW, Patterns.HIGH
local FREE = Patterns.TRIGGER.FREE

local Hammer = { label = "Hammer" }

Hammer.TUNING = Common.hit_tuning({
    gain = 1.0,
    trigger_enabled = true,
    charge_trigger_force = 1.0,
    level_notch_gap = 0.045,
    charge_timeout = 0.12,
    charge_hum = 0.07,
    charge_hum_per_level = 0.05,
    charge_hum_interval = 0.08,
}, 0.50, 0.11)

-- stylua: ignore
Hammer.PATTERN = {
    level_up = { { 0.50, 0.07, HIGH, 0.00 }, { 0.30, 0.07, LOW, 0.00 } },
    level_max = { { 0.60, 0.07, HIGH, 0.00 }, { 0.40, 0.08, LOW, 0.00 }, { 0.80, 0.10, HIGH, 0.12 }, { 0.55, 0.12, LOW, 0.12 } },
    charge_type = { { 0.35, 0.06, HIGH, 0.00 }, { 0.35, 0.06, HIGH, 0.10 } },
    release = { { 0.20, 0.08, LOW, 0.00 }, { 0.40, 0.10, LOW, 0.06 } },
}

local CHARGE_TRIGGER = { 1.0, 0.0, 0.0, 1.0 }

local state = Patterns.new_state({ is_charging = false, notch_start = -10.0, peak = 0 })

function Hammer.status()
    return string.format("charge lv %d  type %s  charging %s", state.level or 0, tostring(state.charge_type),
        tostring(state.is_charging))
end

function Hammer.update(context)
    local tuning, player, now = Hammer.TUNING, context.player, context.now
    if Patterns.begin(state, context) then
        state.is_charging, state.peak = false, 0
    end
    local level = Core.num(player, "<NowChargeLevel>k__BackingField") or 0
    state.level = level
    state.charge_type = Core.num(player, "<NowChargeType>k__BackingField")
    local is_charging = Patterns.timer_rising(state, "charge_timer", Core.num(player, "_ChargeTimer"), now, tuning.charge_timeout)
    local level_change = Patterns.change(state, "level", level)

    if state.is_charging and not is_charging then
        if state.peak >= 1 then
            ActionRumble.play(context, Hammer.PATTERN.release, tuning.gain * (1.0 + 0.25 * state.peak))
        end
        state.peak = 0
    end
    state.is_charging = is_charging
    if is_charging then
        if level_change > 0 then
            state.peak = math.max(state.peak, level)
            state.notch_start = now
            Patterns.play(level >= 3 and Hammer.PATTERN.level_max or Hammer.PATTERN.level_up, tuning.gain)
        end
        Common.hum(state, context, (tuning.charge_hum + tuning.charge_hum_per_level * level) * tuning.gain, tuning.charge_hum_interval)
    end
    if Patterns.change(state, "charge_type", state.charge_type) ~= 0 then
        Patterns.play(Hammer.PATTERN.charge_type, tuning.gain)
    end
    Common.hit(state, context, tuning, 1.0 + 0.2 * level)

    local effect = FREE
    if tuning.trigger_enabled and is_charging and now - state.notch_start >= tuning.level_notch_gap then
        effect = CHARGE_TRIGGER
    end
    AdaptiveTrigger.sync(CHARGE_TRIGGER, 1, tuning.charge_trigger_force)
    AdaptiveTrigger.set("R", effect)
end

return Hammer
