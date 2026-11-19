-- Great Sword (snow.player.GreatSword). Charge is on a face button; R2 = guard: light resistance in the first 20% of
-- the R2 pull while drawn, a vibrating wall when a hit is blocked. Charge levels (_TameLv) and the release rumble.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")
local Common = require("RiseHapticPack.weapons.common")

local AdaptiveTrigger = Drivers.AdaptiveTrigger
local ActionRumble = Patterns.ActionRumble
local LOW, HIGH = Patterns.LOW, Patterns.HIGH
local FREE = Patterns.TRIGGER.FREE

local GreatSword = { label = "Great Sword" }

GreatSword.TUNING = Common.hit_tuning({
    gain = 1.0,
    trigger_enabled = true,
    guard_trigger_force = 0.8,
    charge_timeout = 0.12,
    charge_hum = 0.06,
    charge_hum_per_level = 0.05,
    charge_hum_interval = 0.08,
    release_per_level = 0.25,
    charged_hit_window = 1.2,
    charged_hit_per_level = 0.5,
}, 0.40, 0.09)

-- stylua: ignore
GreatSword.PATTERN = {
    level_up = { { 0.45, 0.06, HIGH, 0.00 }, { 0.20, 0.06, LOW, 0.00 } },
    level_max = { { 0.55, 0.06, HIGH, 0.00 }, { 0.30, 0.06, LOW, 0.00 }, { 0.70, 0.08, HIGH, 0.10 }, { 0.45, 0.10, LOW, 0.10 } },
    release = { { 0.15, 0.08, LOW, 0.00 }, { 0.30, 0.10, LOW, 0.06 }, { 0.20, 0.08, HIGH, 0.06 } },
    max_charge_hit = { { 1.00, 0.20, LOW, 0.00 }, { 0.90, 0.12, HIGH, 0.00 }, { 0.50, 0.20, LOW, 0.20 } },
}

local GUARD_TRIGGER = { 0.8, 0.0, 0.0, 0.2 }
local GUARD_IMPACT_TRIGGER = { 1.0, 0.25, 0.0, 1.0 }

local state = Patterns.new_state({ is_charging = false, peak = 0, charged_level = 0, charged_until = 0.0 })
local steps = Patterns.TriggerSteps.new()

function GreatSword.status()
    return string.format("charge lv %d  charging %s  peak %d", state.level or 0, tostring(state.is_charging), state.peak)
end

function GreatSword.update(context)
    local tuning, player, now = GreatSword.TUNING, context.player, context.now
    if Patterns.begin(state, context) then
        state.is_charging, state.peak, state.charged_level = false, 0, 0
    end
    local level = math.min(Core.num(player, "_TameLv") or 0, 3)
    state.level = level
    local is_charging = Patterns.timer_rising(state, "tame_timer", Core.num(player, "_tameTimer"), now, tuning.charge_timeout)
    local level_change = Patterns.change(state, "level", level)

    if state.is_charging and not is_charging then
        if state.peak >= 1 then
            state.charged_level, state.charged_until = state.peak, now + tuning.charged_hit_window
            ActionRumble.play(context, GreatSword.PATTERN.release, tuning.gain * (1.0 + tuning.release_per_level * (state.peak - 1)))
        end
        state.peak = 0
    end
    state.is_charging = is_charging
    if is_charging then
        if level_change > 0 and level > state.peak then
            state.peak = level
            Patterns.play(level >= 3 and GreatSword.PATTERN.level_max or GreatSword.PATTERN.level_up, tuning.gain)
        end
        Common.hum(state, context, (tuning.charge_hum + tuning.charge_hum_per_level * level) * tuning.gain, tuning.charge_hum_interval)
    end

    local charged = now < state.charged_until and state.charged_level or 0
    if charged >= 3 and tuning.hit_rumble and Patterns.take_hit(state, context, tuning.hit_cooldown) then
        ActionRumble.play(context, GreatSword.PATTERN.max_charge_hit, tuning.gain)
    else
        Common.hit(state, context, tuning, 1.0 + tuning.charged_hit_per_level * charged)
    end

    local effect = FREE
    if tuning.trigger_enabled then
        effect = Common.shield(state, context, steps, nil, GUARD_IMPACT_TRIGGER, 0.08)
            or (Patterns.drawn(state, context) and GUARD_TRIGGER or FREE)
    end
    AdaptiveTrigger.sync(GUARD_TRIGGER, 1, tuning.guard_trigger_force)
    AdaptiveTrigger.set("R", effect)
end

return GreatSword
