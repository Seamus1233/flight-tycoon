--[[
	Flight controller - arcade flight model for the aircraft the server spawns.

	Controls:  mouse = aim   W/S = throttle   A/D = roll   Shift = afterburner
	           F or Space = exit aircraft
	Mobile: the plane follows the camera direction (drag to look), throttle auto-climbs.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Format = require(ReplicatedStorage:WaitForChild("Shared").Util.Format)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Flight = {}

local flying = false
local conn
local hud

local function makeHud()
	local g = Instance.new("ScreenGui")
	g.Name = "FlightHUD"
	g.ResetOnSpawn = false
	local f = Instance.new("TextLabel")
	f.Name = "Info"
	f.Size = UDim2.fromOffset(420, 70)
	f.Position = UDim2.new(0.5, 0, 1, -80)
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
	f.BackgroundTransparency = 0.25
	f.TextColor3 = Color3.fromRGB(120, 255, 160)
	f.Font = Enum.Font.Code
	f.TextScaled = true
	f.Text = ""
	f.Parent = g
	Instance.new("UICorner", f)
	local cross = Instance.new("Frame")
	cross.Name = "Reticle"
	cross.Size = UDim2.fromOffset(10, 10)
	cross.AnchorPoint = Vector2.new(0.5, 0.5)
	cross.BackgroundColor3 = Color3.fromRGB(120, 255, 160)
	cross.Parent = g
	Instance.new("UICorner", cross).CornerRadius = UDim.new(1, 0)
	g.Parent = player:WaitForChild("PlayerGui")
	return g
end

local function startFlying(seat: Seat)
	local model = seat.Parent
	local root = model.PrimaryPart
	local lv: LinearVelocity = root:WaitForChild("Thrust")
	local ao: AlignOrientation = root:WaitForChild("Steer")
	local maxSpeed = model:GetAttribute("MaxSpeed") or 150
	local name = model:GetAttribute("DisplayName") or model.Name
	local extents = model:GetAttribute("Extents") or Vector3.new(20, 6, 20)
	local camDist = math.max(extents.Z, extents.X) * 1.3 + 12

	flying = true
	hud = hud or makeHud()
	hud.Enabled = true
	camera.CameraType = Enum.CameraType.Scriptable

	local throttle = 0
	local speed = 0
	local look = root.CFrame.LookVector
	local roll = 0
	local takeoffSpeed = maxSpeed * 0.3
	local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if isTouch then throttle = 0.7 end

	conn = RunService.RenderStepped:Connect(function(dt)
		if not model.Parent or not seat.Occupant then
			Flight.Stop()
			return
		end
		dt = math.min(dt, 0.1)
		-- throttle
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then throttle = math.min(1, throttle + dt * 0.6) end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then throttle = math.max(0, throttle - dt * 0.6) end
		local boost = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 1.35 or 1
		local target = throttle * maxSpeed * boost
		speed += (target - speed) * math.min(1, dt * 0.8)

		-- aim direction from mouse (or camera centre on touch)
		local mp = isTouch and camera.ViewportSize / 2 or UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mp.X, mp.Y)
		local desired = ray.Direction.Unit
		local airborne = speed >= takeoffSpeed
		if not airborne then
			desired = Vector3.new(desired.X, math.min(desired.Y, 0), desired.Z)
			if desired.Magnitude < 0.1 then desired = look end
			desired = desired.Unit
		end
		-- turn rate limited, slower at low speed
		local turnRate = math.rad(70) * math.clamp(speed / (maxSpeed * 0.5), 0.15, 1)
		local angle = math.acos(math.clamp(look:Dot(desired), -1, 1))
		local newLook = look
		if angle > 1e-3 then
			local t = math.min(1, turnRate * dt / angle)
			newLook = look:Lerp(desired, t).Unit
		end
		-- bank into turns + manual roll
		local yawRate = look:Cross(newLook).Y / math.max(dt, 1e-3)
		local manual = (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0)
		local targetRoll = math.clamp(yawRate * 1.6, -1.2, 1.2) + manual * 1.2
		roll += (targetRoll - roll) * math.min(1, dt * 4)
		look = newLook

		local vel = look * speed
		if not airborne then
			vel = Vector3.new(vel.X, math.min(vel.Y, 0) - 30 * (1 - speed / takeoffSpeed), vel.Z)
		end
		-- soft ceiling
		if root.Position.Y > 2500 and vel.Y > 0 then
			vel = Vector3.new(vel.X, 0, vel.Z)
		end
		lv.VectorVelocity = vel
		ao.CFrame = CFrame.lookAt(Vector3.zero, look) * CFrame.Angles(0, 0, roll)

		-- chase camera
		local camPos = root.Position - look * camDist + Vector3.new(0, camDist * 0.3, 0)
		camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(camPos, root.Position + look * camDist), math.min(1, dt * 6))
		camera.FieldOfView = 70 + 15 * (speed / (maxSpeed * 1.35))

		hud.Info.Text = string.format("%s\nSPD %d  ALT %d  THR %d%%   [F] exit",
			name, math.floor(speed), math.floor(root.Position.Y), math.floor(throttle * 100))
		hud.Reticle.Position = UDim2.fromOffset(mp.X, mp.Y - 36)
	end)
end

function Flight.Stop()
	if conn then conn:Disconnect() conn = nil end
	if not flying then return end
	flying = false
	if hud then hud.Enabled = false end
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		camera.CameraSubject = hum
		if hum.Sit then hum.Sit = false end
	end
	Remotes.Action:FireServer("Land")
end

local function hookCharacter(character: Model)
	local hum = character:WaitForChild("Humanoid")
	hum.Seated:Connect(function(active, seat)
		if active and seat and seat:GetAttribute("AircraftSeat") then
			startFlying(seat)
		elseif not active and flying then
			Flight.Stop()
		end
	end)
end

function Flight.Init()
	if player.Character then task.spawn(hookCharacter, player.Character) end
	player.CharacterAdded:Connect(function(c)
		Flight.Stop()
		hookCharacter(c)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not flying then return end
		if input.KeyCode == Enum.KeyCode.F then
			Flight.Stop()
		end
	end)
end

return Flight
