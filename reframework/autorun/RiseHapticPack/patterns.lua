-- Shared helpers for weapon modules: rumble patterns, edge detection, timed trigger steps, action-bound rumble and
-- the hit counter (your attacks landing).
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")

local Rumble = Drivers.Rumble
local AdaptiveTrigger = Drivers.AdaptiveTrigger

local Patterns = {}

local MOTOR = Rumble.MOTOR
Patterns.LOW, Patterns.HIGH, Patterns.LT, Patterns.RT = MOTOR.LOW, MOTOR.HIGH, MOTOR.LT, MOTOR.RT

-- Adaptive trigger effects { power, frequency, start, end }.
Patterns.TRIGGER = {
    FREE = AdaptiveTrigger.FREE,
    WALL = { 1.0, 0.0, 0.0, 1.0 },
    PULSE = { 1.0, 0.1, 0.0, 1.0 },
    GUARD_START = { 0.8, 0.0, 0.0, 0.2 },
    CLICK = { 0.55, 0.0, 0.30, 0.55 },
}
Patterns.NOTCH_GAP = 0.045 -- trigger click: seconds the trigger goes slack...
Patterns.NOTCH_TIME = 0.07 -- ...then seconds of hard wall
Patterns.KICK_TIME = 0.06

-- Steps are { power, seconds, motor, delay }. owner: optional Rumble.cancel tag.
function Patterns.play(pattern, scale, owner)
    if not pattern then
        return
    end
    scale = scale or 1.0
    for _, step in ipairs(pattern) do
        Rumble.vibrate(step[1] * scale, step[2], step[3], step[4], owner)
    end
end

function Patterns.new_state(fields)
    local state = { previous = {}, player_address = nil, last_update = -10.0 }
    for key, value in pairs(fields or {}) do
        state[key] = value
    end
    return state
end

-- Stores value under name and compares it with the previous frame: 1 = up, -1 = down, 0 = same / first read / nil.
-- Call exactly one of these per name EVERY frame, or it compares against a stale value.
function Patterns.change(state, name, value)
    if value == nil then
        return 0
    end
    local previous = state.previous[name]
    state.previous[name] = value
    if previous == nil or value == previous then
        return 0
    end
    return value > previous and 1 or -1
end

function Patterns.rose(state, name, value)
    return Patterns.change(state, name, value) > 0
end

function Patterns.fell(state, name, value)
    return Patterns.change(state, name, value) < 0
end

-- Call first in a weapon update: true when the state was reset (new hunter object, or no update for a while).
function Patterns.begin(state, context)
    local address = Core.address(context.player)
    local was_reset = address ~= state.player_address or context.now - state.last_update > 0.5
    if was_reset then
        state.player_address = address
        for name in pairs(state.previous) do
            state.previous[name] = nil
        end
    end
    state.last_update = context.now
    return was_reset
end

-- isWeaponOn at most every 0.2 s.
function Patterns.drawn(state, context)
    if context.now >= (state.next_drawn_check or 0) then
        state.next_drawn_check = context.now + 0.2
        state.is_drawn = Core.is_weapon_on(context.player)
    end
    return state.is_drawn == true
end

-- R2 crossed the threshold this frame.
function Patterns.r2_pressed(state, context, threshold)
    local is_down = context.r2 > (threshold or 0.6)
    local pressed = is_down and not state.r2_was_down
    state.r2_was_down = is_down
    return pressed
end

-- True once per hit batch, at most once per cooldown (state.last_hit).
function Patterns.take_hit(state, context, cooldown)
    if context.hits == 0 then
        return false
    end
    if context.now - (state.last_hit or -10.0) < cooldown then
        return false
    end
    state.last_hit = context.now
    return true
end

-- A timer field that rises while charging: true while it rose within timeout seconds.
function Patterns.timer_rising(state, name, value, now, timeout)
    local key = name .. "_rise"
    if Patterns.change(state, name, value) > 0 then
        state[key] = now
    end
    return now - (state[key] or -10.0) < timeout
end

-- TriggerSteps: up to 3 timed trigger effects played back to back (click, kick, slash drag...).
local TriggerSteps = {}
TriggerSteps.__index = TriggerSteps
Patterns.TriggerSteps = TriggerSteps

function TriggerSteps.new()
    local free = Patterns.TRIGGER.FREE
    return setmetatable({ count = 0, effects = { free, free, free }, ends = { 0.0, 0.0, 0.0 } }, TriggerSteps)
end

function TriggerSteps:start(now, first, first_time, second, second_time, third, third_time)
    local free = Patterns.TRIGGER.FREE
    self.count = third_time and 3 or second_time and 2 or 1
    self.effects[1], self.effects[2], self.effects[3] = first, second or free, third or free
    self.ends[1] = now + first_time
    self.ends[2] = self.ends[1] + (second_time or 0)
    self.ends[3] = self.ends[2] + (third_time or 0)
end

-- Click: the trigger goes slack for gap seconds, then hits the wall for time seconds.
function TriggerSteps:notch(now, wall, gap, time)
    self:start(now, Patterns.TRIGGER.FREE, gap or Patterns.NOTCH_GAP, wall or Patterns.TRIGGER.WALL,
        time or Patterns.NOTCH_TIME)
end

function TriggerSteps:kick(now, effect, time)
    self:start(now, effect, time or Patterns.KICK_TIME)
end

-- Effect of the running step, nil once the steps are over.
function TriggerSteps:effect(now)
    for index = 1, self.count do
        if now < self.ends[index] then
            return self.effects[index]
        end
    end
    self.count = 0
    return nil
end

-- ActionRumble: rumble bound to the current action (motion FSM node). When the hunter cancels into another action
-- (dodge, guard...), what is left of it is cut at once.
local ActionRumble = { owner = nil }
Patterns.ActionRumble = ActionRumble

local function action_owner(context)
    local node = Core.node_hash(context.player)
    local owner = ActionRumble.owner
    if owner and owner.node == node then
        return owner
    end
    if owner then
        Rumble.cancel(owner)
    end
    owner = { node = node }
    ActionRumble.owner = owner
    return owner
end

function ActionRumble.play(context, pattern, scale)
    Patterns.play(pattern, scale, action_owner(context))
end

function ActionRumble.vibrate(context, power, seconds, motor, delay)
    return Rumble.vibrate(power, seconds, motor, delay, action_owner(context))
end

-- Every frame: reads the node only while an action rumble is still queued.
function ActionRumble.update(context)
    local owner = ActionRumble.owner
    if not owner then
        return
    end
    if not Rumble.has_owner(owner) then
        ActionRumble.owner = nil
        return
    end
    if owner.node ~= nil and Core.node_hash(context.player) ~= owner.node then
        Rumble.cancel(owner)
        ActionRumble.owner = nil
    end
end

-- Hits: your attacks landing. Several game paths report a hit on the attacking hunter; hits from shells (delayed
-- slashes such as the Long Sword Iai counter follow-ups, bowgun ammo...) may skip afterCalcDamage_AttackSide, so the
-- enemy result calc counts too. Hits from several paths in the same frame are one batch (Patterns.take_hit).
-- Each path has its own counter, shown in the menu, to see which ones fire in game.
local Hits = { pending = 0, master_address = nil, installed = false, total = 0 }
Hits.sources = { after_calc = 0, result_enemy = 0, shell_hit_id = 0 }
Patterns.Hits = Hits

local HIT_PATHS = {
    { method = "afterCalcDamage_AttackSide", source = "after_calc", counts = true },
    { method = "calcHitAttackResultForEnemy", source = "result_enemy", counts = true },
    -- May fire when a shell refreshes its hit id rather than on a hit: counted for the menu only.
    { method = "onUpdateHitIdHitForShell", source = "shell_hit_id", counts = false },
}

function Hits.install()
    if Hits.installed then
        return
    end
    Hits.installed = true
    for _, path in ipairs(HIT_PATHS) do
        Core.hook("snow.player.PlayerQuestBase", path.method, function(args)
            if Hits.master_address and (sdk.to_int64(args[2]) or 0) == Hits.master_address then
                Hits.sources[path.source] = Hits.sources[path.source] + 1
                if path.counts then
                    Hits.pending = Hits.pending + 1
                    Hits.total = Hits.total + 1
                end
            end
        end)
    end
end

function Hits.take()
    local count = Hits.pending
    Hits.pending = 0
    return count
end

return Patterns
