--[[
	Documentation;

	*IMPORTANT*
	You cannot edit a projectile in this system using normal means.
	You can only create a projectile and then delete it unless there is
	a built-in function to edit it in some way.

	The proxy class provides ways to edit the projectile even during runtime,
	attempting to edit this proxy class without using the provided functions will
	result in nothing happening except miss-informed properties.
]]

local EventClassModule = require(script.Parent.Parent.Classes.Event)
local PromiseClassModule = require(script.Parent.Parent.Classes.Promise)

local GetRemoteFunction = require(script.GetRemote)
local ProjectileUpdateEvent = GetRemoteFunction('ProjectileUpdateEvent', 'BindableEvent')

local ThreaderModule = script.Threader
ThreaderModule.BaseThread.RemoteModule.Value = script.GetRemote
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

local ProjectileIdToProxyClass = {}

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
	}, ProxyClass)

	ProjectileIdToProxyClass[projectileId] = proxySelf

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

function ProxyClass:SetOnRayHitResolver(callback)
	self.OnRayHitResolver = callback
	ProjectileUpdateEvent:Fire(self.ID, 'OnRayHitResolver', callback)
end

function ProxyClass:SetRaycastParams(newRaycastParams)
	self.RaycastParams = newRaycastParams
	ProjectileUpdateEvent:Fire(self.ID, 'RaycastParams', newRaycastParams)
end

function ProxyClass:Start()
	ProjectileUpdateEvent:Fire(self.ID, 'Active', true)
end

function ProxyClass:Pause()
	ProjectileUpdateEvent:Fire(self.ID, 'Active', false)
end

function ProxyClass:Destroy()
	ProjectileUpdateEvent:Fire(self.ID, 'Destroyed', true)
end

function ProxyClass:Await()
	return self.CompletionPromise:await()
end

-- // Module // --
local Module = {}

function Module:SetGlobalAcceleration( accelerationVector )
	ThreaderModule:PushModuleFunctionCall('SetGlobalAcceleration', accelerationVector)
end

function Module:SetGlobalTimeScale( newTimeScale )
	ThreaderModule:PushModuleFunctionCall('SetGlobalTimeScale', newTimeScale)
end

function Module:CreateProjectile( Origin, Velocity, OnRayHitResolver )
	if typeof(OnRayHitResolver) ~= 'function' then
		OnRayHitResolver = DefaultOnRayHitResolver
	end

	local EventSignalPropertyList = {'OnHitEvent', 'OnPhysicsStepEvent', 'OnTerminateEvent'}
	ProjectileUpdateEvent.Event:Connect(function(projectileId, key, ...)
		local proxy = ProjectileIdToProxyClass[ projectileId ]
		if proxy and table.find(EventSignalPropertyList, key) then
			proxy[key]:Fire(...)
		end
	end)

	local actorId, projectileId = ThreaderModule:PushProjectile( Origin, Velocity, OnRayHitResolver )

	local proxyProjectile = ProxyClass.New(actorId, projectileId)

	proxyProjectile.CompletionPromise = PromiseClassModule.new(function(_, _)
		local connection; connection = proxyProjectile.OnTerminateEvent:Connect(function(projectileData)
			connection:Disconnect()
			PromiseClassModule.resolve(projectileData)
		end)
	end)

	-- return projectile proxy
	return proxyProjectile
end

return Module
