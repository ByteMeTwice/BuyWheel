local addonName, Addon = ...
local SW = Addon.Sell
local AH = C_AuctionHouse
local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
local events = CreateFrame("Frame")

local function id(key)
    return ("%d:%d:%d:%d"):format(key.itemID, key.itemLevel or 0, key.itemSuffix or 0, key.battlePetSpeciesID or 0)
end

function SW:RefreshInventory()
    -- Position of the selected item in the old list: if it disappears (sold out), the next
    -- sellable item at that position is selected automatically.
    local previousIndex
    if self.selected and self.inventory then
        for i, listed in ipairs(self.inventory) do
            if listed.id == self.selected.id then previousIndex = i break end
        end
    end
    local items = {}
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                local key = AH.GetItemKeyFromItem(loc)
                local commodity = AH.GetItemCommodityStatus(loc) == Enum.ItemCommodityStatus.Commodity
                if key and commodity and AH.IsSellItemValid(loc) then
                    local watchID = id(key)
                    local entry = items[watchID]
                    if not entry then
                        local detail = AH.GetItemKeyInfo(key)
                        entry = { id = watchID, key = key, name = detail and detail.itemName
                            or ("Item %d"):format(key.itemID), quantity = 0, available = 0 }
                        items[watchID] = entry
                    end
                    local quantity = info.stackCount or 1
                    entry.quantity = entry.quantity + quantity
                    if not info.isLocked then entry.available = entry.available + quantity end
                end
            end
        end
    end
    self.inventory = {}
    for _, item in pairs(items) do self.inventory[#self.inventory + 1] = item end
    table.sort(self.inventory, function(a, b)
        if a.name == b.name then return a.id < b.id end
        return a.name < b.name
    end)
    if self.selected then self.selected = items[self.selected.id] end
    if not self.selected then
        self.queued, self.tiers, self.snapshotAt, self.presets = nil, nil, nil, nil
        if self.request then self.request.abandoned = true end
    end
    self.inventoryPending = false
    if self.CheckBagUpdate then self:CheckBagUpdate() end
    if previousIndex and not self.selected and #self.inventory > 0 and not self.post and not self.plan then
        self:Select(self.inventory[math.min(previousIndex, #self.inventory)])
    end
end

-- Quantity is aggregated by unit price, including one-unit offers. Own counts
-- are only those explicitly reported by the API; account flags are not counts.
function SW:CollectTiers(itemID)
    local prices = {}
    for i = 1, AH.GetNumCommoditySearchResults(itemID) do
        local row = AH.GetCommoditySearchResultInfo(itemID, i)
        if row and row.unitPrice and row.unitPrice > 0 and (row.quantity or 0) > 0 then
            local tier = prices[row.unitPrice]
            if not tier then
                tier = { price = row.unitPrice, quantity = 0, owned = 0 }
                prices[row.unitPrice] = tier
            end
            tier.quantity = tier.quantity + row.quantity
            tier.owned = tier.owned + math.max(0, math.min(row.quantity, row.numOwnerItems or 0))
            tier.accountUnknown = tier.accountUnknown or row.containsAccountItem == true
        end
    end
    local result, quantity, owned, largest = {}, 0, 0, 0
    for _, tier in pairs(prices) do result[#result + 1] = tier end
    table.sort(result, function(a, b) return a.price < b.price end)
    for _, tier in ipairs(result) do
        tier.cheaper = quantity
        quantity, owned = quantity + tier.quantity, owned + tier.owned
        tier.cumulative = quantity
        largest = math.max(largest, tier.quantity)
    end
    return result, quantity, owned, largest
end

function SW:CanRead()
    return self.open and self.panel and self.panel:IsVisible() and AuctionHouseFrame:GetAlpha() > 0
        and Addon:CanUseMode(self)
end

function SW:HasPendingAHWork() return self.request ~= nil or self.post ~= nil end

function SW:Stop()
    if self.CancelPosting then self:CancelPosting() end
    self.queued = nil
    if self.request then
        self.request.abandoned = true
        self.status = "Query stopped. Click Refresh to load current offers."
    end
end

function SW:Select(item)
    if self.post or self.plan then self.status = "Erst den laufenden Verkaufsplan beenden oder stoppen." return end
    if not self.open or not self.panel or not self.panel:IsVisible() then return end
    self.selected = item
    self.tiers, self.snapshotAt, self.totalQuantity, self.totalOwned = nil, nil, nil, nil
    self.chartPage = 1
    if self.request then self.request.abandoned = true end
    self.queued = { key = item.key, id = item.id, pages = 0 }
    self.status = "Waiting for the auction house …"
    if self.LoadSellSettings then self:LoadSellSettings(item) end
    self:Pump()
end

function SW:Pump()
    if self.post or self.plan or self.request or not self.queued or not self:CanRead() or InCombatLockdown() then return end
    if not AH.IsThrottledMessageSystemReady() then return end
    local job = self.queued
    self.queued, self.request = nil, job
    self.status = job.more and "Loading remaining price levels …" or "Loading price levels …"
    job.timer = C_Timer.NewTimer(5, function()
        if self.request ~= job then return end
        self.request = nil
        if not job.abandoned then self.status = "No complete reply. Click Refresh to try again." end
        self:Pump()
    end)
    self.sending = true
    local ok
    if job.more then ok = pcall(AH.RequestMoreCommoditySearchResults, job.key.itemID)
    else ok = pcall(AH.SendSearchQuery, job.key, sorts, true) end
    self.sending = false
    if not ok and self.request == job then
        job.timer:Cancel()
        self.request = nil
        self.status = "The auction house rejected the query. Click Refresh to retry."
    end
end

function SW:OnListings(itemID)
    local job = self.request
    if not job or job.key.itemID ~= itemID then return end
    job.timer:Cancel()
    self.request = nil
    if job.abandoned or not self.selected or self.selected.id ~= job.id or not self:CanRead() then
        self:Pump()
        return
    end
    if not AH.HasFullCommoditySearchResults(itemID) then
        local count = AH.GetNumCommoditySearchResults(itemID)
        if job.pages >= 100 or (job.more and count <= (job.count or 0)) then
            self.status = "Price levels are incomplete. Click Refresh to retry."
            return
        end
        self.queued = { key = job.key, id = job.id, more = true, count = count, pages = job.pages + 1 }
        self:Pump()
        return
    end
    self.tiers, self.totalQuantity, self.totalOwned, self.largestTier = self:CollectTiers(itemID)
    -- The loaded price levels are also a free depth sample for BuyWheelM's normal price.
    local multi = Addon.Multi
    if multi and multi.db and multi.RecordDepth and not multi:OwnActionRecent(self.selected.id) then
        local price = multi:DepthPriceFromTiers(self.tiers)
        if price then multi:RecordDepth(self.selected.id, price) end
    end
    self.snapshotAt, self.chartPage = GetTime(), 1
    if self.UpdatePrices then self:UpdatePrices() end
    self.status = #self.tiers == 0 and "No active offers found." or nil
end

local function installHooks()
    if SW.hooked or not hooksecurefunc then return end
    SW.hooked = true
    for _, method in ipairs({ "SendSearchQuery", "SendSellSearchQuery", "RefreshCommoditySearchResults",
        "RequestMoreCommoditySearchResults" }) do
        if AH[method] then
            hooksecurefunc(AH, method, function(key)
                local job = SW.request
                if SW.sending or not job then return end
                local same = type(key) == "table" and key.itemID and id(key) == job.id or key == job.key.itemID
                if same then
                    job.abandoned = true
                    SW.status = "Another search changed these results. Click Refresh to retry."
                end
            end)
        end
    end
end

local handlers = {
    ADDON_LOADED = function(name)
        if name == addonName then
            installHooks()
            if SW.InstallPostHooks then SW:InstallPostHooks() end
        end
    end,
    AUCTION_HOUSE_SHOW = function()
        SW.open = true
        SW.inventoryPending = true
        C_Timer.After(0, function() if SW.open then SW:Attach() end end)
    end,
    AUCTION_HOUSE_CLOSED = function()
        SW.open = false
        SW:Stop()
        SW:HidePanel()
    end,
    BAG_UPDATE_DELAYED = function() SW.inventoryPending = true end,
    GET_ITEM_INFO_RECEIVED = function() SW.inventoryPending = true end,
    AUCTION_HOUSE_THROTTLED_SYSTEM_READY = function() SW:Pump() end,
    COMMODITY_SEARCH_RESULTS_UPDATED = function(itemID) SW:OnListings(itemID) end,
    COMMODITY_SEARCH_RESULTS_ADDED = function(itemID) SW:OnListings(itemID) end,
    AUCTION_HOUSE_AUCTION_CREATED = function() if SW.OnSellCreated then SW:OnSellCreated() end end,
    AUCTION_HOUSE_POST_ERROR = function() if SW.OnSellError then SW:OnSellError() end end,
    AUCTION_HOUSE_SHOW_ERROR = function() if SW.OnSellError then SW:OnSellError() end end,
    ADDON_ACTION_BLOCKED = function(name) if name == addonName and SW.OnSellError then SW:OnSellError() end end,
    ADDON_ACTION_FORBIDDEN = function(name) if name == addonName and SW.OnSellError then SW:OnSellError() end end,
}
for event in pairs(handlers) do pcall(events.RegisterEvent, events, event) end
events:SetScript("OnEvent", function(_, event, ...) if handlers[event] then handlers[event](...) end end)
