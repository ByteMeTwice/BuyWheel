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

-- /bwmax: own max buy percentage for single favorites (e.g. items you need yourself), instead of the
-- global Max buy %. Stored on the watch entry (entry.percent); a reset of the learned data clears it.
--   /bwmax [Item] 90     set      /bwmax [Item] off     remove      /bwmax [Item]     show
--   /bwmax 90            for the item selected in the list          /bwmax            list all
local function maxSay(text)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage("|cffffd24dBuyWheel|r " .. text) end
end

local function maxItemName(id, entry)
    local info = entry.key and AH.GetItemKeyInfo(entry.key)
    return info and info.itemName or id
end

-- The favorite (or saved watch entry) a link or name points to: returns its watch id and entry.
local function maxFind(text)
    local itemID = tonumber(text:match("|Hitem:(%d+)"))
    local name = (text:match("%[(.-)%]") or text):match("^%s*(.-)%s*$"):lower()
    local function same(key)
        if itemID then return key.itemID == itemID end
        local info = AH.GetItemKeyInfo(key)
        return name ~= "" and info and info.itemName and info.itemName:lower() == name
    end
    for _, row in ipairs(BW.favorites or {}) do
        if row.itemKey and same(row.itemKey) then
            local id = BW:WatchID(row.itemKey)
            return id, BW.db.watchItems[id] or { key = row.itemKey, maxPrice = 0, enabled = false }
        end
    end
    for id, entry in pairs(BW.db.watchItems or {}) do
        if entry.key and same(entry.key) then return id, entry end
    end
end

SLASH_BWMAX1 = "/bwmax"
SlashCmdList = SlashCmdList or {}
SlashCmdList["BWMAX"] = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    if msg == "" then
        local list = {}
        for id, entry in pairs(BW.db.watchItems or {}) do
            if entry.percent then list[#list + 1] = ("%s %g%%"):format(maxItemName(id, entry), entry.percent) end
        end
        table.sort(list)
        maxSay(#list > 0 and ("own max buy: " .. table.concat(list, " · "))
            or ("no own values · global " .. (tonumber(BW.db.learnPercent) or 60) .. "%. Use /bwmax [Item] 90"))
        return
    end
    local itemText, value = msg:match("^(.-)%s*(%S+)$")
    local wanted
    if value:lower() == "off" then wanted = false
    elseif value:match("^%d+%.?%d*$") then wanted = tonumber(value)
    else itemText, value = msg, nil end
    local id, entry
    if itemText == "" then
        if BW.target then id = BW:WatchID(BW.target.key); entry = BW.db.watchItems[id] end
        if not entry then maxSay("select an item in the list first, or give an item: /bwmax [Item] 90") return end
    else
        id, entry = maxFind(itemText)
        if not id then maxSay("item not found among your favorites: " .. itemText) return end
    end
    if wanted == nil then
        maxSay(("%s: %s"):format(maxItemName(id, entry), entry.percent and (entry.percent .. "% (own)")
            or ("global " .. (tonumber(BW.db.learnPercent) or 60) .. "%")))
        return
    end
    if wanted and (wanted < 1 or wanted > 200) then maxSay("percentage 1-200, or off") return end
    BW.db.watchItems[id] = entry
    entry.percent = wanted or nil
    -- Apply it to the current limit at once (the live updates keep it from now on).
    local learned = BW.db.learnedPrices and BW.db.learnedPrices[id]
    if learned and learned.normalPrice then
        local percent = entry.percent or tonumber(BW.db.learnPercent) or 60
        local limit = math.max(1, math.floor(learned.normalPrice * percent / 100))
        entry.maxPrice, learned.maxPrice, learned.percent = limit, limit, percent
    end
    if BW.panel then BW.panel.displayedTargetID = nil end
    maxSay(("%s: %s"):format(maxItemName(id, entry), wanted and (wanted .. "% of normal") or
        ("global " .. (tonumber(BW.db.learnPercent) or 60) .. "%")))
end
