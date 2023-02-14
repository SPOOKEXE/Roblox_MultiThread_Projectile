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

local REFLECTION_LOSS_MULTIPLIER = 0.8
local NEGATIVE_RAY_EPSILON_LENGTH = 0.1
local MAX_NEGATIVE_RAY_THREASHOLD = 20

local MaterialPenetrationCostMatrix = {
	Default = 11,

	[Enum.Material.Metal] = 20,
	[Enum.Material.Wood] = 12,
	[Enum.Material.Plastic] = 7,
}

local defaultRaycastParams = RaycastParams.new()
defaultRaycastParams.FilterType = Enum.RaycastFilterType.Blacklist
defaultRaycastParams.IgnoreWater = true

-- // Physics Functions // --

-- return a different value; 0=keep going, 1=penetrate, 2=reflect, 3=stop
local function defaultOnRayHit( projectileData )
	return 3 -- stop on hit by default
end

local function GetPositionAtTime(time: number, origin: Vector3, initialVelocity: Vector3, acceleration: Vector3): Vector3
	local t2 = math.pow(time, 2)
	local force = Vector3.new(acceleration.X * t2, acceleration.Y * t2, acceleration.Z * t2 ) / 2
	return origin + (initialVelocity * time) + force
end

-- A variant of the function above that returns the velocity at a given point in time.
local function GetVelocityAtTime(time: number, initialVelocity: Vector3, acceleration: Vector3): Vector3
	return initialVelocity + (acceleration * time)
end

local defaultParams = RaycastParams.new()
defaultParams.FilterType = Enum.RaycastFilterType.Whitelist
defaultParams.IgnoreWater = true
local function FindRayExitPointFromInstance(Start, Direction, TargetInstance)
	local _origin = Start
	local rayresult = nil
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Whitelist
	params.FilterDescendantsInstances = {TargetInstance}
	while (not rayresult) and (_origin - Start).Magnitude < MAX_NEGATIVE_RAY_THREASHOLD do
		Start += Direction.Unit * NEGATIVE_RAY_EPSILON_LENGTH
		rayresult = workspace:Raycast(Start, -Direction.Unit * NEGATIVE_RAY_EPSILON_LENGTH, params)
		if rayresult and rayresult.Instance then
			return rayresult.Position, (rayresult.Position - Start).Magnitude
		end
	end
	return false, Direction.Magnitude
end

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
	self.TimeElapsed += deltaTime
	if self.Lifetime and (self.TimeElapsed > self.Lifetime) then
		--warn('Terminate Projectile, Time Elapsed over duration of ' .. tostring( self.Lifetime ))
		self:Destroy()
		return
	end

	if self.DelayTime > 0 then
		self.DelayTime -= deltaTime
		if self.DelayTime > 0 then
			return
		end
	end

	local netAcceleration = (self.Acceleration + GLOBAL_ACCELERATION)
	local nextPosition = GetPositionAtTime( deltaTime, self.Position, self.Velocity, netAcceleration)
	local nextVelocity = GetVelocityAtTime( deltaTime, self.Velocity, netAcceleration)

	local rayDirection = self.Velocity * deltaTime
	local raycastResult = workspace:Raycast( self.Position, rayDirection, self.RaycastParams or defaultRaycastParams )

	if self.DebugVisuals then
		local Point = Instance.new('Attachment')
		Point.Visible = false
		Point.WorldPosition = self.Position
		Point.Parent = workspace.Terrain
		Visualizers:Beam(
			self.Position,
			self.Position + rayDirection,
			4,
			{ Color = ColorSequence.new(Color3.new(1, 1, 1))
		})
	end
	self.LastRaycastValue = raycastResult

	local onRayHitJob = raycastResult and (self.OnRayHit and self.OnRayHit( self, raycastResult )) or 0
	local killProjectile = false

	local beforePosition = self.Position
	local beforeVelocity = self.Velocity
	if onRayHitJob == 0 then
		-- keep going
		self.Position = nextPosition
		self.Velocity = nextVelocity
	elseif onRayHitJob == 1 then
		-- penetration
		local exitPosition, distance = FindRayExitPointFromInstance( beforePosition, beforeVelocity, raycastResult.Instance )

		local canPenetrate, afterVelocity = false, false
		if exitPosition then
			local materialMultiplier = MaterialPenetrationCostMatrix[ raycastResult.Material ] or MaterialPenetrationCostMatrix.Default
			canPenetrate, afterVelocity = self:CanPenetrateCalculation( beforeVelocity, distance, materialMultiplier )
		end

		if canPenetrate then
			local delayTime = (distance / beforeVelocity.Magnitude)
			self.DelayTime += delayTime
			self.Position = exitPosition
			self.Velocity = afterVelocity
		else
			self.Position = raycastResult.Position
			self.Velocity = Vector3.new()
			killProjectile = true
		end
	elseif onRayHitJob == 2 then
		-- ricochet (reflect)
		local surfaceNormal = raycastResult.Normal
		local incidentDirection = self.Velocity.Unit
		local reflectedDirection = (incidentDirection - (2 * incidentDirection:Dot(surfaceNormal) * surfaceNormal))
		self.Position = raycastResult.Position
		self.Velocity = reflectedDirection * self.Velocity.Magnitude * REFLECTION_LOSS_MULTIPLIER
	else
		-- stop
		self.Position = raycastResult and raycastResult.Position or nextPosition
		self.Velocity = Vector3.new()
		killProjectile = true
	end

	local stepData = {
		DeltaTime = deltaTime,
		RayHitJob = onRayHitJob,
		TimeElapsed = self.TimeElapsed,
		BeforePosition = beforePosition,
		BeforeVelocity = beforeVelocity,
		AfterPosition = self.Position,
		AfterVelocity = self.Velocity,
	}

	if self.DebugData then
		table.insert(self.DebugSteps, stepData)
	end
	if self.OnRayUpdated then
		task.spawn(self.OnRayUpdated, self, stepData)
	end

	if killProjectile then
		self:Destroy()
	end
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
