local addonInitialized = false
-- Shared with LootMonitor.lua: must be a global, not local to this chunk
DB = nil
RollMenuFrame = nil
CurrentLootItem = nil
-- Central shared loot table (owned by DKPRollTracker)
CurrentLoot = CurrentLoot or {}

-- Helper to strip server names and whitespace
local function CleanName(name)
    if not name then return "" end
    local nameOnly = name:match("^(.-)%-") or name
    return nameOnly:trim():gsub("^%l", string.upper)
end

---------------------------------------------------------
-- 1. Database & Popups
---------------------------------------------------------
StaticPopupDialogs["CONFIRM_DKP_ROLL"] = {
    text = "Are you sure you want to roll DKP (1-100)? This will spend your points if you win.",
    button1 = "Yes, Roll",
    button2 = "Cancel",
    OnAccept = function() RandomRoll(1, 100) end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local addonLoaded = CreateFrame("Frame")
addonLoaded:RegisterEvent("ADDON_LOADED")
addonLoaded:SetScript("OnEvent", function(self, event, name)
    if name ~= "DKPRollTracker" then return end
    DKPRollTrackerDB = DKPRollTrackerDB or {}
    DB = DKPRollTrackerDB
    DB.DKPValues = DB.DKPValues or {}
    DB.AwardHistory = DB.AwardHistory or {}
    DB.WinnerHistory = DB.WinnerHistory or {}
    DB.Costs = DB.Costs or {
        Normal = { Tier = 40, BIS = 80, NonTier = 20 },
        Heroic = { Tier = 60, BIS = 120, NonTier = 30 },
        Mythic = { Tier = 100, BIS = 200, NonTier = 50 },
    }
    DB.WindowPosition = DB.WindowPosition or { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
    DB.AutoOpenLootWindow = DB.AutoOpenLootWindow or false
    addonInitialized = true
end)

---------------------------------------------------------
-- 2. Roll Storage (TAINT-SAFE DETECTION)
---------------------------------------------------------
RollLog = { [100] = {}, [99] = {}, [98] = {}, [97] = {} }
local CategoryNames = { [100] = "DKP", [99] = "MS", [98] = "OS", [97] = "DE" }

-- Create a safe pattern from the game's own roll string
-- This handles "Secret Strings" and different languages automatically
local rollPattern = RANDOM_ROLL_RESULT:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")

local rollFrame = CreateFrame("Frame")
rollFrame:RegisterEvent("CHAT_MSG_SYSTEM")
rollFrame:SetScript("OnEvent", function(_, _, msg)
    if not msg then return end

    -- CORRECT MODERN RETAIL API CHECKS
    -- 1) If the global `issecretvalue` exists and flags this msg, check access
    if issecretvalue and issecretvalue(msg) then
        -- 2) If the global `canaccessvalue` exists and denies access, bail out
        if canaccessvalue and not canaccessvalue(msg) then
            return
        end
    end

    -- Use the raw msg directly with string.match to avoid secret string errors
    local player, roll, low, high = string.match(msg, rollPattern)
    
    if player and low and high then
        roll, high = tonumber(roll), tonumber(high)
        local shortName = CleanName(player)
        
        if RollLog[high] then
            -- Only record the first roll per category
            for _, entry in ipairs(RollLog[high]) do 
                if entry.name == shortName then return end 
            end
            
            table.insert(RollLog[high], { name = shortName, value = roll })
            if RollMenuFrame and RollMenuFrame:IsShown() then 
                RollMenuFrame:RefreshResults() 
            end
        end
    end
end)

---------------------------------------------------------
-- 3. Window Functions (Import, Export, Award)
---------------------------------------------------------

local currentDiff, currentType = "Normal", "Tier"

local function ConsumeLootItem(index)
    local item = CurrentLoot[index]
    if not item then return end

    local totalCount = 0
    for _, entry in ipairs(CurrentLoot) do
        if entry.link == item.link then
            totalCount = totalCount + (entry.count or 1)
        end
    end

    CurrentLootItem = { name = item.name, link = item.link, texture = item.texture, count = totalCount }

    local newLoot = {}
    for _, entry in ipairs(CurrentLoot) do
        if entry.link ~= item.link then
            table.insert(newLoot, entry)
        end
    end
    -- Preserve shared `CurrentLoot` table reference: wipe and refill
    if not CurrentLoot then CurrentLoot = {} end
    for k in pairs(CurrentLoot) do CurrentLoot[k] = nil end
    for _, v in ipairs(newLoot) do table.insert(CurrentLoot, v) end
end

local function RemoveLootItem(index)
    if CurrentLoot[index] then
        table.remove(CurrentLoot, index)
    end
    if RollMenuFrame and RollMenuFrame:IsShown() then
        RollMenuFrame:RefreshLootPanel()
    end
end

local function FormatLootLine(item)
    if item.count and item.count > 1 then
        return item.link .. " |cffffd100x" .. item.count .. "|r"
    end
    return item.link
end

local function RefreshAwardPanel(f)
    local award = f.rightPanel.lootContent.awardContent
    if not award then return end

    --award.statusText:SetText("Select winners from the left roller list, then click Award Winners.")
end

local function RefreshExportPanel(f)
    local export = f.rightPanel.exportContent
    if not export then return end

    local output = ""
    for _, entry in ipairs(DB.AwardHistory or {}) do
        output = output .. string.format("%s, %s, %s, %d\n", entry.name, entry.diff, entry.type, entry.cost)
    end
    export.editBox:SetText(output == "" and "No items awarded yet." or output)
end

local function SaveRollMenuPosition(frame)
    if not DB then return end
    local point, _, relativePoint, xOfs, yOfs = frame:GetPoint()
    if point and relativePoint and xOfs and yOfs then
        DB.WindowPosition = { point = point, relativePoint = relativePoint, x = xOfs, y = yOfs }
    end
end

function CreateRollMenu()
    if RollMenuFrame and type(RollMenuFrame.ShowRightTab) == "function" then
        RollMenuFrame:Show()
        RollMenuFrame:RefreshResults()
        RollMenuFrame:RefreshLootPanel()
        RollMenuFrame:RefreshAwardPanel()
        return
    end

    RollMenuFrame = nil
    local f = CreateFrame("Frame", "RollMenuFrame", UIParent, "BackdropTemplate")
    f:SetSize(840, 560)
    if DB and DB.WindowPosition then
        f:SetPoint(DB.WindowPosition.point, UIParent, DB.WindowPosition.relativePoint, DB.WindowPosition.x, DB.WindowPosition.y)
    else
        f:SetPoint("CENTER")
    end
    f:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0, 0, 0, 0.9)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        SaveRollMenuPosition(f)
    end)

    local closeX = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", -2, -2)
    closeX:SetFrameLevel(f:GetFrameLevel() + 10)
    closeX:SetScript("OnClick", function() f:Hide() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -15)
    title:SetText("DKP & Roll Tracker")

    local leftPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    leftPanel:SetPoint("TOPLEFT", 20, -40)
    leftPanel:SetSize(370, 500)
    leftPanel:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    leftPanel:SetBackdropColor(0, 0, 0, 0.85)

    local btnR100 = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    btnR100:SetSize(80, 22)
    btnR100:SetPoint("TOPLEFT", 10, -10)
    btnR100:SetText("DKP (100)")
    btnR100:SetScript("OnClick", function() StaticPopup_Show("CONFIRM_DKP_ROLL") end)

    local btnR99 = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    btnR99:SetSize(80, 22)
    btnR99:SetPoint("TOPLEFT", btnR100, "TOPRIGHT", 5, 0)
    btnR99:SetText("MS (99)")
    btnR99:SetScript("OnClick", function() RandomRoll(1, 99) end)

    local btnR98 = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    btnR98:SetSize(80, 22)
    btnR98:SetPoint("TOPLEFT", btnR99, "TOPRIGHT", 5, 0)
    btnR98:SetText("OS (98)")
    btnR98:SetScript("OnClick", function() RandomRoll(1, 98) end)

    local btnR97 = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    btnR97:SetSize(80, 22)
    btnR97:SetPoint("TOPLEFT", btnR98, "TOPRIGHT", 5, 0)
    btnR97:SetText("DE (97)")
    btnR97:SetScript("OnClick", function() RandomRoll(1, 97) end)

    local rightPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    rightPanel:SetPoint("TOPRIGHT", -20, -40)
    rightPanel:SetSize(420, 500)
    rightPanel:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    rightPanel:SetBackdropColor(0, 0, 0, 0.85)
    f.rightPanel = rightPanel

    local trackerScroll = CreateFrame("ScrollFrame", nil, leftPanel, "UIPanelScrollFrameTemplate")
    trackerScroll:SetPoint("TOPLEFT", 0, -42)
    trackerScroll:SetSize(340, 420)
    local trackerContent = CreateFrame("Frame", nil, trackerScroll)
    trackerContent:SetSize(340, 420)
    trackerScroll:SetScrollChild(trackerContent)
    leftPanel.content = trackerContent
    leftPanel.rows = {}

    local tabNames = { "Loot", "Import", "Export", "History", "Settings" }
    for i, name in ipairs(tabNames) do
        local btn = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
        btn:SetSize(75, 22)
        btn:SetPoint("TOPLEFT", 10 + ((i - 1) * 80), -10)
        btn:SetText(name)
        btn:SetScript("OnClick", function() f:ShowRightTab(name) end)
        rightPanel[name .. "Tab"] = btn
    end

    local function createRightContent()
        local content = CreateFrame("Frame", nil, rightPanel)
        content:SetPoint("TOPLEFT", 10, -40)
        content:SetSize(380, 440)
        content:Hide()
        return content
    end

    rightPanel.lootContent = createRightContent()
    rightPanel.importContent = createRightContent()
    rightPanel.exportContent = createRightContent()
    rightPanel.historyContent = createRightContent()
    rightPanel.settingsContent = createRightContent()

    do
        local lootPanel = rightPanel.lootContent
        lootPanel.currentItem = CreateFrame("Frame", nil, lootPanel)
        lootPanel.currentItem:SetPoint("TOPLEFT", 0, 0)
        lootPanel.currentItem:SetSize(380, 40)
        lootPanel.currentItem.icon = lootPanel.currentItem:CreateTexture(nil, "ARTWORK")
        lootPanel.currentItem.icon:SetSize(34, 34)
        lootPanel.currentItem.icon:SetPoint("LEFT", 0, 0)
        lootPanel.currentItem.text = lootPanel.currentItem:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lootPanel.currentItem.text:SetPoint("LEFT", lootPanel.currentItem.icon, "RIGHT", 8, 0)
        lootPanel.currentItem.text:SetJustifyH("LEFT")
        lootPanel.currentItem.icon:Hide()

        lootPanel.scroll = CreateFrame("ScrollFrame", nil, lootPanel, "UIPanelScrollFrameTemplate")
        lootPanel.scroll:SetPoint("TOPLEFT", 0, -50)
        lootPanel.scroll:SetSize(380, 260)
        lootPanel.scrollChild = CreateFrame("Frame", nil, lootPanel.scroll)
        lootPanel.scrollChild:SetSize(380, 1)
        lootPanel.scroll:SetScrollChild(lootPanel.scrollChild)
        lootPanel.lootRows = {}

        lootPanel.emptyText = lootPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lootPanel.emptyText:SetPoint("TOPLEFT", 0, -70)
        lootPanel.emptyText:SetText("No loot items in the queue.")
        lootPanel.emptyText:SetJustifyH("LEFT")

        local awardHeader = lootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        awardHeader:SetPoint("TOPLEFT", lootPanel.scroll, "BOTTOMLEFT", 0, -10)
        awardHeader:SetText("Award Winners")

        local awardContent = CreateFrame("Frame", nil, lootPanel)
        awardContent:SetPoint("TOPLEFT", awardHeader, "BOTTOMLEFT", 0, -10)
        awardContent:SetSize(380, 100)
        awardContent.diffBtns = {}
        awardContent.typeBtns = {}

        --awardContent.statusText = awardContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        --awardContent.statusText:SetPoint("TOPLEFT", 0, 0)
        --awardContent.statusText:SetWidth(360)
        --awardContent.statusText:SetJustifyH("LEFT")
        --awardContent.statusText:SetText("Select winners from the left roller list, then click Award Winners.")

        for i, d in ipairs({ "Normal", "Heroic", "Mythic" }) do
            local b = CreateFrame("Button", nil, awardContent, "UIPanelButtonTemplate")
            b:SetSize(80, 20)
            b:SetPoint("TOPLEFT", 0 + ((i - 1) * 85), 0)
            b:SetText(d)
            b:SetScript("OnClick", function()
                currentDiff = d
                for _, btn in ipairs(awardContent.diffBtns) do btn:UnlockHighlight() end
                b:LockHighlight()
            end)
            if d == "Normal" then b:LockHighlight() end
            table.insert(awardContent.diffBtns, b)
        end

        for i, td in ipairs({ { n = "Tier", k = "Tier" }, { n = "BIS", k = "BIS" }, { n = "Non-Tier", k = "NonTier" } }) do
            local b = CreateFrame("Button", nil, awardContent, "UIPanelButtonTemplate")
            b:SetSize(80, 20)
            b:SetPoint("TOPLEFT", 0 + ((i - 1) * 85), -28)
            b:SetText(td.n)
            b:SetScript("OnClick", function()
                currentType = td.k
                for _, btn in ipairs(awardContent.typeBtns) do btn:UnlockHighlight() end
                b:LockHighlight()
            end)
            if td.k == "Tier" then b:LockHighlight() end
            table.insert(awardContent.typeBtns, b)
        end

        local awardButton = CreateFrame("Button", nil, awardContent, "UIPanelButtonTemplate")
        awardButton:SetSize(160, 24)
        awardButton:SetPoint("BOTTOMLEFT", 0, 0)
        awardButton:SetText("Award Winners")
        awardButton:SetScript("OnClick", function()
            if not CurrentLootItem then return end
            local cost = DB.Costs[currentDiff][currentType]
            local selected = {}
            for _, row in ipairs(leftPanel.rows) do
                if row.checkbox and row.checkbox:IsShown() and row.checkbox:GetChecked() then
                    table.insert(selected, { name = row.playerName, high = row.high })
                end
            end
            if #selected == 0 then
                return
            end

            local awardedItem = CurrentLootItem
            local winners = {}
            for _, sel in ipairs(selected) do
                table.insert(DB.WinnerHistory, { name = sel.name, itemName = awardedItem.name, itemLink = awardedItem.link, itemTexture = awardedItem.texture, rollType = CategoryNames[sel.high] })
                if sel.high == 100 then
                    DB.DKPValues[sel.name] = (DB.DKPValues[sel.name] or 0) - cost
                    table.insert(DB.AwardHistory, { name = sel.name, diff = currentDiff, type = currentType, cost = cost })
                end
                table.insert(winners, { name = sel.name, rollType = CategoryNames[sel.high] })
                local channel = GetAnnounceChannel()
                SendChatMessage(string.format("%s won %s", sel.name, awardedItem.link or awardedItem.name), channel)
            end

            for _, row in ipairs(leftPanel.rows) do
                if row.checkbox and row.checkbox:IsShown() then
                    row.checkbox:SetChecked(false)
                end
            end
            RollLog = { [100] = {}, [99] = {}, [98] = {}, [97] = {} }
            CurrentLootItem = nil
            if BroadcastRollAward then BroadcastRollAward(awardedItem, winners) end
            f:RefreshResults()
            f:RefreshLootPanel()
            f:RefreshHistoryPanel()
        end)

        lootPanel.awardContent = awardContent
    end

    do
        local importPanel = rightPanel.importContent
        local title = importPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 0, 0)
        title:SetText("Import DKP Values")
        local inst = importPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        inst:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        inst:SetText("Paste CSV: CharacterName,DKPBalance (one per line)")
        local scroll = CreateFrame("ScrollFrame", nil, importPanel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 0, -40)
        scroll:SetSize(380, 320)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(GameFontHighlight)
        edit:SetWidth(370)
        scroll:SetScrollChild(edit)
        importPanel.editBox = edit
        local importBtn = CreateFrame("Button", nil, importPanel, "UIPanelButtonTemplate")
        importBtn:SetSize(140, 24)
        importBtn:SetPoint("BOTTOMLEFT", 0, 0)
        importBtn:SetText("Confirm Import")
        importBtn:SetScript("OnClick", function()
            local count = 0
            for line in edit:GetText():gmatch("[^\r\n]+") do
                local n, v = line:match("^%s*([^,]+)%s*,%s*(%-?%d+)%s*$")
                if n and v then
                    DB.DKPValues[CleanName(n)] = tonumber(v)
                    count = count + 1
                end
            end
            print("|cff00ff00Imported " .. count .. " players.|r")
            f:RefreshResults()
            f:RefreshAwardPanel()
        end)
    end

    do
        local exportPanel = rightPanel.exportContent
        local title = exportPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 0, 0)
        title:SetText("Export Award History")
        local scroll = CreateFrame("ScrollFrame", nil, exportPanel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 0, -30)
        scroll:SetSize(380, 320)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(GameFontHighlightSmall)
        edit:SetWidth(370)
        edit:SetAutoFocus(false)
        scroll:SetScrollChild(edit)
        exportPanel.editBox = edit
        local copyBtn = CreateFrame("Button", nil, exportPanel, "UIPanelButtonTemplate")
        copyBtn:SetSize(140, 24)
        copyBtn:SetPoint("BOTTOMLEFT", 0, 0)
        copyBtn:SetText("Select All for Copy")
        copyBtn:SetScript("OnClick", function()
            edit:HighlightText()
            edit:SetFocus()
        end)
        local clearBtn = CreateFrame("Button", nil, exportPanel, "UIPanelButtonTemplate")
        clearBtn:SetSize(120, 24)
        clearBtn:SetPoint("BOTTOMRIGHT", 0, 0)
        clearBtn:SetText("Clear History")
        clearBtn:SetScript("OnClick", function()
            DB.AwardHistory = {}
            f:RefreshExportPanel()
        end)
    end

    do
        local settingsPanel = rightPanel.settingsContent
        local title = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 0, 0)
        title:SetText("DKP Cost Settings")

        -- Headers
        local headerY = -30
        local colX = { 140, 220, 300 }  -- Positions for Normal, Heroic, Mythic
        local headers = { "Normal", "Heroic", "Mythic" }
        for i, h in ipairs(headers) do
            local hdr = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            hdr:SetPoint("TOPLEFT", colX[i], headerY)
            hdr:SetText(h)
        end

        -- Rows
        local rowY = -60
        local categories = { "Tier", "BIS Weapons/Trinkets", "Non-Tier" }
        local keys = { "Tier", "BIS", "NonTier" }
        local editBoxes = {}

        for r, cat in ipairs(categories) do
            -- Category label
            local lbl = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("TOPLEFT", 0, rowY)
            lbl:SetText(cat)

            -- Edit boxes for each difficulty
            for c, diff in ipairs({ "Normal", "Heroic", "Mythic" }) do
                local edit = CreateFrame("EditBox", nil, settingsPanel, "InputBoxTemplate")
                edit:SetSize(50, 20)
                edit:SetPoint("TOPLEFT", colX[c], rowY)
                edit:SetNumeric(true)
                edit:SetText(tostring(DB.Costs[diff][keys[r]]))
                edit:SetAutoFocus(false)
                table.insert(editBoxes, { diff = diff, key = keys[r], edit = edit })
            end
            rowY = rowY - 30
        end

        local autoOpenCheck = CreateFrame("CheckButton", nil, settingsPanel, "UICheckButtonTemplate")
        autoOpenCheck:SetPoint("TOPLEFT", 0, rowY)
        autoOpenCheck:SetSize(20, 20)
        autoOpenCheck:SetChecked(DB.AutoOpenLootWindow)
        autoOpenCheck.text = autoOpenCheck.text or autoOpenCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        autoOpenCheck.text:SetPoint("LEFT", autoOpenCheck, "RIGHT", 5, 0)
        autoOpenCheck.text:SetText("Auto-open tracker on loot")
        rowY = rowY - 30

        local saveBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
        saveBtn:SetSize(80, 24)
        saveBtn:SetPoint("BOTTOMLEFT", 0, 0)
        saveBtn:SetText("Save")
        saveBtn:SetScript("OnClick", function()
            for _, eb in ipairs(editBoxes) do
                DB.Costs[eb.diff][eb.key] = tonumber(eb.edit:GetText()) or DB.Costs[eb.diff][eb.key]
            end
            DB.AutoOpenLootWindow = autoOpenCheck:GetChecked()
            print("|cffffff00DKP Settings:|r Costs updated. Auto-open on loot is " .. (DB.AutoOpenLootWindow and "enabled." or "disabled."))
        end)
    end

    do
        local historyPanel = rightPanel.historyContent
        local title = historyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 0, 0)
        title:SetText("Winner History")
        local scroll = CreateFrame("ScrollFrame", nil, historyPanel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 0, -30)
        scroll:SetSize(380, 360)
        local scrollChild = CreateFrame("Frame", nil, scroll)
        scrollChild:SetSize(380, 1)
        scroll:SetScrollChild(scrollChild)
        historyPanel.scrollChild = scrollChild
        historyPanel.historyRows = {}
        local clearBtn = CreateFrame("Button", nil, historyPanel, "UIPanelButtonTemplate")
        clearBtn:SetSize(120, 24)
        clearBtn:SetPoint("BOTTOMLEFT", 0, 0)
        clearBtn:SetText("Clear History")
        clearBtn:SetScript("OnClick", function()
            DB.WinnerHistory = {}
            f:RefreshHistoryPanel()
        end)
    end

    function f:ShowRightTab(name)
        for _, tabName in ipairs(tabNames) do
            if rightPanel[tabName .. "Tab"] then
                rightPanel[tabName .. "Tab"]:UnlockHighlight()
            end
        end
        rightPanel.lootContent:Hide()
        rightPanel.importContent:Hide()
        rightPanel.exportContent:Hide()
        rightPanel.historyContent:Hide()
        rightPanel.settingsContent:Hide()
        if rightPanel[name .. "Tab"] then
            rightPanel[name .. "Tab"]:LockHighlight()
        end
        if name == "Loot" then
            rightPanel.lootContent:Show()
        elseif name == "Import" then
            rightPanel.importContent:Show()
        elseif name == "Export" then
            rightPanel.exportContent:Show()
            f:RefreshExportPanel()
        elseif name == "History" then
            rightPanel.historyContent:Show()
            f:RefreshHistoryPanel()
        elseif name == "Settings" then
            rightPanel.settingsContent:Show()
        end
    end

    function f:RefreshResults()
        for _, row in ipairs(leftPanel.rows) do
            row:Hide()
        end
        if not self.header then
            self.header = CreateFrame("Frame", nil, leftPanel.content)
            self.header:SetSize(580, 20)
            self.header:SetPoint("TOPLEFT", 0, -5)
            self.header.name = self.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            self.header.name:SetPoint("LEFT", 15, 0)
            self.header.name:SetText("Player")
            self.header.roll = self.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            self.header.roll:SetPoint("LEFT", 180, 0)
            self.header.roll:SetText("Roll")
            self.header.dkp = self.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            self.header.dkp:SetPoint("LEFT", 280, 0)
            self.header.dkp:SetText("DKP")
        end

        local y = 25
        local idx = 1
        for cat = 100, 97, -1 do
            if RollLog[cat] and #RollLog[cat] > 0 then
                local section = leftPanel.rows[idx] or CreateFrame("Frame", nil, leftPanel.content)
                section:SetSize(580, 20)
                section.pText = section.pText or section:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                section.pText:SetPoint("LEFT", 15, 0)
                section.pText:SetText("|cffffff00" .. CategoryNames[cat] .. "|r")
                if section.rText then section.rText:SetText("") end
                if section.dText then section.dText:SetText("") end
                if section.checkbox then
                    section.checkbox:Hide()
                    section.checkbox:SetChecked(false)
                end
                section:SetPoint("TOPLEFT", 0, -y)
                section:Show()
                leftPanel.rows[idx] = section
                y = y + 22
                idx = idx + 1

                local rollers = { unpack(RollLog[cat]) }
                if cat == 100 then
                    table.sort(rollers, function(a, b)
                        local dkpA = DB.DKPValues[a.name] or 0
                        local dkpB = DB.DKPValues[b.name] or 0
                        if dkpA ~= dkpB then
                            return dkpA > dkpB
                        end
                        return a.value > b.value
                    end)
                else
                    table.sort(rollers, function(a, b)
                        return a.value > b.value
                    end)
                end

                for _, data in ipairs(rollers) do
                    local rr = leftPanel.rows[idx] or CreateFrame("Frame", nil, leftPanel.content)
                    rr:SetSize(580, 20)
                    rr.checkbox = rr.checkbox or CreateFrame("CheckButton", nil, rr, "UICheckButtonTemplate")
                    rr.checkbox:SetPoint("LEFT", 10, 0)
                    rr.checkbox:SetSize(20, 20)
                    rr.checkbox:Show()
                    rr.checkbox:SetChecked(false)
                    rr.playerName = data.name
                    rr.high = cat
                    rr.pText = rr.pText or rr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    rr.pText:SetPoint("LEFT", 40, 0)
                    rr.rText = rr.rText or rr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    rr.rText:SetPoint("LEFT", 180, 0)
                    rr.dText = rr.dText or rr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    rr.dText:SetPoint("LEFT", 280, 0)
                    rr.pText:SetText(data.name)
                    rr.rText:SetText(data.value)
                    rr.dText:SetText(cat == 100 and (DB.DKPValues[data.name] or "0") or "")
                    rr:SetPoint("TOPLEFT", 0, -y)
                    rr:Show()
                    leftPanel.rows[idx] = rr
                    y = y + 20
                    idx = idx + 1
                end
                y = y + 10
            end
        end
        leftPanel.content:SetHeight(math.max(430, y))
    end

    function f:RefreshLootPanel()
        local lootPanel = rightPanel.lootContent
        if CurrentLootItem then
            lootPanel.currentItem.icon:SetTexture(CurrentLootItem.texture or 134400)
            lootPanel.currentItem.icon:Show()
            local countText = (CurrentLootItem.count and CurrentLootItem.count > 1) and (" x" .. CurrentLootItem.count) or ""
            lootPanel.currentItem.text:SetText("Rolling for: " .. CurrentLootItem.link .. countText)
        else
            lootPanel.currentItem.icon:Hide()
            lootPanel.currentItem.text:SetText("No active roll item. Start a roll from the loot queue below.")
        end

        local y = 0
        for _, row in ipairs(lootPanel.lootRows) do
            row:Hide()
        end

        for idx, item in ipairs(CurrentLoot) do
            local row = lootPanel.lootRows[idx] or CreateFrame("Frame", nil, lootPanel.scrollChild)
            row:SetSize(380, 48)
            row:SetPoint("TOPLEFT", 0, -y)
            row:Show()
            row.icon = row.icon or row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(32, 32)
            row.icon:SetPoint("LEFT", 0, 0)
            row.icon:SetTexture(item.texture or 134400)
            row.link = row.link or row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.link:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
            row.link:SetWidth(240)
            row.link:SetJustifyH("LEFT")
            row.link:SetText(FormatLootLine(item))
            row:SetScript("OnEnter", function()
                GameTooltip:SetOwner(row, "ANCHOR_TOP")
                if item.link then
                    GameTooltip:SetHyperlink(item.link)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            row.start = row.start or CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.start:SetSize(80, 20)
            row.start:SetText("Start Roll")

            row.remove = row.remove or CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.remove:SetSize(70, 20)
            row.remove:SetPoint("BOTTOMRIGHT", 0, 0)
            row.remove:SetText("Remove")
            row.start:SetPoint("BOTTOMRIGHT", row.remove, "BOTTOMLEFT", -10, 0)

            local itemIndex = idx
            row.start:SetScript("OnClick", function()
                ConsumeLootItem(itemIndex)
                RollLog = { [100] = {}, [99] = {}, [98] = {}, [97] = {} }
                f:RefreshResults()
                f:RefreshLootPanel()
                local countText = (CurrentLootItem.count and CurrentLootItem.count > 1) and (" (" .. CurrentLootItem.count .. " available)") or ""
                local channel = GetAnnounceChannel()
                SendChatMessage("--- STARTING ROLL: " .. CurrentLootItem.link .. countText .. " ---", channel)
                SendChatMessage("DKP: /roll 100", channel)
                SendChatMessage("Main Spec: /roll 99", channel)
                SendChatMessage("Off Spec: /roll 98", channel)
                SendChatMessage("Disenchant: /roll 97", channel)
                if BroadcastRollStart then BroadcastRollStart(CurrentLootItem) end
            end)

            row.remove:SetScript("OnClick", function()
                RemoveLootItem(itemIndex)
            end)

            lootPanel.lootRows[idx] = row
            y = y + 52
        end

        lootPanel.scrollChild:SetHeight(math.max(1, y))
        lootPanel.emptyText:SetShown(#CurrentLoot == 0)
    end

    function f:RefreshAwardPanel()
        RefreshAwardPanel(self)
    end

    function f:RefreshExportPanel()
        RefreshExportPanel(self)
    end

    local function RefreshHistoryPanel(f)
        local history = f.rightPanel.historyContent
        if not history then return end

        for _, row in ipairs(history.historyRows) do
            row:Hide()
        end

        local y = 0
        for i, entry in ipairs(DB.WinnerHistory) do
            local row = history.historyRows[i] or CreateFrame("Frame", nil, history.scrollChild)
            row:SetSize(380, 40)
            row:SetPoint("TOPLEFT", 0, -y)
            row:Show()
            row.icon = row.icon or row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(32, 32)
            row.icon:SetPoint("LEFT", 0, 0)
            row.icon:SetTexture(entry.itemTexture or 134400)
            row.icon:SetScript("OnEnter", function()
                GameTooltip:SetOwner(row.icon, "ANCHOR_TOP")
                if entry.itemLink then
                    GameTooltip:SetHyperlink(entry.itemLink)
                end
                GameTooltip:Show()
            end)
            row.icon:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            row.itemText = row.itemText or row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.itemText:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
            row.itemText:SetWidth(170)
            row.itemText:SetJustifyH("LEFT")
            row.itemText:SetText(entry.itemName or "")
            row.nameText = row.nameText or row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.nameText:SetPoint("LEFT", row.itemText, "RIGHT", 10, 0)
            row.nameText:SetWidth(120)
            row.nameText:SetJustifyH("LEFT")
            row.nameText:SetText(entry.name)
            row.typeText = row.typeText or row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.typeText:SetPoint("LEFT", row.nameText, "RIGHT", 10, 0)
            row.typeText:SetWidth(80)
            row.typeText:SetJustifyH("LEFT")
            row.typeText:SetText(entry.rollType or "")
            history.historyRows[i] = row
            y = y + 42
        end

        history.scrollChild:SetHeight(math.max(1, y))
    end

    function f:RefreshHistoryPanel()
        RefreshHistoryPanel(self)
    end

    local bClr = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    bClr:SetSize(80, 25)
    bClr:SetPoint("BOTTOMLEFT", 20, 20)
    bClr:SetText("Clear")
    bClr:SetScript("OnClick", function()
        RollLog = { [100] = {}, [99] = {}, [98] = {}, [97] = {} }
        f:RefreshResults()
    end)

    RollMenuFrame = f
    f:ShowRightTab("Loot")
    f:RefreshResults()
    f:RefreshLootPanel()
    f:RefreshHistoryPanel()
    f:Show()
    -- If LootMonitor queued an update before this UI was available, apply it now
    if PendingLootUpdate and UpdateLootList then
        UpdateLootList()
    end
end

---------------------------------------------------------
-- Automatic Loot Window Activation is handled by LootMonitor.lua's
-- START_LOOT_ROLL handler (the correct, reliable trigger for a roll
-- actually starting), which calls UpdateLootList() when
-- DB.AutoOpenLootWindow is true.
---------------------------------------------------------

SLASH_DKPROLL1 = "/dkp"
SlashCmdList["DKPROLL"] = CreateRollMenu