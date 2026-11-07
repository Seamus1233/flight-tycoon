--[[
	AircraftBuilder

	Builds a Model for an aircraft spec (from Config/Aircraft).

	1. If ReplicatedStorage.AircraftMeshes has a Model named after the aircraft id
	   (the FBX you imported from models/<id>/<id>.fbx), that model is cloned and
	   scaled. This is the high-quality path.
	2. Otherwise a Part-based version is built procedurally from the same
	   parameters the Blender generator uses, so the game is fully playable
	   before any meshes are imported.

	Every model has a PrimaryPart called "Root" facing forward (-Z), with all
	other parts welded to it and Massless, ready for display or flight.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AircraftBuilder = {}

local DETAIL_COLOR = Color3.fromRGB(32, 32, 36)
local GLASS_COLOR = Color3.fromRGB(20, 45, 70)

local function newPart(class, parent, size, cf, color, material)
	local p = Instance.new(class)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

-- cylinder whose axis runs along world Z (forward/back)
local function zCylinder(parent, centre, length, radius, color, material)
	local p = newPart("Part", parent, Vector3.new(length, radius * 2, radius * 2),
		CFrame.new(centre) * CFrame.Angles(0, math.rad(90), 0), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ellipsoid(parent, centre, size, color, material, transparency)
	local p = newPart("Part", parent, size, CFrame.new(centre), color, material)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	p.Transparency = transparency or 0
	return p
end

--[[ A flat tapered panel (wing / stabiliser / canard).
	pivot  : CFrame at the root leading edge
	side   : +1 right, -1 left
	span   : exposed half span
	cRoot, cTip : chords
	thick  : thickness
	Leading edge sweeps back from the root front to the tip front (TE straight);
	`yaw` adds extra sweep by rotating the whole panel. ]]
local function panel(parent, rootLE: Vector3, side, span, cRoot, cTip, thick, sweepDeg, dihedralDeg, color)
	local geomSweep = math.deg(math.atan2(cRoot - cTip, span))
	local extra = math.max(0, sweepDeg - geomSweep) * 0.85
	local pivot = CFrame.new(rootLE)
		* CFrame.Angles(0, math.rad(-extra * side), 0)
		* CFrame.Angles(0, 0, math.rad(dihedralDeg * side))
	-- rectangle (tip chord wide) at the rear
	local d = cRoot - cTip
	if cTip > 0.05 then
		newPart("Part", parent, Vector3.new(span, thick, cTip),
			pivot * CFrame.new(side * span / 2, 0, d + cTip / 2), color)
	end
	-- triangle in front of it
	if d > 0.05 then
		newPart("WedgePart", parent, Vector3.new(thick, span, d),
			pivot * CFrame.new(side * span / 2, 0, d / 2) * CFrame.Angles(0, 0, math.rad(-90 * side)), color)
	end
end

local function fin(parent, rearBase: Vector3, chord, height, thick, cantDeg, color)
	-- WedgePart: tall at the back (+Z), slopes down to the front = swept fin.
	local cf = CFrame.new(rearBase) * CFrame.Angles(0, 0, math.rad(cantDeg))
		* CFrame.new(0, height / 2, -chord / 2)
	newPart("WedgePart", parent, Vector3.new(thick, height, chord), cf, color)
end

local function propeller(parent, centre: Vector3, radius)
	zCylinder(parent, centre + Vector3.new(0, 0, -radius * 0.08), radius * 0.35, radius * 0.13, DETAIL_COLOR)
	for i = 0, 2 do
		local a = i * math.pi * 2 / 3
		newPart("Part", parent, Vector3.new(radius * 0.12, radius * 0.95, radius * 0.04),
			CFrame.new(centre) * CFrame.Angles(0, 0, a) * CFrame.new(0, radius * 0.5, 0), DETAIL_COLOR)
	end
end

-- Procedural part build. Units: metres * k (studs per metre).
local function buildParts(spec, k, model)
	local L, S = spec.L * k, spec.S * k
	local col = Color3.new(spec.color[1], spec.color[2], spec.color[3])
	local big = spec.L > 22 or string.find(spec.role, "Bomber") ~= nil
	local R = L * (spec.props > 0 and 0.072 or (big and 0.058 or 0.062))
	local special = spec.special
	local delta = spec.taper < 0.15
	local front = -L / 2 -- nose z (forward is -Z)
	local rear = L / 2

	if special == "flying_wing" then
		local half = S / 2
		for _, side in ipairs({ 1, -1 }) do
			panel(model, Vector3.new(0, 0, front), side, half, L, L * 0.06, L * 0.06, spec.sweep, 0, col)
		end
		ellipsoid(model, Vector3.new(0, L * 0.03, -L * 0.1), Vector3.new(half * 0.26, L * 0.12, L * 0.75), col)
		ellipsoid(model, Vector3.new(0, L * 0.08, -L * 0.33), Vector3.new(half * 0.1, L * 0.05, L * 0.12),
			GLASS_COLOR, Enum.Material.Glass, 0.15)
		return
	end

	-- fuselage: tail cone, main body, nose sections
	local bodyLen = L * 0.5
	zCylinder(model, Vector3.new(0, 0, front + L * 0.38 + bodyLen / 2), bodyLen, R, col)
	zCylinder(model, Vector3.new(0, 0, rear - L * 0.06), L * 0.12, R * 0.75, col)
	local noseSteps = 4
	for i = 1, noseSteps do
		local t = i / noseSteps
		local r
		if spec.nose == "pointed" or spec.nose == "chine" then
			r = R * (1 - 0.85 * t)
		elseif spec.nose == "intake" then
			r = R * (1 - 0.2 * t)
		else
			r = R * (1 - 0.3 * t * t)
		end
		local segLen = L * 0.38 / noseSteps
		zCylinder(model, Vector3.new(0, 0, front + L * 0.38 - (i - 0.5) * segLen), segLen, r, col)
	end
	if spec.nose == "intake" then
		zCylinder(model, Vector3.new(0, 0, front + 0.05), 0.1, R * 0.62, DETAIL_COLOR)
	end
	if spec.nose == "chine" then
		for _, side in ipairs({ 1, -1 }) do
			panel(model, Vector3.new(side * R * 0.7, 0, front + L * 0.06), side, R * 0.6, L * 0.4, L * 0.1, R * 0.1, 80, 0, col)
		end
	end

	-- wings
	local half = S / 2
	local exposed = half - R * 0.5
	local cRoot
	if delta then
		cRoot = L * ((spec.tail == "delta" or spec.tail == "none") and 0.48 or 0.40)
	else
		local mean = (spec.props > 0 or spec.sweep < 15) and S / 6.2 or S / 4.0
		cRoot = math.min(L * 0.38, 2 * mean / (1 + spec.taper))
	end
	local cTip = cRoot * spec.taper
	local wingY = ({ low = -R * 0.55, mid = 0, high = R * 0.6 })[spec.wing] or 0
	local rootLEz
	if cRoot > L * 0.35 then
		rootLEz = rear - cRoot - L * 0.04
	elseif spec.props > 0 then
		rootLEz = -L * 0.22
	else
		rootLEz = -(cRoot * 0.5 + L * 0.02)
	end
	local wingThick = math.max(cRoot * 0.07, R * 0.12)

	if special == "twin_boom" then
		local bx = S * 0.17
		for _, side in ipairs({ 1, -1 }) do
			zCylinder(model, Vector3.new(side * bx, 0, -L * 0.05), L * 0.85, R * 0.5, col)
			propeller(model, Vector3.new(side * bx, 0, -L * 0.5), S * 0.1)
			fin(model, Vector3.new(side * bx, R * 0.3, rear - L * 0.02), L * 0.15, L * 0.16, L * 0.015, 0, col)
		end
		newPart("Part", model, Vector3.new(bx * 2, L * 0.012, L * 0.1), CFrame.new(0, 0, rear - L * 0.1), col)
	end

	for _, side in ipairs({ 1, -1 }) do
		panel(model, Vector3.new(side * R * 0.5, wingY, rootLEz), side, exposed, cRoot, math.max(cTip, 0.1),
			wingThick, spec.sweep, spec.dihedral, col)
	end

	-- canards
	if spec.canard then
		for _, side in ipairs({ 1, -1 }) do
			panel(model, Vector3.new(side * R * 0.75, R * 0.2, -L * 0.24), side, S * 0.16, L * 0.1, L * 0.03, L * 0.01, 48, 0, col)
		end
	end

	-- tail
	local tail = spec.tail
	local finH = L * (spec.props > 0 and 0.15 or 0.17)
	local finChord = L * 0.17
	local finThick = finChord * 0.08
	if special ~= "twin_boom" and tail ~= "none" then
		if tail == "conv" or tail == "t" or tail == "delta" then
			fin(model, Vector3.new(0, R * 0.6, rear - L * 0.02), finChord, finH, finThick, 0, col)
		elseif tail == "twin" or tail == "canted" or tail == "hbox" then
			local cant = tail == "canted" and 22 or 4
			for _, side in ipairs({ 1, -1 }) do
				local x = tail == "hbox" and side * (R * 0.3 + S * 0.2) or side * R * 0.85
				fin(model, Vector3.new(x, R * 0.4, rear - L * 0.02), finChord * 0.95, finH * 0.85, finThick, -cant * side, col)
			end
		end
		if tail ~= "delta" and special ~= "stealth_facet" then
			local hsHalf = S * (spec.props > 0 and 0.20 or 0.24)
			local hsChord = finChord * 0.85
			local y = tail == "t" and R * 0.6 + finH or R * 0.1
			local z = rear - L * 0.02 - hsChord - (tail == "t" and finH * 0.4 or 0)
			for _, side in ipairs({ 1, -1 }) do
				panel(model, Vector3.new(side * R * 0.3, y, z), side, hsHalf, hsChord, hsChord * 0.45,
					hsChord * 0.08, spec.props > 0 and 2 or spec.sweep * 0.9, 0, col)
			end
		end
	end

	-- canopy
	if big then
		ellipsoid(model, Vector3.new(0, R * 0.55, front + L * 0.1), Vector3.new(R * 1.1, R * 0.7, L * 0.12),
			GLASS_COLOR, Enum.Material.Glass, 0.15)
	else
		ellipsoid(model, Vector3.new(0, R * 0.7, front + L * (spec.props > 0 and 0.22 or 0.25)),
			Vector3.new(R * 0.75, R * 0.75, L * 0.15), GLASS_COLOR, Enum.Material.Glass, 0.15)
	end

	-- engines
	local function wingPoint(side, frac)
		local d = exposed * frac
		local chord = cRoot + (cTip - cRoot) * frac
		local sweepRad = math.rad(spec.sweep)
		return Vector3.new(side * (R * 0.5 + d), wingY + d * math.sin(math.rad(spec.dihedral)), rootLEz + d * math.tan(sweepRad) * 0.5), chord
	end
	if spec.props == 1 then
		propeller(model, Vector3.new(0, 0, front - R * 0.05), S * 0.17)
	elseif spec.props >= 2 and special ~= "twin_boom" then
		local fracs = spec.props == 4 and { 0.28, 0.58 } or { 0.3 }
		for _, side in ipairs({ 1, -1 }) do
			for _, fr in ipairs(fracs) do
				local p, chord = wingPoint(side, fr)
				zCylinder(model, p + Vector3.new(0, 0, chord * 0.1), chord * 1.2, R * 0.42, col)
				propeller(model, p + Vector3.new(0, 0, -chord * 0.55), S * 0.065)
			end
		end
	end
	if spec.pods > 0 then
		local fracs = spec.pods == 2 and { 0.32 } or { 0.25, 0.55 }
		if special == "blackbird" then fracs = { 0.45 } end
		for _, side in ipairs({ 1, -1 }) do
			for _, fr in ipairs(fracs) do
				local p, chord = wingPoint(side, fr)
				local pr = R * (special == "blackbird" and 0.75 or (spec.id == "b1b" and 0.75 or 0.42))
				local yOff = special == "blackbird" and 0 or -pr * 1.4
				zCylinder(model, p + Vector3.new(0, yOff, chord * 0.2), chord * 1.1, pr, col)
				if special == "blackbird" then
					fin(model, p + Vector3.new(0, pr * 0.8, chord * 0.75), L * 0.12, L * 0.11, L * 0.01, -15 * side, col)
				end
			end
		end
	end
	if special == "rear_pods" then
		for _, side in ipairs({ 1, -1 }) do
			zCylinder(model, Vector3.new(side * R * 1.4, R * 1.0, L * 0.22), L * 0.22, R * 0.55, col)
		end
	end
	if spec.jets == 1 then
		zCylinder(model, Vector3.new(0, 0, rear + L * 0.015), L * 0.03, R * 0.5, DETAIL_COLOR, Enum.Material.Metal)
	elseif spec.jets == 2 then
		for _, side in ipairs({ 1, -1 }) do
			zCylinder(model, Vector3.new(side * R * 0.5, 0, rear + L * 0.015), L * 0.03, R * 0.42, DETAIL_COLOR, Enum.Material.Metal)
		end
	end
end

local function finalize(model: Model, name: string)
	local cf, size = model:GetBoundingBox()
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Size = Vector3.new(2, 2, 2)
	root.CFrame = CFrame.new(cf.Position)
	root.Parent = model
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			d.Anchored = false
			d.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = d
			w.Parent = d
		end
	end
	model.PrimaryPart = root
	model.Name = name
	model:SetAttribute("Extents", size)
	return model
end

--[[ Build an aircraft model.
	spec       : entry from Config/Aircraft
	targetSize : studs; the largest of length / span is scaled to this
	Returns a Model whose PrimaryPart "Root" sits at the origin, facing -Z. ]]
function AircraftBuilder.Build(spec, targetSize: number): Model
	local meshes = ReplicatedStorage:FindFirstChild("AircraftMeshes")
	local template = meshes and meshes:FindFirstChild(spec.id)
	local model
	if template and template:IsA("Model") then
		model = template:Clone()
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				if d.Name == "Body" then
					d.Color = Color3.new(spec.color[1], spec.color[2], spec.color[3])
				end
			end
		end
		local _, size = model:GetBoundingBox()
		local largest = math.max(size.X, size.Z)
		if largest > 0 then
			model:ScaleTo(model:GetScale() * targetSize / largest)
		end
		model:PivotTo(CFrame.new())
	else
		model = Instance.new("Model")
		local k = targetSize / math.max(spec.L, spec.S)
		buildParts(spec, k, model)
	end
	return finalize(model, spec.id)
end

return AircraftBuilder
