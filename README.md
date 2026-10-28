# Balatro Run Stats

A Balatro mod by **andrewleeog** for tracking the current run, with summaries, charts, card usage, and probability hit rates.

## Installation

Requires [Lovely](https://github.com/ethangreen-dev/lovely-injector) and [Steamodded](https://github.com/Steamodded/smods).

1. Download or clone this repository.
2. Place the repository's contents in a `BalatroRunStats` folder inside your Balatro `Mods` directory. `manifest.json`, `BalatroRunStats.lua`, and `lovely/` should be directly inside that folder.
3. Restart Balatro.

Open **Run Stats** from the pause menu or the win/game-over screen. After viewing a completed run, Back returns to the result screen.

## Pages

- **Summary:** records, run totals, purchases, all five booster pack families, and average/median hand scores.
- **Trends:** scoring versus blind targets, hands needed to win, earnings/spending, shop cash reserves, poker hands, and consumable use. Switch **View: Overview** to **Analysis** for score consistency and spending categories.
- **Prob:** observed hits/rolls alongside current listed probabilities. Listed probabilities reflect Oops! All Sixes and use the same calculation as card tooltips.
- **Cards:** rank/suit charts with Played, Discarded, Drawn, and Use rate modes.

The shared ante selector offers played antes, skips gaps, and supports endless runs beyond ante 8. Select **All** to show the whole run. An asterisk marks an ante in progress or partial score history.

## Tracking behavior

Stats are saved with the run. The mod does not keep a separate archive after you leave the result screen or start another run.

New metrics begin recording when the relevant mod version is installed. Missing historical data is not reconstructed. Unclassified spending and older pack totals appear under **Other / Earlier**.

**Use rate** measures the share of tracked deck-to-hand draws that were later played at least once. Replaying a card without drawing it again does not increase that rate. A new draw of the same card counts as a new opportunity. Blank bars mean there were no tracked draws for that rank/suit.

## Development checks

Requires LuaJIT, Python 3.11+, and a Steamodded source checkout. Run commands from this repository's root:

```sh
SMODS_DIR=/path/to/smods luajit tests/dashboard.lua
SMODS_DIR=/path/to/smods python3 tests/check_patches.py
```

`SMODS_DIR` defaults to `../smods-stable`. Tests use Steamodded's probability helper to check behavior against its tooltip calculation.

The patch checks also validate and compile game sources when available:

- `BALATRO_GAME_SRC`: extracted sources from your own Balatro installation; defaults to `../game-src`.
- `BALATRO_MODS_DIR`: your Balatro Mods directory, used to find `lovely/dump`. Defaults to the standard Linux Steam/Proton location.

Game sources and loader dependencies are not included in this repository.
