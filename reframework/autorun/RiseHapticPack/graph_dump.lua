-- Dumps the hunter's motion graph (the via.motion.MotionFsm2 behavior tree the game has loaded) to
-- reframework/data/RiseHapticPack_motion_graph.txt: every node with its children and the states it can transition to.
-- It reads the graph only; nothing in the game changes. Used to map node names (atk_107...) to moves.
-- REFramework's behavior-tree bindings are used defensively: what is not available is written to the file instead.
local Core = require("RiseHapticPack.core")

local GraphDump = {}

local FILE = "RiseHapticPack_motion_graph.txt"

local function safe_index(object, key)
    local ok, value = pcall(function()
        return object[key]
    end)
    return ok and value or nil
end

-- Calls object:name(...) if the binding exists; returns ok, result.
local function try(object, name, ...)
    local method = safe_index(object, name)
    if type(method) ~= "function" then
        return false, "no " .. name
    end
    return pcall(method, object, ...)
end

-- Method names visible on a binding (sol keeps them in the metatable or its __index table).
local function binding_keys(object)
    local names, seen = {}, {}
    local function collect(t)
        if type(t) ~= "table" then
            return
        end
        for key in pairs(t) do
            if type(key) == "string" and not seen[key] and key:sub(1, 2) ~= "__" then
                seen[key] = true
                names[#names + 1] = key
            end
        end
    end
    local mt = getmetatable(object)
    if type(mt) == "table" then
        collect(mt)
        collect(rawget(mt, "__index"))
    end
    table.sort(names)
    return table.concat(names, " ")
end

local function node_name(node)
    for _, name in ipairs({ "get_full_name", "get_name" }) do
        local ok, value = try(node, name)
        if ok and type(value) == "string" then
            return value
        end
    end
    return tostring(node)
end

-- A list result (Lua table or game array) of nodes or indices -> names.
local function names_of(list, tree)
    local out = {}
    if type(list) ~= "table" and type(list) ~= "userdata" then
        return out
    end
    local ok = pcall(function()
        for _, item in ipairs(list) do
            if type(item) == "number" and tree then
                local got, node = try(tree, "get_node", item)
                out[#out + 1] = got and node and node_name(node) or ("#" .. item)
            else
                out[#out + 1] = node_name(item)
            end
        end
    end)
    if not ok then
        out[#out + 1] = "?"
    end
    return out
end

local function layer_of(player)
    local game_object = Core.call(player, "get_GameObject")
    local ok, fsm = pcall(function()
        return game_object:call("getComponent(System.Type)", sdk.typeof("via.motion.MotionFsm2"))
    end)
    if not ok or not fsm then
        return nil, "no MotionFsm2 component"
    end
    local layer = Core.call(fsm, "getLayer", 0)
    if not layer then
        return nil, "getLayer(0) failed"
    end
    return layer
end

-- Returns a short result line for the menu.
function GraphDump.dump(player)
    local lines = {}
    local function out(text)
        lines[#lines + 1] = text
    end
    out("# Rise Haptic Pack motion graph dump  " .. os.date("%Y-%m-%d %H:%M:%S"))
    out("# hunter class: " .. Core.type_name(player) .. "   current node: " .. tostring(Core.node_name(player)))
    local layer, err = layer_of(player)
    if not layer then
        return "failed: " .. err
    end
    out("# layer: " .. Core.type_name(layer) .. "  bindings: " .. binding_keys(layer))
    local ok, tree = try(layer, "get_tree_object")
    if not ok or not tree then
        out("# get_tree_object failed: " .. tostring(tree))
    else
        out("# tree bindings: " .. binding_keys(tree))
        local got, count = try(tree, "get_node_count")
        count = got and tonumber(count) or 0
        out("# nodes: " .. count)
        local first_node = nil
        for index = 0, count - 1 do
            local has, node = try(tree, "get_node", index)
            if has and node then
                first_node = first_node or node
                local parts = { string.format("[%d] %s", index, node_name(node)) }
                for _, field in ipairs({ "get_children", "get_states", "get_start_states" }) do
                    local fine, list = try(node, field)
                    if fine and list then
                        local names = names_of(list, tree)
                        if #names > 0 then
                            parts[#parts + 1] = field:sub(5) .. ": " .. table.concat(names, ", ")
                        end
                    end
                end
                out(table.concat(parts, "  |  "))
            end
        end
        if first_node then
            out("# node bindings: " .. binding_keys(first_node))
        end
    end
    local file_ok, file = pcall(io.open, FILE, "w")
    if not file_ok or not file then
        return "failed: cannot write " .. FILE
    end
    file:write(table.concat(lines, "\n"), "\n")
    file:close()
    return string.format("wrote %d lines to reframework/data/%s", #lines, FILE)
end

return GraphDump
