--!strict
-- LuneTest launcher.
--   lune run test                 everything
--   lune run test unit            unit specs only (inside Lune, no Studio)
--   lune run test e2e             end-to-end specs only (Studio play session)
--   lune run test unit Economy    only tests whose name contains "Economy"
local fs = require("@lune/fs")

if string.match(_VERSION, "Lune 0%.%d[^%d]") then
	error('LuneTest needs Lune 0.10 or newer: set  lune = "lune-org/lune@0.10.5"  in rokit.toml or aftman.toml and run  rokit install', 0)
end

local config = {
	project = "default.project.json", -- your normal Rojo project; tests are injected into a copy
	unit = "tests/unit", -- fast specs, run inside Lune; subfolders are groups
	e2e = "tests/e2e", -- server/, client/ and shared/ specs; tried in Lune, then Studio
	testTimeout = 30, -- seconds before a single test counts as hung
	timeout = 300, -- seconds to wait for Studio to report back
	fallback = true, -- try e2e specs in Lune first; only the ones that fail there run in Studio
	cloud = { universeId = 10358916978, placeId = 102338780824373 }, -- LuneTest sandbox place, used by --cloud

	-- Remotes to create in the test place (works in unit and e2e). A bare name is a RemoteEvent.
	remotes = {
		["ReplicatedStorage.Remotes"] = { "Packets", GetProfile = "RemoteFunction" },
	},
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
