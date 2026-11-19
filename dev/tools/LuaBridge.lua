-- LuaBridge: development helper that lets Lua code be run in the live game without resetting scripts.
-- Twice a second it reads reframework/data/bridge/in.lua. When the first line "-- id: <N>" changes, the
-- file is run once on the game thread and everything passed to out(...) is written to bridge/out.txt
-- (first line "id: <N>"). Errors are written there too.
-- Helpers available to bridge code: out(...), dump_type(name), bridge.on_frame[key] = fn (called every
-- frame until set to nil), bridge.vars (table kept between runs).
local TAG = "[LuaBridge] "
local IN_FILE, OUT_FILE = "bridge/in.lua", "bridge/out.txt"

bridge = bridge or { on_frame = {}, vars = {} }
local last_id = nil
local lines = {}

local function to_s(v)
    if type(v) == "userdata" then
        local ok, s = pcall(function()
            local td = v:get_type_definition()
            return string.format("<%s @%x>", td:get_full_name(), v:get_address())
        end)
        if ok then return s end
    end
    return tostring(v)
end

function out(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = to_s((select(i, ...))) end
    lines[#lines + 1] = table.concat(parts, "\t")
end

-- Fields, methods and parent chain of a type, as readable signatures.
function dump_type(name, with_parents)
    local td = type(name) == "string" and sdk.find_type_definition(name) or name
    if not td then out("type not found: " .. tostring(name)); return end
    while td do
        out("== " .. td:get_full_name())
        for _, f in ipairs(td:get_fields() or {}) do
            local ft = f:get_type()
            out(string.format("  F %s%s %s", f:is_static() and "static " or "",
                ft and ft:get_full_name() or "?", f:get_name()))
        end
        for _, m in ipairs(td:get_methods() or {}) do
            local ps = {}
            local ok = pcall(function()
                for _, p in ipairs(m:get_param_types() or {}) do ps[#ps + 1] = p:get_full_name() end
            end)
            local rt = m:get_return_type()
            out(string.format("  M %s %s(%s)", rt and rt:get_full_name() or "?", m:get_name(),
                ok and table.concat(ps, ", ") or "?"))
        end
        if not with_parents then break end
        td = td:get_parent_type()
        if td and td:get_full_name():find("^System%.") then break end
    end
end

local function write_out(id)
    local f = io.open(OUT_FILE, "wb")
    if not f then log.info(TAG .. "cannot write " .. OUT_FILE); return end
    f:write("id: " .. tostring(id) .. "\n")
    f:write(table.concat(lines, "\n"))
    f:write("\n")
    f:close()
end

local function poll()
    local f = io.open(IN_FILE, "rb")
    if not f then return end
    local src = f:read("a")
    f:close()
    local id = src and src:match("^%-%-%s*id:%s*(%S+)")
    if not id or id == last_id then return end
    last_id = id
    lines = {}
    if type(load) ~= "function" then
        out("ERROR: load() is not available in this Lua environment")
    else
        local chunk, err = load(src, "=bridge", "t")
        if not chunk then
            out("COMPILE ERROR: " .. tostring(err))
        else
            local ok, e = xpcall(chunk, function(m)
                return debug and debug.traceback and debug.traceback(tostring(m), 2) or tostring(m)
            end)
            if not ok then out("RUNTIME ERROR: " .. tostring(e)) end
        end
    end
    write_out(id)
end

local frame = 0
re.on_frame(function()
    frame = frame + 1
    if frame % 30 == 0 then pcall(poll) end
    for key, fn in pairs(bridge.on_frame) do
        local ok, err = pcall(fn)
        if not ok then
            bridge.on_frame[key] = nil
            log.info(TAG .. "on_frame '" .. tostring(key) .. "' removed after error: " .. tostring(err))
        end
    end
end)

log.info(TAG .. "loaded")
