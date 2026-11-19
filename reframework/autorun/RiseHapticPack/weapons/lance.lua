-- Lance (snow.player.Lance). R2 = guard: the biggest shield, a firm wall while guarding and a vibrating wall on a
-- blocked hit (counters and power guard included). Charge footsteps and charge power-up rumble.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")
local Common = require("RiseHapticPack.weapons.common")

local AdaptiveTrigger = Drivers.AdaptiveTrigger
local LOW, HIGH = Patterns.LOW, Patterns.HIGH
local FREE = Patterns.TRIGGER.FREE

local Lance = { label = "Lance" }

Lance.TUNING = Common.hit_tuning({
    gain = 1.0,
    trigger_enabled = true,
    guard_trigger_force = 0.9,
    charge_timeout = 0.15,
    charge_step = 0.12,
    charge_step_interval = 0.30,
}, 0.30, 0.08)

-- stylua: ignore
Lance.PATTERN = {
    charge_power_up = { { 0.45, 0.08, HIGH, 0.00 }, { 0.40, 0.10, LOW, 0.04 } },
}

local GUARD_TRIGGER = { 0.9, 0.0, 0.0, 1.0 }
local GUARD_IMPACT_TRIGGER = { 1.0, 0.3, 0.0, 1.0 }

local state = Patterns.new_state({ is_guarding = false })
local steps = Patterns.TriggerSteps.new()

function Lance.status()
    return string.format("guarding %s  charging %s", tostring(state.is_guarding), tostring(state.is_charging))
end

function Lance.update(context)
    local tuning, player, now = Lance.TUNING, context.player, context.now
    Patterns.begin(state, context)
    local effect = Common.shield(state, context, steps, GUARD_TRIGGER, GUARD_IMPACT_TRIGGER, 0.1)
    state.is_charging = Patterns.timer_rising(state, "charge_time", Core.num(player, "_ChargeTime"), now, tuning.charge_timeout)
    if state.is_charging and now >= (state.next_step or 0) then
        state.next_step = now + tuning.charge_step_interval
        Drivers.Rumble.vibrate(tuning.charge_step * tuning.gain, 0.07, LOW)
    end
    if Patterns.rose(state, "power_up", Core.num(player, "_IsChargePowerUp")) then
        Patterns.play(Lance.PATTERN.charge_power_up, tuning.gain)
    end
    Common.hit(state, context, tuning)
    AdaptiveTrigger.sync(GUARD_TRIGGER, 1, tuning.guard_trigger_force)
    AdaptiveTrigger.set("R", tuning.trigger_enabled and effect or FREE)
end

return Lance
