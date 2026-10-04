--!strict
-- Simulated client <-> server networking for unit specs running inside Lune.
--
-- Every thread belongs to a realm ("server" or "client"). RunService:IsServer()/IsClient()
-- answer for the calling thread's realm, modules are required once per realm, and
-- RemoteEvents / UnreliableRemoteEvents / RemoteFunctions loop back between realms the
-- way Roblox delivers them (deferred, arguments copied). Packet libraries built on
-- remotes and RunService.Heartbeat therefore work with no setup.

local roblox = require("@lune/roblox")
local task = require("@lune/task")

type Realm = "server" | "client"

local realmOf: { [thread]: Realm } = setmetatable({}, { __mode = "k" }) :: any

local function currentRealm(): Realm
	-- Untagged threads (the spec itself) act as the server, like Studio's server bucket.
	return realmOf[coroutine.running()] or "server"
end

-- Errors thrown inside simulated handlers; surfaced by network.flush() and network.client/server.
local handlerErrors: { string } = {}

local function spawnIn(realm: Realm, fn: (...any) -> ...any, ...: any): thread
	local co = coroutine.create(function(...)
		local ok, err = xpcall(fn, debug.traceback, ...)
		if not ok then
			table.insert(handlerErrors, `[{realm}] {err}`)
		end
	end)
	realmOf[co] = realm
	return task.spawn(co, ...)
end

-- task/coroutine replacements handed to module environments: new threads inherit the
-- creator's realm, so a server module's task.spawn keeps behaving as the server.
local realmTask: any = table.clone(task)
local function tag(fn: any): any
	if type(fn) ~= "function" then
		return fn -- already a thread
	end
	local co = coroutine.create(fn)
	realmOf[co] = currentRealm()
	return co
end
realmTask.spawn = function(fn, ...)
	return task.spawn(tag(fn), ...)
end
realmTask.defer = function(fn, ...)
	return task.defer(tag(fn), ...)
end
realmTask.delay = function(seconds, fn, ...)
	return task.delay(seconds, tag(fn), ...)
end

local realmCoroutine: any = table.clone(coroutine)
realmCoroutine.create = function(fn)
	return tag(fn)
end
realmCoroutine.wrap = function(fn)
	local co = tag(fn)
	return function(...)
		local result = table.pack(coroutine.resume(co, ...))
		if not result[1] then
			error(result[2], 2)
		end
		return table.unpack(result, 2, result.n)
	end
end

-- Minimal RBXScriptSignal. `queue` holds fires until someone connects, like remotes do.
local function Signal(queue: boolean?)
	local connections = {}
	local pending: { any }? = if queue then {} else nil
	local signal = {}

	function signal:Connect(fn)
		local connection: any = { Connected = true, fn = fn, realm = currentRealm() }
		function connection:Disconnect()
			connection.Connected = false
			local index = table.find(connections, connection)
			if index then
				table.remove(connections, index)
			end
		end
		table.insert(connections, connection)
		if pending and #pending > 0 then
			local queued = pending
			pending = {}
			for _, args in queued do
				spawnIn(connection.realm, fn, table.unpack(args, 1, args.n))
			end
		end
		return connection
	end

	function signal:Once(fn)
		local connection: any
		connection = signal:Connect(function(...)
			connection:Disconnect()
			fn(...)
		end)
		return connection
	end

	function signal:Wait()
		local thread = coroutine.running()
		signal:Once(function(...)
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end

	function signal:Fire(...)
		if #connections == 0 and pending then
			table.insert(pending, table.pack(...))
			return
		end
		for _, connection in table.clone(connections) do
			if connection.Connected then
				spawnIn(connection.realm, connection.fn, ...)
			end
		end
	end

	function signal:HasConnections(): boolean
		return #connections > 0
	end

	return signal
end

-- Roblox copies tables (dropping metatables) and buffers when they cross the network.
local function copy(value: any): any
	if type(value) == "table" then
		local out = {}
		for key, child in value do
			out[copy(key)] = copy(child)
		end
		return out
	elseif type(value) == "buffer" then
		local out = buffer.create(buffer.len(value))
		buffer.copy(out, 0, value)
		return out
	end
	return value
end

local function copyArgs(...: any): { n: number, [number]: any }
	local args = table.pack(...)
	for i = 1, args.n do
		args[i] = copy(args[i])
	end
	return args
end

return function(game: any, waitTimeout: number)
	local Players = game:GetService("Players")
	local network = {}
	local player: any = nil
	local playerAdded, playerRemoving = Signal(), Signal()
	local spies: { [any]: { any } } = setmetatable({}, { __mode = "k" }) :: any

	local function record(remote: any, direction: string, args: { n: number, [number]: any })
		local log = spies[remote]
		if log then
			table.insert(log, { direction = direction, args = { table.unpack(args, 1, args.n) } })
		end
	end

	-- The simulated player joins the first time client code runs, firing PlayerAdded.
	local function ensurePlayer(): any
		if not player then
			player = roblox.Instance.new("Player")
			player.Name = "Player1"
			player.UserId = 1
			player.Parent = Players
			Players.LocalPlayer = player
			playerAdded:Fire(player)
		end
		return player
	end

	-- Per-instance signals and callbacks, created on first access.
	local signals: { [any]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any
	local function signalOf(instance: any, name: string): any
		signals[instance] = signals[instance] or {}
		local signal = signals[instance][name]
		if not signal then
			signal = Signal(true)
			signals[instance][name] = signal
		end
		return signal
	end

	for _, class in { "RemoteEvent", "UnreliableRemoteEvent" } do
		roblox.implementProperty(class, "OnServerEvent", function(self)
			return signalOf(self, "OnServerEvent")
		end)
		roblox.implementProperty(class, "OnClientEvent", function(self)
			return signalOf(self, "OnClientEvent")
		end)
		roblox.implementMethod(class, "FireServer", function(self, ...)
			local args = copyArgs(...)
			record(self, "toServer", args)
			local from = ensurePlayer()
			task.defer(function()
				signalOf(self, "OnServerEvent"):Fire(from, table.unpack(args, 1, args.n))
			end)
		end)
		local function toClient(self, args)
			record(self, "toClient", args)
			task.defer(function()
				signalOf(self, "OnClientEvent"):Fire(table.unpack(args, 1, args.n))
			end)
		end
		roblox.implementMethod(class, "FireClient", function(self, target, ...)
			if target == player then -- one simulated player; others don't exist
				toClient(self, copyArgs(...))
			end
		end)
		roblox.implementMethod(class, "FireAllClients", function(self, ...)
			if player then
				toClient(self, copyArgs(...))
			end
		end)
	end

	-- RemoteFunction callbacks run in the realm that assigned them.
	local callbacks: { [any]: { [string]: { fn: any, realm: Realm } } } = setmetatable({}, { __mode = "k" }) :: any
	local function invoke(self: any, name: string, direction: string, args: { n: number, [number]: any }, ...: any)
		record(self, direction, args)
		local deadline = os.clock() + waitTimeout
		while not (callbacks[self] and callbacks[self][name]) and os.clock() < deadline do
			task.wait()
		end
		local callback = callbacks[self] and callbacks[self][name]
		if not callback then
			error(`{self:GetFullName()}.{name} was never assigned`, 3)
		end
		local result: any = nil
		local prefix = table.pack(...)
		spawnIn(callback.realm, function()
			local all = table.move(args, 1, args.n, prefix.n + 1, table.clone(prefix))
			result = table.pack(pcall(callback.fn, table.unpack(all, 1, prefix.n + args.n)))
		end)
		while result == nil do
			task.wait()
		end
		if not result[1] then
			error(result[2], 3)
		end
		local returned = copyArgs(table.unpack(result, 2, result.n))
		return table.unpack(returned, 1, returned.n)
	end
	for _, name in { "OnServerInvoke", "OnClientInvoke" } do
		roblox.implementProperty("RemoteFunction", name, function(self)
			return callbacks[self] and callbacks[self][name] and callbacks[self][name].fn
		end, function(self, fn)
			callbacks[self] = callbacks[self] or {}
			callbacks[self][name] = if fn then { fn = fn, realm = currentRealm() } else nil :: any
		end)
	end
	roblox.implementMethod("RemoteFunction", "InvokeServer", function(self, ...)
		return invoke(self, "OnServerInvoke", "toServer", copyArgs(...), ensurePlayer())
	end)
	roblox.implementMethod("RemoteFunction", "InvokeClient", function(self, target, ...)
		return invoke(self, "OnClientInvoke", "toClient", copyArgs(...))
	end)

	roblox.implementMethod("RunService", "IsServer", function()
		return currentRealm() == "server"
	end)
	roblox.implementMethod("RunService", "IsClient", function()
		return currentRealm() == "client"
	end)
	roblox.implementMethod("RunService", "IsStudio", function()
		return true
	end)
	roblox.implementMethod("RunService", "IsRunning", function()
		return true
	end)
	roblox.implementMethod("RunService", "IsEdit", function()
		return false
	end)

	-- Frame events tick from one loop, started when first used.
	local frameSignals: { [string]: any } = {}
	local ticking = false
	for _, name in { "Heartbeat", "PostSimulation", "PreSimulation", "Stepped", "RenderStepped", "PreRender", "PreAnimation" } do
		roblox.implementProperty("RunService", name, function()
			if not frameSignals[name] then
				frameSignals[name] = Signal()
			end
			if not ticking then
				ticking = true
				task.spawn(function()
					local clock, last = 0, os.clock()
					while true do
						task.wait()
						local now = os.clock()
						local dt = now - last
						clock, last = clock + dt, now
						for signalName, signal in frameSignals do
							if signal:HasConnections() then
								if signalName == "Stepped" then
									signal:Fire(clock, dt)
								else
									signal:Fire(dt)
								end
							end
						end
					end
				end)
			end
			return frameSignals[name]
		end)
	end

	roblox.implementProperty("Players", "PlayerAdded", function()
		return playerAdded
	end)
	roblox.implementProperty("Players", "PlayerRemoving", function()
		return playerRemoving
	end)
	roblox.implementMethod("Players", "GetPlayers", function()
		return if player then { player } else {}
	end)

	-- Roblox's WaitForChild yields; here the other realm may create it a frame later.
	roblox.implementMethod("Instance", "WaitForChild", function(self, name, timeout)
		-- Timed by the clock: task.wait() under-reports how long it slept on Windows.
		local limit = timeout or waitTimeout
		local deadline = os.clock() + limit
		local found = self:FindFirstChild(name)
		while not found and os.clock() < deadline do
			task.wait()
			found = self:FindFirstChild(name)
		end
		if not found and not timeout then
			error(`WaitForChild("{name}") on {self:GetFullName()} found nothing after {limit}s`, 2)
		end
		return found
	end)

	local function throwHandlerErrors()
		if #handlerErrors > 0 then
			local message = table.concat(handlerErrors, "\n")
			table.clear(handlerErrors)
			error(`a network handler errored:\n{message}`, 0)
		end
	end

	-- Runs `fn` as that realm, waits for it, and returns what it returned.
	local function runAs(realm: Realm, fn: (...any) -> ...any, ...: any): ...any
		if realm == "client" then
			ensurePlayer()
		end
		local result: any = nil
		local co = coroutine.create(function(...)
			result = table.pack(xpcall(fn, function(err)
				return tostring(err)
			end, ...))
		end)
		realmOf[co] = realm
		task.spawn(co, ...)
		while result == nil do
			task.wait()
		end
		if not result[1] then
			error(`[{realm}] {result[2]}`, 0)
		end
		throwHandlerErrors()
		return table.unpack(result, 2, result.n)
	end

	function network.client(fn: (...any) -> ...any, ...: any): ...any
		return runAs("client", fn, ...)
	end

	function network.server(fn: (...any) -> ...any, ...: any): ...any
		return runAs("server", fn, ...)
	end

	-- Lets deferred remote deliveries and a few Heartbeats happen, then rethrows any
	-- error a handler hit on the way.
	function network.flush(frames: number?)
		for _ = 1, frames or 3 do
			task.wait()
		end
		throwHandlerErrors()
	end

	-- Records every message through `remote`: { direction = "toServer" | "toClient", args = {...} }.
	function network.spy(remote: any): { { direction: string, args: { any } } }
		spies[remote] = spies[remote] or {}
		return spies[remote]
	end

	function network.player(): any
		return ensurePlayer()
	end

	return network,
		{
			task = realmTask,
			coroutine = realmCoroutine,
			realm = currentRealm,
		}
end
