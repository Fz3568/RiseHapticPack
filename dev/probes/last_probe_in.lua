-- id: 13
local fsm = sdk.find_type_definition("via.motion.MotionFsm2")
out("MotionFsm2 is BehaviorTree:", fsm:is_a("via.behaviortree.BehaviorTree"), "parent:", fsm:get_parent_type():get_full_name())
local gpd = sdk.find_type_definition("via.hid.GamePadDevice")
out("AnalogR:", gpd:get_method("get_AnalogR") ~= nil, "DualSense is GamePadDevice:", sdk.find_type_definition("via.hid.DualSenseDevice"):is_a("via.hid.GamePadDevice"))
local pu = sdk.find_type_definition("snow.Pad"):get_method("update")
out("snow.Pad.update:", pu ~= nil)
