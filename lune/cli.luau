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
--   lune run test --cloud             run server/shared e2e specs on Roblox's servers (CI)
--   lune run test --cloud --dry-run   print the Open Cloud calls without sending them
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
	startTimeout: number?, -- seconds Studio gets to enter Play before the place is reopened; default 90
	-- The place `--cloud` runs server and shared specs in. It is never modified, but specs
	-- run inside that experience (its DataStores), so a separate test experience is best.
	-- The API key comes from the ROBLOX_API_KEY environment variable, never from here.
	cloud: { universeId: number | string, placeId: number | string }?,
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
local PLACE_FILE = "lunetest.rbxl" -- binary: ~7x faster to load than XML on big places
-- Specs that needed Studio last time, keyed by name with a hash of their source, so the
-- next run sends them straight there instead of waiting them out in Lune again.
local CACHE_FILE = "lunetest.cache.json"
local CACHE_VERSION = 1
-- Held for the whole run: { port, runId }. Two runs in one project would rebuild the same
-- place file and close each other's Studio windows.
local LOCK_FILE = "lunetest.lock"
local ownsLock = false
-- Lune-side waits (WaitForChild, the e2e attempt's per-test timeout). Everything in Lune
-- is one process, so anything slower than this needs the real engine, i.e. Studio. Kept
-- short because every Studio-only spec pays it once before falling back.
local LUNE_WAIT = 2

local cli = {}
cli.packageDir = PACKAGE_DIR

local function info(message: string)
	stdio.write(`[lunetest] {message}\n`)
end

local function fail(message: string): never
	if ownsLock then
		pcall(fs.removeFile, LOCK_FILE)
	end
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
	local okProject, project = pcall(serde.decode, "json" :: "json", fs.readFile(projectPath))
	if not okProject or type(project) ~= "table" or type(project.tree) ~= "table" then
		fail(`{projectPath} isn't a valid Rojo project: {if okProject then "it has no \"tree\"" else string.match(tostring(project), "[^\n]+")}`)
	end

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

-- macOS: pids of the Studio instances running our test place. It always gets its own
-- instance (see openStudio), identified by `-localPlaceFile <path>` on its command line,
-- so the user's own Studio windows are never involved.
local function ourStudioPids(): { string }
	local out = {}
	local target = `-localPlaceFile {absolute(PLACE_FILE)}`
	for line in string.gmatch(process.exec("ps", { "-axo", "pid=,args=" }).stdout, "[^\n]+") do
		local pid, args = string.match(line, "^%s*(%d+)%s+(.*)$")
		if pid and args and string.find(args, "MacOS/RobloxStudio", 1, true) and string.find(args, target, 1, true) then
			table.insert(out, pid)
		end
	end
	return out
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

-- Closes the test place, and only the test place.
local function closeStudio()
	if IS_WINDOWS then
		-- Every place is its own Studio process with the place path on its command line.
		-- Matched by full path (not window title, which is blank while Studio loads), so
		-- another project's test place is left alone.
		local place = string.gsub(absolute(PLACE_FILE), "'", "''")
		process.exec("powershell", {
			"-NoProfile",
			"-Command",
			`Get-CimInstance Win32_Process | Where-Object \{ $_.Name -like 'RobloxStudio*' -and $_.CommandLine -like ('*' + [WildcardPattern]::Escape('{place}') + '*') } | ForEach-Object \{ Stop-Process -Id $_.ProcessId -Force }`,
		})
		return
	end
	for _, pid in ourStudioPids() do
		terminate(pid)
	end
end

local function openStudio()
	if IS_WINDOWS then
		process.exec("cmd", { "/c", "start", "", PLACE_FILE })
	elseif fs.isDir("/Applications/RobloxStudio.app") then
		-- A separate instance (-n), in the background (-g) and hidden (-j): the run doesn't
		-- depend on, or disturb, a Studio the user already has open.
		process.exec("open", {
			"-n",
			"-g",
			"-j",
			"-a",
			"/Applications/RobloxStudio.app",
			"--args",
			"-task",
			"EditFile",
			"-localPlaceFile",
			absolute(PLACE_FILE),
		})
	else
		process.exec("open", { "-g", PLACE_FILE })
	end
end

-- macOS: pid of the frontmost app. Needs no special permission.
local function frontPid(): string?
	local out = process.exec("sh", { "-c", 'lsappinfo info -only pid "$(lsappinfo front)"' }).stdout
	return string.match(out, '"pid"=(%d+)')
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

-- A lock whose run still answers on its port is live; anything else (crash, Ctrl+C) is stale.
local function lockHeldByLiveRun(): boolean
	local ok, lock = pcall(function()
		return serde.decode("json", fs.readFile(LOCK_FILE))
	end)
	if not ok or type(lock) ~= "table" then
		return false
	end
	-- A port we can bind has nobody listening. Checked first because Windows takes ~2s to
	-- refuse a connection to a dead port, which the run after every Ctrl+C would pay.
	local free, probe = pcall(net.serve, lock.port, function()
		return ""
	end)
	if free then
		probe.stop()
		return false
	end
	local reached, response = pcall(net.request, `http://127.0.0.1:{lock.port}/alive`)
	return reached and response.ok and response.body == lock.runId
end

-- Binds the first free port from `first`, so two projects can test at the same time.
-- Returns nil when no port can be opened at all (e.g. a sandboxed AI agent): only Studio
-- needs the listener, so unit runs carry on without it.
local function listen(first: number, handler: (any) -> any): (number?, any)
	for port = first, first + 20 do
		local ok, handle = pcall(net.serve, port, handler)
		if ok then
			return port, handle
		end
	end
	return nil, nil
end

-- Overridable so the client can be tested against a local stand-in server.
local OPEN_CLOUD = process.env.LUNETEST_OPEN_CLOUD_URL or "https://apis.roblox.com"

-- Runs the server and shared specs as an Open Cloud Luau execution task: no Studio, no
-- window, no port, and no change to the place. Results come back as the task's return value.
local function runCloud(config: Config, dryRun: boolean): Results
	local cloud = config.cloud
	if not cloud then
		return fail(
			"`--cloud` needs `cloud = { universeId = ..., placeId = ... }` in your test launcher. "
				.. "Use a BLANK test place, never your production game: specs run inside that experience"
		)
	end
	local key = process.env.ROBLOX_API_KEY
	if not key and not dryRun then
		fail(
			"`--cloud` needs the ROBLOX_API_KEY environment variable: an Open Cloud API key with "
				.. "luau-execution-sessions (write) on that test place"
		)
	end
	local timeout = math.min(config.timeout or 300, 300) -- tasks are capped at 5 minutes

	local function call(method: "GET" | "POST", url: string, contentType: string?, body: string?): any
		if dryRun then
			info(`[dry run] {method} {url}{if body then ` ({#body} bytes)` else ""}`)
			return nil
		end
		local headers: { [string]: string } = { ["x-api-key"] = key :: string }
		if contentType then
			headers["Content-Type"] = contentType
		end
		local response = net.request({ url = url, method = method, headers = headers, body = body })
		if not response.ok then
			fail(`Open Cloud {method} {url} failed: {response.statusCode} {response.statusMessage}\n{response.body}`)
		end
		return serde.decode("json", response.body)
	end

	-- The place itself is never modified. The built test content travels as the task's
	-- binary input and lune/cloud.luau loads it into the task's own, temporary DataModel.
	-- Service children only: service properties (Lighting settings and the like) and
	-- StarterPlayer stay as the host place has them, and Terrain can't be created.
	local built = roblox.deserializePlace(fs.readFile(PLACE_FILE))
	local folders = {}
	for _, service in built:GetChildren() do
		if service.ClassName ~= "StarterPlayer" then
			local folder = roblox.Instance.new("Folder")
			folder.Name = service.ClassName
			for _, child in service:GetChildren() do
				if child.ClassName ~= "Terrain" and child.ClassName ~= "Camera" then
					child.Parent = folder
				end
			end
			if #folder:GetChildren() > 0 then
				table.insert(folders, folder)
			end
		end
	end
	local model = roblox.serializeModel(folders)

	local input = call(
		"POST",
		`{OPEN_CLOUD}/cloud/v2/universes/{cloud.universeId}/luau-execution-session-task-binary-inputs`,
		"application/json",
		serde.encode("json", { size = #model })
	)
	if dryRun then
		info(`[dry run] PUT <uploadUri> ({#model} bytes of test content)`)
	else
		local uploadHeaders: { [string]: string } = { ["Content-Type"] = "application/octet-stream" }
		local upload = net.request({ url = input.uploadUri :: string, method = "PUT", headers = uploadHeaders, body = model })
		if not upload.ok then
			fail(`uploading the test content failed: {upload.statusCode} {upload.statusMessage}\n{upload.body}`)
		end
	end
	local job = call(
		"POST",
		`{OPEN_CLOUD}/cloud/v2/universes/{cloud.universeId}/places/{cloud.placeId}/luau-execution-session-tasks`,
		"application/json",
		serde.encode("json", {
			script = fs.readFile(`{PACKAGE_DIR}/lune/cloud.luau`),
			timeout = `{timeout}s`,
			binaryInput = if input then input.path else "<binary input path>",
		})
	)
	if dryRun then
		info("[dry run] GET the task every 2s until it is COMPLETE or FAILED, then read output.results[1]")
		return { passed = 0, failed = 0, log = {} }
	end

	info(`cloud task: {job.path}`)
	local elapsed = 0
	while job.state ~= "COMPLETE" and job.state ~= "FAILED" and job.state ~= "CANCELLED" and elapsed < timeout + 60 do
		elapsed += task.wait(2)
		job = call("GET", `{OPEN_CLOUD}/cloud/v2/{job.path}`)
	end
	local results = job.state == "COMPLETE" and job.output and job.output.results and job.output.results[1]
	if type(results) == "table" and type(results.log) == "table" then
		return results
	end

	-- Show what the task printed; that's where a broken spec or module shows up.
	local printed = {}
	local okLogs, logs = pcall(call, "GET" :: "GET", `{OPEN_CLOUD}/cloud/v2/{job.path}/logs?view=FLAT`)
	if okLogs and type(logs) == "table" then
		for _, entry in logs.luauExecutionSessionTaskLogs or {} do
			for _, message in entry.messages or {} do
				table.insert(printed, tostring(message))
			end
		end
	end
	return fail(
		`the cloud task ended as {job.state}: {if job.error then job.error.message or job.error.code else "no results returned"}\n{table.concat(
			printed,
			"\n"
		)}`
	)
end

local function run(config: Config)
	local started = DateTime.now().unixTimestampMillis
	local mode = "all"
	local filters = {}
	local fresh, useCloud, dryRun = false, false, false
	for _, arg in process.args do
		if arg == "unit" or arg == "e2e" then
			mode = arg
		elseif arg == "--fresh" then
			fresh = true
		elseif arg == "--cloud" then
			useCloud = true
		elseif arg == "--dry-run" then
			dryRun = true
		else
			table.insert(filters, arg)
		end
	end

	if lockHeldByLiveRun() then
		fail("another `lune run test` is still running in this project; wait for it to finish or stop it")
	end

	-- Results are only accepted from this run (stale or foreign Studios are ignored).
	local runId = `{os.time()}-{math.random(1, 1e9)}`
	local received: Results? = nil
	local playStarted = false
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
		if request.method == "POST" and request.path == "/started" then
			playStarted = playStarted or request.body == runId
			return { status = 200, body = "ok" }
		end
		if request.method == "GET" and request.path == "/alive" then
			return { status = 200, body = runId }
		end
		return { status = 404, body = "not found" }
	end)
	if server then
		-- The lock is "live" only while this port answers, so no port means no lock.
		fs.writeFile(LOCK_FILE, serde.encode("json", { port = port, runId = runId }))
		ownsLock = true
	end

	local attributes = {
		AutoPlay = true,
		RunId = runId,
		Port = port or 0,
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
		if
			not fresh
			and okCache
			and type(cacheFile) == "table"
			and cacheFile.version == CACHE_VERSION
			and type(cacheFile.studio) == "table"
		then
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
			local ranSpecs = {}
			if ok then
				for _, entry in results.log do
					ranSpecs[entry.spec] = true
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
					ranSpecs[name] = true
				end
			end
			for name in failedSpecs do
				table.insert(fallBack, name)
			end
			-- Remember this run's verdicts; specs that passed in Lune are forgotten. A spec the
			-- filters skipped entirely ran nothing, so it proved nothing: keep its entry.
			for _, name in attempt do
				if ranSpecs[name] then
					cached[name] = if failedSpecs[name] then hashes[name] else nil
				end
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
				`{#fallBack} of {e2eSpecs} e2e spec{if e2eSpecs == 1 then "" else "s"} need {if useCloud
					then "the real engine"
					else "Studio"}{if known > 0
					then ` ({known} known from last run)`
					else ""}`
			)
		end
	end

	-- --cloud: Roblox's servers stand in for Studio. A task has no client, so client specs
	-- that need the real engine can't run there; say so instead of dropping them quietly.
	local skipped: { string } = {}
	if needStudio and useCloud then
		local cloudSpecs = 0
		if attributes.Only then
			for _, name in string.split(attributes.Only, "\n") do
				if string.sub(name, 1, 9) == "[client] " then
					table.insert(skipped, name)
				else
					cloudSpecs += 1
				end
			end
		else
			for _, bucket in e2eFolders do
				for _, spec in LuneTest.collect(bucket.folder) do
					if bucket.client then
						table.insert(skipped, `{bucket.label}{spec.Name}`)
					else
						cloudSpecs += 1
					end
				end
			end
		end
		if cloudSpecs > 0 then
			info(`running {cloudSpecs} spec{if cloudSpecs == 1 then "" else "s"} on Roblox's servers...`)
			report(runCloud(config, dryRun), "cloud")
		end
		for _, name in skipped do
			stdio.write(
				`  {stdio.color("yellow")}SKIP{stdio.color("reset")}  {name}  {stdio.style("dim")}(needs a real client: run it in Studio){stdio.style(
					"reset"
				)}\n`
			)
		end
		needStudio = false
	end

	if needStudio and not server then
		fail(
			"these specs need Roblox Studio, but no local port could be opened for Studio to report back "
				.. "(ports are blocked, e.g. by a sandbox). Unit specs are unaffected: `lune run test unit`"
		)
	end
	if needStudio then
		local timeout = config.timeout or 300
		-- Each test place opens in its own Studio process, which reads the plugin fresh, so
		-- an updated plugin takes effect even while other Studio windows are open.
		cli.installPlugin()

		closeStudio()
		info("running in Studio (in the background)...")
		openStudio()
		local elapsed, opens, nextCheck, nextFocus = 0, 1, 8, 0
		local ours: { string } = {}
		local startDeadline: number? = config.startTimeout or 90
		while received == nil and elapsed < timeout do
			elapsed += task.wait(0.1)
			-- Studio brings itself to the front a few times while it loads, whatever it was
			-- told at launch. Each time, hide it again: that takes its window off screen and
			-- gives the front back to the app the user was in. (NSRunningApplication.hide
			-- needs no Accessibility permission. Hiding it continuously, or running Studio
			-- with Qt's offscreen platform, was tried: the first fights Studio's startup and
			-- the second crashes it.)
			if not IS_WINDOWS and elapsed >= nextFocus then
				nextFocus = elapsed + 0.15
				if #ours == 0 then
					ours = ourStudioPids()
				end
				local pid = frontPid()
				if pid and table.find(ours, pid) then
					process.exec("osascript", {
						"-l",
						"JavaScript",
						"-e",
						`ObjC.import("AppKit"); $.NSRunningApplication.runningApplicationWithProcessIdentifier({pid}).hide`,
					})
				end
			end
			-- Studio can accept the plugin's request to start Play and then never start it,
			-- and that window can't be recovered. Close it and open a fresh one, once.
			if startDeadline and not playStarted and elapsed >= startDeadline then
				startDeadline = nil
				info("Studio opened but Play never started; reopening the test place...")
				closeStudio()
				openStudio()
				nextCheck = elapsed + 8
			end
			-- If the launch got lost and no Studio is running our place, open it again.
			-- Checked every 2s, not every tick: `ps` is a process spawn and Studio is booting.
			if not IS_WINDOWS and opens < 3 and elapsed >= nextCheck then
				nextCheck = elapsed + 2
				if #ourStudioPids() == 0 then
					opens += 1
					nextCheck = elapsed + 8
					info("Studio didn't start, opening again...")
					openStudio()
				end
			end
		end
		closeStudio()
		if received == nil then
			fail(`no results from Studio after {timeout}s; check Studio's Output window`)
		end
		report(received :: Results, "studio")
	elseif mode == "e2e" and e2eSpecs == 0 then
		info("no e2e specs found")
	end
	if server then
		server.stop()
	end

	local color: "red" | "green" = if total.failed > 0 then "red" else "green"
	stdio.write(
		`\n[lunetest] {stdio.color(color)}{total.passed} passed, {total.failed} failed{if #skipped > 0
			then `, {#skipped} skipped`
			else ""}{stdio.color("reset")} ({string.format(
			"%.2f",
			(DateTime.now().unixTimestampMillis - started) / 1000
		)}s)\n`
	)
	pcall(fs.removeFile, LOCK_FILE)
	process.exit(if total.failed > 0 then 1 else 0)
end

function cli.run(config: Config)
	-- The results listener keeps Lune alive, so an uncaught error here would hang the
	-- run forever with the lock held. Report it and exit instead.
	local ok, err = xpcall(run :: (...any) -> ...any, function(e)
		return debug.traceback(tostring(e), 2) -- tostring: Lune errors aren't always strings
	end, config)
	if not ok then
		fail(`internal error, please report it:\n{err}`)
	end
end

return cli
