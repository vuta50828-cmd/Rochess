local Services = setmetatable({}, {
	__index = function(Self, Service)
		return cloneref(game:GetService(Service))
	end
})

local Players = Services.Players
local UserInputService = Services.UserInputService
local LocalPlayer = Players.LocalPlayer

local App = require(game.ReplicatedStorage.ChessClient.App)
local mastermindbotplayer = require(game.ReplicatedStorage.Chess.VortexBot)
local BoardHelper = require(game.ReplicatedStorage.Chess.Engine)

-- variables
local lastComputedKey = nil
local lastAutoExecutedKey = nil
local isThinking = false
local assistEnabled = true
local highPowerMode = true
local autoPlayEnabled = false
local dragging = false
local dragStart = nil
local panelStartPos = nil
local connections = {}

local AUTO_DELAY = 0.18

-- 1. Danh sách phong cách đánh (Playstyles)
local PLAYSTYLES = {
	{
		id = "all",
		name = "ALL-ROUND",
		aggressiveness = 0.85,
		contempt = 25,
		depthBonus = 0,
		preferredOpenings = { "Ruy Lopez", "Queen's Gambit", "Sicilian Najdorf" }
	},
	{
		id = "aggressive",
		name = "AGGRESSIVE",
		aggressiveness = 1.0,
		contempt = 80,
		depthBonus = 0,
		preferredOpenings = { "King's Gambit", "Sicilian Najdorf", "Italian Game" }
	},
	{
		id = "solid",
		name = "SOLID / POS",
		aggressiveness = 0.45,
		contempt = 0,
		depthBonus = 1,
		preferredOpenings = { "Queen's Gambit", "Caro-Kann", "English Opening" }
	},
	{
		id = "tactical",
		name = "TACTICAL",
		aggressiveness = 0.95,
		contempt = 50,
		depthBonus = 1,
		preferredOpenings = { "Italian Game", "King's Indian", "Sicilian Najdorf" }
	}
}
local currentStyleIndex = 1

-- 2. Danh sách các nhánh khai cuộc theo tên
local OPENING_BRANCHES = {
	{
		name = "AUTO BOOK",
		lines = {
			[""] = { "e2e4", "d2d4", "c2c4" },
			["e2e4 e7e5 g1f3 b8c6"] = { "f1b5", "f1c4" },
			["e2e4 c7c5"] = { "g1f3" },
			["e2e4 e7e6"] = { "d2d4" },
			["e2e4 c7c6"] = { "d2d4" },
			["d2d4 d7d5"] = { "c2c4" },
			["d2d4 g8f6"] = { "c2c4" }
		}
	},
	{
		name = "Ruy Lopez",
		lines = {
			[""] = { "e2e4" },
			["e2e4 e7e5"] = { "g1f3" },
			["e2e4 e7e5 g1f3 b8c6"] = { "f1b5" },
			["e2e4 e7e5 g1f3 b8c6 f1b5 a7a6"] = { "b5a4" },
			["e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5a4 g8f6"] = { "e1g1" },
			["e2e4 e7e5 g1f3 b8c6 f1b5 g8f6"] = { "e1g1" }
		}
	},
	{
		name = "Italian Game",
		lines = {
			[""] = { "e2e4" },
			["e2e4 e7e5"] = { "g1f3" },
			["e2e4 e7e5 g1f3 b8c6"] = { "f1c4" },
			["e2e4 e7e5 g1f3 b8c6 f1c4 f8c5"] = { "c2c3", "d2d3" },
			["e2e4 e7e5 g1f3 b8c6 f1c4 g8f6"] = { "d2d3", "g1g5" }
		}
	},
	{
		name = "King's Gambit",
		lines = {
			[""] = { "e2e4" },
			["e2e4 e7e5"] = { "f2f4" },
			["e2e4 e7e5 f2f4 e5f4"] = { "g1f3" },
			["e2e4 e7e5 f2f4 f8c5"] = { "g1f3" }
		}
	},
	{
		name = "Sicilian Najdorf",
		lines = {
			[""] = { "e2e4" },
			["e2e4 c7c5"] = { "g1f3" },
			["e2e4 c7c5 g1f3 d7d6"] = { "d2d4" },
			["e2e4 c7c5 g1f3 d7d6 d2d4 c5d4"] = { "f3d4" },
			["e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6"] = { "b1c3" },
			["e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 a7a6"] = { "f1g5", "f2f3", "f1c4" }
		}
	},
	{
		name = "French Defense",
		lines = {
			["e2e4"] = { "e7e6" },
			["e2e4 e7e6 d2d4"] = { "d7d5" },
			["e2e4 e7e6 d2d4 d7d5 b1c3"] = { "f8b4", "g8f6" },
			["e2e4 e7e6 d2d4 d7d5 e4e5"] = { "c7c5" }
		}
	},
	{
		name = "Caro-Kann",
		lines = {
			["e2e4"] = { "c7c6" },
			["e2e4 c7c6 d2d4"] = { "d7d5" },
			["e2e4 c7c6 d2d4 d7d5 b1c3"] = { "d5e4" },
			["e2e4 c7c6 d2d4 d7d5 e4e5"] = { "c8f5" }
		}
	},
	{
		name = "Queen's Gambit",
		lines = {
			[""] = { "d2d4" },
			["d2d4 d7d5"] = { "c2c4" },
			["d2d4 d7d5 c2c4 e7e6"] = { "b1c3", "g1f3" },
			["d2d4 d7d5 c2c4 c7c6"] = { "g1f3", "b1c3" },
			["d2d4 d7d5 c2c4 d5c4"] = { "g1f3", "e2e3" }
		}
	},
	{
		name = "King's Indian",
		lines = {
			["d2d4"] = { "g8f6" },
			["d2d4 g8f6 c2c4"] = { "g7g6" },
			["d2d4 g8f6 c2c4 g7g6 b1c3"] = { "f8g7" },
			["d2d4 g8f6 c2c4 g7g6 b1c3 f8g7 e2e4"] = { "d7d6" }
		}
	},
	{
		name = "English Opening",
		lines = {
			[""] = { "c2c4" },
			["c2c4 e7e5"] = { "b1c3" },
			["c2c4 c7c5"] = { "g1f3", "b1c3" },
			["c2c4 g8f6"] = { "b1c3", "g1f3" }
		}
	}
}
local currentOpeningIndex = 1

-- gui
local gui = Instance.new("ScreenGui")
gui.Name = "MoveAssist"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(252, 186)
panel.Position = UDim2.fromOffset(12, 68)
panel.BackgroundColor3 = Color3.fromRGB(15, 15, 17)
panel.BorderSizePixel = 1
panel.BorderColor3 = Color3.fromRGB(55, 55, 60)
panel.Active = true
panel.Parent = gui

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 22)
titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
titleBar.BorderSizePixel = 0
titleBar.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -26, 1, 0)
title.Position = UDim2.fromOffset(8, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.Code
title.TextSize = 13
title.TextColor3 = Color3.fromRGB(220, 220, 220)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "move assist v4 (9000)"
title.Parent = titleBar

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(22, 22)
close.Position = UDim2.new(1, -22, 0, 0)
close.BackgroundTransparency = 1
close.Font = Enum.Font.Code
close.TextSize = 14
close.TextColor3 = Color3.fromRGB(220, 220, 220)
close.Text = "X"
close.Parent = titleBar

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 36)
status.Position = UDim2.fromOffset(8, 26)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Code
status.TextSize = 13
status.TextColor3 = Color3.fromRGB(255, 255, 255)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextWrapped = true
status.Text = "Join a Game"
status.Parent = panel

-- Hàng nút 1: ASSIST + MODE
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.fromOffset(114, 24)
toggleBtn.Position = UDim2.fromOffset(8, 66)
toggleBtn.BackgroundColor3 = Color3.fromRGB(34, 92, 48)
toggleBtn.BorderSizePixel = 1
toggleBtn.BorderColor3 = Color3.fromRGB(70, 140, 85)
toggleBtn.Font = Enum.Font.Code
toggleBtn.TextSize = 12
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Text = "ASSIST: ON"
toggleBtn.Parent = panel

local modeBtn = Instance.new("TextButton")
modeBtn.Size = UDim2.fromOffset(114, 24)
modeBtn.Position = UDim2.fromOffset(130, 66)
modeBtn.BackgroundColor3 = Color3.fromRGB(42, 42, 52)
modeBtn.BorderSizePixel = 1
modeBtn.BorderColor3 = Color3.fromRGB(80, 80, 95)
modeBtn.Font = Enum.Font.Code
modeBtn.TextSize = 12
modeBtn.TextColor3 = Color3.fromRGB(230, 230, 230)
modeBtn.Text = "MODE: MAX"
modeBtn.Parent = panel

-- Hàng nút 2: STYLE (Chọn cách đánh)
local styleBtn = Instance.new("TextButton")
styleBtn.Size = UDim2.fromOffset(236, 24)
styleBtn.Position = UDim2.fromOffset(8, 96)
styleBtn.BackgroundColor3 = Color3.fromRGB(36, 48, 72)
styleBtn.BorderSizePixel = 1
styleBtn.BorderColor3 = Color3.fromRGB(75, 105, 155)
styleBtn.Font = Enum.Font.Code
styleBtn.TextSize = 12
styleBtn.TextColor3 = Color3.fromRGB(215, 235, 255)
styleBtn.Text = "STYLE: " .. PLAYSTYLES[currentStyleIndex].name
styleBtn.Parent = panel

-- Hàng nút 3: OPENING (Chọn nhánh tên khai cuộc)
local openingBtn = Instance.new("TextButton")
openingBtn.Size = UDim2.fromOffset(236, 24)
openingBtn.Position = UDim2.fromOffset(8, 126)
openingBtn.BackgroundColor3 = Color3.fromRGB(54, 40, 74)
openingBtn.BorderSizePixel = 1
openingBtn.BorderColor3 = Color3.fromRGB(115, 85, 160)
openingBtn.Font = Enum.Font.Code
openingBtn.TextSize = 12
openingBtn.TextColor3 = Color3.fromRGB(235, 220, 255)
openingBtn.Text = "OPENING: " .. OPENING_BRANCHES[currentOpeningIndex].name
openingBtn.Parent = panel

-- Hàng nút 4: AUTO PLAY
local autoBtn = Instance.new("TextButton")
autoBtn.Size = UDim2.fromOffset(236, 24)
autoBtn.Position = UDim2.fromOffset(8, 156)
autoBtn.BackgroundColor3 = Color3.fromRGB(72, 46, 24)
autoBtn.BorderSizePixel = 1
autoBtn.BorderColor3 = Color3.fromRGB(145, 95, 48)
autoBtn.Font = Enum.Font.Code
autoBtn.TextSize = 12
autoBtn.TextColor3 = Color3.fromRGB(255, 230, 190)
autoBtn.Text = "AUTO PLAY: OFF"
autoBtn.Parent = panel

-- helpers
local function setStatus(text, color)
	if status.Text ~= text then
		status.Text = text
	end
	if color and status.TextColor3 ~= color then
		status.TextColor3 = color
	end
end

local function clearArrow()
	pcall(function()
		if App and App.board then
			App.board:setArrow("best", nil)
		end
	end)
end

local function extractUciMove(rawMove)
	if type(rawMove) == "table" then
		rawMove = rawMove.uci or rawMove.move or rawMove[1]
	end
	if type(rawMove) ~= "string" or #rawMove < 4 then
		return nil, nil, nil, nil
	end
	local clean = rawMove:lower()
	local fromSq = clean:sub(1, 2)
	local toSq = clean:sub(3, 4)
	local promo = (#clean >= 5) and clean:sub(5, 5) or nil
	return fromSq, toSq, promo, clean
end

local function getBotConfig()
	local style = PLAYSTYLES[currentStyleIndex]
	local baseDepth = highPowerMode and 18 or 11
	local baseTime = highPowerMode and 90 or 25
	return {
		rating = 9000,
		elo = 9000,
		depth = baseDepth + (style.depthBonus or 0),
		movetime = baseTime,
		skillLevel = 20,
		aggressiveness = style.aggressiveness,
		contempt = style.contempt
	}
end

local function lookupOpeningMove(session, uciList)
	if session.startFen and session.startFen ~= "" and session.startFen ~= "startpos" then
		return nil, nil
	end
	if #uciList > 14 then
		return nil, nil
	end

	local key = table.concat(uciList, " ")
	local selectedBranch = OPENING_BRANCHES[currentOpeningIndex]

	-- Ưu tiên nhánh khai cuộc đang được chọn trong menu
	if selectedBranch and selectedBranch.lines then
		local directCandidates = selectedBranch.lines[key]
		if type(directCandidates) == "table" and #directCandidates > 0 then
			return directCandidates[math.random(1, #directCandidates)], selectedBranch.name
		end
	end

	-- Nếu chọn AUTO BOOK, tìm thêm theo phong cách đang chọn
	if selectedBranch and selectedBranch.name == "AUTO BOOK" then
		local style = PLAYSTYLES[currentStyleIndex]
		for _, prefName in ipairs(style.preferredOpenings) do
			for _, branch in ipairs(OPENING_BRANCHES) do
				if branch.name == prefName and branch.lines[key] then
					local list = branch.lines[key]
					return list[math.random(1, #list)], branch.name
				end
			end
		end
	end

	return nil, nil
end

local function buildPositionKey(session)
	local ucis = type(session.ucis) == "table" and session.ucis or {}
	local modeTag = highPowerMode and "MAX" or "FAST"
	local styleTag = PLAYSTYLES[currentStyleIndex].id
	local openTag = OPENING_BRANCHES[currentOpeningIndex].name
	return tostring(session)
		.. "|" .. tostring(session.startFen)
		.. "|" .. modeTag
		.. "|" .. styleTag
		.. "|" .. openTag
		.. "|" .. tostring(#ucis)
		.. "|" .. table.concat(ucis, ",")
end

local function tryExecuteMove(session, uciMove, fromSq, toSq, promo, fromIdx, toIdx)
	local attempts = {
		function()
			if type(session.makeMove) == "function" then
				return session:makeMove(uciMove)
			end
		end,
		function()
			if type(session.playMove) == "function" then
				return session:playMove(fromSq, toSq, promo)
			end
		end,
		function()
			if App and type(App.makeMove) == "function" then
				return App:makeMove(uciMove)
			end
		end,
		function()
			if App and type(App.playMove) == "function" then
				return App:playMove(fromIdx, toIdx, promo)
			end
		end,
		function()
			if App and App.board and type(App.board.makeMove) == "function" then
				return App.board:makeMove(fromIdx, toIdx, promo)
			end
		end
	}

	for _, fn in ipairs(attempts) do
		local ok, res = pcall(fn)
		if ok and res ~= false then
			return true
		end
	end
	return false
end

local function computeBestMove(session, posKey)
	if isThinking then
		return
	end
	isThinking = true
	setStatus("Thinking [" .. PLAYSTYLES[currentStyleIndex].name .. "]...", Color3.fromRGB(255, 220, 110))

	task.spawn(function()
		local uciList = type(session.ucis) == "table" and table.clone(session.ucis) or {}
		local bookMove, branchName = lookupOpeningMove(session, uciList)
		local rawMove = bookMove
		local sourceTag = branchName or "AI"

		if not rawMove then
			local cfg = getBotConfig()
			local ok, moveResult = pcall(function()
				return mastermindbotplayer.think(session.startFen, uciList, cfg, {})
			end)
			if ok and moveResult then
				rawMove = moveResult
			else
				local okFallback, fallbackResult = pcall(function()
					return mastermindbotplayer.think(session.startFen, uciList, { rating = 9000 }, {})
				end)
				if okFallback then
					rawMove = fallbackResult
				end
			end
		end

		isThinking = false

		if not gui.Parent or not assistEnabled then
			return
		end

		local currentSession = App and App.session
		if not currentSession or currentSession ~= session or currentSession.over or not currentSession:isMyTurn() then
			return
		end
		if buildPositionKey(currentSession) ~= posKey then
			return
		end

		local fromSq, toSq, promo, cleanMove = extractUciMove(rawMove)
		if not (fromSq and toSq) then
			setStatus("Move parse error", Color3.fromRGB(255, 110, 110))
			return
		end

		local fromIdx = BoardHelper.algToIndex64(fromSq)
		local toIdx = BoardHelper.algToIndex64(toSq)
		if not (fromIdx and toIdx) then
			setStatus("Bad square: " .. fromSq .. toSq, Color3.fromRGB(255, 110, 110))
			return
		end

		local arrowColor = branchName
			and Color3.fromRGB(120, 210, 255)
			or (highPowerMode and Color3.fromRGB(120, 230, 130) or Color3.fromRGB(255, 215, 110))

		pcall(function()
			App.board:setArrow("best", fromIdx, toIdx, arrowColor, 0.2)
		end)

		lastComputedKey = posKey
		local label = "[" .. sourceTag .. "] " .. fromSq .. " > " .. toSq .. (promo and (" =" .. promo:upper()) or "")
		setStatus(label, Color3.fromRGB(140, 255, 160))

		if autoPlayEnabled and lastAutoExecutedKey ~= posKey then
			lastAutoExecutedKey = posKey
			task.delay(AUTO_DELAY, function()
				if not gui.Parent or not assistEnabled or not autoPlayEnabled then
					return
				end
				local liveSession = App and App.session
				if not liveSession or liveSession ~= session or liveSession.over or not liveSession:isMyTurn() then
					return
				end
				if buildPositionKey(liveSession) ~= posKey then
					return
				end

				local played = tryExecuteMove(liveSession, cleanMove, fromSq, toSq, promo, fromIdx, toIdx)
				if played then
					setStatus("AUTO [" .. sourceTag .. "]: " .. fromSq .. ">" .. toSq, Color3.fromRGB(120, 255, 210))
				else
					setStatus("Auto hook N/A: " .. fromSq .. ">" .. toSq, Color3.fromRGB(255, 170, 100))
				end
			end)
		end
	end)
end

-- events
table.insert(connections, titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		dragStart = input.Position
		panelStartPos = panel.Position
	end
end))

table.insert(connections, UserInputService.InputChanged:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local d = input.Position - dragStart
		panel.Position = UDim2.new(
			panelStartPos.X.Scale,
			panelStartPos.X.Offset + d.X,
			panelStartPos.Y.Scale,
			panelStartPos.Y.Offset + d.Y
		)
	end
end))

table.insert(connections, UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = false
	end
end))

table.insert(connections, toggleBtn.MouseButton1Click:Connect(function()
	assistEnabled = not assistEnabled
	if assistEnabled then
		toggleBtn.Text = "ASSIST: ON"
		toggleBtn.BackgroundColor3 = Color3.fromRGB(34, 92, 48)
		lastComputedKey = nil
		lastAutoExecutedKey = nil
	else
		toggleBtn.Text = "ASSIST: OFF"
		toggleBtn.BackgroundColor3 = Color3.fromRGB(95, 38, 38)
		clearArrow()
		setStatus("Paused", Color3.fromRGB(200, 200, 200))
	end
end))

table.insert(connections, modeBtn.MouseButton1Click:Connect(function()
	highPowerMode = not highPowerMode
	modeBtn.Text = highPowerMode and "MODE: MAX" or "MODE: FAST"
	lastComputedKey = nil
end))

-- Chuột trái: tiến tới phong cách tiếp theo | Chuột phải: lùi lại
table.insert(connections, styleBtn.MouseButton1Click:Connect(function()
	currentStyleIndex = (currentStyleIndex % #PLAYSTYLES) + 1
	styleBtn.Text = "STYLE: " .. PLAYSTYLES[currentStyleIndex].name
	lastComputedKey = nil
end))

table.insert(connections, styleBtn.MouseButton2Click:Connect(function()
	currentStyleIndex = ((currentStyleIndex - 2) % #PLAYSTYLES) + 1
	styleBtn.Text = "STYLE: " .. PLAYSTYLES[currentStyleIndex].name
	lastComputedKey = nil
end))

-- Chuột trái: tiến tới khai cuộc tiếp theo | Chuột phải: lùi lại
table.insert(connections, openingBtn.MouseButton1Click:Connect(function()
	currentOpeningIndex = (currentOpeningIndex % #OPENING_BRANCHES) + 1
	openingBtn.Text = "OPENING: " .. OPENING_BRANCHES[currentOpeningIndex].name
	lastComputedKey = nil
end))

table.insert(connections, openingBtn.MouseButton2Click:Connect(function()
	currentOpeningIndex = ((currentOpeningIndex - 2) % #OPENING_BRANCHES) + 1
	openingBtn.Text = "OPENING: " .. OPENING_BRANCHES[currentOpeningIndex].name
	lastComputedKey = nil
end))

table.insert(connections, autoBtn.MouseButton1Click:Connect(function()
	autoPlayEnabled = not autoPlayEnabled
	if autoPlayEnabled then
		autoBtn.Text = "AUTO PLAY: ON"
		autoBtn.BackgroundColor3 = Color3.fromRGB(130, 72, 24)
		lastAutoExecutedKey = nil
	else
		autoBtn.Text = "AUTO PLAY: OFF"
		autoBtn.BackgroundColor3 = Color3.fromRGB(72, 46, 24)
	end
end))

table.insert(connections, close.MouseButton1Click:Connect(function()
	assistEnabled = false
	autoPlayEnabled = false
	for _, conn in ipairs(connections) do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(connections)
	clearArrow()
	gui:Destroy()
end))

-- main loop
task.spawn(function()
	while task.wait(0.05) do
		if not gui.Parent then
			break
		end

		if not assistEnabled then
			continue
		end

		local session = App and App.session
		if not session or session.kind ~= "online" or session.over then
			lastComputedKey = nil
			lastAutoExecutedKey = nil
			clearArrow()
			setStatus("Join a Game", Color3.fromRGB(220, 220, 220))

		elseif not session:isMyTurn() then
			lastComputedKey = nil
			clearArrow()
			setStatus("Wait for your turn", Color3.fromRGB(185, 195, 215))

		else
			local posKey = buildPositionKey(session)
			if posKey ~= lastComputedKey and not isThinking then
				computeBestMove(session, posKey)
			end
		end
	end
end)
