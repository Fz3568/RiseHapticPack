# Rise Haptic Pack — developer notes

Everything learned while porting "MHWilds Haptic Pack 1.3.0" and "LS Extended DualSense Support 2.3" to
Monster Hunter Rise: Sunbreak (REFramework v1.5.9). The two original mods are **not** in this repo (they are other
people's work); only what was learned from them is.

## Layout (dev branch)

| Path | What |
| --- | --- |
| `reframework/autorun/RiseHapticPack.lua`, `RiseHapticPack/` | The mod (Lua). Copy `reframework/` into the game folder. |
| `reframework/plugins/RiseHapticTrigger.dll` | Prebuilt trigger plugin. |
| `plugin_src/RiseHapticTrigger.c`, `build.bat` | Plugin source and build (MinGW-w64 gcc). |
| `dev/tests/` | Offline tests: the whole mod runs against a fake Rise (Python + `lupa`). |
| `dev/c_tests/` | Hardware tests for the plugin (talk to a real DualSense). |
| `dev/tools/LuaBridge.lua` | Live Lua console for a running game (see below). |
| `dev/probes/` | Example LuaBridge probe. |
| `dev/data/` | Long Sword motion graph dump, latest Long Sword trace, Rise type dumps. |
| `reframework/autorun/RiseHapticPack/graph_dump.lua` | Menu button that dumps the loaded motion graph (dev only). |

## Hardware path

* Rise has **no native DualSense support**: the pad must go through Steam Input, so the game sees a
  `WindowsXInput` pad. The engine has `via.hid.DualSenseDevice.setAdaptiveTriggerFeedback(motor, power, frequency,
  start_pos, end_pos)` but it is unusable without a native DualSense.
* Rumble goes through the game: `snow.Pad.setMotorPower(via.hid.GamePadMotor, float)`. The game itself calls it once
  per frame with motor `All` (6) only while one of its 37 presets plays (`snow.Pad.requestVibration(id, isLoop)`), and
  never when idle. The mod hooks it, remembers the game's power, and right after `snow.Pad.update` writes
  `max(game, mod)` to `LowFrequencyMotor` (128) / `HighFrequencyMotor` (129) (or `All` in "combined motor mode").
  Steam Input turns that into DualSense haptics.
* Adaptive triggers go through `RiseHapticTrigger.dll`:
  * Lua writes `reframework/data/RiseHapticPack_trigger.txt`:
    `<seq> <Rpower> <Rfreq> <Rstart> <Rend> <Lpower> <Lfreq> <Lstart> <Lend> end` (all 0..1, written on change).
  * The DLL (plain DLL, worker thread from `DllMain`) polls it every 4 ms and sends DualSense output reports with only
    `valid_flag0 = 0x0C` (right + left trigger effect), so Steam keeps rumble / haptics / lights. USB report `0x02`
    (48 bytes); Bluetooth report `0x31` (78 bytes, CRC32 seeded with `0xA2`).
  * Effect encoding: off `0x05`; resistance zones `0x21`; click (start >= 2, end <= 8, width <= 3 zones) `0x25`;
    vibration `0x26` (frequency = 5 + f * 195 Hz).
  * Active effects are re-sent every 300 ms; triggers go free while the game window is not in front and when the game
    closes.
  * Steam Input hides the pad from the game process: SetupAPI enumeration finds nothing. The DLL also looks it up
    with CfgMgr32 (pass 2, the one that works in game) and the `DeviceClasses` registry key (pass 3), and can open it
    with `ntdll!NtCreateFile`. `HidD_GetPreparsedData` fails there, so the USB report length falls back to 48.
  * Status: `reframework/data/RiseHapticPack_bridge.txt` (key=value, rewritten every second). The menu shows it.

## Rise API used (verified live)

* Player: `snow.player.PlayerManager:findMasterPlayer()`. In a quest the player object **is** the weapon class
  (`snow.player.LongSword`, ...); in the village it is `PlayerLobbyBase` (no weapon module runs).
* `isWeaponOn()`, `isActionStatusTag(snow.player.ActStatus)` (Guard, Damage, ...).
* Motion FSM: GameObject component `via.motion.MotionFsm2` (a `via.behaviortree.BehaviorTree`):
  `getCurrentNodeName(0)`, `getCurrentNodeNameHash(0)`. REFramework bindings for the whole graph:
  `layer:get_tree_object()` → `tree:get_node_count()/get_node(i)` → `node:get_full_name()/get_children()/get_states()`.
* Your hits: `snow.player.PlayerQuestBase.afterCalcDamage_AttackSide` and `calcHitAttackResultForEnemy`.
* Hit reactions: `judgeDamageReaction*` on `PlayerQuestBase` (one per reaction). `judgeDamageReactionGuard` is
  overridden by GreatSword, ShortSword, Lance, ChargeAxe (all hooked).
* `sdk.get_tdb` does not exist in this REFramework build; `get_types_inheriting_from_this()` and
  `method:get_param_names()` do.

## Long Sword node map (from the game's motion graph, `dev/data/longsword_motion_graph.txt`)

| Node | Move |
| --- | --- |
| `atk.atk151.atk_151_A`, `atk_156_A` | sheathing into Special Sheathe (R2 free) |
| `atk_151_B`, `atk_156_B`, `atk_152` | holding the stance (R2 resistance after 0.06 s) |
| `atk_153`, `atk_300`, `atk_305` | leaving the stance / end of a slash |
| `atk_154` | Iai Slash (face button) — R2 free |
| `atk_155` → `成否` → `success` / `faled` | Iai Spirit Slash, counter success / miss |
| `atk_321`, `atk_106` | Spirit Blade I (321 = running lead-in) |
| `atk_107.atk_107`, `atk_107.atk_329` | Spirit Blade II |
| `atk_108` | Spirit Blade III (switch-skill "3段目") |
| `atk_109` | Spirit Roundslash (only from atk_108, Foresight success `atk_147.コマンド`, Sacred Sheathe `atk_161_MR`, "4段目") |
| `*.atk_317a/b` → `atk_315/316` → `atk_111` | Spirit Breaker 3rd hit (switch skill 入れ替えB) |
| `atk_112` | Spirit Breaker final hit |
| `atk_155.success` → `atk_107.Branch_B1` → `Branch_L` → `atk_317a/b` | Iai counter chained into the Spirit Breaker 3rd hit |
| `atk_147` (`成功` child) | Foresight Slash (success) |
| `atk_161_MR` (`カウンター成功/失敗`) | Sacred Sheathe |

Notes: `_IsIaiCounter` and the `iaiCounterSuccess` hook fire during **Sacred Sheathe**, not Special Sheathe.
`createLongSwordShell020` / `createSpacingShell` / `<IsIaiCounterSuccess>` were never seen firing.
Node names of the other 13 weapons are not mapped yet: their modules use weapon fields only (untested in game).

## Workflow

* **Ask before booting the game.**
* Live probing: copy `dev/tools/LuaBridge.lua` to `reframework/autorun`, reset scripts once. Write probes to
  `reframework/data/bridge/in.lua` (first line `-- id: N`, change N to run again); output lands in
  `reframework/data/bridge/out.txt`. Helpers: `out(...)`, `dump_type(name)`, `bridge.on_frame[key]`, `bridge.vars`.
  Remove it from autorun when done.
* Motion graph: menu → "Dump motion graph of the current weapon" (in a quest / training area) →
  `reframework/data/RiseHapticPack_motion_graph.txt`. Query it with
  `py dev/tests/graph_query.py <dump> into|out|children|list <prefix>`.
* Long Sword trace: `reframework/data/RiseHapticPack_ls_trace.txt` (node entries with R2 and Spirit Gauge level,
  Iai and Spirit Breaker events), written while `trace_nodes` is on.

## Tests

From a scratch folder (they write runtime files to the current directory), with Python 3 and `lupa`:

```
py <repo>/dev/tests/smoke_test.py <repo>/reframework/autorun      # compile + 14 weapons x 360 frames
py <repo>/dev/tests/seq_breaker.py <repo>/reframework/autorun     # Spirit Breaker + Iai chain, prints R2 commands
py <repo>/dev/tests/seq_parts.py <repo>/reframework/autorun       # sheathe / stance / Iai Slash / Iai Spirit Slash
```

The `seq_*` files are copies of `smoke_test.py` with a scripted node sequence (`SEQ(frame)`); `TRIG` lines are the
trigger commands sent to the plugin. Hardware: `gcc dev/c_tests/bridge_test.c -lsetupapi -lhid -lcfgmgr32` (R2 wall
for 3 s), `pass_test.c` (each lookup pass), `host_test.c` (loads the DLL like REFramework, needs a
`reframework/data` folder next to the exe).
