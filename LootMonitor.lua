CurrentLoot = {}

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

    local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
    local bindType = itemID and select(14, GetItemInfo(itemID))
    if bindType == 4 or bindType == 5 or bindType == 7 or bindType == 8 or bindType == 9 then
        return false
    end

    if bindType == 1 then
        return HasTradeTimeRemaining(itemLink)
    end

    return true
end

local function IsBagItemTradable(info)
    if not info or not info.hyperlink then
        return false
    end

    if info.isQuestItem or info.isBound or info.isSoulbound then
        return false
    end

    return IsItemLinkTradable(info.hyperlink)
end

local function RefreshLootWindow()
    if type(CreateRollMenu) == "function" then
        CreateRollMenu()
    else
        print("|cffff0000DKP Error:|r Main tracker function 'CreateRollMenu' not found. Ensure it is not 'local'.")
        return
    end

    if RollMenuFrame then
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

    CurrentLoot = {}
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

local e = CreateFrame("Frame")
e:RegisterEvent("LOOT_OPENED")
e:SetScript("OnEvent", function()
    local tempLoot = {}
    for i = 1, GetNumLootItems() do
        local texture, name, _, _, rarity = GetLootSlotInfo(i)
        local link = GetLootSlotLink(i)
        if rarity and rarity >= 4 and name and link and IsItemLinkTradable(link) then
            if tempLoot[name] then
                tempLoot[name].count = tempLoot[name].count + 1
            else
                tempLoot[name] = { name = name, link = link, texture = texture, count = 1 }
            end
        end
    end
    CurrentLoot = {}
    for _, data in pairs(tempLoot) do table.insert(CurrentLoot, data) end
    if #CurrentLoot > 0 then UpdateLootList() end
end)