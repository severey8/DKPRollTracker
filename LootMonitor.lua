-- Use the tracker's global `CurrentLoot` table; do not reassign it here
CurrentLoot = CurrentLoot or {}

function GetAnnounceChannel()
    return (IsInRaid() and "RAID") or (IsInGroup() and "PARTY") or "SAY"
end

local function DoesTooltipIndicateNonTradable(itemLink)
    if not itemLink or not C_TooltipInfo.GetHyperlink then
        return false
    end

    local tooltipData = C_TooltipInfo.GetHyperlink(itemLink)
    if not tooltipData or not tooltipData.lines then
        return false
    end

    for _, line in ipairs(tooltipData.lines) do
        local leftText = line.leftText
        local rightText = line.rightText
        local leftSecondaryText = line.leftSecondaryText
        local rightSecondaryText = line.rightSecondaryText

        for _, text in ipairs({ leftText, rightText, leftSecondaryText, rightSecondaryText }) do
            if text then
                local lower = text:lower()
                if lower:find("account bound") or lower:find("bnet") or lower:find("warband") or lower:find("soulbound") then
                    return true
                end
            end
        end
    end

    return false
end

local function HasTradeTimeRemaining(itemLink)
    if not itemLink or not C_TooltipInfo.GetHyperlink then
        return false
    end

    local tooltipData = C_TooltipInfo.GetHyperlink(itemLink)
    if not tooltipData or not tooltipData.lines then
        return false
    end

    local searchText = BIND_TRADE_TIME_REMAINING and BIND_TRADE_TIME_REMAINING:lower()
    if not searchText then
        return false
    end

    for _, line in ipairs(tooltipData.lines) do
        local leftText = line.leftText
        local rightText = line.rightText
        if (leftText and leftText:lower():find(searchText)) or (rightText and rightText:lower():find(searchText)) then
            return true
        end
    end

    return false
end

local function IsItemLinkTradable(itemLink)
    if not itemLink then
        return false
    end

    if DoesTooltipIndicateNonTradable(itemLink) then
        return false
    end

    --local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
    --local bindType = itemID and select(14, GetItemInfo(itemID))
    --if bindType == 4 or bindType == 5 or bindType == 7 or bindType == 8 or bindType == 9 then
    --    return false
    --end

    --if bindType == 1 then
    --    return HasTradeTimeRemaining(itemLink)
    --end

    return true
end

local function IsBagItemTradable(info)
    --if not info or not info.hyperlink then
    --    return false
    --end

    --if info.isQuestItem or info.isBound or info.isSoulbound then
    --    return false
    --end

    return IsItemLinkTradable(info.hyperlink)
end

local function NormalizeName(name)
    if not name then
        return nil
    end
    local cleanName = name:match("^(.-)%-") or name
    return cleanName:gsub("^%l", string.upper)
end

local function GetTradePartnerName()
    local partner
    if _G.TradeFrameRecipientName and _G.TradeFrameRecipientName.GetText then
        partner = _G.TradeFrameRecipientName:GetText()
    end
    if not partner or partner == "" then
        partner = UnitName("target")
    end
    return NormalizeName(partner)
end

local function GetContainerItemLinkSafe(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bag, slot)
    elseif GetContainerItemLink then
        return GetContainerItemLink(bag, slot)
    end
    return nil
end

local function GetItemIDFromLink(link)
    return link and tonumber(string.match(link, "item:(%d+)"))
end

local function FindBagSlotForItemLink(itemLink)
    if not itemLink then
        return nil
    end

    local targetID = GetItemIDFromLink(itemLink)
    for bag = 0, 5 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local link = GetContainerItemLinkSafe(bag, slot)
            if link then
                if link == itemLink then
                    return bag, slot
                end
                if targetID and GetItemIDFromLink(link) == targetID then
                    return bag, slot
                end
            end
        end
    end
    return nil
end

local function AutoPlaceTradeItem(itemLink)
    local bag, slot = FindBagSlotForItemLink(itemLink)
    if not bag then
        return false
    end

    if CursorHasItem and CursorHasItem() then
        ClearCursor()
    end

    C_Container.PickupContainerItem(bag, slot)
    return true
end

local function AutoPlaceTradeHistoryItem()
    if not DB or not DB.WinnerHistory then
        return
    end

    local partner = GetTradePartnerName()
    if not partner or partner == "" then
        return
    end

    for i = #DB.WinnerHistory, 1, -1 do
        local entry = DB.WinnerHistory[i]
        if entry and entry.name == partner and entry.itemLink then
            if AutoPlaceTradeItem(entry.itemLink) then
                print("|cffffff00DKP:|r Auto-placing " .. entry.itemLink .. " for trade with " .. partner)
            else
                print("|cffffff00DKP:|r Could not find " .. (entry.itemLink or entry.name) .. " in bags for trade.")
            end
            return
        end
    end
end

local function RefreshLootWindow()
    if type(CreateRollMenu) ~= "function" then
        print("|cffff0000DKP Error:|r Main tracker function 'CreateRollMenu' not found. Ensure it is not 'local'.")
        return
    end

    CreateRollMenu()

    if not RollMenuFrame or type(RollMenuFrame.ShowRightTab) ~= "function" then
        RollMenuFrame = nil
        CreateRollMenu()
    end

    if RollMenuFrame and type(RollMenuFrame.ShowRightTab) == "function" then
        RollMenuFrame:ShowRightTab("Loot")
        RollMenuFrame:RefreshLootPanel()
        RollMenuFrame:RefreshAwardPanel()
        RollMenuFrame:RefreshResults()
    end
end

local function CollectEpicLoot(onlyTradable)
    local tempLoot = {}
    local foundAny = false

    for b = 0, 5 do
        for s = 1, C_Container.GetContainerNumSlots(b) do
            local info = C_Container.GetContainerItemInfo(b, s)
            if info and info.hyperlink and info.quality and info.quality >= 4 and (not onlyTradable or IsBagItemTradable(info)) then
                local name = GetItemInfo(info.hyperlink)
                if name then
                    foundAny = true
                    if tempLoot[name] then
                        tempLoot[name].count = tempLoot[name].count + 1
                    else
                        tempLoot[name] = { name = name, link = info.hyperlink, texture = info.iconFileID, count = 1 }
                    end
                end
            end
        end
    end

    if not CurrentLoot then CurrentLoot = {} end
    for k in pairs(CurrentLoot) do CurrentLoot[k] = nil end
    for _, data in pairs(tempLoot) do table.insert(CurrentLoot, data) end

    if not foundAny and not onlyTradable then
        print("|cffffff00DKP DEBUG:|r No Epics found. Adding a fake [Test Sword] for debugging.")
        table.insert(CurrentLoot, {
            name = "Test Sword",
            link = "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r",
            texture = 135057,
            count = 1,
        })
    end
end

function UpdateLootList()
    -- If the main UI hasn't loaded yet, mark a pending update so the tracker can apply it later
    if type(CreateRollMenu) ~= "function" then
        PendingLootUpdate = true
        return
    end
    PendingLootUpdate = nil
    RefreshLootWindow()
end

SLASH_DKPLOOT1 = "/dkploot"
SlashCmdList["DKPLOOT"] = function()
    print("|cffffff00DKP DEBUG:|r Scanning bags for tradable Epic items...")
    CollectEpicLoot(true)
    UpdateLootList()
end

local function GenerateTestRollData()
    RollLog = {
        [100] = {
            { name = "Ariella", value = 92 },
            { name = "Bren", value = 78 },
            { name = "Cora", value = 64 },
        },
        [99] = {
            { name = "Darel", value = 88 },
            { name = "Ezra", value = 74 },
        },
        [98] = {
            { name = "Fina", value = 85 },
            { name = "Grim", value = 69 },
        },
        [97] = {
            { name = "Hale", value = 51 },
        },
    }
end

local function DumpLootRollAPI(rollID)
    print(string.format("|cff33ccff[DKPDEBUG]|r --- rollID=%s ---", tostring(rollID)))

    local itemLink = GetLootRollItemLink and GetLootRollItemLink(rollID)
    print(string.format("|cff33ccff[DKPDEBUG]|r GetLootRollItemLink -> %s", tostring(itemLink)))

    local raw = { GetLootRollItemInfo(rollID) }
    print(string.format("|cff33ccff[DKPDEBUG]|r GetLootRollItemInfo numReturns=%d", #raw))
    for i, v in ipairs(raw) do
        print(string.format("|cff33ccff[DKPDEBUG]|r   ret[%d] type=%s value=%s", i, type(v), tostring(v)))
        if type(v) == "table" then
            for k2, v2 in pairs(v) do
                print(string.format("|cff33ccff[DKPDEBUG]|r     [%s]=%s", tostring(k2), tostring(v2)))
            end
        end
    end
end

SLASH_DKPTESTAPILOOT1 = "/dkptestapiloot"
SlashCmdList["DKPTESTAPILOOT"] = function(msg)
    local rollID = tonumber(msg)
    if rollID then
        DumpLootRollAPI(rollID)
        return
    end

    local activeRolls = GetActiveLootRollIDs and GetActiveLootRollIDs() or {}
    print(string.format("|cff33ccff[DKPDEBUG]|r no rollID given; active roll count=%d", #activeRolls))
    for _, id in ipairs(activeRolls) do
        DumpLootRollAPI(id)
    end
end

SLASH_DKPTEST1 = "/dkptest"
SlashCmdList["DKPTEST"] = function()
    print("|cffffff00DKP DEBUG:|r Running DKP loot + test data generation...")
    CollectEpicLoot(false)
    UpdateLootList()
    GenerateTestRollData()
    if RollMenuFrame then
        RollMenuFrame:RefreshResults()
        RollMenuFrame:RefreshAwardPanel()
    end
end

local function RefreshActiveLootRolls()
    -- Populate CurrentLoot from active roll IDs (group loot roll window)
    local tempLoot = {}
    local activeRolls = GetActiveLootRollIDs and GetActiveLootRollIDs() or {}

    for _, rollID in ipairs(activeRolls) do
        local itemLink = GetLootRollItemLink and GetLootRollItemLink(rollID)
        if itemLink then
            -- NOTE: do not guard this call with `GetLootRollItemInfo and ...` —
            -- Lua's `and`/`or` collapse a multi-return call to a single value,
            -- which silently truncated every field after `texture` to nil.
            local texture, name, count, quality = GetLootRollItemInfo(rollID)
            if quality and quality >= 4 then
                local itemName = name or (GetItemInfo and GetItemInfo(itemLink)) or itemLink:match("%[(.-)%]")
                table.insert(tempLoot, { name = itemName, link = itemLink, texture = texture, count = count or 1, rollID = rollID })
            end
        end
    end

    if not CurrentLoot then CurrentLoot = {} end
    for k in pairs(CurrentLoot) do CurrentLoot[k] = nil end
    for _, data in ipairs(tempLoot) do table.insert(CurrentLoot, data) end

    if #CurrentLoot > 0 and ((RollMenuFrame and RollMenuFrame:IsShown()) or (DB and DB.AutoOpenLootWindow)) then
        UpdateLootList()
    end
end

local e = CreateFrame("Frame")
e:RegisterEvent("START_LOOT_ROLL")
e:RegisterEvent("TRADE_SHOW")
e:SetScript("OnEvent", function(_, event)
    if event == "TRADE_SHOW" then
        AutoPlaceTradeHistoryItem()
    elseif event == "START_LOOT_ROLL" then
        -- Defer by one frame: GetActiveLootRollIDs() can briefly be empty
        -- at the exact instant START_LOOT_ROLL fires, before the roll is
        -- fully registered client-side.
        C_Timer.After(0, RefreshActiveLootRolls)
    end
end)