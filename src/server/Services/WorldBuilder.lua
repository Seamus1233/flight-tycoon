--[[
	WorldBuilder - generates the map, plots and every tycoon structure in code,
	so the place needs no hand-built geometry (works straight from Rojo).
]]
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Game = require(Shared.Config.Game)
local Items = require(Shared.Config.Items)
local Aircraft = require(Shared.Config.Aircraft)
local Layout = require(Shared.Layout)
local Format = require(Shared.Util.Format)

local WorldBuilder = {}

local function part(props)
	local p = Instance.new(props.Class or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		if k ~= "Class" and k ~= "Parent" then
			p[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

local function label(parent: BasePart, text: string, sub: string?, color: Color3?, height: number?)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = UDim2.fromOffset(220, sub and 64 or 40)
	bb.StudsOffset = Vector3.new(0, height or 4, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 140
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0, 36)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.3
	t.Text = text
	t.Parent = bb
	if sub then
		local s = t:Clone()
		s.Name = "Sub"
		s.Position = UDim2.fromOffset(0, 36)
		s.Size = UDim2.new(1, 0, 0, 26)
		s.Font = Enum.Font.GothamBold
		s.TextColor3 = color or Color3.fromRGB(120, 255, 140)
		s.Text = sub
		s.Parent = bb
	end
	bb.Parent = parent
	return bb
end
WorldBuilder.Label = label

function WorldBuilder.Environment()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.2
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 150)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.28
		atm.Haze = 1.2
		atm.Color = Color3.fromRGB(199, 214, 230)
		atm.Parent = Lighting
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect", Lighting)
	bloom.Intensity = 0.4
	bloom.Threshold = 1.6

	local map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace
	local cols = Game.MaxPlots // 2
	local width = cols * Game.PlotSpacing + 600
	local depth = 2 * Game.PlotSpacing + 900
	part({ Name = "Ground", Parent = map, Size = Vector3.new(width, 4, depth), Position = Vector3.new(0, -2.5, 0),
		Color = Color3.fromRGB(92, 128, 72), Material = Enum.Material.Grass })
	-- central lobby strip between the two rows of plots
	part({ Name = "Boulevard", Parent = map, Size = Vector3.new(width - 200, 1, 40), Position = Vector3.new(0, -0.4, 0),
		Color = Color3.fromRGB(70, 70, 76), Material = Enum.Material.Asphalt })
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.Position = Vector3.new(0, 0.1, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(255, 200, 60)
	spawn.Material = Enum.Material.Neon
	spawn.Parent = map

	-- invisible ceiling for flight isn't needed; a soft world boundary keeps planes nearby
	map:SetAttribute("FlightRadius", math.max(width, depth))
	return map
end

-- Plot world CFrame for plot index (1..MaxPlots). Plots face the boulevard (z = 0).
function WorldBuilder.PlotCFrame(index: number): CFrame
	local cols = Game.MaxPlots // 2
	local col = (index - 1) % cols
	local row = (index - 1) // cols
	local x = (col - (cols - 1) / 2) * Game.PlotSpacing
	local z = (Game.PlotSize.Z / 2 + 40)
	if row == 0 then
		-- front of plot (local -Z) faces the boulevard at world z = 0
		return CFrame.new(x, 0, z)
	end
	return CFrame.new(x, 0, -z) * CFrame.Angles(0, math.pi, 0)
end

function WorldBuilder.Plot(index: number)
	local cf = WorldBuilder.PlotCFrame(index)
	local plot = Instance.new("Model")
	plot.Name = "Plot" .. index
	plot:SetAttribute("Index", index)
	local at = function(v: Vector3) return cf * CFrame.new(v) end

	local base = part({ Name = "Base", Parent = plot, Size = Game.PlotSize, CFrame = at(Vector3.new(0, -0.5, 0)),
		Color = Color3.fromRGB(150, 152, 156), Material = Enum.Material.Concrete })
	plot.PrimaryPart = base
	part({ Name = "Runway", Parent = plot, Size = Layout.RunwaySize, CFrame = at(Layout.RunwayCenter + Vector3.new(0, 0.2, 0)),
		Color = Color3.fromRGB(45, 45, 50), Material = Enum.Material.Asphalt })
	for z = -150, 150, 20 do
		part({ Name = "Stripe", Parent = plot, Size = Vector3.new(1.2, 0.1, 9),
			CFrame = at(Layout.RunwayCenter + Vector3.new(0, 0.45, z)), Color = Color3.new(1, 1, 1), CanCollide = false })
	end
	-- owner sign at the entrance
	local sign = part({ Name = "OwnerSign", Parent = plot, Size = Vector3.new(30, 8, 1),
		CFrame = at(Vector3.new(-120, 9, -163)), Color = Color3.fromRGB(30, 34, 44) })
	part({ Name = "Post", Parent = plot, Size = Vector3.new(1, 9, 1), CFrame = at(Vector3.new(-134, 4.5, -163)), Color = Color3.fromRGB(30, 34, 44) })
	part({ Name = "Post", Parent = plot, Size = Vector3.new(1, 9, 1), CFrame = at(Vector3.new(-106, 4.5, -163)), Color = Color3.fromRGB(30, 34, 44) })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.PixelsPerStud = 20
	local t = Instance.new("TextLabel")
	t.Name = "Owner"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = Color3.fromRGB(255, 210, 80)
	t.Text = "VACANT AIRBASE"
	t.Parent = sg
	sg.Parent = sign

	-- spawn pad (owner respawns here)
	part({ Name = "SpawnPad", Parent = plot, Size = Vector3.new(10, 0.4, 10), CFrame = at(Layout.Spawn + Vector3.new(0, 0.2, 0)),
		Color = Color3.fromRGB(80, 170, 255), Material = Enum.Material.Neon, CanCollide = false })

	-- collector: vault terminal
	local collector = part({ Name = "Collector", Parent = plot, Size = Vector3.new(12, 0.6, 12),
		CFrame = at(Layout.Collector + Vector3.new(0, 0.3, 0)), Color = Color3.fromRGB(60, 220, 110), Material = Enum.Material.Neon })
	part({ Name = "VaultBox", Parent = plot, Size = Vector3.new(10, 8, 3), CFrame = at(Layout.Collector + Vector3.new(0, 4, 7.5)),
		Color = Color3.fromRGB(50, 56, 66), Material = Enum.Material.DiamondPlate })
	label(collector, "VAULT", "$0", nil, 9)

	-- rebirth pad
	local rebirth = part({ Name = "RebirthPad", Parent = plot, Size = Vector3.new(12, 0.6, 12),
		CFrame = at(Layout.RebirthPad + Vector3.new(0, 0.3, 0)), Color = Color3.fromRGB(190, 80, 255), Material = Enum.Material.Neon })
	label(rebirth, "REBIRTH", "Buy the F-22 to unlock", Color3.fromRGB(230, 180, 255), 6)

	-- bay floor markings for every aircraft slot (shows how much there is to unlock)
	local floors = Instance.new("Folder")
	floors.Name = "BayFloors"
	floors.Parent = plot
	for id, bcf in pairs(Layout.Bay) do
		local a = Aircraft.ById[id]
		local eraColor = Aircraft.Eras[a.era].color
		part({ Name = id, Parent = floors, Size = Vector3.new(Layout.BayW - 2, 0.2, Layout.BayD - 2),
			CFrame = cf * bcf * CFrame.new(0, 0.1, 0),
			Color = a.premium and Color3.fromRGB(40, 30, 10) or Color3.new(eraColor[1] * 0.7, eraColor[2] * 0.7, eraColor[3] * 0.7),
			Material = Enum.Material.DiamondPlate, CanCollide = false })
	end

	local built = Instance.new("Folder")
	built.Name = "Built"
	built.Parent = plot
	local pads = Instance.new("Folder")
	pads.Name = "Pads"
	pads.Parent = plot
	plot.Parent = workspace:WaitForChild("Plots")
	return plot
end

-- Buy pad for an item. Returns the pad part.
function WorldBuilder.Pad(plot: Model, itemId: string, title: string, cost: number?, premium: boolean?)
	local plotCf = plot.PrimaryPart.CFrame * CFrame.new(0, 0.5, 0)
	local pos = Layout.Pad[itemId]
	local p = part({ Name = itemId, Parent = plot.Pads, Size = Vector3.new(6, 0.6, 6),
		CFrame = plotCf * CFrame.new(pos + Vector3.new(0, 0.3, 0)),
		Color = premium and Color3.fromRGB(255, 190, 40) or Color3.fromRGB(70, 200, 90), Material = Enum.Material.Neon })
	p:SetAttribute("ItemId", itemId)
	p:SetAttribute("Cost", cost or 0)
	label(p, title, premium and "R$ GAME PASS" or Format.Money(cost or 0), premium and Color3.fromRGB(255, 215, 80) or nil, 4)
	return p
end

local FACILITY_STYLE = {
	fence = function(f, cf)
		for i = -1, 1, 2 do
			part({ Parent = f, Size = Vector3.new(298, 6, 1), CFrame = cf * CFrame.new(0, 3, i * 164.5), Color = Color3.fromRGB(120, 120, 125),
				Material = Enum.Material.Metal, Transparency = 0.3 })
			part({ Parent = f, Size = Vector3.new(1, 6, 330), CFrame = cf * CFrame.new(i * 149.5, 3, 0), Color = Color3.fromRGB(120, 120, 125),
				Material = Enum.Material.Metal, Transparency = 0.3 })
		end
	end,
	tower = function(f, cf)
		part({ Parent = f, Size = Vector3.new(8, 34, 8), CFrame = cf * CFrame.new(0, 17, 0), Color = Color3.fromRGB(230, 230, 225), Material = Enum.Material.Concrete })
		part({ Parent = f, Size = Vector3.new(14, 7, 14), CFrame = cf * CFrame.new(0, 37.5, 0), Color = Color3.fromRGB(60, 120, 170), Material = Enum.Material.Glass, Transparency = 0.25 })
		part({ Parent = f, Size = Vector3.new(15, 1, 15), CFrame = cf * CFrame.new(0, 41.5, 0), Color = Color3.fromRGB(40, 40, 45) })
	end,
	fuel = function(f, cf)
		for i = -1, 1, 2 do
			local c = part({ Parent = f, Shape = Enum.PartType.Cylinder, Size = Vector3.new(12, 9, 9),
				CFrame = cf * CFrame.new(i * 5, 6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(235, 235, 230), Material = Enum.Material.Metal })
			c.Name = "Tank"
		end
	end,
	radar = function(f, cf)
		part({ Parent = f, Size = Vector3.new(8, 10, 8), CFrame = cf * CFrame.new(0, 5, 0), Color = Color3.fromRGB(200, 200, 200), Material = Enum.Material.Concrete })
		part({ Parent = f, Shape = Enum.PartType.Ball, Size = Vector3.new(16, 16, 16), CFrame = cf * CFrame.new(0, 14, 0), Color = Color3.fromRGB(245, 245, 245) })
	end,
	satellite = function(f, cf)
		part({ Parent = f, Size = Vector3.new(2, 12, 2), CFrame = cf * CFrame.new(0, 6, 0), Color = Color3.fromRGB(180, 180, 185), Material = Enum.Material.Metal })
		part({ Parent = f, Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 16, 16),
			CFrame = cf * CFrame.new(0, 14, 0) * CFrame.Angles(0, 0, math.rad(60)), Color = Color3.fromRGB(240, 240, 240) })
	end,
	monument = function(f, cf)
		part({ Parent = f, Size = Vector3.new(14, 4, 14), CFrame = cf * CFrame.new(0, 2, 0), Color = Color3.fromRGB(60, 60, 64), Material = Enum.Material.Marble })
		part({ Parent = f, Size = Vector3.new(3, 30, 3), CFrame = cf * CFrame.new(0, 19, 0), Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Foil })
	end,
}

function WorldBuilder.Facility(plot: Model, item)
	local plotCf = plot.PrimaryPart.CFrame * CFrame.new(0, 0.5, 0)
	local f = Instance.new("Model")
	f.Name = item.id
	local cf = item.id == "fence" and plotCf or plotCf * Layout.Facility[item.id]
	local styler = FACILITY_STYLE[item.id]
	if styler then
		styler(f, cf)
	else
		-- generic hangar-style building, taller and darker in later eras
		local h = 10 + item.era * 2
		local era = Aircraft.Eras[item.era].color
		part({ Parent = f, Size = Vector3.new(20, h, 20), CFrame = cf * CFrame.new(0, h / 2, 0),
			Color = Color3.new(era[1], era[2], era[3]), Material = Enum.Material.Concrete })
		part({ Parent = f, Size = Vector3.new(21, 1.5, 21), CFrame = cf * CFrame.new(0, h + 0.75, 0), Color = Color3.fromRGB(45, 45, 50) })
		part({ Parent = f, Size = Vector3.new(10, h * 0.6, 0.5), CFrame = cf * CFrame.new(0, h * 0.3, -10.1),
			Color = Color3.fromRGB(70, 75, 85), Material = Enum.Material.CorrugatedSteel })
		if item.gate then
			part({ Parent = f, Size = Vector3.new(21, 1, 21), CFrame = cf * CFrame.new(0, h + 2, 0),
				Color = Color3.fromRGB(80, 170, 255), Material = Enum.Material.Neon, Transparency = 0.4 })
		end
	end
	if item.id ~= "fence" then
		local anchor = part({ Name = "LabelAnchor", Parent = f, Size = Vector3.new(1, 1, 1), CFrame = cf * CFrame.new(0, 18, 0),
			Transparency = 1, CanCollide = false })
		label(anchor, item.name, item.bonus > 0 and ("+" .. math.floor(item.bonus * 100) .. "% income") or nil, nil, 4)
	end
	f.Parent = plot.Built
	return f
end

-- Aircraft on display in its bay, with name sign
function WorldBuilder.DisplayAircraft(plot: Model, spec, model: Model)
	local plotCf = plot.PrimaryPart.CFrame * CFrame.new(0, 0.5, 0)
	local bcf = plotCf * Layout.Bay[spec.id]
	local extents = model:GetAttribute("Extents") or Vector3.new(10, 4, 10)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model:PivotTo(bcf * CFrame.new(0, extents.Y / 2 + 1.5, 0))
	model.Parent = plot.Built
	local root = model.PrimaryPart
	label(root, spec.name, spec.premium and "BLACK PROJECT" or Aircraft.Eras[spec.era].name,
		spec.premium and Color3.fromRGB(255, 210, 70) or Color3.fromRGB(180, 210, 255), extents.Y / 2 + 4)
	root:SetAttribute("Bay", spec.id)
	return model
end

return WorldBuilder
