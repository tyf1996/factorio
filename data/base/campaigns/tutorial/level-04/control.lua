local util = require("new-hope-util")
require("story")

local researched_technology_list =
{
  ["automation"] = true,
  ["gun-turret"] = true,
  ["military"] = true,
  ["optics"] = true
}

local enabled_technology_list =
{
  ["automation-2"] = true,
  ["automobilism"] = true,
  ["electronics"] = true,
  ["engine"] = true,
  ["fast-inserter"] = true,
  ["heavy-armor"] = true,
  ["logistic-science-pack"] = true,
  ["logistics-2"] = true,
  ["logistics"] = true,
  ["physical-projectile-damage-1"] = true,
  ["steel-axe"] = true,
  ["steel-processing"] = true,
  ["stone-wall"] = true,
  ["weapon-shooting-speed-1"] = true
}

local spawn_position = {-0.5, 44}

script.on_init(function()
  global.story = story_init()
end)

local init = function()

  game.map_settings.enemy_expansion.enabled = false
  game.map_settings.enemy_evolution.enabled = false
  game.map_settings.unit_group.min_group_gathering_time = 60 * 60
  game.map_settings.unit_group.max_group_gathering_time = 120 * 60
  game.map_settings.unit_group.max_unit_group_size = 15
  game.map_settings.pollution.enabled = true
  game.map_settings.pollution.enemy_attack_pollution_consumption_modifier = 8

  game.forces.enemy.evolution_factor = 0

  local force = game.forces.player
  force.reset()
  force.clear_chart()
  force.disable_all_prototypes()
  force.reset_recipes()

  local surface = game.surfaces[1]
  force.set_spawn_position(spawn_position, surface)
  surface.always_day = false
  surface.daytime = 0.4

  util.set_technologies_researched(force, researched_technology_list)
  util.set_technologies_enabled(force, enabled_technology_list)
  force.reset_technology_effects()

  util.verify_techs(force)

  global.delayed_messages = {}
  game.players[1].clear_recipe_notifications()
  game.players[1].add_recipe_notification("lab");
end

local item_list =
{
  ["iron-plate"] = 10,
  ["copper-plate"] = 10,
  ["coal"] = 40,
  ["transport-belt"] = 100,
  ["inserter"] = 20,
  ["small-electric-pole"] = 20,
  ["electric-mining-drill"] = 5,
  ["pistol"] = 1,
  ["firearm-magazine"] = 20,
  ["electronic-circuit"] = 40
}

local on_player_created = function(event)
  local player = game.get_player(event.player_index)
  util.insert_safe(player.character, item_list)
end

local default_delay = 5
local think_with_delay = function(string, seconds)
  return
  {
    condition = story_elapsed_check(seconds or default_delay),
    action = function()
      game.print(util.think_string(string))
    end
  }
end

local car_distance_goal = 200

local update_car_progress = function(gui)
  local progress = gui.progress
  if not progress then
    progress = gui.add{type = "progressbar", name = "progress"}
    progress.style.horizontally_stretchable = true
    progress.parent.style.padding = 0
  end
  progress.value = math.min(1, global.distance_travelled / car_distance_goal)
end

local finish_materials =
{
  ["iron-plate"] = 400,
  ["copper-plate"] = 200,
  ["gun-turret"] = 20,
  ["firearm-magazine"] = 200,
  ["steel-plate"] = 50,
  ["coal"] = 100
}

local get_car_contents = function()
  local cars = game.surfaces[1].find_entities_filtered{name = "car"}
  if not cars[1] then return {} end
  local contents = {}
  for k, car in pairs (cars) do
    for name, count in pairs(car.get_inventory(defines.inventory.car_trunk).get_contents()) do
      contents[name] = (contents[name] or 0) + count
    end
    for name, count in pairs(car.get_inventory(defines.inventory.car_ammo).get_contents()) do
      contents[name] = (contents[name] or 0) + count
    end
  end
  return contents
end

local update_materials_gui = function(gui)
  local contents = get_car_contents()
  local table = gui.holding_table
  if not table then
    table = gui.add{type = "table", column_count = 3, style = "bordered_table", name = "holding_table"}
  end

  local items = game.item_prototypes

  for item, count in pairs(finish_materials) do
    if items[item] then
      local count_label = table[item]
      if not count_label then
        local sprite = table.add{type = "sprite", sprite = "item/"..item}
        sprite.style.width = 32
        sprite.style.height = 32
        local item_label = table.add{type = "label", caption = items[item].localised_name, style = "bold_label"}
        item_label.style.horizontally_stretchable = false
        count_label = table.add{type = "label", name = item}
      end
      local current_count = contents[item] or 0
      count_label.caption = current_count.."/"..count
      if current_count >= count then
        count_label.style = "bold_green_label"
      else
        count_label.style = "label"
      end
    end
  end

end

local car_content_check = function()
  local car_contents = get_car_contents()
  for item, count in pairs (finish_materials) do
    if not car_contents[item] then return end
    if car_contents[item] < count then return end
  end
  return true
end

local story_table =
{
  {
    {
      init = function()
        init()
      end
    },
    {
      init = function()
        global.radar = game.surfaces[1].find_entities_filtered{name = "radar", limit = 1}[1]
        if global.radar then
          for k, player in pairs (game.players) do
            player.set_controller
            {
              type = defines.controllers.cutscene,
              waypoints =
              {
                {
                  target = global.radar,
                  transition_time = 300,
                  time_to_wait = 100,
                  zoom = 2
                },
                {
                  target = player.character,
                  transition_time = 100,
                  time_to_wait = 0,
                  zoom = 1
                }
              },
              start_position = global.radar.position,
              start_zoom = 4
            }
          end
        end
      end,
      condition = story_elapsed_check(6)
    },
    {
      action = function()
        story_show_message_dialog{text = {"msg-sector-scan-completed"}}
        story_show_message_dialog{text = {"msg-detected-distress-beacon"}}
      end
    },
    think_with_delay({"think-track-distress-beacon-1"}, 5),
    think_with_delay({"think-track-distress-beacon-2"}, 8),
    think_with_delay({"think-track-distress-beacon-3"}, 7),
    think_with_delay({"think-track-distress-beacon-4"}, 9),
    {
      condition = story_elapsed_check(5)
    },
    {
      init = function()
        set_goal({"goal-build-lab"})
      end,
      condition = function(event)
        if event.tick % 60 ~= 0 then return end

        if game.forces.player.get_entity_count("lab") == 0 then return end

        local lab = game.surfaces[1].find_entities_filtered{name = "lab", limit = 1}[1]
        if not lab then return end

        lab.energy = 1 -- avoid the not enough energy icon in this frame
        story_show_message_dialog{text = {"msg-research-labs-1"}, point_to = {type = "entity", entity = lab}}
        story_show_message_dialog{text = {"msg-research-labs-2"}, point_to = {type = "entity", entity = lab}}
        return true
      end
    },
    {
      init = function()
        set_goal()
      end,
      condition = story_elapsed_check(3)
    },
    {
      init = function()
        set_goal({"goal-research-walls"})
      end,
      condition = function() return game.forces.player.technologies["stone-wall"].researched end,
      action = function()
        set_goal()
      end
    },
    think_with_delay({"think-research-car-1"}, 8),
    think_with_delay({"think-research-car-2"}, 8),
    think_with_delay({"think-research-car-3"}, 8),
    {
      condition = story_elapsed_check(5)
    },
    {
      init = function()
        set_goal({"goal-research-automobilism"})
      end,
      condition = function()
        return game.forces.player.technologies["automobilism"].researched
      end
    },
    {
      init = function()
        set_goal({"goal-build-car"})
      end,
      condition = function(event)
        if event.tick % 60 ~= 0 then return end
        local car_count = game.surfaces[1].count_entities_filtered{name = "car", limit = 1}
        return car_count > 0
      end,
      action = function()
        set_goal()
      end
    },
    {
      condition = story_elapsed_check(5)
    },
    {
      init = function()
        set_goal({"goal-drive-car"})
        global.distance_travelled = 0
        set_info({custom_function = update_car_progress})
      end,
      condition = function(event)
        if event.tick % 60 ~= 0 then return end
        local car = game.surfaces[1].find_entities_filtered{name = "car", limit = 1}[1]
        if not car then return end
        if car.energy == 0 then return end
        global.car = car
        global.last_car_position = car.position
        return true
      end
    },
    {
      condition = function(event)
        if not global.car.valid then return true end
        if global.distance_travelled >= car_distance_goal then return true end
      end,
      update = function(event)
        if not global.car.valid then return end
        local new_position = global.car.position
        local distance = util.distance(new_position, global.last_car_position)
        global.distance_travelled = global.distance_travelled + distance
        global.last_car_position = new_position
        set_info{custom_function = update_car_progress}
      end,
      action = function()
        set_goal()
        set_info()
      end
    },
    think_with_delay({"think-stop-messing-around-1"}, 5),
    think_with_delay({"think-stop-messing-around-2"}, 8),
    {
      condition = story_elapsed_check(5)
    },
    {
      init = function()
        set_goal({"goal-prepare-materials"})
        set_info({
          custom_function = update_materials_gui
        })
      end,
      update = function(event)
        if event.tick % 60 ~= 0 then return end
        set_info({
          custom_function = update_materials_gui
        })
      end,
      condition = function(event)
        if event.tick % 60 ~= 0 then return end
        return car_content_check()
      end,
      action = function()
        set_goal()
        set_info()
      end
    },
    think_with_delay({"think-lets-go"}, 5),
    {
      condition = story_elapsed_check(5),
      action = function()
        game.set_game_state({game_finished=true, player_won=true, can_continue=false, next_level = "level-05"})
      end
    }
  }
}

local check_automate_science_packs_advice = function(event)
  if not global.science_packs_crafted then
    global.science_packs_crafted = 0
  end
  if event.item_stack.name == "automation-science-pack" then
    global.science_packs_crafted = global.science_packs_crafted + event.item_stack.count
  end
  if global.science_packs_crafted > 15 and global.automate_science_packs_advice == nil then
    game.print(util.think_string({"think-automate-science-pack-crafting"}))
    global.automate_science_packs_advice = true
  end
end

local group_notice_count = 3
local go_kill_group_count = 8
local bump_biter_difficulty_group_count = 12
local on_unit_group_finished_gathering = function(event)

  --Assuming they are gathering due to pollution.
  global.gathered_group_count = (global.gathered_group_count or 0) + 1

  if not global.showed_pollution_tip and global.gathered_group_count >= group_notice_count then
    global.showed_pollution_tip = true
    global.delayed_messages[game.tick + (20 * 60)] = util.think_string({"think-pollution-tip"})
  end

  if not global.showed_murder_tip and global.gathered_group_count >= go_kill_group_count then
    global.showed_murder_tip = true
    global.delayed_messages[game.tick + (20 * 60)] = util.think_string({"think-kill-bases-tip"})
  end

  if not global.bumped_biter_difficulty and global.gathered_group_count >= bump_biter_difficulty_group_count then
    game.map_settings.pollution.enemy_attack_pollution_consumption_modifier = 1
  end

end

local minimum_delay_between_messages = 60 * 10
local check_delayed_message = function(event)

  if event.tick < ((global.last_message_tick or 0) + minimum_delay_between_messages) then
    --Just prevent the rare case of spamming unrelated things at the same time.
    return
  end

  for tick, message in pairs (global.delayed_messages) do
    if event.tick >= tick then
      game.print(message)
      global.delayed_messages[tick] = nil
      global.last_message_tick = event.tick
      return
    end
  end
end

local check_low_power = function()
  if global.showed_power_tip then return end
  local test_entities = game.surfaces[1].find_entities_filtered{type = {"mining-drill", "inserter", "assembling-machine", "radar", "lab", "lamp"}, force = "player"}
  for k, entity in pairs (test_entities) do
    if entity.is_connected_to_electric_network() then
      local buffer_size = entity.electric_buffer_size
      if buffer_size then
        if entity.energy < (buffer_size * 0.6) then
          global.showed_power_tip = true
          global.delayed_messages[game.tick + (5 * 60)] = util.think_string({"think-low-power"})
        end
      end
    end
  end
end

story_init_helpers(story_table)

local story_events =
{
  defines.events.on_tick
}

script.on_event(story_events, function(event)
  story_update(global.story, event, "level-05")
end)

script.on_event(defines.events.on_player_crafted_item, check_automate_science_packs_advice)

script.on_event(defines.events.on_player_created, on_player_created)

script.on_event(defines.events.on_unit_group_finished_gathering, on_unit_group_finished_gathering)

script.on_nth_tick(103, check_delayed_message)

script.on_nth_tick(269, check_low_power)
