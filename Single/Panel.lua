local _, Addon = ...
local BW = Addon.Single
local AH = C_AuctionHouse
local wheel = CreateFrame("Button", "BuyWheelSMouseButton", UIParent)
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

local function moneyInput(parent, title, x, amount, y, inline)
    local gold, silver, copper
    if inline then
        label(parent, title, "GameFontNormalSmall", x, y - 7):SetWidth(84)
        gold = edit(parent, 48, x + 88, y, 9)
        silver = edit(parent, 48, x + 154, y, 2)
        copper = edit(parent, 48, x + 220, y, 2)
        label(parent, "g", "GameFontDisableSmall", x + 140, y - 7)
        label(parent, "s", "GameFontDisableSmall", x + 206, y - 7)
        label(parent, "c", "GameFontDisableSmall", x + 272, y - 7)
    else
        label(parent, title, "GameFontNormal", x, y)
        gold = edit(parent, 48, x + 4, y - 32, 9)
        silver = edit(parent, 48, x + 61, y - 32, 2)
        copper = edit(parent, 48, x + 118, y - 32, 2)
        label(parent, "Gold", "GameFontDisableSmall", x + 4, y - 17)
        label(parent, "Silver", "GameFontDisableSmall", x + 61, y - 17)
        label(parent, "Copper", "GameFontDisableSmall", x + 118, y - 17)
    end

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

    label(searchPane, "Favorites", "GameFontNormalLarge", 9, 0)
    local searchStatus = label(searchPane, "", "GameFontDisableSmall", 9, -32)

    local rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, searchPane)
        row:SetPoint("TOPLEFT", 8, -28 - (i - 1) * 28)
        row:SetSize(258, 26)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetNormalFontObject("GameFontHighlightSmall")
        row:SetDisabledFontObject("GameFontDisableSmall")
        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("LEFT", 8, 0)
        title:SetWidth(243)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        row:SetFontString(title)
        row:SetScript("OnClick", function(self)
            BW:Select(self.key)
            panel:RefreshBuyWheel()
        end)
        local selected = row:CreateTexture(nil, "BACKGROUND")
        selected:SetAllPoints(row)
        selected:SetColorTexture(0.65, 0.56, 0.38, 0.25)
        selected:Hide()
        row.selected = selected
        rows[i] = row
    end

    local previous = button(searchPane, "‹", 34, 9, -343, function() panel.page = panel.page - 1 end)
    local nextPage = button(searchPane, "›", 34, 47, -343, function() panel.page = panel.page + 1 end)
    local more = button(searchPane, "Load more", 72, 144, -343, function() BW:LoadFavorites(true) end)
    local pageText = label(searchPane, "", "GameFontDisableSmall", 91, -351)
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
        panel:RefreshBuyWheel()
    end)
    historyToggle:SetFrameLevel(history:GetFrameLevel() + 2)
    local avgUnit = label(history, "", "GameFontHighlight", 9, -32)
    local purchaseTotal = label(history, "", "GameFontHighlightSmall", 9, -51)
    local purchaseRows = {}
    local historyPage = 1
    for i = 1, 6 do
        local y = -82 - (i - 1) * 42
        local name = label(history, "", "GameFontNormal", 9, y)
        name:SetWidth(252)
        name:SetWordWrap(false)
        local price = label(history, "", "GameFontHighlightSmall", 9, y - 17)
        purchaseRows[i] = { name = name, price = price }
    end
    local historyPrev = button(history, "‹", 34, 9, -343, function() historyPage = historyPage - 1 end)
    local historyNext = button(history, "›", 34, 47, -343, function() historyPage = historyPage + 1 end)
    local historyPosition = label(history, "", "GameFontDisableSmall", 91, -351)
    local historyReset = button(history, "Reset", 60, 156, -343, function()
        BW:ResetPurchases()
        historyPage = 1
        panel:RefreshBuyWheel()
    end)
    historyReset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Reset purchases")
        GameTooltip:AddLine("Clears the history and Bought/Missed counters.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    historyReset:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local x = 311
    local target = label(panel, "Select a favorite.", "GameFontHighlightLarge", x, 0)
    target:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, 0)
    target:SetJustifyV("TOP")
    target:SetWordWrap(false)
    local baitPriceBoxes, baitPrice = moneyInput(panel, "Bait sell price", x + 188, BW.db.baitPrice, -54)
    for _, box in ipairs(baitPriceBoxes) do
        box:SetScript("OnTextChanged", function() BW.db.baitPrice = baitPrice() end)
    end

    local nowPrice = label(panel, "–", "GameFontHighlightLarge", x, -24)
    local refresh = label(panel, "Refresh: –", "GameFontHighlightSmall", x, -30)
    refresh:ClearAllPoints()
    refresh:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -30)
    refresh:SetJustifyH("RIGHT")
    local baitButton = button(panel, "Bait", 72, x + 364, -86, function()
        BW:PostOne()
        panel:RefreshBuyWheel()
    end)
    baitButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Bait")
        GameTooltip:AddLine("Posts 1 item at the Bait sell price, shortest duration.", 1, 1, 1, true)
        if not (BW.db.baitPrice and BW.db.baitPrice > 0) then
            GameTooltip:AddLine("Set the Bait sell price first.", 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    baitButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local baitAge = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    baitAge:SetPoint("BOTTOMLEFT", baitButton, "TOPLEFT", 0, 3)
    baitAge:SetWidth(72)
    baitAge:SetJustifyH("LEFT")
    baitAge:SetText("")
    local repeatBait = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    repeatBait:SetPoint("TOPLEFT", x + 276, -50)
    repeatBait:SetSize(20, 20)
    local repeatLabel = label(panel, "Repeat bait", "GameFontHighlightSmall", x + 260, -82)
    repeatLabel:ClearAllPoints()
    repeatLabel:SetPoint("LEFT", repeatBait, "RIGHT", 3, 0)
    repeatBait:SetScript("OnClick", function(self)
        BW:SetRepeatBait(self:GetChecked())
        panel:RefreshBuyWheel()
    end)
    repeatBait:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Repeat bait · while GO is active")
        GameTooltip:AddLine("Posts a new bait after each sale; every post needs a fresh wheel step. STOP ends it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    repeatBait:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local maxPriceBoxes, maxPrice = moneyInput(panel, "Max Buy Price · per item", x, BW.db.maxPrice, -54)
    local budgetBoxes, budget = moneyInput(panel, "Spend up to (total)", x, BW.db.budget, -176, true)
    local function limits()
        BW:Limits(maxPrice(), budget())
    end
    for _, boxes in ipairs({ maxPriceBoxes, budgetBoxes }) do
        for _, box in ipairs(boxes) do box:SetScript("OnTextChanged", limits) end
    end
    limits()

    local go = button(panel, "GO", 166, x, -146, function()
        for _, boxes in ipairs({ maxPriceBoxes, budgetBoxes, baitPriceBoxes }) do
            for _, box in ipairs(boxes) do box:ClearFocus() end
        end
        BW:Start(false)
        panel:RefreshBuyWheel()
    end)
    local stop = button(panel, "STOP", 166, x + 188, -146, function()
        BW:Stop()
        panel:RefreshBuyWheel()
    Addon:Tip(previous, "Previous page")
    Addon:Tip(nextPage, "Next page")
    Addon:Tip(more, "Load more", "Loads more favorites from the auction house.")
    Addon:Tip(historyToggle, "Favorites / Purchases", "Switches between the favorites and the purchase history.")
    Addon:Tip(historyPrev, "Previous page")
    Addon:Tip(historyNext, "Next page")
    Addon:Tip(go, "GO", "Starts buying with the mouse wheel under the Max Buy Price.")
    Addon:Tip(stop, "STOP", "Stops buying.")
    for _, box in ipairs(maxPriceBoxes) do Addon:Tip(box, "Max Buy Price", "Limit per unit: gold / silver / copper.") end
    for _, box in ipairs(budgetBoxes) do Addon:Tip(box, "Spend up to", "Total gold for this run.") end
    for _, box in ipairs(baitPriceBoxes) do Addon:Tip(box, "Bait sell price", "Buyout of the posted bait.") end
    end)

    local bait = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    bait:SetPoint("TOPLEFT", x - 3, -114)
    bait:SetSize(24, 24)
    bait:SetChecked(BW.db.leaveBait == true)
    local baitLabel = label(panel, "Leave Bait", "GameFontHighlight", x + 24, -121)
    baitLabel:SetPoint("LEFT", bait, "RIGHT", 3, 0)
    bait:SetScript("OnClick", function(self) BW:SetLeaveBait(self:GetChecked()) end)
    bait:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Leave Bait")
        GameTooltip:AddLine("Leaves one item at the lowest price. For indivisible stacks, leaves the cheapest auction.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    bait:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local fastQuote = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    fastQuote:SetPoint("TOPLEFT", x + 110, -114)
    fastQuote:SetSize(24, 24)
    fastQuote:SetChecked(BW.db.fastQuote == true)
    local fastLabel = label(panel, "Buy Bait", "GameFontHighlight", x + 137, -121)
    fastLabel:SetPoint("LEFT", fastQuote, "RIGHT", 3, 0)
    fastQuote:SetScript("OnClick", function(self) BW:SetFastQuote(self:GetChecked()) end)
    fastQuote:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Buy Bait")
        GameTooltip:AddLine("Quotes 1 unit straight from Browse. Needs Leave Bait off. STOP before changing.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    fastQuote:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local fastQuoteX3 = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    fastQuoteX3:SetPoint("TOPLEFT", x + 220, -114)
    fastQuoteX3:SetSize(24, 24)
    fastQuoteX3:SetChecked(BW.db.fastQuoteX3 == true)
    local fastX3Label = label(panel, "Buy Bait", "GameFontHighlight", x + 247, -121)
    fastX3Label:SetPoint("LEFT", fastQuoteX3, "RIGHT", 3, 0)
    local fastQuantity = edit(panel, 48, 0, 0, 6)
    fastQuantity:ClearAllPoints()
    fastQuantity:SetPoint("LEFT", fastX3Label, "RIGHT", 10, 0)
    fastQuantity:SetNumeric(true)
    fastQuantity:SetText(tostring(BW:FastQuoteQuantity()))
    fastQuantity:SetScript("OnTextChanged", function(self, userInput)
        if userInput then BW:SetFastQuoteQuantity(self:GetText()) end
    end)
    fastQuantity:SetScript("OnEditFocusLost", function(self)
        self:SetText(tostring(BW:FastQuoteQuantity()))
    end)
    fastQuantity:SetScript("OnEnterPressed", fastQuantity.ClearFocus)
    Addon:Tip(fastQuantity, "Quantity", "Units per Buy Bait quote.")
    fastQuoteX3:SetScript("OnClick", function(self) BW:SetFastQuoteX3(self:GetChecked()) end)
    fastQuoteX3:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Buy Bait quantity · experimental")
        GameTooltip:AddLine("Quotes N units straight from Browse (experimental). Needs Leave Bait off. STOP before changing.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    fastQuoteX3:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local state = label(panel, "", "GameFontHighlight", x, -206)
    state:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -206)
    local low = caption(panel, "Lowest since GO", x + 258, -228)
    local spent = caption(panel, "Confirmed spending", x, -228)
    local remaining = caption(panel, "Budget left", x + 139, -228)
    local detail = label(panel, "", "GameFontHighlightSmall", x, -268)

    function panel:RefreshBuyWheel()
        if parent:GetAlpha() == 0 and (BW.running or BW.benchmark or BW.finding or BW.priceLookup) then BW:Stop() end
        local posting = BW:PostStatus()
        for _, box in ipairs(baitPriceBoxes) do
            box:SetEnabled(not posting and not BW:PostWaiting() and not BW.benchmark and not BW.learning)
        end
        local confirmingPost = BW:PostNeedsConfirmation()
        local waitingToPost = BW:PostWaiting()
        local busy = not Addon:CanUseMode(BW) or BW.running or BW.benchmark or BW:PurchasePending() or BW.finding or posting
        if BW.favoritesPending and not busy and not BW.priceLookup then
            BW:LoadFavorites()
            busy = busy or BW.finding
        end
        local result = BW.favorites or {}
        local pages = math.max(1, math.ceil(#result / ROWS))
        panel.page = math.min(panel.page, pages)
        for i, row in ipairs(rows) do
            local item = result[(panel.page - 1) * ROWS + i]
            row:SetShown(item ~= nil)
            if item then
                local key = item.itemKey
                local info = AH.GetItemKeyInfo(key)
                row.key = key
                local targetKey = BW.target and BW.target.key
                row.selected:SetShown(targetKey ~= nil and key.itemID == targetKey.itemID
                    and (key.itemLevel or 0) == (targetKey.itemLevel or 0)
                    and (key.itemSuffix or 0) == (targetKey.itemSuffix or 0)
                    and (key.battlePetSpeciesID or 0) == (targetKey.battlePetSpeciesID or 0))
                row:SetText(info and info.itemName and itemText(key, info) or ("Item %d · loading …"):format(key.itemID))
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
            local netUnits = BW.unitsBought - BW.baitsPosted
            local averageLabel = BW.baitsPosted > 0 and "Avg per item incl. bait   " or "Avg per item   "
            avgUnit:SetText(averageLabel .. (netUnits > 0 and money(BW.purchaseSpent / netUnits) or "–"))
            local total = ("%d items bought · %s"):format(BW.unitsBought, money(BW.purchaseSpent))
            if BW.baitsPosted > 0 then total = total .. (" · %d Bait"):format(BW.baitsPosted) end
            purchaseTotal:SetText(total)
            historyPosition:SetText(("%d / %d"):format(historyPage, historyPages))
            historyPrev:SetEnabled(historyPage > 1)
            historyNext:SetEnabled(historyPage < historyPages)
            for i, row in ipairs(purchaseRows) do
                local entry = BW.purchases[count - (historyPage - 1) * rowsPerPage - i + 1]
                row.name:SetText(entry and ("%d× %s"):format(entry.quantity, entry.name) or "")
                row.price:SetText(entry and ("%s total  ·  %s / item"):format(money(entry.cost), money(entry.cost / entry.quantity)) or "")
            end
        end

        target:SetText(BW.target and itemText(BW.target.key, { itemName = BW.target.name }) or "Select a favorite.")
        go:SetEnabled(not not BW:CanStart())
        stop:SetEnabled(not not (BW.running or BW.repeatBait or BW.benchmark or BW.finding or confirmingPost or waitingToPost))
        bait:SetEnabled(not BW.benchmark and not BW:PurchasePending())
        fastQuote:SetEnabled(BW:CanChangeFastQuote())
        fastQuote:SetChecked(BW.db.fastQuote == true)
        fastQuoteX3:SetChecked(BW.db.fastQuoteX3 == true)
        fastQuoteX3:SetEnabled(BW:CanChangeFastQuote())
        fastQuantity:SetEnabled(BW:CanChangeFastQuote())
        for _, boxes in ipairs({ maxPriceBoxes, budgetBoxes }) do
            for _, box in ipairs(boxes) do box:SetEnabled(not BW.benchmark and not posting) end
        end
        baitButton:SetText(confirmingPost and "Confirm bait"
            or waitingToPost and (BW:PostReady() and "Post bait" or "Waiting …") or "Bait")
        baitButton:SetEnabled(BW.target ~= nil and not InCombatLockdown() and not BW.benchmark
            and not BW.finding and not BW:PurchasePending()
            and (not posting or (confirmingPost or waitingToPost) and BW:PostReady()))
        local age, sold = BW:BaitAge()
        repeatBait:SetChecked(BW.repeatBait ~= nil)
        repeatBait:SetEnabled(BW.repeatBait ~= nil or (BW.target ~= nil and not BW.benchmark
            and not posting and not BW:PurchasePending() and not BW.finding))
        baitAge:SetText(age and ("%.1f"):format(age) or "")
        if sold then
            baitAge:SetTextColor(0.38, 0.92, 0.50)
        else
            baitAge:SetTextColor(1, 0.82, 0)
        end
        local offer = BW.running and BW:Offer()
        nowPrice:SetText(offer and offer.quoteOnly and "Server quote ready"
            or BW.current and currentMoney(BW.current) or BW.updatedAt and "No listings"
            or BW.priceError and "No response" or BW.target and "Waiting for data" or "–")
        if offer and offer.quoteOnly then
            nowPrice:SetTextColor(1, 0.82, 0)
        elseif BW.current and BW.maxPrice and BW.current > BW.maxPrice then
            nowPrice:SetTextColor(1.0, 0.39, 0.34)
        elseif BW.currentQuantity == 1 then
            nowPrice:SetTextColor(0.38, 0.68, 1.0)
        elseif BW.currentQuantity and BW.currentQuantity > 1 then
            nowPrice:SetTextColor(0.38, 0.92, 0.50)
        else
            nowPrice:SetTextColor(1, 1, 1)
        end
        local average = BW:RefreshAverage()
        refresh:SetText(average and ("Refresh: %.0f ms"):format(average) or "Refresh: –")
        low:SetText(BW.low and money(BW.low) or "–")
        spent:SetText(money(BW.spent))
        remaining:SetText(BW.budget and money(BW:Remaining()) or "–")

        if Addon:BusyMessage(BW) then
            state:SetText(Addon:BusyMessage(BW))
        elseif posting then
            state:SetText(posting)
        elseif BW:PurchaseUnconfirmed() then
            state:SetText(BW.running and "Purchase unresolved · prices updating, wheel paused."
                or "Purchase unresolved · waiting for server.")
        elseif BW:PurchasePending() then
            state:SetText(BW.notice or "Purchase confirmation pending …")
        elseif BW.benchmark then
            state:SetText(BW:BenchmarkProgress())
        elseif offer and offer.quoteOnly then
            state:SetText(("Scroll to quote   ·   %d items   ·   max %s"):format(offer.quantity, money(offer.cost)))
        elseif offer then
            state:SetText(("Scroll to buy   ·   %d items   ·   %s"):format(offer.quantity, money(offer.cost)))
        elseif BW.notice then
            state:SetText(BW.notice)
        elseif BW.priceLookup then
            state:SetText("Loading price …")
        elseif BW.priceError then
            state:SetText("Please reload the price.")
        elseif BW.running then
            state:SetText("Live · waiting for a matching offer")
        elseif BW.target and (not BW.maxPrice or not BW.budget) then
            state:SetText("Enter a price limit per item and a total budget.")
        else
            state:SetText(BW.target and ("Ready · " .. BW:RouteName(BW:Route())) or "")
        end
        local totalUnits = BW.unitsBought + BW.unitsMissed
        local rate = totalUnits > 0 and BW.unitsBought / totalUnits * 100 or 0
        local results = ("Bought/Missed: %d/%d (%.0f%%)"):format(BW.unitsBought, BW.unitsMissed, rate)
        detail:SetText(BW.running and (results .. "   ·   " .. BW:RouteName(BW:Route())) or results)
        if BW.repeatBait then
            detail:SetText(results .. (not BW.running and " · Repeat bait armed: press GO"
                or BW:HasLiveBait() and " · Bait live" or " · Scroll to post bait"))
        end
        self:RefreshPurchaseStats()
    end

    local elapsed = 0
    panel:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.15 then return end
        elapsed = 0
        panel:RefreshBuyWheel()
    end)
    panel:SetScript("OnShow", function(self)
        Addon:SelectMode(BW)
        BW.favoritesPending = true
        self:RefreshBuyWheel()
    end)
    panel:SetScript("OnHide", function()
        BW:Stop()
    end)
    Addon:AttachPurchaseStats(BW, panel, detail, 290)
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
