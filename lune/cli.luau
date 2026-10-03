--!strict
-- The `lune run test` command.
--   unit specs: run right here inside Lune against the Rojo-built place (no Studio, fast)
--   e2e specs:  run in a real Studio play session (server + client), started by the plugin
--
--   lune run test                     everything
--   lune run test unit                only unit specs
--   lune run test e2e                 only Studio specs
--   lune run test unit Economy Coins  only tests whose name contains "Economy" or "Coins"
--   lune run test --fresh             forget which e2e specs needed Studio last time
--
-- e2e specs are tried in Lune first; any spec with a failure there is rerun in Studio,
-- whose verdict is final. Studio only opens when at least one spec needs it.

local DateTime = require("@lune/datetime")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

local createNetwork = require("./network")

export type Config = {
	project: string?, -- base Rojo project, default "default.project.json"
	unit: string?, -- unit spec folder, default "tests/unit"
	e2e: string?, -- folder holding server/, client/, shared/; default "tests/e2e"
	port: number?, -- first port to try for Studio's results; default 44774
	timeout: number?, -- seconds to wait for Studio; default 300
	testTimeout: number?, -- seconds before one test counts as hung; default 30
	clientTimeout: number?, -- seconds the Studio client gets to start; default 90
	-- Remotes to create in the test place, by parent path:
	--   { ["ReplicatedStorage.Remotes"] = { "Chat", GetData = "RemoteFunction" } }
	-- A bare name is a RemoteEvent.
	remotes: { [string]: { [any]: string } }?,
	-- Try e2e specs in Lune first and only send the ones that fail to Studio. Default true.
	fallback: boolean?,
}

type Results = {
	passed: number,
	failed: number,
	log: { { status: string, name: string, spec: string, message: string? } },
	runId: string?,
}

local IS_WINDOWS = process.os == "windows"
-- This file lives at <package>/lune/cli.luau.
local PACKAGE_DIR = assert(string.match(debug.info(1, "s"), "^(.*)[/\\]lune[/\\]cli"), "cannot locate LuneTest package")
local PLACE_FILE = "lunetest.rbxlx"
-- Specs that needed Studio last time, keyed by name with a hash of their source, so the
-- next run sends them straight there instead of waiting them out in Lune again.
local CACHE_FILE = "lunetest.cache.json"
local CACHE_VERSION = 1
-- Lune-side waits (WaitForChild, the e2e attempt's per-test timeout). Everything in Lune
-- is one process, so anything slower than this needs the real engine, i.e. Studio. Kept
-- short because every Studio-only spec pays it once before falling back.
local LUNE_WAIT = 2

local cli = {}

local function info(message: string)
	stdio.write(`[lunetest] {message}\n`)
end

local function fail(message: string): never
	stdio.ewrite(`[lunetest] {stdio.color("red")}{message}{stdio.color("reset")}\n`)
	return process.exit(1)
end

local function absolute(path: string): string
	if string.match(path, "^/") or string.match(path, "^%a:[/\\]") then
		return path
	end
	return process.cwd .. path
end

local function pluginPath(): string?
	if IS_WINDOWS and process.env.LOCALAPPDATA then
		return `{process.env.LOCALAPPDATA}\\Roblox\\Plugins\\LuneTest.rbxmx`
	elseif process.os == "macos" and process.env.HOME then
		return `{process.env.HOME}/Documents/Roblox/Plugins/LuneTest.rbxmx`
	end
	return nil
end

-- Writes the Studio plugin (lune/plugin.luau) if missing or outdated. Returns true when it wrote.
function cli.installPlugin(): boolean
	local path = pluginPath()
	if not path then
		return false
	end
	local source = fs.readFile(`{PACKAGE_DIR}/lune/plugin.luau`)
	if fs.isFile(path) then
		local ok, existing = pcall(roblox.deserializeModel, fs.readFile(path))
		if ok and existing[1] and (existing[1] :: any).Source == source then
			return false
		end
	end
	local script = roblox.Instance.new("Script")
	script.Name = "LuneTest"
	script.Source = source
	fs.writeDir(string.match(path, "^(.*)[/\\]") :: string)
	fs.writeFile(path, roblox.serializeModel({ script }, true))
	return true
end

-- Copies the base project and injects the runtime, specs and runner scripts.
local function writeTestProject(config: Config, attributes: { [string]: any }): string
	local projectPath = config.project or "default.project.json"
	if not fs.isFile(projectPath) then
		fail(`{projectPath} not found; set \`project\` in your test launcher`)
	end
	local project = serde.decode("json", fs.readFile(projectPath))

	-- A library project (not a whole place) gets mounted under ReplicatedStorage.
	local tree = project.tree
	if tree["$className"] ~= "DataModel" then
		tree = { ["$className"] = "DataModel", ReplicatedStorage = { [project.name] = tree } }
		project.tree = tree
	end

	local function child(parent: any, name: string, className: string): any
		parent[name] = parent[name] or { ["$className"] = className }
		return parent[name]
	end
	local function folder(path: string): any
		path = absolute(path)
		return if fs.isDir(path) then { ["$path"] = path } else nil
	end
	local e2e = config.e2e or "tests/e2e"

	local httpService = child(tree, "HttpService", "HttpService")
	httpService["$properties"] = httpService["$properties"] or {}
	httpService["$properties"].HttpEnabled = true

	local replicatedStorage = child(tree, "ReplicatedStorage", "ReplicatedStorage")
	replicatedStorage.LuneTest = { ["$path"] = PACKAGE_DIR }
	replicatedStorage.LuneTestSpecs = {
		["$className"] = "Folder",
		["$attributes"] = attributes, -- AutoPlay is the marker the Studio plugin looks for
		Unit = folder(config.unit or "tests/unit"),
		Shared = folder(`{e2e}/shared`),
		Client = folder(`{e2e}/client`),
	}

	local serverScriptService = child(tree, "ServerScriptService", "ServerScriptService")
	serverScriptService.LuneTestSpecs = { ["$className"] = "Folder", Server = folder(`{e2e}/server`) }
	serverScriptService.LuneTestServer = { ["$path"] = `{PACKAGE_DIR}/runners/Server.server.luau` }

	local starterPlayer = child(tree, "StarterPlayer", "StarterPlayer")
	local playerScripts = child(starterPlayer, "StarterPlayerScripts", "StarterPlayerScripts")
	playerScripts.LuneTestClient = { ["$path"] = `{PACKAGE_DIR}/runners/Client.client.luau` }

	for parentPath, remotes in (config.remotes or {}) :: { [string]: { [any]: string } } do
		local node = tree
		for _, name in string.split(parentPath, ".") do
			-- Top-level names are services (class = name); deeper ones are Folders.
			node = child(node, name, if node == tree then name else "Folder")
		end
		for key, value in remotes do
			local name, className = if type(key) == "number" then value else key, if type(key) == "number" then "RemoteEvent" else value
			node[name] = node[name] or { ["$className"] = className }
		end
	end

	-- Written next to the base project so its relative $paths still resolve.
	local outPath = (string.match(projectPath, "^(.*[/\\])") or "") .. "lunetest.project.json"
	fs.writeFile(outPath, serde.encode("json", project, true))
	return outPath
end

-- Loads the built place and gives ModuleScripts a Roblox-like require(), so the same
-- runtime and specs run here without Studio. Modules load once per realm (server/client)
-- so network.client() code sees its own copy, like a real client would.
local function loadPlace(waitTimeout: number): (any, (any) -> any, any)
	local game = roblox.deserializePlace(fs.readFile(PLACE_FILE))
	local network, realmGlobals = createNetwork(game, waitTimeout)

	local globals = {}
	for key, value in roblox :: any do
		if string.match(key, "^%u") then -- Instance, Vector3, CFrame, Enum, ...
			globals[key] = value
		end
	end
	globals.game = game
	globals.workspace = game:GetService("Workspace")
	globals.task = realmGlobals.task
	globals.coroutine = realmGlobals.coroutine
	-- Legacy globals some older modules still use.
	globals.wait = realmGlobals.task.wait
	globals.spawn = realmGlobals.task.defer
	globals.delay = realmGlobals.task.delay
	globals.tick = function()
		return DateTime.now().unixTimestampMillis / 1000
	end

	local caches = { server = {}, client = {} }
	local function requireModule(module: any): any
		if type(module) ~= "userdata" or not module:IsA("ModuleScript") then
			error(`unit specs can only require ModuleScripts, got {typeof(module)}`, 2)
		end
		local cache = caches[realmGlobals.realm()]
		if cache[module] == nil then
			local env = table.clone(globals)
			env.script = module
			-- "=" prints the chunk name as-is, so errors read "Path.To.Module:12" like Studio.
			local chunk = luau.load(module.Source, { debugName = "=" .. module:GetFullName(), environment = env })
			cache[module] = chunk()
		end
		return cache[module]
	end
	globals.require = requireModule
	return game, requireModule, network
end

-- macOS: { pid, args } for every Studio process. Each place opened while Studio is
-- already running gets its own child process with `-localPlaceFile <path>`.
local function studioProcesses(): { { pid: string, args: string } }
	local out = {}
	for line in string.gmatch(process.exec("ps", { "-axo", "pid=,args=" }).stdout, "[^\n]+") do
		local pid, args = string.match(line, "^%s*(%d+)%s+(.*)$")
		if pid and args and (string.match(args, "MacOS/RobloxStudio$") or string.find(args, "MacOS/RobloxStudio ", 1, true)) then
			table.insert(out, { pid = pid, args = args })
		end
	end
	return out
end

local function studioRunning(): boolean
	if IS_WINDOWS then
		return string.find(process.exec("tasklist", {}).stdout, "RobloxStudio", 1, true) ~= nil
	end
	return #studioProcesses() > 0
end

-- Studio ignores SIGTERM but exits cleanly on SIGHUP; SIGKILL only if it hangs.
local function terminate(pid: string)
	process.exec("kill", { "-HUP", pid })
	for _ = 1, 30 do
		task.wait(0.1)
		if not process.exec("kill", { "-0", pid }).ok then
			return
		end
	end
	process.exec("kill", { "-9", pid })
end

-- Closes the LuneTest place. `quitStudio` also quits Studio itself when we launched it
-- and nothing else is open in it, so unsaved work in your other places is never touched.
local function closeStudio(quitStudio: boolean)
	if IS_WINDOWS then
		process.exec("powershell", {
			"-NoProfile",
			"-Command",
			`Get-Process RobloxStudio* -ErrorAction SilentlyContinue | Where-Object \{ $_.MainWindowTitle -like '*{PLACE_FILE}*' } | Stop-Process -Force`,
		})
		return
	end
	local target = `-localPlaceFile {absolute(PLACE_FILE)}`
	local main, otherPlaces = nil, 0
	for _, studio in studioProcesses() do
		if string.find(studio.args, target, 1, true) then
			terminate(studio.pid)
		elseif string.find(studio.args, "-localPlaceFile", 1, true) then
			otherPlaces += 1
		elseif string.match(studio.args, "MacOS/RobloxStudio$") then
			main = studio.pid -- a cold start opens our place in here
		end
	end
	if quitStudio and main and otherPlaces == 0 then
		terminate(main)
	end
end

local function openStudio()
	if IS_WINDOWS then
		process.exec("cmd", { "/c", "start", "", PLACE_FILE })
	elseif fs.isDir("/Applications/RobloxStudio.app") then
		process.exec("open", { "-a", "/Applications/RobloxStudio.app", PLACE_FILE })
	else
		process.exec("open", { PLACE_FILE })
	end
end

local function printResults(results: Results, where: string?)
	local suffix = if where then `  {stdio.style("dim")}({where}){stdio.style("reset")}` else ""
	for _, entry in results.log do
		if entry.status == "pass" then
			stdio.write(`  {stdio.color("green")}PASS{stdio.color("reset")}  {entry.name}{suffix}\n`)
		else
			stdio.write(`  {stdio.color("red")}FAIL{stdio.color("reset")}  {entry.name}{suffix}\n`)
			if entry.message then
				stdio.write(`        {string.gsub(entry.message, "\n", "\n        ")}\n`)
			end
		end
	end
end

local function matches(name: string, filters: { string }): boolean
	for _, filter in filters do
		if string.find(name, filter, 1, true) then
			return true
		end
	end
	return false
end

-- Binds the first free port from `first`, so two projects can test at the same time.
local function listen(first: number, handler: (any) -> any): (number, any)
	for port = first, first + 20 do
		local ok, handle = pcall(net.serve, port, handler)
		if ok then
			return port, handle
		end
	end
	return fail(`no free port between {first} and {first + 20}`)
end

function cli.run(config: Config)
	local started = DateTime.now().unixTimestampMillis
	local mode = "all"
	local filters = {}
	local fresh = false
	for _, arg in process.args do
		if arg == "unit" or arg == "e2e" then
			mode = arg
		elseif arg == "--fresh" then
			fresh = true
		else
			table.insert(filters, arg)
		end
	end

	-- Results are only accepted from this run (stale or foreign Studios are ignored).
	local runId = `{os.time()}-{math.random(1, 1e9)}`
	local received: Results? = nil
	local port, server = listen(config.port or 44774, function(request)
		if request.method == "POST" and request.path == "/results" then
			local ok, results = pcall(function()
				return serde.decode("json", request.body)
			end)
			if ok and type(results) == "table" and results.runId == runId then
				received = results
				return { status = 200, body = "ok" }
			end
			return { status = 400, body = "not for this run" }
		end
		return { status = 404, body = "not found" }
	end)

	local attributes = {
		AutoPlay = true,
		RunId = runId,
		Port = port,
		TestTimeout = config.testTimeout or 30,
		ClientTimeout = config.clientTimeout or 90,
		Filters = if #filters > 0 then table.concat(filters, "\n") else nil,
		Only = nil :: string?,
	}
	local function build()
		local projectFile = writeTestProject(config, attributes)
		local result = process.exec("rojo", { "build", projectFile, "-o", PLACE_FILE })
		if not result.ok then
			fail(`rojo build of {projectFile} failed:\n{result.stderr}`)
		end
	end
	build()

	local game, requireModule, network = loadPlace(LUNE_WAIT)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local LuneTest = requireModule(ReplicatedStorage.LuneTest)
	LuneTest.network = network -- unit specs only; Studio has the real network
	local specs = ReplicatedStorage.LuneTestSpecs
	local e2eFolders = {
		{ label = "[server] ", folder = game:GetService("ServerScriptService").LuneTestSpecs:FindFirstChild("Server") },
		{ label = "[shared] ", folder = specs:FindFirstChild("Shared") },
		{ label = "[client] ", folder = specs:FindFirstChild("Client"), client = true },
	}
	local total = { passed = 0, failed = 0 }
	local function report(results: Results, where: string?)
		printResults(results, where)
		total.passed += results.passed
		total.failed += results.failed
	end
	local filterList = if #filters > 0 then filters else nil

	if mode ~= "e2e" then
		report(LuneTest.run(specs:FindFirstChild("Unit"), "[unit] ", {
			filters = filterList,
			timeout = config.testTimeout,
		}))
	end

	local e2eSpecs = 0
	for _, bucket in e2eFolders do
		e2eSpecs += #LuneTest.collect(bucket.folder)
	end
	local needStudio = mode ~= "unit" and e2eSpecs > 0

	if needStudio and config.fallback ~= false then
		-- Try e2e specs in Lune; a spec with any failure goes to Studio instead.
		local cached: { [string]: string? } = {}
		local okCache, cacheFile = pcall(function()
			return serde.decode("json", fs.readFile(CACHE_FILE))
		end)
		if not fresh and okCache and type(cacheFile) == "table" and cacheFile.version == CACHE_VERSION then
			cached = cacheFile.studio
		end

		local passed: Results = { passed = 0, failed = 0, log = {} }
		local fallBack: { string } = {}
		local hashes: { [string]: string } = {}
		local known = 0
		for _, bucket in e2eFolders do
			-- Cached specs skip Lune only when the filters would select the whole spec;
			-- otherwise Lune decides which of its tests match.
			local attempt: { string } = {}
			for _, spec in LuneTest.collect(bucket.folder) do
				local name, parent = spec.Name, spec.Parent
				while parent and parent ~= bucket.folder do
					name, parent = `{parent.Name}/{name}`, parent.Parent
				end
				name = bucket.label .. name
				hashes[name] = serde.hash("sha256", spec.Source)
				if cached[name] == hashes[name] and (not filterList or matches(name, filterList)) then
					table.insert(fallBack, name)
					known += 1
				else
					table.insert(attempt, name)
				end
			end

			local options = { filters = filterList, timeout = LUNE_WAIT, bail = true, only = attempt }
			local ok, results = pcall(function()
				if bucket.client then
					return network.client(LuneTest.run, bucket.folder, bucket.label, options)
				end
				return LuneTest.run(bucket.folder, bucket.label, options)
			end)
			local failedSpecs = {}
			if ok then
				for _, entry in results.log do
					if entry.status == "fail" then
						failedSpecs[entry.spec] = true
					end
				end
				for _, entry in results.log do
					if not failedSpecs[entry.spec] then
						table.insert(passed.log, entry)
						passed.passed += 1
					end
				end
			else
				-- The attempt itself broke (e.g. a network handler error): Studio decides all of it.
				for _, name in attempt do
					failedSpecs[name] = true
				end
			end
			for name in failedSpecs do
				table.insert(fallBack, name)
			end
			-- Remember this run's verdicts; specs that passed in Lune are forgotten.
			for _, name in attempt do
				cached[name] = if failedSpecs[name] then hashes[name] else nil
			end
		end
		pcall(fs.writeFile, CACHE_FILE, serde.encode("json", { version = CACHE_VERSION, studio = cached }))

		report(passed, "lune")
		needStudio = #fallBack > 0
		if needStudio then
			table.sort(fallBack)
			attributes.Only = table.concat(fallBack, "\n")
			build()
			info(
				`{#fallBack} of {e2eSpecs} e2e spec{if e2eSpecs == 1 then "" else "s"} need Studio{if known > 0
					then ` ({known} known from last run)`
					else ""}`
			)
		end
	end

	if needStudio then
		local timeout = config.timeout or 300
		local alreadyRunning = studioRunning()
		if cli.installPlugin() and alreadyRunning then
			fail("updated the LuneTest Studio plugin, but the open Studio won't load it until restarted. Close Studio and run again")
		end

		closeStudio(false)
		info("running in Studio...")
		openStudio()
		local elapsed, opens, nextCheck = 0, 1, 8
		while received == nil and elapsed < timeout do
			elapsed += task.wait(0.1)
			-- macOS race: right after a Studio quits, `open` can hand the file to the dying
			-- app and nothing launches. No Studio process at all means it was lost; reopen.
			-- Checked every 2s, not every tick: `ps` is a process spawn and Studio is booting.
			if not IS_WINDOWS and opens < 3 and elapsed >= nextCheck then
				nextCheck = elapsed + 2
				if #studioProcesses() == 0 then
					opens += 1
					nextCheck = elapsed + 8
					info("Studio didn't start, opening again...")
					openStudio()
				end
			end
		end
		closeStudio(not alreadyRunning)
		if received == nil then
			fail(`no results from Studio after {timeout}s; check Studio's Output window`)
		end
		report(received :: Results, "studio")
	elseif mode == "e2e" and e2eSpecs == 0 then
		info("no e2e specs found")
	end
	server.stop()

	local color: "red" | "green" = if total.failed > 0 then "red" else "green"
	stdio.write(
		`\n[lunetest] {stdio.color(color)}{total.passed} passed, {total.failed} failed{stdio.color("reset")} ({string.format(
			"%.2f",
			(DateTime.now().unixTimestampMillis - started) / 1000
		)}s)\n`
	)
	process.exit(if total.failed > 0 then 1 else 0)
end

return cli
