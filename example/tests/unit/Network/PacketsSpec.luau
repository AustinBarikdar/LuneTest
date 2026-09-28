--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LuneTest = require(ReplicatedStorage.LuneTest)
local expect, network = LuneTest.expect, LuneTest.network

local Remotes = ReplicatedStorage.Remotes
local PacketsModule = ReplicatedStorage.Shared.Packets

return {
	["remotes from the config table exist"] = function()
		expect(Remotes.Packets.ClassName).toBe("RemoteEvent")
		expect(Remotes.GetProfile.ClassName).toBe("RemoteFunction")
	end,

	["each realm gets its own copy of a module"] = function()
		local server = network.server(function()
			return require(PacketsModule), RunService:IsServer()
		end)
		local client, isClient = network.client(function()
			return require(PacketsModule), RunService:IsClient()
		end)
		expect(server).never.toBe(client)
		expect(isClient).toBe(true)
	end,

	["batched packets go client -> server -> client"] = function()
		local fromPlayer, echoed
		network.server(function()
			local Packets = require(PacketsModule)
			Packets.on("Hello", function(data, player)
				fromPlayer = player
				Packets.send("Echo", { n = data.n + 1 })
			end)
		end)
		network.client(function()
			local Packets = require(PacketsModule)
			Packets.on("Echo", function(data)
				echoed = data
			end)
			Packets.send("Hello", { n = 1 })
		end)
		network.flush()
		expect(fromPlayer).toBe(network.player())
		expect(echoed).toEqual({ n = 2 })
	end,

	["RemoteFunction invokes the server and returns"] = function()
		network.server(function()
			Remotes.GetProfile.OnServerInvoke = function(player, key)
				return { name = player.Name, key = key }
			end
		end)
		local profile = network.client(function()
			return Remotes.GetProfile:InvokeServer("coins")
		end)
		expect(profile).toEqual({ name = "Player1", key = "coins" })
	end,

	["spy records what crossed the wire"] = function()
		local log = network.spy(Remotes.Packets)
		network.client(function()
			require(PacketsModule).send("Ping", 5)
		end)
		network.flush()
		expect(#log).toBe(1)
		expect(log[1].direction).toBe("toServer")
		local batch: { { any } } = { { "Ping", 5 } }
		expect(log[1].args[1]).toEqual(batch)
	end,

	["an erroring handler fails the test"] = function()
		local remote = Instance.new("RemoteEvent")
		remote.Parent = ReplicatedStorage
		network.server(function()
			remote.OnServerEvent:Connect(function()
				error("server handler broke")
			end)
		end)
		network.client(function()
			remote:FireServer()
		end)
		expect(function()
			network.flush()
		end).toThrow("server handler broke")
		remote:Destroy()
	end,
}
