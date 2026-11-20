local _, Addon = ...

function Addon:ShouldSuppressPurchaseError(message)
    if type(message) ~= "string" or (issecretvalue and issecretvalue(message)) then return false end
    if message ~= ERR_AUCTION_DATABASE_ERROR and message ~= "Internal auction error."
        and message ~= "Internal auction error" then return false end
    if message ~= ERR_AUCTION_DATABASE_ERROR and message ~= "Internal auction error."
        and message ~= "Internal auction error" then return false end
    if not AuctionHouseFrame or AuctionHouseFrame:GetAlpha() == 0 then return false end
    local now = GetTime()
    for _, mode in ipairs({ self.Single, self.Multi }) do
        if mode.open and mode.panel and mode.panel:IsVisible()
            and ((mode.PurchasePending and mode:PurchasePending())
                or (mode.purchaseErrorUntil and now < mode.purchaseErrorUntil)) then return true end
    end
    return false
end

function Addon:InstallPurchaseErrorFilter()
    local frame = UIErrorsFrame
    if not frame or self.purchaseErrorFilterInstalled then return end
    self.purchaseErrorFilterInstalled = true
    -- Filter display only: the original AH/UI events still reach diagnostics
    -- and purchase completion handlers regardless of their dispatch order.
    for _, method in ipairs({ "AddMessage", "AddExternalErrorMessage" }) do
        local original = frame[method]
        if type(original) == "function" then
            frame[method] = function(target, message, ...)
                if self:ShouldSuppressPurchaseError(message) then return end
                return original(target, message, ...)
            end
        end
    end
end

function Addon:AttachPurchaseFeedback(panel)
    self:InstallPurchaseErrorFilter()
    local flash = CreateFrame("Frame", nil, panel)
    flash:SetAllPoints(panel)
    flash:SetFrameLevel(panel:GetFrameLevel() + 40)
    flash:EnableMouse(false)
    flash.edges = {}
    for _, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local line = flash:CreateTexture(nil, "OVERLAY")
        if edge == "TOP" or edge == "BOTTOM" then
            line:SetPoint(edge .. "LEFT", 0, 0)
            line:SetPoint(edge .. "RIGHT", 0, 0)
            line:SetHeight(4)
        else
            line:SetPoint("TOP" .. edge, 0, 0)
            line:SetPoint("BOTTOM" .. edge, 0, 0)
            line:SetWidth(4)
        end
        flash.edges[#flash.edges + 1] = line
    end
    local popup = CreateFrame("Frame", nil, flash, BackdropTemplateMixin and "BackdropTemplate" or nil)
    popup:SetSize(250, 74)
    popup:SetPoint("BOTTOM", flash, "BOTTOM", 0, 24)
    popup:EnableMouse(false)
    if popup.SetBackdrop then
        popup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        popup:SetBackdropColor(0, 0, 0, 0.88)
        popup:SetBackdropBorderColor(0.15, 1, 0.3, 1)
    end
    popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    popup.title:SetPoint("TOP", 0, -8)
    popup.title:SetWidth(238)
    popup.title:SetWordWrap(false)
    popup.ratio = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    popup.ratio:SetPoint("CENTER", 0, 0)
    popup.profit = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    popup.profit:SetPoint("BOTTOM", 0, 8)
    popup:Hide()
    flash.popup = popup
    flash:SetScript("OnHide", function(self)
        self.popup:Hide()
        if self.timer then self.timer:Cancel() self.timer = nil end
    end)
    flash:Hide()
    panel.purchaseFeedback = flash
end

local function popupMoney(value)
    local amount = math.abs(value)
    if amount >= 10000 then return ("%.2f g"):format(amount / 10000) end
    if amount >= 100 then return ("%.2f s"):format(amount / 100) end
    return ("%.2f c"):format(amount)
end

-- Shown only while the green border is visible (it hides with the flash frame).
function Addon:ShowPurchasePopup(mode, quantity, name, profit, ratio)
    local panel = mode.panel
    local flash = panel and panel.purchaseFeedback
    if not flash or not flash:IsShown() or not flash.popup then return end
    local popup = flash.popup
    popup.title:SetText(("%d× %s"):format(quantity or 0, name or "?"))
    -- Price paid as a share of the learned normal price (80% = 20% below normal).
    popup.ratio:SetText(type(ratio) == "number" and ("%.0f%% of normal price"):format(ratio) or "")
    if type(profit) ~= "number" then
        popup.profit:SetText("Profit: –")
    elseif profit < 0 then
        popup.profit:SetText("|cffff6464Profit: -" .. popupMoney(profit) .. "|r")
    else
        popup.profit:SetText("|cff60eb80Profit: +" .. popupMoney(profit) .. "|r")
    end
    popup:Show()
end

-- Blue border for a bait you posted yourself (same frame and duration as the
-- purchase result flash; the latest result replaces the previous color).
function Addon:FlashBait(mode)
    local panel = mode.panel
    if not panel or not panel:IsVisible() or AuctionHouseFrame:GetAlpha() == 0 then return end
    local flash = panel.purchaseFeedback
    if not flash then return end
    if flash.timer then flash.timer:Cancel() end
    if flash.popup then flash.popup:Hide() end
    for _, line in ipairs(flash.edges) do line:SetColorTexture(0.2, 0.55, 1, 0.95) end
    flash:Show()
    flash.timer = C_Timer.NewTimer(0.45, function()
        flash.timer = nil
        flash:Hide()
    end)
end

function Addon:FlashPurchaseResult(mode, success)
    -- The UI message can be dispatched just after the failure event. A short
    -- grace period handles either order without hiding errors for the whole run.
    mode.purchaseErrorUntil = not success and GetTime() + 1 or nil
    local panel = mode.panel
    if not panel or not panel:IsVisible() or AuctionHouseFrame:GetAlpha() == 0 then return end
    local flash = panel.purchaseFeedback
    if not flash then return end
    if flash.timer then flash.timer:Cancel() end
    if flash.popup then flash.popup:Hide() end
    for _, line in ipairs(flash.edges) do
        if success then line:SetColorTexture(0.15, 1, 0.3, 0.95)
        else line:SetColorTexture(1, 0.15, 0.1, 0.95) end
    end
    flash:Show()
    flash.timer = C_Timer.NewTimer(0.45, function()
        flash.timer = nil
        flash:Hide()
    end)
end

local function plainMoney(value)
    value = math.floor(value + 0.5)
    if value >= 10000 then return ("%dg %02ds %02dc"):format(math.floor(value / 10000), math.floor(value / 100) % 100, value % 100) end
    if value >= 100 then return ("%ds %02dc"):format(math.floor(value / 100), value % 100) end
    return ("%dc"):format(value)
end

-- A posted bait (auto or by hand): one chat line, so you can see what was baited
-- and compare with others, plus the data for the panel's "last bait" line.
function Addon:AnnounceBait(mode, target, price, auto)
    if not target or type(price) ~= "number" then return end
    local normal = target.id and self:LearnedNormalPrice(mode, target.id)
    local percent = normal and (" · %.0f%% of normal"):format(price / normal * 100) or ""
    mode.lastBaitInfo = { name = target.name, price = price, auto = auto == true, at = GetTime() }
    local text
    if mode.db and mode.db.chatReport then
        -- Chat report on: one short blue line, item and percent of normal.
        text = ("|cff66b3ffBait %s%s|r"):format(target.name or "?",
            normal and normal > 0 and (" · %.0f%%"):format(price / normal * 100) or "")
    else
        text = ("|cff66b3ffBuyWheel Bait|r (%s): %s · %s%s"):format(
            auto and "auto" or "manual", target.name or "?", plainMoney(price), percent)
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage(text) end
end

-- Chat report of purchases (Multi checkbox "Chat report", db.chatReport). On: the game's
-- "You won an auction for ..." line is replaced by a short one: quantity, item, % of the
-- normal price and the profit of the trade. Green = bought, red = missed, blue = own bait
-- (see AnnounceBait). Off: the game's message stays exactly as it is.
-- Short, rounded money: 12g, 3.5g, 40s, 7c.
local function reportMoney(value)
    local amount = math.abs(value)
    local text
    if amount >= 100000 then text = ("%dg"):format(math.floor(amount / 10000 + 0.5))
    elseif amount >= 10000 then text = (("%.1f"):format(amount / 10000):gsub("%.0$", "")) .. "g"
    elseif amount >= 100 then text = ("%ds"):format(math.floor(amount / 100 + 0.5))
    else text = ("%dc"):format(math.floor(amount + 0.5)) end
    return (value < 0 and "-" or "+") .. text
end

function Addon:AnnouncePurchase(mode, order, success, missed)
    if not mode.db or not mode.db.chatReport or not order then return end
    if not (success or missed) then return end
    local quantity, cost = order.quantity or 0, order.cost or 0
    if quantity <= 0 then return end
    local name = ("%d× %s"):format(quantity, order.name or "?")
    local text
    if success then
        local normal = order.normalPrice
        if type(normal) == "number" and normal > 0 then
            text = ("|cff40ff60%s · %.0f%% · %s|r"):format(name, cost / (normal * quantity) * 100,
                reportMoney(normal * quantity - cost))
        else
            text = ("|cff40ff60%s|r"):format(name)
        end
    else
        text = ("|cffff5050%s · missed|r"):format(name)
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage(text) end
end

-- Own bait sold (the bait is gone): short blue line with the item and how long it stood.
function Addon:AnnounceBaitSold(mode, bait, now)
    if not mode.db or not mode.db.chatReport or not bait then return end
    local text = "|cff66b3ffBait sold " .. (bait.name or "?")
    if bait.postedAt then
        local total = math.max(0, math.floor(now - bait.postedAt))
        text = text .. " · " .. (total >= 3600
            and ("%d:%02d:%02d"):format(math.floor(total / 3600), math.floor(total / 60) % 60, total % 60)
            or ("%d:%02d"):format(math.floor(total / 60), total % 60))
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage(text .. "|r") end
end

-- Hides the game's own won-auction line, but only while the report is on and only for a
-- purchase made by this addon (just now or still running); manual purchases keep the line.
-- The line does not always come as a system chat event (the auction house notification
-- writes it straight into the chat frame), so besides the event filter the chat frames'
-- AddMessage is wrapped.
local function wonPattern()
    local format = ERR_AUCTION_WON_S or "You won an auction for %s"
    return "^" .. format:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", ".+")
end

local wonPatternText
function Addon:HideWonMessage(message)
    local mode = Addon.Multi
    if type(message) ~= "string" or not mode or not mode.db or not mode.db.chatReport then return false end
    wonPatternText = wonPatternText or wonPattern()
    if message:find(wonPatternText) or message:find("won an auction", 1, true) then
        return mode.PurchaseActiveOrRecent and mode:PurchaseActiveOrRecent() or false
    end
    -- The game's sale line of an own bait: replaced by the blue "Bait sold" line.
    if mode.IsBaitSaleMessage and mode:IsBaitSaleMessage(message) then return true end
    -- The game's "auction created" line for an own bait (yellow): replaced by the blue bait line.
    local lower = message:lower()
    if lower:find("auction", 1, true) and (lower:find("creat", 1, true) or lower:find("start", 1, true)
        or lower:find("post", 1, true) or lower:find("list", 1, true)) then
        return mode.PostActiveOrRecent and mode:PostActiveOrRecent() or false
    end
    return false
end

local wonFilterAdded
function Addon:AddWonFilter()
    if wonFilterAdded then return end
    wonFilterAdded = true
    if ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, message)
            return Addon:HideWonMessage(message)
        end)
    end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.AddMessage then
            local original = frame.AddMessage
            frame.AddMessage = function(self, message, ...)
                if Addon:HideWonMessage(message) then return end
                return original(self, message, ...)
            end
        end
    end
end
Addon:AddWonFilter()
