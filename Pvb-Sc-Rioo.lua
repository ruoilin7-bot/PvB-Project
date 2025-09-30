-- AutoBuy (robust) for Plant vs Brainrot
-- Prevent duplicates
if _G.AutoBuyPvB_Loaded then
    warn("[AutoBuyPvB] already loaded, aborting duplicate load.")
    return
end
_G.AutoBuyPvB_Loaded = true

local ok, mainErr = pcall(function()
    -- Services
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local UserInputService = game:GetService("UserInputService")
    local StarterGui = game:GetService("StarterGui")

    -- Wait for local player (some executors need a tick)
    local player = Players.LocalPlayer
    local try = 0
    while not player and try < 20 do
        try = try + 1
        wait(0.2)
        player = Players.LocalPlayer
    end
    if not player then
        -- fallback: wait indefinitely but print
        warn("[AutoBuyPvB] LocalPlayer not found immediately; waiting for Player to load...")
        player = Players.PlayerAdded:Wait()
    end

    -- Parent GUI to PlayerGui (safer than CoreGui for most executors)
    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then
        playerGui = player:FindFirstChild("PlayerGui") or Instance.new("Folder", player) -- fallback
        warn("[AutoBuyPvB] PlayerGui not found quickly; proceeding but UI might fail.")
    end

    -- Defaults: you can extend this list if you know names
    local DEFAULT_PLANTS = {
        "Cactus",
        "Strawberry",
        "Pumpkin",
        "Sunflower",
        "Dragon Fruit",
        "Eggplant",
        "Watermelon",
        "Grape",
        "Cocotank Seed"
    }

    -- State
    local Rows = {}            -- name -> { Frame, UpdateStock, SetToggle }
    local AutoBuy = {}         -- name -> bool
    local KnownStocks = {}     -- name -> number (last known)
    local LastBuyT = {}        -- name -> last timestamp
    local BUY_COOLDOWN = 1.0

    -- Helper: find remotes dynamically
    local function findRemotesFolder()
        if ReplicatedStorage:FindFirstChild("Remotes") then
            return ReplicatedStorage:FindFirstChild("Remotes")
        end
        -- some games put remotes directly or under other folder names
        for _, child in ipairs(ReplicatedStorage:GetChildren()) do
            if child.ClassName == "Folder" and (#child:GetChildren() > 0) then
                -- heuristic: name contains "Remote" or "Remotes" or "Events"
                local n = string.lower(child.Name)
                if n:match("remote") or n:match("remotes") or n:match("event") then
                    return child
                end
            end
        end
        -- fallback: use ReplicatedStorage itself
        return ReplicatedStorage
    end

    local remotesRoot = findRemotesFolder()
    print("[AutoBuyPvB] Using remotes root:", remotesRoot:GetFullName())

    -- candidate names
    local candidateUpdNames = {"UpdStock","UpdateStock","StockUpdate","StockChanged","UpdStocks","UpdateStocks","StockEvent"}
    local candidateBuyNames = {"BuyStock","BuyItem","Purchase","PurchaseItem","Buy","BuyPlant","BuySeed","PurchaseRemote","BuyRemote"}

    local function findRemoteEventByNames(names)
        for _, inst in ipairs(remotesRoot:GetDescendants()) do
            if inst.ClassName == "RemoteEvent" then
                for _, n in ipairs(names) do
                    if string.lower(inst.Name) == string.lower(n) or string.find(string.lower(inst.Name), string.lower(n)) then
                        return inst
                    end
                end
            end
        end
        return nil
    end
    local function findRemoteByNames(names)
        for _, inst in ipairs(remotesRoot:GetDescendants()) do
            if inst.ClassName == "RemoteFunction" or inst.ClassName == "RemoteEvent" then
                for _, n in ipairs(names) do
                    if string.lower(inst.Name) == string.lower(n) or string.find(string.lower(inst.Name), string.lower(n)) then
                        return inst
                    end
                end
            end
        end
        return nil
    end

    local UpdStockRemote = findRemoteEventByNames(candidateUpdNames)
    local BuyRemote = findRemoteByNames(candidateBuyNames)

    if UpdStockRemote then
        print("[AutoBuyPvB] Found UpdStock remote:", UpdStockRemote:GetFullName())
    else
        warn("[AutoBuyPvB] Could not find a dedicated UpdStock RemoteEvent. Will connect to all RemoteEvents under remotes root for debugging.")
    end

    if BuyRemote then
        print("[AutoBuyPvB] Found Buy remote (will try to use):", BuyRemote:GetFullName(), "Class:", BuyRemote.ClassName)
    else
        warn("[AutoBuyPvB] Buy remote not found. Auto-buy attempts will still be attempted but may fail. If you know the buy remote name, tell me and I will hardcode it.")
    end

    -- UI helpers
    local function make(instName, props)
        local i = Instance.new(instName)
        if props then
            for k, v in pairs(props) do
                pcall(function() i[k] = v end)
            end
        end
        return i
    end

    -- Build UI
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoBuyPvB_UI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    local mainFrame = make("Frame", {
        Name = "Main",
        Size = UDim2.new(0, 300, 0, 380),
        Position = UDim2.new(0.65, 0, 0.15, 0),
        BackgroundColor3 = Color3.fromRGB(30,30,30),
        BorderSizePixel = 0,
        Parent = screenGui,
    })
    mainFrame.Active = true

    make("UICorner", {Parent = mainFrame, CornerRadius = UDim.new(0,8)})

    local title = make("TextLabel", {
        Parent = mainFrame,
        Size = UDim2.new(1, -100, 0, 36),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = "🌱 AutoBuy Manager",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Color3.fromRGB(230,230,230),
        Font = Enum.Font.SourceSansBold,
        TextSize = 18,
    })

    local btnMin = make("TextButton", {
        Parent = mainFrame, Size = UDim2.new(0,28,0,28), Position = UDim2.new(1,-88,0,4),
        Text = "▢", Font = Enum.Font.SourceSans, TextSize = 18,
        BackgroundColor3 = Color3.fromRGB(45,45,45), TextColor3 = Color3.fromRGB(230,230,230),
    })
    local btnHide = make("TextButton", {
        Parent = mainFrame, Size = UDim2.new(0,28,0,28), Position = UDim2.new(1,-50,0,4),
        Text = "✕", Font = Enum.Font.SourceSans, TextSize = 18,
        BackgroundColor3 = Color3.fromRGB(220,60,60), TextColor3 = Color3.fromRGB(255,255,255),
    })
    local btnToggle = make("TextButton", {
        Parent = mainFrame, Size = UDim2.new(0,28,0,28), Position = UDim2.new(1,-126,0,4),
        Text = "—", Font = Enum.Font.SourceSans, TextSize = 18,
        BackgroundColor3 = Color3.fromRGB(80,80,80), TextColor3 = Color3.fromRGB(255,255,255),
    })

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
    uiList.FillDirection = Enum.FillDirection.Vertical
    uiList.SortOrder = Enum.SortOrder.LayoutOrder

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

    local mini = make("TextButton", {
        Parent = screenGui,
        Name = "MiniButton",
        Size = UDim2.new(0,36,0,36),
        Position = UDim2.new(0.95, -40, 0.05, 0),
        BackgroundColor3 = Color3.fromRGB(40,40,40),
        Text = "▶",
        Visible = false,
    })
    make("UICorner", {Parent = mini, CornerRadius = UDim.new(0,8)})

    -- Create a hint when no items
    local hint = make("TextLabel", {
        Parent = scroll, Size = UDim2.new(1,-12,0,40), Text = "Waiting for stock events... (check console F9 for remote names)",
        BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(180,180,180), Font = Enum.Font.SourceSansItalic, TextSize = 14,
    })

    -- Create a row (uses UIListLayout for positioning)
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

        AutoBuy[itemName] = AutoBuy[itemName] or false
        chk.Text = AutoBuy[itemName] and "☑" or "☐"

        chk.MouseButton1Click:Connect(function()
            AutoBuy[itemName] = not AutoBuy[itemName]
            chk.Text = AutoBuy[itemName] and "☑" or "☐"
            print("[AutoBuyPvB] Toggle", itemName, AutoBuy[itemName])
        end)
        buyNow.MouseButton1Click:Connect(function()
            local now = tick()
            if LastBuyT[itemName] and now - LastBuyT[itemName] < BUY_COOLDOWN then
                warn("[AutoBuyPvB] buy cooldown", itemName)
                return
            end
            LastBuyT[itemName] = now
            if BuyRemote then
                local suc, res = pcall(function()
                    if BuyRemote.ClassName == "RemoteEvent" and BuyRemote.FireServer then
                        BuyRemote:FireServer(itemName, 1)
                    elseif BuyRemote.ClassName == "RemoteFunction" and BuyRemote.InvokeServer then
                        BuyRemote:InvokeServer(itemName, 1)
                    else
                        -- try generic call
                        BuyRemote:FireServer(itemName, 1)
                    end
                end)
                if suc then
                    print("[AutoBuyPvB] Manual buy requested for", itemName)
                else
                    warn("[AutoBuyPvB] manual buy failed:", res)
                end
            else
                warn("[AutoBuyPvB] Buy remote not found; cannot buy", itemName)
            end
        end)

        local function updateStock(n)
            KnownStocks[itemName] = n
            stockLbl.Text = "Stock: " .. tostring(n)
        end

        return {
            Frame = row,
            UpdateStock = updateStock,
            SetToggle = function(v)
                AutoBuy[itemName] = v
                chk.Text = v and "☑" or "☐"
            end
        }
    end

    local function ensureItem(itemName, initialStock)
        if not itemName or itemName == "" then return end
        if Rows[itemName] then
            if initialStock ~= nil and Rows[itemName].UpdateStock then Rows[itemName].UpdateStock(initialStock) end
            return Rows[itemName]
        end
        -- remove hint first time
        if hint and hint.Parent then
            hint:Destroy()
        end
        local r = createItemRow(itemName)
        Rows[itemName] = r
        uiList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            scroll.CanvasSize = UDim2.new(0,0,0, uiList.AbsoluteContentSize.Y + 8)
        end)
        if initialStock ~= nil then r.UpdateStock(initialStock) end
        lblInfo.Text = ("Items: %d"):format((function() local c=0; for _ in pairs(Rows) do c=c+1 end; return c end)())
        return r
    end

    -- populate defaults
    for _, name in ipairs(DEFAULT_PLANTS) do
        ensureItem(name, 0)
    end

    -- Buttons
    btnSelectAll.MouseButton1Click:Connect(function()
        for name,_ in pairs(Rows) do
            if Rows[name].SetToggle then Rows[name].SetToggle(true) end
        end
    end)
    btnDeselectAll.MouseButton1Click:Connect(function()
        for name,_ in pairs(Rows) do
            if Rows[name].SetToggle then Rows[name].SetToggle(false) end
        end
    end)

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
    btnHide.MouseButton1Click:Connect(function()
        pcall(function() screenGui:Destroy() end)
        _G.AutoBuyPvB_Loaded = false
    end)
    btnToggle.MouseButton1Click:Connect(function()
        if content.Visible then
            content.Visible = false
            bottom.Visible = false
            mainFrame.Size = UDim2.new(0, 300, 0, 44)
            btnToggle.Text = "+"
        else
            content.Visible = true
            bottom.Visible = true
            mainFrame.Size = UDim2.new(0, 300, 0, 380)
            btnToggle.Text = "—"
        end
    end)

    -- Dragging (on the whole frame for better reliability)
    local dragging, dragStart, startPos
    mainFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement and dragging and dragStart and startPos then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    -- Safe buy helper
    local function safeBuy(itemName, amount)
        amount = amount or 1
        if not BuyRemote then
            warn("[AutoBuyPvB] BuyRemote missing. Can't buy", itemName)
            return false, "BuyRemoteMissing"
        end
        local suc, res = pcall(function()
            if BuyRemote.ClassName == "RemoteEvent" then
                BuyRemote:FireServer(itemName, amount)
            elseif BuyRemote.ClassName == "RemoteFunction" then
                return BuyRemote:InvokeServer(itemName, amount)
            else
                -- try FireServer fallback
                if BuyRemote.FireServer then
                    BuyRemote:FireServer(itemName, amount)
                else
                    error("unknown buy remote type")
                end
            end
        end)
        return suc, res
    end

    -- Parse typical args (supports: (name), (name, stock), ({Name=...,Stock=...}), other combos)
    local function parseArgsIntoItemStock(args)
        local item, stock
        if #args == 1 then
            local a = args[1]
            local t = typeof(a)
            if t == "string" then
                item = a
            elseif t == "table" then
                item = a.Name or a.name or a.item
                stock = a.Stock or a.stock or a.amount or a.count
            end
        elseif #args >= 2 then
            if typeof(args[1]) == "string" then item = args[1] end
            if typeof(args[2]) == "number" then stock = args[2] end
        end
        return item, stock
    end

    -- Handler when an event says stock updated
    local function handleStockEvent(itemName, stock)
        if not itemName then return end
        -- fix common formatting differences
        itemName = tostring(itemName)
        ensureItem(itemName, stock or 0)
        if stock ~= nil then
            KnownStocks[itemName] = stock
            if Rows[itemName] and Rows[itemName].UpdateStock then Rows[itemName].UpdateStock(stock) end
        end

        if AutoBuy[itemName] and (stock == nil or (type(stock) == "number" and stock > 0)) then
            local now = tick()
            if not LastBuyT[itemName] or now - LastBuyT[itemName] >= BUY_COOLDOWN then
                LastBuyT[itemName] = now
                print("[AutoBuyPvB] Auto-buy attempt for", itemName, "stock:", stock)
                local suc, res = safeBuy(itemName, 1)
                if not suc then
                    warn("[AutoBuyPvB] buy failed for", itemName, res)
                end
            end
        end
    end

    -- Connect to UpdStock if found, else connect to all RemoteEvents (for debugging)
    if UpdStockRemote then
        UpdStockRemote.OnClientEvent:Connect(function(...)
            local item, stock = parseArgsIntoItemStock({...})
            print("[AutoBuyPvB] UpdStock fired ->", item, stock)
            handleStockEvent(item, stock)
        end)
    else
        -- connect to every RemoteEvent under remotesRoot to help find which one is used
        for _, inst in ipairs(remotesRoot:GetDescendants()) do
            if inst.ClassName == "RemoteEvent" then
                pcall(function()
                    inst.OnClientEvent:Connect(function(...)
                        local args = {...}
                        print(("[AutoBuyPvB] RemoteEvent '%s' fired ->"):format(inst:GetFullName()), unpack(args))
                        local item, stock = parseArgsIntoItemStock(args)
                        if item then
                            -- if we found an item pattern, treat this as stock update
                            handleStockEvent(item, stock)
                        end
                    end)
                end)
            end
        end
        warn("[AutoBuyPvB] No dedicated UpdStock found. Watching all RemoteEvents (see console).")
    end

    print("[AutoBuyPvB] UI created. Check F9 console for remote detection logs.")
end)

if not ok then
    warn("[AutoBuyPvB] failed to start:", mainErr)
end