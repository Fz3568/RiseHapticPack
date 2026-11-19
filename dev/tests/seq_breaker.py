"""Compile every Lua file of the mod and run it against a fake Rise (stub sdk / re / imgui) for a few frames per weapon.
Usage: py -I smoke_test.py <autorun dir>
"""
import os
import sys

from lupa import lua54

AUTORUN = os.path.abspath(sys.argv[1])

STUBS = r"""
local AUTORUN = ...
package.path = AUTORUN .. "/?.lua;" .. package.path

LOG = {}
log = { info = function(m) LOG[#LOG + 1] = tostring(m) end }
json = { load_file = function() return nil end, dump_file = function() return true end }
local frame_fns, draw_fns, hooks = {}, {}, {}
HOOKS = hooks
re = {
  on_frame = function(f) frame_fns[#frame_fns + 1] = f end,
  on_draw_ui = function(f) draw_fns[#draw_fns + 1] = f end,
  on_script_reset = function(f) end,
}
imgui = setmetatable({
  tree_node = function() return true end,
  checkbox = function(_, v) return false, v end,
  slider_float = function(_, v) return false, v end,
  button = function() return false end,
}, { __index = function() return function() end end })

UPTIME = 100.0
TRIGGER_LINES = {}
local real_open = io.open
io.open = function(name, mode)
  if name == "RiseHapticPack_trigger.txt" then
    return { write = function(self, ...) local t = {...}; TRIGGER_LINES[#TRIGGER_LINES + 1] = string.format("%.2f ", UPTIME) .. table.concat(t) end, close = function() end }
  end
  return real_open(name, mode)
end
SENT_TRIGGERS, MOTOR_WRITES = {}, {}

local ENUMS = {
  ["snow.player.ActStatus"] = { Guard = 1032510341, Damage = 2010177820, Attack = 3124057592 },
  ["via.hid.DeviceKindDetails"] = { DualSense = 8, WindowsXInput = 12 },
}

local function fake_method(type_name, name)
  return {
    call = function(self, obj, ...)
      if type_name == "via.Application" and name == "get_UpTimeSecond" then return UPTIME end
      return nil
    end,
  }
end

local function fake_td(name)
  return {
    get_full_name = function() return name end,
    get_method = function(_, m) return fake_method(name, m) end,
    get_field = function(_, f)
      return { get_data = function() return 100.0 end }
    end,
    get_fields = function()
      local list = {}
      for k, v in pairs(ENUMS[name] or {}) do
        list[#list + 1] = { is_static = function() return true end, get_data = function() return v end,
          get_name = function() return k end }
      end
      return list
    end,
    is_a = function(_, other)
      local other_name = type(other) == "string" and other or other.get_full_name()
      return name == other_name or (name == "via.hid.VendorNativeDualSenseDevice" and other_name == "via.hid.DualSenseDevice")
    end,
  }
end

local function object(type_name, address, fields, calls)
  local o = { fields = fields or {}, calls = calls or {} }
  function o:get_type_definition() return fake_td(type_name) end
  function o:get_address() return address end
  function o:get_field(n) return self.fields[n] end
  function o:call(sig, ...)
    local handler = self.calls[sig]
    if type(handler) == "function" then return handler(...) end
    return handler
  end
  return o
end
OBJECT = object

DEVICE = object("via.hid.VendorNativeDualSenseDevice", 0x9000, {}, {})
DEVICE.calls["setAdaptiveTriggerFeedback(via.hid.AdaptiveTriggerMotor, System.Single, System.Single, System.Single, System.Single)"] =
  function(motor, p, f, s, e) SENT_TRIGGERS[#SENT_TRIGGERS + 1] = { motor, p, f, s, e } end
DEVICE.calls["resetAdaptiveTriggerFeedback"] = function() SENT_TRIGGERS[#SENT_TRIGGERS + 1] = { "reset" } end
DEVICE.calls["get_AnalogR"] = function() return R2 or 0.0 end
DEVICE.calls["get_DeviceKindDetails"] = 8

PAD = object("snow.Pad", 0x8000, {}, {})
PAD.calls["setMotorPower(via.hid.GamePadMotor, System.Single)"] = function(m, p)
  MOTOR_WRITES[#MOTOR_WRITES + 1] = { m, p }
  if hooks[1] then hooks[1].pre({ 0, PAD, m, p }) end
end

PLAYER = nil
PM = object("snow.player.PlayerManager", 0x7000, {}, { findMasterPlayer = function() return PLAYER end })

sdk = {
  find_type_definition = function(name) return fake_td(name) end,
  get_managed_singleton = function(name)
    if name == "snow.Pad" then return PAD end
    if name == "snow.player.PlayerManager" then return PM end
    return nil
  end,
  get_native_singleton = function(name) return name == "via.hid.GamePad" and {} or nil end,
  call_native_func = function(native, td, sig, ...)
    if sig == "getConnectingDevicesCount" then return 1 end
    if sig == "getConnectingDevices(System.UInt32)" then return DEVICE end
    if sig == "get_Device" or sig == "get_LastInputDevice" then return DEVICE end
    return nil
  end,
  hook = function(method, pre, post)
    -- methods are fake tables: identify them by the order they were created is not possible, so tag via debug
    hooks[#hooks + 1] = { pre = pre, post = post }
  end,
  to_int64 = function(x) if type(x) == "table" then return x:get_address() end return x end,
  to_float = function(x) return x end,
  typeof = function(n) return n end,
}

function RUN_FRAME()
  UPTIME = UPTIME + 1 / 60
  for _, f in ipairs(frame_fns) do f() end
end
function RUN_DRAW() for _, f in ipairs(draw_fns) do f() end end
"""


def main():
    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    # 1. Compile every file.
    failures = 0
    for root, _, files in os.walk(AUTORUN):
        for name in files:
            if name.endswith(".lua"):
                path = os.path.join(root, name)
                with open(path, "r", encoding="utf-8") as handle:
                    source = handle.read()
                result = lua.eval("function(src, name) local f, e = load(src, '=' .. name, 't'); return e end")(source, name)
                if result:
                    failures += 1
                    print("COMPILE ERROR", result)
    print("compile failures:", failures)
    if failures:
        sys.exit(1)

    # 2. Smoke run.
    lua.execute(STUBS, AUTORUN.replace("\\", "/"))
    lua.execute('dofile(package.path:match("^(.-)%?%.lua") .. "RiseHapticPack.lua")')
    lua.execute(r"""
    -- The real sdk.hook gets method objects; identify hooks by order is fragile, so give the rumble hooks names:
    -- Rumble.install hooks setMotorPower first, then update.
    """)
    weapons = {
        "snow.player.LongSword": ("_LongSwordGaugeLv", "_LongSwordGauge"),
        "snow.player.GreatSword": ("_TameLv", "_tameTimer"),
        "snow.player.ShortSword": ("_IsShouryuCounter", None),
        "snow.player.DualBlades": (None, None),
        "snow.player.Hammer": ("<NowChargeLevel>k__BackingField", "_ChargeTimer"),
        "snow.player.Horn": ("<RevoltGuage>k__BackingField", None),
        "snow.player.Lance": ("_IsChargePowerUp", "_ChargeTime"),
        "snow.player.GunLance": ("<ShotChargeLv>k__BackingField", None),
        "snow.player.SlashAxe": ("_weaponOwnMode", "_BottleGauge"),
        "snow.player.ChargeAxe": ("<ChargedBottleNum>k__BackingField", "_weaponOwnMode"),
        "snow.player.InsectGlaive": ("_RedExtractiveTime", "_WhiteExtractiveTime"),
        "snow.player.Bow": ("<ChargeLv>k__BackingField", "_ChargeTimer"),
        "snow.player.HeavyBowgun": ("_MachineGunFireCount", "_ShotChargeLv"),
        "snow.player.LightBowgun": ("_RapidCount", "<IsFullAutoShooting>k__BackingField"),
    }
    address = 0x1000
    for type_name, (level_field, timer_field) in weapons.items():
        address += 0x100
        lua.execute(
            r"""
            local type_name, address, level_field, timer_field = ...
            local fields = {}
            local node = "Normal.Idle"
            PLAYER = OBJECT(type_name, address, fields, {
              isWeaponOn = true,
              ["isActionStatusTag(snow.player.ActStatus)"] = function(v) return v == 1032510341 and GUARDING end,
              get_GameObject = OBJECT("via.GameObject", address + 1, {}, {
                ["getComponent(System.Type)"] = OBJECT("via.motion.MotionFsm2", address + 2, {}, {
                  ["getCurrentNodeName(System.UInt32)"] = function() return node end,
                  ["getCurrentNodeNameHash(System.UInt32)"] = function() return #node end,
                }),
              }),
              isKijin = function() return (UPTIME * 10) % 20 > 10 end,
              isBottleAwake = function() return UPTIME > 103 end,
              isGetAllExtractive = function() return UPTIME > 103 end,
              isSwordBuff = false, isShieldBuff = false,
            })
            local function SEQ(f)
              -- A: normal Spirit Breaker combo
              if f <= 20 then return "wait.main" end
              if f < 50 then return "atk.atk_106.atk_106.o" end
              if f < 90 then return "atk.atk_107.atk_107" end
              if f < 106 then return "atk.atk_107.atk_317a" end
              if f < 140 then return "atk.atk_107.atk_316" end
              if f < 167 then return "atk.atk_111.atk_111.new state 4FAA0952" end
              if f < 230 then return "atk.atk_112.atk_112.new state 9BAB8272" end
              if f < 250 then return "wait.main" end
              -- B: Iai stance -> Iai Spirit Slash success -> 3rd hit -> final hit
              if f < 290 then return "atk.atk151.atk_156_A" end
              if f < 305 then return "atk.atk151.atk_156_B" end
              if f < 323 then return "atk.atk151.atk_155.new state 277A1BD6" end
              if f < 325 then return "atk.atk151.atk_155.成否" end
              if f < 350 then return "atk.atk151.atk_155.success" end
              if f < 351 then return "atk.atk_107.Branch_B1" end
              if f < 352 then return "atk.atk_107.Branch_L" end
              if f < 368 then return "atk.atk_107.atk_317b" end
              if f < 400 then return "atk.atk_107.atk_315" end
              if f < 427 then return "atk.atk_111.atk_111.new state 4FAA0952" end
              if f < 490 then return "atk.atk_112.atk_112.new state 9BAB8272" end
              if f < 510 then return "wait.main" end
              -- C: Iai success -> regular Spirit Blade III
              if f < 530 then return "atk.atk151.atk_155.success" end
              if f < 531 then return "atk.atk_107.Branch_B1" end
              if f < 580 then return "atk.atk_108.atk_108.new state 22863B5D" end
              return "wait.main"
            end
            for frame = 1, 600 do
              if level_field then fields[level_field] = 1 end
              if timer_field then fields[timer_field] = (frame % 120 < 80) and frame or 0 end
              local n = SEQ(frame); R2 = (n:find('atk_156_A') or n:find('atk_10[6789]') or n:find('atk_31') or n:find('atk_112')) and 1.0 or 0.0
              if frame % 30 == 1 then
                local f = io.open("RiseHapticPack_bridge.txt", "w")
                f:write("version=0.1.0\nopen=1\nnote=DualSense open (USB)\nsent=1\nerrors=0\ntick=" .. frame .. "\n")
                f:close()
              end
              GUARDING = frame > 200 and frame < 260
              node = SEQ(frame)
              RUN_FRAME()
              -- snow.Pad.update post hook (rumble flush) is the 2nd hook installed.
              if HOOKS[2] and HOOKS[2].post then HOOKS[2].post(nil) end
              -- Every 45 frames: fire every hook's pre with this hunter (hits, damage reactions, guard, setMusic).
              if false then
                for index = 3, #HOOKS do
                  if HOOKS[index].pre then HOOKS[index].pre({ 0, PLAYER, 1, 0.5 }) end
                end
              end
            end
            RUN_DRAW()
            """,
            type_name, address, level_field, timer_field,
        )
    errors = lua.eval("(function() local s = '' ; return s end)()")
    for line in lua.eval("TRIGGER_LINES").values():
        t = float(line.split()[0])
        if 100.0 <= t <= 110.0:
            print("TRIG", line.strip())
    status = lua.eval("package.loaded['RiseHapticPack.menu'] and true")
    print("menu loaded:", status)
    print("log:", list(lua.eval("LOG").values()))
    print("trigger sends:", len(lua.eval("SENT_TRIGGERS")))
    print("motor writes (direct):", len(lua.eval("MOTOR_WRITES")))
    print("hooks installed:", len(lua.eval("HOOKS")))
    # Error counter lives in the main chunk's local `status`; expose via menu draw is not possible, so re-run a frame
    # with a probe: the main script records errors into status.error_count which the menu prints via imgui.text.
    texts = []
    lua.globals().imgui["text_colored"] = lambda t, c=None: texts.append(t)
    lua.execute("RUN_DRAW()")
    print("menu error lines:", texts)
    stats = lua.eval("package.loaded['RiseHapticPack.drivers'].AdaptiveTrigger.stats")
    print("trigger command writes:", stats["writes"], "failures:", stats["failures"])
    print("bridge available:", lua.eval("package.loaded['RiseHapticPack.drivers'].AdaptiveTrigger.is_available()"))
    print("LS counts:", dict(lua.eval("package.loaded['RiseHapticPack.weapons.long_sword'].counts").items()))
    print("hit sources:", dict(lua.eval("package.loaded['RiseHapticPack.patterns'].Hits.sources").items()))
    with open("RiseHapticPack_trigger.txt", encoding="utf-8") as handle:
        print("last command line:", handle.read().strip())



def trace_main():
    main()
trace_main()
