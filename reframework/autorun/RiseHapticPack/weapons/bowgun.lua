-- Light and Heavy Bowgun (snow.player.LightBowgun / HeavyBowgun). While aiming, R2 has a trigger "break" click; each
-- R2 press while aiming kicks R2 and the grips (heavy = stronger). Heavy: Wyvernheart / machine-gun fire vibrates R2,
-- charge levels click. Light: rapid fire and full auto vibrate lighter.
-- UNVERIFIED in game: shots are read from R2 presses while aiming (Rise has no single "shot fired" hook found yet).
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")
local Common = require("RiseHapticPack.weapons.common")

local AdaptiveTrigger = Drivers.AdaptiveTrigger
local Rumble = Drivers.Rumble
local LOW, HIGH = Patterns.LOW, Patterns.HIGH
local FREE = Patterns.TRIGGER.FREE

local function aiming(player)
    local value = Core.field(player, "<IsAimModeAction>k__BackingField")
    if value == nil then
        value = Core.field(player, "<IsActionAimMode>k__BackingField")
    end
    return value == true
end

local function new_bowgun(is_heavy)
    local Bowgun = { label = is_heavy and "Heavy Bowgun" or "Light Bowgun" }
    Bowgun.TUNING = Common.hit_tuning({
        gain = 1.0,
        trigger_enabled = true,
        ready_click_force = is_heavy and 0.65 or 0.5,
        kick_vibration = is_heavy and 0.32 or 0.22,
        kick_time = is_heavy and 0.08 or 0.05,
        recoil_power = is_heavy and 0.45 or 0.28,
    }, 0.15, 0.05)
    Bowgun.TUNING.hit_rumble = false -- shots already kick; ammo hits stay quiet by default

    -- stylua: ignore
    Bowgun.PATTERN = {
        recoil = { { 1.0, 0.06, HIGH, 0.00 }, { 0.8, 0.09, LOW, 0.02 } },
        charge_level = { { 0.40, 0.06, HIGH, 0.00 } },
    }

    local READY_TRIGGER = { Bowgun.TUNING.ready_click_force, 0.0, 0.30, 0.55 }
    local KICK_TRIGGER = { 1.0, Bowgun.TUNING.kick_vibration, 0.0, 1.0 }
    local AUTO_TRIGGER = { 0.7, 0.18, 0.0, 1.0 }
    local CLICK_TRIGGER = { 0.8, 0.0, 0.2, 0.5 }

    local state = Patterns.new_state({ is_aiming = false })
    local steps = Patterns.TriggerSteps.new()

    function Bowgun.status()
        return string.format("aiming %s  auto %s", tostring(state.is_aiming), tostring(state.is_auto))
    end

    function Bowgun.update(context)
        local tuning, player, now = Bowgun.TUNING, context.player, context.now
        Patterns.begin(state, context)
        local drawn = Patterns.drawn(state, context)
        state.is_aiming = drawn and aiming(player)
        local pressed = Patterns.r2_pressed(state, context, 0.55)
        if pressed and state.is_aiming then
            Patterns.play(Bowgun.PATTERN.recoil, tuning.recoil_power * tuning.gain)
            steps:kick(now, KICK_TRIGGER, tuning.kick_time)
        end
        if is_heavy then
            -- Wyvernheart / machine gun: the fire count keeps rising while it spins.
            state.is_auto = Patterns.timer_rising(state, "machine_gun", Core.num(player, "_MachineGunFireCount"), now, 0.25)
            if Patterns.rose(state, "charge_level", Core.num(player, "_ShotChargeLv")) then
                Patterns.play(Bowgun.PATTERN.charge_level, tuning.gain)
                steps:kick(now, CLICK_TRIGGER, 0.07)
            end
        else
            state.is_auto = Core.num(player, "<IsFullAutoShooting>k__BackingField") == 1
            if Patterns.rose(state, "rapid", Core.num(player, "_RapidCount")) then
                Rumble.vibrate(tuning.recoil_power * 0.6 * tuning.gain, 0.05, HIGH)
            end
        end
        if state.is_auto and now >= (state.next_auto or 0) then
            state.next_auto = now + 0.08
            Rumble.vibrate(tuning.recoil_power * 0.7 * tuning.gain, 0.08, HIGH)
            Rumble.vibrate(tuning.recoil_power * 0.5 * tuning.gain, 0.08, LOW)
        end
        Common.hit(state, context, tuning)

        local effect = FREE
        if tuning.trigger_enabled then
            effect = steps:effect(now) or (state.is_auto and AUTO_TRIGGER) or (state.is_aiming and READY_TRIGGER) or FREE
        end
        AdaptiveTrigger.sync(READY_TRIGGER, 1, tuning.ready_click_force)
        AdaptiveTrigger.sync(KICK_TRIGGER, 2, tuning.kick_vibration)
        AdaptiveTrigger.set("R", effect)
    end

    return Bowgun
end

return { light = new_bowgun(false), heavy = new_bowgun(true) }
