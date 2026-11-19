-- Long Sword (snow.player.LongSword). Port of LS_Adaptive_Trigger.lua + the Wilds pack's long_sword tunes.
-- R2 = Spirit Blade. Special Sheathe: smooth R2 resistance (Iai Spirit Slash is on R2). Iai Spirit Slash (the
-- unsheathe counter): R2 gives way as the blade leaves the sheath, holds a light vibrating tension while the counter
-- window is open, and a successful counter clashes, locks and fades. Spirit Gauge level up: R2 pulse + rumble.
-- Spirit Blade I..III / Roundslash: R2 impact, drag, fade. Rise has no Wilds-style spirit charge.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")

local AdaptiveTrigger = Drivers.AdaptiveTrigger
local ActionRumble = Patterns.ActionRumble
local LOW, HIGH, LT, RT = Patterns.LOW, Patterns.HIGH, Patterns.LT, Patterns.RT
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
    swoosh_cooldown = 0.15,
    swoosh_combo_window = 1.3,
    swoosh_per_combo = 0.25,
    swoosh_per_level = 0.20,
    hit_rumble = true,
    hit_power = 0.30,
    hit_power_per_level = 0.10,
    hit_time = 0.08,
    hit_cooldown = 0.06,
    -- Iai Spirit Slash counter: its follow-up slashes land over the next seconds; each hit in this window rumbles as
    -- a counter hit and kicks R2.
    counter_window = 3.0,
    counter_hit_gain = 1.0,
    counter_hit_trigger = true,
    -- Iai Spirit Slash on R2.
    iai_slash_trigger = true,
    iai_draw_slack_time = 0.0, -- > 0: R2 goes slack this long as the blade leaves the sheath (0 = stays adaptive)
    iai_tension_force = 0.5, -- light vibrating tension while the counter can still land
    iai_tension_frequency = 0.08,
    iai_gp_window = 0.45, -- tension time when the game's counter flag is not seen
    iai_press_grace = 0.20, -- an R2 press this soon after leaving the stance is still the Iai Spirit Slash
    iai_clash_time = 0.12,
    iai_lock_time = 0.10,
    iai_fade_time = 0.20,
    trace_nodes = true, -- write reframework/data/RiseHapticPack_ls_trace.txt (node names, Iai events)
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
    spirit_cut = { { 0.50, 0.06, HIGH, 0.00 }, { 0.60, 0.10, LOW, 0.03 } },
    helm_breaker_start = { { 0.25, 0.15, LOW, 0.00 }, { 0.15, 0.10, HIGH, 0.00 } },
}

-- { power, frequency, start, end }
local IAI_TRIGGER = { 1.0, 0.0, 0.2, 0.8 } -- smooth resistance 20%..80% while in Special Sheathe
local LEVEL_PULSE_TRIGGER = { 1.0, 0.1, 0.0, 1.0 }
-- stylua: ignore
local SLASH_IMPACT_TRIGGER = { { 1.0, 0.20, 0.0, 1.0 }, { 1.0, 0.23, 0.0, 1.0 }, { 1.0, 0.26, 0.0, 1.0 }, { 1.0, 0.37, 0.0, 1.0 } }
local SLASH_DRAG_SCALE = { 1.0, 1.2, 1.45, 1.9 }
local SLASH_DRAG_TRIGGER, SLASH_FADE_TRIGGER = {}, {}
for combo = 1, 4 do
    SLASH_DRAG_TRIGGER[combo] = { 0.30, 0.0, 0.0, 1.0 }
    SLASH_FADE_TRIGGER[combo] = { 0.15, 0.0, 0.0, 1.0 }
end
local ROUNDSLASH_LENGTH = 1.8

-- Node names below come from the game's own motion graph (menu dump, 2026-11-18 21:46: 4478 nodes with transitions).
--
-- Iai group "atk.atk151.":
--   atk_151_A -> atk_151_B (or straight to atk_155), atk_156_A -> atk_156_B: getting into Special Sheathe
--   atk_152: holding the stance (goes to atk_155, atk_154 or atk_153)
--   atk_153: leaving the stance (to wait / run)
--   atk_154: Iai Slash (A)          atk_155: Iai Spirit Slash (R2)
--   atk_155."new state ..." -> atk_155.成否 (success / fail check) -> atk_155.success | atk_155.faled
--   atk_300 / atk_305: the end of the slash, back to wait / run
-- R2 per part (user's choice): sheathing animation free; stance resistance after a tiny delay; Iai Slash free (its
-- effect must not linger into the next press); Iai Spirit Slash tension, then the clash on success.
-- Trace timings: 156_A lasts ~0.66 s and 151_A ~1.26 s, entered with R2 still held from the R2+A input.
LongSword.IAI_GROUP = "atk.atk151."
LongSword.IAI_SHEATHE_NODES = { "atk_151_A", "atk_156_A" }
LongSword.IAI_STANCE_NODES = { "atk_151_B", "atk_152", "atk_156_B" }
LongSword.IAI_SLASH_NODES = { "atk_154" }
LongSword.IAI_SPIRIT_SLASH_NODES = { "atk_155" }
LongSword.IAI_EXIT_NODES = { "atk_153", "atk_300", "atk_305" }
LongSword.IAI_COUNTER_SUCCESS_NODE = "atk.atk151.atk_155.success"

-- Spirit Blade moves by node group: 1..3 = Spirit Blade I..III, 4 = Spirit Roundslash. From the motion graph:
--   atk_109 Roundslash: entered only from atk_108, atk_147.コマンド (successful Foresight Slash), atk_161_MR (Sacred
--           Sheathe) and the switch-skill node "入れ替えB判定(4段目)" (4th stage)
--   atk_108 Spirit Blade III: the switch-skill node "入れ替えB判定(3段目)" (3rd stage) leads here
--   atk_107 Spirit Blade II: entered from atk_106, Iai Slash, and a successful Iai Spirit Slash
--   atk_106 Spirit Blade I: entered from neutral, most attacks, landings and dodges; atk_321 = its running lead-in
--
-- Spirit Breaker combo (switch skill "入れ替えB" = swap B: replaces Spirit Blade III and the Roundslash):
--   3rd hit: atk_317a / atk_317b -> atk_315 / atk_316 -> atk_111 (the swap's "3段目"). These sub-states sit under
--            several groups (atk_107, atk_110, atk_161_MR, the switch-skill nodes...). A successful Iai Spirit Slash
--            reaches it directly: atk_155.success -> atk_107.Branch_B1 -> atk_107.Branch_L -> atk_317a/b.
--   final hit: atk_112 (the swap's "4段目"; the Spirit Gauge level rose during it in the user's trace)
-- Seen in the trace: atk_106 -> atk_107 -> atk_107.atk_317a -> atk_316 -> atk_111 -> atk_112.
-- Once any of these is seen, R2 presses no longer guess the combo step.
LongSword.SPIRIT_MOVE_NODES = {
    { "atk.atk_321", 1 }, { "atk.atk_106.", 1 },
    { "atk.atk_107.atk_107", 2 }, { "atk.atk_107.atk_329", 2 }, -- not atk_107.Branch_* / the 3rd-hit sub-states
    { "atk.atk_108.", 3 }, { "atk.atk_109.", 4 },
    { "atk.atk_111.", "breaker_third" }, { "atk.atk_112.", "breaker_final" },
}
LongSword.BREAKER_THIRD_SUBSTATES = { atk_317a = true, atk_317b = true, atk_315 = true, atk_316 = true }

-- Move of a node: 1..4 (Spirit Blade I..III, Roundslash), "breaker_third", "breaker_final", or nil.
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

-- Nodes the Iai Spirit Slash counter passes through on its way into the Spirit Breaker 3rd hit.
local function is_iai_chain_node(name)
    return type(name) == "string"
        and (name:sub(1, 26) == "atk.atk151.atk_155.success" or name:match("^atk%.atk_107%.Branch") ~= nil)
end

local COUNTER_HIT_TRIGGER = { 1.0, 0.30, 0.0, 1.0 }
-- Spirit Breaker: { effect, seconds } steps. Third hit (after a successful Iai Spirit Slash): a heavy bite that drags;
-- final hit: the heaviest effect of the weapon, longer than the Roundslash.
local BREAKER_THIRD_STEPS = { { 1.0, 0.30, 0.0, 1.0 }, 0.08, { 0.45, 0.0, 0.0, 1.0 }, 0.20, { 0.22, 0.0, 0.0, 1.0 }, 0.12 }
local BREAKER_FINAL_STEPS = { { 1.0, 0.42, 0.0, 1.0 }, 0.12, { 0.65, 0.0, 0.0, 1.0 }, 0.30, { 0.32, 0.0, 0.0, 1.0 }, 0.20 }
-- Iai Spirit Slash: whole-travel effects, since R2 is already pulled when they play.
local IAI_TENSION_TRIGGER = { 0.5, 0.08, 0.0, 1.0 }
local IAI_CLASH_TRIGGER = { 1.0, 0.45, 0.0, 1.0 }
local IAI_LOCK_TRIGGER = { 1.0, 0.0, 0.0, 1.0 }
local IAI_FADE_TRIGGER = { 0.35, 0.0, 0.0, 1.0 }

local state = Patterns.new_state({ combo = 0, last_swoosh = -10.0, last_pulse = -10.0, pulse_until = 0.0,
    is_iai = false, node = nil, counter_until = 0.0, last_iai = -10.0, gp_until = 0.0 })
local impact = Patterns.TriggerSteps.new()

-- Trace of Long Sword node names and Iai events, so the real Rise names can replace the guessed ones.
local trace = { seen = {}, order = {}, events = {}, dirty = false, next_write = 0.0 }

local function trace_event(now, text)
    if not LongSword.TUNING.trace_nodes then
        return
    end
    if #trace.events >= 400 then
        table.remove(trace.events, 1)
    end
    trace.events[#trace.events + 1] = string.format("%.2f %s", now, text)
    trace.dirty = true
end

local function trace_node(name)
    if not LongSword.TUNING.trace_nodes or type(name) ~= "string" then
        return
    end
    if not trace.seen[name] then
        if #trace.order >= 400 then
            return
        end
        trace.seen[name] = 0
        trace.order[#trace.order + 1] = name
    end
    trace.seen[name] = trace.seen[name] + 1
    trace.dirty = true
end

local function trace_write(now)
    if not trace.dirty or now < trace.next_write then
        return
    end
    trace.dirty, trace.next_write = false, now + 2.0
    local ok, file = pcall(io.open, "RiseHapticPack_ls_trace.txt", "w")
    if not ok or not file then
        return
    end
    file:write("# Long Sword node names (entries)\n")
    for _, name in ipairs(trace.order) do
        file:write(string.format("%5d  %s\n", trace.seen[name], name))
    end
    file:write("\n# Events\n")
    for _, line in ipairs(trace.events) do
        file:write(line, "\n")
    end
    file:close()
end

-- snow.player.LongSword events, your hunter only. Counted for the menu (which ones fire is not verified in game).
local hook = { installed = false, master = nil, counter = 0, shell020 = 0, spacing = 0 }
LongSword.counts = { counter = 0, shell020 = 0, spacing = 0, counter_hits = 0, level_counter = 0 }

local function install_hooks()
    if hook.installed then
        return
    end
    hook.installed = true
    local function on(method, key)
        Core.hook("snow.player.LongSword", method, function(args)
            if hook.master and (sdk.to_int64(args[2]) or 0) == hook.master then
                hook[key] = hook[key] + 1
                LongSword.counts[key] = LongSword.counts[key] + 1
            end
        end)
    end
    on("iaiCounterSuccess", "counter")
    on("createLongSwordShell020", "shell020")
    on("createSpacingShell", "spacing")
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

-- "sheathe", "stance", "iai_slash", "spirit_slash", "other" (unknown Iai node), or nil outside the group / leaving it.
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

local function on_spirit_slash(context, combo, level, from_iai)
    local tuning = LongSword.TUNING
    if combo == "breaker_third" or combo == "breaker_final" then
        local is_final = combo == "breaker_final"
        local scale = 1.0 + tuning.swoosh_per_combo * 2 + tuning.swoosh_per_level * level
        ActionRumble.play(context, is_final and LongSword.PATTERN.roundslash or LongSword.PATTERN.swoosh,
            tuning.gain * (is_final and 1.15 or scale))
        -- Final hit: always (if enabled). Third hit: only when chained from a successful Iai Spirit Slash.
        local trigger_on = is_final and tuning.spirit_breaker_final_trigger
            or not is_final and from_iai and tuning.spirit_breaker_iai_third_trigger
        if trigger_on then
            local s = is_final and BREAKER_FINAL_STEPS or BREAKER_THIRD_STEPS
            impact:start(context.now, s[1], s[2], s[3], s[4], s[5], s[6])
            state.move_fx_until = context.now + s[2] + s[4] + s[6]
        end
        trace_event(context.now, string.format("spirit breaker %s%s  trigger=%s", is_final and "final hit" or "3rd hit",
            from_iai and " (from Iai counter)" or "", tostring(trigger_on)))
        return
    end
    local length = combo >= 4 and ROUNDSLASH_LENGTH or 1.0
    if combo >= 4 then
        ActionRumble.play(context, LongSword.PATTERN.roundslash, tuning.gain)
    else
        local scale = 1.0 + tuning.swoosh_per_combo * (combo - 1) + tuning.swoosh_per_level * level
        ActionRumble.play(context, LongSword.PATTERN.swoosh, tuning.gain * scale)
    end
    local trigger_on = combo >= 4 and tuning.spirit_roundslash_trigger or combo < 4 and tuning.spirit_blade_combo_trigger
    if not trigger_on then
        return
    end
    local impact_effect, impact_time = SLASH_IMPACT_TRIGGER[combo], tuning.slash_impact_time * length
    if not tuning.slash_drag_enabled then
        impact:start(context.now, impact_effect, impact_time)
        return
    end
    local drag_force = math.min(tuning.slash_drag_force * SLASH_DRAG_SCALE[combo], 1.0)
    AdaptiveTrigger.sync(SLASH_DRAG_TRIGGER[combo], 1, drag_force)
    AdaptiveTrigger.sync(SLASH_FADE_TRIGGER[combo], 1, drag_force * 0.5)
    impact:start(context.now, impact_effect, impact_time, SLASH_DRAG_TRIGGER[combo], tuning.slash_drag_time * length,
        SLASH_FADE_TRIGGER[combo], tuning.slash_fade_time * length)
    state.move_fx_until = context.now + impact_time + (tuning.slash_drag_time + tuning.slash_fade_time) * length
end

-- Iai Spirit Slash starts (R2 out of Special Sheathe): R2 goes slack for a moment, then the counter-window tension.
local function on_iai_spirit_slash(context, source)
    local tuning, now = LongSword.TUNING, context.now
    if now < state.gp_until then
        return
    end
    state.gp_until = now + tuning.iai_gp_window
    play(LongSword.PATTERN.iai_draw)
    if tuning.iai_slash_trigger and tuning.iai_draw_slack_time > 0 then
        impact:start(now, FREE, tuning.iai_draw_slack_time)
    end
    trace_event(now, string.format("iai spirit slash (%s) node=%s", source, tostring(state.node)))
end

-- Counter landed: clash (heavy buzz), lock (wall), fade.
local function on_iai_counter(context, source)
    local tuning, now = LongSword.TUNING, context.now
    state.gp_until = 0.0
    play(LongSword.PATTERN.iai_counter)
    if tuning.iai_slash_trigger then
        impact:start(now, IAI_CLASH_TRIGGER, tuning.iai_clash_time, IAI_LOCK_TRIGGER, tuning.iai_lock_time,
            IAI_FADE_TRIGGER, tuning.iai_fade_time)
        -- The counter's own hit lands at the same moment: its R2 kick must not cut the clash short.
        state.clash_until = now + tuning.iai_clash_time + tuning.iai_lock_time + tuning.iai_fade_time
    end
    state.counter_until = now + tuning.counter_window
    trace_event(now, string.format("counter success (%s) node=%s", source, tostring(state.node)))
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
    if tuning.iai_slash_trigger and (state.iai_part == "spirit_slash" or now < state.gp_until) then
        return IAI_TENSION_TRIGGER
    end
    if state.iai_part == "stance" and now - state.stance_since >= tuning.iai_stance_delay then
        return IAI_TRIGGER
    end
    return FREE
end

function LongSword.status()
    local counts = LongSword.counts
    return string.format("gauge %.0f  level %d  iai %s  node %s\n  counter %d (level-up %d)  shell020 %d  spacing %d"
        .. "  counter hits %d", state.gauge or 0, state.level or 0, tostring(state.iai_part), tostring(state.node),
        counts.counter, counts.level_counter, counts.shell020, counts.spacing, counts.counter_hits)
end

function LongSword.update(context)
    local tuning, player, now = LongSword.TUNING, context.player, context.now
    if Patterns.begin(state, context) then
        state.combo, state.is_iai, state.iai_part, state.counter_until = 0, false, nil, 0.0
        state.stance_since, state.gp_until = 0.0, 0.0
        hook.counter, hook.shell020, hook.spacing = 0, 0, 0
    end
    install_hooks()
    hook.master = Core.address(player)
    local drawn = Patterns.drawn(state, context)

    -- Iai moves (motion FSM node group): sheathe -> stance -> Iai Slash or Iai Spirit Slash.
    local previous_node = state.node
    state.node = Core.node_name(player)
    local previous_part = state.iai_part
    state.iai_part = iai_part(state.node)
    -- In Special Sheathe (sheathing or holding): an R2 press there is never a Spirit Blade.
    state.is_iai = state.iai_part == "stance" or state.iai_part == "sheathe"
    if state.iai_part then
        state.last_iai_group = now
    end
    if state.is_iai then
        state.last_iai = now
    end
    if state.iai_part == "stance" and previous_part ~= "stance" then
        state.stance_since = now
        play(LongSword.PATTERN.iai_stance)
    end
    -- Left the Iai Spirit Slash: its tension window must not carry over into the next move.
    if previous_part == "spirit_slash" and state.iai_part ~= "spirit_slash" then
        state.gp_until = 0.0
    end
    local spirit_combo = nil
    if state.node ~= previous_node then
        trace_node(state.node)
        local is_attack_node = type(state.node) == "string" and state.node:sub(1, 3) == "atk"
        if state.iai_part or previous_part or is_attack_node then
            trace_event(now, string.format("node %s  part=%s  r2=%.2f  level=%s  gp=%s", tostring(state.node),
                tostring(state.iai_part), context.r2, tostring(state.level), tostring(Core.num(player, "_IsIaiCounter"))))
        end
        -- A new Spirit Blade / Spirit Breaker move (not just the next sub-node of the same one).
        local move = spirit_move_of(state.node)
        if move and move ~= spirit_move_of(previous_node) then
            spirit_combo = move
            state.spirit_nodes_seen = true
        end
        -- The game's own verdict on the Iai Spirit Slash counter; it may chain into the Spirit Breaker 3rd hit.
        if type(state.node) == "string"
            and state.node:sub(1, #LongSword.IAI_COUNTER_SUCCESS_NODE) == LongSword.IAI_COUNTER_SUCCESS_NODE then
            state.counter_node = true
            state.iai_chain = true
        elseif not is_iai_chain_node(state.node) and move ~= "breaker_third" then
            state.iai_chain = false -- the counter led somewhere else
        end
    end
    -- The Iai Spirit Slash (atk_155) began: draw rumble, then tension until it ends or the counter lands.
    if state.iai_part == "spirit_slash" and previous_part ~= "spirit_slash" and now >= state.gp_until then
        on_iai_spirit_slash(context, "spirit slash node")
    end

    -- Iai Spirit Slash: the game's counter-window flag, or an R2 press in (or just out of) the stance.
    -- _IsIaiCounter also rises during Sacred Sheathe (atk_161_MR, seen in the trace): only trust it in the Iai group.
    local in_iai_group = state.iai_part ~= nil
    local gp_flag = Core.num(player, "_IsIaiCounter") or 0
    if Patterns.rose(state, "gp_flag", gp_flag) and in_iai_group then
        on_iai_spirit_slash(context, "counter flag")
    end
    if gp_flag > 0 and in_iai_group and tuning.iai_slash_trigger then
        state.gp_until = math.max(state.gp_until, now + 0.05)
    end
    -- An R2 press in the stance only keeps the Spirit Blade fallback away: the Iai Spirit Slash itself starts with
    -- its node (atk_155), and the R2+A press that enters the stance must not swap the stance resistance for tension.
    local r2_pressed = Patterns.r2_pressed(state, context)
    local is_iai_press = r2_pressed and (state.is_iai or now - state.last_iai <= tuning.iai_press_grace)

    -- Spirit Gauge level (snow.player.LongSword.LongSwordKijin: Lv0..Lv3).
    state.gauge = Core.num(player, "_LongSwordGauge") or 0
    local level = math.min(Core.num(player, "_LongSwordGaugeLv") or 0, 3)
    state.level = level
    local level_change = Patterns.change(state, "level", level)
    -- The counter's own level-up (during or right after an Iai slash) only rumbles: the success node plays the clash,
    -- and the level-up R2 pulse must not cut it.
    local in_iai_slash = state.iai_part == "spirit_slash" or now < state.gp_until
        or now - (state.last_iai_group or -10.0) <= 0.3
    if level_change > 0 and in_iai_slash then
        LongSword.counts.level_counter = LongSword.counts.level_counter + 1
        play(LongSword.PATTERN.level_up[math.max(level, 1)])
    elseif level_change > 0 and level >= 1 then
        play(LongSword.PATTERN.level_up[level])
        if now - state.last_pulse > tuning.level_pulse_cooldown then
            state.last_pulse, state.pulse_until = now, now + tuning.level_pulse_time
        end
    elseif level_change < 0 then
        play(LongSword.PATTERN.level_down)
    end

    -- Iai Spirit Slash counter (hook or flag), and the follow-up slashes it spawns (shells).
    local counter_flag = Patterns.rose(state, "iai_counter", Core.num(player, "<IsIaiCounterSuccess>k__BackingField"))
    local clash_running = now < (state.clash_until or 0) -- already played this counter
    if state.counter_node then
        state.counter_node = false
        if not clash_running then
            on_iai_counter(context, "success node")
            clash_running = true
        end
    end
    -- The iaiCounterSuccess hook fired during Sacred Sheathe in the trace: only an Iai-group counter plays the clash.
    local near_iai = now - (state.last_iai_group or -10.0) <= 0.5
    if hook.counter > 0 then
        hook.counter = 0
        if not clash_running and near_iai then
            on_iai_counter(context, "hook")
        end
    elseif counter_flag and not clash_running and near_iai then
        on_iai_counter(context, "flag")
    end
    if hook.shell020 > 0 or hook.spacing > 0 then
        trace_event(now, string.format("follow-up shell (shell020 %d, spacing %d)", hook.shell020, hook.spacing))
        hook.shell020, hook.spacing = 0, 0
        state.counter_until = math.max(state.counter_until, now + tuning.counter_window)
        play(LongSword.PATTERN.spirit_cut, tuning.counter_hit_gain)
    end
    if Patterns.rose(state, "helm_breaker", Core.num(player, "_IsKabutowari")) then
        ActionRumble.play(context, LongSword.PATTERN.helm_breaker_start, tuning.gain)
    end
    local helm_hits = Core.num(player, "_HitKabutowariCount")
    if Patterns.rose(state, "helm_hits", helm_hits) then
        local power = math.min(0.5 + 0.1 * helm_hits, 1.0) * tuning.gain
        ActionRumble.vibrate(context, power, 0.10, LOW)
        ActionRumble.vibrate(context, power * 0.7, 0.08, HIGH)
    end

    -- Your hits. Inside the counter window every hit (the delayed follow-up slashes included) is a counter hit; it
    -- is not bound to the current action, since those slashes land while you already do something else.
    if tuning.hit_rumble and Patterns.take_hit(state, context, tuning.hit_cooldown) then
        if now < state.counter_until then
            LongSword.counts.counter_hits = LongSword.counts.counter_hits + 1
            play(LongSword.PATTERN.counter_hit, tuning.counter_hit_gain)
            -- Not over the clash or a move's own effect (e.g. the Spirit Breaker 3rd hit chained from the counter).
            if tuning.counter_hit_trigger and now >= (state.clash_until or 0) and now >= (state.move_fx_until or 0) then
                impact:kick(now, COUNTER_HIT_TRIGGER, 0.06)
            end
        else
            local power = (tuning.hit_power + tuning.hit_power_per_level * level) * tuning.gain
            ActionRumble.vibrate(context, power, tuning.hit_time, LOW)
            ActionRumble.vibrate(context, power * 0.8, tuning.hit_time * 0.7, HIGH)
        end
    end

    -- Spirit Blade presses (R2): combo 1..3 = Spirit Blade I..III, 4 = Spirit Roundslash.
    -- By node: each Spirit Blade move plays when it starts, whatever led into it (Iai Slash -> Roundslash included).
    -- A new move is a real follow-up, so it replaces a counter clash that is still fading.
    if spirit_combo and tuning.swoosh_enabled then
        local from_iai = spirit_combo == "breaker_third" and state.iai_chain
        state.last_swoosh, state.clash_until = now, 0.0
        if type(spirit_combo) == "number" then
            state.combo = spirit_combo
        end
        on_spirit_slash(context, spirit_combo, level, from_iai)
        state.iai_chain = false
    end
    -- Fallback until a Spirit Blade node has been seen: guess the step from R2 presses.
    -- Never inside an Iai move or its clash: R2 there belongs to the Iai Spirit Slash.
    if not state.spirit_nodes_seen and r2_pressed and not is_iai_press and not state.iai_part
        and tuning.swoosh_enabled and drawn and now >= state.gp_until and now >= (state.clash_until or 0)
        and now - state.last_swoosh >= tuning.swoosh_cooldown then
        if now - state.last_swoosh > tuning.swoosh_combo_window then
            state.combo = 0
        end
        state.last_swoosh = now
        state.combo = state.combo % 4 + 1
        on_spirit_slash(context, state.combo, level)
    end

    AdaptiveTrigger.sync(IAI_TRIGGER, 1, tuning.iai_trigger_force)
    AdaptiveTrigger.sync(IAI_TENSION_TRIGGER, 1, tuning.iai_tension_force)
    AdaptiveTrigger.sync(IAI_TENSION_TRIGGER, 2, tuning.iai_tension_frequency)
    AdaptiveTrigger.set("R", desired_trigger(context))
    trace_write(now)
end

return LongSword
