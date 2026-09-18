local Config = {}
local CONFIG_PATH = "flightos/config.dat"
local defaults = {
    pitch_kp = 1.5,
    pitch_ki = 0.8,
    pitch_kd = 3.5,
    roll_kp = 0.8,
    roll_ki = 0.4,
    roll_kd = 1.8,
    motor_min = -128,
    motor_max = 128,
    corr_max = 90,
    ki_out_max = 80,
    motor_br_id = "Create_RotationSpeedController_0",
    motor_bl_id = "Create_RotationSpeedController_1",
    motor_fl_id = "Create_RotationSpeedController_2",
    motor_fr_id = "Create_RotationSpeedController_3",
    log_enabled = false,
    stab_enabled = true,
    motor_speed_id = "Create_RotationSpeedController_5",
    motor_steer_id = "Create_RotationSpeedController_4",
    target_x = 0,
    target_y = 64,
    target_z = 0,
    auto_enabled = false,
    speed_invert = false,
    steer_invert = false,
    rs_relay_id = "none",
    rs_side = "top",
    auto_speed_max = 128,
    auto_steer_max = 128,
    auto_steer_kp = 80,
    auto_steer_kd = 15,
    manual_enabled = true,
    manual_propeller_id = "none",
    manual_thrust_id = "none",
    manual_steering_id = "none",
    manual_propeller_max = 128,
    manual_thrust_max = 128,
    manual_steering_max = 128,
}
function Config.load()
    local cfg = {}
    for k, v in pairs(defaults) do
        cfg[k] = v
    end
    if fs.exists(CONFIG_PATH) then
        local f = fs.open(CONFIG_PATH, "r")
        if f then
            local data = f.readAll()
            f.close()
            local loaded = textutils.unserialise(data)
            if type(loaded) == "table" then
                for k, v in pairs(loaded) do
                    cfg[k] = v
                end
            end
        end
    end
    return cfg
end
function Config.save(cfg)
    local f = fs.open(CONFIG_PATH, "w")
    if f then
        f.write(textutils.serialise(cfg))
        f.close()
        return true
    end
    return false
end
function Config.getDefaults()
    local d = {}
    for k, v in pairs(defaults) do
        d[k] = v
    end
    return d
end
return Config