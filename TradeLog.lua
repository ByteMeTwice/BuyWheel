local _, Addon = ...

-- Permanent trade log.
--
-- Every confirmed purchase, every posted listing and every sale is appended to
-- BuyWheelDB.tradeLog (saved variables, so it survives reloads and logouts and is
-- never reset by the purchase statistics Reset). Entries are plain tables:
--
--   kind "buy"       a confirmed purchase (BuyWheelS / BuyWheelM)
--   kind "post"      a listing posted by a bait or SellWheel
--   kind "sale"      "A buyer has been found for your auction of X" (chat)
--   kind "invoice"   the sale or purchase invoice mail (real money, deposit, fee)
--
-- Purchases carry the learned price state at the time of the buy (normal price, buy
-- limit, source, drift/falling/anchored flags), so a bad buy can be explained later.
-- Use /bwlog for a summary, /bwlog last [n] for the newest lines.
local logLimit, logTrim = 20000, 500

local function serverNow() return GetServerTime and GetServerTime() or time() end

function Addon:TradeLogList()
    self:GetModeDB("multi") -- makes sure BuyWheelDB exists in its current layout
    local list = BuyWheelDB.tradeLog
    if type(list) ~= "table" then
        list = {}
        BuyWheelDB.tradeLog = list
    end
    return list
end

function Addon:TradeLog(kind, entry)
    local ok, err = pcall(function()
        entry.kind, entry.t = kind, serverNow()
        local list = self:TradeLogList()
        list[#list + 1] = entry
        if #list > logLimit + logTrim then
            -- Lua 5.1 (no table.move): shift down in one pass, then drop the tail.
            local count = #list
            for i = 1, count - logTrim do list[i] = list[i + logTrim] end
            for i = count - logTrim + 1, count do list[i] = nil end
        end
    end)
    return ok, err
end

local function itemName(itemID)
    if not itemID or not GetItemInfo then return end
    local name = GetItemInfo(itemID)
    return name
end

-- A confirmed purchase. `order` is the purchase order of BuyWheelS/M.
function Addon:LogPurchase(mode, order)
    local quantity = order.quantity or 0
    if quantity <= 0 then return end
    local source = mode == self.Single and self.Multi or mode
    local prices = source and source.db and source.db.learnedPrices
    local learned = prices and prices[order.tradeKey]
    local watched = source and source.db and source.db.watchItems and source.db.watchItems[order.tradeKey]
    local cost = order.cost or 0
    local entry = {
        mode = mode.short, item = order.name, id = order.itemID, qty = quantity, cost = cost,
        unit = cost / quantity, normal = order.normalPrice,
        limit = order.log and order.log.maxUnit or watched and watched.maxPrice,
        key = order.tradeKey, leave = order.leaveBait and true or nil,
    }
    if entry.normal and entry.normal > 0 then entry.pct = entry.unit / entry.normal * 100 end
    if learned then
        entry.src, entry.depth, entry.anchor = learned.source, learned.depth, learned.anchor
        entry.drift, entry.falling, entry.anchored = learned.drift, learned.falling, learned.anchored
        entry.samples, entry.ratio = learned.samples, learned.ratio
    end
    self:TradeLog("buy", entry)
end

-- A posted listing. quantity is 1 for a bait.
function Addon:LogPost(itemID, unitPrice, duration, quantity, bait)
    self:TradeLog("post", { id = itemID, item = itemName(itemID), unit = unitPrice, qty = quantity or 1,
        duration = duration, bait = bait or nil })
end

-- Sale messages: "A buyer has been found for your auction of %s." (localized global).
local function salePattern()
    local template = _G.ERR_AUCTION_SOLD_S
    if type(template) ~= "string" then return end
    return "^" .. template:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$"
end

local function onSystemMessage(message)
    if type(message) ~= "string" then return end
    local pattern = salePattern()
    local name = pattern and message:match(pattern)
    if not name then return end
    local itemID = tonumber(name:match("|Hitem:(%d+)"))
    Addon:TradeLog("sale", { item = name:match("%[(.-)%]") or name, id = itemID })
end

-- Invoice mails carry the real numbers: price paid by the buyer, deposit and AH cut.
local function seenTable()
    local db = Addon:GetModeDB("multi") and BuyWheelDB
    if type(db.tradeLogSeen) ~= "table" then db.tradeLogSeen = {} end
    return db.tradeLogSeen
end

local function onInbox()
    if not (GetInboxNumItems and GetInboxInvoiceInfo and GetInboxHeaderInfo) then return end
    local now = serverNow()
    local seen = seenTable()
    for key, expires in pairs(seen) do
        if expires < now - 31 * 86400 then seen[key] = nil end
    end
    for i = 1, (GetInboxNumItems()) do
        local invoiceType, name, buyer, bid, buyout, deposit, consignment, _, _, _, count = GetInboxInvoiceInfo(i)
        if invoiceType then
            local _, _, _, subject, _, _, daysLeft = GetInboxHeaderInfo(i)
            -- The mail's expiry (rounded to the hour) is stable while it sits in the inbox.
            local bucket = math.floor((now + (daysLeft or 0) * 86400) / 3600)
            local base = ("%s|%s|%s|%s|%s"):format(invoiceType, tostring(name), tostring(count), tostring(bid), tostring(buyer))
            local known = seen[base .. "|" .. bucket] or seen[base .. "|" .. (bucket - 1)] or seen[base .. "|" .. (bucket + 1)]
            if not known then
                seen[base .. "|" .. bucket] = now
                Addon:TradeLog("invoice", { type = invoiceType, item = name, qty = count, price = bid, buyout = buyout,
                    deposit = deposit, fee = consignment, other = buyer, subject = subject })
            end
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_SYSTEM")
events:RegisterEvent("MAIL_INBOX_UPDATE")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_SYSTEM" then pcall(onSystemMessage, ...)
    else pcall(onInbox) end
end)

-- /bwlog [hours]  summary per item of the last N hours (default 24)
-- /bwlog last [n] the newest n log lines (default 15)
local function money(copper)
    copper = math.floor((copper or 0) + 0.5)
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    return ("%s%dg %02ds %02dc"):format(sign, math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

local function say(text)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffBuyWheel log:|r " .. text) end
end

function Addon:TradeLogSummary(hours)
    local list = self:TradeLogList()
    local since = serverNow() - hours * 3600
    local items = {}
    local function row(name)
        name = name or "?"
        if not items[name] then items[name] = { bought = 0, cost = 0, posted = 0, postValue = 0, sales = 0, revenue = 0 } end
        return items[name]
    end
    for _, entry in ipairs(list) do
        if entry.t >= since then
            if entry.kind == "buy" then
                local r = row(entry.item)
                r.bought, r.cost = r.bought + entry.qty, r.cost + entry.cost
            elseif entry.kind == "post" then
                local r = row(entry.item)
                r.posted, r.postValue = r.posted + entry.qty, r.postValue + (entry.unit or 0) * entry.qty
            elseif entry.kind == "sale" then
                row(entry.item).sales = row(entry.item).sales + 1
            elseif entry.kind == "invoice" and entry.type == "seller" then
                local r = row(entry.item)
                r.revenue = r.revenue + (entry.price or 0) + (entry.deposit or 0) - (entry.fee or 0)
            end
        end
    end
    local names = {}
    for name in pairs(items) do names[#names + 1] = name end
    table.sort(names, function(a, b) return items[a].cost > items[b].cost end)
    say(("last %d h, %d entries in the log"):format(hours, #list))
    for _, name in ipairs(names) do
        local r = items[name]
        say(("%s: bought %d for %s (avg %s) · posted %d (avg %s) · sales %d, invoice net %s"):format(name, r.bought,
            money(r.cost), r.bought > 0 and money(r.cost / r.bought) or "-", r.posted,
            r.posted > 0 and money(r.postValue / r.posted) or "-", r.sales, money(r.revenue)))
    end
    if #names == 0 then say("nothing logged in this period") end
end

function Addon:TradeLogLast(count)
    local list = self:TradeLogList()
    for i = math.max(1, #list - count + 1), #list do
        local e = list[i]
        local when = date and date("%d.%m. %H:%M:%S", e.t) or tostring(e.t)
        if e.kind == "buy" then
            say(("%s BUY %dx %s at %s (normal %s, limit %s, %s%s%s)"):format(when, e.qty, tostring(e.item), money(e.unit),
                e.normal and money(e.normal) or "?", e.limit and money(e.limit) or "?", tostring(e.src or "?"),
                e.drift and ", drift" or "", e.anchored and ", capped" or ""))
        elseif e.kind == "post" then
            say(("%s POST %dx %s at %s"):format(when, e.qty or 1, tostring(e.item or e.id), money(e.unit)))
        elseif e.kind == "invoice" then
            say(("%s INVOICE %s %dx %s for %s (deposit %s, fee %s)"):format(when, tostring(e.type), e.qty or 1,
                tostring(e.item), money(e.price), money(e.deposit), money(e.fee)))
        else
            say(("%s %s %s"):format(when, tostring(e.kind):upper(), tostring(e.item or "")))
        end
    end
end

-- Evaluation page (tools/BuyWheelLog.html). WoW cannot start a browser or open a file, so a
-- small window names the two files and the launcher to double-click; the paths can be copied.
local reportWindow
function Addon:ShowReportWindow()
    if not reportWindow then
        local frame = CreateFrame("Frame", "BuyWheelReportWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        frame:SetSize(560, 236)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        if frame.SetBackdrop then
            frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 } })
        end
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -18)
        title:SetText("BuyWheel evaluation page")
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -6, -6)
        local intro = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        intro:SetPoint("TOPLEFT", 22, -46)
        intro:SetWidth(516)
        intro:SetJustifyH("LEFT")
        intro:SetText("1. Type /reload so WoW writes the current data.".."\n".."2. In your WoW folder, double-click the launcher below. It opens the page in your browser and shows BuyWheel.lua in Explorer; drag that file onto the page (or use Update after the first time).")
        local function field(y, caption, text)
            local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOPLEFT", 22, y)
            label:SetText(caption)
            local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
            box:SetPoint("TOPLEFT", 28, y - 14)
            box:SetSize(506, 22)
            box:SetAutoFocus(false)
            box:SetMaxLetters(400)
            box:SetText(text)
            box.fixed = text
            box:SetCursorPosition(0)
            box:SetScript("OnEditFocusGained", box.HighlightText)
            box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(self.fixed) self:HighlightText() end end)
            box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            return box
        end
        field(-104, "Launcher (double-click):", "Interface\\AddOns\\BuyWheel\\tools\\OpenBuyWheelLog.bat")
        field(-142, "Evaluation page:", "Interface\\AddOns\\BuyWheel\\tools\\BuyWheelLog.html")
        local realm = GetRealmName and GetRealmName() or "<Realm>"
        local name = UnitName and UnitName("player") or "<Character>"
        field(-180, "Data file (this character):", ("WTF\\Account\\<Account>\\%s\\%s\\SavedVariables\\BuyWheel.lua"):format(realm, name))
        tinsert(UISpecialFrames, "BuyWheelReportWindow")
        reportWindow = frame
    end
    reportWindow:Show()
end

SLASH_BWLOG1 = "/bwlog"
SlashCmdList = SlashCmdList or {}
SlashCmdList["BWLOG"] = function(arg)
    arg = arg or ""
    if arg:match("^%s*html%s*$") or arg:match("^%s*report%s*$") then Addon:ShowReportWindow() return end
    local count = arg:match("^last%s*(%d*)$")
    if count then Addon:TradeLogLast(tonumber(count) or 15) return end
    Addon:TradeLogSummary(tonumber(arg) or 24)
end
