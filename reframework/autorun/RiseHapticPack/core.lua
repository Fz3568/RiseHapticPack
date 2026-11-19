-- Every call into Monster Hunter Rise goes through here. Functions never throw: they return nil/false on failure.
-- Names were read from the live game (REFramework v1.5.9, Rise + Sunbreak) on 2026-11-18.
local Core = {}

-- True while the mod calls a hooked game method itself (hooks skip the mod's own calls).
Core.self_call = false

local type_cache = {}

function Core.type(name)
    local td = type_cache[name]
    if td == nil then
        td = sdk.find_type_definition(name) or false
        type_cache[name] = td
    end
    return td or nil
end

-- obj:call(signature, ...) without throwing.
function Core.call(obj, signature, ...)
    if not obj then
        return nil
    end
    local ok, result = pcall(obj.call, obj, signature, ...)
    if ok then
        return result
    end
    return nil
end

function Core.field(obj, name)
    if not obj then
        return nil
    end
    local ok, value = pcall(obj.get_field, obj, name)
    if ok then
        return value
    end
    return nil
end

function Core.to_number(value)
    if type(value) == "boolean" then
        return value and 1 or 0
    end
    return tonumber(value)
end

-- Field read as a number (booleans: 1 / 0).
function Core.num(obj, name)
    return Core.to_number(Core.field(obj, name))
end

function Core.address(obj)
    if not obj then
        return nil
    end
    local ok, address = pcall(obj.get_address, obj)
    if ok then
        return address
    end
    return nil
end

function Core.type_name(obj)
    if not obj then
        return ""
    end
    local ok, name = pcall(function()
        return obj:get_type_definition():get_full_name()
    end)
    return ok and name or ""
end

local uptime_method = nil
local last_uptime = 0.0

-- Game uptime in seconds (via.Application.get_UpTimeSecond).
function Core.now()
    if uptime_method == nil then
        local td = Core.type("via.Application")
        uptime_method = td and td:get_method("get_UpTimeSecond") or false
    end
    if not uptime_method then
        return os.clock()
    end
    local ok, value = pcall(uptime_method.call, uptime_method, nil)
    if ok and type(value) == "number" then
        last_uptime = value
    end
    return last_uptime
end

-- Managers are recreated between scenes: cached for one second only.
local singleton_cache = {}

function Core.singleton(name)
    local clock = os.clock()
    local entry = singleton_cache[name]
    if entry and entry.object and clock < entry.expires then
        return entry.object
    end
    local ok, object = pcall(sdk.get_managed_singleton, name)
    entry = entry or {}
    entry.object, entry.expires = ok and object or nil, clock + 1.0
    singleton_cache[name] = entry
    return entry.object
end

local enum_cache = {}

-- { name = value } of a game enum, cached.
function Core.enum(type_name)
    local values = enum_cache[type_name]
    if values then
        return values
    end
    values = {}
    local td = Core.type(type_name)
    if td then
        for _, f in ipairs(td:get_fields() or {}) do
            if f:is_static() then
                local ok, value = pcall(f.get_data, f, nil)
                if ok and type(value) == "number" then
                    values[f:get_name()] = value
                end
            end
        end
    end
    enum_cache[type_name] = values
    return values
end

function Core.enum_name(type_name, value)
    for name, v in pairs(Core.enum(type_name)) do
        if v == value then
            return name
        end
    end
    return nil
end

Core.hook_errors = {}

-- Hooks fire for every hunter in co-op: filter the local player inside `pre`. `pre` never lets an error escape.
function Core.hook(type_name, method_name, pre, post)
    local td = Core.type(type_name)
    local method = td and td:get_method(method_name)
    if not method then
        Core.hook_errors[#Core.hook_errors + 1] = "missing " .. type_name .. "." .. method_name
        return false
    end
    local guarded = function(args)
        if pre then
            pcall(pre, args)
        end
    end
    local ok, err = pcall(sdk.hook, method, guarded, post or function(retval)
        return retval
    end)
    if not ok then
        Core.hook_errors[#Core.hook_errors + 1] = type_name .. "." .. method_name .. ": " .. tostring(err)
    end
    return ok
end

function Core.arg_uint(args, index)
    return (sdk.to_int64(args[index]) or 0) & 0xFFFFFFFF
end

function Core.arg_float(args, index)
    local ok, value = pcall(sdk.to_float, args[index])
    return ok and value or 0.0
end

-- Player -------------------------------------------------------------------------------------------------------

-- Local hunter (snow.player.PlayerBase subclass: the weapon class itself in a quest, PlayerLobbyBase in the village).
function Core.master_player()
    return Core.call(Core.singleton("snow.player.PlayerManager"), "findMasterPlayer")
end

local WEAPON_BY_TYPE = {
    ["snow.player.GreatSword"] = "gs",
    ["snow.player.ShortSword"] = "sns",
    ["snow.player.DualBlades"] = "db",
    ["snow.player.LongSword"] = "ls",
    ["snow.player.Hammer"] = "hammer",
    ["snow.player.Horn"] = "hh",
    ["snow.player.Lance"] = "lance",
    ["snow.player.GunLance"] = "gl",
    ["snow.player.SlashAxe"] = "sa",
    ["snow.player.ChargeAxe"] = "cb",
    ["snow.player.InsectGlaive"] = "ig",
    ["snow.player.Bow"] = "bow",
    ["snow.player.HeavyBowgun"] = "hbg",
    ["snow.player.LightBowgun"] = "lbg",
}

local kind_cache = { address = nil, kind = nil }

-- Weapon key ("ls", "gs"...) from the player's class; nil outside quests / training area.
function Core.weapon_kind(player)
    local address = Core.address(player)
    if address ~= kind_cache.address then
        kind_cache.address = address
        kind_cache.kind = WEAPON_BY_TYPE[Core.type_name(player)]
    end
    return kind_cache.kind
end

function Core.is_weapon_on(player)
    return Core.call(player, "isWeaponOn") == true
end

local ACT_STATUS = nil

-- snow.player.ActStatus tag of the current action ("Guard", "Attack", "Damage", "Escape"...).
function Core.has_status(player, name)
    ACT_STATUS = ACT_STATUS or Core.enum("snow.player.ActStatus")
    local value = ACT_STATUS[name]
    if not value then
        return false
    end
    return Core.call(player, "isActionStatusTag(snow.player.ActStatus)", value) == true
end

local fsm_cache = { address = nil, fsm = nil }

local function motion_fsm(player)
    local address = Core.address(player)
    if address ~= fsm_cache.address then
        fsm_cache.address = address
        local go = Core.call(player, "get_GameObject")
        local ok, fsm = pcall(function()
            return go:call("getComponent(System.Type)", sdk.typeof("via.motion.MotionFsm2"))
        end)
        fsm_cache.fsm = ok and fsm or nil
    end
    return fsm_cache.fsm
end

-- Name of the current motion FSM node (layer 0), e.g. the Long Sword sheathe stance. nil if unknown.
function Core.node_name(player, layer)
    return Core.call(motion_fsm(player), "getCurrentNodeName(System.UInt32)", layer or 0)
end

-- Hash of the current node name: tells "the action changed" cheaply.
function Core.node_hash(player, layer)
    return Core.call(motion_fsm(player), "getCurrentNodeNameHash(System.UInt32)", layer or 0)
end

-- Gamepad ------------------------------------------------------------------------------------------------------

local GAMEPAD = "via.hid.GamePad"

local function gamepad_call(signature, ...)
    local td = Core.type(GAMEPAD)
    local native = sdk.get_native_singleton(GAMEPAD)
    if not (td and native) then
        return nil
    end
    local ok, result = pcall(sdk.call_native_func, native, td, signature, ...)
    if ok then
        return result
    end
    return nil
end

-- Merged device the game reads input from.
function Core.main_device()
    return gamepad_call("get_Device")
end

-- R2 / RT travel, 0..1.
function Core.analog_r()
    local value = Core.call(Core.main_device(), "get_AnalogR")
    if type(value) ~= "number" then
        return 0.0
    end
    return value
end

local device_cache = { next_scan = 0.0, kind = nil }

-- via.hid.DeviceKindDetails name of the last input device, refreshed every 2 s. With Steam Input (needed: Rise has
-- no native DualSense support) this is "WindowsXInput" even for a DualSense.
function Core.device_kind(now)
    if now < device_cache.next_scan then
        return device_cache.kind
    end
    device_cache.next_scan = now + 2.0
    local details = Core.call(gamepad_call("get_LastInputDevice"), "get_DeviceKindDetails")
    device_cache.kind = details and Core.enum_name("via.hid.DeviceKindDetails", details) or nil
    return device_cache.kind
end

return Core
