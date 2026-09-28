--!strict
-- Assertions. Matchers error with a readable message; the runner adds the spec line.
-- `expect(x).never.toBe(y)` negates any matcher.

local function show(value: any, depth: number?): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	if type(value) ~= "table" then
		return `{tostring(value)} ({typeof(value)})`
	end
	if (depth or 0) >= 2 then
		return "{...}"
	end
	local parts = {}
	for key, child in value do
		table.insert(parts, `[{show(key, 2)}] = {show(child, (depth or 0) + 1)}`)
	end
	table.sort(parts)
	return `\{ {table.concat(parts, ", ")} }`
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

export type Matchers = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
	toBeNil: () -> (),
	toBeA: (typeName: string) -> (),
	toBeCloseTo: (expected: number, epsilon: number?) -> (),
	toBeGreaterThan: (expected: number) -> (),
	toBeLessThan: (expected: number) -> (),
	toContain: (item: any) -> (),
	toThrow: (substring: string?) -> (),
}
export type Expectation = Matchers & { never: Matchers }

local function matchers(value: any, negated: boolean): Matchers
	-- Level 0: Luau inlines small functions, so error levels can't reliably find the
	-- spec line. The runner adds it from the traceback instead.
	local function check(pass: boolean, message: string)
		if pass == negated then
			error(if negated then `expected not: {message}` else `expected {message}`, 0)
		end
	end

	return {
		toBe = function(expected)
			check(value == expected, `{show(value)} to be {show(expected)}`)
		end,
		toEqual = function(expected)
			check(deepEqual(value, expected), `{show(value)} to deep-equal {show(expected)}`)
		end,
		toBeTruthy = function()
			check(not not value, `{show(value)} to be truthy`)
		end,
		toBeFalsy = function()
			check(not value, `{show(value)} to be falsy`)
		end,
		toBeNil = function()
			check(value == nil, `{show(value)} to be nil`)
		end,
		toBeA = function(typeName)
			check(typeof(value) == typeName, `{show(value)} to be a {typeName}`)
		end,
		toBeCloseTo = function(expected, epsilon)
			check(
				type(value) == "number" and math.abs(value - expected) <= (epsilon or 1e-3),
				`{show(value)} to be within {epsilon or 1e-3} of {expected}`
			)
		end,
		toBeGreaterThan = function(expected)
			check(type(value) == "number" and value > expected, `{show(value)} to be > {expected}`)
		end,
		toBeLessThan = function(expected)
			check(type(value) == "number" and value < expected, `{show(value)} to be < {expected}`)
		end,
		toContain = function(item)
			local found = false
			if type(value) == "string" then
				found = string.find(value, tostring(item), 1, true) ~= nil
			elseif type(value) == "table" then
				found = table.find(value, item) ~= nil
			end
			check(found, `{show(value)} to contain {show(item)}`)
		end,
		toThrow = function(substring)
			if type(value) ~= "function" then
				error("toThrow expects a function", 0)
			end
			local ok, err = pcall(value)
			local matches = not ok and (substring == nil or string.find(tostring(err), substring, 1, true) ~= nil)
			check(matches, if substring then `function to throw containing {show(substring)}, got {show(err)}` else "function to throw")
		end,
	}
end

local function expect(value: any): Expectation
	local expectation = matchers(value, false) :: any
	expectation.never = matchers(value, true)
	return expectation
end

return expect
