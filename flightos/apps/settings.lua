local UI = require("ui")
local Config = require("config")
local app = {}
app.name = "Settings"
local fields = {
    { key = "roll_kp",  label = "Roll Kp",  min = 0.1, max = 5.0, step = 0.1 },
    { key = "roll_ki",  label = "Roll Ki",  min = 0.05, max = 2.0, step = 0.05 },
    { key = "roll_kd",  label = "Roll Kd",  min = 0.5, max = 8.0, step = 0.1 },
    { key = "pitch_kp", label = "Pitch Kp", min = 0.1, max = 5.0, step = 0.1 },
    { key = "pitch_ki", label = "Pitch Ki", min = 0.05, max = 2.0, step = 0.05 },
    { key = "pitch_kd", label = "Pitch Kd", min = 0.5, max = 8.0, step = 0.1 },
    { key = "corr_max", label = "Corr Max", min = 10, max = 128, step = 5 },
    { key = "ki_out_max", label = "KI Max",  min = 20, max = 120, step = 5 },
    { key = "motor_fl_id", label = "FL Fan ID", is_string = true },
    { key = "motor_fr_id", label = "FR Fan ID", is_string = true },
    { key = "motor_bl_id", label = "BL Fan ID", is_string = true },
    { key = "motor_br_id", label = "BR Fan ID", is_string = true },
    { key = "motor_speed_left_id", label = "Left Thrust ID", is_string = true },
    { key = "motor_speed_right_id", label = "Right Thrust ID", is_string = true },
    { key = "system_enable_side", label = "Enable Redstone Side", is_string = true },
    { key = "manual_enable_side", label = "Manual Redstone Side", is_string = true },
    { key = "manual_propeller_id", label = "Prop Lever ID", is_string = true },
    { key = "manual_thrust_id", label = "Thrust Lever ID", is_string = true },
    { key = "manual_steering_id", label = "Steering Wheel ID", is_string = true },
}
local selectedField = 1
local scrollOffset = 0
local editCfg = nil
local dirty = false
local waiting_for_input = false
function app.init(cfg)
    editCfg = {}
    for k, v in pairs(cfg) do
        editCfg[k] = v
    end
    dirty = false
    selectedField = 1
    scrollOffset = 0
end
function app.draw(target, service)
    local w, h = target.getSize()
    UI.writeAt(target, 2, 3, "PID Configuration", UI.colors.header)
    UI.writeAt(target, 2, 4, string.rep("-", w - 2), UI.colors.border)
    if not editCfg then return end
    local maxVisible = h - 8
    if selectedField > scrollOffset + maxVisible then
        scrollOffset = selectedField - maxVisible
    elseif selectedField <= scrollOffset then
        scrollOffset = selectedField - 1
    end
    for i = 1, maxVisible do
        local idx = scrollOffset + i
        local f = fields[idx]
        if not f then break end
        local y = 4 + i
        local val = editCfg[f.key]
        local prefix = (idx == selectedField) and "> " or "  "
        local fg = (idx == selectedField) and UI.colors.accent or UI.colors.text
        local valStr
        if f.is_string then
            valStr = tostring(val or "")
        else
            valStr = string.format("%6.2f", val or 0)
        end
        local line = string.format("%s%-11s %s", prefix, f.label, valStr)
        UI.writeAt(target, 2, y, UI.padRight(line, w - 3), fg)
    end
    local footerY = h - 2
    if dirty then
        UI.writeAt(target, 2, footerY, "* Unsaved changes", UI.colors.warn)
    end
    UI.writeAt(target, 2, h - 1, "[Up/Down] Navigate  [Left/Right] Adjust", UI.colors.textDim)
    UI.writeAt(target, 2, h, "[Enter] Edit ID  [S] Save Changes  [R] Reset", UI.colors.textDim)
end
function app.handleEvent(event, service, cfg, target)
    if waiting_for_input then return false end
    if event[1] ~= "key" or not editCfg then return false end
    local key = event[2]
    local f = fields[selectedField]
    if key == keys.up then
        selectedField = math.max(1, selectedField - 1)
        return true
    elseif key == keys.down then
        selectedField = math.min(#fields, selectedField + 1)
        return true
    elseif key == keys.left and not f.is_string then
        editCfg[f.key] = math.max(f.min, (editCfg[f.key] or 0) - f.step)
        dirty = true
        return true
    elseif key == keys.right and not f.is_string then
        editCfg[f.key] = math.min(f.max, (editCfg[f.key] or 0) + f.step)
        dirty = true
        return true
    elseif key == keys.enter and f.is_string then
        waiting_for_input = true
        local w, h_term = target.getSize()
        local inputY = 4 + (selectedField - scrollOffset)
        target.setCursorPos(15, inputY)
        target.setBackgroundColor(colors.white)
        target.setTextColor(colors.black)
        target.write(string.rep(" ", w - 16))
        target.setCursorPos(15, inputY)
        target.setCursorBlink(true)
        local prev = term.redirect(target)
        local input = read(nil, nil, nil, editCfg[f.key])
        term.redirect(prev)
        target.setCursorBlink(false)
        waiting_for_input = false
        if input and #input > 0 then
            editCfg[f.key] = input
            dirty = true
        end
        return true
    elseif key == keys.s then
        for k, v in pairs(editCfg) do
            cfg[k] = v
        end
        Config.save(cfg)
        if service and service.applyConfig then
            service.applyConfig(cfg)
        end
        dirty = false
        return true, "saved"
    elseif key == keys.r then
        local defs = Config.getDefaults()
        for _, fd in ipairs(fields) do
            editCfg[fd.key] = defs[fd.key]
        end
        dirty = true
        return true
    end
    return false
end
return app