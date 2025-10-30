local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Suspension = {}
Suspension.SuspensionType = {
    Torsion = "Torsion",
    Christie = "Christie",
    Rigid = "Rigid",
}

local function createSwingArm(hull, wheelPart, pivotCFrame)
    local hinge = Instance.new("HingeConstraint")
    hinge.Name = "SwingArmHinge"
    hinge.Attachment0 = Instance.new("Attachment")
    hinge.Attachment0.Name = "ArmPivot"
    hinge.Attachment0.CFrame = pivotCFrame
    hinge.Attachment0.Parent = hull

    hinge.Attachment1 = Instance.new("Attachment")
    hinge.Attachment1.Name = "WheelArm"
    hinge.Attachment1.Parent = wheelPart
    hinge.LimitsEnabled = false
    hinge.AngularResponsiveness = 0
    hinge.Parent = hull
    return hinge
end

local function createDebugBeam(parent, attachment0, attachment1, color)
    local beam = Instance.new("Beam")
    beam.Name = "DebugBeam"
    beam.Attachment0 = attachment0
    beam.Attachment1 = attachment1
    beam.Width0 = 0.05
    beam.Width1 = 0.05
    beam.Color = ColorSequence.new(color)
    beam.FaceCamera = true
    beam.Parent = parent
    return beam
end

local function defaultDamperSelector(index, suspensionType)
    if suspensionType == Suspension.SuspensionType.Torsion then
        return index == 1 or index == 2 or index == 5 or index == 6
    elseif suspensionType == Suspension.SuspensionType.Christie then
        return index == 1 or index == 5
    end
    return false
end

local WheelState = {}
WheelState.__index = WheelState

function WheelState.new(params)
    local self = setmetatable({}, WheelState)
    self.index = params.index
    self.side = params.side
    self.config = params.config
    self.wheelPart = params.wheelPart
    self.hull = params.hull
    self.hinge = params.hinge
    self.damperEnabled = params.damperEnabled
    self.springType = params.springType
    self.state = {
        armAngle = params.restAngle or 0,
        armVelocity = 0,
        deflection = 0,
        deflectionVelocity = 0,
        lastContactCount = 0,
        sinkage = 0,
        slipRatio = 0,
        slipAngle = 0,
        longitudinalForce = 0,
        lateralForce = 0,
        normalForce = 0,
        damperForce = 0,
    }
    self.debug = {}
    return self
end

function WheelState:updateDebugVisuals()
    if self.hinge and not self.debug.armBeam then
        self.debug.armBeam = createDebugBeam(self.hull, self.hinge.Attachment0, self.hinge.Attachment1, Color3.fromRGB(0, 255, 0))
    end

    if not self.debug.forceBillboard then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "ForceBillboard"
        billboard.Size = UDim2.fromOffset(120, 90)
        billboard.StudsOffset = Vector3.new(0, 2, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = self.wheelPart

        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextStrokeTransparency = 0.5
        label.TextScaled = true
        label.Text = ""
        label.Parent = billboard

        self.debug.forceBillboard = billboard
        self.debug.forceText = label
    end

    if self.debug.forceText then
        self.debug.forceText.Text = string.format(
            "%s%d\\nDef %.3f\\nN %.0f\\nFx %.0f\\nFy %.0f\\nSlip %.2f/%.1f°\\nSink %.2f",
            self.side:sub(1, 1),
            self.index,
            self.state.deflection,
            self.state.normalForce,
            self.state.longitudinalForce,
            self.state.lateralForce,
            self.state.slipRatio,
            math.deg(self.state.slipAngle),
            self.state.sinkage
        )
    end
end

local function semiImplicitEuler(position, velocity, acceleration, dt)
    velocity += acceleration * dt
    position += velocity * dt
    return position, velocity
end

local function applyStops(config, displacement)
    local stopForce = 0
    if displacement > config.bumpStopCompression then
        stopForce += config.bumpStopStiffness * (displacement - config.bumpStopCompression)
    end
    if displacement < -config.droopLimit then
        stopForce -= config.bumpStopStiffness * (-config.droopLimit - displacement)
    end
    return stopForce
end

local function torsionTorque(config, angle, angularVelocity)
    -- Torsion bars resist twist because the steel bar stores elastic energy; torque rises linearly with angle.
    local torque = -config.k * (angle - config.restAngle - config.preload)
    torque -= config.c * angularVelocity
    torque += applyStops(config, angle - config.restAngle)
    return torque
end

local function christieForce(config, deflection, velocity, damperEnabled)
    -- Christie coil bogies use large vertical springs to maximize wheel travel for higher cross-country speed.
    local force = -config.k * (deflection - config.preload)
    if damperEnabled then
        force -= config.c * velocity
    end
    force += applyStops(config, deflection)
    return force
end

local function createWheelPart(radius, width, position, parent)
    local wheel = Instance.new("Part")
    wheel.Shape = Enum.PartType.Cylinder
    wheel.Name = "RoadWheel"
    wheel.Size = Vector3.new(width, radius * 2, radius * 2)
    wheel.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
    wheel.CustomPhysicalProperties = PhysicalProperties.new(75, 0.4, 0.5)
    wheel.Massless = false
    wheel.TopSurface = Enum.SurfaceType.Smooth
    wheel.BottomSurface = Enum.SurfaceType.Smooth
    wheel.Parent = parent
    return wheel
end

local function createHull(config)
    local hull = Instance.new("Part")
    hull.Name = "Hull"
    hull.Size = config.hullSize or Vector3.new(8, 2, 16)
    hull.Anchored = false
    hull.Position = config.hullPosition or Vector3.new(0, 4, 0)
    hull.CustomPhysicalProperties = PhysicalProperties.new(config.mass or 22000, 0.3, 0.4)
    hull.Parent = Workspace

    local cgAttachment = Instance.new("Attachment")
    cgAttachment.Name = "HullCG"
    cgAttachment.Position = config.cgOffset or Vector3.new(0, 0.5, 0)
    cgAttachment.Parent = hull

    return hull, cgAttachment
end

function Suspension.new(config)
    local hull, hullAttachment = createHull(config)
    local self = setmetatable({
        config = config,
        hull = hull,
        hullAttachment = hullAttachment,
        wheelStates = {},
        soilModel = config.soilModel,
        wheelContact = config.wheelContact,
        powertrain = config.powertrain,
        connections = {},
        debugFolder = Instance.new("Folder"),
    }, Suspension)

    self.debugFolder.Name = "SuspensionDebug"
    self.debugFolder.Parent = hull

    self:createRoadWheels()
    self:createIdlerAndSprocket()

    self.connections.heartbeat = RunService.Heartbeat:Connect(function(dt)
        self:update(dt)
    end)

    return self
end

function Suspension:destroy()
    if self.connections.heartbeat then
        self.connections.heartbeat:Disconnect()
    end
    for _, wheelState in ipairs(self.wheelStates) do
        if wheelState.debug.forceBillboard then
            wheelState.debug.forceBillboard:Destroy()
        end
        if wheelState.wheelPart then
            wheelState.wheelPart:Destroy()
        end
    end
    if self.driveMotors then
        for _, motor in pairs(self.driveMotors) do
            motor:Destroy()
        end
    end
    if self.sprockets then
        for _, sprocket in pairs(self.sprockets) do
            sprocket:Destroy()
        end
    end
    if self.idlers then
        for _, data in pairs(self.idlers) do
            if data.constraint then
                data.constraint:Destroy()
            end
            if data.part then
                data.part:Destroy()
            end
        end
    end
    if self.hull then
        self.hull:Destroy()
    end
end

function Suspension:createRoadWheels()
    local cfg = self.config
    local stationSpacing = cfg.stationCount > 1 and cfg.wheelbase / (cfg.stationCount - 1) or 0
    local halfWheelbase = cfg.wheelbase * 0.5
    local widthHalf = cfg.trackWidth * 0.5

    local function createSide(sign, sideName)
        for index = 1, cfg.stationCount do
            local zOffset = -halfWheelbase + (index - 1) * stationSpacing
            local xOffset = sign * widthHalf
            local yOffset = -cfg.armLength * math.sin(math.rad(cfg.armRestAngle or 0))
            local position = self.hull.Position + Vector3.new(xOffset, yOffset, zOffset)

            local wheel = createWheelPart(cfg.wheelRadius, cfg.wheelWidth, position, Workspace)
            local hinge
            if cfg.suspensionType ~= Suspension.SuspensionType.Rigid then
                hinge = createSwingArm(self.hull, wheel, CFrame.new(xOffset, 0, zOffset) * CFrame.Angles(0, 0, math.rad(90)))
            else
                local ball = Instance.new("BallSocketConstraint")
                ball.Name = "RigidJoint"
                ball.Attachment0 = Instance.new("Attachment")
                ball.Attachment0.Parent = self.hull
                ball.Attachment0.Position = Vector3.new(xOffset, 0, zOffset)
                ball.Attachment1 = Instance.new("Attachment")
                ball.Attachment1.Parent = wheel
                ball.Parent = self.hull
            end

            local wheelState = WheelState.new({
                index = index,
                side = sideName,
                config = cfg,
                wheelPart = wheel,
                hull = self.hull,
                hinge = hinge,
                damperEnabled = cfg.damperStations and cfg.damperStations[index] or defaultDamperSelector(index, cfg.suspensionType),
                springType = cfg.suspensionType,
                restAngle = math.rad(cfg.armRestAngle or 0),
            })

            wheelState.armLength = cfg.armLength
            wheelState:updateDebugVisuals()
            table.insert(self.wheelStates, wheelState)
        end
    end

    createSide(1, "Right")
    createSide(-1, "Left")
end

function Suspension:createIdlerAndSprocket()
    local cfg = self.config
    self.sprockets = {}
    self.idlers = {}
    self.driveMotors = {}

    local widthHalf = cfg.trackWidth * 0.5

    local function createEndWheel(sideName, sign)
        local sprocket = Instance.new("Part")
        sprocket.Name = sideName .. "DriveSprocket"
        sprocket.Shape = Enum.PartType.Cylinder
        sprocket.Size = Vector3.new(cfg.sprocketWidth or cfg.wheelWidth, cfg.sprocketRadius * 2, cfg.sprocketRadius * 2)
        sprocket.CFrame = CFrame.new(
            self.hull.Position + Vector3.new(sign * widthHalf, -cfg.armLength, cfg.wheelbase * 0.5 + (cfg.sprocketOffset or 1))
        ) * CFrame.Angles(0, 0, math.rad(90))
        sprocket.Parent = Workspace

        local motor = Instance.new("HingeConstraint")
        motor.Name = sideName .. "DriveMotor"
        motor.Attachment0 = Instance.new("Attachment")
        motor.Attachment0.Parent = self.hull
        motor.Attachment0.Position = sprocket.Position - self.hull.Position
        motor.Attachment1 = Instance.new("Attachment")
        motor.Attachment1.Parent = sprocket
        motor.MotorMaxTorque = cfg.sprocketMaxTorque or 1e6
        motor.Parent = self.hull

        local idler = Instance.new("Part")
        idler.Name = sideName .. "Idler"
        idler.Shape = Enum.PartType.Cylinder
        idler.Size = Vector3.new(cfg.idlerWidth or cfg.wheelWidth, cfg.idlerRadius * 2, cfg.idlerRadius * 2)
        idler.CFrame = CFrame.new(
            self.hull.Position
                + Vector3.new(sign * widthHalf, -cfg.armLength + (cfg.idlerHeightOffset or 0), -cfg.wheelbase * 0.5 - cfg.idlerOffset)
        ) * CFrame.Angles(0, 0, math.rad(90))
        idler.Parent = Workspace

        local idlerConstraint = Instance.new("HingeConstraint")
        idlerConstraint.Name = sideName .. "IdlerPivot"
        idlerConstraint.Attachment0 = Instance.new("Attachment")
        idlerConstraint.Attachment0.Parent = self.hull
        idlerConstraint.Attachment0.Position = idler.Position - self.hull.Position
        idlerConstraint.Attachment1 = Instance.new("Attachment")
        idlerConstraint.Attachment1.Parent = idler
        idlerConstraint.AngularResponsiveness = 0
        idlerConstraint.Parent = self.hull
        -- The idler location works with track tension to keep the track seated around the sprocket and road wheels, preventing de-tracking under load.

        self.sprockets[sideName] = sprocket
        self.driveMotors[sideName] = motor
        self.idlers[sideName] = {
            part = idler,
            constraint = idlerConstraint,
        }
    end

    createEndWheel("Right", 1)
    createEndWheel("Left", -1)
end

function Suspension:update(dt)
    local soilPreset = self.soilModel and self.soilModel:getActivePreset()

    for _, wheelState in ipairs(self.wheelStates) do
        self:updateWheel(wheelState, dt, soilPreset)
        wheelState:updateDebugVisuals()
    end

    if self.powertrain then
        self.powertrain:updateDrive(self, dt)
    end
end

function Suspension:updateWheel(wheelState, dt, soilPreset)
    if not wheelState.wheelPart then
        return
    end

    local wheel = wheelState.wheelPart
    local hinge = wheelState.hinge
    local contactResult

    if self.wheelContact then
        contactResult = self.wheelContact:computeContact(wheelState, soilPreset, dt)
    end

    if contactResult then
        wheelState.state.normalForce = contactResult.normalForce
        wheelState.state.longitudinalForce = contactResult.longitudinalForce
        wheelState.state.lateralForce = contactResult.lateralForce
        wheelState.state.lastContactCount = contactResult.contactCount
        wheelState.state.sinkage = contactResult.sinkage
        wheelState.state.slipRatio = contactResult.slipRatio
        wheelState.state.slipAngle = contactResult.slipAngle
        wheelState.state.deflection = contactResult.deflection
        wheelState.state.deflectionVelocity = contactResult.deflectionVelocity
        wheelState.state.damperForce = contactResult.damperForce
    else
        wheelState.state.normalForce = 0
        wheelState.state.longitudinalForce = 0
        wheelState.state.lateralForce = 0
        wheelState.state.lastContactCount = 0
        wheelState.state.sinkage = 0
        wheelState.state.slipRatio = 0
        wheelState.state.slipAngle = 0
        wheelState.state.damperForce = 0
    end

    if hinge and self.config.suspensionType ~= Suspension.SuspensionType.Rigid then
        local configTable = self.config.torsion or self.config
        local restAngle = wheelState.restAngle or 0
        local angle = hinge.CurrentAngle
        local angularVelocity = wheelState.state.armVelocity
        local torque = 0

        if wheelState.springType == Suspension.SuspensionType.Torsion then
            configTable.restAngle = restAngle
            torque = torsionTorque(configTable, angle, angularVelocity)
        elseif wheelState.springType == Suspension.SuspensionType.Christie then
            torque = christieForce(self.config.christie or self.config, wheelState.state.deflection, wheelState.state.deflectionVelocity, wheelState.damperEnabled)
        end

        local inertia = self.config.armInertia or 75
        local angularAcceleration = torque / inertia
        local newAngle, newVelocity = semiImplicitEuler(angle, angularVelocity, angularAcceleration, dt)
        wheelState.state.armAngle = newAngle
        wheelState.state.armVelocity = newVelocity
    end
end

function Suspension:getWheelStates()
    return self.wheelStates
end

return Suspension
