# Lean UI

A lightweight custom inventory UI for Luanti with armor slots and a
searchable recipe encyclopedia.

## What it is

Lean UI replaces the default inventory window with a custom one that
adds:

- **Armor slots** (only shown if `3d_armor` is installed)
- **Recipe Book button** that opens a searchable recipe encyclopedia
- **Category browsing** (Tools, Armor, Light, Ores, Food, Crafting, Building)
- **Pagination** for large recipe lists
- **Tooltips** on all ingredients and results
- **Ukrainian and English localization**

## Features

### Custom inventory
- Clean layout with craft grid, main inventory and hotbar
- Armor slots appear automatically when `3d_armor` is detected
- Falls back gracefully if `3d_armor` is not installed

### Recipe Book
- Search recipes by name or description
- Filter by category using a dropdown
- Page through results (36 per page)
- View ingredient layout for each recipe
- Hover tooltips show item descriptions
- Filters and page number are preserved when returning from a recipe

### Performance
- Recipe index is built **once** at server startup
- Per-category lists are pre-sorted — switching categories is instant
- Lowercase name/description cached — no repeated string conversion
- No `globalstep`, no per-frame work
- Suitable for servers with thousands of recipes

Tested with 234 recipes on a live server: index builds in ~5 ms.

## Requirements

- Luanti (Minetest) 5.8 or later
- `default` mod (usually part of the game)

**Optional:**
- `3d_armor` — enables armor slots in the inventory

## Installation

1. Download the archive from the Releases section.
2. Extract the `lean_ui` folder into your game's `mods` directory:
   - `games/<your_game>/mods/lean_ui/`
3. Restart Luanti.

If you use a `mods/` folder at the world level, place it there instead.

## Usage

- Press `i` to open the inventory.
- Click **Recipes** to open the Recipe Book.
- Use the search field or category dropdown to find what you need.
- Click any item to see its recipe.
- Press **Back** to return to the recipe list (keeps your filters).
- Press **Back to inventory** or **X** to close.

## Localization

The mod includes Ukrainian (`uk`) and English (built-in) translations.

To add another language, create
`lean_ui/locale/lean_ui.<lang>.tr` with this format:

```
# textdomain: lean_ui
Recipe Book=...
Recipes=...
```

See `locale/lean_ui.uk.tr` for the full list of translatable strings.

## Configuration

Constants at the top of `recipes.lua` can be tweaked:

| Constant | Default | Meaning |
|---|---|---|
| `RESULTS_PER_PAGE` | 36 | Items per page in Recipe Book |
| `COLS` | 9 | Columns in the result grid |
| `CELL` | 1.2 | Size of each item icon |
| `CELL_STEP` | 1.25 | Spacing between icons |

Inventory layout coordinates are inside `init.lua` in
`build_inventory_formspec()`.

## License

This mod is licensed under the **GNU General Public License v3.0**
(GPL-3.0-only) — version 3.0 only, not "or later".

You are free to use, modify and redistribute this mod, including on
commercial servers, **as long as any derivative work is also released
under GPL-3.0-only**. Closed-source forks are not permitted.

See the `LICENSE` file for the full license text.

## Author

8a7l