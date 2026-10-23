repeat task.wait() until game:IsLoaded()

local PlayerService = game:GetService("Players")
local RunService = game:GetService("RunService")
local WorkSpace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local NetworkClient = game:GetService("NetworkClient")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = PlayerService.LocalPlayer

shared.AlSploitUnInjected = false

local CONFIG = {
	Speed = 25,
	Distance = 500,
	BagMax = 50,
	CollectWait = 0.2,
	SkipTime = 2,
	MurdererAvoidRadius = 17,
	MurdererPollRate = 0.5,
	PlayerAvoidRadius = 10,
	TimeoutMargin = 2,
	StuckCheckTime = 0.4,
	StuckMinProgress = 0.35,
	UnstuckJump = 4,

	-- AUTO-REJOIN
	AutoRejoin = true,
	ScriptUrl = "https://raw.githubusercontent.com/Wilkr34/ooidyhhd/refs/heads/main/mm2.lua",
	ScriptFile = "MM2AutoFarm.lua",
	HopRetryDelay = 8,
	HopOnKick = true,
	HopOnShutdown = true,
	HopOnConnectionLost = true,
	HopOnIdle = true,
	HopOnUnknown = true,
}

local Resetting = false
local Visited = {}
local MurdererPlayer = nil
local Connections = {}

local function Notify(Text)
	print("[AutoFarm] " .. Text)

	pcall(function()
		StarterGui:SetCore("SendNotification", {Title = "AutoFarm", Text = Text, Duration = 6})
	end)
end

-- ANTI-AFK
Connections.AntiAfk = LocalPlayer.Idled:Connect(function()
	pcall(function()
		VirtualUser:Button2Down(Vector2.new(0, 0), WorkSpace.CurrentCamera.CFrame)
		task.wait(1)
		VirtualUser:Button2Up(Vector2.new(0, 0), WorkSpace.CurrentCamera.CFrame)
	end)
end)

-- ANTI-FLING
Connections.AntiFling = RunService.Stepped:Connect(function()
	for _, player in pairs(PlayerService:GetPlayers()) do
		if player ~= LocalPlayer and player.Character then
			for _, v in pairs(player.Character:GetDescendants()) do
				if v:IsA("BasePart") then
					v.CanCollide = false
				end
			end
		end
	end
end)

-- NOCLIP PERMANENT (Stepped = avant le calcul de la physique)
Connections.Noclip = RunService.Stepped:Connect(function()
	local Character = LocalPlayer.Character

	if Character then
		for _, v in ipairs(Character:GetDescendants()) do
			if v:IsA("BasePart") then
				v.CanCollide = false
			end
		end
	end
end)

-- AUTO-REJOIN : DETECTION KICK / DECONNEXION + CHANGEMENT DE SERVEUR
local Hopping = false
local Queued = false

local function QueueScript()
	if Queued == true then return true end

	local QueueFunction = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)

	if not QueueFunction then
		Notify("queue_on_teleport indisponible : le script ne se relancera pas tout seul")
		return false
	end

	local Source

	if CONFIG.ScriptUrl ~= "" then
		Source = string.format("loadstring(game:HttpGet(%q, true))()", CONFIG.ScriptUrl)
	else
		if isfile and isfile(CONFIG.ScriptFile) == false then
			Notify("Fichier " .. CONFIG.ScriptFile .. " introuvable dans le workspace")
		end

		Source = string.format("loadstring(readfile(%q))()", CONFIG.ScriptFile)
	end

	local Ok = pcall(QueueFunction, "task.wait(3)\n" .. Source)

	Queued = Ok

	return Ok
end

local function FindNewServer()
	local Url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true"

	local Ok, Body = pcall(function()
		return HttpService:JSONDecode(game:HttpGet(Url))
	end)

	if not Ok or type(Body) ~= "table" or type(Body.data) ~= "table" then
		return nil
	end

	local Candidates = {}

	for _, Server in ipairs(Body.data) do
		if tonumber(Server.playing) and tonumber(Server.maxPlayers) and Server.id ~= game.JobId then
			if Server.playing < (Server.maxPlayers - 1) then
				table.insert(Candidates, Server.id)
			end
		end
	end

	if #Candidates == 0 then
		return nil
	end

	return Candidates[math.random(1, #Candidates)]
end

local function HopToNewServer(Reason)
	if Hopping == true or shared.AlSploitUnInjected == true then return end

	Hopping = true

	Notify("Deconnecte (" .. Reason .. ") : changement de serveur")

	QueueScript()

	task.spawn(function()
		local Attempt = 0

		while shared.AlSploitUnInjected == false do
			Attempt = Attempt + 1

			local JobId = FindNewServer()

			pcall(function()
				if JobId then
					TeleportService:TeleportToPlaceInstance(game.PlaceId, JobId, LocalPlayer)
				elseif Attempt % 2 == 1 then
					TeleportService:Teleport(game.PlaceId, LocalPlayer)
				else
					TeleportService:TeleportAsync(game.PlaceId, {LocalPlayer}, Instance.new("TeleportOptions"))
				end
			end)

			task.wait(CONFIG.HopRetryDelay)
		end
	end)
end

-- Classe la cause de la déconnexion d'après le code d'erreur Roblox et le texte du message
local function Classify(Message)
	Message = string.lower(Message or "")

	local CodeName = ""

	pcall(function()
		CodeName = string.lower(tostring(GuiService:GetErrorCode()))
	end)

	local Number = tonumber(string.match(Message, "error code:%s*(%d+)"))

	if string.find(Message, "banned") or string.find(Message, "ban ") or string.find(CodeName, "ban") then
		return "Ban"
	end

	if Number == 273 or string.find(Message, "another device") or string.find(CodeName, "duplicate") then
		return "Duplicate"
	end

	if Number == 267 or Number == 268 or string.find(Message, "kick") or string.find(CodeName, "kick") then
		return "Kick"
	end

	if Number == 274 or string.find(Message, "shutdown") or string.find(Message, "shut down") then
		return "Shutdown"
	end

	if Number == 278 or string.find(Message, "idle") then
		return "Idle"
	end

	if Number == 277 or Number == 279 or string.find(Message, "lost") or string.find(Message, "connection") or string.find(Message, "timeout") or string.find(CodeName, "timeout") or string.find(CodeName, "connectionlost") then
		return "ConnectionLost"
	end

	return "Unknown"
end

local function HandleDisconnect(Message)
	if CONFIG.AutoRejoin == false or Hopping == true or shared.AlSploitUnInjected == true then return end

	local Kind = Classify(Message)

	if Kind == "Ban" then
		Notify("Ban detecte : pas de changement de serveur")
		return
	end

	if Kind == "Duplicate" then
		Notify("Compte connecte ailleurs : pas de changement de serveur")
		return
	end

	local Allowed = {
		Kick = CONFIG.HopOnKick,
		Shutdown = CONFIG.HopOnShutdown,
		ConnectionLost = CONFIG.HopOnConnectionLost,
		Idle = CONFIG.HopOnIdle,
		Unknown = CONFIG.HopOnUnknown,
	}

	if Allowed[Kind] == true then
		HopToNewServer(Kind)
	end
end

Connections.ErrorMessage = GuiService.ErrorMessageChanged:Connect(function(Message)
	if not Message or Message == "" then return end

	HandleDisconnect(Message)
end)

Connections.NetworkRemoved = NetworkClient.ChildRemoved:Connect(function()
	task.wait(1)

	local Message = ""

	pcall(function()
		Message = GuiService:GetErrorMessage()
	end)

	HandleDisconnect(Message)
end)

if CONFIG.AutoRejoin == true then
	QueueScript()
end

task.spawn(function()
	repeat task.wait(0.5) until shared.AlSploitUnInjected == true

	for _, v in pairs(Connections) do
		v:Disconnect()
	end
end)

local function IsAlive(Player)
	if not Player.Character then return false end
	if not Player.Character:FindFirstChildOfClass("Humanoid") then return false end
	if Player.Character.Humanoid.Health <= 0 then return false end
	if not Player.Character.PrimaryPart then return false end

	return true
end

-- DETECTION DU MURDER
local function GetMurdererName()
	local Roles

	local Ok = pcall(function()
		Roles = ReplicatedStorage:FindFirstChild("GetPlayerData", true):InvokeServer()
	end)

	if not Ok or type(Roles) ~= "table" then
		return nil
	end

	for Name, Data in pairs(Roles) do
		if type(Data) == "table" and Data.Role == "Murderer" then
			return Name
		end
	end

	return nil
end

task.spawn(function()
	while shared.AlSploitUnInjected == false do
		local Name = GetMurdererName()

		if Name then
			MurdererPlayer = PlayerService:FindFirstChild(Name)
		else
			MurdererPlayer = nil
		end

		task.wait(CONFIG.MurdererPollRate)
	end
end)

-- Le bonbon existe encore et peut être ramassé
local function IsCoinValid(Coin)
	return Coin ~= nil
		and Coin.Parent ~= nil
		and Coin:IsDescendantOf(WorkSpace)
		and Coin:FindFirstChild("TouchInterest") ~= nil
end

-- Un autre joueur (autre farmer) est près du bonbon
local function IsOtherPlayerNear(Coin)
	for _, Player in ipairs(PlayerService:GetPlayers()) do
		if Player ~= LocalPlayer and IsAlive(Player) == true then
			local Distance = (Player.Character.PrimaryPart.Position - Coin.Position).Magnitude

			if Distance <= CONFIG.PlayerAvoidRadius then
				return true
			end
		end
	end

	return false
end

local function IsCoinSafe(Coin)
	if IsCoinValid(Coin) == false then
		return false
	end

	if IsOtherPlayerNear(Coin) == true then
		return false
	end

	if not MurdererPlayer or MurdererPlayer == LocalPlayer then
		return true
	end

	if not IsAlive(MurdererPlayer) then
		return true
	end

	local Distance = (MurdererPlayer.Character.PrimaryPart.Position - Coin.Position).Magnitude

	return Distance > CONFIG.MurdererAvoidRadius
end

local function FindNearestCoin(MaxDistance)
	local NearestCoinDistance = MaxDistance or math.huge
	local NearestCoin = nil

	for i, v in next, WorkSpace:GetDescendants() do
		if v.Name == "Coin_Server" and v:FindFirstChild("TouchInterest") then
			local LastVisit = Visited[v]

			if not LastVisit or (tick() - LastVisit) > CONFIG.SkipTime then
				if IsCoinSafe(v) == true then
					local Distance = (LocalPlayer.Character.PrimaryPart.Position - v.Position).Magnitude

					if Distance <= NearestCoinDistance then
						NearestCoinDistance = Distance
						NearestCoin = v
					end
				end
			end
		end
	end

	return NearestCoin, NearestCoinDistance
end

local function GetCoinsLabel()
	local Node = LocalPlayer:FindFirstChild("PlayerGui")

	for _, Name in ipairs({"MainGUI", "Game", "CoinBags", "Container", "Candy", "CurrencyFrame", "Icon", "Coins"}) do
		Node = Node and Node:FindFirstChild(Name)
	end

	return Node
end

local function GetBagCount()
	local Label = GetCoinsLabel()

	if Label then
		return tonumber(string.match(Label.Text, "%d+"))
	end

	return nil
end

-- Retourne true si arrivé, false si interrompu :
-- bonbon disparu, joueur/murder proche, timeout, mort, reset
local function MoveTo(Target, Coin)
	local Character = LocalPlayer.Character
	local Root = Character and Character.PrimaryPart

	if not Root then return false end

	local StartTime = tick()
	local MaxTime = ((Target - Root.Position).Magnitude / CONFIG.Speed) + CONFIG.TimeoutMargin

	local LastCheckTime = tick()
	local LastCheckPosition = Root.Position

	while shared.AlSploitUnInjected == false and Resetting == false and IsAlive(LocalPlayer) == true do
		local Delta = RunService.Heartbeat:Wait()

		if (tick() - StartTime) > MaxTime then
			return false
		end

		if Coin and IsCoinSafe(Coin) == false then
			return false
		end

		Character = LocalPlayer.Character
		Root = Character and Character.PrimaryPart

		if not Root then return false end

		local Offset = Target - Root.Position
		local Distance = Offset.Magnitude

		if Distance < 0.5 then
			Root.CFrame = CFrame.new(Target)
			return true
		end

		local Step = math.min(CONFIG.Speed * Delta, Distance)

		-- DETECTION DE BLOCAGE
		if (tick() - LastCheckTime) >= CONFIG.StuckCheckTime then
			local Progress = (Root.Position - LastCheckPosition).Magnitude
			local Expected = CONFIG.Speed * (tick() - LastCheckTime)

			if Progress < (Expected * CONFIG.StuckMinProgress) then
				Step = math.min(CONFIG.UnstuckJump, Distance)
			end

			LastCheckTime = tick()
			LastCheckPosition = Root.Position
		end

		Root.CFrame = CFrame.new(Root.Position + Offset.Unit * Step)
		Root.AssemblyLinearVelocity = Vector3.zero
		Root.AssemblyAngularVelocity = Vector3.zero
	end

	return false
end

local function TouchCoin(Coin)
	local Root = LocalPlayer.Character and LocalPlayer.Character.PrimaryPart

	if Root and firetouchinterest and IsCoinValid(Coin) == true then
		pcall(function()
			firetouchinterest(Root, Coin, 0)
			task.wait()
			firetouchinterest(Root, Coin, 1)
		end)
	end
end

-- NETTOYAGE DES BONBONS DISPARUS
task.spawn(function()
	while shared.AlSploitUnInjected == false do
		task.wait(5)

		for Coin in pairs(Visited) do
			if not Coin.Parent then
				Visited[Coin] = nil
			end
		end
	end
end)

-- RESET QUAND LE SAC EST PLEIN
task.spawn(function()
	while shared.AlSploitUnInjected == false do
		task.wait(0.2)

		local Count = GetBagCount()

		if Count and Count >= CONFIG.BagMax and IsAlive(LocalPlayer) == true then
			Resetting = true

			local Respawned = false
			local Connection = LocalPlayer.CharacterAdded:Connect(function()
				Respawned = true
			end)

			pcall(function()
				LocalPlayer.Character.Humanoid.Health = 0
			end)

			repeat task.wait(0.2) until Respawned == true or shared.AlSploitUnInjected == true

			Connection:Disconnect()

			repeat
				task.wait(0.2)
				Count = GetBagCount()
			until shared.AlSploitUnInjected == true or (Count and Count < CONFIG.BagMax)

			Resetting = false
		end
	end
end)

-- AUTOFARM
task.spawn(function()
	repeat
		task.wait()

		if Resetting == false and IsAlive(LocalPlayer) == true then
			local NearestCoin = FindNearestCoin(CONFIG.Distance)

			if NearestCoin then
				pcall(function()
					LocalPlayer.Character.Humanoid.PlatformStand = false

					if MoveTo(NearestCoin.Position, NearestCoin) == false then return end

					TouchCoin(NearestCoin)
					task.wait(CONFIG.CollectWait)

					Visited[NearestCoin] = tick()
				end)
			end
		end
	until shared.AlSploitUnInjected == true
end)

print(string.format("[AutoFarm] Speed=%d | PlayerAvoid=%d | MurdererAvoid=%d | AutoRejoin=%s | Queue=%s | Url=%s",
	CONFIG.Speed, CONFIG.PlayerAvoidRadius, CONFIG.MurdererAvoidRadius, tostring(CONFIG.AutoRejoin), tostring(Queued), CONFIG.ScriptUrl))
