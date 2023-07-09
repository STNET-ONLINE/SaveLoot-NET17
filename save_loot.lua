destroy_objects = {}
destroy_objects["mp_ammo_9x18_fmj"] = true
destroy_objects["ammo_gravi"] = true
destroy_objects["wpn_rpg7"] = true

ignore_save_loot = {}
ignore_save_loot["bolt"]		 	 = true
ignore_save_loot["mp_wpn_knife"] 	 = true
ignore_save_loot["device_pda"]		 = true
ignore_save_loot["mp_device_torch"]  = true
ignore_save_loot["mp_wpn_binoc"] 	 = true
ignore_save_loot["wpn_addon_scope_none"] = true

ignore_save_loot["mp_ammo_9x18_fmj"] = true
ignore_save_loot["ammo_gravi"] = true

local need_save_loot = true
local passwords = {}
local death_count = {}
local authorization_time = {}
local authorization_count = {}
local max_authorization_count = 3
local packet = net_packet ()
local hard_key_two = {}
local not_kicked_person = {}
local player_by_name = {}
local max_player_money = {}

local spawn_loot_queue_process_size = 10
local deffered_iterate_inventory = {}
local not_destroy_item = {}

local is_zooombe = {}
local actual_team_leader = {}
local is_very_very_dead = {}

local agit_time_delta = 5 * 60 * 1000
local agit_time = time_global() + agit_time_delta

xrLua.TermenateProcess = function()
	error_log("Server was shut down.")
end

game_object.take_item = function (self, obj)
--	local P = net_packet ()
	u_EventGen (packet, 1, self:id())
	packet:w_u16 (obj:id())
	u_EventSend (packet)
--	self:transfer_item(obj, self)
end

game_object.destroy_object = function (self)
	u_EventGen (packet, 8, self:id())
	u_EventSend (packet)
end

game_object.set_actor_position = function (self, pos)
	u_EventGen (packet, 29, self:id())
	packet:w_vec3(pos)
	packet:w_vec3(self:direction())
	SendBroadcast (packet)
end

game_object.allow_sprint = function (self, allow_sprint)
	u_EventGen(packet, 47, self:id())
	packet:w_u8(allow_sprint and -1 or 1)
	SendBroadcast (packet)
end

function send_tip_server(text)
	for i = 0, 65535 do
		local obj = level.object_by_id(i)
		if obj and obj:section() == "mp_actor" then
			u_EventGen(packet, 107, i)
			packet:w_stringZ("st_tip")
			packet:w_stringZ(text)
			packet:w_stringZ("ui_inGame2_Vibros")
			u_EventSend(packet)
		end
	end
end

function send_to_user(text, user)
	if user then
		u_EventGen(packet, 107, user:id())
		packet:w_stringZ("st_tip")
		packet:w_stringZ(text)
		packet:w_stringZ("ui_inGame2_Polucheni_koordinaty_taynika")
		u_EventSend(packet)
	end
end

local log_packet = net_packet()
function log_test(text)
	if xrLua then
		xrLua.log("$ " .. text)
		return
	end
	get_console():execute("cfg_load ~" .. text)
end

function fix_no_alife_object(obj)
	if obj and alife() then
		local binder = obj:binded_object()
		local se_obj
		if binder and binder.is_ammo then
			se_obj = alife():create_ammo(obj:section(), db.actor:position(), db.actor:level_vertex_id(), db.actor:game_vertex_id(), -1, binder.ammo_cnt)
		else
			se_obj = alife():create(obj:section(), db.actor:position(), db.actor:level_vertex_id(), db.actor:game_vertex_id())
		end
		level.client_spawn_manager():add(se_obj.id, 0, spawn_callback, obj)
	end
end

--- Make a shallow copy of a table, including any metatable (for a
-- deep copy, use tree.clone).
-- @param t table
-- @param nometa if non-nil don't copy metatable
-- @return copy of table
function table.clone (t, nometa)
  local u = {}
  if not nometa then
    setmetatable (u, getmetatable (t))
  end
  for i, v in pairs (t) do
    u[i] = v
  end
  return u
end

--- Merge two tables.
-- If there are duplicate fields, u's will be used. The metatable of
-- the returned table is that of t.
-- @param t first table
-- @param u second table
-- @return merged table
function table.merge (t, u)
  local r = table.clone (t)
  for i, v in pairs (u) do
    r[i] = v
  end
  return r
end

function get_item_table(item)
	local sobj = alife():object(item:id())
	local tbl = get_object_data(sobj)
	local t = {}
	if not tbl or (tbl and not tbl.condition) then
		log_test("Why? " .. item:name())
		item:destroy_object()
		return nil
	end
	t.ammo_elapsed = tbl.ammo_elapsed
	-- t.ammo_current = tbl.ammo_current
	t.addon_flags = tbl.addon_flags
	t.condition = item:condition()
	t.ammo_type = tbl.ammo_type
	t.ammo_left = tbl.ammo_left
	t.section = item:section()
	return t
end

local last_tick = {}
local last_hit_tick = {}
local last_pos_tick = {}
local last_in_safe_zone = {}

local is_surge_real_started = false

function update_save_loot(obj)
	if not obj then
		return true
	end
	if authorization_time[obj:id()] then
		if authorization_time[obj:id()] < time_global() then 
			if authorization_count[obj:id()] == max_authorization_count then
				logf_test("[%s] error authorization!!!", obj:name())
				--cheak_ban_char(obj:name(), obj:name())
				return true
			end
			authorization_count[obj:id()] = authorization_count[obj:id()] + 1
			authorization_time[obj:id()] = time_global() + 5000
			obj:give_info_portion("need_check_autorize=" .. device().frame)
		end
		return false
	end
	if not hard_key_two[obj:id()] then
		logf_test("[%s] error hard key 2!!!", obj:name())
		--cheak_ban_char(obj:name(), obj:name())
		xrLua.KickPlayer(obj:id())
		not_kicked_person[obj:name()] = true
		return true
	end
	if is_very_very_dead[obj:id()] then
		save_player_loot_table(obj)
		return true
	end
	if not last_tick[obj:id()] then
		last_tick[obj:id()] = 0
	end
	if not last_hit_tick[obj:id()] then
		last_hit_tick[obj:id()] = 0
	end
	if not last_pos_tick[obj:id()] then
		last_pos_tick[obj:id()] = 0
	end
	if obj:alive() then
		local zone = db.zone_by_name["sr_surge"]
		if zone and not is_zooombe[obj:id()] then
			if is_surge_real_started and last_hit_tick[obj:id()] < time_global() then
				if not zone:inside(obj:position()) then
					local h = hit()
					h.draftsman = obj
					h.type = hit.radiation
					h.direction = vector():set(0, 1, 0)
					h.power = math.random(3, 20) * 0.01
					h.impulse = 1
					obj:hit(h)
				end
				last_hit_tick[obj:id()] = time_global() + 2000
			end
		end
		local safe_zone = db.zone_by_name["sr_safe_zone"]
		if safe_zone then
			if last_in_safe_zone[obj:id()] then
				if not safe_zone:inside(obj:position()) then
					last_in_safe_zone[obj:id()] = false
					send_to_user("Вы вышли из безопасной зоны. Ваш прогресс не будет сохранен.", obj)
				end
			else
				if safe_zone:inside(obj:position()) then
					last_in_safe_zone[obj:id()] = true
					send_to_user("Вы вошли в безопасную зону. Ваш прогресс будет сохранен.", obj)
				end
			end
		end
		if last_pos_tick[obj:id()] < time_global() then
			if obj:position().y > 60.0 then
				local pos = obj:position()
				get_console():execute("chat %c[255,190,20,20][ANTI-CHEAT] " .. obj:name() .. " - Подозревается в использование запрещенного программного обеспечения.")
				pos.y = 55.0
				obj:set_actor_position(pos)
			end
			last_pos_tick[obj:id()] = time_global() + 500
		end
		if last_tick[obj:id()] > time_global() then
			return false
		end
		save_player_loot_table(obj)
	end
	last_tick[obj:id()] = time_global() + math.random(3000, 5000)
	return false
end

function spawn_in_inv(sect, parent)
	local so_obj = alife():create(sect, db.actor:position(), db.actor:level_vertex_id(), db.actor:game_vertex_id(), -1)
	level.client_spawn_manager():add(so_obj.id, 0, spawn_in_inv_callback, {parent:id(), sect})
	--level.client_spawn_manager():add(so_obj.id, 0, spawn_in_inv_callback)
	return so_obj
end

function spawn_in_inv_callback(parent_id, id, obj)
	local new_parent = level.object_by_id(parent_id[1])
	--local new_parent = level.object_by_id(parent_id)
	if new_parent then
		if obj:parent() then
			obj:parent():transfer_item(obj, new_parent)
			return
		end
		new_parent:take_item(obj)
		if parent_id[2] ~= obj:section() then logf_test("Why random %s, %s", parent_id[2], obj:section()) end 
	end
end

function kill_player(obj)
	-- if obj then
		-- local h = hit()
		-- h.draftsman = db.actor or obj
		-- h.type = hit.explosion
		-- h.direction = vector():set(0, 1, 0)
		-- h.power = 10000
		-- h.impulse = 0
		-- obj:hit(h)
	-- end
end

function cheak_ban_char(name, char)
	if name:find(char) then
		get_console():execute(string.format("sv_listplayers %s", char))
		get_console():execute("sv_kick_id last_printed")
		kill_player(player_by_name[name])
		return true
	end
	return false
end

function sv_kick_vasan(name)
	local ban = false
	ban = ban or cheak_ban_char(name, [[/]])
	ban = ban or cheak_ban_char(name, [[\]])
	ban = ban or cheak_ban_char(name, [[:]])
	ban = ban or cheak_ban_char(name, [[*]])
	ban = ban or cheak_ban_char(name, [[?]])
	ban = ban or cheak_ban_char(name, [["]])
	ban = ban or cheak_ban_char(name, [[<]])
	ban = ban or cheak_ban_char(name, [[>]])
	ban = ban or cheak_ban_char(name, [[|]])
	ban = ban or cheak_ban_char(name, [[#]])
	ban = ban or cheak_ban_char(name, [["]])
	ban = ban or cheak_ban_char(name, [[']])
	ban = ban or cheak_ban_char(name, [[=]])
	return ban
end

function process_spawn_loot(spawn_loot_queue)
	if need_save_loot then
		local process_spawn = function ()
			local process_size = math.min(spawn_loot_queue_process_size, #spawn_loot_queue)
			for j = 1, process_size do
				local index = 1 -- do so for now
				local t = spawn_loot_queue[index].loot_table
				local obj = level.object_by_id(spawn_loot_queue[index].parent_id)
				if obj and t and t.condition then
					if obj:name() ~= spawn_loot_queue[index].parent_name then 
						logf_test("Why [%s] spizdil u [%s]",
							tostring(obj:name()), tostring(spawn_loot_queue[index].parent_name)) end
					local sobj = spawn_in_inv(t.section, obj)
					if sobj then
						local tpk = get_object_data(sobj)
						if tpk then
							t = table.merge(tpk, t)
							t.level_vertex_id = tpk.level_vertex_id
							t.game_vertex_id = tpk.game_vertex_id
							set_object_data(t, sobj)
						end
					end
				end
				table.remove(spawn_loot_queue, index)
			end
			return #spawn_loot_queue == 0
		end
		level.add_call(process_spawn, function() end)
	end
end

function load_player_loot(obj)
	if obj:get_visual_name():find("stalker_monolith_4") or 
	obj:get_visual_name():find("stalker_monolith_5") or 
	obj:get_visual_name():find("stalker_monolith_6") then
		obj:allow_sprint(false)
		is_zooombe[obj:id()] = true
	end
	if not_kicked_person[obj:name()] then
		kill_player(obj)
	end
	player_by_name[obj:name()] = obj
	is_very_very_dead[obj:id()] = false
	max_player_money[obj:id()] = 0
	hard_key_two[obj:id()] = true
	authorization_time[obj:id()] = time_global() + 10000
	authorization_count[obj:id()] = 2
	logf_test("[%s] try to spawn", obj:name())
	if obj:get_visual_name():find("spectrum") then
		if level.name() == "jupiter_stnet_v2" then
		local jupiter_spectrum_rpoint = math.random(1, 2)
		if jupiter_spectrum_rpoint == 1 then
			obj:set_actor_position(vector():set(-358.39, 5.10, 405.14))
		end
		if jupiter_spectrum_rpoint == 2 then
			obj:set_actor_position(vector():set(-309.44, 14.63, 413.27))
		end
		elseif level.name() == "zaton" then
		local zaton_spectrum_rpoint = math.random(1, 5)
		if zaton_spectrum_rpoint == 1 then
			obj:set_actor_position(vector():set(-416.90, 24.20, -327.99))
		end
		if zaton_spectrum_rpoint == 2 then
			obj:set_actor_position(vector():set(-337.02, 41.62, -398.52))
		end
		if zaton_spectrum_rpoint == 3 then
			obj:set_actor_position(vector():set(-318.99, 41.60, -307.21))
		end
		if zaton_spectrum_rpoint == 4 then
			obj:set_actor_position(vector():set(-414.37, 41.90, -306.83))
		end
		if zaton_spectrum_rpoint == 5 then
			obj:set_actor_position(vector():set(-371.02, 41.55, -330.85))
		end
		end
	end
	if xrLua.CheakBanWord(obj:id()) then
		xrLua.KickPlayer(obj:id())
		return true
	end
	local path = getFS():update_path("$app_data_root$", "accounts\\")
	local data = io.open(path .. obj:name() ..  "_inventory.lua")
	if not data then return true end
	local tbl = loadstring(data:read("*a"))()
	data:close()
	if not tbl then return true end
	if not obj:alive() then
		return true
	end
	local spawn_loot_queue = {}
	if not death_count[obj:id()] then
		death_count[obj:id()] = 0
	end
	for k, v in pairs(tbl) do
		if k == "password" then
			passwords[obj:id()] = tostring(v)
		elseif k == "death_count" then
			death_count[obj:id()] = tonumber(v)
		elseif k == "position" then
		--	obj:set_actor_position(vector():set(v.x, v.y, v.z))
		else
			local t = {}
			t.loot_table = v
			t.parent_id = obj:id()
			t.parent_name = obj:name()
			if need_save_loot then
				table.insert(spawn_loot_queue, t)
			end
			-- execute deffered
		end
	end
	process_spawn_loot(spawn_loot_queue)
	return false
end

function objects_equal(obj1, obj2)
	if obj1 and obj2 then
		if obj2:name() == obj1:name() and obj2:id() == obj1:id() then
			return true
		end
	end
	return false
end

function save_player_loot_table(player)
	local loot_table = {}
	local function add_items (parent, item)
		local owner = item:parent()
		if objects_equal(owner, player) and 
		not ignore_save_loot[item:section()] and alife():object(item:id()) then
			local tbl = get_item_table(item)
			if tbl then
				table.insert(loot_table, tbl)
			end
		end
	end
	if player:alive() and need_save_loot then
		player:iterate_inventory(add_items, player)
		local position = player:position()
	--	loot_table["position"] = {x=position.x, y=position.y + 0.1, z=position.z}
	end
	if passwords[player:id()] then
		loot_table["password"] = passwords[player:id()]
	end
	if death_count[player:id()] then
		loot_table["death_count"] = death_count[player:id()]
	end
	local script = print_tableg(loot_table, "mp_actor")
	script = script .. "return mp_actor \n"
	printfile(script, player)
end

function printfile(text, obj)
	local path = getFS():update_path("$app_data_root$", "accounts\\")
	local file = io.open(path .. obj:name() ..  "_inventory.lua", "w")
	if not file or xrLua.CheakBanWord(obj:id()) then
		if file then
			file:close()
		end
		return
	end
	file:write(text)
	file:close()
end

function printfg(fmt,...) return string.format(fmt, ...) .. "\n" end

-- ѕечатает таблицу как дерево.
function print_tableg(table, sub)
	if not sub then sub = "" end
	if not table then table = _G sub = "_G" end
	local text = sub .. " = {}\n"
	for k,v in pairs(table) do
	if type(k) == "string" then k = [["]]..k..[["]] end
		if type(v) == "table" then
		--	text = text .. printfg(sub.."[%s] = {}", tostring(k))
			text = text .. print_tableg(v, sub.."["..tostring(k).."]")
		elseif type(v) == "function" then
			text = text .. printfg(sub.."[%s] = function() end", tostring(k))
		elseif type(v) == "userdata" then
			text = text .. printfg(sub.."[%s] = userdata", tostring(k))
		elseif type(v) == "boolean" then
					if v == true then
							if(type(k)~="userdata") then
									text = text .. printfg(sub.."[%s] = true", tostring(k))
							else
									text = text .. printfg(sub.."userdata:true")
							end
					else
							if(type(k)~="userdata") then
									text = text .. printfg(sub.."[%s] = false", tostring(k))
							else
									text = text .. printfg(sub.."userdata:false")
							end
					end
		else
			if v ~= nil then
				if type(v) == "string" then
					text = text .. printfg(sub.."[%s] = [[%s]]", tostring(k),v)
				else
					text = text .. printfg(sub..[[[%s] = %s]], tostring(k),v)
				end
			else
				text = text .. printfg(sub..[[[%s] = nil]], tostring(k))
			end
		end
	end
	return text
end

function spawn_callback(obj, id, wpn)
	local par = obj:parent()
	obj:destroy_object()
	if par then
		spawn_in_inv_callback({par:id(), wpn:section()}, id, wpn)
	end
end

function logf_test(fmt, ...)
	log_test(string.format(fmt, ...))
end

function death_callback(obj, npc, who)
	local torch = npc:item_in_slot(10)
	if torch then
		torch:destroy_object()
	end
	-- local safe_zone = db.zone_by_name["sr_safe_zone"]
	-- if safe_zone and not safe_zone:inside(npc:position()) then
		-- is_very_very_dead[npc:id()] = true
 	-- end
	actual_team_leader[npc:id()] = nil
	if not death_count[npc:id()] then
		death_count[npc:id()] = 0
	else
		death_count[npc:id()] = death_count[npc:id()] + 1
	end
	if who and who:id() ~= obj:id() and not is_zooombe[obj:id()] then
		local binder = who:binded_object()
		if binder and binder.community == "stalker" then
			is_very_very_dead[who:id()] = true
		end
	end
	local binder = npc:binded_object()
	if binder then
		binder:death_callback(obj, who)
	end
end
function drop_callback(npc, obj)
	last_tick[npc:id()] = time_global() + 200
	bind_taynik_box.on_item_drop(npc, obj)
	if not npc:alive() and not not_destroy_item[obj:id()] then
		obj:destroy_object()
	end
	not_destroy_item[obj:id()] = nil
	local binder = npc:binded_object()
	if binder and (alife():object(obj:id()) or ignore_save_loot[obj:section()]) then
		binder:on_item_drop(obj)
	end
end

function take_callback(npc, obj)
	if not npc:alive() then
		return 
	end
	if need_save_loot then
		if destroy_objects[obj:section()] then
			obj:destroy_object()
			return
		end
		if not (alife():object(obj:id()) or ignore_save_loot[obj:section()]) then
			fix_no_alife_object(obj)
		end
	else
		if destroy_objects[obj:section()] then
			obj:destroy_object()
		end
	end
	last_tick[npc:id()] = time_global() + 200
end

db.add_actor = function(obj)
	db.actor = obj
	db.actor_proxy:net_spawn( obj )
	db.add_obj(obj)
	if alife() then
		obj:set_fastcall(server_update, nil)
		obj:set_callback(callback.inventory_info, single_actor_info, obj)
	end
	log_test("module save_loot connected...")
end

local start_surge_time = nil
local end_surge_time = nil
local is_surge_started = false

function server_update()
	if level.is_wfx_playing() and not is_surge_started then
		is_surge_real_started = false
		is_surge_started = true
		local time = math.random(15000, 40000)
		start_surge_time = time_global() + time
		end_surge_time = time_global() + 190000
		send_tip_server(string.format("Выброс начнется через %.1f секунд!", time * 0.001))
	elseif not level.is_wfx_playing() and is_surge_started then
		is_surge_started = false
	end
	if is_surge_started and start_surge_time and start_surge_time < time_global() and not is_surge_real_started then
		is_surge_real_started = true
		start_surge_time = nil
	end
	if end_surge_time and end_surge_time < time_global() then
		send_tip_server("Выброс закончился!")
		end_surge_time = nil
		is_surge_real_started = false
	end
	if agit_time < time_global() then
		local path = getFS():update_path("$app_data_root$", "agait_manager.ltx")
		local agait_table = {}
		for line in io.lines(path) do
			if line then
				table.insert(agait_table, line) 
			end
		end
		agit_time = time_global() + agit_time_delta
		if #agait_table > 0 then
			get_console():execute("chat " .. agait_table[math.random(1, #agait_table)])
		end
	end
	return false
end

function use_callback (self, obj, who)
	if is_very_very_dead[obj:id()] then
		local drop_table = {}
		local drop_table_count = {}
		local function drop_items (parent, item)
			if not ignore_save_loot[item:section()] then
				table.insert(drop_table, item:id())
				not_destroy_item[item:id()] = true
			end
		end
		obj:iterate_inventory(drop_items, obj)
		if #drop_table > 0 then
			who:allow_sprint(false)
			local function time_transfer_items() 
				local size = math.min(#drop_table, spawn_loot_queue_process_size)
				for i = 1, size do
					local index = #drop_table
					local item = level.object_by_id(drop_table[index])
					if item then
						local parent = item:parent()
						if who and parent then
							parent:transfer_item(item, who)
							local name = game.translate_string(system_ini():r_string(item:section(), "inv_name"))
							if drop_table_count[name] then
								drop_table_count[name] = drop_table_count[name] + 1
							else
								drop_table_count[name] = 1
							end
						end
					end
					table.remove(drop_table, index)
				end
				return #drop_table == 0
			end
			function on_time_transfer_items() 
				local temp_tbl = {}
				for k, v in pairs(drop_table_count) do
					table.insert(temp_tbl, k .. " = " .. v)
				end
				if who then
					who:allow_sprint(true)
					send_to_user(table.concat(temp_tbl, ", "), who)
				end 
			end
			level.add_call(time_transfer_items, on_time_transfer_items)
		end
	end
end

db.add_obj = function ( obj )
	if obj:section() == "mp_actor" and alife() then
		obj:set_fastcall(update_save_loot, obj)
		obj:set_callback(callback.inventory_info, info_callback, obj)
		obj:set_callback(callback.on_item_take, take_callback, obj)
		obj:set_callback(callback.on_item_drop, drop_callback, obj)
		obj:set_callback(callback.death,	death_callback, obj)
		obj:set_callback(callback.use_object, use_callback, obj)
		local is_new = load_player_loot(obj)
	end
	printf("adding object %s",obj:name())
	db.storage[obj:id()].object = obj
end

function single_actor_info(self, obj, info)
	logf_test("actor has %s", info)
	if info:find("game_player_flag_very_very_dead=") then
		is_very_very_dead[tonumber(string_expl(info, "=")[2])] = true
	end
end

function info_callback (self, obj, id)
	log_test(obj:name() .. " " .. id)
	local id_expl = string_expl(id, "=")
	local binder = obj:binded_object()
	local safe_nickname = obj:name()
	if not binder then
		-- cheak_ban_char(obj:name(), obj:name())
		xrLua.KickPlayer(obj:id())
		return
	end
	if id:find("password=") and id_expl[2] and id_expl[2] ~= "" then
		local password = id_expl[2]
		if passwords[obj:id()] then
			if passwords[obj:id()] ~= password then
				-- cheak_ban_char(obj:name(), obj:name())
				xrLua.KickPlayer(obj:id())
				return
			end
		else
			passwords[obj:id()] = password:gsub("{", ""):gsub("}", "") --:gsub("[", ""):gsub("]", "") 
		end
		local path = getFS():update_path("$app_data_root$", "team_leads.lua")
		local data = io.open(path)
		if data then
			local tbl = loadstring(data:read("*a"))()
			if tbl and tbl[safe_nickname] then
				obj:give_info_portion("player_team_lead_" .. binder.community)
		--		obj:give_info_portion("add_list_command=" .. binder.community .. "=" .. obj:name() .. "=" .. device().frame)
				actual_team_leader[obj:id()] = tbl[safe_nickname]
				data:close()
				return
			end
			data:close()
		end
		local path = getFS():update_path("$app_data_root$", "team_players.lua")
		local data = io.open(path)
		if data then
			local tbl = loadstring(data:read("*a"))()
			--get_console():execute("chat %c[0,183,0,20][FACTION-SYSTEM] " .. obj:name() .. " подключился к группировке " .. binder.community ..  " ")
			if tbl then
				if binder.community ~= "stalker" and (binder.community ~= tbl[safe_nickname] or not tbl[safe_nickname]) then
					logf_test("Не является участником группировки %s %s", obj:name(), binder.community)
					get_console():execute("chat %c[0,183,0,20][FACTION-SYSTEM] " .. obj:name() .. " Не является участником группировки " .. binder.community ..  " - Automatically kicked...")
					-- cheak_ban_char(obj:name(), obj:name())
					xrLua.KickPlayer(obj:id())
				end
			end
			data:close()
		end
		authorization_time[obj:id()] = nil 
		authorization_count[obj:id()] = nil 
	elseif id:find("user_key=") or (id:find("hard_key") and id:find("=")) or id:find("computer_name=")  or id:find("user_name=")then
		local user_key = id_expl[2]
		local path = getFS():update_path("$app_data_root$", "banned_list_cmd.ltx")
		local data = io.open(path)
		if data then
			local ini = create_ini_file(data:read("*a"))
			if ini:line_exist("banned_list", user_key) then
				get_console():execute("chat %c[147,203,255,20][BAN-SYSTEM] " .. obj:name() .. " - Обнаружено наличие блокировки. Automatically kicked...")
				-- cheak_ban_char(obj:name(), obj:name())
				xrLua.KickPlayer(obj:id())
				not_kicked_person[obj:name()] = true
			end
			data:close()
		end
		if id:find("hard_key2") then
			hard_key_two[obj:id()] = true
		end
	elseif id:find("delta_money=") then
		local delta_money = tonumber(id_expl[2])		
		max_player_money[obj:id()] = max_player_money[obj:id()] + delta_money
		if max_player_money[obj:id()] > 150000 then
			get_console():execute("chat %c[255,190,20,20][ANTI-CHEAT] " .. obj:name() .. " - Подозревается в использование запрещенного программного обеспечения.")
			-- cheak_ban_char(obj:name(), obj:name())
			xrLua.KickPlayer(obj:id())
			not_kicked_person[obj:name()] = true
		end
	elseif id:find("add_list_command=") then
		if actual_team_leader[obj:id()] == binder.community and binder.community == id_expl[2] then
			local name = tostring(id_expl[3]):gsub("'", ''):gsub('"', ''):gsub('?', '')
			local path = getFS():update_path("$app_data_root$", "team_players.lua")
			local data = io.open(path)
			local tbl = {}
			if data then
				tbl = loadstring(data:read("*a"))()
				data:close()
			end
			if tbl then
				tbl[name] = tostring(id_expl[2]):gsub("'", '?'):gsub('"', '?')
			end
			local text = print_tableg(tbl, "tbl")
			text = text .. "return tbl \n"
			local data = io.open(path, "w")
			if data then
				data:write(text)
				data:close()
			end
		end
	elseif id:find("remove_list_command=") then
		if actual_team_leader[obj:id()] == binder.community and binder.community == id_expl[2] then
			local name = tostring(id_expl[3]):gsub("'", ''):gsub('"', ''):gsub('?', '')
			local path = getFS():update_path("$app_data_root$", "team_players.lua")
			local data = io.open(path)
			if data then
				local tbl = loadstring(data:read("*a"))()
				if tbl then
					tbl[name] = nil
				end
				data:close()
				local text = print_tableg(tbl, "tbl")
				text = text .. "return tbl \n"
				data = io.open(path, "w")
				if data then
					data:write(text)
					data:close()
				end
			end
		end
	elseif id:find("update_list_command=") then
		if actual_team_leader[obj:id()] == binder.community and binder.community == id_expl[2] then
			local path = getFS():update_path("$app_data_root$", "team_players.lua")
			local data = io.open(path)
			if data then
				local tbl = loadstring(data:read("*a"))()
				if tbl then
					for player, community in pairs(tbl) do
						if community == binder.community then
							obj:give_info_portion("add_player_to_my_list=" .. player .. "=" .. device().frame)
						end
					end
				end
				data:close()
			end
		end
	elseif id:find("anticheat_executed") then
		get_console():execute("chat %c[255,20,220,20][ANTI-CHEAT] " .. obj:name() .. " - Отключен за использование запрещенного программного обеспечения.")
	end
end

function string_expl(sStr, sDiv, Mode, bNoClear)
  sStr = tostring(sStr)
  if not (sStr ~= "nil" and sStr ~= '') then return {} end --> нечего разделять
  local tRet = {}
  local sPattern = '[%w%_]+' --> дефолтный патерн (разделение по 'словам')
  if type(sDiv) == "string" then --> если задан сепаратор: разделяем по нему
    if bNoClear then --> если НЕ указано 'чистить пробелы'
      sPattern = '([^'..sDiv..']+)'
    else --> иначе с чисткой пробелов
      sPattern = '%s*([^'..sDiv..']+)%s*'
    end
  end
  --* разделяем строку по патерну
  if Mode == nil then --> обычный массив
    for sValue in sStr:gmatch(sPattern) do
      table.insert(tRet, sValue)
    end
  else
    local sTypeMode = type(Mode)
    if sTypeMode == "boolean" then --> таблица '[значение] = true или false'
      for sValue in sStr:gmatch(sPattern) do
        tRet[sValue] = Mode
      end
    elseif sTypeMode == "number" then --> таблица '[idx] = число или стринг'
      for sValue in sStr:gmatch(sPattern) do
        tRet[#tRet+1] = tonumber(sValue) or sValue
      end
    end
  end
  return tRet --> возвращаем таблицу
end

-- stpk_utils
-- Alundaio

local stpk = net_packet()
local uppk = net_packet()

-- only use if you don't know the object class, otherwise call get_* directly to avoid needless overhead
function get_object_data(sobj)
	if not (sobj) then
		return nil
	end
	local m_classes =
	{
		["S_ACTOR"]  = get_actor_data,
		["O_ACTOR"]  = get_actor_data,
		
		["ARTEFACT"] = get_item_data,
		["SCRPTART"] = get_item_data,

		["II_ATTCH"] = get_item_data,
		["II_BTTCH"] = get_item_data,

		["II_DOC"]   = get_item_document_data,

		["TORCH_S"]  = get_item_data,
		["TORCH"]  = get_item_data,

		["DET_SIMP"] = get_item_data,
		["DET_ADVA"] = get_item_data,
		["DET_ELIT"] = get_item_data,
		["DET_SCIE"] = get_item_data,

		["E_STLK"]   = get_item_data,
		["E_HLMET"]  = get_item_data,
		["EQU_STLK"]   = get_item_data,
		["EQU_HLMET"]  = get_item_data,
		
		["II_BANDG"] = get_item_data,
		["II_MEDKI"] = get_item_data,
		["II_ANTIR"] = get_item_data,
		["II_BOTTL"] = get_item_data,
		["II_FOOD"]  = get_item_data,
		["S_FOOD"]   = get_item_data,

		["S_PDA"]    = get_item_pda_data,
		["D_PDA"]    = get_item_pda_data,

		["II_BOLT"]  = get_item_data,

		["WP_AK74"] = get_weapon_data,
		["WP_ASHTG"] = get_weapon_data,
		["WP_BINOC"] = get_weapon_data,
		["WP_BM16"] = get_weapon_data,
		["WP_GROZA"] = get_weapon_data,
		["WP_HPSA"] = get_weapon_data,
		["WP_KNIFE"] = get_weapon_data,
		["WP_LR300"] = get_weapon_data,
		["WP_PM"] = get_weapon_data,
		["WP_RG6"] = get_weapon_data,
		["WP_RPG7"] = get_weapon_data,
		["WP_SVD"] = get_weapon_data,
		["WP_SVU"] = get_weapon_data,
		["WP_VAL"] = get_weapon_data,

		["S_EXPLO"]  = get_item_data,
		["II_EXPLO"]  = get_item_data,

		["AMMO"]   = get_ammo_data,
		["AMMO_S"]   = get_ammo_data,
		["S_OG7B"]   = get_ammo_data,
		["S_VOG25"]  = get_ammo_data,
		["S_M209"]   = get_ammo_data,

		["G_F1_S"]   = get_item_data,
		["G_RGD5_S"] = get_item_data,
		["G_F1"]   	 = get_item_data,
		["G_RGD5"]	 = get_item_data,
		
		["WP_SCOPE"] = get_item_data,
		["WP_SILEN"] = get_item_data,
		["W_SILENC"] = get_item_data,
		["WP_GLAUN"] = get_item_data
	}
	local class = system_ini():r_string(sobj:section_name(),"class")
	if (class == nil or class == "") then 
		return nil
	end 
	
	return m_classes[class] and m_classes[class](sobj) or nil
end 

function set_object_data(t,sobj)
	if not (sobj) then
		return nil
	end
	local m_classes =	{
		["S_ACTOR"]  = set_actor_data,
		["O_ACTOR"]  = set_actor_data,
		["ARTEFACT"] = set_item_data,
		["SCRPTART"] = set_item_data,
		["II_ATTCH"] = set_item_data,
		["II_BTTCH"] = set_item_data,
		["II_DOC"]   = set_item_document_data,
		["TORCH_S"]  = set_item_data,
		["TORCH"]  = set_item_data,
		["DET_SIMP"] = set_item_data,
		["DET_ADVA"] = set_item_data,
		["DET_ELIT"] = set_item_data,
		["DET_SCIE"] = set_item_data,

		["E_STLK"]   = set_item_data,
		["E_HLMET"]  = set_item_data,
		["EQU_STLK"]   = set_item_data,
		["EQU_HLMET"]  = set_item_data,
		
		["II_BANDG"] = set_item_data,
		["II_MEDKI"] = set_item_data,
		["II_ANTIR"] = set_item_data,
		["II_BOTTL"] = set_item_data,
		["II_FOOD"]  = set_item_data,
		["S_FOOD"]   = set_item_data,

		["S_PDA"]    = set_item_pda_data,
		["D_PDA"]    = set_item_pda_data,

		["II_BOLT"]  = set_item_data,

		["WP_AK74"] = set_weapon_data,
		["WP_ASHTG"] = set_weapon_data,
		["WP_BINOC"] = set_weapon_data,
		["WP_BM16"] = set_weapon_data,
		["WP_GROZA"] = set_weapon_data,
		["WP_HPSA"] = set_weapon_data,
		["WP_KNIFE"] = set_weapon_data,
		["WP_LR300"] = set_weapon_data,
		["WP_PM"] = set_weapon_data,
		["WP_RG6"] = set_weapon_data,
		["WP_RPG7"] = set_weapon_data,
		["WP_SVD"] = set_weapon_data,
		["WP_SVU"] = set_weapon_data,
		["WP_VAL"] = set_weapon_data,
		["S_EXPLO"]  = set_item_data,
		["II_EXPLO"]  = set_item_data,

		["AMMO"]   = set_ammo_data,
		["AMMO_S"]   = set_ammo_data,
		["S_OG7B"]   = set_ammo_data,
		["S_VOG25"]  = set_ammo_data,
		["S_M209"]   = set_ammo_data,

		["G_F1_S"]   = set_item_data,
		["G_RGD5_S"] = set_item_data,
		["G_F1"]   	 = set_item_data,
		["G_RGD5"]	 = set_item_data,
		
		["WP_SCOPE"] = set_item_data,
		["WP_SILEN"] = set_item_data,
		["W_SILENC"] = set_item_data,
		["WP_GLAUN"] = set_item_data
	}
	local class = system_ini():r_string(sobj:section_name(),"class")
	if (class == nil or class == "") then 
		return nil
	end 
	
	return m_classes[class] and m_classes[class](t,sobj) or nil
end 

function get_abstract_data(stpk)
	if (stpk:r_eof()) then 
		return
	end
    if (stpk:w_tell() <= 2) then
	return
    end

    local t = {}

    stpk:r_seek(0)
    t.dummy16 = stpk:r_u16()
    t.section_name = stpk:r_stringZ()
    t.name = stpk:r_stringZ()
    t.s_gameid = stpk:r_u8()
    t.s_rp = stpk:r_u8()
	t.position = vector()
    stpk:r_vec3(t.position)
	t.direction = vector()
    stpk:r_vec3(t.direction)
    t.respawn_time = stpk:r_u16()
    t.object_id = stpk:r_u16()
    t.parent_id = stpk:r_u16()
    t.phantom_id = stpk:r_u16()
    t.s_flags = stpk:r_u16()
    t.version = stpk:r_u16()
    t.cse_abstract__unk1_h16 = stpk:r_u16()
    t.script_version = stpk:r_u16()
    t.unused = stpk:r_u16()
    if t.unused > 0 then
	t.extra = {}
	for i = 1, t.unused do
	    t.extra[i] = stpk:r_u8()
	end
    end
    t.spawn_id = stpk:r_u16()
    t.extended_size = stpk:r_u16()
    return t
end

function set_abstract_data(t,stpk)
    stpk:w_begin(t.dummy16)
    stpk:w_stringZ(t.section_name)
    stpk:w_stringZ(t.name)
    stpk:w_u8(t.s_gameid)
    stpk:w_u8(t.s_rp)
    stpk:w_vec3(t.position)
    stpk:w_vec3(t.direction)
    stpk:w_u16(t.respawn_time)
    stpk:w_u16(t.object_id)
    stpk:w_u16(t.parent_id)
    stpk:w_u16(t.phantom_id)
    stpk:w_u16(t.s_flags)
    stpk:w_u16(t.version)
    stpk:w_u16(t.cse_abstract__unk1_h16)
    stpk:w_u16(t.script_version)
    stpk:w_u16(t.unused)
    if t.unused > 0 and t.extra ~= nil then
	for i = 1, t.unused do
	    stpk:w_u8(t.extra[i])
	end
    end
    stpk:w_u16(t.spawn_id)
    stpk:w_u16(t.extended_size)
end

function get_squad_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	stpk:r_seek(2)
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_alife_online_offline_group_properties_packet(t,stpk)
	return t
end 

function set_squad_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_alife_online_offline_group_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end 

function get_weapon_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_alife_item_properties_packet(t,stpk)
	parse_cse_alife_item_weapon_properties_packet(t,stpk)
	return t
end

function set_weapon_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_item_properties_packet(t,stpk)
		fill_cse_alife_item_weapon_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_item_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	stpk:r_seek(2)

	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_alife_item_properties_packet(t,stpk)
	return t
end

function set_item_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_item_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_ammo_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	stpk:r_seek(2)

	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_alife_item_properties_packet(t,stpk)
	t.ammo_left = stpk:r_u16()
	return t
end

function set_ammo_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_item_properties_packet(t,stpk)
		stpk:w_u16(t.ammo_left)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_inv_box_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_alife_inventory_box_properties_packet(t,stpk)
	return t
end

function set_inv_box_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_inventory_box_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_item_document_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_alife_item_properties_packet(t,stpk)
	t.info_portion = stpk:r_stringZ()
	return t
end

function set_item_document_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_item_properties_packet(t,stpk)
		stpk:w_stringZ(t.info_portion)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_item_pda_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_alife_item_properties_packet(t,stpk)
	t.original_owner = stpk:r_u16()
	t.specific_character = stpk:r_stringZ()
	t.info_portion = stpk:r_stringZ()
	return t
end

function set_item_pda_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_item_properties_packet(t,stpk)
		stpk:w_u16(t.original_owner)
		stpk:w_stringZ(t.specific_character)
		stpk:w_stringZ(t.info_portion)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_actor_data(sobj)
	if not (sobj) then return end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_alife_creature_abstract_properties_packet(t,stpk)
	parse_cse_alife_trader_abstract_properties_packet(t,stpk)
	parse_cse_ph_skeleton_properties_packet(t,stpk)
	parse_cse_alife_creature_actor_properties_packet(t,stpk)
	parse_se_actor_properties_packet(t,stpk)
	return t
end 

function set_actor_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_creature_abstract_properties_packet(t,stpk)
		fill_cse_alife_trader_abstract_properties_packet(t,stpk)
		fill_cse_ph_skeleton_properties_packet(t,stpk)
		fill_cse_alife_creature_actor_properties_packet(t,stpk)
		fill_se_actor_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end 

function get_stalker_data(sobj)
	if not (sobj) then return end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_trader_abstract_properties_packet(t,stpk)
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_alife_creature_abstract_properties_packet(t,stpk)
	parse_cse_alife_monster_abstract_properties_packet(t,stpk)
	parse_cse_alife_human_abstract_properties_packet(t,stpk)
	parse_cse_ph_skeleton_properties_packet(t,stpk)
	parse_se_stalker_properties_packet(t,stpk)
	return t
end

function set_stalker_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_trader_abstract_properties_packet(t,stpk)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_creature_abstract_properties_packet(t,stpk)
		fill_cse_alife_monster_abstract_properties_packet(t,stpk)
		fill_cse_alife_human_abstract_properties_packet(t,stpk)
		fill_cse_ph_skeleton_properties_packet(t,stpk)
		fill_se_stalker_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_monster_data(sobj)
	if not (sobj) then return end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_alife_creature_abstract_properties_packet(t,stpk)
	parse_cse_alife_monster_abstract_properties_packet(t,stpk)
	parse_cse_ph_skeleton_properties_packet(t,stpk)
	parse_se_monster_properties_packet(t,stpk)
	return t
end

function set_monster_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_creature_abstract_properties_packet(t,stpk)
		fill_cse_alife_monster_abstract_properties_packet(t,stpk)
		fill_cse_ph_skeleton_properties_packet(t,stpk)
		fill_se_monster_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_smart_cover_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)

	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_shape_properties_packet(t,stpk)
	parse_cse_smart_cover_properties_packet(t,stpk)
	parse_se_smart_cover_properties_packet(t,stpk)
	return t
end

function set_smart_cover_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_shape_properties_packet(t,stpk)
		fill_cse_smart_cover_properties_packet(t,stpk)
		fill_se_smart_cover_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function spawn_smart_cover(anm,sec,pos,lvid,gvid)
	local se_cover = alife():create(sec,pos,lvid,gvid)
	se_cover.last_description = anm
	se_cover.loopholes[anm] = 1
	local data = alun_utils.get_smart_cover_data(se_cover)
	data.description = anm
	data.last_description = anm
	data.loopholes[anm] = 1
	alun_utils.set_smart_cover_data(data,se_cover)
	return se_cover
end

function get_climable_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_shape_properties_packet(t,stpk)
	parse_cse_alife_object_climable_properties_packet(t,stpk)
	return t
end

function set_climable_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_shape_properties_packet(t,stpk)
		fill_cse_alife_object_climable_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_heli_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_motion_properties_packet(t,stpk)
	parse_cse_ph_skeleton_properties_packet(t,stpk)
	parse_cse_alife_helicopter_properties_packet(t,stpk)
	return t
end

function set_heli_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_motion_properties_packet(t,stpk)
		fill_cse_ph_skeleton_properties_packet(t,stpk)
		fill_cse_alife_helicopter_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end


function spawn_heli(section)
	local pos = db.actor:position()
	local se_obj = alife():create(section,vector():set(pos.x,pos.y,pos.z),db.actor:level_vertex_id(),db.actor:game_vertex_id())
	if (se_obj) then
		local data = get_heli_data(se_obj)
		if (data) then
			data.visual_name = [[dynamics\vehicles\ghost_train]]
			data.motion_name = [[test_ghost_train.anm]]
			data.startup_animation = "idle"
			data.skeleton_name = "idle"
			data.engine_sound = [[vehicles\ghost_train\ghost_train_01]]
			set_heli_data(data,se_obj)
		end
	end
	return se_obj
end

function get_lamp_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_ph_skeleton_properties_packet(t,stpk)
	parse_cse_alife_object_hanging_lamp_properties_packet(t,stpk)
	return t
end

function set_lamp_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_ph_skeleton_properties_packet(t,stpk)
		fill_cse_alife_object_hanging_lamp_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_physic_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_ph_skeleton_properties_packet(t,stpk)
	parse_cse_alife_object_physic_properties_packet(t,stpk)
	return t
end

function set_physic_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_ph_skeleton_properties_packet(t,stpk)
		fill_cse_alife_object_physic_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_space_restrictor_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_shape_properties_packet(t,stpk)
	parse_cse_alife_space_restrictor_properties_packet(t,stpk)
	return t
end

function set_space_restrictor_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_shape_properties_packet(t,stpk)
		fill_cse_alife_space_restrictor_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end


function get_anom_zone_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_shape_properties_packet(t,stpk)
	parse_cse_alife_space_restrictor_properties_packet(t,stpk)
	parse_cse_alife_custom_zone_properties_packet(t,stpk)
	parse_cse_alife_anomalous_zone_properties_packet(t,stpk)
	parse_se_zone_properties_packet(t,stpk)
	return t
end

function set_anom_zone_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_shape_properties_packet(t,stpk)
		fill_cse_alife_space_restrictor_properties_packet(t,stpk)
		fill_cse_alife_custom_zone_properties_packet(t,stpk)
		fill_cse_alife_anomalous_zone_properties_packet(t,stpk)
		fill_se_zone_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end


function get_visual_zone_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)
	
	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_shape_properties_packet(t,stpk)
	parse_cse_alife_space_restrictor_properties_packet(t,stpk)
	parse_cse_alife_custom_zone_properties_packet(t,stpk)
	parse_cse_alife_anomalous_zone_properties_packet(t,stpk)
	parse_cse_visual_properties_packet(t,stpk)
	parse_cse_alife_zone_visual_properties_packet(t,stpk)
	parse_se_zone_properties_packet(t,stpk)
	return t
end

function set_visual_zone_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_shape_properties_packet(t,stpk)
		fill_cse_alife_space_restrictor_properties_packet(t,stpk)
		fill_cse_alife_custom_zone_properties_packet(t,stpk)
		fill_cse_alife_anomalous_zone_properties_packet(t,stpk)
		fill_cse_visual_properties_packet(t,stpk)
		fill_cse_alife_zone_visual_properties_packet(t,stpk)
		fill_se_zone_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end

function get_level_changer_data(sobj)
	if not sobj then
		return
	end
	stpk:w_begin(0)
	sobj:STATE_Write(stpk)
	
	stpk:r_seek(2)

	local t = {}
	parse_cse_alife_object_properties_packet(t,stpk)
	parse_cse_shape_properties_packet(t,stpk)
	parse_cse_alife_space_restrictor_properties_packet(t,stpk)
	parse_cse_alife_level_changer_properties_packet(t,stpk)
	parse_se_level_changer_properties_packet(t,stpk)
	return t
end

function set_level_changer_data(t,sobj)
	if sobj then
		stpk:w_begin(0)
		fill_cse_alife_object_properties_packet(t,stpk)
		fill_cse_shape_properties_packet(t,stpk)
		fill_cse_alife_space_restrictor_properties_packet(t,stpk)
		fill_cse_alife_level_changer_properties_packet(t,stpk)
		fill_se_level_changer_properties_packet(t,stpk)
		local size = stpk:w_tell()
		stpk:r_seek(2)
		
		sobj:STATE_Read(stpk,size)
	end
end


function get_item_update_data(sobj)
	if not sobj then
		return
	end
	uppk:w_begin(0)
	sobj:UPDATE_Write(uppk)
	if (uppk:r_eof()) then 
		return
	end
	uppk:r_seek(2)
	local t = {}
	if data_left(uppk) then
		t.upd_num_items = uppk:r_u8()
		if (t.upd_num_items > 0) then
			t.upd_ph_force = read_chunk(uppk, 3, "s32")
			t.upd_ph_torque = read_chunk(uppk, 3, "s32")
			t.upd_ph_position = read_chunk(uppk, 3, "float")
			t.upd_ph_rotation = read_chunk(uppk, 4, "float")
			if bit_and(t.upd_num_items, 64) == 0 then
				if uppk:r_elapsed() >= 12 then
					t.upd_ph_angular_vel = read_chunk(uppk, 3, "float")
				else
					printf("cse_alife_item::update_read => cannot read 'upd:ph_angular_vel'")
					return
				end
			end
			if bit_and(t.upd_num_items, 128) == 0 then
				if uppk:r_elapsed() >= 12 then
					t.upd_ph_linear_vel = read_chunk(uppk, 3, "float")
				else
					printf("cse_alife_item::update_read => cannot read 'upd:ph_linear_vel'")
					return
				end
			end
			if data_left(uppk) then
				t.upd_cse_alife_item__marker_one = uppk:r_u8()
			end
		end
		if data_left(uppk) then
			t.upd_torch_flags = uppk:r_u8()
		end
	end
	return t
end

function set_item_update_data(t,sobj)
	if sobj then
		uppk:w_begin(0)
		if t.upd_num_items ~= nil then
			uppk:w_u8(t.upd_num_items)
			if t.upd_num_items ~= 0 then
				write_chunk(uppk, t.upd_ph_force, "s32")
				write_chunk(uppk, t.upd_ph_torque, "s32")
				write_chunk(uppk, t.upd_ph_position, "float")
				write_chunk(uppk, t.upd_ph_rotation, "float")
				write_chunk(uppk, t.upd_ph_angular_vel, "float")
				write_chunk(uppk, t.upd_ph_linear_vel, "float")
				if t.upd_cse_alife_item__marker_one ~= nil then
					uppk:w_u8(t.upd_cse_alife_item__marker_one)
				end
			end
		end
		if (t.upd_torch_flags) then
			uppk:w_u8(t.upd_torch_flags)
		end
		local size = uppk:w_tell()
		uppk:r_seek(2)
		sobj:UPDATE_Read(uppk,size)
	end
end

----------------------------------------------------------------------------
----------------------------------------------------------------------------

-- cse_abstract_properties
function parse_cse_abstract_properties_packet(ret,stpk)
    t.dummy16 = stpk:r_u16()
    t.section_name = stpk:r_stringZ()
    t.name = stpk:r_stringZ()
    t.s_gameid = stpk:r_u8()
    t.s_rp = stpk:r_u8()
	t.position = vector()
    stpk:r_vec3(t.position)
	t.direction = vector()
    stpk:r_vec3(t.direction)
    t.respawn_time = stpk:r_u16()
    t.object_id = stpk:r_u16()
    t.parent_id = stpk:r_u16()
    t.phantom_id = stpk:r_u16()
    t.s_flags = stpk:r_u16()
    t.version = stpk:r_u16()
    t.cse_abstract__unk1_h16 = stpk:r_u16()
    t.script_version = stpk:r_u16()
    t.unused = stpk:r_u16()
    if t.unused > 0 then
	t.extra = {}
	for i = 1, t.unused do
	    t.extra[i] = stpk:r_u8()
	end
    end
    t.spawn_id = stpk:r_u16()
    t.extended_size = stpk:r_u16()
    return t
end

function fill_cse_abstract_properties_packet(ret,stpk)
	stpk:w_u16(ret.dummy16)
	stpk:w_stringZ(ret.section_name)
	stpk:w_stringZ(ret.name)
	stpk:w_u8(ret.s_gameid)
	stpk:w_u8(ret.s_rp)
	stpk:w_vec3(ret.position)
	stpk:w_vec3(ret.direction)
	stpk:w_u16(ret.respawn_time)
	stpk:w_u16(ret.object_id)
	stpk:w_u16(ret.parent_id)
	stpk:w_u16(ret.phantom_id)
	stpk:w_u16(ret.s_flags)
	stpk:w_u16(ret.version)
	stpk:w_u16(ret.cse_abstract__unk3_u16)
	stpk:w_u16(ret.script_version)
	stpk:w_u16(ret.unused)
	if (ret.unused > 0 and ret.extra ~= nil) then
	for i = 1, ret.unused do
	    stpk:w_u8(ret.extra[i])
	end
    end
	stpk:w_u16(ret.spawn_id)
	stpk:w_u16(ret.extended_size)
end

-- cse_alife_graph_point_properties
function parse_cse_alife_graph_point_properties_packet(ret,stpk)
	ret.connection_point_name = stpk:r_stringZ()
	ret.connection_level_name = stpk:r_stringZ()
	ret.location0 = stpk:r_u8()
	ret.location1 = stpk:r_u8()
	ret.location2 = stpk:r_u8()
	ret.location3 = stpk:r_u8()
	return ret
end

function fill_cse_alife_graph_point_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.connection_point_name)
	stpk:w_stringZ(ret.connection_level_name)
	stpk:w_u8(ret.location0)
	stpk:w_u8(ret.location1)
	stpk:w_u8(ret.location2)
	stpk:w_u8(ret.location3)
end

-- cse_shape_properties
function parse_cse_shape_properties_packet(ret,stpk)
	local shape_count = stpk:r_u8()
	ret.shapes = {}
	if (shape_count > 0) then
		for i = 1, shape_count do
			local shape_type = stpk:r_u8()
			ret.shapes[i] = {}
			ret.shapes[i].shtype = shape_type
			if shape_type == 0 then
				-- sphere
				ret.shapes[i].center = vector()
				stpk:r_vec3(ret.shapes[i].center)
				ret.shapes[i].radius = stpk:r_float()
			else
				-- box
				ret.shapes[i].v1 = vector()
				ret.shapes[i].v2 = vector()
				ret.shapes[i].v3 = vector()
				ret.shapes[i].offset = vector()
				stpk:r_vec3(ret.shapes[i].v1)
				stpk:r_vec3(ret.shapes[i].v2)
				stpk:r_vec3(ret.shapes[i].v3)
				stpk:r_vec3(ret.shapes[i].offset)
			end
		end
	end
	return ret
end

function fill_cse_shape_properties_packet(ret,stpk)
	local shape_count = table.getn(ret.shapes)
	stpk:w_u8(shape_count or 0)
	if (shape_count > 0) then
		for i = 1, shape_count do
			stpk:w_u8(ret.shapes[i].shtype)
			if ret.shapes[i].shtype == 0 then
				-- sphere
				stpk:w_vec3(ret.shapes[i].center)
				stpk:w_float(ret.shapes[i].radius)
			else
				-- box
				stpk:w_vec3(ret.shapes[i].v1)
				stpk:w_vec3(ret.shapes[i].v2)
				stpk:w_vec3(ret.shapes[i].v3)
				stpk:w_vec3(ret.shapes[i].offset)
			end
		end
	end
end

-- cse_visual_properties
function parse_cse_visual_properties_packet(ret,stpk)
	ret.visual_name = stpk:r_stringZ()
	ret.visual_flags = stpk:r_u8()
	return ret
end

function fill_cse_visual_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.visual_name)
	stpk:w_u8(ret.visual_flags)
end

-- cse_motion_properties
function parse_cse_motion_properties_packet(ret,stpk)
	ret.motion_name = stpk:r_stringZ()
	return ret
end

function fill_cse_motion_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.motion_name)
end

-- cse_ph_skeleton_properties
function parse_cse_ph_skeleton_properties_packet(ret,stpk)
	ret.skeleton_name = stpk:r_stringZ()
	ret.skeleton_flags = stpk:r_u8()
	ret.source_id = stpk:r_u16()
	return ret
end

function fill_cse_ph_skeleton_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.skeleton_name)
	stpk:w_u8(ret.skeleton_flags)
	stpk:w_u16(ret.source_id)
end

--[[
local object_flags = {
		[1] = "flUseSwitches",
		[2] = "flSwitchOnline",
		[4] = "flSwitchOffline",
		[8] = "flInteractive",
		[16] = "flVisibleForAI",
		[32] = "flUsefulForAI",
		[64] = "flOfflineNoMove",
		[128] = "flUsedAI_Locations",
		[256] = "flUseGroupBehaviour",
		[512] = "flCanSave",
		[1024] = "flVisibleForMap",
		[2048] = "flUseSmartTerrains",
		[4096] = "flCheckForSeparator",
		[8192] = "flCorpseRemoval"
}
--]]

-- cse_alife_object_properties
function parse_cse_alife_object_properties_packet(ret,stpk)
	ret.game_vertex_id = stpk:r_u16()
	ret.distance = stpk:r_float()
	ret.direct_control = stpk:r_s32()
	ret.level_vertex_id = stpk:r_s32()
	ret.object_flags = stpk:r_s32()
	ret.custom_data = stpk:r_stringZ()
	ret.story_id = stpk:r_s32()
	ret.spawn_story_id = stpk:r_s32()
	return ret
end

function fill_cse_alife_object_properties_packet(ret,stpk)
	stpk:w_u16(ret.game_vertex_id)
	stpk:w_float(ret.distance)
	stpk:w_s32(ret.direct_control)
	stpk:w_s32(ret.level_vertex_id)
	stpk:w_s32(ret.object_flags)
	stpk:w_stringZ(ret.custom_data)
	stpk:w_s32(ret.story_id)
	stpk:w_s32(ret.spawn_story_id)
end

-- cse_alife_object_climable_properties
function parse_cse_alife_object_climable_properties_packet(ret,stpk)
	ret.game_material = stpk:r_stringZ()
	return ret
end

function fill_cse_alife_object_climable_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.game_material)
end

-- cse_smart_cover_properties
function parse_cse_smart_cover_properties_packet(ret,stpk)
	ret.description = stpk:r_stringZ()
	ret.unk2_f32 = stpk:r_float()
	ret.enter_min_enemy_distance = stpk:r_float()
	ret.exit_min_enemy_distance = stpk:r_float()
	ret.is_combat_cover = stpk:r_u8()
	ret.can_fire = stpk:r_u8()
end

function fill_cse_smart_cover_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.description)
	stpk:w_float(ret.unk2_f32)
	stpk:w_float(ret.enter_min_enemy_distance)
	stpk:w_float(ret.exit_min_enemy_distance)
	stpk:w_u8(ret.is_combat_cover)
	stpk:w_u8(ret.can_fire)
end

-- se_smart_cover_properties
function parse_se_smart_cover_properties_packet(ret,stpk)
	if (data_left(stpk)) then
		local n = stpk:r_u8()
		for i = 1, n do
			local loophole_id = stpk:r_stringZ()
			local loophole_exist = stpk:r_bool()
			if not ret.loopholes then
				ret.loopholes = {}
			end
			ret.loopholes[loophole_id] = loophole_exist
		end
	end
	return ret
end

function fill_se_smart_cover_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.last_description)
	local n = table.size(ret.loopholes)
	stpk:w_u8(n)
	for k,v in pairs (ret.loopholes) do
		stpk:w_stringZ(k)
		stpk:w_bool(v)
	end
end

-- cse_alife_object_physic_properties
function parse_cse_alife_object_physic_properties_packet(ret,stpk)
	ret.physic_type = stpk:r_s32()
	ret.mass = stpk:r_float()
	ret.fixed_bones = stpk:r_stringZ()
	return ret
end

function fill_cse_alife_object_physic_properties_packet(ret,stpk)
	stpk:w_s32(ret.physic_type)
	stpk:w_float(ret.mass)
	stpk:w_stringZ(ret.fixed_bones)
end

-- cse_alife_object_hanging_lamp_properties
function parse_cse_alife_object_hanging_lamp_properties_packet(ret,stpk)
	ret.main_color = stpk:r_u32()
	ret.main_brightness = stpk:r_float()
	ret.main_color_animator = stpk:r_stringZ()
	ret.main_range = stpk:r_float()
	ret.light_flags = stpk:r_u16()
	ret.startup_animation = stpk:r_stringZ()
	ret.lamp_fixed_bones = stpk:r_stringZ()
	ret.health = stpk:r_float()
	ret.main_virtual_size = stpk:r_float()
	ret.ambient_radius = stpk:r_float()
	ret.ambient_power = stpk:r_float()
	ret.ambient_texture = stpk:r_stringZ()
	ret.main_texture = stpk:r_stringZ()
	ret.main_bone = stpk:r_stringZ()
	ret.main_cone_angle = stpk:r_float()
	ret.glow_texture = stpk:r_stringZ()
	ret.glow_radius = stpk:r_float()
	ret.ambient_bone = stpk:r_stringZ()
	ret.volumetric_quality = stpk:r_float()
	ret.volumetric_intensity = stpk:r_float()
	ret.volumetric_distance = stpk:r_float()
	return ret
end

function fill_cse_alife_object_hanging_lamp_properties_packet(ret,stpk)
	stpk:w_u32(ret.main_color)
	stpk:w_float(ret.main_brightness)
	stpk:w_stringZ(ret.main_color_animator)
	stpk:w_float(ret.main_range)
	stpk:w_u16(ret.light_flags)
	stpk:w_stringZ(ret.startup_animation)
	stpk:w_stringZ(ret.lamp_fixed_bones)
	stpk:w_float(ret.health)
	stpk:w_float(ret.main_virtual_size)
	stpk:w_float(ret.ambient_radius)
	stpk:w_float(ret.ambient_power)
	stpk:w_stringZ(ret.ambient_texture)
	stpk:w_stringZ(ret.main_texture)
	stpk:w_stringZ(ret.main_bone)
	stpk:w_float(ret.main_cone_angle)
	stpk:w_stringZ(ret.glow_texture)
	stpk:w_float(ret.glow_radius)
	stpk:w_stringZ(ret.ambient_bone)
	stpk:w_float(ret.volumetric_quality)
	stpk:w_float(ret.volumetric_intensity)
	stpk:w_float(ret.volumetric_distance)
end

-- cse_alife_inventory_box_properties
function parse_cse_alife_inventory_box_properties_packet(ret,stpk)
	ret.unk1_u8 = stpk:r_u8()
	ret.unk2_u8 = stpk:r_u8()
	ret.tip = stpk:r_stringZ()
	return ret
end

function fill_cse_alife_inventory_box_properties_packet(ret,stpk)
	stpk:w_u8(ret.unk1_u8)
	stpk:w_u8(ret.unk2_u8)
	stpk:w_stringZ(ret.tip)
end

-- cse_alife_object_breakable_properties
function parse_cse_alife_object_breakable_properties_packet(ret,stpk)
	ret.health = stpk:r_float()
	return ret
end

function fill_cse_alife_object_breakable_properties_packet(ret,stpk)
	stpk:w_float(ret.health)
end

-- cse_alife_helicopter_properties
function parse_cse_alife_helicopter_properties_packet(ret,stpk)
	ret.startup_animation = stpk:r_stringZ()
	ret.engine_sound = stpk:r_stringZ()
	return ret
end

function fill_cse_alife_helicopter_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.startup_animation or "idle")
	stpk:w_stringZ(ret.engine_sound)
end

-- cse_alife_creature_abstract_properties
function parse_cse_alife_creature_abstract_properties_packet(ret,stpk)
	ret.g_team = stpk:r_u8()
	ret.g_squad = stpk:r_u8()
	ret.g_group = stpk:r_u8()
	ret.health = stpk:r_float()
	ret.dynamic_out_restrictions = read_chunk(stpk, stpk:r_s32(), "u16")
	ret.dynamic_in_restrictions = read_chunk(stpk, stpk:r_s32(), "u16")
	ret.killer_id = stpk:r_u16()
	ret.game_death_time = read_chunk(stpk, 8, "u8")
	return ret
end

function fill_cse_alife_creature_abstract_properties_packet(ret,stpk)
	stpk:w_u8(ret.g_team)
	stpk:w_u8(ret.g_squad)
	stpk:w_u8(ret.g_group)
	stpk:w_float(ret.health)

	stpk:w_s32(#ret.dynamic_out_restrictions)
	write_chunk(stpk, ret.dynamic_out_restrictions, "u16")

	stpk:w_s32(#ret.dynamic_in_restrictions)
	write_chunk(stpk, ret.dynamic_in_restrictions, "u16")

	stpk:w_u16(ret.killer_id)
	write_chunk(stpk, ret.game_death_time, "u8")
end

-- cse_alife_monster_abstract_properties
function parse_cse_alife_monster_abstract_properties_packet(ret,stpk)
	ret.base_out_restrictors = stpk:r_stringZ()
	ret.base_in_restrictors = stpk:r_stringZ()
	ret.smart_terrain_id = stpk:r_u16()
	ret.smart_terrain_task_active = stpk:r_u8()
	return ret
end

function fill_cse_alife_monster_abstract_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.base_out_restrictors)
	stpk:w_stringZ(ret.base_in_restrictors)
	stpk:w_u16(ret.smart_terrain_id)
	stpk:w_u8(ret.smart_terrain_task_active)
end

-- cse_alife_trader_abstract_properties
function parse_cse_alife_trader_abstract_properties_packet(ret,stpk)
	ret.money = stpk:r_u32()
	ret.specific_character = stpk:r_stringZ()
	ret.trader_flags = stpk:r_s32()
	ret.character_profile = stpk:r_stringZ()
	ret.community_index = stpk:r_s32()
	ret.rank = stpk:r_s32()
	ret.reputation = stpk:r_s32()
	ret.character_name = stpk:r_stringZ()
	ret.dead_body_can_take = stpk:r_u8()
	ret.dead_body_closed = stpk:r_u8()
	return ret
end

function fill_cse_alife_trader_abstract_properties_packet(ret,stpk)
	stpk:w_u32(ret.money)
	stpk:w_stringZ(ret.specific_character)
	stpk:w_s32(ret.trader_flags)
	stpk:w_stringZ(ret.character_profile)
	stpk:w_s32(ret.community_index)
	stpk:w_s32(ret.rank)
	stpk:w_s32(ret.reputation)
	stpk:w_stringZ(ret.character_name)
	stpk:w_u8(ret.dead_body_can_take)
	stpk:w_u8(ret.dead_body_closed)
end

-- cse_alife_human_abstract_properties
function parse_cse_alife_human_abstract_properties_packet(ret,stpk)
	ret.equipment_preferences = read_chunk(stpk, stpk:r_s32(), "u8")
	ret.weapon_preferences = read_chunk(stpk, stpk:r_s32(), "u8")
end

function fill_cse_alife_human_abstract_properties_packet(ret,stpk)
	stpk:w_s32(#ret.equipment_preferences)
	write_chunk(stpk, ret.equipment_preferences, "u8")

	stpk:w_s32(#ret.weapon_preferences)
	write_chunk(stpk, ret.weapon_preferences, "u8")
end

-- se_stalker_properties
function parse_se_stalker_properties_packet(ret,stpk)
	if data_left(stpk) then
		ret.old_lvid = stpk:r_stringZ()
		ret.active_section = stpk:r_stringZ()
		ret.death_droped = stpk:r_bool()
	end
	return ret
end

function fill_se_stalker_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.old_lvid)
	stpk:w_stringZ(ret.active_section)
	stpk:w_bool(ret.death_droped)
end

-- cse_alife_creature_actor_properties
function parse_cse_alife_creature_actor_properties_packet(ret,stpk,upd)
	if (upd) then
		ret.upd_actor_state = stpk:r_u16()
		ret.upd_actor_accel_header = stpk:r_u16()
		ret.upd_actor_accel_data = stpk:r_s32()
		ret.upd_actor_velocity_header = stpk:r_u16()
		ret.upd_actor_velocity_data = stpk:r_s32()
		ret.upd_actor_radiation = stpk:r_float()
		ret.upd_actor_weapon = stpk:r_u8()
		ret.upd_num_items = stpk:r_u16()
	else
		ret.holder_id = stpk:r_u16()
	end
	return ret
end

function fill_cse_alife_creature_actor_properties_packet(ret,stpk,upd)
	if (upd) then
		stpk:w_u16(ret.upd_actor_state)
		stpk:w_u16(ret.upd_actor_accel_header)
		stpk:w_s32(ret.upd_actor_accel_data)
		stpk:w_u16(ret.upd_actor_velocity_header)
		stpk:w_s32(ret.upd_actor_velocity_data)
		stpk:w_float(ret.upd_actor_radiation)
		stpk:w_u8(ret.upd_actor_weapon)
		stpk:w_u16(ret.upd_num_items)
	else
		stpk:w_u16(ret.holder_id)
	end
end

-- se_actor_properties
function parse_se_actor_properties_packet(ret,stpk)
	if data_left(stpk) then
		ret.start_position_filled = stpk:r_bool()
		ret.se_actor_save_marker = stpk:r_u16()
	end
	return ret
end

function fill_se_actor_properties_packet(ret,stpk)
	if ret.start_position_filled ~= nil then
		stpk:w_bool(ret.start_position_filled)
		stpk:w_u16(ret.se_actor_save_marker)
	end
end

-- cse_alife_monster_base_properties
function parse_cse_alife_monster_base_properties_packet(ret,stpk)
	ret.spec_object_id = stpk:r_u16()
	return ret
end

function fill_cse_alife_monster_base_properties_packet(ret,stpk)
	stpk:w_u16(ret.spec_object_id)
end

-- se_monster_properties
function parse_se_monster_properties_packet(ret,stpk)
	ret.off_level_vertex_id = stpk:r_stringZ()
	ret.active_section = stpk:r_stringZ()
	return ret
end

function fill_se_monster_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.off_level_vertex_id)
	stpk:w_stringZ(ret.active_section)
end

-- cse_alife_monster_zombie_properties
function parse_cse_alife_monster_zombie_properties_packet(ret,stpk)
	ret.field_of_view = stpk:r_float()
	ret.eye_range = stpk:r_float()
	ret.minimum_speed = stpk:r_float()
	ret.maximum_speed = stpk:r_float()
	ret.attack_speed = stpk:r_float()
	ret.pursuit_distance = stpk:r_float()
	ret.home_distance = stpk:r_float()
	ret.hit_power = stpk:r_float()
	ret.hit_interval = stpk:r_u16()
	ret.distance = stpk:r_float()
	ret.maximum_angle = stpk:r_float()
end

function fill_cse_alife_monster_zombie_properties_packet(ret,stpk)
	stpk:w_float(ret.field_of_view)
	stpk:w_float(ret.eye_range)
	stpk:w_float(ret.minimum_speed)
	stpk:w_float(ret.maximum_speed)
	stpk:w_float(ret.attack_speed)
	stpk:w_float(ret.pursuit_distance)
	stpk:w_float(ret.home_distance)
	stpk:w_float(ret.hit_power)
	stpk:w_u16(ret.hit_interval)
	stpk:w_float(ret.distance)
	stpk:w_float(ret.maximum_angle)
end

-- cse_alife_space_restrictor_properties
function parse_cse_alife_space_restrictor_properties_packet(ret,stpk)
	--[[
		[0] = "NONE default restrictor",
		[1] = "OUT default restrictor",
		[2] = "IN default restrictor",
		[3] = "NOT A restrictor"
	--]]
	ret.restrictor_type = stpk:r_u8()
end

function fill_cse_alife_space_restrictor_properties_packet(ret,stpk)
	stpk:w_u8(ret.restrictor_type)
end

-- se_anomaly_field_properties
function parse_se_anomaly_field_properties_packet(ret,stpk)
	ret.initialized = stpk:r_u8()
end

function fill_se_anomaly_field_properties_packet(ret,stpk)
	stpk:w_u8(ret.initialized)
end

-- se_respawn_properties
function parse_se_respawn_properties_packet(ret,stpk)
	if data_left(stpk) then
		ret.spawned_obj_count = stpk:r_u8()
		ret.spawned_obj_ids = read_chunk(stpk, ret.spawned_obj_count, "u16")
	end
end

function fill_se_respawn_properties_packet(ret,stpk)
	write_chunk(stpk, ret.spawned_obj_ids, "u16")
end

-- cse_alife_team_base_zone_properties
function parse_cse_alife_team_base_zone_properties_packet(ret,stpk)
	ret.team = stpk:r_u8()
end

function fill_cse_alife_team_base_zone_properties_packet(ret,stpk)
	stpk:w_u8(ret.team)
end

-- cse_alife_level_changer_properties
function parse_cse_alife_level_changer_properties_packet(ret,stpk)
	ret.dest_game_vertex_id = stpk:r_u16()
	ret.dest_level_vertex_id = stpk:r_s32()
	ret.dest_position = vector()
	stpk:r_vec3(ret.dest_position)
	ret.dest_direction = vector()
	stpk:r_vec3(ret.dest_direction)
	ret.dest_level_name = stpk:r_stringZ()
	ret.dest_graph_point = stpk:r_stringZ()
	ret.silent_mode = stpk:r_u8()
	return ret
end

function fill_cse_alife_level_changer_properties_packet(ret,stpk)
	stpk:w_u16(ret.dest_game_vertex_id)
	stpk:w_s32(ret.dest_level_vertex_id)
	stpk:w_vec3(ret.dest_position)
	stpk:w_vec3(ret.dest_direction)
	stpk:w_stringZ(ret.dest_level_name)
	stpk:w_stringZ(ret.dest_graph_point)
	stpk:w_u8(ret.silent_mode)
end

-- se_level_changer_properties
function parse_se_level_changer_properties_packet(ret,stpk)
	if (data_left(stpk)) then
		ret.enabled = stpk:r_bool()
		ret.hint = stpk:r_stringZ()
		ret.se_level_changer_save_marker = stpk:r_u16()
	end
end

function fill_se_level_changer_properties_packet(ret,stpk)
	stpk:w_bool(ret.enabled or true)
	stpk:w_stringZ(ret.hint or "")
	stpk:w_u16(ret.se_level_changer_save_marker or 0)
end

-- se_respawn_properties
function parse_se_respawn_properties_packet(ret,stpk)

end

function fill_se_respawn_properties_packet(ret,stpk)
	write_chunk(stpk, ret.spawned_obj_ids, "u16")
end

-- cse_alife_custom_zone_properties
function parse_cse_alife_custom_zone_properties_packet(ret,stpk)
	ret.max_power = stpk:r_float()
	ret.owner_id = stpk:r_s32()
	ret.enabled_time = stpk:r_s32()
	ret.disabled_time = stpk:r_s32()
	ret.start_time_shift = stpk:r_s32()
end

function fill_cse_alife_custom_zone_properties_packet(ret,stpk)
	stpk:w_float(ret.max_power)
	stpk:w_s32(ret.owner_id)
	stpk:w_s32(ret.enabled_time)
	stpk:w_s32(ret.disabled_time)
	stpk:w_s32(ret.start_time_shift)
end

-- cse_alife_anomalous_zone_properties
function parse_cse_alife_anomalous_zone_properties_packet(ret,stpk)
	ret.offline_interactive_radius = stpk:r_float()
	ret.artefact_spawn_count = stpk:r_u16()
	ret.artefact_position_offset = stpk:r_s32()
end

function fill_cse_alife_anomalous_zone_properties_packet(ret,stpk)
	stpk:w_float(ret.offline_interactive_radius)
	stpk:w_u16(ret.artefact_spawn_count)
	stpk:w_s32(ret.artefact_position_offset)
end

-- se_zone_properties
function parse_se_zone_properties_packet(ret,stpk)
	if data_left(stpk) then
		ret.last_spawn_time = stpk:r_u8()
		if ret.last_spawn_time == 1 then
			if data_left(stpk) then
				ret.c_time = utils.r_CTime(stpk)
			end
		end
	end
end

function fill_se_zone_properties_packet(ret,stpk)
	if ret.last_spawn_time ~= nil then
		stpk:w_u8(ret.last_spawn_time)
		if ret.last_spawn_time == 1 then
			utils.w_CTime(stpk, ret.c_time)
		end
	else
		stpk:w_u8(0)
	end
end

-- cse_alife_zone_visual_properties
function parse_cse_alife_zone_visual_properties_packet(ret,stpk)
	ret.idle_animation = stpk:r_stringZ()
	ret.attack_animation = stpk:r_stringZ()
end

function fill_cse_alife_zone_visual_properties_packet(ret,stpk)
	stpk:w_stringZ(ret.idle_animation or "idle")
	stpk:w_stringZ(ret.attack_animation or "blast")
end

-- cse_alife_online_offline_group_properties
function parse_cse_alife_online_offline_group_properties_packet(ret,stpk)
	ret.members_count = stpk:r_s32()
	ret.members = read_chunk(stpk, ret.members_count, "u16")
	if data_left(stpk) then
		-- sim_squad_scripted:
		ret.current_target_id = stpk:r_stringZ()
		ret.respawn_point_id = stpk:r_stringZ()
		ret.respawn_point_prop_section = stpk:r_stringZ()
		ret.smart_id = stpk:r_stringZ()
		ret.sim_squad_scripted_save_marker = stpk:r_u16()
	end
end

function fill_cse_alife_online_offline_group_properties_packet(ret,stpk)
	stpk:w_s32(ret.members_count)
	write_chunk(stpk, ret.members, "u16")

	--if ret.current_target_id ~= nil then
		stpk:w_stringZ(ret.current_target_id or "nil")
		stpk:w_stringZ(ret.respawn_point_id or "nil")
		stpk:w_stringZ(ret.respawn_point_prop_section or "nil")
		stpk:w_stringZ(ret.smart_id or "nil")
		stpk:w_u16(ret.sim_squad_scripted_save_marker or 0)
	--end
end

-- cse_alife_item_properties
function parse_cse_alife_item_properties_packet(ret,stpk)
	ret.condition = stpk:r_float()
	ret.upgrades = readvu32stringZ(stpk)
end

function fill_cse_alife_item_properties_packet(ret,stpk)
	stpk:w_float(ret.condition)
	writevu32stringZ(stpk,ret.upgrades)
end

-- cse_alife_item_weapon_properties
function parse_cse_alife_item_weapon_properties_packet(ret,stpk)
	ret.ammo_current = stpk:r_u16()
	ret.ammo_elapsed = stpk:r_u16()
	ret.weapon_state = stpk:r_u8()
	ret.addon_flags = stpk:r_u8()
	ret.ammo_type = stpk:r_u8()
	ret.xz1 = stpk:r_u8()
	return ret
end

function fill_cse_alife_item_weapon_properties_packet(ret,stpk)
	stpk:w_u16(ret.ammo_current)
	stpk:w_u16(ret.ammo_elapsed)
	stpk:w_u8(ret.weapon_state)
	stpk:w_u8(ret.addon_flags)
	stpk:w_u8(ret.ammo_type)
	stpk:w_u8(ret.xz1)
	return ret
end

-- se_sim_faction_properties
function parse_se_sim_faction_properties_packet(ret,stpk)
	if data_left(stpk) then
		ret.community_player = stpk:r_bool()
		ret.start_position_filled = stpk:r_bool()
		ret.current_expansion_level = stpk:r_u8()
		ret.last_spawn_time = utils.r_CTime(stpk)

		local tmp = nil
		local num = nil

		ret.squad_target_cache_count = stpk:r_u8()
		if ret.squad_target_cache_count > 0 then
			ret.squad_target_cache = {}
			for i = 1, ret.squad_target_cache_count do
				tmp = stpk:r_stringZ()
				num = stpk:r_u16()
				ret.squad_target_cache[tmp] = num
			end
		end

		ret.random_tasks_count = stpk:r_u8()
		if ret.random_tasks_count > 0 then
			ret.random_tasks = {}
			for i = 1, ret.random_tasks_count do
				tmp = stpk:r_u16()
				num = stpk:r_u16()
				ret.random_tasks[tmp] = num
			end
		end

		ret.current_attack_quantity_count = stpk:r_u8()
		if ret.current_attack_quantity_count > 0 then
			ret.current_attack_quantity = {}
			for i = 1, ret.current_attack_quantity_count do
				tmp = stpk:r_u16()
				num = stpk:r_u8()
				ret.current_attack_quantity[tmp] = num
			end
		end

		ret.squads_count = stpk:r_u16()
		if ret.squads_count > 0 then
			ret.init_squad_queue = {}
			for i = 1, ret.squads_count do
				local squad_id = stpk:r_stringZ()
				local settings_id = stpk:r_stringZ()
				local flag = stpk:r_bool()
			end
		end

		ret.se_sim_faction_save_marker = stpk:r_u16()
	end
end

function fill_se_sim_faction_properties_packet(ret,stpk)
	if ret.community_player ~= nil then
		stpk:w_bool(ret.community_player)
		stpk:w_bool(ret.start_position_filled)
		stpk:w_u8(ret.current_expansion_level)
		utils.w_CTime(stpk, ret.last_spawn_time)

		stpk:w_u8(ret.squad_target_cache_count)
		if ret.squad_target_cache ~= nil then
			for k, v in pairs(ret.squad_target_cache) do
				stpk:w_stringZ(k)
				stpk:w_u16(v)
			end
		end

		stpk:w_u8(ret.random_tasks_count)
		if ret.random_tasks ~= nil then
			for k, v in pairs(ret.random_tasks) do
				stpk:w_u16(k)
				stpk:w_u16(v)
			end
		end

		stpk:w_u8(ret.current_attack_quantity_count)
		if ret.current_attack_quantity ~= nil then
			for k, v in pairs(ret.current_attack_quantity) do
				stpk:w_u16(k)
				stpk:w_u8(v)
			end
		end

		stpk:w_u16(ret.squads_count)
	end
end

------------------------------------------------------------------
------------------------------------------------------------------
function data_left(stpk)
	return (stpk:r_elapsed() ~= 0)
end

function read_chunk(stpk, length, c_type)
	local tab = {}
	for i = 1, length do
		if c_type == "u8" then
			tab[i] = stpk:r_u8()
		elseif c_type == "u16" then
			tab[i] = stpk:r_u16()
		elseif c_type == "u32" then
			tab[i] = stpk:r_u32()
		elseif c_type == "s32" then
			tab[i] = stpk:r_s32()
		elseif c_type == "float" then
			tab[i] = stpk:r_float()
		elseif c_type == "string" then
			tab[i] = stpk:r_stringZ()
		elseif c_type == "bool" then
			tab[i] = stpk:r_bool()
		end
	end
	return tab
end
function write_chunk(stpk, tab, c_type)
	if tab == nil then
		return
	end
	for k, v in ipairs(tab) do
		if c_type == "u8" then
			stpk:w_u8(v)
		elseif c_type == "u16" then
			stpk:w_u16(v)
		elseif c_type == "u32" then
			stpk:w_u32(v)
		elseif c_type == "s32" then
			stpk:w_s32(v)
		elseif c_type == "float" then
			stpk:w_float(v)
		elseif c_type == "string" then
			stpk:w_stringZ(v)
		elseif c_type == "bool" then
			stpk:w_bool(v)
		end
	end
end
function readvu8uN(stpk,cnt)
	local v = {}
	for i=1,cnt do
		v[i] = stpk:r_u8()
	end
	return v
end
function writevu8uN(stpk,v)
	for i=1,#v,1 do
		stpk:w_u8(v[i])
	end
end
function readvu32stringZ(stpk)
	local v = {}
	local cnt = stpk:r_s32()
	for i=1,cnt do
		v[i] = stpk:r_stringZ()
	end
	return v
end
function writevu32stringZ(pk,v)
	v = v or {}
	local len = #v
	pk:w_s32(len)
	for i=1,len do
		pk:w_stringZ(v[i])
	end
end

--/-------------------------------------------------------------------
--/ Строковые функции
--/-------------------------------------------------------------------
--/ для правильного парсинга запрещены комментарии!!!
function parse_custom_data(str)
	local t = {}
	if str then
		for section, section_data in string.gmatch(str,"%s*%[([^%]]*)%]%s*([^%[%z]*)%s*") do
			section = string.trim(section)
			t[section] = {}
			for line in string.gmatch(string.trim(section_data), "([^\n]*)\n*") do
				if string.find(line,"=") ~= nil then
					for k, v in string.gmatch(line, "([^=]-)%s*=%s*(.*)") do
						k = string.trim(k)
						if k ~= nil and k ~= "" and v ~= nil then
							t[section][k] = string.trim(v)
						end
					end
				else
					for k, v in string.gmatch(line, "(.*)") do
						k = string.trim(k)
						if k ~= nil and k ~= "" then
							t[section][k] = "<<no_value>>"
						end
					end
				end
			end
		end
	end
	return t
end

function gen_custom_data(tbl)
	local str = ""
	for key, value in pairs(tbl) do
		str = str.."\n["..key.."]\n"
		for k, v in pairs(value) do
			if v ~= "<<no_value>>" then
				if type(v) == "table" then
					store_table(v, "ABORT:["..key.."]>>")
					abort("TABLE NOT ALLOWED IN PARSE TABLE")
				end
				str = str..k.." = "..v.."\n"
			else
				str = str..k.."\n"
			end
		end
	end
	return str
end

-- return this