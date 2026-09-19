local PID = require("pid")
local Service = {}
local gimbal, motor_BR, motor_BL, motor_FL, motor_FR, monitor
local motor_speed_left, motor_speed_right, motor_steer
local manual_propeller, manual_thrust, manual_steering
local rollPID, pitchPID
local cfg
local running = false
local tick = 0
local lastTime = 0
local logFile = nil
local lastConfigSaveTime = os.clock()
Service.data = {
    roll = 0, pitch = 0,
    rollOut = 0, pitchOut = 0,
    rP = 0, rI = 0, rD = 0,
    pP = 0, pI = 0, pD = 0,
    fl = 0, fr = 0, bl = 0, br = 0,
    rollRate = 0, pitchRate = 0,
    rollBias = 0, pitchBias = 0,
    rollKd = 0, pitchKd = 0,
    tick = 0, dt = 0,
    enabled = false,
    system_enabled = false,
    logging = false,
    auto_enabled = false,
    manual_active = false,
    manual_propeller = 0,
    manual_thrust = 0,
    manual_steering = 0,
    x = nil, y = nil, z = nil,
    dist = nil, progress = 0,
    test_msg = nil,
}
local function clamp(val, lo, hi)
    return math.max(lo, math.min(hi, val))
end
local function setMotorSpeeds(fl, fr, bl, br, outputMax)
    local maxSpeed = outputMax or cfg.motor_max
    local minSpeed = -maxSpeed
    fl = clamp(fl, minSpeed, maxSpeed)
    fr = clamp(fr, minSpeed, maxSpeed)
    bl = clamp(bl, minSpeed, maxSpeed)
    br = clamp(br, minSpeed, maxSpeed)
    parallel.waitForAll(
        function() motor_FL.setTargetSpeed(fl) end,
        function() motor_FR.setTargetSpeed(fr) end,
        function() motor_BL.setTargetSpeed(bl) end,
        function() motor_BR.setTargetSpeed(br) end
    )
    return fl, fr, bl, br
end
local function stopMotors()
    pcall(function()
        parallel.waitForAll(
            function() motor_FL.setTargetSpeed(0) end,
            function() motor_FR.setTargetSpeed(0) end,
            function() motor_BL.setTargetSpeed(0) end,
            function() motor_BR.setTargetSpeed(0) end
        )
    end)
end
local function setThrustMotorSpeeds(left, right, outputMax)
    local maxSpeed = outputMax or cfg.motor_max
    left = clamp(left, -maxSpeed, maxSpeed)
    right = clamp(right, -maxSpeed, maxSpeed)
    parallel.waitForAll(
        function() motor_speed_left.setTargetSpeed(left) end,
        function() motor_speed_right.setTargetSpeed(right) end
    )
    return left, right
end
local function stopThrustMotors()
    pcall(function()
        parallel.waitForAll(
            function() motor_speed_left.setTargetSpeed(0) end,
            function() motor_speed_right.setTargetSpeed(0) end
        )
    end)
end
local function readSystemEnabled()
    local side = cfg and cfg.system_enable_side or "back"
    local ok, powered = pcall(redstone.getInput, side)
    if not ok then return false end
    if cfg and cfg.system_enable_active_high == false then
        return not powered
    end
    return powered
end
local function stopAllOutputs()
    stopMotors()
    stopThrustMotors()
    pcall(function()
        if motor_steer then motor_steer.setTargetSpeed(0) end
    end)
end
local function findByType(peripheralType, index)
    local matches = {}
    for _, name in ipairs(peripheral.getNames()) do
        local ok, actualType = pcall(peripheral.getType, name)
        if ok and (actualType == peripheralType or actualType == "create:" .. peripheralType) then
            matches[#matches + 1] = name
        end
    end
    return matches[index or 1] and peripheral.wrap(matches[index or 1]) or nil
end
local function wrapConfigured(id, peripheralType, index)
    if id and id ~= "" and id ~= "none" then
        local configured = peripheral.wrap(id)
        if configured then return configured end
    end
    return findByType(peripheralType, index)
end
local function readControl(control)
    if not control then return nil end
    local methods = {"getValue", "getPosition", "getAngle", "getRotation", "getWheelAngle", "getPercent", "getPower", "getSpeed", "getState"}
    for _, method in ipairs(methods) do
        if type(control[method]) == "function" then
            local ok, value = pcall(control[method])
            if ok and type(value) == "number" then
                return value, method
            end
        end
    end
    return nil
end
local function normalizedControl(control, inputMax)
    local value, method = readControl(control)
    if value == nil then return nil end
    if math.abs(value) > 1 then
        local scale = inputMax or 100
        value = value / scale
    end
    return clamp(value, -1, 1)
end
local function normalizedSteering(control)
    if not control then return nil end
    local methods = {"getWheelAngle", "getAngle", "getRotation", "getValue", "getPosition", "getPercent"}
    for _, method in ipairs(methods) do
        if type(control[method]) == "function" then
            local ok, value = pcall(control[method])
            if ok and type(value) == "number" then
                if math.abs(value) > 1 then
                    value = value / 90
                end
                return clamp(value, -1, 1)
            end
        end
    end
    return nil
end
local function applyManualControls()
    if not cfg.manual_enabled then return false end
    local propeller = normalizedControl(manual_propeller, 15)
    local thrust = normalizedControl(manual_thrust, 15)
    local steering = normalizedSteering(manual_steering)
    if not propeller and not thrust and not steering then return false end
    local thrustSpeed = (thrust or 0) * (cfg.manual_thrust_max or 128)
    local thrustSteer = (steering or 0) * (cfg.manual_thrust_steer_max or cfg.manual_thrust_max or 128)
    if motor_speed_left and motor_speed_right then
        setThrustMotorSpeeds(
            thrustSpeed - thrustSteer,
            thrustSpeed + thrustSteer,
            cfg.manual_thrust_max or 512
        )
    end
    if motor_steer then
        pcall(motor_steer.setTargetSpeed, (steering or 0) * (cfg.manual_steering_max or 128))
    end
    if propeller then
        local speed = propeller * (cfg.manual_propeller_max or 128)
        if cfg.manual_propeller_invert then
            speed = -speed
        end
        setMotorSpeeds(speed, speed, speed, speed, cfg.manual_propeller_max or 1024)
    end
    Service.data.manual_active = true
    Service.data.manual_propeller = propeller or 0
    Service.data.manual_thrust = thrust or 0
    Service.data.manual_steering = steering or 0
    return true
end
local function drawBar(monitor, y, label, val, maxVal, colorOk, colorWarn, colorErr)
    local mw, _ = monitor.getSize()
    local barW = mw - 18
    if barW < 8 then barW = 8 end
    monitor.setCursorPos(2, y)
    monitor.setTextColor(colors.lightGray)
    monitor.write(label .. ": ")
    local absVal = math.abs(val)
    local tColor = colorOk
    if absVal > 3.0 then tColor = colorErr
    elseif absVal > 1.0 then tColor = colorWarn end
    monitor.setTextColor(tColor)
    monitor.write(string.format("%+6.2f ", val))
    local center = math.floor(barW / 2) + 1
    local percent = val / maxVal
    local shift = math.floor(percent * (barW / 2) + 0.5)
    monitor.setTextColor(colors.gray)
    monitor.write("[")
    for i = 1, barW do
        if i == center then
            monitor.setTextColor(colors.white)
            monitor.write("|")
        elseif (shift > 0 and i > center and i <= center + shift) or
               (shift < 0 and i < center and i >= center + shift) then
            monitor.setTextColor(tColor)
            monitor.write("=")
        else
            monitor.write(" ")
        end
    end
    monitor.setTextColor(colors.gray)
    monitor.write("]")
end
local function updateMonitor()
    if not monitor then return end
    local d = Service.data
    local mw, mh = monitor.getSize()
    local function fillLine(y, background)
        monitor.setCursorPos(1, y)
        monitor.setBackgroundColor(background)
        monitor.write(string.rep(" ", mw))
    end
    local function centerText(y, text, foreground, background)
        local x = math.floor((mw - #text) / 2) + 1
        monitor.setCursorPos(x, y)
        monitor.setBackgroundColor(background)
        monitor.setTextColor(foreground)
        monitor.write(text)
        monitor.setBackgroundColor(colors.black)
    end
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    if not d.system_enabled then
        fillLine(1, colors.gray)
        centerText(1, "Unsinkbar 4", colors.white, colors.gray)
        centerText(math.floor((mh + 1) / 2), "DISPLAY DEAKTIVIERT", colors.orange, colors.black)
        return
    end
    fillLine(1, colors.blue)
    centerText(1, "Unsinkbar 4", colors.white, colors.blue)
    if mw >= 38 then
        monitor.setCursorPos(2, 3)
        monitor.setTextColor(colors.lightGray)
        monitor.write("Roll : ")
        local absRoll = math.abs(d.roll)
        local rColor = colors.lime
        if absRoll > 3.0 then rColor = colors.red
        elseif absRoll > 1.0 then rColor = colors.yellow end
        monitor.setTextColor(rColor)
        monitor.write(string.format("%+5.1f ", d.roll))
        monitor.setCursorPos(21, 3)
        monitor.setTextColor(colors.gray)
        monitor.write("Auto: ")
        local aStatus = d.auto_enabled and "ACTIVE  " or "DISABLED"
        local aColor = d.auto_enabled and colors.lime or colors.red
        monitor.setTextColor(aColor)
        monitor.write(aStatus)
        monitor.setCursorPos(2, 4)
        monitor.setTextColor(colors.lightGray)
        monitor.write("Pitch: ")
        local absPitch = math.abs(d.pitch)
        local pColor = colors.lime
        if absPitch > 3.0 then pColor = colors.red
        elseif absPitch > 1.0 then pColor = colors.yellow end
        monitor.setTextColor(pColor)
        monitor.write(string.format("%+5.1f ", d.pitch))
        monitor.setCursorPos(21, 4)
        monitor.setTextColor(colors.gray)
        monitor.write("POS : ")
        if d.x then
            monitor.setTextColor(colors.white)
            monitor.write(string.format("%d %d ", math.floor(d.x+0.5), math.floor(d.z+0.5)))
        else
            monitor.setTextColor(colors.red)
            monitor.write("GPS OFFLINE  ")
        end
        monitor.setCursorPos(2, 5)
        monitor.setTextColor(colors.gray)
        monitor.write("PID  : ")
        monitor.setTextColor(colors.white)
        monitor.write(string.format("%.1f/%.1f", cfg.roll_kp or 0, d.rollKd or 0))
        monitor.setCursorPos(21, 5)
        monitor.setTextColor(colors.gray)
        monitor.write("Targ: ")
        monitor.setTextColor(colors.white)
        monitor.write(string.format("%d %d ", cfg.target_x or 0, cfg.target_z or 0))
        monitor.setCursorPos(2, 6)
        monitor.setTextColor(colors.gray)
        monitor.write("Bias : ")
        monitor.setTextColor(colors.white)
        monitor.write(string.format("%+4.1f", d.rollBias or 0))
        monitor.setCursorPos(21, 6)
        if d.auto_enabled and d.dist then
            monitor.setTextColor(colors.gray)
            monitor.write("Dest: ")
            monitor.setTextColor(colors.white)
            monitor.write(string.format("%d ", math.floor(d.dist + 0.5)))
        else
            monitor.setTextColor(colors.gray)
            monitor.write("Dest: ----")
        end
        monitor.setCursorPos(2, 7)
        if d.auto_enabled and d.dist then
            monitor.setTextColor(colors.gray)
            monitor.write("Prog : ")
            local barW = mw - 9
            if barW >= 8 then
                monitor.setTextColor(colors.gray)
                monitor.write("[")
                local filled = math.floor((d.progress / 100) * (barW - 2) + 0.5)
                for i = 1, barW - 2 do
                    if i < filled then
                        monitor.setTextColor(colors.lime)
                        monitor.write("=")
                    elseif i == filled then
                        monitor.setTextColor(colors.lime)
                        monitor.write(">")
                    else
                        monitor.write(" ")
                    end
                end
                monitor.setTextColor(colors.gray)
                monitor.write("] ")
                monitor.setTextColor(colors.white)
                monitor.write(string.format("%d%%", math.floor(d.progress)))
            else
                monitor.setTextColor(colors.lime)
                monitor.write(string.format("%d%%", math.floor(d.progress)))
            end
        else
            monitor.write(string.rep(" ", mw - 2))
        end
    else
        monitor.setCursorPos(2, 3)
        monitor.setTextColor(colors.lightGray)
        monitor.write("Roll : ")
        local absRoll = math.abs(d.roll)
        local rColor = colors.lime
        if absRoll > 3.0 then rColor = colors.red
        elseif absRoll > 1.0 then rColor = colors.yellow end
        monitor.setTextColor(rColor)
        monitor.write(string.format("%+6.2f deg", d.roll))
        monitor.setCursorPos(2, 4)
        monitor.setTextColor(colors.lightGray)
        monitor.write("Pitch: ")
        local absPitch = math.abs(d.pitch)
        local pColor = colors.lime
        if absPitch > 3.0 then pColor = colors.red
        elseif absPitch > 1.0 then pColor = colors.yellow end
        monitor.setTextColor(pColor)
        monitor.write(string.format("%+6.2f deg", d.pitch))
        if d.x then
            monitor.setCursorPos(2, 5)
            monitor.setTextColor(colors.gray)
            monitor.write("GPS  : ")
            monitor.setTextColor(colors.white)
            local gpsStr = string.format("%d %d %d", math.floor(d.x+0.5), math.floor(d.y+0.5), math.floor(d.z+0.5))
            monitor.write(gpsStr)
            local left = mw - 9 - #gpsStr
            if left > 0 then monitor.write(string.rep(" ", left)) end
        else
            monitor.setCursorPos(2, 5)
            monitor.setTextColor(colors.gray)
            monitor.write("GPS  : ")
            monitor.setTextColor(colors.red)
            monitor.write("NO SIGNAL")
            local left = mw - 9 - 9
            if left > 0 then monitor.write(string.rep(" ", left)) end
        end
        if d.auto_enabled and d.dist then
            monitor.setCursorPos(2, 6)
            monitor.setTextColor(colors.gray)
            monitor.write("Target: ")
            monitor.setTextColor(colors.white)
            local tStr = string.format("%d %d", cfg.target_x, cfg.target_z)
            monitor.write(tStr)
            local left = mw - 9 - #tStr
            if left > 0 then monitor.write(string.rep(" ", left)) end
            monitor.setCursorPos(2, 7)
            monitor.setTextColor(colors.gray)
            monitor.write("Prog  : ")
            local barW = mw - 18
            if barW >= 6 then
                monitor.setTextColor(colors.gray)
                monitor.write("[")
                local filled = math.floor((d.progress / 100) * (barW - 2) + 0.5)
                for i = 1, barW - 2 do
                    if i < filled then
                        monitor.setTextColor(colors.lime)
                        monitor.write("=")
                    elseif i == filled then
                        monitor.setTextColor(colors.lime)
                        monitor.write(">")
                    else
                        monitor.write(" ")
                    end
                end
                monitor.setTextColor(colors.gray)
                monitor.write("] ")
                monitor.setTextColor(colors.white)
                monitor.write(string.format("%d%%", math.floor(d.progress)))
            else
                monitor.setTextColor(colors.lime)
                monitor.write(string.format("%d%%", math.floor(d.progress)))
                local left2 = mw - 9 - 4
                if left2 > 0 then monitor.write(string.rep(" ", left2)) end
            end
        else
            monitor.setCursorPos(2, 6)
            monitor.setTextColor(colors.gray)
            monitor.write("PID   : ")
            monitor.setTextColor(colors.white)
            local pidStr = string.format("Kp:%.1f Ki:%.1f Kd:%.1f", cfg.roll_kp, cfg.roll_ki, d.rollKd)
            monitor.write(pidStr)
            local left = mw - 9 - #pidStr
            if left > 0 then monitor.write(string.rep(" ", left)) end
            monitor.setCursorPos(2, 7)
            monitor.setTextColor(colors.gray)
            monitor.write("Biases: ")
            monitor.setTextColor(colors.white)
            local biasStr = string.format("R:%+4.1f P:%+4.1f", d.rollBias, d.pitchBias)
            monitor.write(biasStr)
            local left2 = mw - 9 - #biasStr
            if left2 > 0 then monitor.write(string.rep(" ", left2)) end
        end
    end
    monitor.setCursorPos(2, 8)
    monitor.setTextColor(colors.lightGray)
    monitor.write("FL:")
    monitor.setTextColor(d.fl ~= 0 and colors.lime or colors.white)
    monitor.write(string.format("%+5.1f ", d.fl))
    monitor.setTextColor(colors.lightGray)
    monitor.write("FR:")
    monitor.setTextColor(d.fr ~= 0 and colors.lime or colors.white)
    monitor.write(string.format("%+5.1f ", d.fr))
    monitor.setTextColor(colors.lightGray)
    monitor.write("BL:")
    monitor.setTextColor(d.bl ~= 0 and colors.lime or colors.white)
    monitor.write(string.format("%+5.1f ", d.bl))
    monitor.setTextColor(colors.lightGray)
    monitor.write("BR:")
    monitor.setTextColor(d.br ~= 0 and colors.lime or colors.white)
    monitor.write(string.format("%+5.1f", d.br))
    if mh >= 10 then
        monitor.setCursorPos(1, 9)
        monitor.setTextColor(colors.cyan)
        monitor.write(string.rep("-", mw))
        monitor.setCursorPos(2, 10)
        local Music = package.loaded["music_service"]
        if Music and Music.state.playing and Music.state.now_playing then
            monitor.setTextColor(colors.lime)
            local txt = Music.state.now_playing.name .. " - " .. Music.state.now_playing.artist
            if #txt > mw - 4 then txt = txt:sub(1, mw - 4) end
            monitor.write(txt)
        else
            monitor.setTextColor(colors.gray)
            monitor.write("Player Idle")
        end
    end
end
function Service.applyConfig(config)
    cfg = config
    if rollPID and pitchPID then
        rollPID.kp = cfg.roll_kp
        rollPID.ki = cfg.roll_ki
        rollPID.kd = cfg.roll_kd
        rollPID.kd_base = cfg.roll_kd
        pitchPID.kp = cfg.pitch_kp
        pitchPID.ki = cfg.pitch_ki
        pitchPID.kd = cfg.pitch_kd
        pitchPID.kd_base = cfg.pitch_kd
        local rollKiLimit = cfg.ki_out_max / cfg.roll_ki
        local pitchKiLimit = cfg.ki_out_max / cfg.pitch_ki
        rollPID:clampOutput(-cfg.corr_max, cfg.corr_max)
        pitchPID:clampOutput(-cfg.corr_max, cfg.corr_max)
        rollPID:limitIntegral(-rollKiLimit, rollKiLimit)
        pitchPID:limitIntegral(-pitchKiLimit, pitchKiLimit)
        gimbal   = peripheral.find("gimbal_sensor")
        motor_BR = peripheral.wrap(cfg.motor_br_id)
        motor_BL = peripheral.wrap(cfg.motor_bl_id)
        motor_FL = peripheral.wrap(cfg.motor_fl_id)
        motor_FR = peripheral.wrap(cfg.motor_fr_id)
        monitor  = peripheral.find("monitor")
        motor_speed_left = peripheral.wrap(cfg.motor_speed_left_id or cfg.motor_speed_id)
        motor_speed_right = peripheral.wrap(cfg.motor_speed_right_id)
        motor_steer = peripheral.wrap(cfg.motor_steer_id)
        manual_propeller = wrapConfigured(cfg.manual_propeller_id, "throttle_lever", 1)
        manual_thrust = wrapConfigured(cfg.manual_thrust_id, "throttle_lever", 2)
        manual_steering = wrapConfigured(cfg.manual_steering_id, "steering_wheel")
    end
end
function Service.init(config)
    cfg = config
    gimbal   = peripheral.find("gimbal_sensor")
    motor_BR = peripheral.wrap(cfg.motor_br_id)
    motor_BL = peripheral.wrap(cfg.motor_bl_id)
    motor_FL = peripheral.wrap(cfg.motor_fl_id)
    motor_FR = peripheral.wrap(cfg.motor_fr_id)
    monitor  = peripheral.find("monitor")
    motor_speed_left = peripheral.wrap(cfg.motor_speed_left_id or cfg.motor_speed_id)
    motor_speed_right = peripheral.wrap(cfg.motor_speed_right_id)
    motor_steer = peripheral.wrap(cfg.motor_steer_id)
    manual_propeller = wrapConfigured(cfg.manual_propeller_id, "throttle_lever", 1)
    manual_thrust = wrapConfigured(cfg.manual_thrust_id, "throttle_lever", 2)
    manual_steering = wrapConfigured(cfg.manual_steering_id, "steering_wheel")
    if not gimbal then return false, "Gimbal not found" end
    if not motor_BR then return false, "Motor BR not found" end
    if not motor_BL then return false, "Motor BL not found" end
    if not motor_FL then return false, "Motor FL not found" end
    if not motor_FR then return false, "Motor FR not found" end
    if not motor_speed_left then return false, "Left thrust motor not found" end
    if not motor_speed_right then return false, "Right thrust motor not found" end
    rollPID  = PID.new(cfg.roll_kp, cfg.roll_ki, cfg.roll_kd)
    pitchPID = PID.new(cfg.pitch_kp, cfg.pitch_ki, cfg.pitch_kd)
    Service.applyConfig(cfg)
    if monitor then
        monitor.setTextScale(0.5)
        monitor.clear()
    end
    tick = 0
    lastTime = os.clock()
    running = true
    Service.data.enabled = cfg.stab_enabled
    return true
end
local prev_gps_x, prev_gps_z
local last_heading_x, last_heading_z
local smooth_vx, smooth_vz = 0, 0
local last_set_speed, last_set_steer = 0, 0
local current_heading = 0
local is_moving = false
local start_dist
local prev_err = 0
local auto_start_time = nil
local steer_tick_counter = 0
local test_running = false
local test_seq_idx = 1
local test_phase = "wait"
local test_phase_start = 0
local function setAutopilotRedstone(powered)
    pcall(function()
        local relay
        if cfg.rs_relay_id and cfg.rs_relay_id ~= "none" and cfg.rs_relay_id ~= "" then
            relay = peripheral.wrap(cfg.rs_relay_id)
        else
            relay = peripheral.find("redstone_relay")
        end
        if relay then
            relay.setOutput(cfg.rs_side or "top", powered)
        end
    end)
end
function Service.setEnabled(en)
    if en and not readSystemEnabled() then return false end
    Service.data.enabled = en
    if not en then
        stopMotors()
    end
    return true
end
function Service.setAutoEnabled(en)
    if en and not readSystemEnabled() then return false end
    Service.data.auto_enabled = en
    setAutopilotRedstone(en)
    if not en then
        prev_gps_x, prev_gps_z = nil, nil
        last_heading_x, last_heading_z = nil, nil
        smooth_vx, smooth_vz = 0, 0
        last_set_speed, last_set_steer = 0, 0
        is_moving = false
        start_dist = nil
        prev_err = 0
        auto_start_time = nil
        steer_tick_counter = 0
        pcall(function()
            stopThrustMotors()
            if motor_steer then motor_steer.setTargetSpeed(0) end
        end)
    end
end
function Service.isEnabled()
    return Service.data.enabled
end
function Service.startMotorTest()
    Service.setEnabled(false)
    Service.setAutoEnabled(false)
    test_running = true
    test_seq_idx = 1
    test_phase = "wait"
    test_phase_start = os.clock()
    Service.data.test_msg = "Preparing test..."
end
function Service.startLogging()
    if logFile then return end
    logFile = fs.open("flightlog.txt", "w")
    if logFile then
        logFile.writeLine("tick\tdt\troll\tpitch\trollOut\tpitchOut\tP_r\tI_r\tD_r\tP_p\tI_p\tD_p\tFL\tFR\tBL\tBR")
        logFile.flush()
        Service.data.logging = true
    end
end
function Service.stopLogging()
    if logFile then
        logFile.close()
        logFile = nil
    end
    Service.data.logging = false
end
function Service.clearLogging()
    Service.stopLogging()
    if fs.exists("flightlog.txt") then
        fs.delete("flightlog.txt")
    end
end
local monitorTick = 0
function Service.step(runStabilizer)
    if not running then return end
    local systemEnabled = readSystemEnabled()
    Service.data.system_enabled = systemEnabled
    if not systemEnabled then
        if Service.data.enabled or Service.data.auto_enabled or test_running then
            Service.data.enabled = false
            Service.data.auto_enabled = false
            test_running = false
            Service.data.test_msg = nil
            setAutopilotRedstone(false)
        end
        stopAllOutputs()
        Service.data.manual_active = false
        Service.data.dist = nil
        Service.data.progress = 0
        updateMonitor()
        return
    end
    if test_running then
        local now = os.clock()
        local elapsed = now - test_phase_start
        local names = {"FL Fan", "FR Fan", "BL Fan", "BR Fan"}
        local active_name = names[test_seq_idx]
        if test_phase == "wait" then
            setMotorSpeeds(0, 0, 0, 0)
            local remain = math.max(0, math.ceil(3.0 - elapsed))
            Service.data.test_msg = active_name .. " prep: " .. remain .. "s"
            if elapsed >= 3.0 then
                test_phase = "spin"
                test_phase_start = now
            end
        elseif test_phase == "spin" then
            local spd = 45
            if test_seq_idx == 1 then setMotorSpeeds(spd, 0, 0, 0)
            elseif test_seq_idx == 2 then setMotorSpeeds(0, spd, 0, 0)
            elseif test_seq_idx == 3 then setMotorSpeeds(0, 0, spd, 0)
            elseif test_seq_idx == 4 then setMotorSpeeds(0, 0, 0, spd) end
            Service.data.test_msg = active_name .. " active!"
            if elapsed >= 3.0 then
                setMotorSpeeds(0, 0, 0, 0)
                test_seq_idx = test_seq_idx + 1
                if test_seq_idx > 4 then
                    test_running = false
                    Service.data.test_msg = nil
                else
                    test_phase = "wait"
                    test_phase_start = now
                end
            end
        end
        pcall(function()
            stopThrustMotors()
            if motor_steer then motor_steer.setTargetSpeed(0) end
        end)
        updateMonitor()
        return
    end
    local now = os.clock()
    local dt = math.max(now - lastTime, 0.001)
    lastTime = now
    local d = Service.data
    d.manual_active = false
    local manualActive = applyManualControls()
    if manualActive then
        d.auto_enabled = false
        d.dist = nil
        d.progress = 0
        setAutopilotRedstone(false)
    end
    local ok, angles = pcall(function() return gimbal.getAngles() end)
    if not ok or not angles then return end
    local rollAngle  = angles[1]
    local pitchAngle = angles[2]
    local rollOut, rP, rI, rD = 0, 0, 0, 0
    local pitchOut, pP, pI, pD = 0, 0, 0, 0
    if Service.data.enabled and runStabilizer then
        rollOut, rP, rI, rD = rollPID:step(rollAngle, dt)
        pitchOut, pP, pI, pD = pitchPID:step(pitchAngle, dt)
        local nowTime = os.clock()
        if nowTime - lastConfigSaveTime >= 300 then
            lastConfigSaveTime = nowTime
            local changed = false
            local newRollKd = math.max(0.5, math.min(8.0, rollPID.kd))
            if newRollKd ~= cfg.roll_kd then
                cfg.roll_kd = newRollKd
                rollPID.kd_base = newRollKd
                changed = true
            end
            local newPitchKd = math.max(0.5, math.min(8.0, pitchPID.kd))
            if newPitchKd ~= cfg.pitch_kd then
                cfg.pitch_kd = newPitchKd
                pitchPID.kd_base = newPitchKd
                changed = true
            end
            if changed then
                local Config = require("config")
                Config.save(cfg)
            end
        end
    else
        if rollPID.prev_angle ~= nil then
            local raw = (rollAngle - rollPID.prev_angle) / dt
            rollPID.filtered_rate = rollPID.filtered_rate * 0.75 + raw * 0.25
        end
        rollPID.prev_angle = rollAngle
        if pitchPID.prev_angle ~= nil then
            local raw = (pitchAngle - pitchPID.prev_angle) / dt
            pitchPID.filtered_rate = pitchPID.filtered_rate * 0.75 + raw * 0.25
        end
        pitchPID.prev_angle = pitchAngle
    end
    local fl = -pitchOut + rollOut
    local fr = -pitchOut - rollOut
    local bl =  pitchOut + rollOut
    local br =  pitchOut - rollOut
    if Service.data.enabled and runStabilizer then
        fl, fr, bl, br = setMotorSpeeds(fl, fr, bl, br)
    end
    d.roll = rollAngle
    d.pitch = pitchAngle
    d.rollOut = rollOut
    d.pitchOut = pitchOut
    d.rP = rP; d.rI = rI; d.rD = rD
    d.pP = pP; d.pI = pI; d.pD = pD
    d.fl = fl; d.fr = fr; d.bl = bl; d.br = br
    d.rollRate = rollPID.filtered_rate
    d.pitchRate = pitchPID.filtered_rate
    d.rollBias = rollPID.bias
    d.pitchBias = pitchPID.bias
    d.rollKd = rollPID.kd
    d.pitchKd = pitchPID.kd
    d.tick = tick
    d.dt = dt
    if manualActive then
        d.manual_active = true
    elseif d.auto_enabled and motor_speed_left and motor_speed_right and motor_steer then
        local cx, cy, cz = d.x, d.y, d.z
        if cx and cz then
            local tx = cfg.target_x or 0
            local tz = cfg.target_z or 0
            local dx = tx - cx
            local dz = tz - cz
            local dist = math.sqrt(dx*dx + dz*dz)
            if not start_dist then
                start_dist = dist
            end
            local progress = 0
            if start_dist and start_dist > 0 then
                progress = math.max(0, math.min(100, (1 - dist / start_dist) * 100))
            end
            d.dist = dist
            d.progress = progress
            if dist > 3 then
                if not auto_start_time then
                    auto_start_time = os.clock()
                end
                if not last_heading_x then
                    last_heading_x = cx
                    last_heading_z = cz
                    smooth_vx = 0
                    smooth_vz = 0
                end
                if prev_gps_x and (cx ~= prev_gps_x or cz ~= prev_gps_z) then
                    local dx_move = cx - last_heading_x
                    local dz_move = cz - last_heading_z
                    local move_dist = math.sqrt(dx_move*dx_move + dz_move*dz_move)
                    if move_dist > 0.5 then
                        smooth_vx = smooth_vx * 0.7 + dx_move * 0.3
                        smooth_vz = smooth_vz * 0.7 + dz_move * 0.3
                        current_heading = math.atan2(smooth_vx, smooth_vz)
                        is_moving = true
                        last_heading_x = cx
                        last_heading_z = cz
                    end
                end
                prev_gps_x = cx
                prev_gps_z = cz
                local max_speed = cfg.auto_speed_max or 128
                local elapsed = os.clock() - auto_start_time
                local accel_ramp = math.min(1.0, elapsed / 5.0)
                local cruise_speed = max_speed * accel_ramp
                local brake_dist = 100
                local reverse_dist = 15
                local base_speed
                if dist < reverse_dist then
                    local reverse_factor = (reverse_dist - dist) / reverse_dist
                    base_speed = -max_speed * 0.5 * reverse_factor
                elseif dist < brake_dist then
                    local decel_factor = (dist - reverse_dist) / (brake_dist - reverse_dist)
                    base_speed = cruise_speed * math.max(0.15, decel_factor)
                else
                    base_speed = cruise_speed
                end
                if cfg.speed_invert then base_speed = -base_speed end
                local speed = clamp(base_speed, -max_speed, max_speed)
                local steer_blend = math.min(1.0, math.max(0, elapsed / 3.0))
                local steer_speed = 0
                if is_moving and steer_blend > 0 and dist > reverse_dist then
                    local target_h = math.atan2(dx, dz)
                    local err = target_h - current_heading
                    err = math.atan2(math.sin(err), math.cos(err))
                    local derr = err - prev_err
                    derr = math.atan2(math.sin(derr), math.cos(derr))
                    local deriv = derr / dt
                    prev_err = err
                    local abs_err = math.abs(err)
                    local kp_factor = (cfg.auto_steer_kp or 80.0) / 80.0
                    local kd_factor = (cfg.auto_steer_kd or 15.0) / 15.0
                    local proportional = (abs_err / 0.20) * kp_factor
                    local damping = math.abs(deriv) * kd_factor * 0.02
                    local turn_strength = clamp((proportional - damping) * steer_blend, 0, 1)
                    if abs_err >= 0.03 then
                        steer_speed = (err > 0 and 1 or -1) * (cfg.auto_steer_max or 128) * turn_strength
                        if cfg.steer_invert then
                            steer_speed = -steer_speed
                        end
                    end
                else
                    steer_tick_counter = 0
                end
                local thrustSteer = steer_speed * (cfg.auto_thrust_steer_mix or 1.0)
                setThrustMotorSpeeds(
                    speed - thrustSteer,
                    speed + thrustSteer,
                    max_speed
                )
                last_set_speed = speed
                last_set_steer = steer_speed
                pcall(motor_steer.setTargetSpeed, steer_speed)
            else
                stopThrustMotors()
                last_set_speed = 0
                last_set_steer = 0
                pcall(motor_steer.setTargetSpeed, 0)
                d.auto_enabled = false
                d.dist = nil
                d.progress = 100
                start_dist = nil
                auto_start_time = nil
                setAutopilotRedstone(false)
            end
        end
    else
        d.dist = nil
        d.progress = 0
        start_dist = nil
    end
    monitorTick = monitorTick + 1
    if not Service.data.enabled or monitorTick % 4 == 0 then
        updateMonitor()
    end
    tick = tick + 1
    if logFile and Service.data.enabled and runStabilizer then
        if tick % 100 == 0 then
            local size = fs.getSize("flightlog.txt")
            if size and size > 500 * 1024 then
                logFile.close()
                fs.delete("flightlog.txt")
                logFile = fs.open("flightlog.txt", "w")
                if logFile then
                    logFile.writeLine("[Auto-cleaned: log size exceeded 500 KB]")
                    logFile.writeLine("tick\tdt\troll\tpitch\trollOut\tpitchOut\tP_r\tI_r\tD_r\tP_p\tI_p\tD_p\tFL\tFR\tBL\tBR")
                    logFile.flush()
                end
            end
        end
        if logFile then
            logFile.writeLine(string.format(
                "%d\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.1f\t%.1f\t%.1f\t%.1f",
                tick, dt, rollAngle, pitchAngle, rollOut, pitchOut,
                rP, rI, rD, pP, pI, pD, fl, fr, bl, br
            ))
            if tick % 40 == 0 then
                logFile.flush()
            end
        end
    end
end
function Service.getRollPID()
    return rollPID
end
function Service.getPitchPID()
    return pitchPID
end
function Service.gpsLoop()
    while running do
        local x, y, z = gps.locate(0.5)
        if x then
            Service.data.x = x
            Service.data.y = y
            Service.data.z = z
        end
        sleep(0.5)
    end
end
function Service.loop()
    while running do
        if Service.data.enabled then
            Service.step(true)
            sleep(0.05)
        else
            Service.step(false)
            sleep(0.2)
        end
    end
end
function Service.stop()
    running = false
    Service.setAutoEnabled(false)
    stopMotors()
    Service.stopLogging()
end
function Service.getConfig()
    return cfg
end
return Service