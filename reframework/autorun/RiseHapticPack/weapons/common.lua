-- Pieces several weapons share: hit rumble, shield (guard on R2) trigger, morph clicks, charge hum.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")
local PlayerStatus = require("RiseHapticPack.player_status")

local Rumble = Drivers.Rumble
local ActionRumble = Patterns.ActionRumble
local LOW, HIGH = Patterns.LOW, Patterns.HIGH

local Common = {}

-- Default tuning keys for hit rumble; a weapon copies them into its TUNING.
function Common.hit_tuning(tuning, power, time)
    tuning.hit_rumble = true
    tuning.hit_power = power or 0.35
    tuning.hit_time = time or 0.09
    tuning.hit_cooldown = 0.06
    return tuning
end

-- Your attack landed: LOW body + lighter HIGH, cut if you cancel the action. scale: charge level, buff...
function Common.hit(state, context, tuning, scale)
    if not tuning.hit_rumble or not Patterns.take_hit(state, context, tuning.hit_cooldown) then
        return false
    end
    local power = tuning.hit_power * (scale or 1.0) * tuning.gain
    ActionRumble.vibrate(context, power, tuning.hit_time, LOW)
    ActionRumble.vibrate(context, power * 0.8, tuning.hit_time * 0.7, HIGH)
    return true
end

-- Shield on R2: weight while guarding, a vibrating wall for a moment when a hit is blocked.
-- Guarding = ActStatus Guard tag. Returns the effect to play, or nil when not guarding.
function Common.shield(state, context, steps, guard_effect, impact_effect, impact_time)
    if PlayerStatus.is_guard_event(context.player_event) then
        steps:kick(context.now, impact_effect, impact_time or 0.1)
    end
    local effect = steps:effect(context.now)
    if effect then
        return effect
    end
    state.is_guarding = Core.has_status(context.player, "Guard")
    if state.is_guarding then
        return guard_effect
    end
    return nil
end

-- Charge hum on the HIGH motor while a charge is held, every interval seconds.
function Common.hum(state, context, power, interval)
    if context.now >= (state.next_hum or 0) then
        state.next_hum = context.now + interval
        Rumble.vibrate(power, interval + 0.03, HIGH)
    end
end

-- snow.player.PlayerBase._weaponOwnMode (axe / sword mode of Switch Axe and Charge Blade).
function Common.weapon_mode(player)
    return Core.num(player, "_weaponOwnMode")
end

return Common
