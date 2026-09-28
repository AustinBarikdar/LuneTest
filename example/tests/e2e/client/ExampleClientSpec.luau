--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local expect = require(ReplicatedStorage.LuneTest).expect

return {
	["has a character"] = function()
		expect(Players.LocalPlayer.Character).never.toBeNil()
	end,
}
