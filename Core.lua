local _, Addon = ...
-- `short` is the label on the auction house tab; `title` stays the window title.
Addon.Single = { title = "BuyWheelS", short = "BWS" }
Addon.Multi = { title = "BuyWheelM", short = "BWM" }
Addon.Sell = { title = "SellWheel", short = "SW" }
Addon.modes = { Addon.Single, Addon.Multi, Addon.Sell }

local function isLegacyCharacter(character)
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player") end
    if not name and UnitName then name = UnitName("player") end
    if name == character then return true end
    realm = realm or (GetRealmName and GetRealmName())
    return name and realm and name .. "-" .. realm:gsub("%s", "") == character
end

function Addon:GetModeDB(mode)
    if type(BuyWheelDB) ~= "table" or BuyWheelDB.schemaVersion ~= 1 then
        local single = type(BuyWheelDB) == "table" and BuyWheelDB or {}
        local multi = type(BuyWheel2DB) == "table" and BuyWheel2DB or nil
        if not multi and self.LegacyMulti then
            local matches = isLegacyCharacter(self.LegacyMulti.character)
            if matches then
                multi = self.LegacyMulti.db
            else
                -- Some clients do not expose the full player identity until
                -- PLAYER_LOGIN. Keep the same mode table when importing later.
                self.pendingLegacyMulti = self.LegacyMulti
            end
        end
        BuyWheelDB = { schemaVersion = 1, single = single, multi = multi or {} }
        self.LegacyMulti = nil
    end
    if type(BuyWheelDB[mode]) ~= "table" then BuyWheelDB[mode] = {} end
    return BuyWheelDB[mode]
end

local migrationEvents = CreateFrame("Frame")
migrationEvents:RegisterEvent("PLAYER_LOGIN")
migrationEvents:SetScript("OnEvent", function(self)
    local legacy = Addon.pendingLegacyMulti
    if legacy and isLegacyCharacter(legacy.character) then
        local db = Addon:GetModeDB("multi")
        for key, value in pairs(legacy.db) do db[key] = value end
    end
    Addon.pendingLegacyMulti = nil
    self:UnregisterEvent("PLAYER_LOGIN")
end)

-- Unit prices this character posted, per item, kept until the listing expires.
-- The AH flags a whole browse row with containsOwnerItem when any listing of the
-- item is ours. Such a row is still a market price unless its lowest price is one
-- of our own listings.
local function serverNow() return GetServerTime and GetServerTime() or time() end
local durationSeconds = { [1] = 2 * 3600, [2] = 8 * 3600, [3] = 24 * 3600 }

function Addon:NoteOwnPost(itemID, unitPrice, duration, quantity)
    if not itemID or type(unitPrice) ~= "number" then return end
    if self.LogPost then pcall(self.LogPost, self, itemID, unitPrice, duration, quantity) end
    self:GetModeDB("multi") -- makes sure BuyWheelDB exists in its current layout
    local posts = BuyWheelDB.ownPosts
    if type(posts) ~= "table" then posts = {}; BuyWheelDB.ownPosts = posts end
    local now = serverNow()
    local list = posts[itemID]
    if type(list) ~= "table" then list = {}; posts[itemID] = list end
    for i = #list, 1, -1 do
        if list[i].expires <= now then table.remove(list, i) end
    end
    list[#list + 1] = { price = unitPrice, expires = now + (durationSeconds[duration] or durationSeconds[3]) }
end

function Addon:IsOwnPostPrice(itemID, price)
    local posts = type(BuyWheelDB) == "table" and BuyWheelDB.ownPosts
    local list = posts and posts[itemID]
    if not list then return false end
    local now = serverNow()
    for _, entry in ipairs(list) do
        if entry.price == price and entry.expires > now then return true end
    end
    return false
end

-- True when a browse row's lowest price can be used as a market price.
function Addon:IsMarketRow(row)
    if not row or not row.itemKey then return false end
    if not row.containsOwnerItem then return not row.containsAccountItem end
    return not self:IsOwnPostPrice(row.itemKey.itemID, row.minPrice)
end

function Addon:OtherMode(mode)
    return mode == self.Single and self.Multi or self.Single
end

function Addon:Notify(mode, message)
    mode.notice = message
    local text = mode.title .. ": " .. message
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(text, 1, 0.25, 0.2)
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    end
end

function Addon:CanUseMode(mode)
    if self.activeMode and self.activeMode ~= mode then return false end
    for _, other in ipairs(self.modes) do
        if other ~= mode and other.HasPendingAHWork and other:HasPendingAHWork() then return false end
    end
    return true
end

function Addon:BusyMessage(mode)
    for _, other in ipairs(self.modes) do
        if other ~= mode and other.HasPendingAHWork and other:HasPendingAHWork() then
            return other.title .. " is finishing an auction house request …"
        end
    end
end

function Addon:SelectMode(mode)
    self.activeMode = mode
    for _, other in ipairs(self.modes) do
        if other ~= mode and other.panel then
            other:Stop()
            other:HidePanel()
        end
    end
end

function Addon:RegisterModeTabs()
    if self.tabsCreated then return end
    for _, mode in ipairs(self.modes) do if not mode.panel then return end end
    self.tabsCreated = true
    local parent = AuctionHouseFrame
    local modes = self.modes
    local tabs = LibStub and LibStub("LibAHTab-1-0", true)
    if tabs then
        for _, mode in ipairs(modes) do
            tabs:CreateTab(mode.title, mode.panel, mode.short or mode.title)
            mode.tab = tabs:GetButton(mode.title)
        end
        return
    end

    local previous = parent.Tabs[#parent.Tabs]
    for _, mode in ipairs(modes) do
        local tab = CreateFrame("Button", mode.title .. "AuctionTab", parent, "AuctionHouseFrameDisplayModeTabTemplate")
        mode.tab = tab
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", previous, "TOPRIGHT", 3, 0)
        tab:SetText(mode.short or mode.title)
        PanelTemplates_TabResize(tab, 20, nil, 50)
        PanelTemplates_DeselectTab(tab)
        tab:SetScript("OnClick", function()
            parent:SetDisplayMode({})
            for _, native in ipairs(parent.Tabs) do PanelTemplates_DeselectTab(native) end
            self:SelectMode(mode)
            PanelTemplates_SelectTab(tab)
            parent:SetTitle(mode.title)
            mode.panel:Show()
        end)
        previous = tab
    end
    hooksecurefunc(parent, "SetDisplayMode", function(_, displayMode)
        if displayMode and #displayMode > 0 then
            for _, mode in ipairs(modes) do mode:HidePanel() end
            self.activeMode = nil
        end
    end)
end
