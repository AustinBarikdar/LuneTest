--!strict
local Coins = {}

function Coins.add(balance: number, amount: number): number
	assert(amount >= 0, "amount must be positive")
	return balance + amount
end

return Coins
