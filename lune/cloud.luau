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
-- print() goes to the task's log, which the CLI shows if the task fails or stalls.
local input = ({ ... })[1]
print("[LuneTest] loading test content")
local folders = SerializationService:DeserializeInstancesAsync(input.BinaryInput)
print(`[LuneTest] loaded {#folders} services`)
for _, folder in folders do
	local service = (game :: any):GetService(folder.Name)
	for _, child in folder:GetChildren() do
		local existing = service:FindFirstChild(child.Name)
		if existing then
			pcall(existing.Destroy, existing) -- the built project wins over the host place
		end
		child.Parent = service
	end
end

-- FindFirstChild, not WaitForChild: nothing else will add these, so waiting would only
-- stall the task until it times out.
local runtime = ReplicatedStorage:FindFirstChild("LuneTest")
local specs = ReplicatedStorage:FindFirstChild("LuneTestSpecs")
if not runtime or not specs then
	error("the test content did not load: ReplicatedStorage.LuneTest or LuneTestSpecs is missing")
end
local LuneTest = require(runtime :: ModuleScript)
local serverSpecs = ServerScriptService:FindFirstChild("LuneTestSpecs")
local options = LuneTest.optionsFrom(specs)

local merged = { passed = 0, failed = 0, log = {} }
local function merge(results: any)
	merged.passed += results.passed
	merged.failed += results.failed
	table.move(results.log, 1, #results.log, #merged.log + 1, merged.log)
end

print("[LuneTest] running server specs")
merge(LuneTest.run(serverSpecs and serverSpecs:FindFirstChild("Server"), "[server] ", options))
print("[LuneTest] running shared specs")
merge(LuneTest.run(specs:FindFirstChild("Shared"), "[shared] ", options))
print(`[LuneTest] {merged.passed} passed, {merged.failed} failed`)

-- The task's return value is how results get back: Open Cloud serializes it to JSON.
return merged
