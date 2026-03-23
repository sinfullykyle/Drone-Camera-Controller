--// Services
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local TweenService=game:GetService("TweenService")

--// Player references
local player=Players.LocalPlayer
local camera=workspace.CurrentCamera

--//==================================================
--// Spring
--//==================================================
local Spring={}
Spring.__index=Spring

function Spring.new(speed,damping,initial)
	local self=setmetatable({},Spring)
	self.Speed=speed or 10
	self.Damping=damping or 0.8
	self.Position=initial or Vector3.zero
	self.Velocity=Vector3.zero
	self.Target=initial or Vector3.zero
	return self
end

function Spring:Shove(force)
	self.Velocity+=force
end

function Spring:SetTarget(target)
	self.Target=target
end

function Spring:SetPosition(position)
	self.Position=position
end

function Spring:SetVelocity(velocity)
	self.Velocity=velocity
end

function Spring:Update(dt)
	local offset=self.Target-self.Position
	self.Velocity+=offset*self.Speed*dt
	self.Velocity*=math.max(0,1-self.Damping*dt*10)
	self.Position+=self.Velocity*dt
	return self.Position
end

function Spring:Reset(value)
	self.Position=value or Vector3.zero
	self.Target=value or Vector3.zero
	self.Velocity=Vector3.zero
end

--//==================================================
--// Controller
--//==================================================
local Controller={}
Controller.__index=Controller

function Controller.new()
	local self=setmetatable({},Controller)

	self.Enabled=true
	self.Aiming=false
	self.ShowDebug=true
	self.Destroyed=false

	self.Character=nil
	self.Humanoid=nil
	self.Root=nil
	self.Head=nil

	self.MouseDelta=Vector2.zero
	self.SmoothedMouse=Vector2.zero
	self.LastAppliedOffset=CFrame.new()
	self.LastInputTime=0
	self.LastRecoilName="Light"

	self.SwaySpring=Spring.new(18,0.82,Vector3.zero)
	self.RotationSpring=Spring.new(20,0.84,Vector3.zero)
	self.RecoilSpring=Spring.new(24,0.86,Vector3.zero)
	self.RollSpring=Spring.new(16,0.82,Vector3.zero)
	self.IdleSpring=Spring.new(8,0.9,Vector3.zero)

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

	self.Connections={}
	self.DebugGui=nil
	self.DebugFrame=nil
	self.DebugLines={}

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
		self.Character=char
		self.Humanoid=char:WaitForChild("Humanoid")
		self.Root=char:WaitForChild("HumanoidRootPart")
		self.Head=char:WaitForChild("Head")
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
	if self.Aiming then
		return self.Settings.AimMultiplier
	end
	return self.Settings.NormalMultiplier
end

function Controller:GetSignedMouseDelta(delta)
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
	return Vector2.new(
		math.clamp(delta.X,-self.Settings.MaxMouseDelta,self.Settings.MaxMouseDelta),
		math.clamp(delta.Y,-self.Settings.MaxMouseDelta,self.Settings.MaxMouseDelta)
	)
end

function Controller:RecordMouse(delta)
	local signed=self:GetSignedMouseDelta(delta)
	local clamped=self:ClampMouseDelta(signed)
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
		if input.UserInputType==Enum.UserInputType.MouseButton2 then
			self:ToggleAim(false)
		end
	end)
end

function Controller:AdjustSensitivity(delta)
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
	self.SmoothedMouse=self.SmoothedMouse:Lerp(target,alpha)
	if math.abs(self.SmoothedMouse.X)<self.Settings.MouseDecayThreshold then
		self.SmoothedMouse=Vector2.new(0,self.SmoothedMouse.Y)
	end
	if math.abs(self.SmoothedMouse.Y)<self.Settings.MouseDecayThreshold then
		self.SmoothedMouse=Vector2.new(self.SmoothedMouse.X,0)
	end
	self.MouseDelta=self.MouseDelta:Lerp(Vector2.zero,0.35)
	return self.SmoothedMouse
end

function Controller:GetMousePositionOffset(delta)
	local mult=self:GetMultiplier()
	local px=-delta.Y*self.Settings.SwayPositionY*mult
	local py=-delta.X*self.Settings.SwayPositionX*mult
	local pz=delta.X*self.Settings.SwayPositionZ*mult
	return Vector3.new(px,py,pz)
end

function Controller:GetMouseRotationOffset(delta)
	local mult=self:GetMultiplier()
	local rx=delta.Y*self.Settings.RotationPitch*mult
	local ry=delta.X*self.Settings.RotationYaw*mult
	local rz=-delta.X*self.Settings.RotationRoll*mult
	return Vector3.new(rx,ry,rz)
end

function Controller:GetIdleOffset(dt)
	local currentTime=time()
	local sinceInput=currentTime-self.LastInputTime
	if sinceInput<0.08 then
		self.IdleSpring:SetTarget(Vector3.zero)
		return self.IdleSpring:Update(dt)
	end
	local wave=currentTime*self.Settings.IdleFrequency
	local x=math.sin(wave)*self.Settings.IdleAmplitudeX
	local y=math.cos(wave*1.3)*self.Settings.IdleAmplitudeY
	local z=math.sin(wave*0.7)*self.Settings.IdleAmplitudeZ
	self.IdleSpring:SetTarget(Vector3.new(x,y,z)*self:GetMultiplier())
	return self.IdleSpring:Update(dt)
end

function Controller:GetFovTarget(deltaMagnitude)
	local kick=math.clamp(deltaMagnitude*self.Settings.FovKickScale,0,self.Settings.MaxFov-self.Settings.MinFov)
	return self.Settings.MinFov+kick
end

function Controller:UpdateFov(deltaMagnitude)
	local target=self:GetFovTarget(deltaMagnitude)
	camera.FieldOfView=camera.FieldOfView+(target-camera.FieldOfView)*self.Settings.FovSmooth
end

function Controller:ApplyRecoil(profileName)
	local profile=self.RecoilProfiles[profileName]
	if not profile then
		return
	end
	self.LastRecoilName=profileName
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
	local target=Vector3.new(0,0,-delta.X*self.Settings.RotationRoll*0.6*self:GetMultiplier())
	self.RollSpring:SetTarget(target)
	return self.RollSpring:Update(dt)
end

function Controller:UpdateRecoil(dt)
	self.RecoilSpring.Target*=self.Settings.RecoilReturn
	return self.RecoilSpring:Update(dt)
end

function Controller:ComputeOffset(dt)
	local delta=self:GetSmoothedMouse()
	local sway=self:UpdateSway(dt,delta)
	local rot=self:UpdateRotation(dt,delta)
	local recoil=self:UpdateRecoil(dt)
	local roll=self:UpdateRoll(dt,delta)
	local idle=self:GetIdleOffset(dt)

	local pos=sway+recoil+idle
	local rx=rot.X+recoil.X*0.10
	local ry=rot.Y
	local rz=rot.Z+roll.Z

	return CFrame.new(pos)*CFrame.Angles(rx,ry,rz),delta
end

function Controller:CreateLine(parent,name,positionY,textSize)
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
			self:UpdateFov(0)
			self:UpdateDebug(Vector2.zero)
			return
		end

		if not self.Character or not self.Head or not self.Root then
			return
		end

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
	if self.DebugGui then
		self.DebugGui:Destroy()
		self.DebugGui=nil
	end
end

--//==================================================
--// Boot
--//==================================================
local controller=Controller.new()
