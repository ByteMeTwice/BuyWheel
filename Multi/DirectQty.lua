local _, Addon = ...
local BW = Addon.Multi
local AH = C_AuctionHouse

-- Learned Direct buy quantity per item.
--
-- Direct buy asks the AH for N units without loading the listings first. The right N
-- differs a lot per item (Rugged Leather: usually 1 unit under the limit, Medium
-- Leather: 15-80), so it is learned per item from two sources:
--
--  1. Observations: whenever listings are loaded anyway (the normal purchase path, depth
--     probes), the number of foreign units at or below the buy limit is noted, but only
--     when there are any (a buyable moment). The median of the last 20 notes is the base.
--  2. Outcomes of own Direct buys: a confirmed buy whose average price left room under the
--     limit raises N (x1.5); a quote rejected because its average was above the limit
--     halves N. N never falls below half the base and never exceeds 500.
--
-- Stored in BuyWheelDB.directQty (per character), apart from learned prices and purchase
-- statistics: neither Reset learned, a learning run nor the purchase Reset touches it.
-- On first use it is seeded from the purchase diagnostics already saved.
local keepNotes = 20
local noteGap = 10          -- seconds between two notes of the same item
local defaultQuantity = 3   -- without any data
local maxQuantity = 500
local growRatio, growRoom = 1.5, 0.9 -- grow when the average paid was at most 90% of the limit

local function median(values)
    local list = {}
    for i, value in ipairs(values) do list[i] = value end
    table.sort(list)
    local count = #list
    if count == 0 then return end
    local middle = math.floor((count + 1) / 2)
    return count % 2 == 1 and list[middle] or (list[middle] + list[middle + 1]) / 2
end

-- Watch ID of a commodity from its item ID (commodity keys differ only by item ID).
local function idForItem(watchItems, itemID)
    for id, entry in pairs(watchItems or {}) do
        if entry.key and entry.key.itemID == itemID then return id end
    end
end

-- One-time seed from the saved purchase diagnostics: their quantity on the listing path
-- is the number of units that were buyable at the lowest price level at that moment.
local function seed(store, multiDB)
    if store.seeded then return end
    store.seeded = true
    for _, log in ipairs(multiDB and multiDB.purchaseDiagnostics or {}) do
        local quantity = tonumber(log.quantity)
        if log.offerSource == "listings" and log.itemID and quantity and quantity >= 1 then
            local id = idForItem(multiDB.watchItems, log.itemID)
            if id then
                local item = store.items[id] or { notes = {} }
                store.items[id] = item
                item.notes[#item.notes + 1] = math.floor(quantity)
                while #item.notes > keepNotes do table.remove(item.notes, 1) end
            end
        end
    end
end

function BW:DirectQtyStore()
    local multiDB = Addon:GetModeDB("multi") -- makes sure BuyWheelDB exists in its current layout
    local store = BuyWheelDB.directQty
    if type(store) ~= "table" then
        store = { items = {} }
        BuyWheelDB.directQty = store
    end
    if type(store.items) ~= "table" then store.items = {} end
    seed(store, multiDB)
    return store
end

local function itemEntry(id, create)
    local items = BW:DirectQtyStore().items
    local item = items[id]
    if not item and create then
        item = { notes = {} }
        items[id] = item
    end
    return item
end

-- Base (median of the notes) and the lowest allowed quantity for an item.
local function base(item)
    local value = item and item.notes and median(item.notes)
    return value and math.max(1, math.floor(value + 0.5)) or nil
end

local function floorFor(item)
    local value = base(item)
    return value and math.max(1, math.ceil(value / 2)) or 1
end

-- The quantity Direct buy asks for (before the listed quantity and budget caps).
function BW:DirectQuantity(id)
    local item = id and itemEntry(id)
    local quantity = item and item.quantity or base(item) or defaultQuantity
    return math.max(floorFor(item), math.min(maxQuantity, math.floor(quantity)))
end

-- Number of foreign units at or below `limit` in the commodity listings the AH holds now.
function BW:UnitsUnderLimit(itemID, limit)
    if not itemID or not limit or limit <= 0 then return 0 end
    local units = 0
    for i = 1, AH.GetNumCommoditySearchResults(itemID) do
        local row = AH.GetCommoditySearchResultInfo(itemID, i)
        if row and row.unitPrice and row.unitPrice > 0 and row.unitPrice <= limit and not row.containsAccountItem then
            units = units + math.max(0, (row.quantity or 0) - (row.numOwnerItems or 0))
        end
    end
    return units
end

-- A note from loaded listings: only buyable moments (at least one unit under the limit).
function BW:NoteDirectUnits(id, itemID, limit)
    if not id then return end
    local units = self:UnitsUnderLimit(itemID, limit)
    if units < 1 then return end
    -- GetTime() restarts with the client, so the last note time is kept out of the saved data.
    local now = GetTime()
    self.directNotedAt = self.directNotedAt or {}
    local last = self.directNotedAt[id]
    if last and now - last < noteGap then return end
    self.directNotedAt[id] = now
    local item = itemEntry(id, true)
    item.notes[#item.notes + 1] = units
    while #item.notes > keepNotes do table.remove(item.notes, 1) end
end

-- A confirmed Direct buy: grow when the average price left room under the limit.
function BW:DirectQtyConfirmed(id, quantity, averageUnit, limit)
    local item = id and itemEntry(id, true)
    if not item then return end
    item.ok = (item.ok or 0) + 1
    local current = self:DirectQuantity(id)
    if limit and limit > 0 and averageUnit and averageUnit <= limit * growRoom and quantity >= current then
        item.quantity = math.min(maxQuantity, math.max(current + 1, math.ceil(current * growRatio)))
    else
        item.quantity = current
    end
end

-- A Direct buy quote whose average was above the limit: halve the quantity.
function BW:DirectQtyRejected(id, quantity)
    local item = id and itemEntry(id, true)
    if not item then return end
    item.rejected = (item.rejected or 0) + 1
    local current = math.min(self:DirectQuantity(id), quantity or maxQuantity)
    item.quantity = math.max(floorFor(item), math.floor(current / 2))
end

-- Lines for the Direct buy tooltip: watched items with their learned quantity.
function BW:DirectQtySummary(limit)
    local list = {}
    for id, entry in pairs(self.db.watchItems or {}) do
        if entry.enabled and entry.key then
            local item = itemEntry(id)
            local info = AH.GetItemKeyInfo(entry.key)
            if info and info.isCommodity then
                list[#list + 1] = { name = info.itemName or ("Item " .. entry.key.itemID), quantity = self:DirectQuantity(id),
                    notes = item and item.notes and #item.notes or 0, ok = item and item.ok or 0,
                    rejected = item and item.rejected or 0 }
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    local lines = {}
    for i = 1, math.min(limit or 12, #list) do
        local e = list[i]
        lines[i] = ("%s: %d  (%d notes · %d ok · %d too high)"):format(e.name, e.quantity, e.notes, e.ok, e.rejected)
    end
    return lines, #list
end
