--!strict
-- One-command installer. From your project root:
--   curl -fsSL https://raw.githubusercontent.com/AustinBarikdar/LuneTest/main/install.luau | lune run -
-- PowerShell:
--   irm https://raw.githubusercontent.com/AustinBarikdar/LuneTest/main/install.luau | lune run -
--
-- Adds LuneTest to wally.toml, downloads it, sets the project up and runs the unit
-- examples. Safe to run again: nothing that already exists is overwritten.

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local DEPENDENCY = 'LuneTest = "austinbarikdar/lunetest@0.1.0"' -- ^0.1.0: newest compatible release

local function step(message: string)
	stdio.write(`{stdio.color("cyan")}==>{stdio.color("reset")} {message}\n`)
end

local function stop(message: string): never
	stdio.ewrite(`{stdio.color("red")}error:{stdio.color("reset")} {message}\n`)
	return process.exit(1)
end

-- Runs a tool with its output shown; false when it's missing or fails.
local function run(program: string, args: { string }): boolean
	local ok, result = pcall(process.exec, program, args, { stdio = "inherit" :: "inherit" })
	return ok and result.ok
end

local function has(program: string): boolean
	local ok, result = pcall(process.exec, program, { "--version" })
	return ok and result.ok
end

-- 1. Tools. Lune is already here (it's running this); Rojo and Wally come from Rokit.
for _, tool in { "rojo", "wally" } do
	if not has(tool) then
		if not has("rokit") then
			stop(`{tool} isn't installed, and neither is Rokit to install it. Get Rokit from https://github.com/rojo-rbx/rokit and run this again`)
		end
		step(`installing {tool} with Rokit`)
		if not fs.isFile("rokit.toml") then
			run("rokit", { "init" })
		end
		if not run("rokit", { "add", tool }) then
			stop(`\`rokit add {tool}\` failed`)
		end
	end
end

-- 2. wally.toml
if not fs.isFile("wally.toml") then
	step("creating wally.toml")
	local name = string.lower(string.match(process.cwd, "([^/\\]+)[/\\]*$") or "project")
	name = string.gsub(name, "[^%l%d%-]", "-")
	fs.writeFile(
		"wally.toml",
		`[package]\nname = "local/{name}"\nversion = "0.1.0"\nregistry = "https://github.com/UpliftGames/wally-index"\nrealm = "shared"\n\n[dev-dependencies]\n{DEPENDENCY}\n`
	)
else
	local manifest = fs.readFile("wally.toml")
	if string.find(string.lower(manifest), "/lunetest@", 1, true) then
		step("wally.toml already lists LuneTest")
	else
		step("adding LuneTest to wally.toml")
		local header = "[dev-dependencies]"
		local at, to = string.find(manifest, header, 1, true)
		if at and to then
			manifest = string.sub(manifest, 1, to) .. "\n" .. DEPENDENCY .. string.sub(manifest, to + 1)
		else
			local sep = if string.sub(manifest, -1) == "\n" then "" else "\n"
			manifest ..= `{sep}\n{header}\n{DEPENDENCY}\n`
		end
		fs.writeFile("wally.toml", manifest)
	end
end

-- 3. Download
step("wally install")
if not run("wally", { "install" }) then
	stop("`wally install` failed")
end

-- 4. Set the project up with the copy that was just downloaded
local package: string? = nil
if fs.isDir("DevPackages/_Index") then
	for _, name in fs.readDir("DevPackages/_Index") do
		if string.find(name, "_lunetest@", 1, true) then
			package = `DevPackages/_Index/{name}/lunetest`
		end
	end
end
if not package then
	stop("wally install finished but DevPackages has no lunetest; check wally.toml")
end
step("setting up the project")
if not run("lune", { "run", `{package}/lune/init.luau` }) then
	stop("setup failed")
end

-- 5. Prove it works. Unit only: fast, and it never opens Studio by surprise.
if fs.isFile("default.project.json") then
	step("lune run test unit")
	run("lune", { "run", "test", "unit" })
	stdio.write("\nRun everything, including Studio specs, with: lune run test\n")
else
	stdio.write("\nNo default.project.json here yet. Once your Rojo project exists, run: lune run test\n")
end
