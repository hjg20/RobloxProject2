local GameConfig = {}

GameConfig.Run = {
	StartingTokens = 15,
	StartingCash = 15,
	StartingTickets = 0,
	StartingHealth = 3,
	StartingDamage = 12,
	StartingMaxHealth = 3,
	RoomsToBoss = 4,
	RoomTokenReward = 18,
	RoomCashReward = 18,
	EnemySpawnRadius = 28,
	StartingGambles = 999,
}

GameConfig.MetaUpgrades = {
	Bankroll = {
		DisplayName = "Starter Tokens",
		MaxLevel = 5,
		BaseCost = 3,
		Description = "+8 starting tokens per level",
	},
	Vitality = {
		DisplayName = "Vitality",
		MaxLevel = 5,
		BaseCost = 4,
		Description = "+1 max heart per level",
	},
	Edge = {
		DisplayName = "Laser Focus",
		MaxLevel = 5,
		BaseCost = 5,
		Description = "+3 laser damage per level",
	},
	Luck = {
		DisplayName = "Lucky Joystick",
		MaxLevel = 4,
		BaseCost = 6,
		Description = "+2% arcade prize chance per level",
	},
}

GameConfig.GameUnlocks = {
	CardBattles = {
		DisplayName = "Card Battle",
		Cost = 5,
		RequiredWins = 0,
		Description = "Unlock the Card Battle arcade machine.",
	},
	GuessingGame = {
		DisplayName = "Guessing Game",
		Cost = 20,
		RequiredWins = 3,
		Description = "Unlock the Guessing Game arcade machine.",
	},
	MysteryWheel = {
		DisplayName = "Mystery Wheel",
		Cost = 50,
		RequiredWins = 5,
		Description = "Unlock the Mystery Wheel arcade machine.",
	},
}

-- Put Creator Store model asset IDs here. A value of 0 keeps the current fallback model.
GameConfig.CreatorStoreAssets = {
	Base = {
		TokenShop = 2310029676,
		WhackAMole = 0,
		CardBattle = 0,
		GuessingGame = 0,
		MysteryWheel = 0,
	},
	Enemies = {
		Grunt = 18410234566,
		Brute = 133676574,
		Dealer = 11828997942,
		Boss = 460217555,
	},
}

GameConfig.GuiImages = {
	ArcadeRush = "rbxassetid://100069856506384",
	Map = "rbxassetid://124742725015739",
	Shop = "rbxassetid://86048304002227",
	ItemLibrary = "rbxassetid://122971181450283",
	Start = "rbxassetid://108056925526072",
	Restart = "rbxassetid://106730712404682",
	Pause = "rbxassetid://115733781486000",
	Resume = "rbxassetid://101813961912441",
	Quit = "rbxassetid://101466859199749",
	WhackAMole = "rbxassetid://108498330093062",
	CardBattle = "rbxassetid://90958297469438",
	GuessingGame = "rbxassetid://104322050610028",
	MysteryWheel = "rbxassetid://92167325033232",
}

GameConfig.Items = {
	["Lighter Bones"] = {
		Name = "Lighter Bones",
		Rarity = "Common",
		Tooltip = "We drilled holes in your bones while you slept... on the bright side you're 50% faster now!",
		UnlockText = "Always unlocked.",
		Sprite = "rbxassetid://88964560200651",
		AlwaysUnlocked = true,
	},
	["Gold-Stitched Pockets"] = {
		Name = "Gold-Stitched Pockets",
		Rarity = "Common",
		Tooltip = "25% more tokens! Thanks evil alien dudes!",
		UnlockText = "Always unlocked.",
		Sprite = "rbxassetid://99328738664890",
		AlwaysUnlocked = true,
	},
	["Mom's Credit Card"] = {
		Name = "Mom's Credit Card",
		Rarity = "Uncommon",
		Tooltip = "Makes all arcade games free for 30 seconds! Thanks mom!",
		UnlockText = "Play a single arcade game 10 times in one room.",
		Sprite = "rbxassetid://137704741349569",
		Active = true,
		ChargeType = "Room",
		UnlockCondition = "MaxRoomGamePlays",
		UnlockThreshold = 10,
	},
	["Pocket Watch"] = {
		Name = "Pocket Watch",
		Rarity = "Uncommon",
		Tooltip = "Slows down time-based games by 25%. Boring!",
		UnlockText = "Get a perfect score in Whack-a-Mole.",
		Sprite = "rbxassetid://111410935969293",
		UnlockCondition = "ItemProgress",
		UnlockKey = "WhackAMolePerfect",
		UnlockThreshold = 1,
	},
	["Token on a String"] = {
		Name = "Token on a String",
		Rarity = "Uncommon",
		Tooltip = "10% chance for a machine to not take tokens. What, are you broke?",
		UnlockText = "Spend 1,000 tokens.",
		Sprite = "rbxassetid://136434279495520",
		UnlockCondition = "ItemProgress",
		UnlockKey = "TokensSpent",
		UnlockThreshold = 1000,
	},
	["Helium-Filled Sneakers"] = {
		Name = "Helium-Filled Sneakers",
		Rarity = "Rare",
		Tooltip = "Do helium-filled shoes let you jump twice? Idk, but now they do!",
		UnlockText = "Defeat the boss once.",
		Sprite = "rbxassetid://87302634792921",
		UnlockCondition = "Wins",
		UnlockThreshold = 1,
	},
	["Counterfeit Ticket"] = {
		Name = "Counterfeit Ticket",
		Rarity = "Rare",
		Tooltip = "Do you think the ticket guy will fall for it?",
		UnlockText = "Hold 500 tickets at once.",
		Sprite = "rbxassetid://117273716979559",
		Active = true,
		ChargeType = "Room",
		UnlockCondition = "Tickets",
		UnlockThreshold = 500,
	},
	["Four-Leaf Clover"] = {
		Name = "Four-Leaf Clover",
		Rarity = "Legendary",
		Tooltip = "Feels lucky... like 100% increase to your luck stat lucky...",
		UnlockText = "Beat a floor without getting hit.",
		Sprite = "rbxassetid://107466951128649",
		UnlockCondition = "UnlockKey",
		UnlockKey = "NoHitFloor",
	},
}

GameConfig.Gambles = {
	WhackAMole = {
		DisplayName = "Whack-a-Mole",
		Cost = 5,
		Description = "Whack real moles for points. Fake moles and blank slots cost points.",
		Slots = 10,
		Rounds = 12,
		PopupDuration = 0.55,
		HitPoints = 5,
		MissPenalty = 3,
		FakePenalty = 4,
		FakeChance = 0.45,
	},
	CardBattles = {
		DisplayName = "Card Battle",
		Cost = 10,
		Description = "Battle an arcade worker to get closest to 21.",
		WinPayout = 20,
		CardBattlesPayout = 30,
		PushPayout = 10,
	},
	MysteryWheel = {
		DisplayName = "Mystery Wheel",
		Cost = 18,
		Description = "Spin the wheel for a random ticket prize.",
		Rarities = {
			{ Name = "Small Prize", Weight = 50, Tickets = 5, Cash = 5, Color = { 150, 158, 170 } },
			{ Name = "Nice Prize", Weight = 30, Tickets = 20, Cash = 20, Color = { 74, 190, 114 } },
			{ Name = "Big Prize", Weight = 10, Tickets = 50, Cash = 50, Color = { 78, 139, 234 } },
			{ Name = "Jackpot", Weight = 9, Tickets = 100, Cash = 100, Color = { 238, 177, 54 } },
			{ Name = "Mega Arcade Rush", Weight = 1, Tickets = 1000, Cash = 1000, Color = { 238, 68, 212 } },
		},
	},
	GuessingGame = {
		DisplayName = "Guessing Game",
		Cost = 10,
		Description = "Guess the result: color, odd/even, or exact number.",
		ColorPayoutMultiplier = 2,
		ParityPayoutMultiplier = 2,
		NumberPayoutMultiplier = 35,
	},
}

GameConfig.ShopItems = {
	Sword = {
		DisplayName = "Laser Amplifier",
		Cost = 25,
		CostIncrease = 15,
		Description = "+10 laser damage",
	},
	Medkit = {
		DisplayName = "Medkit",
		Cost = 18,
		Description = "Heal 1 heart",
	},
	Armor = {
		DisplayName = "Cheap Armor",
		Cost = 35,
		Description = "+1 max heart and heal 1 heart",
	},
	CoinCharm = {
		DisplayName = "Lucky Token",
		Cost = 45,
		Description = "+6% arcade prize chance this run",
	},
	CashMagnet = {
		DisplayName = "Token Magnet",
		Cost = 40,
		CostIncrease = 25,
		Description = "+10% enemy token drops",
	},
}

GameConfig.Enemies = {
	Grunt = {
		DisplayName = "Prize Snatcher",
		Health = 75,
		Damage = 1,
		Speed = 12,
		Cash = 6,
	},
	Brute = {
		DisplayName = "Arcade Guard",
		Health = 150,
		Damage = 1,
		Speed = 15,
		Cash = 11,
	},
	Dealer = {
		DisplayName = "Dash Bot",
		Health = 300,
		Damage = 1,
		Speed = 28,
		Cash = 16,
	},
	Boss = {
		DisplayName = "The Final Cabinet",
		Health = 1500,
		Damage = 1,
		Speed = 10,
		Cash = 50,
		Tokens = 5,
	},
}

GameConfig.RouletteLookup = {
	Red = {
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
	},
}

GameConfig.Arena = {
	BaseColumnsPerSide = 4,
	BaseSpacingX = 170,
	BaseRowZ = 165,
	CombatFloorSize = 92,
	CombatWallDistance = 58,
	CombatFloorClearance = 118,
	SlotRingSpacing = 145,
	EnemySpawnEffectDuration = 0.15,
}

GameConfig.Gameplay = {
	WhackAMolePopupDuration = 0.55,
	CardBattleAnimationSpeed = 0.15,
	MysteryWheelSpinDuration = 2.8,
	ShootGunMaxRange = 150,
	ProjectilePersistenceFrames = 80,
}

return GameConfig
