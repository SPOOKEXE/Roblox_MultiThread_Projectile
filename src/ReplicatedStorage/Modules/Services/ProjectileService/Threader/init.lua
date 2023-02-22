local HttpService = game:GetService("HttpService")
local RunService = game:GetService('RunService')

local GetRemoteFunction = require(script.Parent.GetRemote)
local SharedFunctionCall = GetRemoteFunction('SharedFunctionCallEvent', 'BindableEvent')
local CreateProjectileEvent = GetRemoteFunction('CreateProjectileEvent', 'BindableEvent')

local ResolveFunctionResponse = GetRemoteFunction('ResolveFunctionResponse', 'BindableFunction')
ResolveFunctionResponse.OnInvoke = function(func, ...)
	return func(...) -- attempt to call the function in this Lua VM.
end

local ThreadFolder = Instance.new('Folder')
ThreadFolder.Name = 'ThreadActors'
ThreadFolder.Parent = RunService:IsServer() and game:GetService('ServerScriptService') or game:GetService('Players').LocalPlayer:WaitForChild('PlayerScripts')

local ACTOR_COUNT = 1
local ActorIdsArray = {}

-- // Module // --
local Module = {}

Module.NextActorSelect = 0
for _ = 1, ACTOR_COUNT do
	local actorId = HttpService:GenerateGUID(false)
	local cloneActor = script.BaseThread:Clone()
	cloneActor.Name = actorId
	cloneActor.Parent = ThreadFolder
	table.insert(ActorIdsArray, actorId)
end

function Module:FindNextFreeActorId()
	Module.NextActorSelect += 1
	if Module.NextActorSelect > ACTOR_COUNT then
		Module.NextActorSelect = 1
	end
	return ActorIdsArray[ Module.NextActorSelect ]
end

function Module:PushProjectile( Origin, Velocity, OnHitResolver )
	local actorId = Module:FindNextFreeActorId()
	local projectileId = HttpService:GenerateGUID(false)
	print(actorId, projectileId, Origin, Velocity)
	CreateProjectileEvent:Fire(actorId, projectileId, Origin, Velocity, OnHitResolver)
	return actorId, projectileId
end

function Module:PushModuleFunctionCall(...)
	SharedFunctionCall:Fire(...)
end

return Module
