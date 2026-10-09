-- lean_ui/init.lua
--
-- Custom inventory UI for Lean Core.

local S = minetest.get_translator("lean_ui")
local HAS_ARMOR = minetest.get_modpath("3d_armor") ~= nil
local after = minetest.after

local function build_inventory_formspec(player)
	local name = player:get_player_name()
	local p = {}

	-----------------------------------------------------------
	-- РОЗМІР ВІКНА
	-- Перше число = ширина, друге = висота
	-----------------------------------------------------------
	p[#p+1] = "formspec_version[4]"
	p[#p+1] = "size[11.7,11]"

	-----------------------------------------------------------
	-- КНОПКА "RECIPES"
	-- формат: button[X, Y; ширина, висота; ім'я; підпис]
	-- X - відступ зліва, Y - відступ зверху
	-----------------------------------------------------------
	p[#p+1] = "button[9.8,0.3;1.5,0.7;lean_ui_recipes;" .. S("Recipes") .. "]"

	-----------------------------------------------------------
	-- СЛОТИ БРОНІ (тільки якщо встановлено 3d_armor)
	-- формат: list[detached:ГРАВЕЦЬ_armor;armor;X, Y; ширина, висота;]
	-----------------------------------------------------------
	if HAS_ARMOR then
		p[#p+1] = "list[detached:" .. name .. "_armor;armor;1.0,1.5;2,3;]"
	end

	-----------------------------------------------------------
	-- КРАФТ 3x3
	-- X=3, Y=1.5 - де починається сітка крафту
	-----------------------------------------------------------
	p[#p+1] = "list[current_player;craft;4.7,1.5;3,3;]"

	-----------------------------------------------------------
	-- СТРІЛКА (маленька картинка між крафтом і результатом)
	-- X=6, Y=2.5 - має бути правіше крафту (3 + 3 = 6)
	-----------------------------------------------------------
	p[#p+1] = "image[8.6,2.5;1,1;gui_furnace_arrow_bg.png^[transformR270]"

	-----------------------------------------------------------
	-- РЕЗУЛЬТАТ КРАФТУ (прев'ю)
	-- X=7, Y=2.5 - має бути правіше стрілки (6 + 1 = 7)
	-----------------------------------------------------------
	p[#p+1] = "list[current_player;craftpreview;9.8,2.5;1,1;]"

	-----------------------------------------------------------
	-- ГОЛОВНИЙ ІНВЕНТАР ГРАВЦЯ (4 ряди: hotbar + 3)
	-- Перший рядок: X=1, Y=5.5 - 8 слотів
	-- Другий блок: X=1, Y=6.75 - 3 ряди по 8
	-----------------------------------------------------------
	p[#p+1] = "list[current_player;main;1,5.5;8,1;]"
	p[#p+1] = "list[current_player;main;1,6.75;8,3;8]"
	p[#p+1] = "listring[current_player;main]"
	p[#p+1] = "listring[current_player;craft]"


	return table.concat(p)
end

local function apply_inventory(player)
	player:set_inventory_formspec(build_inventory_formspec(player))
end

dofile(minetest.get_modpath("lean_ui") .. "/recipes.lua")

minetest.register_on_joinplayer(function(player)
	after(0.2, function()
		if player and player:is_player() then
			apply_inventory(player)
		end
	end)
end)

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if fields.lean_ui_recipes and lean_ui_recipes then
		lean_ui_recipes.show_main(player, "", "")
		return true
	end
end)

lean_ui = {
	has_armor = HAS_ARMOR,
	apply_inventory = apply_inventory,
	build_inventory_formspec = build_inventory_formspec,
}