local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local remotes = ReplicatedStorage:WaitForChild("ArcadeRushRemotes")
local actionEvent = remotes:WaitForChild("Action") :: RemoteEvent
local stateEvent = remotes:WaitForChild("State") :: RemoteEvent
local messageEvent = remotes:WaitForChild("Message") :: RemoteEvent
local gambleResultEvent = remotes:WaitForChild("GambleResult") :: RemoteEvent
local feedbackEvent = remotes:WaitForChild("Feedback") :: RemoteEvent
local interactionEvent = remotes:WaitForChild("Interaction") :: RemoteEvent

local currentState = nil
local tutorialOpen = false
local tutorialDismissedThisSession = false
local tutorialPage = 1
local casinoOpen = false
local shopOpen = false
local itemLibraryOpen = false
local mapOpen = false
local confirmRunOpen = false
local tokenShopOpen = false
local animatingGamble = false
local scratchBackdropOpen = false
local casinoBackdropName: string? = nil
local pendingConfirmAction = "StartRun"
local openRunConfirmation: (string, string, string, string) -> () = function() end
local setCasinoOpen: (boolean) -> () = function() end
local setShopOpen: (boolean) -> () = function() end
local setItemLibraryOpen: (boolean) -> () = function() end
local setMapOpen: (boolean) -> () = function() end
local setConfirmRunOpen: (boolean) -> () = function() end
local render: () -> () = function() end
local showGuessingGameChoices: () -> () = function() end
local clearStage: () -> () = function() end
local showwhackAMoleStart: (any) -> () = function() end
local showCardBattlesStart: () -> () = function() end
local showCardBattle: (any) -> () = function() end
local showMysteryWheelStart: () -> () = function() end
local makeStageLabel: (string, UDim2, UDim2, Color3) -> TextLabel = function()
	return Instance.new("TextLabel")
end
local makeStageButton: (string, UDim2, () -> ()) -> TextButton = function()
	return Instance.new("TextButton")
end
local scratchTiles: { [number]: TextButton } = {}
local CardBattlesButtons: { TextButton } = {}
local activeMiniGame: string? = nil
local boundGunTools: { [Instance]: boolean } = {}
local FONT = Enum.Font.Arcade

local orderNames = {
	Gambles = { "WhackAMole", "CardBattles", "GuessingGame", "MysteryWheel" },
	ShopItems = { "Sword", "CashMagnet", "Medkit", "Armor", "CoinCharm" },
	MetaUpgrades = { "Bankroll", "Vitality", "Edge", "Luck" },
	GameUnlocks = { "CardBattles", "GuessingGame", "MysteryWheel" },
}

local function bindRunPistol(tool: Instance)
	if not tool:IsA("Tool") or tool.Name ~= "RunLaserGun" or boundGunTools[tool] then
		return
	end
	boundGunTools[tool] = true
	tool.Activated:Connect(function()
		local run = currentState and currentState.Run
		if run and (run.BattleCountdown or 0) > 0 then
			return
		end
		actionEvent:FireServer("ShootGun", mouse.Hit.Position)
	end)
end

local function watchTools(container: Instance?)
	if not container then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		bindRunPistol(child)
	end
	container.ChildAdded:Connect(bindRunPistol)
end

watchTools(player:WaitForChild("Backpack"))
player.CharacterAdded:Connect(function(character)
	watchTools(character)
end)
if player.Character then
	watchTools(player.Character)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ArcadeRushHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = screenGui

local countdownLabel = Instance.new("TextLabel")
countdownLabel.Name = "BattleCountdown"
countdownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
countdownLabel.BackgroundTransparency = 1
countdownLabel.Position = UDim2.fromScale(0.5, 0.48)
countdownLabel.Size = UDim2.fromOffset(320, 180)
countdownLabel.Font = FONT
countdownLabel.TextColor3 = Color3.fromRGB(255, 246, 150)
countdownLabel.TextStrokeColor3 = Color3.fromRGB(20, 18, 24)
countdownLabel.TextStrokeTransparency = 0
countdownLabel.TextScaled = true
countdownLabel.Visible = false
countdownLabel.ZIndex = 50
countdownLabel.Parent = root

local function addCorner(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function tween(instance: Instance, duration: number, properties)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local created = TweenService:Create(instance, info, properties)
	created:Play()
	return created
end

local function playSfx(assetId: number, volume: number)
	local sound = Instance.new("Sound")
	sound.SoundId = `rbxassetid://{assetId}`
	sound.Volume = volume
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	task.delay(3, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local statusPanel = Instance.new("Frame")
statusPanel.Name = "StatusPanel"
statusPanel.Position = UDim2.fromOffset(18, 64)
statusPanel.Size = UDim2.fromOffset(310, 300)
statusPanel.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
statusPanel.BackgroundTransparency = 1
statusPanel.BorderSizePixel = 0
statusPanel.Parent = root
addCorner(statusPanel, 8)

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(14, 10)
title.Size = UDim2.new(1, -28, 0, 28)
title.Font = FONT
title.Text = "ARCADE RUSH"
title.TextColor3 = Color3.fromRGB(255, 230, 166)
title.TextSize = 22
title.TextXAlignment = Enum.TextXAlignment.Left
title.Visible = false
title.Parent = statusPanel

local stats = Instance.new("TextLabel")
stats.Name = "Stats"
stats.BackgroundTransparency = 1
stats.Position = UDim2.fromOffset(0, 0)
stats.Size = UDim2.new(1, 0, 1, 0)
stats.Font = FONT
stats.TextColor3 = Color3.fromRGB(255, 239, 184)
stats.TextSize = 27
stats.TextStrokeColor3 = Color3.fromRGB(18, 12, 10)
stats.TextStrokeTransparency = 0.12
stats.TextXAlignment = Enum.TextXAlignment.Left
stats.TextYAlignment = Enum.TextYAlignment.Top
stats.TextWrapped = true
stats.Parent = statusPanel

local hitFlash = Instance.new("Frame")
hitFlash.Name = "HitFlash"
hitFlash.BackgroundColor3 = Color3.fromRGB(255, 42, 66)
hitFlash.BackgroundTransparency = 1
hitFlash.BorderSizePixel = 0
hitFlash.Size = UDim2.fromScale(1, 1)
hitFlash.ZIndex = 80
hitFlash.Parent = root

local heartsPanel = Instance.new("Frame")
heartsPanel.Name = "HeartsPanel"
heartsPanel.AnchorPoint = Vector2.new(0, 1)
heartsPanel.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
heartsPanel.BackgroundTransparency = 0.15
heartsPanel.BorderSizePixel = 0
heartsPanel.Position = UDim2.new(0, 18, 1, -24)
heartsPanel.Size = UDim2.fromOffset(260, 76)
heartsPanel.Visible = false
heartsPanel.ZIndex = 25
heartsPanel.Parent = root
addCorner(heartsPanel, 8)

local heartsLayout = Instance.new("UIListLayout")
heartsLayout.FillDirection = Enum.FillDirection.Horizontal
heartsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
heartsLayout.Padding = UDim.new(0, 6)
heartsLayout.SortOrder = Enum.SortOrder.LayoutOrder
heartsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
heartsLayout.Parent = heartsPanel

local heartsPadding = Instance.new("UIPadding")
heartsPadding.PaddingBottom = UDim.new(0, 8)
heartsPadding.PaddingLeft = UDim.new(0, 12)
heartsPadding.PaddingRight = UDim.new(0, 12)
heartsPadding.PaddingTop = UDim.new(0, 8)
heartsPadding.Parent = heartsPanel

local heartLabels: { TextLabel } = {}

local hitText = Instance.new("TextLabel")
hitText.Name = "HitText"
hitText.AnchorPoint = Vector2.new(0, 1)
hitText.BackgroundTransparency = 1
hitText.Position = UDim2.new(0, 26, 1, -108)
hitText.Size = UDim2.fromOffset(220, 44)
hitText.Font = FONT
hitText.TextColor3 = Color3.fromRGB(255, 76, 91)
hitText.TextSize = 28
hitText.TextStrokeColor3 = Color3.fromRGB(30, 10, 18)
hitText.TextStrokeTransparency = 0.15
hitText.TextTransparency = 1
hitText.Visible = false
hitText.ZIndex = 82
hitText.Parent = root

local tutorialOverlay = Instance.new("Frame")
tutorialOverlay.Name = "TutorialOverlay"
tutorialOverlay.BackgroundColor3 = Color3.fromRGB(3, 5, 10)
tutorialOverlay.BackgroundTransparency = 0.22
tutorialOverlay.BorderSizePixel = 0
tutorialOverlay.Size = UDim2.fromScale(1, 1)
tutorialOverlay.Visible = false
tutorialOverlay.ZIndex = 90
tutorialOverlay.Parent = root

local tutorialModal = Instance.new("Frame")
tutorialModal.Name = "TutorialModal"
tutorialModal.AnchorPoint = Vector2.new(0.5, 0.5)
tutorialModal.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
tutorialModal.BorderSizePixel = 0
tutorialModal.Position = UDim2.fromScale(0.5, 0.5)
tutorialModal.Size = UDim2.fromOffset(560, 360)
tutorialModal.ZIndex = 91
tutorialModal.Parent = tutorialOverlay
addCorner(tutorialModal, 10)

local tutorialTitle = Instance.new("TextLabel")
tutorialTitle.BackgroundTransparency = 1
tutorialTitle.Position = UDim2.fromOffset(20, 18)
tutorialTitle.Size = UDim2.new(1, -120, 0, 34)
tutorialTitle.Font = FONT
tutorialTitle.Text = "WELCOME TO ARCADE RUSH"
tutorialTitle.TextColor3 = Color3.fromRGB(255, 230, 166)
tutorialTitle.TextSize = 24
tutorialTitle.TextXAlignment = Enum.TextXAlignment.Left
tutorialTitle.ZIndex = 92
tutorialTitle.Parent = tutorialModal

local tutorialPageLabel = Instance.new("TextLabel")
tutorialPageLabel.BackgroundTransparency = 1
tutorialPageLabel.Position = UDim2.fromOffset(20, 58)
tutorialPageLabel.Size = UDim2.new(1, -40, 0, 182)
tutorialPageLabel.Font = FONT
tutorialPageLabel.TextColor3 = Color3.fromRGB(246, 248, 252)
tutorialPageLabel.TextSize = 22
tutorialPageLabel.TextWrapped = true
tutorialPageLabel.TextXAlignment = Enum.TextXAlignment.Left
tutorialPageLabel.TextYAlignment = Enum.TextYAlignment.Top
tutorialPageLabel.ZIndex = 92
tutorialPageLabel.Parent = tutorialModal

local tutorialCounter = Instance.new("TextLabel")
tutorialCounter.BackgroundTransparency = 1
tutorialCounter.Position = UDim2.fromOffset(20, 242)
tutorialCounter.Size = UDim2.new(1, -40, 0, 24)
tutorialCounter.Font = FONT
tutorialCounter.TextColor3 = Color3.fromRGB(200, 203, 214)
tutorialCounter.TextSize = 16
tutorialCounter.TextXAlignment = Enum.TextXAlignment.Left
tutorialCounter.ZIndex = 92
tutorialCounter.Parent = tutorialModal

local tutorialFooter = Instance.new("Frame")
tutorialFooter.BackgroundTransparency = 1
tutorialFooter.Position = UDim2.fromOffset(20, 276)
tutorialFooter.Size = UDim2.new(1, -40, 0, 42)
tutorialFooter.ZIndex = 92
tutorialFooter.Parent = tutorialModal

local tutorialDontShow = Instance.new("TextButton")
tutorialDontShow.BackgroundColor3 = Color3.fromRGB(54, 63, 82)
tutorialDontShow.BorderSizePixel = 0
tutorialDontShow.Position = UDim2.fromOffset(0, 0)
tutorialDontShow.Size = UDim2.fromOffset(214, 34)
tutorialDontShow.Font = FONT
tutorialDontShow.Text = ""
tutorialDontShow.TextColor3 = Color3.fromRGB(246, 248, 252)
tutorialDontShow.TextSize = 16
tutorialDontShow.TextXAlignment = Enum.TextXAlignment.Left
tutorialDontShow.ZIndex = 92
tutorialDontShow.Parent = tutorialFooter
addCorner(tutorialDontShow, 6)

local tutorialDontShowMark = Instance.new("TextLabel")
tutorialDontShowMark.BackgroundTransparency = 1
tutorialDontShowMark.Position = UDim2.fromOffset(10, 0)
tutorialDontShowMark.Size = UDim2.fromOffset(28, 34)
tutorialDontShowMark.Font = FONT
tutorialDontShowMark.Text = "[ ]"
tutorialDontShowMark.TextColor3 = Color3.fromRGB(255, 230, 166)
tutorialDontShowMark.TextSize = 18
tutorialDontShowMark.TextXAlignment = Enum.TextXAlignment.Left
tutorialDontShowMark.ZIndex = 93
tutorialDontShowMark.Parent = tutorialDontShow

local tutorialDontShowText = Instance.new("TextLabel")
tutorialDontShowText.BackgroundTransparency = 1
tutorialDontShowText.Position = UDim2.fromOffset(44, 0)
tutorialDontShowText.Size = UDim2.new(1, -50, 1, 0)
tutorialDontShowText.Font = FONT
tutorialDontShowText.Text = "Don't show again"
tutorialDontShowText.TextColor3 = Color3.fromRGB(246, 248, 252)
tutorialDontShowText.TextSize = 16
tutorialDontShowText.TextXAlignment = Enum.TextXAlignment.Left
tutorialDontShowText.ZIndex = 93
tutorialDontShowText.Parent = tutorialDontShow

local tutorialNav = Instance.new("Frame")
tutorialNav.BackgroundTransparency = 1
tutorialNav.AnchorPoint = Vector2.new(1, 0)
tutorialNav.Position = UDim2.new(1, 0, 0, 0)
tutorialNav.Size = UDim2.fromOffset(176, 34)
tutorialNav.ZIndex = 92
tutorialNav.Parent = tutorialFooter

local tutorialPrev = Instance.new("TextButton")
tutorialPrev.BackgroundColor3 = Color3.fromRGB(54, 63, 82)
tutorialPrev.BorderSizePixel = 0
tutorialPrev.Position = UDim2.fromOffset(0, 0)
tutorialPrev.Size = UDim2.fromOffset(52, 34)
tutorialPrev.Font = FONT
tutorialPrev.Text = "<"
tutorialPrev.TextColor3 = Color3.fromRGB(246, 248, 252)
tutorialPrev.TextSize = 18
tutorialPrev.ZIndex = 92
tutorialPrev.Parent = tutorialNav
addCorner(tutorialPrev, 6)

local tutorialNext = Instance.new("TextButton")
tutorialNext.BackgroundColor3 = Color3.fromRGB(54, 63, 82)
tutorialNext.BorderSizePixel = 0
tutorialNext.Position = UDim2.fromOffset(60, 0)
tutorialNext.Size = UDim2.fromOffset(60, 34)
tutorialNext.Font = FONT
tutorialNext.Text = ">"
tutorialNext.TextColor3 = Color3.fromRGB(246, 248, 252)
tutorialNext.TextSize = 18
tutorialNext.ZIndex = 92
tutorialNext.Parent = tutorialNav
addCorner(tutorialNext, 6)

local tutorialClose = Instance.new("TextButton")
tutorialClose.BackgroundColor3 = Color3.fromRGB(54, 63, 82)
tutorialClose.BorderSizePixel = 0
tutorialClose.Position = UDim2.fromOffset(128, 0)
tutorialClose.Size = UDim2.fromOffset(48, 34)
tutorialClose.Font = FONT
tutorialClose.Text = "X"
tutorialClose.TextColor3 = Color3.fromRGB(246, 248, 252)
tutorialClose.TextSize = 18
tutorialClose.ZIndex = 92
tutorialClose.Parent = tutorialNav
addCorner(tutorialClose, 6)

local tutorialPages = {
	"Tokens let you play the arcade machines.",
	"Winning games gives Tickets, which buy upgrades.",
	"Clear rooms, fight enemies, and beat the boss.",
	"Come back stronger and unlock more machines.",
}

local tutorialRememberChoice = false
local function refreshTutorialPage()
	local total = #tutorialPages
	tutorialPage = math.clamp(tutorialPage, 1, total)
	tutorialPageLabel.Text = tutorialPages[tutorialPage]
	tutorialCounter.Text = `Page {tutorialPage}/{total}`
	tutorialPrev.Active = tutorialPage > 1
	tutorialPrev.AutoButtonColor = tutorialPage > 1
	tutorialPrev.TextTransparency = if tutorialPage > 1 then 0 else 0.45
	tutorialNext.Text = if tutorialPage >= total then "Done" else ">"
	tutorialDontShowMark.Text = if tutorialRememberChoice then "[x]" else "[ ]"
end

local function closeTutorial()
	tutorialOpen = false
	tutorialDismissedThisSession = true
	tutorialOverlay.Visible = false
	if tutorialRememberChoice then
		actionEvent:FireServer("MarkTutorialSeen")
	end
end

tutorialDontShow.Activated:Connect(function()
	tutorialRememberChoice = not tutorialRememberChoice
	refreshTutorialPage()
end)

tutorialClose.Activated:Connect(closeTutorial)
tutorialPrev.Activated:Connect(function()
	if tutorialPage > 1 then
		tutorialPage -= 1
		refreshTutorialPage()
	end
end)
tutorialNext.Activated:Connect(function()
	if tutorialPage < #tutorialPages then
		tutorialPage += 1
		refreshTutorialPage()
	else
		closeTutorial()
	end
end)

refreshTutorialPage()

local actionsPanel = Instance.new("Frame")
actionsPanel.Name = "ActionsPanel"
actionsPanel.AnchorPoint = Vector2.new(1, 0)
actionsPanel.Position = UDim2.new(1, -18, 0, 18)
actionsPanel.Size = UDim2.fromOffset(520, 82)
actionsPanel.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
actionsPanel.BackgroundTransparency = 1
actionsPanel.BorderSizePixel = 0
actionsPanel.Parent = root
addCorner(actionsPanel, 8)

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingBottom = UDim.new(0, 12)
panelPadding.PaddingLeft = UDim.new(0, 12)
panelPadding.PaddingRight = UDim.new(0, 12)
panelPadding.PaddingTop = UDim.new(0, 12)
panelPadding.Parent = actionsPanel

local actionIconBar = Instance.new("Frame")
actionIconBar.Name = "ActionIconBar"
actionIconBar.BackgroundTransparency = 1
actionIconBar.Position = UDim2.fromOffset(12, 12)
actionIconBar.Size = UDim2.new(1, -24, 0, 64)
actionIconBar.Parent = actionsPanel

local actionIconLayout = Instance.new("UIListLayout")
actionIconLayout.FillDirection = Enum.FillDirection.Horizontal
actionIconLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
actionIconLayout.Padding = UDim.new(0, 10)
actionIconLayout.SortOrder = Enum.SortOrder.LayoutOrder
actionIconLayout.Parent = actionIconBar

local upgradesFrame = Instance.new("Frame")
upgradesFrame.Name = "UpgradesFrame"
upgradesFrame.BackgroundTransparency = 1
upgradesFrame.Position = UDim2.fromOffset(12, 78)
upgradesFrame.Size = UDim2.new(1, -24, 1, -90)
upgradesFrame.Parent = actionsPanel

local upgradesLayout = Instance.new("UIListLayout")
upgradesLayout.Padding = UDim.new(0, 8)
upgradesLayout.SortOrder = Enum.SortOrder.LayoutOrder
upgradesLayout.Parent = upgradesFrame

local function makeHeader(parent: Instance, text: string, order: number)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, 24)
	label.Font = FONT
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 230, 166)
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, text: string, order: number, callback: () -> ())
	local button = Instance.new("TextButton")
	button.AutoButtonColor = true
	button.BackgroundColor3 = Color3.fromRGB(54, 63, 82)
	button.BorderSizePixel = 0
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, 38)
	button.Font = FONT
	button.Text = text
	button.TextColor3 = Color3.fromRGB(246, 248, 252)
	button.TextSize = 14
	button.TextWrapped = true
	button.Parent = parent
	addCorner(button, 6)

	button.Activated:Connect(function()
		local baseSize = button.Size
		local pressedSize = UDim2.new(baseSize.X.Scale, baseSize.X.Offset, baseSize.Y.Scale, math.max(0, baseSize.Y.Offset - 4))
		tween(button, 0.08, { Size = pressedSize }).Completed:Wait()
		tween(button, 0.12, { Size = baseSize })
		callback()
	end)

	return button
end

local function makeIconButton(parent: Instance, icon: string, order: number, callback: () -> ())
	local button = Instance.new("TextButton")
	button.AutoButtonColor = true
	button.BackgroundColor3 = Color3.fromRGB(54, 63, 82)
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(66, 66)
	button:SetAttribute("IconButton", true)
	button.Font = FONT
	button.Text = icon
	button.TextColor3 = Color3.fromRGB(255, 230, 166)
	button.TextSize = 24
	button.Parent = parent
	addCorner(button, 8)

	button.Activated:Connect(function()
		tween(button, 0.08, { Size = UDim2.fromOffset(58, 58) }).Completed:Wait()
		tween(button, 0.12, { Size = UDim2.fromOffset(66, 66) })
		callback()
	end)

	return button
end

local function makeIconFrame(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3, radius: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Position = position
	frame.Size = size
	frame.Parent = parent
	if radius then
		addCorner(frame, radius)
	end
	return frame
end

local function resolveGuiIconImage(iconName: string): string?
	local iconsFolder = ReplicatedStorage:FindFirstChild("GuiIcons")
	local icon = iconsFolder and iconsFolder:FindFirstChild(iconName)
	if not icon then
		return nil
	end

	if icon:IsA("ImageLabel") or icon:IsA("ImageButton") then
		return icon.Image
	elseif icon:IsA("Decal") or icon:IsA("Texture") then
		return icon.Texture
	elseif icon:IsA("StringValue") then
		return icon.Value
	end

	local nested = icon:FindFirstChildWhichIsA("ImageLabel", true) or icon:FindFirstChildWhichIsA("ImageButton", true)
	if nested and (nested:IsA("ImageLabel") or nested:IsA("ImageButton")) then
		return nested.Image
	end
	return nil
end

local function applyGuiIconImage(button: TextButton, iconName: string): boolean
	local image = resolveGuiIconImage(iconName)
	button.Text = ""
	if not image or image == "" then
		return false
	end

	local icon = Instance.new("ImageLabel")
	icon.Name = "CustomIcon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromOffset(58, 58)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = image
	icon.Parent = button
	return true
end

local function drawMapIcon(button: TextButton)
	button.Text = ""
	local parchment = makeIconFrame(button, "MapParchment", UDim2.fromOffset(13, 12), UDim2.fromOffset(26, 28), Color3.fromRGB(226, 173, 89), 6)
	parchment.Rotation = -10
	makeIconFrame(button, "MapRollTop", UDim2.fromOffset(10, 8), UDim2.fromOffset(31, 8), Color3.fromRGB(167, 92, 39), 8).Rotation = -10
	makeIconFrame(button, "MapRollBottom", UDim2.fromOffset(12, 35), UDim2.fromOffset(31, 8), Color3.fromRGB(167, 92, 39), 8).Rotation = -10
	makeIconFrame(parchment, "TrailOne", UDim2.fromOffset(7, 8), UDim2.fromOffset(12, 3), Color3.fromRGB(145, 82, 43), 3).Rotation = -20
	makeIconFrame(parchment, "TrailTwo", UDim2.fromOffset(10, 17), UDim2.fromOffset(13, 3), Color3.fromRGB(145, 82, 43), 3).Rotation = 18
	makeIconFrame(parchment, "IslandOne", UDim2.fromOffset(4, 15), UDim2.fromOffset(7, 7), Color3.fromRGB(196, 119, 54), 4)
	makeIconFrame(parchment, "IslandTwo", UDim2.fromOffset(18, 5), UDim2.fromOffset(6, 6), Color3.fromRGB(196, 119, 54), 4)
end

local function drawPokerChipIcon(button: TextButton)
	button.Text = ""
	local chip = makeIconFrame(button, "PokerChip", UDim2.fromOffset(10, 10), UDim2.fromOffset(32, 32), Color3.fromRGB(240, 240, 235), 18)
	makeIconFrame(chip, "RedTop", UDim2.fromOffset(11, 0), UDim2.fromOffset(10, 8), Color3.fromRGB(196, 40, 35), 2)
	makeIconFrame(chip, "RedBottom", UDim2.fromOffset(11, 24), UDim2.fromOffset(10, 8), Color3.fromRGB(196, 40, 35), 2)
	makeIconFrame(chip, "RedLeft", UDim2.fromOffset(0, 11), UDim2.fromOffset(8, 10), Color3.fromRGB(196, 40, 35), 2)
	makeIconFrame(chip, "RedRight", UDim2.fromOffset(24, 11), UDim2.fromOffset(8, 10), Color3.fromRGB(196, 40, 35), 2)
	makeIconFrame(chip, "BlackOne", UDim2.fromOffset(4, 4), UDim2.fromOffset(7, 7), Color3.fromRGB(10, 12, 17), 2)
	makeIconFrame(chip, "BlackTwo", UDim2.fromOffset(21, 4), UDim2.fromOffset(7, 7), Color3.fromRGB(10, 12, 17), 2)
	makeIconFrame(chip, "BlackThree", UDim2.fromOffset(4, 21), UDim2.fromOffset(7, 7), Color3.fromRGB(10, 12, 17), 2)
	makeIconFrame(chip, "BlackFour", UDim2.fromOffset(21, 21), UDim2.fromOffset(7, 7), Color3.fromRGB(10, 12, 17), 2)
	local center = makeIconFrame(chip, "ChipCenter", UDim2.fromOffset(8, 8), UDim2.fromOffset(16, 16), Color3.fromRGB(196, 40, 35), 10)
	makeIconFrame(center, "SpadeTop", UDim2.fromOffset(6, 4), UDim2.fromOffset(5, 5), Color3.fromRGB(255, 255, 255), 4)
	makeIconFrame(center, "SpadeStem", UDim2.fromOffset(7, 8), UDim2.fromOffset(3, 5), Color3.fromRGB(255, 255, 255), 1)
end

local startButton = makeIconButton(actionIconBar, "+", 1, function()
	openRunConfirmation(
		"START NEW RUN?",
		"This starts fresh at your base with your unlocked arcade machines.",
		"Start",
		"StartRun"
	)
end)
if not applyGuiIconImage(startButton, "Start") then
	startButton.Text = "+"
end
local restartButton = makeIconButton(actionIconBar, "R", 2, function()
	openRunConfirmation(
		"RESTART RUN?",
		"This abandons your current run and starts over from room 1.",
		"Restart",
		"StartRun"
	)
end)
if not applyGuiIconImage(restartButton, "Restart") then
	restartButton.Text = "R"
end
local pauseButton = makeIconButton(actionIconBar, "II", 3, function()
	actionEvent:FireServer("PauseRun")
end)
if not applyGuiIconImage(pauseButton, "Pause") then
	pauseButton.Text = "II"
end
local resumeButton = makeIconButton(actionIconBar, ">", 4, function()
	actionEvent:FireServer("ResumeRun")
end)
if not applyGuiIconImage(resumeButton, "Resume") then
	resumeButton.Text = ">"
end
local quitButton = makeIconButton(actionIconBar, "X", 5, function()
	openRunConfirmation(
		"QUIT RUN?",
		"This deletes your current run progress. Cash and unlocked machines stay saved.",
		"Quit",
		"QuitRun"
	)
end)
if not applyGuiIconImage(quitButton, "Quit") then
	quitButton.Text = "X"
end
local mapButton = makeIconButton(actionIconBar, "", 6, function()
	mapOpen = not mapOpen
	setMapOpen(mapOpen)
end)
if not applyGuiIconImage(mapButton, "Map") then
	drawMapIcon(mapButton)
end
local casinoButton = makeIconButton(actionIconBar, "", 7, function()
	casinoOpen = not casinoOpen
	setCasinoOpen(casinoOpen)
end)
if not applyGuiIconImage(casinoButton, "Casino") then
	drawPokerChipIcon(casinoButton)
end
casinoButton.Visible = false
casinoButton.Active = false
local shopButton = makeIconButton(actionIconBar, "$", 8, function()
	tokenShopOpen = not tokenShopOpen
	render()
end)
applyGuiIconImage(shopButton, "Shop")
local itemLibraryButton = makeIconButton(actionIconBar, "", 9, function()
	itemLibraryOpen = not itemLibraryOpen
	render()
end)
if not applyGuiIconImage(itemLibraryButton, "ItemLibrary") then
	itemLibraryButton.Text = "?"
end

local shopButtons: { [string]: TextButton } = {}
local mapButtons: { TextButton } = {}
local itemButtons: { [string]: TextButton } = {}

local tokenShopHeader = makeHeader(upgradesFrame, "Machine Shop", 60)
local tokenShopCloseButton = makeButton(upgradesFrame, "Close", 64, function()
	tokenShopOpen = false
	render()
end)
local upgradeButtons: { [string]: TextButton } = {}
local gambleButtons: { [string]: TextButton } = {}
local tooltip = Instance.new("TextLabel")
tooltip.Name = "Tooltip"
tooltip.Visible = false
tooltip.BackgroundColor3 = Color3.fromRGB(12, 14, 19)
tooltip.BackgroundTransparency = 0.04
tooltip.BorderSizePixel = 0
tooltip.Size = UDim2.fromOffset(310, 72)
tooltip.Font = FONT
tooltip.TextColor3 = Color3.fromRGB(255, 248, 221)
tooltip.TextSize = 13
tooltip.TextWrapped = true
tooltip.ZIndex = 20
tooltip.Parent = root
addCorner(tooltip, 6)

local function setTooltip(button: GuiButton, getText: () -> string)
	button.MouseEnter:Connect(function()
		tooltip.Text = getText()
		tooltip.Position = UDim2.fromOffset(mouse.X - 320, mouse.Y + 18)
		tooltip.Visible = true
	end)
	button.MouseLeave:Connect(function()
		tooltip.Visible = false
	end)
	button.MouseMoved:Connect(function(x, y)
		tooltip.Position = UDim2.fromOffset(x - 320, y + 18)
	end)
end

setTooltip(startButton, function()
	return "Start Run\nBegin a fresh run from room 1."
end)
setTooltip(restartButton, function()
	return "Restart Run\nStart over from room 1 after confirmation."
end)
setTooltip(pauseButton, function()
	return "Pause Run\nSave this run in place so you can resume later."
end)
setTooltip(resumeButton, function()
	return "Resume Run\nContinue your paused run."
end)
setTooltip(quitButton, function()
	return "Quit Run\nDiscard current run progress after confirmation."
end)
setTooltip(mapButton, function()
	return "Map\nChoose the next combat room and preview its enemies."
end)
setTooltip(casinoButton, function()
	return "Arcade\nOpen the arcade game panel."
end)
setTooltip(shopButton, function()
	return "Machine Shop\nSpend Cash on new arcade machines."
end)
setTooltip(itemLibraryButton, function()
	return "Item Library\nBrowse unlocked and locked crane items."
end)

local function renderHearts(currentHealth: number, maxHealth: number)
	local displayMax = math.max(0, math.floor(maxHealth))
	local filled = math.max(0, math.floor(currentHealth))
	heartsPanel.Size = UDim2.fromOffset(math.max(112, (displayMax * 46) + 24), 76)

	for index = 1, displayMax do
		local label = heartLabels[index]
		if not label then
			label = Instance.new("TextLabel")
			label.Name = `Heart{index}`
			label.BackgroundTransparency = 1
			label.LayoutOrder = index
			label.Size = UDim2.fromOffset(40, 56)
			label.Font = FONT
			label.Text = "♥"
			label.TextScaled = true
			label.TextStrokeColor3 = Color3.fromRGB(41, 8, 18)
			label.TextStrokeTransparency = 0.08
			label.ZIndex = 26
			label.Parent = heartsPanel
			heartLabels[index] = label
		end
		label.Visible = true
		if index <= filled then
			label.TextColor3 = Color3.fromRGB(255, 42, 66)
			label.TextTransparency = 0
		else
			label.TextColor3 = Color3.fromRGB(82, 69, 80)
			label.TextTransparency = 0.25
		end
	end

	for index = displayMax + 1, #heartLabels do
		heartLabels[index].Visible = false
	end
end

local hitFeedbackBusy = false
local function showHitFeedback(heartsLost: number)
	local amount = math.max(1, math.floor(heartsLost))
	hitFlash.BackgroundTransparency = 0.5
	tween(hitFlash, 0.35, { BackgroundTransparency = 1 })

	hitText.Text = if amount == 1 then "-1 HEART" else `-{amount} HEARTS`
	hitText.Position = UDim2.new(0, 26, 1, -108)
	hitText.TextTransparency = 0
	hitText.TextStrokeTransparency = 0.15
	hitText.Visible = true
	tween(hitText, 0.55, {
		Position = UDim2.new(0, 26, 1, -136),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	if not hitFeedbackBusy then
		hitFeedbackBusy = true
		local basePosition = UDim2.new(0, 18, 1, -24)
		heartsPanel.Position = UDim2.new(0, 10, 1, -24)
		tween(heartsPanel, 0.08, { Position = UDim2.new(0, 28, 1, -24) }).Completed:Wait()
		tween(heartsPanel, 0.12, { Position = basePosition }).Completed:Wait()
		hitFeedbackBusy = false
	end
end

local casinoOverlay = Instance.new("Frame")
casinoOverlay.Name = "CasinoOverlay"
casinoOverlay.BackgroundColor3 = Color3.fromRGB(3, 5, 10)
casinoOverlay.BackgroundTransparency = 1
casinoOverlay.Visible = false
casinoOverlay.Size = UDim2.fromScale(1, 1)
casinoOverlay.Parent = root

local casinoModal = Instance.new("Frame")
casinoModal.Name = "CasinoModal"
casinoModal.AnchorPoint = Vector2.new(0.5, 0.5)
casinoModal.Position = UDim2.fromScale(0.5, 0.5)
casinoModal.Size = UDim2.fromOffset(0, 0)
casinoModal.BackgroundColor3 = Color3.fromRGB(20, 18, 26)
casinoModal.BorderSizePixel = 0
casinoModal.ClipsDescendants = true
casinoModal.Parent = casinoOverlay
addCorner(casinoModal, 8)

local casinoBackdropImages: { [string]: ImageLabel } = {}
local function makeCasinoBackdrop(name: string, iconName: string)
	local image = Instance.new("ImageLabel")
	image.Name = `{name}Backdrop`
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.ScaleType = Enum.ScaleType.Crop
	image.Visible = false
	image.ZIndex = 0
	image.Parent = casinoModal

	local aliases = {
		WhackAMole = { "WhackAMole", "WhackAMole", "WhackAMole" },
		CardBattles = { "CardBattle", "CardBattles", "CardBattles" },
		GuessingGame = { "GuessingGame", "GuessingGame" },
		MysteryWheel = { "MysteryWheel", "MysteryWheeles", "MysteryWheel" },
	}
	local asset = resolveGuiIconImage(iconName)
	if not asset or asset == "" then
		asset = resolveGuiIconImage(name)
	end
	for _, alias in ipairs(aliases[name] or {}) do
		if not asset or asset == "" then
			asset = resolveGuiIconImage(alias)
		end
	end
	if asset and asset ~= "" then
		image.Image = asset
	end
	casinoBackdropImages[name] = image
end

makeCasinoBackdrop("WhackAMole", "WhackAMole")
makeCasinoBackdrop("CardBattles", "CardBattle")
makeCasinoBackdrop("GuessingGame", "GuessingGame")
makeCasinoBackdrop("MysteryWheel", "MysteryWheel")

local modalTitle = Instance.new("TextLabel")
modalTitle.BackgroundTransparency = 1
modalTitle.Position = UDim2.fromOffset(20, 14)
modalTitle.Size = UDim2.new(1, -80, 0, 34)
modalTitle.Font = FONT
modalTitle.Text = ""
modalTitle.TextColor3 = Color3.fromRGB(255, 230, 166)
modalTitle.TextSize = 24
modalTitle.TextXAlignment = Enum.TextXAlignment.Left
modalTitle.ZIndex = 2
modalTitle.Parent = casinoModal

local closeCasinoButton = makeButton(casinoModal, "X", 1, function()
	casinoOpen = false
	setCasinoOpen(false)
end)
closeCasinoButton.Position = UDim2.new(1, -54, 0, 14)
closeCasinoButton.Size = UDim2.fromOffset(34, 34)
closeCasinoButton.ZIndex = 3

local resultStage = Instance.new("Frame")
resultStage.Name = "ResultStage"
resultStage.Position = UDim2.fromOffset(20, 58)
resultStage.Size = UDim2.new(1, -40, 0, 176)
resultStage.BackgroundColor3 = Color3.fromRGB(31, 35, 46)
resultStage.BorderSizePixel = 0
resultStage.ZIndex = 1
resultStage.Parent = casinoModal
addCorner(resultStage, 8)

local resultText = Instance.new("TextLabel")
resultText.Text = ""
resultText.BackgroundTransparency = 1
resultText.Position = UDim2.fromOffset(12, 128)
resultText.Size = UDim2.new(1, -24, 0, 38)
resultText.Font = FONT
resultText.TextColor3 = Color3.fromRGB(255, 248, 221)
resultText.TextSize = 20
resultText.TextWrapped = true
resultText.ZIndex = 2
resultText.Parent = resultStage


local function setCasinoBackdrop(name: string?, scratchLayout: boolean?)
	casinoBackdropName = name
	scratchBackdropOpen = scratchLayout == true
	local activeBackdrop = name and casinoBackdropImages[name] or nil
	for backdropName, image in pairs(casinoBackdropImages) do
		image.Visible = backdropName == name and image.Image ~= ""
	end

	local hasBackdrop = activeBackdrop ~= nil and activeBackdrop.Image ~= ""
	casinoModal.BackgroundTransparency = if hasBackdrop then 1 else 0
	resultStage.BackgroundTransparency = if hasBackdrop then 1 else 0
	resultStage.Position = if scratchBackdropOpen then UDim2.fromOffset(0, 0) else UDim2.fromOffset(20, 58)
	resultStage.Size = if scratchBackdropOpen then UDim2.fromScale(1, 1) else UDim2.new(1, -40, 0, 176)
	resultText.Position = if scratchBackdropOpen then UDim2.fromOffset(70, 222) else UDim2.fromOffset(12, 128)
	resultText.Size = if scratchBackdropOpen then UDim2.fromOffset(380, 48) else UDim2.new(1, -24, 0, 38)
	resultText.TextXAlignment = Enum.TextXAlignment.Center
	casinoOverlay.BackgroundTransparency = if scratchBackdropOpen then 1 else casinoOverlay.BackgroundTransparency
	if casinoOpen then
		local targetSize = if scratchBackdropOpen then UDim2.fromOffset(520, 390) elseif name == "GuessingGame" then UDim2.fromOffset(560, 460) else UDim2.fromOffset(440, 430)
		local targetOverlayTransparency = if scratchBackdropOpen then 1 else 0.28
		tween(casinoOverlay, 0.12, { BackgroundTransparency = targetOverlayTransparency })
		tween(casinoModal, 0.18, { Size = targetSize })
	end
end

local function setScratchBackdrop(open: boolean)
	setCasinoBackdrop(if open then "WhackAMole" else nil, open)
end

local gambleGrid = Instance.new("Frame")
gambleGrid.Name = "GambleGrid"
gambleGrid.BackgroundTransparency = 1
gambleGrid.Position = UDim2.fromOffset(20, 250)
gambleGrid.Size = UDim2.new(1, -40, 0, 150)
gambleGrid.Visible = false
gambleGrid.Parent = casinoModal

local grid = Instance.new("UIGridLayout")
grid.CellPadding = UDim2.fromOffset(10, 10)
grid.CellSize = UDim2.fromOffset(180, 64)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = gambleGrid

local shopOverlay = Instance.new("Frame")
shopOverlay.Name = "ShopOverlay"
shopOverlay.BackgroundColor3 = Color3.fromRGB(3, 5, 10)
shopOverlay.BackgroundTransparency = 1
shopOverlay.Visible = false
shopOverlay.Size = UDim2.fromScale(1, 1)
shopOverlay.Parent = root

local shopModal = Instance.new("Frame")
shopModal.Name = "ShopModal"
shopModal.AnchorPoint = Vector2.new(0.5, 0.5)
shopModal.Position = UDim2.fromScale(0.5, 0.5)
shopModal.Size = UDim2.fromOffset(0, 0)
shopModal.BackgroundColor3 = Color3.fromRGB(20, 18, 26)
shopModal.BorderSizePixel = 0
shopModal.ClipsDescendants = true
shopModal.Parent = shopOverlay
addCorner(shopModal, 8)

local shopTitle = Instance.new("TextLabel")
shopTitle.BackgroundTransparency = 1
shopTitle.Position = UDim2.fromOffset(20, 14)
shopTitle.Size = UDim2.new(1, -80, 0, 34)
shopTitle.Font = FONT
shopTitle.Text = "TICKET BOOTH"
shopTitle.TextColor3 = Color3.fromRGB(255, 230, 166)
shopTitle.TextSize = 24
shopTitle.TextXAlignment = Enum.TextXAlignment.Left
shopTitle.Parent = shopModal

local closeShopButton = makeButton(shopModal, "X", 1, function()
	shopOpen = false
	setShopOpen(false)
end)
closeShopButton.Position = UDim2.new(1, -54, 0, 14)
closeShopButton.Size = UDim2.fromOffset(34, 34)

local shopGrid = Instance.new("Frame")
shopGrid.Name = "ShopGrid"
shopGrid.BackgroundTransparency = 1
shopGrid.Position = UDim2.fromOffset(20, 64)
shopGrid.Size = UDim2.new(1, -40, 1, -84)
shopGrid.Parent = shopModal

local shopGridLayout = Instance.new("UIGridLayout")
shopGridLayout.CellPadding = UDim2.fromOffset(10, 10)
shopGridLayout.CellSize = UDim2.fromOffset(185, 58)
shopGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
shopGridLayout.Parent = shopGrid

local machineShopOverlay = Instance.new("Frame")
machineShopOverlay.Name = "MachineShopOverlay"
machineShopOverlay.BackgroundColor3 = Color3.fromRGB(3, 5, 10)
machineShopOverlay.BackgroundTransparency = 1
machineShopOverlay.Visible = false
machineShopOverlay.Size = UDim2.fromScale(1, 1)
machineShopOverlay.Parent = root

local itemLibraryOverlay = Instance.new("Frame")
itemLibraryOverlay.Name = "ItemLibraryOverlay"
itemLibraryOverlay.BackgroundColor3 = Color3.fromRGB(3, 5, 10)
itemLibraryOverlay.BackgroundTransparency = 1
itemLibraryOverlay.Visible = false
itemLibraryOverlay.Size = UDim2.fromScale(1, 1)
itemLibraryOverlay.Parent = root

local itemLibraryModal = Instance.new("Frame")
itemLibraryModal.Name = "ItemLibraryModal"
itemLibraryModal.AnchorPoint = Vector2.new(0.5, 0.5)
itemLibraryModal.Position = UDim2.fromScale(0.5, 0.5)
itemLibraryModal.Size = UDim2.fromOffset(760, 500)
itemLibraryModal.BackgroundColor3 = Color3.fromRGB(20, 18, 26)
itemLibraryModal.BorderSizePixel = 0
itemLibraryModal.ClipsDescendants = true
itemLibraryModal.Parent = itemLibraryOverlay
addCorner(itemLibraryModal, 8)

local itemLibraryTitle = Instance.new("TextLabel")
itemLibraryTitle.BackgroundTransparency = 1
itemLibraryTitle.Position = UDim2.fromOffset(20, 14)
itemLibraryTitle.Size = UDim2.new(1, -80, 0, 34)
itemLibraryTitle.Font = FONT
itemLibraryTitle.Text = "ITEM LIBRARY"
itemLibraryTitle.TextColor3 = Color3.fromRGB(255, 230, 166)
itemLibraryTitle.TextSize = 24
itemLibraryTitle.TextXAlignment = Enum.TextXAlignment.Left
itemLibraryTitle.Parent = itemLibraryModal

local closeItemLibraryButton = makeButton(itemLibraryModal, "X", 1, function()
	itemLibraryOpen = false
	setItemLibraryOpen(false)
end)
closeItemLibraryButton.Position = UDim2.new(1, -54, 0, 14)
closeItemLibraryButton.Size = UDim2.fromOffset(34, 34)

local itemLibraryScroll = Instance.new("ScrollingFrame")
itemLibraryScroll.BackgroundTransparency = 1
itemLibraryScroll.BorderSizePixel = 0
itemLibraryScroll.Position = UDim2.fromOffset(20, 64)
itemLibraryScroll.Size = UDim2.new(1, -40, 1, -84)
itemLibraryScroll.CanvasSize = UDim2.fromOffset(0, 0)
itemLibraryScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
itemLibraryScroll.ScrollBarThickness = 8
itemLibraryScroll.Parent = itemLibraryModal

local itemLibraryLayout = Instance.new("UIGridLayout")
itemLibraryLayout.CellPadding = UDim2.fromOffset(10, 10)
itemLibraryLayout.CellSize = UDim2.fromOffset(170, 150)
itemLibraryLayout.SortOrder = Enum.SortOrder.LayoutOrder
itemLibraryLayout.Parent = itemLibraryScroll

local machineShopModal = Instance.new("Frame")
machineShopModal.Name = "MachineShopModal"
machineShopModal.AnchorPoint = Vector2.new(0.5, 0.5)
machineShopModal.Position = UDim2.fromScale(0.5, 0.5)
machineShopModal.Size = UDim2.fromOffset(0, 0)
machineShopModal.BackgroundColor3 = Color3.fromRGB(20, 18, 26)
machineShopModal.BorderSizePixel = 0
machineShopModal.ClipsDescendants = true
machineShopModal.Parent = machineShopOverlay
addCorner(machineShopModal, 8)

upgradesFrame.Parent = machineShopModal
upgradesFrame.Position = UDim2.fromOffset(20, 18)
upgradesFrame.Size = UDim2.new(1, -40, 1, -36)

local mapOverlay = Instance.new("Frame")
mapOverlay.Name = "MapOverlay"
mapOverlay.BackgroundColor3 = Color3.fromRGB(3, 5, 10)
mapOverlay.BackgroundTransparency = 1
mapOverlay.Visible = false
mapOverlay.Size = UDim2.fromScale(1, 1)
mapOverlay.Parent = root

local mapModal = Instance.new("Frame")
mapModal.Name = "MapModal"
mapModal.AnchorPoint = Vector2.new(0.5, 0.5)
mapModal.Position = UDim2.fromScale(0.5, 0.5)
mapModal.Size = UDim2.fromOffset(0, 0)
mapModal.BackgroundColor3 = Color3.fromRGB(20, 18, 26)
mapModal.BorderSizePixel = 0
mapModal.ClipsDescendants = true
mapModal.Parent = mapOverlay
addCorner(mapModal, 8)

local mapTitle = Instance.new("TextLabel")
mapTitle.BackgroundTransparency = 1
mapTitle.Position = UDim2.fromOffset(20, 14)
mapTitle.Size = UDim2.new(1, -80, 0, 34)
mapTitle.Font = FONT
mapTitle.Text = "MAP"
mapTitle.TextColor3 = Color3.fromRGB(255, 230, 166)
mapTitle.TextSize = 24
mapTitle.TextXAlignment = Enum.TextXAlignment.Left
mapTitle.Parent = mapModal

local closeMapButton = makeButton(mapModal, "X", 1, function()
	mapOpen = false
	setMapOpen(false)
end)
closeMapButton.Position = UDim2.new(1, -54, 0, 14)
closeMapButton.Size = UDim2.fromOffset(34, 34)

local mapHint = Instance.new("TextLabel")
mapHint.BackgroundTransparency = 1
mapHint.Position = UDim2.fromOffset(20, 54)
mapHint.Size = UDim2.new(1, -40, 0, 42)
mapHint.Font = FONT
mapHint.Text = "Follow the rooms in order. Click the next square to fight."
mapHint.TextColor3 = Color3.fromRGB(232, 236, 244)
mapHint.TextSize = 15
mapHint.TextWrapped = true
mapHint.TextXAlignment = Enum.TextXAlignment.Left
mapHint.Parent = mapModal

local mapGrid = Instance.new("Frame")
mapGrid.Name = "MapGrid"
mapGrid.BackgroundTransparency = 1
mapGrid.Position = UDim2.fromOffset(20, 108)
mapGrid.Size = UDim2.new(1, -40, 1, -132)
mapGrid.Parent = mapModal

local mapGridLayout = Instance.new("UIListLayout")
mapGridLayout.FillDirection = Enum.FillDirection.Horizontal
mapGridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
mapGridLayout.Padding = UDim.new(0, 10)
mapGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
mapGridLayout.Parent = mapGrid

local confirmRunOverlay = Instance.new("Frame")
confirmRunOverlay.Name = "ConfirmRunOverlay"
confirmRunOverlay.BackgroundColor3 = Color3.fromRGB(3, 5, 10)
confirmRunOverlay.BackgroundTransparency = 1
confirmRunOverlay.Visible = false
confirmRunOverlay.Size = UDim2.fromScale(1, 1)
confirmRunOverlay.Parent = root

local confirmRunModal = Instance.new("Frame")
confirmRunModal.Name = "ConfirmRunModal"
confirmRunModal.AnchorPoint = Vector2.new(0.5, 0.5)
confirmRunModal.Position = UDim2.fromScale(0.5, 0.5)
confirmRunModal.Size = UDim2.fromOffset(0, 0)
confirmRunModal.BackgroundColor3 = Color3.fromRGB(20, 18, 26)
confirmRunModal.BorderSizePixel = 0
confirmRunModal.ClipsDescendants = true
confirmRunModal.Parent = confirmRunOverlay
addCorner(confirmRunModal, 8)

local confirmTitle = Instance.new("TextLabel")
confirmTitle.BackgroundTransparency = 1
confirmTitle.Position = UDim2.fromOffset(20, 16)
confirmTitle.Size = UDim2.new(1, -40, 0, 34)
confirmTitle.Font = FONT
confirmTitle.Text = "START NEW RUN?"
confirmTitle.TextColor3 = Color3.fromRGB(255, 230, 166)
confirmTitle.TextSize = 22
confirmTitle.TextXAlignment = Enum.TextXAlignment.Left
confirmTitle.Parent = confirmRunModal

local confirmText = Instance.new("TextLabel")
confirmText.BackgroundTransparency = 1
confirmText.Position = UDim2.fromOffset(20, 62)
confirmText.Size = UDim2.new(1, -40, 0, 70)
confirmText.Font = FONT
confirmText.Text = "This starts fresh at your base with your unlocked arcade machines."
confirmText.TextColor3 = Color3.fromRGB(232, 236, 244)
confirmText.TextSize = 16
confirmText.TextWrapped = true
confirmText.TextXAlignment = Enum.TextXAlignment.Left
confirmText.TextYAlignment = Enum.TextYAlignment.Top
confirmText.Parent = confirmRunModal

local confirmStartButton = makeButton(confirmRunModal, "Confirm", 1, function()
	confirmRunOpen = false
	setConfirmRunOpen(false)
	local action = pendingConfirmAction
	pendingConfirmAction = "StartRun"
	actionEvent:FireServer(action)
end)
confirmStartButton.Position = UDim2.new(0, 20, 1, -58)
confirmStartButton.Size = UDim2.new(0.5, -26, 0, 38)

local cancelStartButton = makeButton(confirmRunModal, "Cancel", 2, function()
	confirmRunOpen = false
	setConfirmRunOpen(false)
end)
cancelStartButton.Position = UDim2.new(0.5, 6, 1, -58)
cancelStartButton.Size = UDim2.new(0.5, -26, 0, 38)

openRunConfirmation = function(title: string, body: string, confirmButtonText: string, actionName: string)
	confirmTitle.Text = title
	confirmText.Text = body
	confirmStartButton.Text = confirmButtonText
	pendingConfirmAction = actionName
	confirmRunOpen = true
	setConfirmRunOpen(true)
end

local function getMetaCost(upgradeConfig, level: number): number
	return upgradeConfig.BaseCost + (level * 2)
end

local function isGambleUnlocked(state, gambleName: string): boolean
	if gambleName == "WhackAMole" then
		return true
	end
	local meta = state and state.Meta
	return meta ~= nil and meta.Unlocks ~= nil and meta.Unlocks[gambleName] == true
end

local function getGambleCost(gambleName: string): number?
	local gambles = currentState and currentState.Config and currentState.Config.Gambles
	local gamble = gambles and gambles[gambleName]
	return gamble and gamble.Cost
end

local function gambleCostText(gambleName: string, overrideCost: number?): string
	local cost = overrideCost or getGambleCost(gambleName)
	return if cost then tostring(cost) .. " Tokens" else "? Tokens"
end

local function openPhysicalCasinoGame(gambleName: string)
	local run = currentState and currentState.Run
	if not run or not run.Active or run.InCombat then
		render()
		return
	end
	if not isGambleUnlocked(currentState, gambleName) then
		render()
		return
	end
	casinoOpen = true
	setCasinoOpen(true)
	if gambleName == "WhackAMole" then
		showwhackAMoleStart({
			Buying = true,
			Slots = 10,
			Rounds = (currentState.Config.Gambles.WhackAMole and currentState.Config.Gambles.WhackAMole.Rounds) or 12,
			Cost = getGambleCost("WhackAMole"),
			HitPoints = (currentState.Config.Gambles.WhackAMole and currentState.Config.Gambles.WhackAMole.HitPoints) or 5,
		})
	elseif gambleName == "CardBattles" then
		showCardBattlesStart()
	elseif gambleName == "GuessingGame" then
		showGuessingGameChoices()
	elseif gambleName == "MysteryWheel" then
		showMysteryWheelStart()
	else
		actionEvent:FireServer("Gamble", gambleName)
	end
end

setCasinoOpen = function(open: boolean)
	casinoOverlay.Visible = true
	local targetSize = if open then (if scratchBackdropOpen then UDim2.fromOffset(520, 390) elseif casinoBackdropName == "GuessingGame" then UDim2.fromOffset(560, 460) else UDim2.fromOffset(440, 430)) else UDim2.fromOffset(0, 0)
	local targetTransparency = if open then (if scratchBackdropOpen then 1 else 0.28) else 1
	tween(casinoOverlay, 0.15, { BackgroundTransparency = targetTransparency })
	local modalTween = tween(casinoModal, 0.2, { Size = targetSize })
	if not open then
		modalTween.Completed:Connect(function()
			if not casinoOpen then
				casinoOverlay.Visible = false
			end
		end)
	end
end

setShopOpen = function(open: boolean)
	shopOverlay.Visible = true
	local targetSize = if open then UDim2.fromOffset(440, 430) else UDim2.fromOffset(0, 0)
	local targetTransparency = if open then 0.28 else 1
	tween(shopOverlay, 0.15, { BackgroundTransparency = targetTransparency })
	local modalTween = tween(shopModal, 0.2, { Size = targetSize })
	if not open then
		modalTween.Completed:Connect(function()
			if not shopOpen then
				shopOverlay.Visible = false
			end
		end)
	end
end

local function setMachineShopOpen(open: boolean)
	machineShopOverlay.Visible = true
	local targetSize = if open then UDim2.fromOffset(440, 340) else UDim2.fromOffset(0, 0)
	local targetTransparency = if open then 0.28 else 1
	tween(machineShopOverlay, 0.15, { BackgroundTransparency = targetTransparency })
	local modalTween = tween(machineShopModal, 0.2, { Size = targetSize })
	if not open then
		modalTween.Completed:Connect(function()
			if not tokenShopOpen then
				machineShopOverlay.Visible = false
			end
		end)
	end
end

setItemLibraryOpen = function(open: boolean)
	itemLibraryOverlay.Visible = true
	local targetSize = if open then UDim2.fromOffset(760, 500) else UDim2.fromOffset(0, 0)
	local targetTransparency = if open then 0.28 else 1
	tween(itemLibraryOverlay, 0.15, { BackgroundTransparency = targetTransparency })
	local modalTween = tween(itemLibraryModal, 0.2, { Size = targetSize })
	if not open then
		modalTween.Completed:Connect(function()
			if not itemLibraryOpen then
				itemLibraryOverlay.Visible = false
			end
		end)
	end
end

setMapOpen = function(open: boolean)
	mapOverlay.Visible = true
	local targetSize = if open then UDim2.fromOffset(500, 410) else UDim2.fromOffset(0, 0)
	local targetTransparency = if open then 0.28 else 1
	tween(mapOverlay, 0.15, { BackgroundTransparency = targetTransparency })
	local modalTween = tween(mapModal, 0.2, { Size = targetSize })
	if not open then
		modalTween.Completed:Connect(function()
			if not mapOpen then
				mapOverlay.Visible = false
			end
		end)
	end
end

setConfirmRunOpen = function(open: boolean)
	confirmRunOverlay.Visible = true
	local targetSize = if open then UDim2.fromOffset(380, 210) else UDim2.fromOffset(0, 0)
	local targetTransparency = if open then 0.28 else 1
	tween(confirmRunOverlay, 0.15, { BackgroundTransparency = targetTransparency })
	local modalTween = tween(confirmRunModal, 0.2, { Size = targetSize })
	if not open then
		modalTween.Completed:Connect(function()
			if not confirmRunOpen then
				confirmRunOverlay.Visible = false
			end
		end)
	end
end

clearStage = function()
	for _, child in ipairs(resultStage:GetChildren()) do
		if child ~= resultText and not child:IsA("UICorner") then
			child:Destroy()
		end
	end
end

makeStageLabel = function(text: string, position: UDim2, size: UDim2, color: Color3)
	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = color
	label.BorderSizePixel = 0
	label.Position = position
	label.Size = size
	label.Font = FONT
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.ZIndex = 2
	label.Parent = resultStage
	addCorner(label, 6)
	return label
end

local function colorFromTriplet(triplet)
	return Color3.fromRGB(triplet[1], triplet[2], triplet[3])
end

local ROULETTE_RED: { [number]: boolean } = GameConfig.RouletteLookup.Red

local function guessingGameColorName(value): string
	if value == "0" or value == "00" then
		return "Green"
	end
	return if ROULETTE_RED[tonumber(value) or 0] then "Red" else "Black"
end

local function guessingGameColor3(value): Color3
	local color = guessingGameColorName(value)
	if color == "Green" then
		return Color3.fromRGB(38, 132, 78)
	elseif color == "Red" then
		return Color3.fromRGB(176, 43, 49)
	end
	return Color3.fromRGB(22, 24, 29)
end

showwhackAMoleStart = function(data)
	activeMiniGame = "WhackAMole"
	animatingGamble = false
	setCasinoBackdrop("WhackAMole", false)
	clearStage()
	scratchTiles = {}
	resultText.Text = "Whack some Moles!"
	local costText = gambleCostText("WhackAMole", data.Cost)
	if data.Buying then
		resultText.Position = UDim2.fromOffset(12, 132)
		resultText.Text = `Whack-a-Mole costs {costText}. Earn Tickets from your score.`
		local buyButton = makeStageButton(`Play Whack-a-Mole ({costText})`, UDim2.fromOffset(108, 76), function()
			actionEvent:FireServer("Gamble", "WhackAMole")
		end)
		buyButton.Size = UDim2.fromOffset(224, 46)
		return
	end
	resultText.Position = UDim2.fromOffset(12, 132)
	resultText.Text = `Score: 0    Hit +{data.HitPoints or 5}    Avoid fakes.`

	local slots = data.Slots or 10
	for i = 1, slots do
		local button = Instance.new("TextButton")
		button.Name = `WhackSlot{i}`
		button.BackgroundColor3 = Color3.fromRGB(42, 48, 62)
		button.BorderSizePixel = 0
		button.Position = UDim2.fromOffset(36 + (((i - 1) % 5) * 74), 20 + (math.floor((i - 1) / 5) * 62))
		button.Size = UDim2.fromOffset(58, 48)
		button.Font = FONT
		button.Text = ""
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.TextSize = 15
		button.ZIndex = 3
		button.Parent = resultStage
		addCorner(button, 6)
		scratchTiles[i] = button
		button.Activated:Connect(function()
			actionEvent:FireServer("WhackMoleHit", {
				Slot = i,
				Round = button:GetAttribute("Round"),
			})
		end)
	end
end

local function whackAMole(data)
	if data.Event == "WhackMolePop" then
		for index, button in pairs(scratchTiles) do
			button:SetAttribute("Round", data.Round)
			button.Text = ""
			button.BackgroundColor3 = Color3.fromRGB(42, 48, 62)
			if index == data.MoleSlot then
				button.Text = "MOLE"
				button.BackgroundColor3 = Color3.fromRGB(74, 190, 114)
			elseif index == data.FakeSlot then
				button.Text = "FAKE"
				button.BackgroundColor3 = Color3.fromRGB(184, 53, 86)
			end
		end
		resultText.Text = `Round {data.Round}    Score: {data.Score or 0}`
		local round = data.Round
		task.delay((data.Duration or 0.85) + 0.03, function()
			for _, button in pairs(scratchTiles) do
				if button.Parent and button:GetAttribute("Round") == round then
					button.Text = ""
					button.BackgroundColor3 = Color3.fromRGB(42, 48, 62)
				end
			end
		end)
		return
	elseif data.Event == "WhackMoleEnd" then
		activeMiniGame = nil
		for _, button in pairs(scratchTiles) do
			button.Text = ""
			button.BackgroundColor3 = Color3.fromRGB(42, 48, 62)
		end
		resultText.Position = UDim2.fromOffset(12, 225)
		resultText.Text = `Done: {data.Score} points for {data.Tickets} Tickets`
		local costText = gambleCostText("WhackAMole", data.Cost)
		local replay = makeStageButton(`Play Again ({costText})`, UDim2.fromOffset(122, 136), function()
			actionEvent:FireServer("Gamble", "WhackAMole")
		end)
		replay.Size = UDim2.fromOffset(196, 38)
		return
	end

	local tile = scratchTiles[data.Slot]
	if not tile then
		return
	end
	playSfx(if data.Correct then 72764897006138 else 121661337260877, if data.Correct then 0.45 else 0.16)
	tween(tile, 0.15, {
		BackgroundColor3 = if data.Correct then Color3.fromRGB(74, 190, 114) else Color3.fromRGB(255, 76, 91),
		Size = UDim2.fromOffset(62, 52),
	}).Completed:Wait()
	tween(tile, 0.12, { Size = UDim2.fromOffset(58, 48) })
	resultText.Text = `Score: {data.Score}    {if data.Delta >= 0 then "+" else ""}{data.Delta} points`
end

local function cardText(card): string
	return card.Rank
end

local function drawCardRow(cards, y: number, hiddenSecond: boolean)
	for i, card in ipairs(cards) do
		local text = if hiddenSecond and i == 2 then "?" else cardText(card)
		local cardGui = makeStageLabel(text, UDim2.fromOffset(20 + ((i - 1) * 48), y), UDim2.fromOffset(40, 54), Color3.fromRGB(238, 238, 232))
		cardGui.TextColor3 = Color3.fromRGB(28, 31, 39)
	end
end

makeStageButton = function(text: string, position: UDim2, callback: () -> ())
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = Color3.fromRGB(54, 63, 82)
	button.BorderSizePixel = 0
	button.Position = position
	button.Size = UDim2.fromOffset(96, 36)
	button.Font = FONT
	button.Text = text
	button.TextColor3 = Color3.fromRGB(246, 248, 252)
	button.TextSize = 14
	button.ZIndex = 3
	button.Parent = resultStage
	addCorner(button, 6)
	button.Activated:Connect(callback)
	return button
end

showCardBattlesStart = function()
	activeMiniGame = "CardBattles"
	animatingGamble = false
	setCasinoBackdrop("CardBattles", false)
	clearStage()
	resultStage.Size = UDim2.new(1, -40, 0, 270)
	resultText.Position = UDim2.fromOffset(12, 218)
	resultText.Size = UDim2.new(1, -24, 0, 42)
	resultText.Text = "Battle an arcade worker in a game of cards!"
	for _, button in ipairs(CardBattlesButtons) do
		button:Destroy()
	end
	CardBattlesButtons = {}

	local costText = gambleCostText("CardBattles", nil)
	makeStageLabel("CARD BATTLE", UDim2.fromOffset(98, 24), UDim2.fromOffset(220, 42), Color3.fromRGB(54, 63, 82))
	local playButton = makeStageButton(`Play Card Battle ({costText})`, UDim2.fromOffset(105, 84), function()
		resultText.Text = "Dealing cards..."
		actionEvent:FireServer("Gamble", "CardBattles")
	end)
	playButton.Size = UDim2.fromOffset(205, 42)
	CardBattlesButtons = { playButton }
end

showCardBattle = function(data)
	activeMiniGame = if data.Ended then nil else "CardBattles"
	animatingGamble = false
	setCasinoBackdrop("CardBattles", false)
	clearStage()
	resultStage.Size = UDim2.new(1, -40, 0, 270)
	resultText.Position = UDim2.fromOffset(12, 218)
	resultText.Size = UDim2.new(1, -24, 0, 42)
	for _, button in ipairs(CardBattlesButtons) do
		button:Destroy()
	end
	CardBattlesButtons = {}

	makeStageLabel("YOU", UDim2.fromOffset(20, 10), UDim2.fromOffset(70, 24), Color3.fromRGB(54, 63, 82))
	drawCardRow(data.PlayerCards, 40, false)
	makeStageLabel("WORKER", UDim2.fromOffset(20, 104), UDim2.fromOffset(90, 24), Color3.fromRGB(54, 63, 82))
	drawCardRow(data.DealerCards, 132, data.HideDealerCard)

	local dealerTotal = if data.DealerTotal then ` Worker: {data.DealerTotal}` else ""
	resultText.Text = `{data.Status}   You: {data.PlayerTotal}{dealerTotal}`
	if not data.Ended then
		local hit = makeStageButton("Hit", UDim2.fromOffset(286, 54), function()
			actionEvent:FireServer("CardBattlesHit")
		end)
		local stand = makeStageButton("Stand", UDim2.fromOffset(286, 104), function()
			actionEvent:FireServer("CardBattlesStand")
		end)
		CardBattlesButtons = { hit, stand }
	else
		local costText = gambleCostText("CardBattles", data.Cost)
		local replay = makeStageButton(`Play Again ({costText})`, UDim2.fromOffset(254, 104), function()
			resultText.Text = "Dealing cards..."
			actionEvent:FireServer("Gamble", "CardBattles")
		end)
		replay.Size = UDim2.fromOffset(140, 38)
		CardBattlesButtons = { replay }
	end
end

showMysteryWheelStart = function()
	activeMiniGame = "MysteryWheel"
	animatingGamble = false
	setCasinoBackdrop("MysteryWheel", false)
	clearStage()

	resultText.Text = "Spin the wheel to win Tickets."
	resultText.Visible = true
	resultText.TextColor3 = Color3.fromRGB(255, 248, 221)

	local costText = gambleCostText("MysteryWheel", nil)
	local label = makeStageLabel("MYSTERY WHEEL", UDim2.fromOffset(76, 24), UDim2.fromOffset(260, 42), Color3.fromRGB(54, 63, 82))
	label.BackgroundTransparency = if casinoBackdropImages.MysteryWheel and casinoBackdropImages.MysteryWheel.Image ~= "" then 0.25 else 0
	local playButton = makeStageButton(`Spin Wheel ({costText})`, UDim2.fromOffset(105, 84), function()
		resultText.Text = "Spinning wheel..."
		actionEvent:FireServer("Gamble", "MysteryWheel")
	end)
	playButton.Size = UDim2.fromOffset(205, 42)
end

local function animateMysteryWheel(data)
	activeMiniGame = nil
	animatingGamble = true
	setCasinoBackdrop("MysteryWheel", false)
	clearStage()
	resultText.Text = "Spinning..."
	local crate = makeStageLabel("SPIN", UDim2.fromOffset(132, 26), UDim2.fromOffset(150, 92), Color3.fromRGB(139, 84, 43))
	local rarities = data.Rarities or {}
	for i = 1, 22 do
		local rarity = rarities[((i - 1) % #rarities) + 1]
		if rarity then
			crate.Text = rarity.Name
			crate.BackgroundColor3 = colorFromTriplet(rarity.Color)
		end
		tween(crate, 0.04, { Rotation = if i % 2 == 0 then 5 else -5 }).Completed:Wait()
	end
	crate.Rotation = 0
	crate.Text = data.Rarity
	tween(crate, 0.2, {
		BackgroundColor3 = colorFromTriplet(data.Color),
		Size = UDim2.fromOffset(170, 104),
		Position = UDim2.fromOffset(122, 18),
	})
	resultText.Text = `{data.Rarity}! +{data.Tickets or data.Cash} Tickets`
	animatingGamble = false
	local costText = gambleCostText("MysteryWheel", data.Cost)
	local replay = makeStageButton(`Spin Again ({costText})`, UDim2.fromOffset(122, 124), function()
		resultText.Text = "Spinning wheel..."
		actionEvent:FireServer("Gamble", "MysteryWheel")
	end)
	replay.Size = UDim2.fromOffset(170, 38)
end

showGuessingGameChoices = function()
	activeMiniGame = "GuessingGame"
	setCasinoBackdrop("GuessingGame", false)
	clearStage()
	tween(casinoModal, 0.18, { Size = UDim2.fromOffset(560, 460) })
	resultStage.Size = UDim2.new(1, -40, 0, 350)
	resultText.Position = UDim2.fromOffset(18, 306)
	resultText.Size = UDim2.new(1, -36, 0, 36)
	local costText = gambleCostText("GuessingGame", nil)
	resultText.Text = `Choose a guess. Play costs {costText}.`
	local choices = {
		{ Text = "Red", Bet = { Type = "Color", Value = "Red" } },
		{ Text = "Black", Bet = { Type = "Color", Value = "Black" } },
		{ Text = "Even", Bet = { Type = "Parity", Value = "Even" } },
		{ Text = "Odd", Bet = { Type = "Parity", Value = "Odd" } },
	}
	for i, choice in ipairs(choices) do
		local x = 28 + (((i - 1) % 2) * 118)
		local y = 26 + (math.floor((i - 1) / 2) * 46)
		local button = makeStageButton(choice.Text, UDim2.fromOffset(x, y), function()
			activeMiniGame = nil
			actionEvent:FireServer("GuessingGameBet", choice.Bet)
		end)
		if choice.Text == "Red" then
			button.BackgroundColor3 = guessingGameColor3(1)
		elseif choice.Text == "Black" then
			button.BackgroundColor3 = guessingGameColor3(2)
		end
	end
	local numbers = { "0", "00" }
	for number = 1, 36 do
		table.insert(numbers, tostring(number))
	end
	for index, numberText in ipairs(numbers) do
		local col = (index - 1) % 13
		local row = math.floor((index - 1) / 13)
		local button = makeStageButton(numberText, UDim2.fromOffset(28 + (col * 38), 132 + (row * 34)), function()
			activeMiniGame = nil
			actionEvent:FireServer("GuessingGameBet", { Type = "Number", Value = numberText })
		end)
		button.Size = UDim2.fromOffset(32, 28)
		button.TextSize = 13
		button.BackgroundColor3 = guessingGameColor3(numberText)
	end
end

local function animateGuessingGameResult(data)
	activeMiniGame = nil
	animatingGamble = true
	setCasinoBackdrop("GuessingGame", false)
	clearStage()
	local wheel = makeStageLabel("1", UDim2.fromOffset(132, 18), UDim2.fromOffset(150, 104), guessingGameColor3(1))
	local spinValues = { "0", "00" }
	for number = 1, 36 do
		table.insert(spinValues, tostring(number))
	end
	for i = 1, 18 do
		local value = spinValues[math.random(1, #spinValues)]
		wheel.Text = value
		wheel.BackgroundColor3 = guessingGameColor3(value)
		task.wait(0.045)
	end
	wheel.Text = tostring(data.Result)
	wheel.BackgroundColor3 = guessingGameColor3(data.Result)
	resultText.Text = `{data.Result} {data.ResultColor or guessingGameColorName(data.Result)} - {data.BetValue}: {if data.Won then "Win" else "Loss"} +{data.Tickets or data.Cash} Tickets`
	animatingGamble = false
	local costText = gambleCostText("GuessingGame", data.Cost)
	local replay = makeStageButton(`Play Again ({costText})`, UDim2.fromOffset(190, 160), function()
		showGuessingGameChoices()
	end)
	replay.Size = UDim2.fromOffset(180, 38)
end

local function animateQuickResult(data)
	resultText.Text = "Rolling..."
	local reel = makeStageLabel("0", UDim2.fromOffset(126, 18), UDim2.fromOffset(160, 104), Color3.fromRGB(92, 47, 133))
	for i = 1, 14 do
		reel.Text = tostring(math.random(0, 9)) .. tostring(math.random(0, 9)) .. tostring(math.random(0, 9))
		reel.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(184, 53, 86) else Color3.fromRGB(92, 47, 133)
		task.wait(0.06)
	end
	reel.Text = if data.Cash > 0 then tostring(data.Cash) .. " Tickets" else "MISS"
end

local function animateGambleResult(data)
	casinoOpen = true
	setCasinoOpen(true)
	if data.Event == "whackAMoleStart" or data.Event == "WhackMoleStart" then
		showwhackAMoleStart(data)
	elseif data.Event == "ScratchReveal" or data.Event == "WhackMolePop" or data.Event == "WhackMoleHit" or data.Event == "WhackMoleEnd" then
		whackAMole(data)
	elseif data.Event == "CardBattle" then
		showCardBattle(data)
	elseif data.GambleName == "CardBattles" then
		showCardBattle(data)
	elseif data.Event == "MysteryWheel" or data.GambleName == "MysteryWheel" then
		animateMysteryWheel(data)
	elseif data.Event == "GuessingGameResult" or data.GambleName == "GuessingGame" then
		animateGuessingGameResult(data)
	else
		animatingGamble = true
		setScratchBackdrop(false)
		clearStage()
		resultText.Text = data.DisplayName
		animateQuickResult(data)
		local reward = if data.Item then data.Item else tostring(data.Tickets or data.Cash) .. " Tickets"
		resultText.Text = `{data.DisplayName}: {data.Text} ({reward})`
		tween(resultText, 0.12, { TextSize = 24 }).Completed:Wait()
		tween(resultText, 0.14, { TextSize = 20 })
		animatingGamble = false
	end
end

local function rebuildStaticButtons(state)
	if not state or not state.Config then
		return
	end

	for index, gambleName in ipairs(orderNames.Gambles) do
		if not gambleButtons[gambleName] and state.Config.Gambles[gambleName] then
			local gamble = state.Config.Gambles[gambleName]
			gambleButtons[gambleName] = makeButton(gambleGrid, "", index, function()
				if not isGambleUnlocked(currentState, gambleName) then
					return
				end

				local run = currentState and currentState.Run
				local cost = gamble.Cost or 0

				if not run or (run.Cash or 0) < cost then
					resultText.Text = `Not enough Tokens. Need {cost}.`
					resultText.TextColor3 = Color3.fromRGB(255, 90, 90)
					resultText.Visible = true
					return
				end

				if not animatingGamble and not activeMiniGame then
					if gambleName == "GuessingGame" then
						showGuessingGameChoices()
					elseif gambleName == "MysteryWheel" then
						showMysteryWheelStart()
					else
						actionEvent:FireServer("Gamble", gambleName)
					end
				end
			end)
			gambleButtons[gambleName].Name = gambleName
			gambleButtons[gambleName].Text = `{gamble.DisplayName}\n{gamble.Cost} Tokens`
			setTooltip(gambleButtons[gambleName], function()
				if not isGambleUnlocked(currentState, gambleName) then
					return "????\nBeat runs and spend Cash to reveal this machine."
				end
				return `{gamble.DisplayName}\n{gamble.Description}\nCost: {gamble.Cost} Tokens`
			end)
		end
	end

	for index, itemName in ipairs(orderNames.ShopItems) do
		if not shopButtons[itemName] and state.Config.ShopItems[itemName] then
			local item = state.Config.ShopItems[itemName]
			shopButtons[itemName] = makeButton(shopGrid, "", index, function()
				actionEvent:FireServer("BuyItem", itemName)
			end)
			shopButtons[itemName].Name = itemName
			shopButtons[itemName].Text = `{item.DisplayName} - {item.Cost} Tickets`
			setTooltip(shopButtons[itemName], function()
				local run = currentState and currentState.Run
				local shopState = currentState and currentState.ShopState
				if itemName == "Sword" then
					local barrel = shopState and shopState.Sword
					local level = barrel and barrel.Level or 0
					local damage = barrel and barrel.Damage or (run and run.Damage or 0)
					local nextCost = barrel and barrel.Cost or item.Cost
					return `Laser Amplifier {level + 1}\nCurrent laser damage: {damage}\nNext upgrade: +10 damage\nCost: {nextCost} Tickets`
				elseif itemName == "CoinCharm" then
					return `Lucky Token\nCurrent luck: {run and math.floor((run.LuckBonus or 0) * 100) or 0}%\nAdds +6% luck to arcade prizes this run.`
				elseif itemName == "CashMagnet" then
					local magnet = shopState and shopState.CashMagnet
					local level = magnet and magnet.Level or 0
					local bonus = magnet and magnet.BonusPercent or 0
					local nextCost = magnet and magnet.Cost or item.Cost
					return `Token Magnet {level + 1}\nCurrent enemy token bonus: {bonus}%\nNext upgrade: +10% enemy tokens\nCost: {nextCost} Tickets`
				end
				return `{item.DisplayName}\n{item.Description}\nCost: {item.Cost} Tickets`
			end)
		end
	end

	for index, gambleName in ipairs(orderNames.GameUnlocks) do
		if not upgradeButtons[gambleName] and state.Config.GameUnlocks and state.Config.GameUnlocks[gambleName] then
			upgradeButtons[gambleName] = makeButton(upgradesFrame, "", 60 + index, function()
				actionEvent:FireServer("BuyGameUnlock", gambleName)
			end)
			upgradeButtons[gambleName].Name = gambleName
			setTooltip(upgradeButtons[gambleName], function()
				local unlock = currentState and currentState.Config and currentState.Config.GameUnlocks and currentState.Config.GameUnlocks[gambleName]
				if not unlock then
					return "Unavailable"
				end
				local wins = currentState and currentState.Meta and (currentState.Meta.Wins or 0) or 0
				local requiredWins = unlock.RequiredWins or 0
				return `{unlock.DisplayName}\n{unlock.Description}\nCost: {unlock.Cost} Cash\nWins: {wins}/{requiredWins}`
			end)
		end
	end

	local itemOrder = {}
	if state.Config.Items then
		for name in pairs(state.Config.Items) do
			table.insert(itemOrder, name)
		end
		table.sort(itemOrder)
	end
	for index, itemName in ipairs(itemOrder) do
		if not itemButtons[itemName] then
			local item = state.Config.Items[itemName]
			local button = makeButton(itemLibraryScroll, "", index, function()
				-- library is informational only
			end)
			button.Size = UDim2.fromOffset(170, 150)
			button.Text = ""
			button.TextTransparency = 1
			itemButtons[itemName] = button
			local sprite = Instance.new("ImageLabel")
			sprite.Name = "Sprite"
			sprite.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
			sprite.BackgroundTransparency = 0.15
			sprite.Position = UDim2.fromOffset(45, 16)
			sprite.Size = UDim2.fromOffset(80, 80)
			sprite.ScaleType = Enum.ScaleType.Fit
			sprite.Parent = button
			addCorner(sprite, 8)
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "Name"
			nameLabel.BackgroundTransparency = 1
			nameLabel.Position = UDim2.fromOffset(10, 104)
			nameLabel.Size = UDim2.new(1, -20, 0, 28)
			nameLabel.Font = FONT
			nameLabel.TextColor3 = Color3.fromRGB(255, 230, 166)
			nameLabel.TextSize = 14
			nameLabel.TextWrapped = true
			nameLabel.TextXAlignment = Enum.TextXAlignment.Center
			nameLabel.Parent = button
			local infoLabel = Instance.new("TextLabel")
			infoLabel.Name = "Info"
			infoLabel.BackgroundTransparency = 1
			infoLabel.Position = UDim2.fromOffset(10, 130)
			infoLabel.Size = UDim2.new(1, -20, 0, 16)
			infoLabel.Font = FONT
			infoLabel.TextColor3 = Color3.fromRGB(190, 196, 210)
			infoLabel.TextSize = 11
			infoLabel.TextWrapped = true
			infoLabel.TextXAlignment = Enum.TextXAlignment.Center
			infoLabel.TextYAlignment = Enum.TextYAlignment.Center
			infoLabel.Parent = button
			setTooltip(button, function()
				local state = currentState
				local currentItem = state and state.Config and state.Config.Items and state.Config.Items[itemName]
				if not currentItem then
					return "Unavailable"
				end
				local unlocked = currentItem.AlwaysUnlocked == true
				if not unlocked and state and state.ItemState and state.ItemState.Unlocks then
					unlocked = state.ItemState.Unlocks[itemName] == true
				end
				if not unlocked and state and state.Meta and state.Meta.ItemUnlocks then
					unlocked = state.Meta.ItemUnlocks[itemName] == true
				end
				local requirement = currentItem.UnlockText or "Unlock requirement unknown."
				if currentItem.AlwaysUnlocked then
					requirement = "Always unlocked."
				end
				local progressText = ""
				local progress = state and state.ItemState and state.ItemState.Progress and state.ItemState.Progress[itemName]
				if not currentItem.AlwaysUnlocked and type(progress) == "table" and progress.Goal then
					local current = math.min(tonumber(progress.Current) or 0, tonumber(progress.Goal) or 0)
					progressText = `\nProgress: {current}/{progress.Goal}`
				end
				if unlocked then
					return `{currentItem.Name or itemName}\n{currentItem.Tooltip or "No tooltip yet."}\nRarity: {currentItem.Rarity or "Unknown"}{progressText}`
				end
				return `???\nUnlock: {requirement}{progressText}`
			end)
		end
	end

	for index = 1, 5 do
		if not mapButtons[index] then
			local button = Instance.new("TextButton")
			button.AutoButtonColor = true
			button.BackgroundColor3 = Color3.fromRGB(54, 63, 82)
			button.BorderSizePixel = 0
			button.LayoutOrder = index
			button.Size = UDim2.fromOffset(78, 78)
			button.Font = FONT
			button.Text = ""
			button.TextColor3 = Color3.fromRGB(246, 248, 252)
			button.TextSize = 16
			button.TextWrapped = true
			button.Parent = mapGrid
			addCorner(button, 8)
			button.Activated:Connect(function()
				if mapButtons[index]:GetAttribute("IsNext") == true then
					tween(mapButtons[index], 0.08, { BackgroundColor3 = Color3.fromRGB(255, 246, 150) })
					mapOpen = false
					setMapOpen(false)
					actionEvent:FireServer("StartFight")
				end
			end)
			button.Name = `MapSquare{index}`
			button.TextXAlignment = Enum.TextXAlignment.Center
			button.TextYAlignment = Enum.TextYAlignment.Center
			setTooltip(button, function()
				local node = currentState and currentState.MapPath and currentState.MapPath[index]
				if not node then
					return "Locked\nStart a run to reveal the map."
				end
				return `{node.DisplayName} - {node.Status}\nEnemies: {node.EnemySummary}`
			end)
			mapButtons[index] = button
		end
	end
end

local function setButtonUsable(button: TextButton, usable: boolean)
	button.Active = usable
	button.AutoButtonColor = usable
	if button:GetAttribute("IconButton") == true then
		button.BackgroundTransparency = 1
	else
		button.BackgroundColor3 = if usable then Color3.fromRGB(54, 63, 82) else Color3.fromRGB(40, 42, 48)
	end
	button.TextColor3 = if usable then Color3.fromRGB(246, 248, 252) else Color3.fromRGB(140, 146, 158)
end

local function maybeOpenTutorial(state)
	local meta = state and state.Meta
	if tutorialDismissedThisSession then
		return
	end
	if meta and meta.TutorialSeen == true then
		return
	end
	tutorialOpen = true
	tutorialOverlay.Visible = true
	refreshTutorialPage()
end

render = function()
	local state = currentState
	rebuildStaticButtons(state)
	setCasinoOpen(casinoOpen)
	setShopOpen(shopOpen)
	setMachineShopOpen(tokenShopOpen)
	setItemLibraryOpen(itemLibraryOpen)
	setMapOpen(mapOpen)
	setConfirmRunOpen(confirmRunOpen)
	tutorialOverlay.Visible = tutorialOpen

	if not state then
		stats.Text = "Loading..."
		countdownLabel.Visible = false
		heartsPanel.Visible = false
		return
	end

	maybeOpenTutorial(state)

	local run = state.Run
	local meta = state.Meta
	local countdown = run and (run.BattleCountdown or 0) or 0
	if countdown > 0 then
		countdownLabel.Text = tostring(countdown)
		countdownLabel.Visible = true
		countdownLabel.TextTransparency = 0
		countdownLabel.TextStrokeTransparency = 0
		countdownLabel.Size = UDim2.fromOffset(360, 200)
		tween(countdownLabel, 0.18, { Size = UDim2.fromOffset(300, 165) })
	else
		countdownLabel.Visible = false
	end
	if run and run.Active then
		local fightLabel = if run.Room > state.Config.RoomsToBoss then "Boss" else `Room {run.Room}/{state.Config.RoomsToBoss}`
		stats.Text = `Tokens: {run.Cash}\nTickets: {run.Tickets or 0}\nDamage: {run.Damage}\nLuck: {math.floor((run.LuckBonus or 0) * 100)}%\n{fightLabel}\nCash: {meta and meta.Tokens or 0}`
		heartsPanel.Visible = true
		renderHearts(run.Health or 0, run.MaxHealth or 0)
	elseif run and run.Paused then
		local fightLabel = if run.Room > state.Config.RoomsToBoss then "Boss" else `Room {run.Room}/{state.Config.RoomsToBoss}`
		stats.Text = `Paused Run\nTokens: {run.Cash}\nTickets: {run.Tickets or 0}\nDamage: {run.Damage}\n{fightLabel}\nCash: {meta and meta.Tokens or 0}`
		heartsPanel.Visible = false
	else
		stats.Text = `No Active Run\nCash: {meta and meta.Tokens or 0}\nStart Fresh`
		heartsPanel.Visible = false
	end
	local runActive = run ~= nil and run.Active == true
	local runPaused = run ~= nil and run.Paused == true and not runActive
	local betweenRuns = not runActive and not runPaused
	if runActive then
		tokenShopOpen = false
	end
	startButton.Visible = not runActive and not runPaused
	restartButton.Visible = runActive
	pauseButton.Visible = runActive
	resumeButton.Visible = runPaused
	quitButton.Visible = runActive
	setButtonUsable(startButton, startButton.Visible)
	setButtonUsable(restartButton, restartButton.Visible)
	setButtonUsable(pauseButton, pauseButton.Visible)
	setButtonUsable(resumeButton, resumeButton.Visible)
	setButtonUsable(quitButton, quitButton.Visible)
	local showRunIcons = runActive
	mapButton.Visible = showRunIcons
	shopButton.Visible = not runActive
	setButtonUsable(mapButton, showRunIcons and not run.InCombat)
	casinoButton.Visible = false
	casinoButton.Active = false
	setButtonUsable(shopButton, not runActive)
	upgradesFrame.Visible = tokenShopOpen
	tokenShopHeader.Visible = tokenShopOpen
	tokenShopCloseButton.Visible = tokenShopOpen

	for gambleName, button in pairs(gambleButtons) do
		local gamble = state.Config.Gambles[gambleName]
		local unlocked = isGambleUnlocked(state, gambleName)
		local canUse = unlocked and run ~= nil and run.Active and not run.InCombat and run.Cash >= gamble.Cost and not animatingGamble and not activeMiniGame
		button.Text = if unlocked then `{gamble.DisplayName}\n{gamble.Cost} Tokens` else "????\n??"
		setButtonUsable(button, canUse)
		if not unlocked then
			button.BackgroundColor3 = Color3.fromRGB(31, 33, 39)
			button.TextColor3 = Color3.fromRGB(118, 122, 132)
		end
	end

	for itemName, button in pairs(shopButtons) do
		local item = state.Config.ShopItems[itemName]
		local displayCost = item.Cost
		local displayName = item.DisplayName
		if itemName == "Sword" and state.ShopState and state.ShopState.Sword then
			displayCost = state.ShopState.Sword.Cost
			displayName = `Laser Amplifier {state.ShopState.Sword.Level + 1}`
		elseif itemName == "CashMagnet" and state.ShopState and state.ShopState.CashMagnet then
			displayCost = state.ShopState.CashMagnet.Cost
			displayName = `Token Magnet {state.ShopState.CashMagnet.Level + 1}`
		end
		local canUse = run ~= nil and run.Active and not run.InCombat and (run.Tickets or 0) >= displayCost
		button.Text = `{displayName} - {displayCost} Tickets`
		setButtonUsable(button, canUse)
	end

	for itemName, button in pairs(itemButtons) do
		local item = state.Config.Items and state.Config.Items[itemName]
		if item then
			local unlocked = false
			if item.AlwaysUnlocked then
				unlocked = true
			elseif state.ItemState and state.ItemState.Unlocks then
				unlocked = state.ItemState.Unlocks[itemName] == true
			elseif state.Meta and state.Meta.ItemUnlocks then
				unlocked = state.Meta.ItemUnlocks[itemName] == true
			end
			local spriteId = item.Sprite or ""
			local nameLabel = button:FindFirstChild("Name")
			local infoLabel = button:FindFirstChild("Info")
			local image = button:FindFirstChild("Sprite")
			if image and image:IsA("ImageLabel") then
				image.Image = if unlocked then spriteId else ""
				image.ImageTransparency = if unlocked and spriteId ~= "" then 0 else 0.55
				image.BackgroundColor3 = if unlocked then Color3.fromRGB(18, 20, 26) else Color3.fromRGB(40, 42, 48)
			end
			if nameLabel and nameLabel:IsA("TextLabel") then
				nameLabel.Text = if unlocked then item.Name or itemName else "???"
				nameLabel.TextColor3 = if unlocked then Color3.fromRGB(255, 230, 166) else Color3.fromRGB(150, 154, 166)
			end
			if infoLabel and infoLabel:IsA("TextLabel") then
				infoLabel.Text = if unlocked then item.Rarity or "" else "Locked"
			end
			button.BackgroundColor3 = if unlocked then Color3.fromRGB(54, 63, 82) else Color3.fromRGB(31, 33, 39)
			button.Text = ""
			button.Visible = itemLibraryOpen
			button.Active = true
			button.AutoButtonColor = false
			button.TextColor3 = Color3.fromRGB(246, 248, 252)
		end
	end

	for index, button in ipairs(mapButtons) do
		local node = state.MapPath and state.MapPath[index]
		if node then
			button:SetAttribute("IsNext", node.IsNext == true)
			button.Size = UDim2.fromOffset(78, 78)
			button.Text = if node.IsBoss then "BOSS" else tostring(node.Index)
			button.Visible = true
			setButtonUsable(button, run ~= nil and run.Active and not run.InCombat and node.IsNext == true)
			if node.Status == "Cleared" then
				button.BackgroundColor3 = Color3.fromRGB(46, 118, 83)
				button.TextColor3 = Color3.fromRGB(220, 255, 230)
			elseif node.IsNext then
				button.BackgroundColor3 = Color3.fromRGB(217, 183, 87)
				button.TextColor3 = Color3.fromRGB(20, 18, 24)
			elseif node.IsBoss then
				button.BackgroundColor3 = Color3.fromRGB(72, 38, 70)
				button.TextColor3 = Color3.fromRGB(238, 68, 212)
			end
		else
			button:SetAttribute("IsNext", false)
			button.Text = "Locked"
			button.Visible = false
		end
	end

	for gambleName, button in pairs(upgradeButtons) do
		local unlock = state.Config.GameUnlocks and state.Config.GameUnlocks[gambleName]
		if unlock then
			local unlocked = isGambleUnlocked(state, gambleName)
			local wins = meta and (meta.Wins or 0) or 0
			local requiredWins = unlock.RequiredWins or 0
			local availableByWins = wins >= requiredWins
			button.Visible = tokenShopOpen
			if unlocked then
				button.Text = `{unlock.DisplayName} unlocked`
			elseif not availableByWins then
				button.Text = `{unlock.DisplayName} - locked\nWin {requiredWins} runs`
			else
				button.Text = `{unlock.DisplayName} - {unlock.Cost} Cash`
			end
			setButtonUsable(button, tokenShopOpen and not (run and run.InCombat) and meta ~= nil and not unlocked and availableByWins and meta.Tokens >= unlock.Cost)
			if not unlocked and not availableByWins then
				button.BackgroundColor3 = Color3.fromRGB(40, 42, 48)
				button.TextColor3 = Color3.fromRGB(140, 146, 158)
			end
		end
	end
end

messageEvent.OnClientEvent:Connect(function(text)
	resultText.Text = tostring(text)
	resultText.TextColor3 = Color3.fromRGB(255, 255, 255)
	resultText.Visible = true
end)

stateEvent.OnClientEvent:Connect(function(state)
	currentState = state
	render()
end)

gambleResultEvent.OnClientEvent:Connect(function(data)
	task.spawn(function()
		animateGambleResult(data)
		render()
	end)
end)

feedbackEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or data.Event ~= "Hit" then
		return
	end
	task.spawn(function()
		showHitFeedback(tonumber(data.HeartsLost) or 1)
	end)
end)

interactionEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	if data.Event == "TokenShop" then
		tokenShopOpen = true
		render()
	elseif data.Event == "TicketBooth" then
		local run = currentState and currentState.Run
		if run and run.Active and not run.InCombat then
			shopOpen = true
			setShopOpen(true)
			render()
		end
	elseif (data.Event == "ArcadeGame" or data.Event == "CasinoGame") and type(data.GambleName) == "string" then
		openPhysicalCasinoGame(data.GambleName)
	end
end)

task.defer(function()
	while not currentState do
		actionEvent:FireServer("RequestState")
		task.wait(1)
	end
end)
