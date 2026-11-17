local _, Addon = ...
local BW = Addon.Multi
local AH = C_AuctionHouse

-- Normal price from the depth of the market.
--
-- The lowest listed price is a fragile measurement: a thin bait level pulls it
-- down and our own purchases push it up. The depth price is the price at which
-- the first units of the supply are reached (10% of the loaded supply, at least
-- 20 units), excluding our own listings. A thin bait level cannot move it and our
-- own purchases barely do. Depth samples come for free from listings the addon
-- loads anyway (purchases, SellWheel) plus an optional low query rate.
--
-- Between depth samples the live minimum price moves the value: normal =
-- median minimum price x ratio, where ratio = depth price / median minimum price
-- measured together. The result stays within 0.7x-1.4x of the depth price.
local depthMinUnits, depthShare = 20, 0.10
local depthWindow = 90 * 60 -- seconds a depth sample counts
local maxDepthSamples, maxRatios = 12, 8
local ownQuiet = 30 -- seconds after an own buy or bait in which that item is not measured
local ratioLow, ratioHigh = 0.7, 1.4
local maxRate = 6

local function serverNow() return GetServerTime and GetServerTime() or time() end

local function median(values)
    local list = {}
    for i, value in ipairs(values) do list[i] = value end
    table.sort(list)
    local count = #list
    if count == 0 then return end
    local middle = math.floor((count + 1) / 2)
    return count % 2 == 1 and list[middle] or (list[middle] + list[middle + 1]) / 2
end

-- rows: { price, units } sorted by price, own units already removed.
-- Returns the depth price, or nil when the market is too thin for a depth.
function Addon:DepthPriceFromRows(rows)
    local total = 0
    for _, row in ipairs(rows) do total = total + row.units end
    local need = math.max(depthMinUnits, math.ceil(total * depthShare))
    if total < need then return end
    local cumulative = 0
    for _, row in ipairs(rows) do
        cumulative = cumulative + row.units
        if cumulative >= need then return row.price end
    end
end

-- From the commodity search results the AH currently holds for this item.
function BW:DepthPriceFromListings(itemID)
    local rows = {}
    for i = 1, AH.GetNumCommoditySearchResults(itemID) do
        local row = AH.GetCommoditySearchResultInfo(itemID, i)
        if row and row.unitPrice and row.unitPrice > 0 and (row.quantity or 0) > 0 then
            local units = row.quantity - (row.numOwnerItems or 0)
            if units > 0 then rows[#rows + 1] = { price = row.unitPrice, units = units } end
        end
    end
    table.sort(rows, function(a, b) return a.price < b.price end)
    return Addon:DepthPriceFromRows(rows)
end

-- From SellWheel's price levels ({ price, quantity, owned }, sorted).
function BW:DepthPriceFromTiers(tiers)
    local rows = {}
    for _, tier in ipairs(tiers or {}) do
        local units = tier.quantity - (tier.owned or 0)
        if units > 0 then rows[#rows + 1] = { price = tier.price, units = units } end
    end
    return Addon:DepthPriceFromRows(rows)
end

function BW:NoteOwnAction(id)
    if not id then return end
    self.ownActionAt = self.ownActionAt or {}
    self.ownActionAt[id] = GetTime()
end

function BW:OwnActionRecent(id)
    local at = self.ownActionAt and self.ownActionAt[id]
    return at ~= nil and GetTime() - at < ownQuiet
end

-- Applies the item's buy limit when Limit live is on.
function BW:ApplyLiveLimit(id, learned, normal)
    if not self.db.liveLimit then return end
    local watched = self.db.watchItems and self.db.watchItems[id]
    if not watched then return end
    local percent = tonumber(self.db.learnPercent) or 60
    local limit = math.max(1, math.floor(normal * percent / 100))
    watched.maxPrice, learned.maxPrice, learned.percent = limit, limit, percent
end

local function freshDepths(learned)
    local now, prices = serverNow(), {}
    for _, entry in ipairs(learned.depthList or {}) do
        if now - entry.at <= depthWindow then prices[#prices + 1] = entry.price end
    end
    return prices
end

-- The normal price of an item from its depth samples and the live minimum.
-- minMedian is the median of recent minimum prices, or nil when there are none.
-- Returns the value and stores source/drift on the learned entry.
function BW:NormalFromMeasurements(learned, minMedian)
    local depth = median(freshDepths(learned))
    learned.depth = depth
    learned.drift = nil
    if depth then
        local normal = depth
        if minMedian and learned.ratio then
            local moved = minMedian * learned.ratio
            normal = math.max(depth * ratioLow, math.min(depth * ratioHigh, moved))
            learned.drift = moved < depth * ratioLow or moved > depth * ratioHigh or nil
        end
        learned.source = "depth"
        return normal
    end
    learned.source = "min"
    return minMedian
end

-- A depth sample for a watched item: from a listing, SellWheel or a probe.
function BW:RecordDepth(id, price)
    if not self.db or type(price) ~= "number" or price <= 0 then return end
    local entry = self.db.watchItems and self.db.watchItems[id]
    if not entry then return end
    self.db.learnedPrices = self.db.learnedPrices or {}
    local learned = self.db.learnedPrices[id]
    if not learned then
        learned = {}
        self.db.learnedPrices[id] = learned
    end
    local now = serverNow()
    local list = {}
    for _, item in ipairs(learned.depthList or {}) do
        if now - item.at <= depthWindow then list[#list + 1] = item end
    end
    list[#list + 1] = { at = now, price = price }
    while #list > maxDepthSamples do table.remove(list, 1) end
    learned.depthList, learned.depthAt = list, now
    -- How far the live minimum lies from the depth price, measured together.
    local minMedian = self:LiveMinMedian(id)
    if minMedian and minMedian > 0 then
        local ratios = learned.ratioList or {}
        ratios[#ratios + 1] = price / minMedian
        while #ratios > maxRatios do table.remove(ratios, 1) end
        learned.ratioList, learned.ratio = ratios, median(ratios)
    end
    local normal = self:NormalFromMeasurements(learned, minMedian)
    if normal then
        learned.normalPrice, learned.timestamp = normal, now
        self:ApplyLiveLimit(id, learned, normal)
    end
    self.depthSamplesTaken = (self.depthSamplesTaken or 0) + 1
end

-- Status of an item's normal price for the panel: text, color escape and state.
function BW:NormalInfo(id)
    local learned = self.db and self.db.learnedPrices and self.db.learnedPrices[id]
    if not learned or not learned.normalPrice then return end
    local now = serverNow()
    local age = now - (learned.timestamp or 0)
    local text
    if age < 90 then text = "jetzt"
    elseif age < 3600 then text = ("%d min"):format(math.floor(age / 60))
    else text = ("%d h"):format(math.floor(age / 3600)) end
    local depthAge = learned.depthAt and now - learned.depthAt
    -- While watching, a value without a measurement for 10 minutes is old; when idle
    -- nothing is measured, so only values from hours ago count as old.
    local staleAfter = self.running and 600 or 6 * 3600
    if age > staleAfter then return "|cffff6464alt · " .. text .. "|r", "old", age end
    if learned.source == "depth" and depthAge and depthAge <= depthWindow then
        if learned.drift then return "|cffffd100Markt bewegt sich · " .. text .. "|r", "drift", age end
        return "|cff60eb80Tiefe · " .. text .. "|r", "ok", age
    end
    return "|cffffd100ungenau · " .. text .. "|r", "rough", age
end

-- Depth queries per minute (0 = off). Default 1.
function BW:DepthRate()
    local rate = tonumber(self.db.depthPerMinute)
    if not rate then return 1 end
    return math.max(0, math.min(maxRate, math.floor(rate)))
end

function BW:SetDepthRate(value)
    local number = tonumber(value)
    if not number or number ~= math.floor(number) or number < 0 or number > maxRate then return end
    self.db.depthPerMinute = number
end

-- True when the next depth probe is due while watching.
function BW:DepthDue()
    local rate = self:DepthRate()
    if rate <= 0 then return false end
    return GetTime() >= (self.depthNextAt or 0)
end

-- The watched commodity whose depth measurement is the oldest (never first).
function BW:DepthPick()
    local keys = self.runWatchKeys
    if not keys or #keys == 0 then return end
    local best, bestAge
    for _, key in ipairs(keys) do
        local id = self:WatchID(key)
        local info = AH.GetItemKeyInfo(key)
        if info and info.isCommodity and not self:OwnActionRecent(id) then
            local learned = self.db.learnedPrices and self.db.learnedPrices[id]
            local at = learned and learned.depthAt or 0
            -- A little jitter so equal ages do not always pick the same item.
            local score = at + math.random()
            if not best or score < bestAge then best, bestAge = key, score end
        end
    end
    return best
end

-- A free depth sample from the commodity listings the AH holds right now (used
-- after listings were loaded for a purchase). At most one per item and minute,
-- never right after our own buy or bait.
function BW:SampleDepthFromListings(itemID, id)
    if not id or self:OwnActionRecent(id) then return end
    self.freeDepthAt = self.freeDepthAt or {}
    local last = self.freeDepthAt[id]
    if last and GetTime() - last < 60 then return end
    self.freeDepthAt[id] = GetTime()
    local price = self:DepthPriceFromListings(itemID)
    if price then self:RecordDepth(id, price) end
end

-- Called when a probe was sent: schedules the next one around 60/rate seconds out.
function BW:DepthScheduled()
    local rate = self:DepthRate()
    self.depthNextAt = GetTime() + (rate > 0 and 60 / rate or 60) * (0.8 + math.random() * 0.4)
end
