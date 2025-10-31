local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("TankModules")
local UI = require(modulesFolder:WaitForChild("UI"))

local updateConfigEvent = ReplicatedStorage:WaitForChild("TankConfigUpdate")
local controlEvent = ReplicatedStorage:WaitForChild("TankControl")
local soilCycleEvent = ReplicatedStorage:WaitForChild("TankCycleSoil")
local soilChangedEvent = ReplicatedStorage:WaitForChild("TankSoilChanged")
local telemetryEvent = ReplicatedStorage:WaitForChild("TankTelemetry")
local presetEvent = ReplicatedStorage:WaitForChild("TankApplyPreset")
local presetChangedEvent = ReplicatedStorage:WaitForChild("TankPresetChanged")

local sharedFolder = ReplicatedStorage:WaitForChild("TankShared")

local initialState = {
    suspensionType = sharedFolder:FindFirstChild("SuspensionType") and sharedFolder.SuspensionType.Value,
    soilPresetName = sharedFolder:FindFirstChild("SoilPreset") and sharedFolder.SoilPreset.Value,
    k = tonumber(sharedFolder:FindFirstChild("SpringK") and sharedFolder.SpringK.Value) or 160000,
    c = tonumber(sharedFolder:FindFirstChild("DampingC") and sharedFolder.DampingC.Value) or 1200,
    armLength = tonumber(sharedFolder:FindFirstChild("ArmLength") and sharedFolder.ArmLength.Value) or 3,
    stationCount = tonumber(sharedFolder:FindFirstChild("StationCount") and sharedFolder.StationCount.Value) or 6,
    trackWidth = tonumber(sharedFolder:FindFirstChild("TrackWidth") and sharedFolder.TrackWidth.Value) or 6,
    wheelbase = tonumber(sharedFolder:FindFirstChild("Wheelbase") and sharedFolder.Wheelbase.Value) or 12,
    trackTension = tonumber(sharedFolder:FindFirstChild("TrackTension") and sharedFolder.TrackTension.Value) or 0.5,
    mass = tonumber(sharedFolder:FindFirstChild("Mass") and sharedFolder.Mass.Value) or 26000,
    presetName = sharedFolder:FindFirstChild("PresetName") and sharedFolder.PresetName.Value or "Custom",
}

local ui = UI.new({
    updateConfig = updateConfigEvent,
    control = controlEvent,
    requestNextSoil = soilCycleEvent,
    requestPreset = presetEvent,
}, initialState)

soilChangedEvent.OnClientEvent:Connect(function(name)
    ui:updateSoilDisplay(name)
end)

telemetryEvent.OnClientEvent:Connect(function(payload)
    ui:onTelemetry(payload)
end)

presetChangedEvent.OnClientEvent:Connect(function(presetName)
    ui:updatePresetDisplay(presetName)
end)
