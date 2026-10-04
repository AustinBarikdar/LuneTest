--!strict
-- Runs on Roblox's servers, not in Lune: `lune run test --cloud` sends this file as the
-- script of an Open Cloud Luau execution task on the configured test place.
--
-- A task is a bare server DataModel: no players, no client, no physics simulation, and
-- the place's own scripts don't start. So only server and shared specs run here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SerializationService = game:GetService("SerializationService")
local ServerScriptService = game:GetService("ServerScriptService")

-- The test content arrives as the task's binary input: one Folder per service, named
-- after it, holding that service's children. Move them into this task's DataModel.
-- Nothing here is saved; the DataModel is discarded when the task ends.
local input = ({ ... })[1]
for _, folder in SerializationService:DeserializeInstancesAsync(input.BinaryInput) do
	local service = (game :: any):GetService(folder.Name)
	for _, child in folder:GetChildren() do
		local existing = service:FindFirstChild(child.Name)
		if existing then
			pcall(existing.Destroy, existing) -- the built project wins over the host place
		end
		child.Parent = service
	end
end

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
