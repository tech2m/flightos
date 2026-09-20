local Config = {}
local CONFIG_PATH = "flightos/config.dat"
local defaults = {
    pitch_kp = 1.5,
    pitch_ki = 0.8,
    pitch_kd = 3.5,
    roll_kp = 0.8,
    roll_ki = 0.4,
    roll_kd = 1.8,
    motor_min = -256,
    motor_max = 256,
    corr_max = 90,
    ki_out_max = 80,
    motor_br_id = "Create_RotationSpeedController_0",
    motor_bl_id = "Create_RotationSpeedController_2",
    motor_fl_id = "Create_RotationSpeedController_4",
    motor_fr_id = "Create_RotationSpeedController_1",
    log_enabled = false,
    stab_enabled = true,
    motor_speed_id = "Create_RotationSpeedController_7",
    motor_speed_left_id = "Create_RotationSpeedController_11",
    motor_speed_right_id = "Create_RotationSpeedController_10",
    motor_steer_id = "Create_RotationSpeedController_9",
    target_x = 0,
    target_y = 64,
    target_z = 0,
    auto_enabled = false,
    speed_invert = false,
    steer_invert = true,
    rs_relay_id = "none",
    rs_side = "top",
    system_enable_side = "back",
    system_enable_active_high = true,
    auto_speed_max = 256,
    auto_steer_max = 256,
    auto_steer_kp = 80,
    auto_steer_kd = 15,
    manual_enabled = true,
    manual_enable_side = "right",
    manual_enable_active_high = true,
    manual_propeller_id = "throttle_lever_1",
    manual_thrust_id = "throttle_lever_2",
    manual_steering_id = "steering_wheel_0",
    manual_propeller_max = 1024,
    manual_thrust_max = 512,
    manual_thrust_steer_max = 512,
    manual_steering_max = 256,
    manual_propeller_invert = true,
    auto_thrust_steer_mix = 1.0,
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
                if loaded.motor_speed_id and not loaded.motor_speed_left_id then
                    cfg.motor_speed_left_id = loaded.motor_speed_id
                end
                if loaded.motor_min == -128 then cfg.motor_min = -256 end
                if loaded.motor_max == 128 then cfg.motor_max = 256 end
                if loaded.auto_speed_max == 128 then cfg.auto_speed_max = 256 end
                if loaded.auto_steer_max == 128 then cfg.auto_steer_max = 256 end
                if loaded.manual_propeller_max == 128 or loaded.manual_propeller_max == 256 then cfg.manual_propeller_max = 1024 end
                if loaded.manual_thrust_max == 128 or loaded.manual_thrust_max == 256 then cfg.manual_thrust_max = 512 end
                if loaded.manual_steering_max == 128 then cfg.manual_steering_max = 256 end
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