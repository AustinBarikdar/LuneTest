--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local expect = require(ReplicatedStorage.LuneTest).expect

return {
	["runs on the server"] = function()
		expect(RunService:IsServer()).toBe(true)
	end,
}
