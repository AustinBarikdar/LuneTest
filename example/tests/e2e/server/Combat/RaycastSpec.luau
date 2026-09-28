--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local expect = require(ReplicatedStorage.LuneTest).expect

-- workspace:Raycast only exists in the real engine, so this spec falls back to Studio.
return {
	["ray into empty space hits nothing"] = function()
		expect(workspace:Raycast(Vector3.new(0, 500, 0), Vector3.new(0, 10, 0))).toBeNil()
	end,
}
