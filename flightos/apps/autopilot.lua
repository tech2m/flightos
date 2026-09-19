local UI = require("ui")
local Config = require("config")
local app = {}
app.name = "Autopilot"
local fields = {
    { key = "target_x",       label = "Target X",   is_string = true },
    { key = "target_y",       label = "Target Y",   is_string = true },
    { key = "target_z",       label = "Target Z",   is_string = true },
    { key = "motor_steer_id", label = "Steer ID",  is_string = true },
    { key = "speed_invert",   label = "Inv Speed", is_string = true },
    { key = "steer_invert",   label = "Inv Steer", is_string = true },
    { key = "rs_relay_id",    label = "Relay ID",  is_string = true },
    { key = "rs_side",        label = "Relay Side",is_string = true },
    { key = "auto_speed_max", label = "Max Speed",  is_string = true },
    { key = "auto_steer_max", label = "Max Steer",  is_string = true },
    { key = "auto_steer_kp",  label = "Steer Kp",   is_string = true },
    { key = "auto_steer_kd",  label = "Steer Kd",   is_string = true },
}
local selectedField = 1
local scrollOffset = 0
local editCfg = nil
local dirty = false
local waiting_for_input = false
local statusMsg = nil
function app.draw(target, service)
    local w, h = target.getSize()
    local d = service.data
    local cfg = service.getConfig and service.getConfig() or {}
    if not editCfg then
        editCfg = {}
        for k, v in pairs(cfg) do
            editCfg[k] = v
        end
    end
    local status = d.auto_enabled and "ACTIVE" or "DISABLED"
    local statusColor = d.auto_enabled and UI.colors.accent or UI.colors.err
    UI.writeAt(target, 2, 3, "Status: ", UI.colors.textDim)
    UI.writeAt(target, 10, 3, UI.padRight(status, 10), statusColor)
    if d.x then
        local gpsStr = string.format("GPS: %d %d %d", math.floor(d.x+0.5), math.floor(d.y+0.5), math.floor(d.z+0.5))
        UI.writeAt(target, 2, 4, UI.padRight(gpsStr, w - 3), UI.colors.text)
        if d.dist then
            local distStr = string.format("Dist: %.1fm  Prog: %d%%", d.dist, math.floor(d.progress))
            UI.writeAt(target, 2, 5, UI.padRight(distStr, w - 3), UI.colors.accent)
        else
            UI.writeAt(target, 2, 5, string.rep(" ", w - 3), UI.colors.text)
        end
    else
        UI.writeAt(target, 2, 4, UI.padRight("GPS: OFFLINE", w - 3), UI.colors.textDim)
        UI.writeAt(target, 2, 5, string.rep(" ", w - 3), UI.colors.text)
    end
    local visibleLines = h - 8
    for i = 1, visibleLines do
        local idx = i + scrollOffset
        if idx > #fields then break end
        local f = fields[idx]
        local val = editCfg[f.key]
        local isSelected = (idx == selectedField)
        local lineY = 5 + i
        local displayVal = (val == nil and "" or tostring(val))
        local paddedVal = UI.padRight(displayVal, w - 15)
        if isSelected then
            UI.writeAt(target, 2, lineY, "> " .. f.label .. ":", UI.colors.accent)
            UI.writeAt(target, 15, lineY, paddedVal, UI.colors.accent)
        else
            UI.writeAt(target, 2, lineY, "  " .. f.label .. ":", UI.colors.textDim)
            UI.writeAt(target, 15, lineY, paddedVal, UI.colors.text)
        end
    end
    local footerY = h - 2
    if statusMsg then
        UI.writeAt(target, 2, footerY, UI.padRight(statusMsg, w - 3), UI.colors.accent)
    elseif dirty then
        UI.writeAt(target, 2, footerY, UI.padRight("* Unsaved changes", w - 3), UI.colors.warn)
    else
        UI.writeAt(target, 2, footerY, string.rep(" ", w - 3), UI.colors.text)
    end
    UI.writeAt(target, 2, h - 1, "[Up/Down] Navigate  [Enter] Edit Field", UI.colors.textDim)
    UI.writeAt(target, 2, h, "[Space] Toggle  [S] Save  [R] Reset", UI.colors.textDim)
end
local function doSave(service, cfg)
    for k, v in pairs(editCfg) do
        if k == "target_x" or k == "target_y" or k == "target_z" or k == "auto_speed_max" or k == "auto_steer_max" or k == "auto_steer_kp" or k == "auto_steer_kd" then
            cfg[k] = tonumber(v) or 0
        elseif k == "speed_invert" or k == "steer_invert" then
            local s = tostring(v):lower()
            cfg[k] = (s == "true" or s == "1" or s == "yes")
        else
            cfg[k] = v
        end
    end
    local ok, err = pcall(Config.save, cfg)
    if ok then
        statusMsg = "Saved successfully!"
    else
        statusMsg = "Save error: " .. tostring(err)
    end
    if service and service.applyConfig then
        service.applyConfig(cfg)
    end
    dirty = false
end
function app.handleEvent(event, service, cfg, target)
    if not editCfg then
        editCfg = {}
        for k, v in pairs(cfg) do
            editCfg[k] = v
        end
    end
    if waiting_for_input then
        return false
    end
    if event[1] == "char" then
        local ch = event[2]:lower()
        if ch == "s" or ch == "ы" then
            doSave(service, cfg)
            return true
        elseif ch == "r" or ch == "к" then
            local defs = Config.getDefaults()
            for _, fd in ipairs(fields) do
                editCfg[fd.key] = defs[fd.key]
            end
            dirty = true
            statusMsg = nil
            return true
        end
    end
    if event[1] == "key" then
        local key = event[2]
        if key == keys.up then
            selectedField = math.max(1, selectedField - 1)
            if selectedField <= scrollOffset then
                scrollOffset = selectedField - 1
            end
            statusMsg = nil
            return true
        elseif key == keys.down then
            selectedField = math.min(#fields, selectedField + 1)
            local w, h = target.getSize()
            local visibleLines = h - 8
            if selectedField > scrollOffset + visibleLines then
                scrollOffset = selectedField - visibleLines
            end
            statusMsg = nil
            return true
        elseif key == keys.space then
            service.setAutoEnabled(not service.data.auto_enabled)
            statusMsg = nil
            return true
        elseif key == keys.enter then
            local f = fields[selectedField]
            waiting_for_input = true
            local w, h = target.getSize()
            local inputY = 5 + (selectedField - scrollOffset)
            target.setCursorPos(15, inputY)
            target.setBackgroundColor(colors.white)
            target.setTextColor(colors.black)
            target.write(string.rep(" ", w - 16))
            target.setCursorPos(15, inputY)
            target.setCursorBlink(true)
            local prev = term.redirect(target)
            local input = read(nil, nil, nil, editCfg[f.key] == nil and "" or tostring(editCfg[f.key]))
            term.redirect(prev)
            target.setCursorBlink(false)
            waiting_for_input = false
            if input then
                editCfg[f.key] = input
                dirty = true
                statusMsg = nil
            end
            return true
        elseif key == keys.s then
            doSave(service, cfg)
            return true
        elseif key == keys.r then
            local defs = Config.getDefaults()
            for _, fd in ipairs(fields) do
                editCfg[fd.key] = defs[fd.key]
            end
            dirty = true
            statusMsg = nil
            return true
        end
    end
    return false
end
return app