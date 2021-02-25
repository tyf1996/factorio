local util = require("util")
local get_walkable_tile = util.get_walkable_tile
local mod_gui = require("mod-gui")
local config = require("wave_defense_config")
local upgrades = require("wave_defense_upgrades")
local increment = util.increment
local format_number = util.format_number
local format_time = util.formattime
local insert = table.insert
local floor = math.floor
local ceil = math.ceil

local game_state =
{
  in_round = 1,
  in_preview = 2,
  defeat = 3,
  victory = 4
}

local script_data =
{
  config = config,
  difficulty = config.difficulties.normal,
  day_number = 1,
  money = 0,
  team_upgrades = {},
  gui_elements =
  {
    preview_frame = {},
    day_button = {},
    upgrade_frame_button = {},
    upgrade_frame = {},
    upgrade_table = {},
    admin_frame_button = {},
    admin_frame = {}
  },
  gui_labels =
  {
    money_label = {},
    time_label = {},
    day_label = {}
  },
  gui_actions = {},
  spawners = {},
  spawner_distances = {},
  spawner_path_requests = {},
  state = game_state.in_preview,
  random = nil,
  wave_tick = nil,
  spawn_time = nil,
  wave_time = nil,
  path_request_queue = {}
}

local get_starting_point = function()
  return {x = 0, y = 0}
end

local is_player_force = function(force)
  return force == game.forces.player
end

local get_preview_size = function()
  return 32 * 10
end

local script_events =
{
  on_round_started = script.generate_event_name()
}

local power_functions =
{
  default = function(level)
    return (level ^ 1.15) * 500 * ((#game.connected_players) ^ 0.5)
  end,
  hard = function(level)
    return (level ^ 1.2) * 500 * ((#game.connected_players) ^ 0.75)
  end
}

local speed_multiplier_functions =
{
  default = function(level)
    return (level ^ 0.1) - 0.2
  end
}

local set_daytime_settings = function()
  local surface = script_data.surface
  if not (surface and surface.valid) then return end
  local settings = script_data.difficulty.day_settings
  for name, value in pairs (settings) do
    surface[name] = value
  end
end

local max_seed = 2^32 - 2
local initial_seed = 2390375328

local players = function(index)
  return (index and game.get_player(index)) or game.players
end

function deregister_gui(gui)
  local player_gui_actions = script_data.gui_actions[gui.player_index]
  if not player_gui_actions then return end
  player_gui_actions[gui.index] = nil
  for k, child in pairs (gui.children) do
    deregister_gui(child)
  end
end

function register_gui_action(gui, param)
  local gui_actions = script_data.gui_actions
  local player_gui_actions = gui_actions[gui.player_index]
  if not player_gui_actions then
    gui_actions[gui.player_index] = {}
    player_gui_actions = gui_actions[gui.player_index]
  end
  player_gui_actions[gui.index] = param
end

function init_player_force()

  for name, upgrade in pairs (get_upgrades()) do
    script_data.team_upgrades[name] = 0
  end

  local force = game.forces.player
  force.reset()
  local surface = script_data.surface
  if surface and surface.valid then
    local size = get_preview_size()
    local starting_point = get_starting_point()
    force.chart(surface, {{starting_point.x - size, starting_point.y - size},{starting_point.x + (size - 32), starting_point.y + (size - 32)}})
  end
  set_research(force)
  set_recipes(force)

  force.disable_research()

end

function set_tiles_safe(surface, tiles)
  local grass = get_walkable_tile()
  local grass_tiles = {}
  for k, tile in pairs (tiles) do
    grass_tiles[k] = {position = {x = (tile.position.x or tile.position[1]), y = (tile.position.y or tile.position[2])}, name = grass}
  end
  surface.set_tiles(grass_tiles, false)
  surface.set_tiles(tiles)
end

local set_up_player = function(player)
  if not player.connected then return end
  gui_init(player)

  if not is_player_force(player.force) then return end

  if player.ticks_to_respawn then player.ticks_to_respawn = nil end

  if script_data.state == game_state.in_preview then
    if player.character then
      player.character.destroy()
    end
    player.spectator = true
    player.set_controller{type = defines.controllers.god}
    player.teleport({0,0}, game.surfaces.nauvis)
    player.create_character()
    return
  end

  if script_data.state == game_state.in_round or script_data.state == game_state.victory then
    local surface = script_data.surface
    if player.surface == surface then return end
    if player.character then
      player.character.destroy()
    end
    local force = game.forces.player
    local spawn = force.get_spawn_position(surface)
    player.teleport(spawn, surface)
    local character = surface.create_entity{name = "character", position = surface.find_non_colliding_position("character", spawn, 0, 1), force = force}
    player.set_controller{type = defines.controllers.character, character = character}
    give_respawn_equipment(player)
    player.print({"wave-defense-intro"})
    return
  end

  if script_data.state == game_state.defeat then
    if player.character then
      player.character.destroy()
    end
    local surface = script_data.surface
    local force = game.forces.player
    local position = force.get_spawn_position(surface)
    player.set_controller{type = defines.controllers.spectator}
    player.teleport(position, surface)
    return
  end

end

function set_up_players()
  for k, player in pairs (players()) do
    set_up_player(player)
  end
end

local init_enemy_force = function()
  local force = game.forces.enemy
  force.reset()
  force.evolution_factor = script_data.difficulty.starting_evolution_factor
end

function start_round()
  game.reset_time_played()
  local surface = script_data.surface
  surface.daytime = surface.dawn
  surface.always_day = false
  script_data.state = game_state.in_round
  local tick = game.tick
  script_data.money = 0
  script_data.day_number = 1
  --How often waves are sent
  script_data.wave_time = surface.ticks_per_day
  --How long waves last
  script_data.spawn_time = floor(surface.ticks_per_day * (surface.morning - surface.evening))
  --First spawn
  script_data.wave_tick = tick + ceil(surface.ticks_per_day * surface.evening) + ceil((1 - surface.dawn) * surface.ticks_per_day)
  script_data.dawn_tick = nil
  script_data.spawn_tick = nil
  script_data.end_spawn_tick = nil
  game.print({"start-round-message"})
  set_up_players()
  init_player_force()
  init_enemy_force()
  script.raise_event(script_events.on_round_started, {})
  for k, player in pairs (players()) do
    player.clear_recipe_notifications()
  end
end

function restart_round()
  script_data.game_state = game_state.in_preview
  set_up_players()
  local seed = script_data.surface.map_gen_settings.seed
  create_battle_surface(seed)
  start_round()
end

local get_random_seed = function()
  return (32452867 * game.tick) % max_seed
end

local get_starting_area_size = function()
  return script_data.difficulty.starting_area_size
end

local get_base_radius = function()
  return (32 * (floor(((script_data.surface.get_starting_area_radius() / 32) - 1) / (2 ^ 0.5))))
end

function create_battle_surface(seed)
  local index = 1
  local name = "Surface "
  while game.surfaces[name..index] do
    index = index + 1
  end
  name = name..index
  for k, surface in pairs (game.surfaces) do
    if surface.name ~= "nauvis" then
      game.delete_surface(surface.name)
    end
  end

  --Must be cleared before the new surface is generated, as these lists are updated on chunk_generated.
  script_data.spawners = {}
  script_data.spawner_distances = {}
  script_data.spawner_path_requests = {}
  script_data.path_request_queue = {}

  local settings = script_data.config.map_gen_settings
  local seed = seed or get_random_seed()
  script_data.random = game.create_random_generator(seed)
  settings.seed = seed
  settings.starting_area = get_starting_area_size()
  local starting_point = get_starting_point()
  settings.starting_points = {starting_point}

  settings.property_expression_names =
  {
    elevation = not script_data.config.infinite and "0_17-island" or nil
  }

  local surface = game.create_surface(name, settings)
  local size = get_preview_size()
  script_data.surface = surface
  set_daytime_settings()
  surface.request_to_generate_chunks(starting_point, 1 + ceil(get_base_radius() / 32))
  surface.force_generate_chunk_requests()
  --Must force generate the starting chunks before placing the silo, walls etc.
  create_silo(starting_point)
  create_wall(starting_point)
  create_turrets(starting_point)
  create_starting_chest(starting_point)
  game.forces.player.chart(surface, {{starting_point.x - size, starting_point.y - size},{starting_point.x + (size - 32), starting_point.y + (size - 32)}})
  for k, player in pairs (players()) do
    refresh_preview_gui(player)
  end
end

function create_silo(starting_point)
  local force = game.forces.player
  local surface = script_data.surface
  local silo_position = {starting_point.x, starting_point.y - 8}
  local silo_name = "rocket-silo"
  if not game.entity_prototypes[silo_name] then log("Silo not created as "..silo_name.." is not a valid entity prototype") return end
  local silo = surface.create_entity{name = silo_name, position = silo_position, force = force, raise_built = true, create_build_effect_smoke = false}
  if not (silo and silo.valid) then return end
  rendering.draw_light
  {
    sprite = "utility/light_medium",
    target = silo,
    surface = silo.surface,
    scale = 4
  }
  silo.minable = false
  if silo.supports_backer_name() then
    silo.backer_name = ""
  end
  script_data.silo = silo

  local tile_name = "concrete"
  if not game.tile_prototypes[tile_name] then tile_name = get_walkable_tile() end

  local tiles_2 = {}
  local box = silo.bounding_box
  local x1, x2, y1, y2 =
    floor(box.left_top.x) - 1,
    floor(box.right_bottom.x) + 1,
    floor(box.left_top.y) - 1,
    floor(box.right_bottom.y) + 1
  for X = x1, x2 do
    for Y = y1, y2 do
      insert(tiles_2, {name = tile_name, position = {X, Y}})
    end
  end

  for i, entity in pairs(surface.find_entities_filtered({area = {{x1 - 1, y1 - 1},{x2 + 1, y2 + 1}}, force = "neutral"})) do
    entity.destroy()
  end

  set_tiles_safe(surface, tiles_2)
end

local is_in_map = function(width, height, position)
  return position.x >= -width
    and position.x < width
    and position.y >= -height
    and position.y < height
end

function create_wall(starting_point)
  local force = game.forces.player
  local surface = script_data.surface
  local origin = starting_point or force.get_spawn_position(surface)
  local radius =  get_base_radius() + 5
  local height = surface.map_gen_settings.height / 2
  local width = surface.map_gen_settings.width / 2
  local perimeter_top = {}
  local perimeter_bottom = {}
  local perimeter_left = {}
  local perimeter_right = {}
  local tiles = {}
  local insert = insert
  local can_place_entity = surface.can_place_entity
  for X = -radius, radius - 1 do
    insert(perimeter_top, {x = origin.x + X, y = origin.y - radius})
    insert(perimeter_bottom, {x = origin.x + X, y = origin.y + (radius-1)})
  end
  for Y = -radius, radius - 1 do
    insert(perimeter_left, {x = origin.x - radius, y = origin.y + Y})
    insert(perimeter_right, {x = origin.x + (radius-1), y = origin.y + Y})
  end
  local tile_name = "refined-concrete"
  if not game.tile_prototypes[tile_name] then tile_name = get_walkable_tile() end
  local areas =
  {
    {{perimeter_top[1].x, perimeter_top[1].y - 1}, {perimeter_top[#perimeter_top].x, perimeter_top[1].y + 3}},
    {{perimeter_bottom[1].x, perimeter_bottom[1].y - 3}, {perimeter_bottom[#perimeter_bottom].x, perimeter_bottom[1].y + 1}},
    {{perimeter_left[1].x - 1, perimeter_left[1].y}, {perimeter_left[1].x + 3, perimeter_left[#perimeter_left].y}},
    {{perimeter_right[1].x - 3, perimeter_right[1].y}, {perimeter_right[1].x + 1, perimeter_right[#perimeter_right].y}}
  }
  local find_entities_filtered = surface.find_entities_filtered
  local destroy_param = {do_cliff_correction = true}
  for k, area in pairs (areas) do
    for i, entity in pairs(find_entities_filtered({area = area})) do
      entity.destroy(destroy_param)
    end
  end
  local wall_name = "stone-wall"
  local gate_name = "gate"
  if not game.entity_prototypes[wall_name] then
    log("Setting walls cancelled as "..wall_name.." is not a valid entity prototype")
    return
  end
  if not game.entity_prototypes[gate_name] then
    log("Setting walls cancelled as "..gate_name.." is not a valid entity prototype")
    return
  end
  local should_gate =
  {
    [12] = true,
    [13] = true,
    [14] = true,
    [15] = true,
    [16] = true,
    [17] = true,
    [18] = true,
    [19] = true
  }
  local create_entity = surface.create_entity
  for k, position in pairs (perimeter_left) do
    if is_in_map(width, height, position) and can_place_entity{name = wall_name, position = position, force = force, build_check_type = defines.build_check_type.manual_ghost, forced = true} then
      if (k ~= 1) and (k ~= #perimeter_left) then
        insert(tiles, {name = tile_name, position = {position.x + 2, position.y}})
        insert(tiles, {name = tile_name, position = {position.x + 1, position.y}})
      end
      if should_gate[position.y % 32] then
        create_entity{name = gate_name, position = position, direction = 0, force = force, create_build_effect_smoke = false}
      else
        create_entity{name = wall_name, position = position, force = force, create_build_effect_smoke = false}
      end
    end
  end
  for k, position in pairs (perimeter_right) do
    if is_in_map(width, height, position) and can_place_entity{name = wall_name, position = position, force = force, build_check_type = defines.build_check_type.manual_ghost, forced = true} then
      if (k ~= 1) and (k ~= #perimeter_right) then
        insert(tiles, {name = tile_name, position = {position.x - 2, position.y}})
        insert(tiles, {name = tile_name, position = {position.x - 1, position.y}})
      end
      if should_gate[position.y % 32] then
        create_entity{name = gate_name, position = position, direction = 0, force = force, create_build_effect_smoke = false}
      else
        create_entity{name = wall_name, position = position, force = force, create_build_effect_smoke = false}
      end
    end
  end
  for k, position in pairs (perimeter_top) do
    if is_in_map(width, height, position) and can_place_entity{name = wall_name, position = position, force = force, build_check_type = defines.build_check_type.manual_ghost, forced = true} then
      if (k ~= 1) and (k ~= #perimeter_top) then
        insert(tiles, {name = tile_name, position = {position.x, position.y + 2}})
        insert(tiles, {name = tile_name, position = {position.x, position.y + 1}})
      end
      if should_gate[position.x % 32] then
        create_entity{name = gate_name, position = position, direction = 2, force = force, create_build_effect_smoke = false}
      else
        create_entity{name = wall_name, position = position, force = force, create_build_effect_smoke = false}
      end
    end
  end
  for k, position in pairs (perimeter_bottom) do
    if is_in_map(width, height, position) and can_place_entity{name = wall_name, position = position, force = force, build_check_type = defines.build_check_type.manual_ghost, forced = true} then
      if (k ~= 1) and (k ~= #perimeter_bottom) then
        insert(tiles, {name = tile_name, position = {position.x, position.y - 2}})
        insert(tiles, {name = tile_name, position = {position.x, position.y - 1}})
      end
      if should_gate[position.x % 32] then
        create_entity{name = gate_name, position = position, direction = 2, force = force, create_build_effect_smoke = false}
      else
        create_entity{name = wall_name, position = position, force = force, create_build_effect_smoke = false}
      end
    end
  end
  set_tiles_safe(surface, tiles)
end

function create_turrets(starting_point)
  local force = game.forces.player
  local turret_name = "gun-turret"
  if not game.entity_prototypes[turret_name] then return end
  local surface = script_data.surface
  local ammo_name = "firearm-magazine"
  local direction = defines.direction
  local surface = script_data.surface
  local height = surface.map_gen_settings.height / 2
  local width = surface.map_gen_settings.width / 2
  local origin = starting_point
  local radius = get_base_radius() - 5
  local positions = {}
  local Xo = origin.x
  local Yo = origin.y
  for X = -radius, radius do
    local Xt = X + Xo
    if X == -radius then
      for Y = -radius, radius do
        local Yt = Y + Yo
        if (Yt + 16) % 32 ~= 0 and Yt % 8 == 0 then
          insert(positions, {x = Xo - radius, y = Yt, direction = direction.west})
          insert(positions, {x = Xo + radius, y = Yt, direction = direction.east})
        end
      end
    elseif (Xt + 16) % 32 ~= 0 and Xt % 8 == 0 then
      insert(positions, {x = Xt, y = Yo - radius, direction = direction.north})
      insert(positions, {x = Xt, y = Yo + radius, direction = direction.south})
    end
  end
  local tiles = {}
  local tile_name = "hazard-concrete-left"
  if not game.tile_prototypes[tile_name] then tile_name = get_walkable_tile() end
  local stack
  if ammo_name and game.item_prototypes[ammo_name] then
    stack = {name = ammo_name, count = 50}
  end
  local direction_offset =
  {
    [direction.north] = {0, -13},
    [direction.east] = {13, 0},
    [direction.south] = {0, 13},
    [direction.west] = {-13, 0}
  }
  local find_entities_filtered = surface.find_entities_filtered
  local neutral = game.forces.neutral
  local destroy_params = {do_cliff_correction = true}
  local floor = floor
  local create_entity = surface.create_entity
  local can_place_entity = surface.can_place_entity
  for k, position in pairs (positions) do
    if is_in_map(width, height, position) and can_place_entity{name = turret_name, position = position, force = force, build_check_type = defines.build_check_type.manual_ghost, forced = true} then
      local turret = create_entity{name = turret_name, position = position, force = force, direction = position.direction, create_build_effect_smoke = false}
      poop = --rendering.draw_light
      {
        sprite = "utility/light_cone",
        target = turret,
        surface = turret.surface,
        scale = 4,
        orientation = turret.orientation,
        target_offset = direction_offset[position.direction],
        minimum_darkness = 0.3
      }
      local box = turret.bounding_box
      for k, entity in pairs (find_entities_filtered{area = turret.bounding_box, force = neutral}) do
        entity.destroy(destroy_params)
      end
      if stack then
        turret.insert(stack)
      end
      for x = floor(box.left_top.x), floor(box.right_bottom.x) do
        for y = floor(box.left_top.y), floor(box.right_bottom.y) do
          insert(tiles, {name = tile_name, position = {x, y}})
        end
      end
    end
  end
  set_tiles_safe(surface, tiles)
end

local root_2 = 2 ^ 0.5

function get_chest_offset(n)
  local offset_x = 0
  n = n / 2
  if n % 1 == 0.5 then
    offset_x = -1
    n = n + 0.5
  end
  local root = n ^ 0.5
  local nearest_root = math.floor(root + 0.5)
  local upper_root = math.ceil(root)
  local root_difference = math.abs(nearest_root ^ 2 - n)
  if nearest_root == upper_root then
    x = upper_root - root_difference
    y = nearest_root
  else
    x = upper_root
    y = root_difference
  end
  local orientation = 2 * math.pi * (45/360)
  x = x * root_2
  y = y * root_2
  local rotated_x = math.floor(0.5 + x * math.cos(orientation) - y * math.sin(orientation))
  local rotated_y = math.floor(0.5 + x * math.sin(orientation) + y * math.cos(orientation))
  return {x = rotated_x + offset_x, y = rotated_y}
end

function create_starting_chest(starting_point)
  local force = game.forces.player
  local inventory = script_data.difficulty.starting_chest_items
  if not (table_size(inventory) > 0) then return end
  local surface = script_data.surface
  local chest_name = "iron-chest"
  local prototype = game.entity_prototypes[chest_name]
  if not prototype then
    log("Starting chest "..chest_name.." is not a valid entity prototype, picking a new container from prototype list")
    for name, chest in pairs (game.entity_prototypes) do
      if chest.type == "container" then
        chest_name = name
        prototype = chest
        break
      end
    end
  end
  local size = math.ceil(prototype.radius * 2)
  local origin = {x = starting_point.x, y = starting_point.y}
  local index = 1
  local position = {x = origin.x + get_chest_offset(index).x * size, y = origin.y + get_chest_offset(index).y * size}
  local chest = surface.create_entity{name = chest_name, position = position, force = force, create_build_effect_smoke = false}
  for k, v in pairs (surface.find_entities_filtered{force = "neutral", area = chest.bounding_box}) do
    v.destroy()
  end
  local tiles = {}
  local grass = {}
  local tile_name = "refined-concrete"
  if not game.tile_prototypes[tile_name] then tile_name = get_walkable_tile() end
  insert(tiles, {name = tile_name, position = {x = position.x, y = position.y}})
  chest.destructible = false
  local items = game.item_prototypes
  for name, count in pairs (inventory) do
    if items[name] then
      local count_to_insert = math.ceil(count)
      local difference = count_to_insert - chest.insert{name = name, count = count_to_insert}
      while difference > 0 do
        index = index + 1
        position = {x = origin.x + get_chest_offset(index).x * size, y = origin.y + get_chest_offset(index).y * size}
        chest = surface.create_entity{name = chest_name, position = position, force = force, create_build_effect_smoke = false}
        for k, v in pairs (surface.find_entities_filtered{force = "neutral", area = chest.bounding_box}) do
          v.destroy()
        end
        insert(tiles, {name = tile_name, position = {x = position.x, y = position.y}})
        chest.destructible = false
        difference = difference - chest.insert{name = name, count = difference}
      end
    end
  end
  set_tiles_safe(surface, tiles)
end

local get_ticks_till_dawn = function()
  local surface = script_data.surface
  local current_daytime = surface.daytime
  local dawn = surface.dawn
  local diff = dawn - current_daytime
  if diff < 0 then diff = diff + 1 end
  local ticks = math.ceil(diff * surface.ticks_per_day)
  return ticks
end

local make_next_dawn_tick = function()
  script_data.dawn_tick = game.tick + get_ticks_till_dawn()
end

local check_dawn = function(tick)
  if not script_data.dawn_tick or tick < script_data.dawn_tick then return end
  increment(script_data, "day_number")
  game.print({"dawn-of-new-day", script_data.day_number})
  update_label_list(script_data.gui_labels.day_label, {"current-day", script_data.day_number})
  script_data.dawn_tick = nil
end

function check_next_wave(tick)
  if not script_data.wave_tick then return end
  if script_data.wave_tick ~= tick then return end
  next_wave()
end

function next_wave()
  make_next_wave_tick()
  make_next_spawn_tick()
  spawn_units()
end

function wave_end()
  make_next_dawn_tick()
  script_data.spawn_tick = nil
  script_data.end_spawn_tick = nil
end

local victory_sound = {path = "utility/game_won"}

local round_won = function()
  if script_data.state ~= game_state.in_round then return end
  game.play_sound(victory_sound)
  game.print({"you-win", script_data.day_number})
  script_data.state = game_state.victory
  set_up_players()
  --TODO, maybe popup some ugly GUI with stats etc.
end

function make_next_spawn_tick()
  local addition = 8 * 60
  script_data.spawn_tick = game.tick + addition
end

function check_spawn_units(tick)
  if not script_data.spawn_tick then return end

  if script_data.end_spawn_tick <= tick then
    wave_end()
    return
  end

  if script_data.spawn_tick == tick then
    spawn_units()
    make_next_spawn_tick()
  end
end

function get_wave_spawners()
  local spawners = script_data.spawner_distances
  local wave_spawners = {}
  local count = math.min(#spawners, math.ceil(script_data.random(5, 15) * math.log(1 + script_data.day_number)))
  for k = count, 1, -1 do
    local spawn = spawners[k]
    if (spawn and spawn.entity.valid) then
      insert(wave_spawners, spawn.entity)
    else
      table.remove(spawners, k)
    end
  end
  return wave_spawners
end

local get_wave_power = function()
  return power_functions[script_data.difficulty.wave_power_function or "default"](script_data.day_number)
end

function get_wave_units()
  local wave = script_data.day_number
  local prices = script_data.difficulty.unit_prices
  local units = {}
  for name, unit_wave in pairs (script_data.difficulty.unit_waves) do
    if wave >= unit_wave[1] then
      if not unit_wave[2] or wave <= unit_wave[2] then
        insert(units, {name = name, amount = floor(((wave - unit_wave[1]) + 1) ^ 1.25), price = prices[name]})
      end
    end
  end
  return units
end

local get_speed_multiplier = function()
  local level = script_data.day_number
  if level == 0 then return 0.8 end
  return speed_multiplier_functions[script_data.difficulty.speed_multiplier_function or "default"](level)
end

function select_unit(units, power)

  local roll_max = 1
  local available = {}
  for k, unit in pairs (units) do
    if unit.price <= power then
      insert(available, unit)
      roll_max = roll_max + unit.amount
    end
  end

  local roll_value = script_data.random(roll_max)
  for k, unit in pairs (available) do
    roll_value = roll_value - unit.amount
    if (roll_value < 0) then
      return unit
    end
  end

end

local random_base_position = function()
  local random = script_data.random
  local position = get_starting_point()
  local radius = get_base_radius()
  position.x = position.x + random(-radius, radius)
  position.y = position.y + random(-radius, radius)
  return position
end


local group_path_flags =
{
  cache = false,
  low_priority = false,
  no_break = true
}

function spawn_units()
  local random = script_data.random
  local surface = script_data.surface
  local silo = script_data.silo
  if not (silo and silo.valid) then return end
  local command =
  {
    type = defines.command.compound,
    structure_type = defines.compound_command.return_last,
    commands =
    {
      {
        type = defines.command.go_to_location,
        destination = random_base_position(),
        distraction = defines.distraction.by_anything,
        radius = 16,
        pathfind_flags = group_path_flags
      },
      {
        type = defines.command.go_to_location,
        destination_entity = silo,
        distraction = defines.distraction.by_enemy,
        radius = get_base_radius() / 2,
        pathfind_flags = group_path_flags
      },
      {
        type = defines.command.attack,
        target = silo,
        distraction = defines.distraction.by_damage
      }
    }
  }
  local power = get_wave_power()
  local some_spawns = get_wave_spawners()
  local spawns_count = #some_spawns

  if spawns_count == 0 then
    return
  end

  local units = get_wave_units()
  local units_length = #units
  local find_non_colliding_position = surface.find_non_colliding_position
  local create_entity = surface.create_entity
  local entities = game.entity_prototypes
  local speed_multiplier = get_speed_multiplier()

  local get_spawn_position = function(spawn_position, unit)
    local origin = {spawn_position[1] + random(-8, 8), spawn_position[2] + random(-8, 8)}
    local position = find_non_colliding_position(unit.name, origin, 0, 1)
    return position
  end

  local power_per_spawner = power / spawns_count
  for k, spawner in pairs (some_spawns) do

    local spawner_power = power_per_spawner

    local spawn_position = {spawner.position.x + random(-16, 16), spawner.position.y + random(-16, 16)}

    local group = surface.create_unit_group{position = spawn_position, force = spawner.force}

    for k, unit in pairs (spawner.units) do
      unit.release_from_spawner()
      unit.speed = unit.prototype.speed * speed_multiplier
      group.add_member(unit)
    end

    while true do
      local unit = select_unit(units, spawner_power)
      if not unit then break end
      spawner_power = spawner_power - unit.price
      local entity = create_entity{name = unit.name, position = get_spawn_position(spawn_position, unit)}
      entity.speed = entity.prototype.speed * speed_multiplier
      group.add_member(entity)
      if spawner_power <= 0 then break end
    end

    group.set_command(command)

  end

end

function make_next_wave_tick()
  script_data.end_spawn_tick = game.tick + script_data.spawn_time
  script_data.wave_tick  = game.tick + script_data.wave_time
end

function time_to_next_wave()
  if not script_data.wave_tick then return end
  return format_time(script_data.wave_tick - game.tick)
end

function time_to_wave_end()
  if not script_data.end_spawn_tick then return end
  return format_time(script_data.end_spawn_tick - game.tick)
end

local lose_sound = {path = "utility/game_lost"}
function rocket_died(event)
  if not (script_data.silo and script_data.silo.valid) then return end
  local silo = event.entity
  if silo ~= script_data.silo then
    return
  end
  script_data.state = game_state.defeat
  script_data.silo = nil
  set_up_players()
  game.play_sound(lose_sound)
  game.print({"you-lose", script_data.day_number})
end

local insert_items = util.insert_safe

give_respawn_equipment = function(player)
  if not is_player_force(player.force) then return end
  local equipment = script_data.difficulty.respawn_items
  local items = game.item_prototypes
  local list = {items = {}, armor = false, equipment = {}}
  for name, count in pairs (equipment) do
    local item = items[name]
    if item then
      if item.type == "armor" then
        local count = count
        if not list.armor then
          list.armor = item
        end
        count = count - 1
        if count > 0 then
          list.items[item] = (list.items[item] or 0) + count
        end
      elseif item.place_as_equipment_result then
        list.equipment[item] = (list.equipment[item] or 0) + count
      else
        list.items[item] = (list.items[item] or 0) + count
      end
    else
      equipment[name] = nil
    end
  end
  local put_equipment = false
  if list.armor then
    local stack = player.get_inventory(defines.inventory.character_armor)[1]
    stack.set_stack{name = list.armor.name}
    local grid = stack.grid
    if grid then
      put_equipment = true
      for prototype, count in pairs (list.equipment) do
        local equipment = prototype.place_as_equipment_result
        for k = 1, count do
          local equipment = grid.put{name = equipment.name}
          if equipment then
            equipment.energy = equipment.max_energy
          else
            player.insert{name = prototype.name}
          end
        end
      end
    end
  end

  if not put_equipment then
    for prototype, count in pairs (list.equipment) do
      player.insert{name = prototype.name, count = count}
    end
  end

  for prototype, count in pairs (list.items) do
    player.insert{name = prototype.name, count = count}
  end
end

function refresh_preview_gui(player)
  local frame = script_data.gui_elements.preview_frame[player.index]
  if not (frame and frame.valid) then return end
  deregister_gui(frame)
  frame.clear()

  local admin = player.admin
  local inner = frame.add{type = "frame", style = "inside_deep_frame", direction = "vertical"}.add{type = "flow", direction = "vertical"}
  inner.style.vertical_spacing = 0
  local subheader = inner.add{type = "frame", style = "subheader_frame"}
  local surface = script_data.surface
  if not (surface and surface.valid) then return end
  subheader.style.horizontally_stretchable = true
  local label = subheader.add{type = "label", caption = {"gui-map-generator.difficulty"}, style = "subheader_caption_label"}
  --label.style.vertically_stretchable = true
  label.style.vertical_align = "center"
  label.style.right_padding = 4
  if admin then
    local config = subheader.add{type = "drop-down"}
    local count = 1
    local index
    for name, difficulty in pairs (script_data.config.difficulties) do
      config.add_item{name}
      if difficulty == script_data.difficulty then
        index = count
      end
      count = count + 1
    end
    config.selected_index = index
    register_gui_action(config, {type = "difficulty_changed"})
  else
    local key
    for k, value in pairs (script_data.config.difficulties) do
      if value == script_data.difficulty then key = k break end
    end
    subheader.add{type = "label", caption = {key}, style = "caption_label"}
  end

  local line = subheader.add{type = "line", direction = "vertical"}

  local infinite_checkbox = subheader.add{type = "checkbox", state = script_data.config.infinite, caption = {"infinite-map"}, enabled = admin}
  register_gui_action(infinite_checkbox, {type = "infinite_checkbox_input"})

  local pusher = subheader.add{type = "flow"}
  pusher.style.horizontally_stretchable = true
  local seed_flow = subheader.add{type = "flow", direction = "horizontal", style = "player_input_horizontal_flow"}
  seed_flow.add{type = "label", style = "caption_label", caption = {"gui-map-generator.map-seed"}}
  if admin then
    local seed_input = seed_flow.add
    {
      type = "textfield", text = surface.map_gen_settings.seed, style = "long_number_textfield",
      numeric = true, allow_decimal = false, allow_negative = false
    }
    register_gui_action(seed_input, {type = "check_seed_input"})
    local shuffle_button = seed_flow.add{type = "sprite-button", sprite = "utility/shuffle", style = "tool_button"}
    register_gui_action(shuffle_button, {type = "shuffle_button"})
  else
    seed_flow.add{type = "label", style = "caption_label", caption = surface.map_gen_settings.seed}
  end
  local size = get_preview_size()
  local max = math.min(size * 2, player.display_resolution.width * 0.8 / player.display_scale, player.display_resolution.height * 0.8 / player.display_scale)
  local zoom = max / (size * 2)
  local position = player.force.get_spawn_position(surface)
  local minimap = inner.add
  {
    type = "minimap",
    surface_index = surface.index,
    zoom = zoom,
    force = player.force.name,
    position = position
  }
  minimap.style.natural_width = max
  minimap.style.natural_height = max

  local button_flow = frame.add{type = "flow"}
  button_flow.style.horizontally_stretchable = true
  button_flow.style.vertical_align = "center"
  button_flow.style.top_padding = 4
  local pusher = button_flow.add{type = "empty-widget", style = "draggable_space_header"}
  pusher.style.vertically_stretchable = true
  pusher.style.horizontally_stretchable = true
  pusher.drag_target = frame
  local start_round = button_flow.add{type = "button", caption = {"start-round"}, style = "confirm_button", enabled = admin}
  start_round.style.natural_width = max / 3
  register_gui_action(start_round, {type = "start_round"})
end

local setup_frame = {type = "frame", caption = {"setup-frame"}, direction = "vertical"}

function make_preview_gui(player)
  local gui = player.gui.screen
  local frame = script_data.gui_elements.preview_frame[player.index]
  if not (frame and frame.valid) then
    frame = gui.add(setup_frame)
    frame.auto_center = true
    frame.style.horizontal_align = "right"
    frame.style.maximal_height = player.display_resolution.height / player.display_scale
    frame.style.vertically_stretchable = true
    script_data.gui_elements.preview_frame[player.index] = frame
  end
  refresh_preview_gui(player)
end

local day_button_param =
{
  type = "button",
  ignored_by_interaction = true,
  style = mod_gui.button_style
}

local upgrade_button_param =
{
  type = "button",
  caption = {"upgrade-button"},
  tooltip = {"upgrade-button-tooltip"},
  style = mod_gui.button_style
}

local admin_button_param =
{
  type = "button",
  caption = {"admin"},
  style = mod_gui.button_style
}

local add_admin_buttons = function(player)

  if not player.admin then return end

  local button_flow = mod_gui.get_button_flow(player)
  local admin_button = button_flow.add(admin_button_param)
  script_data.gui_elements.admin_frame_button[player.index] = admin_button
  register_gui_action(admin_button, {type = "admin_button"})
end

local add_gui_buttons= function(player)

  if not is_player_force(player.force) then return end

  local button_flow = mod_gui.get_button_flow(player)

  local day_button = script_data.gui_elements.day_button[player.index]
  if not day_button then
    day_button = button_flow.add(day_button_param)
    script_data.gui_elements.day_button[player.index] = day_button
  end
  day_button.caption = {"current-day", script_data.day_number}
  insert(script_data.gui_labels.day_label, day_button)

  local upgrade_button = script_data.gui_elements.upgrade_frame_button[player.index]
  if not upgrade_button then
    upgrade_button = button_flow.add(upgrade_button_param)
    script_data.gui_elements.upgrade_frame_button[player.index] = upgrade_button
    register_gui_action(upgrade_button, {type = "upgrade_button"})
  end
end

local delete_game_gui = function(player)
  local index = player.index
  for k, gui_list in pairs(script_data.gui_elements) do
    local element = gui_list[index]
    if (element and element.valid) then
      deregister_gui(element)
      element.destroy()
    end
    gui_list[index] = nil
  end
end

function gui_init(player)

  delete_game_gui(player)

  if script_data.state == game_state.in_preview then
    make_preview_gui(player)
    return
  end

  if script_data.state == game_state.in_round then
    add_gui_buttons(player)
    add_admin_buttons(player)
    return
  end

  if script_data.state == game_state.defeat or script_data.state == game_state.victory then
    add_admin_buttons(player)
    return
  end

end

local cash_font_color = {r = 0.8, b = 0.5, g = 0.8}

local upgrade_frame = {type = "frame", style = mod_gui.frame_style, caption = {"buy-upgrades"}, direction = "vertical"}
function toggle_upgrade_frame(player)

  local frame = script_data.gui_elements.upgrade_frame[player.index]
  if frame and frame.valid then
    deregister_gui(frame)
    frame.destroy()
    script_data.gui_elements.upgrade_frame[player.index] = nil
    return
  end

  frame = mod_gui.get_frame_flow(player).add(upgrade_frame)
  script_data.gui_elements.upgrade_frame[player.index] = frame
  frame.visible = true

  inner = frame.add{type = "frame", style = "inside_deep_frame", direction = "vertical"}
  local subheader = inner.add{type = "frame", style = "subheader_frame"}
  subheader.style.horizontally_stretchable = "true"
  local label = subheader.add{type = "label", caption = {"force-money"}, style = "subheader_label"}
  label.style.font = "default-semibold"
  local cash = subheader.add{type = "label", caption = get_money()}
  insert(script_data.gui_labels.money_label, cash)
  cash.style.font_color = {r = 0.8, b = 0.5, g = 0.8}
  local scroll = inner.add{type = "scroll-pane", style = "scroll_pane_with_dark_background_under_subheader"}
  scroll.style.padding = 0
  scroll.style.maximal_height = (player.display_resolution.height * 0.5) / player.display_scale
  local upgrade_table = scroll.add{type = "table", column_count = 2}
  upgrade_table.style.horizontal_spacing = 0
  upgrade_table.style.vertical_spacing = 0
  script_data.gui_elements.upgrade_table[player.index] = upgrade_table
  update_upgrade_listing(player)
end

function update_upgrade_listing(player)
  local gui = script_data.gui_elements.upgrade_table[player.index]
  if not (gui and gui.valid) then return end
  local upgrades = script_data.team_upgrades
  deregister_gui(gui)
  gui.clear()
  for name, upgrade in pairs (get_upgrades()) do
    local level = upgrades[name] or 0
    local sprite = gui.add{type = "sprite-button", name = name, sprite = upgrade.sprite, tooltip = {"purchase"}, style = "slot_sized_button"}
    sprite.style.minimal_height = 64 + 8
    sprite.style.minimal_width = 64 + 8
    sprite.style.margin = -1
    sprite.number = upgrade.price(level)
    register_gui_action(sprite, {type = "purchase_button", name = name})
    local flow = gui.add{type = "frame", name = name.."_flow", direction = "vertical", style = "subpanel_frame"}
    flow.style.horizontally_stretchable = true
    flow.style.vertically_stretchable = true
    local label = flow.add{type = "label", name = name.."_name", caption = {"", upgrade.caption, " "..upgrade.modifier}}
    label.style.font = "default-bold"
    local level = flow.add{type = "label", name = name.."_level", caption = {"upgrade-level", level}}
  end
end

function get_upgrades()
  return upgrades
end

function get_money()
  return format_number(script_data.money)
end

function update_label_list(list, caption)
  for k, label in pairs (list) do
    if label.valid then
      label.caption = caption
    else
      list[k] = nil
    end
  end
end

local admin_frame_param =
{
  type = "frame",
  style = mod_gui.frame_style,
  caption = {"admin"},
  direction = "vertical"
}

local admin_buttons =
{
  {
    param = {type = "button", caption = {"end-round"}},
    action = {type = "end_round"}
  },
  {
    param = {type = "button", caption = {"restart-round"}},
    action = {type = "restart_round"}
  },
  --[[{
    param = {type = "button", caption = "Dev only: Send wave"},
    action = {type = "send_wave"}
  },]]

}

local toggle_admin_frame = function(player)
  if not (player and player.valid) then return end
  local frame = script_data.gui_elements.admin_frame[player.index]
  if (frame and frame.valid) then
    deregister_gui(frame)
    frame.destroy()
    script_data.gui_elements.admin_frame[player.index] = nil
    return
  end
  local gui = mod_gui.get_frame_flow(player)
  frame = gui.add(admin_frame_param)
  frame.style.vertically_stretchable = false
  frame.style.horizontally_stretchable = false
  script_data.gui_elements.admin_frame[player.index] = frame
  local inner = frame.add{type = "frame", direction = "vertical", style = "window_content_frame_deep"}
  for k, button in pairs (admin_buttons) do
    local butt = inner.add(button.param)
    butt.style.horizontally_stretchable = true
    register_gui_action(butt, button.action)
  end

end

local techs_to_disable =
{
  "physical-projectile-damage",
  "stronger-explosives",
  "refined-flammables",
  "energy-weapons-damage",
  "weapon-shooting-speed",
  "laser-shooting-speed",
  "follower-robot-count",
  "mining-productivity"
}

function set_research(force)
  force.research_all_technologies()
  local tech = force.technologies
  for k, name in pairs (techs_to_disable) do
    for i = 1, 20 do
      local full_name = name.."-"..i
      if tech[full_name] then
        tech[full_name].researched = false
      end
    end
  end
  force.reset_technology_effects()
end

function set_recipes(force)
  local recipes = force.recipes
  local disable =
  {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "military-science-pack",
    "production-science-pack",
    "utility-science-pack",
    "lab"
  }

  for k, name in pairs (disable) do
    if recipes[name] then
      recipes[name].enabled = false
    else
      error(name.." is not a valid recipe")
    end
  end
end

local init_map_settings = function()
  local settings = game.map_settings

  settings.pollution.enabled = false
  settings.enemy_expansion.enabled = false

  --So, when path cache is enabled, negative path cache is also enabled.
  --The problem is, when a single unit inside a nest can't get to the silo,
  --He tells all other biters nearby that they also can't get to the silo.
  --Which causes whole groups of them just to chillout and idle...
  settings.path_finder.use_path_cache = false

  --The bases are surrounded by walls
  --This stops the pathfinder wasting a ton of time trying to go around the walls
  settings.path_finder.general_entity_collision_penalty = 1
  settings.path_finder.general_entity_subsequent_collision_penalty = 1

  settings.path_finder.max_steps_worked_per_tick = 1000
  settings.path_finder.max_clients_to_accept_any_new_request = 5000
  settings.path_finder.ignore_moving_enemy_collision_distance = 0
  settings.short_request_max_steps = 1000000
  settings.short_request_ratio = 1
  settings.max_failed_behavior_count = 2

  --settings.steering.moving.force_unit_fuzzy_goto_behavior = true
  --settings.steering.moving.radius = 6
  --settings.steering.moving.separation_force = 0.02
  --settings.steering.moving.separation_factor = 8
  --settings.steering.default.force_unit_fuzzy_goto_behavior = true
  --settings.steering.default.radius = 1
  --settings.steering.default.separation_force = 0.01
  --settings.steering.default.separation_factor  = 1

  settings.unit_group=
  {
    -- pollution triggered group waiting time is a random time between min and max gathering time
    min_group_gathering_time = 3600,
    max_group_gathering_time = 10 * 3600,
    -- after the gathering is finished the group can still wait for late members,
    -- but it doesn't accept new ones anymore
    max_wait_time_for_late_members = 2 * 3600,
    -- limits for group radius (calculated by number of numbers)
    max_group_radius = 50.0,
    min_group_radius = 5.0,
    -- when a member falls behind the group he can speedup up till this much of his regular speed
    max_member_speedup_when_behind = 2,
    -- When a member gets ahead of its group, it will slow down to at most this factor of its speed
    max_member_slowdown_when_ahead = 0.9,
    -- When members of a group are behind, the entire group will slow down to at most this factor of its max speed
    max_group_slowdown_factor = 0.9,
    -- If a member falls behind more than this times the group radius, the group will slow down to max_group_slowdown_factor
    max_group_member_fallback_factor = 2,
    -- If a member falls behind more than this time the group radius, it will be removed from the group.
    member_disown_distance = 50,
    tick_tolerance_when_member_arrives = 60,

    -- Maximum number of automatically created unit groups gathering for attack at any time.
    max_gathering_unit_groups = 30,

    -- Maximum size of an attack unit group. This only affects automatically-created unit groups; manual groups
    -- created through the API are unaffected.
    max_unit_group_size = 200
  }
end

local on_init = function()
  init_map_settings()
  game.forces.player.disable_research()
  game.surfaces.nauvis.always_day = true
end

local spawner_died = function(event)
  local spawner = event.entity
  if not (spawner and spawner.valid) then return end
  script_data.spawners[spawner.unit_number] = nil
end

local bounty_color = {r = 0.2, g = 0.8, b = 0.2, a = 0.2}
local on_entity_died = function(event)
  if script_data.state ~= game_state.in_round then return end

  local died = event.entity
  if not (died and died.valid) then return end

  local bounty = script_data.difficulty.bounties[died.name]
  if bounty and is_player_force(event.force) then
    local cash = floor(bounty * (script_data.difficulty.bounty_modifier or 1))
    increment(script_data, "money", cash)
    died.surface.create_entity{name = "flying-text", position = died.position, text = "+"..cash, color = bounty_color}
    update_label_list(script_data.gui_labels.money_label, get_money())
  end

  if died.type == "rocket-silo" then
    return rocket_died(event)
  end

  if died.type == "unit-spawner" then
    return spawner_died(event)
  end
end

local on_rocket_launched = function(event)
  round_won()
end

local on_player_joined_game = function(event)
  local player = players(event.player_index)
  if not (script_data.surface and script_data.surface.valid) then
    create_battle_surface(initial_seed)
  end
  set_up_player(player)
end

local on_player_respawned = function(event)
  give_respawn_equipment(players(event.player_index))
end

local is_reasonable_seed = function(string)
  local number = tonumber(string)
  if not number then return end
  if number < 0 or number > max_seed then
    return
  end
  return true
end

local end_round = function(player)
  script_data.state = game_state.in_preview
  script_data.wave_tick = nil
  script_data.spawn_tick = nil
  local seed = script_data.surface.map_gen_settings.seed
  game.delete_surface(script_data.surface)
  create_battle_surface(script_data.surface.map_gen_settings.seed)
  set_up_players()
end

local gui_functions =
{
  upgrade_button = function(event)
    toggle_upgrade_frame(players(event.player_index))
  end,
  admin_button = function(event)
    toggle_admin_frame(players(event.player_index))
  end,
  purchase_button = function(event, param)
    local name = param.name
    local list = get_upgrades()
    local upgrades = script_data.team_upgrades
    local player = players(event.player_index)
    local upgrade = list[name]
    if not upgrade then
      --Maybe some migration, we don't have an upgrade by this name anymore, so, get lost...
      toggle_upgrade_frame(player)
      return
    end
    local price = upgrade.price(upgrades[name])

    if script_data.money < price then
      player.print({"not-enough-money"})
      return
    end

    increment(script_data, "money", -price)
    for k, effect in pairs (upgrade.effect) do
      effect(player.force)
    end

    increment(script_data.team_upgrades, name)
    player.force.print({"purchased-team-upgrade", player.name, upgrade.caption, upgrades[name]})
    for k, player in pairs (game.connected_players) do
      update_upgrade_listing(player)
    end
    update_label_list(script_data.gui_labels.money_label, get_money())

  end,
  shuffle_button = function(event, param)
    create_battle_surface()
  end,
  check_seed_input = function(event, param)
    local gui = event.element
    if not (gui and gui.valid) then return end
    if not is_reasonable_seed(gui.text) then
      return
    end
    gui.style = "long_number_textfield"
    if event.name == defines.events.on_gui_confirmed then
      create_battle_surface(tonumber(gui.text))
    end
  end,
  infinite_checkbox_input = function(event, param)
    local gui = event.element
    if not (gui and gui.valid) then return end
    script_data.config.infinite = gui.state
    create_battle_surface(script_data.surface.map_gen_settings.seed)
  end,
  start_round = function(event, param)
    start_round()
  end,
  send_wave = function(event, param)
    spawn_units()
  end,
  end_round = function(event, param)
    end_round()
  end,
  restart_round = function(event, param)
    restart_round()
  end,
  difficulty_changed = function(event, param)
    local gui = event.element
    if not (gui and gui.valid) then return end
    if not (event.name == defines.events.on_gui_selection_state_changed) then return end
    local selected = gui.selected_index
    local index = 1
    for name, difficulty in pairs (script_data.config.difficulties) do
      if index == selected then
        script_data.difficulty = difficulty
        break
      end
      index = index + 1
    end
    create_battle_surface(script_data.surface.map_gen_settings.seed)
  end
}

function generic_gui_event(event)
  local gui = event.element
  if not (gui and gui.valid) then return end

  local player_gui_actions = script_data.gui_actions[gui.player_index]
  if not player_gui_actions then return end

  local action = player_gui_actions[gui.index]
  if not action then return end

  gui_functions[action.type](event, action)
end

local chart_base_area = function()
  if script_data.state ~= game_state.in_round then return end
  local surface = script_data.surface
  if not (surface and surface.valid) then return end
  local force = game.forces.player
  local origin = force.get_spawn_position(surface)
  local size = get_base_radius()
  force.chart(surface,
  {
    {
      origin.x - (size + 32),
      origin.y - (size + 32)
    },
    {
      origin.x + size,
      origin.y + size
    }
  })
end

local collision_mask = {"colliding-with-tiles-only", "water-tile"}
local bounding_box = {{0,0},{0,0}}
local flags =
{
  cache = false,
  low_priority = false,
  no_break = true
}

local max_pending_paths = 15
local process_path_queue = function()

  local queue = script_data.path_request_queue
  if not queue then return end

  local requests = script_data.spawner_path_requests
  local current_count = table_size(requests)

  for k = 1, (max_pending_paths - current_count) do

    local unit_number, spawner = next(queue)

    if not unit_number then
      return
    end

    queue[unit_number] = nil

    if not (spawner and spawner.valid) then
      return
    end

    local key = spawner.surface.request_path
    {
      bounding_box = bounding_box,
      collision_mask = collision_mask,
      start = spawner.position,
      goal = get_starting_point(),
      radius = get_base_radius(),
      force = spawner.force,
      path_resolution_modifier = -1,
      pathfind_flags = flags
    }

    requests[key] = spawner

  end

end

local on_tick = function(event)
  local tick = event.tick

  if script_data.state == game_state.in_round then
    check_next_wave(tick)
    check_spawn_units(tick)
    check_dawn(tick)
    process_path_queue()
    return
  end

  if script_data.state == game_state.in_preview then
    if script_data.surface and script_data.surface.valid then
      script_data.surface.force_generate_chunk_requests()
    end
  end

end

local oh_no_you_dont = {game_finished = false}

local on_player_died = function(event)
  if not game.is_multiplayer() then
    game.set_game_state(oh_no_you_dont)
  end
end

local request_path_for_spawner = function(spawner)

  if not (spawner and spawner.valid) then return end

  local unit_number = spawner.unit_number

  if script_data.spawners[unit_number] then
    --Already know a path exists.
    return
  end

  script_data.path_request_queue[unit_number] = spawner

end

local on_chunk_generated = function(event)
  local surface = event.surface
  if not (surface and surface.valid and surface == script_data.surface) then return end

  for k, spawner in pairs (surface.find_entities_filtered{area = event.area, type = "unit-spawner"}) do
    request_path_for_spawner(spawner)
  end

end

local refresh_player_gui_event = function(event)
  return gui_init(players(event.player_index))
end

local add_remote_interface = function()
  remote.add_interface("wave_defense",
  {
    set_config = function(data)
      if type(data) ~= "table" then
        error("Data type for 'set_config' must be a table")
      end
      log("Wave defense config set by remote call, can expect script errors after this point.")
      script_data.config = data
    end,
    get_config = function()
      return script_data.config
    end,
    get_events = function()
      return script_events
    end
  })
end

local on_script_path_request_finished = function(event)
  local id = event.id
  local spawner = script_data.spawner_path_requests[id]
  if not (spawner and spawner.valid) then return end

  script_data.spawner_path_requests[id] = nil

  if event.try_again_later then
    request_path_for_spawner(spawner)
    return
  end

  if not event.path then
    --pathing from the spawner to the silo failed, so we don't add it to our list of spawn/kill candidates.
    return
  end

  script_data.spawners[spawner.unit_number] = spawner

  local path = event.path
  local distance = #path
  local spawners = script_data.spawner_distances
  local inserted = false

  for k, other_spawner in pairs (spawners) do
    if distance < other_spawner.distance then
      insert(spawners, k, {entity = spawner, distance = distance})
      inserted = true
      break
    end
  end

  if not inserted then
    insert(spawners, {entity = spawner, distance = distance})
  end

end

local on_ai_command_completed = function(event)
  --Used only for debugging.
  local unit = script_data.units[event.unit_number]
  local silo = script_data.silo
  if not (silo and silo.valid) then return end
  if unit and unit.valid then
    unit.ai_settings.path_resolution_modifier = math.min(0, unit.ai_settings.path_resolution_modifier + 1)
    unit.set_command
    {
      type = defines.command.attack,
      target = silo,
      distraction = defines.distraction.by_damage
    }
  end
end

local on_pre_player_died = function(event)
  -- People were complaining about cheesing the death and respawn items.
  -- So we just remove all the respawn items from them when they die.
  -- Theoretically, they can put the items in a chest and then die, but this covers the typical case.
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  if not is_player_force(player.force) then return end
  local remove_item = player.remove_item
  for name, count in pairs (script_data.difficulty.respawn_items) do
    remove_item{name = name, count = count}
  end
end

local on_player_changed_force = function(event)
  local player = players(event.player_index)
  set_up_player(player)
end

local on_technology_effects_reset = function(event)
  local force = event.force
  if force.name ~= "player" then return end

  local upgrades = script_data.team_upgrades

  for name, upgrade in pairs (get_upgrades()) do
    local count = upgrades[name] or 0
    if count > 1 then
      for k, effect in pairs (upgrade.effect) do
        for j = 1, count do
          effect(force)
        end
      end
    end
  end

end

local lib = {}

lib.events =
{
  [defines.events.on_chunk_generated] = on_chunk_generated,
  [defines.events.on_entity_died] = on_entity_died,

  [defines.events.on_gui_click] = generic_gui_event,
  [defines.events.on_gui_selection_state_changed] = generic_gui_event,
  [defines.events.on_gui_text_changed] = generic_gui_event,
  [defines.events.on_gui_confirmed] = generic_gui_event,
  [defines.events.on_gui_checked_state_changed] = generic_gui_event,

  [defines.events.on_player_died] = on_player_died,
  [defines.events.on_pre_player_died] = on_pre_player_died,

  [defines.events.on_player_demoted] = refresh_player_gui_event,
  [defines.events.on_player_display_resolution_changed] = refresh_player_gui_event,
  [defines.events.on_player_display_scale_changed] = refresh_player_gui_event,
  [defines.events.on_player_promoted] = refresh_player_gui_event,

  [defines.events.on_player_joined_game] = on_player_joined_game,
  [defines.events.on_player_changed_force] = on_player_changed_force,
  [defines.events.on_player_respawned] = on_player_respawned,
  [defines.events.on_rocket_launched] = on_rocket_launched,
  [defines.events.on_script_path_request_finished] = on_script_path_request_finished,
  --[defines.events.on_ai_command_completed] = on_ai_command_completed,
  [defines.events.on_tick] = on_tick,

  [defines.events.on_technology_effects_reset] = on_technology_effects_reset

}

lib.on_nth_tick =
{
  [13] = chart_base_area
}

lib.on_event = function(event)
  local action = events[event.name]
  if not action then return end
  return action(event)
end

lib.on_load = function()
  script_data = global.wave_defense or script_data
  add_remote_interface()
end

lib.on_init = function()
  global.wave_defense = global.wave_defense or script_data
  on_init()
  add_remote_interface()
end

lib.on_configuration_changed = function(data)
  for name, upgrade in pairs (get_upgrades()) do
    script_data.team_upgrades[name] = script_data.team_upgrades[name] or 0
  end

  for k, player in pairs (game.players) do
    update_upgrade_listing(player)
  end

  init_map_settings()
  set_recipes(game.forces.player)
  game.forces.player.disable_research()

  if script_data.surface and script_data.surface.valid then
    script_data.path_request_queue = {}
    script_data.spawner_path_requests = {}
    for k, spawner in pairs (script_data.surface.find_entities_filtered{type = "unit-spawner"}) do
      request_path_for_spawner(spawner)
    end
  end

  if type(script_data.difficulty.wave_power_function) ~= "string" then
    script_data.difficulty.wave_power_function = "default"
  end

  if type(script_data.difficulty.speed_multiplier_function) ~= "string" then
    script_data.difficulty.speed_multiplier_function  = "default"
  end

end

return lib
