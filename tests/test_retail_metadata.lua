local function read_file(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end

local toc = read_file("TrueShot.toc")
local build = read_file("scripts/build_package.sh")
local version = read_file("VERSION"):match("^%s*(.-)%s*$")
local settings = read_file("SettingsPanel.lua")

assert(toc:find("## Interface: 120007", 1, true), "TOC must target Interface 120007")
assert(toc:find("## Version: @project-version@", 1, true), "source TOC must retain package version placeholder")
assert(version == "0.27.1-rc.1", "VERSION must default argless packages to 0.27.1-rc.1")
assert(build:find('VERSION_VALUE="$(tr -d \'[:space:]\' < VERSION)"', 1, true),
    "argless package builds must source their version from VERSION")
assert(build:find("^## Interface: 120007$", 1, true), "package assertion must require Interface 120007")
assert(not build:find("120005", 1, true), "package script must not retain Interface 120005")
assert(settings:find("Strict Compliance", 1, true), "settings must expose Strict Compliance")
assert(settings:find("Show Blizzard's current Assisted Combat recommendation unchanged", 1, true),
    "Strict settings copy must describe unchanged Blizzard current recommendation")
assert(settings:find("Experimental: show", 1, true), "experimental controls must be visibly labeled")
assert(settings:find("SetCheckboxEnabled", 1, true), "Strict mode must disable experimental controls")

print("10 passed, 0 failed")
