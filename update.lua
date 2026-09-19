local repository = "https://raw.githubusercontent.com/tech2m/flightos/main/"
local files = {
    "startup.lua",
    "flightos/config.lua",
    "flightos/main.lua",
    "flightos/music_service.lua",
    "flightos/net_server.lua",
    "flightos/pid.lua",
    "flightos/service.lua",
    "flightos/ui.lua",
    "flightos/apps/autopilot.lua",
    "flightos/apps/dashboard.lua",
    "flightos/apps/music.lua",
    "flightos/apps/settings.lua",
    "flightos/apps/terminal.lua",
    "flightos/apps/update.lua",
    "tablet/remote.lua",
    "tablet/startup.lua",
}
local function download(path)
    local response = http.get(repository .. path)
    if not response then
        error("Download failed: " .. path)
    end
    local content = response.readAll()
    response.close()
    if not content or #content == 0 then
        error("Downloaded file is empty: " .. path)
    end
    return content
end
local function install(path, content)
    local directory = path:match("^(.*)/[^/]+$")
    if directory and not fs.exists(directory) then
        fs.makeDir(directory)
    end
    local file = fs.open(path, "w")
    if not file then
        error("Cannot write: " .. path)
    end
    file.write(content)
    file.close()
end
print("Downloading FlightOS update...")
local downloaded = {}
for _, path in ipairs(files) do
    print("Downloading " .. path)
    downloaded[path] = download(path)
end
for _, path in ipairs(files) do
    print("Installing " .. path)
    install(path, downloaded[path])
end
print("FlightOS update complete.")
