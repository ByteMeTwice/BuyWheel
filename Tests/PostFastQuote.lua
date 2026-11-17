-- Run from the WoW directory with Lua 5.1:
-- lua Interface/AddOns/BuyWheel/Tests/PostFastQuote.lua
-- Optional first argument: path to the BuyWheel addon, including trailing slash.
local root = ... or "Interface/AddOns/BuyWheel/"
local count = 0
local function eq(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Compile every loaded addon file as well as executing Market against a small,
-- deterministic AH. No real client, purchases or network calls are involved.
for _, path in ipairs({ "Core.lua", "Fingerprint.lua", "Feedback.lua", "Statistics.lua", "Help.lua",
    "Single/Market.lua", "Single/Panel.lua", "Multi/Market.lua", "Multi/Multi.lua",
    "Multi/Learning.lua", "Multi/Depth.lua", "Multi/Panel.lua", "Sell/Market.lua", "Sell/Selling.lua", "Sell/Panel.lua" }) do
    assert(loadfile(root .. path))
end

local function fixture(options)
    options = options or {}
    local f = { now = 100, ready = true, calls = {}, timers = {}, money = 100000, bindings = false }
    local env = setmetatable({}, { __index = _G })
    local mode = {}
    local addon = { Single = options.multi and {} or mode, Multi = options.multi and mode or {} }
    function addon:CanUseMode() return true end
    function addon:PurchaseStatsKey() return "test", "Test" end
    function addon:LearnedNormalPrice() end
    function addon:RecordPurchaseStats() end
    function addon:RecordBaitPost() end
    function addon:RecordBaitSale() end
    function addon:NoteOwnPost() end
    function addon:IsMarketRow(row) return not row.containsOwnerItem and not row.containsAccountItem end
    if options.fingerprint then
        setfenv(assert(loadfile(root .. "Fingerprint.lua")), env)("BuyWheel", addon)
    else
        function addon:FingerprintPrice(price) return price end
        function addon:LooksLikeBait() return false end
    end
    function addon:StartPurchaseStats() end
    function addon:StopPurchaseStats() end
    function addon:Notify(m, message) m.notice = message end
    function mode:BindWheel(enable) f.bindings = enable end
    local function timer(delay, callback)
        local t = { at = f.now + delay, callback = callback }
        function t:Cancel() self.cancelled = true end
        f.timers[#f.timers + 1] = t
        return t
    end
    function f:advance(seconds)
        local untilTime = self.now + seconds
        for _ = 1, 1000 do
            local nextTimer
            for _, t in ipairs(self.timers) do
                if not t.cancelled and t.at <= untilTime and (not nextTimer or t.at < nextTimer.at) then nextTimer = t end
            end
            if not nextTimer then self.now = untilTime return end
            self.now = nextTimer.at
            nextTimer.cancelled = true
            nextTimer.callback()
        end
        error("timer loop")
    end
    local function command(name, ...)
        f.calls[#f.calls + 1] = { name = name, args = { ... } }
        f.ready = false
    end
    function f:total(name)
        local n = 0
        for _, call in ipairs(self.calls) do if call.name == name then n = n + 1 end end
        return n
    end
    local ah = {
        IsThrottledMessageSystemReady = function() return f.ready end,
        IsSellItemValid = function() return true end,
        GetAvailablePostCount = function() return 1 end,
        GetItemCommodityStatus = function() return 1 end,
        PostCommodity = function(...) command("post", ...) return options.confirmPost == true end,
        ConfirmPostCommodity = function(...) command("post_confirm", ...) end,
        StartCommoditiesPurchase = function(...) command("quote", ...) end,
        ConfirmCommoditiesPurchase = function(...) command("confirm", ...) end,
        CancelCommoditiesPurchase = function(...) command("cancel", ...) end,
        HasSearchResults = function() return false end,
        SendSearchQuery = function(...) command("list", ...) end,
        SendBrowseQuery = function(...) command("browse", ...) end,
        SearchForItemKeys = function(...) command("batch", ...) end,
        GetBrowseResults = function() return f.browseRows or {} end,
        HasFullBrowseResults = function() return f.fullBrowse ~= false end,
        GetItemKeyInfo = function() return { itemName = "Linen Cloth", isCommodity = true } end,
        HasFullCommoditySearchResults = function() return true end,
        GetNumCommoditySearchResults = function() return #f.listings end,
        GetCommoditySearchResultInfo = function(_, i) return f.listings[i] end,
    }
    env.C_AuctionHouse = ah
    env.C_Timer = { NewTimer = timer, After = timer }
    env.Enum = { AuctionHouseSortOrder = { Price = 1, Buyout = 2, Bid = 3 },
        ItemCommodityStatus = { Commodity = 1 }, AuctionHouseNotification = { AuctionSold = 4 } }
    env.GetTime = function() return f.now end
    env.GetServerTime = function() return 100000 end
    env.GetMoney = function() return f.money end
    env.InCombatLockdown = function() return false end
    env.AuctionHouseFrame = { GetAlpha = function() return 1 end }
    env.ItemLocation = { CreateFromBagAndSlot = function() return {} end }
    env.C_Item = { GetItemGUID = function() return "bag-item" end,
        GetItemMaxStackSizeByID = function() return 200 end }
    env.C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
        GetContainerItemInfo = function() if not f.noStock then return { itemID = 2589, isLocked = false } end end,
    }
    env.CreateFrame = function()
        local frame = {}
        function frame:RegisterEvent() end
        function frame:SetScript(_, fn) f.dispatch = fn end
        return frame
    end
    function f:emit(event, ...) self.dispatch(nil, event, ...) end
    setfenv(assert(loadfile(root .. (options.multi and "Multi" or "Single") .. "/Market.lua")), env)("BuyWheel", addon)
    if options.multi then
        setfenv(assert(loadfile(root .. "Multi/Multi.lua")), env)("BuyWheel", addon)
        setfenv(assert(loadfile(root .. "Multi/Learning.lua")), env)("BuyWheel", addon)
        setfenv(assert(loadfile(root .. "Multi/Depth.lua")), env)("BuyWheel", addon)
    end
    mode.db = { fastQuoteX3 = options.fast ~= false, fastQuote = options.one == true,
        fastQuoteQuantity = 10, leaveBait = options.leave == true, routes = {},
        purchaseDiagnostics = {}, postDiagnostics = {}, scanDiagnostics = {}, watchItems = {},
        baitPrice = options.baitPrice ~= nil and options.baitPrice or 99 }
    if options.unsetBaitPrice then mode.db.baitPrice = nil end
    if options.one then mode.db.fastQuoteX3 = false end
    mode.target = { key = { itemID = 2589 }, id = "2589:0:0:0", name = "Linen Cloth", commodity = true, stackSize = 200 }
    mode.maxPrice, mode.budget = 100, options.budget or 10000
    mode.db.maxPrice, mode.db.budget = mode.maxPrice, mode.budget
    mode.running, mode.open = options.running ~= false, true
    mode.panel = { IsVisible = function() return true end }
    if not options.multi and options.repeatBait ~= false then mode:SetRepeatBait(true) end
    f.listings = { { unitPrice = 80, quantity = 21, numOwnerItems = 1 } }
    f.mode, f.env, f.addon = mode, env, addon
    setfenv(assert(loadfile(root .. "Feedback.lua")), env)("BuyWheel", addon)
    if options.realStats then
        setfenv(assert(loadfile(root .. "Statistics.lua")), env)("BuyWheel", addon)
    end
    function f:post()
        self.mode:PostOne()
        eq(self:total("post"), 1, "one bait posted")
        self:emit("AUCTION_HOUSE_AUCTION_CREATED")
    end
    function f:readyAfterPost()
        self.ready = true
        self:advance(0.51)
    end
    return f
end

local function test(title, run)
    run()
    count = count + 1
    print("PASS " .. title)
end

test("Multi starts with eleven current favorites instead of seventeen saved watches", function()
    local f = fixture({ multi = true, running = false })
    local mode = f.mode
    mode.favorites = {}
    for i = 1, 17 do
        local key = { itemID = 3000 + i }
        mode.db.watchItems[mode:WatchID(key)] = { key = key, enabled = true, maxPrice = 100 }
        if i <= 11 then mode.favorites[#mode.favorites + 1] = { itemKey = key } end
    end
    mode:Start()
    eq(mode.running, true)
    eq(#mode.runWatchKeys, 11)
    eq(f:total("batch"), 1)
    eq(#f.calls[1].args[1], 11, "actual AH query excludes removed favorites")
    for _, key in ipairs(f.calls[1].args[1]) do
        assert(key.itemID <= 3011, "removed favorite sent to AH")
    end
    eq(mode.db.watchItems["3017:0:0:0"].enabled, true, "saved settings remain intact")
end)

test("Multi filters unchecked and unpriced favorites, deduplicates keys and keeps variants separate", function()
    local f = fixture({ multi = true, running = false })
    local mode = f.mode
    local keys = { { itemID = 3001 }, { itemID = 3002 }, { itemID = 3003 },
        { itemID = 3001, itemLevel = 10 } }
    mode.favorites = {}
    for i, key in ipairs(keys) do
        mode.db.watchItems[mode:WatchID(key)] = { key = key, enabled = i ~= 2, maxPrice = i == 3 and 0 or 100 }
        if i < 4 then mode.favorites[#mode.favorites + 1] = { itemKey = key } end
    end
    mode.favorites[#mode.favorites + 1] = mode.favorites[1]
    eq(#mode:WatchKeys(), 1)
    mode.favorites = {}
    eq(#mode:WatchKeys(), 0)
    eq(mode:CanStart(), false)
    mode.favorites = { { itemKey = keys[4] } }
    eq(mode:WatchKeys()[1], keys[4], "re-added variant uses its saved setting")
    mode.favoritesPending = true
    eq(mode:CanStart(), false, "wait for refreshed favorites before starting")
    mode.favoritesPending, mode.favoritesError = false, true
    eq(mode:CanStart(), false, "failed favorites refresh cannot use stale entries")
    mode.favoritesError = false
    eq(mode:CanStart(), true)
end)

local function priorityFixture()
    local f = fixture({ multi = true, realStats = true, fast = false, one = true })
    f.mode.watchLows = {}
    f.mode.db.learnedPrices = {}
    -- The ranking tests need the deterministic order; Volume Trading is on by default.
    f.mode.db.volumeTrading = false
    function f:candidate(id, price, normal, limit, quantity)
        local key = { itemID = id }
        local watchID = self.mode:WatchID(key)
        self.mode.db.watchItems[watchID] = { key = key, enabled = true, maxPrice = limit or 100 }
        if normal then self.mode.db.learnedPrices[watchID] = { normalPrice = normal } end
        return { itemKey = key, minPrice = price, totalQuantity = quantity or 100, containsOwnerItem = false }
    end
    return f
end

test("Multi prioritizes absolute per-unit margin over rotation, discount percentage and group size", function()
    local f = priorityFixture()
    local cheap = f:candidate(3001, 1, 10, 100, 99999)
    local valuable = f:candidate(3002, 90, 150, 100, 100)
    eq(f.mode:ChooseWatch({ cheap, valuable }), valuable)
    eq(f.mode:ChooseWatch({ valuable, cheap }), valuable, "higher margin stays first on the next query")
    eq(f.mode.watchSelection.margin, 60)
    eq(f.mode.watchSelection.source, "normal_price")
    eq(#f.calls, 0, "ranking never sends AH requests")
end)

test("Volume Trading is on by default: several candidates are drawn by weight", function()
    local f = priorityFixture()
    f.mode.db.volumeTrading = nil
    local a = f:candidate(3001, 50, 100)
    local b = f:candidate(3002, 80, 130)
    local picked = f.mode:ChooseWatch({ a, b })
    assert(picked == a or picked == b)
    eq(f.mode.watchSelection.volume, true)
    eq(f.mode.watchSelection.candidates, 2)
end)

test("Multi equal-margin matches rotate regardless of server row order", function()
    local f = priorityFixture()
    local a = f:candidate(3001, 50, 100)
    local b = f:candidate(3002, 80, 130)
    local c = f:candidate(3003, 40, 90)
    eq(f.mode:ChooseWatch({ c, b, a }), a)
    eq(f.mode:ChooseWatch({ a, c, b }), b)
    eq(f.mode:ChooseWatch({ b, a, c }), c)
    eq(f.mode:ChooseWatch({ c, a, b }), a, "tie rotation wraps")
end)

test("Multi fallback margin preserves watch, price, quantity and budget constraints", function()
    local f = priorityFixture()
    local a = f:candidate(3001, 50, nil, 200)
    local b = f:candidate(3002, 80, 180, 100)
    eq(f.mode:ChooseWatch({ b, a }), a)
    eq(f.mode.watchSelection.margin, 150)
    eq(f.mode.watchSelection.source, "buy_limit")
    f.mode.db.watchItems[f.mode:WatchID(a.itemKey)].enabled = false
    eq(f.mode:ChooseWatch({ a, b }), b)
    local overLimit = f:candidate(3003, 101, 10000, 100)
    local noFunds = f:candidate(3004, 101, 10000, 200)
    f.money = 100
    eq(f.mode:ChooseWatch({ overLimit, noFunds, b }), b)
    f.mode.db.fastQuote, f.mode.db.fastQuoteX3 = false, true
    f.mode.db.fastQuoteQuantity = 3
    local small = f:candidate(3005, 20, 999, 100, 2)
    local costly = f:candidate(3006, 40, 999, 100, 100)
    local affordable = f:candidate(3007, 30, 100, 100, 100)
    eq(f.mode:ChooseWatch({ small, costly, affordable }), affordable)
    eq(f.mode:ChooseWatch({ small, costly }), nil)
    eq(f.mode.watchSelection, nil, "no stale selection metadata")
end)

test("Multi buys the higher-margin batch match with no added queries and logs its priority", function()
    local f = priorityFixture()
    local a = f:candidate(3001, 10, 20)
    local b = f:candidate(3002, 80, 200)
    f.mode.runWatchKeys = { a.itemKey, b.itemKey }
    f.browseRows = { a, b }
    f.mode:Pump()
    f:emit("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    eq(f.mode.target.key, b.itemKey)
    eq(f:total("batch"), 1)
    eq(f:total("list"), 0)
    eq(f:total("quote"), 0, "still requires wheel input")
    f.ready = true
    f.mode:Buy()
    eq(f:total("quote"), 1)
    local log = f.mode.db.purchaseDiagnostics[1]
    eq(log.itemID, 3002)
    eq(log.selectionMargin, 120)
    eq(log.selectionReference, 200)
    eq(log.selectionSource, "normal_price")
    f:emit("COMMODITY_PRICE_UPDATED", 80, 80)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
    eq(f.mode.unitsBought, 1)
end)

test("Multi waits for AH readiness even with the retired flag saved", function()
    local f = fixture({ multi = true, realStats = true, fast = false })
    f.mode.db.earlyBuy = true -- An old saved setting must have no effect.
    f.mode.offers = { { unit = 80, quantity = 3 } }
    f.ready = false
    f.mode:Buy()
    f:advance(0.1)
    eq(f:total("quote"), 0, "no commodity quote while the AH is busy")
    eq(f.mode.db.purchaseDiagnostics[1], nil)
    eq(f.addon:PurchaseStatsKey(f.mode), "normal", "retired flag does not split Compare")
    f.ready = true
    f.mode:Buy()
    eq(f:total("quote"), 1, "fresh input after readiness requests the quote")
    eq(f.mode.db.purchaseDiagnostics[1].earlyBuyAttempt, nil)
    eq(f.mode.db.purchaseDiagnostics[1].readyAtBuy, true)
    f.mode:Buy()
    eq(f:total("quote"), 1, "pending quote blocks duplicate input")
    f:emit("COMMODITY_PRICE_UPDATED", 80, 240)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
    eq(f.mode.unitsBought, 3)
end)

test("post does not query or buy; next real input quotes exactly ten", function()
    local f = fixture()
    f:post()
    eq(f:total("quote"), 0)
    f:readyAfterPost()
    eq(f:total("list"), 0)
    eq(f:total("browse"), 0)
    eq(f:total("quote"), 0)
    local offer = f.mode:Offer()
    eq(offer.quantity, 10)
    eq(offer.quoteOnly, true)
    f.mode:Buy()
    eq(f:total("quote"), 1)
    eq(f.calls[#f.calls].args[2], 10)
    f.mode:Buy()
    eq(f:total("quote"), 1, "no duplicate pending purchase")
    f:emit("COMMODITY_PRICE_UPDATED", 80, 800)
    eq(f:total("confirm"), 1)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
    eq(f.mode.unitsBought, 10)
    eq(f.mode.spent, 800)
    f.ready = true
    f:advance(0.51)
    eq(f:total("list"), 0, "success resumes normal scanning")
    eq(f:total("browse"), 1)
    eq(f.mode.db.purchaseDiagnostics[1].offerSource, "post_fast_quote")
end)

for _, quote in ipairs({ { "over limit", 101, 1010 }, { "mixed tiers", 80, 850 }, { "invalid", 0, 0 } }) do
    test("reject " .. quote[1] .. " and fall back to a fixed-size detailed offer", function()
        local f = fixture()
        f:post()
        f:readyAfterPost()
        f.mode:Buy()
        f:emit("COMMODITY_PRICE_UPDATED", quote[2], quote[3])
        eq(f:total("confirm"), 0)
        eq(f:total("cancel"), 1)
        eq(f.mode.spent, 0)
        f.ready = true
        f:advance(0.51)
        eq(f:total("list"), 1)
        f:emit("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
        eq(f.mode:Offer().quantity, 10, "fallback never increases the selected quantity")
        eq(f.mode:Offer().quoteOnly, nil)
    end)
end

test("reject if budget shrinks while server quote is pending", function()
    local f = fixture()
    f:post()
    f:readyAfterPost()
    f.mode:Buy()
    f.mode.budget = 500
    f:emit("COMMODITY_PRICE_UPDATED", 80, 800)
    eq(f:total("confirm"), 0)
    eq(f.mode.spent, 0)
end)

test("unavailable quote falls back once instead of retrying blindly", function()
    local f = fixture()
    f:post()
    f:readyAfterPost()
    f.mode:Buy()
    f:emit("COMMODITY_PRICE_UNAVAILABLE")
    f.ready = true
    f:advance(0.51)
    eq(f:total("list"), 1)
    eq(f:total("quote"), 1)
    eq(f.mode.spent, 0)
end)

test("without input the reserved quote slot expires into a detailed query", function()
    local f = fixture()
    f:post()
    f:readyAfterPost()
    f:advance(2.01)
    eq(f:total("quote"), 0)
    eq(f:total("list"), 1)
end)

for _, options in ipairs({ { fast = false }, { repeatBait = false }, { leave = true } }) do
    test("non-fast configuration retains detailed recovery", function()
        local f = fixture(options)
        f:post()
        f:readyAfterPost()
        eq(f:total("list"), 1)
        eq(f:total("quote"), 0)
    end)
end

test("one-item Buy Bait uses a single-item post quote", function()
    local f = fixture({ one = true })
    f:post()
    f:readyAfterPost()
    eq(f.mode:Offer().quantity, 1)
    f.mode:Buy()
    eq(f.calls[#f.calls].args[2], 1)
end)

test("Stop cancels the opportunity and never sends a timed purchase", function()
    local f = fixture()
    f:post()
    f:readyAfterPost()
    f.mode:Stop()
    f:advance(3)
    eq(f.mode:Offer(), nil)
    eq(f:total("quote"), 0)
    eq(f:total("list"), 0)
end)

test("disabling Repeat bait releases the quote opportunity", function()
    local f = fixture()
    f:post()
    f:readyAfterPost()
    f.mode:SetRepeatBait(false)
    eq(f:total("list"), 1)
    eq(f:total("quote"), 0)
end)

test("fallback does not buy a smaller or self-only quantity", function()
    for _, rows in ipairs({ { { unitPrice = 80, quantity = 10, numOwnerItems = 1 } },
        { { unitPrice = 80, quantity = 1, numOwnerItems = 1 } } }) do
        local f = fixture({ budget = 500 }) -- Ceiling is not affordable; read actual prices.
        f.listings = rows
        f:post()
        f:readyAfterPost()
        eq(f:total("list"), 1)
        f:emit("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
        eq(f.mode:Offer(), nil)
    end
end)

test("manual reserved Bait continues by wheel without buying or Repeat", function()
    local f = fixture({ repeatBait = false, running = false })
    f.ready = false
    f.mode:PostOne()
    eq(f.bindings, true)
    f.ready = true
    f.mode:Buy()
    eq(f:total("post"), 1)
    eq(f:total("quote"), 0)
    f:emit("AUCTION_HOUSE_AUCTION_CREATED")
    eq(f.bindings, false)
    eq(f:total("quote"), 0)
end)

test("an unconfirmed bait post never creates a purchase opportunity", function()
    local f = fixture()
    f.mode:PostOne()
    f:advance(10.01)
    eq(f:total("quote"), 0)
    eq(f.mode.repeatBait, nil)
    eq(f.mode.lastBait, nil)
end)

test("a sold bait is replaced before buying, with a new single quote slot", function()
    local f = fixture()
    f:post()
    f:readyAfterPost()
    f:emit("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Linen Cloth")
    f.mode:Buy()
    eq(f:total("post"), 2)
    eq(f:total("quote"), 0)
    f:emit("AUCTION_HOUSE_AUCTION_CREATED")
    f:readyAfterPost()
    f.mode:Buy()
    eq(f:total("quote"), 1)
    eq(f.calls[#f.calls].args[2], 10)
end)

test("Leave Bait enabled while ready cancels the direct quote", function()
    local f = fixture()
    f:post()
    f:readyAfterPost()
    f.mode:SetLeaveBait(true)
    eq(f:total("list"), 1)
    eq(f:total("quote"), 0)
end)

test("a conservative budget skip can still buy a cheaper full batch from listings", function()
    local f = fixture({ budget = 500 })
    f.listings = { { unitPrice = 40, quantity = 21, numOwnerItems = 1 } }
    f:post()
    f:readyAfterPost()
    eq(f:total("list"), 1)
    f:emit("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
    eq(f.mode:Offer().quantity, 10)
    eq(f.mode:Offer().cost, 400)
end)

test("new confirmed bait replaces an older timer with a missing sale message", function()
    local f = fixture({ repeatBait = false, fast = false })
    f:post()
    local old = f.mode.lastBait
    f:advance(1)
    f.ready = true
    f.mode:PostOne()
    f:emit("AUCTION_HOUSE_AUCTION_CREATED")
    local latest = f.mode.lastBait
    assert(latest ~= old)
    eq(f.mode:BaitAge(), 0, "new confirmed post resets timer")
    f:advance(0.3)
    f:emit("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Linen Cloth.")
    local age, sold = f.mode:BaitAge()
    eq(sold, true, "sale stops latest timer instead of the old one")
    eq(old.soldAt, nil, "old unconfirmed sale does not steal new message")
    eq(f.mode:HasLiveBait(), false)
    f:advance(1)
    eq(f.mode:BaitAge(), age, "sold timer stays frozen")
end)

test("failed replacement does not reset the previous timer", function()
    local f = fixture({ repeatBait = false, fast = false })
    f:post()
    local old = f.mode.lastBait
    f:advance(1)
    f.ready = true
    f.mode:PostOne()
    f:emit("AUCTION_HOUSE_POST_ERROR")
    eq(f.mode.lastBait, old)
    f:emit("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Linen Cloth.")
    local _, sold = f.mode:BaitAge()
    eq(sold, true)
end)

test("duplicate sale of previous bait does not stop the new timer", function()
    local f = fixture({ repeatBait = false, fast = false })
    f:post()
    f:emit("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Linen Cloth")
    f.ready = true
    f.mode:PostOne()
    f:emit("AUCTION_HOUSE_AUCTION_CREATED")
    local latest = f.mode.lastBait
    f:emit("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Linen Cloth.")
    eq(latest.soldAt, nil, "old sale's second channel is still deduplicated")
    f:emit("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Linen Cloth.")
    local _, sold = f.mode:BaitAge()
    eq(sold, true, "new sale stops the new timer")
end)

for _, multi in ipairs({ false, true }) do
    local title = multi and "Multi" or "Single"
    test(title .. " posts the explicit sell price independently of the buy limit", function()
        local f = fixture({ multi = multi, baitPrice = 12345 })
        f.mode.maxPrice = 17
        f.mode:PostOne()
        eq(f:total("post"), 1)
        eq(f.calls[#f.calls].args[4], 12345)
        eq(f.mode.db.postDiagnostics[1].price, 12345)
    end)
    test(title .. " never derives a sell price when its fields are empty", function()
        local f = fixture({ multi = multi, unsetBaitPrice = true })
        f.mode:PostOne()
        eq(f:total("post"), 0)
        assert(f.mode.notice:find("Bait sell price", 1, true))
    end)
    test(title .. " rejects zero and fractional sell prices", function()
        for _, price in ipairs({ 0, -1, 0.5 }) do
            local f = fixture({ multi = multi, baitPrice = price })
            f.mode:PostOne()
            eq(f:total("post"), 0)
        end
    end)
    test(title .. " confirmation keeps the sell price when only the buy limit changes", function()
        local f = fixture({ multi = multi, baitPrice = 12345, confirmPost = true })
        f.mode:PostOne()
        eq(f.mode:PostNeedsConfirmation(), true)
        f.ready = true
        f.mode.maxPrice = 555
        f.mode:PostOne()
        eq(f:total("post_confirm"), 1)
        eq(f.calls[#f.calls].args[4], 12345)
    end)
end

for _, multi in ipairs({ false, true }) do
    test(multi and "Multi omits manual Bait price fields" or "Single gold/silver/copper fields load and save an independent sell price", function()
        local f = fixture({ multi = multi, baitPrice = 12345 })
        local objects, methods = {}, {}
        local function noop() end
        local function object(kind)
            local o = setmetatable({ kind = kind, scripts = {}, value = "" }, {
                __index = function(_, key) return methods[key] or noop end,
            })
            objects[#objects + 1] = o
            return o
        end
        function methods:CreateFontString() return object("FontString") end
        function methods:CreateTexture() return object("Texture") end
        function methods:GetFrameLevel() return 0 end
        function methods:GetAlpha() return 1 end
        function methods:SetScript(name, fn) self.scripts[name] = fn end
        function methods:SetPoint(...) self.point = { ... } end
        function methods:GetText() return self.value end
        function methods:SetText(value)
            self.value = value
            if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
        end
        f.env.CreateFrame = function(kind) return object(kind) end
        f.env.UIParent = object("Frame")
        f.env.AuctionHouseFrame = object("Frame")
        f.env.AuctionHouseFrame.Tabs = { {} }
        f.env.RegisterStateDriver = noop
        f.addon.RegisterModeTabs, f.addon.AttachHelp, f.addon.AttachPurchaseStats = noop, noop, noop
        function f.mode:Limits(price, budget) self.maxPrice, self.budget = price, budget end
        f.mode.panel = nil
        setfenv(assert(loadfile(root .. (multi and "Multi" or "Single") .. "/Panel.lua")), f.env)("BuyWheel", f.addon)
        f.mode:Attach()
        local boxes = {}
        for _, o in ipairs(objects) do
            local point = rawget(o, "point")
            if o.kind == "EditBox" and point and point[1] == "TOPLEFT" and point[3] == -22 then
                boxes[#boxes + 1] = o
            end
        end
        if multi then
            eq(#boxes, 0)
            eq(f.mode.db.baitPrice, 12345, "hiding controls does not erase saved data")
            f.mode.db.watchItems[f.mode.target.id] = { key = f.mode.target.key, enabled = true, maxPrice = 80 }
            f.mode.db.learnedPrices = { [f.mode.target.id] = { normalPrice = 200, samples = 10, live = true } }
            f.mode.favorites = { { itemKey = f.mode.target.key } }
            f.mode.runWatchKeys = { f.mode.target.key }
            f.addon.BusyMessage = noop
            f.mode.panel.RefreshPurchaseStats = noop
            f.mode.panel:RefreshBuyWheelM()
            local favorite
            for _, o in ipairs(objects) do
                if type(rawget(o, "key")) == "table" and rawget(o, "normalPrice") then favorite = o break end
            end
            assert(favorite)
            eq(favorite.counts:GetText(), "0/0", "favorites without purchases start at zero")
            f.mode.purchaseStats = { items = { [f.mode.target.id] = { bought = 123, missed = 45 } } }
            f.mode.panel:RefreshBuyWheelM()
            eq(favorite.counts:GetText(), "123/45", "bought/missed quantities appear beside the normal price")
            local itemStats = f.mode.purchaseStats.items[f.mode.target.id]
            itemStats.estimatedProfit, itemStats.profitUnits = 12345, 123
            f.now = f.now + 5
            f.mode.panel:RefreshBuyWheelM()
            eq(favorite.profit:GetText(), "|cff60eb80+1.23g|r")
            itemStats.estimatedProfit = -123
            f.mode.panel:RefreshBuyWheelM()
            eq(favorite.profit:GetText(), "|cff60eb80+1.23g|r", "profit display retains five-second cadence")
            f.now = f.now + 5
            f.mode.panel:RefreshBuyWheelM()
            eq(favorite.profit:GetText(), "|cffff6464-1.23s|r")
            itemStats.estimatedProfit, itemStats.profitUnits, itemStats.profitUnknownUnits = nil, 0, 123
            f.now = f.now + 5
            f.mode.panel:RefreshBuyWheelM()
            eq(favorite.profit:GetText(), "–", "unknown value is not shown as zero profit")
            f.mode.purchaseStats = nil
            f.mode.panel:RefreshBuyWheelM()
            eq(favorite.counts:GetText(), "0/0", "clearing statistics clears the favorite's display")
            eq(favorite.profit:GetText(), "0c", "Reset clears item profit immediately")
            eq(favorite.normalPrice:GetText(), "2s 0c", "favorite displays normal price, not the 80-copper limit")
            f.mode.db.watchItems[f.mode.target.id].maxPrice = 0
            f.mode.panel:RefreshBuyWheelM()
            eq(favorite.normalPrice:GetText(), "2s 0c", "missing buy limit does not replace the price column")
            f.mode.db.learnedPrices[f.mode.target.id].normalPrice = 4.5
            f.mode.panel:RefreshBuyWheelM()
            eq(favorite.normalPrice:GetText(), "4.50c")
            f.mode.db.learnedPrices[f.mode.target.id] = nil
            f.mode.panel:RefreshBuyWheelM()
            eq(favorite.normalPrice:GetText(), "–")
            local first = f.mode.favorites[1]
            local second = { itemKey = { itemID = 2592 } }
            local third = { itemKey = { itemID = 4306 } }
            f.mode.favorites = { first, second, third }
            f.mode.purchaseStats = { items = {
                [f.mode:WatchID(second.itemKey)] = { bought = 5, missed = 9 },
                [f.mode:WatchID(third.itemKey)] = { bought = 10, missed = 0 },
            } }
            f.mode.panel:RefreshBuyWheelM()
            eq(favorite.key, third.itemKey, "largest bought quantity appears first")
            eq(favorite.counts:GetText(), "10/0", "counters follow the sorted item")
            eq(f.mode.favorites[1], first, "sorting leaves the source favorites unchanged")
            f.mode.purchaseStats.items[f.mode:WatchID(second.itemKey)].bought = 11
            f.mode.panel.scripts.OnUpdate(f.mode.panel, 0.15)
            eq(favorite.key, second.itemKey, "live refresh reorders after new bought quantities")
            f.mode.purchaseStats.items[f.mode:WatchID(third.itemKey)].bought = 11
            f.mode.panel:RefreshBuyWheelM()
            eq(favorite.key, second.itemKey, "ties retain original favorites order")
            f.mode.purchaseStats = nil
            f.mode.panel:RefreshBuyWheelM()
            eq(favorite.key, first.itemKey, "Reset restores original order when all counts are zero")
            eq(favorite.counts:GetText(), "0/0")
            return
        end
        eq(#boxes, 3)
        eq(boxes[1]:GetText(), "1")
        eq(boxes[2]:GetText(), "23")
        eq(boxes[3]:GetText(), "45")
        boxes[1]:SetText("2")
        boxes[2]:SetText("00")
        boxes[3]:SetText("07")
        eq(f.mode.db.baitPrice, 20007)
        eq(f.mode.maxPrice, 100, "editing sell price leaves buy limit intact")
        for _, box in ipairs(boxes) do box:SetText("") end
        eq(f.mode.db.baitPrice, nil, "empty fields do not derive a price")
    end)
end

test("Single and Multi throttle statistics display to five seconds while keeping controls immediate", function()
    for _, multi in ipairs({ false, true }) do
        local f = fixture({ multi = multi, realStats = true })
        local writes = 0
        local methods = {}
        local function noop() end
        local function object()
            return setmetatable({ shown = true, height = 500 }, { __index = function(_, k) return methods[k] or noop end })
        end
        function methods:CreateFontString() return object() end
        function methods:CreateTexture() return object() end
        function methods:GetFrameLevel() return 0 end
        function methods:GetHeight() return self.height end
        function methods:SetHeight(h) self.height = h end
        function methods:SetText() writes = writes + 1 end
        function methods:IsShown() return self.shown end
        function methods:Hide() self.shown = false end
        f.env.CreateFrame = object
        local panel, detail = object(), object()
        f.addon:StartPurchaseStats(f.mode)
        f.addon:AttachPurchaseStats(f.mode, panel, detail, multi and 382 or 332)
        panel:RefreshPurchaseStats()
        local previous = writes
        f.addon:RecordPurchaseStats(f.mode, { quantity = 3, cost = 30, tradeKey = f.mode.target.id }, true)
        eq(f.mode.purchaseStats.items[f.mode.target.id].bought, 3, "accounting remains immediate")
        f.now = f.now + 4.99
        panel:RefreshPurchaseStats()
        eq(writes, previous, "no display recalculation within five seconds")
        f.now = f.now + 0.01
        panel:RefreshPurchaseStats()
        assert(writes > previous, "display refreshes at five seconds")
        previous = writes
        f.addon:ResetPurchaseStats(f.mode)
        panel:RefreshPurchaseStats()
        assert(writes > previous, "Reset refreshes immediately")
        previous = writes
        f.mode.running = false
        panel:RefreshPurchaseStats()
        assert(writes > previous, "STOP refreshes immediately")
        previous = writes
        f.mode.db.leaveBait = true
        panel:RefreshPurchaseStats()
        assert(writes > previous, "settings refresh immediately")
        previous = writes
        panel.height = 200
        panel:RefreshPurchaseStats()
        assert(writes > previous, "compact layout refreshes immediately")
    end
end)

test("Per-item profit matches totals, excludes missed and unpriced purchases and follows bait corrections", function()
    local f = fixture({ multi = true, realStats = true })
    local mode, addon = f.mode, f.addon
    local first, second, unknown = mode.target.id, "2592:0:0:0", "4306:0:0:0"
    addon:RecordPurchaseStats(mode, { tradeKey = first, quantity = 3, cost = 240, normalPrice = 150 }, true)
    addon:RecordPurchaseStats(mode, { tradeKey = first, quantity = 9, cost = 720, normalPrice = 150 }, false, true)
    addon:RecordPurchaseStats(mode, { tradeKey = second, quantity = 2, cost = 160, normalPrice = 50 }, true)
    addon:RecordPurchaseStats(mode, { tradeKey = unknown, quantity = 4, cost = 40 }, true)
    local items = mode.purchaseStats.items
    eq(items[first].estimatedProfit, 210)
    eq(items[second].estimatedProfit, -60)
    eq(items[unknown].estimatedProfit, nil)
    eq(items[unknown].profitUnknownUnits, 4)
    eq(mode.purchaseStats.estimatedProfit, 150)
    local bait = { targetID = first, price = 20 }
    addon:RecordBaitPost(addon.Single, bait)
    eq(items[first].estimatedProfit, 60, "cross-mode bait corrects original buying item")
    addon:RecordBaitSale(bait)
    eq(items[first].estimatedProfit, 80)
    addon:RecordBaitSale(bait)
    eq(items[first].estimatedProfit, 80, "duplicate sale adds no profit")
    local unpricedBait = { targetID = unknown, price = 20 }
    addon:RecordBaitPost(mode, unpricedBait)
    eq(items[unknown].estimatedProfit, -10)
    eq(items[unknown].profitUnknownUnits, 3)
    eq(items[unknown].profitUnits, 1)
    addon:RecordBaitSale(unpricedBait)
    eq(items[unknown].estimatedProfit, 10)
    local total = 0
    for _, item in pairs(items) do total = total + (item.estimatedProfit or 0) end
    eq(total, mode.purchaseStats.estimatedProfit, "item profits sum to mode profit")
    local pending = { targetID = first, price = 30 }
    addon:RecordBaitPost(mode, pending)
    mode:ResetPurchases()
    addon:RecordBaitSale(pending)
    eq(mode.purchaseStats.items, nil, "old sale cannot recreate item profit after Reset")
end)

local function feedbackFixture(multi)
    local f = fixture({ multi = multi, repeatBait = false })
    local methods = {}
    local function noop() end
    local function object()
        return setmetatable({ shown = false, scripts = {} }, { __index = function(_, k)
            if k == "timer" then return nil end
            return methods[k] or noop
        end })
    end
    function methods:CreateTexture() return object() end
    function methods:SetScript(event, fn) self.scripts[event] = fn end
    function methods:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function methods:Show() self.shown = true end
    function methods:Hide()
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function f.mode.panel:GetFrameLevel() return 1 end
    f.env.CreateFrame = object
    f.addon:AttachPurchaseFeedback(f.mode.panel)
    return f, f.mode.panel.purchaseFeedback
end

test("Both modes flash green only on confirmation, replace it with red and expire from the latest result", function()
    for _, multi in ipairs({ false, true }) do
        local f, flash = feedbackFixture(multi)
        f.mode.offers = { { unit = 80, quantity = 3 } }
        f.mode:Buy()
        eq(flash.shown, false, "pending purchase is not a result")
        f:emit("COMMODITY_PRICE_UPDATED", 80, 240)
        eq(flash.shown, false, "a quote is not a successful purchase")
        f:emit("COMMODITY_PURCHASE_SUCCEEDED")
        eq(flash.shown, true)
        eq(flash.edges[1].color[2], 1, "confirmed purchase flashes green")
        local firstTimer = flash.timer
        f:emit("COMMODITY_PURCHASE_SUCCEEDED")
        eq(flash.timer, firstTimer, "duplicate success does not retrigger feedback")
        f:advance(0.2)
        f.mode.offers = { { unit = 80, quantity = 3 } }
        f.ready = true
        f.mode:Buy()
        f:emit("COMMODITY_PRICE_UPDATED", 101, 303)
        eq(flash.edges[1].color[1], 1, "rejected price flashes red")
        eq(firstTimer.cancelled, true)
        f:advance(0.3)
        eq(flash.shown, true, "previous timer cannot hide a newer result")
        f:advance(0.16)
        eq(flash.shown, false)
        eq(flash.timer, nil)
    end
end)

test("Result feedback handles cancellation, hidden panels and closing the effect", function()
    local f, flash = feedbackFixture(true)
    f.mode:Stop()
    eq(flash.shown, false, "STOP without a purchase does not flash")
    f.mode.running = true
    f.mode.offers = { { unit = 80, quantity = 3 } }
    f.mode:Buy()
    f.mode:Stop()
    eq(flash.shown, true)
    eq(flash.edges[1].color[1], 1, "cancelled quote flashes red")
    local timer = flash.timer
    flash:Hide()
    eq(timer.cancelled, true, "hiding the effect clears its timer")
    function f.mode.panel:IsVisible() return false end
    f.addon:FlashPurchaseResult(f.mode, true)
    eq(flash.shown, false, "hidden panel cannot trigger an effect")
    eq(flash.timer, nil)
end)

test("Internal auction errors are hidden only for BuyWheel purchases; diagnostics and red feedback remain", function()
    for _, multi in ipairs({ false, true }) do
        local f, flash = feedbackFixture(multi)
        local shown = {}
        f.env.ERR_AUCTION_DATABASE_ERROR = "Internal auction error."
        f.env.UIErrorsFrame = {
            AddMessage = function(_, message) shown[#shown + 1] = message end,
            AddExternalErrorMessage = function(self, message) self:AddMessage(message) end,
        }
        f.addon:InstallPurchaseErrorFilter()
        local wrapper = f.env.UIErrorsFrame.AddMessage
        f.addon:InstallPurchaseErrorFilter()
        eq(f.env.UIErrorsFrame.AddMessage, wrapper, "filter is installed only once")
        f.env.UIErrorsFrame:AddExternalErrorMessage("Internal auction error.")
        eq(#shown, 1, "searches or unrelated manual actions still show errors")
        f.mode.offers = { { unit = 80, quantity = 3 } }
        f.mode:Buy()
        f.env.UIErrorsFrame:AddExternalErrorMessage("Internal auction error.")
        eq(#shown, 1, "error arriving before purchase outcome is hidden")
        f.env.UIErrorsFrame:AddMessage("Not enough money")
        eq(shown[2], "Not enough money", "other errors remain visible")
        f:emit("UI_ERROR_MESSAGE", 441, "Internal auction error.")
        local found
        for _, e in ipairs(f.mode.db.purchaseDiagnostics[1].events) do
            if e.event == "ui_error_during_purchase" then found = true end
        end
        assert(found, "UI error still reaches diagnostic logs")
        f:emit("COMMODITY_PURCHASE_FAILED")
        eq(flash.shown, true)
        eq(flash.edges[1].color[1], 1, "purchase failure still flashes red")
        f.env.UIErrorsFrame:AddExternalErrorMessage("Internal auction error.")
        eq(#shown, 2, "error arriving after purchase outcome is hidden too")
        f:advance(1.01)
        f.env.UIErrorsFrame:AddMessage("Internal auction error.")
        eq(#shown, 3, "normal message display resumes after the short purchase window")
        f.env.ERR_AUCTION_DATABASE_ERROR = "Interner Auktionsfehler."
        f.mode.purchaseErrorUntil = f.now + 1
        f.env.UIErrorsFrame:AddExternalErrorMessage("Interner Auktionsfehler.")
        eq(#shown, 3, "localized error uses the client constant")
        function f.mode.panel:IsVisible() return false end
        f.env.UIErrorsFrame:AddMessage("Interner Auktionsfehler.")
        eq(#shown, 4, "hidden BuyWheel tab cannot suppress unrelated errors")
    end
end)

local function startPricedBuy(f, quantity, unit, normal)
    local mode = f.mode
    local source = mode == f.addon.Single and f.addon.Multi or mode
    source.db = source.db or {}
    source.db.learnedPrices = source.db.learnedPrices or {}
    source.db.learnedPrices[mode.target.id] = normal and { normalPrice = normal } or nil
    mode.offers = { { unit = unit, quantity = quantity } }
    f.ready = true
    mode:Buy()
end

test("Multi per-item counts use confirmed quantities, separate items and clear with Reset", function()
    local f = fixture({ multi = true, realStats = true })
    local firstID = f.mode.target.id
    startPricedBuy(f, 12, 80)
    eq(f.mode.purchaseStats, nil, "pending quote contributes no items")
    f:emit("COMMODITY_PRICE_UPDATED", 80, 960)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
    eq(f.mode.purchaseStats.items[firstID].bought, 12)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
    eq(f.mode.purchaseStats.items[firstID].bought, 12, "duplicate event adds nothing")
    startPricedBuy(f, 3, 80)
    f:emit("COMMODITY_PRICE_UPDATED", 80, 240)
    f:emit("COMMODITY_PURCHASE_FAILED")
    eq(f.mode.purchaseStats.items[firstID].bought, 12)
    eq(f.mode.purchaseStats.items[firstID].missed, 3)
    f.mode:Stop()
    eq(f.mode.purchaseStats.items[firstID].bought, 12, "STOP preserves per-item totals")
    f.mode.running = true
    f.mode.target = { key = { itemID = 2592 }, id = "2592:0:0:0", name = "Wool Cloth", commodity = true }
    startPricedBuy(f, 5, 80)
    f:emit("COMMODITY_PRICE_UPDATED", 80, 400)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
    eq(f.mode.purchaseStats.items[f.mode.target.id].bought, 5)
    eq(f.mode.purchaseStats.items[f.mode.target.id].missed, 0)
    eq(f.mode.purchaseStats.items[firstID].bought, 12)
    f.mode:ResetPurchases()
    eq(f.mode.purchaseStats.items, nil, "Reset clears every item's counts")
end)

test("Multi profit snapshots each item's normal price and uses actual confirmed cost", function()
    local f = fixture({ multi = true, realStats = true })
    startPricedBuy(f, 3, 80, 150)
    f.mode.db.learnedPrices[f.mode.target.id].normalPrice = 300
    f:emit("COMMODITY_PRICE_UPDATED", 80, 240)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
    eq(f.mode.purchaseStats.estimatedProfit, 210)
    eq(f.mode.purchases[1].normalPrice, 150)
    eq(f.mode.purchases[1].estimatedProfit, 210)
    f.mode.target = { key = { itemID = 2592 }, id = "2592:0:0:0", name = "Wool Cloth", commodity = true }
    startPricedBuy(f, 2, 80, 50)
    f:emit("COMMODITY_PRICE_UPDATED", 60, 120) -- Real cost is lower than the original 160.
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
    eq(f.mode.purchaseStats.estimatedProfit, 190, "sum includes a negative margin on another item")
    eq(f.mode.purchaseStats.profitUnits, 5)
    eq(f.mode.purchases[2].estimatedProfit, -20)
    eq(f.mode.purchaseSpent, 360)
end)

test("Multi profit excludes unknown prices and failed attempts", function()
    local f = fixture({ multi = true, realStats = true })
    startPricedBuy(f, 4, 80)
    f:emit("COMMODITY_PRICE_UPDATED", 80, 320)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
    eq(f.mode.purchaseStats.estimatedProfit, nil)
    eq(f.mode.purchaseStats.profitUnknownUnits, 4)
    startPricedBuy(f, 6, 80, 150)
    f:emit("COMMODITY_PRICE_UPDATED", 80, 480)
    f:emit("COMMODITY_PURCHASE_FAILED")
    eq(f.mode.purchaseStats.estimatedProfit, nil)
    eq(f.mode.purchaseStats.profitUnits, nil)
    eq(f.mode.purchaseStats.profitUnknownUnits, 4)
    eq(f.mode.unitsBought, 4)
end)

test("Multi profit keeps fractional learned prices and negative estimates", function()
    local f = fixture({ multi = true, realStats = true })
    startPricedBuy(f, 3, 5, 4.5)
    f:emit("COMMODITY_PRICE_UPDATED", 5, 15)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
    eq(f.mode.purchaseStats.estimatedProfit, -1.5)
    eq(f.mode.purchaseStats.profitUnits, 3)
end)

test("Multi profit persists across watching sessions and resets with Purchases", function()
    local f = fixture({ multi = true, realStats = true })
    startPricedBuy(f, 3, 80, 150)
    f:emit("COMMODITY_PRICE_UPDATED", 80, 240)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
    f.mode:Stop()
    f.mode.running = true
    f.addon:StartPurchaseStats(f.mode)
    eq(f.mode.purchaseStats.estimatedProfit, 210)
    f.mode:ResetPurchases()
    eq(f.mode.purchaseStats.estimatedProfit, nil)
    eq(f.mode.purchaseStats.profitUnits, nil)
    eq(f.mode.purchaseStats.profitUnknownUnits, nil)
    eq(f.mode.spent, 240, "reset does not restore the run budget")
end)

for _, multi in ipairs({ false, true }) do
local title = multi and "Multi" or "Single"
test(title .. " gold/hour uses all active option groups, pauses on Stop and resets", function()
    local f = fixture({ multi = multi, repeatBait = false, realStats = true })
    f.addon:StartPurchaseStats(f.mode)
    eq(f.addon:PurchaseProfitGoldPerHour(f.mode), nil, "no division by zero")
    startPricedBuy(f, 3, 80, 150)
    f:emit("COMMODITY_PRICE_UPDATED", 80, 240)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED") -- 210 copper estimated profit.
    f.now = f.now + 1800
    f.mode.db.fastQuoteX3 = false
    f.addon:StartPurchaseStats(f.mode)
    f.now = f.now + 1800
    eq(f.addon:TotalPurchaseStatsSeconds(f.mode), 3600)
    eq(f.addon:PurchaseProfitGoldPerHour(f.mode), 0.021)
    f.mode:Stop()
    f.now = f.now + 3600
    eq(f.addon:TotalPurchaseStatsSeconds(f.mode), 3600)
    eq(f.addon:PurchaseProfitGoldPerHour(f.mode), 0.021, "idle hour does not dilute the rate")
    f.mode.running = true
    f.addon:StartPurchaseStats(f.mode)
    f.now = f.now + 3600
    eq(f.addon:PurchaseProfitGoldPerHour(f.mode), 0.0105)
    f.mode:ResetPurchases()
    eq(f.addon:TotalPurchaseStatsSeconds(f.mode), 0)
    eq(f.addon:PurchaseProfitGoldPerHour(f.mode), nil)
    f.now = f.now + 60
    eq(f.addon:PurchaseProfitGoldPerHour(f.mode), 0)
end)

test(title .. " gold/hour stays unknown for unpriced-only purchases", function()
    local f = fixture({ multi = multi, repeatBait = false, realStats = true })
    f.addon:StartPurchaseStats(f.mode)
    startPricedBuy(f, 4, 80)
    f:emit("COMMODITY_PRICE_UPDATED", 80, 320)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
    f.now = f.now + 3600
    eq(f.addon:PurchaseProfitGoldPerHour(f.mode), nil)
end)

end

test("Single profit spans items and uses Multi's learned-price snapshots", function()
    local f = fixture({ repeatBait = false, realStats = true })
    startPricedBuy(f, 3, 80, 150)
    f.addon.Multi.db.learnedPrices[f.mode.target.id].normalPrice = 300
    f:emit("COMMODITY_PRICE_UPDATED", 80, 240)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
    eq(f.mode.purchaseStats.estimatedProfit, 210)
    eq(f.mode.purchases[1].normalPrice, 150)
    eq(f.mode.purchases[1].estimatedProfit, 210)
    f.mode.target = { key = { itemID = 2592 }, id = "2592:0:0:0", name = "Wool Cloth", commodity = true }
    startPricedBuy(f, 2, 80, 50)
    f:emit("COMMODITY_PRICE_UPDATED", 60, 120)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
    eq(f.mode.purchaseStats.estimatedProfit, 190, "all Single items contribute, including losses")
    eq(f.mode.purchaseStats.profitUnits, 5)
    eq(f.mode.purchases[2].estimatedProfit, -20)
    eq(f.mode.purchaseSpent, 360)
end)

test("Single profit excludes failed trades and preserves Multi totals on reset", function()
    local f = fixture({ repeatBait = false, realStats = true })
    startPricedBuy(f, 3, 80, 150)
    f:emit("COMMODITY_PRICE_UPDATED", 80, 240)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
    startPricedBuy(f, 6, 80, 150)
    f:emit("COMMODITY_PRICE_UPDATED", 80, 480)
    f:emit("COMMODITY_PURCHASE_FAILED")
    eq(f.mode.purchaseStats.estimatedProfit, 210)
    eq(f.mode.purchaseStats.profitUnits, 3)
    f.addon:RecordPurchaseStats(f.addon.Multi, { normalPrice = 200, quantity = 2, cost = 100 }, true)
    eq(f.addon.Multi.purchaseStats.estimatedProfit, 300)
    eq(f.mode.purchaseStats.estimatedProfit, 210)
    f.mode:ResetPurchases()
    eq(f.mode.purchaseStats.estimatedProfit, nil)
    eq(f.addon.Multi.purchaseStats.estimatedProfit, 300)
end)

test("Single post-fast-quote purchases also contribute estimated profit", function()
    local f = fixture({ realStats = true })
    f.addon.Multi.db = { learnedPrices = { [f.mode.target.id] = { normalPrice = 150 } } }
    f:post()
    f:readyAfterPost()
    f.mode:Buy()
    f:emit("COMMODITY_PRICE_UPDATED", 80, 800)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
    eq(f.mode.db.purchaseDiagnostics[1].offerSource, "post_fast_quote")
    eq(f.mode.purchaseStats.estimatedProfit, 700)
    eq(f.mode.purchaseStats.profitUnits, 10)
end)

local function confirmBuy(f, quantity, cost, normal)
    startPricedBuy(f, quantity, cost, normal)
    f:emit("COMMODITY_PRICE_UPDATED", cost, quantity * cost)
    f:emit("COMMODITY_PURCHASE_SUCCEEDED")
end

local function confirmBait(f, price)
    f.mode.db.baitPrice = price
    f.ready = true
    f.mode:PostOne()
    f:emit("AUCTION_HOUSE_AUCTION_CREATED")
end

local function sellBait(f)
    f:emit("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Linen Cloth")
end

test("bait replaces normal proceeds without charging purchase cost twice", function()
    local f = fixture({ realStats = true, repeatBait = false, budget = 100000 })
    f.mode.maxPrice = 20000
    f.addon:StartPurchaseStats(f.mode)
    confirmBuy(f, 1, 10000, 20000)
    eq(f.mode.purchaseStats.estimatedProfit, 10000)
    confirmBait(f, 1000)
    eq(f.mode.purchaseStats.estimatedProfit, -10000, "unconfirmed sale proceeds stay excluded")
    eq(f.mode.purchaseStats.baitPending, 1)
    sellBait(f)
    eq(f.mode.purchaseStats.estimatedProfit, -9000, "one gold cost and ten silver proceeds")
    eq(f.mode.purchaseStats.baitPending, 0)
    eq(f.mode.purchaseStats.baitSales, 1)
    eq(f.mode.spent, 10000)
    eq(f.mode.purchaseSpent, 10000)
    f.now = f.now + 3600
    eq(f.addon:PurchaseProfitGoldPerHour(f.mode), -0.9)
    f:emit("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Linen Cloth.")
    f.addon:RecordBaitSale(f.mode.lastBait)
    eq(f.mode.purchaseStats.estimatedProfit, -9000, "duplicate notifications credit nothing extra")
end)

test("bait stock uses FIFO snapshots even if learned prices change", function()
    local f = fixture({ realStats = true, repeatBait = false })
    confirmBuy(f, 1, 80, 150)
    confirmBuy(f, 1, 90, 200)
    eq(f.mode.purchaseStats.estimatedProfit, 180)
    confirmBait(f, 10)
    eq(f.mode.lastBait.profitRecord.normalPrice, 150)
    sellBait(f)
    eq(f.mode.purchaseStats.estimatedProfit, 40)
    confirmBait(f, 10)
    eq(f.mode.lastBait.profitRecord.normalPrice, 200)
    sellBait(f)
    eq(f.mode.purchaseStats.estimatedProfit, -150, "twenty proceeds minus 170 purchase cost")
    eq(f.mode.purchaseStats.profitLots[f.mode.target.id], nil)
end)

test("bait from purchased unpriced stock realizes its known cost and sale price", function()
    local f = fixture({ realStats = true, repeatBait = false })
    confirmBuy(f, 2, 80)
    eq(f.mode.purchaseStats.profitUnknownUnits, 2)
    confirmBait(f, 10)
    eq(f.mode.purchaseStats.estimatedProfit, -80)
    eq(f.mode.purchaseStats.profitUnknownUnits, 1)
    sellBait(f)
    eq(f.mode.purchaseStats.estimatedProfit, -70)
    confirmBait(f, 10)
    sellBait(f)
    eq(f.mode.purchaseStats.estimatedProfit, -140)
    eq(f.mode.purchaseStats.profitUnknownUnits, 0)
    eq(f.mode.purchaseStats.profitUnits, 2)
end)

test("missing bait sale does not leave imaginary normal-price revenue", function()
    local f = fixture({ realStats = true, repeatBait = false })
    confirmBuy(f, 2, 80, 150)
    confirmBait(f, 10)
    confirmBait(f, 10) -- Previous sale notice never arrived; timer is replaced.
    eq(f.mode.purchaseStats.estimatedProfit, -160)
    eq(f.mode.purchaseStats.baitPending, 2)
    sellBait(f)
    eq(f.mode.purchaseStats.estimatedProfit, -150)
    eq(f.mode.purchaseStats.baitPending, 1, "missing proceeds remain explicitly unresolved")
    local _, sold = f.mode:BaitAge()
    eq(sold, true, "new timer still stops normally")
end)

test("failed posting does not consume purchase basis or change profit", function()
    local f = fixture({ realStats = true, repeatBait = false })
    confirmBuy(f, 1, 80, 150)
    f.ready = true
    f.mode:PostOne()
    f:emit("AUCTION_HOUSE_POST_ERROR")
    eq(f.mode.purchaseStats.estimatedProfit, 70)
    eq(f.mode.purchaseStats.baitPending, nil)
    confirmBait(f, 10)
    sellBait(f)
    eq(f.mode.purchaseStats.estimatedProfit, -70)
end)

test("bait sale from before Reset cannot change new profit", function()
    local f = fixture({ realStats = true, repeatBait = false })
    confirmBuy(f, 1, 80, 150)
    confirmBait(f, 10)
    f.mode:ResetPurchases()
    sellBait(f)
    eq(f.mode.purchaseStats.estimatedProfit, nil)
    eq(f.mode.purchaseStats.baitSales, nil)
    eq(f.mode.spent, 80)
end)

test("preexisting bait without tracked purchase does not invent a profit basis", function()
    local f = fixture({ realStats = true, repeatBait = false })
    confirmBait(f, 10)
    eq(f.mode.purchaseStats.baitUnpriced, 1)
    sellBait(f)
    eq(f.mode.purchaseStats.estimatedProfit, nil)
    eq(f.mode.purchaseStats.baitSales, 1)
    eq(f.mode.purchaseStats.baitPending, 0)
    f.addon:StartPurchaseStats(f.mode)
    f.now = f.now + 3600
    eq(f.addon:PurchaseProfitGoldPerHour(f.mode), nil)
end)

test("cross-mode bait corrects the original purchase's profit only", function()
    local f = fixture({ realStats = true, repeatBait = false })
    local other = f.addon.Multi
    other.db = {}
    f.addon:RecordPurchaseStats(other, { tradeKey = f.mode.target.id, quantity = 1, cost = 80, normalPrice = 150 }, true)
    f.addon:StartPurchaseStats(f.mode)
    confirmBait(f, 10)
    eq(other.purchaseStats.estimatedProfit, -80)
    eq(f.mode.purchaseStats.estimatedProfit, nil)
    f.mode:ResetPurchases()
    sellBait(f)
    eq(other.purchaseStats.estimatedProfit, -70)
    eq(f.mode.purchaseStats.estimatedProfit, nil)
end)

local function normalFixture()
    local f = fixture({ multi = true, repeatBait = false, realStats = true })
    f.mode.db.watchItems[f.mode.target.id] = { key = f.mode.target.key, enabled = true, maxPrice = 50 }
    return f
end

local function observe(f, price, quantity, owner, account)
    f.mode:ObserveNormalPrices({ { itemKey = f.mode.target.key, minPrice = price,
        totalQuantity = quantity or 20, containsOwnerItem = owner, containsAccountItem = account } })
end

test("live normal price warms up, uses a median and never changes buy limits", function()
    local f = normalFixture()
    f.mode.db.learnedPrices = { [f.mode.target.id] = { normalPrice = 100, samples = 20, percent = 50, maxPrice = 50 } }
    for i = 1, 9 do f.now = 100 + (i - 1) * 5 observe(f, 200) end
    eq(f.mode.db.learnedPrices[f.mode.target.id].normalPrice, 100)
    f.now = 145
    observe(f, 200)
    local learned = f.mode.db.learnedPrices[f.mode.target.id]
    eq(learned.normalPrice, 200)
    eq(learned.samples, 10)
    eq(learned.live, true)
    eq(learned.percent, 50)
    eq(f.mode.db.watchItems[f.mode.target.id].maxPrice, 50)
    eq(f.addon:LearnedNormalPrice(f.addon.Single, f.mode.target.id), 200, "Single sees refreshed references")
    eq(#f.calls, 0, "sampling sends no API commands")
    eq(#f.timers, 0, "sampling creates no timers")
end)

test("live learning bootstraps an unpriced item and preserves half-copper medians", function()
    local f = normalFixture()
    for i = 1, 10 do f.now = 100 + (i - 1) * 5 observe(f, 100 + i) end
    eq(f.mode.db.learnedPrices[f.mode.target.id].normalPrice, 105.5)
    eq(f.mode.db.learnedPrices[f.mode.target.id].samples, 10)
end)

test("live sampling rejects own stock and single-item bait and limits frequency", function()
    local f = normalFixture()
    observe(f, 100)
    for _ = 1, 5 do observe(f, 200) end
    eq(#f.mode.normalPriceSamples[f.mode.target.id].samples, 1)
    f.now = 105
    observe(f, 1, 1)
    observe(f, 1, 20, true)
    observe(f, 1, 20, false, true)
    observe(f, 0)
    observe(f, -1)
    eq(#f.mode.normalPriceSamples[f.mode.target.id].samples, 1)
    observe(f, 200)
    eq(#f.mode.normalPriceSamples[f.mode.target.id].samples, 2)
    f.now = 110
    f.mode.db.watchItems[f.mode.target.id].enabled = false
    observe(f, 300)
    eq(#f.mode.normalPriceSamples[f.mode.target.id].samples, 2)
end)

test("live learning ignores stopped, benchmark and explicit learning sessions", function()
    local f = normalFixture()
    f.mode.running = false observe(f, 100)
    f.mode.running = true f.mode.benchmark = {} observe(f, 100)
    f.mode.benchmark = nil f.mode.learning = {} observe(f, 100)
    eq(f.mode.normalPriceSamples, nil)
end)

test("live median resists isolated low listings and expires old observations", function()
    local f = normalFixture()
    for i = 1, 10 do f.now = 100 + (i - 1) * 5 observe(f, i == 5 and 1 or 100) end
    eq(f.mode.db.learnedPrices[f.mode.target.id].normalPrice, 100)
    f.now = f.now + 601
    observe(f, 250)
    eq(#f.mode.normalPriceSamples[f.mode.target.id].samples, 1)
    eq(f.mode.db.learnedPrices[f.mode.target.id].normalPrice, 100, "keep last learned value until enough fresh data")
    for _ = 1, 9 do f.now = f.now + 5 observe(f, 250) end
    eq(f.mode.db.learnedPrices[f.mode.target.id].normalPrice, 250)
    for _ = 1, 130 do f.now = f.now + 5 observe(f, 250) end
    eq(#f.mode.normalPriceSamples[f.mode.target.id].samples, 120)
end)

test("ordinary Multi batch replies update references with no extra queries", function()
    local f = normalFixture()
    f.mode.runWatchKeys = { f.mode.target.key }
    f.browseRows = { { itemKey = f.mode.target.key, minPrice = 200, totalQuantity = 20 } }
    for i = 1, 10 do
        f.now, f.ready = 100 + (i - 1) * 5, true
        f.mode:Pump()
        f:emit("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    end
    eq(f:total("batch"), 10)
    eq(#f.calls, 10)
    eq(f.mode.db.learnedPrices[f.mode.target.id].normalPrice, 200)
    eq(f.mode.db.watchItems[f.mode.target.id].maxPrice, 50)
end)

test("explicit learning replaces old live buffers instead of reusing stale samples", function()
    local f = normalFixture()
    for i = 1, 10 do f.now = 100 + (i - 1) * 5 observe(f, 100) end
    f.mode.running = false
    f.mode.learning = { phase = "prices", started = f.now - 60, percent = 50, queries = 12, failures = 0,
        items = { [f.mode.target.id] = { key = f.mode.target.key, samples = { 200,200,200,200,200,200,200,200,200,200 } } } }
    f.mode:FinishLearning(false)
    eq(f.mode.db.learnedPrices[f.mode.target.id].normalPrice, 200)
    eq(f.mode.db.watchItems[f.mode.target.id].maxPrice, 100)
    eq(f.mode.normalPriceSamples[f.mode.target.id], nil)
    f.mode.running = true f.now = f.now + 5
    observe(f, 300)
    eq(f.mode.db.learnedPrices[f.mode.target.id].normalPrice, 200)
end)

test("Bait budget: it saves up while blocked, and Lasts derives the budget from stock and time", function()
    local f = fixture({ multi = true, realStats = true })
    local mode = f.mode
    local key = { itemID = 2589 }
    local id = mode:WatchID(key)
    mode.db.watchItems[id] = { key = key, enabled = true, maxPrice = 100 }
    mode.db.learnedPrices = { [id] = { normalPrice = 100 } }
    mode.runWatchKeys = { key }
    mode.ab = { tokens = 1, tokenAt = f.now, postTimes = {}, justPosted = {}, owner = {} }
    eq(mode:AutoBaitBudget(), nil, "no budget set: unlimited")
    eq(mode:AutoBaitTokens(), nil)
    mode:SetBaitsPerHour(7000)
    eq(mode.db.baitsPerHour, nil, "invalid values are ignored")
    mode:SetBaitsPerHour(6)
    eq(mode:AutoBaitBudget(), 6)
    eq(mode:AutoBaitTokens(), 1)
    f.now = f.now + 1800
    eq(mode:AutoBaitTokens(), 3, "half an hour saves up 3 baits, capped at max(2, ceil(6 / 2)) = 3")
    f.now = f.now + 7200
    eq(mode:AutoBaitTokens(), 3, "the saved-up baits are capped")
    mode.ab.tokens = mode.ab.tokens - 1
    f.now = f.now + 600
    eq(mode:AutoBaitTokens(), 3, "10 minutes bring back the one that was used")
    -- Lasts: 1 item in the bags (fixture), 2 hours -> 0.5 baits per hour; wins over the number.
    mode:SetBaitLastsHours(2)
    eq(mode:AutoBaitStock(), 1)
    local perHour = mode:AutoBaitBudget()
    assert(math.abs(perHour - 0.5) < 1e-6, "budget " .. tostring(perHour))
    f.now = f.now + 3600
    mode.ab.stockAt = nil
    perHour = mode:AutoBaitBudget()
    assert(math.abs(perHour - 1) < 1e-6, "one hour left: the same stock must last half the time, got " .. tostring(perHour))
    mode:SetBaitLastsHours(0)
    eq(mode:AutoBaitBudget(), 6, "0 switches Lasts off again")
end)

test("Bait prices carry the fingerprint in Single and Multi", function()
    for _, multi in ipairs({ false, true }) do
        local f = fixture({ multi = multi, baitPrice = 12345, fingerprint = true })
        f.mode:PostOne()
        eq(f:total("post"), 1)
        local posted = f.calls[#f.calls].args[4]
        eq(posted, f.addon:FingerprintPrice(12345, 2589))
        assert(posted ~= 12345 and f.addon:FingerprintMatches(posted, 2589), "the price is moved to a qualifying one")
        eq(f.mode.db.postDiagnostics[1].price, posted, "the diagnostics keep the price that was posted")
        -- Cheap baits keep their exact price.
        f = fixture({ multi = multi, baitPrice = 150, fingerprint = true })
        f.mode:PostOne()
        eq(f.calls[#f.calls].args[4], 150)
    end
end)

print("PASS " .. count .. " integration scenarios; all addon files compile as Lua 5.1")
