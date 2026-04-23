local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local Shared = ReplicatedStorage:WaitForChild("PlacementShared")
local Remotes = Shared:WaitForChild("Remotes")
local SoundsFolder = Shared:WaitForChild("Sounds")
local ObjectsFolder = Shared:WaitForChild("Objects")
local SettingsFolder = Shared:WaitForChild("Settings")

local PlaceObjectRemote = Remotes:WaitForChild("PlaceObject")
local DeleteObjectRemote = Remotes:WaitForChild("DeleteObject")

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local PlacementUI = PlayerGui:WaitForChild("PlacementUI")
local PlacementTimeGroup = PlacementUI:WaitForChild("PlacementTime")
local PlacementFill = PlacementTimeGroup:WaitForChild("PlacementFill")
local PlacementGradient = PlacementFill:WaitForChild("UIGradient")

local TOOL_ATTRIBUTE = "PlacementSystem"

local equippedTool = nil
local selectedPlacementName = nil
local selectedSettings = nil

local currentRotationY = 0
local placementInProgress = false
local placementSessionId = 0
local soundSessionId = 0

local previewGhost = nil
local pendingGhost = nil

local activeTransparencyTween = nil
local activeFillTween = nil
local activePlacementSounds = {}

local function stopTween(tween)
	if tween then
		tween:Cancel()
	end
end

local function stopAllPlacementTweens()
	stopTween(activeTransparencyTween)
	stopTween(activeFillTween)

	activeTransparencyTween = nil
	activeFillTween = nil
end

local function resetPlacementProgressUI()
	stopAllPlacementTweens()
	PlacementGradient.Offset = Vector2.new(-1, 0)
	PlacementTimeGroup.GroupTransparency = 1
end

local function playPlacementProgressUI()
	stopAllPlacementTweens()

	PlacementTimeGroup.GroupTransparency = 1
	PlacementGradient.Offset = Vector2.new(-1, 0)

	activeTransparencyTween = TweenService:Create(
		PlacementTimeGroup,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ GroupTransparency = 0 }
	)

	activeFillTween = TweenService:Create(
		PlacementGradient,
		TweenInfo.new(selectedSettings.PlacementDelay, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Offset = Vector2.new(0, 0) }
	)

	activeTransparencyTween:Play()
	activeFillTween:Play()
end

local function getPlacementSoundTemplates()
	local soundTemplates = {}

	for _, child in ipairs(SoundsFolder:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(soundTemplates, child)
		end
	end

	return soundTemplates
end

local function stopPlacementAudio()
	soundSessionId += 1

	for _, sound in ipairs(activePlacementSounds) do
		if sound and sound.Parent then
			sound:Stop()
			sound:Destroy()
		end
	end

	table.clear(activePlacementSounds)
end

local function playPlacementAudio(sessionId)
	stopPlacementAudio()

	local soundTemplates = getPlacementSoundTemplates()
	if #soundTemplates == 0 then
		return
	end

	soundSessionId += 1
	local activeSoundSession = soundSessionId

	task.spawn(function()
		while placementInProgress
			and placementSessionId == sessionId
			and soundSessionId == activeSoundSession do

			local soundTemplate = soundTemplates[math.random(1, #soundTemplates)]
			local soundInstance = soundTemplate:Clone()
			soundInstance.Parent = SoundService

			table.insert(activePlacementSounds, soundInstance)

			local finished = false
			local endedConnection

			endedConnection = soundInstance.Ended:Connect(function()
				finished = true

				if endedConnection then
					endedConnection:Disconnect()
					endedConnection = nil
				end
			end)

			soundInstance:Play()

			while not finished do
				if not placementInProgress
					or placementSessionId ~= sessionId
					or soundSessionId ~= activeSoundSession then

					if endedConnection then
						endedConnection:Disconnect()
						endedConnection = nil
					end

					soundInstance:Stop()
					break
				end

				task.wait()
			end

			for index = #activePlacementSounds, 1, -1 do
				if activePlacementSounds[index] == soundInstance then
					table.remove(activePlacementSounds, index)
					break
				end
			end

			if soundInstance.Parent then
				soundInstance:Destroy()
			end
		end
	end)
end

local function getSelectedTemplate()
	if not selectedPlacementName then
		return nil
	end

	return ObjectsFolder:FindFirstChild(selectedPlacementName)
end

local function applyGhostVisuals(instance, transparency)
	if instance:IsA("BasePart") then
		instance.Transparency = transparency
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
		instance.Anchored = true
		instance.Material = Enum.Material.ForceField
		return
	end

	if not instance:IsA("Model") then
		return
	end

	local primaryPartName = instance.PrimaryPart and instance.PrimaryPart.Name or nil

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Anchored = true
			descendant.Material = Enum.Material.ForceField

			if descendant.Name ~= primaryPartName then
				descendant.Transparency = transparency
			end
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = transparency
		end
	end
end

local function setInstanceCFrame(instance, targetCFrame)
	if instance:IsA("Model") then
		if not instance.PrimaryPart then
			return false
		end

		instance:PivotTo(targetCFrame)
		return true
	end

	if instance:IsA("BasePart") then
		instance.CFrame = targetCFrame
		return true
	end

	return false
end

local function destroyGhost(instance)
	if instance then
		instance:Destroy()
	end
end

local function destroyAllGhosts()
	destroyGhost(previewGhost)
	destroyGhost(pendingGhost)

	previewGhost = nil
	pendingGhost = nil
end

local function createGhost(transparency)
	local template = getSelectedTemplate()
	if not template then
		return nil
	end

	local ghost = template:Clone()

	if ghost:IsA("Model") and not ghost.PrimaryPart then
		warn(("Model '%s' requires a PrimaryPart for placement."):format(ghost.Name))
		ghost:Destroy()
		return nil
	end

	applyGhostVisuals(ghost, transparency)
	ghost.Parent = workspace

	return ghost
end

local function createPreviewGhost()
	destroyGhost(previewGhost)
	previewGhost = nil

	if not selectedPlacementName then
		return
	end

	previewGhost = createGhost(0.5)
end

local function clearPendingGhost()
	destroyGhost(pendingGhost)
	pendingGhost = nil
end

local function createPendingGhost(targetCFrame)
	clearPendingGhost()

	pendingGhost = createGhost(0.25)
	if not pendingGhost then
		return
	end

	if not setInstanceCFrame(pendingGhost, targetCFrame) then
		clearPendingGhost()
	end
end

local function getHumanoidRootPart()
	local character = LocalPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function isPlacementWithinRange(targetCFrame)
	if not selectedSettings or not targetCFrame then
		return false
	end

	local rootPart = getHumanoidRootPart()
	if not rootPart then
		return false
	end

	local distance = (rootPart.Position - targetCFrame.Position).Magnitude
	return distance <= selectedSettings.MaxPlacementDistance
end

local function getPlacementCFrame()
	if not equippedTool or not selectedSettings then
		return nil
	end

	local hitCFrame = Mouse.Hit
	if not hitCFrame then
		return nil
	end

	local position = hitCFrame.Position
	local rotation = CFrame.Angles(0, math.rad(currentRotationY), 0)

	return CFrame.new(position) * rotation
end

local function updateGhostTransparency(ghost, transparency)
	if not ghost then
		return
	end

	if ghost:IsA("Model") then
		for _, descendant in ipairs(ghost:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Transparency = transparency
			elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
				descendant.Transparency = transparency
			end
		end
	elseif ghost:IsA("BasePart") then
		ghost.Transparency = transparency
	end
end

local function updatePreviewGhost()
	if not equippedTool or not previewGhost or placementInProgress then
		return
	end

	local targetCFrame = getPlacementCFrame()
	if not targetCFrame then
		return
	end

	setInstanceCFrame(previewGhost, targetCFrame)

	local isInRange = isPlacementWithinRange(targetCFrame)
	updateGhostTransparency(previewGhost, isInRange and 0.5 or 0.8)
end

local function cancelPlacementOperation()
	placementSessionId += 1
	placementInProgress = false

	stopPlacementAudio()
	clearPendingGhost()
	resetPlacementProgressUI()

	if previewGhost and equippedTool then
		previewGhost.Parent = workspace
	end
end

local function disablePlacementMode()
	cancelPlacementOperation()

	equippedTool = nil
	selectedPlacementName = nil
	selectedSettings = nil
	currentRotationY = 0

	destroyAllGhosts()
	resetPlacementProgressUI()
end

local function enablePlacementMode(tool)
	cancelPlacementOperation()

	local placementName = tool:GetAttribute(TOOL_ATTRIBUTE)
	if typeof(placementName) ~= "string" or placementName == "" then
		return
	end

	local template = ObjectsFolder:FindFirstChild(placementName)
	local settingsModule = SettingsFolder:FindFirstChild(placementName)

	if not template or not settingsModule then
		warn(("Missing placement object or settings for '%s'."):format(placementName))
		return
	end

	equippedTool = tool
	selectedPlacementName = placementName
	selectedSettings = require(settingsModule)
	currentRotationY = 0
	placementInProgress = false

	createPreviewGhost()
	resetPlacementProgressUI()
end

local function requestOwnedObjectDeletion()
	local target = Mouse.Target
	if not target then
		return
	end

	DeleteObjectRemote:FireServer(target)
end

local function bindPlacementTool(tool)
	if not tool:IsA("Tool") then
		return
	end

	if not tool:GetAttribute(TOOL_ATTRIBUTE) then
		return
	end

	tool.Equipped:Connect(function()
		enablePlacementMode(tool)
	end)

	tool.Unequipped:Connect(function()
		if equippedTool == tool then
			disablePlacementMode()
		else
			cancelPlacementOperation()
		end
	end)
end

local function monitorCharacterTools(character)
	for _, child in ipairs(character:GetChildren()) do
		bindPlacementTool(child)
	end

	character.ChildAdded:Connect(function(child)
		bindPlacementTool(child)
	end)
end

local function beginPlacement()
	if not equippedTool or not selectedSettings or placementInProgress then
		return
	end

	local targetCFrame = getPlacementCFrame()
	if not targetCFrame then
		return
	end

	if not isPlacementWithinRange(targetCFrame) then
		return
	end

	local placementTool = equippedTool
	local placementName = selectedPlacementName
	local placementSettings = selectedSettings

	placementSessionId += 1
	local sessionId = placementSessionId

	placementInProgress = true

	playPlacementProgressUI()
	playPlacementAudio(sessionId)

	if previewGhost then
		previewGhost.Parent = nil
	end

	createPendingGhost(targetCFrame)

	task.delay(placementSettings.PlacementDelay, function()
		if placementSessionId ~= sessionId then
			return
		end

		if not placementInProgress then
			return
		end

		if equippedTool ~= placementTool then
			cancelPlacementOperation()
			return
		end

		if selectedPlacementName ~= placementName then
			cancelPlacementOperation()
			return
		end

		if not placementTool.Parent then
			cancelPlacementOperation()
			return
		end

		PlaceObjectRemote:FireServer(placementName, targetCFrame)

		stopPlacementAudio()
		clearPendingGhost()
		resetPlacementProgressUI()

		if previewGhost and equippedTool == placementTool then
			previewGhost.Parent = workspace
		end

		placementInProgress = false
	end)
end

if LocalPlayer.Character then
	monitorCharacterTools(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(function(character)
	disablePlacementMode()
	monitorCharacterTools(character)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		requestOwnedObjectDeletion()
		return
	end

    if not equippedTool or not selectedSettings then
		return
	end

	if input.KeyCode == Enum.KeyCode.R and selectedSettings.AllowRotation then
		currentRotationY += 30
	end
end)

Mouse.Button1Down:Connect(beginPlacement)

resetPlacementProgressUI()

RunService.RenderStepped:Connect(function()
	updatePreviewGhost()
end)