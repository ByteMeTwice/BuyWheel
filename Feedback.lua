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
    local text = ("|cff66b3ffBuyWheel Bait|r (%s): %s · %s%s"):format(
        auto and "auto" or "manual", target.name or "?", plainMoney(price), percent)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage(text) end
end
