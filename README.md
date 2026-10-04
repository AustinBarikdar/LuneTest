<div align="center">

<img src="https://raw.githubusercontent.com/AustinBarikdar/LuneTest/main/docs/logo.svg" width="104" alt="LuneTest logo">

# LuneTest

**Test your Roblox game from the terminal.**

One command runs your specs. Plain logic finishes in milliseconds without opening Studio,<br>
and tests that need the real engine run in Studio or on Roblox's own servers.

[![CI](https://github.com/AustinBarikdar/LuneTest/actions/workflows/test.yml/badge.svg)](https://github.com/AustinBarikdar/LuneTest/actions/workflows/test.yml)
[![Wally](https://img.shields.io/badge/wally-austinbarikdar%2Flunetest-f4e9c1?labelColor=1b2550)](https://wally.run/package/austinbarikdar/lunetest)
[![License: MIT](https://img.shields.io/badge/license-MIT-4ade80?labelColor=1b2550)](LICENSE)
[![Strict Luau](https://img.shields.io/badge/luau---!strict-9db4ff?labelColor=1b2550)](#writing-specs)

[**Website**](https://austinbarikdar.github.io/LuneTest/) · [Quick start](#quick-start) · [Writing specs](#writing-specs) · [Simulated network](#simulated-network-unit-specs) · [CI/CD](#cicd) · [AI agents](#ai-coding-agents) · [Contributing](#contributing)

</div>

```
$ lune run test
  PASS  [unit] Economy/CoinsSpec › adds coins
  PASS  [unit] Network/PacketsSpec › batched packets go client -> server -> client
  FAIL  [unit] Economy/CoinsSpec › rejects negative amounts
        ReplicatedStorage.LuneTestSpecs.Unit.Economy.CoinsSpec:12: expected function to throw
  PASS  [server] ExampleServerSpec › runs on the server  (lune)
[lunetest] 2 of 3 e2e specs need Studio
[lunetest] running in Studio (in the background)...
  PASS  [server] Combat/RaycastSpec › ray into empty space hits nothing  (studio)
  PASS  [client] HudSpec › PlayerGui exists  (studio)

[lunetest] 5 passed, 1 failed (8.06s)
```

## Why LuneTest

<table>
<tr>
<td width="33%" valign="top">

### ⚡ Fast by default

Unit specs run inside Lune against your Rojo-built place. No Studio, and 6,000 tests take about 0.2 seconds.

</td>
<td width="33%" valign="top">

### 🎮 Real when it matters

Specs that need the engine run in a real Studio Play session, with a real server, client and character. Studio starts in the background and closes itself.

</td>
<td width="33%" valign="top">

### ☁️ Works in CI

Server specs run on Roblox's own servers through Open Cloud, with no Studio. Your place is never changed.

</td>
</tr>
<tr>
<td valign="top">

### 🔁 Lune first

Every e2e spec is tried in Lune before Studio opens. Only the ones that fail there go to Studio, whose result is final.

</td>
<td valign="top">

### 📡 Network without Studio

Client and server code run together inside Lune, with working remotes and per-frame packet batching.

</td>
<td valign="top">

### 🤖 Agent-ready

Setup installs a skill that teaches Claude Code and Codex to write good specs.

</td>
</tr>
</table>

## Quick start

From your Rojo project's folder, one command sets everything up and runs the example tests:

**macOS / Linux (Terminal):**

```sh
curl -fsSL https://raw.githubusercontent.com/AustinBarikdar/LuneTest/main/install.luau | lune run -
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/AustinBarikdar/LuneTest/main/install.luau | lune run -
```

After that:

```sh
lune run test          # everything
lune run test unit     # only the fast specs, no Studio
```

There are two kinds of test, decided by the folder a spec is in:

| Kind | Folder | Runs | Speed |
| --- | --- | --- | --- |
| **unit** | `tests/unit/` | Inside Lune, against your Rojo-built place. No Studio. | milliseconds |
| **e2e** | `tests/e2e/{server,client,shared}/` | Tried in Lune first. Any spec that fails there is rerun in a real Studio Play session. | Instant if Lune passes, ~8s if Studio is needed |

Studio only opens when at least one e2e spec actually needs it. It runs in the background in its own instance, and that instance closes when the run is over. A Studio you already have open is left alone.

The exit code is 0 when everything passes and 1 when something fails, so it works in scripts and CI.

## Contents

- [Requirements](#requirements)
- [Setup](#setup)
- [Running](#running)
- [Writing specs](#writing-specs)
- [Lune first, Studio fallback](#lune-first-studio-fallback-e2e-specs)
- [Simulated network](#simulated-network-unit-specs)
- [Remotes table](#remotes-table)
- [CI/CD](#cicd)
- [AI coding agents](#ai-coding-agents)
- [Config](#config)
- [Reliability on slow machines](#reliability-on-slow-machines)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Developing LuneTest](#developing-lunetest)

## Requirements

- [Rojo](https://rojo.space) 7, [Lune](https://lune-org.github.io/docs) **0.10 or newer** and [Wally](https://wally.run). If your project pins an older Lune, LuneTest's setup updates the pin for you and tells you to run `rokit install`. With [Rokit](https://github.com/rojo-rbx/rokit): `rokit init` (if the project has no `rokit.toml` yet), then `rokit add rojo`, `rokit add lune`, `rokit add wally`.
- For e2e specs only: Roblox Studio on macOS or Windows, signed in.

## Setup

From your project root, one command does everything. Use the one for your system:

**macOS / Linux (Terminal):**

```sh
curl -fsSL https://raw.githubusercontent.com/AustinBarikdar/LuneTest/main/install.luau | lune run -
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/AustinBarikdar/LuneTest/main/install.luau | lune run -
```

It adds LuneTest to `wally.toml` (creating the file if you don't have one), runs `wally install`, sets the project up, and runs the example unit tests so you can see it working. If Rojo or Wally is missing, it installs them with Rokit. It's safe to run again.

### Easy download integration for Wally

Already use Wally? Add LuneTest like any other package:

1. Add LuneTest to `wally.toml`:

   ```toml
   [dev-dependencies]
   LuneTest = "austinbarikdar/lunetest@0.1.0"
   ```

2. Download it (same on every system):

   ```sh
   wally install
   ```

3. Run the LuneTest `init`, from your project root. You only do this **once per project**. This command differs by system:

   **macOS / Linux (Terminal):**

   ```sh
   lune run DevPackages/_Index/*/lunetest/lune/init.luau
   ```

   **Windows (PowerShell):**

   ```powershell
   lune run (Resolve-Path DevPackages/_Index/*/lunetest/lune/init.luau)
   ```

4. Run your tests (same on every system):

   ```sh
   lune run test
   ```

After that first run you never need `init` again:

- **Updating LuneTest is just `wally install`.** The launcher always loads whichever version is installed.
- **Teammates don't run it.** The launcher and tests are committed with your project, so after cloning they only need `wally install`.

Running `init` again is harmless. It never overwrites anything and only adds files that are missing. It creates:

- **`.lune/test.luau`**: the launcher and your config. If you already have a `lune/` folder, it goes at `lune/test.luau` instead.
- **`tests/`**: example unit and e2e specs.
- **`.gitignore` entries**: for the generated `lunetest.project.json`, `lunetest.rbxl`, `lunetest.cache.json` and `lunetest.lock`, plus the `lunetest.rbxl.lock` Studio leaves behind on Windows.
- **A skill for AI coding agents**: `.claude/skills/lunetest-testing/` for Claude Code and `.agents/skills/lunetest-testing/` for Codex. See [AI coding agents](#ai-coding-agents).
- **The Studio plugin**: `LuneTest.rbxmx` in your Studio Plugins folder. No restart is needed: each test run opens its own Studio process, which loads it.

Lune runs `lune/test.luau` before `.lune/test.luau`. If you already have a `lune/test.luau`, `init` tells you instead of writing a second launcher that would never run.

## Running

```sh
lune run test                        # everything
lune run test unit                   # unit specs only (no Studio)
lune run test e2e                    # e2e specs only
lune run test unit Economy           # tests whose name contains "Economy"
lune run test unit Economy Network   # ...or "Network"
lune run test e2e server             # e2e tests whose name contains "server"
lune run test --fresh                # retry every e2e spec in Lune, ignoring the cache
lune run test --cloud                # CI: server/shared e2e specs on Roblox's servers, no Studio
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
- **Studio-only specs are remembered.** LuneTest saves which specs needed Studio in `lunetest.cache.json`, keyed by a fingerprint of each spec file. On the next run they go straight to Studio without retrying in Lune. Editing a spec file makes LuneTest retry it in Lune.
- **`lune run test --fresh` retries everything in Lune.** The fingerprint only covers the spec file itself, so use this after fixing a module a cached spec depends on.

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

## CI/CD

CI can run two of the three kinds of test. Set up Part 1 first; Part 2 is optional.

| What | Runs in CI? | How |
| --- | --- | --- |
| Unit specs, including simulated client ↔ server tests | Yes | `lune run test unit` on any runner |
| Server and shared specs that need the real engine | Yes | `lune run test --cloud` on Roblox's servers |
| Specs that need a real player, character or UI | No | Studio, on your own machine |

### Part 1: unit tests on every push

Unit specs need nothing from Roblox. Add this file to your repository:

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: CompeyDev/setup-rokit@v0.1.2   # installs Rojo, Lune and Wally from rokit.toml
      - run: wally install
      - run: lune run test unit
```

Push it, and every push and pull request runs your unit specs. A failing test fails the check.

### Part 2: server specs on Roblox's servers

`--cloud` runs your `tests/e2e/server` and `tests/e2e/shared` specs in an Open Cloud [Luau execution task](https://create.roblox.com/docs/cloud/reference/features/luau-execution): a real Roblox server, with no Studio and no window.

> [!CAUTION]
> **Do NOT use your production game's Universe ID or Place ID.**
> **Create a blank place and use its IDs instead.**
>
> **Your tests can overwrite live data.** Specs run *inside* the experience you configure, with full access to its DataStores, MemoryStores and messaging. A spec that calls `SetAsync` or `RemoveAsync` changes that experience's saved data for real, and it stays changed after the test ends. Pointed at your production game, a test could overwrite or delete real player data.
>
> The place itself is not overwritten: `--cloud` never saves or publishes anything to it. The risk is the experience's data, and a blank test experience has none to lose.

**Step 1: create a blank test place.** In Roblox Studio: **File → New → Baseplate**, then **File → Publish to Roblox**. Name it something like `MyGame Tests` and keep it private.

**Step 2: copy its two IDs.** On the [Creator Dashboard](https://create.roblox.com/dashboard/creations), click the **⋯** on the test experience: **Copy Universe ID** and **Copy Start Place ID**.

**Step 3: put the IDs in your launcher config** (`.lune/test.luau`):

```lua
cloud = { universeId = 1234567890, placeId = 9876543210 }, -- the BLANK test place, never production
```

**Step 4: create an API key** at [create.roblox.com/dashboard/credentials](https://create.roblox.com/dashboard/credentials):

1. Click **Create API Key**.
2. Under **Access Permissions**, add **luau-execution-sessions**.
3. Inside it, add **only your test experience** and tick **Write**. Leaving your production game off the key means the key can't touch it, even by mistake.
4. Under **Security**, accept `0.0.0.0/0` so CI machines can use it.
5. Save and copy the key. Treat it like a password: never commit it, paste it in a chat or put it in a file.

**Step 5: try it on your machine.** In a terminal:

```sh
read -s ROBLOX_API_KEY && export ROBLOX_API_KEY   # paste the key, press Enter (nothing is shown)
lune run test --cloud
```

A line ending in `(cloud)` ran on Roblox's servers:

```
  PASS  [server] Combat/RaycastSpec › ray into empty space hits nothing  (cloud)
  SKIP  [client] HudSpec  (needs a real client: run it in Studio)
```

**Step 6: add it to CI.** Store the key as a repository secret named `ROBLOX_API_KEY` (GitHub: **Settings → Secrets and variables → Actions → New repository secret**), then change the last step of the workflow to:

```yaml
      - run: lune run test --cloud
        env:
          ROBLOX_API_KEY: ${{ secrets.ROBLOX_API_KEY }}
```

### How `--cloud` works and what it can't do

- **The place is never changed.** The built test content is sent to the task as binary input and loaded into the task's own temporary copy of the place, which is thrown away when the task ends. Nothing is saved or published.
- **It's a bare server.** No player ever joins, so there is no client, no character and no UI. Physics doesn't simulate, and your game's own scripts don't start, so a spec has to `require` and call what it tests.
- **Client specs are skipped,** and each is listed as `SKIP` so nothing disappears silently. Run those in Studio with `lune run test`.
- **Lune goes first here too.** Only specs that fail in Lune are sent to the cloud.
- **Only the contents of each service are sent.** Service properties (Lighting settings, Workspace gravity and so on) and `StarterPlayer` stay as the test place has them, and Terrain isn't included.
- **A task can run for 5 minutes at most.**
- **`lune run test --cloud --dry-run`** prints the Open Cloud calls without sending anything.

If the run stops with `403 Scope not authorized`, the key doesn't have the test experience added under **luau-execution-sessions** with **Write**.

## AI coding agents

`init` adds a skill that teaches Claude Code and Codex how to write LuneTest specs well. Both tools pick it up automatically when you ask for tests in the project, for example "add tests for the Inventory module" or "write a failing test for this bug, then fix it".

The skill covers:

- **How LuneTest works:** the spec format, where each kind of test goes, the matchers, the simulated network, and how to run and filter tests.
- **Established testing practice:** write the failing test first, name tests after behaviors, one behavior per test, cover boundaries and error paths, keep tests deterministic and independent, and prefer fast unit tests over Studio ones.

| Tool | Where the skill lives |
| --- | --- |
| Claude Code | `.claude/skills/lunetest-testing/SKILL.md` |
| Codex | `.agents/skills/lunetest-testing/SKILL.md` |

It's a plain Markdown file, so you can edit it to add your project's own conventions. Commit it so your whole team's agents get it. To pick up a newer version after updating LuneTest, delete those two folders and run `init` again.

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
| `startTimeout` | `90` | Seconds Studio gets to enter Play before the test place is reopened once |
| `port` | `44774` | First port tried for Studio's results. If it's taken, the next free one is used. |
| `remotes` | none | See [Remotes table](#remotes-table) |
| `cloud` | none | `{ universeId, placeId }` of a **blank test place** for `--cloud`. Never your production game. See [CI/CD](#cicd) |
| `fallback` | `true` | Try e2e specs in Lune first and send only the failures to Studio |

If your project is a library, meaning its tree isn't a `DataModel`, LuneTest mounts it at `ReplicatedStorage.<project name>`.

## Reliability on slow machines

- **Starting Play:** the plugin starts Play through `StudioTestService`. It never sends keystrokes, so it can't press Play in the wrong window. It first waits until Studio has finished loading (its interface stops changing), because Studio silently drops a request made too early. That wait adapts to the machine, so it isn't a fixed delay.
- **Play that never starts:** the server reports in as soon as Play begins. If that hasn't happened after `startTimeout` seconds, LuneTest closes the test place and opens a fresh one, once, so the run doesn't sit until the full timeout.
- **Client startup:** the client reports "started" as soon as it loads. The server waits for that signal, not for a fixed amount of time, so a slow client is never cut off halfway through.
- **Stale results:** each run has a random ID, and results from an old or unrelated Studio are ignored.
- **Sandboxes that block network ports** (some AI coding agents): unit specs still run. Only Studio needs a port, so an e2e run stops with a message saying so.
- **Parallel runs:** if the port is taken, the next free one is used, so two projects can run at the same time. Each run only ever closes its own test place, never another project's or a place you have open.
- **One run per project:** a second `lune run test` in the same project stops right away instead of fighting over the test place and Studio windows. A lock left behind by a crashed or Ctrl+C'd run is detected and taken over automatically.
- **Updated plugin:** every test place opens in its own Studio process, which loads the plugin fresh. An updated plugin takes effect on the next run, even with other Studio windows open.
- **Studio stays out of your way (macOS):** the test place opens in its own Studio instance, in the background, separate from any Studio you have open. Studio still brings itself to the front briefly while it boots; LuneTest hides it again each time, so it's on screen for a second or two instead of the whole run. Your own Studio windows are never touched.

## Troubleshooting

- **`no results from Studio`**: check Studio's Output window. The runners print `[LuneTest] N passed, M failed` when they finish.
- **A unit spec says something `is not a valid member`**: that's engine behavior Lune doesn't have. Move the spec to `tests/e2e`.
- **Every `lune` command prints `ERROR No such file or directory (os error 2)`**, even `lune --version`: your project pins a Lune version that isn't installed on this machine, so Lune itself can't start and LuneTest never runs. Open `rokit.toml` or `aftman.toml` in the project, set `lune = "lune-org/lune@0.10.5"`, then run `rokit install`.
- **"LuneTest needs Lune 0.10 or newer"**: the project pins an older Lune. LuneTest has already updated the pin in `rokit.toml` or `aftman.toml` for you. Run `rokit install` (or `aftman install`), then run your command again.
- **`Aftman error: ... no aftman.toml files list this tool`**: an old Aftman install is ahead of Rokit on your `PATH`, and Aftman doesn't read `rokit.toml`. Move Rokit's `bin` folder (`~/.rokit/bin`) above Aftman's in `PATH`, then open a new terminal.
- **The first e2e run takes a minute or more**: Studio was updating itself before it opened the place. Later runs are back to a few seconds.

## Contributing

Found a bug, or want to fix one? Both are welcome.

- **Report a bug:** open an issue with the [bug report form](https://github.com/AustinBarikdar/LuneTest/issues/new/choose). Include the command you ran, the terminal output, your versions and your system. Never paste an API key or token.
- **Fix a bug:** reproduce it with a failing spec in `example/tests/` first, fix the cause, then keep the spec so it can't come back.
- **Open a pull request:** branch from `main`, keep it to one fix or feature, run `lune run test unit` in `example/`, and say what you tested and on which system. CI runs the unit specs and strict type checks on every pull request.

The full guide, with setup steps and a map of the code, is in [CONTRIBUTING.md](CONTRIBUTING.md).

## Developing LuneTest

`example/` is a small project that uses every feature. Wally has no local path dependencies, so link this repo into it by hand:

**macOS / Linux (Terminal):**

```sh
mkdir -p example/DevPackages/_Index/austinbarikdar_lunetest@0.1.0
ln -s "$PWD" example/DevPackages/_Index/austinbarikdar_lunetest@0.1.0/lunetest
cd example && lune run test
```

**Windows (PowerShell)**, using a junction (no admin rights needed):

```powershell
New-Item -ItemType Directory -Force example/DevPackages/_Index/austinbarikdar_lunetest@0.1.0
New-Item -ItemType Junction -Path example/DevPackages/_Index/austinbarikdar_lunetest@0.1.0/lunetest -Target $PWD
cd example; lune run test
```

Type-check everything in strict mode (needs Roblox's `globalTypes.d.luau` from the luau-lsp repo, and `lune setup` for the `.luaurc` alias). On Windows, run these from Git Bash: PowerShell doesn't expand the `*` in the paths.

```sh
cd example && rojo sourcemap lunetest.project.json -o sourcemap.json
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src tests DevPackages/_Index/*/lunetest/src DevPackages/_Index/*/lunetest/runners DevPackages/_Index/*/lunetest/lune/plugin.luau
cd .. && luau-lsp analyze --platform=standard lune/cli.luau lune/network.luau lune/init.luau example/.lune/test.luau
```

To publish: bump `version` in `wally.toml` (a published version can't be replaced), then `wally login` once and `wally publish`.
