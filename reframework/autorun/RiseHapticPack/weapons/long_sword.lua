-- Long Sword (snow.player.LongSword).
-- Moves are recognised by the motion FSM node the hunter is in (names from the game's own motion graph):
--   Special Sheathe: the sheathing animation leaves R2 free; the stance holds a smooth resistance (after a tiny delay).
--   Iai Slash: R2 free. Iai Spirit Slash: light vibrating tension; a successful counter clashes, locks and fades, and
--   every hit for a few seconds after it (the delayed follow-up slashes included) is a counter hit.
--   Spirit Blade I..III and Spirit Roundslash: R2 impact, drag and fade, stronger along the combo.
--   Spirit Breaker combo (switch skill): its final hit always; its 3rd hit only when chained from an Iai counter.
--   Spirit Gauge level up: R2 pulse + rumble.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")

local AdaptiveTrigger = Drivers.AdaptiveTrigger
local ActionRumble = Patterns.ActionRumble
local LOW, HIGH, RT = Patterns.LOW, Patterns.HIGH, Patterns.RT
local FREE = Patterns.TRIGGER.FREE

local LongSword = { label = "Long Sword" }

LongSword.TUNING = {
    gain = 1.0,
    trigger_enabled = true,
    spirit_blade_combo_trigger = true, -- false: Spirit Blade I..III keep their rumble but R2 stays free
    spirit_roundslash_trigger = true, -- Spirit Roundslash R2 effect, separate from the combo toggle above
    spirit_breaker_final_trigger = true, -- Spirit Breaker combo: R2 effect on the final hit
    spirit_breaker_iai_third_trigger = true, -- Spirit Breaker 3rd hit, only when chained from a successful Iai Spirit Slash
    iai_trigger_force = 1.0,
    iai_stance_delay = 0.06, -- seconds into the stance before the resistance starts (not on the transition itself)
    level_pulse_time = 0.055,
    level_pulse_cooldown = 0.5,
    slash_impact_time = 0.06,
    slash_drag_enabled = true,
    slash_drag_force = 0.30,
    slash_drag_time = 0.16,
    slash_fade_time = 0.10,
    swoosh_enabled = true,
    swoosh_per_combo = 0.25,
    swoosh_per_level = 0.20,
    hit_rumble = true,
    hit_power = 0.30,
    hit_power_per_level = 0.10,
    hit_time = 0.08,
    hit_cooldown = 0.06,
    counter_window = 3.0, -- seconds after a successful Iai counter in which hits count as counter hits
    counter_hit_gain = 1.0,
    counter_hit_trigger = true,
    iai_slash_trigger = true,
    iai_draw_slack_time = 0.0, -- > 0: R2 goes slack this long as the blade leaves the sheath (0 = stays adaptive)
    iai_tension_force = 0.5, -- light vibrating tension while the Iai Spirit Slash can still counter
    iai_tension_frequency = 0.08,
    iai_clash_time = 0.12,
    iai_lock_time = 0.10,
    iai_fade_time = 0.20,
}

-- stylua: ignore
LongSword.PATTERN = {
    swoosh = { { 0.12, 0.08, HIGH, 0.00 }, { 0.26, 0.08, HIGH, 0.05 }, { 0.12, 0.08, HIGH, 0.11 }, { 0.30, 0.06, RT, 0.00 } },
    roundslash = {
        { 0.20, 0.06, HIGH, 0.00 }, { 0.45, 0.06, HIGH, 0.05 }, { 0.70, 0.14, LOW, 0.08 }, { 0.30, 0.14, LOW, 0.22 },
    },
    level_up = {
        { { 0.45, 0.10, LOW, 0.00 }, { 0.30, 0.10, HIGH, 0.00 } },
        { { 0.45, 0.09, LOW, 0.00 }, { 0.65, 0.12, LOW, 0.13 }, { 0.40, 0.12, HIGH, 0.13 } },
        {
            { 0.45, 0.09, LOW, 0.00 }, { 0.70, 0.09, LOW, 0.12 }, { 1.00, 0.20, LOW, 0.24 }, { 0.80, 0.16, HIGH, 0.24 },
            { 0.35, 0.20, LOW, 0.44 },
        },
    },
    level_down = { { 0.30, 0.10, LOW, 0.00 }, { 0.15, 0.12, LOW, 0.10 } },
    iai_stance = { { 0.35, 0.08, HIGH, 0.00 }, { 0.18, 0.08, LOW, 0.03 } },
    iai_draw = { { 0.45, 0.05, HIGH, 0.00 }, { 0.25, 0.08, LOW, 0.02 } },
    iai_counter = { { 1.00, 0.08, HIGH, 0.00 }, { 1.00, 0.20, LOW, 0.04 }, { 0.40, 0.18, LOW, 0.24 } },
    counter_hit = { { 0.90, 0.07, HIGH, 0.00 }, { 0.80, 0.11, LOW, 0.02 }, { 0.30, 0.12, LOW, 0.13 } },
    helm_breaker_start = { { 0.25, 0.15, LOW, 0.00 }, { 0.15, 0.10, HIGH, 0.00 } },
}

-- Trigger effects { power, frequency, start, end }.
local IAI_TRIGGER = { 1.0, 0.0, 0.2, 0.8 } -- smooth resistance 20%..80% while holding Special Sheathe
local LEVEL_PULSE_TRIGGER = { 1.0, 0.1, 0.0, 1.0 }
local COUNTER_HIT_TRIGGER = { 1.0, 0.30, 0.0, 1.0 }
-- stylua: ignore
local SLASH_IMPACT_TRIGGER = { { 1.0, 0.20, 0.0, 1.0 }, { 1.0, 0.23, 0.0, 1.0 }, { 1.0, 0.26, 0.0, 1.0 }, { 1.0, 0.37, 0.0, 1.0 } }
local SLASH_DRAG_SCALE = { 1.0, 1.2, 1.45, 1.9 }
local SLASH_DRAG_TRIGGER, SLASH_FADE_TRIGGER = {}, {}
for combo = 1, 4 do
    SLASH_DRAG_TRIGGER[combo] = { 0.30, 0.0, 0.0, 1.0 }
    SLASH_FADE_TRIGGER[combo] = { 0.15, 0.0, 0.0, 1.0 }
end
local ROUNDSLASH_LENGTH = 1.8
-- Spirit Breaker { effect, seconds } x3: 3rd hit = heavy bite that drags; final hit = the heaviest effect.
local BREAKER_THIRD_STEPS = { { 1.0, 0.30, 0.0, 1.0 }, 0.08, { 0.45, 0.0, 0.0, 1.0 }, 0.20, { 0.22, 0.0, 0.0, 1.0 }, 0.12 }
local BREAKER_FINAL_STEPS = { { 1.0, 0.42, 0.0, 1.0 }, 0.12, { 0.65, 0.0, 0.0, 1.0 }, 0.30, { 0.32, 0.0, 0.0, 1.0 }, 0.20 }
-- Iai Spirit Slash: whole-travel effects, since R2 is already pulled when they play.
local IAI_TENSION_TRIGGER = { 0.5, 0.08, 0.0, 1.0 }
local IAI_CLASH_TRIGGER = { 1.0, 0.45, 0.0, 1.0 }
local IAI_LOCK_TRIGGER = { 1.0, 0.0, 0.0, 1.0 }
local IAI_FADE_TRIGGER = { 0.35, 0.0, 0.0, 1.0 }

-- Iai moves: every node sits under "atk.atk151.".
--   atk_151_A / atk_156_A: sheathing into Special Sheathe     atk_151_B / atk_156_B / atk_152: holding the stance
--   atk_154: Iai Slash     atk_155: Iai Spirit Slash, whose "success" sub-state is the counter landing
--   atk_153 / atk_300 / atk_305: leaving the stance, the end of a slash
LongSword.IAI_GROUP = "atk.atk151."
LongSword.IAI_SHEATHE_NODES = { "atk_151_A", "atk_156_A" }
LongSword.IAI_STANCE_NODES = { "atk_151_B", "atk_152", "atk_156_B" }
LongSword.IAI_SLASH_NODES = { "atk_154" }
LongSword.IAI_SPIRIT_SLASH_NODES = { "atk_155" }
LongSword.IAI_EXIT_NODES = { "atk_153", "atk_300", "atk_305" }
LongSword.IAI_COUNTER_SUCCESS_NODE = "atk.atk151.atk_155.success"

-- Spirit Blade moves: 1..3 = Spirit Blade I..III (atk_321 is Spirit Blade I from a run), 4 = Spirit Roundslash.
-- Spirit Breaker combo (switch skill replacing Spirit Blade III and the Roundslash): the 3rd hit runs through the
-- sub-states atk_317a/b -> atk_315/316 (under several groups) -> atk_111; the final hit is atk_112.
-- A successful Iai Spirit Slash reaches the 3rd hit through atk_155.success -> atk_107.Branch_B1 -> Branch_L.
LongSword.SPIRIT_MOVE_NODES = {
    { "atk.atk_321", 1 }, { "atk.atk_106.", 1 },
    { "atk.atk_107.atk_107", 2 }, { "atk.atk_107.atk_329", 2 }, -- not atk_107.Branch_* / the 3rd-hit sub-states
    { "atk.atk_108.", 3 }, { "atk.atk_109.", 4 },
    { "atk.atk_111.", "breaker_third" }, { "atk.atk_112.", "breaker_final" },
}
LongSword.BREAKER_THIRD_SUBSTATES = { atk_317a = true, atk_317b = true, atk_315 = true, atk_316 = true }

local state = Patterns.new_state({ last_pulse = -10.0, pulse_until = 0.0, node = nil, iai_part = nil,
    stance_since = 0.0, counter_until = 0.0, clash_until = 0.0, move_fx_until = 0.0, iai_chain = false })
local impact = Patterns.TriggerSteps.new()

-- Move of a node: 1..4, "breaker_third", "breaker_final", or nil.
local function spirit_move_of(name)
    if type(name) ~= "string" then
        return nil
    end
    local sub = name:match("^atk%.[^%.]+%.([^%.]+)")
    if sub and LongSword.BREAKER_THIRD_SUBSTATES[sub] then
        return "breaker_third"
    end
    for _, entry in ipairs(LongSword.SPIRIT_MOVE_NODES) do
        if name:sub(1, #entry[1]) == entry[1] then
            return entry[2]
        end
    end
    return nil
end

-- Nodes an Iai counter passes through on its way into the Spirit Breaker 3rd hit.
local function is_iai_chain_node(name)
    return type(name) == "string"
        and (name:sub(1, #LongSword.IAI_COUNTER_SUCCESS_NODE) == LongSword.IAI_COUNTER_SUCCESS_NODE
            or name:match("^atk%.atk_107%.Branch") ~= nil)
end

-- True when the node is (or is inside) one of the listed Iai sub-states.
local function in_iai_nodes(name, keys)
    local base = #LongSword.IAI_GROUP
    for _, key in ipairs(keys) do
        local prefix = name:sub(base + 1, base + #key)
        local next_char = name:sub(base + #key + 1, base + #key + 1)
        if prefix == key and (next_char == "" or next_char == ".") then
            return true
        end
    end
    return false
end

-- "sheathe", "stance", "iai_slash", "spirit_slash", "other", or nil outside the Iai group / while leaving it.
local function iai_part(name)
    if type(name) ~= "string" or name:sub(1, #LongSword.IAI_GROUP) ~= LongSword.IAI_GROUP then
        return nil
    end
    if in_iai_nodes(name, LongSword.IAI_EXIT_NODES) then
        return nil
    end
    for _, part in ipairs({
        { "sheathe", LongSword.IAI_SHEATHE_NODES }, { "stance", LongSword.IAI_STANCE_NODES },
        { "iai_slash", LongSword.IAI_SLASH_NODES }, { "spirit_slash", LongSword.IAI_SPIRIT_SLASH_NODES },
    }) do
        if in_iai_nodes(name, part[2]) then
            return part[1]
        end
    end
    return "other"
end

local function play(pattern, scale)
    Patterns.play(pattern, LongSword.TUNING.gain * (scale or 1.0))
end

local function on_spirit_breaker(context, is_final, level, from_iai)
    local tuning = LongSword.TUNING
    local scale = is_final and 1.15 or 1.0 + tuning.swoosh_per_combo * 2 + tuning.swoosh_per_level * level
    ActionRumble.play(context, is_final and LongSword.PATTERN.roundslash or LongSword.PATTERN.swoosh, tuning.gain * scale)
    local trigger_on = is_final and tuning.spirit_breaker_final_trigger
        or not is_final and from_iai and tuning.spirit_breaker_iai_third_trigger
    if trigger_on then
        local s = is_final and BREAKER_FINAL_STEPS or BREAKER_THIRD_STEPS
        impact:start(context.now, s[1], s[2], s[3], s[4], s[5], s[6])
        state.move_fx_until = context.now + s[2] + s[4] + s[6]
    end
end

-- move: 1..3 Spirit Blade I..III, 4 Roundslash, "breaker_third" / "breaker_final".
local function on_spirit_move(context, move, level, from_iai)
    if move == "breaker_third" or move == "breaker_final" then
        on_spirit_breaker(context, move == "breaker_final", level, from_iai)
        return
    end
    local tuning = LongSword.TUNING
    local length = move >= 4 and ROUNDSLASH_LENGTH or 1.0
    if move >= 4 then
        ActionRumble.play(context, LongSword.PATTERN.roundslash, tuning.gain)
    else
        local scale = 1.0 + tuning.swoosh_per_combo * (move - 1) + tuning.swoosh_per_level * level
        ActionRumble.play(context, LongSword.PATTERN.swoosh, tuning.gain * scale)
    end
    local trigger_on = move >= 4 and tuning.spirit_roundslash_trigger or move < 4 and tuning.spirit_blade_combo_trigger
    if not trigger_on then
        return
    end
    local impact_effect, impact_time = SLASH_IMPACT_TRIGGER[move], tuning.slash_impact_time * length
    if not tuning.slash_drag_enabled then
        impact:start(context.now, impact_effect, impact_time)
        state.move_fx_until = context.now + impact_time
        return
    end
    local drag_force = math.min(tuning.slash_drag_force * SLASH_DRAG_SCALE[move], 1.0)
    AdaptiveTrigger.sync(SLASH_DRAG_TRIGGER[move], 1, drag_force)
    AdaptiveTrigger.sync(SLASH_FADE_TRIGGER[move], 1, drag_force * 0.5)
    impact:start(context.now, impact_effect, impact_time, SLASH_DRAG_TRIGGER[move], tuning.slash_drag_time * length,
        SLASH_FADE_TRIGGER[move], tuning.slash_fade_time * length)
    state.move_fx_until = context.now + impact_time + (tuning.slash_drag_time + tuning.slash_fade_time) * length
end

-- The Iai Spirit Slash starts: draw rumble (and an optional moment of slack).
local function on_iai_spirit_slash(context)
    local tuning = LongSword.TUNING
    play(LongSword.PATTERN.iai_draw)
    if tuning.iai_slash_trigger and tuning.iai_draw_slack_time > 0 then
        impact:start(context.now, FREE, tuning.iai_draw_slack_time)
    end
end

-- The counter landed: clash (heavy buzz), lock (wall), fade; then a window of counter hits.
local function on_iai_counter(context)
    local tuning, now = LongSword.TUNING, context.now
    play(LongSword.PATTERN.iai_counter)
    if tuning.iai_slash_trigger then
        impact:start(now, IAI_CLASH_TRIGGER, tuning.iai_clash_time, IAI_LOCK_TRIGGER, tuning.iai_lock_time,
            IAI_FADE_TRIGGER, tuning.iai_fade_time)
        -- The counter's own hit lands at the same moment: its R2 kick must not cut the clash short.
        state.clash_until = now + tuning.iai_clash_time + tuning.iai_lock_time + tuning.iai_fade_time
    end
    state.counter_until = now + tuning.counter_window
end

local function desired_trigger(context)
    local tuning, now = LongSword.TUNING, context.now
    if not tuning.trigger_enabled then
        return FREE
    end
    if now < state.pulse_until then
        return LEVEL_PULSE_TRIGGER
    end
    local effect = impact:effect(now)
    if effect then
        return effect
    end
    -- Iai Spirit Slash: tension. Stance: resistance once it has lasted iai_stance_delay. Sheathing, Iai Slash: free.
    if tuning.iai_slash_trigger and state.iai_part == "spirit_slash" then
        return IAI_TENSION_TRIGGER
    end
    if state.iai_part == "stance" and now - state.stance_since >= tuning.iai_stance_delay then
        return IAI_TRIGGER
    end
    return FREE
end

function LongSword.status()
    return string.format("Spirit Gauge %.0f  level %d  Iai %s  node %s", state.gauge or 0, state.level or 0,
        tostring(state.iai_part or "-"), tostring(state.node))
end

-- Iai stance / slash parts, Spirit Blade / Spirit Breaker moves and the counter verdict, from the current node.
-- Returns the move that started this frame, if any.
local function update_node(context, now)
    local previous_node, previous_part = state.node, state.iai_part
    state.node = Core.node_name(context.player)
    state.iai_part = iai_part(state.node)
    if state.iai_part then
        state.last_iai_group = now
    end
    if state.iai_part == "stance" and previous_part ~= "stance" then
        state.stance_since = now
        play(LongSword.PATTERN.iai_stance)
    end
    if state.iai_part == "spirit_slash" and previous_part ~= "spirit_slash" then
        on_iai_spirit_slash(context)
    end
    if state.node == previous_node then
        return nil
    end
    local move = spirit_move_of(state.node)
    if move == spirit_move_of(previous_node) then
        move = nil -- the next sub-node of the same move
    end
    -- The game's own verdict on the Iai Spirit Slash; the counter may chain into the Spirit Breaker 3rd hit.
    if type(state.node) == "string"
        and state.node:sub(1, #LongSword.IAI_COUNTER_SUCCESS_NODE) == LongSword.IAI_COUNTER_SUCCESS_NODE then
        state.iai_chain = true
        if now >= state.clash_until then
            on_iai_counter(context)
        end
    elseif not is_iai_chain_node(state.node) and move ~= "breaker_third" then
        state.iai_chain = false
    end
    return move
end

local function update_level(now)
    local tuning = LongSword.TUNING
    state.gauge = Core.num(state.player, "_LongSwordGauge") or 0
    local level = math.min(Core.num(state.player, "_LongSwordGaugeLv") or 0, 3)
    state.level = level
    local change = Patterns.change(state, "level", level)
    -- An Iai counter raises the level too: that one only rumbles, so the R2 pulse does not cut the clash.
    local after_iai_slash = state.iai_part == "spirit_slash" or now - (state.last_iai_group or -10.0) <= 0.3
    if change > 0 and after_iai_slash then
        play(LongSword.PATTERN.level_up[math.max(level, 1)])
    elseif change > 0 and level >= 1 then
        play(LongSword.PATTERN.level_up[level])
        if now - state.last_pulse > tuning.level_pulse_cooldown then
            state.last_pulse, state.pulse_until = now, now + tuning.level_pulse_time
        end
    elseif change < 0 then
        play(LongSword.PATTERN.level_down)
    end
    return level
end

local function update_helm_breaker(context)
    local tuning = LongSword.TUNING
    if Patterns.rose(state, "helm_breaker", Core.num(context.player, "_IsKabutowari")) then
        ActionRumble.play(context, LongSword.PATTERN.helm_breaker_start, tuning.gain)
    end
    local hits = Core.num(context.player, "_HitKabutowariCount")
    if Patterns.rose(state, "helm_hits", hits) then
        local power = math.min(0.5 + 0.1 * hits, 1.0) * tuning.gain
        ActionRumble.vibrate(context, power, 0.10, LOW)
        ActionRumble.vibrate(context, power * 0.7, 0.08, HIGH)
    end
end

-- Inside the counter window every hit (the delayed follow-up slashes included) is a counter hit; it is not bound to
-- the current action, since those slashes land while the hunter already does something else.
local function update_hits(context, level, now)
    local tuning = LongSword.TUNING
    if not (tuning.hit_rumble and Patterns.take_hit(state, context, tuning.hit_cooldown)) then
        return
    end
    if now < state.counter_until then
        play(LongSword.PATTERN.counter_hit, tuning.counter_hit_gain)
        if tuning.counter_hit_trigger and now >= state.clash_until and now >= state.move_fx_until then
            impact:kick(now, COUNTER_HIT_TRIGGER, 0.06)
        end
        return
    end
    local power = (tuning.hit_power + tuning.hit_power_per_level * level) * tuning.gain
    ActionRumble.vibrate(context, power, tuning.hit_time, LOW)
    ActionRumble.vibrate(context, power * 0.8, tuning.hit_time * 0.7, HIGH)
end

function LongSword.update(context)
    local tuning, now = LongSword.TUNING, context.now
    if Patterns.begin(state, context) then
        state.iai_part, state.stance_since, state.counter_until = nil, 0.0, 0.0
        state.clash_until, state.move_fx_until, state.iai_chain = 0.0, 0.0, false
    end
    state.player = context.player
    local move = update_node(context, now)
    local level = update_level(now)
    update_helm_breaker(context)
    update_hits(context, level, now)
    -- Each Spirit Blade / Spirit Breaker move plays when it starts, whatever led into it; a new move replaces a
    -- counter clash that is still fading.
    if move and tuning.swoosh_enabled then
        local from_iai = move == "breaker_third" and state.iai_chain
        state.clash_until = 0.0
        on_spirit_move(context, move, level, from_iai)
        state.iai_chain = false
    end
    AdaptiveTrigger.sync(IAI_TRIGGER, 1, tuning.iai_trigger_force)
    AdaptiveTrigger.sync(IAI_TENSION_TRIGGER, 1, tuning.iai_tension_force)
    AdaptiveTrigger.sync(IAI_TENSION_TRIGGER, 2, tuning.iai_tension_frequency)
    AdaptiveTrigger.set("R", desired_trigger(context))
end

return LongSword
