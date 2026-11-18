-- /tmp/buywheel-lua BuyWheel/Tests/LeaveBait.lua BuyWheel/
local root = ... or "Interface/AddOns/BuyWheel/"
local count = 0
local function eq(a, b, message)
    assert(a == b, (message or "unexpected value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end
local function test(name, run) run() count = count + 1 print("PASS " .. name) end

local function fixture()
    local env = setmetatable({}, { __index = _G })
    local addon = { Multi = {} }
    local normals = {}
    function addon:LearnedNormalPrice(_, id) return normals[id] end
    setfenv(assert(loadfile(root .. "Multi/LeaveBait.lua")), env)("BuyWheel", addon)
    addon.Multi.db = {}
    return addon.Multi, normals
end

test("The old checkbox migrates: checked means always (0), unchecked never (100)", function()
    local mode = fixture()
    eq(mode:LeaveBaitThreshold(), 100)
    mode.db.leaveBait = true
    eq(mode:LeaveBaitThreshold(), 0)
    mode.db.leaveBaitFrom = 60
    eq(mode:LeaveBaitThreshold(), 60, "the new field wins over the old checkbox")
    mode.db.leaveBaitFrom = 250
    eq(mode:LeaveBaitThreshold(), 100, "values are clamped to 0..100")
    mode.db.leaveBaitFrom = -5
    eq(mode:LeaveBaitThreshold(), 0)
end)

test("Threshold 0 always leaves a bait, 100 never", function()
    local mode, normals = fixture()
    normals.a = 100
    mode.db.leaveBaitFrom = 0
    eq(mode:LeaveBaitFor("a", 10), true)
    eq(mode:LeaveBaitFor("unknown", nil), true, "even without a price")
    mode.db.leaveBaitFrom = 100
    eq(mode:LeaveBaitFor("a", 99), false)
end)

test("Small margin (lowest price at or above the threshold) leaves a bait, a big margin buys everything", function()
    local mode, normals = fixture()
    normals.a = 200
    mode.db.leaveBaitFrom = 60
    eq(mode:LeaveBaitFor("a", 119), false, "59.5% of normal: big margin")
    eq(mode:LeaveBaitFor("a", 120), true, "exactly 60%")
    eq(mode:LeaveBaitFor("a", 140), true, "70%: small margin")
    mode.db.leaveBaitFrom = 99
    eq(mode:LeaveBaitFor("a", 197), false, "98.5%")
    eq(mode:LeaveBaitFor("a", 198), true, "exactly 99%")
end)

test("Unknown margin buys everything for thresholds from 1 to 99", function()
    local mode, normals = fixture()
    mode.db.leaveBaitFrom = 60
    eq(mode:LeaveBaitFor("none", 50), false, "no learned normal price")
    normals.a = 0
    eq(mode:LeaveBaitFor("a", 50), false, "zero normal price")
    normals.a = 100
    eq(mode:LeaveBaitFor("a", nil), false, "no price")
    eq(mode:LeaveBaitFor(nil, 90), false, "no item")
end)

print("PASS " .. count .. " LeaveBait scenarios")
