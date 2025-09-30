-- AutoBuy UI + Logic for Delta executor
-- Usage: paste & execute in Delta. Edit BuyRemote path if needed.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Remotes (ubah path ini jika berbeda di game)
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local UpdStock = RemotesFolder:WaitForChild("UpdStock") -- RemoteEvent
local BuyRemote = RemotesFolder:FindFirstChild("BuyItem") or RemotesFolder:FindFirstChild("Purchase") -- coba beberapa nama umum

-- jika tidak ada BuyRemote, masih tetap lanjut tapi beri peringatan
if not BuyRemote then
    warn("[AutoBuy] Buy remote tidak ditemukan. Edit variable BuyRemote sesuai struktur game.")
end

-- Data structures
local AutoBuy = {}           -- map itemName -> boolean (apakah auto-buy aktif)
local KnownStocks = {}       -- map itemName -> last known stock number
local LastBuyT = {}          -- map itemName -> last buy timestamp untuk cooldown
local BUY_COOLDOWN = 1.0     -- detik antara dua percobaan buy untuk item yang sama

-- Helper: safe fire/invoke
local function safeBuy(itemName, amount)
    amount = amount or 1
    if not BuyRemote then return false, "BuyRemote missing" end

    -- Try :FireServer first, then :InvokeServer
    local ok, res = pcall(function()
        if BuyRemote.FireServer then
            return BuyRemote:FireServer(itemName, amount)
        elseif BuyRemote.InvokeServer then -- remotefunction
            return BuyRemote:InvokeServer(itemName, amount)
        else
            -- fallback: call like a function
            return BuyRemote(itemName, amount)
        end
    end)
    return ok, res
end

-- Create ScreenGui
local screengui = Instance.new("ScreenGui")
screengui.Name = "AutoBuyUI"
screengui.ResetOnSpawn = false
screengui.Parent = game:GetService("CoreGui") or LocalPlayer:WaitForChild("PlayerGui")

-- Styling helpers
local function make(obj, props)
    local o = Instance.new(obj)
    for k,v in pairs(props or {}) do o[k] = v end
    return o
end

-- Main frame
local mainFrame = make("Frame", {
    Name = "MainFrame",
    Size = UDim2.new(0, 320, 0, 420),
    Position = UDim2.new(0.7, 0, 0.2, 0),
    AnchorPoint = Vector2.new(0,0),
    BackgroundColor3 = Color3.fromRGB(30, 30, 30),
    BorderSizePixel = 0,
    Parent = screengui,
})

local uicorner = make("UICorner", {CornerRadius = UDim.new(0,8), Parent = mainFrame})

-- Titlebar
local title = make("Frame", {
    Parent = mainFrame,
    Size = UDim2.new(1,0,0,36),
    BackgroundTransparency = 1,
})
local titleLabel = make("TextLabel", {
    Parent = title,
    Size = UDim2.new(1, -90, 1, 0),
    Position = UDim2.new(0,12,0,0),
    BackgroundTransparency = 1,
    Text = "AutoBuy Manager",
    TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = Color3.fromRGB(230,230,230),
    Font = Enum.Font.SourceSansBold,
    TextSize = 16,
})
local btnMin = make("TextButton", {
    Parent = title, Size = UDim2.new(0,28,0,28), Position = UDim2.new(1,-84,0,4),
    Text = "▢", Font = Enum.Font.SourceSans, TextSize = 18,
    BackgroundColor3 = Color3.fromRGB(45,45,45), TextColor3 = Color3.fromRGB(230,230,230),
})
local btnHide = make("TextButton", {
    Parent = title, Size = UDim2.new(0,28,0,28), Position = UDim2.new(1,-46,0,4),
    Text = "✕", Font = Enum.Font.SourceSans, TextSize = 18,
    BackgroundColor3 = Color3.fromRGB(220,60,60), TextColor3 = Color3.fromRGB(255,255,255),
})
local btnToggle = make("TextButton", {
    Parent = title, Size = UDim2.new(0,28,0,28), Position = UDim2.new(1,-116,0,4),
    Text = "—", Font = Enum.Font.SourceSans, TextSize = 18,
    BackgroundColor3 = Color3.fromRGB(80,80,80), TextColor3 = Color3.fromRGB(255,255,255),
})

-- Content area (scroll)
local content = make("Frame", {
    Parent = mainFrame, Position = UDim2.new(0,8,0,44), Size = UDim2.new(1,-16,1,-92),
    BackgroundTransparency = 1,
})
local scroll = make("ScrollingFrame", {
    Parent = content,
    Size = UDim2.new(1,0,1,0),
    CanvasSize = UDim2.new(0,0,0,0),
    ScrollBarThickness = 6,
    BackgroundTransparency = 1,
})
local uiList = make("UIListLayout", {Parent = scroll, Padding = UDim.new(0,6)})
uiList.SortOrder = Enum.SortOrder.LayoutOrder

-- Controls bottom
local bottom = make("Frame", {
    Parent = mainFrame, Size = UDim2.new(1, -16, 0, 36), Position = UDim2.new(0,8,1,-44),
    BackgroundTransparency = 1,
})
local btnSelectAll = make("TextButton", {
    Parent = bottom, Size = UDim2.new(0,100,1,0), Position = UDim2.new(0,0,0,0),
    Text = "Select All", Font = Enum.Font.SourceSans, TextSize = 14,
    BackgroundColor3 = Color3.fromRGB(70,130,70), TextColor3 = Color3.fromRGB(255,255,255),
})
local btnDeselectAll = make("TextButton", {
    Parent = bottom, Size = UDim2.new(0,110,1,0), Position = UDim2.new(0,110,0,0),
    Text = "Deselect All", Font = Enum.Font.SourceSans, TextSize = 14,
    BackgroundColor3 = Color3.fromRGB(150,70,70), TextColor3 = Color3.fromRGB(255,255,255),
})
local lblInfo = make("TextLabel", {
    Parent = bottom, Size = UDim2.new(1, -230, 1, 0), Position = UDim2.new(0,220,0,0),
    Text = "Items: 0", BackgroundTransparency = 1,
    TextColor3 = Color3.fromRGB(200,200,200), Font = Enum.Font.SourceSans, TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
})

-- Minimized small button
local mini = make("TextButton", {
    Parent = screengui,
    Name = "MiniButton",
    Size = UDim2.new(0,36,0,36),
    Position = UDim2.new(0.95, -40, 0.05, 0),
    BackgroundColor3 = Color3.fromRGB(40,40,40),
    Text = "▶",
    Visible = false,
})
make("UICorner", {Parent = mini, CornerRadius = UDim.new(0,8)})

-- Resize grip (simple)
local grip = make("Frame", {
    Parent = mainFrame,
    Size = UDim2.new(0,16,0,16),
    Position = UDim2.new(1,-16,1,-16),
    BackgroundTransparency = 1,
})
local gripImg = make("ImageLabel", {
    Parent = grip, Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, Image = "rbxassetid://3926305904", ImageColor3 = Color3.fromRGB(120,120,120), ScaleType = Enum.ScaleType.Slice
})
gripImg.ImageTransparency = 0.6

-- Function to create an item row
local function createItemRow(itemName)
    local row = make("Frame", {
        Parent = scroll,
        Size = UDim2.new(1, -12, 0, 40),
        BackgroundColor3 = Color3.fromRGB(40,40,40),
    })
    make("UICorner", {Parent = row, CornerRadius = UDim.new(0,6)})
    local chk = make("TextButton", {
        Parent = row, Size = UDim2.new(0,36,1,0), Position = UDim2.new(0,6,0,0),
        Text = "☐", Font = Enum.Font.SourceSans, TextSize = 18, BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(230,230,230)
    })
    local nameLbl = make("TextLabel", {
        Parent = row, Size = UDim2.new(0.65,0,1,0), Position = UDim2.new(0,48,0,0),
        Text = itemName, TextColor3 = Color3.fromRGB(230,230,230), BackgroundTransparency = 1,
        Font = Enum.Font.SourceSansBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left
    })
    local stockLbl = make("TextLabel", {
        Parent = row, Size = UDim2.new(0,70,1,0), Position = UDim2.new(1,-86,0,0),
        Text = "Stock: ?", TextColor3 = Color3.fromRGB(200,200,200), BackgroundTransparency = 1,
        Font = Enum.Font.SourceSans, TextSize = 14
    })
    local buyNow = make("TextButton", {
        Parent = row, Size = UDim2.new(0,70,0,28), Position = UDim2.new(1,-86,0.5,-14),
        Text = "Buy", Font = Enum.Font.SourceSans, TextSize = 14, BackgroundColor3 = Color3.fromRGB(60,150,60), TextColor3 = Color3.fromRGB(255,255,255)
    })

    -- state
    AutoBuy[itemName] = AutoBuy[itemName] or false
    chk.Text = AutoBuy[itemName] and "☑" or "☐"

    -- bindings
    chk.MouseButton1Click:Connect(function()
        AutoBuy[itemName] = not AutoBuy[itemName]
        chk.Text = AutoBuy[itemName] and "☑" or "☐"
    end)
    buyNow.MouseButton1Click:Connect(function()
        local now = tick()
        if LastBuyT[itemName] and now - LastBuyT[itemName] < BUY_COOLDOWN then return end
        LastBuyT[itemName] = now
        safeBuy(itemName, 1)
    end)

    -- function to update stock text
    local function updateStock(n)
        KnownStocks[itemName] = n
        stockLbl.Text = "Stock: " .. tostring(n)
    end

    return {
        Frame = row,
        UpdateStock = updateStock,
    }
end

-- map of name->row
local Rows = {}

-- Update item list count
local function updateCount()
    local c = 0
    for _ in pairs(Rows) do c = c + 1 end
    lblInfo.Text = ("Items: %d"):format(c)
    -- update canvas size
    local itemCount = c
    local itemHeight = 46
    scroll.CanvasSize = UDim2.new(0,0,0, itemCount * itemHeight)
end

-- Add or ensure row exists
local function ensureItem(itemName)
    if Rows[itemName] then return Rows[itemName] end
    local r = createItemRow(itemName)
    Rows[itemName] = r
    updateCount()
    return r
end

-- Handler for UpdStock event
-- Assume event gives either (itemName) or (itemName, stockAmount)
UpdStock.OnClientEvent:Connect(function(itemName, stockAmount)
    -- some games send complex tables; handle gracefully
    if typeof(itemName) == "table" then
        -- try to extract name & stock
        local data = itemName
        itemName = data.Name or data.name or data.item or tostring(data)
        stockAmount = stockAmount or data.Stock or data.stock or data.amount
    end
    if not itemName then return end

    local r = ensureItem(itemName)
    if typeof(stockAmount) ~= "number" then
        -- if no number provided, set as unknown (use -1)
        stockAmount = (KnownStocks[itemName] ~= nil) and KnownStocks[itemName] or -1
    end
    if r.UpdateStock then r.UpdateStock(stockAmount) end

    -- Auto-buy logic
    if AutoBuy[itemName] and (type(stockAmount) == "number" and stockAmount > 0) then
        local now = tick()
        if not LastBuyT[itemName] or now - LastBuyT[itemName] >= BUY_COOLDOWN then
            LastBuyT[itemName] = now
            coroutine.wrap(function()
                local ok, res = safeBuy(itemName, 1)
                if ok then
                    -- optionally update known stock (decrement)
                    if KnownStocks[itemName] and KnownStocks[itemName] > 0 then
                        KnownStocks[itemName] = KnownStocks[itemName] - 1
                        if Rows[itemName] and Rows[itemName].UpdateStock then
                            Rows[itemName].UpdateStock(KnownStocks[itemName])
                        end
                    end
                else
                    warn("[AutoBuy] failed to buy", itemName, res)
                end
            end)()
        end
    end
end)

-- Buttons behavior
btnSelectAll.MouseButton1Click:Connect(function()
    for name,_ in pairs(Rows) do
        AutoBuy[name] = true
        -- update checkbox text by re-setting UI (hack: find inner button)
        local f = Rows[name].Frame
        for _,v in pairs(f:GetChildren()) do
            if v:IsA("TextButton") and v.Text:match("[☐☑]") then
                v.Text = "☑"
            end
        end
    end
end)

btnDeselectAll.MouseButton1Click:Connect(function()
    for name,_ in pairs(Rows) do
        AutoBuy[name] = false
        local f = Rows[name].Frame
        for _,v in pairs(f:GetChildren()) do
            if v:IsA("TextButton") and v.Text:match("[☐☑]") then
                v.Text = "☐"
            end
        end
    end
end)

-- Minimize toggles
local minimized = false
btnMin.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        mainFrame.Visible = false
        mini.Visible = true
    else
        mainFrame.Visible = true
        mini.Visible = false
    end
end)
mini.MouseButton1Click:Connect(function()
    minimized = false
    mainFrame.Visible = true
    mini.Visible = false
end)

-- Hide/close
btnHide.MouseButton1Click:Connect(function()
    screengui:Destroy()
end)

-- Toggle (collapse title only) -- a simple hide content
local collapsed = false
btnToggle.MouseButton1Click:Connect(function()
    collapsed = not collapsed
    content.Visible = not collapsed
    bottom.Visible = not collapsed
    if collapsed then
        mainFrame.Size = UDim2.new(0,320,0,44)
    else
        mainFrame.Size = UDim2.new(0,320,0,420)
    end
end)

-- Draggable title (simple)
local userInputService = game:GetService("UserInputService")
local dragging, dragStartPos, startPos

title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStartPos = input.Position
        startPos = mainFrame.Position
    end
end)
title.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)
userInputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
        local delta = input.Position - dragStartPos
        mainFrame.Position = UDim2.new(0, startPos.X.Offset + delta.X, 0, startPos.Y.Offset + delta.Y)
    end
end)

-- Resize via grip
local resizing, resizeStartMouse, resizeStartSize
grip.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        resizing = true
        resizeStartMouse = input.Position
        resizeStartSize = Vector2.new(mainFrame.Size.X.Offset, mainFrame.Size.Y.Offset)
    end
end)
grip.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        resizing = false
    end
end)
userInputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement and resizing then
        local delta = input.Position - resizeStartMouse
        local newW = math.clamp(resizeStartSize.X + delta.X, 220, 800)
        local newH = math.clamp(resizeStartSize.Y + delta.Y, 120, 900)
        mainFrame.Size = UDim2.new(0, newW, 0, newH)
    end
end)

-- Init: show a small hint row if no items yet
local hint = make("TextLabel", {
    Parent = scroll, Size = UDim2.new(1,-12,0,40), Text = "Waiting for UpdStock events...", BackgroundTransparency = 1,
    TextColor3 = Color3.fromRGB(180,180,180), Font = Enum.Font.SourceSansItalic, TextSize = 14,
})
uiList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() end)

-- Expose helper to add item programmatically (optional)
local function addKnownItem(itemName, stock)
    local r = ensureItem(itemName)
    if r.UpdateStock then r.UpdateStock(stock or 0) end
end

-- Replace hint if first real item added
local firstItemAdded = false
local function maybeRemoveHint()
    if not firstItemAdded then
        for k,_ in pairs(Rows) do
            firstItemAdded = true
            if hint and hint.Parent then hint:Destroy() end
            break
        end
    end
end

-- Observe Rows creation to clean hint
local spawnCheck = coroutine.wrap(function()
    while screengui.Parent do
        maybeRemoveHint()
        wait(0.5)
    end
end)
spawnCheck()

-- End of script
print("[AutoBuy] UI loaded. Waiting for UpdStock events.")
