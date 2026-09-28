--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local expect = require(ReplicatedStorage.LuneTest).expect

-- Unit specs run inside Lune in milliseconds: use them for plain functions.
return {
	["math still works"] = function()
		expect(1 + 1).toBe(2)
		expect({ a = { 1, 2 } }).toEqual({ a = { 1, 2 } })
		expect(0.1 + 0.2).toBeCloseTo(0.3)
	end,

	["errors can be asserted"] = function()
		expect(function()
			error("boom")
		end).toThrow("boom")
	end,
}
