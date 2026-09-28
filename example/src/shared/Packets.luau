--!strict
-- A tiny packet module in the style of ByteNet/Packet: sends are queued and flushed
-- once per frame over a single RemoteEvent.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Packets") :: RemoteEvent
local handlers: { [string]: (data: any, player: Player?) -> () } = {}
local queue: { { any } } = {}

local Packets = {}

function Packets.on(name: string, handler: (data: any, player: Player?) -> ())
	handlers[name] = handler
end

function Packets.send(name: string, data: any)
	table.insert(queue, { name, data })
end

local function receive(batch: { { any } }, player: Player?)
	for _, packet in batch do
		local handler = handlers[packet[1]]
		if handler then
			handler(packet[2], player)
		end
	end
end

if RunService:IsServer() then
	remote.OnServerEvent:Connect(function(player, batch)
		receive(batch, player)
	end)
else
	remote.OnClientEvent:Connect(receive)
end

RunService.Heartbeat:Connect(function()
	if #queue == 0 then
		return
	end
	local batch = queue
	queue = {}
	if RunService:IsServer() then
		remote:FireAllClients(batch)
	else
		remote:FireServer(batch)
	end
end)

return Packets
