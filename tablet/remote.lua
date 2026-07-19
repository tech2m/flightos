local CHANNEL = 42
local VERSION = "1.0"
local modem = peripheral.find("modem", function(name, m) return m.isWireless() end)
if not modem then
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.red)
    print("No wireless modem found!")
    print("Attach an ender modem.")
    return
end
modem.open(CHANNEL)
local w, h = term.getSize()
local data = {}
local remoteCfg = {}
local connected = false
local missedPackets = 0
local shipId = nil
local activeTab = 1
local tabNames = {"Dash", "Auto", "Ctrl", "Update"}
local updateUrl = ""
local editFields = {
    { key = "target_x",       label = "Target X" },
    { key = "target_y",       label = "Target Y" },
    { key = "target_z",       label = "Target Z" },
    { key = "auto_speed_max", label = "Max Speed" },
    { key = "auto_steer_max", label = "Max Steer" },
    { key = "auto_steer_kp",  label = "Steer Kp" },
    { key = "auto_steer_kd",  label = "Steer Kd" },
}
local selectedField = 1
local editScrollOffset = 0
local function sendCmd(msg)
    msg.type = "cmd"
    modem.transmit(CHANNEL, CHANNEL, msg)
end
local function padRight(s, len)
    s = tostring(s)
    if #s >= len then return s:sub(1, len) end
    return s .. string.rep(" ", len - #s)
end
local function drawTabBar()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    local x = 1
    for i, name in ipairs(tabNames) do
        term.setCursorPos(x, 1)
        if i == activeTab then
            term.setBackgroundColor(colors.cyan)
            term.setTextColor(colors.black)
        else
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.lightGray)
        end
        term.write(" " .. name .. " ")
        x = x + #name + 2
    end
    term.setBackgroundColor(colors.gray)
    term.write(string.rep(" ", w - x + 1))
end
local function drawStatusBar()
    term.setCursorPos(1, 2)
    if connected then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.lime)
        term.write(padRight(" LINK: Ship #" .. tostring(shipId), w))
    else
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.red)
        term.write(padRight(" NO LINK - Scanning...", w))
    end
end
local function clearContent()
    term.setBackgroundColor(colors.black)
    for y = 3, h do
        term.setCursorPos(1, y)
        term.write(string.rep(" ", w))
    end
end
local function wrt(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    if bg then term.setBackgroundColor(bg) end
    if fg then term.setTextColor(fg) end
    term.write(text)
end
local function drawDash()
    clearContent()
    if not connected then
        wrt(2, 5, "Waiting for signal...", colors.gray, colors.black)
        return
    end
    local d = data
    wrt(1, 3, " Roll :", colors.gray, colors.black)
    local rollVal = d.roll and string.format("%+6.1f", d.roll) or "  N/A"
    local rollCol = colors.lime
    if d.roll and math.abs(d.roll) > 3 then rollCol = colors.red
    elseif d.roll and math.abs(d.roll) > 1 then rollCol = colors.yellow end
    wrt(9, 3, padRight(rollVal, w - 9), rollCol)
    wrt(1, 4, " Pitch:", colors.gray, colors.black)
    local pitchVal = d.pitch and string.format("%+6.1f", d.pitch) or "  N/A"
    local pitchCol = colors.lime
    if d.pitch and math.abs(d.pitch) > 3 then pitchCol = colors.red
    elseif d.pitch and math.abs(d.pitch) > 1 then pitchCol = colors.yellow end
    wrt(9, 4, padRight(pitchVal, w - 9), pitchCol)
    wrt(1, 6, " GPS:", colors.gray, colors.black)
    if d.x then
        local gps = string.format("%d %d %d", math.floor(d.x+0.5), math.floor(d.y+0.5), math.floor(d.z+0.5))
        wrt(7, 6, padRight(gps, w - 7), colors.white)
    else
        wrt(7, 6, padRight("OFFLINE", w - 7), colors.red)
    end
    wrt(1, 8, " Stab:", colors.gray, colors.black)
    if d.enabled then
        wrt(8, 8, padRight("ON", w - 8), colors.lime)
    else
        wrt(8, 8, padRight("OFF", w - 8), colors.red)
    end
    wrt(1, 9, " Auto:", colors.gray, colors.black)
    if d.auto_enabled then
        wrt(8, 9, padRight("ACTIVE", w - 8), colors.lime)
    else
        wrt(8, 9, padRight("OFF", w - 8), colors.gray)
    end
    if d.auto_enabled and d.dist then
        wrt(1, 11, " Dist:", colors.gray, colors.black)
        wrt(8, 11, padRight(string.format("%.0fm", d.dist), w - 8), colors.white)
        wrt(1, 12, " Prog:", colors.gray, colors.black)
        local prog = d.progress or 0
        local barW = w - 9
        local filled = math.floor(barW * prog / 100)
        wrt(8, 12, "", colors.lime)
        term.write(string.rep("=", filled))
        term.setTextColor(colors.gray)
        term.write(string.rep("-", barW - filled))
        wrt(w - 3, 12, string.format("%2d%%", prog), colors.white)
    end
    if remoteCfg.target_x then
        wrt(1, 14, " Targ:", colors.gray, colors.black)
        local targ = string.format("%d %d %d", remoteCfg.target_x, remoteCfg.target_y or 64, remoteCfg.target_z)
        wrt(8, 14, padRight(targ, w - 8), colors.cyan)
    end
    wrt(1, 16, string.rep("-", w), colors.cyan, colors.black)
    local fl = d.fl or 0
    local fr = d.fr or 0
    local bl = d.bl or 0
    local br = d.br or 0
    wrt(1, 17, string.format(" FL:%+5.1f FR:%+5.1f", fl, fr), colors.lightGray, colors.black)
    wrt(1, 18, string.format(" BL:%+5.1f BR:%+5.1f", bl, br), colors.lightGray, colors.black)
end
local function drawAuto()
    clearContent()
    if not connected then
        wrt(2, 5, "Waiting for signal...", colors.gray, colors.black)
        return
    end
    wrt(1, 3, " Status:", colors.gray, colors.black)
    if data.auto_enabled then
        wrt(10, 3, padRight("ACTIVE", w - 10), colors.lime)
    else
        wrt(10, 3, padRight("DISABLED", w - 10), colors.red)
    end
    local visibleLines = h - 7
    for i = 1, visibleLines do
        local idx = i + editScrollOffset
        if idx > #editFields then break end
        local f = editFields[idx]
        local val = remoteCfg[f.key]
        local lineY = 4 + i
        local displayVal = (val == nil and "?" or tostring(val))
        if idx == selectedField then
            wrt(1, lineY, " > " .. f.label .. ":", colors.cyan, colors.black)
            wrt(15, lineY, padRight(displayVal, w - 15), colors.cyan)
        else
            wrt(1, lineY, "   " .. f.label .. ":", colors.gray, colors.black)
            wrt(15, lineY, padRight(displayVal, w - 15), colors.white)
        end
    end
    wrt(1, h - 1, padRight(" [Enter] Edit  [Space] Toggle", w), colors.lightGray, colors.black)
    wrt(1, h, padRight(" [Up/Dn] Nav", w), colors.lightGray, colors.black)
end
local function drawCtrl()
    clearContent()
    if not connected then
        wrt(2, 5, "Waiting for signal...", colors.gray, colors.black)
        return
    end
    wrt(2, 4, "Quick Controls:", colors.cyan, colors.black)
    wrt(2, 6, " [A] Toggle Autopilot", colors.white, colors.black)
    if data.auto_enabled then
        wrt(w - 5, 6, " ON ", colors.black, colors.lime)
    else
        wrt(w - 5, 6, " OFF", colors.white, colors.red)
    end
    wrt(2, 8, " [S] Toggle Stabilizer", colors.white, colors.black)
    if data.enabled then
        wrt(w - 5, 8, " ON ", colors.black, colors.lime)
    else
        wrt(w - 5, 8, " OFF", colors.white, colors.red)
    end
    wrt(2, 10, " [I] Invert Speed", colors.white, colors.black)
    if remoteCfg.speed_invert then
        wrt(w - 5, 10, " INV", colors.black, colors.yellow)
    else
        wrt(w - 5, 10, " NRM", colors.white, colors.gray)
    end
    wrt(2, 12, " [O] Invert Steer", colors.white, colors.black)
    if remoteCfg.steer_invert then
        wrt(w - 5, 12, " INV", colors.black, colors.yellow)
    else
        wrt(w - 5, 12, " NRM", colors.white, colors.gray)
    end
    wrt(2, 14, " [T] Test Motors", colors.white, colors.black)
    if data.test_msg then
        wrt(w - 7, 14, " ACTIVE", colors.black, colors.yellow)
        wrt(2, 15, padRight(data.test_msg, w - 2), colors.yellow, colors.black)
    else
        wrt(w - 7, 14, " IDLE  ", colors.white, colors.gray)
        wrt(2, 15, string.rep(" ", w - 2), colors.black, colors.black)
    end
    wrt(1, 16, string.rep("-", w), colors.cyan, colors.black)
    wrt(2, 17, "Remote v" .. VERSION, colors.gray, colors.black)
    wrt(2, 18, "Channel: " .. CHANNEL, colors.gray, colors.black)
end
local function drawUpdate()
    clearContent()
    wrt(2, 4, "FlightOS Remote Update", colors.cyan, colors.black)
    wrt(2, 5, string.rep("-", w - 2), colors.gray, colors.black)
    wrt(2, 7, "Enter update URL:", colors.white, colors.black)
    wrt(2, 9, "[ " .. padRight(updateUrl == "" and "click Enter to edit" or updateUrl, w - 6) .. " ]", colors.lightGray, colors.black)
    wrt(2, 12, "Press [U] to run update", colors.yellow, colors.black)
    wrt(2, h, padRight(" [Enter] Edit URL  [U] Run Update", w), colors.lightGray, colors.black)
end
local function draw()
    drawTabBar()
    drawStatusBar()
    if activeTab == 1 then
        drawDash()
    elseif activeTab == 2 then
        drawAuto()
    elseif activeTab == 3 then
        drawCtrl()
    elseif activeTab == 4 then
        drawUpdate()
    end
end
local function switchTab(idx)
    if idx < 1 or idx > #tabNames then return end
    activeTab = idx
    draw()
end
local function handleAutoEvent(event)
    if event[1] == "key" then
        local key = event[2]
        if key == keys.up then
            selectedField = math.max(1, selectedField - 1)
            if selectedField <= editScrollOffset then
                editScrollOffset = selectedField - 1
            end
            return true
        elseif key == keys.down then
            selectedField = math.min(#editFields, selectedField + 1)
            local visibleLines = h - 7
            if selectedField > editScrollOffset + visibleLines then
                editScrollOffset = selectedField - visibleLines
            end
            return true
        elseif key == keys.space then
            sendCmd({ cmd = "toggle_auto" })
            return true
        elseif key == keys.enter then
            local f = editFields[selectedField]
            local lineY = 4 + (selectedField - editScrollOffset)
            term.setCursorPos(15, lineY)
            term.setBackgroundColor(colors.white)
            term.setTextColor(colors.black)
            term.write(string.rep(" ", w - 16))
            term.setCursorPos(15, lineY)
            term.setCursorBlink(true)
            local input = read(nil, nil, nil, remoteCfg[f.key] == nil and "" or tostring(remoteCfg[f.key]))
            term.setCursorBlink(false)
            if input and input ~= "" then
                local numVal = tonumber(input)
                if f.key == "target_x" or f.key == "target_y" or f.key == "target_z" then
                    local tx = f.key == "target_x" and (numVal or remoteCfg.target_x) or remoteCfg.target_x
                    local ty = f.key == "target_y" and (numVal or remoteCfg.target_y) or remoteCfg.target_y
                    local tz = f.key == "target_z" and (numVal or remoteCfg.target_z) or remoteCfg.target_z
                    sendCmd({ cmd = "set_target", x = tx, y = ty, z = tz })
                    remoteCfg.target_x = tx
                    remoteCfg.target_y = ty
                    remoteCfg.target_z = tz
                else
                    sendCmd({ cmd = "set_config", key = f.key, value = numVal or input })
                    remoteCfg[f.key] = numVal or input
                end
            end
            return true
        end
    end
    return false
end
local function handleCtrlEvent(event)
    if event[1] == "char" then
        local ch = event[2]:lower()
        if ch == "a" or ch == "ф" then
            sendCmd({ cmd = "toggle_auto" })
            return true
        elseif ch == "s" or ch == "ы" then
            sendCmd({ cmd = "toggle_stab" })
            return true
        elseif ch == "i" or ch == "ш" then
            local newVal = not remoteCfg.speed_invert
            sendCmd({ cmd = "set_config", key = "speed_invert", value = newVal })
            remoteCfg.speed_invert = newVal
            return true
        elseif ch == "o" or ch == "щ" then
            local newVal = not remoteCfg.steer_invert
            sendCmd({ cmd = "set_config", key = "steer_invert", value = newVal })
            remoteCfg.steer_invert = newVal
            return true
        elseif ch == "t" or ch == "е" then
            sendCmd({ cmd = "test_motors" })
            return true
        end
    end
    return false
end
local function handleUpdateEvent(event)
    if event[1] == "key" then
        local key = event[2]
        if key == keys.enter then
            term.setCursorPos(4, 9)
            term.setBackgroundColor(colors.white)
            term.setTextColor(colors.black)
            term.write(string.rep(" ", w - 6))
            term.setCursorPos(4, 9)
            term.setCursorBlink(true)
            local input = read(nil, nil, nil, updateUrl)
            term.setCursorBlink(false)
            if input then
                updateUrl = input
            end
            return true
        end
    elseif event[1] == "char" then
        local ch = event[2]:lower()
        if ch == "u" or ch == "г" then
            if updateUrl == "" then return false end
            term.setBackgroundColor(colors.black)
            term.clear()
            wrt(2, 5, "Connecting to dpaste...", colors.cyan, colors.black)
            local ok, err = pcall(function()
                local res = http.get(updateUrl)
                if res then
                    local content = res.readAll()
                    res.close()
                    local f = fs.open("installer.lua", "w")
                    f.write(content)
                    f.close()
                    term.clear()
                    wrt(2, 5, "Downloaded successfully!", colors.lime, colors.black)
                    wrt(2, 7, "Running installer...", colors.white, colors.black)
                    sleep(1.0)
                    shell.run("installer.lua")
                else
                    error("Connection failed")
                end
            end)
            if not ok then
                term.clear()
                wrt(2, 5, "Update failed!", colors.red, colors.black)
                wrt(2, 7, tostring(err), colors.lightGray, colors.black)
                sleep(3.0)
            end
            return true
        end
    end
    return false
end
term.setBackgroundColor(colors.black)
term.clear()
draw()
local refreshTimer = os.startTimer(0.5)
while true do
    local event = {os.pullEvent()}
    if event[1] == "modem_message" and event[3] == CHANNEL then
        local msg = event[5]
        if type(msg) == "table" and msg.type == "telemetry" then
            data = msg.data or {}
            remoteCfg = msg.cfg or remoteCfg
            shipId = msg.ship_id
            connected = true
            missedPackets = 0
        end
    end
    if event[1] == "timer" and event[2] == refreshTimer then
        missedPackets = missedPackets + 1
        if missedPackets > 6 then
            connected = false
            shipId = nil
        end
        if missedPackets > 16 then
            term.setBackgroundColor(colors.black)
            term.clear()
            wrt(2, 5, "======================", colors.red, colors.black)
            wrt(2, 6, "   CONNECTION LOST!   ", colors.red, colors.black)
            wrt(2, 7, "======================", colors.red, colors.black)
            wrt(2, 9, "Rebooting in 3...", colors.yellow, colors.black)
            sleep(1.0)
            wrt(2, 9, "Rebooting in 2...", colors.yellow, colors.black)
            sleep(1.0)
            wrt(2, 9, "Rebooting in 1...", colors.yellow, colors.black)
            sleep(1.0)
            os.reboot()
        end
        draw()
        refreshTimer = os.startTimer(0.5)
    end
    if event[1] == "key" then
        local key = event[2]
        if key == keys.f1 then switchTab(1)
        elseif key == keys.f2 then switchTab(2)
        elseif key == keys.f3 then switchTab(3)
        elseif key == keys.f4 then switchTab(4)
        elseif key == keys.tab then
            switchTab((activeTab % #tabNames) + 1)
        end
    end
    if event[1] == "mouse_click" and event[4] == 1 then
        local mx = event[3]
        local x = 1
        for i, name in ipairs(tabNames) do
            local x2 = x + #name + 1
            if mx >= x and mx <= x2 then
                switchTab(i)
                break
            end
            x = x2 + 1
        end
    end
    if activeTab == 2 then
        if handleAutoEvent(event) then draw() end
    elseif activeTab == 3 then
        if handleCtrlEvent(event) then draw() end
    elseif activeTab == 4 then
        if handleUpdateEvent(event) then draw() end
    end
end