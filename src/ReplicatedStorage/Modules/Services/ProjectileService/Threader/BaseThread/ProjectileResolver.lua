local RunService = game:GetService('RunService')

local ActorInstance = script.Parent
local ActorId = ActorInstance.Name

local CreateProjectileEvent = script.Parent.CreateProjectile.Value
local ProjectileUpdateEvent = script.Parent.UpdateEvent.Value
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

local DefaultRayParams = RaycastParams.new()
DefaultRayParams.FilterType = Enum.RaycastFilterType.Whitelist
DefaultRayParams.IgnoreWater = true

local ActiveProjectileClasses = {}

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

		OnRayHit = resolverFunction,

		_initPosition = OriginPosition,
		_initVelocity = Velocity,
		RaycastParams = DefaultRayParams,

		DebugVisuals = false, -- visualize with beams
		DebugData = false, -- do we store DebugStep data
		DebugSteps = {}, -- DebugStep data (projectile path with info)

		IsUpdating = false,
		Destroyed = false,
	}, BaseProjectile)

	return self
end

-- // Module // --
local Module = { GLOBAL_TIME_SCALE = 1 }

function Module:IsActorId(actorId)
	return ActorInstance.Name == actorId
end

function Module:CreateProjectile(projectileId, origin, velocity, resolverFunction)

end

function Module:Start()

	CreateProjectileEvent.Event:Connect(function(actorId, projectileId, origin, velocity, resolverFunction)
		if not Module:IsActorId(actorId) then
			return
		end
		Module:CreateProjectile(projectileId, origin, velocity, resolverFunction)
	end)

	RunService.Heartbeat:Connect(function(deltaTime)
		deltaTime *= Module.GLOBAL_TIME_SCALE

		local index = 1
		while index <= #ActiveProjectileClasses do
			local projectileClass = ActiveProjectileClasses[index]
			if projectileClass:IsDestroyed() or projectileClass.ERRORED then
				table.remove(ActiveProjectileClasses, index)
			else
				if not projectileClass.IsUpdating then
					projectileClass.IsUpdating = true
					task.defer(function()
						projectileClass:Update(deltaTime)
						projectileClass.IsUpdating = false
					end)
				end
				index += 1
			end
		end
	end)

end

function Module:Init()

end

return Module
