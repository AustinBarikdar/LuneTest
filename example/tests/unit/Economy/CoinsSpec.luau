--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local expect = require(ReplicatedStorage.LuneTest).expect
local Coins = require(ReplicatedStorage.Shared.Coins)

return {
	["adds coins"] = function()
		expect(Coins.add(10, 5)).toBe(15)
	end,

	["rejects negative amounts"] = function()
		expect(function()
			Coins.add(10, -1)
		end).toThrow("must be positive")
	end,
}
