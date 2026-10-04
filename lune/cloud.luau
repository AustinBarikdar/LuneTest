--!strict
-- Runs on Roblox's servers, not in Lune: `lune run test --cloud` sends this file as the
-- script of an Open Cloud Luau execution task against the uploaded test place.
--
-- A task is a bare server DataModel: no players, no client, no physics simulation, and
-- the place's own scripts don't start. So only server and shared specs run here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LuneTest = require(ReplicatedStorage:WaitForChild("LuneTest") :: ModuleScript)
local specs = ReplicatedStorage:WaitForChild("LuneTestSpecs")
local serverSpecs = ServerScriptService:FindFirstChild("LuneTestSpecs")
local options = LuneTest.optionsFrom(specs)

local merged = { passed = 0, failed = 0, log = {} }
local function merge(results: any)
	merged.passed += results.passed
	merged.failed += results.failed
	table.move(results.log, 1, #results.log, #merged.log + 1, merged.log)
end

merge(LuneTest.run(serverSpecs and serverSpecs:FindFirstChild("Server"), "[server] ", options))
merge(LuneTest.run(specs:FindFirstChild("Shared"), "[shared] ", options))

-- The task's return value is how results get back: Open Cloud serializes it to JSON.
return merged
