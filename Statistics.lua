local _, Addon = ...
local purchaseLotSerial = 0

function Addon:LearnedNormalPrice(mode, id)
    -- Learning belongs to Multi; Single reuses those same per-item references.
    local source = mode == self.Single and self.Multi or mode
    local prices = source and source.db and source.db.learnedPrices
    local learned = prices and prices[id]
    local normal = learned and learned.normalPrice
    if type(normal) == "number" and normal > 0 then return normal end
end

function Addon:PurchaseStatsKey(mode)
    -- Leave Bait uses detailed listings regardless of the fast-quote toggles.
    if mode.db.leaveBait then return "leave", "Leave Bait" end
    if mode.db.fastQuoteX3 then
        local quantity = mode:FastQuoteQuantity()
        return "fixed:" .. quantity, "Buy Bait x" .. quantity .. " fixed"
    end
    if mode.db.fastQuote then return "one", "Buy Bait x1" end
    return "normal", "Normal"
end

local function bucket(mode, key, title)
    if not mode.purchaseStats then mode.purchaseStats = { rows = {}, order = {} } end
    local stats = mode.purchaseStats
    if not stats.rows[key] then
        stats.rows[key] = { title = title, seconds = 0, units = 0, buys = 0, missed = 0, cost = 0 }
        stats.order[#stats.order + 1] = key
    end
    return stats.rows[key]
end

function Addon:StopPurchaseStats(mode)
    local stats = mode.purchaseStats
    if not stats or not stats.started then return end
    local row = stats.rows[stats.active]
    row.seconds = row.seconds + math.max(0, GetTime() - stats.started)
    stats.started, stats.active = nil, nil
end

function Addon:StartPurchaseStats(mode)
    self:StopPurchaseStats(mode)
    local key, title = self:PurchaseStatsKey(mode)
    bucket(mode, key, title)
    mode.purchaseStats.active, mode.purchaseStats.started = key, GetTime()
end

function Addon:ResetPurchaseStats(mode)
    mode.purchaseStats = nil
    if mode.running then self:StartPurchaseStats(mode) end
end

function Addon:RecordPurchaseStats(mode, order, success, missed)
    if not success and not missed then return end
    local key, title = order.statsKey, order.statsTitle
    if not key then key, title = self:PurchaseStatsKey(mode) end
    local row = bucket(mode, key, title)
    local item
    if order.tradeKey then
        local stats = mode.purchaseStats
        stats.items = stats.items or {}
        item = stats.items[order.tradeKey]
        if not item then
            item = { bought = 0, missed = 0 }
            stats.items[order.tradeKey] = item
        end
        if success then
            item.bought = item.bought + order.quantity
            item.cost = (item.cost or 0) + order.cost
        else item.missed = item.missed + order.quantity end
    end
    if success then
        row.units, row.buys = row.units + order.quantity, row.buys + 1
        row.cost = row.cost + order.cost
        local stats = mode.purchaseStats
        if type(order.normalPrice) == "number" and order.normalPrice > 0 then
            local profit = order.normalPrice * order.quantity - order.cost
            stats.estimatedProfit = (stats.estimatedProfit or 0) + profit
            stats.profitUnits = (stats.profitUnits or 0) + order.quantity
            if item then
                item.estimatedProfit = (item.estimatedProfit or 0) + profit
                item.profitUnits = (item.profitUnits or 0) + order.quantity
            end
            if order.log then order.log.estimatedProfit = profit end
        else
            stats.profitUnknownUnits = (stats.profitUnknownUnits or 0) + order.quantity
            if item then item.profitUnknownUnits = (item.profitUnknownUnits or 0) + order.quantity end
        end
        if order.tradeKey then
            stats.profitLots = stats.profitLots or {}
            local stock = stats.profitLots[order.tradeKey]
            if not stock then
                stock = { lots = {}, head = 1, tail = 0 }
                stats.profitLots[order.tradeKey] = stock
            end
            purchaseLotSerial = purchaseLotSerial + 1
            stock.tail = stock.tail + 1
            stock.lots[stock.tail] = { quantity = order.quantity, unitCost = order.cost / order.quantity,
                normalPrice = order.normalPrice, serial = purchaseLotSerial }
        end
    else
        row.missed = row.missed + order.quantity
    end
end

function Addon:RecordBaitPost(postingMode, bait)
    if bait.profitRecord then return end
    -- Match purchased stock FIFO across both modes. The correction belongs to
    -- the mode that originally credited this unit's expected resale value.
    local owner, stats, stock, lot
    for _, mode in ipairs({ self.Single, self.Multi }) do
        local candidate = mode.purchaseStats
        local inventory = candidate and candidate.profitLots and candidate.profitLots[bait.targetID]
        local first = inventory and inventory.lots[inventory.head]
        if first and (not lot or first.serial < lot.serial) then
            owner, stats, stock, lot = mode, candidate, inventory, first
        end
    end
    if not lot then
        local key, title = self:PurchaseStatsKey(postingMode)
        bucket(postingMode, key, title)
        owner, stats = postingMode, postingMode.purchaseStats
    end
    local record = { mode = owner, stats = stats, tracked = lot ~= nil }
    record.item = stats.items and stats.items[bait.targetID]
    bait.profitRecord = record
    if bait.log then
        bait.log.baitProfitTracked = record.tracked
        bait.log.baitProfitPending = true
    end
    stats.baitPending = (stats.baitPending or 0) + 1
    if lot then
        record.unitCost, record.normalPrice = lot.unitCost, lot.normalPrice
        lot.quantity = lot.quantity - 1
        if lot.quantity == 0 then
            stock.lots[stock.head] = nil
            stock.head = stock.head + 1
            if stock.head > stock.tail then stats.profitLots[bait.targetID] = nil end
        end
        local adjustment
        if type(record.normalPrice) == "number" and record.normalPrice > 0 then
            -- Purchase costs were already deducted: remove only the expected
            -- normal-price proceeds, not the cost of this unit a second time.
            adjustment = -record.normalPrice
        else
            -- Previously unpriced purchases contributed no profit or cost.
            -- Their actual cost is now known, awaiting the bait's sale proceeds.
            adjustment = -record.unitCost
            stats.profitUnknownUnits = math.max(0, (stats.profitUnknownUnits or 0) - 1)
            stats.profitUnits = (stats.profitUnits or 0) + 1
            if record.item then
                record.item.profitUnknownUnits = math.max(0, (record.item.profitUnknownUnits or 0) - 1)
                record.item.profitUnits = (record.item.profitUnits or 0) + 1
            end
        end
        stats.estimatedProfit = (stats.estimatedProfit or 0) + adjustment
        if record.item then record.item.estimatedProfit = (record.item.estimatedProfit or 0) + adjustment end
        stats.baitProfitAdjustment = (stats.baitProfitAdjustment or 0) + adjustment
        if bait.log then
            bait.log.baitProfitPostAdjustment = adjustment
            bait.log.baitUnitCost = record.unitCost
            bait.log.baitNormalPrice = record.normalPrice
        end
    else
        stats.baitUnpriced = (stats.baitUnpriced or 0) + 1
    end
end

function Addon:RecordBaitSale(bait)
    local record = bait.profitRecord
    if not record or record.sold then return end
    record.sold = true
    if bait.log then bait.log.baitProfitPending = false end
    -- A reset starts a new accounting scope; old sales must not enter it.
    if record.mode.purchaseStats ~= record.stats then
        if bait.log then bait.log.baitProfitIgnoredAfterReset = true end
        return
    end
    local stats = record.stats
    stats.baitPending = math.max(0, (stats.baitPending or 0) - 1)
    stats.baitSales = (stats.baitSales or 0) + 1
    if record.tracked then
        stats.estimatedProfit = (stats.estimatedProfit or 0) + bait.price
        if record.item then record.item.estimatedProfit = (record.item.estimatedProfit or 0) + bait.price end
        stats.baitProfitAdjustment = (stats.baitProfitAdjustment or 0) + bait.price
        stats.baitSaleRevenue = (stats.baitSaleRevenue or 0) + bait.price
        if bait.log then bait.log.baitProfitSaleAdjustment = bait.price end
    end
end

function Addon:PurchaseStatsSeconds(mode, key)
    local stats = mode.purchaseStats
    local row = stats and stats.rows[key]
    if not row then return 0 end
    return row.seconds + (stats.active == key and stats.started and math.max(0, GetTime() - stats.started) or 0)
end

function Addon:TotalPurchaseStatsSeconds(mode)
    local stats = mode.purchaseStats
    if not stats then return 0 end
    local seconds = 0
    for _, key in ipairs(stats.order) do seconds = seconds + self:PurchaseStatsSeconds(mode, key) end
    return seconds
end

function Addon:PurchaseProfitGoldPerHour(mode)
    local stats = mode.purchaseStats
    local seconds = self:TotalPurchaseStatsSeconds(mode)
    if not stats or seconds <= 0
        or ((stats.profitUnits or 0) == 0 and ((stats.profitUnknownUnits or 0) + (stats.baitUnpriced or 0)) > 0) then return end
    return (stats.estimatedProfit or 0) * 3600 / (seconds * 10000)
end

local function duration(seconds)
    local whole = math.floor(seconds)
    return ("%d:%02d:%02d"):format(math.floor(whole / 3600), math.floor(whole / 60) % 60, whole % 60)
end

local function profitMoney(amount)
    local sign = amount < 0 and "-" or ""
    if amount < 0 then amount = -amount end
    local whole = math.floor(amount)
    local copper = whole % 100 + amount - whole
    local coins = copper % 1 == 0 and tostring(copper) or ("%.2f"):format(copper)
    return ("%s%dg %02ds %sc"):format(sign, math.floor(whole / 10000), math.floor(whole / 100) % 100, coins)
end

local function text(parent, font, x, y, width)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    return label
end

function Addon:AttachPurchaseStats(mode, panel, detail, preferredY)
    local isMulti = mode == self.Multi
    local hasProfit = isMulti or mode == self.Single
    local modeName = isMulti and "Multi" or "Single"
    local summary = CreateFrame("Frame", nil, panel)
    summary:SetPoint("TOPLEFT", 311, -preferredY)
    summary:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -preferredY)
    summary:SetHeight(40)
    local heading = text(summary, "GameFontNormal", 0, 0, 276)
    local rates = text(summary, "GameFontHighlight", 0, -20, 354)
    local profit = hasProfit and text(summary, "GameFontHighlightSmall", 0, -40, 354)
    local compare = CreateFrame("Button", nil, summary, "UIPanelButtonTemplate")
    compare:SetPoint("TOPRIGHT", 0, 5)
    compare:SetSize(72, 22)
    compare:SetText("Compare")

    local page = CreateFrame("Frame", nil, panel)
    page:SetPoint("TOPLEFT", 303, 4)
    page:SetPoint("BOTTOMRIGHT", -4, 4)
    page:SetFrameLevel(panel:GetFrameLevel() + 20)
    page:EnableMouse(true)
    local background = page:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(page)
    background:SetColorTexture(0.045, 0.04, 0.03, 1)
    text(page, "GameFontNormalLarge", 8, -8, 270):SetText("Purchase rate comparison")
    local close = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    close:SetPoint("TOPRIGHT", -8, -4)
    close:SetSize(54, 24)
    close:SetText("Back")
    close:SetScript("OnClick", function() page:Hide() end)
    local intro = text(page, "GameFontHighlightSmall", 8, -39, 330)
    intro:SetHeight(42)
    intro:SetWordWrap(true)
    intro:SetText("Active GO time; STOP pauses the clock. Each setting shows bought/missed item counts behind its hit rate.")
    local rowHeight = 58
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -103)
    scroll:SetPoint("BOTTOMRIGHT", -28, 58)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(320, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * rowHeight)))
    end)
    local empty = text(content, "GameFontDisableSmall", 0, -8, 320)
    empty:SetText("Press GO to begin measuring purchases.")
    local columns = { 0, 120, 176, 224, 276 }
    local widths = { 118, 54, 46, 50, 44 }
    for i, title in ipairs({ "Setting", "Time", "/min", "/hour", "Hit %" }) do
        text(page, "GameFontNormalSmall", 8 + columns[i], -85, widths[i]):SetText(title)
    end
    local note = text(page, "GameFontDisableSmall", 8, 0, 330)
    note:ClearAllPoints()
    note:SetPoint("BOTTOMLEFT", 8, 8)
    note:SetHeight(42)
    note:SetWordWrap(true)
    note:SetText("Compare the same items, limits and market conditions. Short measurements fluctuate. Reset in Purchases clears this table. Reloading also clears it.")
    local rows = {}
    local function showTooltip(self)
        local row = self.data
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(row.title)
        GameTooltip:AddLine(("%d items bought · %d successful purchases"):format(row.units, row.buys), 1, 1, 1)
        GameTooltip:AddLine(("%d items missed · %.2f gold spent"):format(row.missed, row.cost / 10000), 1, 1, 1)
        local seconds = Addon:PurchaseStatsSeconds(mode, self.key)
        if seconds > 0 then
            GameTooltip:AddLine(("%.1f purchases/min · %.1f items/purchase"):format(row.buys * 60 / seconds, row.buys > 0 and row.units / row.buys or 0), 1, 1, 1)
        end
        GameTooltip:AddLine("Hit % uses bought / (bought + missed) item quantities. Unresolved attempts are excluded.", 1, 1, 1, true)
        GameTooltip:Show()
    end
    function page:Refresh()
        local stats = mode.purchaseStats
        local keys = stats and stats.order or {}
        empty:SetShown(#keys == 0)
        for i, key in ipairs(keys) do
            if not rows[i] then
                local frame = CreateFrame("Frame", nil, content)
                frame:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
                frame:SetSize(320, rowHeight - 2)
                frame:EnableMouse(true)
                frame:SetScript("OnEnter", showTooltip)
                frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
                frame.labels = {}
                for j = 1, 5 do
                    frame.labels[j] = text(frame, "GameFontHighlightSmall", columns[j], -3, widths[j])
                end
                frame.labels[1]:SetWordWrap(true)
                frame.labels[1]:SetHeight(32)
                frame.labels[1]:SetJustifyV("TOP")
                frame.items = text(frame, "GameFontDisableSmall", 0, -37, 320)
                rows[i] = frame
            end
            local row, frame = stats.rows[key], rows[i]
            local seconds = Addon:PurchaseStatsSeconds(mode, key)
            local total = row.units + row.missed
            frame.data, frame.key = row, key
            frame.labels[1]:SetText((stats.active == key and "|cff80ff80" or "") .. row.title .. "|r")
            frame.labels[2]:SetText(duration(seconds))
            frame.labels[3]:SetText(seconds > 0 and ("%.1f"):format(row.units * 60 / seconds) or "–")
            frame.labels[4]:SetText(seconds > 0 and ("%.0f"):format(row.units * 3600 / seconds) or "–")
            frame.labels[5]:SetText(total > 0 and ("%.0f%%"):format(row.units * 100 / total) or "–")
            frame.items:SetText(("Items: %d bought · %d missed · %d total"):format(row.units, row.missed, total))
            frame:Show()
        end
        for i = #keys + 1, #rows do rows[i]:Hide() end
        content:SetHeight(math.max(rowHeight, #keys * rowHeight))
    end
    page:SetScript("OnShow", function(self)
        self:Refresh()
        if mode.running or mode:PostWaiting() or mode:PostNeedsConfirmation() then mode:BindWheel(false) end
    end)
    page:SetScript("OnHide", function()
        GameTooltip:Hide()
        if (mode.running or mode:PostWaiting() or mode:PostNeedsConfirmation())
            and not (panel.helpPage and panel.helpPage:IsShown()) then mode:BindWheel(true) end
    end)
    page:Hide()
    panel.statsPage = page
    compare:SetScript("OnClick", function() page:Show() end)
    summary:EnableMouse(true)
    summary:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Purchase rates · current setting")
        local key, title = Addon:PurchaseStatsKey(mode)
        GameTooltip:AddLine(title .. " · " .. duration(Addon:PurchaseStatsSeconds(mode, key)), 1, 1, 1)
        GameTooltip:AddLine("Confirmed items divided by active watching time for this setting, across all runs since Reset. Waiting for offers and manual bait posting count as active time.", 1, 1, 1, true)
        GameTooltip:AddLine("STOP pauses measurement. Compare pauses mouse-wheel buying while open; its watching time still counts.", 1, 1, 1, true)
        if hasProfit then
            local stats = mode.purchaseStats or {}
            GameTooltip:AddLine("Estimated profit · all " .. modeName .. " purchases since Reset")
            GameTooltip:AddLine("Learned value minus actual purchase costs, adjusted for tracked bait sales. Before AH fees/deposits.", 1, 1, 1, true)
            GameTooltip:AddLine(("%d items valued · %d items without a learned normal price excluded"):format(stats.profitUnits or 0, stats.profitUnknownUnits or 0), 1, 1, 1, true)
            GameTooltip:AddLine(("Bait: %d sold · %d pending/unreported · %d without a tracked purchase excluded"):format(stats.baitSales or 0, stats.baitPending or 0, stats.baitUnpriced or 0), 1, 1, 1, true)
            GameTooltip:AddLine("Posted bait is removed from expected resale value. Only a matching sale credits its set sale price. Purchase costs are not deducted twice. FIFO stock matching assigns corrections to the purchase's original mode.", 1, 1, 1, true)
            GameTooltip:AddLine("Gold/hour uses total active " .. modeName .. " time across all settings: " .. duration(Addon:TotalPurchaseStatsSeconds(mode)) .. ". STOP pauses the clock.", 1, 1, 1, true)
            if not isMulti then
                GameTooltip:AddLine("Single uses normal prices learned in Multi. Each mode keeps its own totals.", 1, 1, 1, true)
            end
        end
        GameTooltip:Show()
    end)
    summary:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local refreshedAt, displayedStats, displayedKey, displayedRunning, displayedCompact
    local displayedSignature, cachedHourlyText = nil, "– g/h"
    -- The profit amount follows every purchase and bait sale at once; only the
    -- rates and gold/hour are paced (5 seconds).
    local function profitSignature(stats)
        if not stats then return "none" end
        return ("%s:%s:%s:%s"):format(tostring(stats.estimatedProfit or 0), tostring(stats.profitUnits or 0),
            tostring(stats.profitUnknownUnits or 0), tostring(stats.baitUnpriced or 0))
    end
    local function profitLine(stats, hourlyText)
        local total = stats and stats.estimatedProfit or 0
        local valued = stats and stats.profitUnits or 0
        local unknown = stats and ((stats.profitUnknownUnits or 0) + (stats.baitUnpriced or 0)) or 0
        local amount = valued == 0 and unknown > 0 and "–" or profitMoney(total)
        local color = valued == 0 and "|cffaaaaaa" or total < 0 and "|cffff6464" or "|cff60eb80"
        local suffix = unknown > 0 and (" · %d unpriced"):format(unknown) or ""
        return "Est. profit: " .. color .. amount .. " · " .. hourlyText .. "|r" .. suffix
    end
    function panel:RefreshPurchaseStats()
        -- Multi uses its statistics area above the controls in short windows;
        -- Single keeps its bottom area and drops only the heading when needed.
        local compact = hasProfit and panel:GetHeight() < preferredY + 64
        local now = GetTime()
        local key, title = Addon:PurchaseStatsKey(mode)
        local stats = mode.purchaseStats
        -- Purchases keep accumulating immediately; only presentation is paced.
        -- Reset, settings, GO/STOP and layout changes still show up immediately.
        if refreshedAt and now - refreshedAt < 5 and stats == displayedStats
            and key == displayedKey and mode.running == displayedRunning
            and compact == displayedCompact then
            -- Paced presentation, but the profit itself is live.
            if hasProfit and profit then
                local signature = profitSignature(stats)
                if signature ~= displayedSignature then
                    displayedSignature = signature
                    profit:SetText(profitLine(stats, cachedHourlyText))
                end
            end
            return
        end
        refreshedAt, displayedStats, displayedKey = now, stats, key
        displayedRunning, displayedCompact = mode.running, compact
        -- Multi has a fixed compact block at the bottom of its column: the profit
        -- figure first and larger, then small grey rates (the panel adds spending
        -- and Bought/Missed below). Single keeps the layout it always had.
        local y = isMulti and 246 or preferredY
        summary:ClearAllPoints()
        summary:SetPoint("TOPLEFT", panel, "TOPLEFT", 311, -y)
        summary:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -y)
        summary:SetHeight(isMulti and 34 or compact and 40 or hasProfit and 60 or 40)
        heading:SetShown(not compact and not isMulti)
        detail:SetShown(isMulti or not compact)
        rates:ClearAllPoints()
        rates:SetPoint("TOPLEFT", 0, isMulti and -22 or compact and 0 or -20)
        rates:SetWidth(isMulti and 270 or compact and 276 or 354)
        rates:SetFontObject(isMulti and "GameFontDisableSmall" or "GameFontHighlight")
        local row = stats and stats.rows[key]
        local seconds = Addon:PurchaseStatsSeconds(mode, key)
        heading:SetText(title .. " · " .. duration(seconds))
        rates:SetText(seconds > 0 and ("%.1f items/min  ·  %.0f items/hour"):format((row and row.units or 0) * 60 / seconds, (row and row.units or 0) * 3600 / seconds)
            or "– items/min  ·  – items/hour")
        if hasProfit then
            local hourly = Addon:PurchaseProfitGoldPerHour(mode)
            cachedHourlyText = hourly and ("%.2f g/h"):format(hourly) or "– g/h"
            displayedSignature = profitSignature(stats)
            profit:ClearAllPoints()
            profit:SetPoint("TOPLEFT", 0, isMulti and 0 or compact and -20 or -40)
            profit:SetWidth(isMulti and 270 or 354)
            profit:SetFontObject(isMulti and "GameFontHighlight" or "GameFontHighlightSmall")
            profit:Show()
            profit:SetText(profitLine(stats, cachedHourlyText))
        end
        if page:IsShown() then page:Refresh() end
    end
end
