local util = require("new-hope-util")
local final_screen = require("final_screen")
require("story")

local car_supplies =
{
  ["piercing-rounds-magazine"] =  200,
  ["steel-plate"] = 200,
  ["iron-gear-wheel"] = 250,
  ["electronic-circuit"] = 500,
  ["solar-panel"] = 200
}

local get_car_contents = function()
  local cars = global.cars
  local contents = {}
  for k, car in pairs (cars) do
    if not car.valid then
      cars[k] = nil
    else
      for name, count in pairs(car.get_inventory(defines.inventory.car_trunk).get_contents()) do
        contents[name] = (contents[name] or 0) + count
      end
      for name, count in pairs(car.get_inventory(defines.inventory.car_ammo).get_contents()) do
        contents[name] = (contents[name] or 0) + count
      end
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

  for item, count in pairs(car_supplies) do
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
  for item, count in pairs (car_supplies) do
    if not car_contents[item] then return end
    if car_contents[item] < count then return end
  end
  return true
end

local researched_technology_list =
{
  ["automation-2"] = true,
  ["automation"] = true,
  ["automobilism"] = true,
  ["electronics"] = true,
  ["engine"] = true,
  ["fast-inserter"] = true,
  ["heavy-armor"] = true,
  ["logistic-science-pack"] = true,
  ["logistics-2"] = true,
  ["logistics"] = true,
  ["military"] = true,
  ["optics"] = true,
  ["physical-projectile-damage-1"] = true,
  ["steel-axe"] = true,
  ["steel-processing"] = true,
  ["stone-wall"] = true,
  ["gun-turret"] = true,
  ["weapon-shooting-speed-1"] = true
}

local enabled_technology_list =
{
  ["advanced-material-processing"] = true,
  ["automated-rail-transportation"] = true,
  ["concrete"] = true,
  ["electronics"] = true,
  ["electric-energy-distribution-1"] = true,
  ["engine"] = true,
  ["gate"] = true,
  ["landfill"] = true,
  ["military-2"] = true,
  ["physical-projectile-damage-2"] = true,
  ["rail-signals"] = true,
  ["railway"] = true,
  ["research-speed-1"] = true,
  ["research-speed-2"] = true,
  ["solar-energy"] = true,
  ["stronger-explosives-1"] = true,
  ["toolbelt"] = true,
  ["weapon-shooting-speed-2"] = true
}

local spawn_position = {-23, 5}

script.on_init(function()
  global.story = story_init()
  game.forces.player.set_spawn_position(spawn_position, 1)
end)

local set_remnants_permament = function()
  for k, remnant in pairs (game.surfaces[1].find_entities_filtered{type = {"corpse", "rail-remnants"}}) do
    if remnant.name:find("remnant") then
      remnant.corpse_expires = false
    end
  end
end

local chart_areas = function()
  local surface = game.surfaces[1]
  local force = game.forces.player
  for k, entity in pairs (surface.find_entities_filtered{force = force, area = {{-500, -250},{500, 250}}}) do
    local position = entity.position
    force.chart(surface, {{position.x - 16, position.y - 16}, {position.x + 16, position.y + 16}})
  end
  force.chart(surface, {{spawn_position[1] - 200, spawn_position[2] - 200}, {spawn_position[1] + 200, spawn_position[2] + 200}})
end

local init = function()

  game.map_settings.enemy_expansion.enabled = false
  game.map_settings.enemy_evolution.enabled = false
  game.forces.enemy.evolution_factor = 0
  game.surfaces[1].daytime = 0.8

  local force = game.forces.player
  force.reset_recipes()
  force.disable_all_prototypes()

  util.set_technologies_enabled(force, enabled_technology_list)
  util.set_technologies_researched(force, researched_technology_list)

  force.reset_technology_effects()
  force.clear_chart()
  force.maximum_following_robot_count = 10

  util.verify_techs(force)

  global.cars = global.cars or {}
  game.players[1].clear_recipe_notifications()
end

local player_item_list =
{
  ["assembling-machine-1"] = 10,
  ["coal"] = 40,
  ["copper-plate"] = 100,
  ["electric-mining-drill"] = 5,
  ["electronic-circuit"] = 100,
  ["submachine-gun"] = 1,
  ["firearm-magazine"] = 40,
  ["shotgun"] = 1,
  ["shotgun-shell"] = 20,
  ["heavy-armor"] = 1,
  ["inserter"] = 20,
  ["iron-gear-wheel"] = 50,
  ["iron-plate"] = 200,
  ["lab"] = 5,
  ["long-handed-inserter"] = 10,
  ["pipe"] = 40,
  ["small-electric-pole"] = 20,
  ["small-lamp"] = 20,
  ["stone"] = 200,
  ["transport-belt"] = 50,
  ["wood"] = 50
}

local car_item_list =
{
  ["iron-plate"] = 400,
  ["copper-plate"] = 200,
  ["gun-turret"] = 20,
  ["firearm-magazine"] = 200,
  ["steel-plate"] = 50,
  ["coal"] = 100
}

local train_stop_locale =
{
  dropoff_stop = {"iron-processing-stop"},
  mine_stop = {"iron-mine-stop"}
}

local translate_stops = function(player)
  player.request_translation(train_stop_locale.dropoff_stop)
  player.request_translation(train_stop_locale.mine_stop)
end

local on_player_created = function(event)
  local player = game.get_player(event.player_index)
  util.insert_safe(player.character, player_item_list)
  if event.player_index == 1 then
    translate_stops(player)
  end
end

local on_string_translated = function(event)
  if not event.translated then return end
  if event.localised_string[1] == train_stop_locale.dropoff_stop[1] then
    local train_stop = game.surfaces[1].find_entity("train-stop", {-29, -7})
    if train_stop then
      train_stop.backer_name = event.result
    end
    return
  end
  if event.localised_string[1] == train_stop_locale.mine_stop[1] then
    local train_stop = game.surfaces[1].find_entity("train-stop", {-423, -145})
    if train_stop then
      train_stop.backer_name = event.result
    end
    return
  end
end

local get_angle = function(position_1, position_2)
  local d_x = (position_2[1] or position_2.x) - (position_1[1] or position_1.x)
  local d_y = (position_2[2] or position_2.y) - (position_1[2] or position_1.y)
  return math.atan2(d_y, d_x)
end

local get_orientation = function(source_position, target_position)

  -- Angle in rads
  local angle = get_angle(target_position, source_position)

  -- Convert to orientation
  local orientation =  (angle / (2 * math.pi)) - 0.25
  if orientation < 0 then orientation = orientation + 1 end
  if orientation > 1 then orientation = orientation - 1 end

  return orientation

end

--local car_waypoints =
--{
--  {50, 100},
--  {45, 55},
--  {15, 30},
--  {-35, 20},
--  {-30, 5},
--}

local car_waypoints =
{
  {-200, 20},
  {-165, -6},
  {-122, -5},
  {-95, -5},
  {-88, -0},
  {-82, 0},
  {-50, 3},
  {-25, 5}
}

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

local update_car_driving = function()

  local car = global.car
  local waypoint = global.car_waypoints[1]

  if not waypoint then
    car.speed = car.speed * 0.95
    car.riding_state =
    {
      acceleration = defines.riding.acceleration.braking,
      direction = defines.riding.direction.straight
    }
    return
  end

  local distance = util.distance(car.position, {x = waypoint[1], y = waypoint[2]})
  if distance < 2 then
    table.remove(global.car_waypoints, 1)
    return
  end

  local direction

  local target_orientation = get_orientation(car.position, waypoint)
  if math.abs(car.orientation - target_orientation) <= 1/128 then
    car.orientation = target_orientation
    direction = defines.riding.direction.straight
  else

    local change = car.orientation - target_orientation
    if change > 0.5 then
      change = -1 + change
    end
    if change < -0.5 then
      change = 1 + change
    end

    if change > 0 then
      --direction = defines.riding.direction.left
      car.orientation = car.orientation - (0.08 * change)
    else
      car.orientation = car.orientation - (0.08 * change)
      --direction = defines.riding.direction.right
    end

  end

  car.riding_state =
  {
    acceleration = defines.riding.acceleration.accelerating,
    direction = defines.riding.direction.straight
  }
end

story_table =
{
  {
    {
      init = function()
        init()
      end
    },
    {
      init = function()
        global.car_waypoints = car_waypoints
        for k, waypoint in pairs (car_waypoints) do
          -- Debug visualisation to see car waypoints.
          --game.surfaces[1].set_tiles{{name = "concrete", position = waypoint}}
        end
        for k, player in pairs (game.players) do
          if player.character then player.character.destroy() end
        end
        local start_position = global.car_waypoints[1]
        table.remove(global.car_waypoints, 1)
        local driving_car = game.surfaces[1].create_entity{name = "car", position = start_position, force = "player"}
        global.cars =
        {
          [driving_car.unit_number] = driving_car
        }
        local dude = game.surfaces[1].create_entity{name = "character", force = "player", position = start_position}
        driving_car.set_passenger(dude)
        global.dude = dude
        global.car = driving_car
        global.car.orientation = get_orientation(global.car.position, global.car_waypoints[1])
        global.car.speed = 0.3
        util.insert_safe(global.car, car_item_list)
        global.car.color = { r = 0.869, g = 0.5  , b = 0.130, a = 0.5 }
        for k, player in pairs (game.players) do
          player.set_controller
          {
            type = defines.controllers.cutscene,
            waypoints =
            {
              {
                target = global.car,
                transition_time = 0,
                time_to_wait = 1000,
                zoom = 1.5
              }
            },
            start_position = global.car.position,
            start_zoom = 1.5
          }
        end
      end,
      update = update_car_driving,
      condition = function(event)
        if event.tick % 60 ~= 0 then return end
        return global.car.speed == 0
      end
    },
    {
      init = function()
        chart_areas()
        if global.dude and global.dude.valid then
          global.dude.destroy()
        end
        for k, player in pairs (game.players) do
          if player.controller_type == defines.controllers.cutscene then
            player.exit_cutscene()
          end
          if player.character then player.character.destroy() end
          player.teleport({x = global.car.position.x + 1, y = global.car.position.y - 1})
          player.create_character()
          util.insert_safe(player, player_item_list)
          player.zoom = 0.75
          player.set_controller
          {
            type = defines.controllers.cutscene,
            waypoints =
            {
              {
                target = player.character,
                transition_time = 150,
                time_to_wait = 30,
                zoom = 0.75
              }
            },
            start_position = global.car.position,
            start_zoom = 1.5
          }
        end
      end,
      condition = story_elapsed_check(3)
    },
    think_with_delay({"think-arrived-1"}, 2),
    think_with_delay({"think-arrived-2"}, 6),
    think_with_delay({"think-arrived-3"}, 7),
    think_with_delay({"think-arrived-4"}, 8),
    think_with_delay({"think-arrived-5"}, 7),
    {
      condition = story_elapsed_check(2)
    },
    {
      init = function()
        set_goal({"goal-repair-base-and-research-railway"})
      end,
      condition = function(event)
        if event.tick % 60 ~= 0 then return end
        local force = game.forces.player
        return force.technologies["automated-rail-transportation"].researched == true
      end,
      action = function()
        set_goal("")
      end
    },
    think_with_delay({"think-recover-railway"}),
    {
      condition = story_elapsed_check(6)
    },
    {
      init = function(event)
        set_goal({"goal-set-up-train"})
      end,
      condition = function(event)
        if event.name ~= defines.events.on_train_changed_state then return end
        local train = event.train
        if not (train and train.valid) then return end
        if train.manual_mode then return end
        if train.state ~= defines.train_state.wait_station then return end
        if #train.cargo_wagons == 0 then return end
        local schedule = train.schedule
        if not schedule then return end
        return #schedule.records >= 2
      end,
      action = function(event)
        set_goal()
      end
    },
    think_with_delay({"think-gather-supplies-1"}, 5),
    think_with_delay({"think-gather-supplies-2"}, 6),
    think_with_delay({"think-gather-supplies-3"}, 7),
    think_with_delay({"think-gather-supplies-4"}, 7),
    {
      condition = story_elapsed_check(5)
    },
    {
      init = function(event)
        set_goal({"goal-get-supplies"})
        set_info({custom_function = update_materials_gui})
      end,
      condition = function(event)
        if event.tick % 60 ~= 0 then return end
        set_info({custom_function = update_materials_gui})
        return car_content_check()
      end,
      action = function()
        set_goal("")
        set_info()
      end
    },
    think_with_delay({"think-ready-to-go"}, 5),
    {
      condition = story_elapsed_check(5)
    },
    {
      init = function()
        if not game.is_multiplayer() then
          game.tick_paused = true
        end
        for k, player in pairs (game.connected_players) do
          final_screen.create(player)
        end
        game.play_sound({path = "utility/game_won"})
      end,
      condition = function()
        return false
      end
    }
  }
}

skippity = function()
  for k, player in pairs (game.connected_players) do
    final_screen.create(player)
  end
end

story_init_helpers(story_table)

local story_events =
{
  defines.events.on_tick,
  defines.events.on_train_changed_state
}

local build_events =
{
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive
}

local on_built_entity = function(event)

  local entity = event.entity or event.created_entity
  if not (entity and entity.valid) then return end

  if entity.name == "car" then
    global.cars[entity.unit_number] = entity
  end

end

local on_player_driving_changed_state = function(event)
  -- If they find the car in the ruin, only consider it for the objectives if they get in.
  local car = event.entity
  if not (car and car.valid) then return end

  if car.name ~= "car" then return end

  global.cars[car.unit_number] = car

end

script.on_event(story_events, function(event)
  story_update(global.story, event)
end)

script.on_event(defines.events.on_player_created, on_player_created)

script.on_event(build_events, on_built_entity)
script.on_event(defines.events.on_player_driving_changed_state, on_player_driving_changed_state)
script.on_event(defines.events.on_gui_click, final_screen.on_gui_click)
script.on_event(defines.events.on_string_translated, on_string_translated)
