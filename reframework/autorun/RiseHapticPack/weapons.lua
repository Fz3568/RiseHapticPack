-- Weapon modules keyed by Core.weapon_kind. Each has label, TUNING (menu), PATTERN, update(context), status().
local Bowgun = require("RiseHapticPack.weapons.bowgun")

return {
    gs = require("RiseHapticPack.weapons.great_sword"),
    sns = require("RiseHapticPack.weapons.sword_and_shield"),
    db = require("RiseHapticPack.weapons.dual_blades"),
    ls = require("RiseHapticPack.weapons.long_sword"),
    hammer = require("RiseHapticPack.weapons.hammer"),
    hh = require("RiseHapticPack.weapons.hunting_horn"),
    lance = require("RiseHapticPack.weapons.lance"),
    gl = require("RiseHapticPack.weapons.gunlance"),
    sa = require("RiseHapticPack.weapons.switch_axe"),
    cb = require("RiseHapticPack.weapons.charge_blade"),
    ig = require("RiseHapticPack.weapons.insect_glaive"),
    bow = require("RiseHapticPack.weapons.bow"),
    hbg = Bowgun.heavy,
    lbg = Bowgun.light,
}
