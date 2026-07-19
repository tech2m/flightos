local PID = {}
PID.__index = PID
function PID.new(kp, ki, kd)
    return setmetatable({
        kp = kp or 1, ki = ki or 0, kd = kd or 0,
        kd_base = kd or 0, integral = 0, bias = 0,
        prev_angle = nil, prev_sign = 0,
        peak_before_cross = 0, overshoot_after_cross = 0,
        crossed = false, filtered_rate = 0,
        output_min = nil, output_max = nil,
        integral_min = nil, integral_max = nil,
    }, PID)
end
function PID:step(angle, dt)
    dt = dt or 0.05
    local err = -angle
    local p = self.kp * err
    local cur_sign = 0
    if angle > 0.05 then cur_sign = 1
    elseif angle < -0.05 then cur_sign = -1 end
    if self.prev_sign ~= 0 and cur_sign ~= 0 and cur_sign ~= self.prev_sign then
        self.crossed = true
        self.overshoot_after_cross = 0
    end
    if self.crossed then
        if math.abs(angle) > self.overshoot_after_cross then
            self.overshoot_after_cross = math.abs(angle)
        end
        if math.abs(angle) > 0.1 and angle * self.filtered_rate < 0 then
            self.crossed = false
            local overshoot = self.overshoot_after_cross
            if overshoot > 1.0 then
                self.kd = math.min(8.0, self.kd * (1.0 + overshoot * 0.03))
            elseif overshoot < 0.3 then
                self.kd = math.max(self.kd_base * 0.7, self.kd * 0.995)
            end
            self.overshoot_after_cross = 0
        end
    else
        if math.abs(angle) > self.peak_before_cross then
            self.peak_before_cross = math.abs(angle)
        end
    end
    if cur_sign ~= 0 then self.prev_sign = cur_sign end
    local decay = 1.0
    local scale_integration = 1.0
    if err * self.integral < 0 then
        decay = 1.0 - math.min(0.2, math.abs(angle) / 6.0)
    elseif angle * self.filtered_rate < 0 then
        local ratio = math.abs(self.filtered_rate) / (math.abs(angle) + 0.3)
        decay = 1.0 - math.min(0.2, (ratio * ratio) * 0.015)
        scale_integration = math.max(0, 1.0 - math.abs(self.filtered_rate) * 0.2)
    end
    local new_integral = self.integral * decay + (err * scale_integration) * dt
    if self.integral_min and self.integral_max then
        new_integral = math.max(self.integral_min, math.min(self.integral_max, new_integral))
    end
    self.integral = new_integral
    local i = self.ki * self.integral
    if self.ki > 0 then
        if err * self.integral > 0 and math.abs(self.filtered_rate) < 0.75 then
            local shift = i * 0.08 * dt
            local new_bias = math.max(-80, math.min(80, self.bias + shift))
            local actual_shift = new_bias - self.bias
            self.bias = new_bias
            self.integral = self.integral - actual_shift / self.ki
            i = self.ki * self.integral
        end
    end
    local d = 0
    if self.prev_angle ~= nil then
        local raw_rate = (angle - self.prev_angle) / dt
        self.filtered_rate = self.filtered_rate * 0.75 + raw_rate * 0.25
        d = -self.kd * self.filtered_rate
    end
    self.prev_angle = angle
    local output = p + i + d + self.bias
    if self.output_min and self.output_max then
        output = math.max(self.output_min, math.min(self.output_max, output))
    end
    return output, p, i, d
end
function PID:clampOutput(min, max)
    self.output_min = min
    self.output_max = max
end
function PID:limitIntegral(min, max)
    self.integral_min = min
    self.integral_max = max
end
function PID:reset()
    self.integral = 0
    self.bias = 0
    self.prev_angle = nil
    self.prev_sign = 0
    self.peak_before_cross = 0
    self.overshoot_after_cross = 0
    self.crossed = false
    self.filtered_rate = 0
    self.kd = self.kd_base
end
return PID