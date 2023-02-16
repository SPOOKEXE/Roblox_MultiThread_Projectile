local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local RemoteService = require(script.Parent.RemoteService)
local BulletVisualEvent = RemoteService:GetRemote('BulletVisualEvent', 'RemoteEvent', false)

local EventClass = require(script.Parent.Parent.Classes.Event)
local Visualizers = require(script.Parent.Parent.Utility.Visualizers)

local ActiveProjectileClasses = {}

local STEP_ITERATIONS = 6
local GLOBAL_TIME_SCALE = 0.8
local GLOBAL_ACCELERATION = -Vector3.new( 0, workspace.Gravity * 0.15, 0 )



local NEGATIVE_RAY_EPSILON_LENGTH = 0.1
local MAX_NEGATIVE_RAY_THREASHOLD = 20

local MaterialPenetrationCostMatrix = {
	Default = 11,

	[Enum.Material.Metal] = 20,
	[Enum.Material.Wood] = 12,
	[Enum.Material.Plastic] = 7,
}

-- // Class // --
local BaseProjectileClass = {}
BaseProjectileClass.__index = BaseProjectileClass

function BaseProjectileClass.New( OriginPosition, Velocity )
	local self = setmetatable({
		Active = false,
		TimeElapsed = 0,
		DelayTime = 0,
		Lifetime = 5,

		Position = OriginPosition,
		Velocity = Velocity,
		Acceleration = Vector3.new(),
		LastRaycastValue = false,

		RayHitEvent = EventClass.New(),
		RayTerminatedEvent = EventClass.New(),

		OnRayHit = defaultOnRayHit,
		OnRayUpdated = false,
		OnProjectileTerminated = false,

		UserData = { UUID = HttpService:GenerateGUID(false), },
		_initPosition = OriginPosition,
		_initVelocity = Velocity,
		RaycastParams = defaultRaycastParams,

		DebugVisuals = false, -- visualize with beams
		DebugData = false, -- do we store DebugStep data
		DebugSteps = {}, -- DebugStep data (projectile path with info)

		IsUpdating = false,
		Destroyed = false,
	}, BaseProjectileClass)
	self:Update(0)
	return self
end

function BaseProjectileClass:Update(deltaTime)
	
end

function BaseProjectileClass:SetActive( isActive )
	self.Active = (isActive==true)
end

function BaseProjectileClass:SetRayOnHitFunction( func )
	if typeof(func) == 'function' then
		self.OnRayHit = func
	end
end

function BaseProjectileClass:SetTerminatedFunction( func )
	if typeof(func) == 'function' then
		self.OnProjectileTerminated = func
	end
end

function BaseProjectileClass:SetUpdatedFunction( func )
	if typeof(func) == 'function' then
		self.OnRayUpdated = func
	end
end

function BaseProjectileClass:AddAccelerate( acceleration : Vector3 )
	self.Acceleration += acceleration
end

function BaseProjectileClass:SetAcceleration( acceleration : Vector3 )
	self.Acceleration = acceleration
end

function BaseProjectileClass:IsDestroyed()
	return self.Destroyed
end

function BaseProjectileClass:Destroy()
	if not self:IsDestroyed() then
		if self.OnProjectileTerminated then
			task.spawn(self.OnProjectileTerminated, self)
		end
	end
	self.Destroyed = true
end

function BaseProjectileClass:AddToGlobalResolver()
	-- if it is not within the global resolver, add it
	if not self:IsInGlobalResolver() then
		table.insert(ActiveProjectileClasses, self)
	end
end

function BaseProjectileClass:RemoveFromGlobalResolver()
	-- remove all occurances of this projectile
	local index = table.find(ActiveProjectileClasses, self)
	while index do
		table.remove(ActiveProjectileClasses, index)
		index = table.find(ActiveProjectileClasses, self)
	end
end

function BaseProjectileClass:IsInGlobalResolver()
	-- returns the index of the projectile in the global resolver
	-- if it is not within the global resolver, returns nil
	return table.find(ActiveProjectileClasses, self)
end

-- // Module // --
local Module = {}

Module.BaseProjectileClass = BaseProjectileClass

function Module:SetGlobalAcceleration( AccelerationVector3 )
	GLOBAL_ACCELERATION = AccelerationVector3
end

function Module:SetGlobalTimeScale( newTimeScale )
	GLOBAL_TIME_SCALE = newTimeScale
end

function Module:SetStepIterations( newCount )
	STEP_ITERATIONS = newCount
end

function Module:DisposeProjectileFromUUID( projectileUUID )
	for _, projectileData in ipairs( ActiveProjectileClasses ) do
		if not projectileData.UserData then
			continue
		end
		if projectileData.UserData.UUID == projectileUUID then
			projectileData:Destroy()
			break
		end
	end
end

function Module:CreateBulletProjectile( LocalPlayer, OriginVector, VelocityVector )
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	raycastParams.IgnoreWater = true
	raycastParams.FilterDescendantsInstances = { LocalPlayer.Character }

	local projectileData = BaseProjectileClass.New( OriginVector, VelocityVector )
	projectileData.RaycastParams = raycastParams

	-- 0=keep going, 1=penetrate, 2=reflect, 3=stop
	-- Note: factors; velocity magnitude, figure out penetration depth of object, etc
	projectileData:SetRayOnHitFunction(function( self, raycastResult )
		return 3
	end)

	projectileData:AddToGlobalResolver()

	if RunService:IsServer() then
		BulletVisualEvent:FireAllClients(LocalPlayer, OriginVector, VelocityVector)
	else
		local beamInstance = Visualizers:Beam(
			projectileData._initPosition,
			projectileData._initPosition + (projectileData._initVelocity * 0.01),
			false,
			{ Color = ColorSequence.new(Color3.new(1,1,1)) }
		)

		projectileData:SetTerminatedFunction(function(self)
			beamInstance.Attachment0:Destroy()
			beamInstance.Attachment1:Destroy()
			Visualizers:Attachment( self.Position, 4 )
		end)

		--[[local bounceCounter = 0
		projectileData:SetRayOnHitFunction(function()
			bounceCounter += 1
			if bounceCounter <= 3 then
				return 2 -- bounce of the surface
			end
			return 3 -- 3 = stop at this point
		end)]]

		projectileData:SetRayOnHitFunction( function()
			return 1
		end)

		local LastPosition = projectileData._initPosition
		local timeElapsed = 0
		projectileData:SetUpdatedFunction(function(self, stepData)
			timeElapsed += stepData.DeltaTime
			if timeElapsed < 0.05 then
				return
			end
			timeElapsed = 0

			beamInstance.Attachment0.WorldPosition = LastPosition
			beamInstance.Attachment1.WorldPosition = stepData.AfterPosition
			LastPosition = stepData.AfterPosition
		end)
	end

	return projectileData
end

if RunService:IsClient() then

	BulletVisualEvent.OnClientEvent:Connect(function(LocalPlayer, OriginVector, VelocityVector)
		Module:CreateBulletProjectile( LocalPlayer, OriginVector, VelocityVector )
	end)

end

return Module
