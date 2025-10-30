local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local modulesFolder = ReplicatedStorage:WaitForChild("TankModules")
local Suspension = require(modulesFolder:WaitForChild("Suspension"))
local WheelContact = require(modulesFolder:WaitForChild("WheelContact"))
local SoilModel = require(modulesFolder:WaitForChild("SoilModel"))
local Powertrain = require(modulesFolder:WaitForChild("Powertrain"))

local soilModel = SoilModel.new("hard_road")

local powertrain = Powertrain.new({
    neutralSteerGain = 8,
    maxForwardSpeed = 40,
})

local wheelContact = WheelContact.new({
    soilModel = soilModel,
    trackTension = 0.5,
    raycastLength = 6,
})

local baseConfig = {
    suspensionType = Suspension.SuspensionType.Torsion,
    stationCount = 6,
    wheelRadius = 1.1,
    wheelWidth = 0.9,
    trackWidth = 6,
    wheelbase = 12,
    armLength = 3,
    armRestAngle = -6,
    torsion = {
        k = 160000,
        c = 1200,
        preload = 0,
        bumpStopCompression = 0.5,
        droopLimit = 0.6,
        bumpStopStiffness = 320000,
    },
    christie = {
        k = 140000,
        c = 900,
        preload = 0.1,
        bumpStopCompression = 0.7,
        droopLimit = 0.9,
        bumpStopStiffness = 260000,
        dampersOnlyOnSelected = true,
    },
    sprocketRadius = 1.2,
    sprocketWidth = 1,
    sprocketOffset = 1,
    sprocketMaxTorque = 800000,
    idlerRadius = 1.2,
    idlerOffset = 2,
    idlerHeightOffset = 0.2,
    hullSize = Vector3.new(8, 2, 16),
    mass = 26000,
    cgOffset = Vector3.new(0, 0.6, 0),
    trackTension = 0.5,
    damperStations = {true, true, false, false, true, true},
    maxForwardSpeed = 40,
}

local presets = {
    ["WWII torsion-bar, 6 road wheels/side"] = function()
        baseConfig.suspensionType = Suspension.SuspensionType.Torsion
        baseConfig.stationCount = 6
        baseConfig.armLength = 3
        baseConfig.wheelRadius = 1.1
        baseConfig.wheelWidth = 0.9
        baseConfig.wheelbase = 12
        baseConfig.mass = 26000
        baseConfig.cgOffset = Vector3.new(0, 0.6, 0)
        baseConfig.torsion.k = 180000
        baseConfig.torsion.c = 1400
        baseConfig.damperStations = {true, true, false, false, true, true}
        baseConfig.trackTension = 0.55
    end,
    ["Christie cruiser, 5 large wheels/side"] = function()
        baseConfig.suspensionType = Suspension.SuspensionType.Christie
        baseConfig.stationCount = 5
        baseConfig.armLength = 3.6
        baseConfig.wheelRadius = 1.4
        baseConfig.wheelWidth = 1.1
        baseConfig.wheelbase = 14
        baseConfig.mass = 23000
        baseConfig.cgOffset = Vector3.new(0, 0.55, 0)
        baseConfig.christie.k = 150000
        baseConfig.christie.c = 800
        baseConfig.damperStations = {true, false, true, false, true}
        baseConfig.trackTension = 0.45
    end,
}

local presetKeys = {}
for name in pairs(presets) do
    table.insert(presetKeys, name)
end
table.sort(presetKeys)

local currentPresetIndex = 0
local currentPresetName = "Custom"

local currentSuspension

local sharedFolder = ReplicatedStorage:FindFirstChild("TankShared") or Instance.new("Folder")
sharedFolder.Name = "TankShared"
sharedFolder.Parent = ReplicatedStorage

local function setSharedValue(name, value)
    local obj = sharedFolder:FindFirstChild(name)
    if not obj then
        obj = Instance.new("StringValue")
        obj.Name = name
        obj.Parent = sharedFolder
    end
    obj.Value = tostring(value)
end

local presetChangedEvent

local function applyConfig(config)
    if currentSuspension then
        currentSuspension:destroy()
    end

    config.soilModel = soilModel
    config.wheelContact = wheelContact
    config.powertrain = powertrain

    wheelContact.trackTension = config.trackTension or wheelContact.trackTension

    currentSuspension = Suspension.new(config)

    setSharedValue("SuspensionType", config.suspensionType)
    setSharedValue("SoilPreset", soilModel:getActivePreset().displayName)
    local springSettings = config.torsion
    if config.suspensionType == Suspension.SuspensionType.Christie then
        springSettings = config.christie
    end
    setSharedValue("SpringK", springSettings.k)
    setSharedValue("DampingC", springSettings.c)
    setSharedValue("ArmLength", config.armLength)
    setSharedValue("StationCount", config.stationCount)
    setSharedValue("TrackWidth", config.trackWidth)
    setSharedValue("Wheelbase", config.wheelbase)
    setSharedValue("TrackTension", config.trackTension)
    setSharedValue("Mass", config.mass)
    setSharedValue("PresetName", currentPresetName)
    presetChangedEvent:FireAllClients(currentPresetName)
end

local updateConfigEvent = Instance.new("RemoteEvent")
updateConfigEvent.Name = "TankConfigUpdate"
updateConfigEvent.Parent = ReplicatedStorage

local controlEvent = Instance.new("RemoteEvent")
controlEvent.Name = "TankControl"
controlEvent.Parent = ReplicatedStorage

local soilCycleEvent = Instance.new("RemoteEvent")
soilCycleEvent.Name = "TankCycleSoil"
soilCycleEvent.Parent = ReplicatedStorage

local soilChangedEvent = Instance.new("RemoteEvent")
soilChangedEvent.Name = "TankSoilChanged"
soilChangedEvent.Parent = ReplicatedStorage

local telemetryEvent = Instance.new("RemoteEvent")
telemetryEvent.Name = "TankTelemetry"
telemetryEvent.Parent = ReplicatedStorage

local presetEvent = Instance.new("RemoteEvent")
presetEvent.Name = "TankApplyPreset"
presetEvent.Parent = ReplicatedStorage

presetChangedEvent = Instance.new("RemoteEvent")
presetChangedEvent.Name = "TankPresetChanged"
presetChangedEvent.Parent = ReplicatedStorage

local soilOptions = soilModel:getPresetOptions()
local soilIndex = 1

local function cycleSoil()
    soilIndex += 1
    if soilIndex > #soilOptions then
        soilIndex = 1
    end
    soilModel:setPreset(soilOptions[soilIndex].key)
    soilChangedEvent:FireAllClients(soilOptions[soilIndex].displayName)
    setSharedValue("SoilPreset", soilOptions[soilIndex].displayName)
end

soilCycleEvent.OnServerEvent:Connect(function(player)
    cycleSoil()
end)

controlEvent.OnServerEvent:Connect(function(player, input)
    powertrain:setInputs(input)
end)

updateConfigEvent.OnServerEvent:Connect(function(player, payload)
    currentPresetName = "Custom"
    if payload.k then
        baseConfig.torsion.k = payload.k
        baseConfig.christie.k = payload.k
    end
    if payload.c then
        baseConfig.torsion.c = payload.c
        baseConfig.christie.c = payload.c
    end
    if payload.preload then
        baseConfig.torsion.preload = payload.preload
        baseConfig.christie.preload = payload.preload
    end
    if payload.armLength then
        baseConfig.armLength = payload.armLength
    end
    if payload.wheelbase then
        baseConfig.wheelbase = payload.wheelbase
    end
    if payload.stationCount then
        baseConfig.stationCount = math.clamp(math.floor(payload.stationCount + 0.5), 2, 8)
        local dampers = {}
        for i = 1, baseConfig.stationCount do
            dampers[i] = (i == 1) or (i == baseConfig.stationCount)
        end
        baseConfig.damperStations = dampers
    end
    if payload.trackWidth then
        baseConfig.trackWidth = payload.trackWidth
    end
    if payload.idlerOffset then
        baseConfig.idlerOffset = payload.idlerOffset
    end
    if payload.trackTension then
        baseConfig.trackTension = payload.trackTension
    end
    if payload.cgHeight then
        baseConfig.cgOffset = Vector3.new(0, payload.cgHeight, 0)
    end
    if payload.mass then
        baseConfig.mass = payload.mass
    end
    if payload.suspensionType then
        baseConfig.suspensionType = payload.suspensionType
    end
    applyConfig(baseConfig)
end)

presetEvent.OnServerEvent:Connect(function(player, payload)
    if payload == "cycle" then
        currentPresetIndex += 1
        if currentPresetIndex > #presetKeys then
            currentPresetIndex = 1
        end
    elseif type(payload) == "string" and presets[payload] then
        currentPresetIndex = table.find(presetKeys, payload) or currentPresetIndex
    end

    local presetName = presetKeys[currentPresetIndex]
    local presetFunction = presetName and presets[presetName]
    if presetFunction then
        presetFunction()
        currentPresetName = presetName
        applyConfig(baseConfig)
    end
end)

local telemetryAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
    telemetryAccumulator += dt
    if telemetryAccumulator >= 0.1 and currentSuspension then
        telemetryAccumulator = 0
        local wheelData = {}
        for _, wheelState in ipairs(currentSuspension:getWheelStates()) do
            table.insert(wheelData, {
                index = wheelState.index,
                side = wheelState.side,
                deflection = wheelState.state.deflection,
                deflectionVelocity = wheelState.state.deflectionVelocity,
                damperForce = wheelState.state.damperForce,
                contactCount = wheelState.state.lastContactCount,
                slipRatio = wheelState.state.slipRatio,
                sinkage = wheelState.state.sinkage,
            })
        end
        telemetryEvent:FireAllClients({
            wheels = wheelData,
        })
    end
end)

applyConfig(baseConfig)

Players.PlayerAdded:Connect(function(player)
    soilChangedEvent:FireClient(player, soilModel:getActivePreset().displayName)
    presetChangedEvent:FireClient(player, currentPresetName)
end)

return {
    presets = presets,
}
