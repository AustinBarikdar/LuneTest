--!strict
-- One-time project setup. From your project root, after `wally install`:
--   lune run DevPackages/_Index/<scope>_lunetest@<version>/lunetest/lune/init.luau
-- Never overwrites anything that already exists; safe to re-run.

local fs = require("@lune/fs")
local stdio = require("@lune/stdio")

local cli = require("@self/cli") -- init.luau resolves "./" from its parent folder

local LAUNCHER = [[
--!strict
-- LuneTest launcher.
--   lune run test                 everything
--   lune run test unit            unit specs only (inside Lune, no Studio)
--   lune run test e2e             end-to-end specs only (Studio play session)
--   lune run test unit Economy    only tests whose name contains "Economy"
local fs = require("@lune/fs")

local config = {
	project = "default.project.json", -- your normal Rojo project; tests are injected into a copy
	unit = "tests/unit", -- fast specs, run inside Lune; subfolders are groups
	e2e = "tests/e2e", -- server/, client/ and shared/ specs; tried in Lune, then Studio
	testTimeout = 30, -- seconds before a single test counts as hung
	timeout = 300, -- seconds to wait for Studio to report back
	fallback = true, -- try e2e specs in Lune first; only the ones that fail there run in Studio

	-- Remotes to create in the test place (works in unit and e2e). A bare name is a RemoteEvent.
	-- remotes = {
	-- 	["ReplicatedStorage.Remotes"] = { "Chat", GetData = "RemoteFunction", Move = "UnreliableRemoteEvent" },
	-- },
}

-- ponytail: takes the first installed version; Wally normally keeps only one.
for _, packages in { "DevPackages", "Packages", "ServerPackages" } do
	local index = `{packages}/_Index`
	if fs.isDir(index) then
		for _, name in fs.readDir(index) do
			if string.find(name, "_lunetest@", 1, true) then
				-- Cast: the path is only known at runtime, which strict mode can't resolve.
				return (require :: any)(`../{index}/{name}/lunetest/lune/cli`).run(config)
			end
		end
	end
end
error("LuneTest isn't installed: add it to [dev-dependencies] in wally.toml, then run `wally install`")
]]

local EXAMPLES: { [string]: string } = {
	["unit/ExampleSpec.luau"] = [[
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
]],
	["unit/NetworkSpec.luau"] = [[
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LuneTest = require(ReplicatedStorage.LuneTest)
local expect, network = LuneTest.expect, LuneTest.network

-- network simulates client <-> server remotes inside Lune, so packet flows test without Studio.
return {
	["client -> server -> client round trip"] = function()
		local remote = Instance.new("RemoteEvent")
		remote.Name = "Ping"
		remote.Parent = ReplicatedStorage

		network.server(function()
			remote.OnServerEvent:Connect(function(player, message)
				remote:FireClient(player, message .. " pong")
			end)
		end)

		local reply
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
]],
	["e2e/server/ExampleServerSpec.luau"] = [[
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local expect = require(ReplicatedStorage.LuneTest).expect

return {
	["runs on the server"] = function()
		expect(RunService:IsServer()).toBe(true)
	end,
}
]],
	["e2e/client/ExampleClientSpec.luau"] = [[
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local expect = require(ReplicatedStorage.LuneTest).expect

return {
	["has a character"] = function()
		expect(Players.LocalPlayer.Character).never.toBeNil()
	end,
}
]],
}

local function create(path: string, contents: string)
	if fs.isFile(path) then
		print(`  exists   {path}`)
		return
	end
	local dir = string.match(path, "^(.*)/")
	if dir then
		fs.writeDir(dir)
	end
	fs.writeFile(path, contents)
	print(`  created  {path}`)
end

-- Lune looks in lune/ before .lune/, so an existing lune/test.luau would shadow ours.
if fs.isFile("lune/test.luau") and not string.find(fs.readFile("lune/test.luau"), "LuneTest launcher", 1, true) then
	stdio.write(
		`  {stdio.color("yellow")}skipped{stdio.color("reset")}  lune/test.luau already exists and \`lune run test\` would run it instead.\n`
			.. "           Rename or delete it, then run init again.\n"
	)
else
	create(if fs.isDir("lune") then "lune/test.luau" else ".lune/test.luau", LAUNCHER)
end

if fs.isDir("tests") then
	print("  exists   tests/")
else
	for path, contents in EXAMPLES do
		create(`tests/{path}`, contents)
	end
end

local gitignore = if fs.isFile(".gitignore") then fs.readFile(".gitignore") else ""
local missing = {}
for _, entry in { "lunetest.project.json", "lunetest.rbxlx" } do
	if not string.find(gitignore, entry, 1, true) then
		table.insert(missing, entry)
	end
end
if #missing > 0 then
	local sep = if gitignore == "" or string.sub(gitignore, -1) == "\n" then "" else "\n"
	fs.writeFile(".gitignore", `{gitignore}{sep}{table.concat(missing, "\n")}\n`)
	print("  updated  .gitignore")
end

if cli.installPlugin() then
	print("  installed LuneTest Studio plugin (restart Studio if it's open)")
end

stdio.write(`\n{stdio.color("green")}Ready.{stdio.color("reset")} Run your tests with: lune run test\n`)
