-- Haptic outputs: HapticBreak (one gate for everything), Rumble (grip motors) and AdaptiveTrigger (DualSense L2 / R2).
local Core = require("RiseHapticPack.core")

local Drivers = {}

-- HapticBreak -------------------------------------------------------------------------------------------------
-- While a break is active (the hunter was hit), new rumble is dropped and the triggers go free.
local HapticBreak = { until_time = 0.0, unblocked_depth = 0, listeners = {} }
Drivers.HapticBreak = HapticBreak

function HapticBreak.on_start(callback)
    HapticBreak.listeners[#HapticBreak.listeners + 1] = callback
end

function HapticBreak.start(now, seconds)
    local was_active = now < HapticBreak.until_time
    HapticBreak.until_time = math.max(HapticBreak.until_time, now + seconds)
    if not was_active then
        for _, callback in ipairs(HapticBreak.listeners) do
            pcall(callback, now)
        end
    end
end

function HapticBreak.is_active(now)
    return now < HapticBreak.until_time
end

function HapticBreak.is_blocked(now)
    return HapticBreak.unblocked_depth == 0 and now < HapticBreak.until_time
end

-- The reaction to the hit itself must still play.
function HapticBreak.unblocked(callback, ...)
    HapticBreak.unblocked_depth = HapticBreak.unblocked_depth + 1
    local ok, message = pcall(callback, ...)
    HapticBreak.unblocked_depth = HapticBreak.unblocked_depth - 1
    return ok, message
end

function HapticBreak.reset()
    HapticBreak.until_time = 0.0
end

-- Rumble ------------------------------------------------------------------------------------------------------
-- Rise has no "rumble for N seconds" call: snow.Pad.setMotorPower sets a motor until the next call. While one of
-- its own vibrations plays, the game calls it once per frame with motor All. The mod queues timed pulses per motor
-- and, right after snow.Pad.update, writes max(game power, strongest mod pulse) to each grip motor.
local Rumble = { gain = 1.0, combined = false }
Drivers.Rumble = Rumble

-- Logical motors used by patterns: { power, seconds, motor, delay }.
local MOTOR = { LOW = 0, HIGH = 1, LT = 2, RT = 3 }
Rumble.MOTOR = MOTOR

-- via.hid.GamePadMotor values (read from the game).
local PAD_MOTOR = { ALL = 6, LOW = 128, HIGH = 129 }
-- Neither XInput (Steam Input) nor the DualSense rumble emulation has trigger motors: LT / RT pulses play on the grips.
local BODY_OF = { [MOTOR.LOW] = MOTOR.LOW, [MOTOR.HIGH] = MOTOR.HIGH, [MOTOR.LT] = MOTOR.LOW, [MOTOR.RT] = MOTOR.HIGH }
local BODY_SCALE = { [MOTOR.LOW] = 1.0, [MOTOR.HIGH] = 1.0, [MOTOR.LT] = 0.8, [MOTOR.RT] = 1.0 }
local MAXIMUM_POWER = 1.0
local MINIMUM_PULSE = 0.05
local MAXIMUM_PULSES = 32
local GAME_HOLD = 0.1 -- seconds a game motor write stays valid

local channels = { [MOTOR.LOW] = {}, [MOTOR.HIGH] = {} }
local game = { power = { [MOTOR.LOW] = 0.0, [MOTOR.HIGH] = 0.0 }, time = -10.0 }
local was_active = false
Rumble.stats = { game_writes = 0, mod_writes = 0, flush_hook = false }

function Rumble.vibrate(power, seconds, motor, delay, owner)
    motor = motor or MOTOR.LOW
    power = (power or 0) * Rumble.gain * (BODY_SCALE[motor] or 1.0)
    if power <= 0 or not seconds or seconds <= 0 then
        return false
    end
    local now = Core.now()
    if HapticBreak.is_blocked(now) then
        return false
    end
    local pulses = channels[BODY_OF[motor] or MOTOR.LOW]
    if #pulses >= MAXIMUM_PULSES then
        table.remove(pulses, 1)
    end
    local start = now + (delay or 0)
    pulses[#pulses + 1] = {
        power = math.min(power, MAXIMUM_POWER),
        start = start,
        stop = start + math.max(seconds, MINIMUM_PULSE),
        owner = owner,
    }
    return true
end

function Rumble.body(power, seconds, delay)
    Rumble.vibrate(power, seconds, MOTOR.LOW, delay)
    Rumble.vibrate(power, seconds, MOTOR.HIGH, delay)
end

-- Drops the pulses tagged with owner (also the ones not started yet).
function Rumble.cancel(owner)
    for _, pulses in pairs(channels) do
        for index = #pulses, 1, -1 do
            if pulses[index].owner == owner then
                table.remove(pulses, index)
            end
        end
    end
end

function Rumble.has_owner(owner)
    for _, pulses in pairs(channels) do
        for _, pulse in ipairs(pulses) do
            if pulse.owner == owner then
                return true
            end
        end
    end
    return false
end

function Rumble.clear()
    for _, pulses in pairs(channels) do
        for index = #pulses, 1, -1 do
            pulses[index] = nil
        end
    end
end

local function strongest(pulses, now)
    local best = 0.0
    for index = #pulses, 1, -1 do
        local pulse = pulses[index]
        if now >= pulse.stop then
            table.remove(pulses, index)
        elseif now >= pulse.start and pulse.power > best then
            best = pulse.power
        end
    end
    return best
end

local SET_MOTOR = "setMotorPower(via.hid.GamePadMotor, System.Single)"

local function send(motor, power)
    local pad = Core.singleton("snow.Pad")
    if not pad then
        return
    end
    Core.self_call = true
    Core.call(pad, SET_MOTOR, motor, power)
    Core.self_call = false
    Rumble.stats.mod_writes = Rumble.stats.mod_writes + 1
end

function Rumble.flush(now)
    now = now or Core.now()
    local low = strongest(channels[MOTOR.LOW], now)
    local high = strongest(channels[MOTOR.HIGH], now)
    local is_game_active = now - game.time < GAME_HOLD
    if low <= 0 and high <= 0 then
        if was_active then
            was_active = false
            -- Stop what the mod left on; the game re-sends its own power next frame if it still vibrates.
            if not is_game_active then
                send(PAD_MOTOR.ALL, 0.0)
            end
        end
        return
    end
    was_active = true
    local game_low = is_game_active and game.power[MOTOR.LOW] or 0.0
    local game_high = is_game_active and game.power[MOTOR.HIGH] or 0.0
    if Rumble.combined then
        -- Fallback for pads that ignore the separate motor channels: one power on motor All, like the game itself.
        send(PAD_MOTOR.ALL, math.max(low, high, game_low, game_high))
        return
    end
    send(PAD_MOTOR.LOW, math.max(low, game_low))
    send(PAD_MOTOR.HIGH, math.max(high, game_high))
end

function Rumble.stop()
    Rumble.clear()
    was_active = false
    send(PAD_MOTOR.ALL, 0.0)
end

function Rumble.install()
    Core.hook("snow.Pad", "setMotorPower", function(args)
        if Core.self_call then
            return
        end
        local motor = Core.arg_uint(args, 3)
        local power = Core.arg_float(args, 4)
        if motor == PAD_MOTOR.ALL then
            game.power[MOTOR.LOW], game.power[MOTOR.HIGH] = power, power
        elseif motor == PAD_MOTOR.LOW or motor == 0 then
            game.power[MOTOR.LOW] = power
        elseif motor == PAD_MOTOR.HIGH or motor == 1 then
            game.power[MOTOR.HIGH] = power
        end
        game.time = Core.now()
        Rumble.stats.game_writes = Rumble.stats.game_writes + 1
    end)
    -- Write after the game's own vibration update of this frame.
    Rumble.stats.flush_hook = Core.hook("snow.Pad", "update", nil, function(retval)
        pcall(Rumble.flush)
        return retval
    end)
end

HapticBreak.on_start(function()
    Rumble.clear()
end)

-- AdaptiveTrigger ---------------------------------------------------------------------------------------------
-- Rise has no native DualSense support: the pad reaches the game through Steam Input as an XInput pad, so the game
-- cannot drive the triggers. This driver writes the wanted effects to reframework/data/RiseHapticPack_trigger.txt and
-- the plugin reframework/plugins/RiseHapticTrigger.dll sends them to the DualSense over HID (USB or Bluetooth),
-- setting only the trigger bits of the report: Steam keeps rumble, haptics and lights.
-- Effects are { power, frequency, start, end }: power 0..1 resistance, frequency > 0 vibrates, start/end 0..1 travel.
local AdaptiveTrigger = { gain = 1.0, enabled = true }
Drivers.AdaptiveTrigger = AdaptiveTrigger

local FREE = { 0.0, 0.0, 0.0, 1.0 }
AdaptiveTrigger.FREE = FREE
local COMMAND_FILE = "RiseHapticPack_trigger.txt"
local STATUS_FILE = "RiseHapticPack_bridge.txt"
local STATUS_READ = 1.0
local STATUS_STALE = 3.5

local sides = { L = { effect = FREE }, R = { effect = FREE } }
local written = nil -- last command line written (without the sequence number)
local sequence = (os.time() % 100000) * 10
local is_dirty = true
local was_blocked = false
AdaptiveTrigger.stats = { writes = 0, failures = 0 }

-- Plugin status read from its status file: { open, bluetooth, sent, errors, note, ... }, live while its tick moves.
local bridge = { status = {}, is_live = false, last_tick = nil, tick_seen = -10.0, next_read = 0.0 }
AdaptiveTrigger.bridge = bridge

function AdaptiveTrigger.set(side, effect)
    local state = sides[side] or sides.R
    effect = effect or FREE
    if state.effect ~= effect then
        state.effect = effect
        is_dirty = true
    end
end

-- A reused effect table changed (menu slider): write again.
function AdaptiveTrigger.invalidate()
    written = nil
    is_dirty = true
end

function AdaptiveTrigger.sync(effect, index, value)
    if effect[index] ~= value then
        effect[index] = value
        AdaptiveTrigger.invalidate()
    end
end

local function is_free(effect)
    return effect == FREE or (effect[1] or 0) <= 0 and (effect[2] or 0) <= 0
end

local function values(effect)
    if is_free(effect) then
        return 0.0, 0.0, 0.0, 1.0
    end
    return math.min((effect[1] or 0) * AdaptiveTrigger.gain, 1.0), math.min(effect[2] or 0, 1.0), effect[3] or 0,
        effect[4] or 1
end

local function write_command(line)
    local ok, file = pcall(io.open, COMMAND_FILE, "w")
    if not ok or not file then
        AdaptiveTrigger.stats.failures = AdaptiveTrigger.stats.failures + 1
        return false
    end
    sequence = sequence + 1
    file:write(tostring(sequence), " ", line, " end\n")
    file:close()
    AdaptiveTrigger.stats.writes = AdaptiveTrigger.stats.writes + 1
    return true
end

local function read_status(now)
    if now < bridge.next_read then
        return
    end
    bridge.next_read = now + STATUS_READ
    local ok, file = pcall(io.open, STATUS_FILE, "r")
    if not ok or not file then
        bridge.is_live = false
        return
    end
    local text = file:read("a") or ""
    file:close()
    local status = {}
    for key, value in text:gmatch("([%w_]+)=([^\r\n]*)") do
        status[key] = value
    end
    bridge.status = status
    if status.tick ~= bridge.last_tick then
        bridge.last_tick, bridge.tick_seen = status.tick, now
    end
    -- The file stays on disk after the game closes: trust it only while the plugin keeps rewriting it.
    bridge.is_live = now - bridge.tick_seen < STATUS_STALE
end

-- True while the plugin runs and has a DualSense open.
function AdaptiveTrigger.is_available()
    return bridge.is_live and bridge.status.open == "1"
end

function AdaptiveTrigger.update(now)
    read_status(now)
    local is_blocked = HapticBreak.is_blocked(now) or not AdaptiveTrigger.enabled
    if is_blocked ~= was_blocked then
        was_blocked = is_blocked
        is_dirty = true
    end
    if not is_dirty then
        return
    end
    is_dirty = false
    local left = is_blocked and FREE or sides.L.effect
    local right = is_blocked and FREE or sides.R.effect
    local rp, rf, rs, re_ = values(right)
    local lp, lf, ls, le = values(left)
    local line = string.format("%.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f", rp, rf, rs, re_, lp, lf, ls, le)
    if line ~= written then
        if write_command(line) then
            written = line
        else
            is_dirty = true
        end
    end
end

function AdaptiveTrigger.release()
    sides.L.effect, sides.R.effect = FREE, FREE
    is_dirty = true
end

-- Frees both triggers at once (script reset, mod disabled).
function AdaptiveTrigger.free_now()
    AdaptiveTrigger.release()
    written = nil
    write_command("0 0 0 1 0 0 0 1")
end

function AdaptiveTrigger.current(side)
    return (sides[side] or sides.R).effect
end

HapticBreak.on_start(function()
    is_dirty = true
end)

return Drivers
