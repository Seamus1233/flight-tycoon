--[[
	Plot layout, in plot-local coordinates (origin = plot centre, -Z = front,
	facing the boulevard). Each plot is a hangar with an airfield behind it.

	   z = -280  boulevard side
	   ┌──────────────── HANGAR (250 x 270, arched roof) ────────────────┐
	   │ entrance · spawn · vault · rebirth · Black Project showcase      │  z -270..-222
	   │ aircraft bays: 8 columns x 6 rows                                │  z -220..-16
	   └──────────────────── main doors (190 wide) ───────────────────────┘  z = 0
	   facilities line both sides of the hangar
	   apron                                                                 z 0..70
	   taxiways (x = ±170)                                                   z 70..150
	   runway (430 x 50), runs along X                                       z 150..200
	   facilities along the far edge                                         z ~245
	   z = +280
]]
local Items = require(script.Parent.Config.Items)
local Aircraft = require(script.Parent.Config.Aircraft)

local Layout = {}

-- hangar shell
Layout.Hangar = {
	MinX = -125, MaxX = 125,
	FrontZ = -270, BackZ = 0,
	Eave = 48, Peak = 70,
	DoorWidth = 190, DoorHeight = 40,
	EntranceWidth = 16, EntranceHeight = 16,
}

-- aircraft bays inside the hangar
Layout.BayCols = 8
Layout.BayW = 26
Layout.BayD = 34
Layout.BayOrigin = Vector3.new(-91, 0, -203) -- centre of the first bay

-- entrance hall
Layout.Spawn = Vector3.new(0, 0, -250)
Layout.Collector = Vector3.new(-45, 0, -248)
Layout.RebirthPad = Vector3.new(-88, 0, -248)

-- airfield
Layout.Apron = { Center = Vector3.new(0, 0, 35), Size = Vector3.new(400, 0, 70) }
Layout.Taxiways = {
	{ Center = Vector3.new(-170, 0, 110), Size = Vector3.new(24, 0, 80) },
	{ Center = Vector3.new(170, 0, 110), Size = Vector3.new(24, 0, 80) },
}
Layout.RunwayCenter = Vector3.new(0, 0, 175)
Layout.RunwaySize = Vector3.new(430, 0.3, 50)
-- take-off point at the west threshold, facing down the runway (+X)
Layout.RunwayStart = CFrame.new(-195, 0, 175) * CFrame.Angles(0, -math.pi / 2, 0)

local bay = {}       -- itemId -> CFrame of bay centre
local pad = {}       -- itemId -> Vector3 of buy pad
local facility = {}  -- itemId -> CFrame

-- facility slots: 4 down each side of the hangar, then 9 along the far edge of the airfield
local facilitySlots = {}
for _, z in ipairs({ -230, -170, -110, -50 }) do
	table.insert(facilitySlots, Vector3.new(-172, 0, z))
	table.insert(facilitySlots, Vector3.new(172, 0, z))
end
for i = 0, 8 do
	table.insert(facilitySlots, Vector3.new(-180 + i * 45, 0, 245))
end

local planeIdx, facIdx = 0, 0
for _, it in ipairs(Items.List) do
	if it.kind == "aircraft" then
		local c = planeIdx % Layout.BayCols
		local r = planeIdx // Layout.BayCols
		local centre = Layout.BayOrigin + Vector3.new(c * Layout.BayW, 0, r * Layout.BayD)
		bay[it.id] = CFrame.new(centre) * CFrame.Angles(0, math.rad(180), 0) -- nose toward the entrance
		pad[it.id] = centre + Vector3.new(0, 0, -Layout.BayD / 2 + 3)
		planeIdx += 1
	else
		facIdx += 1
		local slot = facilitySlots[facIdx] or Vector3.new(0, 0, 260)
		facility[it.id] = CFrame.new(slot)
		-- pad on the side facing the hangar / apron
		local toward = slot.Z > 200 and Vector3.new(0, 0, -14) or Vector3.new(slot.X > 0 and -14 or 14, 0, 0)
		pad[it.id] = slot + toward
	end
end

-- premium "Black Project" showcase bays in the entrance hall (visible from the door)
local premiumX = { b21 = 40, f47 = 72, sr72 = 104 }
for _, a in ipairs(Aircraft.List) do
	if a.premium then
		local x = premiumX[a.id] or 0
		bay[a.id] = CFrame.new(x, 0, -240) * CFrame.Angles(0, math.rad(180), 0)
		pad[a.id] = Vector3.new(x, 0, -262)
	end
end

Layout.Bay = bay
Layout.Pad = pad
Layout.Facility = facility

return Layout
