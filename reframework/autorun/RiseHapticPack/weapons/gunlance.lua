-- Gunlance (snow.player.GunLance). R2 = guard: shield wall while guarding, vibrating wall on a blocked hit.
-- Charged shelling levels click R2; Wyvern's Fire aim builds a rumble; shells and stabs rumble on hit.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")
local Common = require("RiseHapticPack.weapons.common")

local AdaptiveTrigger = Drivers.AdaptiveTrigger
local LOW, HIGH = Patterns.LOW, Patterns.HIGH
local FREE = Patterns.TRIGGER.FREE

local Gunlance = { label = "Gunlance" }

Gunlance.TUNING = Common.hit_tuning({
    gain = 1.0,
    trigger_enabled = true,
    guard_trigger_force = 0.85,
}, 0.40, 0.10)

-- stylua: ignore
Gunlance.PATTERN = {
    charge_level = { { 0.40, 0.06, HIGH, 0.00 }, { 0.25, 0.06, LOW, 0.00 } },
    wyverns_fire = {
        { 0.10, 0.30, HIGH, 0.00 }, { 0.20, 0.30, HIGH, 0.30 }, { 0.30, 0.30, HIGH, 0.60 }, { 0.45, 0.30, LOW, 0.90 },
        { 0.60, 0.30, LOW, 1.20 },
    },
}

local GUARD_TRIGGER = { 0.85, 0.0, 0.0, 1.0 }
local GUARD_IMPACT_TRIGGER = { 1.0, 0.3, 0.0, 1.0 }
local CLICK_TRIGGER = { 0.8, 0.0, 0.2, 0.5 }

local state = Patterns.new_state({ is_guarding = false })
local steps = Patterns.TriggerSteps.new()

function Gunlance.status()
    return string.format("guarding %s  shot charge %d", tostring(state.is_guarding), state.shot_charge or 0)
end

function Gunlance.update(context)
    local tuning, player, now = Gunlance.TUNING, context.player, context.now
    Patterns.begin(state, context)
    state.shot_charge = Core.num(player, "<ShotChargeLv>k__BackingField") or 0
    if Patterns.rose(state, "shot_charge", state.shot_charge) then
        Patterns.play(Gunlance.PATTERN.charge_level, tuning.gain)
        steps:kick(now, CLICK_TRIGGER, 0.07)
    end
    if Patterns.rose(state, "wyverns_fire", Core.num(player, "<_IsAimDragonSlayCannon>k__BackingField")) then
        Patterns.play(Gunlance.PATTERN.wyverns_fire, tuning.gain)
    end
    local effect = Common.shield(state, context, steps, GUARD_TRIGGER, GUARD_IMPACT_TRIGGER, 0.1)
    Common.hit(state, context, tuning)
    AdaptiveTrigger.sync(GUARD_TRIGGER, 1, tuning.guard_trigger_force)
    AdaptiveTrigger.set("R", tuning.trigger_enabled and effect or FREE)
end

return Gunlance
