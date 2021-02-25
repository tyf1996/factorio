require "util"
require("story")

local set_arrow = function(arrow_settings)
  if global.arrow then
    global.arrow.destroy()
  end
  if arrow_settings == nil then
    global.arrow = nil
  else
    global.arrow = game.players[1].surface.create_entity(arrow_settings)
  end
end

local generate_pause_to_think_node = function(thought)
  if not global.thoughts then global.thoughts = {} end
  global.thoughts[thought] = false
  return
  {
    name = 'pause-to-think-'..thought,
    init = function()
      game.players[1].set_goal_description("")
    end,
    condition = story_elapsed_check(3),-- or global.thoughts[thought] == true end,
    action = function()
      if global.thoughts[thought] == false then
        game.players[1].print({"","[img=entity/character][color=orange]",{"engineer-title"},": [/color]",{"think-"..thought}})
      end
    end
  }
end

local generate_post_pause_to_think_node = function(thought)
  return {
    name = 'after-pause-to-think-'..thought,
    condition = story_elapsed_check(3),-- or global.thoughts[thought] == true end,
    action = function()
      global.thoughts[thought] = true
    end
  }
end

local count_items_in_container = function (container)
  return container.get_item_count("coal") +
  container.get_item_count("iron-ore") +
  container.get_item_count("stone") +
  container.get_item_count("iron-plate") +
  container.get_item_count("stone-brick")
end

local count_smelted_objects_in_furnace = function (container)
  return container.get_item_count("iron-plate") +
  container.get_item_count("stone-brick")
end

local count_fuel_objects_in_drill = function (container)
  return container.get_item_count("coal")
end

local count_items_in_unknown = function(container)
  local count = 0
  if container.type == 'container' then
    count = count_items_in_container(container)
  elseif container.name == 'burner-mining-drill' then
    count = count_fuel_objects_in_drill(container)
  elseif container.name == 'stone-furnace' then
    count = count_smelted_objects_in_furnace(container)
  end
  return count
end

local get_furnace = function()

  if global.furnace and global.furnace.valid then
    return global.furnace
  end

  local furnaces = game.surfaces[1].find_entities_filtered({name='stone-furnace'})
  if #furnaces > 0 then
    global.furnace = furnaces[1]
    return global.furnace
  end

end

local get_miner_drop_target = function()
  if global.miner and global.miner.valid and global.miner_drop_target and global.miner_drop_target.valid and global.miner.drop_target == global.miner_drop_target then
    return global.miner_drop_target
  end
  local miners = game.surfaces[1].find_entities_filtered({name='burner-mining-drill'})
  for _, miner in pairs(miners) do
    if miner.drop_target then
      global.miner_drop_target = miner.drop_target
      global.miner = miner
      --game.print("miner drop target changed "..global.miner_drop_target.name)
      --game.print("miner changed "..global.miner.name)
      return global.miner_drop_target
    end
  end
  return nil
end

local get_miner = function()

  if global.miner and global.miner.valid then
    return global.miner
  end

  local miners = game.surfaces[1].find_entities_filtered({name='burner-mining-drill'})
  for _, miner in pairs(miners) do
    if miner.drop_target then
      global.miner = miner
      return global.miner
    end
  end

  if #miners > 0 then
    global.miner = miners[1]
  end

end

local intro_time = 500

-- Definition of the level behaviour, it is used by the story module
local story_table =
{
  {
    {
      name = 'setup',
      init = function()
        game.players[1].disable_recipe_groups()
        game.players[1].disable_recipe_subgroups()
        game.players[1].minimap_enabled = false
        game.players[1].character.disable_flashlight()
        game.players[1].force.disable_all_prototypes() -- Only let the player have stuff we explicitly allowed
        game.players[1].force.disable_research()
        game.players[1].zoom = 2
        game.map_settings.pollution.enabled = false
        game.players[1].game_view_settings =
        {
          show_quickbar = false,
          show_shortcut_bar = false,
          show_side_menu = false
        }

        game.players[1].surface.daytime = 0.5

        global.starting_player_position = game.players[1].position

        local recipelist = game.players[1].force.recipes
        recipelist["iron-plate"].enabled = true
        recipelist["copper-plate"].enabled = true
        game.players[1].clear_recipe_notifications()
        global.wreck = game.get_entity_by_tag("wreck")
        global.wreck.insert({ name = "iron-gear-wheel", count = 2 })
      end
    },
    {
      name = 'sunrise',
      init = function()
        local player = game.get_player(1)
        player.set_controller
        {
          type = defines.controllers.cutscene,
          waypoints =
          {
            {
              target = player.character,
              zoom = 2,
              transition_time = intro_time,
              time_to_wait = 0
            }
          },
          start_zoom = 3,
          start_position = player.position
        }
      end,
      update = function()
        game.surfaces[1].daytime = math.min(game.players[1].surface.daytime + (0.5 / intro_time), 1)
      end,
      condition = function() return game.players[1].surface.daytime > 0.95 end,
      action = function()
        game.players[1].surface.freeze_daytime = true
      end
    },
    generate_pause_to_think_node('introduction'),
    generate_post_pause_to_think_node('introduction'),
    {
      name = 'think-2',
      condition = story_elapsed_check(2),
      action = function()
        game.show_message_dialog({
          text = {"msg-intro"},
          point_to = {
            type = "entity",
            entity = game.players[1].character
          }
        })
      end
    },
    {
      name = 'movement',
      init = function()
        game.show_message_dialog({
          text = {"msg-goal-in-top-left"},
          point_to = {type = "goal"}
        })
        game.players[1].set_goal_description({"goal-movement"})
      end,
      condition = function()
        return util.distance(global.starting_player_position, game.players[1].position) > 5
      end,
      action = function()
        if global.wreck.get_item_count("iron-gear-wheel") ~= 2 then
          story_jump_to( global.story,"iron-ore-gathering")
        end
      end
    },
    generate_pause_to_think_node('search-wreck'),
    generate_post_pause_to_think_node('search-wreck'),
    {
      name = 'close-inv-if-open',
      init = function()
        if game.players[1].opened_self == true then
          game.players[1].set_goal_description({"goal-close-character-screen"})
        end
      end,
      condition = function()
        return game.players[1].opened_self == false
      end
    },
    {
      name = 'open-wreck',
      init = function()
        game.players[1].set_goal_description({"goal-search-wreck"})
        game.players[1].set_gui_arrow({type="position", position=game.get_entity_by_tag('wreck').position})
      end,
      condition = function(event)
        --if event.name == defines.events.on_tick then return false end
        return game.players[1].opened == game.get_entity_by_tag('wreck') or game.get_entity_by_tag('wreck').get_item_count('iron-gear-wheel') == 0
      end
    },
    {
      name = 'take-plates-from-wreck',
      init = function()
        game.players[1].set_goal_description({"goal-take-iron-from-wreck"})
        game.players[1].clear_gui_arrow()
      end,
      condition = function (event)
        --if event.name == defines.events.on_tick then return false end
        return (game.players[1].cursor_stack.valid_for_read and
        game.players[1].cursor_stack.count >= 2) or
        game.get_entity_by_tag('wreck').get_item_count('iron-gear-wheel') == 0
      end
    },
    {
      name = 'put-plates',
      condition = function (event)
        return (game.players[1].get_item_count('iron-gear-wheel') >= 2 and
        game.players[1].cursor_stack.valid_for_read == false)
      end
    },
    {
      name = 'close-wreck-gui',
      init = function()
        game.players[1].set_goal_description({"goal-close-screen"})
      end,
      condition = function(event)
        --if event.name == defines.events.on_tick then return false end
        return game.players[1].opened == nil
      end,
      action = function()
        game.players[1].set_goal_description({""})
      end
    },
    generate_pause_to_think_node('nothing-more'),
    generate_post_pause_to_think_node('nothing-more'),
    {
      name = 'wait-longer',
      condition = story_elapsed_check(1)
    },
    generate_pause_to_think_node('see-iron-ore'),
    generate_post_pause_to_think_node('see-iron-ore'),
    {
      name = "iron-ore-gathering",
      init = function()

        game.players[1].set_gui_arrow({type="position", position={-15.5,-3.5}})
        game.players[1].set_goal_description({"goal-mine-iron-ore"})
      end,
      condition = function(event)
        if event.name == defines.events.on_tick then return false end
        local selectedentity = game.players[1].selected
        return selectedentity ~= nil and selectedentity.name == "iron-ore" and game.players[1].can_reach_entity(selectedentity)
      end
    },
    {
      name = 'show-tooltip',
      init = function()
        game.players[1].clear_gui_arrow()
      end,
      action = function()
        game.show_message_dialog({
          text = {"msg-entity-info"},
          point_to = {type = "entity_info"}
        })
      end
    },
    {
      name = 'handmining',
      init = function()
        game.players[1].set_goal_description({"goal-mine-iron-ore-precise",
        game.players[1].get_item_count('iron-ore'), 5})
      end,
      update = function(event)
        if event.name == defines.events.on_tick then return false end
        game.players[1].set_goal_description({"goal-mine-iron-ore-precise",
        game.players[1].get_item_count('iron-ore'), 5},true)
      end,
      condition = function(event)
        if event.name == defines.events.on_tick then return false end
        return game.players[1].get_item_count("iron-ore") >= 5
      end
    },
    generate_pause_to_think_node('smelt-iron'),
    generate_post_pause_to_think_node('smelt-iron'),
    {
      name = 'craft-furnace-start',
      init = function()
        game.players[1].set_goal_description({"goal-craft-furnace"})

      end,
      condition = function (event)
        return game.players[1].opened_gui_type == defines.gui_type.controller
      end
    },
    {
      name = 'wait-for-crafting-to-open',
      condition = story_elapsed_check(0.0000001),
      action = function()
        local recipelist = game.players[1].force.recipes
        recipelist["stone-furnace"].enabled = true
      end
    },
    {
      name = 'craft-furnace-finish',
      init = function()
        game.show_message_dialog({text={"msg-recipes-info-1"}, point_to= {type="active_window"}})
        game.show_message_dialog({text={"msg-recipes-info-3"}, point_to= {type="active_window"}})
      end,
      condition = function (event)
        if event.name == defines.events.on_tick then return false end
        return game.players[1].crafting_queue_size > 0
      end
    },
    {
      name = 'show-crafting-queue',
      init = function()
        game.show_message_dialog({
          text={"msg-crafting-queue-1"},
          point_to=
          {
            type = "crafting_queue",
            crafting_queueindex = game.players[1].crafting_queue_size
          }
        })
      end,
      condition = function(event)
        if event.name == defines.events.on_tick then return false end
        return game.players[1].get_item_count("stone-furnace") >= 1
      end
    },
    {
      name = 'place-stone-furnace',
      init = function()
        game.players[1].set_goal_description({"goal-build-furnace"})
      end,
      condition = function(event)
        if event.name == defines.events.on_tick then return false end
        return get_furnace()
      end,
      action = function()
        if global.placed_furnace_before == true then
          story_jump_to(global.story,'wait-for-iron-plates')
        end
      end
    },
    generate_pause_to_think_node('furnace-useful'),
    generate_post_pause_to_think_node('furnace-useful'),
    {
      name = 'open-furnace',
      init = function()
        game.players[1].set_goal_description({"goal-open-furnace"})
      end,
      update = function(event)
        if event.name == defines.events.on_tick then return false end
        if not get_furnace() then
          story_jump_to(global.story,'place-stone-furnace')
        end
      end,
      condition = function(event)
        if event.name == defines.events.on_tick then return false end
        return (get_furnace() and game.players[1].opened == get_furnace()) or
        get_furnace() and get_furnace().get_item_count('iron-ore') > 0
      end
    },
    {
      name = 'put-iron-ore',
      init = function()
        game.players[1].set_goal_description({"goal-insert-iron-into-furnace"})
      end,
      update = function(event)
        if event.name == defines.events.on_tick then return false end
        if not get_furnace() then
          story_jump_to(global.story,'place-stone-furnace')
        end
      end,
      condition = function(event)
        if event.name == defines.events.on_tick then return false end
        return get_furnace() and get_furnace().get_item_count('iron-ore') > 0
      end
    },
    {
      name = 'put-coal',
      init = function()
        game.players[1].set_goal_description({"goal-insert-fuel-into-furnace"})
      end,
      update = function (event)
        if event.name == defines.events.on_tick then return false end
        if not get_furnace() then
          story_jump_to(global.story,'place-stone-furnace')
        end
      end,
      condition = function()
        local furnace = get_furnace()
        return furnace and furnace.valid and furnace.energy > 0
      end
    },
    {
      name = 'show-furnace-smelting',
      init = function()
        game.players[1].set_goal_description("")
        if game.players[1].opened == get_furnace() then
          game.show_message_dialog(
          {
            text={"msg-furnace-working"},
            point_to={type="active_window"}
          })
        elseif game.players[1].opened == nil then
          game.show_message_dialog(
          {
            text={"msg-furnace-working"},
            point_to={type="entity", entity=get_furnace()}
          })
        end
      end,
      update = function(event)
        if event.name == defines.events.on_tick then return false end
        if not get_furnace() then
          story_jump_to(global.story,'place-stone-furnace')
        end
      end,

    },
    generate_pause_to_think_node('tired'),
    generate_post_pause_to_think_node('tired'),
    {
      name = 'wait-for-iron-plates',
      init = function()
        if global.placed_furnace_before == true then
          game.players[1].set_goal_description({"goal-wait-for-smelting"})
        else
          game.players[1].set_goal_description("")
        end
        global.placed_furnace_before = true

      end,
      condition = function(event)
        if event.name == defines.events.on_tick and event.tick % 60 ~= 0 then return end

        local furnace = get_furnace()
        if not furnace then
          story_jump_to(global.story,'place-stone-furnace')
          return
        end

        local plate_count = furnace.get_item_count("iron-plate")
        if plate_count > 3 then return true end

        local ore_count = furnace.get_item_count("iron-ore")
        if ore_count > 0 then return end

        if game.players[1].get_item_count("iron-plate") > 3 then
          --Player took the plates, skip somewhere more relevant.
          story_jump_to(global.story,'craft-burner-mining-drill')
          return
        end

      end
    },
    {
      name = 'take-plates-from-furnace',
      init = function()
        game.players[1].set_goal_description({"goal-get-iron-plates-from-furnace"})
        game.players[1].set_gui_arrow({type="entity", entity=get_furnace()})
      end,
      update = function(event)
        if event.name == defines.events.on_tick then return false end
        if get_furnace() == nil then
          game.players[1].clear_gui_arrow()
          story_jump_to(global.story,'place-stone-furnace')
        end
      end,
      condition = function (event)
        if event.name == defines.events.on_tick then return false end
        return get_furnace() and get_furnace().get_item_count('iron-plate') == 0
      end,
      action = function()
        game.players[1].clear_gui_arrow()
      end
    },
    {
      name = 'craft-burner-mining-drill',
      init = function()
        game.players[1].set_goal_description({"goal-craft-burner-miner"})
        local recipelist = game.players[1].force.recipes
        recipelist["iron-gear-wheel"].enabled = true
        recipelist["burner-mining-drill"].enabled = true
      end,
      condition = function (event)
        if event.name == defines.events.on_tick then return false end
        return game.players[1].get_item_count("burner-mining-drill") > 0
      end
    },
    {
      name = 'add_filter',
      init = function()
        game.players[1].set_goal_description({"goal-add-filter"})
        game.players[1].game_view_settings = {
          show_quickbar = true
        }
      end,
      condition = function(event)
        for slot=1,40 do
          if game.players[1].get_quick_bar_slot(slot)
             and game.players[1].get_quick_bar_slot(slot).name == 'burner-mining-drill' then
            return true
          end
        end
        if event.name == defines.events.on_built_entity
           and event.created_entity.name == "burner-mining-drill" then
          global.miner = event.created_entity
          return true
        end
        return false
      end
    },
    {
      name = 'empty-hand-contents',
      init = function ()
        if not game.players[1].cursor_stack.valid_for_read then
          --Already empty...
          story_jump_to( global.story,"place-burner-mining-drill")
        end
        if get_furnace() then
          --Already built it
          story_jump_to( global.story,"fuel-burner-mining-drill")
        end
        game.players[1].set_goal_description({"goal-fast-empty-hand"})
      end,
      condition = function ()
        return game.players[1].cursor_stack.valid_for_read == false
      end
    },
    {
      name = 'place-burner-mining-drill',
      init = function()
        set_arrow()
        game.players[1].set_goal_description({"goal-place-burner-miner"})
      end,
      condition = function (event)
        if event.name == defines.events.on_tick then return false end
        return get_miner() and get_miner().valid
      end
    },
    {
      name = 'fuel-burner-mining-drill',
      init = function()
        game.players[1].set_goal_description({"goal-insert-fuel-into-burner-miner"})
      end,
      update = function(event)
        if event.name == defines.events.on_tick and event.tick % 60 ~= 0 then return false end
        if get_miner() == nil then
          story_jump_to(global.story,'place-burner-mining-drill')
        elseif get_miner().valid and get_miner().energy > 0 then
          game.players[1].set_goal_description("")
        end
      end,
      condition = function (event)
        if event.name == defines.events.on_tick and event.tick % 60 ~= 0 then return false end
        return get_miner() and get_miner().valid and get_miner().energy > 0
      end

    },
    generate_pause_to_think_node('burner-miner-working'),
    generate_post_pause_to_think_node('burner-miner-working'),
    {
      name = 'wait-to-check-target',
      init = function()
        game.players[1].set_goal_description("")
      end,
      condition = function(event)
        if event.name == defines.events.on_tick and event.tick % 60 ~= 0 then return false end
        return game.players[1].opened == nil and (game.surfaces[1].count_entities_filtered({name='item-on-ground'}) > 0 and
        get_miner() and get_miner().status == defines.entity_status.waiting_for_space_in_destination) or
        get_miner_drop_target() or get_miner() == nil
      end,
      action = function()
        local drop_target = get_miner_drop_target()
        local miner = get_miner()
        if get_miner() == nil then
          story_jump_to(global.story,'place-burner-mining-drill')
        elseif drop_target and drop_target.can_insert(miner.mining_target.name) then
          story_jump_to(global.story,'wait-for-chest-to-fill')
        elseif drop_target then
          story_jump_to(global.story,'remove-blocking-entity')
        elseif global.picked_up_item_before == true then
          story_jump_to(global.story,'place-iron-chest')
        end
      end
    },
    {
      name = 'show-miner-blockage',
      init = function()

        game.players[1].set_goal_description("")
        game.show_message_dialog({
          text={"msg-burner-miner-resources-placement"},
          point_to={type="position", position=global.miner.drop_position}
        })
        set_arrow({name="orange-arrow-with-circle", position = global.miner.drop_position})
        game.players[1].set_goal_description({"goal-pick-mined-item"})
      end,
      update = function(event)
        if event.name == defines.events.on_tick then return false end
        if get_miner() == nil then
          set_arrow()
          story_jump_to(global.story,'place-burner-mining-drill')
        end
      end,
      condition = function (event)
        if event.name == defines.events.on_tick then return false end
        if event.name == defines.events.on_player_mined_entity and event.entity.name =='item-on-ground' then
          return true
        elseif event.name == defines.events.on_picked_up_item then
          return true
        end
        return false
      end,
      action = function()
        set_arrow()
      end
    },
    generate_pause_to_think_node('storage-needed'),
    generate_post_pause_to_think_node('storage-needed'),
    {
      name = 'craft-iron-chest',
      init = function()
        global.placed_miner_before = true
        global.picked_up_item_before = true
        game.players[1].set_goal_description({"goal-craft-chest"})
        local recipelist = game.players[1].force.recipes
        recipelist["wooden-chest"].enabled = true
        recipelist["iron-chest"].enabled = true
      end,
      condition = function (event)
        if event.name == defines.events.on_tick then return false end
        local have_wood_chest = game.players[1].get_item_count("wooden-chest") > 0
        local have_iron_chest = game.players[1].get_item_count("iron-chest") > 0
        local placed_any_chest = game.surfaces[1].count_entities_filtered({name={'wooden-chest','iron-chest'}}) > 0
        return  have_wood_chest or have_iron_chest or placed_any_chest
      end,
      update = function(event)
        if get_miner() == nil then
          story_jump_to(global.story,'place-burner-mining-drill')
        elseif get_miner().energy == 0 then
          story_jump_to(global.story,'fuel-burner-mining-drill')
        end
      end
    },
    {
      name = 'place-iron-chest',
      init = function()
        game.players[1].set_goal_description({"goal-put-chest-below-burner-miner"})
        set_arrow({name="orange-arrow-with-circle", position = global.miner.drop_position})
        local recipelist = game.players[1].force.recipes
        recipelist["wooden-chest"].enabled = true
      end,
      update = function(event)
        if event.name == defines.events.on_tick then return false end
        if get_miner() == nil then
          story_jump_to(global.story,'place-burner-mining-drill')
        elseif get_miner().energy == 0 then
          story_jump_to(global.story,'fuel-burner-mining-drill')
        end
      end,
      condition = function (event)
        if event.name == defines.events.on_tick then return false end
        return get_miner_drop_target() and get_miner_drop_target().valid and get_miner_drop_target().can_insert(get_miner().mining_target.name)
      end,
      action = function(event)
        set_arrow()
      end
    },
    generate_pause_to_think_node('learned-something'),
    generate_post_pause_to_think_node('learned-something'),
    {
      name = 'wait-for-chest-to-fill',
      init = function()
        if get_miner_drop_target() then
          global.original_count = count_items_in_unknown(get_miner_drop_target())
          if get_miner_drop_target().name == 'stone-furnace' then
            game.players[1].set_goal_description({"goal-collect-in-furnace",
            global.original_count + 2,
            get_miner_drop_target().localised_name})
          else
            game.players[1].set_goal_description({"goal-collect-in-container",
            global.original_count + 2,
            get_miner_drop_target().localised_name})
          end
        end
      end,
      update = function (event)
        if event.name == defines.events.on_tick and event.tick % 60 ~= 0 then return false end
        if get_miner() == nil then
          game.players[1].clear_gui_arrow()
          story_jump_to(global.story,'place-burner-mining-drill')
        elseif get_miner_drop_target() == nil then
          game.players[1].clear_gui_arrow()
          story_jump_to(global.story,'place-iron-chest')
        else
          game.players[1].set_gui_arrow({type="position", position=get_miner_drop_target().position})
          if get_miner_drop_target().name == 'stone-furnace' then
            game.players[1].set_goal_description({"goal-collect-in-furnace",
            global.original_count + 2,
            get_miner_drop_target().localised_name},true)
          else
            game.players[1].set_goal_description({"goal-collect-in-container",
            global.original_count + 2,
            get_miner_drop_target().localised_name},true)
          end
        end
      end,
      condition = function (event)
        if event.name == defines.events.on_tick and event.tick % 60 ~= 0 then return false end
        local drop_target = get_miner_drop_target()
        local count = count_items_in_unknown(drop_target)
        return drop_target and drop_target.valid and count >= global.original_count + 2
      end
    },
    {
      name = 'take-items',
      init = function()
        if get_miner_drop_target().name == 'stone-furnace' then
          game.players[1].set_goal_description({"goal-empty-furnace",get_miner_drop_target().localised_name})
        else
          game.players[1].set_goal_description({"goal-empty-container",get_miner_drop_target().localised_name})
        end
      end,
      update = function(event)
        if event.name == defines.events.on_tick then return false end
        if get_miner() == nil then
          game.players[1].clear_gui_arrow()
          story_jump_to(global.story,'place-burner-mining-drill')
        elseif get_miner_drop_target() == nil then
          game.players[1].clear_gui_arrow()
          story_jump_to(global.story,'place-iron-chest')
        else
          game.players[1].set_gui_arrow({type="position", position=get_miner_drop_target().position})
        end
      end,
      condition = function (event)
        if event.name == defines.events.on_tick then return false end
        return get_miner_drop_target() and count_items_in_unknown(get_miner_drop_target()) == 0
      end,
      action = function()
        game.players[1].set_goal_description("")
        game.players[1].clear_gui_arrow()
      end
    },
    generate_pause_to_think_node('go-around'),
    generate_post_pause_to_think_node('go-around'),
    {
      name = 'victory',
      init = function()
        game.set_game_state({game_finished=true, player_won=true, can_continue=true,next_level='level-02'})
        game.tick_paused = true
      end
    },
    {
      name = 'remove-blocking-entity',
      init = function()
        game.players[1].set_goal_description("")
        --game.show_message_dialog({
        --  text={"msg-entity-blocking-miner"},
        --  point_to={type="entity", entity=get_miner_drop_target()}
        --})
        game.players[1].set_gui_arrow({type="position", position=get_miner_drop_target().position})
        game.players[1].set_goal_description({"goal-remove-blocking-entity"})
      end,
      condition = function(event)
        if event.name == defines.events.on_tick then return false end
        return get_miner() == nil or (get_miner() and get_miner_drop_target() == nil) or
        (get_miner() and get_miner_drop_target() and get_miner_drop_target().can_insert(get_miner().mining_target.name))
      end,
      action = function()
        game.players[1].clear_gui_arrow()
        if get_miner() == nil then
          story_jump_to(global.story,'place-burner-mining-drill')
        elseif get_miner_drop_target() == nil then
          story_jump_to(global.story,'wait-to-check-target')
        end
      end
    }
  }
}

story_init_helpers(story_table)

local story_events =
{
  defines.events.on_player_cursor_stack_changed,
  defines.events.on_player_main_inventory_changed,
  defines.events.on_gui_opened,
  defines.events.on_gui_closed,
  defines.events.on_picked_up_item,
  defines.events.on_player_mined_entity,
  defines.events.on_player_mined_item,
  defines.events.on_built_entity,
  defines.events.on_player_rotated_entity,
  defines.events.on_selected_entity_changed,
  defines.events.on_pre_player_crafted_item,
  defines.events.on_tick
}

script.on_init(function()
  global.story = story_init()
end)

script.on_event(story_events, function(event)
  if not game.tick_paused then
    story_update(global.story, event, "level-02")
  end
end)
