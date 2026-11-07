--[[
	Plot layout, in plot-local coordinates (origin = plot centre, +Z = back).

	  front (z = -165)  [entrance] [collector] [premium bays x3]
	  middle            aircraft bays, 8 columns x 6 rows       | runway
	  back  (z = +165)  facilities, 2 rows                        | runway
]]
local Items = require(script.Parent.Config.Items)
local Aircraft = require(script.Parent.Config.Aircraft)

local Layout = {}

Layout.BayCols = 8
Layout.BayW = 26
Layout.BayD = 34
Layout.BayOrigin = Vector3.new(-140 + 13, 0, -112 + 17)
Layout.Spawn = Vector3.new(-120, 0, -150)
Layout.Collector = Vector3.new(-85, 0, -150)
Layout.RunwayCenter = Vector3.new(112, 0, 0)
Layout.RunwaySize = Vector3.new(50, 0.4, 320)
Layout.RunwayStart = CFrame.new(112, 0, 140) -- take-off point, facing -Z (down the runway)
Layout.RebirthPad = Vector3.new(-50, 0, -150)

local bay = {}       -- itemId -> CFrame of bay centre
local pad = {}       -- itemId -> Vector3 of buy pad
local facility = {}  -- itemId -> CFrame

local planeIdx, facIdx = 0, 0
for _, it in ipairs(Items.List) do
	if it.kind == "aircraft" then
		local c = planeIdx % Layout.BayCols
		local r = planeIdx // Layout.BayCols
		local centre = Layout.BayOrigin + Vector3.new(c * Layout.BayW, 0, r * Layout.BayD)
		bay[it.id] = CFrame.new(centre) * CFrame.Angles(0, math.rad(180), 0) -- nose toward the front walkway
		pad[it.id] = centre + Vector3.new(0, 0, -Layout.BayD / 2 + 3)
		planeIdx += 1
	else
		local c = facIdx % 9
		local r = facIdx // 9
		local centre = Vector3.new(-128 + c * 25, 0, 115 + r * 30)
		facility[it.id] = CFrame.new(centre)
		pad[it.id] = centre + Vector3.new(0, 0, -12)
		facIdx += 1
	end
end

-- premium "Black Project" showcase bays, by the entrance (visible to everyone)
local premiumX = { b21 = -10, f47 = 22, sr72 = 54 }
for _, a in ipairs(Aircraft.List) do
	if a.premium then
		local x = premiumX[a.id] or 0
		bay[a.id] = CFrame.new(x, 0, -142) * CFrame.Angles(0, math.rad(180), 0)
		pad[a.id] = Vector3.new(x, 0, -158)
	end
end

Layout.Bay = bay
Layout.Pad = pad
Layout.Facility = facility

return Layout
