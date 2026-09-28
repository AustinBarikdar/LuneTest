# LuneTest

A Roblox testing framework for Rojo projects that you run from the terminal with one command:

```
$ lune run test
  PASS  [unit] Economy/CoinsSpec › adds coins
  PASS  [unit] Network/PacketsSpec › batched packets go client -> server -> client
  FAIL  [unit] Economy/CoinsSpec › rejects negative amounts
        ReplicatedStorage.LuneTestSpecs.Unit.Economy.CoinsSpec:12: expected function to throw
[lunetest] running 2 e2e specs in Studio...
  PASS  [server] ExampleServerSpec › runs on the server
  PASS  [client] ExampleClientSpec › has a character

[lunetest] 12 passed, 1 failed (8.06s)
```

There are two kinds of test:

| Kind | Folder | Runs | Speed |
| --- | --- | --- | --- |
| **unit** | `tests/unit/` | Inside Lune, against your Rojo-built place. No Studio. | milliseconds |
| **e2e** | `tests/e2e/{server,client,shared}/` | Tried in Lune first. Any spec that fails there is rerun in a real Studio Play session. | Instant if Lune passes, ~8s if Studio is needed |

Studio only opens when at least one e2e spec actually needs it. When the run is over, the test place closes. If LuneTest launched Studio, Studio quits too.

The exit code is 0 when everything passes and 1 when something fails, so it works in scripts and CI.

## Requirements

- [Rojo](https://rojo.space) 7, [Lune](https://lune-org.github.io/docs) 0.10+ and [Wally](https://wally.run). With [Rokit](https://github.com/rojo-rbx/rokit): `rokit add rojo`, `rokit add lune`, `rokit add wally`.
- For e2e specs only: Roblox Studio on macOS or Windows, signed in.

## Setup

1. Add LuneTest to `wally.toml`:

   ```toml
   [dev-dependencies]
   LuneTest = "austinbarikdar/lunetest@0.1.0"
   ```

2. Install it and run `init` from your project root:

   ```sh
   wally install
   lune run DevPackages/_Index/*/lunetest/lune/init.luau
   ```

   On Windows PowerShell:

   ```powershell
   wally install
   lune run (Resolve-Path DevPackages/_Index/*/lunetest/lune/init.luau)
   ```

`init` never overwrites anything, so it's safe to run again. It creates:

- **`.lune/test.luau`**: the launcher and your config. If you already have a `lune/` folder, it goes at `lune/test.luau` instead.
- **`tests/`**: example unit and e2e specs.
- **`.gitignore` entries**: for the generated `lunetest.project.json` and `lunetest.rbxlx`.
- **The Studio plugin**: `LuneTest.rbxmx` in your Studio Plugins folder. **Restart Studio once** if it was already open.

Lune runs `lune/test.luau` before `.lune/test.luau`. If you already have a `lune/test.luau`, `init` tells you instead of writing a second launcher that would never run.

## Running

```sh
lune run test                        # everything
lune run test unit                   # unit specs only (no Studio)
lune run test e2e                    # e2e specs only
lune run test unit Economy           # tests whose name contains "Economy"
lune run test unit Economy Network   # ...or "Network"
lune run test e2e server             # e2e tests whose name contains "server"
```

A test's full name is `[kind] Group/SubGroup/SpecName › test name`. Any subfolder is a group, so filters can pick a folder, a spec file or a single test.

## Writing specs

A spec is a ModuleScript whose name ends in `Spec`. Everything in LuneTest is written in `--!strict`, including `expect` and `LuneTest.network`, so your specs can be too. It returns a table of named test functions. Other modules in the spec folders are treated as helpers and never run.

```lua
--!strict
-- tests/unit/Economy/CoinsSpec.luau
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
```

| Folder | Runs on | Lives in the test place at |
| --- | --- | --- |
| `tests/unit` | Lune | `ReplicatedStorage.LuneTestSpecs.Unit` |
| `tests/e2e/server` | Studio server | `ServerScriptService.LuneTestSpecs.Server` |
| `tests/e2e/shared` | Studio server | `ReplicatedStorage.LuneTestSpecs.Shared` |
| `tests/e2e/client` | Studio client | `ReplicatedStorage.LuneTestSpecs.Client` |

Each test runs in its own thread with a timeout (`testTimeout`, default 30s). A stuck `WaitForChild` fails only that test instead of hanging the whole run. Tests run in name order.

### Matchers

`toBe`, `toEqual` (deep), `toBeTruthy`, `toBeFalsy`, `toBeNil`, `toBeA(typeName)`, `toBeCloseTo(n, epsilon?)`, `toBeGreaterThan`, `toBeLessThan`, `toContain` (works on arrays and substrings), and `toThrow(substring?)`.

Put `.never` in front of any matcher to negate it: `expect(x).never.toBeNil()`.

### What unit specs can use

Unit specs get:
- **The Rojo-built place:** `game`, `workspace`, `script`, and `require` of any ModuleScript in it.
- **Lune's Roblox types:** `Instance`, `Vector3`, `CFrame`, `Enum` and the rest.
- **`task`.**
- **The simulated network** (below).

Engine behavior is not there: no physics, no characters, no DataStores. Put tests that need those in `e2e`.

## Lune first, Studio fallback (e2e specs)

Many specs written for Studio pass in Lune too. So LuneTest tries every e2e spec in Lune first:

```
  PASS  [server] ExampleServerSpec › runs on the server  (lune)
[lunetest] 2 of 3 e2e specs need Studio
[lunetest] running in Studio...
  PASS  [server] Combat/RaycastSpec › ray into empty space hits nothing  (studio)
  PASS  [client] ExampleClientSpec › has a character  (studio)
```

- **In Lune:** server and shared specs run as the simulated server, and client specs run as the simulated client.
- **A spec with any failure in Lune is rerun in Studio.** This covers a real bug, a missing engine feature like `workspace:Raycast`, and a character that doesn't exist. Studio's result is final, so a gap in Lune can never produce a false failure.
- **The Lune attempt is fast.** A spec stops at its first failure, and each test gets 5 seconds, so specs that need Studio hand over quickly.
- **Studio only runs the specs that fell back,** and it doesn't open at all if everything passed in Lune.
- **Each line says where the test ran:** `(lune)` or `(studio)`.

Set `fallback = false` in the config to always run e2e specs in Studio.

## Simulated network (unit specs)

`LuneTest.network` runs client and server code together inside Lune, so networking and packet code can be tested without opening Studio.

```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LuneTest = require(ReplicatedStorage.LuneTest)
local expect, network = LuneTest.expect, LuneTest.network

return {
	["client -> server -> client"] = function()
		local fromPlayer, echoed
		network.server(function()
			local Packets = require(ReplicatedStorage.Shared.Packets)
			Packets.on("Hello", function(data, player)
				fromPlayer = player
				Packets.send("Echo", { n = data.n + 1 })
			end)
		end)
		network.client(function()
			local Packets = require(ReplicatedStorage.Shared.Packets)
			Packets.on("Echo", function(data)
				echoed = data
			end)
			Packets.send("Hello", { n = 1 })
		end)

		network.flush()
		expect(fromPlayer).toBe(network.player())
		expect(echoed).toEqual({ n = 2 })
	end,
}
```

| API | What it does |
| --- | --- |
| `network.client(fn, ...)` | Runs `fn` as the client and returns what it returns. `RunService:IsClient()` is true and `Players.LocalPlayer` is set. |
| `network.server(fn, ...)` | Runs `fn` as the server. Spec code outside either call also counts as the server. |
| `network.flush(frames?)` | Waits a few frames (default 3) so queued remotes and `Heartbeat` batches get delivered, then re-throws any error a handler hit. |
| `network.spy(remote)` | Returns a live list of `{ direction = "toServer" \| "toClient", args = {...} }` for everything sent through `remote`. |
| `network.player()` | The simulated player. It joins, firing `Players.PlayerAdded`, the first time client code runs. From then on, `Players.LocalPlayer` is set for server code too (one shared `Players` service). |

How it behaves:
- **Modules load once per side.** Code inside `network.client` gets its own copy of every module, just like a real client.
- **Remotes behave like Roblox.** `RemoteEvent`, `UnreliableRemoteEvent` and `RemoteFunction` (`FireServer`, `FireClient`, `FireAllClients`, `InvokeServer`, `InvokeClient`) deliver on the next frame and copy their arguments. Events sent before anyone connects are queued.
- **Frame events tick.** `RunService.Heartbeat`, `Stepped`, `PostSimulation` and the other frame events fire every frame, so packet libraries that batch per frame (ByteNet, Packet, custom ones) work without any setup.
- **Handler errors fail the test.** If a remote handler errors, the next `network.flush()`, `network.client()` or `network.server()` fails with that error.

### Custom packet handlers

No setup is needed for libraries built on remotes. If your packet module lets you replace its transport, you can test the logic without remotes instead. Call the server handler directly inside `network.server(function() ... end)` with the data your client code produced in `network.client`.

## Remotes table

If your game keeps its remotes in a table, declare it in the launcher config. LuneTest creates the instances in the test place, so they exist in unit **and** e2e runs:

```lua
remotes = {
	["ReplicatedStorage.Remotes"] = {
		"Chat",                        -- a bare name is a RemoteEvent
		GetData = "RemoteFunction",
		Move = "UnreliableRemoteEvent",
	},
},
```

The keys are parent paths. Folders along the path are created if they don't exist, and if the folder is already in your project, the remotes are added to it.

## Config

The config is the table at the top of `.lune/test.luau`:

| Key | Default | Meaning |
| --- | --- | --- |
| `project` | `"default.project.json"` | Base Rojo project. Your file is never changed. LuneTest writes `lunetest.project.json` next to it. |
| `unit` | `"tests/unit"` | Unit spec folder |
| `e2e` | `"tests/e2e"` | Folder holding `server/`, `client/` and `shared/` |
| `testTimeout` | `30` | Seconds before a single test counts as hung |
| `timeout` | `300` | Seconds to wait for Studio to report back |
| `clientTimeout` | `90` | Seconds the Studio client gets to *start*. Once started, it's only limited by per-test timeouts. |
| `port` | `44774` | First port tried for Studio's results. If it's taken, the next free one is used. |
| `remotes` | none | See [Remotes table](#remotes-table) |
| `fallback` | `true` | Try e2e specs in Lune first and send only the failures to Studio |

If your project is a library, meaning its tree isn't a `DataModel`, LuneTest mounts it at `ReplicatedStorage.<project name>`.

## Reliability on slow machines

- **Starting Play:** the plugin starts Play through `StudioTestService` and retries with backoff. It never sends keystrokes, so it can't press Play in the wrong window.
- **Client startup:** the client reports "started" as soon as it loads. The server waits for that signal, not for a fixed amount of time, so a slow client is never cut off halfway through.
- **Stale results:** each run has a random ID, and results from an old or unrelated Studio are ignored.
- **Parallel runs:** if the port is taken, the next free one is used, so two projects can run at the same time.
- **Updated plugin:** if the plugin was just updated while Studio is open, the run stops immediately and tells you to restart Studio, instead of waiting for the timeout.
- **Back-to-back runs on macOS:** if `open` hands the place to a Studio that's still quitting and nothing launches, LuneTest notices and opens it again.

## Troubleshooting

- **"updated the LuneTest Studio plugin…"**: close Studio and run again.
- **`no results from Studio`**: check Studio's Output window. The runners print `[LuneTest] N passed, M failed` when they finish.
- **A unit spec says something `is not a valid member`**: that's engine behavior Lune doesn't have. Move the spec to `tests/e2e`.

## Developing LuneTest

`example/` is a small project that uses every feature. Wally has no local path dependencies, so link this repo into it by hand:

```sh
mkdir -p example/DevPackages/_Index/austinbarikdar_lunetest@0.1.0
ln -s "$PWD" example/DevPackages/_Index/austinbarikdar_lunetest@0.1.0/lunetest
cd example && lune run test
```

Type-check everything in strict mode (needs Roblox's `globalTypes.d.luau` from the luau-lsp repo, and `lune setup` for the `.luaurc` alias):

```sh
cd example && rojo sourcemap lunetest.project.json -o sourcemap.json
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src tests DevPackages/_Index/*/lunetest/src DevPackages/_Index/*/lunetest/runners
cd .. && luau-lsp analyze --platform=standard lune example/.lune/test.luau
```

To publish: `wally login`, then `wally publish`.
