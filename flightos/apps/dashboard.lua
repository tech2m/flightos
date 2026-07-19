local UI = require("ui")
local app = {}
app.name = "Dashboard"
function app.draw(target, service)
    local w, h = target.getSize()
    local d = service.data
    local status = d.enabled and "ACTIVE" or "DISABLED"
    local statusColor = d.enabled and UI.colors.accent or UI.colors.err
    UI.writeAt(target, 2, 3, "Status: ", UI.colors.textDim)
    UI.writeAt(target, 10, 3, status, statusColor)
    UI.writeAt(target, 20, 3, string.format("Tick: %d", d.tick), UI.colors.textDim)
    local logStatus = d.logging and "ACTIVE" or "INACTIVE"
    local logColor = d.logging and UI.colors.accent or UI.colors.textDim
    UI.writeAt(target, 2, 4, "Log: ", UI.colors.textDim)
    UI.writeAt(target, 7, 4, logStatus, logColor)
    local autoStatus = d.auto_enabled and "ACTIVE" or "DISABLED"
    local autoColor = d.auto_enabled and UI.colors.accent or UI.colors.err
    UI.writeAt(target, 16, 4, "Auto: ", UI.colors.textDim)
    UI.writeAt(target, 22, 4, autoStatus, autoColor)
    if d.x then
        local posStr = string.format("GPS: %d %d %d", math.floor(d.x+0.5), math.floor(d.y+0.5), math.floor(d.z+0.5))
        if d.auto_enabled and d.dist then
            local pBar = ""
            local barSize = 5
            local filled = math.floor((d.progress / 100) * barSize + 0.5)
            for i = 1, barSize do
                if i < filled then pBar = pBar .. "="
                elseif i == filled then pBar = pBar .. ">"
                else pBar = pBar .. " " end
            end
            posStr = posStr .. string.format(" D:%d [%s]%d%%", math.floor(d.dist+0.5), pBar, math.floor(d.progress))
        end
        UI.writeAt(target, 2, 5, UI.padRight(posStr, w - 3), UI.colors.text)
    else
        UI.writeAt(target, 2, 5, UI.padRight("GPS: NO SIGNAL", w - 3), UI.colors.textDim)
    end
    UI.drawBox(target, 1, 6, w, 5, "Roll")
    UI.writeAt(target, 3, 7, string.format("Angle: %+7.2f", d.roll), UI.colors.text)
    UI.writeAt(target, 3, 8, string.format("P:%+5.1f I:%+5.1f B:%+5.1f D:%+5.1f",
        d.rP, d.rI, d.rollBias, d.rD), UI.colors.textDim)
    UI.writeAt(target, 3, 9, string.format("Out:%+6.1f  Kd:%.2f  Rate:%+.1f",
        d.rollOut, d.rollKd, d.rollRate), UI.colors.accent)
    UI.drawBox(target, 1, 11, w, 5, "Pitch")
    UI.writeAt(target, 3, 12, string.format("Angle: %+7.2f", d.pitch), UI.colors.text)
    UI.writeAt(target, 3, 13, string.format("P:%+5.1f I:%+5.1f B:%+5.1f D:%+5.1f",
        d.pP, d.pI, d.pitchBias, d.pD), UI.colors.textDim)
    UI.writeAt(target, 3, 14, string.format("Out:%+6.1f  Kd:%.2f  Rate:%+.1f",
        d.pitchOut, d.pitchKd, d.pitchRate), UI.colors.accent)
    if h >= 19 then
        UI.writeAt(target, 2, 17, string.format("FL:%+6.1f  FR:%+6.1f", d.fl, d.fr), UI.colors.text)
        UI.writeAt(target, 2, 18, string.format("BL:%+6.1f  BR:%+6.1f", d.bl, d.br), UI.colors.text)
    end
    UI.writeAt(target, 2, h, "[Space] Toggle  [A] Auto  [L] Log  [C] Clear", UI.colors.textDim)
end
function app.handleEvent(event, service)
    if event[1] == "key" then
        local key = event[2]
        if key == keys.space then
            service.setEnabled(not service.isEnabled())
            return true
        elseif key == keys.a then
            service.setAutoEnabled(not service.data.auto_enabled)
            return true
        elseif key == keys.l then
            if service.data.logging then
                service.stopLogging()
            else
                service.startLogging()
            end
            return true
        elseif key == keys.c then
            service.clearLogging()
            return true
        end
    end
    return false
end
return app