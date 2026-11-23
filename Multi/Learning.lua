local _, Addon = ...
local BW = Addon.Multi
local AH = C_AuctionHouse
local sampleInterval = 5
local minimumSamples = 10
local rollingWindow = 600
local maximumSamples = 120
-- A sample this far below the rolling median looks like foreign bait. It is held
-- back unless it persists, so genuine price drops are still followed.
local lowOutlierRatio = 0.65
local lowOutlierPatience = 6

local function medianOfSamples(samples)
    local prices = {}
    for i, sample in ipairs(samples) do prices[i] = sample.price end
    table.sort(prices)
    local middle = math.floor((#prices + 1) / 2)
    return #prices % 2 == 1 and prices[middle] or (prices[middle] + prices[middle + 1]) / 2
end

-- Median of the recent minimum-price samples of an item (nil before enough).
function BW:LiveMinMedian(id)
    local history = self.normalPriceSamples and self.normalPriceSamples[id]
    if history and #history.samples >= minimumSamples then return medianOfSamples(history.samples) end
end

-- Depth probes sent between two minimum-price samples while learning.
local learningDepthBurst, learningDepthGap = 8, 0
-- A run ends by itself once every item has this many depth probes (and enough
-- minimum-price samples). The time limit only guards against a stuck run.
local learningProbeTarget, learningMaxSeconds = 6, 30 * 60

-- Consume complete batch replies already obtained by normal watching. These
-- observations never send queries. They update the normal price and the item's
-- buy limit (percent of the normal price, see ApplyLiveLimit).
function BW:ObserveNormalPrices(rows)
    if not self.running or self.learning or self.benchmark then return end
    local now = GetTime()
    self.normalPriceSamples = self.normalPriceSamples or {}
    for _, row in ipairs(rows) do
        local key, price = row.itemKey, row.minPrice
        if key and key.itemID and type(price) == "number" and price > 0
            and (row.totalQuantity or 0) > 1 and Addon:IsMarketRow(row) then
            local id = self:WatchID(key)
            local watched = self.db.watchItems and self.db.watchItems[id]
            if watched and watched.enabled then
                local history = self.normalPriceSamples[id]
                if not history then
                    history = { samples = {} }
                    self.normalPriceSamples[id] = history
                end
                -- Right after our own buy or bait the lowest price is not the market.
                if not self:OwnActionRecent(id) and (not history.lastAt or now - history.lastAt >= sampleInterval) then
                    history.lastAt = now
                    local samples = history.samples
                    local accept = true
                    if #samples >= minimumSamples
                        and price < medianOfSamples(samples) * lowOutlierRatio then
                        history.lowStreak = (history.lowStreak or 0) + 1
                        accept = history.lowStreak > lowOutlierPatience
                    else
                        history.lowStreak = 0
                    end
                    if accept then
                        samples[#samples + 1] = { at = now, price = price }
                    end
                    while samples[1] and (samples[1].at < now - rollingWindow or #samples > maximumSamples) do
                        table.remove(samples, 1)
                    end
                    if accept and #samples >= minimumSamples then
                        self.db.learnedPrices = self.db.learnedPrices or {}
                        local learned = self.db.learnedPrices[id] or {}
                        -- Depth samples (if any) anchor the value; the live minimum moves it.
                        local normal = self:NormalFromMeasurements(learned, medianOfSamples(samples))
                        learned.normalPrice, learned.samples = normal, #samples
                        learned.timestamp, learned.live = GetServerTime(), true
                        self:ApplyLiveLimit(id, learned, normal)
                        self.db.learnedPrices[id] = learned
                    end
                end
            end
        end
    end
end

function BW:CanLearn()
    return self:CanTest() and not self.priceLookup and not self.learning
        and not self.favoritesPending and not self:OtherWheelActive()
        and self.favorites and #self.favorites > 0 and AH.SearchForItemKeys ~= nil
end

function BW:StartLearning(percent)
    if not self:CanLearn() then return end
    percent = tonumber(percent)
    if not percent or percent < 1 or percent > 100 then
        self.notice = "Enter a buy percentage from 1–100."
        return
    end
    self.db.learnPercent = percent
    self.learning = { phase = "favorites", percent = percent,
        items = {}, keys = {}, queries = 0, failures = 0 }
    self.notice = nil
    self.favoritesPending = true
    -- Refresh and load every favorites page, including unchecked favorites.
    self:LoadFavorites()
end

-- Share of the work done (0-1): every item needs its depth probes (commodities)
-- and enough minimum-price samples; items without item info count samples only.
-- Deletes everything learned: normal prices, depth measurements, live buffers and
-- the buy limits that came from them, so the next learning run is the only data.
-- Watch checkboxes stay. Returns false while watching or learning.
function BW:ResetLearned()
    if self.running or self.learning or self.benchmark or self:PurchasePending() then
        self.notice = "Stop watching or learning before resetting."
        return false
    end
    local count = 0
    for id, learned in pairs(self.db.learnedPrices or {}) do
        count = count + 1
        local entry = self.db.watchItems and self.db.watchItems[id]
        if entry and learned.maxPrice then entry.maxPrice = 0 end
    end
    -- Own max buy percentages (/bwmax) do not survive a reset.
    for _, entry in pairs(self.db.watchItems or {}) do entry.percent = nil end
    self.db.learnedPrices = {}
    self.db.learningDiagnostics = nil
    self.normalPriceSamples, self.freeDepthAt, self.ownActionAt = {}, {}, {}
    self.depthNextAt = nil
    if self.panel then self.panel.displayedTargetID = nil end
    self.notice = ("Learned data reset (%d items). Run Start Learning Prices before watching."):format(count)
    return true
end

function BW:LearningProgress(session)
    local total, sum = 0, 0
    for _, item in pairs(session.items) do
        total = total + 1
        local info = AH.GetItemKeyInfo(item.key)
        local samples = math.min(1, #item.samples / minimumSamples)
        if info and info.isCommodity then
            sum = sum + math.min(samples, (item.probes or 0) / learningProbeTarget)
        else
            sum = sum + samples
        end
    end
    return total > 0 and math.min(1, sum / total) or 0
end

function BW:LearningFailed(session, reason)
    if self.learning ~= session then return end
    session.failures = session.failures + 1
    session.lastError = reason
    session.waiting = false
    session.nextQueryAt = GetTime() + sampleInterval
end

function BW:LearningReply(session, rows)
    if self.learning ~= session or session.phase ~= "prices" then return end
    if GetTime() >= session.deadline then self:FinishLearning(false) return end
    if not AH.HasFullBrowseResults() then
        self:RequestLearningQuery(true)
        return
    end
    local now = GetTime()
    for _, row in ipairs(rows) do
        local item = session.items[self:WatchID(row.itemKey)]
        local price = row.minPrice
        -- Same filters as live sampling: own/account listings and one-unit rows
        -- are not market prices.
        if item and type(price) == "number" and price > 0 and (row.totalQuantity or 0) > 1
            and Addon:IsMarketRow(row)
            and (not item.lastAt or now - item.lastAt >= 3) then
            item.samples[#item.samples + 1] = price
            item.lastAt = now
            if self.target and self.target.id == self:WatchID(row.itemKey) then
                self.current, self.updatedAt = price, now
                self.currentQuantity = row.totalQuantity == 1 and 1 or nil
            end
        end
    end
    session.waiting = false
    session.lastBrowseAt = now
    -- Depth probes follow before the next minimum-price sample.
    session.depthBurst = AH.SendSearchQuery and learningDepthBurst or 0
    session.nextQueryAt = now + (session.depthBurst > 0 and learningDepthGap or sampleInterval)
    self:TickLearning()
end

-- A depth probe answered during a learning run.
function BW:LearningDepthReply(session, id, price)
    if self.learning ~= session or session.phase ~= "prices" then return end
    local item = session.items[id]
    if item then
        -- A probe counts as done even in a market too thin for a depth price.
        item.probes = (item.probes or 0) + 1
        if price then
            item.depth = item.depth or {}
            item.depth[#item.depth + 1] = price
        end
    end
    session.waiting = false
    session.nextQueryAt = GetTime() + ((session.depthBurst or 0) > 0 and learningDepthGap or sampleInterval)
    self:TickLearning()
end

function BW:FinishLearning(cancelled)
    local session = self.learning
    if not session then return end
    self:CancelLearningQuery()
    self.learning = nil
    local report = { timestamp = GetServerTime(), cancelled = cancelled,
        seconds = session.started and math.floor(GetTime() - session.started) or 0,
        percent = session.percent, queries = session.queries, failures = session.failures,
        applied = 0, skipped = 0, items = {} }
    self.db.learnedPrices = self.db.learnedPrices or {}
    for id, item in pairs(session.items) do
        local samples = item.samples
        table.sort(samples)
        local count = #samples
        local result = { key = item.key, samples = count }
        if count > 0 then
            local middle = math.floor((count + 1) / 2)
            result.normalPrice = count % 2 == 1 and samples[middle]
                or (samples[middle] + samples[middle + 1]) / 2
            result.minPrice, result.maxPrice = samples[1], samples[count]
        end
        if not cancelled and count >= minimumSamples then
            -- The depth price (median of the depth probes) is the normal price when
            -- there are enough probes; otherwise the median minimum price stays.
            local depths = item.depth or {}
            local minNormal = result.normalPrice
            local learned = { samples = count, timestamp = report.timestamp, percent = session.percent,
                source = "min" }
            if #depths >= 3 then
                -- Lower quartile of the depth probes, and never more than 3% above the median
                -- of the lowest prices.
                local depth = self:LowerQuartile(depths)
                result.normalPrice, result.depthSamples = self:CapNormal(depth, minNormal), #depths
                learned.source, learned.depth, learned.depthAt = "depth", depth, report.timestamp
                learned.depthList = {}
                for _, price in ipairs(depths) do
                    learned.depthList[#learned.depthList + 1] = { at = report.timestamp, price = price }
                end
                while #learned.depthList > 12 do table.remove(learned.depthList, 1) end
                if minNormal and minNormal > 0 then
                    learned.ratio = depth / minNormal
                    learned.ratioList = { learned.ratio }
                end
            end
            -- Keep the long-term price memory across learning runs and cap the new value by it.
            local previous = self.db.learnedPrices[id]
            learned.hist = previous and previous.hist
            result.normalPrice = self:ApplyLongTermAnchor(learned, result.normalPrice, minNormal)
            local entry = self.db.watchItems[id] or { key = item.key, enabled = false }
            result.buyLimit = math.max(1, math.floor(result.normalPrice * (tonumber(entry.percent) or session.percent) / 100))
            result.previousLimit = entry.maxPrice
            entry.maxPrice = result.buyLimit
            self.db.watchItems[id] = entry
            learned.normalPrice, learned.maxPrice = result.normalPrice, result.buyLimit
            self.db.learnedPrices[id] = learned
            if self.normalPriceSamples then self.normalPriceSamples[id] = nil end
            report.applied = report.applied + 1
        else
            report.skipped = report.skipped + 1
        end
        report.items[id] = result
    end
    self.db.learningDiagnostics = self.db.learningDiagnostics or {}
    local history = self.db.learningDiagnostics
    history[#history + 1] = report
    if #history > 5 then table.remove(history, 1) end
    if self.panel then self.panel.displayedTargetID = nil end
    self.notice = cancelled and "Learning cancelled · price limits unchanged."
        or ("Learning complete · %d limits set to %g%% · %d unchanged."):format(report.applied, session.percent, report.skipped)
end

function BW:TickLearning()
    local session = self.learning
    if not session then return end
    if self:OtherWheelActive() then self:FinishLearning(true) return end
    if session.phase == "favorites" then
        if self.finding then return end
        if self.favoritesError then self:FinishLearning(true) return end
        if self.favoritesPending then self:LoadFavorites() return end
        if self.searchMore then self:LoadFavorites(true) return end
        for _, row in ipairs(self.favorites or {}) do
            local id = self:WatchID(row.itemKey)
            if not session.items[id] then
                session.items[id] = { key = row.itemKey, samples = {} }
                session.keys[#session.keys + 1] = row.itemKey
            end
        end
        if #session.keys == 0 then self:FinishLearning(true) return end
        session.phase, session.started = "prices", GetTime()
        session.deadline = session.started + learningMaxSeconds
        session.nextQueryAt = session.started
    end
    if GetTime() >= session.deadline or self:LearningProgress(session) >= 1 then
        self:FinishLearning(false)
        return
    end
    if not session.waiting and GetTime() >= session.nextQueryAt then
        session.waiting = true
        if (session.depthBurst or 0) > 0 and self:RequestLearningDepth(session) then
            session.depthBurst = session.depthBurst - 1
        else
            session.depthBurst = 0
            -- Minimum-price samples are at least 3 seconds apart.
            local due = (session.lastBrowseAt or 0) + 3
            if GetTime() < due then
                session.waiting = false
                session.nextQueryAt = due
            else
                self:RequestLearningQuery(false)
            end
        end
    end
end

function BW:LearningStatus()
    local session = self.learning
    if not session then return end
    if session.phase == "favorites" then return "Learning · loading all favorites …" end
    -- The progress in percent is shown on the Start learning button.
    return ("Learning %d favorites · apply %g%%"):format(#session.keys, session.percent)
end
