local RunService = game:GetService('RunService')

--[[
	Documentation;

	*IMPORTANT*
	You cannot edit a projectile in this system using normal means.
	You can only create a projectile and then delete it unless there is
	a built-in function to edit it in some way.
]]

local EventClassModule = require(script.Parent.Parent.Classes.Event)
local PromiseClassModule = require(script.Parent.Parent.Classes.Promise)

local ProjectileUpdateEvent = script.Parent.ProjectileUpdateEvent
local CreateProjectileFunction = script.Parent.CreateProjectileFunction
local ResolveFunctionResponse = script.Parent.ResolveFunctionResponse
ResolveFunctionResponse.OnInvoke = function(func, ...)
	return func(...) -- attempt to call the function in this Lua VM.
end

local ThreaderModule = script.Threader
ThreaderModule.BaseThread.ResolveFunction.Value = ResolveFunctionResponse
ThreaderModule.BaseThread.UpdateEvent.Value = ProjectileUpdateEvent
ThreaderModule.BaseThread.CreateProjectile.Value = CreateProjectileFunction
ThreaderModule = require(ThreaderModule)

local DefaultRayParams = RaycastParams.new()
DefaultRayParams.FilterType = Enum.RaycastFilterType.Whitelist
DefaultRayParams.IgnoreWater = true

local function DefaultOnRayHitResolver()
	return 3 -- stop
end

local function DefaultPenetrateResolver(incomingVelocity, distance, materialMultiplier)
	local velocityAfterPenetrationCost = 0
	local materialFrictionMultiplier = math.clamp(1/(distance * materialMultiplier), 0, 1)
	if incomingVelocity.Magnitude * materialFrictionMultiplier >= incomingVelocity.Magnitude then
		velocityAfterPenetrationCost = incomingVelocity.Magnitude - (1.5 + distance)
	else
		velocityAfterPenetrationCost = incomingVelocity.Magnitude * materialFrictionMultiplier
	end
	if velocityAfterPenetrationCost < materialMultiplier then
		velocityAfterPenetrationCost = 0
	else
		velocityAfterPenetrationCost = math.clamp(velocityAfterPenetrationCost, 0, incomingVelocity.Magnitude)
	end
	local penetrationVelocity = incomingVelocity.Unit * velocityAfterPenetrationCost
	return (incomingVelocity - penetrationVelocity).Magnitude > 0, penetrationVelocity
end

-- // Proxy Class // --
local ProxyClass = {}
ProxyClass.__index = ProxyClass

function ProxyClass.New(actorId, projectileId)
	local proxySelf = setmetatable({
		actorId = actorId,
		projectileId = projectileId,

		Active = false,

		OnHitEvent = EventClassModule.New(),
		OnPhysicsStepEvent = EventClassModule.New(),
		OnTerminateEvent = EventClassModule.New(),

		OnRayHitResolver = DefaultOnRayHitResolver,
		PenetrationCalculationResolver = DefaultPenetrateResolver,
		RaycastParams = DefaultRayParams,

		CompletionPromise = false,
		Destroyed = false,
	})

	return proxySelf
end

function ProxyClass:GetProjectileId()
	return self.ID
end

function ProxyClass:OnHitCallback(callback)
	return self.OnHitEvent:Connect(callback)
end

function ProxyClass:OnPhysicsStepCallback(callback)
	return self.OnPhysicsStepEvent:Connect(callback)
end

function ProxyClass:OnTerminateCallback(callback)
	return self.OnTerminateEvent:Connect(callback)
end

function ProxyClass:SetOnRayHitCallback(callback)
	ProjectileUpdateEvent:Fire(self.ID, 'OnRayHitCallback', callback)
end

function ProxyClass:SetRaycastParams(newRaycastParams)
	ProjectileUpdateEvent:Fire(self.ID, 'RaycastParams', newRaycastParams)
end

function ProxyClass:Start()
	ProjectileUpdateEvent:Fire(self.ID, 'Active', true)
end

function ProxyClass:Pause()
	ProjectileUpdateEvent:Fire(self.ID, 'Active', false)
end

-- Destroy the projectile - finishes the await promise
function ProxyClass:Destroy()
	ProjectileUpdateEvent:Fire(self.ID, 'Destroyed', true)
end

function ProxyClass:Await()
	-- await the projectile return promise (returns table from actor class)
end

-- // Module // --
local Module = {}

function Module:_GetFinalProjectileData(projectileId, deleteAfter)

end

function Module:CreateProjectile( Origin, Velocity, OnRayHitResolver )
	if typeof(OnRayHitResolver) ~= 'function' then
		OnRayHitResolver = DefaultOnRayHitResolver
	end

	local actorId, projectileId = ThreaderModule:PushProjectile( Origin, Velocity, OnRayHitResolver )

	local proxyProjectile = ProxyClass.New(actorId, projectileId)

	proxyProjectile.CompletionPromise = PromiseClassModule.New(function(_, _)
		local connection; connection = proxyProjectile.OnTerminateEvent:Connect(function()
			connection:Disconnect()
			PromiseClassModule.resolve(Module:_GetFinalProjectileData(projectileId, true))
		end)
	end)

	-- return projectile proxy
	return proxyProjectile
end

return Module
