local _, Addon = ...

-- Bait fingerprint.
--
-- A bait is not posted at exactly the price the percentage gives, but at the nearest
-- price that satisfies a fixed rule. Every BuyWheel user uses the same rule, so
-- BuyWheel can recognize the baits of other BuyWheel users in the price list (they
-- get a color of their own). The rule needs no setting and no communication.
--
-- A price qualifies when (price + itemID) is divisible by M. M depends on the price
-- so that the price moves by about 2.5% at most:
--
--     from 2s      M = 11   (about 1 of 11 ordinary prices matches by chance)
--     from 5s      M = 23
--     from 20s     M = 97
--     from 1g      M = 499
--
-- Below 2s there is no fingerprint (the steps would be too large).
--
-- A listing is only reported as a probable BuyWheel bait when it also looks like a
-- bait: at most two units at that price and, if the normal price is known, a price
-- of at most 80% of it. That makes a chance match rare.
local TIERS = { { 200, 11 }, { 500, 23 }, { 2000, 97 }, { 10000, 499 } }
local MAX_BAIT_UNITS = 2
local MAX_NORMAL_RATIO = 0.8

local function modulus(price)
    local m
    for _, tier in ipairs(TIERS) do
        if price >= tier[1] then m = tier[2] end
    end
    return m
end

function Addon:FingerprintMatches(price, itemID)
    local m = modulus(price)
    if not m or not itemID then return false end
    return (price + itemID) % m == 0
end

-- The nearest qualifying price (the lower one on a tie). Prices below the first tier
-- are returned unchanged.
function Addon:FingerprintPrice(price, itemID)
    if type(price) ~= "number" or not itemID or price < TIERS[1][1] then return price end
    price = math.floor(price)
    for distance = 0, 600 do
        local lower = price - distance
        if lower >= TIERS[1][1] and self:FingerprintMatches(lower, itemID) then return lower end
        if distance > 0 and self:FingerprintMatches(price + distance, itemID) then return price + distance end
    end
    return price
end

-- True when a price level looks like a bait of another BuyWheel user: units is the
-- number of competing units at that price, normal the learned normal price or nil.
function Addon:LooksLikeBait(price, itemID, units, normal)
    if not units or units < 1 or units > MAX_BAIT_UNITS then return false end
    if not self:FingerprintMatches(price, itemID) then return false end
    if type(normal) == "number" and normal > 0 and price > normal * MAX_NORMAL_RATIO then return false end
    return true
end
