--!strict
-- LuneTest runtime. A spec is a ModuleScript named *Spec that returns
-- { ["test name"] = function() ... end }. Runs in Studio and inside Lune.

-- Missing when specs run inside Lune instead of Studio.
local messageOut: RBXScriptSignal? = nil
pcall(function()
	messageOut = game:GetService("LogService").MessageOut
end)

export type LogEntry = {
	status: "pass" | "fail",
	name: string, -- "[label] Group/Spec › test"
	spec: string, -- "[label] Group/Spec"
	message: string?,
}

export type Results = {
	passed: number,
	failed: number,
	log: { LogEntry },
}

export type Options = {
	filters: { string }?, -- only run tests whose full name contains one of these
	timeout: number?, -- seconds per test before it counts as hung
	only: { string }?, -- only run these specs (LogEntry.spec names)
	bail: boolean?, -- stop a spec at its first failure
}

-- Simulated client <-> server networking; see README "Simulated network".
export type Network = {
	client: (fn: (...any) -> ...any, ...any) -> ...any,
	server: (fn: (...any) -> ...any, ...any) -> ...any,
	flush: (frames: number?) -> (),
	spy: (remote: Instance) -> { { direction: "toServer" | "toClient", args: { any } } },
	player: () -> Player,
}

local LuneTest = {}

LuneTest.expect = require(script.Expect)
-- Installed by the Lune CLI for unit specs. nil inside Studio, which has the real network.
LuneTest.network = (nil :: any) :: Network

-- Spec modules under `container`, in a stable order. Other modules are helpers.
function LuneTest.collect(container: Instance?): { ModuleScript }
	local out: { ModuleScript } = {}
	if container then
		for _, child in container:GetDescendants() do
			if child:IsA("ModuleScript") and string.match(child.Name, "[Ss]pec$") then
				table.insert(out, child)
			end
		end
	end
	table.sort(out, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return out
end

-- Options the CLI baked into the LuneTestSpecs folder's attributes.
function LuneTest.optionsFrom(specsFolder: Instance): Options
	local function list(attribute: string): { string }?
		local value = specsFolder:GetAttribute(attribute) :: string?
		return if value and value ~= "" then string.split(value, "\n") else nil
	end
	return {
		filters = list("Filters"),
		only = list("Only"),
		timeout = specsFolder:GetAttribute("TestTimeout") :: number?,
	}
end

-- "Economy/CoinsSpec" for container/Economy/CoinsSpec: the group folders are part of the name.
local function relativeName(spec: Instance, container: Instance): string
	local name = spec.Name
	local parent = spec.Parent
	while parent and parent ~= container do
		name = `{parent.Name}/{name}`
		parent = parent.Parent
	end
	return name
end

local function matches(name: string, filters: { string }?): boolean
	if not filters then
		return true
	end
	for _, filter in filters do
		if string.find(name, filter, 1, true) then
			return true
		end
	end
	return false
end

-- Prefixes the spec's own line (from the traceback) when the error doesn't name it.
local function withSpecLine(err: any, specPath: string): string
	local message = tostring(err)
	if string.find(message, specPath, 1, true) then
		return message
	end
	local escaped = string.gsub(specPath, "%p", "%%%0")
	local line = string.match(debug.traceback(), escaped .. ":(%d+)")
	return if line then `{specPath}:{line}: {message}` else message
end

-- Runs `fn` in its own thread so a hung WaitForChild fails one test, not the run.
local function runWithTimeout(fn: () -> (), timeout: number, specPath: string): (boolean, string?)
	local done, ok, message = false, false, nil
	local thread = task.spawn(function()
		local success, err = xpcall(fn :: (...any) -> ...any, function(e)
			return withSpecLine(e, specPath)
		end)
		done, ok, message = true, success, if success then nil else err
	end)
	local elapsed = 0
	while not done and elapsed < timeout do
		elapsed += task.wait()
	end
	if not done then
		task.cancel(thread)
		return false, `timed out after {timeout}s`
	end
	return ok, message
end

-- Runs every spec under `container`. Never throws; failures land in the results log.
function LuneTest.run(container: Instance?, label: string, options: Options?): Results
	local filters = options and options.filters
	local only = options and options.only
	local bail = options and options.bail
	local timeout = options and options.timeout or 30
	local results: Results = { passed = 0, failed = 0, log = {} }

	for _, spec in LuneTest.collect(container) do
		local specName = `{label}{relativeName(spec, container :: Instance)}`
		if only and not table.find(only, specName) then
			continue
		end
		local function record(ok: boolean, name: string, message: string?)
			if ok then
				results.passed += 1
			else
				results.failed += 1
			end
			table.insert(results.log, { status = if ok then "pass" else "fail", name = name, spec = specName, message = message })
		end

		-- Studio's require() re-throws module errors as a generic message; the real one
		-- only reaches the output log a frame later, so grab it from there.
		local capturedError: string? = nil
		local logConnection = messageOut and messageOut:Connect(function(message, messageType)
			if messageType == Enum.MessageType.MessageError and not capturedError then
				capturedError = message
			end
		end)
		local okRequire, tests = pcall(require, spec :: any)
		if logConnection then
			if not okRequire then
				task.wait()
			end
			logConnection:Disconnect()
		end

		if not okRequire or type(tests) ~= "table" then
			if matches(specName, filters) then
				record(
					false,
					specName,
					if okRequire
						then "spec must return a table of { [name] = function }"
						else `require error: {tests}{if capturedError then ` | {capturedError}` else ""}`
				)
			end
			continue
		end

		-- Keys are usually strings, but an array of functions is valid too; compare as
		-- strings so mixed key types can't make the sort throw.
		local names: { any } = {}
		for name in tests :: { [any]: any } do
			table.insert(names, name)
		end
		table.sort(names, function(a, b)
			return tostring(a) < tostring(b)
		end)

		for _, name in names do
			local testName = `{specName} › {tostring(name)}`
			if not matches(testName, filters) then
				continue
			end
			local fn = (tests :: any)[name]
			if type(fn) ~= "function" then
				record(false, testName, "test value is not a function")
			else
				local ok, message = runWithTimeout(fn, timeout, spec:GetFullName())
				record(ok, testName, message)
				if not ok and bail then
					break
				end
			end
		end
	end

	return results
end

return LuneTest
