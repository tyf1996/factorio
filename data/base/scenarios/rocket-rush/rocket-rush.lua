local production_score = require("production-score")
local config = require("rocket-rush-config")

local script_data =
{
  game_state = nil,
  prices = nil
}

local game_state =
{
  preparing = 0,
  in_progress = 1
}

local sort_groups = function(groups)
  local new = {}
  for name, group in pairs (groups) do
    local order = group.order
    local put = false
    for k, other in pairs (new) do
      if order <= other.order then
        table.insert(new, k, group)
        put = true
        break
      end
    end
    if not put then
      table.insert(new, group)
    end
  end
  return new
end

local get_all_groups = function(items)
  local groups = {}
  local subgroups = {}
  for name, item in pairs (items) do
    if not item.has_flag("hidden") then
      if not groups[item.group.name] then
        --log("Made group "..item.group.name.." because of item "..item.name)
        groups[item.group.name] = item.group
      end
      if not subgroups[item.subgroup.name] then
        subgroups[item.subgroup.name] = {}
      end
      local subgroup = subgroups[item.subgroup.name]
      local order = item.order
      local put = false
      for k, other in pairs (subgroup) do
        if order <= other.order then
          table.insert(subgroup, k, item)
          put = true
          break
        end
      end
      if not put then
        table.insert(subgroup, item)
      end
    end
  end
  return sort_groups(groups), subgroups
end

local make_markets = function(surface)

  local subgroup_filter =
  {
    --["science-pack"] = true,
    ["raw-resource"] = true,
    ["armor"] = true,
    ["equipment"] = true
  }

  local name_filter =
  {
    --["lab"] = true
  }

  local prices = script_data.prices

  local is_valid_item = function(item)
    local name = item.name
    if not (prices[name] and (prices[name] <= config.starting_money) and prices[name] >= 1) then
      return false
    end

    if name_filter[name] or subgroup_filter[item.subgroup.name] then
      return false
    end

    if item.has_flag("hidden") then
      return false
    end

    return true

  end

  local items = {}
  for k, item in pairs (game.item_prototypes) do
    if is_valid_item(item) then
      items[k] = item
    end

  end

  local groups, subgroups = get_all_groups(items)
  --error(serpent.block{groups = groups, subgroups = subgroups})
  local market_width = 5
  local width = math.min(market_width * #groups, 40)
  market_width = width / #groups
  local offset = {2, -5}
  local icon_offset = {0, 0}
  local icon_scale = 0.5

  for k, group in pairs (groups) do
    local market = surface.create_entity
    {
      name = "market",
      position = {((k - 1) * market_width) - (width / 2) + offset[1], offset[2]},
      force = "player"
    }
    market.destructible = false

    rendering.draw_sprite
    {
      sprite = "utility/entity_info_dark_background",
      surface = surface,
      target = market,
      target_offset = icon_offset,
      x_scale = icon_scale * 4,
      y_scale = icon_scale * 4,
      only_in_alt_mode = true
    }

    rendering.draw_sprite
    {
      sprite = "item-group/"..group.name,
      surface = surface,
      target = market,
      target_offset = icon_offset,
      x_scale = icon_scale,
      y_scale = icon_scale,
      only_in_alt_mode = true
    }

    for k, subgroup in pairs (group.subgroups) do
      local items = subgroups[subgroup.name]
      if items then
        for k, item in pairs (items) do
          local price = prices[item.name]
          local count = 1
          if price < 40 then
            count = math.floor(40 / price)
            price = price * count
          end
          market.add_market_item
          {
            price = {{"coin", price}}, offer = {type = "give-item", item = item.name, count = count}
          }
        end
      end
    end

  end

end

local make_money_bags = function(surface)

  local offsets =
  {
    {-4, 4},
    {3, 4},
    {-4, 3},
    {3, 3}
  }

  local money_per_chest = config.starting_money / #offsets

  for k, offset in pairs (offsets) do
    local chest = surface.create_entity{name = "steel-chest", force = "player", position = offset}
    chest.insert{name = "coin", count = money_per_chest}
    chest.minable = false
    chest.destructible = false
  end

end

local get_lobby = function()
  local lobby = game.surfaces.lobby
  if (lobby and lobby.valid) then
    return lobby
  end

  lobby = game.create_surface("lobby", {width = 1, height = 1})

  lobby.solar_power_multiplier = 0

  for x = -1, 1 do
    for y = -1, 1 do
      lobby.set_chunk_generated_status({x, y}, defines.chunk_generated_status.entities)
    end
  end

  local tiles = {}

  for x = -20, 19 do
    for y = -10, 9 do
      local name = "refined-concrete"
      if x == -20 or x == 19 or y == -10 or y == 9 then
        name = "tutorial-grid"
      end
      table.insert(tiles, {name = name, position = {x, y}})
    end
  end

  for x = -3, 2 do
    for y = 9, 9 + 29 do
      local name = "refined-concrete"
      if x == -3 or x == 2 or y == 9 + 29 then
        name = "tutorial-grid"
      end
      table.insert(tiles, {name = name, position = {x, y}})
    end
  end

  for x = -6, 5 do
    for y = 31, 41 do
      local name = "hazard-concrete-left"
      if x == -6 or x == 5 or y == 41 then
        name = "tutorial-grid"
      end
      table.insert(tiles, {name = name, position = {x, y}})
    end
  end

  table.insert(tiles, {name = "tutorial-grid", position = {-5, 30}})
  table.insert(tiles, {name = "tutorial-grid", position = {-6, 30}})
  table.insert(tiles, {name = "tutorial-grid", position = {-4, 30}})
  table.insert(tiles, {name = "tutorial-grid", position = {3, 30}})
  table.insert(tiles, {name = "tutorial-grid", position = {4, 30}})
  table.insert(tiles, {name = "tutorial-grid", position = {5, 30}})

  lobby.set_tiles(tiles)

  lobby.always_day = true
  lobby.daytime = 0

  make_markets(lobby)
  make_money_bags(lobby)

  return lobby

end

local give_respawn_equipment = function(player)
  local equipment = config.starting_equipment
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

local launchpad_area = {{x = -5, y = 31}, {x = 5, y = 41}}
local teleport_shift = {x = 0, y = -36}

local start_round = function()
  script_data.game_state = game_state.in_progress

  local surface = game.surfaces.nauvis
  surface.request_to_generate_chunks({0,0}, 5)
  surface.force_generate_chunk_requests()

  local spawn_position = surface.find_non_colliding_position("rocket-silo", {0,0}, 100, 2, false) or {0,0}

  game.forces.player.set_spawn_position(spawn_position, surface)

  local tiles = {}
  for x = -5, 4 do
    for y = -5, 4 do
      local name = "refined-hazard-concrete-left"
      table.insert(tiles, {name = name, position = {x + spawn_position.x, y + spawn_position.y}})
    end
  end

  surface.set_tiles(tiles)

  local remove_param = {name = "coin", count = config.starting_money}

  local get_position = function(position, entity)
    return surface.find_non_colliding_position(entity, {(position.x + teleport_shift.x) + spawn_position.x, (position.y + teleport_shift.y) + spawn_position.y}, 100, 0.25, false)
  end

  for k, player in pairs (game.players) do
    if player.surface ~= surface then
      if player.vehicle then
        if player.vehicle.train then
          player.driving = false
          player.teleport(get_position(player.position, player.character and player.character.name or "character"), surface)
        else
          player.vehicle.remove_item(remove_param)
          player.vehicle.teleport(get_position(player.vehicle.position, player.vehicle.name), surface)
        end
      else
        player.teleport(get_position(player.position, "character"), surface)
      end
    end

    player.remove_item(remove_param)

    if player.character then
      player.get_inventory(defines.inventory.character_trash).remove(remove_param)
    end

  end

  local lobby = get_lobby()
  local entities = lobby.find_entities_filtered{area = launchpad_area}
  for k, entity in pairs (entities) do
    entity.remove_item(remove_param)
    if not entity.valid then
      entities[k] = nil
    end
  end
  lobby.clone_entities{entities = entities, destination_offset = {teleport_shift.x + spawn_position.x, teleport_shift.y + spawn_position.y} , destination_surface = surface}

  surface.play_sound{path = "utility/achievement_unlocked"}

  game.forces.enemy.evolution_factor = config.starting_evolution_factor
  game.forces.enemy.ai_controllable = true

  game.delete_surface(lobby)
  game.reset_time_played()

  game.forces.player.manual_crafting_speed_modifier = 0

  --Don't need these anymore, don't keep them around junking up global.
  script_data.prices = nil

end

local notify_ready = function()

  if not script_data.start_tick then
    script_data.start_tick = game.tick + (59 * 15)
    script_data.tick_of_autosave = game.tick + (59 * 10)
    game.print({"all-players-ready"})
    return
  end

  if game.tick == script_data.tick_of_autosave then
    game.auto_save("rocket-rush-prelaunch")
  end

  if game.tick >= script_data.start_tick then
    start_round()
  end

end

local notify_not_ready = function()
  if not script_data.start_tick then return end
  game.print({"not-all-players-ready"})
  script_data.start_tick = nil
  script_data.tick_of_autosave = nil
end

local is_in_launchpad = function(position)

  local left_top = launchpad_area[1]
  if position.x < left_top.x or position.y < left_top.y then
    return
  end

  local right_bottom = launchpad_area[2]
  if position.x > right_bottom.x or position.y > right_bottom.y then
    return
  end

  return true
end

local check_launchpad = function()

  if script_data.game_state == game_state.in_progress then return end

  local player_count = #game.connected_players
  if player_count == 0 then
    notify_not_ready()
    return
  end

  for k, player in pairs (game.connected_players) do
    if not (is_in_launchpad(player.position)) then
      notify_not_ready()
      return
    end
  end

  notify_ready()

end

local on_player_created = function(event)

  check_launchpad()

  local player = game.get_player(event.player_index)

  player.game_view_settings.show_entity_info = true

  give_respawn_equipment(player)

  if script_data.game_state == game_state.in_progress then
    if game.is_multiplayer() then
      player.print({"msg-intro"})
    else
      game.show_message_dialog{text = {"msg-intro"}}
    end
    return
  end

  if script_data.game_state == game_state.preparing then
    local surface = get_lobby()
    local position = surface.find_non_colliding_position("character", {0,0}, 100, 0.25, false)
    player.teleport(position, surface)

    if game.is_multiplayer() then
      player.print({"msg-intro"})
      player.print({"msg-buy-equipment"})
      player.print({"msg-refund-hint"})
    else
      game.show_message_dialog{text = {"msg-intro"}}
      game.show_message_dialog{text = {"msg-buy-equipment"}}
      game.show_message_dialog{text = {"msg-refund-hint"}}
    end

    return
  end

end

local on_pre_player_died = function(event)
  if script_data.game_state == game_state.in_progress then
    return
  end

  local player = game.get_player(event.player_index)

  local character = player.character
  if character then
    character.health = 1
  end

end

local anti_cheese =
{
  ["refined-concrete"] = true,
  ["hazard-concrete"] = true
}

local check_trash_refund = function()
  if script_data.game_state == game_state.in_progress then
    return
  end

  -- We check trash slots, and refund any items they put there.

  local prices = script_data.prices
  local equipment = config.starting_equipment

  for k, player in pairs (game.connected_players) do
    if player.character then
      local inventory = player.get_inventory(defines.inventory.character_trash)
      if inventory then
        local contents = inventory.get_contents()
        for name, count in pairs (contents) do
          if prices[name] and not (equipment[name] or anti_cheese[name]) then
            local removed_count = inventory.remove({name = name, count = count})
            if removed_count > 0 then
              player.insert{name = "coin", count = removed_count * prices[name]}
            end
          end
        end
      end
    end
  end

end

local lib = {}

lib.events =
{
  [defines.events.on_player_created] = on_player_created,
  [defines.events.on_pre_player_died] = on_pre_player_died,

}

lib.on_nth_tick =
{
  [59] = check_launchpad,
  [127] = check_trash_refund
}

lib.on_init = function()
  global.rocket_rush = global.rocket_rush or script_data

  script_data.prices = production_score.generate_price_list(config.prices_param)
  script_data.game_state = game_state.preparing

  game.forces.player.research_all_technologies()
  game.forces.player.manual_crafting_speed_modifier = -1
  --game.forces.player.disable_research()

  game.forces.enemy.evolution_factor = config.starting_evolution_factor
  game.forces.enemy.ai_controllable = false

end

lib.on_load = function()
  script_data = global.rocket_rush or script_data
end

lib.on_configuration_changed = function()

end

return lib
