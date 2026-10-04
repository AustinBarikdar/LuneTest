---
name: lunetest-testing
description: Write and run tests for Roblox / Luau code with LuneTest (`lune run test`). Use this whenever the user asks to write tests, add a spec, test a module or function, do TDD, cover a bug with a regression test, test RemoteEvents or packet/network code, or fix a failing `lune run test`, in any project that has a `tests/` folder with `*Spec.luau` files or a `.lune/test.luau` launcher. Also use it before changing game logic that has no tests yet, even if the user doesn't say the word "test".
---

# Writing tests with LuneTest

LuneTest runs Luau specs from the terminal. Good tests here follow the same proven practices as anywhere else; this skill gives you those practices and the exact LuneTest mechanics, so the tests you write are fast, readable, and actually catch bugs.

## The loop to follow

1. **Read the code under test** and find its require path. Paths come from the Rojo project (`default.project.json`): a file at `src/shared/Coins.luau` mapped under `ReplicatedStorage.Shared` is `require(ReplicatedStorage.Shared.Coins)`.
2. **Pick the level** (see "Where a test goes"). Default to unit.
3. **Write one failing test first.** Run it and read the failure. A test you have never seen fail may not be testing anything: a typo in the name, a wrong path, or an assertion that can't fail all look like a pass.
4. **Make it pass**, then add the next case. Keep each cycle small.
5. **Run the whole group before finishing** so you know you didn't break a neighbour.

For a bug fix, the first step is always a test that reproduces the bug and fails. Then fix the code. That test stays forever and stops the bug coming back.

When you add tests for code that already works, they pass on the first run, which proves little. Check that each one can fail: briefly change the expected value (or break the line of code it covers), see the failure, then put it back.

## Running

```sh
lune run test unit                 # all unit specs, milliseconds, no Studio
lune run test unit Economy         # only tests whose name contains "Economy"
lune run test unit Coins Wallet    # ...or "Coins" or "Wallet"
lune run test e2e                  # specs that need the real game
lune run test                      # everything
```

A test's full name is `[unit] Folder/SpecName › test name`, so a filter can be a folder, a spec, or one test. Exit code is 0 on success and 1 on any failure.

Each test prints a `PASS` or `FAIL` line, sorted by name, then a summary such as `[lunetest] 18 passed, 0 failed (0.02s)`. Failures give the file and line:

```
FAIL  [unit] Economy/CoinsSpec › rejects negative amounts
      ReplicatedStorage.LuneTestSpecs.Unit.Economy.CoinsSpec:12: expected function to throw
```

Prefer `lune run test unit <Filter>` while working. Plain `lune run test` and `lune run test e2e` can open Roblox Studio on the user's machine for a few seconds, so run them when the work calls for it, not on every edit.

## Where a test goes

| Put it in | When | Runs |
| --- | --- | --- |
| `tests/unit/` | Plain functions, data, math, parsing, state machines, and RemoteEvent / packet flows (via `LuneTest.network`) | Inside Lune, instantly |
| `tests/e2e/server/` | Needs the real server: physics, raycasts, characters, DataStores, engine services | Tried in Lune, then Studio if it fails there |
| `tests/e2e/shared/` | Shared modules that need a live game | Same, on the server |
| `tests/e2e/client/` | Needs a real client: `LocalPlayer.Character`, PlayerGui, UI, input | Same, on the client |

Write many unit tests and few e2e tests. Unit tests give an answer in milliseconds, so you can run them constantly; e2e tests are for the handful of things only the real engine can show. If logic is hard to unit test because it's tangled with engine calls, the better fix is usually to pull the logic into a plain function and unit test that.

Subfolders are groups: `tests/unit/Economy/CoinsSpec.luau` belongs to group `Economy`. Follow the layout the project already has: put a spec next to related specs, and only start a new folder when several specs share a feature. Name the spec after the module it tests (`Inventory.luau` → `InventorySpec.luau`).

New spec files are picked up automatically on the next run. There is nothing to register.

A unit spec that fails with `X is not a valid member of Y` is touching engine behavior Lune doesn't have. Move that spec to `tests/e2e/`.

## Spec format

A spec is a file whose name ends in `Spec` (other files in the test folders are helpers and never run). It returns a table of named test functions.

```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local expect = require(ReplicatedStorage.LuneTest).expect
local Coins = require(ReplicatedStorage.Shared.Coins)

return {
	["adds the amount to the balance"] = function()
		expect(Coins.add(10, 5)).toBe(15)
	end,

	["rejects negative amounts"] = function()
		expect(function()
			Coins.add(10, -1)
		end).toThrow("must be positive")
	end,
}
```

## What makes a good test

**Name the behavior, not the function.** `"rejects negative amounts"` tells the reader what broke when it fails; `"test add 2"` tells them nothing. Write names as short sentences about what the code does.

**One behavior per test.** When a test checks one thing, a failure points at one cause. Several `expect` calls are fine when they describe the same behavior.

**Arrange, act, assert.** Set up the inputs, do the one thing under test, then check the result. If a test needs a long setup, move the setup into a local helper function at the top of the spec.

**Cover more than the happy path.** For each function, think through:
- the normal case
- boundaries: `0`, `1`, the maximum, an empty table, an empty string, `nil`
- invalid input and the error it should raise
- every branch of each `if`

**Test through the public API.** Check what a module returns or does, not its private variables. Tests tied to internals break on every refactor even when behavior is unchanged. Data the module hands back counts as public: if a function returns a table, or a type is exported, its documented fields are fair to assert on.

**Use table-driven tests for many similar cases.** A loop that builds the tests keeps them short and makes gaps obvious:

```lua
local cases = {
	{ name = "zero", input = 0, expected = 0 },
	{ name = "rounds down", input = 1.9, expected = 1 },
	{ name = "negative", input = -3, expected = 0 },
}

local tests = {}
for _, case in cases do
	tests[`clamps {case.name}`] = function()
		expect(Stats.clamp(case.input)).toBe(case.expected)
	end
end
return tests
```

**Keep tests deterministic.** A test that passes sometimes is worse than no test. Avoid real time and real randomness: pass a clock, a seed, or the random value in as an argument. Don't wait with a fixed `task.wait(1)` and hope; after sending over the network use `network.flush()`, and when waiting on a condition, poll it with a deadline.

**Keep tests independent.** Tests run in name order, and there is no automatic reset between them: a module's state, a connection, or an instance left behind by one test is still there for the next. So build fresh state inside each test (a `makeWallet()` helper beats a shared `local wallet` at the top), and clean up what you create: `:Destroy()` instances, `:Disconnect()` connections. No test should depend on another having run first.

**Prefer fakes you write over the real dependency.** When code needs a clock, a data store or a network sender, give the module a way to receive it (an argument or a setter) and pass a small fake: a table that records the calls it gets. Then assert on what was recorded.

**Assert precisely.** `toEqual` for tables (`toEqual({})` checks a table is empty), `toBeCloseTo` for floats (never `toBe(0.3)`), and give `toThrow` the message text you expect so the test doesn't pass on some unrelated error. `toThrow` matches the text of both `error("...")` and `assert(cond, "...")`.

## Matchers

`expect(value)` followed by:

| Matcher | Passes when |
| --- | --- |
| `.toBe(x)` | `value == x` |
| `.toEqual(x)` | deep equality for tables |
| `.toBeTruthy()` / `.toBeFalsy()` | truthiness |
| `.toBeNil()` | `value == nil` |
| `.toBeA("Vector3")` | `typeof(value)` matches |
| `.toBeCloseTo(n, epsilon?)` | within `epsilon` (default 0.001) |
| `.toBeGreaterThan(n)` / `.toBeLessThan(n)` | numeric comparison |
| `.toContain(x)` | array contains `x`, or string contains substring `x` |
| `.toThrow(substring?)` | `value` is a function that errors (with that text) |

Put `.never` first to negate any of them: `expect(x).never.toBeNil()`.

## Testing network code without Studio

In unit specs, `LuneTest.network` runs client code and server code together, with working `RemoteEvent`, `UnreliableRemoteEvent` and `RemoteFunction`, and `RunService.Heartbeat` ticking. Packet libraries built on remotes work as they are.

```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LuneTest = require(ReplicatedStorage.LuneTest)
local expect, network = LuneTest.expect, LuneTest.network

return {
	["server answers a ping from the client"] = function()
		local remote = Instance.new("RemoteEvent")
		remote.Parent = ReplicatedStorage

		network.server(function()
			remote.OnServerEvent:Connect(function(player, message)
				remote:FireClient(player, message .. " pong")
			end)
		end)

		local reply: string? = nil
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
```

| Call | Does |
| --- | --- |
| `network.server(fn, ...)` | Runs `fn` as the server and returns its results. Code outside either call also runs as the server. |
| `network.client(fn, ...)` | Runs `fn` as the client: `RunService:IsClient()` is true, `Players.LocalPlayer` is set. |
| `network.flush(frames?)` | Lets queued remote messages and per-frame batches deliver, then re-raises any error a handler hit. Call it between sending and asserting. |
| `network.spy(remote)` | Returns a live list of `{ direction = "toServer" \| "toClient", args = {...} }` for everything sent through `remote`. |
| `network.player()` | The simulated player. |

Things to know:
- `require` a module **inside** `network.client` / `network.server` to get that side's own copy, exactly like a real client and server each loading the module.
- Messages arrive on a later frame, as in Roblox. Asserting right after `FireServer` without `network.flush()` checks too early.
- An error inside a remote handler fails the test at the next `flush`, `client` or `server` call.
- There is one simulated player and no character. Anything needing `Character` belongs in `tests/e2e/client/`.

If the project declares its remotes in the launcher config, they already exist in every test:

```lua
-- .lune/test.luau
remotes = {
	["ReplicatedStorage.Remotes"] = { "Chat", GetData = "RemoteFunction" },
},
```

## e2e specs

Same format, placed under `tests/e2e/server`, `shared` or `client`. Client specs start after the local character has spawned. Each test has a timeout (30 seconds unless the config changes it), so prefer `WaitForChild(name, 10)` with a real limit over waiting forever.

If an e2e run stops with "no local port could be opened", you are running in a sandbox that blocks network ports, so Studio can't report back. Unit tests still work there. Don't try to work around it: finish with `lune run test unit`, and tell the user to run `lune run test e2e` themselves.

LuneTest first tries each e2e spec in Lune and only sends the ones that fail there to Studio, whose result is final. You don't need to do anything for this; it just means an e2e spec that turns out to be pure logic is still fast. `lune run test --fresh` forces every spec to be retried in Lune.

## Strict mode

Specs should start with `--!strict`. Two things that trip it up:

- A local assigned inside a callback needs a type, or it's inferred as `nil`: write `local reply: string? = nil`, not `local reply`.
- A table mixing value types needs an annotation: `local batch: { any } = { "Ping", 5 }`.

## Before you finish

- Every new test was seen failing once, then passing.
- Names read as behaviors.
- Happy path, boundaries and error path are covered for the code you touched.
- No fixed sleeps, no leftover instances or connections, no dependence on test order.
- `lune run test unit` passes. If you added or changed e2e specs, `lune run test e2e` passes too.

Don't edit or commit files whose names start with `lunetest.` (`lunetest.project.json`, `lunetest.rbxl`, `lunetest.rbxl.lock`, `lunetest.cache.json`, `lunetest.lock`); LuneTest generates them on every run.
