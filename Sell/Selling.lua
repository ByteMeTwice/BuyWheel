local _, Addon = ...
local SW = Addon.Sell
local AH = C_AuctionHouse
-- Auction duration codes of the AH API: 1 = 2 h, 2 = 8 h, 3 = 24 h.
SW.durationHours = { 2, 8, 24 }

function SW:Settings()
    self.db = self.db or Addon:GetModeDB("sell")
    self.db.items = self.db.items or {}
    return self.db
end

-- Saved duration code for new posts (default: the shortest, 2 h).
function SW:Duration()
    local value = tonumber(self:Settings().duration)
    return (value == 1 or value == 2 or value == 3) and value or 1
end

function SW:SetDuration(value)
    if not self:CanEditSale() or (value ~= 1 and value ~= 2 and value ~= 3) then return end
    self:Settings().duration = value
end

-- Share (0-100 %) of the quantity sold at the cheapest price; the rest goes to the
-- 25 % price. Saved with the other SellWheel settings.
function SW:CheapShare()
    local value = tonumber(self:Settings().cheapShare)
    if not value or value < 0 or value > 100 then return 50 end
    return math.floor(value)
end

function SW:SetCheapShare(value)
    value = tonumber(value)
    if not self:CanEditSale() or not value or value < 0 or value > 100 or value ~= math.floor(value) then return end
    self:Settings().cheapShare = value
end

-- Number of items of every commodity that is never sold (kept as bait); 0 = off.
function SW:KeepCount()
    local value = tonumber(self:Settings().keepBait)
    if not value or value < 0 then return 0 end
    return math.floor(value)
end

function SW:SetKeepCount(value)
    value = tonumber(value)
    if not self:CanEditSale() or not value or value < 0 or value > 9999999 or value ~= math.floor(value) then return end
    self:Settings().keepBait = value
    if self.selected and (tonumber(self.quantity) or 0) > self:Sellable(self.selected) then
        self.quantity = self:Sellable(self.selected)
    end
end

-- What may be sold of an inventory item: the unlocked stock minus the kept bait items.
function SW:Sellable(item)
    return math.max(0, (item and item.available or 0) - self:KeepCount())
end

function SW:LoadSellSettings(item)
    -- A refresh of the same item keeps the quantity that was typed in.
    if self.quantityItem ~= item.id or (tonumber(self.quantity) or 0) < 1 then
        self.quantity, self.quantityItem = self:Sellable(item), item.id
    end
    self:UpdatePrices()
end

function SW:CanEditSale() return self.post == nil and self.plan == nil end

function SW:PriceTick()
    return AH.SupportsCopperValues and not AH.SupportsCopperValues() and 100 or 1
end

-- A price level only counts as the real cheapest offer once this much competing
-- supply is reached (share of the total, at least that many units). Thin leading
-- levels are usually bait and are skipped.
local significantShare, significantUnits = 0.05, 5
-- ...or when a single level holds this share of the supply on its own (at least
-- 5 units): a real level below the 5% point is not bait, even in a huge market.
local singleShare = 0.005

function SW:UpdatePrices()
    self.presets, self.listing = nil, nil
    if not self.tiers or #self.tiers == 0 then return end
    local tick = self:PriceTick()
    -- Competing supply only: own listings never count as competition.
    local others, total = {}, 0
    for _, tier in ipairs(self.tiers) do
        local other = tier.quantity - tier.owned
        if other > 0 then
            others[#others + 1] = { price = tier.price, quantity = other }
            total = total + other
        end
    end
    local first = others[1] and others[1].price or self.tiers[1].price
    local function rounded(price) return math.max(tick, math.ceil(price / tick) * tick) end
    -- Price of the level in which the given share of competing units is reached.
    local function percentile(share)
        local target, cumulative = total * share, 0
        for _, tier in ipairs(others) do
            cumulative = cumulative + tier.quantity
            if cumulative >= target then return tier.price end
        end
        return first
    end
    -- First level that holds a meaningful part of the supply.
    local significant = first
    if total > 0 then
        local need = math.min(total, math.max(significantUnits, math.ceil(total * significantShare)))
        local singleNeed = math.min(total, math.max(significantUnits, math.ceil(total * singleShare)))
        local cumulative = 0
        for _, tier in ipairs(others) do
            cumulative = cumulative + tier.quantity
            if cumulative >= need or tier.quantity >= singleNeed then significant = tier.price break end
        end
    end
    -- Cheapest: the price of the first meaningful level itself (no undercut),
    -- so a thin bait below it is not chased.
    local cheapest = rounded(significant)
    -- 25% level: just below the level where 25% of the competing supply is
    -- reached, never below the first meaningful level.
    local quarter = rounded(math.max(percentile(0.25) - tick, significant))
    if quarter < cheapest then quarter = cheapest end
    self.presets = {
        { title = "Cheapest", price = cheapest },
        { title = "25% level", price = quarter },
    }
    for _, preset in ipairs(self.presets) do
        preset.lowest = first
        preset.vsLowest = first > 0 and (preset.price / first - 1) or 0
        -- Units (all sellers) and competing units that are cheaper than this price.
        preset.ahead, preset.aheadShare = 0, 0
        local cheaper = 0
        for _, tier in ipairs(self.tiers) do
            if tier.price < preset.price then preset.ahead = preset.ahead + tier.quantity end
        end
        for _, tier in ipairs(others) do
            if tier.price < preset.price then cheaper = cheaper + tier.quantity end
        end
        preset.aheadShare = total > 0 and cheaper / total or 0
    end

    -- The comparison list: every price level with its quantity, the cumulative
    -- share of the competing supply, and the rows our two prices land on. A
    -- planned price without a level of its own becomes a separate row.
    local rows, cumulative = {}, 0
    local normal = self.selected and Addon.LearnedNormalPrice and Addon.Multi
        and Addon:LearnedNormalPrice(Addon.Multi, self.selected.id)
    local itemID = self.selected and self.selected.key and self.selected.key.itemID
    for _, tier in ipairs(self.tiers) do
        cumulative = cumulative + (tier.quantity - tier.owned)
        rows[#rows + 1] = { price = tier.price, quantity = tier.quantity, owned = tier.owned,
            share = total > 0 and cumulative / total or 0,
            -- Probably a bait of another BuyWheel user (see Fingerprint.lua).
            bait = Addon.LooksLikeBait and Addon:LooksLikeBait(tier.price, itemID, tier.quantity - tier.owned, normal) or nil }
    end
    for stage, preset in ipairs(self.presets) do
        local placed
        for _, row in ipairs(rows) do
            if row.price == preset.price then
                row.stage = (row.stage and row.stage ~= stage) and 3 or stage
                placed = true
            end
        end
        if not placed then
            local planned = { price = preset.price, planned = true, stage = stage, quantity = 0, owned = 0, share = 0 }
            local at = #rows + 1
            for i, row in ipairs(rows) do
                if row.price > preset.price then at = i break end
            end
            if at > 1 then planned.share = rows[at - 1].share end
            table.insert(rows, at, planned)
        end
    end
    self.listing = rows
end

function SW:SalePreview()
    if not self.selected or not self.presets then return nil, "Select an item and load its market prices first." end
    if self:KeepCount() > 0 and self:Sellable(self.selected) < 1 then
        return nil, "Nothing to sell: all of this item is kept as bait (Keep Bait Items)."
    end
    local quantity = tonumber(self.quantity)
    if not quantity or quantity ~= math.floor(quantity) or quantity < 1 then return nil, "Enter a whole quantity greater than zero." end
    if quantity > self:Sellable(self.selected) then
        return nil, self:KeepCount() > 0 and "The quantity exceeds the stock that is not kept as bait."
            or "The quantity exceeds the available stock."
    end
    -- Stage 1 sells the cheap share (rounded), stage 2 the rest.
    local cheap = math.floor(quantity * self:CheapShare() / 100 + 0.5)
    local counts = { cheap, quantity - cheap }
    local preview = { counts = counts, entries = {}, quantity = quantity, total = 0,
        item = { id = self.selected.id, key = self.selected.key, name = self.selected.name }, prices = self.presets }
    for i = 1, 2 do
        local price = self.presets[i].price
        if price < 1 or price >= 10000000000000 or price ~= math.floor(price) or price % self:PriceTick() ~= 0 then
            return nil, "The auction house does not support this unit price."
        end
        if counts[i] > 0 then
            local entry
            for _, existing in ipairs(preview.entries) do if existing.price == price then entry = existing end end
            if not entry then
                entry = { price = price, quantity = 0, remaining = 0 }
                preview.entries[#preview.entries + 1] = entry
            end
            entry.quantity, entry.remaining = entry.quantity + counts[i], entry.remaining + counts[i]
            preview.total = preview.total + counts[i] * price
        end
    end
    return preview
end

function SW:FindPostLocation(item)
    local best, bestCount
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == item.key.itemID and not info.isLocked then
                local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                if AH.IsSellItemValid(loc, false) then
                    local key = AH.GetItemKeyFromItem(loc)
                    local same = key and key.itemID == item.key.itemID
                        and (key.itemLevel or 0) == (item.key.itemLevel or 0)
                        and (key.itemSuffix or 0) == (item.key.itemSuffix or 0)
                        and (key.battlePetSpeciesID or 0) == (item.key.battlePetSpeciesID or 0)
                    local count = same and AH.GetAvailablePostCount(loc) or 0
                    if count and count > (bestCount or 0) then
                        best = { loc = loc, bag = bag, slot = slot,
                            guid = C_Item and C_Item.GetItemGUID and C_Item.GetItemGUID(loc) }
                        bestCount = count
                    end
                end
            end
        end
    end
    return best, bestCount
end

function SW:PlanFinished(plan)
    for _, entry in ipairs(plan.entries) do
        if entry.remaining > 0 then return false end
    end
    return true
end

-- Index of the plan entry a price card posts: the entry at that card's price.
-- Without a card, the first entry with something left. Done entries are only
-- returned when includeDone is set (to mark finished cards).
function SW:PlanEntryIndex(plan, card, includeDone)
    if not plan then return end
    if not card then
        for index, entry in ipairs(plan.entries) do
            if entry.remaining > 0 then return index end
        end
        return
    end
    local price = plan.prices[card] and plan.prices[card].price
    for index, entry in ipairs(plan.entries) do
        if entry.price == price and (includeDone or entry.remaining > 0) then return index end
    end
end

-- A list of what was posted (saved): the sum of quantity x price, and how much of it came from
-- the 25% level instead of the cheapest price.
function SW:RecordPosted(job)
    local db = self:Settings()
    local p = db.posted
    if type(p) ~= "table" then
        p = { total = 0, extra = 0, units = 0, items = {}, since = time and time() or nil }
        db.posted = p
    end
    local value = job.quantity * job.price
    local cheapest = job.plan.prices and job.plan.prices[1] and job.plan.prices[1].price or job.price
    local extra = job.price > cheapest and job.quantity * (job.price - cheapest) or 0
    p.total, p.extra, p.units = p.total + value, p.extra + extra, p.units + job.quantity
    local id = job.plan.item.id
    local item = p.items[id]
    if not item then
        item = { name = job.plan.item.name, units = 0, value = 0 }
        p.items[id] = item
    end
    item.units, item.value = item.units + job.quantity, item.value + value
end

function SW:PostedSummary() return self:Settings().posted end

function SW:ResetPosted() self:Settings().posted = nil end

function SW:FinishSellPost(success, message)
    local job = self.post
    if not job then return end
    if job.timer then job.timer:Cancel() end
    self.post = nil
    job.log.outcome = success and "posted" or "failed"
    job.log.finished = GetTime()
    if success then
        local entry = job.plan.entries[job.index]
        Addon:NoteOwnPost(job.plan.item.key.itemID, job.price, job.duration, job.quantity)
        self.lastSoldID = job.plan.item.id
        self:RecordPosted(job)
        if Addon.Multi.NoteOwnAction then Addon.Multi:NoteOwnAction(job.plan.item.id) end
        entry.remaining = entry.remaining - job.quantity
        job.plan.posted = (job.plan.posted or 0) + 1
        self.quantity = math.max(0, (tonumber(self.quantity) or 0) - job.quantity)
        self.waitingForBags = { id = job.plan.item.id, available = job.beforeAvailable - job.quantity }
        self:RefreshInventory()
        self:CheckBagUpdate()
        if self.plan == job.plan and self:PlanFinished(job.plan) then self.plan = nil end
        self.status = message or ("%d items posted for %d h (code %d). Not a confirmed sale yet."):format(job.quantity, self.durationHours[job.duration] or 0, job.duration or 0)
    else
        self.plan = nil
        self.status = message or "Posting failed. Nothing is retried automatically."
    end
    self.inventoryPending = true
end

function SW:CheckBagUpdate()
    local wait = self.waitingForBags
    if not wait then return end
    local available = 0
    for _, item in ipairs(self.inventory or {}) do if item.id == wait.id then available = item.available end end
    if available <= wait.available then self.waitingForBags = nil end
end

function SW:CancelPosting(clearUnknown)
    self.plan = nil
    local job = self.post
    if job and job.state == "confirm" then
        if AH.CancelSell then pcall(AH.CancelSell) end
        if job.timer then job.timer:Cancel() end
        job.log.outcome, self.post = "cancelled_before_confirmation", nil
        if StaticPopup_Visible and StaticPopup_Visible("AUCTION_HOUSE_POST_WARNING") then StaticPopup_Hide("AUCTION_HOUSE_POST_WARNING") end
    elseif job and job.state == "unknown" and clearUnknown then
        if job.timer then job.timer:Cancel() end
        job.log.outcome, self.post = "unresolved_cleared", nil
    end
    if clearUnknown and not self.post then self.waitingForBags = nil end
end

-- This method is called only by a fresh click. Results, timers and readiness
-- events never send another post, even when several price levels are planned.
-- A price card passes its number: without Staffeln that click posts the whole
-- quantity at the card's price; with Staffeln it posts that card's share.
-- Without a card (confirmation, legacy callers) the first open entry is used.
function SW:PostNext(card)
    if not self:CanRead() or InCombatLockdown() or self.request or self.queued then return end
    if self.post and self.post.state ~= "confirm" then return end
    if not AH.IsThrottledMessageSystemReady() then self.status = "The auction house is busy. Please click again in a moment." return end
    self:RefreshInventory()
    self:CheckBagUpdate()
    if self.waitingForBags then self.status = "Waiting for the updated bag contents." return end
    local job = self.post
    if not self.plan and not job then
        if not self.snapshotAt or GetTime() - self.snapshotAt > 60 then
            -- Old prices are never posted. Reload them; the next click uses the new ones.
            if self.selected then self:Select(self.selected) end
            self.status = "The market prices were older than a minute and are being reloaded. Click again afterwards."
            return
        end
        local plan, message = self:SalePreview()
        if not plan then self.status = message return end
        plan.started = GetTime()
        self.plan = plan
    end
    local plan = job and job.plan or self.plan
    local entryIndex = job and job.index or self:PlanEntryIndex(plan, card)
    local entry = entryIndex and plan.entries[entryIndex]
    if not entry then
        -- This card has no share or is already posted. A plan nothing was posted
        -- for is dropped again so the inputs stay editable.
        if not job then
            if (plan.posted or 0) == 0 or self:PlanFinished(plan) then self.plan = nil end
            self.status = "This stage is already posted or has 0 items."
        end
        return
    end
    local sameItem = self.selected and self.selected.id == plan.item.id
    -- stock = what is really in the bags; available = what may be sold (minus the kept bait items).
    local stock = sameItem and self.selected.available or 0
    local available = sameItem and self:Sellable(self.selected) or 0
    local location, count = self:FindPostLocation(plan.item)
    if not location or available < 1 then
        if job then self:CancelPosting() end
        self.plan, self.status = nil, "No matching unlocked items left to sell in your bags."
        return
    end
    local requested = job and job.quantity or entry.remaining
    -- A started post keeps its duration through the confirmation step.
    local duration = job and job.duration or self:Duration()
    local deposit = AH.CalculateCommodityDeposit and AH.CalculateCommodityDeposit(plan.item.key.itemID, duration, requested)
    if deposit and deposit > GetMoney() then
        if not job then self.plan = nil end
        self.status = "Not enough gold for the deposit."
        return
    end
    if job then
        local info = C_Container.GetContainerItemInfo(job.bag, job.slot)
        local loc = ItemLocation:CreateFromBagAndSlot(job.bag, job.slot)
        local guid = info and C_Item and C_Item.GetItemGUID and C_Item.GetItemGUID(loc)
        local key = info and AH.GetItemKeyFromItem(loc)
        local same = key and key.itemID == plan.item.key.itemID
            and (key.itemLevel or 0) == (plan.item.key.itemLevel or 0)
            and (key.itemSuffix or 0) == (plan.item.key.itemSuffix or 0)
            and (key.battlePetSpeciesID or 0) == (plan.item.key.battlePetSpeciesID or 0)
        if not info or info.itemID ~= plan.item.key.itemID or info.isLocked or (job.guid and job.guid ~= guid)
            or not same
            or not AH.IsSellItemValid(loc, false) or (AH.GetAvailablePostCount(loc) or 0) < job.quantity then
            self:CancelPosting()
            self.status = "The stock changed. Please check the quantity again."
            return
        end
        job.loc = loc
        if job.timer then job.timer:Cancel() end
    else
        local quantity = entry.remaining
        if quantity > available or quantity > count then
            self.plan = nil
            self.status = ("The stock changed or the AH quantity limit applies: at most %d items. Please choose the quantity again."):format(math.min(available, count))
            return
        end
        job = { plan = plan, index = entryIndex, quantity = quantity, price = entry.price,
            loc = location.loc, bag = location.bag, slot = location.slot, guid = location.guid,
            beforeAvailable = stock, duration = duration }
        local db = self:Settings()
        db.postDiagnostics = db.postDiagnostics or {}
        job.log = { itemID = plan.item.key.itemID, item = plan.item.name, quantity = quantity,
            unitPrice = job.price, durationCode = duration, durationHours = self.durationHours[duration],
            timestamp = GetServerTime and GetServerTime(), outcome = "pending" }
        db.postDiagnostics[#db.postDiagnostics + 1] = job.log
        if #db.postDiagnostics > 100 then table.remove(db.postDiagnostics, 1) end
        self.post = job
    end
    local confirming = job.state == "confirm"
    job.state = "sent"
    job.timer = C_Timer.NewTimer(12, function()
        if self.post ~= job then return end
        job.state, job.log.outcome, self.plan = "unknown", "unresolved", nil
        self.status = "No confirmation. Check your auctions, then click Release if needed."
    end)
    self.sendingPost = true
    local ok, needsConfirm = pcall(confirming and AH.ConfirmPostCommodity or AH.PostCommodity,
        job.loc, job.duration, job.quantity, job.price)
    self.sendingPost = false
    if self.post ~= job then return end
    if not ok then self:FinishSellPost(false, "WoW rejected the posting.")
    elseif not confirming and needsConfirm then
        job.state = "confirm"
        job.timer:Cancel()
        job.timer = C_Timer.NewTimer(30, function()
            if self.post == job then self:CancelPosting() self.status = "The confirmation expired." end
        end)
        self.status = "The auction house asks for a confirmation. Click Confirm."
        C_Timer.After(0, function()
            if self.post == job and job.state == "confirm" and StaticPopup_Visible
                and StaticPopup_Visible("AUCTION_HOUSE_POST_WARNING") then StaticPopup_Hide("AUCTION_HOUSE_POST_WARNING") end
        end)
    else self.status = "Waiting for the confirmation of the posted listing …" end
end

function SW:OnSellCreated()
    local job = self.post
    if job and not job.foreign and (job.state == "sent" or job.state == "unknown") then self:FinishSellPost(true) end
end

function SW:OnSellError()
    if self.post and not self.post.foreign then self:FinishSellPost(false) end
end

function SW:InstallPostHooks()
    if self.postHooks or not hooksecurefunc then return end
    self.postHooks = true
    for _, method in ipairs({ "PostCommodity", "PostItem", "ConfirmPostCommodity", "ConfirmPostItem" }) do
        if AH[method] then
            hooksecurefunc(AH, method, function()
                if self.post and not self.sendingPost then
                    self.post.foreign, self.post.state, self.plan = true, "unknown", nil
                    self.post.log.outcome = "interference"
                    if self.post.timer then self.post.timer:Cancel() end
                    self.status = "Another posting was detected. Check your auctions and click Release."
                end
            end)
        end
    end
end
