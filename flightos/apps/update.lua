local UI = require("ui")
local app = {}
app.name = "Update"
local update_status = ""
local status_color = UI.colors.text
local updateCoroutine = nil
local updateUrl = "https://raw.githubusercontent.com/tech2m/flightos/main/update.lua"
function app.draw(target, service)
    local w, h = target.getSize()
    UI.centerText(target, 4, "FlightOS System Update", UI.colors.header)
    UI.centerText(target, 7, "Update from GitHub", UI.colors.textDim)
    UI.drawButton(target, 2, 9, "Download and install latest version", updateCoroutine ~= nil)
    if update_status ~= "" then
        UI.centerText(target, 11, update_status, status_color)
    end
    UI.centerText(target, 14, "Warning: Updating will restart FlightOS", colors.yellow)
end
local function performUpdate(target)
    update_status = "Resolving URL..."
    status_color = colors.yellow
    os.queueEvent("redraw_screen")
    sleep(0.5)
    update_status = "Downloading update..."
    os.queueEvent("redraw_screen")
    sleep(0.5)
    local response = http.get(updateUrl)
    if not response then
        update_status = "Download failed! URL invalid or blocked."
        status_color = colors.red
        os.queueEvent("redraw_screen")
        return
    end
    local code = response.readAll()
    response.close()
    if not code or #code < 50 then
        update_status = "Error: Downloaded file is empty or invalid"
        status_color = colors.red
        os.queueEvent("redraw_screen")
        return
    end
    update_status = "Download complete! Installing..."
    status_color = colors.lime
    os.queueEvent("redraw_screen")
    sleep(1.0)
    local f = fs.open("update_temp.lua", "w")
    f.write(code)
    f.close()
    local pf = fs.open("flightos/update_pending.txt", "w")
    pf.write("update_temp.lua")
    pf.close()
    os.queueEvent("flightos_update")
end
function app.handleEvent(event, service, cfg, target)
    if event[1] == "mouse_click" and event[4] == 10 then
        local mx = event[3]
        local w, h = term.getSize()
        if mx >= 2 and mx <= w - 1 then
            if updateCoroutine and coroutine.status(updateCoroutine) ~= "dead" then return true end
            updateCoroutine = coroutine.create(function()
                performUpdate(target)
            end)
            coroutine.resume(updateCoroutine)
            return true
        end
    end
    if updateCoroutine and coroutine.status(updateCoroutine) ~= "dead" then
        local ok, result = coroutine.resume(updateCoroutine, table.unpack(event))
        if not ok then
            update_status = "Error: " .. tostring(result)
            status_color = colors.red
            updateCoroutine = nil
        end
        return true
    end
    return false
end
return app