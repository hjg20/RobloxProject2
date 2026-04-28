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
	Blackjack = {
		DisplayName = "Card Battle",
		Cost = 5,
		RequiredWins = 0,
		Description = "Unlock the Card Battle arcade machine.",
	},
	Roulette = {
		DisplayName = "Guessing Game",
		Cost = 20,
		RequiredWins = 3,
		Description = "Unlock the Guessing Game arcade machine.",
	},
	LootBox = {
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

GameConfig.Gambles = {
	ScratchOff = {
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
	Blackjack = {
		DisplayName = "Card Battle",
		Cost = 12,
		Description = "Battle an arcade worker to get closest to 21.",
		WinPayout = 24,
		BlackjackPayout = 36,
		PushPayout = 12,
	},
	LootBox = {
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
	Roulette = {
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

return GameConfig
