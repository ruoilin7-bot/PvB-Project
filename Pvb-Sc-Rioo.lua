--[[ 
🌱 Auto-Buy Plants Script (Fix)
--]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Remotes
local UpdStock = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UpdStock")
local BuyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BuyStock") -- pastikan nama sesuai

-- List semua plant di game
local PLANTS = {
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

-- State AutoBuy
local AutoBuy = {}
for _, plant in ipairs(PLANTS) do
    AutoBuy[plant] = false
end

-- UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoBuyUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame", screenGui)
mainFrame.Size = UDim2.new(0, 220, 0, 300)
mainFrame.Position = UDim2.new(0.05, 0, 0.2, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true

local title = Instance.new("TextLabel", mainFrame)
title.Text = "🌱 Auto-Buy Plants"
title.Size = UDim2.new(1, -30, 0, 30)
title.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.Font = Enum.Font.SourceSansBold

local toggleBtn = Instance.new("TextButton", mainFrame)
toggleBtn.Text = "-"
toggleBtn.Size = UDim2.new(0, 30, 0, 30)
toggleBtn.Position = UDim2.new(1, -30, 0, 0)
toggleBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.SourceSansBold
toggleBtn.TextScaled = true

local scroll = Instance.new("ScrollingFrame", mainFrame)
scroll.Size = UDim2.new(1, -10, 1, -40)
scroll.Position = UDim2.new(0, 5, 0, 35)
scroll.CanvasSize = UDim2.new(0, 0, 0, #PLANTS * 30)
scroll.ScrollBarThickness = 6
scroll.BackgroundTransparency = 1

-- Generate daftar plant
for i, plant in ipairs(PLANTS) do
    local btn = Instance.new("TextButton", scroll)
    btn.Size = UDim2.new(1, -10, 0, 25)
    btn.Position = UDim2.new(0, 5, 0, (i-1)*30)
    btn.Text = "[ ] " .. plant
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    btn.Font = Enum.Font.SourceSans
    btn.TextSize = 18

    btn.MouseButton1Click:Connect(function()
        AutoBuy[plant] = not AutoBuy[plant]
        btn.Text = (AutoBuy[plant] and "[✔] " or "[ ] ") .. plant
    end)
end

-- Collapse / Expand
local collapsed = false
toggleBtn.MouseButton1Click:Connect(function()
    collapsed = not collapsed
    if collapsed then
        scroll.Visible = false
        mainFrame.Size = UDim2.new(0, 220, 0, 30)
        toggleBtn.Text = "+"
    else
        scroll.Visible = true
        mainFrame.Size = UDim2.new(0, 220, 0, 300)
        toggleBtn.Text = "-"
    end
end)

-- Dragging
local dragging, dragInput, dragStart, startPos
title.InputBegan:Connect(function(input)
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
UIS.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        dragInput = input
    end
end)
UIS.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

-- Listener stok (cuma 1 argumen: itemName)
UpdStock.OnClientEvent:Connect(function(itemName)
    if AutoBuy[itemName] then
        BuyRemote:FireServer(itemName, 1)
    end
end)