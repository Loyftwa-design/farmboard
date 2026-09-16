-- Farmboard v1.0.0 - by Loyftwa
local addonName = ...

local Farmboard = {}
_G.Farmboard = Farmboard

local DEFAULT_SLOT_COUNT = 6
local MIN_SLOT_COUNT = 1
local MAX_SLOT_COUNT = 24
local MAX_GOAL = 9999
local SLOT_WIDTH = 68
local SLOT_HEIGHT = 68
local ICON_SIZE = 44
local HORIZONTAL_SLOT_STEP = 76
local VERTICAL_SLOT_STEP = 76
local FRAME_PADDING = 12
local TITLE_HEIGHT = 24

Farmboard.frames = {}

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffc800Farmboard:|r " .. tostring(message))
end

local GOAL_SOUND_PATH = "Interface\\AddOns\\Farmboard\\Media\\GoalComplete.ogg"
local GOAL_COMPLETE_MESSAGE = "- Ziel Erreicht! -"

local function PlayGoalCompleteSound()
    if PlaySoundFile then
        local willPlay = PlaySoundFile(GOAL_SOUND_PATH, "Master")
        if willPlay ~= false then
            return true
        end
    end

    -- Fallback to a built-in sound if the custom file cannot be played.
    if PlaySound and SOUNDKIT then
        local soundID = SOUNDKIT.READY_CHECK or SOUNDKIT.ALARM_CLOCK_WARNING_3 or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
        if soundID then
            PlaySound(soundID, "Master")
            return true
        end
    end

    return false
end

local function ShowGoalCompleteMessage()
    if RaidNotice_AddMessage and RaidWarningFrame then
        local info = (ChatTypeInfo and ChatTypeInfo["RAID_WARNING"]) or { r = 1, g = 0.82, b = 0.12 }
        RaidNotice_AddMessage(RaidWarningFrame, GOAL_COMPLETE_MESSAGE, info)
        return
    end

    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(GOAL_COMPLETE_MESSAGE, 1, 0.82, 0.12, 1.5)
    end
end

local function NotifyGoalComplete()
    PlayGoalCompleteSound()
    ShowGoalCompleteMessage()
end

local function NewSlotData()
    return { itemID = nil, goal = 0 }
end

local function IsValidSlotCount(value)
    value = tonumber(value)
    if not value or value ~= math.floor(value) then
        return false
    end
    return value >= MIN_SLOT_COUNT and value <= MAX_SLOT_COUNT
end

local function NormalizeBoard(board, fallbackID, fallbackName)
    board.id = tonumber(board.id) or fallbackID
    board.name = (type(board.name) == "string" and board.name ~= "") and board.name or fallbackName or ("Farmboard " .. tostring(board.id))
    board.visible = board.visible ~= false
    board.locked = board.locked == true
    board.orientation = board.orientation == "VERTICAL" and "VERTICAL" or "HORIZONTAL"
    board.slotCount = IsValidSlotCount(board.slotCount) and tonumber(board.slotCount) or DEFAULT_SLOT_COUNT
    board.notifyOnComplete = board.notifyOnComplete == true

    if type(board.position) ~= "table" then
        board.position = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = (board.id - 1) * 24,
            y = -((board.id - 1) * 24),
        }
    end

    if type(board.slots) ~= "table" then
        board.slots = {}
    end

    for i = 1, MAX_SLOT_COUNT do
        if type(board.slots[i]) ~= "table" then
            board.slots[i] = NewSlotData()
        end
        board.slots[i].itemID = tonumber(board.slots[i].itemID)
        board.slots[i].goal = math.min(MAX_GOAL, math.max(0, tonumber(board.slots[i].goal) or 0))
    end
end

local function EnsureDatabase()
    if type(FarmboardDB) ~= "table" then
        FarmboardDB = {}
    end

    -- Migration from the single-board versions <= 0.1.x.
    if type(FarmboardDB.boards) ~= "table" then
        local legacyBoard = {
            id = 1,
            name = "Farmboard",
            visible = FarmboardDB.visible ~= false,
            locked = FarmboardDB.locked == true,
            orientation = FarmboardDB.orientation,
            slotCount = FarmboardDB.slotCount,
            position = FarmboardDB.position,
            slots = FarmboardDB.slots,
        }
        FarmboardDB.boards = { legacyBoard }
    end

    if #FarmboardDB.boards == 0 then
        FarmboardDB.boards[1] = { id = 1, name = "Farmboard" }
    end

    local maxID = 0
    for index, board in ipairs(FarmboardDB.boards) do
        NormalizeBoard(board, index, index == 1 and "Farmboard" or ("Farmboard " .. index))
        maxID = math.max(maxID, board.id)
    end

    -- v0.3.5 migration: older versions silently defaulted goal notifications to off.
    -- Enable them once so existing boards actually notify when a goal is crossed.
    if FarmboardDB.goalNotificationMigration ~= 1 then
        for _, board in ipairs(FarmboardDB.boards) do
            board.notifyOnComplete = true
        end
        FarmboardDB.goalNotificationMigration = 1
    end

    FarmboardDB.nextBoardID = math.max(tonumber(FarmboardDB.nextBoardID) or 1, maxID + 1)

    if type(FarmboardDB.minimap) ~= "table" then
        FarmboardDB.minimap = {}
    end
    FarmboardDB.minimap.angle = tonumber(FarmboardDB.minimap.angle) or 225
end

local function GetBoardData(boardID)
    boardID = tonumber(boardID)
    if not boardID or not FarmboardDB or type(FarmboardDB.boards) ~= "table" then
        return nil, nil
    end

    for index, board in ipairs(FarmboardDB.boards) do
        if board.id == boardID then
            return board, index
        end
    end

    return nil, nil
end

local function GetCounts(itemID)
    if not itemID then
        return 0, 0, 0, 0
    end

    local bags = C_Item.GetItemCount(itemID, false, false, false, false) or 0
    local bagsAndBank = C_Item.GetItemCount(itemID, true, false, false, false) or bags
    local allStorage = C_Item.GetItemCount(itemID, true, false, false, true) or bagsAndBank

    local characterBank = math.max(0, bagsAndBank - bags)
    local accountBank = math.max(0, allStorage - bagsAndBank)

    return allStorage, bags, characterBank, accountBank
end

local function GetItemDisplayInfo(itemID)
    if not itemID then
        return nil, nil, nil
    end

    local itemName, itemLink, _, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemID)
    if not itemTexture then
        local _, _, _, _, instantIcon = C_Item.GetItemInfoInstant(itemID)
        itemTexture = instantIcon
    end

    return itemName, itemLink, itemTexture
end

local function GetCraftingQualityInfo(itemID)
    if not itemID or not C_TradeSkillUI then
        return nil
    end

    if C_TradeSkillUI.GetItemReagentQualityInfo then
        local info = C_TradeSkillUI.GetItemReagentQualityInfo(itemID)
        if info and info.quality and info.quality > 0 then
            return info
        end
    end

    if C_TradeSkillUI.GetItemCraftedQualityInfo then
        local info = C_TradeSkillUI.GetItemCraftedQualityInfo(itemID)
        if info and info.quality and info.quality > 0 then
            return info
        end
    end

    return nil
end

local function SetBackdrop(frame, borderColor)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.025, 0.02, 0.02, 0.92)
    local color = borderColor or { 0.55, 0.48, 0.34, 1 }
    frame:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
end

local function SaveBoardPosition(boardFrame)
    local data = boardFrame.data
    local point, _, relativePoint, x, y = boardFrame:GetPoint(1)
    data.position = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = math.floor((x or 0) + 0.5),
        y = math.floor((y or 0) + 0.5),
    }
end

local function RestoreBoardPosition(boardFrame)
    local position = boardFrame.data.position or {}
    boardFrame:ClearAllPoints()
    boardFrame:SetPoint(
        position.point or "CENTER",
        UIParent,
        position.relativePoint or "CENTER",
        position.x or 0,
        position.y or 0
    )
end

local function ResetBoardPosition(boardFrame)
    local order = 1
    for index, board in ipairs(FarmboardDB.boards) do
        if board.id == boardFrame.data.id then
            order = index
            break
        end
    end

    boardFrame.data.position = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = (order - 1) * 26,
        y = -((order - 1) * 26),
    }
    RestoreBoardPosition(boardFrame)
end

local function ClearSlot(boardFrame, index)
    local data = boardFrame.data.slots[index]
    if not data then
        return
    end

    data.itemID = nil
    data.goal = 0
    Farmboard:UpdateSlot(boardFrame, index)
end

local function AssignItem(boardFrame, index, itemID)
    itemID = tonumber(itemID)
    if not itemID then
        return
    end

    local data = boardFrame.data.slots[index]
    if not data then
        return
    end

    data.itemID = itemID
    data.goal = tonumber(data.goal) or 0
    C_Item.RequestLoadItemDataByID(itemID)
    Farmboard:UpdateSlot(boardFrame, index)
    ClearCursor()
end

local function CreateSlot(boardFrame, index)
    local slot = CreateFrame("Button", nil, boardFrame, "BackdropTemplate")
    slot:SetSize(SLOT_WIDTH, SLOT_HEIGHT)
    slot.index = index
    slot.boardFrame = boardFrame
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:RegisterForDrag("LeftButton")
    SetBackdrop(slot, { 0.45, 0.45, 0.45, 1 })

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetSize(ICON_SIZE, ICON_SIZE)
    slot.icon:SetPoint("TOP", 0, -5)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot.icon:Hide()

    slot.qualityBadge = slot:CreateTexture(nil, "OVERLAY", nil, 7)
    slot.qualityBadge:SetSize(30, 30)
    slot.qualityBadge:SetPoint("TOPLEFT", slot, "TOPLEFT", -8, 8)
    slot.qualityBadge:Hide()

    slot.qualityText = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slot.qualityText:SetPoint("CENTER", slot.qualityBadge, "CENTER", 0, 0)
    slot.qualityText:SetTextColor(1, 0.82, 0.12)
    slot.qualityText:Hide()

    slot.emptyText = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    slot.emptyText:SetPoint("CENTER", 0, 1)
    slot.emptyText:SetText("+")
    slot.emptyText:SetTextColor(0.34, 0.34, 0.34)

    slot.progressBG = slot:CreateTexture(nil, "ARTWORK")
    slot.progressBG:SetPoint("BOTTOMLEFT", 4, 4)
    slot.progressBG:SetPoint("BOTTOMRIGHT", -4, 4)
    slot.progressBG:SetHeight(14)
    slot.progressBG:SetColorTexture(0, 0, 0, 0.72)
    slot.progressBG:Hide()

    slot.progress = slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    slot.progress:SetPoint("BOTTOM", 0, 6)
    slot.progress:SetWidth(SLOT_WIDTH - 4)
    slot.progress:SetJustifyH("CENTER")
    slot.progress:SetWordWrap(false)
    slot.progress:SetText("")
    slot.progress:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")

    slot.completeMark = slot:CreateTexture(nil, "OVERLAY")
    slot.completeMark:SetSize(12, 12)
    slot.completeMark:SetPoint("TOPRIGHT", -3, -3)
    slot.completeMark:SetTexture("Interface\\AddOns\\Farmboard\\Media\\CompleteTriangle.tga")
    slot.completeMark:Hide()

    slot:SetScript("OnReceiveDrag", function(self)
        local infoType, itemID = GetCursorInfo()
        if infoType == "item" and itemID then
            AssignItem(self.boardFrame, self.index, itemID)
        end
    end)

    slot:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            local infoType, itemID = GetCursorInfo()
            if infoType == "item" and itemID then
                AssignItem(self.boardFrame, self.index, itemID)
            end
            return
        end

        if button == "RightButton" then
            if IsShiftKeyDown() then
                ClearSlot(self.boardFrame, self.index)
                return
            end

            local data = self.boardFrame.data.slots[self.index]
            if data and data.itemID then
                Farmboard:OpenGoalDialog(self.boardFrame, self.index)
            end
        end
    end)

    slot:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.78, 0.15, 1)

        local data = self.boardFrame.data.slots[self.index]
        if not data or not data.itemID then
            return
        end

        local total, bags, bank, accountBank = GetCounts(data.itemID)
        local _, itemLink = GetItemDisplayInfo(data.itemID)

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if itemLink then
            GameTooltip:SetHyperlink(itemLink)
        else
            GameTooltip:SetText("Item " .. tostring(data.itemID))
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Taschen", tostring(bags), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Charakterbank", tostring(bank), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Kriegsmeutenbank", tostring(accountBank), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Gesamt", tostring(total), 1, 0.82, 0.12, 1, 0.82, 0.12)

        local qualityInfo = GetCraftingQualityInfo(data.itemID)
        if qualityInfo and qualityInfo.quality then
            GameTooltip:AddDoubleLine("Qualität", tostring(qualityInfo.quality), 0.8, 0.8, 0.8, 1, 0.82, 0.12)
        end

        local goal = tonumber(data.goal) or 0
        if goal > 0 then
            GameTooltip:AddDoubleLine("Ziel", tostring(goal), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Fehlen", tostring(math.max(0, goal - total)), 0.8, 0.8, 0.8, 1, 1, 1)
            local percent = math.min(100, (total / goal) * 100)
            GameTooltip:AddDoubleLine("Fortschritt", string.format("%.1f%%", percent), 0.8, 0.8, 0.8, 1, 1, 1)
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Rechtsklick: Ziel setzen", 0.65, 0.65, 0.65)
        GameTooltip:AddLine("Shift + Rechtsklick: Entfernen", 0.65, 0.65, 0.65)
        GameTooltip:Show()
    end)

    slot:SetScript("OnLeave", function(self)
        local data = self.boardFrame.data.slots[self.index]
        if data and data.itemID and (tonumber(data.goal) or 0) > 0 then
            local total = GetCounts(data.itemID)
            if total >= (tonumber(data.goal) or 0) then
                self:SetBackdropBorderColor(0.25, 0.85, 0.35, 1)
            else
                self:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
            end
        else
            self:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
        end
        GameTooltip:Hide()
    end)

    boardFrame.slots[index] = slot
end

function Farmboard:LayoutBoard(boardFrame)
    local data = boardFrame.data
    local slotCount = tonumber(data.slotCount) or DEFAULT_SLOT_COUNT
    local totalWidth = (slotCount - 1) * HORIZONTAL_SLOT_STEP

    boardFrame.title:SetText(data.name)

    for i, slot in ipairs(boardFrame.slots) do
        slot:ClearAllPoints()
        if i <= slotCount then
            slot:Show()
            if data.orientation == "VERTICAL" then
                slot:SetPoint("TOP", boardFrame, "TOP", 0, -(TITLE_HEIGHT + 12) - ((i - 1) * VERTICAL_SLOT_STEP))
            else
                local x = -totalWidth / 2 + ((i - 1) * HORIZONTAL_SLOT_STEP)
                slot:SetPoint("TOP", boardFrame, "TOP", x, -(TITLE_HEIGHT + 12))
            end
        else
            slot:Hide()
        end
    end

    if data.orientation == "VERTICAL" then
        boardFrame:SetSize(SLOT_WIDTH + 40, TITLE_HEIGHT + 18 + ((slotCount - 1) * VERTICAL_SLOT_STEP) + SLOT_HEIGHT + FRAME_PADDING)
    else
        boardFrame:SetSize(totalWidth + SLOT_WIDTH + 24, TITLE_HEIGHT + SLOT_HEIGHT + 30)
    end
end

function Farmboard:UpdateSlot(boardFrame, index)
    local slot = boardFrame.slots[index]
    local data = boardFrame.data.slots[index]
    if not slot or not data then
        return
    end

    if not data.itemID then
        slot.icon:SetTexture(nil)
        slot.icon:Hide()
        slot.emptyText:SetText("+")
        slot.emptyText:Show()
        slot.progress:SetText("")
        slot.progressBG:Hide()
        slot.completeMark:Hide()
        slot.qualityBadge:Hide()
        slot.qualityText:Hide()
        boardFrame.completionState[index] = nil
        boardFrame.lastCounts[index] = nil
        slot:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
        return
    end

    local _, _, texture = GetItemDisplayInfo(data.itemID)
    if texture then
        slot.icon:SetTexture(texture)
        slot.icon:Show()
        slot.emptyText:Hide()
    else
        slot.icon:Hide()
        slot.emptyText:Show()
        slot.emptyText:SetText("…")
    end

    local qualityInfo = GetCraftingQualityInfo(data.itemID)
    if qualityInfo then
        local atlas = qualityInfo.iconSmall or qualityInfo.iconInventory or qualityInfo.icon
        if atlas and atlas ~= "" then
            slot.qualityBadge:SetAtlas(atlas, false)
            slot.qualityBadge:SetSize(30, 30)
            slot.qualityBadge:Show()
            slot.qualityText:Hide()
        else
            slot.qualityBadge:Hide()
            slot.qualityText:SetText(tostring(qualityInfo.quality or ""))
            slot.qualityText:Show()
        end
    else
        slot.qualityBadge:Hide()
        slot.qualityText:Hide()
    end

    local total = GetCounts(data.itemID)
    local goal = math.min(MAX_GOAL, tonumber(data.goal) or 0)
    data.goal = goal
    slot.progressBG:Show()

    if goal > 0 then
        slot.progress:SetText(string.format("%d/%d", total, goal))
        local isComplete = total >= goal
        local previousTotal = boardFrame.lastCounts[index]

        -- Track the actual count crossing the target. This is more reliable than only
        -- comparing the visual completion flag when several WoW inventory events fire.
        if previousTotal ~= nil and previousTotal < goal and total >= goal then
            if boardFrame.data.notifyOnComplete then
                NotifyGoalComplete()
            end
        end

        boardFrame.lastCounts[index] = total
        boardFrame.completionState[index] = isComplete

        if isComplete then
            slot.progress:SetTextColor(0.25, 1, 0.35)
            slot.completeMark:Show()
            slot:SetBackdropBorderColor(0.25, 0.85, 0.35, 1)
        else
            slot.progress:SetTextColor(1, 0.82, 0.12)
            slot.completeMark:Hide()
            slot:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
        end
    else
        boardFrame.completionState[index] = nil
        boardFrame.lastCounts[index] = total
        slot.progress:SetText(tostring(total))
        slot.progress:SetTextColor(0.82, 0.82, 0.82)
        slot.completeMark:Hide()
        slot:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
    end
end

function Farmboard:UpdateBoard(boardFrame)
    for i = 1, MAX_SLOT_COUNT do
        self:UpdateSlot(boardFrame, i)
    end
end

function Farmboard:UpdateAll()
    for _, boardFrame in pairs(self.frames) do
        self:UpdateBoard(boardFrame)
    end
end

function Farmboard:CreateBoardFrame(boardData)
    if self.frames[boardData.id] then
        return self.frames[boardData.id]
    end

    local boardFrame = CreateFrame("Frame", "FarmboardBoardFrame" .. tostring(boardData.id), UIParent, "BackdropTemplate")
    boardFrame.data = boardData
    boardFrame.slots = {}
    boardFrame.completionState = {}
    boardFrame.lastCounts = {}
    boardFrame:SetFrameStrata("MEDIUM")
    boardFrame:SetClampedToScreen(true)
    boardFrame:SetMovable(true)
    boardFrame:EnableMouse(true)
    SetBackdrop(boardFrame)

    boardFrame.title = boardFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    boardFrame.title:SetPoint("TOP", 0, -8)
    boardFrame.title:SetText(boardData.name)
    boardFrame.title:SetTextColor(1, 0.82, 0.12)


    boardFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not self.data.locked then
            self:StartMoving()
        elseif button == "RightButton" then
            Farmboard:OpenContextMenu(self)
        end
    end)

    boardFrame:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self:StopMovingOrSizing()
            SaveBoardPosition(self)
        end
    end)

    for i = 1, MAX_SLOT_COUNT do
        CreateSlot(boardFrame, i)
    end

    self.frames[boardData.id] = boardFrame
    self:LayoutBoard(boardFrame)
    RestoreBoardPosition(boardFrame)
    self:UpdateBoard(boardFrame)

    if boardData.visible then
        boardFrame:Show()
    else
        boardFrame:Hide()
    end

    return boardFrame
end

function Farmboard:SetOrientation(boardFrame, orientation)
    if orientation ~= "HORIZONTAL" and orientation ~= "VERTICAL" then
        return
    end
    boardFrame.data.orientation = orientation
    self:LayoutBoard(boardFrame)
    RestoreBoardPosition(boardFrame)
end

function Farmboard:SetSlotCount(boardFrame, slotCount)
    slotCount = tonumber(slotCount)
    if not IsValidSlotCount(slotCount) then
        return
    end
    boardFrame.data.slotCount = slotCount
    self:LayoutBoard(boardFrame)
    RestoreBoardPosition(boardFrame)
    self:UpdateBoard(boardFrame)
end

-- Goal dialog ---------------------------------------------------------------
local goalDialog = CreateFrame("Frame", "FarmboardGoalDialog", UIParent, "BackdropTemplate")
goalDialog:SetSize(330, 190)
goalDialog:SetPoint("CENTER")
goalDialog:SetFrameStrata("DIALOG")
goalDialog:SetClampedToScreen(true)
SetBackdrop(goalDialog, { 0.75, 0.62, 0.25, 1 })
goalDialog:Hide()

local goalTitle = goalDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
goalTitle:SetPoint("TOP", 0, -16)
goalTitle:SetText("Farmziel setzen")
goalTitle:SetTextColor(1, 0.82, 0.12)

local goalItem = goalDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
goalItem:SetPoint("TOP", 0, -43)
goalItem:SetWidth(290)
goalItem:SetJustifyH("CENTER")

local goalCurrent = goalDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
goalCurrent:SetPoint("TOP", 0, -60)
goalCurrent:SetTextColor(0.75, 0.75, 0.75)

local goalEdit = CreateFrame("EditBox", nil, goalDialog, "InputBoxTemplate")
goalEdit:SetSize(210, 28)
goalEdit:SetPoint("TOP", 0, -82)
goalEdit:SetAutoFocus(false)
goalEdit:SetNumeric(true)
goalEdit:SetMaxLetters(4)
goalEdit:SetJustifyH("CENTER")

local goalHint = goalDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
goalHint:SetPoint("TOP", goalEdit, "BOTTOM", 0, -8)
goalHint:SetText("0 = Ziel entfernen  ·  Max. 9999")
goalHint:SetTextColor(0.55, 0.55, 0.55)

local goalOK = CreateFrame("Button", nil, goalDialog, "UIPanelButtonTemplate")
goalOK:SetSize(100, 24)
goalOK:SetPoint("BOTTOMLEFT", 52, 18)
goalOK:SetText("OK")

local goalCancel = CreateFrame("Button", nil, goalDialog, "UIPanelButtonTemplate")
goalCancel:SetSize(100, 24)
goalCancel:SetPoint("BOTTOMRIGHT", -52, 18)
goalCancel:SetText("Abbrechen")

local function ApplyGoal()
    local boardFrame = Farmboard.frames[goalDialog.boardID]
    local index = goalDialog.slotIndex
    if not boardFrame or not index or not boardFrame.data.slots[index] then
        goalDialog:Hide()
        return
    end

    local value = tonumber(goalEdit:GetText())
    if not value or value < 0 then
        Print("Bitte eine gültige Zielmenge eingeben.")
        return
    end

    value = math.floor(value)
    if value > MAX_GOAL then
        Print("Die maximale Zielmenge ist 9999.")
        goalEdit:SetText(tostring(MAX_GOAL))
        goalEdit:HighlightText()
        return
    end

    boardFrame.data.slots[index].goal = value
    boardFrame.completionState[index] = nil
    boardFrame.lastCounts[index] = nil
    Farmboard:UpdateSlot(boardFrame, index)
    goalDialog:Hide()
end

goalOK:SetScript("OnClick", ApplyGoal)
goalCancel:SetScript("OnClick", function() goalDialog:Hide() end)
goalEdit:SetScript("OnEnterPressed", ApplyGoal)
goalEdit:SetScript("OnEscapePressed", function() goalDialog:Hide() end)
goalDialog:SetScript("OnShow", function()
    goalEdit:SetFocus()
    goalEdit:HighlightText()
end)
goalDialog:SetScript("OnHide", function() goalEdit:ClearFocus() end)

function Farmboard:OpenGoalDialog(boardFrame, index)
    local data = boardFrame.data.slots[index]
    if not data or not data.itemID then
        return
    end

    goalDialog.boardID = boardFrame.data.id
    goalDialog.slotIndex = index

    local itemName = GetItemDisplayInfo(data.itemID)
    local total = GetCounts(data.itemID)
    goalItem:SetText(itemName or ("Item " .. tostring(data.itemID)))
    goalCurrent:SetText("Aktuell gesammelt: " .. tostring(total))

    local goal = tonumber(data.goal) or 0
    goalEdit:SetText(goal > 0 and tostring(goal) or "")
    goalDialog:Show()
end

-- Rename dialog -------------------------------------------------------------
local renameDialog = CreateFrame("Frame", "FarmboardRenameDialog", UIParent, "BackdropTemplate")
renameDialog:SetSize(330, 145)
renameDialog:SetPoint("CENTER")
renameDialog:SetFrameStrata("DIALOG")
renameDialog:SetClampedToScreen(true)
SetBackdrop(renameDialog, { 0.75, 0.62, 0.25, 1 })
renameDialog:Hide()

local renameTitle = renameDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
renameTitle:SetPoint("TOP", 0, -16)
renameTitle:SetText("Farmboard umbenennen")
renameTitle:SetTextColor(1, 0.82, 0.12)

local renameEdit = CreateFrame("EditBox", nil, renameDialog, "InputBoxTemplate")
renameEdit:SetSize(230, 28)
renameEdit:SetPoint("TOP", 0, -50)
renameEdit:SetAutoFocus(false)
renameEdit:SetMaxLetters(32)
renameEdit:SetJustifyH("CENTER")

local renameOK = CreateFrame("Button", nil, renameDialog, "UIPanelButtonTemplate")
renameOK:SetSize(100, 24)
renameOK:SetPoint("BOTTOMLEFT", 52, 18)
renameOK:SetText("OK")

local renameCancel = CreateFrame("Button", nil, renameDialog, "UIPanelButtonTemplate")
renameCancel:SetSize(100, 24)
renameCancel:SetPoint("BOTTOMRIGHT", -52, 18)
renameCancel:SetText("Abbrechen")

local function ApplyRename()
    local boardFrame = Farmboard.frames[renameDialog.boardID]
    if not boardFrame then
        renameDialog:Hide()
        return
    end

    local newName = strtrim(renameEdit:GetText() or "")
    if newName == "" then
        Print("Bitte einen Namen eingeben.")
        return
    end

    boardFrame.data.name = newName
    boardFrame.title:SetText(newName)
    renameDialog:Hide()
end

renameOK:SetScript("OnClick", ApplyRename)
renameCancel:SetScript("OnClick", function() renameDialog:Hide() end)
renameEdit:SetScript("OnEnterPressed", ApplyRename)
renameEdit:SetScript("OnEscapePressed", function() renameDialog:Hide() end)
renameDialog:SetScript("OnShow", function()
    renameEdit:SetFocus()
    renameEdit:HighlightText()
end)
renameDialog:SetScript("OnHide", function() renameEdit:ClearFocus() end)

function Farmboard:OpenRenameDialog(boardFrame)
    renameDialog.boardID = boardFrame.data.id
    renameEdit:SetText(boardFrame.data.name or "Farmboard")
    renameDialog:Show()
end

function Farmboard:AddBoard()
    local id = FarmboardDB.nextBoardID
    FarmboardDB.nextBoardID = id + 1

    local order = #FarmboardDB.boards + 1
    local board = {
        id = id,
        name = "Farmboard " .. tostring(order),
        visible = true,
        locked = false,
        orientation = "HORIZONTAL",
        slotCount = DEFAULT_SLOT_COUNT,
        position = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = (order - 1) * 26,
            y = -((order - 1) * 26),
        },
        slots = {},
    }
    NormalizeBoard(board, id, board.name)
    table.insert(FarmboardDB.boards, board)

    local boardFrame = self:CreateBoardFrame(board)
    self:OpenRenameDialog(boardFrame)
    Print("Neues Farmboard erstellt.")
    return boardFrame
end

function Farmboard:DuplicateBoard(sourceFrame)
    if not sourceFrame or not sourceFrame.data then
        return nil
    end

    local source = sourceFrame.data
    local id = FarmboardDB.nextBoardID
    FarmboardDB.nextBoardID = id + 1
    local order = #FarmboardDB.boards + 1

    local board = {
        id = id,
        name = (source.name or "Farmboard") .. " Kopie",
        visible = true,
        locked = false,
        orientation = source.orientation,
        slotCount = source.slotCount,
        notifyOnComplete = source.notifyOnComplete == true,
        position = {
            point = source.position and source.position.point or "CENTER",
            relativePoint = source.position and source.position.relativePoint or "CENTER",
            x = (source.position and source.position.x or 0) + 28,
            y = (source.position and source.position.y or 0) - 28,
        },
        slots = {},
    }

    for i = 1, MAX_SLOT_COUNT do
        local srcSlot = source.slots and source.slots[i] or nil
        board.slots[i] = {
            itemID = srcSlot and srcSlot.itemID or nil,
            goal = srcSlot and (tonumber(srcSlot.goal) or 0) or 0,
        }
    end

    NormalizeBoard(board, id, board.name)
    table.insert(FarmboardDB.boards, board)

    local boardFrame = self:CreateBoardFrame(board)
    Print("Farmboard dupliziert.")
    return boardFrame
end

function Farmboard:DeleteBoard(boardFrame)
    if #FarmboardDB.boards <= 1 then
        Print("Das letzte Farmboard kann nicht gelöscht werden.")
        return
    end

    local _, index = GetBoardData(boardFrame.data.id)
    if not index then
        return
    end

    table.remove(FarmboardDB.boards, index)
    boardFrame:Hide()
    self.frames[boardFrame.data.id] = nil
    Print("Farmboard gelöscht.")
end

StaticPopupDialogs["FARMBOARD_DELETE_BOARD"] = {
    text = "Farmboard '%s' wirklich löschen?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        local boardFrame = data and Farmboard.frames[data.boardID]
        if boardFrame then
            Farmboard:DeleteBoard(boardFrame)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Slot count dialog ---------------------------------------------------------
local slotCountDialog = CreateFrame("Frame", "FarmboardSlotCountDialog", UIParent, "BackdropTemplate")
slotCountDialog:SetSize(330, 160)
slotCountDialog:SetPoint("CENTER")
slotCountDialog:SetFrameStrata("DIALOG")
slotCountDialog:SetClampedToScreen(true)
SetBackdrop(slotCountDialog, { 0.75, 0.62, 0.25, 1 })
slotCountDialog:Hide()

local slotCountTitle = slotCountDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
slotCountTitle:SetPoint("TOP", 0, -16)
slotCountTitle:SetText("Anzahl der Felder")
slotCountTitle:SetTextColor(1, 0.82, 0.12)

local slotCountEdit = CreateFrame("EditBox", nil, slotCountDialog, "InputBoxTemplate")
slotCountEdit:SetSize(170, 28)
slotCountEdit:SetPoint("TOP", 0, -50)
slotCountEdit:SetAutoFocus(false)
slotCountEdit:SetNumeric(true)
slotCountEdit:SetMaxLetters(2)
slotCountEdit:SetJustifyH("CENTER")

local slotCountHint = slotCountDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
slotCountHint:SetPoint("TOP", slotCountEdit, "BOTTOM", 0, -8)
slotCountHint:SetText("1 bis " .. tostring(MAX_SLOT_COUNT) .. " Felder")
slotCountHint:SetTextColor(0.55, 0.55, 0.55)

local slotCountOK = CreateFrame("Button", nil, slotCountDialog, "UIPanelButtonTemplate")
slotCountOK:SetSize(100, 24)
slotCountOK:SetPoint("BOTTOMLEFT", 52, 18)
slotCountOK:SetText("OK")

local slotCountCancel = CreateFrame("Button", nil, slotCountDialog, "UIPanelButtonTemplate")
slotCountCancel:SetSize(100, 24)
slotCountCancel:SetPoint("BOTTOMRIGHT", -52, 18)
slotCountCancel:SetText("Abbrechen")

local function ApplySlotCount()
    local boardFrame = Farmboard.frames[slotCountDialog.boardID]
    if not boardFrame then
        slotCountDialog:Hide()
        return
    end

    local value = tonumber(slotCountEdit:GetText())
    if not IsValidSlotCount(value) then
        Print("Bitte eine Feldanzahl zwischen " .. tostring(MIN_SLOT_COUNT) .. " und " .. tostring(MAX_SLOT_COUNT) .. " eingeben.")
        return
    end

    Farmboard:SetSlotCount(boardFrame, value)
    slotCountDialog:Hide()
end

slotCountOK:SetScript("OnClick", ApplySlotCount)
slotCountCancel:SetScript("OnClick", function() slotCountDialog:Hide() end)
slotCountEdit:SetScript("OnEnterPressed", ApplySlotCount)
slotCountEdit:SetScript("OnEscapePressed", function() slotCountDialog:Hide() end)
slotCountDialog:SetScript("OnShow", function()
    slotCountEdit:SetFocus()
    slotCountEdit:HighlightText()
end)
slotCountDialog:SetScript("OnHide", function() slotCountEdit:ClearFocus() end)

function Farmboard:OpenSlotCountDialog(boardFrame)
    slotCountDialog.boardID = boardFrame.data.id
    slotCountEdit:SetText(tostring(boardFrame.data.slotCount or DEFAULT_SLOT_COUNT))
    slotCountDialog:Show()
end

function Farmboard:OpenContextMenu(boardFrame)
    if not MenuUtil or not MenuUtil.CreateContextMenu then
        Print("Kontextmenü konnte nicht geöffnet werden.")
        return
    end

    MenuUtil.CreateContextMenu(boardFrame, function(_, rootDescription)
        rootDescription:CreateTitle(boardFrame.data.name)

        rootDescription:CreateRadio(
            "Horizontal",
            function() return boardFrame.data.orientation == "HORIZONTAL" end,
            function() Farmboard:SetOrientation(boardFrame, "HORIZONTAL") end
        )

        rootDescription:CreateRadio(
            "Vertikal",
            function() return boardFrame.data.orientation == "VERTICAL" end,
            function() Farmboard:SetOrientation(boardFrame, "VERTICAL") end
        )

        rootDescription:CreateDivider()

        rootDescription:CreateButton("Felder (" .. tostring(boardFrame.data.slotCount or DEFAULT_SLOT_COUNT) .. ")...", function()
            Farmboard:OpenSlotCountDialog(boardFrame)
        end)

        rootDescription:CreateCheckbox(
            "Benachrichtigung bei erreichtem Ziel",
            function() return boardFrame.data.notifyOnComplete == true end,
            function()
                boardFrame.data.notifyOnComplete = not boardFrame.data.notifyOnComplete
                if boardFrame.data.notifyOnComplete then
                    NotifyGoalComplete()
                end
            end
        )

        rootDescription:CreateButton("Benachrichtigung testen", function()
            ShowGoalCompleteMessage()
            if not PlayGoalCompleteSound() then
                Print("Sound konnte nicht abgespielt werden.")
            end
        end)

        rootDescription:CreateDivider()

        rootDescription:CreateButton("Umbenennen", function()
            Farmboard:OpenRenameDialog(boardFrame)
        end)

        rootDescription:CreateButton("Duplizieren", function()
            Farmboard:DuplicateBoard(boardFrame)
        end)

        rootDescription:CreateDivider()

        rootDescription:CreateButton(
            boardFrame.data.locked and "Fenster entsperren" or "Fenster sperren",
            function()
                boardFrame.data.locked = not boardFrame.data.locked
                Print(boardFrame.data.locked and "Fenster gesperrt." or "Fenster entsperrt.")
            end
        )

        rootDescription:CreateButton("Position zurücksetzen", function()
            ResetBoardPosition(boardFrame)
            Print("Position zurückgesetzt.")
        end)

        if #FarmboardDB.boards > 1 then
            rootDescription:CreateDivider()
            rootDescription:CreateButton("Farmboard löschen", function()
                StaticPopup_Show("FARMBOARD_DELETE_BOARD", boardFrame.data.name, nil, { boardID = boardFrame.data.id })
            end)
        end
    end)
end

function Farmboard:ShowAll()
    for _, board in ipairs(FarmboardDB.boards) do
        board.visible = true
        local boardFrame = self.frames[board.id] or self:CreateBoardFrame(board)
        boardFrame:Show()
        self:UpdateBoard(boardFrame)
    end
end

function Farmboard:HideAll()
    for _, board in ipairs(FarmboardDB.boards) do
        board.visible = false
        local boardFrame = self.frames[board.id]
        if boardFrame then
            boardFrame:Hide()
        end
    end
end

function Farmboard:ToggleAll()
    local anyShown = false
    for _, boardFrame in pairs(self.frames) do
        if boardFrame:IsShown() then
            anyShown = true
            break
        end
    end

    if anyShown then
        self:HideAll()
    else
        self:ShowAll()
    end
end

local function AreAnyBoardsShown()
    for _, boardFrame in pairs(Farmboard.frames) do
        if boardFrame:IsShown() then
            return true
        end
    end
    return false
end

local function AreAllBoardsLocked()
    if not FarmboardDB or not FarmboardDB.boards or #FarmboardDB.boards == 0 then
        return false
    end

    for _, board in ipairs(FarmboardDB.boards) do
        if not board.locked then
            return false
        end
    end
    return true
end

function Farmboard:SetAllLocked(locked)
    for _, board in ipairs(FarmboardDB.boards) do
        board.locked = locked and true or false
    end
    Print(locked and "Alle Farmboards gesperrt." or "Alle Farmboards entsperrt.")
end

function Farmboard:ResetAllPositions()
    for _, boardFrame in pairs(self.frames) do
        ResetBoardPosition(boardFrame)
    end
    Print("Positionen zurückgesetzt.")
end

local function SetMinimapButtonPosition()
    if not Farmboard.minimapButton or not FarmboardDB or not FarmboardDB.minimap then
        return
    end

    local angle = math.rad(FarmboardDB.minimap.angle or 225)
    local radius = 80
    Farmboard.minimapButton:ClearAllPoints()
    Farmboard.minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function Farmboard:OpenMinimapMenu(owner)
    if not MenuUtil or not MenuUtil.CreateContextMenu then
        Print("Kontextmenü konnte nicht geöffnet werden.")
        return
    end

    MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
        rootDescription:CreateTitle("Farmboard")

        rootDescription:CreateButton("Neues Farmboard", function()
            Farmboard:AddBoard()
        end)

        local boardsMenu = rootDescription:CreateButton("Farmboards (" .. tostring(#FarmboardDB.boards) .. ")")
        for _, board in ipairs(FarmboardDB.boards) do
            local boardID = board.id
            local boardFrame = Farmboard.frames[boardID]
            if boardFrame then
                local boardMenu = boardsMenu:CreateButton(board.name)

                boardMenu:CreateCheckbox(
                    "Anzeigen",
                    function() return boardFrame:IsShown() end,
                    function()
                        boardFrame.data.visible = not boardFrame:IsShown()
                        if boardFrame.data.visible then
                            boardFrame:Show()
                            Farmboard:UpdateBoard(boardFrame)
                        else
                            boardFrame:Hide()
                        end
                    end
                )

                boardMenu:CreateButton("Umbenennen", function()
                    Farmboard:OpenRenameDialog(boardFrame)
                end)

                boardMenu:CreateButton("Duplizieren", function()
                    Farmboard:DuplicateBoard(boardFrame)
                end)

                boardMenu:CreateButton(boardFrame.data.locked and "Entsperren" or "Sperren", function()
                    boardFrame.data.locked = not boardFrame.data.locked
                end)

                boardMenu:CreateButton("Position zurücksetzen", function()
                    ResetBoardPosition(boardFrame)
                end)

                if #FarmboardDB.boards > 1 then
                    boardMenu:CreateDivider()
                    boardMenu:CreateButton("Löschen", function()
                        StaticPopup_Show("FARMBOARD_DELETE_BOARD", boardFrame.data.name, nil, { boardID = boardFrame.data.id })
                    end)
                end
            end
        end

        rootDescription:CreateDivider()

        if AreAnyBoardsShown() then
            rootDescription:CreateButton("Alle Farmboards ausblenden", function()
                Farmboard:HideAll()
            end)
        else
            rootDescription:CreateButton("Alle Farmboards anzeigen", function()
                Farmboard:ShowAll()
            end)
        end

        local allLocked = AreAllBoardsLocked()
        rootDescription:CreateButton(allLocked and "Alle entsperren" or "Alle sperren", function()
            Farmboard:SetAllLocked(not allLocked)
        end)

        rootDescription:CreateButton("Positionen zurücksetzen", function()
            Farmboard:ResetAllPositions()
        end)
    end)
end

function Farmboard:CreateMinimapButton()
    if self.minimapButton then
        return
    end

    local button = CreateFrame("Button", "FarmboardMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("CENTER", 0, 0)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\AddOns\\Farmboard\\Media\\FarmboardMinimapIcon.tga")
    icon:SetTexCoord(0, 1, 0, 1)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function(self, mouseButton)
        if self.wasDragged then
            self.wasDragged = false
            return
        end

        if mouseButton == "LeftButton" then
            Farmboard:ToggleAll()
        elseif mouseButton == "RightButton" then
            Farmboard:OpenMinimapMenu(self)
        end
    end)

    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        self.wasDragged = true
    end)

    button:SetScript("OnDragStop", function(self)
        self.dragging = false
    end)

    button:SetScript("OnUpdate", function(self)
        if not self.dragging then
            return
        end

        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        px, py = px / scale, py / scale

        local angle = math.deg(math.atan2(py - my, px - mx))
        FarmboardDB.minimap.angle = angle
        SetMinimapButtonPosition()
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Farmboard", 1, 0.82, 0.12)
        GameTooltip:AddLine("Linksklick: Farmboards ein-/ausblenden", 1, 1, 1)
        GameTooltip:AddLine("Rechtsklick: Farmboard-Menü", 1, 1, 1)
        GameTooltip:AddLine("Ziehen: Minimap-Button verschieben", 0.65, 0.65, 0.65)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.minimapButton = button
    SetMinimapButtonPosition()
end

-- Events --------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("BANKFRAME_CLOSED")
eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= addonName then
            return
        end

        EnsureDatabase()
        for _, board in ipairs(FarmboardDB.boards) do
            Farmboard:CreateBoardFrame(board)
        end
        Farmboard:CreateMinimapButton()
        Farmboard:UpdateAll()
        Print("geladen. /farmboard oder /fb")
        return
    end

    if not FarmboardDB or type(FarmboardDB.boards) ~= "table" then
        return
    end

    Farmboard:UpdateAll()
end)

-- Slash commands ------------------------------------------------------------
SLASH_FARMBOARD1 = "/farmboard"
SLASH_FARMBOARD2 = "/fb"

SlashCmdList.FARMBOARD = function(message)
    local rawMessage = strtrim(message or "")
    local messageLower = string.lower(rawMessage)

    if messageLower == "" or messageLower == "toggle" then
        Farmboard:ToggleAll()
        return
    end

    if messageLower == "show" then
        Farmboard:ShowAll()
        return
    end

    if messageLower == "hide" then
        Farmboard:HideAll()
        return
    end

    if messageLower == "new" or messageLower == "neu" then
        Farmboard:AddBoard()
        return
    end

    if messageLower == "reset" then
        Farmboard:ResetAllPositions()
        return
    end

    Print("Befehle:")
    Print("/fb - alle Farmboards ein-/ausblenden")
    Print("/fb new - neues Farmboard erstellen")
    Print("/fb show - alle Farmboards anzeigen")
    Print("/fb hide - alle Farmboards ausblenden")
    Print("/fb reset - alle Positionen zurücksetzen")
    Print("Minimap: Linksklick = ein/aus, Rechtsklick = globales Menü")
    Print("Board-Rechtsklick: Layout, Feldanzahl, Umbenennen, Sperren, Löschen")
end
