-- Dual Blades (snow.player.DualBlades). R2 = Demon Mode: an R2 "switch" click on every toggle, free otherwise.
-- Demon / Archdemon mode rumble.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")
local Common = require("RiseHapticPack.weapons.common")

local AdaptiveTrigger = Drivers.AdaptiveTrigger
local LOW, HIGH = Patterns.LOW, Patterns.HIGH
local FREE = Patterns.TRIGGER.FREE

local DualBlades = { label = "Dual Blades" }

DualBlades.TUNING = Common.hit_tuning({
    gain = 1.0,
    trigger_enabled = true,
    notch_force = 1.0,
    notch_gap = 0.045,
    notch_time = 0.07,
}, 0.22, 0.06)
DualBlades.TUNING.hit_cooldown = 0.08

-- stylua: ignore
DualBlades.PATTERN = {
    demon_enter = { { 0.40, 0.08, HIGH, 0.00 }, { 0.30, 0.10, LOW, 0.04 } },
    demon_exit = { { 0.25, 0.08, LOW, 0.00 } },
    archdemon = { { 0.50, 0.08, HIGH, 0.00 }, { 0.60, 0.12, LOW, 0.06 }, { 0.30, 0.12, LOW, 0.18 } },
}

local NOTCH_TRIGGER = { 1.0, 0.0, 0.0, 1.0 }

local state = Patterns.new_state({})
local steps = Patterns.TriggerSteps.new()

function DualBlades.status()
    return string.format("demon %s  archdemon %s", tostring(state.demon), tostring(state.archdemon))
end

function DualBlades.update(context)
    local tuning, player, now = DualBlades.TUNING, context.player, context.now
    Patterns.begin(state, context)
    state.demon = Core.call(player, "isKijin") == true
    state.archdemon = Core.call(player, "isKijinKyouka") == true
    local demon_change = Patterns.change(state, "demon", state.demon and 1 or 0)
    if demon_change ~= 0 then
        Patterns.play(demon_change > 0 and DualBlades.PATTERN.demon_enter or DualBlades.PATTERN.demon_exit, tuning.gain)
        steps:notch(now, NOTCH_TRIGGER, tuning.notch_gap, tuning.notch_time)
    end
    if Patterns.rose(state, "archdemon", state.archdemon and 1 or 0) then
        Patterns.play(DualBlades.PATTERN.archdemon, tuning.gain)
    end
    Common.hit(state, context, tuning, state.demon and 1.2 or 1.0)
    AdaptiveTrigger.sync(NOTCH_TRIGGER, 1, tuning.notch_force)
    AdaptiveTrigger.set("R", tuning.trigger_enabled and steps:effect(now) or FREE)
end

return DualBlades
