-- /tmp/buywheel-lua BuyWheel/Tests/Depth.lua BuyWheel/
-- Also works with a normal Lua 5.1 interpreter.
local root = ... or "Interface/AddOns/BuyWheel/"
local count = 0
local function eq(a, b, message)
    assert(a == b, (message or "unexpected value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end
local function test(name, run) run() count = count + 1 print("PASS " .. name) end

local function fixture()
    local f = { now = 1000, server = 1794820000, listings = {} }
    local env = setmetatable({}, { __index = _G })
    local addon = { Multi = {} }
    env.GetTime = function() return f.now end
    env.GetServerTime = function() return f.server end
    env.C_AuctionHouse = {
        GetNumCommoditySearchResults = function(itemID) return #(f.listings[itemID] or {}) end,
        GetCommoditySearchResultInfo = function(itemID, i) return f.listings[itemID][i] end,
        GetItemKeyInfo = function(key) return { itemName = "Item " .. key.itemID, isCommodity = true } end,
    }
    setfenv(assert(loadfile(root .. "Multi/Depth.lua")), env)("BuyWheel", addon)
    local mode = addon.Multi
    mode.db = { watchItems = { ["765:5:0:0"] = { enabled = true } }, learnedPrices = {} }
    function mode:WatchID(key) return ("%d:%d:0:0"):format(key.itemID, key.itemLevel or 0) end
    mode.minMedian = nil
    function mode:LiveMinMedian() return self.minMedian end
    f.addon, f.mode, f.env = addon, mode, env
    return f
end

test("The depth price skips thin bait levels and needs enough supply", function()
    local f = fixture()
    -- 2 units at 34, 121 at 35: the first 20 units are reached at 35.
    eq(f.addon:DepthPriceFromRows({ { price = 34, units = 2 }, { price = 35, units = 121 } }), 35)
    -- 5% of a big supply: 3000 units need 150 units, reached at 38.
    eq(f.addon:DepthPriceFromRows({ { price = 35, units = 100 }, { price = 38, units = 100 },
        { price = 40, units = 2800 } }), 38)
    eq(f.addon:DepthPriceFromRows({ { price = 35, units = 10 }, { price = 36, units = 5 } }), nil, "too thin")
    -- Own units are not part of the supply.
    eq(f.mode:DepthPriceFromTiers({ { price = 35, quantity = 121, owned = 121 }, { price = 40, quantity = 50, owned = 0 } }), 40)
    f.listings[765] = { { unitPrice = 34, quantity = 2 }, { unitPrice = 35, quantity = 121, numOwnerItems = 121 },
        { unitPrice = 36, quantity = 30 } }
    eq(f.mode:DepthPriceFromListings(765), 36, "own units are removed from the rows")
end)

test("Normal price: depth anchors it, the live minimum moves it, never more than 3% above the lowest prices", function()
    local f = fixture()
    local id = "765:5:0:0"
    f.mode.minMedian = 48
    f.mode:RecordDepth(id, 49)
    local learned = f.mode.db.learnedPrices[id]
    eq(learned.normalPrice, 49, "49 is within 3% of the lowest prices (48 x 1.03 = 49.44)")
    eq(learned.source, "depth")
    assert(math.abs(learned.ratio - 49 / 48) < 1e-9)
    -- The market falls: minimum 40 x ratio = 40.83, inside the cap of 41.2.
    local normal = f.mode:NormalFromMeasurements(learned, 40)
    assert(math.abs(normal - 40 * 49 / 48) < 1e-9, tostring(normal))
    eq(learned.drift, nil)
    -- A big move is clamped to 0.7x of the depth price (34.3), then capped at 3% above the minimum (20.6); flagged.
    normal = f.mode:NormalFromMeasurements(learned, 20)
    assert(math.abs(normal - 20.6) < 1e-9, tostring(normal))
    eq(learned.drift, true)
    local _, state = f.mode:NormalInfo(id)
    eq(state, "drift")
    -- Without depth samples the minimum alone decides.
    local plain = { }
    eq(f.mode:NormalFromMeasurements(plain, 33), 33)
    eq(plain.source, "min")
end)

test("The cap keeps the normal price at most 3% above the lowest prices", function()
    local f = fixture()
    assert(math.abs(f.mode:CapNormal(100, 80) - 82.4) < 1e-9)
    eq(f.mode:CapNormal(100, 100), 100)
    eq(f.mode:CapNormal(100, nil), 100, "without a lowest price nothing is capped")
    local id = "765:5:0:0"
    f.mode:RecordDepth(id, 100)
    local learned = f.mode.db.learnedPrices[id]
    assert(math.abs(f.mode:NormalFromMeasurements(learned, 80) - 82.4) < 1e-9, "depth 100 but the lowest prices are at 80")
end)

test("Of several depth measurements the lower quartile counts", function()
    local f = fixture()
    local id = "765:5:0:0"
    for _, price in ipairs({ 80, 50, 70, 60 }) do f.mode:RecordDepth(id, price) end
    local learned = f.mode.db.learnedPrices[id]
    eq(learned.depth, 57.5, "sorted 50 60 70 80: the 25% point lies between 50 and 60")
    eq(f.mode:LowerQuartile({ 7 }), 7)
    eq(f.mode:LowerQuartile({ 10, 20 }), 12.5)
    eq(f.mode:LowerQuartile({}), nil)
end)

test("Depth samples expire and the status shows the age", function()
    local f = fixture()
    local id = "765:5:0:0"
    f.mode:RecordDepth(id, 50)
    local text, state = f.mode:NormalInfo(id)
    eq(state, "ok")
    assert(text:find("Depth"))
    f.server = f.server + 91 * 60
    local learned = f.mode.db.learnedPrices[id]
    eq(f.mode:NormalFromMeasurements(learned, 44), 44, "old depth samples no longer count")
    eq(learned.source, "min")
    f.mode.running = true
    learned.timestamp = f.server - 20 * 60
    local _, oldState = f.mode:NormalInfo(id)
    eq(oldState, "old", "no measurement for 20 minutes while watching")
end)

test("Own buys and baits pause the measurement of that item for 30 seconds", function()
    local f = fixture()
    f.mode:NoteOwnAction("765:5:0:0")
    eq(f.mode:OwnActionRecent("765:5:0:0"), true)
    f.listings[765] = { { unitPrice = 35, quantity = 200 } }
    f.mode:SampleDepthFromListings(765, "765:5:0:0")
    eq(f.mode.db.learnedPrices["765:5:0:0"], nil, "no free sample right after an own action")
    f.now = f.now + 31
    eq(f.mode:OwnActionRecent("765:5:0:0"), false)
    f.mode:SampleDepthFromListings(765, "765:5:0:0")
    eq(f.mode.db.learnedPrices["765:5:0:0"].normalPrice, 35)
    f.listings[765] = { { unitPrice = 50, quantity = 200 } }
    f.mode:SampleDepthFromListings(765, "765:5:0:0")
    eq(#f.mode.db.learnedPrices["765:5:0:0"].depthList, 1, "free samples are limited to one a minute per item")
end)

test("Depth probes run once a minute (fixed) and are scheduled around that", function()
    local f = fixture()
    eq(f.mode:DepthRate(), 1)
    eq(f.mode:DepthDue(), true)
    f.mode:DepthScheduled()
    eq(f.mode:DepthDue(), false)
    f.now = f.now + 40
    eq(f.mode:DepthDue(), false, "the next probe is due after 48 to 72 seconds")
    f.now = f.now + 40
    eq(f.mode:DepthDue(), true)
end)

test("A falling market uses the newest depth sample, not the quartile of old higher ones", function()
    local f = fixture()
    local id = "765:5:0:0"
    for _, price in ipairs({ 100, 90, 80, 50 }) do
        f.mode:RecordDepth(id, price)
        f.server = f.server + 600
    end
    local learned = f.mode.db.learnedPrices[id]
    eq(learned.depth, 50, "the quartile would be 72.5, the newest sample is 50")
    eq(learned.normalPrice, 50)
    eq(learned.falling, true)
    eq(learned.drift, true)
    -- While falling or drifting the buy limit only goes down.
    f.mode.db.learnPercent = 60
    f.mode.db.watchItems[id].maxPrice = 20
    f.mode:ApplyLiveLimit(id, learned, 50)
    eq(f.mode.db.watchItems[id].maxPrice, 20, "30 would raise the limit")
    f.mode:ApplyLiveLimit(id, learned, 20)
    eq(f.mode.db.watchItems[id].maxPrice, 12, "a lower value is applied")
end)

test("Normal noise between depth samples is not a falling market and stays grey", function()
    -- Real series from the 0.9.17 log: dips of 1 to 8% flagged 16 of 48 items yellow.
    for _, series in ipairs({ { 266, 270, 258 }, { 224, 224, 222 }, { 2012, 2021, 1909 }, { 110, 100, 99 } }) do
        local f = fixture()
        local id = "765:5:0:0"
        for _, price in ipairs(series) do
            f.mode:RecordDepth(id, price)
            f.server = f.server + 60
        end
        local learned = f.mode.db.learnedPrices[id]
        eq(learned.falling, nil, "series ending in " .. series[#series])
        eq(learned.drift, nil)
        local _, state = f.mode:NormalInfo(id)
        eq(state, "ok")
    end
    -- A real drop of more than 10% below the quartile still counts.
    local f = fixture()
    for _, price in ipairs({ 100, 100, 100, 85 }) do
        f.mode:RecordDepth("765:5:0:0", price)
        f.server = f.server + 60
    end
    eq(f.mode.db.learnedPrices["765:5:0:0"].falling, true)
end)

test("The long-term median caps a spike at 25% above it", function()
    local f = fixture()
    local plain = {}
    f.mode.db.anchorOn = true
    eq(f.mode:NormalFromMeasurements(plain, 100), 100, "no anchor without notes")
    for _ = 1, 8 do
        f.server = f.server + 1800
        eq(f.mode:NormalFromMeasurements(plain, 100), 100)
    end
    eq(plain.anchor, 100)
    eq(plain.anchored, nil)
    -- A spike to 200 is valued at 125.
    eq(f.mode:NormalFromMeasurements(plain, 200), 125)
    eq(plain.anchored, true)
    -- Inside the cap nothing changes.
    eq(f.mode:NormalFromMeasurements(plain, 110), 110)
    eq(plain.anchored, nil)
    -- Checkbox off: still noted, but nothing is capped.
    f.mode.db.anchorOn = false
    eq(f.mode:NormalFromMeasurements(plain, 200), 200)
    eq(plain.anchored, nil)
    eq(plain.anchor, 100)
end)

print("PASS " .. count .. " Depth scenarios")
