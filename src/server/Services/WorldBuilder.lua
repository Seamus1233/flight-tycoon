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
	local width = cols * Game.PlotSpacing + 400
	local depth = 2 * (Game.PlotSize.Z + 40) + 400
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

-- Arched hangar: walls with a window band, entrance, main doors, arched roof with skylights, lamps.
local function buildHangar(plot: Model, at)
	local H = Layout.Hangar
	local wallColor = Color3.fromRGB(176, 184, 194)
	local trimColor = Color3.fromRGB(58, 64, 76)
	local width = H.MaxX - H.MinX
	local depth = H.BackZ - H.FrontZ
	local midZ = (H.FrontZ + H.BackZ) / 2
	local hangar = Instance.new("Model")
	hangar.Name = "Hangar"
	hangar.Parent = plot

	local function block(name, size, pos, color, material, extra)
		local props = { Name = name, Parent = hangar, Size = size, CFrame = at(pos), Color = color,
			Material = material or Enum.Material.SmoothPlastic }
		for k, v in pairs(extra or {}) do
			props[k] = v
		end
		return part(props)
	end

	-- epoxy floor with a yellow safety border
	block("HangarFloor", Vector3.new(width, 0.2, depth), Vector3.new(0, 0.1, midZ), Color3.fromRGB(96, 102, 110))
	block("SafetyLine", Vector3.new(width - 8, 0.05, 0.8), Vector3.new(0, 0.22, H.FrontZ + 47), Color3.fromRGB(240, 200, 40),
		nil, { CanCollide = false })

	-- side walls: solid lower wall, window band, upper wall
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (H.MaxX - 1)
		block("SideWall", Vector3.new(2, 30, depth), Vector3.new(x, 15, midZ), wallColor, Enum.Material.CorrugatedSteel)
		block("Windows", Vector3.new(1.6, 8, depth), Vector3.new(x, 34, midZ), Color3.fromRGB(120, 170, 210),
			Enum.Material.Glass, { Transparency = 0.35 })
		block("SideWall", Vector3.new(2, H.Eave - 38, depth), Vector3.new(x, 38 + (H.Eave - 38) / 2, midZ), wallColor,
			Enum.Material.CorrugatedSteel)
	end

	-- front wall with the personnel entrance
	local fz = H.FrontZ + 1
	local ew, eh = H.EntranceWidth, H.EntranceHeight
	local segW = (width - ew) / 2
	for _, side in ipairs({ -1, 1 }) do
		block("FrontWall", Vector3.new(segW, H.Eave, 2), Vector3.new(side * (ew / 2 + segW / 2), H.Eave / 2, fz), wallColor,
			Enum.Material.CorrugatedSteel)
	end
	block("FrontWall", Vector3.new(ew, H.Eave - eh, 2), Vector3.new(0, eh + (H.Eave - eh) / 2, fz), wallColor,
		Enum.Material.CorrugatedSteel)
	block("Awning", Vector3.new(ew + 8, 1, 8), Vector3.new(0, eh + 1, fz - 4), trimColor)

	-- back wall with the main aircraft doors, door panels parked half open
	local bz = H.BackZ - 1
	local dw, dh = H.DoorWidth, H.DoorHeight
	local sideW = (width - dw) / 2
	for _, side in ipairs({ -1, 1 }) do
		block("BackWall", Vector3.new(sideW, H.Eave, 2), Vector3.new(side * (dw / 2 + sideW / 2), H.Eave / 2, bz), wallColor,
			Enum.Material.CorrugatedSteel)
		for k = 0, 1 do
			block("DoorPanel", Vector3.new(26, dh, 1.2),
				Vector3.new(side * (dw / 2 - 13 + k * 10), dh / 2, bz + 1.8 + k * 1.4), Color3.fromRGB(150, 158, 170),
				Enum.Material.CorrugatedSteel)
		end
	end
	block("DoorHeader", Vector3.new(dw, H.Eave - dh, 2), Vector3.new(0, dh + (H.Eave - dh) / 2, bz), trimColor,
		Enum.Material.Metal)

	-- arched roof: planks on a circular arc from the eaves up to the peak, with skylights
	local half = width / 2
	local rise = H.Peak - H.Eave
	local R = (half * half + rise * rise) / (2 * rise)
	local cy = H.Peak - R
	local thetaMax = math.asin(half / R)
	local N = 14
	local function arcY(x)
		return cy + math.sqrt(R * R - x * x)
	end
	for i = 0, N - 1 do
		local a0 = -thetaMax + 2 * thetaMax * i / N
		local a1 = -thetaMax + 2 * thetaMax * (i + 1) / N
		local mid = (a0 + a1) / 2
		local chord = 2 * R * math.sin((a1 - a0) / 2) + 0.4
		local skylight = (i == 4 or i == 9)
		local p = part({ Name = skylight and "Skylight" or "Roof", Parent = hangar,
			Size = Vector3.new(chord, 1.5, depth + 4),
			CFrame = at(Vector3.new(R * math.sin(mid), cy + R * math.cos(mid) + 0.75, midZ)) * CFrame.Angles(0, 0, -mid),
			Color = skylight and Color3.fromRGB(150, 200, 235) or (i % 2 == 0 and Color3.fromRGB(122, 130, 142) or Color3.fromRGB(112, 120, 132)),
			Material = skylight and Enum.Material.Glass or Enum.Material.CorrugatedSteel,
			Transparency = skylight and 0.45 or 0 })
		p.CastShadow = not skylight
	end
	-- gable ends: vertical strips filling the arch above the eaves at both ends
	for i = 0, N - 1 do
		local x0 = -half + width * i / N
		local x1 = -half + width * (i + 1) / N
		local top = math.min(arcY(x0), arcY(x1))
		local h = top - H.Eave
		if h > 0.2 then
			for _, z in ipairs({ fz, bz }) do
				block("Gable", Vector3.new(x1 - x0 + 0.05, h, 2), Vector3.new((x0 + x1) / 2, H.Eave + h / 2, z), wallColor,
					Enum.Material.CorrugatedSteel)
			end
		end
	end

	-- hanging lamps
	for _, x in ipairs({ -70, 0, 70 }) do
		for _, z in ipairs({ -235, -175, -115, -55 }) do
			local lamp = block("Lamp", Vector3.new(6, 0.6, 6), Vector3.new(x, 40, z), Color3.fromRGB(255, 248, 230),
				Enum.Material.Neon, { CanCollide = false, CastShadow = false })
			local light = Instance.new("PointLight")
			light.Range = 60
			light.Brightness = 1.6
			light.Color = Color3.fromRGB(255, 244, 220)
			light.Shadows = false
			light.Parent = lamp
			block("LampCable", Vector3.new(0.2, arcY(x) - 40.3, 0.2), Vector3.new(x, 40.3 + (arcY(x) - 40.3) / 2, z),
				Color3.fromRGB(30, 30, 30), nil, { CanCollide = false })
		end
	end

	-- path from the boulevard to the entrance
	block("Walkway", Vector3.new(ew + 4, 0.2, 12), Vector3.new(0, 0.1, H.FrontZ - 6), Color3.fromRGB(150, 152, 156),
		Enum.Material.Concrete)

	-- owner sign above the entrance (front face points at the boulevard)
	local sign = part({ Name = "OwnerSign", Parent = plot, Size = Vector3.new(80, 10, 1),
		CFrame = at(Vector3.new(0, 30, H.FrontZ - 0.6)), Color = trimColor })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.PixelsPerStud = 12
	local t = Instance.new("TextLabel")
	t.Name = "Owner"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = Color3.fromRGB(255, 210, 80)
	t.Text = "VACANT HANGAR"
	t.Parent = sg
	sg.Parent = sign
end

-- Airfield behind the hangar: apron, taxiways, runway with markings and lights, windsock.
local function buildAirfield(plot: Model, at)
	local field = Instance.new("Model")
	field.Name = "Airfield"
	field.Parent = plot
	local asphalt = Color3.fromRGB(46, 47, 52)
	local white = Color3.fromRGB(240, 240, 240)
	local yellow = Color3.fromRGB(240, 200, 40)
	local function flat(name, size, pos, color, material, y)
		return part({ Name = name, Parent = field, Size = Vector3.new(size.X, 0.2, size.Z), CFrame = at(pos + Vector3.new(0, y or 0.1, 0)),
			Color = color, Material = material or Enum.Material.SmoothPlastic })
	end
	local function marking(size, pos, color)
		return part({ Name = "Marking", Parent = field, Size = Vector3.new(size.X, 0.05, size.Z), CFrame = at(pos + Vector3.new(0, 0.33, 0)),
			Color = color, CanCollide = false, CastShadow = false })
	end
	local function light(pos, color)
		return part({ Name = "EdgeLight", Parent = field, Size = Vector3.new(0.8, 0.8, 0.8), CFrame = at(pos + Vector3.new(0, 0.6, 0)),
			Color = color, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
	end

	-- apron with parking stand lines
	local ap = Layout.Apron
	flat("Apron", ap.Size, ap.Center, Color3.fromRGB(168, 170, 172), Enum.Material.Concrete)
	for x = -150, 150, 50 do
		marking(Vector3.new(0.8, 0, 50), ap.Center + Vector3.new(x, -0.12, 0), yellow)
	end

	-- taxiways with centrelines and blue edge lights
	for _, tw in ipairs(Layout.Taxiways) do
		flat("Taxiway", tw.Size, tw.Center, asphalt, Enum.Material.Asphalt, 0.12)
		marking(Vector3.new(0.6, 0, tw.Size.Z), tw.Center + Vector3.new(0, -0.1, 0), yellow)
		for dz = -tw.Size.Z / 2 + 5, tw.Size.Z / 2 - 5, 15 do
			for _, sx in ipairs({ -1, 1 }) do
				light(tw.Center + Vector3.new(sx * (tw.Size.X / 2 + 1), 0, dz), Color3.fromRGB(60, 120, 255))
			end
		end
	end

	-- runway
	local rc, rs = Layout.RunwayCenter, Layout.RunwaySize
	part({ Name = "Runway", Parent = field, Size = rs, CFrame = at(rc + Vector3.new(0, 0.15, 0)), Color = asphalt,
		Material = Enum.Material.Asphalt })
	local halfL, halfW = rs.X / 2, rs.Z / 2
	-- centreline dashes
	for x = -halfL + 45, halfL - 45, 22 do
		marking(Vector3.new(11, 0, 1), rc + Vector3.new(x, 0, 0), white)
	end
	-- side stripes
	for _, sz in ipairs({ -1, 1 }) do
		marking(Vector3.new(rs.X - 6, 0, 0.8), rc + Vector3.new(0, 0, sz * (halfW - 2)), white)
	end
	-- threshold "piano keys" and runway numbers at both ends
	for _, sx in ipairs({ -1, 1 }) do
		for k = -3, 3 do
			if k ~= 0 then
				marking(Vector3.new(16, 0, 3), rc + Vector3.new(sx * (halfL - 12), 0, k * 5.5), white)
			end
		end
		local num = part({ Name = "RunwayNumber", Parent = field, Size = Vector3.new(14, 0.05, 20),
			CFrame = at(rc + Vector3.new(sx * (halfL - 34), 0.33, 0)) * CFrame.Angles(0, sx > 0 and math.pi / 2 or -math.pi / 2, 0),
			Transparency = 1, CanCollide = false })
		local g = Instance.new("SurfaceGui")
		g.Face = Enum.NormalId.Top
		g.PixelsPerStud = 10
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.fromScale(1, 1)
		tl.BackgroundTransparency = 1
		tl.TextScaled = true
		tl.Font = Enum.Font.GothamBlack
		tl.TextColor3 = white
		tl.Text = sx < 0 and "09" or "27"
		tl.Parent = g
		g.Parent = num
	end
	-- edge lights (white), threshold lights (green / red)
	for x = -halfL + 5, halfL - 5, 30 do
		for _, sz in ipairs({ -1, 1 }) do
			light(rc + Vector3.new(x, 0, sz * (halfW + 1.5)), Color3.fromRGB(255, 250, 225))
		end
	end
	for k = -4, 4 do
		light(rc + Vector3.new(-halfL - 1.5, 0, k * 5.5), Color3.fromRGB(60, 255, 90))
		light(rc + Vector3.new(halfL + 1.5, 0, k * 5.5), Color3.fromRGB(255, 50, 50))
	end

	-- windsock near the east threshold
	local base = rc + Vector3.new(halfL - 20, 0, halfW + 22)
	part({ Name = "WindsockPole", Parent = field, Size = Vector3.new(0.6, 14, 0.6), CFrame = at(base + Vector3.new(0, 7, 0)),
		Color = Color3.fromRGB(200, 200, 200), Material = Enum.Material.Metal })
	for k = 0, 3 do
		local seg = part({ Name = "Windsock", Parent = field, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.2, 2.4 - k * 0.4, 2.4 - k * 0.4),
			CFrame = at(base + Vector3.new(1.4 + k * 2.2, 13.2 - k * 0.35, 0)),
			Color = k % 2 == 0 and Color3.fromRGB(255, 120, 20) or Color3.new(1, 1, 1), CanCollide = false })
		seg.CastShadow = false
	end
end

function WorldBuilder.Plot(index: number)
	local cf = WorldBuilder.PlotCFrame(index)
	local plot = Instance.new("Model")
	plot.Name = "Plot" .. index
	plot:SetAttribute("Index", index)
	local at = function(v: Vector3) return cf * CFrame.new(v) end

	-- grass base; hangar floor and airfield pavement sit on top of it
	local base = part({ Name = "Base", Parent = plot, Size = Game.PlotSize, CFrame = at(Vector3.new(0, -0.5, 0)),
		Color = Color3.fromRGB(88, 126, 70), Material = Enum.Material.Grass })
	plot.PrimaryPart = base
	buildHangar(plot, at)
	buildAirfield(plot, at)

	-- spawn pad (owner respawns here, just inside the entrance)
	part({ Name = "SpawnPad", Parent = plot, Size = Vector3.new(10, 0.4, 10), CFrame = at(Layout.Spawn + Vector3.new(0, 0.3, 0)),
		Color = Color3.fromRGB(80, 170, 255), Material = Enum.Material.Neon, CanCollide = false })

	-- collector: vault terminal against the front wall
	local collector = part({ Name = "Collector", Parent = plot, Size = Vector3.new(12, 0.6, 12),
		CFrame = at(Layout.Collector + Vector3.new(0, 0.4, 0)), Color = Color3.fromRGB(60, 220, 110), Material = Enum.Material.Neon })
	part({ Name = "VaultBox", Parent = plot, Size = Vector3.new(10, 8, 3), CFrame = at(Layout.Collector + Vector3.new(0, 4, -10)),
		Color = Color3.fromRGB(50, 56, 66), Material = Enum.Material.DiamondPlate })
	label(collector, "VAULT", "$0", nil, 9)

	-- rebirth pad
	local rebirth = part({ Name = "RebirthPad", Parent = plot, Size = Vector3.new(12, 0.6, 12),
		CFrame = at(Layout.RebirthPad + Vector3.new(0, 0.4, 0)), Color = Color3.fromRGB(190, 80, 255), Material = Enum.Material.Neon })
	label(rebirth, "REBIRTH", "Buy the F-22 to unlock", Color3.fromRGB(230, 180, 255), 6)

	-- bay floor markings for every aircraft slot (shows how much there is to unlock)
	local floors = Instance.new("Folder")
	floors.Name = "BayFloors"
	floors.Parent = plot
	for id, bcf in pairs(Layout.Bay) do
		local a = Aircraft.ById[id]
		local eraColor = Aircraft.Eras[a.era].color
		part({ Name = id, Parent = floors, Size = Vector3.new(Layout.BayW - 2, 0.2, Layout.BayD - 2),
			CFrame = cf * bcf * CFrame.new(0, 0.25, 0),
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
		local hx, hz = Game.PlotSize.X / 2 - 0.5, Game.PlotSize.Z / 2 - 0.5
		local mat = { Color = Color3.fromRGB(120, 120, 125), Material = Enum.Material.Metal, Transparency = 0.3 }
		for i = -1, 1, 2 do
			-- leave a gap in the front fence for the walkway to the entrance
			if i == -1 then
				for _, sx in ipairs({ -1, 1 }) do
					part({ Parent = f, Size = Vector3.new(hx - 12, 6, 1), CFrame = cf * CFrame.new(sx * (12 + (hx - 12) / 2), 3, -hz),
						Color = mat.Color, Material = mat.Material, Transparency = mat.Transparency })
				end
			else
				part({ Parent = f, Size = Vector3.new(hx * 2, 6, 1), CFrame = cf * CFrame.new(0, 3, hz),
					Color = mat.Color, Material = mat.Material, Transparency = mat.Transparency })
			end
			part({ Parent = f, Size = Vector3.new(1, 6, hz * 2), CFrame = cf * CFrame.new(i * hx, 3, 0),
				Color = mat.Color, Material = mat.Material, Transparency = mat.Transparency })
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
	local pitch = math.rad(model:GetAttribute("GroundPitch") or 0)
	model:PivotTo(bcf * CFrame.Angles(pitch, 0, 0))
	local bbCf, bbSize = model:GetBoundingBox()
	local bottom = bbCf.Position.Y - bbSize.Y / 2
	local floorY = bcf.Position.Y + 0.35
	-- meshes with gear stand on their wheels; part-built models hover on a display stand height
	local lift = (floorY - bottom) + (model:GetAttribute("HasGear") and 0 or 1.5)
	model:PivotTo(model:GetPivot() + Vector3.new(0, lift, 0))
	model.Parent = plot.Built
	local root = model.PrimaryPart
	label(root, spec.name, spec.premium and "BLACK PROJECT" or Aircraft.Eras[spec.era].name,
		spec.premium and Color3.fromRGB(255, 210, 70) or Color3.fromRGB(180, 210, 255), extents.Y / 2 + 4)
	root:SetAttribute("Bay", spec.id)
	return model
end

return WorldBuilder
