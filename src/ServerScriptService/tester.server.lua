
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedModules = require(ReplicatedStorage:WaitForChild("Modules"))

local ProjectileService = ReplicatedModules.Services.ProjectileService
local Visualizers = ReplicatedModules.Utility.Visualizers

local function CreateBulletProjectile( OriginVector, VelocityVector )
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	raycastParams.IgnoreWater = true
	raycastParams.FilterDescendantsInstances = {}

	local proxyProjectile = ProjectileService:CreateProjectile( OriginVector, VelocityVector, function()
		return 0
	end )

	proxyProjectile:SetRaycastParams(raycastParams)

	local beamInstance = Visualizers:Beam( OriginVector, OriginVector + (VelocityVector * 0.01), false, { Color = ColorSequence.new(Color3.new(1,1,1)) } )

	proxyProjectile:OnTerminateCallback(function(self)
		beamInstance.Attachment0:Destroy()
		beamInstance.Attachment1:Destroy()
		Visualizers:Attachment( self.Position, 4 )
	end)

	-- 0=keep going, 1=penetrate, 2=reflect, 3=stop
	local bounceCounter = 0
	proxyProjectile:SetOnRayHitResolver(function()
		bounceCounter += 1
		if bounceCounter <= 3 then
			return 2 -- bounce of the surface
		end
		return 3 -- 3 = stop at this point
	end)

	local LastPosition = OriginVector
	local timeElapsed = 0
	proxyProjectile:OnPhysicsStepCallback(function(stepData)
		timeElapsed += stepData.DeltaTime
		if timeElapsed < 0.05 then
			return
		end
		timeElapsed = 0

		beamInstance.Attachment0.WorldPosition = LastPosition
		beamInstance.Attachment1.WorldPosition = stepData.AfterPosition
		LastPosition = stepData.AfterPosition
	end)

	proxyProjectile:Start()

	local completedProjectileData = proxyProjectile:Await()
	print( completedProjectileData )
end

while true do
	local r = Vector3.new( math.random(-20, 20)/10, 0, math.random(-20, 20)/10 ).Unit
	CreateBulletProjectile( Vector3.new(0, 15, 0), r )
	task.wait(0.05)
end
