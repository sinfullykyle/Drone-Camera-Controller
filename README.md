A Roblox camera recoil system that adds dynamic bounce while walking and in first person. Toggle the effect with the E key. Includes a recoil test feature for simulating strong camera kick.

## Features
- Toggle recoil (E key)
- Movement-based camera bounce
- First-person support
- Recoil test function

## Usage
Place the script in a LocalScript inside StarterPlayerScripts.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")

local player=Players.LocalPlayer
local camera=workspace.CurrentCamera

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
function Spring:Update(dt)
	local offset=self.Target-self.Position
	self.Velocity+=offset*self.Speed*dt
	self.Velocity*=math.max(0,1-self.Damping*dt*10)
	self.Position+=self.Velocity*dt
	return self.Position
end
function Spring:Reset(v)
	self.Position=v or Vector3.zero
	self.Target=v or Vector3.zero
	self.Velocity=Vector3.zero
end

local Controller={}
Controller.__index=Controller

function Controller.new()
	local self=setmetatable({},Controller)
	self.Enabled=true
	self.Character=nil
	self.Humanoid=nil
	self.Root=nil
	self.Head=nil
	self.MouseDelta=Vector2.zero
	self.BobTime=0
	self.State="Idle"
	self.SwaySpring=Spring.new(18,0.82,Vector3.zero)
	self.MoveSpring=Spring.new(14,0.84,Vector3.zero)
	self.BobSpring=Spring.new(10,0.86,Vector3.zero)
	self.LandSpring=Spring.new(16,0.8,Vector3.zero)
	self.RecoilSpring=Spring.new(20,0.86,Vector3.zero)
	self.TiltSpring=Spring.new(12,0.85,Vector3.zero)
	self.LastGrounded=true
	self.IsGrounded=true
	self.Settings={
		MouseInfluence=0.0025,
		MoveInfluence=0.03,
		BobFrequencyWalk=10,
		BobAmplitudeWalk=0.09,
		BobFrequencySprint=14,
		BobAmplitudeSprint=0.14,
		StrafeTilt=3.5,
		ForwardTilt=1.2,
		ThirdPersonDistance=12,
	}
	self:BindCharacter()
	self:BindInput()
	self:BindLoop()
	self:CreateDebug()
	return self
end

function Controller:BindCharacter()
	local function setup(char)
		self.Character=char
		self.Humanoid=char:WaitForChild("Humanoid")
		self.Root=char:WaitForChild("HumanoidRootPart")
		self.Head=char:WaitForChild("Head")
		self.BobTime=0
		self.SwaySpring:Reset(Vector3.zero)
		self.MoveSpring:Reset(Vector3.zero)
		self.BobSpring:Reset(Vector3.zero)
		self.LandSpring:Reset(Vector3.zero)
		self.RecoilSpring:Reset(Vector3.zero)
		self.TiltSpring:Reset(Vector3.zero)
	end
	if player.Character then
		setup(player.Character)
	end
	player.CharacterAdded:Connect(setup)
end

function Controller:BindInput()
	UserInputService.InputChanged:Connect(function(input,gpe)
		if gpe then
			return
		end
		if input.UserInputType==Enum.UserInputType.MouseMovement then
			self.MouseDelta=input.Delta
		end
	end)
	UserInputService.InputBegan:Connect(function(input,gpe)
		if gpe then
			return
		end
		if input.KeyCode==Enum.KeyCode.E then
			self.Enabled=not self.Enabled
		end
		if input.KeyCode==Enum.KeyCode.Q then
			self.RecoilSpring:Shove(Vector3.new(-0.6,0,0))
		end
	end)
end

function Controller:GetHorizontalVelocity()
	if not self.Root then
		return Vector3.zero
	end
	local v=self.Root.AssemblyLinearVelocity
	return Vector3.new(v.X,0,v.Z)
end

function Controller:GetLocalVelocity()
	if not self.Root then
		return Vector3.zero
	end
	return self.Root.CFrame:VectorToObjectSpace(self:GetHorizontalVelocity())
end

function Controller:UpdateGrounded()
	if not self.Humanoid or not self.Root then
		return
	end
	local state=self.Humanoid:GetState()
	local grounded=not(state==Enum.HumanoidStateType.Freefall or state==Enum.HumanoidStateType.FallingDown or state==Enum.HumanoidStateType.Jumping)
	self.LastGrounded=self.IsGrounded
	self.IsGrounded=grounded
	if self.IsGrounded and not self.LastGrounded then
		local impact=math.clamp(math.abs(self.Root.AssemblyLinearVelocity.Y)*0.015,0,1.2)
		self.LandSpring:Shove(Vector3.new(0,-impact,0))
	end
end

function Controller:GetMoveState(speed)
	if speed<0.15 then
		return"Idle"
	elseif speed<14 then
		return"Walk"
	else
		return"Sprint"
	end
end

function Controller:GetMouseSway(dt)
	local d=self.MouseDelta
	self.MouseDelta=d:Lerp(Vector3.zero,0.35)
	self.SwaySpring.Target=Vector3.new(-d.Y*self.Settings.MouseInfluence,-d.X*self.Settings.MouseInfluence,d.X*self.Settings.MouseInfluence*0.7)
	return self.SwaySpring:Update(dt)
end

function Controller:GetMovementOffset(dt,localVelocity)
	local x=math.clamp(localVelocity.X*self.Settings.MoveInfluence,-0.35,0.35)
	local z=math.clamp(-localVelocity.Z*0.012,-0.2,0.2)
	self.MoveSpring.Target=Vector3.new(0,x,z)
	return self.MoveSpring:Update(dt)
end

function Controller:GetBob(dt,speed)
	if speed<0.15 or not self.IsGrounded then
		self.BobSpring.Target=Vector3.zero
		return self.BobSpring:Update(dt)
	end
	local freq=self.State=="Sprint" and self.Settings.BobFrequencySprint or self.Settings.BobFrequencyWalk
	local amp=self.State=="Sprint" and self.Settings.BobAmplitudeSprint or self.Settings.BobAmplitudeWalk
	self.BobTime+=dt*freq
	local x=math.cos(self.BobTime*0.5)*amp
	local y=math.abs(math.sin(self.BobTime))*amp
	self.BobSpring.Target=Vector3.new(x,y,0)
	return self.BobSpring:Update(dt)
end

function Controller:GetLanding(dt)
	self.LandSpring.Target*=0.88
	return self.LandSpring:Update(dt)
end

function Controller:GetRecoil(dt)
	self.RecoilSpring.Target*=0.9
	return self.RecoilSpring:Update(dt)
end

function Controller:GetTilt(dt,localVelocity)
	local roll=math.rad(math.clamp(-localVelocity.X*0.08,-1,1)*self.Settings.StrafeTilt)
	local pitch=math.rad(math.clamp(localVelocity.Z*0.03,-1,1)*self.Settings.ForwardTilt)
	self.TiltSpring.Target=Vector3.new(pitch,0,roll)
	return self.TiltSpring:Update(dt)
end

function Controller:ComputeOffset(dt)
	self:UpdateGrounded()
	local worldVelocity=self:GetHorizontalVelocity()
	local speed=worldVelocity.Magnitude
	self.State=self:GetMoveState(speed)
	local localVelocity=self:GetLocalVelocity()
	local sway=self:GetMouseSway(dt)
	local move=self:GetMovementOffset(dt,localVelocity)
	local bob=self:GetBob(dt,speed)
	local land=self:GetLanding(dt)
	local recoil=self:GetRecoil(dt)
	local tilt=self:GetTilt(dt,localVelocity)
	local pos=bob+move+land+recoil+sway
	local rx=tilt.X+sway.X*0.5+recoil.X*0.08
	local ry=sway.Y*0.3
	local rz=tilt.Z+sway.Z
	return CFrame.new(pos)*CFrame.Angles(rx,ry,rz),speed
end

function Controller:BindLoop()
	RunService:BindToRenderStep("KyleCameraEffects",Enum.RenderPriority.Camera.Value+1,function(dt)
		if not self.Enabled then
			return
		end
		if not self.Character or not self.Root or not self.Head then
			return
		end
		local offset,speed=self:ComputeOffset(dt)
		camera.CFrame=camera.CFrame*offset
		self.LastSpeed=speed
	end)
end

function Controller:CreateDebug()
	local gui=Instance.new("ScreenGui")
	gui.Name="CameraEffectDebug"
	gui.ResetOnSpawn=false
	gui.Parent=player:WaitForChild("PlayerGui")
	local frame=Instance.new("Frame")
	frame.Size=UDim2.new(0,280,0,120)
	frame.Position=UDim2.new(0,20,0,20)
	frame.BackgroundTransparency=0.25
	frame.BorderSizePixel=0
	frame.Parent=gui
	local corner=Instance.new("UICorner")
	corner.CornerRadius=UDim.new(0,10)
	corner.Parent=frame
	local title=Instance.new("TextLabel")
	title.Size=UDim2.new(1,0,0,28)
	title.BackgroundTransparency=1
	title.Font=Enum.Font.GothamBold
	title.TextSize=16
	title.TextColor3=Color3.new(1,1,1)
	title.Text="Camera Effects Test"
	title.Parent=frame
	local line1=Instance.new("TextLabel")
	line1.Size=UDim2.new(1,-12,0,22)
	line1.Position=UDim2.new(0,6,0,35)
	line1.BackgroundTransparency=1
	line1.TextXAlignment=Enum.TextXAlignment.Left
	line1.Font=Enum.Font.Gotham
	line1.TextSize=14
	line1.TextColor3=Color3.new(1,1,1)
	line1.Parent=frame
	local line2=Instance.new("TextLabel")
	line2.Size=UDim2.new(1,-12,0,22)
	line2.Position=UDim2.new(0,6,0,59)
	line2.BackgroundTransparency=1
	line2.TextXAlignment=Enum.TextXAlignment.Left
	line2.Font=Enum.Font.Gotham
	line2.TextSize=14
	line2.TextColor3=Color3.new(1,1,1)
	line2.Parent=frame
	local line3=Instance.new("TextLabel")
	line3.Size=UDim2.new(1,-12,0,22)
	line3.Position=UDim2.new(0,6,0,83)
	line3.BackgroundTransparency=1
	line3.TextXAlignment=Enum.TextXAlignment.Left
	line3.Font=Enum.Font.Gotham
	line3.TextSize=14
	line3.TextColor3=Color3.new(1,1,1)
	line3.Text="E toggle | Q recoil test"
	line3.Parent=frame
	RunService.RenderStepped:Connect(function()
		line1.Text="Enabled: "..tostring(self.Enabled).." | State: "..tostring(self.State)
		line2.Text="Speed: "..string.format("%.2f",self.LastSpeed or 0)
	end)
end

local controller=Controller.new()
