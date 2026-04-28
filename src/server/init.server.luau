local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local InsertService = game:GetService("InsertService")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local STORE_NAME = "ArcadeRushMetaV1"
local metaStore = DataStoreService:GetDataStore(STORE_NAME)
local useDataStore = not RunService:IsStudio()

local remotes = ReplicatedStorage:FindFirstChild("ArcadeRushRemotes") or ReplicatedStorage:FindFirstChild("CasinoRogueliteRemotes") or Instance.new("Folder")
remotes.Name = "ArcadeRushRemotes"
remotes.Parent = ReplicatedStorage

local guiIcons = ReplicatedStorage:FindFirstChild("GuiIcons") or Instance.new("Folder")
guiIcons.Name = "GuiIcons"
guiIcons.Parent = ReplicatedStorage

local function ensureGuiImageValues()
	for name, image in pairs(GameConfig.GuiImages or {}) do
		if type(image) == "string" and image ~= "" then
			local existing = guiIcons:FindFirstChild(name)
			local imageValue

			if existing and existing:IsA("StringValue") then
				imageValue = existing
			else
				if existing then
					existing:Destroy()
				end

				imageValue = Instance.new("StringValue")
				imageValue.Name = name
				imageValue.Parent = guiIcons
			end

			imageValue.Value = image
		end
	end
end

ensureGuiImageValues()

local function remoteEvent(name: string): RemoteEvent
	local existing = remotes:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = remotes
	return event
end

local actionEvent = remoteEvent("Action")
local stateEvent = remoteEvent("State")
local messageEvent = remoteEvent("Message")
local gambleResultEvent = remoteEvent("GambleResult")
local feedbackEvent = remoteEvent("Feedback")
local interactionEvent = remoteEvent("Interaction")

local arena = Workspace:FindFirstChild("ArcadeRushArena") or Workspace:FindFirstChild("CasinoArena") or Instance.new("Folder")
arena.Name = "ArcadeRushArena"
arena.Parent = Workspace

local weaponFolder = ServerStorage:FindFirstChild("RunWeapons") or Instance.new("Folder")
weaponFolder.Name = "RunWeapons"
weaponFolder.Parent = ServerStorage

local editableRoomTemplates = Workspace:FindFirstChild("ArcadeRushRoomTemplates") or Instance.new("Folder")
editableRoomTemplates.Name = "ArcadeRushRoomTemplates"
editableRoomTemplates.Parent = Workspace

local runtimeRoomTemplates = ServerStorage:FindFirstChild("ArcadeRushRuntimeRoomTemplates") or Instance.new("Folder")
runtimeRoomTemplates.Name = "ArcadeRushRuntimeRoomTemplates"
runtimeRoomTemplates.Parent = ServerStorage

local function refreshRuntimeRoomTemplates()
	runtimeRoomTemplates:ClearAllChildren()
	for _, child in ipairs(editableRoomTemplates:GetChildren()) do
		if child:IsA("Model") or child:IsA("Folder") then
			local clone = child:Clone()
			clone:SetAttribute("UseAuthoredWorldPosition", child:GetAttribute("UseGeneratedPlacement") ~= true)
			clone.Parent = runtimeRoomTemplates
		end
	end

	if #editableRoomTemplates:GetChildren() > 0 then
		editableRoomTemplates.Parent = ServerStorage
	end
end

refreshRuntimeRoomTemplates()

type MetaState = {
	Tokens: number,
	Upgrades: { [string]: number },
	Unlocks: { [string]: boolean },
	Wins: number,
}

type RunState = {
	Active: boolean,
	Paused: boolean,
	Room: number,
	Cash: number,
	Tickets: number,
	Health: number,
	MaxHealth: number,
	Damage: number,
	LuckBonus: number,
	BarrelLevel: number,
	GambleCap: number,
	GamblesLeft: number,
	GambleVoucherLevel: number,
	CashBonusLevel: number,
	EnemiesAlive: number,
	InCombat: boolean,
	BattleCountdown: number,
	BossDefeated: boolean,
}

local metaByPlayer: { [Player]: MetaState } = {}
local runsByPlayer: { [Player]: RunState } = {}
local rngByPlayer: { [Player]: Random } = {}
local scratchByPlayer: { [Player]: any } = {}
local CardBattlesByPlayer: { [Player]: any } = {}
local arenaSlotByPlayer: { [Player]: number } = {}
local arenaSlotOccupied: { [number]: boolean } = {}
local handleAction: (Player, string, any?) -> () = function() end
local addEnemySpawnEffect: (Folder, Vector3, boolean?) -> () = function() end
local buildRoom: (Player) -> () = function() end

local BASE_COLUMNS_PER_SIDE = 4
local BASE_SPACING_X = 170
local BASE_ROW_Z = 165
local BASE_WORLD_CENTER = Vector3.new(0, 2, 0)
local COMBAT_WORLD_Z = 1100

local function getUpgrade(meta: MetaState?, upgradeName: string): number
	if not meta then
		return 0
	end

	return meta.Upgrades[upgradeName] or 0
end

local function isGambleUnlocked(meta: MetaState?, gambleName: string): boolean
	if gambleName == "WhackAMole" then
		return true
	end
	return meta ~= nil and meta.Unlocks ~= nil and meta.Unlocks[gambleName] == true
end

local function canBuyGameUnlock(meta: MetaState?, gambleName: string): (boolean, string?)
	local unlock = GameConfig.GameUnlocks[gambleName]
	if not meta or not unlock then
		return false, nil
	end
	local requiredWins = unlock.RequiredWins or 0
	if (meta.Wins or 0) < requiredWins then
		return false, `Requires {requiredWins} run wins.`
	end
	if meta.Tokens < unlock.Cost then
		return false, "Not enough Cash."
	end
	return true, nil
end

local function getMetaCost(upgradeName: string, level: number): number
	local upgrade = GameConfig.MetaUpgrades[upgradeName]
	return upgrade.BaseCost + (level * 2)
end

local function playerFolder(player: Player): Folder
	local folder = arena:FindFirstChild(tostring(player.UserId))
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = tostring(player.UserId)
	folder.Parent = arena
	return folder
end

local function baseOriginForPlayer(player: Player): Vector3
	local slot = arenaSlotByPlayer[player]
	if not slot then
		slot = 1
		while arenaSlotOccupied[slot] do
			slot += 1
		end
		arenaSlotByPlayer[player] = slot
		arenaSlotOccupied[slot] = true
	end

	local slotIndex = slot - 1
	local sideIndex = slotIndex % (BASE_COLUMNS_PER_SIDE * 2)
	local ring = math.floor(slotIndex / (BASE_COLUMNS_PER_SIDE * 2))
	local column = sideIndex % BASE_COLUMNS_PER_SIDE
	local northSide = sideIndex >= BASE_COLUMNS_PER_SIDE
	local rowOffset = ring * 145
	local x = (column - ((BASE_COLUMNS_PER_SIDE - 1) / 2)) * BASE_SPACING_X
	local z = if northSide then BASE_ROW_Z + rowOffset else -BASE_ROW_Z - rowOffset
	return BASE_WORLD_CENTER + Vector3.new(x, 0, z)
end

local function baseYawForPlayer(player: Player): number
	local slot = arenaSlotByPlayer[player]
	if not slot then
		baseOriginForPlayer(player)
		slot = arenaSlotByPlayer[player]
	end

	local slotIndex = (slot or 1) - 1
	local sideIndex = slotIndex % (BASE_COLUMNS_PER_SIDE * 2)
	return if sideIndex >= BASE_COLUMNS_PER_SIDE then math.rad(180) else 0
end

local function combatOriginForPlayer(player: Player): Vector3
	local slot = arenaSlotByPlayer[player]
	if not slot then
		baseOriginForPlayer(player)
		slot = arenaSlotByPlayer[player]
	end

	local slotIndex = (slot or 1) - 1
	local x = (slotIndex - 3.5) * 150
	return Vector3.new(x, 2, COMBAT_WORLD_Z)
end

local function teleportPlayer(player: Player, position: Vector3)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CFrame = CFrame.new(position)
	end
end

local function setPlayerBattleFrozen(player: Player, frozen: boolean)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") then
		root.Anchored = frozen
	end
	if humanoid then
		if frozen then
			if humanoid:GetAttribute("PreBattleWalkSpeed") == nil then
				humanoid:SetAttribute("PreBattleWalkSpeed", humanoid.WalkSpeed)
			end
			if humanoid:GetAttribute("PreBattleJumpPower") == nil then
				humanoid:SetAttribute("PreBattleJumpPower", humanoid.JumpPower)
			end
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			humanoid.AutoRotate = false
		else
			humanoid.WalkSpeed = humanoid:GetAttribute("PreBattleWalkSpeed") or 16
			humanoid.JumpPower = humanoid:GetAttribute("PreBattleJumpPower") or 50
			humanoid:SetAttribute("PreBattleWalkSpeed", nil)
			humanoid:SetAttribute("PreBattleJumpPower", nil)
			humanoid.AutoRotate = true
		end
	end
end

local function battleCountdownActive(run: RunState?): boolean
	return run ~= nil and run.InCombat and (run.BattleCountdown or 0) > 0
end

local function clearCombatRoom(player: Player)
	local folder = arena:FindFirstChild(tostring(player.UserId))
	local combatRoom = folder and folder:FindFirstChild("CombatRoom")
	if combatRoom then
		combatRoom:Destroy()
	end
end

local function clearPlayerArena(player: Player)
	local folder = arena:FindFirstChild(tostring(player.UserId))
	if folder then
		folder:Destroy()
	end
end

local function sendMessage(player: Player, text: string)
	messageEvent:FireClient(player, text)
end

local function countEnemyTypes(enemyTypes: { string }): { [string]: number }
	local counts = {}
	for _, enemyType in ipairs(enemyTypes) do
		counts[enemyType] = (counts[enemyType] or 0) + 1
	end
	return counts
end

local function makeEnemySummary(enemyTypes: { string }): string
	local counts = countEnemyTypes(enemyTypes)
	local parts = {}
	for _, enemyType in ipairs({ "Grunt", "Brute", "Dealer", "Boss" }) do
		local count = counts[enemyType]
		local stats = GameConfig.Enemies[enemyType]
		if count and stats then
			table.insert(parts, `{count}x {stats.DisplayName}`)
		end
	end
	return table.concat(parts, ", ")
end

local function enemyTypesForRoom(roomNumber: number): { string }
	if roomNumber > GameConfig.Run.RoomsToBoss then
		return { "Boss" }
	end

	local layouts = {
		{ "Grunt", "Grunt", "Brute" },
		{ "Grunt", "Grunt", "Grunt", "Brute", "Brute" },
		{ "Grunt", "Grunt", "Grunt", "Grunt", "Dealer" },
		{ "Grunt", "Grunt", "Grunt", "Dealer", "Dealer", "Brute", "Brute", "Brute", "Brute", "Brute", "Brute" },
	}
	local selected = layouts[roomNumber] or layouts[#layouts]
	local enemies = {}
	for _, enemyType in ipairs(selected) do
		table.insert(enemies, enemyType)
	end
	return enemies
end

local function mapPathForRun(run: RunState?)
	if not run or not run.Active then
		return {}
	end

	local path = {}
	local bossIndex = GameConfig.Run.RoomsToBoss + 1
	for roomNumber = 1, bossIndex do
		local isBoss = roomNumber == bossIndex
		local enemies = enemyTypesForRoom(roomNumber)
		local status = "Locked"
		if roomNumber < run.Room then
			status = "Cleared"
		elseif roomNumber == run.Room then
			status = "Next"
		end
		table.insert(path, {
			Index = roomNumber,
			DisplayName = if isBoss then "Final Cabinet" else `Room {roomNumber}`,
			Subtitle = if isBoss then "Final boss" else "Next fight",
			EnemyTypes = enemies,
			EnemySummary = makeEnemySummary(enemies),
			Status = status,
			IsBoss = isBoss,
			IsNext = status == "Next",
		})
	end
	return path
end

local function publicState(player: Player)
	local run = runsByPlayer[player]
	local meta = metaByPlayer[player]
	local shopState = {}
	if run then
		local barrel = GameConfig.ShopItems.Sword
		local cashMagnet = GameConfig.ShopItems.CashMagnet
		shopState.Sword = {
			Level = run.BarrelLevel or 0,
			Cost = barrel.Cost + ((run.BarrelLevel or 0) * barrel.CostIncrease),
			Damage = run.Damage,
		}
		shopState.CashMagnet = {
			Level = run.CashBonusLevel or 0,
			Cost = cashMagnet.Cost + ((run.CashBonusLevel or 0) * cashMagnet.CostIncrease),
			BonusPercent = (run.CashBonusLevel or 0) * 10,
		}
	end

	return {
		Run = run,
		Meta = meta,
		ShopState = shopState,
		MapPath = mapPathForRun(run),
		Config = {
			Gambles = GameConfig.Gambles,
			ShopItems = GameConfig.ShopItems,
			MetaUpgrades = GameConfig.MetaUpgrades,
			GameUnlocks = GameConfig.GameUnlocks,
			UnlockOrder = { "CardBattles", "GuessingGame", "MysteryWheel" },
			RoomsToBoss = GameConfig.Run.RoomsToBoss,
		},
	}
end

local function pushState(player: Player)
	stateEvent:FireClient(player, publicState(player))
end

local function makePart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function makeNeon(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
	local part = makePart(parent, name, size, position, color)
	part.Material = Enum.Material.Neon
	return part
end

local function localBaseCFrame(player: Player, offset: Vector3): CFrame
	local origin = baseOriginForPlayer(player)
	return CFrame.new(origin) * CFrame.Angles(0, baseYawForPlayer(player), 0) * CFrame.new(offset)
end

local function rotateDescendantsAround(folder: Instance, origin: Vector3, yaw: number)
	if math.abs(yaw) < 0.001 then
		return
	end

	local pivot = CFrame.new(origin)
	local rotation = CFrame.Angles(0, yaw, 0)
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local localCFrame = pivot:ToObjectSpace(descendant.CFrame)
			descendant.CFrame = pivot * rotation * localCFrame
		end
	end
end

local function ensureSharedBasePlaza()
	local plaza = arena:FindFirstChild("SharedBasePlaza")
	if plaza then
		plaza:Destroy()
	end

	plaza = Instance.new("Folder")
	plaza.Name = "SharedBasePlaza"
	plaza.Parent = arena

	local maxRing = 0
	for _, slot in pairs(arenaSlotByPlayer) do
		local ring = math.floor((slot - 1) / (BASE_COLUMNS_PER_SIDE * 2))
		maxRing = math.max(maxRing, ring)
	end

	local platformWidth = (BASE_COLUMNS_PER_SIDE * BASE_SPACING_X) + 170
	local platformDepth = (BASE_ROW_Z * 2) + 180 + (maxRing * 290)
	local mainPlatform = makePart(plaza, "SharedBlackPlatform", Vector3.new(platformWidth, 1, platformDepth), Vector3.new(BASE_WORLD_CENTER.X, -0.85, BASE_WORLD_CENTER.Z), Color3.fromRGB(8, 9, 13))
	mainPlatform.Material = Enum.Material.Slate

	local centerStrip = makePart(plaza, "CentralWalkway", Vector3.new(platformWidth - 80, 0.25, 34), Vector3.new(BASE_WORLD_CENTER.X, -0.1, BASE_WORLD_CENTER.Z), Color3.fromRGB(18, 21, 29))
	centerStrip.Material = Enum.Material.DiamondPlate

	for _, player in ipairs(Players:GetPlayers()) do
		if arenaSlotByPlayer[player] then
			local origin = baseOriginForPlayer(player)
			local yaw = baseYawForPlayer(player)
			local front = (CFrame.new(origin) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0, 58)).Position
			local center = Vector3.new(origin.X, -0.1, BASE_WORLD_CENTER.Z)
			local delta = center - Vector3.new(front.X, -0.1, front.Z)
			local length = math.max(delta.Magnitude, 8)
			local pathCenter = Vector3.new(front.X, -0.1, front.Z):Lerp(center, 0.5)
			local path = makePart(plaza, `BasePath_{player.UserId}`, Vector3.new(32, 0.25, length), pathCenter, Color3.fromRGB(16, 18, 25))
			path.Material = Enum.Material.DiamondPlate
			path.CFrame = CFrame.lookAt(pathCenter, center)

			local glow = makeNeon(plaza, `BasePathGlow_{player.UserId}`, Vector3.new(2, 0.08, length), pathCenter + Vector3.new(0, 0.16, 0), Color3.fromRGB(80, 168, 228))
			glow.Transparency = 0.25
			glow.CFrame = CFrame.lookAt(pathCenter + Vector3.new(0, 0.12, 0), center)
		end
	end
end

local function addPrompt(part: BasePart, actionText: string, objectText: string, callback: (Player) -> ())
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(callback)
	return prompt
end

local function firstBasePart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function prepareCreatorModel(instance: Instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = true
		end
	end
end

local function moveCreatorInstance(instance: Instance, offset: Vector3)
	if instance:IsA("Model") then
		instance:PivotTo(instance:GetPivot() + offset)
	elseif instance:IsA("BasePart") then
		instance.CFrame = instance.CFrame + offset
	end
end

local function alignCreatorBottomToY(instance: Instance, floorY: number?)
	if not floorY then
		return
	end

	local bottomY: number? = nil
	if instance:IsA("Model") then
		local boundsCFrame, boundsSize = instance:GetBoundingBox()
		bottomY = boundsCFrame.Position.Y - (boundsSize.Y / 2)
	elseif instance:IsA("BasePart") then
		bottomY = instance.Position.Y - (instance.Size.Y / 2)
	end

	if bottomY then
		local lift = floorY - bottomY
		if math.abs(lift) > 0.01 then
			moveCreatorInstance(instance, Vector3.new(0, lift, 0))
		end
	end
end

local function getCreatorAssetId(category: string, assetName: string): number
	local assets = GameConfig.CreatorStoreAssets
	local categoryAssets = assets and assets[category]
	if type(categoryAssets) ~= "table" then
		return 0
	end
	return tonumber(categoryAssets[assetName]) or 0
end

local function findRenderableChild(container: Instance): Instance?
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") or child:IsA("BasePart") then
			return child
		end
	end
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("Model") then
			return descendant
		end
	end
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function loadCreatorTemplate(assetName: string, aliases: { string }?): Instance?
	local roots = { ServerStorage, ReplicatedStorage, Workspace }
	local folderNames = { "ArcadeRushAssetTemplates", "AnteboundAssetTemplates", "CreatorStoreAssets", "ToolboxAssets" }
	local names = { assetName }
	for _, alias in ipairs(aliases or {}) do
		table.insert(names, alias)
	end
	for _, root in ipairs(roots) do
		for _, folderName in ipairs(folderNames) do
			local folder = root:FindFirstChild(folderName)
			if folder then
				for _, name in ipairs(names) do
					local template = folder:FindFirstChild(name, true)
					if template then
						local clone = template:Clone()
						if clone:IsA("Model") or clone:IsA("BasePart") then
							prepareCreatorModel(clone)
							return clone
						end
						local renderable = findRenderableChild(clone)
						if renderable then
							renderable.Parent = nil
							clone:Destroy()
							prepareCreatorModel(renderable)
							return renderable
						end
						clone:Destroy()
					end
				end
			end
		end
	end
	return nil
end

local function loadRoomTemplate(templateName: string): Instance?
	local folders = {
		runtimeRoomTemplates,
		ServerStorage:FindFirstChild("ArcadeRushRoomTemplates"),
		ServerStorage:FindFirstChild("RoomTemplates"),
		ReplicatedStorage:FindFirstChild("ArcadeRushRoomTemplates"),
		ReplicatedStorage:FindFirstChild("RoomTemplates"),
		Workspace:FindFirstChild("ArcadeRushRoomTemplates"),
		Workspace:FindFirstChild("RoomTemplates"),
	}

	for _, folder in ipairs(folders) do
		local template = folder and folder:FindFirstChild(templateName)
		if template and (template:IsA("Model") or template:IsA("Folder")) then
			local clone = template:Clone()
			for _, descendant in ipairs(clone:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
				end
			end
			return clone
		end
	end
	return nil
end

local function loadFirstRoomTemplate(templateNames: { string }): Instance?
	for _, templateName in ipairs(templateNames) do
		local template = loadRoomTemplate(templateName)
		if template then
			return template
		end
	end
	return nil
end

local function hasRoomTemplate(templateName: string): boolean
	local template = loadRoomTemplate(templateName)
	if template then
		template:Destroy()
		return true
	end
	return false
end

local function usesAuthoredWorldPosition(instance: Instance): boolean
	return instance:GetAttribute("UseAuthoredWorldPosition") == true and instance:GetAttribute("UseGeneratedPlacement") ~= true
end

local function folderBoundsCFrame(folder: Instance): CFrame
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local found = false
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			found = true
			local half = descendant.Size / 2
			local position = descendant.Position
			minX = math.min(minX, position.X - half.X)
			minY = math.min(minY, position.Y - half.Y)
			minZ = math.min(minZ, position.Z - half.Z)
			maxX = math.max(maxX, position.X + half.X)
			maxY = math.max(maxY, position.Y + half.Y)
			maxZ = math.max(maxZ, position.Z + half.Z)
		end
	end

	if not found then
		return CFrame.identity
	end

	return CFrame.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
end

local function templatePivotCFrame(instance: Instance): CFrame
	local pivotMarker = instance:FindFirstChild("RoomOrigin", true) or instance:FindFirstChild("TemplatePivot", true) or instance:FindFirstChild("Origin", true)
	if pivotMarker and pivotMarker:IsA("BasePart") then
		return pivotMarker.CFrame
	elseif pivotMarker and pivotMarker:IsA("CFrameValue") then
		return pivotMarker.Value
	elseif instance:IsA("Model") then
		return instance:GetPivot()
	elseif instance:IsA("Folder") then
		return folderBoundsCFrame(instance)
	end
	return CFrame.identity
end

local function pivotRoomTemplate(instance: Instance, targetCFrame: CFrame)
	if instance:IsA("Model") then
		local pivotCFrame = templatePivotCFrame(instance)
		local delta = targetCFrame * pivotCFrame:Inverse()
		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.CFrame = delta * descendant.CFrame
			end
		end
	elseif instance:IsA("Folder") then
		local pivotCFrame = templatePivotCFrame(instance)

		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				local localCFrame = pivotCFrame:ToObjectSpace(descendant.CFrame)
				descendant.CFrame = targetCFrame * localCFrame
			end
		end
	end
end

local function findNamedDescendant(root: Instance, names: { string }): Instance?
	for _, name in ipairs(names) do
		if root.Name == name then
			return root
		end
		local child = root:FindFirstChild(name, true)
		if child then
			return child
		end
	end
	return nil
end

local function cframeOfInstance(instance: Instance?): CFrame?
	if not instance then
		return nil
	elseif instance:IsA("BasePart") then
		return instance.CFrame
	elseif instance:IsA("Model") then
		return instance:GetPivot()
	end
	return nil
end

local function addPromptToInstance(instance: Instance?, actionText: string, objectText: string, callback: (Player) -> ())
	if not instance then
		return
	end
	local promptPart = firstBasePart(instance)
	if not promptPart then
		return
	end
	for _, child in ipairs(promptPart:GetChildren()) do
		if child:IsA("ProximityPrompt") then
			child:Destroy()
		end
	end
	addPrompt(promptPart, actionText, objectText, callback)
end

local function setPromptsEnabled(instance: Instance?, enabled: boolean)
	if not instance then
		return
	end
	if instance:IsA("ProximityPrompt") then
		instance.Enabled = enabled
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			descendant.Enabled = enabled
		end
	end
end

local function setTemplateMachineVisible(instance: Instance?, visible: boolean)
	if not instance then
		return
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = visible and descendant.Transparency or 1
			descendant.CanCollide = visible and descendant.CanCollide or false
			descendant.CanTouch = visible
			descendant.CanQuery = visible
		elseif descendant:IsA("ProximityPrompt") then
			descendant.Enabled = visible
		elseif descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui") then
			descendant.Enabled = visible
		end
	end
	if instance:IsA("BasePart") then
		instance.Transparency = visible and instance.Transparency or 1
		instance.CanCollide = visible and instance.CanCollide or false
		instance.CanTouch = visible
		instance.CanQuery = visible
	end
end

local function loadCreatorAsset(assetId: number, assetName: string?, aliases: { string }?): Instance?
	if assetName then
		local template = loadCreatorTemplate(assetName, aliases)
		if template then
			return template
		end
	end
	if assetId <= 0 then
		return nil
	end

	local ok, container = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not container then
		warn(`Unable to load Creator Store asset {assetName or "Unknown"} ({assetId}): {container}. Put a model/part in ServerStorage.CreatorStoreAssets with that name to use it as a local template.`)
		return nil
	end

	local chosen = findRenderableChild(container)
	if not chosen then
		warn(`Creator Store asset {assetId} did not contain a model or part Roblox can place.`)
		container:Destroy()
		return nil
	end

	chosen.Parent = nil
	container:Destroy()
	prepareCreatorModel(chosen)
	return chosen
end

local function placeCreatorProp(parent: Instance, assetName: string, fallbackName: string, cframe: CFrame, promptAction: string?, promptObject: string?, promptCallback: ((Player) -> ())?, floorY: number?, aliases: { string }?): BasePart?
	local asset = loadCreatorAsset(getCreatorAssetId("Base", assetName), assetName, aliases)
	if not asset then
		return nil
	end

	asset.Name = fallbackName
	asset.Parent = parent
	if asset:IsA("Model") then
		local pivotPart = asset.PrimaryPart or firstBasePart(asset)
		if pivotPart then
			asset.PrimaryPart = pivotPart
		end
		asset:PivotTo(cframe)
	else
		asset.CFrame = cframe
	end
	alignCreatorBottomToY(asset, floorY)

	local promptPart = firstBasePart(asset)
	if promptPart and promptAction and promptObject and promptCallback then
		addPrompt(promptPart, promptAction, promptObject, promptCallback)
	end
	return promptPart
end

local function placeCreatorEnemyVisual(parentModel: Model, enemyType: string, scale: number): BasePart?
	local asset = loadCreatorAsset(getCreatorAssetId("Enemies", enemyType), enemyType)
	if not asset then
		return nil
	end

	asset.Name = `{enemyType}Visual`
	asset.Parent = parentModel
	if asset:IsA("Model") then
		local pivotPart = asset.PrimaryPart or firstBasePart(asset)
		if pivotPart then
			asset.PrimaryPart = pivotPart
		end
		asset:ScaleTo(scale)
		local visualCFrame = CFrame.new(0, 2.8, 0)
		if enemyType == "Boss" then
			visualCFrame *= CFrame.Angles(math.rad(180), 0, 0)
		elseif enemyType == "Brute" then
			visualCFrame *= CFrame.Angles(0, 0, math.rad(90))
		end
		asset:PivotTo(visualCFrame)
	else
		local visualCFrame = CFrame.new(0, 2.8, 0)
		if enemyType == "Boss" then
			visualCFrame *= CFrame.Angles(math.rad(180), 0, 0)
		elseif enemyType == "Brute" then
			visualCFrame *= CFrame.Angles(0, 0, math.rad(90))
		end
		asset.CFrame = visualCFrame
	end

	return firstBasePart(asset)
end

local function makeCylinder(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = makePart(parent, name, size, cframe.Position, color)
	part.Shape = Enum.PartType.Cylinder
	part.CFrame = cframe
	return part
end

local function addPointLight(part: BasePart, color: Color3, brightness: number, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = true
	light.Parent = part
	return light
end

local function addLabel(part: BasePart, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(220, 72)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 0.2
	label.BackgroundColor3 = Color3.fromRGB(20, 18, 24)
	label.TextColor3 = Color3.fromRGB(255, 242, 210)
	label.Font = Enum.Font.Arcade
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = text
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = gui
end

local function addHealthBar(model: Model, adornee: BasePart, maxHealth: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(100, 14)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5.2, 0)
	gui.Parent = adornee

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	back.BorderSizePixel = 0
	back.Size = UDim2.fromScale(1, 1)
	back.Parent = gui

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.fromRGB(74, 190, 114)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = back

	local function update()
		local health = tonumber(model:GetAttribute("EnemyHealth")) or 0
		local ratio = math.clamp(health / maxHealth, 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.BackgroundColor3 = if ratio > 0.55 then Color3.fromRGB(74, 190, 114) elseif ratio > 0.25 then Color3.fromRGB(238, 177, 54) else Color3.fromRGB(255, 76, 91)
	end

	model:GetAttributeChangedSignal("EnemyHealth"):Connect(update)
	update()
end

local function showCashPopup(parent: Instance, position: Vector3, amount: number)
	local anchor = Instance.new("Part")
	anchor.Name = "TokenPopup"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = position + Vector3.new(0, 5, 0)
	anchor.Parent = parent

	local gui = Instance.new("BillboardGui")
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(90, 34)
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Arcade
	label.Text = `+{amount} Tokens`
	label.TextColor3 = Color3.fromRGB(255, 230, 166)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = gui

	task.spawn(function()
		for i = 1, 24 do
			anchor.Position += Vector3.new(0, 0.08, 0)
			label.TextTransparency = i / 24
			label.TextStrokeTransparency = 0.2 + (i / 24)
			task.wait(0.03)
		end
		anchor:Destroy()
	end)
end

local function defeatEnemy(player: Player, model: Model)
	local run = runsByPlayer[player]
	if not run or not model.Parent then
		return
	end

	local baseReward = tonumber(model:GetAttribute("CashReward")) or 0
	local reward = math.floor((baseReward * (1 + ((run.CashBonusLevel or 0) * 0.1))) + 0.5)
	local popupParent = model.Parent
	local popupPosition = model.PrimaryPart and model.PrimaryPart.Position or Vector3.new()
	run.Cash += reward
	run.EnemiesAlive = math.max(0, run.EnemiesAlive - 1)
	showCashPopup(popupParent, popupPosition, reward)
	sendMessage(player, `Defeated {model.Name}. +{reward} Tokens`)
	model:Destroy()
	pushState(player)
end

local function addSurfaceText(part: BasePart, text: string, face: Enum.NormalId?, textColor: Color3?, backgroundColor: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = `SurfaceText_{(face or Enum.NormalId.Front).Name}`
	gui.Face = face or Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 48
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = backgroundColor or Color3.fromRGB(20, 18, 26)
	label.BackgroundTransparency = 0.1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.Arcade
	label.Text = text
	label.TextColor3 = textColor or Color3.fromRGB(255, 230, 166)
	label.TextScaled = true
	label.TextWrapped = true
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = gui
end

local function addDoubleSidedSurfaceText(part: BasePart, text: string, textColor: Color3?, backgroundColor: Color3?)
	addSurfaceText(part, text, Enum.NormalId.Front, textColor, backgroundColor)
	addSurfaceText(part, text, Enum.NormalId.Back, textColor, backgroundColor)
end

local function resolveGuiIconTexture(iconName: string): string?
	local icon = guiIcons:FindFirstChild(iconName)
	if not icon then
		return nil
	end

	if icon:IsA("Decal") or icon:IsA("Texture") then
		return icon.Texture
	elseif icon:IsA("ImageLabel") or icon:IsA("ImageButton") then
		return icon.Image
	elseif icon:IsA("StringValue") then
		return icon.Value
	end

	local nestedImage = icon:FindFirstChildWhichIsA("ImageLabel", true) or icon:FindFirstChildWhichIsA("ImageButton", true)
	if nestedImage and (nestedImage:IsA("ImageLabel") or nestedImage:IsA("ImageButton")) then
		return nestedImage.Image
	end
	local nestedDecal = icon:FindFirstChildWhichIsA("Decal", true) or icon:FindFirstChildWhichIsA("Texture", true)
	if nestedDecal and (nestedDecal:IsA("Decal") or nestedDecal:IsA("Texture")) then
		return nestedDecal.Texture
	end
	return nil
end

local function addSurfaceImage(part: BasePart, image: string, face: Enum.NormalId)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceImage"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 45
	gui.LightInfluence = 0
	gui.Parent = part

	local imageLabel = Instance.new("ImageLabel")
	imageLabel.BackgroundTransparency = 1
	imageLabel.Size = UDim2.fromScale(1, 1)
	imageLabel.ScaleType = Enum.ScaleType.Fit
	imageLabel.Image = image
	imageLabel.Parent = gui
end

local function addDoubleSidedSurfaceImage(part: BasePart, image: string)
	addSurfaceImage(part, image, Enum.NormalId.Front)
	addSurfaceImage(part, image, Enum.NormalId.Back)
end

local function decorateRoom(folder: Folder, origin: Vector3)
	local wallColor = Color3.fromRGB(29, 31, 40)
	local trimColor = Color3.fromRGB(184, 53, 86)
	makePart(folder, "BackWall", Vector3.new(104, 18, 2), origin + Vector3.new(0, 8.5, -51), wallColor)
	makePart(folder, "FrontRail", Vector3.new(104, 5, 2), origin + Vector3.new(0, 2.5, 51), Color3.fromRGB(37, 40, 50))
	makePart(folder, "LeftWall", Vector3.new(2, 18, 104), origin + Vector3.new(-51, 8.5, 0), wallColor)
	makePart(folder, "RightWall", Vector3.new(2, 18, 104), origin + Vector3.new(51, 8.5, 0), wallColor)

	for _, x in ipairs({ -38, -14, 14, 38 }) do
		local column = makeCylinder(folder, "GoldColumn", Vector3.new(4, 16, 4), CFrame.new(origin + Vector3.new(x, 8, -47)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(198, 157, 74))
		column.Material = Enum.Material.Metal
		makeNeon(folder, "ColumnGlow", Vector3.new(4.3, 0.25, 4.3), origin + Vector3.new(x, 15.8, -47), trimColor)
	end

	local casinoSign = makePart(folder, "AnimatedArcadeRushSign", Vector3.new(38, 7, 1), origin + Vector3.new(0, 14, -48.8), Color3.fromRGB(23, 15, 10))
	casinoSign.Material = Enum.Material.Metal
	local arcadeRushImage = resolveGuiIconTexture("ArcadeRush")
	if arcadeRushImage then
		addDoubleSidedSurfaceImage(casinoSign, arcadeRushImage)
	else
		addDoubleSidedSurfaceText(casinoSign, "Arcade Rush", Color3.fromRGB(255, 230, 166), Color3.fromRGB(24, 16, 36))
	end
	makeNeon(folder, "ArcadeRushSignTopTrim", Vector3.new(40, 0.45, 0.7), origin + Vector3.new(0, 17.75, -48.2), Color3.fromRGB(221, 160, 74))
	makeNeon(folder, "ArcadeRushSignBottomTrim", Vector3.new(40, 0.45, 0.7), origin + Vector3.new(0, 10.25, -48.2), Color3.fromRGB(221, 160, 74))
	makeNeon(folder, "ArcadeRushSignLeftTrim", Vector3.new(0.45, 7.8, 0.7), origin + Vector3.new(-20.2, 14, -48.2), Color3.fromRGB(221, 160, 74))
	makeNeon(folder, "ArcadeRushSignRightTrim", Vector3.new(0.45, 7.8, 0.7), origin + Vector3.new(20.2, 14, -48.2), Color3.fromRGB(221, 160, 74))
	addPointLight(casinoSign, Color3.fromRGB(221, 160, 74), 1.4, 28)

	local combatArchLeft = makePart(folder, "CombatArchLeft", Vector3.new(4, 18, 4), origin + Vector3.new(-22, 9, 28), Color3.fromRGB(92, 47, 73))
	local combatArchRight = makePart(folder, "CombatArchRight", Vector3.new(4, 18, 4), origin + Vector3.new(22, 9, 28), Color3.fromRGB(92, 47, 73))
	local combatArchTop = makeNeon(folder, "CombatArchTop", Vector3.new(48, 3, 4), origin + Vector3.new(0, 18, 28), Color3.fromRGB(255, 76, 91))
	addPointLight(combatArchTop, Color3.fromRGB(255, 76, 91), 2, 30)
	combatArchLeft.Material = Enum.Material.Metal
	combatArchRight.Material = Enum.Material.Metal

	for _, z in ipairs({ -15, 5, 25, 41 }) do
		makeNeon(folder, "FloorLane", Vector3.new(84, 0.15, 0.35), origin + Vector3.new(0, 0.25, z), Color3.fromRGB(80, 168, 228))
	end

	task.spawn(function()
		local t = 0
		while folder.Parent do
			t += 0.08
			local pulse = (math.sin(t) + 1) / 2
			casinoSign.Color = Color3.fromRGB(20 + math.floor(16 * pulse), 13 + math.floor(10 * pulse), 8 + math.floor(6 * pulse))
			combatArchTop.Color = Color3.fromRGB(210 + math.floor(45 * pulse), 55, 70)
			for _, descendant in ipairs(folder:GetChildren()) do
				if descendant.Name == "SlotScreen" and descendant:IsA("BasePart") then
					descendant.Color = if pulse > 0.5 then Color3.fromRGB(74, 190, 114) else Color3.fromRGB(78, 139, 234)
				end
			end
			task.wait(0.08)
		end
	end)
end

local function openInteractionForOwner(owner: Player, triggerPlayer: Player, payload)
	if triggerPlayer ~= owner then
		return
	end
	interactionEvent:FireClient(owner, payload)
end

local function buildTokenShop(folder: Folder, player: Player, origin: Vector3)
	local promptCallback = function(triggerPlayer)
		openInteractionForOwner(player, triggerPlayer, { Event = "TicketBooth" })
	end
	local shopCFrame = CFrame.new(origin + Vector3.new(45, 2, 18)) * CFrame.Angles(0, math.rad(-90), 0)
	local creatorPart = placeCreatorProp(folder, "TokenShop", "TicketBoothCounter", shopCFrame, "Open", "Ticket Booth", promptCallback, origin.Y)
	if creatorPart then
		return
	end

	local base = makePart(folder, "TicketBoothCounter", Vector3.new(7, 4, 18), origin + Vector3.new(45, 2, 18), Color3.fromRGB(42, 37, 56))
	base.Material = Enum.Material.Metal
	local screen = makeNeon(folder, "TicketBoothScreen", Vector3.new(0.3, 3.2, 15), origin + Vector3.new(41.35, 4.2, 18), Color3.fromRGB(255, 230, 166))
	addDoubleSidedSurfaceText(screen, "TICKET BOOTH\nPress E", Color3.fromRGB(20, 18, 24), Color3.fromRGB(255, 230, 166))
	addPointLight(screen, Color3.fromRGB(255, 230, 166), 1.8, 20)
	local run = runsByPlayer[player]
	if run and run.Active and not run.InCombat then
		addPrompt(base, "Open", "Ticket Booth", promptCallback)
	end

	-- Machine unlocks now live in the top-right Machine Shop GUI.
end

local function buildScratchCounter(folder: Folder, player: Player, origin: Vector3)
	local promptCallback = function(triggerPlayer)
		openInteractionForOwner(player, triggerPlayer, { Event = "ArcadeGame", GambleName = "WhackAMole" })
	end
	local creatorPart = placeCreatorProp(folder, "WhackAMole", "WhackAMoleMachine", CFrame.new(origin + Vector3.new(-22, 2, -25)), "Play", "Whack-a-Mole", promptCallback, origin.Y, {
		"WhackAMole",
		"Whack A Mole",
		"Whack-a-Mole",
	})
	if creatorPart then
		return
	end

	local counter = makePart(folder, "WhackAMoleMachine", Vector3.new(19, 4, 8), origin + Vector3.new(-22, 2, -25), Color3.fromRGB(61, 84, 92))
	counter.Material = Enum.Material.Metal
	local glass = makeNeon(folder, "WhackAMoleGlowPanel", Vector3.new(15, 0.35, 5), origin + Vector3.new(-22, 4.25, -25), Color3.fromRGB(128, 242, 219))
	glass.Transparency = 0.18
	addPrompt(counter, "Play", "Whack-a-Mole", promptCallback)
end

local function buildCardBattlesTable(folder: Folder, player: Player, origin: Vector3)
	local promptCallback = function(triggerPlayer)
		openInteractionForOwner(player, triggerPlayer, { Event = "ArcadeGame", GambleName = "CardBattles" })
	end
	local creatorPart = placeCreatorProp(folder, "CardBattle", "CardBattleMachine", CFrame.new(origin + Vector3.new(2, 2, -25)), "Play", "Card Battle", promptCallback, origin.Y, {
		"CardBattle",
		"Card Battle",
	})
	if creatorPart then
		return
	end

	local tableTop = makeCylinder(folder, "CardBattleMachine", Vector3.new(12, 1.1, 12), CFrame.new(origin + Vector3.new(2, 2.55, -25)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(20, 112, 72))
	tableTop.Material = Enum.Material.Fabric
	makeCylinder(folder, "CardBattleRim", Vector3.new(13, 0.35, 13), CFrame.new(origin + Vector3.new(2, 3.17, -25)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(93, 55, 35)).Material = Enum.Material.Wood
	addPrompt(tableTop, "Play", "Card Battle", promptCallback)
end

local function buildGuessingGameTable(folder: Folder, player: Player, origin: Vector3)
	local promptCallback = function(triggerPlayer)
		openInteractionForOwner(player, triggerPlayer, { Event = "ArcadeGame", GambleName = "GuessingGame" })
	end
	local creatorPart = placeCreatorProp(folder, "GuessingGame", "GuessingGameMachine", CFrame.new(origin + Vector3.new(24, 2, -25)), "Play", "Guessing Game", promptCallback, origin.Y, {
		"GuessingGame",
		"Guessing Game",
	})
	if creatorPart then
		return
	end

	local tableBase = makePart(folder, "GuessingGameMachine", Vector3.new(14, 2.2, 9), origin + Vector3.new(24, 1.15, -25), Color3.fromRGB(60, 24, 45))
	tableBase.Material = Enum.Material.Wood
	local wheel = makeCylinder(folder, "GuessingGameWheel", Vector3.new(5.5, 1, 5.5), CFrame.new(origin + Vector3.new(20.5, 3, -25)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(184, 53, 86))
	wheel.Material = Enum.Material.Metal
	local hub = makeCylinder(folder, "GuessingGameHub", Vector3.new(2.2, 1.15, 2.2), CFrame.new(origin + Vector3.new(20.5, 3.05, -25)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(20, 18, 24))
	hub.Material = Enum.Material.Neon
	addPrompt(tableBase, "Play", "Guessing Game", promptCallback)
end

local function buildLootWheel(folder: Folder, player: Player, origin: Vector3)
	local promptCallback = function(triggerPlayer)
		openInteractionForOwner(player, triggerPlayer, { Event = "ArcadeGame", GambleName = "MysteryWheel" })
	end
	local creatorPart = placeCreatorProp(folder, "MysteryWheel", "MysteryWheelPlatform", CFrame.new(origin + Vector3.new(40, 2, -25)), "Play", "Mystery Wheel", promptCallback, origin.Y, {
		"MysteryWheel",
		"Mystery Wheel",
	})
	if creatorPart then
		return
	end

	local platform = makePart(folder, "MysteryWheelPlatform", Vector3.new(14, 1, 7), origin + Vector3.new(40, 0.55, -25), Color3.fromRGB(41, 40, 58))
	platform.Material = Enum.Material.Metal
	local wheel = makeCylinder(folder, "MysteryPrizeWheel", Vector3.new(12, 1.2, 12), CFrame.new(origin + Vector3.new(40, 6.5, -25)) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(238, 68, 212))
	wheel.Material = Enum.Material.Neon
	local center = makeCylinder(folder, "MysteryWheelCenter", Vector3.new(3.3, 1.35, 3.3), CFrame.new(origin + Vector3.new(40, 6.5, -25)) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 230, 166))
	center.Material = Enum.Material.Neon
	local pointer = makePart(folder, "MysteryWheelPointer", Vector3.new(1.4, 2.2, 0.6), origin + Vector3.new(40, 13.7, -25), Color3.fromRGB(255, 76, 91))
	pointer.Material = Enum.Material.Neon
	addPrompt(platform, "Play", "Mystery Wheel", promptCallback)
end

local function buildCasinoStations(folder: Folder, player: Player, origin: Vector3)
	local meta = metaByPlayer[player]
	buildScratchCounter(folder, player, origin)
	if isGambleUnlocked(meta, "CardBattles") then
		buildCardBattlesTable(folder, player, origin)
	end
	if isGambleUnlocked(meta, "GuessingGame") then
		buildGuessingGameTable(folder, player, origin)
	end
	if isGambleUnlocked(meta, "MysteryWheel") then
		buildLootWheel(folder, player, origin)
	end
end

local function attachBaseTemplateInteractions(room: Instance, player: Player)
	local meta = metaByPlayer[player]
	local run = runsByPlayer[player]
	local machineDefinitions = {
		{
			GambleName = "WhackAMole",
			DisplayName = "Whack-a-Mole",
			Names = { "WhackAMoleMachine", "WhackAMole", "Whack A Mole", "Whack-a-Mole", "WhackAMoleCounter" },
		},
		{
			GambleName = "CardBattles",
			DisplayName = "Card Battle",
			Names = { "CardBattleMachine", "CardBattle", "Card Battle", "CardBattlesTable" },
		},
		{
			GambleName = "GuessingGame",
			DisplayName = "Guessing Game",
			Names = { "GuessingGameMachine", "GuessingGame", "Guessing Game", "GuessingGameTable" },
		},
		{
			GambleName = "MysteryWheel",
			DisplayName = "Mystery Wheel",
			Names = { "MysteryWheelPlatform", "MysteryWheel", "Mystery Wheel", "LootWheel", "MysteryWheel" },
		},
	}

	for _, definition in ipairs(machineDefinitions) do
		local machine = findNamedDescendant(room, definition.Names)
		local unlocked = isGambleUnlocked(meta, definition.GambleName)
		setTemplateMachineVisible(machine, unlocked)
		if machine and unlocked then
			addPromptToInstance(machine, "Play", definition.DisplayName, function(triggerPlayer)
				openInteractionForOwner(player, triggerPlayer, { Event = "ArcadeGame", GambleName = definition.GambleName })
			end)
		end
	end

	local shop = findNamedDescendant(room, { "TicketBooth", "TicketBoothCounter", "Shop", "MachineShop", "MachineShopCounter", "TokenShop", "CashShop" })
	local shopVisible = true
	setTemplateMachineVisible(shop, shopVisible)
	local boothUsable = run and run.Active and not run.InCombat
	setPromptsEnabled(shop, boothUsable == true)
	if shop and shopVisible and boothUsable then
		addPromptToInstance(shop, "Open", "Ticket Booth", function(triggerPlayer)
			openInteractionForOwner(player, triggerPlayer, { Event = "TicketBooth" })
		end)
	end
end

local function placeBaseTemplate(folder: Folder, player: Player, origin: Vector3): boolean
	local slot = arenaSlotByPlayer[player] or 1
	local template = loadFirstRoomTemplate({
		`BaseRoom_{slot}`,
		`BaseRoom{slot}`,
		"BaseRoom",
	})
	if not template then
		return false
	end

	template.Name = "BaseRoom"
	template.Parent = folder
	if not usesAuthoredWorldPosition(template) then
		pivotRoomTemplate(template, CFrame.new(origin) * CFrame.Angles(0, baseYawForPlayer(player), 0))
	end
	attachBaseTemplateInteractions(template, player)
	return true
end

local function baseSpawnPosition(player: Player): Vector3
	local folder = arena:FindFirstChild(tostring(player.UserId))
	local marker = folder and findNamedDescendant(folder, { "PlayerSpawn", "BaseSpawn", "SpawnPoint" })
	local markerCFrame = cframeOfInstance(marker)
	if markerCFrame then
		return markerCFrame.Position + Vector3.new(0, 3, 0)
	end

	local floor = folder and findNamedDescendant(folder, { "BaseFloor", "Floor", "MainPlatform", "Platform" })
	local floorPart = floor and firstBasePart(floor)
	if floorPart then
		return floorPart.Position + Vector3.new(0, (floorPart.Size.Y / 2) + 4, 0)
	end

	local baseRoom = folder and folder:FindFirstChild("BaseRoom")
	if baseRoom then
		local pivot = templatePivotCFrame(baseRoom)
		return pivot.Position + Vector3.new(0, 6, 0)
	end

	return localBaseCFrame(player, Vector3.new(-35, 5, -32)).Position
end

local function addCombatBoundaries(combatRoom: Instance, origin: Vector3, floorSize: number)
	local floorHalf = floorSize / 2
	local boundaryHeight = 30
	local boundaryThickness = 6
	local boundaryY = (boundaryHeight / 2) - 0.5
	for _, boundary in ipairs({
		{ "CombatBoundaryBack", Vector3.new(floorSize + boundaryThickness, boundaryHeight, boundaryThickness), Vector3.new(0, boundaryY, -floorHalf) },
		{ "CombatBoundaryFront", Vector3.new(floorSize + boundaryThickness, boundaryHeight, boundaryThickness), Vector3.new(0, boundaryY, floorHalf) },
		{ "CombatBoundaryLeft", Vector3.new(boundaryThickness, boundaryHeight, floorSize + boundaryThickness), Vector3.new(-floorHalf, boundaryY, 0) },
		{ "CombatBoundaryRight", Vector3.new(boundaryThickness, boundaryHeight, floorSize + boundaryThickness), Vector3.new(floorHalf, boundaryY, 0) },
	}) do
		if not combatRoom:FindFirstChild(boundary[1] :: string, true) then
			local wall = makePart(combatRoom, boundary[1] :: string, boundary[2] :: Vector3, origin + (boundary[3] :: Vector3), Color3.fromRGB(23, 25, 33))
			wall.Transparency = 1
			wall.CanCollide = true
			wall.CanTouch = false
			wall.CanQuery = false
		end
	end
end

local function combatSpawnPosition(player: Player, combatRoom: Instance, fallbackOrigin: Vector3): Vector3
	local marker = findNamedDescendant(combatRoom, { "PlayerSpawn", "CombatSpawn", "SpawnPoint" })
	local markerCFrame = cframeOfInstance(marker)
	if markerCFrame then
		return markerCFrame.Position + Vector3.new(0, 3, 0)
	end
	return fallbackOrigin + Vector3.new(0, 5, 0)
end

local function placeCombatTemplate(player: Player, folder: Folder, boss: boolean?): (Instance?, Vector3, number)
	local origin = combatOriginForPlayer(player)
	local slot = arenaSlotByPlayer[player] or 1
	local template = loadFirstRoomTemplate(if boss then {
		`BossCombatRoom_{slot}`,
		`BossCombatRoom{slot}`,
		"BossCombatRoom",
	} else {
		`CombatRoom_{slot}`,
		`CombatRoom{slot}`,
		"CombatRoom",
	})
	if not template and boss then
		template = loadFirstRoomTemplate({
			`CombatRoom_{slot}`,
			`CombatRoom{slot}`,
			"CombatRoom",
		})
	end
	if not template then
		return nil, origin, if boss then 118 else 92
	end

	template.Name = "CombatRoom"
	template.Parent = folder
	if not usesAuthoredWorldPosition(template) then
		pivotRoomTemplate(template, CFrame.new(origin))
	end
	local floor = findNamedDescendant(template, { "CombatFloor", "Floor", "ArenaFloor" })
	local floorPart = floor and firstBasePart(floor)
	if floorPart then
		floorPart.Name = "CombatFloor"
		origin = floorPart.Position
		local floorSize = math.max(floorPart.Size.X, floorPart.Size.Z)
		addCombatBoundaries(template, origin, floorSize)
		return template, origin, floorSize
	end

	local marker = Instance.new("Part")
	marker.Name = "CombatFloor"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.Transparency = 1
	marker.Size = Vector3.new(if boss then 118 else 92, 1, if boss then 118 else 92)
	marker.Position = origin + Vector3.new(0, -0.5, 0)
	marker.Parent = template
	addCombatBoundaries(template, origin, marker.Size.X)
	return template, origin, marker.Size.X
end

local function createToolTemplate()
	local oldBlade = weaponFolder:FindFirstChild("RunBlade")
	if oldBlade then
		oldBlade:Destroy()
	end

	local existing = weaponFolder:FindFirstChild("RunLaserGun") or weaponFolder:FindFirstChild("RunPistol")
	if existing then
		existing:Destroy()
	end

	local tool = Instance.new("Tool")
	tool.Name = "RunLaserGun"
	tool.RequiresHandle = true
	tool.ToolTip = "Fire a laser beam. Damage scales with your run."
	tool.Grip = CFrame.new(0.25, -0.2, -0.25) * CFrame.Angles(0, math.rad(90), 0)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.75, 1.25, 0.45)
	handle.Color = Color3.fromRGB(36, 38, 45)
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Parent = tool

	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(2.35, 0.38, 0.38)
	barrel.CFrame = handle.CFrame * CFrame.new(1.45, 0.22, 0)
	barrel.Color = Color3.fromRGB(20, 22, 28)
	barrel.Material = Enum.Material.Metal
	barrel.CanCollide = false
	barrel.Parent = tool

	local muzzle = Instance.new("Part")
	muzzle.Name = "Muzzle"
	muzzle.Size = Vector3.new(0.25, 0.56, 0.56)
	muzzle.CFrame = handle.CFrame * CFrame.new(2.75, 0.22, 0)
	muzzle.Color = Color3.fromRGB(80, 168, 228)
	muzzle.Material = Enum.Material.Neon
	muzzle.CanCollide = false
	muzzle.Parent = tool

	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.45, 1.35, 0.55)
	grip.CFrame = handle.CFrame * CFrame.new(-0.28, -1.05, 0) * CFrame.Angles(0, 0, math.rad(-14))
	grip.Color = Color3.fromRGB(55, 38, 31)
	grip.Material = Enum.Material.Wood
	grip.CanCollide = false
	grip.Parent = tool

	local sight = Instance.new("Part")
	sight.Name = "Sight"
	sight.Size = Vector3.new(0.35, 0.28, 0.2)
	sight.CFrame = handle.CFrame * CFrame.new(0.55, 0.82, 0)
	sight.Color = Color3.fromRGB(217, 183, 87)
	sight.Material = Enum.Material.Metal
	sight.CanCollide = false
	sight.Parent = tool

	for _, part in ipairs({ barrel, muzzle, grip, sight }) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part
	end

	tool.Parent = weaponFolder
end

local lastShotAtByPlayer: { [Player]: number } = {}

local function shootRunGun(player: Player, targetPosition: any)
	local run = runsByPlayer[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local tool = character and (character:FindFirstChild("RunLaserGun") or character:FindFirstChild("RunPistol"))
	if not run or not run.Active or not root or not root:IsA("BasePart") or not tool then
		return
	end
	if battleCountdownActive(run) then
		return
	end
	if typeof(targetPosition) ~= "Vector3" then
		return
	end

	local now = os.clock()
	if now - (lastShotAtByPlayer[player] or 0) < 0.28 then
		return
	end
	lastShotAtByPlayer[player] = now

	local shotOrigin = root.Position + Vector3.new(0, 1.2, 0)
	local targetDirection = targetPosition - shotOrigin
	if targetDirection.Magnitude < 1 then
		return
	end

	local range = 85
	local shotDirection = targetDirection.Unit
	local bestModel: Model? = nil
	local bestDistance = range
	local bestPosition = shotOrigin + (shotDirection * range)
	for _, model in ipairs(arena:GetDescendants()) do
		if model:IsA("Model") and model:GetAttribute("OwnerUserId") == player.UserId and model:GetAttribute("EnemyHealth") then
			local enemyRoot = model.PrimaryPart
			if enemyRoot then
				local toEnemy = enemyRoot.Position - shotOrigin
				local forwardDistance = toEnemy:Dot(shotDirection)
				if forwardDistance > 0 and forwardDistance <= range then
					local closestPoint = shotOrigin + (shotDirection * forwardDistance)
					local missDistance = (enemyRoot.Position - closestPoint).Magnitude
					if missDistance <= 5.5 and forwardDistance < bestDistance then
						bestModel = model
						bestDistance = forwardDistance
						bestPosition = enemyRoot.Position
					end
				end
			end
		end
	end

	local tracer = Instance.new("Part")
	tracer.Name = "LaserTracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	local tracerLength = (bestPosition - shotOrigin).Magnitude
	tracer.Size = Vector3.new(0.16, 0.16, math.max(1, tracerLength))
	tracer.CFrame = CFrame.lookAt(shotOrigin:Lerp(bestPosition, 0.5), bestPosition)
	tracer.Color = Color3.fromRGB(255, 226, 92)
	tracer.Material = Enum.Material.Neon
	tracer.Transparency = 0.12
	tracer.Parent = arena

	local flash = Instance.new("Part")
	flash.Name = "MuzzleFlash"
	flash.Anchored = true
	flash.CanCollide = false
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(1.4, 1.4, 1.4)
	flash.CFrame = CFrame.new(shotOrigin + (shotDirection * 3))
	flash.Color = Color3.fromRGB(255, 226, 92)
	flash.Material = Enum.Material.Neon
	flash.Parent = arena

	local shotSound = Instance.new("Sound")
	shotSound.Name = "RunLaserShot"
	shotSound.SoundId = "rbxassetid://133448091259425"
	shotSound.Volume = 0.55
	shotSound.RollOffMaxDistance = 85
	shotSound.RollOffMinDistance = 8
	shotSound.Parent = arena
	shotSound:Play()
	Debris:AddItem(shotSound, 3)

	task.spawn(function()
		for i = 1, 6 do
			tracer.Transparency = 0.12 + (i * 0.14)
			flash.Transparency = i * 0.16
			flash.Size += Vector3.new(0.25, 0.25, 0.25)
			task.wait(0.025)
		end
		tracer:Destroy()
		flash:Destroy()
	end)

	if bestModel then
		local enemyRoot = bestModel.PrimaryPart
		if bestModel:GetAttribute("Invulnerable") then
			sendMessage(player, "The Final Cabinet shield blocks the shot.")
			return
		end
		local health = (bestModel:GetAttribute("EnemyHealth") :: number) - run.Damage
		bestModel:SetAttribute("EnemyHealth", health)
		local highlight = Instance.new("Highlight")
		highlight.Name = "HitFlash"
		highlight.FillColor = Color3.fromRGB(255, 246, 150)
		highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		highlight.FillTransparency = 0.15
		highlight.Parent = bestModel
		task.delay(0.12, function()
			if highlight.Parent then
				highlight:Destroy()
			end
		end)
		if enemyRoot then
			addEnemySpawnEffect(bestModel.Parent :: Folder, enemyRoot.Position, false)
		end
		if health <= 0 then
			defeatEnemy(player, bestModel)
		end
	end
end

local function bindRunGun(tool: Tool)
	tool:SetAttribute("Bound", true)
end

local function giveRunGun(player: Player)
	local template = weaponFolder:FindFirstChild("RunLaserGun")
	if not template then
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		local oldBlade = backpack:FindFirstChild("RunBlade")
		if oldBlade then
			oldBlade:Destroy()
		end
	end
	if backpack and not backpack:FindFirstChild("RunLaserGun") then
		local tool = template:Clone()
		tool.Parent = backpack
		bindRunGun(tool)
	end
end

local function removeRunGun(player: Player)
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if container then
			local tool = container:FindFirstChild("RunLaserGun") or container:FindFirstChild("RunPistol")
			if tool then
				tool:Destroy()
			end
		end
	end
end

local function makeEnemyPart(model: Model, name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.Size = size
	part.CFrame = CFrame.new(offset)
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function damagePlayer(player: Player, amount: number, sourceName: string)
	local run = runsByPlayer[player]
	if not run or not run.Active then
		return
	end

	local heartsLost = math.max(1, math.floor(amount))
	run.Health = math.max(0, run.Health - heartsLost)
	sendMessage(player, `{sourceName} hits you for {heartsLost} heart.`)
	feedbackEvent:FireClient(player, {
		Event = "Hit",
		HeartsLost = heartsLost,
		Health = run.Health,
		MaxHealth = run.MaxHealth,
		Source = sourceName,
	})
	if run.Health <= 0 then
		run.Active = false
		run.InCombat = false
		run.BattleCountdown = 0
		setPlayerBattleFrozen(player, false)
		sendMessage(player, "Run lost. Return to the machine shop or start again.")
		clearCombatRoom(player)
		buildRoom(player)
	end
	pushState(player)
end

local function fireEnemyProjectile(player: Player, sourceModel: Model, origin: Vector3, damage: number, speed: number, color: Color3, name: string, card: boolean?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local direction = (root.Position + Vector3.new(0, 1, 0) - origin)
	if direction.Magnitude < 1 then
		return
	end
	direction = direction.Unit

	local projectile = Instance.new("Part")
	projectile.Name = name
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.Size = if card then Vector3.new(2.2, 0.08, 3.1) else Vector3.new(0.7, 0.7, 0.7)
	projectile.CFrame = CFrame.lookAt(origin, origin + direction)
	projectile.Color = color
	projectile.Material = Enum.Material.Neon
	projectile.Parent = sourceModel.Parent

	task.spawn(function()
		for _ = 1, 80 do
			if not projectile.Parent or not sourceModel.Parent then
				break
			end
			projectile.CFrame += direction * speed
			if root.Parent and (projectile.Position - root.Position).Magnitude <= 3 then
				damagePlayer(player, damage, sourceModel.Name)
				projectile:Destroy()
				break
			end
			task.wait(0.04)
		end
		if projectile.Parent then
			projectile:Destroy()
		end
	end)
end

local function alignModelBottomToY(model: Model, floorY: number)
	local bottomY = math.huge
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and not string.find(string.lower(descendant.Name), "shield") then
			bottomY = math.min(bottomY, descendant.Position.Y - (descendant.Size.Y / 2))
		end
	end
	if bottomY == math.huge then
		local boundsCFrame, boundsSize = model:GetBoundingBox()
		bottomY = boundsCFrame.Position.Y - (boundsSize.Y / 2)
	end
	local lift = floorY - bottomY + 0.08
	if math.abs(lift) > 0.01 then
		model:PivotTo(model:GetPivot() + Vector3.new(0, lift, 0))
	end
end

local function makeEnemyVisualPart(model: Model, name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?, rotation: CFrame?): Part
	local part = makeEnemyPart(model, name, size, offset, color, material)
	part.Shape = shape or Enum.PartType.Block
	part.CFrame = CFrame.new(offset) * (rotation or CFrame.identity)
	return part
end

local function addEnemyMesh(part: Part, meshType: Enum.MeshType, scale: Vector3?)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = meshType
	mesh.Scale = scale or Vector3.new(1, 1, 1)
	mesh.Parent = part
	return mesh
end

addEnemySpawnEffect = function(folder: Folder, position: Vector3, boss: boolean?)
	local ring = makeCylinder(folder, "EnemySpawnRing", boss and Vector3.new(18, 0.25, 18) or Vector3.new(10, 0.2, 10), CFrame.new(position - Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), boss and Color3.fromRGB(238, 68, 212) or Color3.fromRGB(255, 76, 91))
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.15
	addPointLight(ring, ring.Color, boss and 3 or 2, boss and 28 or 18)
	task.spawn(function()
		for i = 1, 12 do
			ring.Transparency = i / 12
			ring.Size += Vector3.new(0, 0.6, 0.6)
			task.wait(0.04)
		end
		ring:Destroy()
	end)
end

buildRoom = function(player: Player)
	clearPlayerArena(player)

	local folder = playerFolder(player)
	local origin = baseOriginForPlayer(player)

	local usedTemplate = placeBaseTemplate(folder, player, origin)
	if not usedTemplate then
		ensureSharedBasePlaza()
		makePart(folder, "Floor", Vector3.new(100, 1, 100), origin + Vector3.new(0, -0.5, 0), Color3.fromRGB(42, 47, 55)).Material = Enum.Material.Slate
		makePart(folder, "CombatPad", Vector3.new(32, 1, 32), origin + Vector3.new(0, 0.05, 28), Color3.fromRGB(65, 58, 73)).Material = Enum.Material.DiamondPlate
		makePart(folder, "GamblingLounge", Vector3.new(70, 1, 24), origin + Vector3.new(0, 0.1, -26), Color3.fromRGB(30, 98, 76)).Material = Enum.Material.Fabric
		decorateRoom(folder, origin)
		buildCasinoStations(folder, player, origin)

		buildTokenShop(folder, player, origin)

		rotateDescendantsAround(folder, origin, baseYawForPlayer(player))
	end

	teleportPlayer(player, baseSpawnPosition(player))
end

local function buildCombatRoom(player: Player, boss: boolean?)
	clearCombatRoom(player)

	local folder = playerFolder(player)
	local templateRoom, templateOrigin = placeCombatTemplate(player, folder, boss)
	if templateRoom then
		teleportPlayer(player, combatSpawnPosition(player, templateRoom, templateOrigin))
		return
	end

	local combatRoom = Instance.new("Folder")
	combatRoom.Name = "CombatRoom"
	combatRoom.Parent = folder

	local origin = templateOrigin
	local floorSize = if boss then 118 else 92
	local floorHalf = floorSize / 2
	makePart(combatRoom, "CombatFloor", Vector3.new(floorSize, 1, floorSize), origin + Vector3.new(0, -0.5, 0), boss and Color3.fromRGB(48, 24, 39) or Color3.fromRGB(38, 42, 52)).Material = Enum.Material.DiamondPlate
	makePart(combatRoom, "CombatBackWall", Vector3.new(120, 20, 2), origin + Vector3.new(0, 9.5, -58), Color3.fromRGB(23, 25, 33))
	makePart(combatRoom, "CombatLeftWall", Vector3.new(2, 20, 120), origin + Vector3.new(-58, 9.5, 0), Color3.fromRGB(23, 25, 33))
	makePart(combatRoom, "CombatRightWall", Vector3.new(2, 20, 120), origin + Vector3.new(58, 9.5, 0), Color3.fromRGB(23, 25, 33))
	makePart(combatRoom, "CombatFrontWall", Vector3.new(120, 20, 2), origin + Vector3.new(0, 9.5, 58), Color3.fromRGB(23, 25, 33))
	addCombatBoundaries(combatRoom, origin, floorSize)

	local accent = if boss then Color3.fromRGB(238, 68, 212) else Color3.fromRGB(255, 76, 91)
	for _, x in ipairs({ -40, -20, 0, 20, 40 }) do
		makeNeon(combatRoom, "CombatHazardLane", Vector3.new(0.45, 0.18, 92), origin + Vector3.new(x, 0.25, 0), accent)
	end
	local gate = makeNeon(combatRoom, "CombatGateSign", Vector3.new(38, 5, 1), origin + Vector3.new(0, 13, -56.8), accent)
	addDoubleSidedSurfaceText(gate, if boss then "FINAL CABINET" else `FIGHT ROOM {runsByPlayer[player] and runsByPlayer[player].Room or 1}`, Color3.fromRGB(255, 230, 166), Color3.fromRGB(24, 16, 36))
	addPointLight(gate, accent, boss and 3 or 2, 35)

	for _, point in ipairs({
		Vector3.new(-42, 3, -42),
		Vector3.new(42, 3, -42),
		Vector3.new(-42, 3, 42),
		Vector3.new(42, 3, 42),
	}) do
		local pylon = makePart(combatRoom, "CombatPylon", Vector3.new(5, 7, 5), origin + point, Color3.fromRGB(63, 48, 70))
		pylon.Material = Enum.Material.Metal
		makeNeon(combatRoom, "PylonCore", Vector3.new(3.5, 0.5, 3.5), origin + point + Vector3.new(0, 3.8, 0), accent)
	end

	teleportPlayer(player, combatSpawnPosition(player, combatRoom, origin))
end

local function ensureRun(player: Player): RunState
	local meta = metaByPlayer[player]
	local bankroll = getUpgrade(meta, "Bankroll")
	local vitality = getUpgrade(meta, "Vitality")
	local edge = getUpgrade(meta, "Edge")
	local luck = getUpgrade(meta, "Luck")

	local maxHealth = GameConfig.Run.StartingMaxHealth + vitality
	local run = {
		Active = true,
		Paused = false,
		Room = 1,
		Cash = (GameConfig.Run.StartingTokens or GameConfig.Run.StartingCash) + (bankroll * 8),
		Tickets = GameConfig.Run.StartingTickets or 0,
		Health = maxHealth,
		MaxHealth = maxHealth,
		Damage = GameConfig.Run.StartingDamage + (edge * 3),
		LuckBonus = luck * 0.02,
		BarrelLevel = 0,
		GambleCap = GameConfig.Run.StartingGambles,
		GamblesLeft = GameConfig.Run.StartingGambles,
		GambleVoucherLevel = 0,
		CashBonusLevel = 0,
		EnemiesAlive = 0,
		InCombat = false,
		BattleCountdown = 0,
		BossDefeated = false,
	}

	runsByPlayer[player] = run
	return run
end

local function loadMeta(player: Player)
	local defaultMeta = {
		Tokens = 100,
		Upgrades = {},
		Unlocks = {},
		Wins = 100,
	}

	local ok, data = true, nil
	if useDataStore then
		ok, data = pcall(function()
			return metaStore:GetAsync(tostring(player.UserId))
		end)
	end

	if ok and type(data) == "table" then
		defaultMeta.Tokens = tonumber(data.Tokens) or 0
		defaultMeta.Upgrades = type(data.Upgrades) == "table" and data.Upgrades or {}
		defaultMeta.Unlocks = type(data.Unlocks) == "table" and data.Unlocks or {}
		defaultMeta.Wins = tonumber(data.Wins) or 0
	end

	metaByPlayer[player] = defaultMeta
end

local function saveMeta(player: Player)
	local meta = metaByPlayer[player]
	if not meta then
		return
	end
	if not useDataStore then
		return
	end

	pcall(function()
		metaStore:SetAsync(tostring(player.UserId), meta)
	end)
end

local function chooseOutcome(player: Player, gambleName: string)
	local gamble = GameConfig.Gambles[gambleName]
	if not gamble or not gamble.Outcomes then
		return nil
	end

	local run = runsByPlayer[player]
	local rng = rngByPlayer[player] or Random.new()
	local totalWeight = 0
	for index, outcome in ipairs(gamble.Outcomes) do
		local bonus = 0
		if run and index > 1 then
			bonus = math.floor((run.LuckBonus or 0) * 100)
		end
		totalWeight += outcome.Weight + bonus
	end

	local roll = rng:NextInteger(1, totalWeight)
	local cursor = 0
	for index, outcome in ipairs(gamble.Outcomes) do
		local bonus = 0
		if run and index > 1 then
			bonus = math.floor((run.LuckBonus or 0) * 100)
		end
		cursor += outcome.Weight + bonus
		if roll <= cursor then
			return outcome
		end
	end

	return gamble.Outcomes[1]
end

local function canStartGamble(player: Player, gambleName: string): (boolean, RunState?)
	local run = runsByPlayer[player]
	local gamble = GameConfig.Gambles[gambleName]
	local meta = metaByPlayer[player]
	if not run or not run.Active then
		sendMessage(player, "Start a run first.")
		return false, nil
	end
	if run.InCombat then
		sendMessage(player, "Finish the fight before playing machines.")
		return false, nil
	end
	if not gamble then
		return false, nil
	end
	if not isGambleUnlocked(meta, gambleName) then
		sendMessage(player, "That arcade machine is still locked.")
		return false, nil
	end
	if run.Cash < gamble.Cost then
		print("Not enough tokens to play")
		sendMessage(player, "Not enough tokens to play")
		return false, nil
	end

	return true, run
end

local function spendGambleUse(run: RunState)
	_ = run
end

local function cardValue(rank: string): number
	if rank == "A" then
		return 11
	elseif rank == "K" or rank == "Q" or rank == "J" then
		return 10
	end
	return tonumber(rank) or 10
end

local function drawCard(player: Player)
	local rng = rngByPlayer[player] or Random.new()
	local ranks = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
	local rank = ranks[rng:NextInteger(1, #ranks)]
	return {
		Rank = rank,
		Value = cardValue(rank),
	}
end

local function handTotal(cards): number
	local total = 0
	local aces = 0
	for _, card in ipairs(cards) do
		total += card.Value
		if card.Rank == "A" then
			aces += 1
		end
	end
	while total > 21 and aces > 0 do
		total -= 10
		aces -= 1
	end
	return total
end

local function drawWeightedCard(player: Player, currentCards, preferSafe: boolean): any
	local run = runsByPlayer[player]
	local rng = rngByPlayer[player] or Random.new()
	local luck = run and run.LuckBonus or 0
	local ranks = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
	local currentTotal = handTotal(currentCards)
	local totalWeight = 0
	local weighted = {}
	for _, rank in ipairs(ranks) do
		local value = cardValue(rank)
		local adjustedValue = value
		if rank == "A" and currentTotal + 11 > 21 then
			adjustedValue = 1
		end
		local wouldBust = currentTotal + adjustedValue > 21
		local weight = 1
		if preferSafe and not wouldBust then
			weight *= 1 + luck
		elseif not preferSafe and wouldBust then
			weight *= 1 + luck
		end
		totalWeight += weight
		table.insert(weighted, { Rank = rank, Value = value, Weight = weight })
	end
	local roll = rng:NextNumber(0, totalWeight)
	local cursor = 0
	for _, card in ipairs(weighted) do
		cursor += card.Weight
		if roll <= cursor then
			return { Rank = card.Rank, Value = card.Value }
		end
	end
	return { Rank = "K", Value = 10 }
end

local function fireCardBattle(player: Player, gameState, status: string, payout: number?)
	local ended = gameState.Ended == true
	gambleResultEvent:FireClient(player, {
		Event = "CardBattle",
		GambleName = "CardBattles",
		DisplayName = GameConfig.Gambles.CardBattles.DisplayName,
		PlayerCards = gameState.PlayerCards,
		DealerCards = gameState.DealerCards,
		PlayerTotal = handTotal(gameState.PlayerCards),
		DealerTotal = if ended then handTotal(gameState.DealerCards) else nil,
		HideDealerCard = not ended,
		Status = status,
		Ended = ended,
		Cash = payout or 0,
		Tickets = payout or 0,
		Cost = GameConfig.Gambles.CardBattles.Cost,
	})
end

local function finishCardBattles(player: Player, gameState, status: string, payout: number)
	local run = runsByPlayer[player]
	gameState.Ended = true
	CardBattlesByPlayer[player] = nil
	if run and payout > 0 then
		run.Tickets = (run.Tickets or 0) + payout
	end
	sendMessage(player, `{GameConfig.Gambles.CardBattles.DisplayName}: {status} +{payout} Tickets`)
	fireCardBattle(player, gameState, status, payout)
	pushState(player)
end

local ROULETTE_RED: { [number]: boolean } = {
	[1] = true,
	[3] = true,
	[5] = true,
	[7] = true,
	[9] = true,
	[12] = true,
	[14] = true,
	[16] = true,
	[18] = true,
	[19] = true,
	[21] = true,
	[23] = true,
	[25] = true,
	[27] = true,
	[30] = true,
	[32] = true,
	[34] = true,
	[36] = true,
}

local function guessingGameSlots(): { any }
	local slots = { "0", "00" }
	for number = 1, 36 do
		table.insert(slots, number)
	end
	return slots
end

local function guessingGameColor(value): string
	if value == "0" or value == "00" then
		return "Green"
	end
	return if ROULETTE_RED[value] then "Red" else "Black"
end

local function guessingGameBetWins(value, betType: string, betValue): boolean
	if betType == "Color" then
		return guessingGameColor(value) == betValue
	elseif betType == "Parity" then
		if type(value) ~= "number" then
			return false
		end
		return (betValue == "Even" and value % 2 == 0) or (betValue == "Odd" and value % 2 == 1)
	elseif betType == "Number" then
		if betValue == "0" or betValue == "00" then
			return value == betValue
		end
		return type(value) == "number" and value == tonumber(betValue)
	end
	return false
end

local function startWhackAMole(player: Player, run: RunState)
	local gamble = GameConfig.Gambles.WhackAMole
	local rng = rngByPlayer[player] or Random.new()
	spendGambleUse(run)
	run.Cash -= gamble.Cost

	local gameState = {
		Score = 0,
		Round = 0,
		Slots = gamble.Slots or 10,
		Rounds = gamble.Rounds or 12,
		ActiveSlot = nil,
		FakeSlot = nil,
		ActiveUntil = 0,
		HitThisRound = false,
		Ended = false,
	}
	scratchByPlayer[player] = gameState
	CardBattlesByPlayer[player] = nil

	sendMessage(player, "Whack-a-Mole started. Hit real moles, avoid fakes.")
	gambleResultEvent:FireClient(player, {
		Event = "WhackMoleStart",
		GambleName = "WhackAMole",
		DisplayName = gamble.DisplayName,
		Cost = gamble.Cost,
		Slots = gameState.Slots,
		Rounds = gameState.Rounds,
		HitPoints = gamble.HitPoints,
		MissPenalty = gamble.MissPenalty,
		FakePenalty = gamble.FakePenalty,
	})
	pushState(player)

	task.spawn(function()
		task.wait(0.25)
		for round = 1, gameState.Rounds do
			if scratchByPlayer[player] ~= gameState then
				return
			end

			local activeSlot = rng:NextInteger(1, gameState.Slots)
			local fakeSlot = nil
			if rng:NextNumber() <= (gamble.FakeChance or 0.45) then
				fakeSlot = rng:NextInteger(1, gameState.Slots - 1)
				if fakeSlot >= activeSlot then
					fakeSlot += 1
				end
			end

			gameState.Round = round
			gameState.ActiveSlot = activeSlot
			gameState.FakeSlot = fakeSlot
			gameState.HitThisRound = false
			gameState.ActiveUntil = os.clock() + (gamble.PopupDuration or 0.85)

			gambleResultEvent:FireClient(player, {
				Event = "WhackMolePop",
				GambleName = "WhackAMole",
				Round = round,
				MoleSlot = activeSlot,
				FakeSlot = fakeSlot,
				Duration = gamble.PopupDuration or 0.85,
				Score = gameState.Score,
			})

			task.wait(gamble.PopupDuration or 0.85)
			task.wait(0.18)
		end

		if scratchByPlayer[player] ~= gameState then
			return
		end

		gameState.Ended = true
		scratchByPlayer[player] = nil
		local currentRun = runsByPlayer[player]
		local tickets = math.max(0, gameState.Score)
		if currentRun and tickets > 0 then
			currentRun.Tickets = (currentRun.Tickets or 0) + tickets
		end

		sendMessage(player, `Whack-a-Mole finished. +{tickets} Tickets`)
		gambleResultEvent:FireClient(player, {
			Event = "WhackMoleEnd",
			GambleName = "WhackAMole",
			Score = gameState.Score,
			Tickets = tickets,
			Cost = GameConfig.Gambles.WhackAMole.Cost,
		})
		pushState(player)
	end)
end

local function revealScratch(player: Player, payload: any?)
	local run = runsByPlayer[player]
	local gameState = scratchByPlayer[player]
	if not run or not gameState or gameState.Ended or type(payload) ~= "table" then
		return
	end
	local slot = tonumber(payload.Slot)
	local round = tonumber(payload.Round)
	if not slot or not round or round ~= gameState.Round or slot < 1 or slot > gameState.Slots then
		return
	end
	if gameState.HitThisRound or os.clock() > (gameState.ActiveUntil or 0) then
		return
	end

	gameState.HitThisRound = true
	local gamble = GameConfig.Gambles.WhackAMole
	local correct = slot == gameState.ActiveSlot
	local fake = slot == gameState.FakeSlot
	local delta
	if correct then
		delta = gamble.HitPoints or 5
	elseif fake then
		delta = -(gamble.FakePenalty or 4)
	else
		delta = -(gamble.MissPenalty or 3)
	end
	gameState.Score += delta

	gambleResultEvent:FireClient(player, {
		Event = "WhackMoleHit",
		GambleName = "WhackAMole",
		Round = round,
		Slot = slot,
		Correct = correct,
		Fake = fake,
		Delta = delta,
		Score = gameState.Score,
	})
	if correct then
		sendMessage(player, `Whack! +{delta} points`)
	else
		sendMessage(player, `Miss! {delta} points`)
	end
	pushState(player)
end

local function startCardBattles(player: Player, run: RunState)
	local gamble = GameConfig.Gambles.CardBattles
	spendGambleUse(run)
	run.Cash -= gamble.Cost
	scratchByPlayer[player] = nil

	local gameState = {
		PlayerCards = { drawCard(player), drawCard(player) },
		DealerCards = { drawCard(player), drawCard(player) },
		Ended = false,
	}
	CardBattlesByPlayer[player] = gameState

	local playerTotal = handTotal(gameState.PlayerCards)
	if playerTotal == 21 then
		finishCardBattles(player, gameState, "Perfect 21!", gamble.CardBattlesPayout)
	else
		sendMessage(player, "Card Battle started. Hit or stand.")
		fireCardBattle(player, gameState, "Hit or stand.", 0)
		pushState(player)
	end
end

local function hitCardBattles(player: Player)
	local gameState = CardBattlesByPlayer[player]
	if not gameState or gameState.Ended then
		return
	end

	table.insert(gameState.PlayerCards, drawWeightedCard(player, gameState.PlayerCards, true))
	local total = handTotal(gameState.PlayerCards)
	if total > 21 then
		finishCardBattles(player, gameState, "Bust.", 0)
	else
		fireCardBattle(player, gameState, "Hit or stand.", 0)
	end
end

local function standCardBattles(player: Player)
	local gameState = CardBattlesByPlayer[player]
	if not gameState or gameState.Ended then
		return
	end

	while handTotal(gameState.DealerCards) < 17 do
		table.insert(gameState.DealerCards, drawWeightedCard(player, gameState.DealerCards, false))
	end

	local gamble = GameConfig.Gambles.CardBattles
	local playerTotal = handTotal(gameState.PlayerCards)
	local dealerTotal = handTotal(gameState.DealerCards)
	if dealerTotal > 21 or playerTotal > dealerTotal then
		finishCardBattles(player, gameState, "You win.", gamble.WinPayout)
	elseif playerTotal == dealerTotal then
		finishCardBattles(player, gameState, "Push.", gamble.PushPayout)
	else
		finishCardBattles(player, gameState, "Worker wins.", 0)
	end
end

local function playMysteryWheel(player: Player, run: RunState)
	local gamble = GameConfig.Gambles.MysteryWheel
	local rng = rngByPlayer[player] or Random.new()
	spendGambleUse(run)
	run.Cash -= gamble.Cost
	scratchByPlayer[player] = nil
	CardBattlesByPlayer[player] = nil

	local luck = run.LuckBonus or 0
	local totalWeight = 0
	for _, rarity in ipairs(gamble.Rarities) do
		local prize = rarity.Tickets or rarity.Cash or 0
		totalWeight += if prize > gamble.Cost then rarity.Weight * (1 + luck) else rarity.Weight
	end
	local roll = rng:NextNumber(0, totalWeight)
	local cursor = 0
	local selected = gamble.Rarities[1]
	for _, rarity in ipairs(gamble.Rarities) do
		local weight = rarity.Weight
		local prize = rarity.Tickets or rarity.Cash or 0
		if prize > gamble.Cost then
			weight *= 1 + luck
		end
		cursor += weight
		if roll <= cursor then
			selected = rarity
			break
		end
	end

	local prizeTickets = selected.Tickets or selected.Cash or 0
	run.Tickets = (run.Tickets or 0) + prizeTickets
	sendMessage(player, `Mystery Wheel: {selected.Name}! +{prizeTickets} Tickets`)
	gambleResultEvent:FireClient(player, {
		Event = "MysteryWheel",
		GambleName = "MysteryWheel",
		DisplayName = gamble.DisplayName,
		Rarity = selected.Name,
		Cash = prizeTickets,
		Tickets = prizeTickets,
		Color = selected.Color,
		Rarities = gamble.Rarities,
		Cost = gamble.Cost,
	})
	pushState(player)
end

local function playGuessingGame(player: Player, run: RunState, bet)
	local gamble = GameConfig.Gambles.GuessingGame
	if type(bet) ~= "table" then
		sendMessage(player, "Choose a guess first.")
		return
	end
	spendGambleUse(run)
	run.Cash -= gamble.Cost
	scratchByPlayer[player] = nil
	CardBattlesByPlayer[player] = nil

	local betType = tostring(bet.Type or "")
	local betValue = bet.Value
	local slots = guessingGameSlots()

	local rng = rngByPlayer[player] or Random.new()
	local luck = run.LuckBonus or 0
	local eligibleList = {}
	local otherList = {}
	for _, value in ipairs(slots) do
		if guessingGameBetWins(value, betType, betValue) then
			table.insert(eligibleList, value)
		else
			table.insert(otherList, value)
		end
	end
	if #eligibleList == 0 then
		sendMessage(player, "Invalid guess.")
		run.Cash += gamble.Cost
		pushState(player)
		return
	end
	local eligibleChance = math.min(1, (#eligibleList / #slots) * (1 + luck))
	local result
	if rng:NextNumber() <= eligibleChance then
		result = eligibleList[rng:NextInteger(1, #eligibleList)]
	else
		result = otherList[rng:NextInteger(1, #otherList)]
	end

	local won = guessingGameBetWins(result, betType, betValue)
	local payout = 0
	if won then
		if betType == "Number" then
			payout = gamble.Cost * gamble.NumberPayoutMultiplier
		elseif betType == "Color" then
			payout = gamble.Cost * gamble.ColorPayoutMultiplier
		else
			payout = gamble.Cost * gamble.ParityPayoutMultiplier
		end
		run.Tickets = (run.Tickets or 0) + payout
	end
	local resultText = tostring(result)
	local resultColor = guessingGameColor(result)
	sendMessage(player, `Guessing Game result: {resultText} {resultColor}. {if won then "Win" else "Loss"} +{payout} Tickets`)
	gambleResultEvent:FireClient(player, {
		Event = "GuessingGameResult",
		GambleName = "GuessingGame",
		DisplayName = gamble.DisplayName,
		Result = resultText,
		ResultColor = resultColor,
		BetType = betType,
		BetValue = betValue,
		Won = won,
		Cash = payout,
		Tickets = payout,
		Cost = gamble.Cost,
	})
	pushState(player)
end

local function applyItem(player: Player, itemName: string)
	local run = runsByPlayer[player]
	if not run then
		return
	end

	if itemName == "Sword" then
		run.Damage += 10
		run.BarrelLevel = (run.BarrelLevel or 0) + 1
		sendMessage(player, `Laser Amplifier {run.BarrelLevel} installed. +10 laser damage`)
	elseif itemName == "Medkit" then
		run.Health = math.min(run.MaxHealth, run.Health + 1)
		sendMessage(player, "Medkit used. +1 heart")
	elseif itemName == "Armor" then
		run.MaxHealth += 1
		run.Health = math.min(run.MaxHealth, run.Health + 1)
		sendMessage(player, "Armor patched on. +1 max heart")
	elseif itemName == "CoinCharm" then
		run.LuckBonus += 0.06
		sendMessage(player, "Lucky Token acquired. The prizes bend a little.")
	elseif itemName == "CashMagnet" then
		run.CashBonusLevel = (run.CashBonusLevel or 0) + 1
		sendMessage(player, `Token Magnet {run.CashBonusLevel} acquired. Enemy tokens +{run.CashBonusLevel * 10}%.`)
	end
end

local function playGamble(player: Player, gambleName: string)
	local gamble = GameConfig.Gambles[gambleName]
	local canUse, run = canStartGamble(player, gambleName)
	if not canUse or not run or not gamble then
		return
	end

	if gambleName == "WhackAMole" then
		startWhackAMole(player, run)
		return
	elseif gambleName == "CardBattles" then
		startCardBattles(player, run)
		return
	elseif gambleName == "MysteryWheel" then
		playMysteryWheel(player, run)
		return
	elseif gambleName == "GuessingGame" then
		playGuessingGame(player, run, nil)
		return
	end

	run.Cash -= gamble.Cost
	spendGambleUse(run)
	local outcome = chooseOutcome(player, gambleName)
	if not outcome then
		pushState(player)
		return
	end

	if outcome.Cash then
		run.Tickets = (run.Tickets or 0) + outcome.Cash
	end
	if outcome.Item then
		applyItem(player, outcome.Item)
	end

	local payoutText = outcome.Cash and ` +{outcome.Cash} Tickets` or ""
	sendMessage(player, `{gamble.DisplayName}: {outcome.Text}{payoutText}`)
	gambleResultEvent:FireClient(player, {
		Event = "QuickResult",
		GambleName = gambleName,
		DisplayName = gamble.DisplayName,
		Text = outcome.Text,
		Cash = outcome.Cash or 0,
		Tickets = outcome.Cash or 0,
		Item = outcome.Item,
		Cost = gamble.Cost,
	})
	pushState(player)
end

local function makeEnemy(player: Player, enemyType: string, index: number, boss: boolean?)
	local run = runsByPlayer[player]
	local stats = GameConfig.Enemies[enemyType]
	if not run or not stats then
		return
	end

	local folder = playerFolder(player)
	local combatRoom = folder:FindFirstChild("CombatRoom")
	local combatFloor = combatRoom and combatRoom:FindFirstChild("CombatFloor")
	local origin = combatFloor and combatFloor:IsA("BasePart") and combatFloor.Position or combatOriginForPlayer(player)
	local floorTopY = if combatFloor and combatFloor:IsA("BasePart") then combatFloor.Position.Y + (combatFloor.Size.Y / 2) else origin.Y
	local rng = rngByPlayer[player] or Random.new()
	local angle = (index * 2.399963229728653) + rng:NextNumber(-0.2, 0.2)
	local radius = 34 + ((index % 3) * 4)
	if boss then
		radius = 18
	elseif enemyType == "Brute" then
		radius = 42
	elseif enemyType == "Dealer" then
		radius = 38
	end
	local position = Vector3.new(origin.X + math.cos(angle) * radius, floorTopY + 0.2, origin.Z + math.sin(angle) * radius)
	local enemyY = position.Y

	local model = Instance.new("Model")
	model.Name = stats.DisplayName
	model:SetAttribute("OwnerUserId", player.UserId)
	local maxEnemyHealth = if boss then stats.Health else stats.Health + ((run.Room - 1) * 5)
	model:SetAttribute("EnemyHealth", maxEnemyHealth)
	model:SetAttribute("MaxEnemyHealth", maxEnemyHealth)
	model:SetAttribute("CashReward", stats.Cash)
	model.Parent = combatRoom or folder
	run.EnemiesAlive += 1

	local scale = if boss then 2.35 elseif enemyType == "Brute" then 1.22 elseif enemyType == "Dealer" then 1.08 else 0.95
	local mainColor
	local suitColor
	local accentColor
	if boss then
		mainColor = Color3.fromRGB(120, 24, 42)
		suitColor = Color3.fromRGB(45, 18, 42)
		accentColor = Color3.fromRGB(238, 68, 212)
	elseif enemyType == "Brute" then
		mainColor = Color3.fromRGB(35, 67, 96)
		suitColor = Color3.fromRGB(20, 30, 48)
		accentColor = Color3.fromRGB(80, 168, 228)
	elseif enemyType == "Dealer" then
		mainColor = Color3.fromRGB(92, 28, 98)
		suitColor = Color3.fromRGB(24, 22, 33)
		accentColor = Color3.fromRGB(255, 246, 150)
	else
		mainColor = Color3.fromRGB(87, 45, 55)
		suitColor = Color3.fromRGB(34, 29, 38)
		accentColor = Color3.fromRGB(255, 76, 91)
	end
	local rootPart = makeEnemyPart(model, "HumanoidRootPart", Vector3.new(3.5 * scale, 6 * scale, 2.5 * scale), Vector3.new(0, 2.1 * scale, 0), Color3.fromRGB(0, 0, 0), Enum.Material.SmoothPlastic)
	rootPart.Transparency = 1
	model.PrimaryPart = rootPart

	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model

	local creatorVisualPart = placeCreatorEnemyVisual(model, enemyType, boss and 1.35 or 1)
	if creatorVisualPart then
		model:PivotTo(CFrame.new(position))
		alignModelBottomToY(model, floorTopY)
		enemyY = model:GetPivot().Position.Y
		addHealthBar(model, rootPart, maxEnemyHealth)
		addEnemySpawnEffect((combatRoom or folder) :: Folder, position, boss)
		if boss then
			local shield = Instance.new("Part")
			shield.Name = "AlienShield"
			shield.Anchored = true
			shield.CanCollide = false
			shield.CanTouch = false
			shield.CanQuery = false
			shield.Shape = Enum.PartType.Ball
			shield.Size = Vector3.new(20, 20, 20)
			shield.Color = Color3.fromRGB(92, 255, 196)
			shield.Material = Enum.Material.ForceField
			shield.Transparency = 1
			shield.Parent = model

			task.spawn(function()
				while model.Parent and run.Active and run.InCombat do
					if battleCountdownActive(run) then
						task.wait(0.1)
						continue
					end
					model:SetAttribute("Invulnerable", true)
					shield.Transparency = 0.42
					local shieldUntil = os.clock() + 2.5
					while model.Parent and os.clock() < shieldUntil do
						if model.PrimaryPart then
							shield.CFrame = CFrame.new(model.PrimaryPart.Position + Vector3.new(0, 3, 0))
						end
						task.wait(0.06)
					end
					model:SetAttribute("Invulnerable", false)
					shield.Transparency = 1
					task.wait(5)
				end
			end)

			task.spawn(function()
				local summonIndex = 100
				while model.Parent and run.Active and run.InCombat do
					if battleCountdownActive(run) then
						task.wait(0.1)
						continue
					end
					task.wait(3.2)
					if model.Parent and run.Active and run.InCombat then
						summonIndex += 1
						makeEnemy(player, if summonIndex % 2 == 0 then "Grunt" else "Brute", summonIndex, false)
					end
					task.wait(4)
				end
			end)
		end
		task.spawn(function()
			local attackCooldown = os.clock() + 1
			while model.Parent and run.Active and run.InCombat do
				if battleCountdownActive(run) then
					task.wait(0.1)
					continue
				end
				local character = player.Character
				local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
				if targetRoot and targetRoot:IsA("BasePart") and model.PrimaryPart then
					local current = model.PrimaryPart.Position
					local currentFlat = Vector3.new(current.X, enemyY, current.Z)
					local targetPosition = Vector3.new(targetRoot.Position.X, enemyY, targetRoot.Position.Z)
					local direction = targetPosition - currentFlat
					local distance = direction.Magnitude
					if enemyType == "Brute" then
						if distance > 0.5 then
							model:PivotTo(CFrame.lookAt(currentFlat, targetPosition))
						end
						if os.clock() > attackCooldown then
							attackCooldown = os.clock() + 2.4
							fireEnemyProjectile(player, model, currentFlat + Vector3.new(0, 3, 0), stats.Damage, 0.9, Color3.fromRGB(80, 168, 228), "BouncerChip")
						end
					elseif enemyType == "Dealer" then
						if distance > 0.5 then
							model:PivotTo(CFrame.lookAt(currentFlat, targetPosition))
						end
						if os.clock() > attackCooldown and distance > 1 then
							attackCooldown = os.clock() + 4.2
							local dashDirection = direction.Unit
							local dashPosition = currentFlat
							for _ = 1, 18 do
								if not model.Parent or not run.Active or not run.InCombat then
									break
								end
								dashPosition += dashDirection * 2.4
								model:PivotTo(CFrame.lookAt(dashPosition, targetPosition))
								if targetRoot.Parent and (model.PrimaryPart.Position - targetRoot.Position).Magnitude <= 4 then
									damagePlayer(player, stats.Damage, stats.DisplayName)
									break
								end
								task.wait(0.035)
							end
						end
					elseif boss then
						if distance > 6 then
							local step = direction.Unit * math.min(stats.Speed * 0.08, distance)
							local nextPosition = currentFlat + step
							model:PivotTo(CFrame.lookAt(nextPosition, targetPosition))
						elseif distance > 0.5 then
							model:PivotTo(CFrame.lookAt(currentFlat, targetPosition))
						end
						if os.clock() > attackCooldown then
							attackCooldown = os.clock() + 2.6
							for burst = 1, 3 do
								if not model.Parent or not run.Active or not run.InCombat then
									break
								end
								local fireFrom = model.PrimaryPart and model.PrimaryPart.Position or currentFlat
								fireEnemyProjectile(player, model, fireFrom + Vector3.new(0, 7, 0), stats.Damage, 2.4, Color3.fromRGB(92, 255, 196), "AlienLaser", false)
								task.wait(0.16)
							end
						end
					elseif distance > 4 then
						local nextPosition = currentFlat + (direction.Unit * math.min(stats.Speed * 0.07, distance))
						model:PivotTo(CFrame.lookAt(nextPosition, targetPosition))
					elseif os.clock() > attackCooldown then
						attackCooldown = os.clock() + 1.1
						damagePlayer(player, stats.Damage, stats.DisplayName)
					end
				end
				task.wait(0.12)
			end
		end)
		return
	end

	local torso = makeEnemyVisualPart(model, "UpperTorso", Vector3.new(3.4 * scale, 4.2 * scale, 2.3 * scale), Vector3.new(0, 2.3 * scale, 0), suitColor, Enum.Material.Metal, Enum.PartType.Ball)
	local chest = makeEnemyVisualPart(model, "ChestArmor", Vector3.new(3.8 * scale, 2.2 * scale, 0.35 * scale), Vector3.new(0, 2.7 * scale, -1.12 * scale), mainColor, Enum.Material.Metal)
	local head = makeEnemyVisualPart(model, "Head", Vector3.new(2.35 * scale, 2.35 * scale, 2.35 * scale), Vector3.new(0, 5.1 * scale, 0), mainColor, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	addEnemyMesh(head, Enum.MeshType.Head)

	local leftArm = makeEnemyVisualPart(model, "LeftArm", Vector3.new(3.7 * scale, 0.65 * scale, 0.65 * scale), Vector3.new(-2.6 * scale, 2.45 * scale, 0), mainColor, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, CFrame.Angles(0, 0, math.rad(67)))
	local rightArm = makeEnemyVisualPart(model, "RightArm", Vector3.new(3.7 * scale, 0.65 * scale, 0.65 * scale), Vector3.new(2.6 * scale, 2.45 * scale, 0), mainColor, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, CFrame.Angles(0, 0, math.rad(-67)))
	local leftLeg = makeEnemyVisualPart(model, "LeftLeg", Vector3.new(3.4 * scale, 0.75 * scale, 0.75 * scale), Vector3.new(-0.85 * scale, -1.25 * scale, 0), suitColor, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, CFrame.Angles(0, 0, math.rad(90)))
	local rightLeg = makeEnemyVisualPart(model, "RightLeg", Vector3.new(3.4 * scale, 0.75 * scale, 0.75 * scale), Vector3.new(0.85 * scale, -1.25 * scale, 0), suitColor, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, CFrame.Angles(0, 0, math.rad(90)))

	makeEnemyVisualPart(model, "LeftHandClaw", Vector3.new(0.55 * scale, 1.7 * scale, 0.55 * scale), Vector3.new(-3.85 * scale, 0.95 * scale, -0.2 * scale), accentColor, Enum.Material.Neon, Enum.PartType.Cylinder, CFrame.Angles(0, 0, math.rad(18)))
	makeEnemyVisualPart(model, "RightHandClaw", Vector3.new(0.55 * scale, 1.7 * scale, 0.55 * scale), Vector3.new(3.85 * scale, 0.95 * scale, -0.2 * scale), accentColor, Enum.Material.Neon, Enum.PartType.Cylinder, CFrame.Angles(0, 0, math.rad(-18)))
	makeEnemyVisualPart(model, "LeftEye", Vector3.new(0.55 * scale, 0.28 * scale, 0.18 * scale), Vector3.new(-0.48 * scale, 5.25 * scale, -1.08 * scale), Color3.fromRGB(255, 246, 150), Enum.Material.Neon, Enum.PartType.Ball)
	makeEnemyVisualPart(model, "RightEye", Vector3.new(0.55 * scale, 0.28 * scale, 0.18 * scale), Vector3.new(0.48 * scale, 5.25 * scale, -1.08 * scale), Color3.fromRGB(255, 246, 150), Enum.Material.Neon, Enum.PartType.Ball)

	local leftHorn = makeEnemyVisualPart(model, "LeftHorn", Vector3.new(0.65 * scale, 1.4 * scale, 0.65 * scale), Vector3.new(-0.85 * scale, 6.35 * scale, 0), accentColor, Enum.Material.Neon, Enum.PartType.Cylinder, CFrame.Angles(0, 0, math.rad(25)))
	local rightHorn = makeEnemyVisualPart(model, "RightHorn", Vector3.new(0.65 * scale, 1.4 * scale, 0.65 * scale), Vector3.new(0.85 * scale, 6.35 * scale, 0), accentColor, Enum.Material.Neon, Enum.PartType.Cylinder, CFrame.Angles(0, 0, math.rad(-25)))
	leftHorn.Size = Vector3.new(1.4 * scale, 0.45 * scale, 0.45 * scale)
	rightHorn.Size = Vector3.new(1.4 * scale, 0.45 * scale, 0.45 * scale)
	if boss then
		makeEnemyVisualPart(model, "BossCrown", Vector3.new(3.2 * scale, 0.55 * scale, 3.2 * scale), Vector3.new(0, 6.55 * scale, 0), Color3.fromRGB(217, 183, 87), Enum.Material.Metal, Enum.PartType.Cylinder)
		local shield = makeEnemyVisualPart(model, "HouseShield", Vector3.new(9 * scale, 9 * scale, 9 * scale), Vector3.new(0, 2.8 * scale, 0), Color3.fromRGB(80, 168, 228), Enum.Material.ForceField, Enum.PartType.Ball)
		shield.Transparency = 1
	elseif enemyType == "Brute" then
		makeEnemyVisualPart(model, "ShoulderPadLeft", Vector3.new(1.4 * scale, 0.7 * scale, 1.4 * scale), Vector3.new(-2.2 * scale, 3.7 * scale, 0), accentColor, Enum.Material.Metal, Enum.PartType.Ball)
		makeEnemyVisualPart(model, "ShoulderPadRight", Vector3.new(1.4 * scale, 0.7 * scale, 1.4 * scale), Vector3.new(2.2 * scale, 3.7 * scale, 0), accentColor, Enum.Material.Metal, Enum.PartType.Ball)
	elseif enemyType == "Dealer" then
		makeEnemyVisualPart(model, "DealerHat", Vector3.new(2.6 * scale, 0.35 * scale, 2.6 * scale), Vector3.new(0, 6.05 * scale, 0), accentColor, Enum.Material.Metal, Enum.PartType.Cylinder)
		makeEnemyVisualPart(model, "DealerCardLeft", Vector3.new(0.75 * scale, 1.1 * scale, 0.08 * scale), Vector3.new(-1.5 * scale, 3.05 * scale, -1.22 * scale), Color3.fromRGB(255, 255, 245), Enum.Material.SmoothPlastic)
		makeEnemyVisualPart(model, "DealerCardRight", Vector3.new(0.75 * scale, 1.1 * scale, 0.08 * scale), Vector3.new(1.5 * scale, 3.05 * scale, -1.22 * scale), Color3.fromRGB(255, 255, 245), Enum.Material.SmoothPlastic)
	else
		makeEnemyVisualPart(model, "DebtVisor", Vector3.new(1.8 * scale, 0.25 * scale, 0.2 * scale), Vector3.new(0, 5.55 * scale, -1.12 * scale), accentColor, Enum.Material.Neon)
	end
	model:PivotTo(CFrame.new(position))
	alignModelBottomToY(model, floorTopY)
	enemyY = model:GetPivot().Position.Y
	addPointLight(torso, accentColor, boss and 2.5 or 1.4, boss and 22 or 14)
	addHealthBar(model, rootPart, maxEnemyHealth)
	addEnemySpawnEffect((combatRoom or folder) :: Folder, position, boss)

	if boss then
		task.spawn(function()
			local shield = model:FindFirstChild("HouseShield")
			while model.Parent and run.Active and run.InCombat do
				if battleCountdownActive(run) then
					task.wait(0.1)
					continue
				end
				model:SetAttribute("Invulnerable", true)
				if shield and shield:IsA("BasePart") then
					shield.Transparency = 0.45
				end
				task.wait(2.5)
				model:SetAttribute("Invulnerable", false)
				if shield and shield:IsA("BasePart") then
					shield.Transparency = 1
				end
				task.wait(5)
			end
		end)

		task.spawn(function()
			local summonIndex = 100
			while model.Parent and run.Active and run.InCombat do
				if battleCountdownActive(run) then
					task.wait(0.1)
					continue
				end
				local root = model.PrimaryPart
				if root then
					for burst = 1, 3 do
						if not model.Parent or not run.Active or not run.InCombat then
							break
						end
						fireEnemyProjectile(player, model, root.Position + Vector3.new(0, 6, 0), stats.Damage, 2.4, Color3.fromRGB(92, 255, 196), "AlienLaser", false)
						task.wait(0.16)
					end
				end
				task.wait(1.4)
				if model.Parent and run.Active and run.InCombat then
					summonIndex += 1
					makeEnemy(player, if summonIndex % 2 == 0 then "Grunt" else "Brute", summonIndex, false)
				end
				task.wait(4.5)
			end
		end)
	end

	task.spawn(function()
		local attackCooldown = 0
		local bornAt = os.clock()
		while model.Parent and run.Active and run.InCombat do
			if battleCountdownActive(run) then
				task.wait(0.1)
				continue
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and model.PrimaryPart then
				local currentPivot = model:GetPivot()
				local currentFlat = Vector3.new(currentPivot.Position.X, enemyY, currentPivot.Position.Z)
				local targetPosition = Vector3.new(root.Position.X, enemyY, root.Position.Z)
				local direction = targetPosition - currentFlat
				local distance = direction.Magnitude
				if enemyType == "Dealer" then
					if os.clock() > attackCooldown and distance > 1 then
						attackCooldown = os.clock() + 4.2
						local dashDirection = direction.Unit
						for shake = 1, 10 do
							if not model.Parent or not run.Active or not run.InCombat then
								break
							end
							local jitter = Vector3.new(rng:NextNumber(-0.45, 0.45), 0, rng:NextNumber(-0.45, 0.45))
							model:PivotTo(CFrame.lookAt(currentFlat + jitter, targetPosition))
							task.wait(0.1)
						end

						local dashPosition = Vector3.new(model:GetPivot().Position.X, enemyY, model:GetPivot().Position.Z)
						local floorSize = combatFloor and combatFloor:IsA("BasePart") and combatFloor.Size or Vector3.new(92, 1, 92)
						local halfX = math.max(8, (floorSize.X / 2) - 5)
						local halfZ = math.max(8, (floorSize.Z / 2) - 5)
						local minX = origin.X - halfX
						local maxX = origin.X + halfX
						local minZ = origin.Z - halfZ
						local maxZ = origin.Z + halfZ
						local hitPlayer = false
						for _ = 1, 80 do
							if not model.Parent or not run.Active or not run.InCombat then
								break
							end
							dashPosition += dashDirection * 3.2
							if dashPosition.X <= minX or dashPosition.X >= maxX or dashPosition.Z <= minZ or dashPosition.Z >= maxZ then
								dashPosition = Vector3.new(math.clamp(dashPosition.X, minX, maxX), enemyY, math.clamp(dashPosition.Z, minZ, maxZ))
								model:PivotTo(CFrame.lookAt(dashPosition, dashPosition + dashDirection))
								break
							end
							model:PivotTo(CFrame.lookAt(dashPosition, dashPosition + dashDirection))
							local playerRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
							if not hitPlayer and playerRoot and playerRoot:IsA("BasePart") and (dashPosition - Vector3.new(playerRoot.Position.X, enemyY, playerRoot.Position.Z)).Magnitude <= 4 then
								hitPlayer = true
								damagePlayer(player, stats.Damage, stats.DisplayName)
							end
							task.wait(0.035)
						end
					else
						model:PivotTo(CFrame.lookAt(currentFlat, targetPosition))
					end
				elseif enemyType == "Brute" then
					model:PivotTo(CFrame.lookAt(currentFlat, targetPosition))
					if os.clock() > attackCooldown then
						attackCooldown = os.clock() + 1.75
						fireEnemyProjectile(player, model, currentFlat + Vector3.new(0, 3.5, 0), stats.Damage, 1.65, Color3.fromRGB(80, 168, 228), "BouncerChip", false)
					end
				elseif distance > 4 then
					local step = direction.Unit * math.min(stats.Speed * 0.12, distance)
					local nextFlat = currentFlat + step
					local bob = math.sin((os.clock() - bornAt) * 7) * (boss and 0.35 or 0.22)
					model:PivotTo(CFrame.lookAt(nextFlat + Vector3.new(0, bob, 0), targetPosition))
				elseif os.clock() > attackCooldown then
					attackCooldown = os.clock() + 1.2
					damagePlayer(player, stats.Damage, stats.DisplayName)
					model:PivotTo(model:GetPivot() * CFrame.Angles(0, 0, math.rad(boss and 10 or 16)))
					task.delay(0.08, function()
						if model.Parent then
							model:PivotTo(CFrame.lookAt(Vector3.new(model:GetPivot().Position.X, enemyY, model:GetPivot().Position.Z), targetPosition))
						end
					end)
				end
			end
			task.wait(0.12)
		end
	end)

	task.delay(0.2 + (index * 0.05), function()
		pushState(player)
	end)
end

local function completeCombatIfReady(player: Player)
	local run = runsByPlayer[player]
	if not run or not run.InCombat or run.EnemiesAlive > 0 then
		return
	end

	run.InCombat = false
	run.BattleCountdown = 0
	setPlayerBattleFrozen(player, false)
	if run.Room > GameConfig.Run.RoomsToBoss then
		run.BossDefeated = true
		run.Active = false
		clearCombatRoom(player)
		teleportPlayer(player, baseSpawnPosition(player))
		local meta = metaByPlayer[player]
		if meta then
			local tokenReward = GameConfig.Enemies.Boss.Tokens
			meta.Tokens += tokenReward
			meta.Wins = (meta.Wins or 0) + 1
			saveMeta(player)
			sendMessage(player, `Final cabinet defeated. Banked {tokenReward} Cash for arcade machines.`)
		end
		buildRoom(player)
	else
		local tokenReward = GameConfig.Run.RoomTokenReward or GameConfig.Run.RoomCashReward
		run.Cash += tokenReward
		sendMessage(player, `Room cleared. +{tokenReward} Tokens. Play machines, visit the Ticket Booth, then open the map.`)
		run.Room += 1
		clearCombatRoom(player)
		teleportPlayer(player, baseSpawnPosition(player))
	end
	pushState(player)
end

local function watchCombat(player: Player)
	task.spawn(function()
		while player.Parent do
			local run = runsByPlayer[player]
			if run and run.InCombat then
				completeCombatIfReady(player)
			end
			task.wait(0.35)
		end
	end)
end

local function startFight(player: Player)
	local run = runsByPlayer[player]
	if not run or not run.Active then
		sendMessage(player, "Start a run first.")
		return
	end
	if run.InCombat then
		sendMessage(player, "Already in a fight.")
		return
	end

	run.InCombat = true
	run.EnemiesAlive = 0
	run.BattleCountdown = 3
	giveRunGun(player)

	if run.Room > GameConfig.Run.RoomsToBoss then
		buildCombatRoom(player, true)
		setPlayerBattleFrozen(player, true)
		sendMessage(player, "Boss room. Defeat the Final Cabinet.")
		makeEnemy(player, "Boss", 1, true)
	else
		local enemies = enemyTypesForRoom(run.Room)
		buildCombatRoom(player, false)
		setPlayerBattleFrozen(player, true)
		sendMessage(player, `Room {run.Room}: survive {#enemies} enemies.`)
		for i, enemyType in ipairs(enemies) do
			makeEnemy(player, enemyType, i)
		end
	end

	pushState(player)
	task.spawn(function()
		for seconds = 3, 1, -1 do
			local currentRun = runsByPlayer[player]
			if currentRun ~= run or not currentRun or not currentRun.Active or not currentRun.InCombat then
				setPlayerBattleFrozen(player, false)
				return
			end
			currentRun.BattleCountdown = seconds
			pushState(player)
			task.wait(1)
		end

		if runsByPlayer[player] == run and run.Active and run.InCombat then
			run.BattleCountdown = 0
			setPlayerBattleFrozen(player, false)
			sendMessage(player, "Fight!")
			pushState(player)
		end
	end)
end

local function startNewRun(player: Player)
	setPlayerBattleFrozen(player, false)
	scratchByPlayer[player] = nil
	CardBattlesByPlayer[player] = nil
	clearCombatRoom(player)
	ensureRun(player)
	giveRunGun(player)
	buildRoom(player)
	sendMessage(player, "New run started. Spend Tokens on arcade games, earn Tickets, then visit the Ticket Booth.")
	pushState(player)
end

local function pauseRun(player: Player)
	local run = runsByPlayer[player]
	if not run or not run.Active then
		sendMessage(player, "No active run to pause.")
		pushState(player)
		return
	end

	run.Active = false
	run.Paused = true
	run.InCombat = false
	run.BattleCountdown = 0
	setPlayerBattleFrozen(player, false)
	clearCombatRoom(player)
	removeRunGun(player)
	scratchByPlayer[player] = nil
	CardBattlesByPlayer[player] = nil
	buildRoom(player)
	sendMessage(player, "Run paused. Resume when you are ready.")
	pushState(player)
end

local function resumeRun(player: Player)
	local run = runsByPlayer[player]
	if not run or not run.Paused then
		sendMessage(player, "No paused run to resume.")
		pushState(player)
		return
	end

	run.Active = true
	run.Paused = false
	run.InCombat = false
	run.BattleCountdown = 0
	setPlayerBattleFrozen(player, false)
	buildRoom(player)
	giveRunGun(player)
	sendMessage(player, "Run resumed. Continue from your base.")
	pushState(player)
end

local function quitRun(player: Player)
	if not runsByPlayer[player] then
		sendMessage(player, "No run to quit.")
		pushState(player)
		return
	end

	runsByPlayer[player] = nil
	scratchByPlayer[player] = nil
	CardBattlesByPlayer[player] = nil
	setPlayerBattleFrozen(player, false)
	removeRunGun(player)
	buildRoom(player)
	sendMessage(player, "Run quit. Cash and unlocked machines are unchanged.")
	pushState(player)
end

local function buyShopItem(player: Player, itemName: string)
	local run = runsByPlayer[player]
	local item = GameConfig.ShopItems[itemName]
	if not run or not run.Active then
		sendMessage(player, "Ticket Booth is only usable during a run.")
		return
	end
	if run.InCombat then
		sendMessage(player, "No Ticket Booth purchases during combat.")
		return
	end
	if not item then
		return
	end
	local cost = item.Cost
	if itemName == "Sword" then
		cost += (run.BarrelLevel or 0) * (item.CostIncrease or 0)
	elseif itemName == "CashMagnet" then
		cost += (run.CashBonusLevel or 0) * (item.CostIncrease or 0)
	end
	if (run.Tickets or 0) < cost then
		sendMessage(player, "Not enough Tickets.")
		return
	end

	run.Tickets = (run.Tickets or 0) - cost
	applyItem(player, itemName)
	pushState(player)
end

local function buyUpgrade(player: Player, upgradeName: string)
	local meta = metaByPlayer[player]
	local upgrade = GameConfig.MetaUpgrades[upgradeName]
	if not meta or not upgrade then
		return
	end

	local level = meta.Upgrades[upgradeName] or 0
	if level >= upgrade.MaxLevel then
		sendMessage(player, "That upgrade is maxed.")
		return
	end

	local cost = getMetaCost(upgradeName, level)
	if meta.Tokens < cost then
		sendMessage(player, "Not enough Cash.")
		return
	end

	meta.Tokens -= cost
	meta.Upgrades[upgradeName] = level + 1
	saveMeta(player)
	sendMessage(player, `{upgrade.DisplayName} upgraded to level {level + 1}.`)
	pushState(player)
end

local function buyGameUnlock(player: Player, gambleName: string)
	local meta = metaByPlayer[player]
	local run = runsByPlayer[player]
	local unlock = GameConfig.GameUnlocks[gambleName]
	if not meta or not unlock then
		return
	end
	if run and run.Active then
		sendMessage(player, "Machine Shop is unavailable during a run.")
		return
	end
	if isGambleUnlocked(meta, gambleName) then
		sendMessage(player, `{unlock.DisplayName} is already unlocked.`)
		return
	end
	local canBuy, reason = canBuyGameUnlock(meta, gambleName)
	if not canBuy then
		sendMessage(player, reason or "Cannot unlock that yet.")
		return
	end

	meta.Tokens -= unlock.Cost
	meta.Unlocks[gambleName] = true
	saveMeta(player)
	sendMessage(player, `{unlock.DisplayName} machine unlocked for future runs.`)
	buildRoom(player)
	pushState(player)
end

handleAction = function(player: Player, action: string, payload: any?)
	if action == "StartRun" then
		startNewRun(player)
	elseif action == "PauseRun" then
		pauseRun(player)
	elseif action == "ResumeRun" then
		resumeRun(player)
	elseif action == "QuitRun" then
		quitRun(player)
	elseif action == "StartFight" then
		startFight(player)
	elseif action == "ShootGun" then
		shootRunGun(player, payload)
	elseif action == "Gamble" then
		playGamble(player, payload)
	elseif action == "GuessingGameBet" then
		local canUse, run = canStartGamble(player, "GuessingGame")
		if canUse and run then
			playGuessingGame(player, run, payload)
		end
	elseif action == "ScratchReveal" or action == "WhackMoleHit" then
		revealScratch(player, payload)
	elseif action == "CardBattlesHit" then
		hitCardBattles(player)
	elseif action == "CardBattlesStand" then
		standCardBattles(player)
	elseif action == "BuyItem" then
		buyShopItem(player, payload)
	elseif action == "BuyUpgrade" then
		buyUpgrade(player, payload)
	elseif action == "BuyGameUnlock" then
		buyGameUnlock(player, payload)
	elseif action == "RequestState" then
		pushState(player)
	end
end

actionEvent.OnServerEvent:Connect(handleAction)

Players.PlayerAdded:Connect(function(player)
	rngByPlayer[player] = Random.new(player.UserId + os.time())
	loadMeta(player)
	watchCombat(player)

	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		setPlayerBattleFrozen(player, false)
		buildRoom(player)
		if runsByPlayer[player] and runsByPlayer[player].Active then
			giveRunGun(player)
		end
		pushState(player)
	end)

	task.defer(function()
		buildRoom(player)
		pushState(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	saveMeta(player)
	clearPlayerArena(player)
	local slot = arenaSlotByPlayer[player]
	if slot then
		arenaSlotOccupied[slot] = nil
	end
	arenaSlotByPlayer[player] = nil
	ensureSharedBasePlaza()
	metaByPlayer[player] = nil
	runsByPlayer[player] = nil
	rngByPlayer[player] = nil
	scratchByPlayer[player] = nil
	CardBattlesByPlayer[player] = nil
end)

createToolTemplate()
