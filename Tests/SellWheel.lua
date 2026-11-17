-- /tmp/buywheel-lua BuyWheel/Tests/SellWheel.lua BuyWheel/
-- Also works with a normal Lua 5.1 interpreter.
local root = ... or "Interface/AddOns/BuyWheel/"
local count = 0
local function eq(a, b, message)
    assert(a == b, (message or "unexpected value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end
local function test(name, run) run() count = count + 1 print("PASS " .. name) end

local function fixture()
    local f = { now = 100, ready = true, frames = {}, timers = {}, calls = {}, bags = {}, listings = {}, hooks = {} }
    local env = setmetatable({}, { __index = _G })
    local addon, methods = {}, {}
    local function noop() end
    local function object(kind, parent)
        local frame = setmetatable({ kind = kind, parent = parent, scripts = {}, registered = {}, shown = true }, {
            __index = function(_, key) return methods[key] or noop end,
        })
        f.frames[#f.frames + 1] = frame
        return frame
    end
    function methods:RegisterEvent(event) self.registered[event] = true end
    function methods:UnregisterEvent(event) self.registered[event] = nil end
    function methods:SetScript(event, fn) self.scripts[event] = fn end
    function methods:GetFrameLevel() return 0 end
    function methods:GetWidth() return rawget(self, "width") or 400 end
    function methods:SetWidth(width) self.width = width end
    function methods:SetHeight(height) self.height = height end
    function methods:SetSize(width, height) self.width, self.height = width, height end
    function methods:SetText(value) self.text = value end
    function methods:GetText() return self.text or "" end
    function methods:GetChecked() return rawget(self, "checked") end
    function methods:SetChecked(value) self.checked = value end
    function methods:SetEnabled(enabled) self.enabled = enabled end
    function methods:SetPoint(...) self.point = { ... } end
    function methods:SetColorTexture(...) self.color = { ... } end
    function methods:CreateFontString() return object("FontString", self) end
    function methods:CreateTexture() return object("Texture", self) end
    function methods:IsVisible()
        local parent = rawget(self, "parent")
        return self.shown and (not parent or parent:IsVisible())
    end
    function methods:IsShown() return self.shown end
    function methods:Show()
        local wasShown = self.shown
        self.shown = true
        if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function methods:Hide()
        local wasShown = self.shown
        self.shown = false
        if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function methods:SetShown(value) if value then self:Show() else self:Hide() end end
    function methods:GetAlpha() return 1 end
    function f:emit(event, ...)
        for _, frame in ipairs(self.frames) do
            if frame.registered[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
        end
    end
    function f:advance(seconds)
        local finish = self.now + seconds
        for _ = 1, 1000 do
            local nextTimer
            for _, t in ipairs(self.timers) do
                if not t.cancelled and t.at <= finish and (not nextTimer or t.at < nextTimer.at) then nextTimer = t end
            end
            if not nextTimer then self.now = finish return end
            self.now, nextTimer.cancelled = nextTimer.at, true
            nextTimer.fn()
        end
        error("timer loop")
    end
    env.CreateFrame = function(kind, _, parent) return object(kind, parent) end
    env.GetTime = function() return f.now end
    env.GetMoney = function() return f.money or 1000000 end
    env.GetServerTime = function() return 1794820000 + math.floor(f.now) end
    env.BuyWheelDB = { schemaVersion = 1, single = {}, multi = {}, sell = {} }
    env.InCombatLockdown = function() return false end
    env.Enum = { AuctionHouseSortOrder = { Price = 1 }, ItemCommodityStatus = { Commodity = 2 } }
    env.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    env.C_Container = {
        GetContainerNumSlots = function(bag) return #(f.bags[bag] or {}) end,
        GetContainerItemInfo = function(bag, slot) return f.bags[bag][slot] end,
    }
    env.NUM_BAG_SLOTS = 1
    env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 1
    env.GameTooltip = { Hide = noop, SetOwner = noop, AddLine = noop, Show = noop }
    env.PanelTemplates_DeselectTab, env.PanelTemplates_SelectTab, env.PanelTemplates_TabResize = noop, noop, noop
    env.LibStub = false
    env.hooksecurefunc = function(_, method, fn) f.hooks[method] = fn end
    env.RegisterStateDriver = noop
    env.SetOverrideBindingClick = function(_, _, key) f.bound = f.bound or {} f.bound[key] = true end
    env.ClearOverrideBindings = function() f.bound = {} end
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.NUM_CHAT_WINDOWS = 0
    env.C_Timer = { NewTimer = function(delay, fn)
        local timer = { at = f.now + delay, fn = fn }
        function timer:Cancel() self.cancelled = true end
        f.timers[#f.timers + 1] = timer
        return timer
    end }
    env.C_Timer.After = env.C_Timer.NewTimer
    local function command(name, key)
        f.calls[#f.calls + 1] = { name = name, key = key }
        if f.hooks[name] then f.hooks[name](key) end
        f.ready = false
        if f.rejectQuery then error("query rejected") end
    end
    local ah = {
        GetItemKeyFromItem = function(loc) return { itemID = f.bags[loc.bag][loc.slot].itemID } end,
        GetItemCommodityStatus = function(loc) return f.bags[loc.bag][loc.slot].equipment and 1 or 2 end,
        GetItemKeyInfo = function(key) return { itemName = "Material " .. key.itemID, isCommodity = true } end,
        IsSellItemValid = function(loc) return not f.bags[loc.bag][loc.slot].bound end,
        IsThrottledMessageSystemReady = function() return f.ready end,
        SendSearchQuery = function(key) command("SendSearchQuery", key) end,
        RequestMoreCommoditySearchResults = function(key) command("RequestMoreCommoditySearchResults", key) end,
        HasFullCommoditySearchResults = function() return f.full ~= false end,
        GetNumCommoditySearchResults = function(itemID) return #(f.listings[itemID] or {}) end,
        GetCommoditySearchResultInfo = function(itemID, i) return f.listings[itemID][i] end,
        SupportsCopperValues = function() return not f.wholeSilver end,
        GetAvailablePostCount = function(loc)
            local item = f.bags[loc.bag] and f.bags[loc.bag][loc.slot]
            if not item then return 0 end
            local total = 0
            for _, bag in pairs(f.bags) do
                for _, row in ipairs(bag) do
                    if row.itemID == item.itemID and not row.isLocked and not row.bound then total = total + row.stackCount end
                end
            end
            return total
        end,
        CalculateCommodityDeposit = function(_, _, quantity) return quantity end,
        PostCommodity = function(loc, duration, quantity, price)
            command("PostCommodity", loc)
            local call = f.calls[#f.calls]
            call.quantity, call.price, call.duration = quantity, price, duration
            if f.failPost then error("post rejected") end
            return f.confirmRequired == true
        end,
        ConfirmPostCommodity = function(loc, duration, quantity, price)
            command("ConfirmPostCommodity", loc)
            local call = f.calls[#f.calls]
            call.quantity, call.price, call.duration = quantity, price, duration
        end,
        CancelSell = function() f.cancels = (f.cancels or 0) + 1 end,
    }
    env.C_Item = { GetItemGUID = function(loc)
        local item = f.bags[loc.bag] and f.bags[loc.bag][loc.slot]
        return item and (item.guid or tostring(item.itemID) .. ":" .. loc.bag .. ":" .. loc.slot)
    end }
    env.C_AuctionHouse = ah
    env.AuctionHouseFrame = object("AuctionHouse")
    env.AuctionHouseFrame.Tabs = { object("NativeTab") }
    setfenv(assert(loadfile(root .. "Core.lua")), env)("BuyWheel", addon)
    setfenv(assert(loadfile(root .. "Sell/Market.lua")), env)("BuyWheel", addon)
    setfenv(assert(loadfile(root .. "Sell/Selling.lua")), env)("BuyWheel", addon)
    setfenv(assert(loadfile(root .. "Sell/Panel.lua")), env)("BuyWheel", addon)
    for _, mode in ipairs({ addon.Single, addon.Multi }) do
        mode.panel = object("BuyPanel")
        function mode:Stop() self.stops = (self.stops or 0) + 1 end
        function mode:HidePanel() self.panel:Hide() end
        function mode:HasPendingAHWork() return self.pending == true end
    end
    f.env, f.addon, f.sell = env, addon, addon.Sell
    function f:open()
        self:emit("ADDON_LOADED", "BuyWheel")
        self:emit("AUCTION_HOUSE_SHOW")
        self:advance(0)
        self.sell.panel:Show()
    end
    function f:item(id)
        for _, item in ipairs(self.sell.inventory) do if item.key.itemID == id then return item end end
        error("missing bag item " .. id)
    end
    function f:read(itemID, rows)
        self.listings[itemID] = rows
        self.ready = true
        self.sell:Select(self:item(itemID))
        self:emit("COMMODITY_SEARCH_RESULTS_UPDATED", itemID)
        self.ready = true
    end
    function f:completePost()
        local job = self.sell.post
        local remaining = job.quantity
        for _, bag in pairs(self.bags) do
            for i = #bag, 1, -1 do
                local item = bag[i]
                if item.itemID == job.plan.item.key.itemID and not item.isLocked then
                    local take = math.min(remaining, item.stackCount)
                    item.stackCount, remaining = item.stackCount - take, remaining - take
                    if item.stackCount == 0 then table.remove(bag, i) end
                end
            end
        end
        eq(remaining, 0)
        self:emit("AUCTION_HOUSE_AUCTION_CREATED")
        self:emit("BAG_UPDATE_DELAYED")
    end
    f.bags[0] = { { itemID = 2589, stackCount = 12 }, { itemID = 2592, stackCount = 20 } }
    return f
end

test("SellWheel registers a third tab, groups bag stacks and excludes bound items and equipment", function()
    local f = fixture()
    f.bags[1] = { { itemID = 2589, stackCount = 5, isLocked = true },
        { itemID = 3000, stackCount = 1, equipment = true }, { itemID = 3001, stackCount = 3, bound = true } }
    f:open()
    eq(#f.addon.modes, 3)
    eq(f.addon.tabsCreated, true)
    eq(f.sell.tab.text, "SW")
    eq(#f.sell.inventory, 2)
    eq(f:item(2589).quantity, 17)
    eq(f:item(2589).available, 12)
    eq(#f.calls, 0, "opening SellWheel does not send a market query")
    f.sell:Select(f:item(2589))
    f.bags[0][1].stackCount = 7
    f:emit("BAG_UPDATE_DELAYED")
    f.sell.panel:RefreshSellWheel()
    eq(f.sell.selected.quantity, 12)
end)

test("SellWheel aggregates full price levels, own quantities and cumulative depth without dropping bait", function()
    local f = fixture()
    f:open()
    f.listings[2589] = { { unitPrice = 200, quantity = 400, numOwnerItems = 50 },
        { unitPrice = 100, quantity = 1 }, { unitPrice = 200, quantity = 100, containsAccountItem = true },
        { unitPrice = 120, quantity = 8 }, { unitPrice = 0, quantity = 999 } }
    f.sell:Select(f:item(2589))
    eq(#f.calls, 1)
    f:emit("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
    eq(#f.sell.tiers, 3)
    eq(f.sell.tiers[1].quantity, 1)
    eq(f.sell.tiers[3].price, 200)
    eq(f.sell.tiers[3].quantity, 500)
    eq(f.sell.tiers[3].owned, 50)
    eq(f.sell.tiers[3].accountUnknown, true)
    eq(f.sell.tiers[3].cheaper, 9)
    eq(f.sell.tiers[3].cumulative, 509)
    eq(f.sell.totalQuantity, 509)
    eq(f.sell.totalOwned, 50)
    eq(f.sell:HasPendingAHWork(), false)
    for i = 1, 20 do f.sell.panel:RefreshSellWheel() end
    eq(#f.calls, 1, "view refreshes send no AH queries")
end)

test("SellWheel waits for throttle and all pages before publishing the chart", function()
    local f = fixture()
    f:open()
    f.ready = false
    f.sell:Select(f:item(2589))
    eq(#f.calls, 0)
    f.ready = true
    f:emit("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    eq(#f.calls, 1)
    f.full = false
    f.listings[2589] = { { unitPrice = 100, quantity = 1 } }
    f:emit("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
    eq(f.sell.tiers, nil)
    eq(#f.calls, 1, "pagination waits for readiness")
    f.ready = true
    f.sell:Pump()
    eq(f.calls[2].name, "RequestMoreCommoditySearchResults")
    f.full = true
    f.listings[2589][2] = { unitPrice = 200, quantity = 20 }
    f:emit("COMMODITY_SEARCH_RESULTS_ADDED", 2589)
    eq(#f.sell.tiers, 2)
end)

test("SellWheel ignores wrong-item and abandoned replies during rapid item changes", function()
    local f = fixture()
    f:open()
    f.sell:Select(f:item(2589))
    f.sell:Select(f:item(2592))
    eq(#f.calls, 1)
    f:emit("COMMODITY_SEARCH_RESULTS_UPDATED", 2592)
    eq(f.sell:HasPendingAHWork(), true)
    f:emit("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
    eq(f.sell.tiers, nil)
    f.ready = true
    f.sell:Pump()
    eq(f.calls[2].key.itemID, 2592)
    f.listings[2592] = { { unitPrice = 500, quantity = 30 } }
    f:emit("COMMODITY_SEARCH_RESULTS_UPDATED", 2592)
    eq(f.sell.tiers[1].price, 500)
end)

test("Mode switches stop buys, wait for in-flight work and drain SellWheel reads", function()
    local f = fixture()
    f.addon.Single.pending = true
    f:open()
    assert(f.addon.Single.stops > 0 and f.addon.Multi.stops > 0)
    f.sell:Select(f:item(2589))
    eq(#f.calls, 0, "pending buy work owns the AH until settled")
    assert(f.addon:BusyMessage(f.sell))
    f.addon.Single.pending = false
    f.sell:Pump()
    eq(#f.calls, 1)
    f.addon:SelectMode(f.addon.Multi)
    eq(f.addon:CanUseMode(f.addon.Multi), false, "hidden SellWheel read must drain")
    f:emit("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
    eq(f.addon:CanUseMode(f.addon.Multi), true)
    eq(f.sell.tiers, nil)
end)

test("SellWheel handles timeouts, explicit query errors and foreign searches without automatic loops", function()
    local f = fixture()
    f:open()
    f.sell:Select(f:item(2589))
    f:advance(5.01)
    eq(f.sell.request, nil)
    eq(f.sell.tiers, nil)
    eq(#f.calls, 1)
    f.ready, f.rejectQuery = true, true
    f.sell:Select(f:item(2589))
    eq(f.sell.request, nil)
    eq(#f.calls, 2)
    f.ready, f.rejectQuery = true, false
    f.sell:Select(f:item(2589))
    f.hooks.SendSearchQuery({ itemID = 2589 })
    f.listings[2589] = { { unitPrice = 999, quantity = 99 } }
    f:emit("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
    eq(f.sell.tiers, nil, "another addon's same-item results are not published")
    eq(f.sell.request, nil)
end)

test("SellWheel lists the price levels, marks nothing without data and browsing never posts", function()
    local f = fixture()
    f:open()
    f.listings[2589] = {}
    for i = 1, 25 do f.listings[2589][i] = { unitPrice = i * 100, quantity = i } end
    f.sell:Select(f:item(2589))
    f:emit("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
    f.ready = true
    f.sell.panel:RefreshSellWheel()
    assert(f.sell.listing and #f.sell.listing >= 25, "the comparison list keeps every level")
    eq(#f.sell.presets, 2)
    assert(f.sell.panel.listRows[1].shown, "the list shows rows")
    assert(f.sell.panel.sellButton.enabled, "the main button is ready")
    eq(#f.calls, 1)
    f.bags[0] = {}
    f:emit("BAG_UPDATE_DELAYED")
    f.sell.panel:RefreshSellWheel()
    eq(f.sell.selected, nil)
    eq(f.sell.tiers, nil)
end)

-- Default share here is 100 % cheapest, so a single click posts everything.
local function seller(share)
    local f = fixture()
    f.bags[0][1].stackCount = 100
    f:open()
    f.sell:SetCheapShare(share or 100)
    f:read(2589, { { unitPrice = 100, quantity = 2 }, { unitPrice = 120, quantity = 8 },
        { unitPrice = 200, quantity = 100 }, { unitPrice = 205, quantity = 300 },
        { unitPrice = 210, quantity = 1200 } })
    return f
end

test("Two prices: cheapest skips thin levels, the 25 % level follows, recalculation sends no queries", function()
    local f = seller()
    eq(f.sell.presets[1].price, 200, "Günstigstes is the first meaningful level itself, no undercut")
    eq(f.sell.presets[2].price, 204, "the 25 % level is reached in the 205 tier, one step below")
    eq(f.sell.presets[1].lowest, 100)
    eq(f.sell.presets[1].ahead, 10)
    assert(math.abs(f.sell.presets[1].aheadShare - 10 / 1610) < 1e-9)
    f.sell:UpdatePrices()
    eq(#f.calls, 1)
    f.wholeSilver = true
    f.sell:UpdatePrices()
    for _, preset in ipairs(f.sell.presets) do eq(preset.price % 100, 0) end
end)

test("A thin bait level is not the cheapest price", function()
    local f = fixture()
    f.bags[0][1].stackCount = 100
    f:open()
    f:read(2589, { { unitPrice = 34, quantity = 2 }, { unitPrice = 35, quantity = 121 },
        { unitPrice = 37, quantity = 136 }, { unitPrice = 38, quantity = 40 },
        { unitPrice = 39, quantity = 127 }, { unitPrice = 40, quantity = 402 } })
    eq(f.sell.presets[1].price, 35, "the 2-unit level at 34 is skipped: 35 is the first meaningful level")
    assert(f.sell.presets[2].price >= f.sell.presets[1].price)
end)

test("The list marks the rows our two prices land on, including planned prices without a level", function()
    local f = seller(50)
    local found = {}
    for _, row in ipairs(f.sell.listing) do
        if row.stage then found[row.stage] = row end
    end
    assert(found[1] and not found[1].planned and found[1].price == 200, "200 marks the existing level")
    assert(found[2] and found[2].planned and found[2].price == 204, "204 has no level and becomes a planned row")
    for i = 2, #f.sell.listing do
        assert(f.sell.listing[i - 1].price <= f.sell.listing[i].price, "rows stay sorted by price")
    end
    f.sell.panel:RefreshSellWheel()
    assert(f.sell.panel.listRows[1].shown)
end)

test("Sale previews split 50/50, round the cheap share and merge identical prices", function()
    local f = seller(50)
    local preview = assert(f.sell:SalePreview())
    eq(preview.counts[1], 50)
    eq(preview.counts[2], 50)
    eq(preview.quantity, 100)
    eq(preview.total, 50 * 200 + 50 * 204)
    f.sell.quantity = 1
    preview = assert(f.sell:SalePreview())
    eq(preview.counts[1], 1)
    eq(preview.counts[2], 0)
    f.sell.quantity = 7
    f.sell:SetCheapShare(0)
    preview = assert(f.sell:SalePreview())
    eq(preview.counts[1], 0)
    eq(preview.counts[2], 7)
    f.sell:SetCheapShare(50)
    f.sell.presets[2].price = f.sell.presets[1].price
    preview = assert(f.sell:SalePreview())
    eq(#preview.entries, 1)
    eq(preview.entries[1].quantity, 7)
end)

test("Invalid quantities, shares and stale prices never post", function()
    for _, value in ipairs({ 0, -1, 101, 1.5, "" }) do
        local f = seller()
        f.sell.quantity = value
        f.sell:PostNext()
        eq(#f.calls, 1)
    end
    local f = seller(50)
    for _, value in ipairs({ -1, 101, 1.5, "x", "" }) do
        f.sell:SetCheapShare(value)
        eq(f.sell:CheapShare(), 50, "an invalid share is ignored")
    end
    f.sell:SetCheapShare(30)
    eq(f.sell:CheapShare(), 30)
    f = seller()
    f:advance(61)
    f.sell:PostNext()
    eq(#f.calls, 2, "stale prices are reloaded, never posted")
    eq(f.calls[2].name, "SendSearchQuery")
end)

test("One price (100 % or 0 % cheap) posts everything once and confirmations do not post duplicates", function()
    local f = seller(0)
    f.sell:PostNext()
    eq(f.calls[2].name, "PostCommodity")
    eq(f.calls[2].quantity, 100)
    eq(f.calls[2].price, 204, "0 % cheap sells all at the 25 % price")
    eq(f.calls[2].duration, 1)
    for i = 1, 20 do f.sell:PostNext() end
    eq(#f.calls, 2)
    f:completePost()
    eq(f.sell.post, nil)
    eq(f.sell.plan, nil)
    eq(f.sell.quantity, 0)
    eq(f.sell.db.postDiagnostics[1].outcome, "posted")
    f:emit("AUCTION_HOUSE_AUCTION_CREATED")
    eq(#f.calls, 2)
end)

test("The two stages post one per fresh click, with frozen prices and no timed continuation", function()
    local f = seller(50)
    for i, expected in ipairs({ { 50, 200 }, { 50, 204 } }) do
        f.ready = true
        f.sell:PostNext()
        eq(f.calls[#f.calls].quantity, expected[1])
        eq(f.calls[#f.calls].price, expected[2])
        local before = #f.calls
        f:completePost()
        f.ready = true
        f:emit("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
        f:advance(0.2)
        eq(#f.calls, before, "post completion and timers never send the next stage")
        if i < 2 then
            f.sell:Select(f:item(2592))
            eq(f.sell.selected.key.itemID, 2589, "item selection is locked for the active plan")
        end
    end
    eq(f.sell.plan, nil)
    eq(#f.sell.db.postDiagnostics, 2)
end)

test("AH confirmation requires another click and cancelling it releases the plan", function()
    local f = seller()
    f.confirmRequired = true
    f.sell:PostNext()
    eq(f.sell.post.state, "confirm")
    f.ready = true
    f:emit("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    eq(#f.calls, 2)
    f.sell:PostNext()
    eq(f.calls[3].name, "ConfirmPostCommodity")
    eq(f.calls[3].quantity, 100)
    eq(f.calls[3].price, 200)
    f:completePost()
    eq(f.sell.post, nil)
    f = seller()
    f.confirmRequired = true
    f.sell:PostNext()
    f.sell:Stop()
    eq(f.sell.post, nil)
    eq(f.sell.plan, nil)
    eq(f.cancels, 1)
end)

test("Bag changes, deposit shortage and busy AH block posting", function()
    local f = seller()
    f.ready = false
    f.sell:PostNext()
    eq(#f.calls, 1)
    f.ready, f.money = true, 0
    f.sell:PostNext()
    eq(#f.calls, 1)
    f = seller()
    f.confirmRequired = true
    f.sell:PostNext()
    f.bags[0][1].guid = "replaced"
    f.ready = true
    f.sell:PostNext()
    eq(#f.calls, 2, "changed stack cannot be confirmed")
    eq(f.sell.post, nil)
end)

test("Failures do not retry, uncertain posts retain AH ownership until checked or resolved", function()
    local f = seller()
    f.failPost = true
    f.sell:PostNext()
    eq(f.sell.post, nil)
    eq(f.sell.plan, nil)
    f:advance(20)
    eq(#f.calls, 2)
    f = seller()
    f.sell:PostNext()
    f:advance(12.01)
    eq(f.sell.post.state, "unknown")
    f.addon:SelectMode(f.addon.Multi)
    eq(f.addon:CanUseMode(f.addon.Multi), false)
    f.sell:CancelPosting(true)
    eq(f.addon:CanUseMode(f.addon.Multi), true)
    eq(#f.calls, 2)
    f = seller()
    f.sell:PostNext()
    f:advance(12.01)
    f:completePost()
    eq(f.sell.post, nil)
    eq(f.sell.db.postDiagnostics[1].outcome, "posted", "late confirmation resolves the original post")
end)

test("The duration checkboxes choose the auction duration code", function()
    local f = seller()
    local panel = f.sell.panel
    eq(f.sell:Duration(), 1, "2 hours by default")
    panel.durationBoxes[3].scripts.OnClick()
    eq(f.sell:Duration(), 3)
    panel:RefreshSellWheel()
    assert(panel.durationBoxes[3].checked and not panel.durationBoxes[1].checked)
    f.sell:PostNext()
    eq(f.calls[2].name, "PostCommodity")
    eq(f.calls[2].duration, 3, "the post uses the selected duration")
    eq(f.sell.post.log.durationHours, 24)
    f.sell:SetDuration(1)
    eq(f.sell:Duration(), 3, "no change while a post is running")
end)

test("The Verkaufen button starts the plan; the wheel only continues a running plan", function()
    local f = seller(50)
    local panel = f.sell.panel
    panel:RefreshSellWheel()
    assert(panel.sellButton.enabled, "ready to sell")
    eq(panel.sellButton.text, "Verkaufen (2 Schritte)")
    eq(f.sell:WheelEnabled(), true, "the wheel option is on by default")
    -- Without a plan the wheel does nothing: it never starts a sale.
    f.sell:WheelStep()
    eq(#f.calls, 1)
    assert(not (f.bound and f.bound.MOUSEWHEELUP), "the wheel is not taken over without a plan")
    panel.sellButton.scripts.OnClick()
    eq(f.calls[2].quantity, 50)
    eq(f.calls[2].price, 200)
    f:completePost()
    f.ready = true
    f:emit("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    f:advance(0.2)
    panel:RefreshSellWheel()
    eq(panel.sellButton.text, "Weiter · Schritt 2/2")
    assert(f.bound and f.bound.MOUSEWHEELUP, "the wheel is bound while the plan runs")
    -- Switched off, the wheel does nothing.
    panel.wheelBox.checked = false
    panel.wheelBox.scripts.OnClick(panel.wheelBox)
    f.sell:WheelStep()
    eq(#f.calls, 2)
    panel.wheelBox.checked = true
    panel.wheelBox.scripts.OnClick(panel.wheelBox)
    panel:RefreshSellWheel()
    f.sell:WheelStep()
    eq(f.calls[3].quantity, 50)
    eq(f.calls[3].price, 204)
    f.sell:WheelStep()
    eq(#f.calls, 3, "a wheel step never posts while a post is still running")
    f:completePost()
    eq(f.sell.plan, nil)
    panel:RefreshSellWheel()
    assert(not (f.bound and f.bound.MOUSEWHEELUP), "the finished plan releases the wheel")
end)

test("Delayed bag updates prevent the next stage from posting stale stock", function()
    local f = seller(50)
    f.sell:PostNext()
    f:emit("AUCTION_HOUSE_AUCTION_CREATED")
    assert(f.sell.waitingForBags)
    f.ready = true
    f.sell:PostNext()
    eq(#f.calls, 2)
    f.bags[0][1].stackCount = 50
    f:emit("BAG_UPDATE_DELAYED")
    f.sell.panel:RefreshSellWheel()
    eq(f.sell.waitingForBags, nil)
    f.sell:PostNext()
    eq(f.calls[3].quantity, 50)
end)

test("Tab switches drain sent posts and foreign postings are not credited as ours", function()
    local f = seller()
    f.sell:PostNext()
    f.addon:SelectMode(f.addon.Multi)
    eq(f.addon:CanUseMode(f.addon.Multi), false)
    f:completePost()
    eq(f.addon:CanUseMode(f.addon.Multi), true)
    eq(#f.calls, 2)
    f = seller()
    f.sell:PostNext()
    f.hooks.PostCommodity({})
    f:emit("AUCTION_HOUSE_AUCTION_CREATED")
    f:emit("AUCTION_HOUSE_POST_ERROR")
    eq(f.sell.post.state, "unknown")
    eq(f.sell.post.log.outcome, "interference")
    f.sell:CancelPosting(true)
    eq(f.sell.post, nil)
    eq(#f.calls, 2)
end)

print("PASS " .. count .. " SellWheel scenarios")
