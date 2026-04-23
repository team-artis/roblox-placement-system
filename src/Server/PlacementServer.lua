local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("PlacementShared")
local RemotesFolder = Shared:WaitForChild("Remotes")
local ObjectsFolder = Shared:WaitForChild("Objects")
local SettingsFolder = Shared:WaitForChild("Settings")

local PlaceObjectRemote = RemotesFolder:WaitForChild("PlaceObject")
local DeleteObjectRemote = RemotesFolder:WaitForChild("DeleteObject")

local TOOL_PLACEMENT_ATTRIBUTE = "PlacementSystem"
local TOOL_ORIGINAL_NAME_ATTRIBUTE = "OriginalToolName"
local TOOL_USES_LEFT_ATTRIBUTE = "PlacementUsesLeft"

local placedObjectsByPlayer = {}

local function getPlacementRoot(instance)
	if instance:IsA("Model") then
		return instance.PrimaryPart
	end

	if instance:IsA("BasePart") then
		return instance
	end

	return nil
end

local function getPlayerBackpack(player)
	return player:FindFirstChild("Backpack")
end

local function getEquippedPlacementTool(player)
	local character = player.Character
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute(TOOL_PLACEMENT_ATTRIBUTE) then
			return child
		end
	end

	return nil
end

local function findPlacementTool(player, placementName)
	local function findInContainer(container)
		if not container then
			return nil
		end

		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute(TOOL_PLACEMENT_ATTRIBUTE) == placementName then
				return child
			end
		end

		return nil
	end

	return findInContainer(player.Character) or findInContainer(getPlayerBackpack(player))
end

local function getPlacementSettingsModule(placementName)
	if typeof(placementName) ~= "string" or placementName == "" then
		return nil
	end

	return SettingsFolder:FindFirstChild(placementName)
end

local function getPlacementObjectTemplate(placementName)
	if typeof(placementName) ~= "string" or placementName == "" then
		return nil
	end

	return ObjectsFolder:FindFirstChild(placementName)
end

local function getToolPlacementData(tool)
	if not tool then
		return nil, nil, nil
	end

	local placementName = tool:GetAttribute(TOOL_PLACEMENT_ATTRIBUTE)
	if typeof(placementName) ~= "string" or placementName == "" then
		return nil, nil, nil
	end

	local objectTemplate = getPlacementObjectTemplate(placementName)
	local settingsModule = getPlacementSettingsModule(placementName)

	if not objectTemplate or not settingsModule then
		return nil, nil, nil
	end

	local settings = require(settingsModule)
	return placementName, objectTemplate, settings
end

local function getToolOriginalName(tool)
	local originalName = tool:GetAttribute(TOOL_ORIGINAL_NAME_ATTRIBUTE)

	if typeof(originalName) ~= "string" or originalName == "" then
		originalName = tool.Name
		tool:SetAttribute(TOOL_ORIGINAL_NAME_ATTRIBUTE, originalName)
	end

	return originalName
end

local function getToolUsesLeft(tool, settings)
	local usesLeft = tool:GetAttribute(TOOL_USES_LEFT_ATTRIBUTE)

	if typeof(usesLeft) ~= "number" then
		usesLeft = settings.MaxUses
		tool:SetAttribute(TOOL_USES_LEFT_ATTRIBUTE, usesLeft)
	end

	return usesLeft
end

local function setToolUsesLeft(tool, usesLeft)
	tool:SetAttribute(TOOL_USES_LEFT_ATTRIBUTE, usesLeft)
end

local function updateToolDisplayName(tool, settings)
	if not tool then
		return
	end

	local originalName = getToolOriginalName(tool)

	if settings.IsUsageLimited then
		local usesLeft = getToolUsesLeft(tool, settings)
		tool.Name = string.format("%s (%d)", originalName, usesLeft)
	else
		tool.Name = originalName
	end
end

local function initializePlacementTool(tool)
	if not tool:IsA("Tool") then
		return
	end

	local _, _, settings = getToolPlacementData(tool)
	if not settings then
		return
	end

	getToolOriginalName(tool)

	if settings.IsUsageLimited then
		getToolUsesLeft(tool, settings)
	end

	updateToolDisplayName(tool, settings)
end

local function watchToolContainer(container)
	for _, child in ipairs(container:GetChildren()) do
		initializePlacementTool(child)
	end

	container.ChildAdded:Connect(function(child)
		initializePlacementTool(child)
	end)
end

local function attachPlacementMetadata(instance, player, placementName)
	local ownerValue = Instance.new("ObjectValue")
	ownerValue.Name = "Owner"
	ownerValue.Value = player
	ownerValue.Parent = instance

	local placementNameValue = Instance.new("StringValue")
	placementNameValue.Name = "PlacementName"
	placementNameValue.Value = placementName
	placementNameValue.Parent = instance
end

local function trackPlacedObject(player, instance)
	placedObjectsByPlayer[player] = placedObjectsByPlayer[player] or {}
	placedObjectsByPlayer[player][instance] = true

	instance.Destroying:Connect(function()
		local playerPlacedObjects = placedObjectsByPlayer[player]
		if playerPlacedObjects then
			playerPlacedObjects[instance] = nil
		end
	end)
end

local function isOwnedByPlayer(instance, player)
	if not instance then
		return false
	end

	local ownerValue = instance:FindFirstChild("Owner")
	return ownerValue
		and ownerValue:IsA("ObjectValue")
		and ownerValue.Value == player
end

local function cleanupPlacedObjectsForPlayer(player)
	local playerPlacedObjects = placedObjectsByPlayer[player]
	if not playerPlacedObjects then
		return
	end

	for instance in pairs(playerPlacedObjects) do
		if instance and instance.Parent then
			instance:Destroy()
		end
	end

	placedObjectsByPlayer[player] = nil
end

local function createRefundedTool(player, placementName, settings)
	local tool = Instance.new("Tool")
	tool.Name = placementName
	tool.RequiresHandle = false

	tool:SetAttribute(TOOL_PLACEMENT_ATTRIBUTE, placementName)
	tool:SetAttribute(TOOL_ORIGINAL_NAME_ATTRIBUTE, placementName)
	tool:SetAttribute(TOOL_USES_LEFT_ATTRIBUTE, 1)

	updateToolDisplayName(tool, settings)

	local backpack = getPlayerBackpack(player)
	if backpack then
		tool.Parent = backpack
	else
		tool.Parent = player
	end

	return tool
end

local function refundPlacementUse(player, placementName)
	local settingsModule = getPlacementSettingsModule(placementName)
	if not settingsModule then
		return
	end

	local settings = require(settingsModule)
	if not settings.IsUsageLimited then
		return
	end

	local tool = findPlacementTool(player, placementName)

	if tool then
		local usesLeft = getToolUsesLeft(tool, settings)
		usesLeft += 1
		setToolUsesLeft(tool, usesLeft)
		updateToolDisplayName(tool, settings)
	else
		createRefundedTool(player, placementName, settings)
	end
end

local function getCharacterRootPart(player)
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function placeObjectFromTemplate(template, targetCFrame)
	local placedObject = template:Clone()

	if placedObject:IsA("Model") then
		if not placedObject.PrimaryPart then
			warn(("Placed model '%s' is missing a PrimaryPart."):format(placedObject.Name))
			placedObject:Destroy()
			return nil
		end

		placedObject:PivotTo(targetCFrame)
	elseif placedObject:IsA("BasePart") then
		placedObject.CFrame = targetCFrame
	else
		placedObject:Destroy()
		return nil
	end

	return placedObject
end

local function resolvePlacedRoot(targetInstance, player)
	if isOwnedByPlayer(targetInstance, player) then
		return targetInstance
	end

	local ancestorModel = targetInstance:FindFirstAncestorWhichIsA("Model")
	if ancestorModel and isOwnedByPlayer(ancestorModel, player) then
		return ancestorModel
	end

	return nil
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		watchToolContainer(character)
	end)

	local backpack = player:WaitForChild("Backpack")
	watchToolContainer(backpack)
end)

Players.PlayerRemoving:Connect(function(player)
	cleanupPlacedObjectsForPlayer(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	local backpack = getPlayerBackpack(player)
	if backpack then
		watchToolContainer(backpack)
	end

	if player.Character then
		watchToolContainer(player.Character)
	end
end

PlaceObjectRemote.OnServerEvent:Connect(function(player, requestedPlacementName, targetCFrame)
	if typeof(requestedPlacementName) ~= "string" then
		return
	end

	if typeof(targetCFrame) ~= "CFrame" then
		return
	end

	local equippedTool = getEquippedPlacementTool(player)
	if not equippedTool then
		return
	end

	local placementName, objectTemplate, settings = getToolPlacementData(equippedTool)
	if not placementName or placementName ~= requestedPlacementName then
		return
	end

	local placementRoot = getPlacementRoot(objectTemplate)
	if not placementRoot then
		warn(("Placement object '%s' must be a BasePart or a Model with a PrimaryPart."):format(placementName))
		return
	end

	local characterRootPart = getCharacterRootPart(player)
	if not characterRootPart then
		return
	end

	local distance = (characterRootPart.Position - targetCFrame.Position).Magnitude
	if distance > settings.MaxPlacementDistance then
		return
	end

	if settings.IsUsageLimited then
		local usesLeft = getToolUsesLeft(equippedTool, settings)
		if usesLeft <= 0 then
			updateToolDisplayName(equippedTool, settings)
			return
		end
	end

	local placedObject = placeObjectFromTemplate(objectTemplate, targetCFrame)
	if not placedObject then
		return
	end

	attachPlacementMetadata(placedObject, player, placementName)

	placedObject.Parent = workspace
	trackPlacedObject(player, placedObject)

	if settings.IsUsageLimited then
		local usesLeft = getToolUsesLeft(equippedTool, settings) - 1
		setToolUsesLeft(equippedTool, usesLeft)
		updateToolDisplayName(equippedTool, settings)

		if usesLeft <= 0 then
			equippedTool:Destroy()
		end
	else
		updateToolDisplayName(equippedTool, settings)
	end
end)

DeleteObjectRemote.OnServerEvent:Connect(function(player, targetInstance)
	if typeof(targetInstance) ~= "Instance" then
		return
	end

	if not targetInstance:IsDescendantOf(workspace) then
		return
	end

	local placedRoot = resolvePlacedRoot(targetInstance, player)
	if not placedRoot then
		return
	end

	local placementNameValue = placedRoot:FindFirstChild("PlacementName")
	local placementName = placementNameValue
		and placementNameValue:IsA("StringValue")
		and placementNameValue.Value
		or nil

	placedRoot:Destroy()

	if placementName and placementName ~= "" then
		refundPlacementUse(player, placementName)
	end
end)