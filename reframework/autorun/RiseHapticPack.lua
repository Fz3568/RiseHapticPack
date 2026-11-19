-- Rise Haptic Pack 0.2.0
-- DualSense adaptive triggers + extra rumble patterns for Monster Hunter Rise: Sunbreak (REFramework).
-- Inspired by "MHWilds Haptic Pack" and "LS Extended DualSense Support" for Monster Hunter Wilds.
-- Rumble patterns go through the game (Steam Input turns them into DualSense haptics); adaptive triggers go through
-- the bundled plugin reframework/plugins/RiseHapticTrigger.dll, which talks to the DualSense directly because Rise
-- only sees Steam Input's XInput pad.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")
local PlayerStatus = require("RiseHapticPack.player_status")
local Weapons = require("RiseHapticPack.weapons")
local Menu = require("RiseHapticPack.menu")

local Rumble = Drivers.Rumble
local AdaptiveTrigger = Drivers.AdaptiveTrigger
local Hits = Patterns.Hits
local settings = Menu.settings

local status = {
    hardware = "rumble",
    device_kind = nil,
    weapon_kind = nil,
    module = nil,
    error_count = 0,
    last_error = "",
    was_enabled = true,
    player_address = nil,
    test_trigger_until = 0.0,
}

local TEST_TRIGGER = { 1.0, 0.0, 0.0, 1.0 }
-- Adaptive triggers are for these weapon kinds only (Core.weapon_kind: from the hunter's weapon class). Every other
-- weapon keeps its rumble and R2 stays free.
local TRIGGER_WEAPONS = { ls = true }
local context = { now = 0.0, player = nil, kind = nil, hardware = "rumble", r2 = 0.0, hits = 0, player_event = nil }

local function record_error(ok, message)
    if not ok then
        status.error_count = status.error_count + 1
        status.last_error = tostring(message)
    end
end

local function on_frame()
    local now = Core.now()
    Menu.save_if_changed(now)
    status.device_kind = Core.device_kind(now)
    status.hardware = AdaptiveTrigger.is_available() and "dualsense" or "rumble"

    if not settings.enabled then
        if status.was_enabled then
            status.was_enabled = false
            Rumble.stop()
            AdaptiveTrigger.release()
            PlayerStatus.idle()
        end
        AdaptiveTrigger.update(now)
        return
    end
    status.was_enabled = true

    local player = Core.master_player()
    local kind = player and Core.weapon_kind(player) or nil
    local module = kind and Weapons[kind] or nil
    local address = Core.address(player)
    if module ~= status.module or address ~= status.player_address then
        -- Weapon or hunter object changed: the old weapon no longer runs, free what it stiffened.
        AdaptiveTrigger.release()
        Patterns.ActionRumble.owner = nil
        Hits.take()
    end
    status.module, status.weapon_kind, status.player_address = module, kind, address
    Hits.master_address = module and address or nil

    if module then
        context.now, context.player, context.kind, context.hardware = now, player, kind, status.hardware
        context.r2 = Core.analog_r()
        context.hits = Hits.take()
        PlayerStatus.update(context)
        Patterns.ActionRumble.update(context)
        record_error(pcall(module.update, context))
        if not TRIGGER_WEAPONS[kind] then
            AdaptiveTrigger.set("R", AdaptiveTrigger.FREE)
            AdaptiveTrigger.set("L", AdaptiveTrigger.FREE)
        end
    else
        PlayerStatus.idle()
        AdaptiveTrigger.set("R", AdaptiveTrigger.FREE)
        AdaptiveTrigger.set("L", AdaptiveTrigger.FREE)
    end

    local lab = Menu.lab_effect()
    if lab then
        AdaptiveTrigger.set("R", lab)
    elseif now < status.test_trigger_until then
        AdaptiveTrigger.set("R", TEST_TRIGGER)
    end
    AdaptiveTrigger.update(now)
    if not Rumble.stats.flush_hook then
        Rumble.flush(now)
    end
end

Menu.load(Weapons)
Rumble.install()
Hits.install()
-- A command left by a previous session (crash, reset mid-effect) must not keep a trigger stiff.
AdaptiveTrigger.free_now()

re.on_frame(function()
    record_error(pcall(on_frame))
end)

re.on_draw_ui(function()
    record_error(pcall(Menu.draw, status))
end)

re.on_script_reset(function()
    pcall(Rumble.stop)
    pcall(AdaptiveTrigger.free_now)
end)

log.info("[RiseHapticPack] loaded")
