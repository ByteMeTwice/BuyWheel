local _, Addon = ...
local BW = Addon.Multi
local AH = C_AuctionHouse

function BW:WatchID(key)
    return ("%d:%d:%d:%d"):format(key.itemID, key.itemLevel or 0, key.itemSuffix or 0, key.battlePetSpeciesID or 0)
end

function BW:WatchEntry(key)
    return self.db.watchItems[self:WatchID(key)]
end

function BW:SetWatched(key, enabled)
    if self.running or self.learning or self:PurchasePending() then return end
    local id = self:WatchID(key)
    local entry = self.db.watchItems[id]
    if not entry then
        entry = { key = key, maxPrice = self.maxPrice or 0 }
        self.db.watchItems[id] = entry
    end
    entry.enabled = enabled == true
end

function BW:WatchKeys()
    -- Saved limits and checkboxes may outlive an AH favorite. Only current
    -- favorites belong in a new run; retain their saved settings for later.
    local entries, seen = {}, {}
    for _, row in ipairs(self.favorites or {}) do
        local id = self:WatchID(row.itemKey)
        local entry = self.db.watchItems[id]
        if not seen[id] and entry and entry.enabled and (entry.maxPrice or 0) > 0 then
            seen[id] = true
            entries[#entries + 1] = { id = id, key = row.itemKey }
        end
    end
    table.sort(entries, function(a, b) return a.id < b.id end)
    local keys = {}
    for _, entry in ipairs(entries) do keys[#keys + 1] = entry.key end
    return keys
end

function BW:ActivateWatch(key)
    local entry = self:WatchEntry(key)
    local info = AH.GetItemKeyInfo(key)
    if not entry or not entry.enabled or (entry.maxPrice or 0) <= 0 or not info or not info.itemName then return false end
    local stackSize = C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(key.itemID)
    if not stackSize or stackSize < 1 then stackSize = select(8, C_Item.GetItemInfo(key.itemID)) end
    self.target = { key = key, id = self:WatchID(key), name = info.itemName,
        commodity = not not info.isCommodity, browseName = info.itemName,
        stackSize = stackSize and math.max(1, stackSize) or 1 }
    self.maxPrice = entry.maxPrice
    self.low = self.watchLows and self.watchLows[self.target.id] or nil
    self.current, self.updatedAt, self.currentQuantity, self.offers = nil, nil, nil, nil
    return true
end

-- Browse does not tell us the quantity available at its minimum price. By default
-- rank absolute estimated margin per unit, never the whole group's total quantity.
-- Ties rotate by watch ID; a single pass avoids sorting or extra AH requests.
-- Volume Trading is always on: draw randomly among all items under their limit instead,
-- weighted by margin x listed quantity (capped), see below.
function BW:ChooseWatch(rows)
    local chosen, bestMargin, bestID, bestNormal
    local candidates = {}
    local lastID = self.lastWatchID or ""
    local room = math.min(self:Remaining(), GetMoney())
    for _, row in ipairs(rows) do
        local entry = self:WatchEntry(row.itemKey)
        local info = AH.GetItemKeyInfo(row.itemKey)
        local price = row.minPrice or 0
        local quantity = info and info.isCommodity and self.db.fastQuoteX3
            and not self:LeaveBaitFor(self:WatchID(row.itemKey), price)
            and self:FastQuoteQuantity() or 1
        if entry and entry.enabled and info and info.itemName and price > 0
            and price <= (entry.maxPrice or 0) and price * quantity <= room
            and (quantity == 1 or (row.totalQuantity or 0) >= quantity) then
            local id = self:WatchID(row.itemKey)
            local normal = Addon:LearnedNormalPrice(self, id)
            local margin = (normal or entry.maxPrice) - price
            local winsTie = bestID and ((id > lastID and bestID <= lastID)
                or ((id > lastID) == (bestID > lastID) and id < bestID))
            if not chosen or margin > bestMargin or (margin == bestMargin and winsTie) then
                chosen, bestMargin, bestID, bestNormal = row, margin, id, normal
            end
            candidates[#candidates + 1] = { row = row, id = id, margin = margin, normal = normal,
                -- Browse only knows the total quantity over all prices: a rough volume
                -- signal, capped so one huge stack cannot dominate the draw.
                weight = math.max(margin, 1) * math.min(math.max(row.totalQuantity or 1, 1), 20) }
        end
    end
    self.candidateCount = #candidates
    self.watchSelection = nil
    -- Always on; only a test can switch it off (db.volumeTrading == false).
    local volume = self.db.volumeTrading ~= false and #candidates > 1
    if volume then
        -- Volume trading: weighted random draw among every item under its limit,
        -- so cheap high-volume items are not starved by a single large margin.
        local total = 0
        for _, candidate in ipairs(candidates) do total = total + candidate.weight end
        local roll = math.random() * total
        local pick = candidates[#candidates]
        for _, candidate in ipairs(candidates) do
            roll = roll - candidate.weight
            if roll <= 0 then pick = candidate break end
        end
        chosen, bestMargin, bestID, bestNormal = pick.row, pick.margin, pick.id, pick.normal
    end
    if chosen and self:ActivateWatch(chosen.itemKey) then
        self.lastWatchID = bestID
        self.watchSelection = { id = bestID, margin = bestMargin,
            reference = bestNormal or self:WatchEntry(chosen.itemKey).maxPrice,
            source = bestNormal and "normal_price" or "buy_limit",
            candidates = #candidates, volume = volume or nil }
        return chosen
    end
end

function BW:OtherWheelActive()
    return not Addon:CanUseMode(self)
end
