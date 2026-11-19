-- Hunting Horn (snow.player.Horn). A song added to the queue (snow.player.Horn.setMusic): R2 piano-key click and a
-- two-note rumble. Infernal Melody gauge full: rumble. Heavy hits.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")
local Common = require("RiseHapticPack.weapons.common")

local AdaptiveTrigger = Drivers.AdaptiveTrigger
local LOW, HIGH = Patterns.LOW, Patterns.HIGH
local FREE = Patterns.TRIGGER.FREE

local HuntingHorn = { label = "Hunting Horn" }

HuntingHorn.TUNING = Common.hit_tuning({
    gain = 1.0,
    trigger_enabled = true,
    click_force = 0.55,
    click_time = 0.09,
}, 0.45, 0.10)

-- stylua: ignore
HuntingHorn.PATTERN = {
    song = { { 0.30, 0.06, HIGH, 0.00 }, { 0.40, 0.08, HIGH, 0.09 } },
    gauge_full = { { 0.40, 0.10, LOW, 0.00 }, { 0.50, 0.10, HIGH, 0.12 }, { 0.30, 0.16, LOW, 0.24 } },
}

local CLICK_TRIGGER = { 0.55, 0.0, 0.30, 0.55 }

local state = Patterns.new_state({ songs = 0 })
local steps = Patterns.TriggerSteps.new()
local hook = { installed = false, master = nil, pending = 0 }

local function install()
    if hook.installed then
        return
    end
    hook.installed = true
    Core.hook("snow.player.Horn", "setMusic", function(args)
        if hook.master and (sdk.to_int64(args[2]) or 0) == hook.master then
            hook.pending = hook.pending + 1
        end
    end)
end

local gauge_max = nil

local function revolt_max()
    if gauge_max == nil then
        local td = Core.type("snow.player.Horn")
        local ok, value = pcall(function()
            return td:get_field("RevoltGuageMax"):get_data(nil)
        end)
        gauge_max = ok and tonumber(value) or false
    end
    return gauge_max or nil
end

function HuntingHorn.status()
    return string.format("songs %d  gauge %.0f / %s", state.songs, state.gauge or 0, tostring(revolt_max()))
end

function HuntingHorn.update(context)
    local tuning, player, now = HuntingHorn.TUNING, context.player, context.now
    if Patterns.begin(state, context) then
        hook.pending = 0
    end
    install()
    hook.master = Core.address(player)
    if hook.pending > 0 then
        hook.pending = 0
        state.songs = state.songs + 1
        Patterns.play(HuntingHorn.PATTERN.song, tuning.gain)
        steps:kick(now, CLICK_TRIGGER, tuning.click_time)
    end
    state.gauge = Core.num(player, "<RevoltGuage>k__BackingField") or 0
    local maximum = revolt_max()
    if maximum and Patterns.rose(state, "gauge_full", state.gauge >= maximum and 1 or 0) then
        Patterns.play(HuntingHorn.PATTERN.gauge_full, tuning.gain)
    end
    Common.hit(state, context, tuning)
    AdaptiveTrigger.sync(CLICK_TRIGGER, 1, tuning.click_force)
    AdaptiveTrigger.set("R", tuning.trigger_enabled and steps:effect(now) or FREE)
end

return HuntingHorn
