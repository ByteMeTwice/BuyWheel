# Changelog

Newest first. Every update is pushed to GitHub with an entry here.

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
