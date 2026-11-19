local addonName, Addon = ...
local BW = Addon.Single
local AH = C_AuctionHouse
local sorts = Enum.AuctionHouseSortOrder
local priceSort = { { sortOrder = sorts.Price, reverseSort = false } }
local itemSort = {
    { sortOrder = sorts.Buyout, reverseSort = false },
    { sortOrder = sorts.Bid, reverseSort = false },
}
local queryTimeout = 2.5
local refreshTimeout = 5
local quoteTimeout = 2
local testBlocks = { "direct", "browse", "browse", "direct" }
local samplesPerBlock = 4
local requiredReady = 3
local benchmarkIdleTimeout = 45
local refreshWindow = 7
local offerHold = 2
local postDuration = 1 -- The shortest duration on Forever.
local lastBag = NUM_BAG_SLOTS or 4
local purchaseLogLimit = 100
local readyRetryDelay = 0.05
local recoveryDelay = 0.5

BW.spent = 0
BW.purchases = {}
BW.purchaseSpent = 0
BW.unitsBought = 0
BW.baitsPosted = 0
BW.missedPurchases = 0
BW.unitsMissed = 0

local request, cycle, purchase, queuedSearch, post, baitWait
local offerTimer, offerDeadline
local sending, pumping, hooked, sendingPurchase
local refreshReplies = {}
local listingReply, recentPurchase
local readyRetry, resumePurchase
local scanRun, scanWindow, readyWaitSince
local priceTiming
local recoveryTimer
local resumePost, recentPost, baitRequestedAt
local postFastQuote
local trackedBaits, recentBaitSales = {}, {}
local events = CreateFrame("Frame")

local function logValue(value)
    if issecretvalue and issecretvalue(value) then return end
    if type(value) == "number" or type(value) == "boolean" then return value end
    if type(value) == "string" then return value:sub(1, 240) end
end

local function milliseconds(seconds)
    return math.floor(seconds * 1000 + 0.5)
end

local function scanSample(field, responseMs)
    if not scanRun then return end
    local offset = math.floor((GetTime() - scanRun.started) / 10) * 10
    if not scanWindow or scanWindow.seconds ~= offset then
        scanWindow = { seconds = offset }
        local windows = scanRun.log.windows
        windows[#windows + 1] = scanWindow
        -- Keep the start for comparison with the most recent ten minutes.
        if #windows > 61 then table.remove(windows, 2) end
    end
    scanWindow[field] = (scanWindow[field] or 0) + 1
    if responseMs then
        local total = field .. "Ms"
        scanWindow[total] = (scanWindow[total] or 0) + responseMs
    end
end

local function logPurchaseEvent(order, event, first, second)
    local log = order and order.log
    if not log or #log.events >= 32 then return end
    log.events[#log.events + 1] = {
        ms = milliseconds(GetTime() - order.started), stage = order.stage,
        event = event, first = logValue(first), second = logValue(second),
    }
end

local function ready()
    return AH.IsThrottledMessageSystemReady()
end

-- Readiness is observed at events, pump retries and wheel clicks; no extra polling.
local function observeReadiness(isReady)
    local now = GetTime()
    if priceTiming and not priceTiming.readyAt and isReady then
        priceTiming.readyAt = now
    end
    if recentPost and isReady and not recentPost.log.resumeReadyMs then
        recentPost.log.resumeReadyMs = milliseconds(now - recentPost.finished)
        logPurchaseEvent(recentPost, "first_ready_after_post")
    end
    if recentPost and isReady and recentPost.log.resumeReplyMs and not recentPost.log.resumeReplyReadyMs then
        recentPost.log.resumeReplyReadyMs = milliseconds(now - recentPost.finished)
        logPurchaseEvent(recentPost, "first_ready_after_post_query")
    end
    if recentPost and isReady and recentPost.log.resumeReplyMs and not recentPost.log.buyReadyMs
        and BW.running and BW.target and recentPost.itemID == BW.target.key.itemID
        and not request and not post and not baitWait and not purchase and not recoveryTimer
        and not (BW.offers and BW.offers[1] and BW.offers[1].quoteOnly) and BW:Offer() then
        recentPost.log.buyReadyMs = milliseconds(now - recentPost.finished)
        logPurchaseEvent(recentPost, "buy_ready_after_post")
    end
    if resumePurchase and isReady and not resumePurchase.log.resumeReadyMs then
        resumePurchase.log.resumeReadyMs = milliseconds(now - resumePurchase.finished)
        logPurchaseEvent(resumePurchase, "first_ready_after_purchase")
    end
end

local function keyID(key)
    if not key then return end
    return ("%d:%d:%d:%d"):format(key.itemID, key.itemLevel or 0, key.itemSuffix or 0, key.battlePetSpeciesID or 0)
end

local function legacyMoney(text)
    if type(text) ~= "string" then return end
    local gold, fraction = text:match("^%s*(%d+)[,.]?(%d*)%s*$")
    if not gold or #fraction > 4 or #gold > 9 then return end
    return tonumber(gold) * 10000 + tonumber(fraction .. string.rep("0", 4 - #fraction))
end

function BW:Limits(maxPrice, budget)
    self.maxPrice, self.budget = maxPrice, budget
    self.db.maxPrice, self.db.budget = maxPrice, budget
    self:Pump()
end

-- History totals last until an explicit reset; spent tracks only the current budget.
function BW:ResetPurchases()
    Addon:ResetPurchaseStats(self)
    self.purchases = {}
    self.purchaseSpent = 0
    self.unitsBought = 0
    self.baitsPosted = 0
    self.missedPurchases = 0
    self.unitsMissed = 0
end

function BW:Remaining()
    return math.max(0, (self.budget or 0) - self.spent)
end

function BW:RefreshAverage()
    local cutoff = GetTime() - refreshWindow
    while refreshReplies[1] and refreshReplies[1] < cutoff do
        table.remove(refreshReplies, 1)
    end
    local count = #refreshReplies
    if count > 1 then
        return (refreshReplies[count] - refreshReplies[1]) * 1000 / (count - 1)
    end
end

function BW:SetLeaveBait(enabled)
    if purchase or self.benchmark then return end
    self.db.leaveBait = enabled == true
    if self.running then Addon:StartPurchaseStats(self) end
    self:Pump()
end

function BW:CanChangeFastQuote()
    return not self.running and not self.benchmark and not purchase
end

function BW:SetFastQuote(enabled)
    if not self:CanChangeFastQuote() then return end
    self.db.fastQuote = enabled == true
    if self.db.fastQuote then self.db.fastQuoteX3 = false end
end

function BW:SetFastQuoteX3(enabled)
    if not self:CanChangeFastQuote() then return end
    self.db.fastQuoteX3 = enabled == true
    if self.db.fastQuoteX3 then self.db.fastQuote = false end
end

-- Keep fastQuoteX3 as the saved toggle for compatibility with existing settings.
function BW:FastQuoteQuantity()
    local quantity = tonumber(self.db.fastQuoteQuantity)
    if not quantity or quantity ~= math.floor(quantity) or quantity < 1 or quantity > 999999 then return 3 end
    return quantity
end

function BW:SetFastQuoteQuantity(value)
    if not self:CanChangeFastQuote() then return end
    local quantity = tonumber(value)
    if not quantity or quantity ~= math.floor(quantity) or quantity < 1 or quantity > 999999 then return end
    self.db.fastQuoteQuantity = quantity
end

local function buyingRoom()
    if not BW.maxPrice or not BW.budget then return 0 end
    return math.min(BW.benchmark and BW.budget or BW:Remaining(), GetMoney())
end

function BW:PostFastQuoteQuantity()
    if not self.running or not self.target or not self.target.commodity or self.db.leaveBait
        or self.repeatBait ~= self.target.id then return end
    if self.db.fastQuoteX3 then return self:FastQuoteQuantity() end
    if self.db.fastQuote then return 1 end
end

function BW:Offer()
    if not self.offers or not self.maxPrice then return end
    if offerDeadline and GetTime() >= offerDeadline then return end
    local room = buyingRoom()
    local bait = self.db.leaveBait
    for i, entry in ipairs(self.offers) do
        if entry.unit > self.maxPrice then return end
        if entry.auctionID then
            if (not bait or i > 1) and entry.cost <= room then return entry end
        elseif entry.unit <= room then
            local available = entry.quantity - (bait and 1 or 0)
            local quantity = math.min(available, math.floor(room / entry.unit))
            if quantity > 0 and (not entry.fixedQuantity or quantity == entry.fixedQuantity) then
                return { unit = entry.unit, quantity = quantity, cost = quantity * entry.unit,
                    fromBrowse = entry.fromBrowse, browseQuantity = entry.browseQuantity,
                    quoteOnly = entry.quoteOnly, postQuote = entry.postQuote }
            end
        end
    end
end

local function clearOfferHold()
    if offerTimer then offerTimer:Cancel() end
    offerTimer, offerDeadline = nil, nil
end

local function holdOffer()
    if offerTimer then return end
    offerDeadline = GetTime() + offerHold
    offerTimer = C_Timer.NewTimer(offerHold, function()
        offerTimer, offerDeadline = nil, nil
        if postFastQuote then
            logPurchaseEvent(postFastQuote.posted, "post_fast_quote_expired")
            postFastQuote = nil
        end
        scanSample("offerHoldExpired", offerHold * 1000)
        BW.offers, BW.currentQuantity = nil, nil
        BW:Pump()
    end)
end

local function discardPostFastQuote(reason)
    if postFastQuote then logPurchaseEvent(postFastQuote.posted, "post_fast_quote_fallback", reason) end
    postFastQuote = nil
    if BW.offers and BW.offers[1] and BW.offers[1].quoteOnly then
        clearOfferHold()
        BW.offers = nil
    end
end

local function recordPrice(price, quantity)
    BW.current, BW.currentQuantity, BW.updatedAt = price, quantity, GetTime()
    priceTiming = BW.running and { at = BW.updatedAt, clicks = 0, blocked = 0 } or nil
    if priceTiming then observeReadiness(ready()) end
    if BW.running and price and (not BW.low or price < BW.low) then BW.low = price end
end

local function collectOffers(target)
    local offers = {}
    local lowest, lowestQuantity
    local function observe(unit, quantity)
        if not lowest or unit < lowest then
            lowest, lowestQuantity = unit, quantity
        elseif unit == lowest then
            lowestQuantity = lowestQuantity + quantity
        end
    end

    if target.commodity then
        local id = target.key.itemID
        local tiers, blocked, marketLow = {}, {}, nil
        for i = 1, AH.GetNumCommoditySearchResults(id) do
            local row = AH.GetCommoditySearchResultInfo(id, i)
            if row and row.unitPrice > 0 and row.quantity > 0 then
                local price = row.unitPrice
                marketLow = marketLow and math.min(marketLow, price) or price
                -- The commodity purchase API always fills from the cheapest tier.
                if not row.containsAccountItem then
                    local available = row.quantity - (row.numOwnerItems or 0)
                    if available > 0 then
                        observe(price, available)
                        tiers[price] = (tiers[price] or 0) + available
                    end
                else
                    blocked[price] = true
                end
            end
        end
        if lowest and lowest == marketLow and not blocked[lowest] then
            offers[1] = { unit = lowest, quantity = tiers[lowest] }
        end
    else
        for i = 1, AH.GetNumItemSearchResults(target.key) do
            local row = AH.GetItemSearchResultInfo(target.key, i)
            if row and row.buyoutAmount and row.buyoutAmount > 0 and not row.containsOwnerItem
                and not row.containsAccountItem then
                -- Forever sometimes reports the group quantity for non-stackable auctions.
                local quantity = math.max(1, math.min(row.quantity or 1, target.stackSize))
                local price = row.buyoutAmount / quantity
                local alreadyBought = BW.running and BW.usedAuctions[row.auctionID]
                if row.auctionID and row.auctionID > 0 and not alreadyBought then
                    observe(price, quantity)
                    offers[#offers + 1] = {
                        auctionID = row.auctionID, quantity = quantity, unit = price, cost = row.buyoutAmount,
                    }
                end
            end
        end
        table.sort(offers, function(a, b)
            if a.unit == b.unit then
                if a.cost == b.cost then return a.auctionID < b.auctionID end
                return a.cost < b.cost
            end
            return a.unit < b.unit
        end)
    end
    return lowest, offers, lowestQuantity
end

local function newStats()
    return { responses = 0, misses = 0, interval = 0, gaps = 0, ready = 0, readyTime = 0 }
end

local function average(total, count)
    if count > 0 then return string.format("%.0f ms", total * 1000 / count) end
    return "–"
end

local function statsLine(stats)
    return ("%d/%d replies   ·   avg interval %s   ·   ready %d× after avg %s"):format(
        stats.responses, stats.responses + stats.misses, average(stats.interval, stats.gaps),
        stats.ready, average(stats.readyTime, stats.ready))
end

function BW:BenchmarkSummary()
    if not self.metrics then return "" end
    return "Direct   " .. statsLine(self.metrics.direct) .. "\nBrowse  " .. statsLine(self.metrics.browse)
end

function BW:BenchmarkProgress()
    local test = self.benchmark
    if not test then return end
    local step = (request and not request.abandoned or ready()) and "Query in progress" or "Waiting for auction house"
    return ("Ready to buy · Direct %d/%d · Browse %d/%d\n%s · %s"):format(
        math.min(self.metrics.direct.ready, requiredReady), requiredReady,
        math.min(self.metrics.browse.ready, requiredReady), requiredReady,
        self:RouteName(testBlocks[test.block]), step)
end

local function answersReliably(stats)
    return stats.responses >= samplesPerBlock * 2 - 1
        and stats.responses * 8 >= (stats.responses + stats.misses) * 7
end

local function chooseRoute()
    local direct, browse = BW.metrics.direct, BW.metrics.browse
    local function reliable(stats)
        return stats.ready >= requiredReady and answersReliably(stats)
    end
    if not reliable(direct) and not reliable(browse) then return end
    if not reliable(direct) then return "browse" end
    if not reliable(browse) then return "direct" end
    local directReady, browseReady = direct.readyTime / direct.ready, browse.readyTime / browse.ready
    if math.abs(directReady - browseReady) > 0.001 then
        return directReady < browseReady and "direct" or "browse"
    end
    return direct.interval / math.max(1, direct.gaps) <= browse.interval / math.max(1, browse.gaps)
        and "direct" or "browse"
end

local function finishBenchmark(stalled)
    BW:Stop()
    local route = chooseRoute()
    if route then
        BW.db.routes[BW.target.id] = route
        BW.notice = stalled and (BW:RouteName(route) .. " saved for GO · no further match for 45 s.")
            or ("Comparison complete · " .. BW:RouteName(route) .. " selected.")
    elseif stalled then
        local directReliable = answersReliably(BW.metrics.direct)
        local browseReliable = answersReliably(BW.metrics.browse)
        if directReliable ~= browseReliable then
            route = directReliable and "direct" or "browse"
            BW.db.routes[BW.target.id] = route
            BW.notice = BW:RouteName(route) .. " saved for GO · not enough purchase readiness samples yet."
        else
            BW.notice = "No further match for 45 s · no reliable selection."
        end
    else
        BW.notice = "Three matches per route measured · both routes had too many failures."
    end
end

local function armBenchmarkTimeout()
    local test = BW.benchmark
    if test.timer then test.timer:Cancel() end
    test.timer = C_Timer.NewTimer(benchmarkIdleTimeout, function()
        if BW.benchmark == test then finishBenchmark(true) end
    end)
end

local function finishCycle(success)
    local finished = cycle
    cycle = nil
    if not finished then return end

    if finished.preview then
        BW.priceLookup:Cancel()
        BW.priceLookup = nil
        BW.priceError = not success
    elseif BW.benchmark then
        local test = BW.benchmark
        local stats = BW.metrics[finished.route]
        local now = finished.answeredAt or GetTime()
        if success then
            stats.responses = stats.responses + 1
            if test.lastResponse then
                stats.interval = stats.interval + now - test.lastResponse
                stats.gaps = stats.gaps + 1
            end
            test.lastResponse = now
        else
            stats.misses = stats.misses + 1
        end
        test.sample = test.sample + 1
        if test.sample == samplesPerBlock then
            test.block, test.sample, test.lastResponse = test.block + 1, 0, nil
        end
        if test.block > #testBlocks then
            test.block, test.baselineDone = 1, true
        end
        if test.baselineDone and BW.metrics.direct.ready >= requiredReady and BW.metrics.browse.ready >= requiredReady then
            finishBenchmark(false)
        elseif test.baselineDone and test.sample == 0 then
            while BW.metrics[testBlocks[test.block]].ready >= requiredReady do
                test.block = test.block % #testBlocks + 1
            end
        end
    elseif BW.running then
        if success then
            scanSample("cycles")
            refreshReplies[#refreshReplies + 1] = finished.answeredAt or GetTime()
            BW.misses = 0
            BW.notice = nil
        else
            BW.misses = BW.misses + 1
            local step = finished.next:find("^list") and "Listings" or "Browse"
            BW.notice = step .. " did not respond · retrying."
            if BW.misses >= 2 and (finished.route == "direct" or step == "Browse") then
                BW.fallback = finished.route == "direct" and "browse" or "direct"
                BW.misses = 0
                BW.notice = step .. " did not respond · switching to " .. BW:RouteName(BW.fallback) .. "."
            end
        end
    end
end

function BW:Route()
    return self.fallback or self.db.routes[self.target.id] or (self.target.commodity and "browse" or "direct")
end

function BW:RouteName(route)
    return route == "browse" and "Browse" or "Direct"
end

local function clearRequest()
    local old = request
    request = nil
    if old then old.timer:Cancel() end
end

local function pauseRecovery(order, delay, reason)
    if recoveryTimer then recoveryTimer:Cancel() end
    logPurchaseEvent(order, "resume_backoff", milliseconds(delay), reason)
    recoveryTimer = C_Timer.NewTimer(delay, function()
        recoveryTimer = nil
        BW:Pump()
    end)
end

local function failRequest(reason, failureEvent)
    local old = request
    clearRequest()
    if not old or old.abandoned then return end
    if old.resumePost then
        local posted = old.resumePost
        posted.log.resumeFailure = failureEvent or reason
        logPurchaseEvent(posted, "query_failed_after_post", old.kind, failureEvent)
    end
    if old.resumePurchase then
        local order = old.resumePurchase
        order.log.resumeFailures = (order.log.resumeFailures or 0) + 1
        logPurchaseEvent(order, "resume_query_failed", old.kind, failureEvent)
        resumePurchase = resumePurchase or order
    end
    if old.manual then
        BW.finding = false
        BW.favoritesError = true
        BW.notice = reason
    else
        if BW.running then scanSample(old.kind:find("^browse") and "browseMisses" or "listingMisses") end
        local order = old.resumePurchase
        if BW.running and order then
            -- Give the purchase transaction time to drain before retrying. Only
            -- switch routes through the normal fallback after two recovery retries.
            pauseRecovery(order, math.min(1, recoveryDelay * order.log.resumeFailures), failureEvent)
            if order.log.resumeFailures <= 2 then
                cycle = nil
            else
                finishCycle(false)
            end
        else
            finishCycle(false)
        end
    end
end

local function send(kind, name, manual)
    local job = { kind = kind, manual = manual, started = GetTime() }
    if resumePurchase and BW.running and not manual then
        job.resumePurchase, resumePurchase = resumePurchase, nil
        local order = job.resumePurchase
        if not order.log.resumeSendMs then
            order.log.resumeSendMs = milliseconds(job.started - order.finished)
            logPurchaseEvent(order, "first_query_sent", kind)
        else
            logPurchaseEvent(order, "resume_query_retried", kind)
        end
    end
    if resumePost and not manual then
        job.resumePost, resumePost = resumePost, nil
        local posted = job.resumePost
        posted.log.resumeSendMs = milliseconds(job.started - posted.finished)
        logPurchaseEvent(posted, "first_query_sent_after_post", kind)
    end
    local target = BW.target
    -- A fresh detailed query avoids another Browse round trip and does not
    -- depend on the pre-post listing cache being usable after the sale update.
    local refresh = kind == "list" and not job.resumePost and AH.HasSearchResults(target.key)
    job.refreshed = not not refresh
    request = job
    job.timer = C_Timer.NewTimer(refresh and refreshTimeout or queryTimeout, function()
        if request ~= job then return end
        failRequest("The auction house query did not respond.", "timeout")
        BW:Pump()
    end)

    sending = true
    local ok
    if kind == "browseFavorites" then
        ok = pcall(AH.SearchForFavorites, { { sortOrder = sorts.Name, reverseSort = false } })
    elseif kind == "browse" then
        ok = pcall(AH.SendBrowseQuery, {
            searchString = name, sorts = priceSort, filters = {}, itemClassFilters = {},
        })
    elseif kind == "browseMore" then
        ok = pcall(AH.RequestMoreBrowseResults)
    else
        job.itemID, job.id, job.commodity = target.key.itemID, target.id, target.commodity
        if kind == "listMore" then
            if target.commodity then
                ok = pcall(AH.RequestMoreCommoditySearchResults, job.itemID)
            else
                ok = pcall(AH.RequestMoreItemSearchResults, target.key)
            end
        elseif refresh then
            if target.commodity then
                ok = pcall(AH.RefreshCommoditySearchResults, job.itemID)
            else
                ok = pcall(AH.RefreshItemSearchResults, target.key)
            end
        else
            ok = pcall(AH.SendSearchQuery, target.key, target.commodity and priceSort or itemSort, true)
        end
    end
    sending = false
    if not ok and request == job then
        -- Leave the watchdog armed so a rejected API call cannot cause a tight retry loop.
        BW.notice = "Auction house query failed · waiting to retry."
    elseif request ~= job then
        C_Timer.After(0, function() BW:Pump() end)
    end
end

function BW:Pump()
    if not Addon:CanUseMode(self) then return end
    if self.running then observeReadiness(ready()) end
    if pumping or sending or sendingPurchase or post or baitWait or not self.open or (purchase and not purchase.timedOut)
        or request or recoveryTimer then return end
    if not (queuedSearch or cycle or self.running or self.benchmark or self.priceLookup) then return end
    if not ready() then
        if scanRun and (cycle or not self:Offer()) then readyWaitSince = readyWaitSince or GetTime() end
        -- Some replies are dispatched before the readiness flag changes.
        if not readyRetry then
            readyRetry = C_Timer.NewTimer(readyRetryDelay, function()
                readyRetry = nil
                self:Pump()
            end)
        end
        return
    end
    if readyRetry then
        readyRetry:Cancel()
        readyRetry = nil
    end
    if readyWaitSince then
        scanSample("apiWait", milliseconds(GetTime() - readyWaitSince))
        readyWaitSince = nil
    end
    -- A quote is sent only by the next real input. Do not spend the newly
    -- available AH slot on a listing query before that one post-quote attempt.
    if postFastQuote and not cycle and not queuedSearch then
        local quantity = self:PostFastQuoteQuantity()
        if quantity == postFastQuote.quantity and self.maxPrice == postFastQuote.cap
            and self.maxPrice > 0 and self.maxPrice * quantity <= buyingRoom() then
            if not postFastQuote.armed then
                postFastQuote.armed = true
                postFastQuote.posted.log.fastQuoteReadyMs = milliseconds(GetTime() - postFastQuote.posted.finished)
                logPurchaseEvent(postFastQuote.posted, "post_fast_quote_ready", quantity)
                self.offers = { { unit = self.maxPrice, quantity = quantity, fixedQuantity = quantity,
                    quoteOnly = true, postQuote = postFastQuote.posted } }
                priceTiming = nil -- This is a price ceiling, not a received market price.
                holdOffer()
            end
            return
        end
        discardPostFastQuote("settings_or_budget")
    end
    pumping = true
    if queuedSearch then
        local search = queuedSearch
        queuedSearch = nil
        send(search.kind, search.name, true)
    elseif self.running or self.benchmark or self.priceLookup then
        if cycle then
            if cycle.done then
                if self.benchmark and self:Offer() then
                    local stats = self.metrics[cycle.route]
                    stats.ready = stats.ready + 1
                    stats.readyTime = stats.readyTime + GetTime() - cycle.started
                    if stats.ready <= requiredReady then armBenchmarkTimeout() end
                end
                finishCycle(true)
            else
                send(cycle.next, self.target.browseName)
            end
        end
        -- Preserve listings and leave the next AH message slot free for the wheel.
        if not cycle then
            if self.running and not purchase and self:Offer() then
                if recentPost and not recentPost.log.offerReadyMs and recentPost.itemID == self.target.key.itemID then
                    recentPost.log.offerReadyMs = milliseconds(GetTime() - recentPost.finished)
                    logPurchaseEvent(recentPost, "offer_ready_after_post")
                end
                holdOffer()
            elseif self.priceLookup or self.benchmark or self.running then
                clearOfferHold()
                local route = self.benchmark and testBlocks[self.benchmark.block] or self:Route()
                if resumePost and self == Addon.Single then route = "direct" end
                if self.priceLookup and not self.target.commodity then route = "direct" end
                cycle = { route = route, started = GetTime(), next = route == "direct" and "list" or "browse",
                    preview = self.priceLookup ~= nil }
                send(cycle.next, self.target.browseName)
            end
        end
    end
    pumping = false
end

local function cancelPriceLookup()
    if not BW.priceLookup then return end
    BW.priceLookup:Cancel()
    BW.priceLookup = nil
    if cycle and cycle.preview then
        cycle = nil
        if request then request.abandoned = true end
    end
end

function BW:RefreshPrice()
    if not self:CanTest() or not self.target then return end
    cancelPriceLookup()
    self.priceError = nil
    local timer
    timer = C_Timer.NewTimer(8, function()
        if self.priceLookup ~= timer then return end
        cancelPriceLookup()
        self.priceError = true
    end)
    self.priceLookup = timer
    self:Pump()
end

function BW:LoadFavorites(more)
    if not Addon:CanUseMode(self) then return end
    if not self.open or self.running or self.benchmark or purchase or post or baitWait or self.finding
        or self.priceLookup or request then return end
    if not AH.SearchForFavorites then
        self.favoritesPending, self.favoritesError = false, true
        self.notice = "Auction house favorites are unavailable in this client."
        return
    end
    if AH.FavoritesAreAvailable and not AH.FavoritesAreAvailable() then return end
    self.favoritesPending, self.favoritesError = false, false
    if not more then
        self.favorites = {}
        self.searchMore = false
    end
    if AH.HasFavorites and not AH.HasFavorites() then
        self.favorites, self.searchMore, self.notice = {}, false, nil
        return
    end
    self.finding, self.notice = true, "Loading favorites …"
    queuedSearch = { kind = more and "browseMore" or "browseFavorites" }
    self:Pump()
end

function BW:Select(key)
    if self.running or self.benchmark or purchase or post or baitWait or self.finding then return end
    local info = AH.GetItemKeyInfo(key)
    if not info or not info.itemName or info.itemName == "" then return end
    self.repeatBait = nil
    local stackSize = C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(key.itemID)
    if not stackSize or stackSize < 1 then
        stackSize = select(8, C_Item.GetItemInfo(key.itemID))
    end
    self.target = {
        key = key, id = keyID(key), name = info.itemName, commodity = not not info.isCommodity,
        browseName = info.itemName,
        stackSize = stackSize and math.max(1, stackSize) or 1,
    }
    self.current, self.updatedAt, self.low, self.offers, self.metrics, self.notice = nil, nil, nil, nil, nil, nil
    self.currentQuantity = nil
    self:RefreshPrice()
end

function BW:CanStart()
    return self:CanTest() and self.target and self.maxPrice and self.budget and not InCombatLockdown()
end

function BW:CanTest()
    return Addon:CanUseMode(self) and self.open and self.panel and self.panel:IsVisible() and AuctionHouseFrame:GetAlpha() > 0
        and not purchase and not post and not baitWait and not self.finding and not self.running and not self.benchmark
end

function BW:Start(benchmark)
    if benchmark and self:CanTest() then
        if not self.target then
            self.notice = "Select an item from your favorites first."
            return
        elseif not self.maxPrice or self.maxPrice <= 0 or not self.budget or self.budget <= 0 then
            self.notice = "Set a price limit per item and a budget above 0 for the test."
            return
        elseif InCombatLockdown() then
            self.notice = "The test can start after combat."
            return
        end
    end
    if not self:CanStart() then return end
    cancelPriceLookup()
    self.offers, self.notice, self.priceError = nil, nil, nil
    if benchmark then
        self.benchmark = { block = 1, sample = 0 }
        self.metrics = { direct = newStats(), browse = newStats() }
        armBenchmarkTimeout()
    else
        self.spent, self.low, self.misses, self.usedAuctions, self.fallback = 0, nil, 0, {}, false
        refreshReplies = {}
        priceTiming = nil
        self.running = true
        Addon:StartPurchaseStats(self)
        local history = self.db.scanDiagnostics
        local log = {
            fastQuote = not not self.db.fastQuote, fastQuoteX3 = not not self.db.fastQuoteX3,
            fastQuoteQuantity = self:FastQuoteQuantity(),
            diagnosticsVersion = 2,
            timestamp = GetServerTime and GetServerTime() or (time and time()),
            item = self.target.name, itemID = self.target.key.itemID, route = self:Route(), windows = {},
        }
        history[#history + 1] = log
        if #history > 5 then table.remove(history, 1) end
        scanRun, scanWindow = { started = GetTime(), log = log }, nil
        self:BindWheel(true)
    end
    self:Pump()
end

function BW:Stop()
    refreshReplies = {}
    discardPostFastQuote("stopped")
    self.repeatBait = nil
    Addon:StopPurchaseStats(self)
    cancelPriceLookup()
    resumePost, recentPost, baitRequestedAt = nil, nil, nil
    clearOfferHold()
    if readyRetry then readyRetry:Cancel() end
    if recoveryTimer then recoveryTimer:Cancel() end
    recoveryTimer = nil
    readyRetry, resumePurchase = nil, nil
    scanRun, scanWindow, readyWaitSince, priceTiming = nil, nil, nil, nil
    if baitWait then
        baitWait:Cancel()
        baitWait = nil
    end
    if self.benchmark then
        self.benchmark.timer:Cancel()
        self.notice = "Speed comparison stopped."
    end
    self.running, self.benchmark, self.finding, self.offers = false, nil, false, nil
    self:BindWheel(false)
    queuedSearch, cycle = nil, nil
    if request then request.abandoned = true end
    if post and post.confirm then
        logPurchaseEvent(post, "post_cancelled_by_stop")
        post.log.outcome = "cancelled"
        post.log.finishedMs = milliseconds(GetTime() - post.started)
        post.timer:Cancel()
        post = nil
        self.notice = "Posting cancelled."
    end
    if purchase and purchase.stage == "quote" then
        logPurchaseEvent(purchase, "quote_cancelled_by_stop")
        purchase.log.outcome = "cancelled"
        purchase.log.finishedMs = milliseconds(GetTime() - purchase.started)
        purchase.finished = GetTime()
        recentPurchase = purchase
        purchase.timer:Cancel()
        purchase = nil
        AH.CancelCommoditiesPurchase()
        Addon:FlashPurchaseResult(self, false)
    end
end

local function logResumeReply(job, event)
    if job.resumePost then
        local posted = job.resumePost
        posted.log.resumeReplyMs = milliseconds(GetTime() - posted.finished)
        posted.log.resumeResponseMs = milliseconds(GetTime() - job.started)
        logPurchaseEvent(posted, "first_query_reply_after_post", event)
        scanSample("postResumeReplies", posted.log.resumeReplyMs)
    end
    local order = job.resumePurchase
    if not order then return end
    order.log.resumeReplyMs = milliseconds(GetTime() - order.finished)
    order.log.resumeResponseMs = milliseconds(GetTime() - job.started)
    logPurchaseEvent(order, "first_query_reply", event)
end

local function onBrowse(event)
    local job = request
    if not job or not job.kind:find("^browse") then return end
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" and job.kind ~= "browseMore" then return end
    clearRequest()
    if job.abandoned then BW:Pump() return end
    logResumeReply(job, event)

    local rows = AH.GetBrowseResults()
    if job.manual then
        BW.favorites = rows
        BW.searchMore = not AH.HasFullBrowseResults()
        BW.finding, BW.notice = false, nil
    else
        scanSample("browseReplies", milliseconds(GetTime() - job.started))
        local match
        for _, row in ipairs(rows) do
            if keyID(row.itemKey) == BW.target.id
                or (BW.target.commodity and row.itemKey.itemID == BW.target.key.itemID) then
                match = row
                break
            end
        end
        local quoteQuantity = BW.db.fastQuoteX3 and BW:FastQuoteQuantity() or 1
        if BW.running and not cycle.preview and not purchase and not BW.db.leaveBait and BW.target.commodity
            and match and ((BW.db.fastQuoteX3 and (match.totalQuantity or 0) >= quoteQuantity)
                or (not BW.db.fastQuoteX3 and (match.totalQuantity == 1 or (BW.db.fastQuote and (match.totalQuantity or 0) > 1))))
            and match.containsOwnerItem == false
            and not match.containsAccountItem and (match.minPrice or 0) > 0
            and match.minPrice <= (BW.maxPrice or 0) and match.minPrice * quoteQuantity <= buyingRoom() then
            local single = match.totalQuantity == 1
            local source = BW.db.fastQuoteX3 and "browse_fast_quote_x3" or single and "browse_single" or "browse_fast_quote"
            recordPrice(match.minPrice, single and 1 or nil)
            BW.offers = { { unit = match.minPrice, quantity = quoteQuantity, fixedQuantity = quoteQuantity, fromBrowse = source,
                browseQuantity = match.totalQuantity } }
            cycle.done, cycle.answeredAt = true, BW.updatedAt
            scanSample(BW.db.fastQuoteX3 and "fastBrowseOffersX3" or single and "singleItemBrowseOffers" or "fastBrowseOffers")
            holdOffer()
        elseif BW.running and not cycle.preview and not purchase and BW.db.fastQuoteX3
            and not BW.db.leaveBait and BW.target.commodity and (match or AH.HasFullBrowseResults()) then
            -- Keep this experimental path at the configured quantity: no detail
            -- fallback that could silently turn the attempt into a one-item buy.
            BW.offers = nil
            recordPrice(match and (match.minPrice or 0) > 0 and match.minPrice or nil, match and match.totalQuantity == 1 and 1 or nil)
            cycle.done, cycle.answeredAt = true, GetTime()
        elseif not match and not AH.HasFullBrowseResults() then
            cycle.next = "browseMore"
        elseif not match or not BW.target.commodity or match.containsOwnerItem or not match.minPrice
            or match.minPrice <= 0
            or (cycle.preview and match.totalQuantity ~= 1)
            or (not cycle.preview and match.minPrice <= (BW.maxPrice or 0) and match.minPrice <= buyingRoom()) then
            -- A missing browse group does not establish that this item has no buyouts.
            if match and BW.target.commodity and not match.containsOwnerItem and (match.minPrice or 0) > 0 then
                recordPrice(match.minPrice, match.totalQuantity == 1 and 1 or nil)
            end
            cycle.next = "list"
        else
            BW.offers = nil
            recordPrice(match.minPrice, match.totalQuantity == 1 and 1 or nil)
            if cycle.preview then
                finishCycle(true)
            else
                cycle.done, cycle.answeredAt = true, BW.updatedAt
            end
        end
    end
    BW:Pump()
end

local function onListings(event, key)
    local job = request
    if not job or (job.kind ~= "list" and job.kind ~= "listMore") then return end
    if event:find("^COMMODITY") then
        if not job.commodity or key ~= job.itemID then return end
    elseif job.commodity or keyID(key) ~= job.id then
        return
    end
    clearRequest()
    if job.abandoned then BW:Pump() return end
    logResumeReply(job, event)

    local full
    if job.commodity then
        full = AH.HasFullCommoditySearchResults(job.itemID)
    else
        full = AH.HasFullItemSearchResults(BW.target.key)
    end
    local lowest, offers, lowestQuantity = collectOffers(BW.target)
    -- The fallback after a post must keep the selected Buy Bait batch size.
    if BW.running and not cycle.preview and BW.target.commodity and not BW.db.leaveBait
        and (BW.db.fastQuote or BW.db.fastQuoteX3) then
        local quantity = BW.db.fastQuoteX3 and BW:FastQuoteQuantity() or 1
        if offers[1] and offers[1].quantity >= quantity then
            offers[1].quantity, offers[1].fixedQuantity = quantity, quantity
        else
            offers = {}
        end
    end
    scanSample("listingReplies", milliseconds(GetTime() - job.started))
    listingReply = {
        event = event, ms = milliseconds(GetTime() - job.started), at = GetTime(), full = full,
        route = cycle.route, refreshed = job.refreshed,
    }
    BW.offers = not cycle.preview and offers or nil
    if job.resumePost then
        job.resumePost.log.resumeHasOffer = BW:Offer() ~= nil
    end
    -- A usable first page can already supply a commodity minimum or a buyable listing.
    if full or (job.commodity and lowest) or (BW.running and BW:Offer()) then
        local confirmedQuantity = (full or (lowestQuantity or 0) > 1) and lowestQuantity or nil
        recordPrice(lowest, confirmedQuantity)
        if cycle.preview then
            finishCycle(true)
        else
            cycle.done, cycle.answeredAt = true, BW.updatedAt
            if BW.running and not purchase and BW:Offer() then holdOffer() end
        end
    else
        if lowest then recordPrice(lowest) end
        cycle.next = "listMore"
    end
    BW:Pump()
end

local function finishPurchase(success, message, missed)
    local bought = purchase
    if not bought then return end
    if bought.timer then bought.timer:Cancel() end
    logPurchaseEvent(bought, success and "purchase_succeeded" or "purchase_ended", message)
    bought.log.outcome = success and "confirmed" or missed and "missed" or (bought.timedOut and "unconfirmed" or "ended")
    bought.log.resultMessage = logValue(message)
    bought.log.finishedMs = milliseconds(GetTime() - bought.started)
    bought.finished = GetTime()
    if bought.postQuote then
        bought.postQuote.log.fastQuoteOutcome = bought.log.outcome
        bought.postQuote.log.fastQuoteFinishedMs = milliseconds(bought.finished - bought.postQuote.finished)
        if success and resumePost == bought.postQuote then resumePost = nil end
        -- Failed quotes leave resumePost intact for a fresh detailed query.
    end
    recentPurchase = bought
    if BW.running and BW.open then resumePurchase = bought end
    if BW.running and BW.open and not success and not bought.auctionID and bought.stage == "confirmed" then
        -- A failure event may arrive while the AH still reports the old ready
        -- state. Avoid immediately sending a scan into the unfinished transaction.
        pauseRecovery(bought, recoveryDelay, "confirmed_purchase_failed")
    end
    purchase = nil
    Addon:FlashPurchaseResult(BW, success)
    Addon:RecordPurchaseStats(BW, bought, success, missed)
    if success then
        BW.spent = BW.spent + bought.cost
        BW.purchaseSpent = BW.purchaseSpent + bought.cost
        BW.unitsBought = BW.unitsBought + bought.quantity
        BW.purchases[#BW.purchases + 1] = {
            name = bought.name, quantity = bought.quantity, cost = bought.cost,
            normalPrice = bought.normalPrice, estimatedProfit = bought.log.estimatedProfit,
        }
        if bought.auctionID then BW.usedAuctions[bought.auctionID] = true end
    elseif missed then
        BW.missedPurchases = BW.missedPurchases + 1
        BW.unitsMissed = BW.unitsMissed + bought.quantity
    end
    BW.currentQuantity = nil
    BW.notice = message
    BW.offers = nil
    if sendingPurchase then
        C_Timer.After(0, function() BW:Pump() end)
    else
        BW:Pump()
    end
end

local function sendPurchase(method, ...)
    local order = purchase
    local previous = sendingPurchase
    sendingPurchase = true
    local ok, result = pcall(method, ...)
    sendingPurchase = previous
    if not ok then logPurchaseEvent(order, "lua_api_error", result) end
    return ok, result
end

function BW:PurchasePending()
    return purchase ~= nil
end

function BW:PurchaseUnconfirmed()
    return purchase and purchase.timedOut
end

function BW:Buy()
    if self:ContinueBaitOnInput() then return end
    if not self.running or not self.open then return end
    -- This is a real wheel/button input. Reserve posting for this input only;
    -- sale notifications and timers must never call a protected posting API.
    if self:HandleRepeatBait() then return end
    local clickedAt, isReady = GetTime(), ready()
    observeReadiness(isReady)
    scanSample("wheelClicks")
    if priceTiming then
        priceTiming.clicks = priceTiming.clicks + 1
        priceTiming.firstClickAt = priceTiming.firstClickAt or clickedAt
    end
    local blocked = self.panel.helpPage and self.panel.helpPage:IsShown() and "help"
        or purchase and "purchase" or post and "post" or baitWait and "bait"
        or recoveryTimer and "recovery"
        or request and "request" or not isReady and "throttle"
        or InCombatLockdown() and "combat"
        or (not self.panel:IsVisible() or AuctionHouseFrame:GetAlpha() == 0) and "hidden"
    if blocked then
        scanSample("wheelBlocked_" .. blocked)
        if priceTiming then priceTiming.blocked = priceTiming.blocked + 1 end
        return
    end
    local offer = self:Offer()
    if not offer then
        scanSample("wheelBlocked_noOffer")
        if priceTiming then priceTiming.blocked = priceTiming.blocked + 1 end
        return
    end

    local order = {
        auctionID = offer.auctionID, itemID = self.target.key.itemID, quantity = offer.quantity,
        cost = offer.cost, unit = offer.unit, stage = offer.auctionID and "sent" or "quote",
        name = self.target.name, leaveBait = self.db.leaveBait,
        tradeKey = self.target.id,
        normalPrice = Addon:LearnedNormalPrice(self, self.target.id),
        quoteOnly = offer.quoteOnly, postQuote = offer.postQuote,
    }
    local details = not offer.fromBrowse and not offer.quoteOnly and listingReply
    order.started = GetTime()
    order.log = {
        diagnosticsVersion = 2,
        priceReadyMs = priceTiming and priceTiming.readyAt and milliseconds(priceTiming.readyAt - priceTiming.at),
        readyToClickMs = priceTiming and priceTiming.readyAt and milliseconds(clickedAt - priceTiming.readyAt),
        firstClickPriceAgeMs = priceTiming and priceTiming.firstClickAt and milliseconds(priceTiming.firstClickAt - priceTiming.at),
        priceWheelClicks = priceTiming and priceTiming.clicks,
        priceBlockedClicks = priceTiming and priceTiming.blocked,
        timestamp = GetServerTime and GetServerTime() or (time and time()),
        item = order.name, itemID = order.itemID, auctionID = order.auctionID, quantity = order.quantity,
        expectedUnit = order.unit, expectedTotal = order.cost, maxUnit = self.maxPrice,
        learnedNormalPrice = order.normalPrice,
        remainingBudget = self:Remaining(), leaveBait = not not order.leaveBait,
        route = offer.quoteOnly and "post_quote" or offer.fromBrowse and "browse" or details and details.route,
        lowestQuantity = not offer.quoteOnly and self.currentQuantity or nil,
        offerSource = offer.quoteOnly and "post_fast_quote" or offer.fromBrowse or "listings",
        quoteOnly = offer.quoteOnly,
        fastQuote = not not self.db.fastQuote, fastQuoteX3 = not not self.db.fastQuoteX3,
        fastQuoteQuantity = self:FastQuoteQuantity(),
        browseQuantity = offer.browseQuantity,
        priceAgeMs = not offer.quoteOnly and self.updatedAt and milliseconds(order.started - self.updatedAt),
        listingAgeMs = details and milliseconds(order.started - details.at) or nil,
        listingResponseMs = details and details.ms or nil,
        listingEvent = details and details.event or nil,
        listingRefreshed = details and details.refreshed,
        fullListing = details and details.full,
        refreshAverageMs = self:RefreshAverage(), outcome = "pending", events = {},
    }
    local history = self.db.purchaseDiagnostics
    scanSample("purchaseAttempts")
    history[#history + 1] = order.log
    if #history > purchaseLogLimit then table.remove(history, 1) end
    order.statsKey, order.statsTitle = Addon:PurchaseStatsKey(self)
    if order.postQuote then
        postFastQuote = nil -- One attempt per confirmed bait, never a quote loop.
        order.postQuote.log.fastQuoteSendMs = milliseconds(order.started - order.postQuote.finished)
        logPurchaseEvent(order.postQuote, "post_fast_quote_sent", order.quantity)
        scanSample("postFastQuoteAttempts")
    end
    purchase = order
    if recentPost and not recentPost.log.firstBuyMs and recentPost.itemID == order.itemID then
        recentPost.log.firstBuyMs = milliseconds(GetTime() - recentPost.finished)
        if recentPost.log.buyReadyMs then
            recentPost.log.buyReadyToClickMs = recentPost.log.firstBuyMs - recentPost.log.buyReadyMs
        end
        logPurchaseEvent(recentPost, "first_buy_after_post", order.quantity)
    end
    clearOfferHold()
    self.offers = nil
    self.currentQuantity = nil
    self.notice = nil
    local ok
    if order.auctionID then
        logPurchaseEvent(order, "PlaceBid")
        ok = sendPurchase(AH.PlaceBid, order.auctionID, order.cost)
    else
        logPurchaseEvent(order, "StartCommoditiesPurchase")
        ok = sendPurchase(AH.StartCommoditiesPurchase, order.itemID, order.quantity)
    end
    if not ok and purchase == order then
        finishPurchase(false, "The auction house rejected the purchase.")
    elseif purchase == order and not order.timer then
        self:WatchPurchase(order)
    end
end

function BW:PostStatus()
    if baitWait then
        if self:PostReady() then return "Bait ready · scroll or click to post." end
        return "Bait reserved · scroll or click once ready."
    end
    if not post then return end
    return post.confirm and "Confirm bait · scroll or click." or "Waiting for auction confirmation …"
end

function BW:PostReady()
    return not request and not sending and not sendingPurchase and ready()
end

function BW:PostWaiting()
    return baitWait ~= nil
end

function BW:PostNeedsConfirmation()
    return post and post.confirm
end

local function cancelBaitWait()
    if baitWait then baitWait:Cancel() end
    baitWait, baitRequestedAt = nil, nil
    if not BW.running then BW:BindWheel(false) end
end

function BW:ContinueBaitOnInput()
    if not baitWait and not (post and post.confirm) then return false end
    -- A pending manual Bait click takes priority over buying, even with
    -- Repeat bait off. Only the actual wheel input can continue the post.
    if not self.open or not Addon:CanUseMode(self) or InCombatLockdown() or not self.panel:IsVisible()
        or AuctionHouseFrame:GetAlpha() == 0 or self.benchmark or purchase or recoveryTimer
        or (post and not post.confirm) or (self.panel.helpPage and self.panel.helpPage:IsShown()) then return true end
    if self:PostReady() then
        self:PostOne()
        scanSample("baitContinuedByWheel")
    end
    return true
end

function BW:BaitAge()
    local bait = self.lastBait
    if not bait then return end
    return math.max(0, (bait.soldAt or GetTime()) - bait.postedAt), bait.soldAt ~= nil
end

function BW:HasLiveBait()
    if not self.target then return false end
    for _, bait in ipairs(trackedBaits) do
        if bait.targetID == self.target.id then return true end
    end
    return false
end

function BW:SetRepeatBait(enabled)
    if not enabled then
        discardPostFastQuote("repeat_disabled")
        if self.repeatBait and baitWait then
            baitWait:Cancel()
            baitWait, baitRequestedAt = nil, nil
        end
        self.repeatBait = nil
        self:Pump()
        return
    end
    if not self.open or not self.target or self.benchmark or post or purchase or self.finding then return end
    self.repeatBait = self.target.id
end

function BW:HandleRepeatBait()
    if not self.repeatBait then return false end
    if not self.target or self.repeatBait ~= self.target.id then
        self.repeatBait = nil
        return false
    end
    if self:HasLiveBait() then return false end
    if not Addon:CanUseMode(self) or InCombatLockdown() or not self.panel:IsVisible()
        or AuctionHouseFrame:GetAlpha() == 0 or self.benchmark or purchase or recoveryTimer
        or (post and not post.confirm) or (self.panel.helpPage and self.panel.helpPage:IsShown()) then return true end
    self:PostOne()
    return true
end

local function plainSaleText(value)
    return value:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :match("^%s*(.-)%s*$")
end

local function localizedSaleName(plain)
    if type(ERR_AUCTION_SOLD_S) ~= "string" then return end
    -- Build a Lua pattern from the client's translated sale message. Escape
    -- punctuation and support both %s and the positional %1$s placeholder.
    local template = plainSaleText(ERR_AUCTION_SOLD_S):gsub("%%1%$s", "\001"):gsub("%%s", "\001")
    local pattern = template:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):gsub("\001", "(.-)")
    if not template:find("\001", 1, true) then return end
    return plain:match("^" .. pattern .. "$")
end

local function recordBaitSale(message, source)
    if type(message) ~= "string" then return end
    local plain = plainSaleText(message)
    local localizedName = localizedSaleName(plain)
    if source == "chat" and not localizedName
        and not plain:find("[Bb]uyer has been found")
        and not (plain:find("[Aa]uction") and plain:find("sold"))
        and not (plain:find("[Aa]uktion") and (plain:find("Käufer") or plain:find("verkauft"))) then return end
    local itemID = tonumber(message:match("|Hitem:(%d+)"))
    local name = localizedName
        or plain:match("[Aa]uction of (.-) has been sold")
        or plain:match("[Aa]uction of (.-) has sold")
        or plain:match("[Aa]uction of (.-)%.?%s*$")
        or plain:match("%[(.-)%]")
        or (source == "notification" and plain)
    if name then
        name = name:match("^%s*(.-)%s*$"):gsub("%s*[xX]%s*%d+$", "")
            :gsub("%s*%(%d+%)$", ""):gsub("^%[(.-)%]$", "%1")
    end
    local function matches(bait)
        if itemID then return itemID == bait.itemID end
        return name == bait.name
    end
    local now = GetTime()
    -- A sale may produce both a formatted notification and a system-chat
    -- message. Pair the two channels without suppressing consecutive sales
    -- on the same channel (including several sales within one second).
    for i = #recentBaitSales, 1, -1 do
        if now - recentBaitSales[i].at > 5 then table.remove(recentBaitSales, i) end
    end
    for i, receipt in ipairs(recentBaitSales) do
        if receipt.source ~= source and matches(receipt) then
            table.remove(recentBaitSales, i)
            return true
        end
    end
    -- Only the latest confirmed bait per item is timed. A missing sale message
    -- for an older bait must not consume the newer bait's eventual sale.
    for i, bait in ipairs(trackedBaits) do
        if matches(bait) then
            bait.soldAt = now
            Addon:RecordBaitSale(bait)
            table.remove(trackedBaits, i)
            recentBaitSales[#recentBaitSales + 1] = {
                itemID = bait.itemID, name = bait.name, source = source, at = now,
            }
            return true
        end
    end
end

local function finishPost(message, success)
    if not post then return end
    local posted = post
    -- An unknown/failed outcome must be checked manually before another post.
    if not success then BW.repeatBait = nil end
    posted.finished = GetTime()
    if posted.log then
        posted.log.finishedMs = milliseconds(posted.finished - posted.started)
        posted.log.outcome = success and "posted" or "failed"
        logPurchaseEvent(posted, success and "post_succeeded" or "post_ended", message)
        scanSample(success and "postSucceeded" or "postFailed")
    end
    if success and BW.open and BW.panel:IsVisible() then
        recentPost = posted
        if BW == Addon.Single then resumePost = posted end
    end
    if success then
        Addon:NoteOwnPost(posted.itemID, posted.price, postDuration, 1, true)
        Addon:AnnounceBait(BW, posted.target, posted.price, false)
        local bait = { postedAt = posted.finished, itemID = posted.itemID, name = posted.target.name,
            targetID = posted.target.id, price = posted.price, log = posted.log }
        Addon:RecordBaitPost(BW, bait)
        for i = #trackedBaits, 1, -1 do
            if trackedBaits[i].itemID == bait.itemID then table.remove(trackedBaits, i) end
        end
        BW.lastBait = bait
        trackedBaits[#trackedBaits + 1] = bait
    end
    if success and post.duringGo then
        BW.baitsPosted = BW.baitsPosted + 1
    end
    post.timer:Cancel()
    post = nil
    cancelBaitWait()
    if success then
        local quantity = BW:PostFastQuoteQuantity()
        if quantity then
            postFastQuote = { posted = posted, quantity = quantity, cap = BW.maxPrice }
            posted.log.fastQuoteQuantity = quantity
        end
    end
    BW.notice = message
    if success and BW.open then
        BW.offers, BW.currentQuantity = nil, nil
        if not BW.running and BW.panel:IsVisible() and AuctionHouseFrame:GetAlpha() > 0 then BW:RefreshPrice() end
    end
    if sendingPurchase then
        C_Timer.After(0, function() BW:Pump() end)
    else
        BW:Pump()
    end
end

local function sellableLocation(bag, slot, target)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or info.itemID ~= target.key.itemID or info.isLocked then return end
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if not AH.IsSellItemValid(loc, false) or (AH.GetAvailablePostCount(loc) or 0) < 1 then return end
    local commodity = AH.GetItemCommodityStatus(loc) == Enum.ItemCommodityStatus.Commodity
    if commodity ~= target.commodity then return end
    if commodity or keyID(AH.GetItemKeyFromItem(loc)) == target.id then return loc end
end

local function findSellableItem(target)
    local reagentBag = Enum.BagIndex and Enum.BagIndex.ReagentBag
    for index = 0, lastBag + 1 do
        local bag = index <= lastBag and index or reagentBag
        if bag and (index <= lastBag or bag > lastBag) then
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local loc = sellableLocation(bag, slot, target)
                if loc then return bag, slot, loc end
            end
        end
    end
end

function BW:PostOne()
    if not Addon:CanUseMode(self) then return end
    if not self.open or not self.target or not self.panel:IsVisible() or AuctionHouseFrame:GetAlpha() == 0
        or InCombatLockdown() or purchase or self.benchmark or self.finding or (post and not post.confirm) then return end
    local target = self.target
    if self.repeatBait and not post and self:HasLiveBait() then
        self.notice = "Repeat bait · waiting for the current bait to sell."
        return
    end
    local bag, slot, loc
    if not post then
        bag, slot, loc = findSellableItem(target)
        if not loc then
            self.repeatBait = nil
            if baitWait then cancelBaitWait() self:Pump() end
            Addon:Notify(self, "No sellable " .. target.name .. " in your bags for bait.")
            return
        end
    end
    local price = tonumber(self.db.baitPrice)
    if not price or price < 1 or price >= 10000000000000 or price ~= math.floor(price)
        or (not target.commodity and price < 100) then
        self.repeatBait = nil
        self.notice = target.commodity and "Set a Bait sell price of at least 1 copper."
            or "Set a Bait sell price of at least 1 silver."
        cancelBaitWait()
        if post then finishPost(self.notice) end
        return
    end
    if AH.SupportsCopperValues and not AH.SupportsCopperValues() and price % 100 ~= 0 then
        self.repeatBait = nil
        self.notice = "Invalid price · the auction house only accepts whole silver amounts."
        cancelBaitWait()
        if post then finishPost(self.notice) end
        return
    end
    -- Fingerprint: the nearest price that marks this bait as one of BuyWheel's.
    if target.commodity and (not AH.SupportsCopperValues or AH.SupportsCopperValues()) then
        price = Addon:FingerprintPrice(price, target.key.itemID)
    end

    if not self:PostReady() then
        if not baitWait then
            baitRequestedAt = GetTime()
            baitWait = C_Timer.NewTimer(10, function()
                scanSample("baitWaitExpired", milliseconds(GetTime() - baitRequestedAt))
                baitRequestedAt = nil
                baitWait = nil
                if not self.running and not (post and post.confirm) then self:BindWheel(false) end
                self.notice = "Bait wait cancelled · scanning continues."
                self:Pump()
            end)
        end
        if not self.running then self:BindWheel(true) end
        return
    end
    if baitWait then
        baitWait:Cancel()
        baitWait = nil
        -- Restore the observation if validation below prevents sending the post.
        C_Timer.After(0, function() self:Pump() end)
    end

    local order = post
    local confirming = order ~= nil
    if confirming and baitRequestedAt then
        order.log.confirmWaitMs = milliseconds(GetTime() - baitRequestedAt)
        baitRequestedAt = nil
    end
    if confirming then
        loc = sellableLocation(order.bag, order.slot, target)
        if not loc then
            local message = "No sellable " .. target.name .. " in your bags for bait."
            finishPost(message)
            Addon:Notify(self, message)
            return
        end
        if order.price ~= price or order.target ~= target
            or (order.guid and C_Item.GetItemGUID(loc) ~= order.guid) then
            finishPost("Item or price changed · click Bait again.")
            return
        end
        order.timer:Cancel()
        order.confirm = false
    else
        discardPostFastQuote("new_bait")
        order = {
            bag = bag, slot = slot, target = target, price = price,
            guid = C_Item.GetItemGUID and C_Item.GetItemGUID(loc),
            duringGo = self.running,
        }
        order.started, order.itemID, order.stage = GetTime(), target.key.itemID, "posting"
        order.log = { timestamp = GetServerTime(), item = target.name, itemID = order.itemID,
            price = price, duringGo = not not order.duringGo, outcome = "pending", events = {},
            beforeSendWaitMs = baitRequestedAt and milliseconds(order.started - baitRequestedAt) or 0 }
        baitRequestedAt = nil
        self.db.postDiagnostics = self.db.postDiagnostics or {}
        local history = self.db.postDiagnostics
        history[#history + 1] = order.log
        if #history > 50 then table.remove(history, 1) end
        scanSample("postAttempts")
        post = order
        cancelPriceLookup()
        clearOfferHold()
        cycle = nil
        self.offers = nil
    end

    order.timer = C_Timer.NewTimer(10, function()
        if post == order then finishPost("No response to posting · check your auctions.") end
    end)
    local method
    if target.commodity then
        method = confirming and AH.ConfirmPostCommodity or AH.PostCommodity
    else
        method = confirming and AH.ConfirmPostItem or AH.PostItem
    end
    local ok, needsConfirm
    order.stage = "posting"
    logPurchaseEvent(order, confirming and "ConfirmPost" or "Post", ready())
    if target.commodity then
        ok, needsConfirm = sendPurchase(method, loc, postDuration, 1, price)
    else
        ok, needsConfirm = sendPurchase(method, loc, postDuration, 1, nil, price)
    end
    if post ~= order then return end
    if not ok then
        finishPost("The auction house rejected the listing.")
    elseif not confirming and needsConfirm then
        order.confirm = true
        if not self.running then self:BindWheel(true) end
        order.stage = "confirmation"
        logPurchaseEvent(order, "post_needs_confirmation")
        order.timer:Cancel()
        order.timer = C_Timer.NewTimer(30, function()
            if post == order then finishPost("Posting was not confirmed.") end
        end)
        C_Timer.After(0, function()
            if post == order and order.confirm and StaticPopup_Visible
                and StaticPopup_Visible("AUCTION_HOUSE_POST_WARNING") then
                StaticPopup_Hide("AUCTION_HOUSE_POST_WARNING")
            end
        end)
    end
end

function BW:WatchPurchase(order)
    if order.timer then order.timer:Cancel() end
    order.timer = C_Timer.NewTimer(order.stage == "quote" and quoteTimeout or 8, function()
        if purchase ~= order then return end
        logPurchaseEvent(order, "purchase_timeout")
        if order.stage == "quote" then
            order.stage = "cancel"
            sendPurchase(AH.CancelCommoditiesPurchase)
            finishPurchase(false, "No price quote received.")
        else
            -- Resume reading prices, but keep the order until a late answer can settle it.
            order.timedOut = true
            order.log.outcome = "unconfirmed"
            BW:Pump()
        end
    end)
end

local function onQuote(unit, total)
    local order = purchase
    if not order or order.stage ~= "quote" then return end
    logPurchaseEvent(order, "COMMODITY_PRICE_UPDATED", unit, total)
    order.log.quotedUnit, order.log.quotedTotal = logValue(unit), logValue(total)
    if not BW.running or not unit or not total or unit <= 0 or total <= 0
        or unit > (BW.maxPrice or 0) or total > (BW.maxPrice or 0) * order.quantity
        or total > order.cost or total > buyingRoom()
        or (order.quoteOnly and total ~= unit * order.quantity)
        or (order.leaveBait and (unit ~= order.unit or total ~= order.cost)) then
        -- A direct post probe has no observed listing to count as "missed".
        local priceIncreased = not order.quoteOnly and BW.running and unit and total and unit > 0 and total > 0
            and (unit > order.unit or total > order.cost)
        order.stage = "cancel"
        logPurchaseEvent(order, "quote_rejected")
        sendPurchase(AH.CancelCommoditiesPurchase)
        finishPurchase(false, "Price quote changed or exceeded the limit.", priceIncreased)
        return
    end
    order.stage, order.cost = "confirmed", total
    logPurchaseEvent(order, "ConfirmCommoditiesPurchase", ready())
    if not sendPurchase(AH.ConfirmCommoditiesPurchase, order.itemID, order.quantity) and purchase == order then
        finishPurchase(false, "The auction house rejected the confirmation.", true)
    elseif purchase == order then
        BW:WatchPurchase(order)
    end
end

local function rejectPurchase(message)
    local order = purchase
    -- Once price queries resume, generic errors can also belong to those queries.
    if not order or order.timedOut or order.stage == "cancel" then return end
    if order.stage == "quote" then
        order.stage = "cancel"
        sendPurchase(AH.CancelCommoditiesPurchase)
    end
    if purchase == order then finishPurchase(false, message, true) end
end

local browseMethods = { "SendBrowseQuery", "SearchForFavorites", "SearchForItemKeys", "RequestMoreBrowseResults" }
local listingMethods = { "SendSearchQuery", "SendSellSearchQuery", "RefreshItemSearchResults",
    "RefreshCommoditySearchResults", "RequestMoreItemSearchResults", "RequestMoreCommoditySearchResults" }

local function installHooks()
    if hooked then return end
    hooked = true
    local function interfere(isBrowse, key)
        if not BW.open or sending then return end
        local sameItem = BW.target and (type(key) == "table" and keyID(key) == BW.target.id
            or key == BW.target.key.itemID)
        local waitingBrowse = request and request.kind:find("^browse")
        if request and not request.abandoned and ((isBrowse and waitingBrowse) or (sameItem and not waitingBrowse)) then
            -- Browse events carry no query identity. Let this request drain or time out.
            request.abandoned = true
            if request.manual then BW.finding = false end
            if cycle and cycle.preview then
                finishCycle(false)
            else
                cycle = nil
            end
            BW.notice = "Another auction house query interfered · retrying."
        end
    end
    for _, method in ipairs(browseMethods) do
        if AH[method] then hooksecurefunc(AH, method, function() interfere(true) end) end
    end
    for _, method in ipairs(listingMethods) do
        if AH[method] then hooksecurefunc(AH, method, function(key) interfere(false, key) end) end
    end
end

local handlers = {
    ADDON_LOADED = function(name)
        if name ~= addonName then return end
        BW.db = Addon:GetModeDB("single")
        BW.db.maxPrice = BW.db.maxPrice or legacyMoney(BW.db.maxPriceText)
        BW.db.budget = BW.db.budget or legacyMoney(BW.db.budgetText)
        BW.db.maxPriceText, BW.db.budgetText = nil, nil
        BW.db.routes = type(BW.db.routes) == "table" and BW.db.routes or {}
        BW.db.purchaseDiagnostics = type(BW.db.purchaseDiagnostics) == "table" and BW.db.purchaseDiagnostics or {}
        BW.db.scanDiagnostics = type(BW.db.scanDiagnostics) == "table" and BW.db.scanDiagnostics or {}
        installHooks()
    end,
    AUCTION_HOUSE_SHOW = function()
        BW.open = true
        C_Timer.After(0, function() if BW.open then BW:Attach() end end)
    end,
    AUCTION_HOUSE_CLOSED = function()
        BW.open = false
        BW:Stop()
        finishPost("Auction house closed · posting result unknown.")
        clearRequest()
        if purchase then
            finishPurchase(false, "Auction house closed · purchase status unknown.")
        end
        BW:HidePanel()
    end,
    PLAYER_REGEN_DISABLED = function() BW:Stop() end,
    PLAYER_REGEN_ENABLED = function() if not BW.running then BW:BindWheel(false) end end,
    PLAYER_MONEY = function() BW:Pump() end,
    AUCTION_HOUSE_FAVORITES_UPDATED = function()
        BW.favoritesPending = true
    end,
    AUCTION_HOUSE_THROTTLED_SYSTEM_READY = function() BW:Pump() end,
    AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED = function()
        if purchase and not purchase.timedOut then logPurchaseEvent(purchase, "throttle_response") end
        if post then logPurchaseEvent(post, "post_throttle_response") end
        BW:Pump()
    end,
    AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED = function()
        if purchase and not purchase.timedOut then logPurchaseEvent(purchase, "throttle_message_dropped") end
        if post then logPurchaseEvent(post, "post_throttle_message_dropped") end
    end,
    UI_ERROR_MESSAGE = function(errorID, message)
        local order = purchase
        if not order and recentPurchase and recentPurchase.finished
            and GetTime() - recentPurchase.finished <= 1 then
            logPurchaseEvent(recentPurchase, "ui_error_after_purchase", errorID, message)
        elseif order and not order.timedOut then
            logPurchaseEvent(order, "ui_error_during_purchase", errorID, message)
        end
    end,
    AUCTION_HOUSE_BROWSE_FAILURE = function()
        if request and request.kind:find("^browse") then
            failRequest("The auction house search failed.", "AUCTION_HOUSE_BROWSE_FAILURE")
            BW:Pump()
        end
    end,
    COMMODITY_PRICE_UPDATED = onQuote,
    COMMODITY_PRICE_UNAVAILABLE = function()
        if purchase and purchase.stage == "quote" then
            logPurchaseEvent(purchase, "COMMODITY_PRICE_UNAVAILABLE")
            finishPurchase(false, "The price is no longer available.", true)
        end
    end,
    COMMODITY_PURCHASE_SUCCEEDED = function()
        if purchase and purchase.stage == "confirmed" then finishPurchase(true) end
    end,
    COMMODITY_PURCHASE_FAILED = function()
        if purchase and not purchase.auctionID then
            logPurchaseEvent(purchase, "COMMODITY_PURCHASE_FAILED")
            finishPurchase(false, "Purchase failed.", true)
        end
    end,
    AUCTION_HOUSE_PURCHASE_COMPLETED = function(auctionID)
        if purchase and purchase.auctionID and purchase.auctionID == auctionID then finishPurchase(true) end
    end,
    AUCTION_HOUSE_AUCTION_CREATED = function()
        if post and not post.confirm then finishPost("Posted 1 item.", true) end
    end,
    AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION = function(note, ...)
        local sold = (Enum.AuctionHouseNotification and Enum.AuctionHouseNotification.AuctionSold) or 4
        if note ~= sold then return end
        -- Some clients supply a raw item name/link rather than full chat text.
        for i = 1, select("#", ...) do
            if recordBaitSale(select(i, ...), "notification") then return end
        end
    end,
    CHAT_MSG_SYSTEM = function(message)
        recordBaitSale(message, "chat")
    end,
    AUCTION_HOUSE_POST_ERROR = function()
        finishPost("The auction house rejected the listing.")
    end,
    AUCTION_HOUSE_SHOW_ERROR = function(errorCode)
        if purchase or post then
            local message = AuctionHouseUtil and AuctionHouseUtil.GetErrorText and AuctionHouseUtil.GetErrorText(errorCode)
            if post then
                finishPost(message or "The auction house rejected the listing.")
            else
                logPurchaseEvent(purchase, "AUCTION_HOUSE_SHOW_ERROR", errorCode, message)
                rejectPurchase(message or "The auction house rejected the purchase.")
            end
        end
    end,
    ADDON_ACTION_BLOCKED = function(name)
        if name ~= addonName then return end
        if post then
            finishPost("WoW blocked posting.")
        elseif purchase then
            finishPurchase(false, "WoW blocked the purchase.")
        end
    end,
    ADDON_ACTION_FORBIDDEN = function(name)
        if name ~= addonName then return end
        if post then
            finishPost("WoW blocked posting.")
        elseif purchase then
            finishPurchase(false, "WoW blocked the purchase.")
        end
    end,
}
for event in pairs(handlers) do
    -- Forever does not expose every event present in other WoW clients.
    pcall(events.RegisterEvent, events, event)
end
for _, event in ipairs({
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
}) do
    events:RegisterEvent(event)
    handlers[event] = function(...) onBrowse(event, ...) end
end
for _, event in ipairs({
    "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED",
}) do
    events:RegisterEvent(event)
    handlers[event] = function(...) onListings(event, ...) end
end
events:SetScript("OnEvent", function(_, event, ...) handlers[event](...) end)

function BW:HasPendingAHWork()
    return request ~= nil or purchase ~= nil or post ~= nil or baitWait ~= nil
end
