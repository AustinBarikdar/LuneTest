--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LuneTest = require(ReplicatedStorage.LuneTest)
local expect, network = LuneTest.expect, LuneTest.network

-- network simulates client <-> server remotes inside Lune, so packet flows test without Studio.
return {
	["client -> server -> client round trip"] = function()
		local remote = Instance.new("RemoteEvent")
		remote.Name = "Ping"
		remote.Parent = ReplicatedStorage

		network.server(function()
			remote.OnServerEvent:Connect(function(player, message)
				remote:FireClient(player, message .. " pong")
			end)
		end)

		local reply
		network.client(function()
			remote.OnClientEvent:Connect(function(message)
				reply = message
			end)
			remote:FireServer("ping")
		end)

		network.flush()
		expect(reply).toBe("ping pong")
		remote:Destroy()
	end,
}
