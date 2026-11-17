-- /tmp/buywheel-lua BuyWheel/Tests/Fingerprint.lua BuyWheel/
-- Also works with a normal Lua 5.1 interpreter.
local root = ... or "Interface/AddOns/BuyWheel/"
local count = 0
local function eq(a, b, message)
    assert(a == b, (message or "unexpected value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end
local function test(name, run) run() count = count + 1 print("PASS " .. name) end

local addon = {}
setfenv(assert(loadfile(root .. "Fingerprint.lua")), setmetatable({}, { __index = _G }))("BuyWheel", addon)

test("Prices from 2s on are moved to the nearest qualifying price, by at most about 2.5% (a little more right at 2s)", function()
    for _, itemID in ipairs({ 2589, 765, 8170, 13422 }) do
        for price = 230, 30000, 37 do
            local result = addon:FingerprintPrice(price, itemID)
            assert(addon:FingerprintMatches(result, itemID), "price " .. price .. " item " .. itemID)
            assert(math.abs(result - price) <= price * 0.026 + 1, ("price %d moved to %d"):format(price, result))
            eq(addon:FingerprintPrice(result, itemID), result, "an already qualifying price stays")
        end
    end
end)

test("Cheap prices have no fingerprint and stay as they are", function()
    for price = 1, 199 do
        eq(addon:FingerprintPrice(price, 2589), price)
        eq(addon:FingerprintMatches(price, 2589), false)
    end
end)

test("A chance match is about 1 in M: 9% in the lowest tier, rarer above", function()
    local function share(from, to, itemID)
        local hits = 0
        for price = from, to do if addon:FingerprintMatches(price, itemID) then hits = hits + 1 end end
        return hits / (to - from + 1)
    end
    local lowest = share(200, 499, 2589)
    assert(lowest > 0.07 and lowest < 0.11, "lowest tier " .. lowest)
    assert(share(500, 1999, 2589) < 0.05, "second tier")
    assert(share(2000, 9999, 2589) < 0.015, "third tier")
    assert(share(10000, 50000, 2589) < 0.003, "fourth tier")
end)

test("A listing is only a probable BuyWheel bait if it also looks like one", function()
    local itemID = 2589
    local price = addon:FingerprintPrice(1000, itemID)
    eq(addon:LooksLikeBait(price, itemID, 1, nil), true, "matches, one unit, normal price unknown")
    eq(addon:LooksLikeBait(price, itemID, 2, 5000), true, "two units are fine")
    eq(addon:LooksLikeBait(price, itemID, 3, 5000), false, "three units are not a bait")
    eq(addon:LooksLikeBait(price, itemID, 1, 1100), false, "the price is not far below the normal price")
    eq(addon:LooksLikeBait(price, itemID, 0, 5000), false, "no competing units")
    eq(addon:LooksLikeBait(price + 1, itemID, 1, 5000), false, "a price that does not qualify")
    eq(addon:LooksLikeBait(150, itemID, 1, 5000), false, "below 2s there is no fingerprint")
end)

print("PASS " .. count .. " Fingerprint scenarios")
