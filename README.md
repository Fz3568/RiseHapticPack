# Rise Haptic Pack

DualSense **adaptive triggers** and extra **rumble patterns** for *Monster Hunter Rise: Sunbreak* on PC, as a
REFramework mod. Version 0.2.0.

Rise has no native DualSense support, so the controller goes through Steam Input and the game can only rumble it. This
mod adds trigger effects by talking to the DualSense directly through a small bundled plugin, while Steam keeps
rumble, haptics and lights.

## Features

**Long Sword** (fully mapped to the game's own move states)

| Move | R2 |
| --- | --- |
| Special Sheathe | free while sheathing; smooth resistance (20–80% of the pull) while holding the stance |
| Iai Slash | free |
| Iai Spirit Slash | light vibrating tension; a successful counter clashes, locks and fades, and the follow-up hits kick R2 |
| Spirit Blade I / II / III | impact, drag and fade, stronger along the combo |
| Spirit Roundslash | the heaviest swing effect |
| Spirit Breaker combo (switch skill) | final hit always; 3rd hit when chained from a successful Iai Spirit Slash |
| Spirit Gauge level up | short pulse |

Every Long Sword trigger effect has its own toggle, and the main ones are shortcuts at the top of the menu.

**Other weapons** (first pass, built from the weapons' gauges and flags)

| Weapon | R2 |
| --- | --- |
| Great Sword | guard weight in the first 20% of the pull; vibrating wall on a blocked hit |
| Sword & Shield, Lance, Gunlance, Charge Blade | shield weight while guarding; vibrating wall on a blocked hit |
| Hammer | wall while charging, a click on each charge level |
| Bow | draw weight while charging, a pulse per charge level, a kick on release |
| Light / Heavy Bowgun | trigger click while aiming, a kick per shot, vibration during rapid / auto fire |
| Dual Blades, Switch Axe, Insect Glaive, Charge Blade | a click on Demon Mode, morphs, Triple Up, phial loads |
| Hunting Horn | a click when a song is queued |

**Rumble** (any controller): charge hums, level-ups, counters, hits and morph patterns per weapon, plus a light
reaction when you are knocked back, roared at, caught in wind or a tremor, or block a hit. While you are reeling
from a hit, weapon rumble goes quiet and the triggers go free.

## Requirements

* Monster Hunter Rise: Sunbreak (Steam, PC)
* [REFramework](https://github.com/praydog/REFramework) for Monster Hunter Rise
* For adaptive triggers: a DualSense or DualSense Edge on USB (tested) or Bluetooth (untested), with **Steam Input
  enabled** for Rise
* Rumble patterns work with any controller the game supports

## Install

Copy the `reframework` folder into the game folder (next to `MonsterHunterRise.exe`) and merge it:

```
reframework/autorun/RiseHapticPack.lua
reframework/autorun/RiseHapticPack/...
reframework/plugins/RiseHapticTrigger.dll
```

Start the game. The plugin loads at startup; the Lua part can be reloaded with REFramework's *Reset scripts*.

To uninstall, delete those files (and `reframework/data/RiseHapticPack*.json|txt` if you want the settings gone).

## Menu

REFramework menu → **Rise Haptic Pack**:

* Enabled, mod rumble strength, adaptive triggers on/off, trigger strength
* Long Sword shortcuts: Spirit Blade I–III, Spirit Roundslash, Spirit Breaker final hit, Spirit Breaker 3rd hit after
  an Iai counter
* Status: whether the trigger plugin has the DualSense open, current weapon, errors
* *Combined motor mode*: try it if **Test rumble** does nothing on your controller
* **Test rumble**, **Test R2 wall**
* *Diagnostics*, *Trigger lab* (play a hand-made R2 effect to find values you like), and *Tuning* (every number and
  toggle per weapon, with reset buttons)

Settings are saved to `reframework/data/RiseHapticPack.json`.

## Notes

* Another program that drives the DualSense triggers at the same time (for example DSX) will fight with this mod.
* The triggers go free while the game window is not in front, and when the game closes.
* The plugin writes a status file, `reframework/data/RiseHapticPack_bridge.txt`, which the menu reads.

## Known limitations

* Weapons other than the Long Sword have not been played through with this version; their effects may need tuning.
* Sacred Sheathe and Foresight Slash have no trigger effects of their own yet.
* Without Steam Input (or without a DualSense) only the rumble part works.

## Building the plugin

`plugin_src/RiseHapticTrigger.c` is plain Win32 C. With MinGW-w64 gcc on `PATH`:

```
plugin_src\build.bat
```

It writes `reframework/plugins/RiseHapticTrigger.dll` (links `setupapi`, `hid`, `cfgmgr32`).

## Credits

* **MHWilds Haptic Pack** (Monster Hunter Wilds) — the overall design this mod follows (drivers, a player-reaction
  layer, per-weapon modules) and several rumble patterns and tuning values.
* **LS Extended DualSense Support** (Monster Hunter Wilds) — the Long Sword adaptive-trigger idea (Iai stance
  resistance, level-up pulse).
* **REFramework** by praydog.

Both Wilds mods belong to their authors; no code from their plugin is used here.

## License

No license has been chosen yet.
