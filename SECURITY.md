# Security

## Reporting a vulnerability

Please report security problems privately, not in a public issue.

Use GitHub's **Report a vulnerability** button on the repository's [Security tab](https://github.com/AustinBarikdar/LuneTest/security/advisories/new). That opens a private report only the maintainer can see. If the button isn't available, open a normal issue that says only "I have a security report" with no details, and you'll be contacted.

Please include what you found, how to reproduce it, and which version you used. You'll get a reply as soon as possible, and credit in the fix if you want it.

Only the latest release is supported. Fixes go into a new version.

## Never share your keys

Don't paste an Open Cloud API key, a Wally token or a `.ROBLOSECURITY` cookie into an issue, a pull request, a log or a chat. If one leaks, revoke it right away:

- **Roblox API key:** delete or regenerate it at [create.roblox.com/dashboard/credentials](https://create.roblox.com/dashboard/credentials).
- **Wally token:** it is a GitHub token. Revoke it under GitHub → Settings → Applications.

## What LuneTest does on your machine

So you can decide whether to trust it:

- **The one-line installer runs code from this repository.** `curl … | lune run -` downloads `install.luau` from the `main` branch and runs it. Read it first if you want to; the Wally steps in the README do the same thing by hand.
- **It installs a Studio plugin** (`LuneTest.rbxmx`) in your Studio Plugins folder. The plugin starts Play automatically, but only in a place that carries the LuneTest marker (`ReplicatedStorage.LuneTestSpecs` with the `AutoPlay` attribute). A place file from someone else that carries that marker would also start Play when you open it, which runs that place's scripts. Only open place files you trust, as you would without LuneTest. Delete the plugin file to remove it.
- **It opens a local port** while a run is in progress, so Studio can send results back. It listens on `127.0.0.1` only, so other machines on your network can't reach it, and it only accepts results that carry the current run's random id.
- **The test place enables `HttpService`** so the runner can report back. That applies only to the generated `lunetest.rbxl`, never to your own project or published game.
- **It closes only its own Studio window,** identified by the test place's full path.

## `--cloud` and your API key

- **The key is read only from the `ROBLOX_API_KEY` environment variable.** It is never written to a file, printed, or put in a URL.
- **It is sent only to `apis.roblox.com`.** The upload of the test content goes to a one-time upload address that Roblox returns, without the key.
- **Give the key the least it needs:** `luau-execution-sessions` → Write, on a blank test experience only. Don't add your production game to it.
- **Specs run inside the experience you configure** and can change its DataStores and other live data. Use a blank test place, never production. See the caution in the README.

## In CI

This repository's workflow follows the same rules it recommends:

- Secrets are passed only to the single step that uses them, so third-party actions can't read them.
- Third-party actions are pinned to exact commits.
- The workflow's own token is read-only.
- Pull requests from forks don't get secrets, so the cloud and publish steps don't run for them.
