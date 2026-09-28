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
	-- No game.Loaded here: an Edit place never reports IsLoaded(). Retry with backoff
	-- instead, since on a slow machine Studio can still be settling in.
	task.wait()
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
