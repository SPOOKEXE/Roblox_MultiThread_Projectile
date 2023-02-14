local HttpService = game:GetService("HttpService")
local RunService = game:GetService('RunService')

local ResolveFunctionResponse = script.Parent.ResolveFunctionResponse :: BindableFunction
local ProjectileUpdateEvent = script.Parent.ProjectileUpdateEvent :: BindableEvent
local CreateProjectileFunction = script.Parent.CreateProjectileFunction :: BindableEvent

local ThreadFolder = Instance.new('Folder')
ThreadFolder.Name = 'ThreadActors'
ThreadFolder.Parent = RunService:IsServer() and game:GetService('ServerScriptService') or game:GetService('Players').LocalPlayer:WaitForChild('PlayerScripts')

-- // Module // --
local Module = {}

Module.ACTOR_COUNT = 16
Module.ActorIdsToActors = {}
Module.ActorIdArray = {}

Module.NextActorSelect = 0
for _ = 1, Module.ACTOR_COUNT do
	local actorId = HttpService:GenerateGUID(false)
	local cloneActor = script.BaseThread:Clone()
	cloneActor.Name = actorId
	cloneActor.Parent = ThreadFolder
	Module.ActorIdsToActors[ actorId ] = cloneActor
end

function Module:FindNextFreeActorId()
	Module.NextActorSelect += 1
	if Module.NextActorSelect > Module.ACTOR_COUNT then
		Module.NextActorSelect = 1
	end
	return Module.ActorIdArray[ Module.NextActorSelect ]
end

function Module:PushProjectile( Origin, Velocity, OnHitResolver )
	local actorId = Module:FindNextFreeActorId()
	local projectileId = HttpService:GenerateGUID(false)
	CreateProjectileFunction:Fire(actorId, projectileId, Origin, Velocity, OnHitResolver)
	return actorId, projectileId
end

return Module
