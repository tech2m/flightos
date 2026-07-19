local UI = require("ui")
local app = {}
app.name = "Terminal"
local shellWindow = nil
local shellCoroutine = nil
local shellRunning = false
local origParentShell = shell.parentShell
function app.init()
    shellRunning = false
    shellCoroutine = nil
    shellWindow = nil
end
local function createShell(target)
    local w, h = target.getSize()
    shellWindow = window.create(target, 1, 2, w, h - 1)
    shellWindow.setBackgroundColor(colors.black)
    shellWindow.setTextColor(colors.white)
    shellWindow.clear()
    shellWindow.setCursorPos(1, 1)
    shellCoroutine = coroutine.create(function()
        local prev = term.redirect(shellWindow)
        shell.run("shell")
        term.redirect(prev)
    end)
    shellRunning = true
    shell.parentShell = function() return 1 end
    local ok, filter = coroutine.resume(shellCoroutine)
    shell.parentShell = origParentShell
    if shellWindow then
        local cx, cy = shellWindow.getCursorPos()
        local blink = shellWindow.getCursorBlink()
        term.current().setCursorPos(cx, cy + 2)
        term.current().setCursorBlink(blink)
    end
end
function app.draw(target, service)
    local w, h = target.getSize()
    if not shellRunning then
        UI.centerText(target, math.floor(h / 2) - 1, "FlightOS Terminal", UI.colors.header)
        UI.centerText(target, math.floor(h / 2) + 1, "Press [Enter] to open shell", UI.colors.textDim)
        UI.centerText(target, math.floor(h / 2) + 2, "Stabilizer keeps running!", UI.colors.accent)
        UI.centerText(target, math.floor(h / 2) + 4, "Type 'exit' to return to FlightOS", UI.colors.textDim)
    else
        if shellWindow then
            shellWindow.setVisible(true)
            shellWindow.redraw()
            local cx, cy = shellWindow.getCursorPos()
            local blink = shellWindow.getCursorBlink()
            term.current().setCursorPos(cx, cy + 2)
            term.current().setCursorBlink(blink)
        end
    end
end
function app.handleEvent(event, service, cfg, target)
    if not shellRunning then
        if event[1] == "key" and event[2] == keys.enter then
            createShell(target)
            return true
        end
        return false
    end
    if shellCoroutine and coroutine.status(shellCoroutine) ~= "dead" then
        local ev = { table.unpack(event) }
        if ev[1] == "mouse_click" or ev[1] == "mouse_up" or ev[1] == "mouse_drag" or ev[1] == "mouse_scroll" then
            ev[4] = ev[4] - 2
        end
        shell.parentShell = function() return 1 end
        local ok, result = coroutine.resume(shellCoroutine, table.unpack(ev))
        shell.parentShell = origParentShell
        if shellRunning and shellWindow then
            local cx, cy = shellWindow.getCursorPos()
            local blink = shellWindow.getCursorBlink()
            term.current().setCursorPos(cx, cy + 2)
            term.current().setCursorBlink(blink)
        end
        if coroutine.status(shellCoroutine) == "dead" then
            shellRunning = false
            shellCoroutine = nil
            shellWindow = nil
            return true
        end
        return true
    else
        shellRunning = false
        return false
    end
end
function app.onActivate(target)
    if shellRunning and shellWindow then
        shellWindow.setVisible(true)
        shellWindow.redraw()
    end
end
function app.onDeactivate()
    if shellWindow then
        shellWindow.setVisible(false)
    end
end
return app