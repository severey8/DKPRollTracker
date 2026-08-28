-- Lightweight view shown to everyone except whoever clicked "Start Roll" in
-- the admin window (they already see the same info live in their own copy).
-- Shows the item currently being rolled on, DKP/MS/OS/DE/Pass buttons, and a
-- persistent local history of every item processed plus how the addon-comm
-- broadcasts from the admin window were resolved.

local ADDON_PREFIX = "DKPRollTrk"
local SEP = "\029" -- unlikely to ever appear inside an item hyperlink or name

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
end

local function GetSyncChannel()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

function BroadcastRollStart(item)
    if not item or not item.link then return end
    local channel = GetSyncChannel()
    if not channel then return end
    local message = table.concat({ "START", tostring(item.count or 1), tostring(item.texture or ""), item.link }, SEP)
    C_ChatInfo.SendAddonMessage(ADDON_PREFIX, message, channel)
end

-- winners: array of { name = "PlayerName", rollType = "DKP"/"MS"/"OS"/"DE" }
function BroadcastRollAward(item, winners)
    if not item or not item.link then return end
    local channel = GetSyncChannel()
    if not channel then return end
    local winnerParts = {}
    for _, w in ipairs(winners or {}) do
        table.insert(winnerParts, w.name .. ":" .. w.rollType)
    end
    local message = table.concat({ "AWARD", item.link, tostring(item.texture or ""), table.concat(winnerParts, ",") }, SEP)
    C_ChatInfo.SendAddonMessage(ADDON_PREFIX, message, channel)
end

function GetMyRollHistory()
    DKPRollTrackerDB = DKPRollTrackerDB or {}
    DKPRollTrackerDB.MyRollHistory = DKPRollTrackerDB.MyRollHistory or {}
    return DKPRollTrackerDB.MyRollHistory
end

local memberFrame = nil
local pendingRoll = nil -- { link, texture, count, myRoll }
local currentLink = nil -- backs the item tooltip hitbox

local function SaveMemberWindowPosition(frame)
    if not DKPRollTrackerDB then return end
    local point, _, relativePoint, x, y = frame:GetPoint()
    if point and relativePoint and x and y then
        DKPRollTrackerDB.MemberWindowPosition = { point = point, relativePoint = relativePoint, x = x, y = y }
    end
end

function SetMemberButtonsShown(shown)
    if not memberFrame then return end
    for _, b in pairs(memberFrame.buttons) do
        b:SetShown(shown)
    end
end

function ResetMemberViewToIdle()
    if not memberFrame then return end
    memberFrame.icon:Hide()
    memberFrame.itemText:SetText("Waiting for the loot master to start a roll...")
    memberFrame.statusText:Hide()
    SetMemberButtonsShown(false)
end

function FormatWinnersText(winnersStr)
    if not winnersStr or winnersStr == "" then
        return "No winner recorded"
    end
    local parts = {}
    for entry in winnersStr:gmatch("[^,]+") do
        local name, rollType = entry:match("^(.-):(.+)$")
        if name and rollType then
            table.insert(parts, string.format("%s (%s)", name, rollType))
        end
    end
    return #parts > 0 and table.concat(parts, ", ") or "No winner recorded"
end

function RefreshMemberHistoryList()
    if not memberFrame then return end
    local history = GetMyRollHistory()
    local scrollChild = memberFrame.historyScrollChild
    local rows = memberFrame.historyRows

    for _, row in ipairs(rows) do
        row:Hide()
    end

    local y = 0
    for i, entry in ipairs(history) do
        local row = rows[i] or CreateFrame("Frame", nil, scrollChild)
        row:SetSize(320, 36)
        row:SetPoint("TOPLEFT", 0, -y)
        row:Show()

        row.icon = row.icon or row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(28, 28)
        row.icon:SetPoint("LEFT", 0, 0)
        row.icon:SetTexture(entry.texture or 134400)

        row.itemText = row.itemText or row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.itemText:SetPoint("LEFT", row.icon, "RIGHT", 8, 6)
        row.itemText:SetWidth(230)
        row.itemText:SetJustifyH("LEFT")
        row.itemText:SetText(entry.link or "")

        row.detailText = row.detailText or row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.detailText:SetPoint("TOPLEFT", row.itemText, "BOTTOMLEFT", 0, -2)
        row.detailText:SetWidth(280)
        row.detailText:SetJustifyH("LEFT")
        row.detailText:SetText(string.format("You: %s  |  Won by: %s", entry.myRoll or "-", entry.winners or "?"))

        row:SetScript("OnEnter", function(self)
            if not entry.link then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(entry.link)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        rows[i] = row
        y = y + 40
    end

    scrollChild:SetHeight(math.max(1, y))
end

local function CreateMemberRollFrame()
    if memberFrame then return memberFrame end

    local f = CreateFrame("Frame", "DKPMemberRollFrame", UIParent, "BackdropTemplate")
    f:SetSize(380, 430)
    local pos = DKPRollTrackerDB and DKPRollTrackerDB.MemberWindowPosition
    if pos then
        f:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end
    f:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0, 0, 0, 0.9)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetFrameStrata("HIGH")
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        SaveMemberWindowPosition(f)
    end)

    local closeX = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", -2, -2)
    closeX:SetScript("OnClick", function() f:Hide() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Roll For Loot")

    -- Current item, with a hover hitbox for the tooltip
    f.itemFrame = CreateFrame("Frame", nil, f)
    f.itemFrame:SetPoint("TOPLEFT", 20, -40)
    f.itemFrame:SetSize(320, 36)
    f.itemFrame:EnableMouse(true)
    f.itemFrame:SetScript("OnEnter", function(self)
        if not currentLink then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(currentLink)
        GameTooltip:Show()
    end)
    f.itemFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.icon = f.itemFrame:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(36, 36)
    f.icon:SetPoint("LEFT", 0, 0)
    f.icon:Hide()

    f.itemText = f.itemFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.itemText:SetPoint("LEFT", f.icon, "RIGHT", 10, 0)
    f.itemText:SetWidth(270)
    f.itemText:SetJustifyH("LEFT")
    f.itemText:SetText("Waiting for the loot master to start a roll...")

    f.statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.statusText:SetPoint("TOPLEFT", f.itemFrame, "BOTTOMLEFT", 0, -8)
    f.statusText:SetWidth(320)
    f.statusText:SetJustifyH("LEFT")
    f.statusText:Hide()

    f.buttons = {}
    local defs = { "DKP", "MS", "OS", "DE", "Pass" }
    local x = 20
    for _, key in ipairs(defs) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(64, 22)
        b:SetPoint("TOPLEFT", x, -84)
        b:SetText(key)
        b:SetScript("OnClick", function()
            HandleMemberRollChoice(key)
        end)
        b:Hide()
        f.buttons[key] = b
        x = x + 68
    end

    local historyTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    historyTitle:SetPoint("TOPLEFT", 20, -118)
    historyTitle:SetText("Loot History")

    local historyScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    historyScroll:SetPoint("TOPLEFT", 20, -138)
    historyScroll:SetSize(330, 230)
    f.historyScrollChild = CreateFrame("Frame", nil, historyScroll)
    f.historyScrollChild:SetSize(330, 1)
    historyScroll:SetScrollChild(f.historyScrollChild)
    f.historyRows = {}

    local clearHistoryBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearHistoryBtn:SetSize(120, 22)
    clearHistoryBtn:SetPoint("BOTTOMLEFT", 20, 15)
    clearHistoryBtn:SetText("Clear History")
    clearHistoryBtn:SetScript("OnClick", function()
        DKPRollTrackerDB = DKPRollTrackerDB or {}
        DKPRollTrackerDB.MyRollHistory = {}
        RefreshMemberHistoryList()
    end)

    memberFrame = f
    RefreshMemberHistoryList()
    return f
end

function StartMemberRoll(link, count, texture)
    if not link then return end
    pendingRoll = { link = link, count = count, texture = texture, myRoll = nil }
    currentLink = link

    local f = CreateMemberRollFrame()
    f.icon:SetTexture(texture or 134400)
    f.icon:Show()
    local countText = (count and count > 1) and (" x" .. count) or ""
    f.itemText:SetText(link .. countText)
    f.statusText:Hide()
    SetMemberButtonsShown(true)
    f:Show()
end

StaticPopupDialogs["CONFIRM_DKP_ROLL_MEMBER"] = {
    text = "Are you sure you want to roll DKP (1-100)? This will spend your points if you win.",
    button1 = "Yes, Roll",
    button2 = "Cancel",
    OnAccept = function()
        RandomRoll(1, 100)
        CommitMemberRollChoice("DKP")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function CommitMemberRollChoice(key)
    if not memberFrame or not pendingRoll then return end
    pendingRoll.myRoll = key
    SetMemberButtonsShown(false)
    local statusText = (key == "Pass")
        and "You passed on this item. Awaiting loot master to award loot."
        or string.format("You rolled %s. Awaiting loot master to award loot.", key)
    memberFrame.statusText:SetText(statusText)
    memberFrame.statusText:Show()
end

function HandleMemberRollChoice(key)
    if not memberFrame or not pendingRoll then return end

    if key == "DKP" then
        StaticPopup_Show("CONFIRM_DKP_ROLL_MEMBER")
        return -- CommitMemberRollChoice runs from the popup's OnAccept
    end

    local rolls = { MS = 99, OS = 98, DE = 97 }
    if rolls[key] then
        RandomRoll(1, rolls[key])
    end

    CommitMemberRollChoice(key)
end

function HandleAwardReceived(link, texture, winnersStr)
    local history = GetMyRollHistory()
    table.insert(history, 1, {
        link = link,
        texture = texture,
        myRoll = (pendingRoll and pendingRoll.link == link) and pendingRoll.myRoll or nil,
        winners = FormatWinnersText(winnersStr),
    })

    CreateMemberRollFrame() -- ensure it exists so the history stays current even if closed
    RefreshMemberHistoryList()

    if pendingRoll and pendingRoll.link == link then
        pendingRoll = nil
        currentLink = nil
    end
    ResetMemberViewToIdle()
end

local function OnAddonMessage(prefix, message, _, sender)
    if prefix ~= ADDON_PREFIX then return end

    -- Everyone gets the popup regardless of raid rank -- leaders/assistants
    -- roll on loot too and usually don't have the admin window open. Only
    -- the person who actually clicked "Start Roll"/"Award Winners" is
    -- excluded, since they already see the same info live in their own
    -- admin window.
    local senderShort = sender and (sender:match("^(.-)-") or sender)
    if senderShort == UnitName("player") then return end

    local msgType, a, b, c = strsplit(SEP, message)
    if msgType == "START" then
        StartMemberRoll(c, tonumber(a), tonumber(b))
    elseif msgType == "AWARD" then
        HandleAwardReceived(a, tonumber(b), c)
    end
end

local commFrame = CreateFrame("Frame")
commFrame:RegisterEvent("CHAT_MSG_ADDON")
commFrame:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
    OnAddonMessage(prefix, message, channel, sender)
end)

-- Manual tests, no second account or live roll needed.
SLASH_DKPMEMBERTEST1 = "/dkpmembertest"
SlashCmdList["DKPMEMBERTEST"] = function()
    StartMemberRoll("|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r", 1, 135057)
end

SLASH_DKPAWARDTEST1 = "/dkpawardtest"
SlashCmdList["DKPAWARDTEST"] = function()
    local link = (pendingRoll and pendingRoll.link) or "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r"
    HandleAwardReceived(link, 135057, "TestWinner:DKP")
end

SLASH_DKPLOOT1 = "/dkploot"
SlashCmdList["DKPLOOT"] = function()
    CreateMemberRollFrame():Show()
end
