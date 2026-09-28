--!strict
-- Injected by `lune run test`. Runs client specs and hands results to the server runner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- No timeouts here: the server gives up if we never report "started".
local specs = ReplicatedStorage:WaitForChild("LuneTestSpecs")
local LuneTest = require(ReplicatedStorage:WaitForChild("LuneTest") :: ModuleScript)
local clientSpecs = specs:FindFirstChild("Client")
if #LuneTest.collect(clientSpecs) == 0 then
	return
end
local remote = specs:WaitForChild("Results") :: RemoteEvent
remote:FireServer("started")

-- Character specs otherwise race the spawn. Bounded so CharacterAutoLoads=false can't hang us.
local player = Players.LocalPlayer
local waited = 0
while not player.Character and waited < 30 do
	waited += task.wait(0.1)
end
if player.Character then
	player.Character:WaitForChild("HumanoidRootPart", 30)
end

remote:FireServer(LuneTest.run(clientSpecs, "[client] ", LuneTest.optionsFrom(specs)))
