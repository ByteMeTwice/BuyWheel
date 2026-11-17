# BuyWheel · full reference

[Back to the overview](../README.md)

One addon with three auction house tabs:

- **BuyWheelS**: single-item watching, with manual bait posting.
- **BuyWheelM**: multi-item watching, per-item limits and normal-price learning.
- **SellWheel**: market price list with two sale prices (cheapest / 25% level) split 50/50.

Selecting a tab stops the other modes, including any learning session. A pending
AH query or purchase must settle before another mode can send requests. A
confirmed purchase is not cancelled merely by switching tabs; its outcome is
still recorded by the mode that initiated it.

The tabs use LibAHTab when available. Otherwise all three tabs are added in order
after the native auction house tabs.

Both buying tabs briefly flash a green border on a confirmed purchase and a red border
when a purchase attempt ends unsuccessfully (including cancellation). The border
lasts 0.45 seconds; a new result replaces the previous color. Search failures,
missed scans and purchases still waiting for an outcome do not flash. No AH
requests or repeating timers are added by this visual feedback.
The central "Internal auction error" message is suppressed during a BuyWheel
purchase and for one second after an unsuccessful result while its tab is
visible. The red border and diagnostic logs remain active; other error messages
and errors outside this purchase window retain their normal display.

## BuyWheelS

Click a favorite, set its maximum price and a budget, then press GO. Scroll to
buy the displayed matching offer. Leave Bait and Buy Bait retain their existing
behavior. The manual Bait button is available in this tab.

## BuyWheelM

Click favorite names to edit their individual limits and check the items to watch.
Each run watches only current favorites that are checked and have a positive buy
limit. Removed favorites are excluded on the next start; their saved settings
and learned prices remain available if they are added again.
Set the shared budget and press **Start watching**. Scroll to buy the displayed
offer. Matching items are prioritized by estimated profit per unit: learned normal
price minus the current minimum price, in copper rather than percentage discount.
Without a learned price, the buy limit is used as a fallback reference. Equal
margins rotate between items. Browse's total quantity is not treated as quantity
available at the minimum price. Ranking adds no AH requests; estimates exclude
fees and deposits and do not guarantee resale proceeds. The favorites list shows learned
normal prices directly; the right column edits the selected item's buy limit
and shows the active item and session totals. The tooltip also shows its limit.
Below each favorite's name, bought/missed item quantities appear as `12/3` to
the left of its normal price. Counts cover all Multi runs and settings since
Purchases Reset, clear on reload and start at `0/0`.
Estimated profit for each item appears after its bought/missed counts, before
the normal price. Green means positive, red negative; `–` means purchases lack
a normal-price reference. Values use each purchase's original learned price
and actual cost, include tracked bait corrections, and exclude AH fees/deposits.
Per-item profit refreshes every five seconds and clears with Purchases Reset.
Rate and estimated-profit displays in both modes refresh every five seconds;
Reset, GO/STOP, settings and layout changes refresh them immediately. Purchases
and item counters are still recorded as soon as their results arrive.
The list updates live with the most bought item quantities first. Equal counts
keep the original favorites order. Sorting applies across all pages and changes
only the display; purchase priority follows the estimated margin described above.

To learn prices, set **Max buy %** (1–100), then press **Start learning**. The
run covers all favorites, including unchecked ones, while the AH and tab remain
open. Its progress in percent replaces the button text ("Learning 63%"). It ends by itself at 100% (a 30 minute
limit only guards against a stuck run). STOP is greyed out while it runs; closing
the tab cancels it. No purchases are made.
At the end, limits become the selected percentage of each item's normal price
(see "Normal price from market depth"), rounded down to at least one copper. An
item needs ten minimum-price samples; otherwise its limit remains unchanged. Existing watch checkboxes are preserved.
Persistent bait can affect this estimate; it measures listings, not sale prices.

BuyWheelS offers **Buy Bait** with a quantity field (removed from BuyWheelM) as an experimental alternative
to the one-item Buy Bait option. The field accepts whole numbers from 1 to
999999 and defaults to 3. Each tab saves its own quantity. Selecting either
checkbox deselects the other. With Leave Bait off, the configurable option
requests one commodity quote for exactly the entered quantity directly from
Browse, subject to sufficient listed stock and budget for the entire order.
It skips unsuitable Browse matches instead of falling back to smaller purchases.
Non-commodity items and Leave Bait continue to use their normal detailed search
behavior. Quote and purchase limits still apply to the entire order. Change the
option or quantity while stopped. For compatibility, logs retain `fastQuoteX3`
and `offerSource = "browse_fast_quote_x3"`; `fastQuoteQuantity` records the
configured quantity, and purchase `quantity` records the actual order size.

**STOP** ends watching or cancels learning. Cancelling learning, closing its tab
or entering combat applies no limits. There is no manual bait button in this tab.

## SellWheel · price list and two-stage sale

The layout follows the Auctionator selling tab. On the left an **icon grid** of the
sellable commodities in your bags (with counts; click an item). On the right: the
item icon and name, **Menge** with **Alle**, the **Laufzeit** (2 / 8 / 24 hours),
the two price strips, the info line (stock, deposit, gross total), the
**Sell** button, and below it a **table of the market offers** (Price,
Available, cumulative share of the competition, "Own" = your own listings in
that price level, and the Sale column). The table scrolls; it starts at the
cheapest offer. Your own listings never count as competition. **Keep Bait Items** (box below the icon grid) reserves that many items of every commodity: they are never sold ("Max" and the quantity limit use the rest), so you can keep using them as bait. 0 switches it off. When only the kept items are left of a sold item, the next item with something to sell is selected. When an item is sold out, the next sellable item of the grid is selected automatically and its prices are loaded.

Two prices are used, as colored strips and highlighted at their rows in the table:

- **Cheapest** (green): the price of the first *meaningful* level itself, not
  undercut by a copper. A level counts once the supply up to it reaches about 5%
  of the competing supply (at least 5 units), or when it holds 0.5% of the supply
  on its own (at least 5 units), so a thin bait level at the very bottom is
  skipped but a real level is not, even in a market of many thousand units.
- **25% level** (blue): just below the price level where about 25% of the
  competing supply is reached, never below the first meaningful level.

A planned price that has no level of its own appears as an extra row in the list.

**Split:** the box on the Cheapest card is the share (0-100%, default 50)
of the quantity sold at the cheapest price; the rest goes to the 25% level (shown
on its card). The whole quantity is sold. Rounding keeps the total, and if both
prices are the same the sale is one step. The cards show quantity, price and
total; the status line shows the gross value before AH fees. Suggestions do not
guarantee sales or profit.

**Sell** posts the first stage with one click (WoW needs a real click for
each post). The button shows the number of steps and, while a plan runs, "Continue ·
step 2/2". **Wheel** (checkbox, on by default): after the first
click, every mouse wheel step posts the next stage (or confirms), so the rest is
a quick scroll. The wheel only continues a running plan: without one it does
nothing and is not taken over. It only works while the SellWheel tab is open and
out of combat; chat scrolling is paused while a plan runs. A step never posts
while a post is still running.

Three checkboxes (2h, 8h, 24h) set the auction duration (default 2h; saved). The
quantity box, the share and the duration can only be changed while no sale plan
runs, and a started post keeps its duration through the confirmation step. The
deposit check uses the selected duration. Entering a quantity or pressing **Alle**
keeps the typed quantity across a refresh of the same item.

**Bestätigen** appears only when the AH asks for an extra confirmation. Results
and timers never post another stage. Prices and quantities stay fixed until
completion or Stop. Stop abandons the remaining plan; previously posted auctions
remain listed. A successful post is not a sale.

A market snapshot at most one minute old is required to start a new plan. If it
is older, the click reloads the prices instead and you click again. **Aktualisieren**
reloads prices. Opening the tab, changing the share, and normal UI updates do not
send market queries. Bags, stack identity, available quantity and deposit money
are checked before posting. Bank/mail stock and non-commodity items are outside
this version.

Switching tabs stops the remaining plan and lets already-sent posts settle
before BuyWheel can send requests. Missing confirmations are never retried
automatically: inspect the native Auctions list before clicking **Freigeben**
to clear an unresolved result. Clearing does not post or cancel any auction.
A late confirmation can still resolve a pending result.

The share, duration and wheel option are saved; posting diagnostics retain
submitted quantities, prices, duration codes and outcomes. Sale proceeds and
persistent purchase-cost accounting are not yet tracked.

## Saved data and migration

All modes save to the character's `SavedVariables/BuyWheel.lua`:

- `BuyWheelDB.single`: existing single settings, purchases and diagnostics.
- `BuyWheelDB.multi`: existing multi settings, watch list, learned prices and logs.
- `BuyWheelDB.sell`: SellWheel share, duration, wheel option and posting logs.

The original single database is wrapped without discarding its fields. A
one-time import of an older multi database (`LegacyMulti.lua`) existed for the
author's own character; it is not part of the public repository, and the code
simply skips the import when that file is missing. New characters start with
their own empty data. Reload or log out to save the combined database.

Pre-merge code and saved data are backed up outside AddOns in
`Interface/BuyWheelBackups/`. BuyWheel2's standalone addon folder is retired
there, so only BuyWheel is installed.

## In-game help and bait messages

Both tabs have a **Help** button beside the bottom page controls. **Previous** and
**Next** select the three help pages; long pages can be scrolled. **Back** returns
to the mode. Watching and learning continue, while wheel purchasing is suspended
until Help is closed. Changing to the other mode still stops the current session.

If the manual Bait action has no sellable copy of the selected item in the bags,
a red message names that item immediately, before waiting for AH readiness. The
same alert is shown if the item becomes unavailable during posting confirmation.
Locked or otherwise unsellable copies also trigger the sellable-item check.

## Bait posting recovery

After a confirmed bait listing in BuyWheelS, the default first price refresh is
one fresh detailed item query. The Repeat bait + Buy Bait combination can first
use the direct post-quote path described below instead. It skips the usual Browse step and avoids reusing a listing
refresh cache from before the post. Subsequent cycles return to the normal route.
AH readiness, quote limits and exclusion of the player's own listings still apply.

The last 50 posting attempts are recorded in each mode's `postDiagnostics`.
Fields distinguish `beforeSendWaitMs` (reserved slot until the next Bait click),
`finishedMs` (post/confirmation round trip), `resumeReadyMs` (first observed AH
readiness after posting), `resumeSendMs`, `resumeReplyMs`, `resumeResponseMs`,
`offerReadyMs` and `firstBuyMs`. The last two also depend on available offers and
wheel input. Failed first queries have `resumeFailure`. Scan windows additionally
count `baitWaitExpired`, `postAttempts`, `postSucceeded` and `postFailed`.

If Bait is clicked while the AH is busy, the next message slot is reserved for
posting. Scroll or click Bait again once ready; no automatic posting is performed. The
reservation expires after ten seconds. While reserved, price scanning and wheel
purchases pause. A posted bait may itself be the lowest auction; the addon cannot
skip that tier when asking the commodity server to buy from the cheapest tier.

## Purchase history reset

Both tabs keep their purchase history, total purchase spending, item counts,
bait counts and Bought/Missed statistics across GO / Start watching runs.
The **Reset** button at the bottom of the Purchases view clears these statistics
for that tab and returns the history to page 1. They live only in memory and
clear when WoW restarts or the UI reloads. A pending purchase confirmed after a
reset appears in the newly cleared history.

Budget accounting and Confirmed spending remain specific to each watching run.
Starting a run resets that budget accounting; resetting Purchases does not
restore any of the current run's budget.

## Purchase rates

In both modes, rates and estimated profit refresh every five seconds (the profit
amount itself is live). Purchases are still recorded immediately. Reset, GO/STOP,
option changes and compact layout changes refresh the display immediately.

The right column shows confirmed items/minute and items/hour for the current
setting, alongside its accumulated active watching time. Each setting
accumulates GO-to-STOP time across runs. Waiting for stock, reading Help and
manual bait posting count toward that time; STOP, learning and benchmarking do
not. Outcomes use the setting from when the purchase began, including
confirmations after STOP. Unresolved attempts are excluded.

Purchases **Reset** clears measurements for that tab and restarts its clock if
watching. Measurements live only in memory and clear on UI reload or restart.
They do not affect purchase limits or budget accounting. (The former Compare
table was removed.)

## Bait lifetime

BuyWheelS shows a bare seconds value below Bait, with one decimal
place. It starts at the latest confirmed bait listing, updates while waiting
and turns green and freezes when the matching sale notification arrives.
Failed posts do not replace the previous measurement. STOP and Purchases Reset
do not clear it; reloading does. The button tooltip identifies the tracked item.

This listens to both system-chat sale messages and formatted auction sale
notifications, without additional auction queries. The translated client sale
message is recognized, and duplicate messages across both channels are paired.
Formatted notifications may contain a raw item name or link. Matching uses the
item link/ID or the notification's item name;
each new confirmed bait replaces older pending timers for that item, so a missing
sale message for the old bait cannot consume the new bait's sale. The event cannot
distinguish other own listings of that same item, so those sales can make the
measurement approximate. Cancellation/expiration is not detected by this timer.
The measured end is receipt of the sale notification, including its delivery delay.

## Repeat bait in BuyWheelS

**Repeat bait**, below Bait, gives real mouse-wheel inputs priority to replace
bait while GO is running. With no tracked bait live, a wheel step invokes the
normal single-item posting path. Once confirmed live, normal wheel buying
continues. A matching sale makes the next wheel step post a replacement; the
sale handler itself never posts. Throttling reserves the next available slot;
confirmation or readiness may require another wheel step. Help and Compare,
combat, hidden panels and pending purchases continue to block these actions.

It posts one item at the configured Bait sell price, with the shortest duration. Posting errors, unknown results, invalid prices and missing sellable
items disarm the option. STOP, closing/changing tabs and selecting a different
item also disarm it. Unchecking Repeat bait releases a reserved posting slot.
The checkbox can be armed before GO; no posting occurs merely by enabling it.
Manual Bait clicks also wait for a tracked live bait while this option is armed.

This reuses item-based sale matching and knows only bait listings confirmed in
this UI session. Other own listings of the same item can affect matching;
cancelled or expired baits still need manual attention. It does not synthesize
input or post automatically from held buttons, update loops or timers.

## Continue a manual Bait with the wheel

A reserved manual Bait post or a server confirmation now has priority on the
next real wheel input once the AH is ready, even with Repeat bait off. The same
input never also buys an item. This works during GO and temporarily outside GO:
without a watching run, wheel bindings are released after the post finishes,
fails, is stopped or its reservation/confirmation times out. Help/Compare,
combat and pending purchases still block posting. No post is sent by a timer.

Post diagnostics now separate the post-to-query wait, the query response,
readiness after that response, the first buyable offer and the next input.
This distinguishes AH throttling from missing offers and time waiting for input.

## Fast Buy Bait immediately after Repeat bait

Enable **Repeat bait** and **Buy Bait** (either one item or the quantity field),
leave **Leave Bait** off, then GO. For commodities, each confirmed bait listing
reserves the next ready AH slot for one direct purchase quote over the selected
quantity. The next real wheel input requests the quote without first querying
Browse or detailed listings. The panel says **Server quote ready** and shows the
quantity and maximum total; it does not present the price ceiling as a market
price. Repeat bait still replaces a sold bait before attempting to buy.

A positive, uniform-price server quote must fit the current per-item price limit,
remaining budget, available gold and the original request ceiling before the
existing confirmation path is used. Mixed price tiers are rejected. Inventory
and ownership restrictions remain enforced by the server: a quote blocked by
own stock or unavailable items can fail and does not prove stock is available.
Only confirmed successful purchases affect spending totals.

Each post gets one probe, not a repeating quote loop. No input within two seconds
of readiness, a rejected/unavailable quote, changed settings or an unaffordable
worst-case total returns to fresh detailed listings. The detailed fallback keeps
the selected Buy Bait quantity, including owner-stock exclusion, and never buys a
smaller or larger batch. Leave Bait, ordinary buying, non-commodities and manual
posting without Repeat bait retain the default recovery path. STOP disarms a
pending quote opportunity. Probes rejected before any listing was observed do
not inflate missed-item statistics; an actual failed confirmed purchase still can.

Post logs contain `fastQuoteQuantity`, `fastQuoteReadyMs`, `fastQuoteSendMs`,
`fastQuoteOutcome` and `fastQuoteFinishedMs`. Purchase attempts identify this path
as `offerSource = "post_fast_quote"` and `route = "post_quote"`. Compare new logs
with default post recovery to establish whether the saved query helps in the
actual market; AH throttling and quote failures can still dominate the result.

Standalone mocked-AH integration checks (Lua 5.1) run from the WoW directory:
`lua Interface/AddOns/BuyWheel/Tests/PostFastQuote.lua`.

A replacement bait resets the displayed age only after the new listing is
confirmed. Failed posting attempts keep the previous timer. Duplicate sale
messages from the previous bait remain filtered across chat and notification
channels. This timer replacement does not prove that an older auction sold;
it simply makes the newest confirmed bait the one being measured.

## Independent Bait sell price

BuyWheelS has a compact **Bait sell** row near the top, with three input boxes
for gold, silver and copper (`g`, `s`, `c`) and the Bait button to their right.
Its numeric `baitPrice` is saved in the existing character settings. The Multi
tab does not show manual bait-selling controls. It is independent of the maximum
buy price and does not change when a different buy limit is entered or selected.
Manual and repeat posting use this exact price; the tooltip and post logs agree.

The fields start empty when no sell price has been configured. Posting requires
an explicit positive whole-copper price; there is no derived-price fallback.
Non-commodity auctions still require at least one silver, and client restrictions
on copper values still apply. The sell fields are disabled during a reserved or
pending post/confirmation. Changing only the buy limit during confirmation does
not change the price being posted.

## Estimated profit in Single and Multi

Both rates areas show **Est. profit**, summed over confirmed purchases in that
mode since its Purchases Reset, across all settings, items and GO runs. Single
and Multi keep independent totals; selecting another item does not clear them. Each contribution is
`learned normal price at purchase start * quantity - actual confirmed total`.
Both modes use the per-item normal prices learned in Multi, via
`Multi.db.learnedPrices[target.id].normalPrice`, independently of the buy limit. The snapshot is retained in the in-memory purchase entry and
purchase diagnostics; later learning does not revalue older purchases.

AH commission, deposits and realized resale proceeds are not part of this
estimate. Failed and unresolved purchases contribute nothing. Purchased items
without a positive learned price are excluded and shown as **unpriced**, rather
than given a fabricated zero normal price. Negative margins and fractional
copper values from median learning are preserved.

The estimate and **gold/hour** share a line below the item rates. Gold/hour is
`estimated profit / total active watching seconds in this mode * 3600 / 10000`, across
all option groups since Reset. STOP pauses the denominator; switching options
does not discard earlier active time. The rate stays blank until time has
elapsed, and is unknown if all purchased items lack a learned price. Four
decimal places preserve small gold rates. Short windows use a two-line
layout: Single retains its bottom statistics area; Multi uses the area above
its session controls. The tooltip shows how many
items were valued or excluded. Profit covers the whole current mode; item rates still
refer to the current option group. GO/STOP retain it; Purchases Reset or reloading
clears it without restoring the active run's spending budget.

## Bait-adjusted estimated profit

Confirmed purchases retain FIFO quantity lots with their original learned normal
price and actual average unit cost. A confirmed bait post consumes one tracked
unit for that item. Lots are matched oldest-first across Single and Multi; the
correction belongs to the mode and Reset scope that recorded the purchase.

For already-valued purchases, posting removes that unit's expected normal-price
proceeds from estimated profit. Its purchase cost was already deducted and is
not charged again. A matching sale notification adds the configured one-item
bait sale price. Example: a 1-gold purchase valued at 2 gold initially estimates
+1 gold; posting removes the expected 2 gold, and a confirmed 10-silver bait sale
leaves -90 silver. Gold/hour uses the adjusted total automatically.

A purchased unit without a learned normal price previously contributed no
estimate. If it becomes bait, its known purchase cost is recognized once, and
its confirmed sale proceeds then determine its actual gross margin. Baits from
preexisting stock without a tracked purchase have no known basis; they are
excluded and included in the on-screen unpriced count.

Posting failures do not consume lots or change estimates. Duplicate sale
notifications cannot credit a bait twice. Missing notices and retired older
timers leave the corresponding proceeds pending/unreported; they never retain
imaginary normal-price income. Cancelled or expired bait without a recognized
sale also remains pending until Reset. The tooltip shows sold, pending/unreported
and unpriced bait counts. AH commission and deposits remain excluded.

Purchases Reset clears the scope's lots and corrections. A sale belonging to an
older Reset scope does not enter the new estimate. Post diagnostics record
`baitProfitTracked`, `baitProfitPending`, `baitUnitCost`, `baitNormalPrice`,
`baitProfitPostAdjustment`, `baitProfitSaleAdjustment` and, when applicable,
`baitProfitIgnoredAfterReset`. Purchase entries retain their original estimate;
the running total includes the separate bait adjustments.

## Auto-Bait (Multi)

The **Bait now** button (next to STOP) posts one bait immediately: a random watched
commodity with bag stock and a learned normal price, at Bait price % of that normal
price. It works with or without watching and ignores the quiet-market rule; while
watching it still skips items with an own listing in the latest scan. A click is
the hardware event; if the AH is busy the first click reserves the slot and the
next click posts (or confirms). A confirmed bait flashes the border blue.

In the favorites list, items you have bought show a percentage between the
bought/missed counts and the estimated profit: the average price paid per unit
since Purchases Reset (green at or below the normal price shown on that row, red
above). It refreshes with the profit figure every five seconds.

A bait you post yourself (confirmed listing) flashes the panel border blue for
0.45 seconds, like the green and red purchase results.

The **Max buy %** field (learning row, "of normal") is the one percentage used by
Start learning and by **Limit live**, which now sits in the budget row. Live
updates set every watched item's max buy price to this percentage of its normal
price, replacing older per-item percentages. The Auto-Bait warning compares each
item's current max buy price with the bait price and names up to four items in
the Bait price tooltip.

The **Auto-Bait** checkbox (row below the options) posts one bait of a random
watched commodity from your bags while watching. **per min** sets the rate
(1-10, default 10 is also the maximum) and **Price %** the bait price as a
percentage of the item's learned normal price (default 100; whole silver when the
client requires it). Items without a learned price, without sellable stock, or
with an own listing in the latest scan are skipped, so at most one own bait per
item is up. The same item is not baited twice within 20 seconds.

Posting needs a real wheel step, never a timer, and the first step may only
reserve the AH slot (the status line then says to scroll once more). Buying always
has priority: nothing is posted while an offer is buyable or a purchase runs.

A bait is only posted in a **quiet market**: no item is under its buy limit and no
enabled item is more than 15% below its normal price (a sign of foreign bait).
After any non-quiet scan a random settle time must pass (two scan intervals plus
the median reply time, plus one to five more scan intervals), so several users do
not bait at the same moment and can see each other's baits first. The interval
between baits is also randomized (60% to 140%) and stretched when the median
browse reply time exceeds 250 ms; above 600 ms nothing is posted. The panel shows
the baits actually posted in the last minute and why it is waiting
("market active", "settling", "waiting", "latency too high"). The real rate can
stay below the setting because of AH throttling and the quiet-market rule.
Posts are logged in `postDiagnostics` with `autoBait` and `autoBaitPercent`.

## BuyWheelM layout

Next to the current price, a large percentage shows that price as a share of the
item's learned normal price (80% means 20% below normal). It is green while the
price is within the max buy price and red above it. The green purchase pop-up
shows the average price paid the same way ("80% of normal price").

The right column follows the order of use: learning (Max buy %, Limit live, Start
learning), the shared budget in whole gold, the options (Leave
Bait, depth queries per minute; Buy Bait is removed here and Volume Trading is always on), the selected item with its max buy price and
learned normal price, then a compact statistics block, the status line and
Start watching / STOP. The statistics lead with the larger Est. profit line
(with gold/hour); items/min, spending, budget left and
Bought/Missed follow as small grey lines. A saved budget with silver or copper is
shown as its whole-gold part and keeps that value until the field is edited.

## Bait filtering and live limits (Multi)

Learning sessions now use the same filters as live sampling: rows containing own
or account listings and rows with a total quantity of one are ignored. An item
whose lowest price is permanently your own listing therefore gets too few samples
and keeps its old limit. Live sampling also holds back a sample more than 35%
below the rolling median (typical of foreign bait) until it persists for more
than six consecutive 5-second samples, so real price drops are still followed.

The **Limit live** checkbox (off by default, change only while stopped) lets each
live normal-price update also set the item's max buy price to the same percentage
of it. The percentage is the item's own learned percent, otherwise the Buy %
field. A manually entered limit is overwritten by the next live update while the
option is on. The raw median can still be influenced by sustained bait.

## Live normal prices while watching in Multi

The Multi favorites price column displays the item's learned normal price,
including fractional copper medians; an unknown price is shown as a dash. A
missing buy limit no longer replaces that reference with "Set limit". The row
color and tooltip still identify an enabled item with no buy limit. Clicking an
item continues to load its independently editable buy limit on the right.

Normal watching also consumes its existing complete batch replies to maintain a
rolling normal-price estimate for enabled watched items. Each item accepts at
most one positive-price observation every five seconds, from replies with more
than one listed unit and no known owner/account listings. A rolling ten-minute
window holds up to 120 observations. At least ten valid observations are needed
before its median updates or creates the saved normal-price record. The last
learned price stays available during warmup or a gap in eligible observations.

No extra AH queries or timers are created. Only items appearing in the existing
watch queries can update; unchecked favorites keep their saved references until
observed in a learning session or watched again. This is still a median of low
listing prices, not realized sale prices; persistent foreign bait can influence
it despite the filtering and median. Live sampling pauses outside normal watching
and during explicit learning/benchmarking.

The live label marks rolling estimates. Live changes update only the reference
price and sample metadata. Without **Limit live** (above) they never recalculate
buy limits or their configured percentage. A completed explicit learning run still applies its selected buy
percentage, and clears older live samples for the items it updates. Raw rolling
samples live only in memory; the last published normal price is saved. New
purchases use the refreshed price; existing purchase/stock profit snapshots do
not change retroactively.

## Normal price from market depth (Multi)

The lowest listed price is fragile: a thin bait level pulls it down and your own
purchases push it up. The learned normal price therefore rests on the **depth
price**: the price at which the first 10% of the loaded supply (at least 20
units) is reached, without your own listings. A thin bait level cannot move it
and your own purchases barely do.

Depth samples come from:

- **Start learning:** between two minimum-price samples the run sends a burst
  of depth probes (detail queries, up to eight, sent as soon as the AH is
  ready). Every commodity needs six probes and ten minimum-price samples; the
  progress shows how much of that is done. The median depth price becomes the
  normal price (at least three probes), otherwise the median minimum price stays.
  Runs take a few minutes, depending on the number of favorites and the AH
  latency.
- **Free samples:** listings that are loaded anyway (before a purchase) and
  SellWheel's price levels, at most one per item and minute.
- **Depth queries per minute** (field "Depth/min" next to Leave Bait, default 1,
  0 = off): while watching, the watched commodity with the oldest depth sample
  gets a detail query, one every 60/rate seconds. Never while a purchase, bait,
  post or offer is pending. One query costs about one scan cycle.

Between depth samples the live minimum price moves the value: normal = median
minimum price x ratio, where ratio = depth price / median minimum price measured
together, limited to 0.7x-1.4x of the depth price. Depth samples count for 90
minutes; without them the value falls back to the median minimum price.

Right after your own buy or bait of an item (30 seconds) that item's minimum
price is not sampled, because your action changed it.

The panel shows how reliable each value is, by color. In the favorites list (and
for the selected item's learned normal price): **grey/white** = fine (depth based and
recent), **yellow** = be careful (only the minimum price was measured, or the live
minimum left the allowed range and waits for the next depth sample), **red** = old
(no measurement for 10 minutes while watching, or for 6 hours when idle). The
tooltip of a favorite spells it out ("Depth · 3 min", "rough · 12 min",
"Market moving", "old · 25 min").

## Live profit, bait announcements and bait timer

- **Est. profit** is shown live: it changes the moment a purchase is confirmed
  or a bait sale is credited. Only the rates and **g/h** are paced (every 5
  seconds). Gold per hour is shown with two decimals.
- **Bait announcement:** every successful bait (Auto-Bait, the Bait button, Bait
  now) writes one chat line, for example `BuyWheel Bait (Auto): Silverleaf ·
  42c · 50% of normal price`, so you can compare baits with others. The panel
  shows the latest one on the right of the detail line ("Bait <item> <price>").
- **Bait timer:** the Auto-Bait status at the right edge counts down the seconds
  until the next bait is allowed (settle time plus the rate interval): "Bait
  2/min · next in 7 s". While the market is active the timer is paused ("market
  active · paused"); "ready" means the next mouse wheel step can post.

## Reset learned (Multi)

**Reset learned** (bottom left, next to Help) deletes all learned normal prices,
depth measurements and live buffers, and sets the buy limits that came from them
to zero, after a confirmation. Watch checkboxes stay. Items without a positive
buy limit are not watched, so run **Start Learning Prices** before watching again;
that run is then the only data in use. It is not possible while watching or
learning.
