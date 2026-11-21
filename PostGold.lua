-- PostGold: gold waiting in the mailbox and gold on its way from sold auctions (this character).
--
-- Sources, like the mail module of other auction addons, but self-contained:
--   * A sale notice (AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION) is priced from the list of your own
--     auctions as read the last time the auction house showed it; less the 5% cut it is an estimate.
--   * The SOLD rows of that list settle the sales (count, price, the row's own arrival countdown).
--   * At a mailbox every letter's money and the "Sale Pending" invoices (exact, with arrival time)
--     replace the estimates. Taking the money out resets the totals on the next read.
-- A sale's money arrives an hour after the sale. "In the mailbox" is what was there at the last visit,
-- plus sales whose hour has passed since.
local _, Addon = ...

local PostGold = {}
Addon.PostGold = PostGold

local DELAY, CUT, MATCH = 3600, 0.05, 600
local SOLD_NOTE = (Enum and Enum.AuctionHouseNotification and Enum.AuctionHouseNotification.AuctionSold) or 4
local SOLD_STATUS = (Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold) or 1

local function root()
    if type(BuyWheelDB) ~= "table" then return nil end
    local r = BuyWheelDB.postGold
    if type(r) ~= "table" then
        r = {}
        BuyWheelDB.postGold = r
    end
    r.mailbox = r.mailbox or {}   -- { { text, amount } }
    r.pending = r.pending or {}   -- sales on their way, see the line shape in noteSale
    r.prices = r.prices or {}     -- own listings by auction ID: { unit, qty, left, item, itemID, commodity, at }
    return r
end

function PostGold.Net(total)
    total = tonumber(total)
    return total and math.floor(total * (1 - CUT) + 0.5) or nil
end

--- { mailbox, coming, nextIn, estimated, lines = { { item, qty, amount, left } }, seenAt }
function PostGold:Summary()
    local r = root()
    local now = time()
    local s = { mailbox = 0, coming = 0, estimated = false, lines = {} }
    if not r then return s end
    for _, m in ipairs(r.mailbox) do s.mailbox = s.mailbox + (m.amount or 0) end
    for _, p in ipairs(r.pending) do
        local left = (p.eta or 0) - now
        if left <= 0 then
            s.mailbox = s.mailbox + (p.amount or 0)
        else
            s.coming = s.coming + (p.amount or 0)
            s.lines[#s.lines + 1] = { item = p.item or "Auction sale", qty = tonumber(p.qty), amount = p.amount, left = left }
            if not s.nextIn or left < s.nextIn then s.nextIn = left end
        end
        if p.estimate or not p.amount then s.estimated = true end
    end
    table.sort(s.lines, function(a, b) return a.left < b.left end)
    s.seenAt = r.seenAt
    return s
end

local function itemFromText(text)
    if type(text) ~= "string" then return nil end
    local name = text:match("%[(.-)%]")
    if name then return name end
    name = text:match("[Aa]uction of (.-)%.?%s*$")
    if name then
        name = name:gsub("%s*[xX]%s*%d+$", ""):gsub("%s*%(%d+%)$", "")
        if name ~= "" then return name end
    end
end

local function soldQty(text)
    if type(text) ~= "string" then return nil end
    local after = text:match(".*%](.*)$") or text
    local n = tonumber(after:match("[xX]%s*(%d+)") or after:match("%((%d+)%)"))
    if n and n > 0 then return n end
end

local function idFromName(name)
    local get = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if type(name) ~= "string" or name == "" or not get then return nil end
    local ok, id = pcall(get, name)
    return ok and tonumber(id) or nil
end

-- A line of the same item, or nil when one side does not know its item.
local function sameItem(p, itemID, name)
    if p.itemID and itemID then return p.itemID == itemID end
    if p.item and name then return p.item == name end
end

------------------------------------------------------------ Own auctions

local AH = C_AuctionHouse

--- Called when the auction house hands over your list of auctions.
function PostGold:ReadOwned()
    local r = root()
    if not (r and AH and AH.GetNumOwnedAuctions) then return end
    local now = time()
    local seen, sales = {}, {}
    for i = 1, AH.GetNumOwnedAuctions() do
        local a = AH.GetOwnedAuctionInfo(i)
        if a and a.auctionID then
            seen[a.auctionID] = true
            local link = type(a.itemLink) == "string" and a.itemLink or nil
            local name = link and link:match("%[(.-)%]") or nil
            local itemID = (type(a.itemKey) == "table" and tonumber(a.itemKey.itemID)) or (link and tonumber(link:match("|Hitem:(%d+)"))) or nil
            if a.status == SOLD_STATUS then
                local total = tonumber(a.buyoutAmount) or tonumber(a.bidAmount)
                local left = tonumber(a.timeLeftSeconds)
                sales[#sales + 1] = {
                    auctionID = a.auctionID, item = name, itemID = itemID, qty = tonumber(a.quantity) or 1,
                    amount = PostGold.Net(total), exact = left and left > 0 or false,
                    eta = left and left > 0 and (now + math.floor(left)) or nil,
                }
            else
                local info = type(a.itemKey) == "table" and AH.GetItemKeyInfo and AH.GetItemKeyInfo(a.itemKey) or nil
                local commodity = info and info.isCommodity or false
                local qty = tonumber(a.quantity) or 1
                local buyout = tonumber(a.buyoutAmount)
                local unit = buyout and (commodity and buyout or buyout / math.max(1, qty)) or nil
                local before = r.prices[a.auctionID]
                r.prices[a.auctionID] = { unit = unit, qty = qty, left = before and before.left and math.min(before.left, qty) or qty,
                    item = name or (before and before.item), itemID = itemID or (before and before.itemID),
                    commodity = commodity, at = now }
            end
        end
    end
    -- Listings that are gone (sold, cancelled, expired) are forgotten after a while.
    for id, e in pairs(r.prices) do
        if not seen[id] and now - (e.at or 0) > 3 * 3600 then r.prices[id] = nil end
    end

    -- Each SOLD row is one sale: settles the line it matches, else it is added.
    local claimed = {}
    for _, s in ipairs(sales) do
        local pick
        for _, p in ipairs(r.pending) do
            if not claimed[p] and p.ownedID == s.auctionID and (p.qty == s.qty or not p.qty) then pick = p break end
        end
        if not pick then
            local best, bestD
            for _, p in ipairs(r.pending) do
                if not claimed[p] and not p.ownedID and sameItem(p, s.itemID, s.item) ~= false then
                    local d = s.eta and math.abs((p.eta or 0) - s.eta) or math.abs((p.soldAt or now) - now)
                    if d <= (s.exact and MATCH or DELAY) and (not bestD or d < bestD) then best, bestD = p, d end
                end
            end
            pick = best
        end
        if pick then
            claimed[pick] = true
            pick.ownedID, pick.noticed = s.auctionID, true
            pick.item = pick.item or s.item
            pick.itemID = pick.itemID or s.itemID
            pick.qty = s.qty
            if not pick.invoice and s.amount then pick.amount, pick.estimate = s.amount, false end
            if s.exact and s.eta then pick.eta = s.eta end
        else
            local line = { ownedID = s.auctionID, fromList = true, item = s.item, itemID = s.itemID, qty = s.qty,
                amount = s.amount, estimate = s.amount == nil, soldAt = s.eta and (s.eta - DELAY) or now, eta = s.eta or (now + DELAY) }
            -- Already past at the last mailbox read: it was in the mail.
            if line.eta > (tonumber(r.seenAt) or 0) then
                r.pending[#r.pending + 1] = line
                claimed[line] = true
            end
        end
    end
    -- No longer SOLD in the list: the money has been mailed. A notice no row answers is dropped.
    for i = #r.pending, 1, -1 do
        local p = r.pending[i]
        if not claimed[p] and (p.eta or 0) > now and not p.invoice then
            if p.ownedID and not seen[p.ownedID] then
                p.eta = now
            elseif not p.ownedID and p.estimate and now - (tonumber(p.soldAt) or now) >= 60 then
                table.remove(r.pending, i)
            end
        end
    end
end

------------------------------------------------------------ Sale notices

local frame = CreateFrame("Frame")
frame:RegisterEvent("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION")
frame:RegisterEvent("OWNED_AUCTIONS_UPDATED")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_INBOX_UPDATE")
frame:RegisterEvent("MAIL_CLOSED")
frame:RegisterEvent("PLAYER_MONEY")

local atMailbox, houseOpen, queryTimer = false, false, nil

-- Chat line for the sale (Chat report on): item, count, what it brings, when the mail arrives.
-- Deferred a moment so an own bait sale (blue line) is known by then and not told twice.
local function announce(line, itemID, name)
    if not (C_Timer and Addon.AnnounceSale) then return end
    local info = { item = line.item or name, qty = line.qty, amount = line.amount, eta = line.eta, itemID = itemID }
    C_Timer.After(0.2, function() pcall(Addon.AnnounceSale, Addon, info) end)
end

local function noteSale(note, text, auctionID)
    if note ~= SOLD_NOTE then return end
    local r = root()
    if not r then return end
    local cached = auctionID and r.prices[auctionID]
    if not cached then
        -- Not by its auction: a listing of the same item that still has some left.
        local tID = tonumber(type(text) == "string" and text:match("|Hitem:(%d+)") or nil) or idFromName(itemFromText(text))
        local tName = itemFromText(text)
        local best, n = nil, 0
        for _, e in pairs(r.prices) do
            local same = (tID and e.itemID and e.itemID == tID) or (not (tID and e.itemID) and tName and e.item == tName)
            if same and e.unit and (e.left or e.qty or 1) > 0 then
                n = n + 1
                if not best or (e.commodity and not best.commodity) or (e.commodity == best.commodity and (e.at or 0) > (best.at or 0)) then best = e end
            end
        end
        if best and (best.commodity or n == 1) then cached = best end
    end
    local amount, qty
    if cached then
        -- A stack can sell a few at a time, one notice per buyer: each counts what it says, never more
        -- than is left of the listing (without a count the rest of the listing, once).
        local left = cached.left or cached.qty or 1
        local n = math.min(soldQty(text) or left, left)
        cached.left = left - n
        if n <= 0 then return end
        amount, qty = math.floor(cached.unit * n * (1 - CUT) + 0.5), n
    end
    local link = type(text) == "string" and text:match("(|c%x+|Hitem:.-|h.-|h|r)") or nil
    local name = (cached and cached.item) or itemFromText(text)
    local itemID = (link and tonumber(link:match("|Hitem:(%d+)"))) or (cached and cached.itemID) or idFromName(name)
    local now = time()
    -- The auction list may already have shown this sale as SOLD: it counts once, from the list.
    for _, p in ipairs(r.pending) do
        if p.fromList and not p.noticed and math.abs((p.eta or 0) - (now + DELAY)) <= MATCH and sameItem(p, itemID, name) ~= false then
            p.noticed = true
            announce(p, itemID, name)
            return
        end
    end
    local line = { auctionID = auctionID, item = name, itemID = itemID, amount = amount, qty = qty,
        estimate = true, soldAt = now, eta = now + DELAY }
    r.pending[#r.pending + 1] = line
    announce(line, itemID, name)
end

------------------------------------------------------------ Mailbox

local function secondsUntil(h, m)
    if not (h and m and GetGameTime) then return nil end
    local nh, nm = GetGameTime()
    return (((h * 60 + m) - (nh * 60 + nm)) % 1440) * 60
end

function PostGold:ReadInbox()
    local r = root()
    if not (r and GetInboxNumItems) then return end
    local now = time()
    local mailbox, invoices = {}, {}
    for i = 1, GetInboxNumItems() or 0 do
        local _, _, sender, subject, money = GetInboxHeaderInfo(i)
        if money and money > 0 then mailbox[#mailbox + 1] = { text = subject or sender or "Mail", amount = money } end
        if GetInboxInvoiceInfo then
            local ok, kind, itemName, _, bid, _, deposit, consignment, _, etaHour, etaMin, count = pcall(GetInboxInvoiceInfo, i)
            if ok and kind == "seller_temp_invoice" then
                count = tonumber(count)
                invoices[#invoices + 1] = { item = itemName, amount = (bid or 0) + (deposit or 0) - (consignment or 0),
                    qty = (count and count > 0) and count or nil, estimate = false, invoice = true,
                    eta = now + (secondsUntil(etaHour, etaMin) or 0) }
            end
        end
    end
    -- Estimates still on their way are replaced by the exact invoice for the same item; without invoices
    -- the remaining estimates stay.
    local pending, used = {}, {}
    for _, inv in ipairs(invoices) do pending[#pending + 1] = inv end
    for _, p in ipairs(r.pending) do
        if (p.eta or 0) > now then
            local matched = false
            for j, inv in ipairs(invoices) do
                if not used[j] and inv.item and inv.item == p.item and (not (inv.qty and p.qty) or inv.qty == p.qty) then
                    used[j], matched = true, true
                    inv.qty, inv.ownedID, inv.itemID = inv.qty or p.qty, p.ownedID, p.itemID
                    break
                end
            end
            if not matched and #invoices == 0 then pending[#pending + 1] = p end
        end
    end
    r.mailbox, r.pending, r.seenAt = mailbox, pending, now
end

local function queryOwnedSoon(delay)
    if queryTimer or not (C_Timer and AH and AH.QueryOwnedAuctions) then return end
    queryTimer = true
    C_Timer.After(delay, function()
        queryTimer = nil
        if not houseOpen then return end
        local multi = Addon.Multi
        if multi and (multi.running or multi.benchmark or multi.finding or (multi.PurchasePending and multi:PurchasePending())) then return end
        pcall(AH.QueryOwnedAuctions, {})
    end)
end

frame:SetScript("OnEvent", function(_, event, a, b, c)
    local ok, err = pcall(function()
        if event == "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION" then
            noteSale(a, b, c)
        elseif event == "OWNED_AUCTIONS_UPDATED" then
            PostGold:ReadOwned()
        elseif event == "AUCTION_HOUSE_SHOW" then
            houseOpen = true
            queryOwnedSoon(1.5)
        elseif event == "AUCTION_HOUSE_CLOSED" then
            houseOpen = false
        elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
            queryOwnedSoon(3)   -- the new listing gets its price recorded
        elseif event == "MAIL_SHOW" then
            atMailbox = true
            if CheckInbox then CheckInbox() end
        elseif event == "MAIL_CLOSED" then
            if atMailbox then PostGold:ReadInbox() end
            atMailbox = false
        elseif event == "MAIL_INBOX_UPDATE" then
            if atMailbox then PostGold:ReadInbox() end
        elseif event == "PLAYER_MONEY" then
            -- Taking money fires this before the inbox refreshes: read again.
            if atMailbox and C_Timer then C_Timer.After(0.3, function() if atMailbox then pcall(PostGold.ReadInbox, PostGold) end end) end
        end
    end)
    if not ok and Addon.Print then Addon:Print("PostGold: " .. tostring(err)) end
end)

