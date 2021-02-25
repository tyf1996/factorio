require "story"

script.on_init(function()
  global.story = story_init()
  game.surfaces[1].always_day = true
  global.items = init_prototypes()
end)

function on_player_created(event)
  local player = game.players[event.player_index]
  player.game_view_settings =
  {
    show_side_menu = false,
    show_research_info = false,
    show_alert_gui = false,
    show_minimap = false
  }
  game.permissions.get_group(0).set_allows_action(defines.input_action.remove_cables, false)
  game.permissions.get_group(0).set_allows_action(defines.input_action.open_production_gui, false)
  game.permissions.get_group(0).set_allows_action(defines.input_action.open_tips_and_tricks_gui, false)
  game.permissions.get_group(0).set_allows_action(defines.input_action.open_blueprint_library_gui, false)
  game.permissions.get_group(0).set_allows_action(defines.input_action.open_logistic_gui, false)
  game.permissions.get_group(0).set_allows_action(defines.input_action.open_technology_gui, false)
  player.character_crafting_speed_modifier = -1 --We don't want them crafting things from the items we give them, until the very end.

  player.force.disable_all_prototypes()
end

intermission =
{
  init = function()
    --player().opened = nil
    player().clear_cursor()
    player().create_local_flying_text
    {
      text = {"tutorial-gui.objective-complete"},
      create_at_cursor = true
    }
  end,
  condition = story_elapsed_check(2)
}

damage = function()
  local character = player().character
  if not character then return end
  character.damage(1/1000000, "player")
end

init_prototypes = function()
  local item_prototypes = game.item_prototypes
  local items =
  {
    wood = item_prototypes["wood"],
    stone = item_prototypes["stone"],
    coal = item_prototypes["coal"],
    iron = item_prototypes["iron-ore"],
    plate = item_prototypes["iron-plate"]
  }
  for k, name in pairs ({"wood", "stone", "coal", "iron", "plate"}) do
    if not items[name] then
      game.set_game_state{player_won = false, game_finished = true, can_continue = false}
    end
  end
  return items
end

story_table =
{
  {
    {
      condition = function() return game.tick >= 60 end,
      update = function() player().zoom = 1 + (game.tick/60) end
    },
    {
      condition = story_elapsed_check(1)
    },
    {
      --Ctrl click To entity
      init = function()
        furnace()
        player().clear_items_inside()
        player().insert(global.items.coal.name)
        player().insert(global.items.coal.name)
        set_goal({"ctrl-click-to-entity"})
        set_info({picture = "file/ctrl-click-to-entity.png"})
      end,
      update = function()
        if player().opened and player().opened == furnace() then
          --They opened the furnace, which they shouldn't be doing
          if furnace().get_item_count(global.items.coal.name) > 0 then
            --Oh naughty
            furnace().remove_item(global.items.coal.name)
            player().clear_cursor()
            player().insert(global.items.coal.name)
            --player().print({"ctrl-click-to-entity"})
            damage()
          end
        end
      end,
      condition = function()
        return player().opened == nil and furnace().get_item_count(global.items.coal.name) > 0
      end
    },
    intermission,
    {
      --Ctrl click to entity from quickbar
      init = function()
        player().clear_items_inside()
        player().insert(global.items.iron.name)
        player().insert(global.items.iron.name)
        player().set_quick_bar_slot(1,global.items.iron.name)
        player().force.recipes['iron-plate'].enabled = true
        set_goal({"ctrl-click-to-entity-2"})
        set_info()
      end,
      update = function()
        if player().opened and player().opened == furnace() then
          --They opened the furnace, which they shouldn't be doing
          if furnace().get_item_count(global.items.iron.name) > 0 then
            --Oh naughty
            furnace().remove_item(global.items.iron.name)
            player().clear_cursor()
            player().clear_items_inside()
            player().insert(global.items.iron.name)
            --player().print({"ctrl-click-to-entity-2"})
            damage()
          end
        elseif player().opened_self then
          player().opened = nil
          damage()
        end
        if player().get_quick_bar_slot(1) == nil then
          damage()
          player().set_quick_bar_slot(1,global.items.iron.name)
        end
      end,
      condition = function()
        return player().opened == nil and furnace().get_item_count(global.items.iron.name) > 0
      end,
      action = function()
        player().game_view_settings.show_entity_info = true
      end
    },
    intermission,
    {
      --Ctrl click from entity
      init = function()
        player().clear_items_inside()
        player().set_quick_bar_slot(1,nil)
        furnace().get_inventory(defines.inventory.furnace_source).insert({name = global.items.iron.name, count = global.items.iron.stack_size / 2})
        furnace().get_inventory(defines.inventory.furnace_result).insert({name = global.items.plate.name, count = global.items.plate.stack_size / 2})
        set_goal({"ctrl-click-from-entity"})
      end,
      update = function()
        if player().opened and player().opened == furnace() then
          if (furnace().get_item_count(global.items.plate.name) < global.items.plate.stack_size / 2) then
            player().clear_cursor()
            player().remove_item({name = global.items.plate.name, count = global.items.plate.stack_size})
            furnace().get_inventory(defines.inventory.furnace_result).insert({name = global.items.plate.name, count = global.items.plate.stack_size / 2})
            --player().print({"ctrl-click-from-entity"})
            damage()
          end
        end
      end,
      condition = function()
        return furnace().get_item_count(global.items.plate.name) < global.items.plate.stack_size / 2
      end
    },
    intermission,
    {
      init = function()
        player().clear_items_inside()
        set_goal({"ctrl-click-to-furnaces"})
        local chest = chest()
        chest.insert({name = global.items.coal.name, count = global.items.coal.stack_size * 6})
        chest.insert({name = global.items.iron.name, count = global.items.iron.stack_size * 6})
        furnace().destroy()
        global.furnaces = {}
        for x = -3, 3, 2 do
          local furnace = surface().create_entity{name = "stone-furnace", position = {x, -3}, force = "player"}
          furnace.minable = false
          table.insert(global.furnaces, furnace)
        end
      end,
      update = function()
        if player().opened then
          player().opened = nil
          damage()
        end
      end,
      condition = function()
        for k, furnace in pairs (global.furnaces) do
          if furnace.valid and furnace.crafting_progress == 0 then
            return false
          end
        end
        return true
      end,
    },
    intermission,
    {
      init = function()
        set_goal({"ctrl-click-from-furnaces"})
        for k, furnace in pairs (global.furnaces) do
          furnace.get_inventory(defines.inventory.furnace_result).insert({name = global.items.plate.name, count = 50})
          furnace.minable = false
        end
      end,
      update = function()
        if player().opened then
          player().opened = nil
          damage()
        end
      end,
      condition = function()
        return player().get_item_count(global.items.plate.name) >= 180
      end
    },
    intermission,
    {
      init = function()
        player().force.reset()
        player().character_crafting_speed_modifier = 0
        set_goal({"finish-text"})
        set_info({custom_function = function(flow) add_button(flow).caption = {"finish"} end, append = true})
      end,
      condition = function()
        return global.continue
      end
    }
  }
}

story_init_helpers(story_table)

function chest()
  local chest_name = "iron-chest"
  local entities = game.entity_prototypes
  if not entities[chest_name] then
    for name, prototype in pairs (entities) do
      if prototype.type == "container" and prototype.get_inventory_size(1) > 5 then
        chest_name = name
        break
      end
    end
  end
  local entities = surface().find_entities_filtered{name = chest_name}
  if entities and entities[1] then return entities[1] end
  local position = surface().find_non_colliding_position(chest_name, {3, 0}, 32, 1)
  local chest
  if position then
    chest = surface().create_entity{name = chest_name, position = position, force = player().force}
    chest.minable = false
  else
    error("Well whaddya know")
  end
  return chest
end

function furnace()
  local furnace_name = "stone-furnace"
  local entities = game.entity_prototypes
  if not entities[furnace_name] then
    for name, prototype in pairs (entities) do
      if prototype.type == "furnace" then
        furnace_name = name
        break
      end
    end
  end
  local entities = surface().find_entities_filtered{name = furnace_name}
  if entities and entities[1] then return entities[1] end
  local furnace
  local position = surface().find_non_colliding_position(furnace_name, {0, -3}, 32, 1)
  if position then
    furnace = surface().create_entity{name = furnace_name, position = position, force = "player"}
    furnace.minable = false
  else
    error("Well whaddya know")
  end
  return furnace
end

script.on_event(defines.events.on_tick, function(event)
  story_update(global.story, event)
end)

script.on_event(defines.events.on_gui_click, function (event)
  story_update(global.story, event)
end)

script.on_event(defines.events.on_player_created, on_player_created)
