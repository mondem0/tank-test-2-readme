local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local UI = {}
UI.__index = UI

local CONTROL_BIND = "TankSandboxControls"

local function createLabel(parent, text, position)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromOffset(220, 24)
    label.Position = position
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0.5
    label.Font = Enum.Font.Gotham
    label.TextSize = 16
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = text
    label.Parent = parent
    return label
end

local function createTextBox(parent, defaultText, position, callback)
    local box = Instance.new("TextBox")
    box.Size = UDim2.fromOffset(120, 24)
    box.Position = position
    box.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    box.BorderSizePixel = 0
    box.TextColor3 = Color3.new(1, 1, 1)
    box.Font = Enum.Font.Gotham
    box.TextSize = 16
    box.ClearTextOnFocus = false
    box.Text = defaultText
    box.Parent = parent

    box.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            callback(box.Text)
        end
    end)

    return box
end

function UI.new(remotes, initialState)
    local self = setmetatable({}, UI)
    self.remotes = remotes
    self.state = initialState or {}
    self.gui = nil
    self.telemetryLabels = {}
    self:create()
    return self
end

function UI:create()
    local player = Players.LocalPlayer
    local gui = Instance.new("ScreenGui")
    gui.Name = "TankSandboxUI"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.Parent = player:WaitForChild("PlayerGui")
    self.gui = gui

    local panel = Instance.new("Frame")
    panel.Name = "ControlPanel"
    panel.Size = UDim2.fromOffset(320, 380)
    panel.Position = UDim2.fromOffset(20, 60)
    panel.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    panel.BackgroundTransparency = 0.2
    panel.BorderSizePixel = 0
    panel.Parent = gui

    local title = createLabel(panel, "Tank Sandbox", UDim2.fromOffset(10, 10))
    title.TextSize = 20

    local suspensionSelector = Instance.new("TextButton")
    suspensionSelector.Name = "SuspensionSelector"
    suspensionSelector.Text = "Suspension: " .. (self.state.suspensionType or "Torsion")
    suspensionSelector.Position = UDim2.fromOffset(10, 40)
    suspensionSelector.Size = UDim2.fromOffset(280, 28)
    suspensionSelector.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    suspensionSelector.TextColor3 = Color3.new(1, 1, 1)
    suspensionSelector.Font = Enum.Font.Gotham
    suspensionSelector.TextSize = 16
    suspensionSelector.Parent = panel

    suspensionSelector.MouseButton1Click:Connect(function()
        local order = {"Torsion", "Christie", "Rigid"}
        local currentIndex = table.find(order, self.state.suspensionType) or 1
        currentIndex += 1
        if currentIndex > #order then
            currentIndex = 1
        end
        self.state.suspensionType = order[currentIndex]
        suspensionSelector.Text = "Suspension: " .. self.state.suspensionType
        self:sendConfig()
    end)

    local soilButton = Instance.new("TextButton")
    soilButton.Name = "SoilButton"
    soilButton.Text = "Soil: " .. (self.state.soilPresetName or "Hard Road")
    soilButton.Position = UDim2.fromOffset(10, 80)
    soilButton.Size = UDim2.fromOffset(280, 28)
    soilButton.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    soilButton.TextColor3 = Color3.new(1, 1, 1)
    soilButton.Font = Enum.Font.Gotham
    soilButton.TextSize = 16
    soilButton.Parent = panel

    soilButton.MouseButton1Click:Connect(function()
        self.remotes.requestNextSoil:FireServer()
    end)

    local presetButton = Instance.new("TextButton")
    presetButton.Name = "PresetButton"
    presetButton.Text = "Preset: " .. (self.state.presetName or "Custom")
    presetButton.Position = UDim2.fromOffset(10, 120)
    presetButton.Size = UDim2.fromOffset(280, 28)
    presetButton.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    presetButton.TextColor3 = Color3.new(1, 1, 1)
    presetButton.Font = Enum.Font.Gotham
    presetButton.TextSize = 16
    presetButton.Parent = panel

    presetButton.MouseButton1Click:Connect(function()
        if self.remotes.requestPreset then
            self.remotes.requestPreset:FireServer("cycle")
        end
    end)

    local y = 160
    local fields = {
        {key = "k", label = "Spring rate k (Nm/rad)", default = tostring(self.state.k or 160000)},
        {key = "c", label = "Damping c (Nm*s/rad)", default = tostring(self.state.c or 1200)},
        {key = "preload", label = "Preload (rad)", default = tostring(self.state.preload or 0)},
        {key = "armLength", label = "Arm length (studs)", default = tostring(self.state.armLength or 2)},
        {key = "wheelbase", label = "Wheelbase (studs)", default = tostring(self.state.wheelbase or 12)},
        {key = "stationCount", label = "Stations/side", default = tostring(self.state.stationCount or 6)},
        {key = "trackWidth", label = "Track width (studs)", default = tostring(self.state.trackWidth or 6)},
        {key = "idlerOffset", label = "Idler offset", default = tostring(self.state.idlerOffset or 2)},
        {key = "trackTension", label = "Track tension", default = tostring(self.state.trackTension or 0.5)},
        {key = "cgHeight", label = "CG height", default = tostring(self.state.cgHeight or 1)},
        {key = "mass", label = "Hull mass (kg)", default = tostring(self.state.mass or 26000)},
    }

    for _, field in ipairs(fields) do
        createLabel(panel, field.label, UDim2.fromOffset(10, y))
        createTextBox(panel, field.default, UDim2.fromOffset(190, y), function(text)
            local value = tonumber(text)
            if value then
                self.state[field.key] = value
                self:sendConfig()
            end
        end)
        y += 30
    end

    local telemetryFrame = Instance.new("Frame")
    telemetryFrame.Name = "Telemetry"
    telemetryFrame.Size = UDim2.fromOffset(320, 220)
    telemetryFrame.Position = UDim2.fromOffset(0, 380)
    telemetryFrame.BackgroundTransparency = 0.6
    telemetryFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    telemetryFrame.BorderSizePixel = 0
    telemetryFrame.Parent = panel

    createLabel(telemetryFrame, "Telemetry", UDim2.fromOffset(10, 0))
    self.telemetryFrame = telemetryFrame

    self:bindControls()
end

function UI:bindControls()
    local function controlAction(actionName, inputState, inputObject)
        if inputState == Enum.UserInputState.Begin or inputState == Enum.UserInputState.End then
            local value = 0
            if inputState == Enum.UserInputState.Begin then
                value = 1
            end

            if inputObject.KeyCode == Enum.KeyCode.W then
                self.state.throttle = value
            elseif inputObject.KeyCode == Enum.KeyCode.S then
                self.state.throttle = -value
            elseif inputObject.KeyCode == Enum.KeyCode.A then
                self.state.steer = -value
            elseif inputObject.KeyCode == Enum.KeyCode.D then
                self.state.steer = value
            elseif inputObject.KeyCode == Enum.KeyCode.Space then
                self.state.brake = value
            end
            self:sendControl()
        end
        return Enum.ContextActionResult.Pass
    end

    ContextActionService:BindAction(CONTROL_BIND, controlAction, true, Enum.KeyCode.W, Enum.KeyCode.S, Enum.KeyCode.A, Enum.KeyCode.D, Enum.KeyCode.Space)
end

function UI:sendConfig()
    if not self.remotes.updateConfig then
        return
    end
    self.remotes.updateConfig:FireServer({
        suspensionType = self.state.suspensionType,
        k = self.state.k,
        c = self.state.c,
        preload = self.state.preload,
        armLength = self.state.armLength,
        wheelbase = self.state.wheelbase,
        stationCount = self.state.stationCount,
        trackWidth = self.state.trackWidth,
        idlerOffset = self.state.idlerOffset,
        trackTension = self.state.trackTension,
        cgHeight = self.state.cgHeight,
        mass = self.state.mass,
    })
end

function UI:sendControl()
    if not self.remotes.control then
        return
    end
    self.remotes.control:FireServer({
        throttle = self.state.throttle or 0,
        steer = self.state.steer or 0,
        brake = self.state.brake or 0,
    })
end

function UI:updateSoilDisplay(preset)
    if self.gui then
        local button = self.gui.ControlPanel and self.gui.ControlPanel:FindFirstChild("SoilButton")
        if button then
            button.Text = "Soil: " .. (preset or "Hard Road")
        end
    end
end

function UI:updatePresetDisplay(presetName)
    self.state.presetName = presetName
    if self.gui then
        local button = self.gui.ControlPanel and self.gui.ControlPanel:FindFirstChild("PresetButton")
        if button then
            button.Text = "Preset: " .. (presetName or "Custom")
        end
    end
end

function UI:onTelemetry(data)
    if not self.telemetryFrame then
        return
    end

    local order = 0
    for _, wheel in ipairs(data.wheels or {}) do
        order += 1
        local key = wheel.side .. wheel.index
        local label = self.telemetryLabels[key]
        if not label then
            label = createLabel(self.telemetryFrame, "", UDim2.fromOffset(10, 20 + (order - 1) * 22))
            self.telemetryLabels[key] = label
        end
        label.Position = UDim2.fromOffset(10, 20 + (order - 1) * 22)
        label.Text = string.format(
            "%s%d | Def %.3f | dDef %.3f | Damp %.0f | N %d | Slip %.2f | Sink %.2f",
            wheel.side:sub(1, 1),
            wheel.index,
            wheel.deflection,
            wheel.deflectionVelocity or 0,
            wheel.damperForce or 0,
            wheel.contactCount or 0,
            wheel.slipRatio,
            wheel.sinkage
        )
    end
end

return UI
