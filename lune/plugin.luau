--!strict
-- Source of the LuneTest Studio plugin. `lune run test` writes it into Studio's
-- Plugins folder. It only acts in places built by LuneTest (the AutoPlay marker),
-- so your real game never starts Play on its own.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StudioTestService = game:GetService("StudioTestService")

local specs = ReplicatedStorage:FindFirstChild("LuneTestSpecs")
if not specs or not specs:GetAttribute("AutoPlay") then
	return
end

if RunService:IsEdit() then
	-- Asking for Play while Studio is still opening the place is accepted and then silently
	-- dropped, and a dropped request can't be cancelled or repeated. There is no "ready"
	-- event (an Edit place never reports IsLoaded()), so wait until Studio's own interface
	-- has stopped changing: it keeps growing for as long as Studio is loading.
	local coreGui = game:GetService("CoreGui")
	local waited, calm, lastCount = 0, 0, -1
	while waited < 30 and (waited < 1 or calm < 0.5) do
		local dt = task.wait(0.1)
		waited += dt
		local count = #coreGui:GetDescendants()
		-- A long frame means Studio is still busy, whatever the count says.
		calm = if count == lastCount and dt < 0.3 then calm + dt else 0
		lastCount = count
	end
	for attempt = 1, 8 do
		-- nil is rejected as an argument, hence the string.
		local ok, err = pcall(StudioTestService.ExecutePlayModeAsync, StudioTestService, "LuneTest")
		if ok then
			return
		end
		warn(`[LuneTest] could not start Play (attempt {attempt}): {err}`)
		task.wait(attempt * 0.5)
	end
elseif RunService:IsServer() then
	if not specs:GetAttribute("Done") then
		specs:GetAttributeChangedSignal("Done"):Wait()
	end
	StudioTestService:EndTest("LuneTest")
end
