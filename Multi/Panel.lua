local _, Addon = ...
local BW = Addon.Multi
local AH = C_AuctionHouse
local wheel = CreateFrame("Button", "BuyWheelMMouseButton", UIParent)
wheel:RegisterForClicks("AnyDown")
wheel:SetScript("OnClick", function() BW:Buy() end)

local bindings = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
bindings:SetAttribute("_onstate-combat", [[ if newstate == "combat" then self:ClearBindings() end ]])
RegisterStateDriver(bindings, "combat", "[combat] combat; peace")

local muted = {}
local function muteScroll(frame)
    if frame and frame.IsMouseWheelEnabled and frame:IsMouseWheelEnabled() then
        frame:EnableMouseWheel(false)
        muted[#muted + 1] = frame
    end
end

function BW:BindWheel(enable)
    for _, frame in ipairs(muted) do frame:EnableMouseWheel(true) end
    wipe(muted)
    if InCombatLockdown() then return end
    ClearOverrideBindings(bindings)
    if not enable then return end
    SetOverrideBindingClick(bindings, true, "MOUSEWHEELUP", wheel:GetName())
    SetOverrideBindingClick(bindings, true, "MOUSEWHEELDOWN", wheel:GetName())
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local chat = _G["ChatFrame" .. i]
        muteScroll(chat)
        if chat then muteScroll(chat.ScrollBar) end
    end
end

local function money(copper)
    local whole = math.floor(copper)
    local fraction = copper - whole
    local gold = math.floor(whole / 10000)
    local silver = math.floor(whole / 100) % 100
    if fraction > 0 then
        return ("%d g  %02d s  %.2f c"):format(gold, silver, whole % 100 + fraction)
    end
    return ("%d g  %02d s  %02d c"):format(gold, silver, whole % 100)
end

local function itemProfitText(counts)
    if counts and (counts.profitUnits or 0) == 0 and (counts.profitUnknownUnits or 0) > 0 then return "–" end
    local value = counts and counts.estimatedProfit or 0
    if value == 0 then return "0c" end
    local amount = value < 0 and -value or value
    local text = amount >= 10000 and ("%.2fg"):format(amount / 10000)
        or amount >= 100 and ("%.2fs"):format(amount / 100) or ("%.2fc"):format(amount)
    return (value < 0 and "|cffff6464-" or "|cff60eb80+") .. text .. "|r"
end

local function currentMoney(copper)
    local hundredths = math.floor(copper * 100 + 0.5)
    local whole = math.floor(hundredths / 100)
    local gold = math.floor(whole / 10000)
    local silver = math.floor(whole / 100) % 100
    local remainder = whole % 100
    local fraction = hundredths % 100
    if fraction > 0 then
        return ("%02d, %02d, %02d.%02d"):format(gold, silver, remainder, fraction)
    end
    return ("%02d, %02d, %02d"):format(gold, silver, remainder)
end

local function compactMoney(copper)
    local whole = math.floor(copper)
    local gold, silver = math.floor(whole / 10000), math.floor(whole / 100) % 100
    local copperValue = whole % 100 + copper - whole
    local coins = copperValue % 1 == 0 and tostring(copperValue) or ("%.2f"):format(copperValue)
    if gold > 0 then return ("%dg %ds %sc"):format(gold, silver, coins) end
    if silver > 0 then return ("%ds %sc"):format(silver, coins) end
    return coins .. "c"
end

local function label(parent, text, font, x, y)
    local value = parent:CreateFontString(nil, "OVERLAY", font)
    value:SetPoint("TOPLEFT", x, y)
    value:SetJustifyH("LEFT")
    value:SetText(text)
    return value
end

local function button(parent, text, width, x, y, action)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetPoint("TOPLEFT", x, y)
    control:SetSize(width, 24)
    control:SetText(text)
    control:SetScript("OnClick", action)
    return control
end

local function edit(parent, width, x, y, maxLetters)
    local control = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    control:SetPoint("TOPLEFT", x, y)
    control:SetSize(width, 24)
    control:SetMaxLetters(maxLetters)
    control:SetAutoFocus(false)
    control:SetScript("OnEscapePressed", control.ClearFocus)
    return control
end

local function moneyInput(parent, title, x, amount, y)
    label(parent, title, "GameFontNormal", x, y)
    local gold = edit(parent, 48, x + 4, y - 32, 9)
    local silver = edit(parent, 48, x + 61, y - 32, 2)
    local copper = edit(parent, 48, x + 118, y - 32, 2)
    label(parent, "Gold", "GameFontDisableSmall", x + 4, y - 17)
    label(parent, "Silver", "GameFontDisableSmall", x + 61, y - 17)
    label(parent, "Copper", "GameFontDisableSmall", x + 118, y - 17)

    local boxes = { gold, silver, copper }
    for i, box in ipairs(boxes) do
        box:SetNumeric(true)
        box:SetJustifyH("CENTER")
        box:SetScript("OnEnterPressed", box.ClearFocus)
        box:SetScript("OnTabPressed", function(self)
            local step = IsShiftKeyDown() and -1 or 1
            local nextBox = boxes[i + step]
            self:ClearFocus()
            if nextBox then
                nextBox:SetFocus()
                nextBox:HighlightText()
            end
        end)
    end
    if amount then
        gold:SetText(tostring(math.floor(amount / 10000)))
        silver:SetText(("%02d"):format(math.floor(amount / 100) % 100))
        copper:SetText(("%02d"):format(amount % 100))
    end

    local function value()
        local g, s, c = gold:GetText(), silver:GetText(), copper:GetText()
        if g == "" and s == "" and c == "" then return end
        return (tonumber(g) or 0) * 10000 + (tonumber(s) or 0) * 100 + (tonumber(c) or 0)
    end
    return boxes, value
end

-- Whole-gold input on one row: returns the same (boxes, value) pair as moneyInput,
-- with value() in copper. Only the gold part of a saved amount is shown.
local function goldInput(parent, title, x, amount, y)
    label(parent, title, "GameFontNormal", x, y - 6)
    local box = edit(parent, 72, x + 132, y, 9)
    box:SetNumeric(true)
    box:SetJustifyH("CENTER")
    box:SetScript("OnEnterPressed", box.ClearFocus)
    label(parent, "g", "GameFontHighlight", x + 210, y - 6)
    if amount then box:SetText(tostring(math.floor(amount / 10000))) end
    local function value()
        local text = box:GetText()
        if text == "" then return end
        return (tonumber(text) or 0) * 10000
    end
    return { box }, value
end

local function caption(parent, title, x, y)
    label(parent, title, "GameFontNormal", x, y)
    return label(parent, "–", "GameFontHighlight", x, y - 19)
end

local ROWS = 11
local function itemText(key, info)
    local name = info.itemName
    if (key.itemSuffix or 0) ~= 0 then name = name .. "   ·   Variant " .. key.itemSuffix end
    if (key.itemLevel or 0) > 0 then name = name .. "   ·   Level " .. key.itemLevel end
    return name
end

local function buildPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:Hide()
    panel:SetPoint("TOPLEFT", 18, -68)
    panel:SetPoint("BOTTOMRIGHT", -18, 31)
    panel:SetFrameLevel(parent:GetFrameLevel() + 8)

    local searchPane = CreateFrame("Frame", nil, panel)
    searchPane:SetAllPoints(panel)
    local split = panel:CreateTexture(nil, "ARTWORK")
    split:SetPoint("TOPLEFT", 285, -4)
    split:SetPoint("BOTTOMLEFT", 285, 11)
    split:SetWidth(1)
    split:SetColorTexture(0.65, 0.56, 0.38, 0.31)

    label(searchPane, "Favorites · normal", "GameFontNormalLarge", 9, 0)
    local searchStatus = label(searchPane, "", "GameFontDisableSmall", 9, -32)
    local maxPriceBoxes, budgetBoxes
    local syncingLimits = false
    function panel:LoadWatchLimit()
        if not BW.target or not maxPriceBoxes then return end
        self.displayedTargetID = BW.target.id
        local entry = BW:WatchEntry(BW.target.key)
        local amount = entry and entry.maxPrice or BW.maxPrice or 0
        syncingLimits = true
        maxPriceBoxes[1]:SetText(tostring(math.floor(amount / 10000)))
        maxPriceBoxes[2]:SetText(("%02d"):format(math.floor(amount / 100) % 100))
        maxPriceBoxes[3]:SetText(("%02d"):format(amount % 100))
        syncingLimits = false
        BW:Limits(amount, BW.budget)
    end

    local rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, searchPane)
        row:SetPoint("TOPLEFT", 8, -28 - (i - 1) * 28)
        row:SetSize(258, 26)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetNormalFontObject("GameFontHighlightSmall")
        row:SetDisabledFontObject("GameFontDisableSmall")
        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("LEFT", 30, 6)
        title:SetWidth(224)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        row:SetFontString(title)
        local reference = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        reference:SetPoint("RIGHT", -4, -7)
        reference:SetWidth(76)
        reference:SetJustifyH("RIGHT")
        reference:SetWordWrap(false)
        row.normalPrice = reference
        local counts = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        counts:SetPoint("LEFT", 30, -7)
        counts:SetWidth(46)
        counts:SetJustifyH("LEFT")
        counts:SetWordWrap(false)
        row.counts = counts
        -- Average price paid per unit.
        local ratio = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ratio:SetPoint("LEFT", 78, -7)
        ratio:SetWidth(52)
        ratio:SetJustifyH("LEFT")
        ratio:SetWordWrap(false)
        row.ratio = ratio
        local profit = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        profit:SetPoint("LEFT", 132, -7)
        profit:SetWidth(46)
        profit:SetJustifyH("LEFT")
        profit:SetWordWrap(false)
        row.profit = profit
        row:SetScript("OnClick", function(self)
            BW:Select(self.key)
            panel:LoadWatchLimit()
            panel:RefreshBuyWheelM()
        end)
        local selected = row:CreateTexture(nil, "BACKGROUND")
        selected:SetAllPoints(row)
        selected:SetColorTexture(0.65, 0.56, 0.38, 0.25)
        selected:Hide()
        row.selected = selected
        local watch = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        watch:SetPoint("LEFT", 0, 0)
        watch:SetSize(24, 24)
        watch:SetScript("OnClick", function(self)
            BW:SetWatched(row.key, self:GetChecked())
            panel:RefreshBuyWheelM()
        end)
        row.watch = watch
        row:SetScript("OnEnter", function(self)
            local entry = BW:WatchEntry(self.key)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local info = AH.GetItemKeyInfo(self.key)
            GameTooltip:AddLine(info and info.itemName and itemText(self.key, info) or "Favorite")
            GameTooltip:AddLine("Click to edit this item's price limit.")
            GameTooltip:AddLine("Check the box to watch this item.", 1, 1, 1)
            local stats = BW.purchaseStats
            local counts = stats and stats.items and stats.items[BW:WatchID(self.key)]
            GameTooltip:AddLine(("Bought/Missed: %d/%d items since Reset"):format(
                counts and counts.bought or 0, counts and counts.missed or 0), 1, 1, 1)
            GameTooltip:AddLine("Estimated profit since Reset: " .. itemProfitText(counts), 1, 1, 1)
            local normalInfo = BW:NormalInfo(BW:WatchID(self.key))
            if normalInfo then GameTooltip:AddLine("Normal price: " .. normalInfo, 1, 1, 1) end
            GameTooltip:AddLine("Learned value at purchase minus actual cost, including tracked bait corrections. Before fees/deposits; purchases without a normal price are excluded.", 1, 1, 1, true)
            if counts and (counts.profitUnknownUnits or 0) > 0 then
                GameTooltip:AddLine(("%d purchased items without a normal price excluded"):format(counts.profitUnknownUnits), 1, 1, 1)
            end
            GameTooltip:AddLine("Max buy price: " .. money(entry and entry.maxPrice or 0), 1, 1, 1)
            local learned = BW.db.learnedPrices and BW.db.learnedPrices[BW:WatchID(self.key)]
            if learned then
                GameTooltip:AddLine("Learned normal price: " .. money(learned.normalPrice), 1, 1, 1)
                GameTooltip:AddLine(("%d samples%s"):format(learned.samples or 0,
                    learned.live and " · live 10-minute median" or " · manual learning"), 1, 1, 1)
                GameTooltip:AddLine(("Buy limit: %.1f%% of normal"):format((entry and entry.maxPrice or 0) * 100 / learned.normalPrice), 1, 1, 1)
            else
                GameTooltip:AddLine("Normal price appears after learning or 10 valid live samples.", 1, 1, 1, true)
            end
            GameTooltip:AddLine("The list shows normal prices. Live updates use existing watching replies; buy limits are edited separately.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = row
    end

    local previous = button(searchPane, "‹", 34, 9, -343, function() panel.page = panel.page - 1 end)
    local nextPage = button(searchPane, "›", 34, 47, -343, function() panel.page = panel.page + 1 end)
    local more = button(searchPane, "Load more", 72, 144, -343, function() BW:LoadFavorites(true) end)
    local pageText = label(searchPane, "", "GameFontDisableSmall", 91, -351)
    StaticPopupDialogs["BUYWHEEL_RESET_LEARNED"] = {
        text = "BuyWheelM: delete ALL learned normal prices, depth measurements and the buy limits derived from them? Watch checkboxes stay. Run Start Learning Prices again before watching.",
        button1 = YES, button2 = NO,
        OnAccept = function() BW:ResetLearned() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    local resetLearned = button(searchPane, "Reset learned", 84, 134, -343, function()
        StaticPopup_Show("BUYWHEEL_RESET_LEARNED")
    end)
    resetLearned:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Reset everything learned")
        GameTooltip:AddLine("Deletes all learned normal prices, depth measurements and the buy limits derived from them, so the next Start Learning Prices is the only data in use. Watch checkboxes stay. Not possible while watching or learning.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    resetLearned:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.page = 1

    local history = CreateFrame("Frame", nil, panel)
    history:SetAllPoints(panel)
    history:Hide()
    label(history, "Purchase history", "GameFontNormalLarge", 9, 0)
    local historyToggle = button(panel, "Purchases", 90, 173, -1, function(self)
        local show = not history:IsShown()
        history:SetShown(show)
        searchPane:SetShown(not show)
        self:SetText(show and "Favorites" or "Purchases")
        panel:RefreshBuyWheelM()
    end)
    historyToggle:SetFrameLevel(history:GetFrameLevel() + 2)
    local avgUnit = label(history, "", "GameFontHighlight", 9, -32)
    local purchaseTotal = label(history, "", "GameFontHighlightSmall", 9, -51)
    local purchaseRows = {}
    local historyPage = 1
    for i = 1, 6 do
        local y = -82 - (i - 1) * 42
        local name = label(history, "", "GameFontNormal", 9, y)
        name:SetWidth(195)
        name:SetWordWrap(false)
        local when = label(history, "", "GameFontDisableSmall", 210, y - 2)
        when:SetWidth(60)
        when:SetJustifyH("RIGHT")
        local price = label(history, "", "GameFontHighlightSmall", 9, y - 17)
        purchaseRows[i] = { name = name, price = price, when = when }
    end
    local historyPrev = button(history, "‹", 34, 9, -343, function() historyPage = historyPage - 1 end)
    local historyNext = button(history, "›", 34, 47, -343, function() historyPage = historyPage + 1 end)
    local historyPosition = label(history, "", "GameFontDisableSmall", 91, -351)
    local historyReset = button(history, "Reset", 60, 156, -343, function()
        BW:ResetPurchases()
        historyPage = 1
        panel:RefreshBuyWheelM()
    end)
    historyReset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Reset purchases")
        GameTooltip:AddLine("Clears purchase history, spending totals, purchase-rate comparisons and Bought/Missed counters for this tab. The current run's budget is unchanged.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    historyReset:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Right column, top to bottom in the order of use:
    --   learn (0) · budget (-36) · options (-68..-112) · selected item (-130..-236)
    --   · statistics (-246..-306) · status (-312) · Start/STOP (-343).
    local x = 311
    local function rule(y)
        local line = panel:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", x - 8, y)
        line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, y)
        line:SetHeight(1)
        line:SetColorTexture(0.65, 0.56, 0.38, 0.3)
    end
    rule(-62)
    rule(-134)

    local target = label(panel, "Select a favorite.", "GameFontHighlightLarge", x, -138)
    target:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -138)
    target:SetJustifyV("TOP")
    target:SetWordWrap(false)
    local nowPrice = label(panel, "–", "GameFontHighlightLarge", x, -157)
    -- Current price as a share of the learned normal price (80% = 20% below normal).
    local priceRatio = label(panel, "", "GameFontHighlightLarge", x + 132, -157)
    local refresh = label(panel, "Refresh: –", "GameFontHighlightSmall", x + 240, -161)
    -- Right-aligned to the column edge so it no longer floats beside the price.
    refresh:ClearAllPoints()
    refresh:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -163)
    refresh:SetJustifyH("RIGHT")

    local maxPrice, budget
    maxPriceBoxes, maxPrice = moneyInput(panel, "Max buy · selected item", x, BW.db.maxPrice, -180)
    -- Same rows as the Max buy block: title, small caption row, then the value
    -- level with the input boxes.
    label(panel, "Learned normal price", "GameFontNormal", x + 188, -180)
    local normalSamples = label(panel, "", "GameFontDisableSmall", x + 188, -198)
    local normalPrice = label(panel, "–", "GameFontHighlight", x + 188, -218)
    -- Small grey lines below the profit figure; the profit line itself is made by Statistics.lua.
    local spendLine = label(panel, "", "GameFontDisableSmall", x, -281)
    local detail = label(panel, "", "GameFontDisableSmall", x, -295)
    -- Auto-bait status, right-aligned on the spending line.
    -- Last posted bait (auto or button), right-aligned on the detail line.
    local lastBait = label(panel, "", "GameFontDisableSmall", x + 200, -295)
    lastBait:ClearAllPoints()
    lastBait:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -295)
    lastBait:SetWidth(150)
    lastBait:SetJustifyH("RIGHT")
    local baitStatus = label(panel, "", "GameFontDisableSmall", x + 200, -281)
    baitStatus:ClearAllPoints()
    baitStatus:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -281)
    baitStatus:SetJustifyH("RIGHT")

    -- Keep session controls fixed at the bottom of the right column. The
    -- favorites list retains all eleven rows, even while a session is active.
    local controlsBackground = panel:CreateTexture(nil, "BACKGROUND")
    controlsBackground:SetPoint("TOPLEFT", x - 8, -243)
    controlsBackground:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", -4, -371)
    controlsBackground:SetColorTexture(0.08, 0.07, 0.05, 0.8)
    local controlsDivider = panel:CreateTexture(nil, "ARTWORK")
    controlsDivider:SetPoint("TOPLEFT", x - 8, -243)
    controlsDivider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -243)
    controlsDivider:SetHeight(1)
    controlsDivider:SetColorTexture(0.65, 0.56, 0.38, 0.5)
    local state = label(panel, "", "GameFontHighlightSmall", x, -312)
    state:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -312)
    state:SetHeight(26)
    state:SetWordWrap(true)
    state:SetJustifyV("TOP")

    local watchSettings = CreateFrame("Frame", nil, panel)
    watchSettings:SetAllPoints(panel)

    budgetBoxes, budget = goldInput(watchSettings, "Shared budget", x, BW.db.budget, -34)
    local function limits()
        if syncingLimits then return end
        BW:Limits(maxPrice(), budget())
    end
    for _, boxes in ipairs({ maxPriceBoxes, budgetBoxes }) do
        for _, box in ipairs(boxes) do box:SetScript("OnTextChanged", limits) end
    end
    limits()

    local liveLimit = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    liveLimit:SetPoint("TOPLEFT", x + 238, -36)
    liveLimit:SetSize(20, 20)
    liveLimit:SetChecked(BW.db.liveLimit == true)
    local liveLimitLabel = label(panel, "Limit live", "GameFontHighlightSmall", 0, 0)
    liveLimitLabel:ClearAllPoints()
    liveLimitLabel:SetPoint("LEFT", liveLimit, "RIGHT", 2, 0)
    liveLimit:SetScript("OnClick", function(self) BW:SetLiveLimit(self:GetChecked()) end)
    liveLimit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Limit live")
        GameTooltip:AddLine("While watching, every live update of an item's normal price also sets its max buy price to the Max buy % (field in the learning row) of that normal price, for all watched items.", 1, 1, 1, true)
        GameTooltip:AddLine("Off: limits only change through Start learning or by hand. Press STOP before changing this option.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    liveLimit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local bait = CreateFrame("CheckButton", nil, watchSettings, "UICheckButtonTemplate")
    bait:SetPoint("TOPLEFT", x, -72)
    bait:SetSize(20, 20)
    bait:SetChecked(BW.db.leaveBait == true)
    local baitLabel = label(watchSettings, "Leave Bait", "GameFontHighlight", 0, 0)
    baitLabel:ClearAllPoints()
    baitLabel:SetPoint("LEFT", bait, "RIGHT", 3, 0)
    bait:SetScript("OnClick", function(self) BW:SetLeaveBait(self:GetChecked()) end)
    bait:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Leave Bait")
        GameTooltip:AddLine("Leaves one item at the lowest price. For indivisible stacks, leaves the cheapest auction.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    bait:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Depth queries per minute (0 = off): how often the watched item with the oldest
    -- depth measurement gets a detail query for its normal price.
    label(watchSettings, "Depth/min", "GameFontNormalSmall", x + 150, -76)
    local depthRate = edit(watchSettings, 28, x + 214, -70, 1)
    depthRate:SetNumeric(true)
    depthRate:SetText(tostring(BW:DepthRate()))
    depthRate:SetScript("OnTextChanged", function(self, userInput)
        if userInput then BW:SetDepthRate(self:GetText()) end
    end)
    depthRate:SetScript("OnEditFocusLost", function(self) self:SetText(tostring(BW:DepthRate())) end)
    depthRate:SetScript("OnEnterPressed", depthRate.ClearFocus)
    depthRate:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Depth measurements per minute (0 = off)")
        GameTooltip:AddLine("While watching, one commodity at a time gets a detail query to measure its price depth (price at which the first 10% of the supply, at least 20 units, is reached). Never sent while a purchase, bait or offer is pending. One query costs about one scan cycle. Listings loaded for purchases and SellWheel count for free.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    depthRate:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Auto-bait row: checkbox, baits per minute (1-10) and bait price as a percent
    -- of the learned normal price.
    local autoBait = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    autoBait:SetPoint("TOPLEFT", x, -104)
    autoBait:SetSize(20, 20)
    autoBait:SetChecked(BW.db.autoBait == true)
    local autoBaitLabel = label(panel, "Auto-Bait", "GameFontHighlight", 0, 0)
    autoBaitLabel:ClearAllPoints()
    autoBaitLabel:SetPoint("LEFT", autoBait, "RIGHT", 3, 0)
    autoBait:SetScript("OnClick", function(self) BW:SetAutoBait(self:GetChecked()) end)
    autoBait:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Auto-Bait")
        GameTooltip:AddLine("While watching, posts one bait of a random watched item from your bags at the set rate and price. Needs a mouse-wheel step (never a timer) and only happens when nothing is buyable.", 1, 1, 1, true)
        GameTooltip:AddLine("Only in a quiet market: no item under its limit or clearly below its normal price. After activity it waits a random time so several users do not bait at once. One own bait per item.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    autoBait:SetScript("OnLeave", function() GameTooltip:Hide() end)
    label(panel, "per min", "GameFontNormalSmall", x + 134, -108)
    local baitRate = edit(panel, 30, x + 96, -102, 2)
    baitRate:SetNumeric(true)
    baitRate:SetText(tostring(BW:AutoBaitRate()))
    baitRate:SetScript("OnTextChanged", function(self, userInput)
        if userInput then BW:SetBaitsPerMinute(self:GetText()) end
    end)
    baitRate:SetScript("OnEditFocusLost", function(self) self:SetText(tostring(BW:AutoBaitRate())) end)
    baitRate:SetScript("OnEnterPressed", baitRate.ClearFocus)
    label(panel, "price", "GameFontNormalSmall", x + 200, -108)
    local baitPercent = edit(panel, 40, x + 238, -102, 4)
    label(panel, "% of normal", "GameFontNormalSmall", x + 284, -108)
    baitPercent:SetNumeric(true)
    baitPercent:SetText(tostring(BW:AutoBaitPercent()))
    baitPercent:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Bait price in % of the Learned normal price")
        GameTooltip:AddLine("Each auto-bait is posted at this percentage of the item's learned normal price.", 1, 1, 1, true)
        local count, names = BW:BaitAboveLimitCount()
        if count > 0 then
            GameTooltip:AddLine(("Warning: for %d watched item(s) this is above their current max buy price, so you would not buy your own bait. The limits are per item (older learning or manual values); Start learning or Limit live sets them all to Max buy %%."):format(count), 1, 0.35, 0.3, true)
            for _, name in ipairs(names) do GameTooltip:AddLine("  " .. name, 1, 0.6, 0.55) end
            if count > #names then GameTooltip:AddLine(("  … and %d more"):format(count - #names), 1, 0.6, 0.55) end
        end
        GameTooltip:Show()
    end)
    baitPercent:SetScript("OnLeave", function() GameTooltip:Hide() end)
    baitPercent:SetScript("OnTextChanged", function(self, userInput)
        if userInput then BW:SetBaitPercent(self:GetText()) end
    end)
    baitPercent:SetScript("OnEditFocusLost", function(self) self:SetText(tostring(BW:AutoBaitPercent())) end)
    baitPercent:SetScript("OnEnterPressed", baitPercent.ClearFocus)

    label(panel, "Max buy", "GameFontNormal", x, -8)
    local learnPercent = edit(panel, 42, x + 62, -2, 3)
    label(panel, "% of normal price", "GameFontNormalSmall", x + 110, -9)
    learnPercent:SetNumeric(true)
    learnPercent:SetText(tostring(BW.db.learnPercent or 60))
    learnPercent:SetScript("OnEnterPressed", learnPercent.ClearFocus)
    -- The field is the single Max buy % for learning and for Limit live.
    learnPercent:SetScript("OnTextChanged", function(self, userInput)
        local value = tonumber(self:GetText())
        if userInput and value and value >= 1 and value <= 100 then BW.db.learnPercent = value end
    end)
    learnPercent:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Max buy price in % of the Learned normal price")
        GameTooltip:AddLine("Start learning sets each item's max buy price to this percentage of its learned normal price (median of the lowest listing prices). With Limit live the same percentage is applied on every live update.", 1, 1, 1, true)
        GameTooltip:AddLine("A bait posted above this percentage (see Auto-Bait) would be above your own buy limit and never be bought by you.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    learnPercent:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local function clearSessionFocus()
        for _, boxes in ipairs({ maxPriceBoxes, budgetBoxes }) do
            for _, box in ipairs(boxes) do box:ClearFocus() end
        end
        learnPercent:ClearFocus()
    end
    local learn = button(panel, "Start Learning Prices", 160, x + 262, -2, function()
        clearSessionFocus()
        BW:StartLearning(learnPercent:GetText())
        panel:RefreshBuyWheelM()
    end)
    learn:ClearAllPoints()
    learn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -2)
    learn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Learn normal prices for all favorites")
        GameTooltip:AddLine("Measures the market depth of every favorite (several detail queries each) and samples the lowest prices in between. No purchases.", 1, 1, 1, true)
        GameTooltip:AddLine("Ends by itself when the progress reaches 100%, then applies the buy percentage to each normal price. STOP is locked while it runs; closing this tab cancels without applying limits.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    learn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local go = button(panel, "Start watching", 150, x, -343, function()
        clearSessionFocus()
        BW:Start(false)
        panel:RefreshBuyWheelM()
    end)
    local stop = button(panel, "STOP", 80, x + 157, -343, function()
        BW:Stop()
        panel:RefreshBuyWheelM()
    end)
    local baitNow = button(panel, "Bait now", 110, x + 244, -343, function()
        clearSessionFocus()
        BW:ManualBait()
        panel:RefreshBuyWheelM()
    end)
    baitNow:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Bait now")
        GameTooltip:AddLine("Posts one bait of a random watched item from your bags at the Bait price % of its learned normal price. Works with or without watching, ignores the quiet-market rule, skips items with an own bait up (while watching).", 1, 1, 1, true)
        GameTooltip:AddLine("If the AH is busy, the first click reserves the slot and the next click posts.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    baitNow:SetScript("OnLeave", function() GameTooltip:Hide() end)

    function panel:RefreshBuyWheelM()
        if parent:GetAlpha() == 0 and (BW.running or BW.learning or BW.benchmark or BW.finding or BW.priceLookup) then BW:Stop() end
        BW:TickLearning()
        if BW.target and self.displayedTargetID ~= BW.target.id and not BW:PurchasePending() then
            self:LoadWatchLimit()
        end
        local posting = BW:PostStatus()
        local confirmingPost = BW:PostNeedsConfirmation()
        local waitingToPost = BW:PostWaiting()
        local busy = not Addon:CanUseMode(BW) or BW.running or BW.learning or BW.benchmark or BW:PurchasePending() or BW.finding or posting
        if BW.favoritesPending and not busy and not BW.priceLookup then
            BW:LoadFavorites()
            busy = busy or BW.finding
        end
        -- Sort a display copy; AH favorites and watch rotation retain their order.
        local result = {}
        local stats = BW.purchaseStats
        for index, item in ipairs(BW.favorites or {}) do
            local counts = stats and stats.items and stats.items[BW:WatchID(item.itemKey)]
            result[#result + 1] = { item = item, bought = counts and counts.bought or 0, index = index }
        end
        table.sort(result, function(a, b)
            if a.bought ~= b.bought then return a.bought > b.bought end
            return a.index < b.index
        end)
        local pages = math.max(1, math.ceil(#result / ROWS))
        panel.page = math.min(panel.page, pages)
        for i, row in ipairs(rows) do
            local display = result[(panel.page - 1) * ROWS + i]
            local item = display and display.item
            row:SetShown(item ~= nil)
            if item then
                local key = item.itemKey
                local info = AH.GetItemKeyInfo(key)
                row.key = key
                local entry = BW:WatchEntry(key)
                local learned = BW.db.learnedPrices and BW.db.learnedPrices[BW:WatchID(key)]
                row.normalPrice:SetText(learned and compactMoney(learned.normalPrice) or "–")
                local stats = BW.purchaseStats
                local counts = stats and stats.items and stats.items[BW:WatchID(key)]
                row.counts:SetText(("%d/%d"):format(counts and counts.bought or 0, counts and counts.missed or 0))
                local id, now = BW:WatchID(key), GetTime()
                if row.profitID ~= id or row.profitStats ~= stats or now - row.profitUpdatedAt >= 5 then
                    row.profit:SetText(itemProfitText(counts))
                    local bought = counts and counts.bought or 0
                    if bought > 0 and counts.cost then
                        -- Average price paid per unit; green when at or below the displayed normal price.
                        local average = counts.cost / bought
                        local text = average < 100 and (("%.1f"):format(average):gsub("%.0$", "") .. "c")
                            or compactMoney(math.floor(average + 0.5))
                        local normal = learned and learned.normalPrice
                        local color = normal and normal > 0 and average > normal and "|cffff6464" or "|cff60eb80"
                        row.ratio:SetText(color .. text .. "|r")
                    else
                        row.ratio:SetText("")
                    end
                    row.profitID, row.profitStats, row.profitUpdatedAt = id, stats, now
                end
                row.watch:SetChecked(entry and entry.enabled == true or false)
                row.watch:SetEnabled(not busy)
                local targetKey = BW.target and BW.target.key
                row.selected:SetShown(targetKey ~= nil and key.itemID == targetKey.itemID
                    and (key.itemLevel or 0) == (targetKey.itemLevel or 0)
                    and (key.itemSuffix or 0) == (targetKey.itemSuffix or 0)
                    and (key.battlePetSpeciesID or 0) == (targetKey.battlePetSpeciesID or 0))
                local text = info and info.itemName and (info.isCommodity and info.itemName or itemText(key, info))
                    or ("Item %d · loading …"):format(key.itemID)
                local _, normalState = BW:NormalInfo(id)
                if entry and entry.enabled and (entry.maxPrice or 0) <= 0 then
                    row.normalPrice:SetTextColor(1, 0.45, 0.3)
                elseif normalState == "old" then
                    row.normalPrice:SetTextColor(1, 0.3, 0.25) -- red: old
                elseif normalState == "rough" or normalState == "drift" then
                    row.normalPrice:SetTextColor(1, 0.82, 0.2) -- yellow: careful
                else
                    row.normalPrice:SetTextColor(0.75, 0.72, 0.65)
                end
                row:SetText(text)
                row:SetEnabled(not busy and info ~= nil and info.itemName ~= nil and info.itemName ~= "")
            end
        end
        searchStatus:SetText(BW.finding and "Loading favorites …"
            or BW.favoritesError and "Loading failed · reopen this tab."
            or BW.favoritesPending and "Waiting for favorites …"
            or (#result == 0 and "No favorites yet" or ("%d favorites"):format(#result)))
        searchStatus:SetShown(#result == 0)
        pageText:SetText(("%d / %d"):format(panel.page, pages))
        previous:SetEnabled(panel.page > 1)
        nextPage:SetEnabled(panel.page < pages)
        more:SetShown(BW.searchMore == true)
        more:SetEnabled(not busy and not BW.priceLookup)

        if history:IsShown() then
            local count = #BW.purchases
            local rowsPerPage = #purchaseRows
            local historyPages = math.max(1, math.ceil(count / rowsPerPage))
            historyPage = math.min(historyPage, historyPages)
            local baitCount = 0
            for _, entry in ipairs(BW.purchases) do
                if entry.bait then baitCount = baitCount + 1 end
            end
            avgUnit:SetText(("Successful purchases: %d  ·  Baits: %d"):format(count - baitCount, baitCount))
            local total = ("%d items bought · %s"):format(BW.unitsBought, money(BW.purchaseSpent))
            purchaseTotal:SetText(total)
            historyPosition:SetText(("%d / %d"):format(historyPage, historyPages))
            historyPrev:SetEnabled(historyPage > 1)
            historyNext:SetEnabled(historyPage < historyPages)
            for i, row in ipairs(purchaseRows) do
                local entry = BW.purchases[count - (historyPage - 1) * rowsPerPage - i + 1]
                if entry and entry.bait then
                    row.name:SetText(("|cffff6060Bait|r  %s"):format(entry.name))
                    row.price:SetText(("|cffff6060-%s|r"):format(money(-entry.cost)))
                else
                    row.name:SetText(entry and ("%d× %s"):format(entry.quantity, entry.name) or "")
                    row.price:SetText(entry and ("%s total  ·  %s / item"):format(money(entry.cost), money(entry.cost / entry.quantity)) or "")
                end
                row.when:SetText(entry and entry.time and date("%H:%M:%S", entry.time) or "")
            end
        end

        target:SetText(BW.target and itemText(BW.target.key, { itemName = BW.target.name }) or "Select a favorite.")
        local learned = BW.target and BW.db.learnedPrices and BW.db.learnedPrices[BW.target.id]
        normalPrice:SetText(learned and money(learned.normalPrice) or "–")
        -- Reliability shows as color only: white = fine, yellow = careful, red = old.
        normalSamples:SetText("")
        local _, targetState = learned and BW.target and BW:NormalInfo(BW.target.id)
        if targetState == "old" then normalPrice:SetTextColor(1, 0.3, 0.25)
        elseif targetState == "rough" or targetState == "drift" then normalPrice:SetTextColor(1, 0.82, 0.2)
        else normalPrice:SetTextColor(1, 1, 1) end
        baitNow:SetEnabled(not BW.learning and not BW.benchmark and not BW:PurchasePending())
        go:SetEnabled(not not BW:CanStart())
        learn:SetEnabled(not not BW:CanLearn())
        resetLearned:SetEnabled(not busy)
        resetLearned:SetShown(not BW.searchMore)
        -- The progress of a learning run sits on the button itself.
        local session = BW.learning
        if not session then learn:SetText("Start Learning Prices")
        elseif session.phase == "favorites" then learn:SetText("Loading …")
        else learn:SetText(("Learning %d%%"):format(math.floor(BW:LearningProgress(session) * 100))) end
        -- During a learning run STOP is greyed out so it cannot be hit by accident; the run
        -- ends by itself (closing the auction house cancels it).
        stop:SetEnabled(not BW.learning and not not (BW.running or BW.benchmark or BW.finding or confirmingPost or waitingToPost))
        bait:SetEnabled(not BW.learning and not BW.benchmark and not BW:PurchasePending())
        liveLimit:SetChecked(BW.db.liveLimit == true)
        liveLimit:SetEnabled(BW:CanChangeFastQuote())
        autoBait:SetChecked(BW.db.autoBait == true)
        if not baitRate:HasFocus() then baitRate:SetText(tostring(BW:AutoBaitRate())) end
        if not baitPercent:HasFocus() then baitPercent:SetText(tostring(BW:AutoBaitPercent())) end
        local baitCount, baitReason, baitRemaining = BW:AutoBaitStatus()
        local last = BW.lastBaitInfo
        lastBait:SetText(last and ("|cff66b3ffBait|r %s %s"):format(last.name or "?", compactMoney(last.price)) or "")
        -- Items whose bait price would exceed their own max buy price (cached, 1 s).
        local clock = GetTime()
        if not self.baitWarnAt or clock - self.baitWarnAt >= 1 then
            self.baitWarnAt, self.baitWarnCount = clock, (BW:BaitAboveLimitCount())
        end
        local baitWarn = self.baitWarnCount or 0
        if baitWarn > 0 then baitPercent:SetTextColor(1, 0.35, 0.3) else baitPercent:SetTextColor(1, 1, 1) end
        baitStatus:SetText(not BW.db.autoBait and "" or baitWarn > 0
            and ("|cffff6464Bait above buy limit: %d item%s|r"):format(baitWarn, baitWarn == 1 and "" or "s")
            or (baitCount and (baitRemaining and ("Bait %d/min · next in %d s"):format(baitCount, math.ceil(baitRemaining))
                or baitReason == "market active" and ("Bait %d/min · market active · paused"):format(baitCount)
                or ("Bait %d/min · %s"):format(baitCount, baitReason)) or "Bait · starts with watching"))
        learnPercent:SetEnabled(not busy and not BW.priceLookup)
        for _, boxes in ipairs({ maxPriceBoxes, budgetBoxes }) do
            for _, box in ipairs(boxes) do box:SetEnabled(not BW.running and not BW.learning and not BW.benchmark and not posting and not BW:PurchasePending()) end
        end
        nowPrice:SetText(BW.current and currentMoney(BW.current) or BW.updatedAt and "No listings"
            or BW.priceError and "No response" or BW.target and "Waiting for data" or "–")
        if BW.current and BW.maxPrice and BW.current > BW.maxPrice then
            nowPrice:SetTextColor(1.0, 0.39, 0.34)
        elseif BW.currentQuantity == 1 then
            nowPrice:SetTextColor(0.38, 0.68, 1.0)
        elseif BW.currentQuantity and BW.currentQuantity > 1 then
            nowPrice:SetTextColor(0.38, 0.92, 0.50)
        else
            nowPrice:SetTextColor(1, 1, 1)
        end
        local normal = learned and learned.normalPrice
        if BW.current and normal and normal > 0 then
            priceRatio:SetText(("%.0f%%"):format(BW.current / normal * 100))
            if BW.maxPrice and BW.current > BW.maxPrice then priceRatio:SetTextColor(1.0, 0.39, 0.34)
            else priceRatio:SetTextColor(0.38, 0.92, 0.50) end
        else
            priceRatio:SetText("")
        end
        local average = BW:RefreshAverage()
        refresh:SetText(average and ("Refresh: %.0f ms"):format(average) or "Refresh: –")
        spendLine:SetText(("Spent %s  ·  Budget left %s"):format(compactMoney(BW.spent),
            BW.budget and compactMoney(BW:Remaining()) or "–"))

        local offer = BW.running and BW:Offer()
        if Addon:BusyMessage(BW) then
            state:SetText(Addon:BusyMessage(BW))
        elseif BW.learning then
            state:SetText(BW:LearningStatus())
        elseif posting then
            state:SetText(posting)
        elseif BW:PurchaseUnconfirmed() then
            state:SetText(BW.running and "Purchase unresolved · prices updating, wheel paused."
                or "Purchase unresolved · waiting for server.")
        elseif BW:PurchasePending() then
            state:SetText(BW.notice or "Purchase confirmation pending …")
        elseif BW.benchmark then
            state:SetText(BW:BenchmarkProgress())
        elseif offer then
            state:SetText(("Scroll to buy   ·   %d items   ·   %s"):format(offer.quantity, money(offer.cost)))
        elseif BW.notice then
            state:SetText(BW.notice)
        elseif BW.priceLookup then
            state:SetText("Loading price …")
        elseif BW.priceError then
            state:SetText("Please reload the price.")
        elseif BW.running then
            state:SetText(("Live · watching %d items"):format(#BW.runWatchKeys))
        else
            state:SetText(BW:OtherWheelActive() and "Wait for BuyWheelS to finish its request."
                or (not BW.budget or BW.budget <= 0) and "Set a shared budget before starting."
                or ("%d items selected · check boxes to watch"):format(#BW:WatchKeys()))
        end
        local totalUnits = BW.unitsBought + BW.unitsMissed
        local rate = totalUnits > 0 and BW.unitsBought / totalUnits * 100 or 0
        local results = ("Bought/Missed: %d/%d (%.0f%%)"):format(BW.unitsBought, BW.unitsMissed, rate)
        detail:SetText(BW.running and (results .. "   ·   " .. BW:RouteName(BW:Route())) or results)
        self:RefreshPurchaseStats()
    end

    local elapsed = 0
    panel:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.15 then return end
        elapsed = 0
        panel:RefreshBuyWheelM()
    end)
    panel:SetScript("OnShow", function(self)
        Addon:SelectMode(BW)
        BW.favoritesPending = true
        self:RefreshBuyWheelM()
    end)
    panel:SetScript("OnHide", function()
        BW:Stop()
    end)
    Addon:AttachPurchaseStats(BW, panel, detail, 382)
    Addon:AttachPurchaseFeedback(panel)
    Addon:AttachHelp(BW, panel)
    return panel
end

function BW:HidePanel()
    if not self.panel then return end
    self.panel:Hide()
    if self.tab then PanelTemplates_DeselectTab(self.tab) end
end

function BW:Attach()
    local parent = AuctionHouseFrame
    if self.panel or not parent or not parent.Tabs or #parent.Tabs == 0 then return end
    self.panel = buildPanel(parent)

    Addon:RegisterModeTabs()
end
