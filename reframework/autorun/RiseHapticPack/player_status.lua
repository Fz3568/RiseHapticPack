-- What monsters do to the hunter -> one state -> its rumble. A hit reaction also starts a HapticBreak: weapon rumble
-- goes quiet and the triggers go free until the hunter is out of the damage action.
-- Rise picks the reaction in snow.player.PlayerQuestBase.judgeDamageReaction*: one hook per reaction.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")

local HapticBreak = Drivers.HapticBreak
local LOW, HIGH = Patterns.LOW, Patterns.HIGH

local PlayerStatus = {}

-- Rise already rumbles when you are hit: these sit on top, so they start lighter than the Wilds defaults.
PlayerStatus.TUNING = {
    enabled = true,
    gain = 0.6,
    free_triggers_when_hit = true,
    reaction_grace = 0.30, -- no damage action by then (hyper armor, Flinch Free): end the break
    maximum_break = 8.0,
}
local TUNING = PlayerStatus.TUNING

-- stylua: ignore
PlayerStatus.PATTERN = {
    flinch = { { 0.30, 0.10, LOW, 0.00 } },
    knockback = { { 0.45, 0.14, LOW, 0.00 } },
    grabbed = { { 0.40, 0.12, LOW, 0.00 }, { 0.25, 0.12, LOW, 0.30 }, { 0.25, 0.12, LOW, 0.60 } },
    roar = { { 0.25, 0.40, LOW, 0.00 } },
    wind = { { 0.15, 0.20, LOW, 0.00 }, { 0.22, 0.20, LOW, 0.20 }, { 0.12, 0.20, LOW, 0.40 } },
    quake = { { 0.30, 0.08, LOW, 0.00 }, { 0.20, 0.08, LOW, 0.12 }, { 0.12, 0.08, LOW, 0.24 } },
    status_effect = { { 0.35, 0.12, LOW, 0.00 } },
    guard_small = { { 0.35, 0.06, LOW, 0.00 }, { 0.22, 0.06, LOW, 0.06 }, { 0.12, 0.08, LOW, 0.12 } },
    guard_medium = { { 0.50, 0.07, LOW, 0.00 }, { 0.32, 0.07, LOW, 0.07 }, { 0.16, 0.10, LOW, 0.14 } },
    guard_large = {
        { 0.70, 0.08, LOW, 0.00 }, { 0.45, 0.08, LOW, 0.08 }, { 0.25, 0.10, LOW, 0.16 }, { 0.12, 0.12, LOW, 0.26 },
    },
}

local STATE_BY_METHOD = {
    judgeDagameReactionNormalDetail = "flinch",
    judgeDamageReactionFlySmallFB = "knockback",
    judgeDamageReactionKnockBack = "knockback",
    judgeDamageReactionFallDown = "knockback",
    judgeDamageReactionSmash = "knockback",
    judgeDamageReactionSmashDown = "knockback",
    judgeDamageReactionSmashDownSp = "knockback",
    judgeDamageReactionSmashDownNoEscape = "knockback",
    judgeDamageReactionUpper = "knockback",
    judgeDamageReactionRecoverableUpper = "knockback",
    judgeDamageReactionSlamDown = "knockback",
    judgeDamageReactionPositionRise = "knockback",
    judgeDamageReactionRestraint = "grabbed",
    judgeDamageReactionNoMediationCatchAttack = "grabbed",
    judgeDamageReactionQuake = "quake",
    judgeDamageReactionQuakeIndirect = "quake",
    judgeDamageReactionEar = "roar",
    judgeDamageReactionWindS = "wind",
    judgeDamageReactionWindM = "wind",
    judgeDamageReactionWindL = "wind",
    judgeDamageReactionTrnado = "wind",
    judgeDamageReactionTrnadoAttack = "knockback",
    judgeDamageReactionFlash = "status_effect",
    judgeDamageReactionBeto = "status_effect",
    judgeDamageReactionFrozen = "status_effect",
    judgeDamageReactionFloating = "status_effect",
}

local BREAK_STATES = {
    flinch = true, knockback = true, grabbed = true, roar = true, wind = true, quake = true, status_effect = true,
}

-- snow.player.PlayerDamageDefine.GuardReaction: S = 0, M = 1, L = 2.
local GUARD_STATE = { [0] = "guard_small", [1] = "guard_medium", [2] = "guard_large" }

-- Weapons that override judgeDamageReactionGuard: each one is hooked too (events within 0.1 s are merged).
local GUARD_TYPES = {
    "snow.player.PlayerQuestBase", "snow.player.GreatSword", "snow.player.ShortSword", "snow.player.Lance",
    "snow.player.ChargeAxe",
}

local status = {
    installed = false,
    master_address = nil,
    pending = nil,
    pending_time = -10.0,
    is_recovering = false,
    has_reacted = false,
    recovery_start = 0.0,
    last_state = nil,
    event_count = 0,
}
PlayerStatus.status = status

local function record(state_name)
    local now = Core.now()
    if status.pending and now - status.pending_time < 0.1 then
        return
    end
    status.pending, status.pending_time = state_name, now
end

local function install()
    if status.installed then
        return
    end
    status.installed = true
    for method, state_name in pairs(STATE_BY_METHOD) do
        Core.hook("snow.player.PlayerQuestBase", method, function(args)
            if status.master_address and (sdk.to_int64(args[2]) or 0) == status.master_address then
                record(state_name)
            end
        end)
    end
    for _, type_name in ipairs(GUARD_TYPES) do
        Core.hook(type_name, "judgeDamageReactionGuard", function(args)
            if status.master_address and (sdk.to_int64(args[2]) or 0) == status.master_address then
                record(GUARD_STATE[Core.arg_uint(args, 3)] or "guard_medium")
            end
        end)
    end
end

local function play(state_name)
    local pattern = PlayerStatus.PATTERN[state_name]
    if pattern then
        HapticBreak.unblocked(Patterns.play, pattern, TUNING.gain)
    end
end

-- Ends the break once the hunter has left the damage action (or never entered one within reaction_grace).
local function update_recovery(context)
    if not status.is_recovering then
        return
    end
    local now = context.now
    if not HapticBreak.is_active(now) then
        status.is_recovering = false
        return
    end
    if Core.has_status(context.player, "Damage") then
        status.has_reacted = true
        return
    end
    if status.has_reacted or now - status.recovery_start >= TUNING.reaction_grace then
        status.is_recovering = false
        HapticBreak.reset()
    end
end

-- Every frame before the weapon update. Sets context.player_event (state name this frame, or nil).
function PlayerStatus.update(context)
    context.player_event = nil
    status.master_address = Core.address(context.player)
    if not TUNING.enabled then
        status.pending = nil
        return
    end
    install()
    if status.pending then
        local state_name = status.pending
        status.pending = nil
        status.last_state = state_name
        status.event_count = status.event_count + 1
        context.player_event = state_name
        if BREAK_STATES[state_name] and TUNING.free_triggers_when_hit then
            HapticBreak.start(context.now, TUNING.maximum_break)
            status.is_recovering, status.has_reacted, status.recovery_start = true, false, context.now
        end
        play(state_name)
    end
    update_recovery(context)
end

-- Called with no hunter (village, menus): nothing is pending.
function PlayerStatus.idle()
    status.master_address = nil
    status.pending = nil
    status.is_recovering = false
    HapticBreak.reset()
end

function PlayerStatus.is_guard_event(state_name)
    return state_name == "guard_small" or state_name == "guard_medium" or state_name == "guard_large"
end

return PlayerStatus
