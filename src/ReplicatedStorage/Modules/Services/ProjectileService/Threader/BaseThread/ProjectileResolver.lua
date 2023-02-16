local RunService = game:GetService('RunService')

local ActorInstance = script.Parent
local ActorId = ActorInstance.Name

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local VisualizersModule = require(ReplicatedStorage:WaitForChild('Modules'):WaitForChild('Utility'):WaitForChild('Visualizers'))

local CreateProjectileEvent = ActorInstance.CreateProjectile.Value
local ProjectileUpdateEvent = ActorInstance.UpdateEvent.Value
local ThreaderFunctionRequest = ActorInstance.ThreaderRequest.Value
local function ResolveFunctionFromHost(func, ...)
	local _, err = pcall(func)
	-- if it is not a function from a different vm, run normally.
	if not string.find(err, 'Lua VM') then
		return func(...)
	end
	-- otherwise request threader for function return
	return ThreaderFunctionRequest:Invoke(func, ...)
end

local STEP_ITERATIONS = 6
local GLOBAL_TIME_SCALE = 0.8
local GLOBAL_ACCELERATION = -Vector3.new( 0, workspace.Gravity * 0.15, 0 )
local ActiveProjectileClasses = {}

local NEGATIVE_RAY_EPSILON_LENGTH = 0.1
local MAX_NEGATIVE_RAY_THREASHOLD = 20

local DefaultRayParams = RaycastParams.new()
DefaultRayParams.FilterType = Enum.RaycastFilterType.Whitelist
DefaultRayParams.IgnoreWater = true

local REFLECTION_LOSS_MULTIPLIER = 0.8
local MaterialPenetrationCostMatrix = {
	Default = 11,

	[Enum.Material.Metal] = 20,
	[Enum.Material.Wood] = 12,
	[Enum.Material.Plastic] = 7,
}

-- // Miscellaneous Functions // --
-- return a different value; 0=keep going, 1=penetrate, 2=reflect, 3=stop
local function DefaultOnRayHit( projectileData )
	return 3 -- stop on hit by default
end

local ExitPointRaycastParams = RaycastParams.new()
ExitPointRaycastParams.FilterType = Enum.RaycastFilterType.Whitelist
ExitPointRaycastParams.IgnoreWater = true
local function FindRayExitPointFromInstance(Start, Direction, TargetInstance)
	local _origin = Start
	local rayresult = nil
	ExitPointRaycastParams.FilterDescendantsInstances = {TargetInstance}
	while (not rayresult) and (_origin - Start).Magnitude < MAX_NEGATIVE_RAY_THREASHOLD do
		Start += Direction.Unit * NEGATIVE_RAY_EPSILON_LENGTH
		rayresult = workspace:Raycast(Start, -Direction.Unit * NEGATIVE_RAY_EPSILON_LENGTH, ExitPointRaycastParams)
		if rayresult and rayresult.Instance then
			return rayresult.Position, (rayresult.Position - Start).Magnitude
		end
	end
	return false, Direction.Magnitude
end

-- // Physics Functions // --
local function GetPositionAtTime(time: number, origin: Vector3, initialVelocity: Vector3, acceleration: Vector3): Vector3
	local t2 = math.pow(time, 2)
	local force = Vector3.new(acceleration.X * t2, acceleration.Y * t2, acceleration.Z * t2 ) / 2
	return origin + (initialVelocity * time) + force
end

-- A variant of the function above that returns the velocity at a given point in time.
local function GetVelocityAtTime(time: number, initialVelocity: Vector3, acceleration: Vector3): Vector3
	return initialVelocity + (acceleration * time)
end

-- // Class // --
local BaseProjectile = {}
BaseProjectile.__index = BaseProjectile

function BaseProjectile.New(projectileId, OriginPosition, Velocity, resolverFunction)
	local self = setmetatable({
		projectileId = projectileId,

		Active = false,
		TimeElapsed = 0,
		DelayTime = 0,
		Lifetime = 5,

		Position = OriginPosition,
		Velocity = Velocity,
		Acceleration = Vector3.new(),
		LastRaycastValue = false,

		OnRayHit = resolverFunction or DefaultOnRayHit,

		_initPosition = OriginPosition,
		_initVelocity = Velocity,
		RaycastParams = DefaultRayParams,

		DebugVisuals = false, -- visualize with beams
		DebugData = false, -- do we store DebugStep data
		DebugSteps = {}, -- DebugStep data (projectile path with info)

		IsUpdating = false,
		Destroyed = false,
	}, BaseProjectile)

	table.insert(ActiveProjectileClasses, self)

	return self
end

function BaseProjectile:Update(deltaTime)
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
	local raycastResult = workspace:Raycast( self.Position, rayDirection, self.RaycastParams or DefaultRayParams )

	if self.DebugVisuals then
		task.synchronize()
		local Point = Instance.new('Attachment')
		Point.Visible = false
		Point.WorldPosition = self.Position
		Point.Parent = workspace.Terrain
		VisualizersModule:Beam(
			self.Position,
			self.Position + rayDirection,
			4,
			{ Color = ColorSequence.new(Color3.new(1, 1, 1))
		})
		task.desynchronize()
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
		ProjectileUpdateEvent:Fire(self.projectileId, stepData)
		task.spawn(self.OnRayUpdated, self, stepData)
	end

	if killProjectile then
		self:Destroy()
	end
end

-- // Module // --
local Module = {}

function Module:IsActorId(actorId)
	return ActorInstance.Name == actorId
end

function Module:CreateProjectile(projectileId, origin, velocity, resolverFunction)
	local projectileClass = BaseProjectile.New(projectileId, origin, velocity, resolverFunction)

	return projectileClass.projectileId
end

function Module:Start()

	CreateProjectileEvent.Event:Connect(function(actorId, projectileId, origin, velocity, resolverFunction)
		if not Module:IsActorId(actorId) then
			return
		end
		Module:CreateProjectile(projectileId, origin, velocity, resolverFunction)
	end)

	RunService.Heartbeat:ConnectParallel(function(deltaTime)
		deltaTime *= Module.GLOBAL_TIME_SCALE

		local index = 1
		while index <= #ActiveProjectileClasses do
			local projectileClass = ActiveProjectileClasses[index]
			if projectileClass:IsDestroyed() or projectileClass.ERRORED then
				table.remove(ActiveProjectileClasses, index)
			else
				if not projectileClass.IsUpdating then
					projectileClass.IsUpdating = true
					-- synchronize?
					task.defer(function()
						projectileClass:Update(deltaTime)
						projectileClass.IsUpdating = false
					end)
					-- desynchronize?
				end
				index += 1
			end
		end
	end)

end

function Module:Init()

end

return Module
