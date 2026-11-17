# Every function

[Back to the overview](../README.md) · [Guide](GUIDE.md) · [Technical reference](REFERENCE.md)

What each control does, tab by tab. The three tabs sit next to the native auction house tabs: **BWS** (BuyWheelS), **BWM** (BuyWheelM) and **SW** (SellWheel).

## Both buying tabs (BWS and BWM)

- **Favorites list (left):** your auction house favorites. Click a name to select the item. The arrows page through the list; **Load more** appears while favorites are still loading.
- **Purchases:** switches the list to the purchase history (time, quantity, item, total and price per item). **Reset** there clears the history, the counters and the rate measurements. In BWM, baits appear as red negative amounts.
- **Help:** the in-game help pages.
- **Mouse wheel buying:** while watching, a mouse-wheel step buys the displayed matching offer. The chat does not scroll meanwhile. Nothing is bought on a timer.
- **Purchase feedback:** a green border and a pop-up (quantity, item, percent of normal price, profit) after a purchase, a red border when an attempt fails, a blue border when a bait is posted.
- **Bait chat line:** every posted bait writes a line to your chat (item, price, percent of normal, auto or manual).
- **Status line and statistics:** state of the scan, **Confirmed spending**, **Budget left**, **Bought/Missed** items, **items/min** and **items/hour**, and **Est. profit** with **g/h**. The profit changes the moment a purchase or bait sale is confirmed; rates and g/h refresh every 5 seconds.

## BuyWheelS (BWS): one item

- **Item header:** name and the current lowest price. Its color shows whether a buy is possible, **Refresh** shows the scan time in ms.
- **Max Buy Price · per item:** the highest unit price you accept (gold, silver, copper).
- **Bait sell price:** the price of a manual bait (gold, silver, copper). The nearest price that carries the bait fingerprint is posted.
- **Bait button:** posts one bait item. If the AH is busy, the first click reserves the slot and the next click or wheel step posts it. The number above the button is the seconds since the bait was confirmed; it turns green when the sale was recognized.
- **Repeat bait:** after a matching sale, the next wheel step posts a new bait before buying resumes.
- **Leave Bait:** leaves one item at the lowest price instead of buying everything.
- **Buy Bait (x1):** requests a server quote for one item directly from the browse price, skipping the detailed listing query.
- **Buy Bait + quantity:** the same for a fixed quantity (experimental, replaces x1).
- **GO / STOP:** start and stop watching.
- **Spend up to (total):** the budget of the run.
- **Lowest since GO:** the lowest price seen in this run.

## BuyWheelM (BWM): many items

### Favorites list
- **Check box:** watch this item. Only checked items with a positive limit are watched.
- **Bought/Missed:** items bought and missed since the last Purchases Reset.
- **Profit and average price:** estimated profit per item and the average price you paid (green at or below the normal price).
- **Normal price:** the learned normal price in the trust color (grey, yellow, red). The tooltip says why.
- **Click a name:** edit the item's own **Max buy** (gold, silver, copper) at the right.

### Learning and limits
- **Max buy % [N] of normal price:** the percentage that turns the normal price into a buying limit.
- **Start Learning Prices:** measures every favorite (market depth plus lowest prices) and sets all limits. The button shows the progress in percent; the run ends by itself. STOP is locked meanwhile. Nothing is bought.
- **Reset learned (bottom left):** deletes all learned prices, measurements and the limits derived from them (after a confirmation). Run **Start Learning Prices** again afterwards.
- **Shared budget:** the total gold for the run (whole gold).
- **Limit live:** keeps every limit at Max buy % of the current normal price while you watch.
- **Depth measurements while watching:** one per minute, automatically, for the item with the oldest measurement (never during a purchase, bait or offer).

### Bait
- **Leave Bait:** leaves one item at the lowest price.
- **Bait price [N] % of normal:** the price of every auto and manual bait. A warning shows if it is above your own buying limit.
- **Auto-Bait:** posts a bait of a random watched item from your bags, only while watching, only in a quiet market and only with a free wheel step. At most one own bait per item.
- **Material lasts [N] hours:** spreads the bait material in your bags over N hours (default 8, 0 = no limit).
- **Bait status (right edge):** baits in the last minute, the current budget per hour, and a countdown to the next bait ("market active · paused" while buying is possible).
- **ROB (Return on Bait, right of the Auto-Bait row):** the sum of items you bought at the bait price or below after your baits, against the number of baits, e.g. `ROB 23 items · 13 baits`. The tooltip shows how many baits led to purchases, the average per bait and the numbers per item. Reset with the purchase statistics reset.
- **Bait now:** posts one bait immediately (a random watched item), independent of the quiet-market rule.
- **Last bait:** the latest posted bait is shown on the detail line.

### Selected item and session
- **Item block:** name, current lowest price (colored), its percent of the normal price, **Learned normal price** (trust color).
- **Start watching / STOP:** start and stop the run. The state line explains what the addon is doing.
- **Volume Trading:** always on; among all items under their limit one is drawn by weight (margin × quantity listed, capped).

## SellWheel (SW)

- **Icon grid (left):** the sellable commodities in your bags with their counts. Click one to load its market prices. The selected one has an orange border.
- **Keep Bait Items [N]:** keeps N items of every commodity out of the sale (0 = off). The info line shows "keep N".
- **Item, Quantity, Max:** name and icon, the quantity to sell, and **Max** for everything that may be sold.
- **Duration:** 2, 8 or 24 hours (saved). It can only change while no sale plan runs.
- **Cheapest (green):** the price of the first real level of the market (thin bait levels at the bottom are skipped), not undercut.
- **25% level (blue):** just below the price where 25% of the competing supply is reached.
- **Share box:** the percent sold at the cheapest price; the rest goes to the 25% level (default 50/50).
- **Info line:** bags, free, kept, **Deposit** and **Total** (gross, before fees).
- **Sell:** posts the first stage. While a plan runs it reads **Continue · step 2/2**; **Confirm** appears when the AH asks for a confirmation. **Stop** (only shown while a plan runs) abandons the rest of the plan; **Release** clears an unclear result (check your auctions first). Every stage is one click.
- **Offer table:** Price, Available, **Cumulative** share of the competition, **Own** (Yes = your own listing, BW = a probable BuyWheel bait) and **Sale** (what would be sold at that level). Green and blue rows are your two prices, **violet** rows are probable BuyWheel baits. The table scrolls and starts at the cheapest offer.
- **Refresh:** reloads the market prices. Prices older than a minute are reloaded automatically before a sale.
- **After a sale:** the next sellable item is selected automatically and its prices are loaded.
