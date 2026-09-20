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
local tabNames = {"Dash", "Auto", "Ctrl", "Music", "Update"}
local updateUrl = ""
local musicView = "now"
local musicSelectedResult = 1
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
    if data.emergency_stop then
        local blinkOn = math.floor(os.clock() * 4) % 2 == 0
        term.setBackgroundColor(blinkOn and colors.red or colors.black)
        term.setTextColor(blinkOn and colors.white or colors.red)
        term.setCursorPos(1, math.floor(h / 2) - 1)
        term.write(string.rep(" ", w))
        wrt(math.max(1, math.floor((w - 16) / 2)), math.floor(h / 2), "!!! NOT-AUS !!!", blinkOn and colors.white or colors.red, blinkOn and colors.red or colors.black)
        wrt(math.max(1, math.floor((w - 25) / 2)), math.floor(h / 2) + 2, "ENTER ZUM REAKTIVIEREN", colors.white, colors.black)
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
    wrt(2, 16, " [V] Toggle Aux Propellers", colors.white, colors.black)
    if data.aux_enabled then
        wrt(w - 5, 16, " ON ", colors.black, colors.lime)
    else
        wrt(w - 5, 16, " OFF", colors.white, colors.red)
    end
    wrt(2, 17, string.format(" Aux HW: L %s R %s", data.aux_left_ready and "OK" or "--", data.aux_right_ready and "OK" or "--"), colors.gray, colors.black)
    wrt(2, 18, string.format(" Aux thrust: %+d", data.aux_thrust or 0), colors.gray, colors.black)
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
local function drawMusic()
    clearContent()
    if not connected then
        wrt(2, 5, "Waiting for signal...", colors.gray, colors.black)
        return
    end
    local music = data.music or {}
    wrt(2, 4, musicView == "now" and "Now Playing" or "Search", colors.cyan, colors.black)
    if musicView == "search" then
        wrt(2, 6, "[Enter] Search", colors.white, colors.black)
        if music.search_error then
            wrt(2, 8, padRight(music.search_error_msg or "Network error", w - 2), colors.red, colors.black)
        elseif music.last_search and not music.search_results then
            wrt(2, 8, "Searching...", colors.yellow, colors.black)
        elseif music.search_results then
            for i = 1, math.min(5, #music.search_results) do
                local result = music.search_results[i]
                local color = i == musicSelectedResult and colors.cyan or colors.white
                wrt(2, 9 + (i - 1) * 2, string.format("%d. %s", i, result.name or "Unknown"), color, colors.black)
                wrt(2, 10 + (i - 1) * 2, padRight("   " .. (result.artist or ""), w - 2), colors.lightGray, colors.black)
            end
        else
            wrt(2, 8, "Enter a title or link to search", colors.gray, colors.black)
        end
        wrt(1, h - 1, padRight(" [1] Play  [2] Next  [3] Queue  [B] Back", w), colors.lightGray, colors.black)
        wrt(1, h, padRight(" [Enter] Search  [Up/Dn] Select", w), colors.lightGray, colors.black)
        return
    end
    if music.now_playing then
        wrt(2, 6, padRight(music.now_playing.name or "Unknown", w - 2), colors.white, colors.black)
        wrt(2, 7, padRight(music.now_playing.artist or "", w - 2), colors.lightGray, colors.black)
    else
        wrt(2, 6, "Not playing", colors.gray, colors.black)
    end
    local status = music.is_loading and "Loading..." or (music.is_error and "Network error" or (music.playing and "Playing" or "Paused"))
    wrt(2, 9, padRight(status, w - 2), music.is_error and colors.red or colors.yellow, colors.black)
    local loopLabel = music.looping == 1 and "Queue" or (music.looping == 2 and "Song" or "Off")
    wrt(2, 11, "[P] Play/Pause  [N] Next", colors.white, colors.black)
    wrt(2, 12, "[X] Stop  [L] Loop: " .. loopLabel, colors.white, colors.black)
    local volume = music.volume or 0
    wrt(2, 14, string.format("Volume: %d%%", math.floor(volume / 3 * 100 + 0.5)), colors.lightGray, colors.black)
    wrt(2, 15, "[-] Down   [+] Up", colors.white, colors.black)
    wrt(2, 17, "Queue: " .. tostring(music.queue_length or 0), colors.gray, colors.black)
    if music.queue then
        for i = 1, math.min(3, #music.queue) do
            wrt(2, 17 + i, string.format("%d. %s", i, music.queue[i].name or "Unknown"), colors.white, colors.black)
        end
    end
    wrt(1, h - 1, padRight(" [P] Play/Pause  [N] Next  [X] Stop", w), colors.lightGray, colors.black)
    wrt(1, h, padRight(" [L] Loop  [+/-] Volume  [Tab] Search", w), colors.lightGray, colors.black)
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
        drawMusic()
    elseif activeTab == 5 then
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
        elseif ch == "v" or ch == "м" then
            sendCmd({ cmd = "toggle_aux" })
            return true
        elseif ch == "e" or ch == "у" then
            sendCmd({ cmd = "emergency_stop" })
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
local function handleMusicEvent(event)
    local music = data.music or {}
    if event[1] == "key" then
        if event[2] == keys.enter then
            if musicView == "now" then
                musicView = "search"
            else
                term.setCursorPos(2, 6)
                term.setBackgroundColor(colors.white)
                term.setTextColor(colors.black)
                term.write(string.rep(" ", w - 2))
                term.setCursorPos(3, 6)
                term.setCursorBlink(true)
                local input = read(nil, nil, nil, music.last_search or "")
                term.setCursorBlink(false)
                if input and input ~= "" then
                    musicSelectedResult = 1
                    sendCmd({ cmd = "music", action = "search", query = input })
                end
            end
            return true
        elseif musicView == "search" and event[2] == keys.up then
            musicSelectedResult = math.max(1, musicSelectedResult - 1)
            return true
        elseif musicView == "search" and event[2] == keys.down then
            musicSelectedResult = math.min(math.max(1, #(music.search_results or {})), musicSelectedResult + 1)
            return true
        end
    elseif event[1] == "char" then
        local ch = event[2]:lower()
        if musicView == "now" and (ch == "s" or ch == "ы") then
            musicView = "search"
            return true
        end
        if musicView == "search" and music.search_results and music.search_results[musicSelectedResult] then
            if ch == "1" then
                sendCmd({ cmd = "music", action = "result", mode = "play_now", index = musicSelectedResult })
                musicView = "now"
            elseif ch == "2" then
                sendCmd({ cmd = "music", action = "result", mode = "play_next", index = musicSelectedResult })
                musicView = "now"
            elseif ch == "3" then
                sendCmd({ cmd = "music", action = "result", mode = "queue", index = musicSelectedResult })
                musicView = "now"
            elseif ch == "b" or ch == "и" then
                musicView = "now"
            else
                return false
            end
            return true
        elseif musicView == "now" then
            if ch == "p" or ch == "з" then
                sendCmd({ cmd = "music", action = "toggle" })
            elseif ch == "n" or ch == "т" then
                sendCmd({ cmd = "music", action = "skip" })
            elseif ch == "x" or ch == "х" then
                sendCmd({ cmd = "music", action = "stop" })
            elseif ch == "l" or ch == "д" then
                sendCmd({ cmd = "music", action = "loop" })
            elseif ch == "+" then
                sendCmd({ cmd = "music", action = "volume", value = math.min(3, (music.volume or 0) + 0.1) })
            elseif ch == "-" then
                sendCmd({ cmd = "music", action = "volume", value = math.max(0, (music.volume or 0) - 0.1) })
            else
                return false
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
    local emergencyCleared = false
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
    if event[1] == "key" and event[2] == keys.enter and data.emergency_stop then
        sendCmd({ cmd = "clear_emergency_stop" })
        draw()
        emergencyCleared = true
    end
    if event[1] == "key" then
        local key = event[2]
        if key == keys.f1 then switchTab(1)
        elseif key == keys.f2 then switchTab(2)
        elseif key == keys.f3 then switchTab(3)
        elseif key == keys.f4 then switchTab(4)
        elseif key == keys.f5 then switchTab(5)
        end
    end
    if event[1] == "mouse_click" then
        local mx = event[3]
        if event[4] == 1 then
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
    end
    if not emergencyCleared and activeTab == 2 then
        if handleAutoEvent(event) then draw() end
    elseif not emergencyCleared and activeTab == 3 then
        if handleCtrlEvent(event) then draw() end
    elseif not emergencyCleared and activeTab == 4 then
        if handleMusicEvent(event) then draw() end
    elseif not emergencyCleared and activeTab == 5 then
        if handleUpdateEvent(event) then draw() end
    end
end