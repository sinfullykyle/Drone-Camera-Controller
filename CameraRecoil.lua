-- Services are cached once at startup because this controller runs every render frame.
-- Repeated GetService calls would still work, but caching keeps the hot path cleaner and
-- makes it obvious which engine systems this controller depends on.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local TweenService=game:GetService("TweenService")

-- The controller only affects the local player's camera, so we resolve those references once
-- and treat them as the root context for the whole system.
local player=Players.LocalPlayer
local camera=workspace.CurrentCamera

--//==================================================
--// Spring
--//==================================================

-- The spring object is the core smoothing primitive used by the controller.
-- Instead of snapping sway/recoil/roll directly to the latest target every frame,
-- each effect moves toward its goal over time. That gives camera motion inertia,
-- makes rapid mouse movement feel less robotic, and lets multiple effects blend
-- together without visible hard transitions.
local Spring={}
Spring.__index=Spring

function Spring.new(speed,damping,initial)
	local self=setmetatable({},Spring)

	-- Speed controls how aggressively the spring chases the target.
	-- Damping controls how quickly extra motion dies out instead of oscillating forever.
	-- Position, Velocity, and Target are kept separate so the spring can simulate momentum
	-- rather than acting like a simple lerp.
	self.Speed=speed or 10
	self.Damping=damping or 0.8
	self.Position=initial or Vector3.zero
	self.Velocity=Vector3.zero
	self.Target=initial or Vector3.zero
	return self
end

function Spring:Shove(force)
	-- Shove adds energy directly into the spring instead of changing its target.
	-- That is useful for short impulses like recoil, because recoil should feel like
	-- an immediate kick layered on top of the current motion rather than a slow retarget.
	self.Velocity+=force
end

function Spring:SetTarget(target)
	-- Target is kept separate from Position so the spring can smoothly chase the desired
	-- value over time. This separation is what gives the system its “weight”.
	self.Target=target
end

function Spring:SetPosition(position)
	self.Position=position
end

function Spring:SetVelocity(velocity)
	self.Velocity=velocity
end

function Spring:Update(dt)
	-- The spring update is intentionally simple:
	-- 1. Measure how far we are from the target.
	-- 2. Accelerate toward that target.
	-- 3. Apply damping so motion settles instead of growing unstable.
	-- 4. Integrate velocity into position.
	--
	-- This gives us a lightweight spring-like response without needing a more expensive
	-- full physics solver, which is ideal for per-frame camera effects.
	local offset=self.Target-self.Position
	self.Velocity+=offset*self.Speed*dt
	self.Velocity*=math.max(0,1-self.Damping*dt*10)
	self.Position+=self.Velocity*dt
	return self.Position
end

function Spring:Reset(value)
	-- Reset clears all accumulated momentum. This matters when the player respawns or the
	-- controller is toggled off, because leftover spring velocity would otherwise carry
	-- old camera motion into the new state and make the camera feel desynced.
	self.Position=value or Vector3.zero
	self.Target=value or Vector3.zero
	self.Velocity=Vector3.zero
end

--//==================================================
--// Controller
--//==================================================

-- The controller owns all camera-effect state and acts like a single local object.
-- Using a metatable here keeps the script as one file while still giving it a clean,
-- method-based structure similar to a lightweight class.
local Controller={}
Controller.__index=Controller

function Controller.new()
	local self=setmetatable({},Controller)

	-- Enabled gates the entire effect stack.
	-- Aiming changes the effect multiplier so the camera becomes quieter when precision matters.
	-- ShowDebug exists so tuning values can be inspected live without editing the script.
	-- Destroyed prevents render callbacks from doing work after cleanup.
	self.Enabled=true
	self.Aiming=false
	self.ShowDebug=true
	self.Destroyed=false

	-- These references are character-dependent and must be refreshed on respawn.
	-- They are stored on the controller so the render loop can avoid repeated hierarchy lookups.
	self.Character=nil
	self.Humanoid=nil
	self.Root=nil
	self.Head=nil

	-- MouseDelta stores the newest raw-ish input sample after sign correction and clamping.
	-- SmoothedMouse is what the camera actually uses. Separating them lets us preserve
	-- responsiveness while still filtering tiny jitter and harsh frame-to-frame jumps.
	self.MouseDelta=Vector2.zero
	self.SmoothedMouse=Vector2.zero

	-- LastInputTime is used to decide when idle motion should take over.
	-- LastRecoilName is debug-only, but storing it makes the overlay useful during tuning.
	self.LastAppliedOffset=CFrame.new()
	self.LastInputTime=0
	self.LastRecoilName="Light"

	-- Each effect gets its own spring because the motion types behave differently.
	-- Separate springs let sway, rotation, recoil, roll, and idle settle at different rates
	-- without interfering with each other’s tuning.
	self.SwaySpring=Spring.new(18,0.82,Vector3.zero)
	self.RotationSpring=Spring.new(20,0.84,Vector3.zero)
	self.RecoilSpring=Spring.new(24,0.86,Vector3.zero)
	self.RollSpring=Spring.new(16,0.82,Vector3.zero)
	self.IdleSpring=Spring.new(8,0.9,Vector3.zero)

	-- These settings are grouped together so the behavior can be tuned without touching the
	-- math in the update functions. The script is easier to reason about when configuration
	-- and implementation are separated like this.
	self.Settings={
		SwayPositionX=0.0028,
		SwayPositionY=0.0022,
		SwayPositionZ=0.0016,
		RotationPitch=0.010,
		RotationYaw=0.008,
		RotationRoll=0.003,
		Smoothing=0.28,
		MaxMouseDelta=36,
		RecoilReturn=0.9,
		IdleFrequency=1.8,
		IdleAmplitudeX=0.010,
		IdleAmplitudeY=0.016,
		IdleAmplitudeZ=0.006,
		MouseDecayThreshold=0.001,
		AimMultiplier=0.45,
		NormalMultiplier=1,
		MinFov=70,
		MaxFov=78,
		FovKickScale=0.06,
		FovSmooth=0.15,
		InvertX=false,
		InvertY=false,
		DebugTransparency=0.25
	}

	-- Recoil is defined as named profiles instead of hardcoded one-off values so the same
	-- recoil pipeline can support multiple weapon or test strengths without branching the system.
	self.RecoilProfiles={
		Light={
			Kick=Vector3.new(-0.40,0.10,0.03),
			Rot=Vector3.new(math.rad(-1.6),math.rad(0.5),math.rad(0.3))
		},
		Medium={
			Kick=Vector3.new(-0.75,0.16,0.05),
			Rot=Vector3.new(math.rad(-2.8),math.rad(0.8),math.rad(0.45))
		},
		Heavy={
			Kick=Vector3.new(-1.15,0.22,0.08),
			Rot=Vector3.new(math.rad(-4.3),math.rad(1.2),math.rad(0.7))
		}
	}

	-- Connections are tracked so the controller can cleanly disconnect everything on destroy
	-- instead of leaving input listeners alive after the object is no longer valid.
	self.Connections={}
	self.DebugGui=nil
	self.DebugFrame=nil
	self.DebugLines={}

	-- Setup is split into small bind/create steps so initialization order is explicit:
	-- character refs first, then input listeners, then render loop, then debug UI.
	self:BindCharacter()
	self:BindInput()
	self:BindLoop()
	self:CreateDebug()

	return self
end

function Controller:Connect(signal,callback)
	local connection=signal:Connect(callback)
	table.insert(self.Connections,connection)
	return connection
end

function Controller:DisconnectAll()
	for _,connection in ipairs(self.Connections) do
		if connection and connection.Disconnect then
			connection:Disconnect()
		end
	end
	table.clear(self.Connections)
end

function Controller:BindCharacter()
	local function setup(char)
		-- Character references are refreshed on every spawn because Humanoid/Root/Head instances
		-- are recreated with the character. Reusing stale references would break the controller.
		self.Character=char
		self.Humanoid=char:WaitForChild("Humanoid")
		self.Root=char:WaitForChild("HumanoidRootPart")
		self.Head=char:WaitForChild("Head")

		-- Respawn is treated as a clean state transition. Input history and spring momentum are
		-- cleared so the new character does not inherit camera motion from the previous one.
		self.MouseDelta=Vector2.zero
		self.SmoothedMouse=Vector2.zero
		self.LastInputTime=time()
		self.SwaySpring:Reset(Vector3.zero)
		self.RotationSpring:Reset(Vector3.zero)
		self.RecoilSpring:Reset(Vector3.zero)
		self.RollSpring:Reset(Vector3.zero)
		self.IdleSpring:Reset(Vector3.zero)
	end

	if player.Character then
		setup(player.Character)
	end

	self:Connect(player.CharacterAdded,setup)
end

function Controller:Toggle()
	self.Enabled=not self.Enabled
	if not self.Enabled then
		-- When disabling the system we immediately clear transient state instead of allowing
		-- the springs to coast out. That makes the toggle feel intentional and prevents the
		-- camera from continuing to drift after the user has turned effects off.
		self.MouseDelta=Vector2.zero
		self.SmoothedMouse=Vector2.zero
		self.SwaySpring:Reset(Vector3.zero)
		self.RotationSpring:Reset(Vector3.zero)
		self.RollSpring:Reset(Vector3.zero)
		self.IdleSpring:Reset(Vector3.zero)
	end
	self:RefreshDebugColors()
end

function Controller:ToggleAim(state)
	-- Aim mode only changes the multiplier, not a separate branch of camera math.
	-- That keeps the feel consistent while still reducing motion enough to communicate
	-- higher precision and control.
	if state==nil then
		self.Aiming=not self.Aiming
	else
		self.Aiming=state
	end
	self:RefreshDebugColors()
end

function Controller:ToggleDebug()
	self.ShowDebug=not self.ShowDebug
	if self.DebugGui then
		self.DebugGui.Enabled=self.ShowDebug
	end
end

function Controller:GetMultiplier()
	-- Centralizing the multiplier here prevents the rest of the camera math from needing
	-- to care whether the player is aiming. The effect functions can stay generic.
	if self.Aiming then
		return self.Settings.AimMultiplier
	end
	return self.Settings.NormalMultiplier
end

function Controller:GetSignedMouseDelta(delta)
	-- Inversion is handled before smoothing so the entire downstream pipeline works from
	-- one consistent input direction. That avoids needing to remember inversion rules in
	-- each sway/rotation function separately.
	local x=delta.X
	local y=delta.Y
	if self.Settings.InvertX then
		x=-x
	end
	if self.Settings.InvertY then
		y=-y
	end
	return Vector2.new(x,y)
end

function Controller:ClampMouseDelta(delta)
	-- Clamping prevents unusually large one-frame mouse spikes from producing a camera jump
	-- that overwhelms the springs. This is especially useful for low frame moments or sudden
	-- high-DPI input bursts.
	return Vector2.new(
		math.clamp(delta.X,-self.Settings.MaxMouseDelta,self.Settings.MaxMouseDelta),
		math.clamp(delta.Y,-self.Settings.MaxMouseDelta,self.Settings.MaxMouseDelta)
	)
end

function Controller:RecordMouse(delta)
	local signed=self:GetSignedMouseDelta(delta)
	local clamped=self:ClampMouseDelta(signed)

	-- We keep the newest clamped input sample and separately record when the player last moved
	-- the mouse. That timestamp is later used to decide when idle motion should fade in.
	self.MouseDelta=clamped
	self.LastInputTime=time()
end

function Controller:BindInput()
	self:Connect(UserInputService.InputChanged,function(input,gpe)
		if gpe then
			return
		end
		if input.UserInputType==Enum.UserInputType.MouseMovement then
			self:RecordMouse(input.Delta)
		end
	end)

	self:Connect(UserInputService.InputBegan,function(input,gpe)
		if gpe then
			return
		end

		-- All runtime tuning and test controls are routed through one input handler so state
		-- changes remain centralized. That is easier to debug than scattering keybind logic
		-- across separate listeners.
		if input.KeyCode==Enum.KeyCode.E then
			self:Toggle()
		elseif input.KeyCode==Enum.KeyCode.Q then
			self:ApplyRecoil("Light")
		elseif input.KeyCode==Enum.KeyCode.R then
			self:ApplyRecoil("Medium")
		elseif input.KeyCode==Enum.KeyCode.T then
			self:ApplyRecoil("Heavy")
		elseif input.KeyCode==Enum.KeyCode.Z then
			self:ToggleAim()
		elseif input.KeyCode==Enum.KeyCode.X then
			self.Settings.InvertX=not self.Settings.InvertX
		elseif input.KeyCode==Enum.KeyCode.Y then
			self.Settings.InvertY=not self.Settings.InvertY
		elseif input.KeyCode==Enum.KeyCode.F3 then
			self:ToggleDebug()
		elseif input.KeyCode==Enum.KeyCode.LeftBracket then
			self:AdjustSensitivity(-0.0002)
		elseif input.KeyCode==Enum.KeyCode.RightBracket then
			self:AdjustSensitivity(0.0002)
		end
	end)

	self:Connect(UserInputService.InputEnded,function(input,gpe)
		if gpe then
			return
		end

		-- Right mouse release explicitly exits aiming. Keeping this separate from the toggle
		-- path allows aim to behave like a hold-based state if you later choose to bind it
		-- to mouse button input instead of a keyboard toggle.
		if input.UserInputType==Enum.UserInputType.MouseButton2 then
			self:ToggleAim(false)
		end
	end)
end

function Controller:AdjustSensitivity(delta)
	-- Sensitivity tuning updates multiple related values together because perceived camera feel
	-- comes from the combination of positional sway and rotational response, not one number alone.
	-- Clamps keep live tuning from pushing the controller into unstable or unreadable ranges.
	self.Settings.SwayPositionX=math.clamp(self.Settings.SwayPositionX+delta,0.0006,0.008)
	self.Settings.SwayPositionY=math.clamp(self.Settings.SwayPositionY+delta,0.0006,0.008)
	self.Settings.SwayPositionZ=math.clamp(self.Settings.SwayPositionZ+delta*0.6,0.0003,0.006)
	self.Settings.RotationPitch=math.clamp(self.Settings.RotationPitch+delta*2.5,0.002,0.03)
	self.Settings.RotationYaw=math.clamp(self.Settings.RotationYaw+delta*2.0,0.0015,0.025)
	self.Settings.RotationRoll=math.clamp(self.Settings.RotationRoll+delta,0.0005,0.01)
end

function Controller:GetSmoothedMouse()
	local target=self.MouseDelta
	local alpha=self.Settings.Smoothing

	-- Input is smoothed before being turned into camera offsets so the springs receive a
	-- cleaner signal. This reduces tiny high-frequency jitter while still allowing larger,
	-- intentional movement to come through quickly.
	self.SmoothedMouse=self.SmoothedMouse:Lerp(target,alpha)

	-- Very small residual values are zeroed out to prevent the camera from visually “buzzing”
	-- near rest because of tiny floating-point leftovers or tiny mouse input noise.
	if math.abs(self.SmoothedMouse.X)<self.Settings.MouseDecayThreshold then
		self.SmoothedMouse=Vector2.new(0,self.SmoothedMouse.Y)
	end
	if math.abs(self.SmoothedMouse.Y)<self.Settings.MouseDecayThreshold then
		self.SmoothedMouse=Vector2.new(self.SmoothedMouse.X,0)
	end

	-- Raw input is also decayed toward zero so the controller naturally settles after motion
	-- ends instead of holding the last mouse sample longer than intended.
	self.MouseDelta=self.MouseDelta:Lerp(Vector2.zero,0.35)
	return self.SmoothedMouse
end

function Controller:GetMousePositionOffset(delta)
	local mult=self:GetMultiplier()

	-- Positional sway is intentionally asymmetric:
	-- vertical mouse movement mainly drives pitch-like positional movement,
	-- horizontal mouse movement drives lateral offset and a subtle forward/back feeling.
	-- This gives the camera a more handheld response than using a single uniform scale.
	local px=-delta.Y*self.Settings.SwayPositionY*mult
	local py=-delta.X*self.Settings.SwayPositionX*mult
	local pz=delta.X*self.Settings.SwayPositionZ*mult
	return Vector3.new(px,py,pz)
end

function Controller:GetMouseRotationOffset(delta)
	local mult=self:GetMultiplier()

	-- Rotation is separated from positional sway because those motions communicate different
	-- kinds of weight. Position makes the camera feel displaced in space; rotation makes it
	-- feel like it is being turned. Blending both produces a stronger illusion than either alone.
	local rx=delta.Y*self.Settings.RotationPitch*mult
	local ry=delta.X*self.Settings.RotationYaw*mult
	local rz=-delta.X*self.Settings.RotationRoll*mult
	return Vector3.new(rx,ry,rz)
end

function Controller:GetIdleOffset(dt)
	local currentTime=time()
	local sinceInput=currentTime-self.LastInputTime

	-- Idle breathing/sway is suppressed immediately after mouse movement so it does not compete
	-- with active player input. Once the user has been still long enough, idle motion fades back
	-- in through its own spring instead of appearing abruptly.
	if sinceInput<0.08 then
		self.IdleSpring:SetTarget(Vector3.zero)
		return self.IdleSpring:Update(dt)
	end

	-- Different sine frequencies are used on each axis so the pattern does not look perfectly
	-- mechanical or loop too obviously. The goal is a subtle “alive” motion, not a repetitive bob.
	local wave=currentTime*self.Settings.IdleFrequency
	local x=math.sin(wave)*self.Settings.IdleAmplitudeX
	local y=math.cos(wave*1.3)*self.Settings.IdleAmplitudeY
	local z=math.sin(wave*0.7)*self.Settings.IdleAmplitudeZ

	self.IdleSpring:SetTarget(Vector3.new(x,y,z)*self:GetMultiplier())
	return self.IdleSpring:Update(dt)
end

function Controller:GetFovTarget(deltaMagnitude)
	-- FOV kick is derived from input magnitude rather than movement speed so the lens response
	-- tracks camera intensity directly. This makes aggressive mouse movement feel slightly more
	-- energetic without needing a separate sprint or movement subsystem.
	local kick=math.clamp(deltaMagnitude*self.Settings.FovKickScale,0,self.Settings.MaxFov-self.Settings.MinFov)
	return self.Settings.MinFov+kick
end

function Controller:UpdateFov(deltaMagnitude)
	local target=self:GetFovTarget(deltaMagnitude)

	-- FOV is smoothed the same way as the other effects so the lens expansion feels responsive
	-- but not abrupt. Hard-setting the FOV every frame would make even small changes feel harsh.
	camera.FieldOfView=camera.FieldOfView+(target-camera.FieldOfView)*self.Settings.FovSmooth
end

function Controller:ApplyRecoil(profileName)
	local profile=self.RecoilProfiles[profileName]
	if not profile then
		return
	end

	self.LastRecoilName=profileName

	-- Recoil injects force into the springs instead of assigning fixed positions. That means the
	-- recoil response naturally blends with whatever motion the camera already has and settles
	-- using the same physical language as the rest of the controller.
	self.RecoilSpring:Shove(profile.Kick)
	self.RotationSpring:Shove(profile.Rot)
	self.RollSpring:Shove(Vector3.new(0,0,profile.Rot.Z))
end

function Controller:UpdateSway(dt,delta)
	local target=self:GetMousePositionOffset(delta)
	self.SwaySpring:SetTarget(target)
	return self.SwaySpring:Update(dt)
end

function Controller:UpdateRotation(dt,delta)
	local target=self:GetMouseRotationOffset(delta)
	self.RotationSpring:SetTarget(target)
	return self.RotationSpring:Update(dt)
end

function Controller:UpdateRoll(dt,delta)
	-- Roll is broken into its own spring rather than being fully absorbed into the main rotation
	-- spring so side tilt can have a different weight and settling behavior from pitch/yaw.
	local target=Vector3.new(0,0,-delta.X*self.Settings.RotationRoll*0.6*self:GetMultiplier())
	self.RollSpring:SetTarget(target)
	return self.RollSpring:Update(dt)
end

function Controller:UpdateRecoil(dt)
	-- The recoil target is continuously reduced toward zero so recoil always tries to return home
	-- after each impulse. The spring then smooths that return rather than snapping it closed.
	self.RecoilSpring.Target*=self.Settings.RecoilReturn
	return self.RecoilSpring:Update(dt)
end

function Controller:ComputeOffset(dt)
	local delta=self:GetSmoothedMouse()

	-- The order here matters because each term represents a different layer of motion:
	-- sway/rotation respond to current input,
	-- recoil adds temporary kick,
	-- roll adds extra lateral character,
	-- idle fills quiet moments.
	--
	-- They are computed separately, then composed into one final camera-space transform.
	local sway=self:UpdateSway(dt,delta)
	local rot=self:UpdateRotation(dt,delta)
	local recoil=self:UpdateRecoil(dt)
	local roll=self:UpdateRoll(dt,delta)
	local idle=self:GetIdleOffset(dt)

	-- Positional effects are combined first, then converted into a translation CFrame.
	-- Rotational effects are combined per-axis so recoil can slightly influence pitch
	-- while roll remains independently tunable.
	local pos=sway+recoil+idle
	local rx=rot.X+recoil.X*0.10
	local ry=rot.Y
	local rz=rot.Z+roll.Z

	return CFrame.new(pos)*CFrame.Angles(rx,ry,rz),delta
end

function Controller:CreateLine(parent,name,positionY,textSize)
	-- Debug labels are generated through a helper so the overlay can be built consistently
	-- without duplicating UI setup code for every row.
	local label=Instance.new("TextLabel")
	label.Name=name
	label.Size=UDim2.new(1,-12,0,20)
	label.Position=UDim2.new(0,6,0,positionY)
	label.BackgroundTransparency=1
	label.TextXAlignment=Enum.TextXAlignment.Left
	label.Font=Enum.Font.Gotham
	label.TextSize=textSize or 14
	label.TextColor3=Color3.new(1,1,1)
	label.Text=""
	label.Parent=parent
	return label
end

function Controller:RefreshDebugColors()
	if not self.DebugFrame then
		return
	end

	-- The background tint reflects whether the controller is active so the overlay communicates
	-- system state immediately without requiring the user to read the text.
	if self.Enabled then
		self.DebugFrame.BackgroundColor3=Color3.fromRGB(30,30,30)
	else
		self.DebugFrame.BackgroundColor3=Color3.fromRGB(55,20,20)
	end
end

function Controller:CreateDebug()
	local gui=Instance.new("ScreenGui")
	gui.Name="MouseCameraDebug"
	gui.ResetOnSpawn=false
	gui.Enabled=self.ShowDebug
	gui.Parent=player:WaitForChild("PlayerGui")
	self.DebugGui=gui

	local frame=Instance.new("Frame")
	frame.Name="Main"
	frame.Size=UDim2.new(0,320,0,190)
	frame.Position=UDim2.new(0,20,0,20)
	frame.BackgroundTransparency=self.Settings.DebugTransparency
	frame.BorderSizePixel=0
	frame.Parent=gui
	self.DebugFrame=frame

	local corner=Instance.new("UICorner")
	corner.CornerRadius=UDim.new(0,12)
	corner.Parent=frame

	local stroke=Instance.new("UIStroke")
	stroke.Thickness=1
	stroke.Transparency=0.35
	stroke.Parent=frame

	local title=self:CreateLine(frame,"Title",8,16)
	title.Font=Enum.Font.GothamBold
	title.Text="Mouse Camera Controller"

	local line1=self:CreateLine(frame,"Line1",38,14)
	local line2=self:CreateLine(frame,"Line2",60,14)
	local line3=self:CreateLine(frame,"Line3",82,14)
	local line4=self:CreateLine(frame,"Line4",104,14)
	local line5=self:CreateLine(frame,"Line5",126,14)
	local line6=self:CreateLine(frame,"Line6",148,13)

	self.DebugLines={line1,line2,line3,line4,line5,line6}

	self:RefreshDebugColors()
end

function Controller:UpdateDebug(delta)
	if not self.ShowDebug then
		return
	end
	if not self.DebugLines[1] then
		return
	end

	-- The debug overlay is focused on tuning-critical values: controller state, filtered input,
	-- sensitivity, inversion, FOV, and the last recoil preset. These are the values most useful
	-- when verifying that the controller is behaving as intended.
	self.DebugLines[1].Text="Enabled: "..tostring(self.Enabled).." | Aim: "..tostring(self.Aiming)
	self.DebugLines[2].Text="Mouse: "..string.format("X %.2f | Y %.2f",delta.X,delta.Y)
	self.DebugLines[3].Text="Sensitivity: "..string.format("%.4f",self.Settings.SwayPositionX)
	self.DebugLines[4].Text="InvertX: "..tostring(self.Settings.InvertX).." | InvertY: "..tostring(self.Settings.InvertY)
	self.DebugLines[5].Text="FOV: "..string.format("%.2f",camera.FieldOfView).." | Recoil: "..self.LastRecoilName
	self.DebugLines[6].Text="E Toggle | Q/R/T Recoil | Z Aim | [ ] Sens | F3 Debug"
end

function Controller:BindLoop()
	RunService:BindToRenderStep("KyleMouseCameraController",Enum.RenderPriority.Camera.Value+1,function(dt)
		if self.Destroyed then
			return
		end

		if not self.Enabled then
			-- Even while disabled we still update the debug overlay and gently move FOV back
			-- toward its resting value so the camera returns to a clean baseline.
			self:UpdateFov(0)
			self:UpdateDebug(Vector2.zero)
			return
		end

		if not self.Character or not self.Head or not self.Root then
			return
		end

		-- The controller samples the current camera after Roblox has done its normal camera work,
		-- then applies an additive offset. Using Camera priority + 1 ensures this script decorates
		-- the final camera instead of fighting the default controller earlier in the frame.
		local base=camera.CFrame
		local offset,delta=self:ComputeOffset(dt)
		camera.CFrame=base*offset

		self:UpdateFov(delta.Magnitude)
		self:UpdateDebug(delta)
	end)
end

function Controller:Destroy()
	if self.Destroyed then
		return
	end

	self.Destroyed=true
	RunService:UnbindFromRenderStep("KyleMouseCameraController")
	self:DisconnectAll()

	-- UI is explicitly destroyed on cleanup so the controller does not leave behind orphaned
	-- debug elements after the script is replaced, reloaded, or intentionally shut down.
	if self.DebugGui then
		self.DebugGui:Destroy()
		self.DebugGui=nil
	end
end

--//==================================================
--// Boot
--//==================================================

-- Construction is kept to one line so the script behaves like a self-contained module instance:
-- define the object, configure its dependencies, then start it immediately.
local controller=Controller.new()
