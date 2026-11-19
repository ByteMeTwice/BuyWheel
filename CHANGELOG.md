# Changelog

Newest first. Every update is pushed to GitHub with an entry here.

## 0.9.21 · 2026-11-18

- **Evaluation page** `tools/BuyWheelLog.html`: a standalone page (no server, no internet) that reads `BuyWheel.lua` from the saved variables and shows the trade log as KPIs (spend, net sales, profit, profit per hour), charts (spend and sales per hour or day, profit per item, price history per item), a sortable item table, the Leave Bait share and the watch-list items without activity. Time range switch (all, 24/48 h, 7 days, last day), light and dark theme, the covered period is shown at the top. In Chrome or Edge the page remembers the file, so **Update** re-reads it after a /reload.
- **Launcher and entry points:** `tools/OpenBuyWheelLog.bat` opens the page and shows `BuyWheel.lua` in Explorer. In the game, the **Report** button in the purchase history (BWM) and `/bwlog html` open a small window with the paths (WoW cannot start a browser itself).

## 0.9.20 · 2026-11-18

- **BWM: Leave Bait is now a threshold instead of a checkbox** (`Multi/LeaveBait.lua`): "Leave Bait [N] %". When the lowest listed price of an item is at or above N % of its learned normal price (small margin), one unit is left at that price; below N % (big margin) everything is bought. 0 = always (the old checked box), 100 = never (the old unchecked box, default); the old setting migrates automatically. Items without a learned normal price are bought completely for N between 1 and 99. The decision is made per purchase, so Direct buy and the fast quote paths only run when no bait is left. Trade log entries carry `leave = true` for such purchases. A thin line under the current price (selected item, same color as the price) marks the prices at which a unit is left behind. BuyWheelS keeps its checkbox.
- **BWM: "Limit live" is gone.** The live limits are always on: while watching, every update of an item's normal price sets its max buy price to the Max buy % (the held limit during a drifting or falling market still applies). The checkbox row now shows **Night anchor** and **Direct buy** side by side.

## 0.9.19 · 2026-11-18

- **Direct buy (BWM, test checkbox next to Limit live, off by default):** buys straight from the multi-item scan without loading the item's listings first, one throttled AH message (about 0.5 s) less per purchase. The AH fills from the cheapest units and the quote is confirmed when its average unit price is within the buy limit (single units may cost more). Not used with Leave Bait or while an own/account listing of the item is up. Purchase statistics get a row "Direct buy"; diagnostics carry `directBuy`, `directBuyQuantity`, `directQtyAfter` and the offer source `browse_direct_avg`.
- **Learned Direct buy quantity per item** (`Multi/DirectQty.lua`, saved in `BuyWheelDB.directQty`, kept through Reset learned, learning runs and the purchase Reset): whenever listings are loaded (normal purchase path, depth probes) the foreign units at or below the buy limit are noted if there are any; the median of the last 20 notes is the base. A confirmed Direct buy at most 90% of the limit on average raises the quantity (x1.5), a quote with an average above the limit halves it; never below half the base, never above 500, always capped by the listed units and the budget. Seeded once from the saved purchase diagnostics. The Direct buy tooltip lists the learned quantity of the watched items.

## 0.9.18 · 2026-11-18

- Fix: prices were marked yellow ("Market moving") far too often since 0.9.17 (16 of 48 items). The falling-market rule fired when the newest depth sample was below the lower quartile by any amount, i.e. on the normal noise of a few percent. It now needs a drop of at least 10% below the quartile (Dense Stone 637 vs 450 still counts); smaller dips stay grey and no longer lock the buy limit.

## 0.9.17 · 2026-11-18

- **Permanent trade log** (`TradeLog.lua`, saved in `BuyWheelDB.tradeLog`, up to 20000 entries, not touched by the statistics Reset): every confirmed purchase (with unit price, learned normal price, buy limit and the learned state: source, drift, falling, capped), every posted listing (bait or SellWheel, with quantity), every sale message and every sale/purchase invoice mail (price, deposit, AH fee). `/bwlog [hours]` prints a summary per item (bought, average price, posted, sales, invoice net), `/bwlog last [n]` the newest lines.
- **Normal price in a falling market:** the lower quartile of 90 minutes of depth samples still contained old, higher prices (Dense Stone: samples 1198 ... 450 gave a normal price of 637 and a buy limit of 446). The newest depth sample now caps the depth price; such a value counts as drift, and while the market drifts or falls the buy limit can only go down.
- **Long-term anchor, switched by the new checkbox "Night anchor" (BWM, next to Limit live, off by default):** the lowest price is noted every 30 minutes for 7 days (always, kept across learning runs). With the checkbox on and 6 notes over at least 2 hours, a normal price may lie at most 25% above their median, so a spike of a few hours (cheap units bought out, thin top of the book) can no longer raise the buy limit. The item shows "Capped by 7-day median" in the panel; the buy limit does not rise while capped. The checkbox can be switched while watching.

## 0.9.16 · 2026-11-17

- BWM: the **Refresh** line also shows the world **Ping** (`Refresh: 1919 ms  ·  Ping 60 ms`), and every purchase diagnostic stores `homePingMs` / `worldPingMs`. Refresh is the time between AH replies, which is limited by the game's AH message throttle and your connection; the ping makes visible which of the two is slow.

## 0.9.15 · 2026-11-17

- BWM: **Auto-Bait and Bait now no longer treat your normal sale listings as baits.** Every item you had any auction of (for example from SellWheel) counted as "own bait up" and was skipped, so with material in the bags the notice still said "No watched item with bait material" (`34 no material, 8 own listing`). An own listing now only counts as a bait when the lowest price of the item is at bait level (at or below the bait price, plus 20% slack for relearned prices).

## 0.9.14 · 2026-11-17

- BWM: the "No watched item with bait material…" notice now says why, per watched item, e.g. `(30 no material, 12 no price, 2 own listing)`. Reasons: disabled, no price, no material, no item info, not commodity, own listing, just posted, unsellable. The same counts are summed in `db.autoBaitDiag` (`skip_*`). Meant to find out why a bait is not possible although the bags hold material.

## 0.9.13 · 2026-11-17

- BWM: fixed "No watched item with bait material, a learned price and no own bait up" although the bags held material. The bait pick gave up after 8 watched items without material (in random order), so with a long watch list it often never reached the items that had stock. The bags are now scanned once and only items that are really in the bags are checked; the limit is gone. New diagnostic counter `skip_unsellable` (in the bags but not postable).

## 0.9.12 · 2026-11-17

- SellWheel: a **Posted** line at the bottom left adds up everything you post (quantity x price, before fees) and shows what the 25% level added on top (`Posted: 48g 20s  + 6g 10s at 25%`). It is saved between sessions; **Reset** next to it starts a new count, and the tooltip lists the items.

## 0.9.11 · 2026-11-17

- BWM: ROB now shows the **sum of items** bought at the bait price or below after your baits, against the number of baits (`ROB 23 items · 13 baits`), instead of a share of baits with any purchase. The tooltip adds the baits that led to purchases and the average per finished bait.

## 0.9.10 · 2026-11-17

- SellWheel: no more "You cannot sell a soulbound item" messages in the chat. The bag scan asked the game whether each item can be sold and let it print an error for soulbound commodities (for example Marks of Honor). Such items were never offered; now the scan is silent.

## 0.9.9 · 2026-11-17

- BWM: **ROB (Return on Bait)** in the Auto-Bait row, right edge: `ROB 62% · 18/29` = baits that were followed by purchases at the bait price or below (others matched or undercut it), out of all finished baits. A bait's window ends with the next bait of that item or after 10 minutes; baits still in their window are not counted yet. Tooltip: open baits, items bought, average per successful bait and the numbers per item. Reset with the purchase statistics reset.

## 0.9.8 · 2026-11-17

- SellWheel: the mouse wheel sale is gone (checkbox "Wheel" and the wheel binding). Every stage is one click on **Sell**. The **Stop** button only shows while a sale plan runs or a result is unclear.

## 0.9.7 · 2026-11-17

- More conservative normal price (rule: rather no profit on a thin margin than a loss): the depth is measured at the first **5%** of the supply instead of 10% (still at least 20 units), and the normal price may lie at most **3%** above the median of the lowest prices instead of 5%. Example: Wild Steelbloom was valued at 97.46c with 480 units between 92c and 96c; it now comes to about 94c. After updating, press **Reset learned** and learn again so that the new rule is the only data in use.

## 0.9.6 · 2026-11-17

- BuyWheelM: the "Depth/min" field is gone; the watching loop runs one depth measurement per minute (not a setting any more).
- BuyWheelM: the bait status moved to the state row, so it no longer overlaps the spending line; the profit and rates lines use the full width. "unpriced" in the profit line now reads "not counted" (units without a known normal price at purchase, or baits whose item was not bought in this profit period).

## 0.9.5 · 2026-11-17

- The learned normal price is more conservative: of several depth measurements the lower quartile counts instead of the middle, and the normal price may lie at most 5% above the median of the lowest prices. Items with a thin top of the book (Linen Cloth, Solid Stone, ...) were valued up to 19% too high, which made their usual lowest price look like a bargain.

## 0.9.4 · 2026-11-17

- **One-file installer and updater for Windows:** `UpdateBuyWheel.bat`. It finds the AddOns folder, downloads the newest version from GitHub and installs it, keeping the saved data. It refuses to touch a Git (development) copy. The README now starts with this.

## 0.9.3 · 2026-11-17

- SellWheel fix: with "Keep Bait Items" above 0 the second stage of a sale was never posted (the wait for the updated bags compared against the wrong stock). Fixed.
- SellWheel: the two prices are shown even when no quantity can be sold (for example when everything is kept as bait); the message then says so.

## 0.9.2 · 2026-11-17

- Auto-Bait simplified: the fields "per min" and "budget" are gone. The only setting is **Material lasts [N] hours** (default 8): Auto-Bait spreads the bait material in your bags over that time and works out the rate itself. The bait speed during quiet windows is fixed.

## 0.9.1 · 2026-11-17

- **Bait fingerprint:** every bait is posted at the nearest price that satisfies a fixed rule (from 2s up), so other BuyWheel users can recognize it. Always on, no setting. In the SellWheel table a probable BuyWheel bait is shown in violet with "BW" in the Own column.

## 0.9.0 · 2026-11-17

- Auto-Bait gets a **bait budget**: "budget" (baits per hour on average) saves up while the market is busy and is spent at the bait speed ("per min") in the quiet windows, so day and night no longer behave completely differently. "lasts" (hours) works the budget out from the bait material in your bags and the time left.
- The bait price field moved to the first options row; the second row now holds Auto-Bait, speed, budget and lasts. The status shows the budget and the countdown.

## 0.8.5 · 2026-11-17

- All SellWheel texts are English again (labels, buttons, tooltips, status messages), as well as the depth status, the purchase pop-up and the bait chat line.
- SellWheel: new **Keep Bait Items** box (left, below the icon grid). That many items of every commodity are never sold, so they stay available as bait; 0 = off. "Max" and the quantity check use only the stock that is not kept.

## 0.8.4 · 2026-11-17

- SellWheel: the single-level rule for "Günstigstes" is now 0.5% of the supply (at least 5 units) instead of 2%, so real offers at the bottom of a huge market count (example: 229 units at 3s 99c in a market of 17000). Baits of a few units are still skipped.

## 0.8.3 · 2026-11-17

- SellWheel: when the selected item is sold out, the next sellable item is selected automatically and its market prices are loaded, so the list is never empty.

## 0.8.2 · 2026-11-17

- SellWheel: "Günstigstes" no longer skips a large real level. A price level now counts as the first real offer also when it holds 2% of the supply on its own (example: 188 units at 19s 60c in a market of 5900), besides the existing 5% rule. Thin bait levels are still skipped.

## 0.8.1 · 2026-11-17

- SellWheel rebuilt after the Auctionator selling tab: icon grid of the bags on the left; item icon and name, quantity with "Alle", duration, deposit and total on the right; the two price strips and the **Verkaufen** button; and a scrolling table of the market offers (Preis, Verfügbar, cumulative share, Dein, Verkauf) with your two prices highlighted.

## 0.8.0 · 2026-11-17

**SellWheel in the style of a selling tab**
- New layout: item icon and name on top, quantity and duration, two colored price cards (green = cheapest, blue = 25% level) with the share box, a big **Verkaufen** button, and the list of the cheapest offers below. The two prices are highlighted in the list at the rows where each half is sold.
- The cheapest price is no longer undercut by one copper: it is the price of the first meaningful level itself.
- **Rest per Mausrad** (on by default): the first click on Verkaufen posts the first stage, then each scroll step posts the next one. Without a running plan the wheel does nothing and is not taken over.

## 0.7.9 · 2026-11-17

- BuyWheelS: more compact and better grouped. Repeat bait sits on the title row of "Bait sell price". Leave Bait / Buy Bait are one row above GO / STOP, "Spend up to (total)" directly below the buttons, and the big gap is gone: status, spending and statistics moved up.

## 0.7.8 · 2026-11-17

- BuyWheelS: "Spend up to" moved to the bottom, between the option checkboxes and the spending statistics (it is a setting you make beforehand). Repeat bait is back above GO / STOP.

## 0.7.7 · 2026-11-17

- BuyWheelS: the two prices belong together now. Top row: Max Buy Price (left) and Bait sell price with the Bait button and its timer (right). The row below holds "Spend up to" and Repeat bait; GO / STOP follow.

## 0.7.6 · 2026-11-17

- BuyWheelS: the "Repeat bait" label now sits next to its checkbox (it floated above the Spend Up To boxes).

## 0.7.5 · 2026-11-17

- BuyWheelS: tidied the panel. The current price and Refresh sit directly under the item name, the Max Buy / Spend Up To boxes follow, then the whole Bait row (Bait sell, three boxes of the same size, Bait button and the bait timer to its right), Repeat bait below it, then GO / STOP.

## 0.7.4 · 2026-11-17

- Removed the **Compare** button and its table of measured settings (both tabs). The rates, Est. profit and the other statistics stay.

## 0.7.3 · 2026-11-17

- BuyWheelM: the Buy Bait option is removed completely (always off in this tab).
- Auto-Bait row re-spaced so rate, price and units no longer overlap.
- The learning button is now "Start Learning Prices" and larger.
- New **Reset learned** button (bottom left, next to Help, with confirmation): deletes all learned normal prices, depth measurements and the limits derived from them, so a new learning run is the only data in use.

## 0.7.2 · 2026-11-17

- BuyWheelM: the top of the right column is tidied. Readable gold labels, "Start learning" on the right edge, the options in two clean rows (Leave Bait · Buy Bait · Depth/min, then Auto-Bait with rate and price percent).

## 0.7.1 · 2026-11-17

**BuyWheelM cleanup**
- Removed the "Buy Bait" option with the quantity field from this tab. A saved setting becomes the one-item Buy Bait. (BuyWheelS keeps both.)
- Volume Trading is now always on; the checkbox is gone.
- The options area is re-ordered: Leave Bait and Buy Bait in the first row, "Tiefe/min" below.
- The in-game help text now describes the depth-based learning and the progress display.

## 0.7.0 · 2026-11-17

**SellWheel**
- New layout: the market as a price list with quantity and cumulative share, your own listings marked, and the two prices you would post highlighted (green = cheapest, blue = 25% level).
- Two-stage sale, default 50% / 50%, whole quantity. The share is editable. **Verkaufen** posts one stage per click; optional **Mausrad** posts the next stage per wheel step.
- "Günstigstes" skips thin bait levels at the bottom of the market.
- Auction duration boxes use the real Forever durations: 2h, 8h, 24h.

**BuyWheelM**
- Learned normal price now comes from market depth (price where the first 10% of the supply is reached). Depth samples come from learning, free from loaded listings and SellWheel, and from an adjustable low query rate ("Tiefe/min").
- Learning shows its progress in percent on the button, ends by itself and is much faster. STOP is greyed out while it runs.
- Reliability by color in the favorites list: grey = fine, yellow = careful, red = old.
- Own listings no longer block price measurements (own posted prices are remembered). No measurement is taken for 30 seconds after an own buy or bait.
- Est. profit is live; gold per hour has two decimals.
- Baits: chat line for every bait, "last bait" display, countdown to the next Auto-Bait, baits listed as negative amounts in the purchase history and included in the profit calculation.

**Other**
- Tabs are shortened to BWS, BWM and SW.
- New GitHub landing page; the detailed text moved to `docs/REFERENCE.md`.

## 0.6.0 · 2026-11-16 and earlier

- Three tabs in one addon: BuyWheelS, BuyWheelM, SellWheel.
- BuyWheelM: purchase history with time and a green pop-up per purchase, 7 second refresh window, Volume Trading, normal-price learning with outlier guard and "Limit live", price as percent of the normal price, Auto-Bait and "Bait now", compact statistics, re-ordered panel layout.
- SellWheel: price suggestions named by position in the supply, duration boxes.
