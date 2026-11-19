-- Switch Axe (snow.player.SlashAxe). R2 = morph: an R2 click on every morph. Amped state and Zero Sum / element
-- discharge rumble.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")
local Common = require("RiseHapticPack.weapons.common")

local AdaptiveTrigger = Drivers.AdaptiveTrigger
local Rumble = Drivers.Rumble
local LOW, HIGH = Patterns.LOW, Patterns.HIGH
local FREE = Patterns.TRIGGER.FREE

local SwitchAxe = { label = "Switch Axe" }

SwitchAxe.TUNING = Common.hit_tuning({
    gain = 1.0,
    trigger_enabled = true,
    notch_force = 1.0,
    notch_gap = 0.045,
    notch_time = 0.07,
    discharge_power = 0.35,
    discharge_interval = 0.12,
}, 0.40, 0.10)

-- stylua: ignore
SwitchAxe.PATTERN = {
    morph = { { 0.35, 0.06, HIGH, 0.00 }, { 0.45, 0.10, LOW, 0.05 } },
    amped = { { 0.50, 0.10, HIGH, 0.00 }, { 0.60, 0.14, LOW, 0.06 }, { 0.30, 0.16, LOW, 0.20 } },
    discharge_start = { { 0.70, 0.10, LOW, 0.00 }, { 0.50, 0.10, HIGH, 0.00 } },
}

local NOTCH_TRIGGER = { 1.0, 0.0, 0.0, 1.0 }

local state = Patterns.new_state({})
local steps = Patterns.TriggerSteps.new()

function SwitchAxe.status()
    return string.format("mode %s  amped %s  gauge %s", tostring(state.mode), tostring(state.amped),
        tostring(state.gauge))
end

function SwitchAxe.update(context)
    local tuning, player, now = SwitchAxe.TUNING, context.player, context.now
    Patterns.begin(state, context)
    state.mode = Common.weapon_mode(player)
    if Patterns.change(state, "mode", state.mode) ~= 0 then
        Patterns.play(SwitchAxe.PATTERN.morph, tuning.gain)
        steps:notch(now, NOTCH_TRIGGER, tuning.notch_gap, tuning.notch_time)
    end
    state.amped = Core.call(player, "isBottleAwake") == true
    state.gauge = Core.num(player, "_BottleGauge")
    if Patterns.rose(state, "amped", state.amped and 1 or 0) then
        Patterns.play(SwitchAxe.PATTERN.amped, tuning.gain)
    end
    local stab = Core.num(player, "<IsHitElementStab>k__BackingField") or 0
    if Patterns.rose(state, "stab", stab) then
        Patterns.play(SwitchAxe.PATTERN.discharge_start, tuning.gain)
    end
    if stab > 0 and now >= (state.next_buzz or 0) then
        state.next_buzz = now + tuning.discharge_interval
        Rumble.vibrate(tuning.discharge_power * tuning.gain, 0.06, HIGH)
        Rumble.vibrate(tuning.discharge_power * 0.7 * tuning.gain, 0.06, LOW)
    end
    Common.hit(state, context, tuning, state.amped and 1.2 or 1.0)
    AdaptiveTrigger.sync(NOTCH_TRIGGER, 1, tuning.notch_force)
    AdaptiveTrigger.set("R", tuning.trigger_enabled and steps:effect(now) or FREE)
end

return SwitchAxe
