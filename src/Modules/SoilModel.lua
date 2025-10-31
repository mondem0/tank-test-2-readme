local SoilModel = {}
SoilModel.__index = SoilModel

local PRESETS = {
    ["hard_road"] = {
        displayName = "Hard Road",
        kc = 2.0e5,
        kphi = 1.5e5,
        n = 0.9,
        cohesion = 1200,
        phi = math.rad(30),
        shearK = 0.04,
        rollingResistance = 0.01,
        mu = 0.95,
        softSoil = false,
    },
    ["firm_dirt"] = {
        displayName = "Firm Dirt",
        kc = 1.2e5,
        kphi = 1.1e5,
        n = 1.1,
        cohesion = 800,
        phi = math.rad(26),
        shearK = 0.06,
        rollingResistance = 0.025,
        mu = 0.85,
        softSoil = true,
    },
    ["soft_sand"] = {
        displayName = "Soft Sand",
        kc = 6.5e4,
        kphi = 8.0e4,
        n = 1.3,
        cohesion = 300,
        phi = math.rad(18),
        shearK = 0.09,
        rollingResistance = 0.05,
        mu = 0.6,
        softSoil = true,
    },
}

function SoilModel.new(initialPreset)
    local self = setmetatable({}, SoilModel)
    self.presets = PRESETS
    self.activeKey = initialPreset or "hard_road"
    return self
end

function SoilModel:getPreset(key)
    return self.presets[key]
end

function SoilModel:setPreset(key)
    if self.presets[key] then
        self.activeKey = key
    end
end

function SoilModel:getActivePreset()
    return self.presets[self.activeKey]
end

function SoilModel:getPresetOptions()
    local options = {}
    for key, preset in pairs(self.presets) do
        table.insert(options, {
            key = key,
            displayName = preset.displayName,
        })
    end
    table.sort(options, function(a, b)
        return a.displayName < b.displayName
    end)
    return options
end

return SoilModel
