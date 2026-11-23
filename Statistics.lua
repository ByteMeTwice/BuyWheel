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
    -- Multi: Leave Bait is active whenever its threshold is below 100 (the decision itself is per purchase).
    local leaving = mode.LeaveBaitThreshold and mode:LeaveBaitThreshold() < 100 or (not mode.LeaveBaitThreshold and mode.db.leaveBait)
    if leaving then return "leave", "Leave Bait" end
    if mode.db.browseBuy and mode == self.Multi then return "direct", "Direct buy" end
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
    mode.rob = nil
    mode.marketBaits = nil
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
        -- Permanent log first: it must never be lost to a later error.
        pcall(self.LogPurchase, self, mode, order)
        if mode == self.Multi and order.tradeKey then self:RobPurchase(mode, order) end
        row.units, row.buys = row.units + order.quantity, row.buys + 1
        row.cost = row.cost + order.cost
        local stats = mode.purchaseStats
        if type(order.normalPrice) == "number" and order.normalPrice > 0 then
            local profit = order.normalPrice * order.quantity - order.cost
            stats.estimatedProfit = (stats.estimatedProfit or 0) + profit
            stats.profitUnits = (stats.profitUnits or 0) + order.quantity
            -- Overall share paid: cost of all valued purchases vs. their normal-price value.
            stats.paidCost = (stats.paidCost or 0) + order.cost
            stats.paidNormal = (stats.paidNormal or 0) + order.normalPrice * order.quantity
            if item then
                item.estimatedProfit = (item.estimatedProfit or 0) + profit
                item.profitUnits = (item.profitUnits or 0) + order.quantity
                -- Stock still valued at the normal price of its purchase; lets the list
                -- revalue the profit when the learned normal price moves.
                item.normalUnits = (item.normalUnits or 0) + order.quantity
                item.normalValue = (item.normalValue or 0) + order.normalPrice * order.quantity
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

-- Return on Bait (ROB): a bait counts as successful when, after it was posted, items of the
-- same commodity were bought at the bait price or below (other sellers matched or undercut it).
-- The window of a bait ends when it is replaced by the next bait of that item, or after 10 minutes.
local ROB_WINDOW = 600

function Addon:RobOpen(mode, bait)
    local rob = mode.rob
    if not rob then
        rob = { current = {}, items = {}, posted = 0, hit = 0, units = 0 }
        mode.rob = rob
    end
    local id = bait.targetID
    if rob.current[id] then rob.current[id].closed = true end
    local item = rob.items[id]
    if not item then
        item = { name = bait.name, posted = 0, hit = 0, units = 0 }
        rob.items[id] = item
    end
    item.posted = item.posted + 1
    rob.posted = rob.posted + 1
    rob.current[id] = { price = bait.price or 0, at = GetTime(), units = 0, item = item }
end

-- A confirmed purchase: counts for the open bait of that item when paid at most the bait price.
function Addon:RobPurchase(mode, order)
    local rob = mode.rob
    local entry = rob and rob.current[order.tradeKey]
    if not entry or entry.closed or GetTime() - entry.at > ROB_WINDOW then return end
    local quantity = order.quantity or 0
    if quantity <= 0 or (order.cost or 0) / quantity > entry.price then return end
    if entry.units == 0 then
        rob.hit = rob.hit + 1
        entry.item.hit = entry.item.hit + 1
    end
    entry.units = entry.units + quantity
    entry.item.units = entry.item.units + quantity
    rob.units = rob.units + quantity
end

-- Baits per minute: over the last 10 minutes (live) and since Reset (average over active
-- watching time). Both nil until a bait was posted.
function Addon:MarketBaitStats(mode)
    local mb = mode.marketBaits
    if not mb then return end
    local now = GetTime()
    local recent = 0
    for _, at in ipairs(mb.times) do
        if now - at <= 600 then recent = recent + 1 end
    end
    local elapsed = now - mb.since
    local window = math.min(600, math.max(60, elapsed))
    return mb.count or 0, recent * 60 / window, mb.total, elapsed >= 60 and mb.total * 60 / elapsed or nil
end

-- posted, successful, still open (window running, no purchase yet), items bought, rate
function Addon:RobSummary(mode)
    local rob = mode.rob
    if not rob or rob.posted == 0 then return 0, 0, 0, 0, nil end
    local open, now = 0, GetTime()
    for _, entry in pairs(rob.current) do
        if entry.units == 0 and not entry.closed and now - entry.at <= ROB_WINDOW then open = open + 1 end
    end
    local decided = rob.posted - open
    return rob.posted, rob.hit, open, rob.units, decided > 0 and rob.hit / decided or nil
end

function Addon:RecordBaitPost(postingMode, bait)
    if bait.profitRecord then return end
    if postingMode == self.Multi then self:RobOpen(postingMode, bait) end
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
            if record.item and (record.item.normalUnits or 0) > 0 then
                record.item.normalUnits = record.item.normalUnits - 1
                record.item.normalValue = (record.item.normalValue or 0) - record.normalPrice
            end
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

-- Item profit revalued with the current normal price: units still counted as stock are
-- worth normalNow instead of the normal price of their purchase.
function Addon:LiveItemProfit(counts, normalNow)
    if not counts then return 0 end
    local profit = counts.estimatedProfit or 0
    if type(normalNow) == "number" and normalNow > 0 and (counts.normalUnits or 0) > 0 then
        profit = profit + counts.normalUnits * normalNow - (counts.normalValue or 0)
    end
    return profit
end

-- Share of the normal price actually paid across all items since Reset (percent).
function Addon:PaidPercent(mode)
    local stats = mode.purchaseStats
    if stats and (stats.paidNormal or 0) > 0 then return (stats.paidCost or 0) * 100 / stats.paidNormal end
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
    summary:EnableMouse(true)
    summary:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Purchase rates")
        local key, title = Addon:PurchaseStatsKey(mode)
        GameTooltip:AddLine(title .. " · " .. duration(Addon:PurchaseStatsSeconds(mode, key)), 1, 1, 1)
        GameTooltip:AddLine("Items per active minute since Reset. STOP pauses it.", 1, 1, 1, true)
        if hasProfit then
            local paid = Addon:PaidPercent(mode)
            GameTooltip:AddLine("Paid " .. (paid and ("%.1f%%"):format(paid) or "–") .. " of normal")
            GameTooltip:AddLine("Est. profit = value at normal price minus cost, before fees. g/h counts " .. duration(Addon:TotalPurchaseStatsSeconds(mode)) .. " active time.", 1, 1, 1, true)
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
        local suffix = unknown > 0 and (" · %d not counted"):format(unknown) or ""
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
        rates:SetWidth(isMulti and 430 or compact and 276 or 354)
        rates:SetFontObject(isMulti and "GameFontDisableSmall" or "GameFontHighlight")
        local row = stats and stats.rows[key]
        local seconds = Addon:PurchaseStatsSeconds(mode, key)
        heading:SetText(title .. " · " .. duration(seconds))
        local paid = Addon:PaidPercent(mode)
        local paidText = hasProfit and ("  ·  Paid " .. (paid and ("%.1f%%"):format(paid) or "–") .. " of normal") or ""
        rates:SetText((seconds > 0 and ("%.1f items/min  ·  %.0f items/hour"):format((row and row.units or 0) * 60 / seconds, (row and row.units or 0) * 3600 / seconds)
            or "– items/min  ·  – items/hour") .. paidText)
        if hasProfit then
            local hourly = Addon:PurchaseProfitGoldPerHour(mode)
            -- Running time (active watching time since Reset), paced like the rates.
            local total = math.floor(Addon:TotalPurchaseStatsSeconds(mode))
            local runtime = total >= 3600 and ("%d:%02d:%02d"):format(math.floor(total / 3600), math.floor(total / 60) % 60, total % 60)
                or ("%d:%02d"):format(math.floor(total / 60), total % 60)
            cachedHourlyText = (hourly and ("%.2f g/h"):format(hourly) or "– g/h") .. " · " .. runtime
            displayedSignature = profitSignature(stats)
            profit:ClearAllPoints()
            profit:SetPoint("TOPLEFT", 0, isMulti and 0 or compact and -20 or -40)
            profit:SetWidth(isMulti and 430 or 354)
            profit:SetFontObject(isMulti and "GameFontHighlight" or "GameFontHighlightSmall")
            profit:Show()
            profit:SetText(profitLine(stats, cachedHourlyText))
        end
    end
end
