--!strict
-- Injected by `lune run test`. Runs server + shared specs, collects the client
-- bucket, and POSTs everything back to the Lune harness.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LuneTest = require(ReplicatedStorage:WaitForChild("LuneTest") :: ModuleScript)
local specs = ReplicatedStorage:WaitForChild("LuneTestSpecs")
local serverSpecs = ServerScriptService:FindFirstChild("LuneTestSpecs")

local options = LuneTest.optionsFrom(specs)
-- IPv4 loopback: Windows "localhost" can stall trying IPv6 first.
local harnessUrl = `http://127.0.0.1:{specs:GetAttribute("Port")}`
local resultsUrl = `{harnessUrl}/results`

-- Tells the harness that Play really started, so it can tell "slow" from "never started".
task.spawn(pcall, HttpService.PostAsync, HttpService, `{harnessUrl}/started`, tostring(specs:GetAttribute("RunId")))
local clientTimeout = (specs:GetAttribute("ClientTimeout") :: number?) or 90

-- Parented and connected in the same frame, so the client can never fire into the void.
local remote = Instance.new("RemoteEvent")
remote.Name = "Results"
remote.Parent = specs

local clientStarted = false
local clientResults: any = nil
remote.OnServerEvent:Connect(function(_player, payload)
	if payload == "started" then
		clientStarted = true
	elseif clientResults == nil and type(payload) == "table" then
		clientResults = payload
	end
end)

local merged = { passed = 0, failed = 0, log = {}, runId = specs:GetAttribute("RunId") }
local function merge(bucket: any)
	merged.passed += bucket.passed
	merged.failed += bucket.failed
	table.move(bucket.log, 1, #bucket.log, #merged.log + 1, merged.log)
end
local function harnessFailure(message: string)
	merge({
		passed = 0,
		failed = 1,
		log = { { status = "fail", name = "[client] harness", spec = "[client] harness", message = message } },
	})
end

merge(LuneTest.run(serverSpecs and serverSpecs:FindFirstChild("Server"), "[server] ", options))
merge(LuneTest.run(specs:FindFirstChild("Shared"), "[shared] ", options))

if #LuneTest.collect(specs:FindFirstChild("Client")) > 0 then
	-- Slow machines take a while to load a client, so only its *start* has a deadline;
	-- once running, per-test timeouts bound it.
	local elapsed = 0
	while not clientStarted and elapsed < clientTimeout do
		elapsed += task.wait(0.1)
	end
	while clientStarted and clientResults == nil and #Players:GetPlayers() > 0 do
		task.wait(0.1)
	end
	if clientResults then
		merge(clientResults)
	elseif clientStarted then
		harnessFailure("the player left before client specs finished")
	else
		harnessFailure(`the client never started within {clientTimeout}s`)
	end
end

print(`[LuneTest] {merged.passed} passed, {merged.failed} failed`)
local body = HttpService:JSONEncode(merged)
for attempt = 1, 5 do
	local ok, err = pcall(HttpService.PostAsync, HttpService, resultsUrl, body, Enum.HttpContentType.ApplicationJson)
	if ok then
		break
	end
	warn(`[LuneTest] could not POST results to {resultsUrl} (attempt {attempt}): {err}`)
	task.wait(attempt * 0.5)
end

-- The LuneTest Studio plugin watches this to end the play session.
specs:SetAttribute("Done", true)
