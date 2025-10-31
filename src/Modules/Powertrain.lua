local Powertrain = {}
Powertrain.__index = Powertrain

local function evaluateCurve(curve, rpm)
    if #curve == 0 then
        return 0
    end
    if rpm <= curve[1].rpm then
        return curve[1].torque
    end
    for i = 1, #curve - 1 do
        local a = curve[i]
        local b = curve[i + 1]
        if rpm <= b.rpm then
            local alpha = (rpm - a.rpm) / (b.rpm - a.rpm)
            return a.torque + (b.torque - a.torque) * alpha
        end
    end
    return curve[#curve].torque
end

local function clamp(x, minValue, maxValue)
    if x < minValue then
        return minValue
    elseif x > maxValue then
        return maxValue
    end
    return x
end

function Powertrain.new(config)
    local self = setmetatable({}, Powertrain)
    self.engineTorqueCurve = config.engineTorqueCurve or {
        {rpm = 600, torque = 2500},
        {rpm = 1500, torque = 3800},
        {rpm = 2200, torque = 3200},
    }
    self.gears = config.gears or { -5.8, -3.2, 0, 4.5, 3.1, 1.9 }
    self.currentGearIndex = config.initialGearIndex or 4
    self.differentialRatio = config.differentialRatio or 5.8
    self.finalDriveEfficiency = config.finalDriveEfficiency or 0.9
    self.backlash = config.backlash or math.rad(2)
    self.brakeTorque = config.brakeTorque or 25000
    self.maxForwardSpeed = config.maxForwardSpeed or 35
    self.input = {
        throttle = 0,
        steer = 0,
        brake = 0,
    }
    self.leftTrackSpeed = 0
    self.rightTrackSpeed = 0
    self.neutralSteerGain = config.neutralSteerGain or 1
    return self
end

function Powertrain:setInputs(inputs)
    for key, value in pairs(inputs) do
        if self.input[key] ~= nil then
            self.input[key] = clamp(value, -1, 1)
        end
    end
end

function Powertrain:shiftGear(delta)
    local newIndex = clamp(self.currentGearIndex + delta, 1, #self.gears)
    self.currentGearIndex = newIndex
end

function Powertrain:evaluateEngineTorque(rpm)
    return evaluateCurve(self.engineTorqueCurve, rpm)
end

function Powertrain:updateDrive(suspension, dt)
    if not suspension.driveMotors then
        return
    end

    local gearRatio = self.gears[self.currentGearIndex] or 1
    if gearRatio == 0 then
        gearRatio = 0.01 -- prevent divide by zero in neutral
    end

    local sprocketRadius = suspension.config.sprocketRadius
    local maxSpeed = suspension.config.maxForwardSpeed or self.maxForwardSpeed
    local desiredLinear = self.input.throttle * maxSpeed
    local steer = self.input.steer

    local leftDesired = desiredLinear - steer * self.neutralSteerGain
    local rightDesired = desiredLinear + steer * self.neutralSteerGain

    local leftOmegaDesired = leftDesired / math.max(sprocketRadius, 0.01)
    local rightOmegaDesired = rightDesired / math.max(sprocketRadius, 0.01)

    self.leftTrackSpeed = leftDesired
    self.rightTrackSpeed = rightDesired

    local function applyMotor(sideName, desiredOmega)
        local motor = suspension.driveMotors[sideName]
        local sprocket = suspension.sprockets[sideName]
        if not motor or not sprocket then
            return
        end

        local currentOmega = sprocket.AssemblyAngularVelocity:Dot(sprocket.CFrame.XVector)
        local error = desiredOmega - currentOmega

        if math.abs(error) < self.backlash then
            desiredOmega = currentOmega
        end

        motor.AngularVelocity = desiredOmega
        local wheelRPM = math.abs(desiredOmega) * 60 / (2 * math.pi)
        local engineRPM = wheelRPM * math.abs(gearRatio) * self.differentialRatio
        engineRPM = math.clamp(engineRPM, 600, 3000)
        local engineTorque = self:evaluateEngineTorque(engineRPM) * self.finalDriveEfficiency

        local driveTorque = engineTorque * math.abs(gearRatio) * self.differentialRatio
        motor.MotorMaxTorque = driveTorque

        if self.input.brake > 0 then
            motor.MotorMaxTorque = motor.MotorMaxTorque + self.brakeTorque * self.input.brake
        end
    end

    applyMotor("Left", leftOmegaDesired)
    applyMotor("Right", rightOmegaDesired)
end

return Powertrain
