local Workspace = game:GetService("Workspace")

local WheelContact = {}
WheelContact.__index = WheelContact

local DEFAULT_SOIL = {
    name = "Hard Road",
    kc = 1.5e5,
    kphi = 1.2e5,
    n = 1,
    cohesion = 1000,
    phi = math.rad(28),
    shearK = 0.05,
    rollingResistance = 0.015,
    mu = 0.9,
}

local function createRaycastParams()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.IgnoreWater = true
    params.FilterDescendantsInstances = {}
    return params
end

local function blendSlip(slipRatio, slipAngle)
    return math.sqrt(slipRatio * slipRatio + slipAngle * slipAngle)
end

local function computeContactPatch(radius, deflection, width)
    if deflection <= 0 then
        return 0, 0
    end
    local contactLength = math.sqrt(2 * radius * deflection)
    local area = contactLength * width
    return contactLength, area
end

local function solveSinkage(normalForce, width, soil, contactArea)
    if not soil or normalForce <= 0 or contactArea <= 0 then
        return 0
    end
    local kcTerm = soil.kc / width
    local pressure = normalForce / contactArea
    local base = (pressure - kcTerm) / math.max(soil.kphi, 1)
    if base <= 0 then
        return 0
    end
    -- Soft soil is approximated with Bekker-Wong parameters; we assume uniform pressure across the contact patch.
    return base ^ (1 / math.max(soil.n, 1))
end

local function janosiShear(soil, normalForce, slipDisplacement)
    local sigma = normalForce
    local c = soil.cohesion
    local phi = soil.phi
    local shearK = soil.shearK
    local shear = (c + sigma * math.tan(phi)) * (1 - math.exp(-math.abs(slipDisplacement) / math.max(shearK, 1e-3)))
    return shear * (slipDisplacement >= 0 and 1 or -1)
end

function WheelContact.new(config)
    local self = setmetatable({}, WheelContact)
    self.trackTension = config.trackTension or 0.5
    self.returnRollerHeight = config.returnRollerHeight or 0.8
    self.raycastLength = config.raycastLength or 5
    self.raycastParams = config.raycastParams or createRaycastParams()
    self.soilModel = config.soilModel
    self.useSpringConstraint = config.useSpringConstraint
    return self
end

function WheelContact:getSoilPreset()
    if self.soilModel then
        return self.soilModel:getActivePreset()
    end
    return DEFAULT_SOIL
end

function WheelContact:computeContact(wheelState, soilPreset, dt)
    local wheel = wheelState.wheelPart
    local radius = wheelState.config.wheelRadius
    local width = wheelState.config.wheelWidth
    local raycastParams = self.raycastParams

    local origin = wheel.Position
    raycastParams.FilterDescendantsInstances = {wheelState.hull, wheel}
    local result = Workspace:Raycast(origin, Vector3.new(0, -(radius + self.raycastLength), 0), raycastParams)

    local contactCount = 0
    local normalForce = 0
    local deflection = 0
    local longitudinalForce = 0
    local lateralForce = 0
    local sinkage = 0
    local slipRatio = 0
    local slipAngle = 0
    local deflectionVelocity = wheelState.state.deflectionVelocity or 0
    local damperForce = 0

    local previousDeflection = wheelState.state.deflection or 0

    local activeSuspensionConfig
    if wheelState.springType == "Christie" then
        activeSuspensionConfig = wheelState.config.christie or wheelState.config
    else
        activeSuspensionConfig = wheelState.config.torsion or wheelState.config
    end

    if result then
        contactCount = 1
        local hitDistance = (origin - result.Position).Magnitude
        deflection = math.max(0, radius - hitDistance)

        local suspensionConfig = activeSuspensionConfig
        local springRate = suspensionConfig.k or 1e5
        local damping = suspensionConfig.c or 1e4
        local preload = suspensionConfig.preload or 0

        deflectionVelocity = (deflection - previousDeflection) / math.max(dt, 1e-3)

        local springForce = springRate * (deflection - preload)
        damperForce = damping * deflectionVelocity
        normalForce = math.max(0, springForce + damperForce)

        local contactLength, contactArea = computeContactPatch(radius, deflection, width)

        local soil = soilPreset or self:getSoilPreset()
        sinkage = solveSinkage(normalForce, width, soil, math.max(contactArea, 1))

        local wheelVelocity = wheel.AssemblyLinearVelocity
        local forwardDir = wheel.CFrame.ZVector
        local lateralDir = wheel.CFrame.XVector

        local forwardSpeed = wheelVelocity:Dot(forwardDir)
        local lateralSpeed = wheelVelocity:Dot(lateralDir)
        local angVel = wheel.AssemblyAngularVelocity:Dot(lateralDir)

        slipRatio = (angVel * radius - forwardSpeed) / math.max(math.abs(forwardSpeed) + math.abs(angVel * radius), 0.1)
        slipAngle = math.atan2(lateralSpeed, math.max(math.abs(forwardSpeed), 0.1))

        local mu = soil.mu or 0.8
        local frictionLimit = normalForce * mu

        local combinedSlip = blendSlip(slipRatio, slipAngle)
        local frictionScale = math.clamp(combinedSlip, 0, 1)

        longitudinalForce = -math.clamp(slipRatio, -1, 1) * frictionLimit * frictionScale
        lateralForce = -math.clamp(slipAngle, -math.rad(30), math.rad(30)) / math.rad(30) * frictionLimit * frictionScale

        if soil.softSoil then
            local slipDisplacement = slipRatio * contactLength
            local shearForce = janosiShear(soil, normalForce, slipDisplacement)
            longitudinalForce += shearForce
            normalForce = normalForce * (1 - soil.rollingResistance)
        end

        normalForce *= 1 + self.trackTension * 0.1
    else
        local droopLimit = (activeSuspensionConfig and activeSuspensionConfig.droopLimit) or 0
        deflection = -droopLimit
        deflectionVelocity = (deflection - previousDeflection) / math.max(dt, 1e-3)
        if self.trackTension and self.trackTension > 0.6 then
            -- High tension represents a taut top run contacting return rollers.
            contactCount = 1
            local springRate = activeSuspensionConfig and activeSuspensionConfig.k or 1e5
            normalForce = (self.trackTension - 0.6) * springRate * 0.05
        end
    end

    return {
        normalForce = normalForce,
        longitudinalForce = longitudinalForce,
        lateralForce = lateralForce,
        contactCount = contactCount,
        sinkage = sinkage,
        slipRatio = slipRatio,
        slipAngle = slipAngle,
        deflection = deflection,
        deflectionVelocity = deflectionVelocity,
        damperForce = damperForce,
    }
end

return WheelContact
