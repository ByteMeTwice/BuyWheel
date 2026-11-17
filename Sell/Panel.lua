local _, Addon = ...
local SW = Addon.Sell
-- Left: icon grid of the sellable commodities in the bags. Right: a selling tab with
-- the item on top, the two prices, the sell button and the list of market offers.
local COLS, GRID_ROWS, CELL = 5, 6, 46
local PER_PAGE = COLS * GRID_ROWS
local ROW_HEIGHT = 18
local X = 300 -- left edge of the right side

local wheel = CreateFrame("Button", "SellWheelMouseButton", UIParent)
wheel:RegisterForClicks("AnyDown")
wheel:SetScript("OnClick", function() SW:WheelStep() end)

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

-- The mouse wheel continues a running sale plan; chat scrolling is paused meanwhile,
-- as in the buy modes. Bound only while a plan runs (see RefreshSellWheel).
function SW:BindWheel(enable)
    enable = enable and true or false
    if self.wheelBound == enable then return end
    if InCombatLockdown() then return end
    self.wheelBound = enable
    for _, frame in ipairs(muted) do frame:EnableMouseWheel(true) end
    wipe(muted)
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

local function money(value)
    if value >= 10000 then return ("%dg %02ds %02dc"):format(math.floor(value / 10000), math.floor(value / 100) % 100, value % 100) end
    if value >= 100 then return ("%ds %02dc"):format(math.floor(value / 100), value % 100) end
    return ("%dc"):format(value)
end

local function label(parent, value, font, x, y, width)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", x, y)
    text:SetWidth(width or 240)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetText(value)
    return text
end

local function button(parent, value, width, x, y, fn)
    local frame = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetSize(width, 24)
    frame:SetText(value)
    frame:SetScript("OnClick", fn)
    return frame
end

local function itemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    if GetItemIcon then return GetItemIcon(id) end
end

local GREEN, BLUE = "|cff60eb80", "|cff66b3ff"
local function stageColor(stage)
    if stage == 2 then return BLUE end
    return GREEN
end

function SW:Attach()
    local parent = AuctionHouseFrame
    if self.panel or not parent or not parent.Tabs or #parent.Tabs == 0 then return end
    local panel = CreateFrame("Frame", nil, parent)
    panel:Hide()
    panel:SetPoint("TOPLEFT", 18, -68)
    panel:SetPoint("BOTTOMRIGHT", -18, 31)
    panel:SetFrameLevel(parent:GetFrameLevel() + 8)
    self.panel = panel
    self.inventoryPage, self.chartPage = 1, 1
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 285, -4)
    divider:SetPoint("BOTTOMLEFT", 285, 11)
    divider:SetWidth(1)
    divider:SetColorTexture(0.65, 0.56, 0.38, 0.31)

    -- ---- Left: icon grid of the bags (like a selling tab's item list) ----
    label(panel, "Commodities", "GameFontNormal", 12, -4, 200)
    local cells = {}
    for i = 1, PER_PAGE do
        local col, rowIndex = (i - 1) % COLS, math.floor((i - 1) / COLS)
        local cell = CreateFrame("Button", nil, panel)
        cell:SetPoint("TOPLEFT", 14 + col * CELL, -30 - rowIndex * CELL)
        cell:SetSize(42, 42)
        cell.border = cell:CreateTexture(nil, "BACKGROUND")
        cell.border:SetPoint("TOPLEFT", -2, 2)
        cell.border:SetPoint("BOTTOMRIGHT", 2, -2)
        cell.border:SetColorTexture(0.25, 0.22, 0.18, 1)
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetAllPoints(cell)
        cell.count = cell:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        cell.count:SetPoint("BOTTOMRIGHT", -3, 3)
        cell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        cell:SetScript("OnClick", function(self)
            if self.item then
                SW:Select(self.item)
                panel:RefreshSellWheel()
            end
        end)
        cell:SetScript("OnEnter", function(self)
            if not self.item then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.item.name)
            GameTooltip:AddLine(("In bags: %d · free: %d"):format(self.item.quantity, self.item.available), 1, 1, 1)
            GameTooltip:AddLine("Click to load the market prices. Nothing is posted until you press Sell.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cells[i] = cell
    end
    local empty = label(panel, "No sellable commodities in your bags.", nil, 14, -34, 250)
    label(panel, "Keep Bait Items", "GameFontNormalSmall", 14, -325, 100)
    local keepBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    keepBox:SetPoint("TOPLEFT", 118, -317)
    keepBox:SetSize(52, 24)
    keepBox:SetAutoFocus(false)
    keepBox:SetNumeric(true)
    keepBox:SetMaxLetters(7)
    keepBox:SetScript("OnEnterPressed", keepBox.ClearFocus)
    keepBox:SetScript("OnEscapePressed", keepBox.ClearFocus)
    keepBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then SW:SetKeepCount(self:GetText()) end
    end)
    keepBox:SetScript("OnEditFocusLost", function(self) self:SetText(tostring(SW:KeepCount())) end)
    keepBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Keep Bait Items")
        GameTooltip:AddLine("This many items of every commodity are never sold: they stay in your bags to be used as bait. 0 switches this off. Can only be changed while no sale plan is running.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    keepBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local invPrev = button(panel, "‹", 34, 9, -343, function() SW.inventoryPage = SW.inventoryPage - 1 end)
    local invNext = button(panel, "›", 34, 47, -343, function() SW.inventoryPage = SW.inventoryPage + 1 end)
    local invPage = label(panel, "", nil, 92, -351, 120)

    -- ---- Right top: item, quantity, duration ----
    local title = label(panel, "Select an item on the left.", "GameFontHighlightLarge", X, -2, 340)
    local iconBorder = panel:CreateTexture(nil, "BACKGROUND")
    iconBorder:SetPoint("TOPLEFT", X - 2, -24)
    iconBorder:SetSize(68, 68)
    iconBorder:SetColorTexture(0.3, 0.26, 0.2, 1)
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", X, -26)
    icon:SetSize(64, 64)
    icon:Hide()
    local function edit(width, x, y)
        local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        box:SetPoint("TOPLEFT", x, y)
        box:SetSize(width, 24)
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        box:SetMaxLetters(7)
        box:SetScript("OnEnterPressed", box.ClearFocus)
        box:SetScript("OnEscapePressed", box.ClearFocus)
        return box
    end
    local refresh = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    refresh:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -2)
    refresh:SetSize(100, 24)
    refresh:SetText("Refresh")
    refresh:SetScript("OnClick", function()
        if SW.selected and SW:CanEditSale() then SW:Select(SW.selected) end
    end)
    refresh:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Reload the market prices")
        GameTooltip:Show()
    end)
    refresh:SetScript("OnLeave", function() GameTooltip:Hide() end)

    label(panel, "Quantity", "GameFontNormalSmall", X + 78, -36, 54)
    local quantity = edit(64, X + 126, -30)
    quantity:SetScript("OnTextChanged", function(self, userInput)
        if userInput and SW:CanEditSale() then SW.quantity = self:GetText() end
    end)
    local all = button(panel, "Max", 50, X + 196, -30, function()
        if SW:CanEditSale() and SW.selected then SW.quantity = SW:Sellable(SW.selected) end
        panel:RefreshSellWheel()
    end)
    label(panel, "Duration", "GameFontNormalSmall", X + 262, -36, 54)
    local durationBoxes = {}
    for index, hours in ipairs(SW.durationHours) do
        local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        box:SetPoint("TOPLEFT", X + 318 + (index - 1) * 46, -33)
        box:SetSize(22, 22)
        local text = label(panel, tostring(hours), "GameFontHighlightSmall", 0, 0, 24)
        text:ClearAllPoints()
        text:SetPoint("LEFT", box, "RIGHT", 0, 0)
        box:SetScript("OnClick", function()
            SW:SetDuration(index)
            panel:RefreshSellWheel()
        end)
        box:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(("Duration: %d hours"):format(hours))
            GameTooltip:AddLine("How long the posted auctions last. A longer duration usually means a higher deposit. Can only be changed while no sale plan is running.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        box:SetScript("OnLeave", function() GameTooltip:Hide() end)
        durationBoxes[index] = box
    end

    -- ---- The two prices as colored strips (green = cheapest, blue = 25% level) ----
    local stageCards = {}
    for stage = 1, 2 do
        local y = -62 - (stage - 1) * 28
        local card = CreateFrame("Frame", nil, panel)
        card:SetPoint("TOPLEFT", X + 78, y)
        card:SetSize(362, 26)
        card.bg = card:CreateTexture(nil, "BACKGROUND")
        card.bg:SetAllPoints(card)
        if stage == 1 then card.bg:SetColorTexture(0.2, 0.8, 0.35, 0.28)
        else card.bg:SetColorTexture(0.25, 0.55, 1, 0.30) end
        card.name = label(card, stage == 1 and "Cheapest" or "25% level", "GameFontNormal", 6, -6, 82)
        card.price = label(card, "", "GameFontHighlight", 90, -6, 90)
        card.amount = label(card, "", "GameFontHighlight", 182, -6, 66)
        card.total = label(card, "", "GameFontDisableSmall", 250, -8, 60)
        stageCards[stage] = card
    end
    -- Share sold at the cheapest price; the rest goes to the 25% level.
    local share = edit(34, X + 78 + 308, -61)
    share:SetMaxLetters(3)
    share:SetScript("OnTextChanged", function(self, userInput)
        if userInput then SW:SetCheapShare(self:GetText()) end
    end)
    label(panel, "%", "GameFontHighlight", X + 78 + 346, -68, 14)
    local restShare = label(panel, "", "GameFontHighlight", X + 78 + 308, -96, 34)
    restShare:SetJustifyH("RIGHT")
    label(panel, "%", "GameFontHighlight", X + 78 + 346, -96, 14)
    local info = label(panel, "", "GameFontNormalSmall", X + 78, -120, 362)

    -- ---- Sell button (the first stage); the wheel does the rest ----
    local sell = button(panel, "Sell", 200, X + 78, -136, function()
        quantity:ClearFocus()
        share:ClearFocus()
        SW:PostNext()
        panel:RefreshSellWheel()
    end)
    sell:SetHeight(28)
    -- Only shown while the AH asks for a confirmation of the current post.
    local post = button(panel, "Confirm", 200, X + 78, -136, function()
        quantity:ClearFocus()
        SW:PostNext()
        panel:RefreshSellWheel()
    end)
    post:SetHeight(28)
    local stop = button(panel, "Stop", 64, X + 284, -136, function()
        SW:CancelPosting(true)
        SW:Stop()
        panel:RefreshSellWheel()
    end)
    stop:SetHeight(28)
    stop:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Stop the sale plan")
        GameTooltip:AddLine("Auctions that are already posted stay listed. If the result is unclear, check your own auctions first; Release does not repeat any posting.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    stop:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local wheelBox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    wheelBox:SetPoint("TOPLEFT", X + 354, -138)
    wheelBox:SetSize(24, 24)
    label(panel, "Wheel", "GameFontHighlightSmall", X + 380, -145, 60)
    wheelBox:SetScript("OnClick", function(self)
        SW:SetWheelEnabled(self:GetChecked() == true)
        panel:RefreshSellWheel()
    end)
    wheelBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Rest by mouse wheel")
        GameTooltip:AddLine("On: the first click on Sell posts the first stage. After that every mouse wheel step does the next step (post or confirm) while the plan runs. Without a running plan the wheel does nothing.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    wheelBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local status = label(panel, "", "GameFontNormalSmall", X, -170, 440)
    status:SetWordWrap(true)
    status:SetHeight(26)

    -- ---- Offer list: a table with a header and a scrollable body ----
    local header = panel:CreateTexture(nil, "BACKGROUND")
    header:SetPoint("TOPLEFT", X, -198)
    header:SetSize(424, 20)
    header:SetColorTexture(0.18, 0.15, 0.1, 1)
    label(panel, "Price", "GameFontNormalSmall", X + 8, -203, 100)
    local headQuantity = label(panel, "Available", "GameFontNormalSmall", X + 104, -203, 74)
    headQuantity:SetJustifyH("RIGHT")
    local headShare = label(panel, "Cumulative", "GameFontNormalSmall", X + 180, -203, 80)
    headShare:SetJustifyH("RIGHT")
    label(panel, "Own", "GameFontNormalSmall", X + 268, -203, 40)
    label(panel, "Sale", "GameFontNormalSmall", X + 318, -203, 100)
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", X, -220)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(420, 1)
    scroll:SetScrollChild(content)
    local listRows = {}
    local function getRow(i)
        local row = listRows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetSize(420, ROW_HEIGHT)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(row)
        row.price = label(row, "", "GameFontHighlightSmall", 8, -4, 100)
        row.quantity = label(row, "", "GameFontHighlightSmall", 104, -4, 74)
        row.quantity:SetJustifyH("RIGHT")
        row.share = label(row, "", "GameFontHighlightSmall", 180, -4, 80)
        row.share:SetJustifyH("RIGHT")
        row.owned = label(row, "", "GameFontHighlightSmall", 268, -4, 44)
        row.tag = label(row, "", "GameFontHighlightSmall", 318, -4, 102)
        listRows[i] = row
        return row
    end
    local emptyList = label(panel, "Loading market prices …", "GameFontDisableSmall", X + 8, -226, 330)

    local note = label(panel, "", "GameFontDisableSmall", 9, -378, 280)
    panel.durationBoxes = durationBoxes
    panel.quantityBox, panel.shareBox = quantity, share
    panel.sellButton, panel.postButton, panel.stopButton, panel.wheelBox = sell, post, stop, wheelBox
    panel.listRows, panel.stageCards, panel.inventoryCells = listRows, stageCards, cells

    -- Fills the table from the listing; only when the data changed.
    local listSignature
    local function fillList(listing, preview)
        local count = listing and #listing or 0
        local signature = ("%s:%d:%d:%d"):format(tostring(listing), preview and preview.quantity or 0,
            preview and preview.counts[1] or 0, preview and preview.counts[2] or 0)
        if signature == listSignature then return end
        listSignature = signature
        for i = 1, count do
            local entry, row = listing[i], getRow(i)
            row:Show()
            local color = entry.stage and (entry.stage == 3 and GREEN or stageColor(entry.stage)) or ""
            local tint
            if entry.stage == 2 then tint = { 0.25, 0.55, 1, 0.30 }
            elseif entry.stage then tint = { 0.2, 0.8, 0.35, 0.30 }
            elseif i % 2 == 0 then tint = { 1, 1, 1, 0.04 } end
            if tint then row.bg:SetColorTexture(unpack(tint)) else row.bg:SetColorTexture(0, 0, 0, 0) end
            row.price:SetText(color .. money(entry.price) .. (color ~= "" and "|r" or ""))
            row.quantity:SetText(entry.planned and "" or tostring(entry.quantity))
            row.share:SetText(("%.0f%%"):format((entry.share or 0) * 100))
            row.owned:SetText(entry.owned and entry.owned > 0 and "|cffffd100Ja|r" or "|cff808080Nein|r")
            local tag = ""
            if entry.stage and preview then
                local amount = entry.stage == 3 and preview.quantity or (preview.counts[entry.stage] or 0)
                tag = ("%s> %d items|r"):format(color, amount)
            end
            row.tag:SetText(tag)
        end
        for i = count + 1, #listRows do listRows[i]:Hide() end
        content:SetHeight(math.max(1, count * ROW_HEIGHT))
        if panel.shownListing ~= listing then
            panel.shownListing = listing
            scroll:SetVerticalScroll(0)
        end
    end

    function panel:RefreshSellWheel()
        if not SW.open or not self:IsVisible() then return end
        if SW.inventoryPending then SW:RefreshInventory() end
        SW:Pump()
        -- Left: the icon grid.
        local inventory = SW.inventory or {}
        local pages = math.max(1, math.ceil(#inventory / PER_PAGE))
        SW.inventoryPage = math.max(1, math.min(SW.inventoryPage, pages))
        empty:SetShown(#inventory == 0)
        for i, cell in ipairs(cells) do
            local item = inventory[(SW.inventoryPage - 1) * PER_PAGE + i]
            cell:SetShown(item ~= nil)
            cell.item = item
            if item then
                local texture = itemIcon(item.key.itemID)
                if texture then cell.icon:SetTexture(texture) end
                cell.count:SetText(item.available > 1 and tostring(item.available) or "")
                if SW.selected and SW.selected.id == item.id then cell.border:SetColorTexture(1, 0.6, 0.1, 1)
                else cell.border:SetColorTexture(0.25, 0.22, 0.18, 1) end
            end
        end
        invPage:SetText(("%d / %d · %d Items"):format(SW.inventoryPage, pages, #inventory))
        invPrev:SetEnabled(SW.inventoryPage > 1)
        invNext:SetEnabled(SW.inventoryPage < pages)

        -- Right: item.
        local item = SW.plan and SW.plan.item or SW.selected
        title:SetText(item and item.name or "Select an item on the left.")
        local texture = item and item.key and itemIcon(item.key.itemID)
        if texture then icon:SetTexture(texture) icon:Show() else icon:Hide() end
        local editable = SW:CanEditSale()
        keepBox:SetEnabled(editable)
        if not keepBox:HasFocus() then keepBox:SetText(tostring(SW:KeepCount())) end
        local preview, problem = SW:SalePreview()
        local plan = SW.plan
        preview = plan or preview
        local ready = SW:CanRead() and not InCombatLockdown() and not SW.request and not SW.queued
            and not SW.waitingForBags and C_AuctionHouse.IsThrottledMessageSystemReady()
        local confirming = SW.post and SW.post.state == "confirm"

        fillList(SW.listing, preview)

        -- The two strips.
        local merged = SW.presets and SW.presets[1].price == SW.presets[2].price
        for stage, card in ipairs(stageCards) do
            local preset = SW.presets and SW.presets[stage]
            if not (preset and preview) then
                card.price:SetText("–")
                card.amount:SetText("")
                card.total:SetText("")
            elseif merged and stage == 2 then
                card.price:SetText(money(preset.price))
                card.amount:SetText("")
                card.total:SetText("same as stage 1")
            else
                local amount = merged and preview.quantity or (preview.counts[stage] or 0)
                local open, done = amount, false
                if plan then
                    local index = SW:PlanEntryIndex(plan, stage, true)
                    local entry = index and plan.entries[index]
                    if entry then open, done = entry.remaining, entry.remaining == 0 end
                end
                card.price:SetText(money(preset.price))
                card.amount:SetText(done and "|cff808080OK|r" or ("%d items"):format(open))
                card.total:SetText(done and "" or money(open * preset.price))
            end
        end
        quantity:SetEnabled(editable)
        share:SetEnabled(editable)
        if not share:HasFocus() then share:SetText(tostring(SW:CheapShare())) end
        restShare:SetText(tostring(100 - SW:CheapShare()))
        all:SetEnabled(editable and SW.selected ~= nil)
        if not quantity:HasFocus() then quantity:SetText(tostring(SW.quantity or "")) end
        local duration = SW:Duration()
        for index, box in ipairs(durationBoxes) do
            box:SetChecked(duration == index)
            box:SetEnabled(editable)
        end
        wheelBox:SetChecked(SW:WheelEnabled())
        -- The wheel is only taken over while a sale plan runs (it continues the plan).
        SW:BindWheel(SW:WheelEnabled() and (SW.plan ~= nil or SW.post ~= nil) and self:IsVisible())
        note:SetText(("Duration %d h · Wheel %s"):format(SW.durationHours[duration],
            SW:WheelEnabled() and "continues the plan" or "off"))

        -- Info line: stock, deposit and gross total.
        local infoText = ""
        if SW.selected then
            infoText = ("Bags %d · free %d"):format(SW.selected.quantity, SW.selected.available)
            if SW:KeepCount() > 0 then infoText = infoText .. ("  ·  keep %d"):format(SW:KeepCount()) end
            local amount = tonumber(SW.quantity)
            if SW.selected.key and amount and amount >= 1 and C_AuctionHouse.CalculateCommodityDeposit then
                local ok, deposit = pcall(C_AuctionHouse.CalculateCommodityDeposit, SW.selected.key.itemID, duration, amount)
                if ok and type(deposit) == "number" then infoText = infoText .. ("  ·  Deposit %s"):format(money(deposit)) end
            end
            if preview and preview.total then infoText = infoText .. ("  ·  Total %s"):format(money(preview.total)) end
        end
        info:SetText(infoText)

        -- Main button: one step per click.
        local steps, doneSteps = 0, 0
        local entries = plan and plan.entries or (preview and preview.entries) or {}
        for _, entry in ipairs(entries) do
            steps = steps + 1
            if plan and entry.remaining == 0 then doneSteps = doneSteps + 1 end
        end
        local pending = plan and doneSteps < steps or (not plan and preview ~= nil and steps > 0)
        if plan then sell:SetText(("Continue · step %d/%d"):format(math.min(steps, doneSteps + 1), steps))
        else sell:SetText(steps > 1 and ("Sell (%d steps)"):format(steps) or "Sell") end
        sell:SetShown(not confirming)
        sell:SetEnabled(ready and not SW.post and pending and true or false)
        post:SetShown(confirming and true or false)
        post:SetEnabled(ready and confirming and true or false)
        local busy = Addon:BusyMessage(SW)
        local age = SW.snapshotAt and math.max(0, math.floor(GetTime() - SW.snapshotAt))
        stop:SetText(SW.post and SW.post.state == "unknown" and "Release" or "Stop")
        stop:SetEnabled(SW.plan ~= nil or SW.post ~= nil or SW.waitingForBags ~= nil or SW.request ~= nil or SW.queued ~= nil)
        refresh:SetEnabled(editable and SW.selected ~= nil and SW.request == nil and SW.queued == nil)
        local invalid = editable and SW.selected and not SW.request and not SW.queued and problem
        local summary = age and ("Market data: %d s ago"):format(age) or nil
        emptyList:SetShown(not SW.listing)
        status:SetText(busy or invalid or SW.status or summary or "Select an item.")
    end
    local elapsed = 0
    panel:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.2 then return end
        elapsed = 0
        panel:RefreshSellWheel()
    end)
    panel:SetScript("OnShow", function()
        Addon:SelectMode(SW)
        SW.inventoryPending = true
        panel:RefreshSellWheel()
    end)
    panel:SetScript("OnHide", function() SW:BindWheel(false) SW:Stop() GameTooltip:Hide() end)
    Addon:RegisterModeTabs()
end

function SW:HidePanel()
    self:BindWheel(false)
    if self.panel then self.panel:Hide() end
    if self.tab then PanelTemplates_DeselectTab(self.tab) end
end
