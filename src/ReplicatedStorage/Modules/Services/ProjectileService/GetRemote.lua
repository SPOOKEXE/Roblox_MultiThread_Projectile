
local function FindRemoteOfNameAndClass(remoteName, className)
	for _, remoteObject in ipairs( script:GetChildren() ) do
		if remoteObject.Name == remoteName and remoteObject.ClassName == className then
			return remoteObject
		end
	end
end

local function FindRemoteOtherwiseCreate(remoteName, className)
	local Remote = FindRemoteOfNameAndClass(remoteName, className)
	if not Remote then
		Remote = Instance.new(className)
		Remote.Name = remoteName
		Remote.Parent = script
	end
	return Remote
end

return FindRemoteOtherwiseCreate
