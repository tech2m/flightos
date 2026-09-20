package.loaded["ui"] = nil
package.loaded["config"] = nil
package.loaded["service"] = nil
package.loaded["net_server"] = nil
package.loaded["music_service"] = nil
package.loaded["apps.dashboard"] = nil
package.loaded["apps.settings"] = nil
package.loaded["apps.autopilot"] = nil
package.loaded["apps.music"] = nil
package.loaded["apps.update"] = nil
package.loaded["apps.terminal"] = nil
local w, h = term.getSize()
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.cyan)
print("FlightOS Bootloader v2.1")
print(string.rep("-", w))
sleep(0.1)
local function logBoot(msg)
    term.setTextColor(colors.white)
    print(msg)
    sleep(0.08)
end
logBoot("Loading UI engine...")
local UI = require("ui")
logBoot("Loading service APIs...")
local Config = require("config")
local Service = require("service")
local NetServer = require("net_server")
local Music = require("music_service")
logBoot("Reading config.dat...")
local cfg = Config.load()
logBoot("Scanning peripherals...")
local ok, err = Service.init(cfg)
if not ok then
    term.setTextColor(colors.red)
    print("Hardware init failed: " .. tostring(err))
    print("Falling back to shell...")
    term.setTextColor(colors.white)
    sleep(3)
    shell.run("shell")
    return
end
logBoot("Starting network server...")
NetServer.init(Service, cfg)
logBoot("Loading system apps...")
local apps = {
    require("apps.dashboard"),
    require("apps.autopilot"),
    require("apps.settings"),
    require("apps.music"),
    require("apps.update"),
    require("apps.terminal"),
}
for _, app in ipairs(apps) do
    if app.init then
        app.init(cfg)
    end
end
logBoot("Starting multi-thread kernel...")
local activeTab = 1
local tabHitboxes = {}
local emergencyHitbox = nil
local needsRedraw = true
local guiRunning = true
local contentWindow = window.create(term.current(), 1, 2, w, h - 1)
local lastSystemEnabled = false
local function drawGUI(forceClear)
    term.current().setCursorBlink(false)
    if Service.data.system_enabled ~= lastSystemEnabled then
        forceClear = true
        lastSystemEnabled = Service.data.system_enabled
    end
    if Service.data.emergency_stop then
        term.setBackgroundColor(colors.black)
        term.clear()
        local blinkOn = math.floor(os.clock() * 4) % 2 == 0
        term.setBackgroundColor(blinkOn and colors.red or colors.black)
        term.setTextColor(blinkOn and colors.white or colors.red)
        term.setCursorPos(1, math.floor(h / 2) - 1)
        term.write(string.rep(" ", w))
        term.setCursorPos(math.max(1, math.floor((w - 18) / 2)), math.floor(h / 2))
        term.write("!!! NOT-AUS !!!")
        term.setCursorPos(math.max(1, math.floor((w - 25) / 2)), math.floor(h / 2) + 2)
        term.write("ENTER ZUM REAKTIVIEREN")
        emergencyHitbox = nil
        needsRedraw = true
        return
    end
    if not Service.data.system_enabled then
        term.setBackgroundColor(colors.black)
        term.clear()
        local function fillLine(y, background)
            term.setCursorPos(1, y)
            term.setBackgroundColor(background)
            term.write(string.rep(" ", w))
        end
        local function centerText(y, text, foreground, background)
            local x = math.floor((w - #text) / 2) + 1
            term.setCursorPos(x, y)
            term.setBackgroundColor(background)
            term.setTextColor(foreground)
            term.write(text)
        end
        fillLine(1, colors.gray)
        centerText(1, "Schiff Tommy", colors.white, colors.gray)
        centerText(math.floor((h + 1) / 2), "DISPLAY DEAKTIVIERT", colors.orange, colors.black)
        tabHitboxes = {}
        needsRedraw = false
        return
    end
    if forceClear then
        term.current().setCursorPos(1, 1)
        term.setBackgroundColor(colors.black)
        tabHitboxes = UI.drawTabBar(term, apps, activeTab, 1)
        contentWindow.setBackgroundColor(UI.colors.bg)
        contentWindow.setTextColor(UI.colors.text)
        contentWindow.clear()
        emergencyHitbox = { x1 = w - 15, x2 = w, y = 1 }
        term.setCursorPos(w - 15, 1)
        term.setBackgroundColor(colors.red)
        term.setTextColor(colors.white)
        term.write(" NOT-AUS ")
    end
    local app = apps[activeTab]
    if app and app.draw then
        app.draw(contentWindow, Service)
    end
    needsRedraw = false
end
local function switchTab(idx)
    if idx < 1 or idx > #apps or idx == activeTab then return end
    local cur = apps[activeTab]
    if cur and cur.onDeactivate then
        cur.onDeactivate()
    end
    activeTab = idx
    local newApp = apps[activeTab]
    if newApp and newApp.onActivate then
        newApp.onActivate(contentWindow)
    end
    drawGUI(true)
end
local function guiLoop()
    local refreshTimer = os.startTimer(0.2)
    drawGUI(true)
    while guiRunning do
        if needsRedraw then
            drawGUI(false)
        end
        local event = { os.pullEvent() }
        local handled = false
        if event[1] == "key" and event[2] == keys.enter and Service.data.emergency_stop then
            Service.clearEmergencyStop()
            needsRedraw = true
            handled = true
        elseif event[1] == "mouse_click" and event[4] == 1 and emergencyHitbox and event[3] >= emergencyHitbox.x1 and event[3] <= emergencyHitbox.x2 and event[2] == emergencyHitbox.y then
            Service.triggerEmergencyStop()
            handled = true
            needsRedraw = true
        end
        if not Service.data.system_enabled then
            if event[1] == "timer" and event[2] == refreshTimer then
                needsRedraw = true
                refreshTimer = os.startTimer(0.25)
            end
        elseif not handled and event[1] == "mouse_click" and event[4] == 1 then
            local mx = event[3]
            for i, hb in pairs(tabHitboxes) do
                if mx >= hb.x1 and mx <= hb.x2 then
                    switchTab(i)
                    handled = true
                    break
                end
            end
        end
        if Service.data.system_enabled and event[1] == "key" then
            local key = event[2]
            for i = 1, math.min(9, #apps) do
                if key == keys["f" .. i] then
                    switchTab(i)
                    handled = true
                    break
                end
            end
        end
        if not handled then
            if event[1] == "flightos_update" then
                guiRunning = false
                handled = true
            elseif event[1] == "redraw_screen" then
                drawGUI(true)
                handled = true
            end
        end
        if Service.data.system_enabled and not handled then
            local app = apps[activeTab]
            if app and app.handleEvent then
                local appHandled, extra = app.handleEvent(event, Service, cfg, contentWindow)
                if appHandled then
                    needsRedraw = true
                end
            end
        end
        if event[1] == "timer" and event[2] == refreshTimer then
            needsRedraw = true
            refreshTimer = os.startTimer(0.25)
        end
    end
end
term.clear()
_G.FLIGHTOS_RUNNING = true
parallel.waitForAny(
    Service.loop,
    guiLoop,
    Service.gpsLoop,
    Music.audioLoop,
    Music.httpLoop,
    NetServer.loop
)
_G.FLIGHTOS_RUNNING = false
Service.stop()
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("FlightOS shut down.")