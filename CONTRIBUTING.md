# Contributing to LuneTest

Bug reports, fixes and improvements are welcome. This page covers how to report a bug, how to fix one, and how to open a pull request that can be merged quickly.

## Reporting a bug

Open an issue with the **Bug report** form: [new issue](https://github.com/AustinBarikdar/LuneTest/issues/new/choose). A report that can be acted on has:

- **What you ran**, for example `lune run test e2e`.
- **What you expected** and **what happened instead**. Paste the terminal output.
- **Versions:** LuneTest (from `wally.toml`), Lune (`lune --version`), Rojo (`rojo --version`).
- **Your system:** macOS or Windows, and its version.
- **For Studio problems:** what Studio's Output window showed. The runners print `[LuneTest] N passed, M failed` when they finish.

The smallest spec that shows the problem is the most useful thing you can include.

Before reporting, check [Troubleshooting](README.md#troubleshooting) and search the [existing issues](https://github.com/AustinBarikdar/LuneTest/issues).

> [!IMPORTANT]
> Never paste an API key, a Wally token or a `.ROBLOSECURITY` cookie into an issue or pull request. If you did by accident, revoke it right away.

## Setting up to work on LuneTest

You need [Rokit](https://github.com/rojo-rbx/rokit). Roblox Studio is only needed for e2e specs.

```sh
git clone https://github.com/AustinBarikdar/LuneTest.git
cd LuneTest
rokit install
```

`example/` is a small project that uses every feature. Wally has no local path dependencies, so link this checkout into it once.

**macOS / Linux (Terminal):**

```sh
mkdir -p example/DevPackages/_Index/austinbarikdar_lunetest@0.1.0
ln -s "$PWD" example/DevPackages/_Index/austinbarikdar_lunetest@0.1.0/lunetest
```

**Windows (PowerShell):**

```powershell
New-Item -ItemType Directory -Force example/DevPackages/_Index/austinbarikdar_lunetest@0.1.0
New-Item -ItemType Junction -Path example/DevPackages/_Index/austinbarikdar_lunetest@0.1.0/lunetest -Target $PWD
```

Then, from `example/`:

```sh
lune run test unit    # fast, no Studio
lune run test         # everything; e2e specs open Studio in the background
```

Because of the link, the example always runs the code in your checkout. Edit a file and run again.

### Where things are

| Path | What it is |
| --- | --- |
| `src/` | The runtime that runs inside Roblox and inside Lune: the runner and `expect`. |
| `runners/` | The server and client scripts injected into the test place. |
| `lune/cli.luau` | The `lune run test` command. |
| `lune/network.luau` | The simulated client ↔ server network for unit specs. |
| `lune/plugin.luau` | The Studio plugin that starts Play. |
| `lune/cloud.luau` | The script that runs on Roblox's servers for `--cloud`. |
| `lune/init.luau`, `install.luau` | Project setup and the one-command installer. |
| `skills/` | The test-writing skill for AI coding agents. |
| `example/` | The project used to test all of the above. |
| `docs/` | The website. |

## Fixing a bug

1. **Reproduce it with a failing test first.** Add or change a spec in `example/tests/` so that it fails because of the bug. Run it and confirm it fails for the reason you expect. This proves the bug and later proves the fix.
2. **Fix the cause, not the symptom.** If the same function is called from several places, fix it there once instead of working around it at one call site.
3. **Run the checks** below.
4. **Keep the test.** It stops the bug from coming back.

If the bug can't be captured in a spec (for example, something about how Studio is launched), describe in the pull request exactly how you reproduced it and how you confirmed the fix.

## Checks to run before opening a pull request

From `example/`:

```sh
lune run test unit
```

If you changed anything that affects Studio runs (`runners/`, `lune/plugin.luau`, the Studio parts of `lune/cli.luau`), also run the full suite on a machine with Studio:

```sh
lune run test
```

Everything is written in `--!strict` and CI type-checks it. To run the same checks locally, see [Developing LuneTest](README.md#developing-lunetest) in the README.

## Opening a pull request

1. Fork the repository and create a branch from `main`.
2. Make your change. Keep a pull request to one fix or one feature; unrelated changes are easier to review separately.
3. Update the README if behavior, commands or config changed. Update `skills/lunetest-testing/SKILL.md` if what an agent should know changed.
4. Push and open the pull request. Fill in the checklist it shows you.

What happens next:

- **CI runs automatically:** unit specs and strict type checks on Linux. The cloud step is skipped on pull requests from forks, because forks don't get the repository's secrets.
- **Say what you tested and where.** Windows and macOS behave differently around Studio, so "tested on Windows 11, e2e passes" is useful to know.
- **Style:** match the code around your change: tabs, `--!strict`, comments that explain why and not what.

Small, focused pull requests with a test get merged fastest.

## Releasing (maintainers)

Bump `version` in `wally.toml`, merge, then push a matching tag. CI runs the tests and publishes to Wally:

```sh
git tag v0.1.2 && git push origin v0.1.2
```

A published version can't be replaced, so every release needs a new number.
