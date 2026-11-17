local _, Addon = ...
local SW = Addon.Sell
local ROWS = 11

local wheel = CreateFrame("Button", "SellWheelMouseButton", UIParent)
wheel:RegisterForClicks("AnyDown")
wheel:SetScript("OnClick", function() SW:WheelStep() end)

local bindings = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
bindings:SetAttribute("_onstate-combat", [[ if newstate == "combat" then self:ClearBindings() end ]])
RegisterStateDriver(bindings, "combat", "[combat] combat; peace")

local muted = {}
local function muteScroll(frame)
    if frame and frame.IsMouseWheelEnabled and frame:IsMouseWheelEnabled() then
        frame:EnableMouseWheel(false)
        muted[#muted + 1] = frame
    end
end

-- The mouse wheel posts the next stage only while the wheel option is on and the
-- SellWheel panel is open; chat scrolling is paused meanwhile, as in the buy modes.
function SW:BindWheel(enable)
    enable = enable and true or false
    if self.wheelBound == enable then return end
    if InCombatLockdown() then return end
    self.wheelBound = enable
    for _, frame in ipairs(muted) do frame:EnableMouseWheel(true) end
    wipe(muted)
    ClearOverrideBindings(bindings)
    if not enable then return end
    SetOverrideBindingClick(bindings, true, "MOUSEWHEELUP", wheel:GetName())
    SetOverrideBindingClick(bindings, true, "MOUSEWHEELDOWN", wheel:GetName())
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local chat = _G["ChatFrame" .. i]
        muteScroll(chat)
        if chat then muteScroll(chat.ScrollBar) end
    end
end

local function money(value)
    if value >= 10000 then return ("%dg %02ds %02dc"):format(math.floor(value / 10000), math.floor(value / 100) % 100, value % 100) end
    if value >= 100 then return ("%ds %02dc"):format(math.floor(value / 100), value % 100) end
    return ("%dc"):format(value)
end

local function label(parent, value, font, x, y, width)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", x, y)
    text:SetWidth(width or 240)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetText(value)
    return text
end

local function button(parent, value, width, x, y, fn)
    local frame = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetSize(width, 24)
    frame:SetText(value)
    frame:SetScript("OnClick", fn)
    return frame
end

function SW:Attach()
    local parent = AuctionHouseFrame
    if self.panel or not parent or not parent.Tabs or #parent.Tabs == 0 then return end
    local panel = CreateFrame("Frame", nil, parent)
    panel:Hide()
    panel:SetPoint("TOPLEFT", 18, -68)
    panel:SetPoint("BOTTOMRIGHT", -18, 31)
    panel:SetFrameLevel(parent:GetFrameLevel() + 8)
    self.panel = panel
    self.inventoryPage, self.chartPage = 1, 1
    label(panel, "SellWheel · bag inventory", "GameFontNormalLarge", 9, 0, 280)
    label(panel, "Commodities · unlocked / total", nil, 9, -23, 280)
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 285, -4)
    divider:SetPoint("BOTTOMLEFT", 285, 11)
    divider:SetWidth(1)
    divider:SetColorTexture(0.65, 0.56, 0.38, 0.31)
    local rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, panel)
        row:SetPoint("TOPLEFT", 8, -43 - (i - 1) * 26)
        row:SetSize(258, 24)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.name = label(row, "", "GameFontHighlightSmall", 3, -3, 172)
        row.quantity = label(row, "", nil, 178, -3, 78)
        row.quantity:SetJustifyH("RIGHT")
        row.selected = row:CreateTexture(nil, "BACKGROUND")
        row.selected:SetAllPoints(row)
        row.selected:SetColorTexture(0.65, 0.56, 0.38, 0.25)
        row:SetScript("OnClick", function(self)
            SW:Select(self.item)
            panel:RefreshSellWheel()
        end)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.item.name)
            GameTooltip:AddLine(("In bags: %d · unlocked: %d"):format(self.item.quantity, self.item.available), 1, 1, 1)
            GameTooltip:AddLine("Klicken lädt die Marktpreise. Eingestellt wird erst mit Verkaufen.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = row
    end
    local empty = label(panel, "No sellable commodities in your bags.", nil, 9, -49, 250)
    local invPrev = button(panel, "‹", 34, 9, -343, function() SW.inventoryPage = SW.inventoryPage - 1 end)
    local invNext = button(panel, "›", 34, 47, -343, function() SW.inventoryPage = SW.inventoryPage + 1 end)
    local invPage = label(panel, "", nil, 92, -351, 120)
    -- Header: icon, item name, stock and refresh (like a selling tab: item on top).
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 311, -2)
    icon:SetSize(36, 36)
    icon:Hide()
    local title = label(panel, "Links ein Item auswählen.", "GameFontHighlightLarge", 354, -4, 300)
    local stock = label(panel, "", nil, 354, -25, 300)
    local function edit(width, x, y)
        local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        box:SetPoint("TOPLEFT", x, y)
        box:SetSize(width, 24)
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        box:SetMaxLetters(7)
        box:SetScript("OnEnterPressed", box.ClearFocus)
        box:SetScript("OnEscapePressed", box.ClearFocus)
        return box
    end
    local refresh = button(panel, "Aktualisieren", 108, 0, -2, function()
        if SW.selected and SW:CanEditSale() then SW:Select(SW.selected) end
    end)
    refresh:ClearAllPoints()
    refresh:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -2)

    -- Quantity and auction duration.
    label(panel, "Menge", "GameFontNormalSmall", 311, -58, 48)
    local quantity = edit(64, 355, -50)
    quantity:SetScript("OnTextChanged", function(self, userInput)
        if userInput and SW:CanEditSale() then SW.quantity = self:GetText() end
    end)
    local all = button(panel, "Alle", 55, 427, -50, function()
        if SW:CanEditSale() and SW.selected then SW.quantity = SW.selected.available end
        panel:RefreshSellWheel()
    end)
    label(panel, "Laufzeit", "GameFontNormalSmall", 520, -58, 50)
    local durationBoxes = {}
    for index, hours in ipairs(SW.durationHours) do
        local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        box:SetPoint("TOPLEFT", 574 + (index - 1) * 52, -51)
        box:SetSize(22, 22)
        local text = label(panel, hours .. "h", "GameFontHighlightSmall", 0, 0, 24)
        text:ClearAllPoints()
        text:SetPoint("LEFT", box, "RIGHT", 0, 0)
        box:SetScript("OnClick", function()
            SW:SetDuration(index)
            panel:RefreshSellWheel()
        end)
        box:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(("Laufzeit %d Stunden"):format(hours))
            GameTooltip:AddLine("Dauer der eingestellten Auktionen. Längere Laufzeit bedeutet meist höhere Anzahlung. Nur änderbar, solange kein Verkaufsplan läuft.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        box:SetScript("OnLeave", function() GameTooltip:Hide() end)
        durationBoxes[index] = box
    end

    -- The two prices as colored cards: stage 1 (green) and stage 2 (blue). The same
    -- colors mark the rows in the offer list below.
    local stageCards = {}
    for stage = 1, 2 do
        local y = -82 - (stage - 1) * 28
        local card = CreateFrame("Frame", nil, panel)
        card:SetPoint("TOPLEFT", 311, y)
        card:SetSize(430, 26)
        card.bg = card:CreateTexture(nil, "BACKGROUND")
        card.bg:SetAllPoints(card)
        if stage == 1 then card.bg:SetColorTexture(0.2, 0.8, 0.35, 0.28)
        else card.bg:SetColorTexture(0.25, 0.55, 1, 0.30) end
        card.name = label(card, stage == 1 and "Günstigstes" or "25 %-Stufe", "GameFontNormal", 8, -6, 100)
        card.price = label(card, "", "GameFontHighlight", 112, -6, 110)
        card.amount = label(card, "", "GameFontHighlight", 226, -6, 70)
        card.total = label(card, "", "GameFontDisableSmall", 300, -8, 84)
        stageCards[stage] = card
    end
    -- Share sold at the cheapest price; the rest goes to the 25 % level.
    local share = edit(40, 386, -81)
    share:SetMaxLetters(3)
    share:SetScript("OnTextChanged", function(self, userInput)
        if userInput then SW:SetCheapShare(self:GetText()) end
    end)
    label(panel, "%", "GameFontHighlight", 430, -88, 14)
    local restShare = label(panel, "", "GameFontHighlight", 392, -116, 40)
    restShare:SetJustifyH("RIGHT")
    label(panel, "%", "GameFontHighlight", 430, -116, 14)

    -- Sell button on top; the wheel continues the rest of the plan.
    local sell = button(panel, "Verkaufen", 200, 311, -140, function()
        quantity:ClearFocus()
        share:ClearFocus()
        SW:PostNext()
        panel:RefreshSellWheel()
    end)
    sell:SetHeight(28)
    -- Only shown while the AH asks for a confirmation of the current post.
    local post = button(panel, "Bestätigen", 200, 311, -140, function()
        quantity:ClearFocus()
        SW:PostNext()
        panel:RefreshSellWheel()
    end)
    post:SetHeight(28)
    local stop = button(panel, "Stop", 70, 517, -140, function()
        SW:CancelPosting(true)
        SW:Stop()
        panel:RefreshSellWheel()
    end)
    stop:SetHeight(28)
    stop:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Verkaufsplan stoppen")
        GameTooltip:AddLine("Bereits eingestellte Auktionen bleiben bestehen. Bei unklarem Ergebnis erst die eigenen Auktionen prüfen; Freigeben wiederholt keine Einstellaktion.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    stop:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local wheelBox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    wheelBox:SetPoint("TOPLEFT", 597, -142)
    wheelBox:SetSize(24, 24)
    label(panel, "Rest per Mausrad", "GameFontHighlightSmall", 623, -149, 110)
    wheelBox:SetScript("OnClick", function(self)
        SW:SetWheelEnabled(self:GetChecked() == true)
        panel:RefreshSellWheel()
    end)
    wheelBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Rest per Mausrad")
        GameTooltip:AddLine("An: Der erste Klick auf Verkaufen stellt die erste Stufe ein. Danach macht jeder Mausradschritt den nächsten Schritt (einstellen bzw. bestätigen), solange der Plan läuft. Ohne laufenden Plan macht das Mausrad nichts.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    wheelBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local status = label(panel, "", "GameFontNormalSmall", 311, -174, 430)
    status:SetWordWrap(true)
    status:SetHeight(26)

    -- Offer list (cheapest first); rows where our prices land are highlighted.
    local LIST_ROWS = 11
    label(panel, "Preis", "GameFontDisableSmall", 314, -204, 100)
    local headQuantity = label(panel, "Menge", "GameFontDisableSmall", 417, -204, 58)
    headQuantity:SetJustifyH("RIGHT")
    local headShare = label(panel, "Konkurrenz kum.", "GameFontDisableSmall", 478, -204, 80)
    headShare:SetJustifyH("RIGHT")
    local listRows = {}
    for i = 1, LIST_ROWS do
        local y = -216 - (i - 1) * 16
        local row = CreateFrame("Frame", nil, panel)
        row:SetPoint("TOPLEFT", 309, y)
        row:SetSize(432, 16)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(row)
        row.price = label(row, "", "GameFontHighlightSmall", 5, -2, 100)
        row.quantity = label(row, "", "GameFontHighlightSmall", 108, -2, 58)
        row.quantity:SetJustifyH("RIGHT")
        row.share = label(row, "", "GameFontHighlightSmall", 169, -2, 80)
        row.share:SetJustifyH("RIGHT")
        row.tag = label(row, "", "GameFontHighlightSmall", 260, -2, 160)
        listRows[i] = row
    end
    local emptyList = label(panel, "Marktpreise laden …", "GameFontDisableSmall", 314, -222, 330)

    local note = label(panel, "", "GameFontDisableSmall", 9, -378, 280)
    panel.durationBoxes = durationBoxes
    panel.quantityBox, panel.shareBox = quantity, share
    panel.sellButton, panel.postButton, panel.stopButton, panel.wheelBox = sell, post, stop, wheelBox
    panel.listRows, panel.stageCards = listRows, stageCards

    local GREEN, BLUE = "|cff60eb80", "|cff66b3ff"
    local function stageColor(stage)
        if stage == 2 then return BLUE end
        return GREEN
    end

    -- Rows shown: the cheapest levels, plus the rows around our two prices.
    local function visibleRows(listing)
        local count = #listing
        local keep = {}
        for i = 1, math.min(3, count) do keep[i] = true end
        for i, row in ipairs(listing) do
            if row.stage then
                for j = math.max(1, i - 1), math.min(count, i + 1) do keep[j] = true end
            end
        end
        local result, last = {}, 0
        for i = 1, count do
            if keep[i] then
                if last > 0 and i - last == 2 then result[#result + 1] = listing[i - 1]
                elseif last > 0 and i - last > 2 then result[#result + 1] = { gap = true } end
                result[#result + 1] = listing[i]
                last = i
            end
        end
        return result
    end

    local function itemIcon(id)
        if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
        if GetItemIcon then return GetItemIcon(id) end
    end

    function panel:RefreshSellWheel()
        if not SW.open or not self:IsVisible() then return end
        if SW.inventoryPending then SW:RefreshInventory() end
        SW:Pump()
        local inventory = SW.inventory or {}
        local pages = math.max(1, math.ceil(#inventory / ROWS))
        SW.inventoryPage = math.max(1, math.min(SW.inventoryPage, pages))
        empty:SetShown(#inventory == 0)
        for i, row in ipairs(rows) do
            local item = inventory[(SW.inventoryPage - 1) * ROWS + i]
            row:SetShown(item ~= nil)
            if item then
                row.item = item
                row.name:SetText(item.name)
                row.quantity:SetText(("%d/%d"):format(item.available, item.quantity))
                row.selected:SetShown(SW.selected and SW.selected.id == item.id or false)
            end
        end
        invPage:SetText(("%d / %d · %d items"):format(SW.inventoryPage, pages, #inventory))
        invPrev:SetEnabled(SW.inventoryPage > 1)
        invNext:SetEnabled(SW.inventoryPage < pages)
        local item = SW.plan and SW.plan.item or SW.selected
        title:SetText(item and item.name or "Links ein Item auswählen.")
        local texture = item and item.key and itemIcon(item.key.itemID)
        if texture then icon:SetTexture(texture) icon:Show() else icon:Hide() end
        stock:SetText(SW.selected and ("In Taschen: %d · frei: %d"):format(SW.selected.quantity, SW.selected.available) or "")
        local editable = SW:CanEditSale()
        local preview, problem = SW:SalePreview()
        local plan = SW.plan
        preview = plan or preview
        local ready = SW:CanRead() and not InCombatLockdown() and not SW.request and not SW.queued
            and not SW.waitingForBags and C_AuctionHouse.IsThrottledMessageSystemReady()
        local confirming = SW.post and SW.post.state == "confirm"

        -- Offer list.
        local listing = SW.listing
        emptyList:SetShown(not listing)
        local shown = listing and visibleRows(listing) or {}
        for i, row in ipairs(listRows) do
            local entry = shown[i]
            row:SetShown(entry ~= nil)
            if entry then
                if entry.gap then
                    row.bg:SetColorTexture(0, 0, 0, 0)
                    row.price:SetText("|cff808080...|r")
                    row.quantity:SetText("")
                    row.share:SetText("")
                    row.tag:SetText("")
                else
                    local color = entry.stage and (entry.stage == 3 and GREEN or stageColor(entry.stage)) or ""
                    local tint = entry.stage == 2 and { 0.25, 0.55, 1, 0.30 } or entry.stage and { 0.2, 0.8, 0.35, 0.30 }
                    if tint then row.bg:SetColorTexture(unpack(tint)) else row.bg:SetColorTexture(0, 0, 0, 0) end
                    row.price:SetText(color .. money(entry.price) .. (color ~= "" and "|r" or ""))
                    row.quantity:SetText(entry.planned and "" or tostring(entry.quantity))
                    row.share:SetText(("%.0f%%"):format((entry.share or 0) * 100))
                    local tag = ""
                    if entry.stage and preview then
                        local amount = 0
                        if entry.stage == 3 then amount = preview.quantity
                        else amount = preview.counts[entry.stage] or 0 end
                        tag = ("%s> %d Stück|r"):format(color, amount)
                    end
                    if entry.owned and entry.owned > 0 then
                        tag = tag .. (tag ~= "" and " " or "") .. ("|cffffd100dein %d|r"):format(entry.owned)
                    end
                    row.tag:SetText(tag)
                end
            end
        end

        -- The two stage cards (what would be posted, or what remains open).
        local merged = SW.presets and SW.presets[1].price == SW.presets[2].price
        for stage, card in ipairs(stageCards) do
            local preset = SW.presets and SW.presets[stage]
            if not (preset and preview) then
                card.price:SetText("–")
                card.amount:SetText("")
                card.total:SetText("")
            elseif merged and stage == 2 then
                card.price:SetText(money(preset.price))
                card.amount:SetText("")
                card.total:SetText("wie Stufe 1")
            else
                local amount = merged and preview.quantity or (preview.counts[stage] or 0)
                local open = amount
                local done = false
                if plan then
                    local index = SW:PlanEntryIndex(plan, stage, true)
                    local entry = index and plan.entries[index]
                    if entry then open, done = entry.remaining, entry.remaining == 0 end
                end
                card.price:SetText(money(preset.price))
                card.amount:SetText(done and "|cff808080OK|r" or ("%d Stück"):format(open))
                card.total:SetText(done and "" or money(open * preset.price))
            end
        end
        quantity:SetEnabled(editable)
        share:SetEnabled(editable)
        if not share:HasFocus() then share:SetText(tostring(SW:CheapShare())) end
        restShare:SetText(tostring(100 - SW:CheapShare()))
        all:SetEnabled(editable and SW.selected ~= nil)
        if not quantity:HasFocus() then quantity:SetText(tostring(SW.quantity or "")) end
        local duration = SW:Duration()
        for index, box in ipairs(durationBoxes) do
            box:SetChecked(duration == index)
            box:SetEnabled(editable)
        end
        wheelBox:SetChecked(SW:WheelEnabled())
        -- The wheel is only taken over while a sale plan runs (it continues the plan).
        SW:BindWheel(SW:WheelEnabled() and (SW.plan ~= nil or SW.post ~= nil) and self:IsVisible())
        note:SetText(("Laufzeit %d h · Mausrad %s"):format(SW.durationHours[duration],
            SW:WheelEnabled() and "setzt den Plan fort" or "aus"))

        -- Main button: one step per click.
        local steps, doneSteps = 0, 0
        local entries = plan and plan.entries or (preview and preview.entries) or {}
        for _, entry in ipairs(entries) do
            steps = steps + 1
            if plan and entry.remaining == 0 then doneSteps = doneSteps + 1 end
        end
        local pending = plan and doneSteps < steps or (not plan and preview ~= nil and steps > 0)
        if plan then sell:SetText(("Weiter · Schritt %d/%d"):format(math.min(steps, doneSteps + 1), steps))
        else sell:SetText(steps > 1 and ("Verkaufen (%d Schritte)"):format(steps) or "Verkaufen") end
        sell:SetShown(not confirming)
        sell:SetEnabled(ready and not SW.post and pending and true or false)
        post:SetShown(confirming and true or false)
        post:SetEnabled(ready and confirming and true or false)
        local busy = Addon:BusyMessage(SW)
        local age = SW.snapshotAt and math.max(0, math.floor(GetTime() - SW.snapshotAt))
        stop:SetText(SW.post and SW.post.state == "unknown" and "Freigeben" or "Stop")
        stop:SetEnabled(SW.plan ~= nil or SW.post ~= nil or SW.waitingForBags ~= nil or SW.request ~= nil or SW.queued ~= nil)
        refresh:SetEnabled(editable and SW.selected ~= nil and SW.request == nil and SW.queued == nil)
        local invalid = editable and SW.selected and not SW.request and not SW.queued and problem
        local summary
        if preview and steps > 0 and age then
            summary = ("Marktstand: vor %d s · %d Stück · %s brutto vor AH-Gebühr"):format(age, preview.quantity, money(preview.total))
        elseif age then
            summary = ("Marktstand: vor %d s"):format(age)
        end
        status:SetText(busy or invalid or SW.status or summary or "Item auswählen.")
    end
    local elapsed = 0
    panel:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.2 then return end
        elapsed = 0
        panel:RefreshSellWheel()
    end)
    panel:SetScript("OnShow", function()
        Addon:SelectMode(SW)
        SW.inventoryPending = true
        panel:RefreshSellWheel()
    end)
    panel:SetScript("OnHide", function() SW:BindWheel(false) SW:Stop() GameTooltip:Hide() end)
    Addon:RegisterModeTabs()
end

function SW:HidePanel()
    self:BindWheel(false)
    if self.panel then self.panel:Hide() end
    if self.tab then PanelTemplates_DeselectTab(self.tab) end
end
