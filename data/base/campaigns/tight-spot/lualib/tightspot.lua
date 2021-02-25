mod_gui = require("mod-gui")
require("util")
require("story")

tightspot_prices =
{
  ["coal"]=5,
  ["transport-belt"]=5,
  ["underground-belt"]=20,
  ["fast-transport-belt"]=50,
  ["fast-underground-belt"]=200,
  ["splitter"]=25,
  ["fast-splitter"]=50,
  ["burner-inserter"]=10,
  ["inserter"]=10,
  ["long-handed-inserter"]=15,
  ["fast-inserter"]=20,
  ["filter-inserter"]=35,
  ["red-wire"]=2,
  ["green-wire"]=2,
  ["wooden-chest"]=5,
  ["iron-chest"]=10,
  ["stone-furnace"]=10,
  ["steel-furnace"]=50,
  ["electric-furnace"]=70,
  ["offshore-pump"]=10,
  ["pipe"]=5,
  ["pipe-to-ground"]=20,
  ["boiler"]=15,
  ["steam-engine"]=50,
  ["small-electric-pole"]=10,
  ["medium-electric-pole"]=50,
  ["big-electric-pole"]=100,
  ["substation"]=150,
  ["assembling-machine-1"]=30,
  ["assembling-machine-2"]=50,
  ["assembling-machine-3"]=100,
  ["electric-mining-drill"]=50,
  ["burner-mining-drill"]=10,
  ["pumpjack"]=50,
  ["oil-refinery"]=100,
  ["chemical-plant"]=50,
  ["storage-tank"]=40,
  ["pump"]=20,
  ["logistic-robot"]=150,
  ["logistic-chest-passive-provider"]=50,
  ["logistic-chest-requester"]=50
}

function tightspot_make_offer(item)
  if not tightspot_prices[item] then game.print(item.." price is not defined. Please report this on the factorio bug forum") return end
  return { price={{"coin", tightspot_prices[item]}}, offer={type="give-item", item=item}}
end

function tightspot_init(level)
  game.players[1].disable_recipe_groups()
  game.players[1].minimap_enabled = false
  game.map_settings.pollution.enabled = false
  global.result_chest = {game.get_entity_by_tag("result-chest").name, game.get_entity_by_tag("result-chest").position}
  global.market = {game.get_entity_by_tag("market").name, game.get_entity_by_tag("market").position}
  global.speed = 8
  local result = {}
  result.level = level
  result.demand = {}
  for index, item in pairs(level.demand) do
    result.demand[item.item] = item.price
  end
  return result
end

function tightspot_get_required_balance()
  if game.difficulty == defines.difficulty.easy then
    return level.required_balance.easy
  elseif game.difficulty == defines.difficulty.normal then
    return level.required_balance.normal
  else
    return level.required_balance.hard
  end
end

function tightspot_init_level(tightspot)
  local player = game.players[1]
  local character = player.character
  player.set_controller{type=defines.controllers.god}
  if character then character.destroy() end
  local playerforce = player.force
  playerforce.manual_mining_speed_modifier = 1000

  local level = tightspot.level
  tightspot.debt = level.money
  tightspot.income = 0
  local surface = player.surface
  local wallCollisionBox = game.entity_prototypes["stone-wall"].collision_box

  for x=level.area[1][1],level.area[2][1],1 do
    for y=level.area[1][2],level.area[2][2],1 do
      local entities = game.players[1].surface.find_entities{{x + 0.1, y + 0.1}, {x + 0.9, y + 0.9}}
      local shouldcover = true
      for index, item in pairs(entities) do
        if item.type == "resource" or
           item.type == "tree" then
          item.minable = false
          if item.type ~= "tree" then
            shouldcover = false
          end
        end
      end
      if shouldcover and surface.can_place_entity{name = "stone-wall", position = {x + 0.5, y + 0.5}} then
        surface.create_entity{name = "stone-wall", position = {x, y}, force=playerforce}
      end
    end
  end
  local market = game.surfaces[1].find_entity(global.market[1], global.market[2])
  for index, item in pairs(level.offers) do
    market.add_market_item(item)
  end
  game.players[1].insert{name = "coin", count = level.money}
  game.players[1].force.disable_all_prototypes()
  local recipe_list = game.players[1].force.recipes
  for index, item in pairs(level.recipes) do
    recipe_list[item].enabled = true
  end
  tightspot_init_spending_frame(tightspot)
  tightspot_update_spending(tightspot)
  game.players[1].clear_recipe_notifications()
end

function tightspot_init_spending_frame(tightspot)
  local player = game.players[1]

  local flow = mod_gui.get_frame_flow(player)
  local frame = flow.add{type="frame", name="tightspot_frame", style=mod_gui.frame_style, caption = {"level", tightspot.level.level_number}, direction="vertical"}
  local inner = frame.add{type = "frame", style = "inside_shallow_frame", direction = "vertical"}
  inner.style.padding = 4
  local info_table = inner.add{type = "table", column_count = 1, style = "bordered_table"}

  local money_flow = info_table.add{type = "flow", direction = "vertical"}

  money_flow.add{type="label", caption={"money"}, style="caption_label"}
  local table = money_flow.add{type="table", column_count=2}

  local available = game.players[1].get_item_count("coin")
  local debt = tightspot.debt

  table.add{type="label", caption={"", {"balance"}, {"colon"}}}
  global.balance_label = table.add{type="label", caption=util.format_number(debt - available), name="balance"}
  table.add{type="label", caption={"", {"required"}, {"colon"}}}
  table.add{type="label", caption=util.format_number(tightspot_get_required_balance())}

  local level = tightspot.level
  table.add{type="label", caption={"", {"time"}, {"colon"}}}
  table.add{type="label", caption=util.formattime(level.time)}

  local demand_flow = info_table.add{type = "flow", direction = "vertical"}

  demand_flow.add{type="label", caption = {"demand"}, style="caption_label"}

  local demand_table = demand_flow.add{type = "table", column_count = 3}
  demand_table.style.column_alignments[3] = "right"
  local item_prototypes = game.item_prototypes
  for index, item in pairs(level.demand) do
    local sprite = demand_table.add{type ="sprite", sprite = "item/"..item.item, style = "small_text_image"}
    demand_table.add{type ="label", caption = {"", item_prototypes[item.item].localised_name, {"colon"}}}
    demand_table.add{type ="label", caption = util.format_number(item.price)}
  end

  mod_gui.get_button_flow(player).add{type = "button", name="tightspot_start", caption={"start"}, style = mod_gui.button_style}
end

function tightspot_init_progress_frame(tightspot)
  local player = game.players[1]
  local flow = mod_gui.get_frame_flow(player)
  local frame = flow.add{type = "frame", name="tightspot_progress_frame", style=mod_gui.frame_style, caption={"progress"}, direction="vertical"}
  local inner = frame.add{type = "frame", direction = "vertical", style = "inside_shallow_frame"}
  inner.style.padding = 4
  local info_table = inner.add{type = "table", column_count = 1, style = "bordered_table"}
  global.progress_bar = info_table.add{type="progressbar", name="tightspot_progressbar", style = "electric_satisfaction_statistics_progressbar"}
  global.progress_bar.style.horizontally_stretchable = true
  global.speed_label = info_table.add{type="label"}
  local controlflow = info_table.add{type="flow"}
  controlflow.add{type="button", caption="+", name="faster"}
  controlflow.add{type="button", caption="-", name="slower"}
  tightspot_update_speed_label()
end

function tightspot_update_progress(tightspot)
  if (game.tick - tightspot.simulation_started_at) % 60 ~= 0 then
    return
  end
  local time = game.tick - tightspot.simulation_started_at
  global.progress_bar.value = time / level.time
  global.progress_bar.caption = {"", {"time"}, {"colon"}, " ", util.formattime(time)}
end

function tightspot_update_spending(tightspot)
  local available
  if game.players[1].controller_type == defines.controllers.god then
    available = game.players[1].get_item_count("coin")
  else
    available = tightspot.available
  end
  local debt = tightspot.debt
  global.balance_label.caption = util.format_number(available - debt + tightspot.income)
end

function tightspot_get_missing_to_win(tightspot)
  local available = tightspot.available
  local debt = tightspot.debt
  local required = tightspot_get_required_balance(tightspot)
  return required + debt - tightspot.income - available
end

function tightspot_sell_back(tightspot)
  local level = tightspot.level
  local player = game.players[1]
  local addition = 0
  for index, item in pairs(level.offers) do
    local count = player.get_item_count(item.offer.item)
    addition = addition + count * item.price[1][2]
  end
  player.surface.create_entity{name = "flying-text", position = player.position, text = "+" .. addition, color = {g = 1}}
  tightspot.debt = tightspot.debt - addition
end

function tightspot_start_level(tightspot)
  map_save()
  tightspot_sell_back(tightspot)
  mod_gui.get_button_flow(game.players[1]).tightspot_start.destroy()
  game.speed = global.speed
  tightspot_init_progress_frame(tightspot)
  mod_gui.get_button_flow(game.players[1]).add{type = "button", name="tightspot_reload", caption={"reload"}, style = mod_gui.button_style}
  tightspot.available = game.players[1].get_item_count("coin")
  game.players[1].set_controller{type=defines.controllers.ghost}
  tightspot.simulation_started_at = game.tick
  local level = tightspot.level
  local entities = game.players[1].surface.find_entities(level.area)
  for index, item in pairs(entities) do
    item.active = true
  end
  tightspot_update_spending(tightspot)
end

function tightspot_show_level_description(tightspot)
  local level = tightspot.level
  if level.description ~= nil then
    game.show_message_dialog(level.description)
  end
end

function tightspot_update_speed_label()
  global.speed_label.caption = {"", {"speed"}, {"colon"}, " ", game.speed}
end

local safe_name = "safe-surface-really-nice-place-and-peaceful"
local get_save_surface = function()
  return game.surfaces[safe_name] or game.create_surface(safe_name, {width = 200, height = 200})
end

local save_area = {{-200, -200}, {200, 200}}
local save_surface = function()
  game.surfaces[1].clone_area
  {
    source_area = save_area,
    destination_area = save_area,
    destination_surface = get_save_surface(),
    clone_tiles = true,
    clone_entities = true,
    clone_decoratives = true,
    clear_destination_entities = true,
    clear_destination_decoratives = true,
    expand_map= true
  }
end

local load_surface = function()
  get_save_surface().clone_area
  {
    source_area = save_area,
    destination_area = save_area,
    destination_surface = game.surfaces[1],
    clone_tiles = true,
    clone_entities = true,
    clone_decoratives = true,
    clear_destination_entities = true,
    clear_destination_decoratives = true,
    expand_map= true
  }
end

function map_load()
  game.speed = 1
  global.tightspot = global.save.tightspot
  load_surface()
  game.players[1].set_controller{type=defines.controllers.god}
  for k = 1, 10 do
    local inv = game.players[1].get_inventory(k)
    if inv then
      inv.clear()
      if global.save.player_inventory[k] then
        for name, count in pairs (global.save.player_inventory[k]) do
          game.players[1].insert({name = name, count = count})
        end
      end
    end
  end
  if mod_gui.get_button_flow(game.players[1]).tightspot_reload then
    mod_gui.get_button_flow(game.players[1]).tightspot_reload.destroy()
  end
  if mod_gui.get_frame_flow(game.players[1]).tightspot_progress_frame then
    mod_gui.get_frame_flow(game.players[1]).tightspot_progress_frame.destroy()
  end
  story_jump_to(global.story, "building")
  mod_gui.get_button_flow(game.players[1]).add{type = "button", name="tightspot_start", caption={"start"}, style = mod_gui.button_style}

end

function map_save()
  global.save = {}
  local player = game.players[1]
  local chest = game.surfaces[1].find_entity(global.result_chest[1], global.result_chest[2])
  if chest then
    for name, count in pairs (chest.get_output_inventory().get_contents()) do
      player.insert({name = name, count = count})
    end
    chest.clear_items_inside()
  end
  global.save.tightspot = util.table.deepcopy(global.tightspot)

  save_surface()

  local player_inventory = {}
  for k = 1, 10 do
    local inv = player.get_inventory(k)
    if inv then
      player_inventory[k] = inv.get_contents()
    end
  end
  global.save.player_inventory = player_inventory
end

function tightspot_check_level(tightspot, event)
  if event.name == defines.events.on_gui_click then
    if event.element.name == "slower" and global.speed > 1 then
      global.speed = global.speed / 2
      game.speed = global.speed
      tightspot_update_speed_label(tightspot)
    elseif event.element.name == "faster" and global.speed < 64 then
      global.speed = global.speed * 2
      game.speed = global.speed
      tightspot_update_speed_label(tightspot)
    elseif event.element.name == "tightspot_reload" then
      map_load()
      return false
    end
    return false
  end
  local result_chest = game.surfaces[1].find_entity(global.result_chest[1], global.result_chest[2])
  local contents = result_chest.get_inventory(defines.inventory.chest).get_contents()
  local addition = 0
  for item_name, count in pairs(contents) do
    local price = tightspot.demand[item_name]
    if price ~= nil then
      addition = addition + price * count
    end
  end
  if addition ~= 0 then
    game.players[1].surface.create_entity{name = "flying-text", position = result_chest.position, text = "+" .. addition, color = {g = 1}}
    tightspot.income = tightspot.income + addition
    tightspot_update_spending(tightspot)
    result_chest.clear_items_inside()
  end
  tightspot_update_progress(tightspot)
  return (game.tick - tightspot.simulation_started_at) >= level.time
end

function land_price(level, position)
  return math.abs(position.x - level.center.x) + math.abs(position.y - level.center.y)
end

story_table =
{
  {
    {
      action = function()
        tightspot_init_level(global.tightspot)
      end
    },
    {
      action = function()
        if level.showrules ~= nil then
          game.show_message_dialog{text={"welcome"}}
          game.show_message_dialog{text={"rules1"}}
          game.show_message_dialog{text={"rules2"}}
          game.show_message_dialog{text={"rules3"}}
        end
      end
    },
    {
      action = function()
        tightspot_show_level_description(global.tightspot)
      end
    },
    {
      name = "building",
      update =
      function(event)
        if event.name == defines.events.on_tick then return end
        tightspot_update_spending(global.tightspot)
        if event.name == defines.events.on_built_entity then
          if event.created_entity.name == "stone-wall" then
            local entity = event.created_entity
            local position = entity.position
            local area = {{position.x - 0.4, position.y - 0.4}, {position.x + 0.4, position.y + 0.4}}
            if #game.players[1].surface.find_entities_filtered{area = area, type = "resource"} ~= 0 then
              event.created_entity.destroy()
              game.players[1].insert{name = "stone-wall", count = 1}
              game.players[1].print("This area is not resellable")
              return
            end
            local price = land_price(level, event.created_entity.position)
            game.players[1].surface.create_entity{name = "flying-text", position = event.created_entity.position, text = "+" .. price, color = {g = 1}}
            game.players[1].insert{name = "coin", count = price}
          else
            event.created_entity.active = false
          end
        end
        if event.name == defines.events.on_pre_player_mined_item and
           event.entity.name == "stone-wall" then
          local position = event.entity.position
          local price = land_price(level, event.entity.position)
          game.players[1].surface.create_entity{name = "flying-text", position = event.entity.position, text = "-" .. price, color = {r = 1}}
          local available = game.players[1].get_item_count("coin")
          game.players[1].remove_item{name = "coin", count = price}
          if available < price then
            global.tightspot.debt = global.tightspot.debt + 5000
            game.players[1].insert{name = "coin", count = 5000 - price + available}
            game.players[1].print("Borrowed 5000 coins to pay for the land")
          end
        end
      end,
      condition =
      function(event)
        return event.name == defines.events.on_gui_click and event.element.name == "tightspot_start"
      end,
      action =
      function()
        tightspot_start_level(global.tightspot)
      end
    },
    {
      condition =
      function(event)
        return tightspot_check_level(global.tightspot, event)
      end,
      action =
      function()
        local missing = tightspot_get_missing_to_win(global.tightspot)
        if missing > 0 then
          game.show_message_dialog{text={"lost-message", missing}}
        else
          game.show_message_dialog{text={"won-message", -missing}}
        end
      end
    },
    {
      condition =
      function()
        if tightspot_get_missing_to_win(global.tightspot) > 0 then
          map_load()
          return false
        end
        return true
      end,
      action = function() end
    }
  }
}

story_init_helpers(story_table)

tightspot_events =
{
  defines.events.on_gui_click,
  defines.events.on_tick,
  defines.events.on_built_entity,
  defines.events.on_player_cursor_stack_changed,
  defines.events.on_pre_player_mined_item
}
