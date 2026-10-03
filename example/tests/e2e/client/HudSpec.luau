--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local expect = require(ReplicatedStorage.LuneTest).expect

-- PlayerGui only exists in a real client, so this spec always needs Studio.
return {
	["PlayerGui exists"] = function()
		expect(Players.LocalPlayer:WaitForChild("PlayerGui")).never.toBeNil()
	end,
	["StarterGui is copied in"] = function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		expect(playerGui:IsA("PlayerGui")).toBe(true)
	end,
}
