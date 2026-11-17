local _, Addon = ...
local pages = {
    {
        title = "Getting started",
        text = [[|cffffd100BuyWheelS · single item|r
Choose a favorite, set Max Buy Price per item and your total budget, then press GO. Scroll the mouse wheel to buy the displayed matching offer. STOP ends the run.

|cffffd100BuyWheelM · multiple items|r
Click favorite names to edit their individual limits. Check the items you want to watch, set a shared budget, then press Start watching. One query checks their prices together. Matches with the largest estimated profit per item come first: learned normal price minus offer price, or buy limit minus offer price if no normal price is known. Equal margins take turns. Group quantity does not establish quantity at the cheap price. Estimates exclude fees and deposits. Detail queries and purchases are handled one at a time.

|cffffd100Your mouse wheel buys the displayed item|r
Watching alone does not buy anything. The displayed price may change before the server confirms it. Price limits, total budget and available gold are checked for each purchase.

|cffffd100Switching tabs and reading Help|r
Switching between BuyWheelS and BuyWheelM stops the previous mode. Opening Help keeps watching or learning active, but pauses mouse-wheel purchases until you press Back.]],
    },
    {
        title = "Bait and buying options",
        text = [[|cffffd100Bait button · BuyWheelS only|r
Posts one item from your bags at the Bait sell price entered in the gold, silver and copper fields, using the shortest auction duration. BuyWheelS saves its sell price independently of the maximum buy price. Enter a price before posting; empty fields have no automatic fallback. You must have a sellable copy in your bags. If the AH is busy, wait for Bait ready, then scroll or click again. A reservation expires after ten seconds. If confirmation is requested, the next wheel step or Bait click confirms once ready, even with Repeat bait off. Outside GO, scrolling is temporarily assigned only to this pending post and is released on completion, cancellation or timeout. The number beside Bait shows seconds since the latest confirmed listing; it turns green and freezes on the matching sale notification. Each new confirmed bait listing resets the timer and replaces older pending timers for that item, even if a previous sale message was missing. Other own listings of the same item can still make sale matching approximate. Cancellation and expiration do not stop this timer.

|cffffd100Repeat bait · BuyWheelS only|r
Enable Repeat bait below the Bait button and press GO. If no tracked bait is active, the next wheel input posts one item at your configured Bait sell price. While that bait is live, scrolling buys normally. After the matching sale, the next wheel input posts its replacement. If posting needs confirmation or the AH is busy, another wheel input completes it once ready. No post is sent from a timer or sale event: each one needs a fresh input. STOP, changing items, posting errors and running out of sellable items turn Repeat bait off. Existing untracked listings are not checked; other listings of the same item can affect matching. With Buy Bait enabled and Leave Bait off, a confirmed commodity bait post first offers one direct server quote for the selected quantity, without a listing query. Scroll once ready; the displayed maximum is a price ceiling. The quote must pass price, total-budget and uniform-price checks. Failed or unused probes return to detailed listings with the same batch size. The server can reject quotes involving own or missing stock; speed gains depend on market conditions.

|cffffd100Leave Bait|r
Leaves one item at the lowest price. For indivisible stacks, it leaves the cheapest auction. It does not post a new bait item. Detailed listings are needed to determine the quantity to leave.

|cffffd100Buy Bait · x1 (BuyWheelS only)|r
With Leave Bait off, requests a server quote for one commodity item directly from the Browse price. This can skip the detailed listing query. The server quote must pass the price and budget checks.

|cffffd100Buy Bait quantity · experimental (BuyWheelS only)|r
Enter the quantity in the field beside the checkbox (default: 3, whole numbers from 1 to 999999). Requests one quote for exactly that many commodity items. Requires the full quantity to be listed and within budget. With Leave Bait off, unsuitable Browse matches are skipped instead of buying a smaller quantity. This option and x1 replace each other; press STOP before changing the option or quantity. The quantity is saved per tab.]],
    },
    {
        title = "Learning, limits and statistics",
        text = [[|cffffd100Learn normal prices · BuyWheelM|r
Set Max buy % (1–100), then press Start Learning Prices. Reset learned (bottom left, next to Help) deletes everything learned if you want a clean start. All favorites are measured, including unchecked items; the button shows the progress in percent and the run ends by itself. No purchases are made. Keep the auction house and this tab open.

|cffffd100Automatic limits|r
The normal price comes from the market depth (the price where the first 10% of the supply is reached) and from the lowest listing prices. At the end, each limit becomes the selected percentage of its normal price. Example: 2 gold at 60% becomes 1 gold 20 silver. An item needs ten samples; otherwise its limit stays unchanged. In the favorites list the normal price is grey when fine, yellow when you should be careful and red when old.

|cffffd100Live normal prices · BuyWheelM|r
The favorites list shows normal prices; click an item to edit its separate buy limit. While watching, existing complete Multi replies update enabled items using a ten-minute rolling median. At most one sample per item every five seconds; at least ten valid samples are required. Known own/account listings and single-unit groups are skipped. No additional queries are sent. The last reference remains until enough new data exists. Live updates affect normal prices only; buy limits remain separately editable. Persistent foreign bait can still affect the estimate. Explicit learning still applies its chosen buy percentage.

|cffffd100Changing settings and stopping|r
STOP cancels learning without applying new limits. Buy Bait options and multi-mode limits require stopping first. Single-mode price and budget can be edited while watching. Leave Bait can be changed when no purchase is pending.

|cffffd100Purchase rates|r
The bottom-right rates show confirmed items per minute and hour for the current setting, using active GO time across runs. STOP pauses the clock. Waiting for offers, Help and manual bait posting count as active watching time. Purchases Reset clears all measurements for this tab; they are not saved across reloads.

|cffffd100Estimated profit · Single and Multi|r
The rates area also shows estimated profit and gold/hour for confirmed purchases in the current mode since Purchases Reset, across all items and GO runs. Single reuses the normal prices learned in Multi; each mode keeps separate totals. Gold/hour uses the current mode's total active watching time across all settings; STOP pauses this clock. Each purchase contributes learned normal price times quantity minus its actual confirmed cost. Tracked bait adjusts this estimate: its expected resale value is removed when posting is confirmed, and a matching sale credits its configured sale price. Purchase cost is never charged twice. Pending or missing sale notices credit no proceeds. Bait is matched FIFO to purchases across both modes and corrects the original buying mode. Baits without any tracked purchase are excluded and counted as unpriced. The normal price is captured when the purchase starts; later learning does not rewrite earlier estimates. AH fees and deposits are not deducted. Items without a learned price are excluded and counted as unpriced. Negative estimates are retained. The estimate survives GO/STOP, clears with Purchases Reset and is not saved across reloads.

|cffffd100Bought/Missed|r
Counts item quantities, not attempts. The percentage is bought / (bought + missed). Repeated attempts can count the same market stock again. Unresolved purchases and deliberately left bait are excluded. These counters and the purchase history persist across watching runs. Use Reset in Purchases to clear them for the current tab. Restarting WoW or reloading the UI also clears them. The budget and Confirmed spending still restart with each watching run; Reset does not change the current run's budget.]],
    },
}

function Addon:AttachHelp(mode, panel)
    local help = CreateFrame("Frame", nil, panel)
    help:SetAllPoints(panel)
    help:SetFrameLevel(panel:GetFrameLevel() + 30)
    help:EnableMouse(true)
    local background = help:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(help)
    background:SetColorTexture(0.045, 0.04, 0.03, 1)
    local title = help:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -6)
    local scroll = CreateFrame("ScrollFrame", nil, help, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -40)
    scroll:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", -36, -330)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 1)
    scroll:SetScrollChild(content)
    local body = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", 0, 0)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetWordWrap(true)
    body:SetSpacing(2)
    local page = 1
    local previous = CreateFrame("Button", nil, help, "UIPanelButtonTemplate")
    previous:SetPoint("TOPLEFT", 9, -343)
    previous:SetSize(70, 24)
    previous:SetText("Previous")
    local nextPage = CreateFrame("Button", nil, help, "UIPanelButtonTemplate")
    nextPage:SetPoint("TOPLEFT", 85, -343)
    nextPage:SetSize(70, 24)
    nextPage:SetText("Next")
    local position = help:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    position:SetPoint("TOPLEFT", 168, -351)
    local toggle = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    toggle:SetPoint("TOPLEFT", 224, -343)
    toggle:SetSize(48, 24)
    toggle:SetFrameLevel(help:GetFrameLevel() + 5)
    toggle:SetText("Help")
    local function refresh()
        local width = math.max(1, panel:GetWidth() - 52)
        content:SetWidth(width)
        body:SetWidth(width)
        title:SetText("BuyWheel Help · " .. pages[page].title)
        body:SetText(pages[page].text)
        content:SetHeight(math.max(1, body:GetStringHeight()))
        scroll:SetVerticalScroll(0)
        position:SetText(("%d / %d"):format(page, #pages))
        previous:SetEnabled(page > 1)
        nextPage:SetEnabled(page < #pages)
    end
    previous:SetScript("OnClick", function() page = page - 1 refresh() end)
    nextPage:SetScript("OnClick", function() page = page + 1 refresh() end)
    toggle:SetScript("OnClick", function()
        GameTooltip:Hide()
        help:SetShown(not help:IsShown())
        toggle:SetText(help:IsShown() and "Back" or "Help")
        if mode.running or mode:PostWaiting() or mode:PostNeedsConfirmation() then
            mode:BindWheel(not help:IsShown())
        end
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local offset = self:GetVerticalScroll() - delta * 32
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), offset)))
    end)
    help:SetScript("OnShow", refresh)
    refresh()
    help:Hide()
    panel.helpPage = help
end
