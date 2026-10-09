-- lean_ui/recipes.lua
-- Recipe encyclopedia with search, category dropdown and pagination.
--
-- PERFORMANCE:
--   * Index built ONCE at mods_loaded.
--   * Per-category lists pre-sorted, so filtering is O(category_size).
--   * Lowercase name/desc cached, no repeated :lower() calls.
--   * When no search term is given, returns the cached list directly.

local S = minetest.get_translator("lean_ui")

lean_ui_recipes = {}

-- ============================================================
-- КОНСТАНТИ
-- ============================================================
local RESULTS_PER_PAGE = 36
local COLS = 9
local CELL = 1.2
local CELL_STEP = 1.25

-- ============================================================
-- Сховища (будуються один раз при старті)
-- ============================================================
local recipes_by_output = {}    -- [name] = {recipe, ...}
local item_category = {}        -- [name] = "Tools" / "Armor" / ...
local sorted_categories = {}    -- ordered list of category names
local items_by_category = {}    -- [category] = sorted list of item names
local all_recipe_names = {}     -- sorted list of ALL item names
local desc_cache = {}           -- [name] = {lc_name, lc_desc}

-- Стан перегляду для кожного гравця
local view_state = {}

local registered_items = minetest.registered_items
local show_formspec = minetest.show_formspec
local formspec_escape = minetest.formspec_escape

-- ============================================================
-- Класифікація предметів
-- ============================================================
local function detect_category(name, def)
	local g = def.groups or {}
	local mod = name:match("^([^:]+):") or ""

	if g.armor or g.armor_head or g.armor_torso or
			g.armor_legs or g.armor_feet or g.armor_shield then
		return "Armor"
	end

	if mod == "default" then
		if g.pickaxe or g.axe or g.shovel or g.sword then
			return "Tools"
		end
		if def.light_source and def.light_source > 0 then
			return "Light"
		end
		if name:find(":stone_with_") or name:find("_lump") or
				name:find("_ingot") or name:find("_crystal") or
				name == "default:mese" or
				name:find("coalblock") or name:find("steelblock") or
				name:find("copperblock") or name:find("tinblock") or
				name:find("goldblock") or name:find("diamondblock") or
				name:find("bronzeblock") then
			return "Ores"
		end
		if g.food or g.eat then
			return "Food"
		end
		if name:find("chest") or name:find("furnace") or
				name:find("bookshelf") then
			return "Crafting"
		end
		return "Building"
	end

	return "Mod: " .. mod
end

-- ============================================================
-- Побудова індексу (один раз при старті)
-- ============================================================
minetest.register_on_mods_loaded(function()
	local t0 = minetest.get_us_time()

	-- Валідація рецепта
	local function recipe_is_valid(recipe)
		for _, item in ipairs(recipe.items or {}) do
			if item and item ~= "" then
				if item:sub(1, 6) ~= "group:" then
					if not registered_items[item] then
						return false
					end
				end
			end
		end
		for _, rep in ipairs(recipe.replacements or {}) do
			local rname = type(rep) == "table" and rep[1] or rep
			if rname and rname ~= "" and not registered_items[rname] then
				return false
			end
		end
		return true
	end

	-- 1. Збираємо валідні рецепти
	for name in pairs(registered_items) do
		local rec = minetest.get_all_craft_recipes(name)
		if rec and #rec > 0 then
			local valid = {}
			for _, r in ipairs(rec) do
				if recipe_is_valid(r) then
					valid[#valid+1] = r
				end
			end
			if #valid > 0 then
				recipes_by_output[name] = valid
			end
		end
	end

	-- 2. Призначаємо категорії + кешуємо lowercase для пошуку
	for name, def in pairs(registered_items) do
		if recipes_by_output[name] then
			local cat = detect_category(name, def)
			item_category[name] = cat
			desc_cache[name] = {
				lc_name = name:lower(),
				lc_desc = ((def and def.description) or ""):lower(),
			}
		end
	end

	-- 3. Групуємо по категоріях
	for name, cat in pairs(item_category) do
		local bucket = items_by_category[cat]
		if not bucket then
			bucket = {}
			items_by_category[cat] = bucket
		end
		bucket[#bucket+1] = name
	end

	-- 4. Сортуємо кожну категорію + загальний список
	for _, bucket in pairs(items_by_category) do
		table.sort(bucket)
	end
	for name in pairs(item_category) do
		all_recipe_names[#all_recipe_names+1] = name
	end
	table.sort(all_recipe_names)

	-- 5. Порядок категорій
	local priority = {
		"Tools", "Armor", "Light", "Ores", "Food",
		"Crafting", "Building",
	}
	local seen = {}
	for _, cat in ipairs(priority) do
		if items_by_category[cat] then
			sorted_categories[#sorted_categories+1] = cat
			seen[cat] = true
		end
	end
	local mod_cats = {}
	for c in pairs(items_by_category) do
		if not seen[c] then
			mod_cats[#mod_cats+1] = c
		end
	end
	table.sort(mod_cats)
	for _, c in ipairs(mod_cats) do
		sorted_categories[#sorted_categories+1] = c
	end

	local n = #all_recipe_names
	local dt = (minetest.get_us_time() - t0) / 1000
	minetest.log("action", "[lean_ui] Indexed " .. n ..
		" craftable items in " .. #sorted_categories ..
		" categories in " .. string.format("%.1f", dt) .. " ms")
end)

-- ============================================================
-- Групи → представник
-- ============================================================
local group_cache = {}
local function group_rep(group_name)
	if group_cache[group_name] then return group_cache[group_name] end
	local g = group_name:sub(7)
	local found = "unknown"
	for name, def in pairs(registered_items) do
		if def.groups and def.groups[g] and def.groups[g] ~= 0 then
			found = name
			break
		end
	end
	group_cache[group_name] = found
	return found
end

local function ingredient_item(s)
	if not s or s == "" then return nil end
	if s:sub(1, 6) == "group:" then return group_rep(s) end
	return s
end

-- ============================================================
-- Фільтр (оптимізований)
-- ============================================================
-- Повертає масив імен. Якщо пошук порожній — повертає кешований
-- список категорії (не копію, а пряме посилання).
local function filter_recipes(search, category)
	-- Вибір джерела
	local source
	if category and category ~= "" then
		source = items_by_category[category] or {}
	else
		source = all_recipe_names
	end

	-- Без пошуку — повертаємо як є (вже відсортовано)
	if not search or search == "" then
		return source
	end

	-- З пошуком — фільтруємо
	local search_lower = search:lower()
	local found = {}
	for i = 1, #source do
		local name = source[i]
		local cache = desc_cache[name]
		if cache then
			if cache.lc_name:find(search_lower, 1, true) or
					cache.lc_desc:find(search_lower, 1, true) then
				found[#found+1] = name
			end
		end
	end
	return found
end

-- ============================================================
-- Головне вікно
-- ============================================================
function lean_ui_recipes.build_main(search, category, page)
	page = page or 1
	local p = {}
	p[#p+1] = "formspec_version[4]"
	p[#p+1] = "size[12.5,11]"
	p[#p+1] = "label[5.0,0.5;" .. S("Recipe Book") .. "]"
	p[#p+1] = "field[0.5,1.4;7,0.7;search;" .. S("Search recipes...") .. ";" ..
		formspec_escape(search or "") .. "]"
	p[#p+1] = "button[7.6,1.4;1.4,0.7;search_btn;" .. S("Search") .. "]"
	p[#p+1] = "button[11.5,0.3;0.8,0.7;close_btn;X]"

	p[#p+1] = "label[0.5,2.65;" .. S("Category:") .. "]"
	local cat_list = "All"
	for _, c in ipairs(sorted_categories) do
		cat_list = cat_list .. "," .. c
	end
	local selected_idx = 1
	if category and category ~= "" then
		for i, c in ipairs(sorted_categories) do
			if c == category then
				selected_idx = i + 1
				break
			end
		end
	end
	p[#p+1] = "dropdown[2,2.35;5,0.7;cat_dropdown;" .. cat_list ..
		";" .. selected_idx .. ";cat_changed]"

	local found = filter_recipes(search, category)
	local total = #found
	local total_pages = math.max(1, math.ceil(total / RESULTS_PER_PAGE))
	if page > total_pages then page = total_pages end
	if page < 1 then page = 1 end

	local label_text
	if category and category ~= "" then
		label_text = S("Category:") .. " " .. category
	else
		label_text = S("All recipes")
	end
	if total == 0 then
		label_text = label_text .. "  (0 / 0)"
	else
		local from_idx = (page - 1) * RESULTS_PER_PAGE + 1
		local to_idx = math.min(page * RESULTS_PER_PAGE, total)
		label_text = label_text .. "  (" .. from_idx .. "-" .. to_idx ..
			" / " .. total .. ")"
	end
	p[#p+1] = "label[0.5,3.35;" .. formspec_escape(label_text) .. "]"

	local grid_y = 3.85
	if total == 0 then
		p[#p+1] = "label[0.5," .. grid_y .. ";" .. S("No recipes found.") .. "]"
	else
		local first = (page - 1) * RESULTS_PER_PAGE + 1
		local last = math.min(page * RESULTS_PER_PAGE, total)
		for i = first, last do
			local name = found[i]
			local slot = i - first
			local col = slot % COLS
			local row = math.floor(slot / COLS)
			local ix = 0.5 + col * CELL_STEP
			local iy = grid_y + row * CELL_STEP
			p[#p+1] = "item_image_button[" .. ix .. "," .. iy ..
				";" .. CELL .. "," .. CELL .. ";" .. name ..
				";ri_" .. name .. ";]"
		end
	end

	if total_pages > 1 then
		local py = 9.4
		if page > 1 then
			p[#p+1] = "button[3.5," .. py .. ";1,0.7;page_" ..
				(page - 1) .. ";<]"
		end
		p[#p+1] = "label[4.7," .. (py + 0.2) .. ";" ..
			S("Page @1 of @2", page, total_pages) .. "]"
		if page < total_pages then
			p[#p+1] = "button[6.8," .. py .. ";1,0.7;page_" ..
				(page + 1) .. ";>]"
		end
	end

	p[#p+1] = "button[0.5,10.2;2.5,0.6;back_inv;" ..
		S("Back to inventory") .. "]"
	return table.concat(p)
end

-- ============================================================
-- Перегляд рецепту
-- ============================================================
function lean_ui_recipes.build_recipe_view(item_name)
	local recipes = recipes_by_output[item_name]
	local def = registered_items[item_name]
	local desc = (def and def.description) or item_name
	local p = {}
	p[#p+1] = "formspec_version[4]"
	p[#p+1] = "size[12,10]"
	p[#p+1] = "label[4.0,1.3;" .. S("Recipe for:") .. " " ..
		formspec_escape(desc) .. "]"

	if not recipes or #recipes == 0 then
		p[#p+1] = "label[4.0,2.5;" .. S("No recipe available.") .. "]"
		p[#p+1] = "button[0.5,9.2;2.5,0.6;back_list;" .. S("Back") .. "]"
		return table.concat(p)
	end

	local recipe = recipes[1]
	local method = recipe.method or "normal"

	if method == "cooking" then
		local input = (recipe.items or {})[1]
		local img = ingredient_item(input) or "unknown"
		local ing_def = registered_items[img]
		local ing_desc = (ing_def and ing_def.description) or img
		local res_def = registered_items[item_name]
		local res_desc = (res_def and res_def.description) or item_name
		p[#p+1] = "item_image_button[3,4;1.5,1.5;" .. img ..
			";ing_in;]"
		p[#p+1] = "tooltip[ing_in;" .. formspec_escape(ing_desc) .. "]"
		p[#p+1] = "image[5,4.3;1.5,1;gui_furnace_arrow_bg.png^[transformR270]"
		p[#p+1] = "item_image_button[7,4;1.5,1.5;" .. item_name ..
			";result_smelt;]"
		p[#p+1] = "tooltip[result_smelt;" .. formspec_escape(res_desc) .. "]"
		p[#p+1] = "label[3,6;" .. S("Smelting") .. "]"
	else
		local w = recipe.width or 3
		local items = recipe.items or {}
		local gx, gy = 3.5, 3
		local cell = 1.2
		local step = cell + 0.05

		for cx = 0, 2 do
			for cy = 0, 2 do
				local px = gx + cx * step
				local py = gy + cy * step
				p[#p+1] = "box[" .. px .. "," .. py .. ";" ..
					cell .. "," .. cell .. ";#2a2a2a]"
			end
		end

		for i = 1, 9 do
			local item = items[i]
			if item and item ~= "" then
				local img = ingredient_item(item)
				if img then
					local cx = (i - 1) % w
					local cy = math.floor((i - 1) / w)
					local px = gx + cx * step
					local py = gy + cy * step
					local ing_def = registered_items[img]
					local ing_desc = (ing_def and ing_def.description)
						or img
					local btn_name = "ing_" .. i
					p[#p+1] = "item_image_button[" .. px .. "," .. py ..
						";" .. cell .. "," .. cell .. ";" .. img ..
						";" .. btn_name .. ";]"
					p[#p+1] = "tooltip[" .. btn_name .. ";" ..
						formspec_escape(ing_desc) .. "]"
				end
			end
		end

		local ax = gx + 3 * step + 0.4
		local ay = gy + cell
		p[#p+1] = "image[" .. ax .. "," .. ay ..
			";1.5,1.2;gui_furnace_arrow_bg.png^[transformR270]"
		local res_def = registered_items[item_name]
		local res_desc = (res_def and res_def.description) or item_name
		p[#p+1] = "item_image_button[" .. (ax + 1.8) .. "," .. ay ..
			";1.2,1.2;" .. item_name .. ";result;]"
		p[#p+1] = "tooltip[result;" ..
			formspec_escape(res_desc) .. "]"
	end

	p[#p+1] = "button[0.5,9.2;2.5,0.6;back_list;" .. S("Back") .. "]"
	return table.concat(p)
end

-- ============================================================
-- Показ вікон
-- ============================================================
function lean_ui_recipes.show_main(player, search, category, page)
	local pname = player:get_player_name()
	view_state[pname] = {search = search, category = category, page = page or 1}
	show_formspec(pname, "lean_ui:recipes",
		lean_ui_recipes.build_main(search, category, page))
end

function lean_ui_recipes.show_recipe(player, item_name)
	show_formspec(player:get_player_name(), "lean_ui:recipes",
		lean_ui_recipes.build_recipe_view(item_name))
end

-- ============================================================
-- Обробка кліків
-- ============================================================
local function resolve_category(raw)
	if raw == nil then return "" end
	raw = tostring(raw)
	if raw == "" or raw == "All" or raw == "1" then return "" end
	for _, c in ipairs(sorted_categories) do
		if c == raw then return c end
	end
	local num = tonumber(raw)
	if num and num > 1 then
		return sorted_categories[num - 1] or ""
	end
	return ""
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "lean_ui:recipes" then return end
	local pname = player:get_player_name()

	if fields.close_btn then
		minetest.close_formspec(pname, "lean_ui:recipes")
		return true
	end

	if fields.back_inv then
		local inv_fs = lean_ui.build_inventory_formspec(player)
		player:set_inventory_formspec(inv_fs)
		show_formspec(pname, "", inv_fs)
		return true
	end

	if fields.back_list then
		local st = view_state[pname] or {}
		lean_ui_recipes.show_main(player, st.search or "",
			st.category or "", st.page or 1)
		return true
	end

	for k in pairs(fields) do
		if k:sub(1, 3) == "ri_" then
			lean_ui_recipes.show_recipe(player, k:sub(4))
			return true
		end
	end

	for k in pairs(fields) do
		local pg = k:match("^page_(%d+)$")
		if pg then
			local cat = resolve_category(fields.cat_dropdown)
			lean_ui_recipes.show_main(player, fields.search or "", cat,
				tonumber(pg))
			return true
		end
	end

	if fields.search_btn or fields.key_enter_field == "search" then
		local cat = resolve_category(fields.cat_dropdown)
		lean_ui_recipes.show_main(player, fields.search or "", cat, 1)
		return true
	end

	if fields.cat_changed or fields.cat_dropdown then
		local raw = fields.cat_changed or fields.cat_dropdown
		local cat = resolve_category(raw)
		lean_ui_recipes.show_main(player, fields.search or "", cat, 1)
		return true
	end

	return false
end)

-- Очищення стану, коли гравець виходить
minetest.register_on_leaveplayer(function(player)
	view_state[player:get_player_name()] = nil
end)