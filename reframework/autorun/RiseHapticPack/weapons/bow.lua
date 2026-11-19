-- Bow (snow.player.Bow). R2 draws and fires: draw weight on R2 while the bow charges, a pulse on each charge level,
-- a short kick when the arrow leaves.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")
local Common = require("RiseHapticPack.weapons.common")

local AdaptiveTrigger = Drivers.AdaptiveTrigger
local ActionRumble = Patterns.ActionRumble
local LOW, HIGH = Patterns.LOW, Patterns.HIGH
local FREE = Patterns.TRIGGER.FREE

local Bow = { label = "Bow" }

Bow.TUNING = Common.hit_tuning({
    gain = 1.0,
    trigger_enabled = true,
    draw_trigger_force = 1.0,
    level_pulse_time = 0.055,
    release_kick_time = 0.05,
    charge_timeout = 0.12,
    draw_hum = 0.05,
    draw_hum_interval = 0.1,
}, 0.20, 0.06)

-- stylua: ignore
Bow.PATTERN = {
    level_up = { { 0.40, 0.06, HIGH, 0.00 }, { 0.20, 0.06, LOW, 0.00 } },
    release = { { 0.35, 0.06, HIGH, 0.00 }, { 0.20, 0.08, LOW, 0.02 } },
}

local DRAW_TRIGGER = { 1.0, 0.0, 0.0, 1.0 }
local LEVEL_PULSE_TRIGGER = { 1.0, 0.1, 0.0, 1.0 }
local RELEASE_TRIGGER = { 1.0, 0.25, 0.0, 1.0 }

local state = Patterns.new_state({ is_drawing = false, pulse_until = 0.0 })
local steps = Patterns.TriggerSteps.new()

function Bow.status()
    return string.format("charge lv %d  drawing %s", state.level or 0, tostring(state.is_drawing))
end

function Bow.update(context)
    local tuning, player, now = Bow.TUNING, context.player, context.now
    if Patterns.begin(state, context) then
        state.is_drawing = false
    end
    local level = Core.num(player, "<ChargeLv>k__BackingField") or 0
    state.level = level
    local is_drawing = Patterns.timer_rising(state, "charge_timer", Core.num(player, "_ChargeTimer"), now, tuning.charge_timeout)
    if Patterns.rose(state, "level", level) and is_drawing then
        Patterns.play(Bow.PATTERN.level_up, tuning.gain)
        state.pulse_until = now + tuning.level_pulse_time
    end
    if state.is_drawing and not is_drawing then
        ActionRumble.play(context, Bow.PATTERN.release, tuning.gain * (1.0 + 0.15 * level))
        steps:kick(now, RELEASE_TRIGGER, tuning.release_kick_time)
    end
    state.is_drawing = is_drawing
    if is_drawing then
        Common.hum(state, context, tuning.draw_hum * (1 + level * 0.3) * tuning.gain, tuning.draw_hum_interval)
    end
    Common.hit(state, context, tuning)

    local effect = FREE
    if tuning.trigger_enabled then
        effect = steps:effect(now) or (now < state.pulse_until and LEVEL_PULSE_TRIGGER)
            or (is_drawing and DRAW_TRIGGER) or FREE
    end
    AdaptiveTrigger.sync(DRAW_TRIGGER, 1, tuning.draw_trigger_force)
    AdaptiveTrigger.set("R", effect)
end

return Bow
