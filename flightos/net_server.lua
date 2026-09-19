local Config = require("config")
local NetServer = {}
local CHANNEL = 42
local service, cfg
local modem
local broadcastTimer
function NetServer.init(svc, config)
    service = svc
    cfg = config
    modem = peripheral.find("modem", function(name, m)
        return m.isWireless()
    end)
    if modem then
        modem.open(CHANNEL)
    end
end
local function buildTelemetry()
    local d = service.data
    return {
        type = "telemetry",
        ship_id = os.getComputerID(),
        data = {
            roll = d.roll,
            pitch = d.pitch,
            x = d.x, y = d.y, z = d.z,
            auto_enabled = d.auto_enabled,
            enabled = d.enabled,
            manual_active = d.manual_active,
            manual_propeller = d.manual_propeller,
            manual_thrust = d.manual_thrust,
            manual_steering = d.manual_steering,
            dist = d.dist,
            progress = d.progress,
            fl = d.fl, fr = d.fr,
            bl = d.bl, br = d.br,
            rollOut = d.rollOut,
            pitchOut = d.pitchOut,
        },
        cfg = {
            target_x = cfg.target_x,
            target_y = cfg.target_y,
            target_z = cfg.target_z,
            auto_speed_max = cfg.auto_speed_max,
            auto_steer_max = cfg.auto_steer_max,
            auto_steer_kp = cfg.auto_steer_kp,
            auto_steer_kd = cfg.auto_steer_kd,
            speed_invert = cfg.speed_invert,
            steer_invert = cfg.steer_invert,
        }
    }
end
local function handleCommand(msg)
    if type(msg) ~= "table" or msg.type ~= "cmd" then return end
    if service.data.system_enabled == false then return end
    if msg.cmd == "set_target" then
        cfg.target_x = tonumber(msg.x) or cfg.target_x
        cfg.target_y = tonumber(msg.y) or cfg.target_y
        cfg.target_z = tonumber(msg.z) or cfg.target_z
        Config.save(cfg)
        if service.applyConfig then service.applyConfig(cfg) end
        os.queueEvent("remote_config_changed")
    elseif msg.cmd == "toggle_auto" then
        service.setAutoEnabled(not service.data.auto_enabled)
    elseif msg.cmd == "toggle_stab" then
        service.setEnabled(not service.data.enabled)
    elseif msg.cmd == "set_config" then
        local key = msg.key
        local val = msg.value
        if key and val ~= nil then
            if key == "auto_speed_max" or key == "auto_steer_max" or key == "auto_steer_kp" or key == "auto_steer_kd" then
                cfg[key] = tonumber(val) or cfg[key]
            elseif key == "speed_invert" or key == "steer_invert" then
                if type(val) == "string" then
                    cfg[key] = (val:lower() == "true")
                else
                    cfg[key] = val
                end
            else
                cfg[key] = val
            end
            Config.save(cfg)
            if service.applyConfig then service.applyConfig(cfg) end
            os.queueEvent("remote_config_changed")
        end
    elseif msg.cmd == "test_motors" then
        if service.startMotorTest then service.startMotorTest() end
    elseif msg.cmd == "ping" then
        if modem then
            modem.transmit(CHANNEL, CHANNEL, {
                type = "pong",
                ship_id = os.getComputerID(),
            })
        end
    end
end
function NetServer.loop()
    if not modem then return end
    broadcastTimer = os.startTimer(0.5)
    while true do
        local event = {os.pullEvent()}
        if event[1] == "modem_message" and event[3] == CHANNEL then
            local ok, msg = pcall(function() return event[5] end)
            if ok and type(msg) == "table" then
                handleCommand(msg)
            end
        elseif event[1] == "timer" and event[2] == broadcastTimer then
            local telem = buildTelemetry()
            modem.transmit(CHANNEL, CHANNEL, telem)
            broadcastTimer = os.startTimer(0.5)
        end
    end
end
return NetServer