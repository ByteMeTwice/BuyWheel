# BuyWheel

**Auction house tools for WoW Classic *Forever*:** buy cheap listings with the mouse wheel, let the addon learn what an item is really worth, and sell with a clear price list.

[Install and update](#install-and-update) · [Quick start](#quick-start) · [How it works](#how-it-works) · [Full reference](docs/REFERENCE.md) · [Changelog](CHANGELOG.md)

---

## Install and update

**The easy way (Windows): one file, no download of the addon**

1. Download **[UpdateBuyWheel.bat](https://raw.githubusercontent.com/ByteMeTwice/BuyWheel/main/UpdateBuyWheel.bat)**: right-click the link and choose *Save link as...*.
2. Double-click the file. If Windows shows a blue "Windows protected your PC" window, click *More info* and then *Run anyway*.
3. The file finds your World of Warcraft folder, downloads the newest BuyWheel from GitHub and installs it (the old `AddOns\BuyWheel` folder is replaced). Your saved data (learned prices, settings) is not touched.
4. Start the game, or type `/reload` if it is already running.

To update later, run **the same file again**. If it cannot find the AddOns folder, it asks you once to paste the folder path (`...\World of Warcraft\_forever_\Interface\AddOns`) and remembers it.

**Manually**

1. [Download the ZIP](https://github.com/ByteMeTwice/BuyWheel/archive/refs/heads/main.zip), unzip it and rename the folder `BuyWheel-main` to **`BuyWheel`**.
2. Put it into your AddOns directory, so that `BuyWheel.toc` sits directly inside `World of Warcraft\_forever_\Interface\AddOns\BuyWheel`.
3. Start the game (or `/reload`). To update, replace the folder with a new download. With Git, `git pull` inside the folder is enough.

## Three tabs, one addon

| Tab | Short | What it is for |
|---|---|---|
| **BuyWheelS** | BWS | Watch **one** item, set a maximum price and a budget, scroll to buy. Manual bait posting. |
| **BuyWheelM** | BWM | Watch **many** favorites at once. Learned normal prices, per-item limits, always-on Volume Trading, Auto-Bait, live profit. |
| **SellWheel** | SW | See the whole market as a price list and sell in two stages (cheapest / 25% level, default 50/50). |

## Highlights

- **Real clicks only.** Buying and posting happen on a mouse-wheel step or a click, never on a timer. The addon respects the AH throttle and never sends more than the AH allows.
- **Learned normal prices from market depth.** Not just "the lowest price right now", but the price where the first 10% of the supply is reached. Thin bait listings and your own purchases barely move it.
- **Color-coded trust.** In the favorites list the learned price is grey when reliable, yellow when you should be careful and red when it is old.
- **Max buy %.** One percentage of the normal price sets every item's buy limit, optionally kept live while you watch.
- **Auto-Bait and manual bait** with a countdown to the next bait, a chat line for every bait and a "last bait" display.
- **Bait fingerprint.** Baits are posted at prices that other BuyWheel users recognize; their offers show in violet in the SellWheel table.
- **Profit at a glance.** Estimated profit updates the moment a purchase or bait sale is confirmed, with gold per hour.
- **SellWheel like the Auctionator selling tab.** An icon grid of your bags on the left; on the right the item, quantity, duration, two colored price strips (green = cheapest, blue = 25% level, default 50/50) and a scrolling table of the market offers with your two prices highlighted. One click sells the first stage, the mouse wheel does the rest.

## Quick start

**Buying with BuyWheelM**

1. Mark the commodities you want as **favorites** in the normal auction house.
2. Open **BWM**, set **Max buy %** (for example 70) and press **Start learning**. The button shows the progress in percent and the run ends by itself.
3. Check the items you want to watch, set a **Shared budget** and press **Start watching**.
4. **Scroll** the mouse wheel. When something is under its limit, a scroll step buys it. A green border and a pop-up confirm each purchase.

**Selling with SellWheel**

1. Open **SW** and click an item in your bags. The market price list loads.
2. Look at the two highlighted prices, adjust the share if you like (default 50% cheapest, 50% at the 25% level) and press **Sell**. That posts the first stage.
3. Scroll the mouse wheel to post the rest (the option "Wheel" is on by default).

## How it works

- **Normal price.** The addon measures the market depth of every favorite (price where the first 10% of the supply, at least 20 units, is reached), ignoring your own listings. Between measurements the lowest price moves the value, within bounds. A value without a fresh measurement turns yellow, then red.
- **Buy limit.** Limit = normal price × Max buy %. Items under their limit are ranked by estimated profit per unit.
- **Bait.** A bait is a single listing at a low price that you post to attract buyers. Auto-Bait posts them when the market is quiet, at a rate and a price percentage you choose.
- **No guarantees.** Prices and profits are estimates before AH fees and deposits and do not promise a sale.

## Good to know

- Made for **WoW Classic Forever** (Interface 1.16). The auction house uses the commodity APIs; items that are not commodities are outside this version.
- Automating purchases may be restricted by your server's rules. Use it at your own responsibility.
- Documentation of every detail (rules, formulas, diagnostics, saved data) is in the [full reference](docs/REFERENCE.md). Debug data is described in [Single/DIAGNOSTICS.md](Single/DIAGNOSTICS.md).

## Development

The addon is plain Lua 5.1 without build step. The test scripts in `Tests/` run with a normal Lua 5.1 interpreter (`lua Tests/SellWheel.lua ./`) against a fake auction house; they do not need the game.

## License

Not specified yet.
