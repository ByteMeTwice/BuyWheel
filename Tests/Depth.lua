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
    -- 10% of a big supply: 3000 units need 300 units, reached at 40.
    eq(f.addon:DepthPriceFromRows({ { price = 35, units = 100 }, { price = 38, units = 100 },
        { price = 40, units = 2800 } }), 40)
    eq(f.addon:DepthPriceFromRows({ { price = 35, units = 10 }, { price = 36, units = 5 } }), nil, "too thin")
    -- Own units are not part of the supply.
    eq(f.mode:DepthPriceFromTiers({ { price = 35, quantity = 121, owned = 121 }, { price = 40, quantity = 50, owned = 0 } }), 40)
    f.listings[765] = { { unitPrice = 34, quantity = 2 }, { unitPrice = 35, quantity = 121, numOwnerItems = 121 },
        { unitPrice = 36, quantity = 30 } }
    eq(f.mode:DepthPriceFromListings(765), 36, "own units are removed from the rows")
end)

test("Normal price: depth anchors it, the live minimum moves it within bounds", function()
    local f = fixture()
    local id = "765:5:0:0"
    f.mode.minMedian = 40
    f.mode:RecordDepth(id, 50)
    local learned = f.mode.db.learnedPrices[id]
    eq(learned.normalPrice, 50)
    eq(learned.source, "depth")
    assert(math.abs(learned.ratio - 1.25) < 1e-9)
    -- The market falls: minimum 32 x ratio 1.25 = 40 (within 0.7x-1.4x of the depth 50).
    local normal = f.mode:NormalFromMeasurements(learned, 32)
    assert(math.abs(normal - 40) < 1e-9)
    eq(learned.drift, nil)
    -- A big move is clamped to 0.7x of the depth price and flagged.
    normal = f.mode:NormalFromMeasurements(learned, 20)
    assert(math.abs(normal - 35) < 1e-9)
    eq(learned.drift, true)
    local _, state = f.mode:NormalInfo(id)
    eq(state, "drift")
    -- Without depth samples the minimum alone decides.
    local plain = { }
    eq(f.mode:NormalFromMeasurements(plain, 33), 33)
    eq(plain.source, "min")
end)

test("Depth samples expire and the status shows the age", function()
    local f = fixture()
    local id = "765:5:0:0"
    f.mode:RecordDepth(id, 50)
    local text, state = f.mode:NormalInfo(id)
    eq(state, "ok")
    assert(text:find("Tiefe"))
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

test("The depth rate defaults to 1 per minute, accepts 0-6 and schedules probes", function()
    local f = fixture()
    eq(f.mode:DepthRate(), 1)
    f.mode:SetDepthRate(7)
    eq(f.mode:DepthRate(), 1)
    f.mode:SetDepthRate(0)
    eq(f.mode:DepthDue(), false, "0 switches the probes off")
    f.mode:SetDepthRate(3)
    eq(f.mode:DepthRate(), 3)
    eq(f.mode:DepthDue(), true)
    f.mode:DepthScheduled()
    eq(f.mode:DepthDue(), false)
    f.now = f.now + 30
    eq(f.mode:DepthDue(), true, "at 3 per minute the next probe is due within about 24 seconds")
end)

print("PASS " .. count .. " Depth scenarios")
