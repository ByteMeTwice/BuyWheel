local _, Addon = ...
local BW = Addon.Multi

-- Leave Bait threshold: "leave one unit at the lowest price when that price is at or above
-- N % of the learned normal price" (small margin). 0 = always, 100 = never. The old checkbox
-- (db.leaveBait) migrates to 0 (checked) or 100 (unchecked).
function BW:LeaveBaitThreshold()
    local value = tonumber(self.db.leaveBaitFrom)
    if value then return math.max(0, math.min(100, math.floor(value))) end
    return self.db.leaveBait and 0 or 100
end

-- True when a purchase at this lowest price should leave a bait. Without a learned normal
-- price the margin is unknown: a threshold between 1 and 99 then buys everything.
function BW:LeaveBaitFor(id, price)
    local threshold = self:LeaveBaitThreshold()
    if threshold <= 0 then return true end
    if threshold >= 100 then return false end
    local normal = id and Addon:LearnedNormalPrice(self, id)
    if not normal or normal <= 0 or type(price) ~= "number" or price <= 0 then return false end
    return price * 100 >= normal * threshold
end
