-- REFramework menu: on/off, strengths, status, trigger lab and per-weapon tuning. Saved to
-- reframework/data/RiseHapticPack.json.
local Core = require("RiseHapticPack.core")
local Drivers = require("RiseHapticPack.drivers")
local Patterns = require("RiseHapticPack.patterns")
local PlayerStatus = require("RiseHapticPack.player_status")
local GraphDump = require("RiseHapticPack.graph_dump")

local Rumble = Drivers.Rumble
local AdaptiveTrigger = Drivers.AdaptiveTrigger

local Menu = {}

local FILE = "RiseHapticPack.json"
local SAVE_DELAY = 0.5

local settings = {
    enabled = true,
    rumble_gain = 1.0,
    trigger_gain = 1.0,
    triggers_enabled = true,
    combined_motors = false,
    tuning = {},
}
Menu.settings = settings

-- Trigger lab: replaces the weapon's R2 effect while on, to find values that feel right.
local lab = { enabled = false, power = 1.0, frequency = 0.0, start = 0.2, finish = 0.8 }
Menu.lab = lab
local lab_effect = { 1.0, 0.0, 0.2, 0.8 }

local modules = {} -- [key] = module with TUNING
local defaults = {}
local is_dirty, last_change = false, 0.0

local function scalar_copy(tuning)
    local copy = {}
    for name, value in pairs(tuning) do
        if type(value) == "number" or type(value) == "boolean" then
            copy[name] = value
        end
    end
    return copy
end

local function apply(tuning, values)
    for name, value in pairs(values or {}) do
        if type(tuning[name]) == type(value) and type(value) ~= "table" then
            tuning[name] = value
        end
    end
end

local function mark_changed()
    is_dirty, last_change = true, Core.now()
end

local function apply_globals()
    Rumble.gain = settings.rumble_gain
    Rumble.combined = settings.combined_motors
    AdaptiveTrigger.gain = settings.trigger_gain
    AdaptiveTrigger.enabled = settings.triggers_enabled
end

-- weapons: { kind = module }; PlayerStatus is tuned under the key "player".
function Menu.load(weapons)
    modules = { player = PlayerStatus }
    for kind, module in pairs(weapons) do
        modules[kind] = module
    end
    local ok, saved = pcall(json.load_file, FILE)
    saved = ok and type(saved) == "table" and saved or {}
    for _, key in ipairs({ "enabled", "rumble_gain", "trigger_gain", "triggers_enabled", "combined_motors" }) do
        if type(saved[key]) == type(settings[key]) then
            settings[key] = saved[key]
        end
    end
    if type(saved.tuning) == "table" then
        settings.tuning = saved.tuning
    end
    for key, module in pairs(modules) do
        defaults[key] = scalar_copy(module.TUNING)
        apply(module.TUNING, settings.tuning[key])
    end
    apply_globals()
end

function Menu.save_if_changed(now)
    if is_dirty and now - last_change >= SAVE_DELAY then
        is_dirty = false
        pcall(json.dump_file, FILE, settings)
    end
end

-- The trigger lab effect, or nil when the lab is off.
function Menu.lab_effect()
    if not lab.enabled then
        return nil
    end
    AdaptiveTrigger.sync(lab_effect, 1, lab.power)
    AdaptiveTrigger.sync(lab_effect, 2, lab.frequency)
    AdaptiveTrigger.sync(lab_effect, 3, lab.start)
    AdaptiveTrigger.sync(lab_effect, 4, lab.finish)
    return lab_effect
end

local function slider(label, holder, key, minimum, maximum)
    local changed, value = imgui.slider_float(label, holder[key], minimum, maximum)
    if changed then
        holder[key] = value
    end
    return changed
end

local function draw_tuning(key, module)
    if not imgui.tree_node((module.label or key) .. "##" .. key) then
        return
    end
    local tuning, changed = module.TUNING, false
    local names = {}
    for name in pairs(defaults[key] or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local value = tuning[name]
        if type(value) == "number" then
            changed = slider(name .. "##" .. key, tuning, name, 0.0, math.max(1.0, defaults[key][name] * 3.0)) or changed
        elseif type(value) == "boolean" then
            local c, v = imgui.checkbox(name .. "##" .. key, value)
            if c then
                tuning[name], changed = v, true
            end
        end
    end
    if imgui.button("Reset to defaults##" .. key) then
        apply(tuning, defaults[key])
        changed = true
    end
    if changed then
        settings.tuning[key] = scalar_copy(tuning)
        AdaptiveTrigger.invalidate()
        mark_changed()
    end
    imgui.tree_pop()
end

local function effect_text(effect)
    return string.format("power %.2f  freq %.2f  %.2f..%.2f", effect[1] or 0, effect[2] or 0, effect[3] or 0, effect[4] or 1)
end

-- status: { hardware, device_kind, weapon_kind, module, error_count, last_error } from the main script.
function Menu.draw(status)
    if not imgui.tree_node("Rise Haptic Pack") then
        return
    end
    local changed, value = imgui.checkbox("Enabled", settings.enabled)
    if changed then
        settings.enabled = value
        mark_changed()
    end
    if slider("Mod rumble strength", settings, "rumble_gain", 0.0, 2.0) then
        apply_globals()
        mark_changed()
    end
    changed, value = imgui.checkbox("DualSense adaptive triggers", settings.triggers_enabled)
    if changed then
        settings.triggers_enabled = value
        apply_globals()
        AdaptiveTrigger.invalidate()
        mark_changed()
    end
    -- Long Sword shortcuts (same values as under Tuning > Long Sword).
    local long_sword = modules.ls
    for _, toggle in ipairs({
        { "spirit_blade_combo_trigger", "Long Sword: adaptive trigger on Spirit Blade I-III" },
        { "spirit_roundslash_trigger", "Long Sword: adaptive trigger on Spirit Roundslash" },
        { "spirit_breaker_final_trigger", "Long Sword: adaptive trigger on Spirit Breaker final hit" },
        { "spirit_breaker_iai_third_trigger", "Long Sword: adaptive trigger on Spirit Breaker 3rd hit after an Iai counter" },
    }) do
        local key = toggle[1]
        if long_sword and type(long_sword.TUNING[key]) == "boolean" then
            local c, v = imgui.checkbox(toggle[2], long_sword.TUNING[key])
            if c then
                long_sword.TUNING[key] = v
                settings.tuning.ls = scalar_copy(long_sword.TUNING)
                AdaptiveTrigger.invalidate()
                mark_changed()
            end
        end
    end
    if slider("Trigger strength", settings, "trigger_gain", 0.0, 1.5) then
        apply_globals()
        AdaptiveTrigger.invalidate()
        mark_changed()
    end

    imgui.text("Controller seen by the game: " .. tostring(status.device_kind or "?") .. " (Steam Input)")
    local bridge = AdaptiveTrigger.bridge
    if status.hardware == "dualsense" then
        imgui.text(string.format("Adaptive triggers: ACTIVE - %s, sent %s, errors %s", tostring(bridge.status.note),
            tostring(bridge.status.sent), tostring(bridge.status.errors)))
    elseif bridge.is_live then
        imgui.text_colored("Adaptive triggers: plugin running, " .. tostring(bridge.status.note) .. " (error "
            .. tostring(bridge.status.last_error) .. ")", 0xFF40C0FF)
    else
        imgui.text_colored("Adaptive triggers: OFF - reframework/plugins/RiseHapticTrigger.dll is not running.", 0xFF40C0FF)
    end
    imgui.text("Weapon: " .. tostring(status.module and status.module.label or "- (village / menus)"))
    if status.module and status.module.status then
        local ok, text = pcall(status.module.status)
        imgui.text("  " .. tostring(ok and text or "?"))
    end
    imgui.text("R2 effect: " .. effect_text(AdaptiveTrigger.current("R")))
    imgui.text(string.format("Last hit reaction: %s (%d)", tostring(PlayerStatus.status.last_state),
        PlayerStatus.status.event_count))
    imgui.text(string.format("Rumble writes: game %d, mod %d%s", Rumble.stats.game_writes, Rumble.stats.mod_writes,
        Rumble.stats.flush_hook and "" or " (frame fallback)"))
    local sources = Patterns.Hits.sources
    imgui.text(string.format("Your hits seen: after-calc %d, result %d, shell-id %d", sources.after_calc,
        sources.result_enemy, sources.shell_hit_id))
    if status.error_count > 0 then
        imgui.text_colored(string.format("Errors: %d, last: %s", status.error_count, status.last_error), 0xFF4040FF)
    end
    for _, message in ipairs(Core.hook_errors) do
        imgui.text_colored("Hook: " .. message, 0xFF4040FF)
    end

    changed, value = imgui.checkbox("Combined motor mode (try if 'Test rumble' does nothing)", settings.combined_motors)
    if changed then
        settings.combined_motors = value
        apply_globals()
        mark_changed()
    end
    if imgui.button("Test rumble") then
        Rumble.body(0.8, 0.3)
    end
    imgui.same_line()
    if imgui.button("Test R2 wall (2 s)") then
        status.test_trigger_until = Core.now() + 2.0
    end
    -- Read-only: writes the loaded motion graph of the current weapon to reframework/data.
    if imgui.button("Dump motion graph of the current weapon") then
        local player = Core.master_player()
        if player and status.module then
            local ok, result = pcall(GraphDump.dump, player)
            status.graph_result = ok and result or ("failed: " .. tostring(result))
        else
            status.graph_result = "take the weapon into a quest or the training area first"
        end
    end
    if status.graph_result then
        imgui.text("  " .. status.graph_result)
    end

    if imgui.tree_node("Trigger lab (R2)") then
        local c
        c, lab.enabled = imgui.checkbox("Play this effect on R2 instead of the weapon's", lab.enabled)
        slider("power", lab, "power", 0.0, 1.0)
        slider("frequency", lab, "frequency", 0.0, 1.0)
        slider("start position", lab, "start", 0.0, 1.0)
        slider("end position", lab, "finish", 0.0, 1.0)
        imgui.text(string.format("Effect line: { %.2f, %.2f, %.2f, %.2f }", lab.power, lab.frequency, lab.start, lab.finish))
        imgui.tree_pop()
    end

    if imgui.tree_node("Tuning") then
        draw_tuning("player", PlayerStatus)
        local keys = {}
        for key in pairs(modules) do
            if key ~= "player" then
                keys[#keys + 1] = key
            end
        end
        table.sort(keys, function(a, b)
            return (modules[a].label or a) < (modules[b].label or b)
        end)
        for _, key in ipairs(keys) do
            draw_tuning(key, modules[key])
        end
        imgui.tree_pop()
    end
    imgui.tree_pop()
end

return Menu
