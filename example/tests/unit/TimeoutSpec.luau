--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LuneTest = require(ReplicatedStorage.LuneTest)
local expect = LuneTest.expect

-- Timeouts are real time. On Windows, Lune's task.wait() sleeps about 15ms and reports
-- 1ms, so a timeout that adds up what it returns runs about 15x too long.
return {
	["WaitForChild gives up on time"] = function()
		local started = os.clock()
		expect(ReplicatedStorage:WaitForChild("Missing", 0.2)).toBeNil()
		expect(os.clock() - started).toBeLessThan(1)
	end,

	["a hung test times out on time"] = function()
		local folder = Instance.new("Folder")
		local spec = Instance.new("ModuleScript")
		spec.Name = "HangSpec"
		spec.Source = "return { hangs = function() task.wait(10) end }"
		spec.Parent = folder

		local started = os.clock()
		local results = LuneTest.run(folder, "", { timeout = 0.2 })
		expect(os.clock() - started).toBeLessThan(1)
		expect(results.log[1].message).toBe("timed out after 0.2s")
	end,
}
