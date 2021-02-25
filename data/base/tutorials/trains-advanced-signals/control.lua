require "story"
require "advanced-signals"

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
  game.permissions.get_group(0).set_allows_action(defines.input_action.open_logistic_gui, false)
  game.permissions.get_group(0).set_allows_action(defines.input_action.open_technology_gui, false)
  player.force.disable_all_prototypes()
end

local clear_vis = function()
  --clear all render render_ids
  for _, id in pairs(global.render_ids) do
    rendering.destroy(id)
  end
end

local add_train_label = function(backer_tag,label_text,color)
  local loco = nil
  for _, train in pairs(surface().find_entities_filtered({name='locomotive'})) do
    if train.backer_name == backer_tag then
      loco = train
    end
  end
  if loco then
    loco.color = {r=1,g=0.6,b=0,a=0.5}
    game.print('adding label')
    local label_id = rendering.draw_text({
      surface = loco.surface,
      target = loco,
      color = {1,1,1},
      text = "red train",
      offset = {0,-2}
    })
    table.insert(global.render_ids,label_id)
  end
end

local add_train_labels = function(trains)
  for _, train in pairs(trains) do
    local ent = surface().find_entities_filtered({name='locomotive',position=train.position})
    if ent then
      game.print('adding label')
      local label_id = rendering.draw_text({
        surface = surface(),
        target = ent,
        color = {1,1,1},
        text = "red train",
        offset = {0,-2}
      })
      table.insert(global.render_ids,label_id)
    end
  end
end

local add_labels = function(label_data)
  for _, data in pairs(label_data) do
    local matching_ents = surface().find_entities_filtered({name=data.entity,position=data.position})
    if #matching_ents>0 then
      for _, ent in pairs(matching_ents) do
        local label_id = rendering.draw_text({
          surface = surface(),
          target = ent,
          color = {1,1,1},
          text = {"label."..data.locale},
          target_offset = {0,1},
          alignment = 'center'
        })
        table.insert(global.render_ids,label_id)
      end
    end
  end
end

story_table =
{
  {
    {
      init = function()
        global.render_ids = {}
        for k, entity in pairs (surface().find_entities()) do
          if entity.name == "locomotive" then
            entity.insert"coal"
          end
          entity.minable = false
          entity.operable = false
          entity.rotatable = false
        end
        player().character.destroy()
        player().set_quick_bar_slot(1,'rail-chain-signal')
        player().set_quick_bar_slot(2,'rail-signal')
        player().game_view_settings = {show_rail_block_visualisation = true}
      end
    },
    {
      init = function()
        clear_vis()
        set_goal("", false)
        set_info({text = {"chain-green"}})
        set_info({custom_function = add_run_trains_button, append = true})
        find_gui_recursive(player().gui, "reset_all").destroy()
        set_continue_button_style(function (button)
          if button.valid then
            button.enabled = true
          end
        end)
        clear_surface()
        global.this_puzzle = setup.chain_green.entities
        global.this_puzzle_param = nil
        global.this_puzzle_labels = {}
        global.this_puzzle_trains = {}
        for k, entity in pairs (global.this_puzzle) do
          entity.minable = false
          entity.operable = false
          if entity.name == "locomotive" then
            if entity.schedule then
              entity.manual_mode = true
            end
            table.insert(global.this_puzzle_trains, entity)
          end
          if entity.label then
            print("found ent with label "..entity.name)
             table.insert(global.this_puzzle_labels,{
               name = entity.name,
               position = entity.position,
               locale = entity.label
              })
          end
        end
        recreate_entities(global.this_puzzle)
        loop_trains(0)
        add_labels(global.this_puzzle_labels)
      end,
      condition = function()
        return global.continue
      end
    },
    {
      init = function()
        set_goal("", false)
        set_info({text = {"chain-blue-go"}})
        set_info({custom_function = add_run_trains_button, append = true})
        find_gui_recursive(player().gui, "reset_all").destroy()
        set_continue_button_style(function (button)
          if button.valid then
            button.enabled = true
          end
        end)
        clear_surface()
        global.this_puzzle = setup.chain_blue_go.entities
        global.this_puzzle_param = nil
        global.this_puzzle_trains = {}
        for k, entity in pairs (global.this_puzzle) do
          entity.minable = false
          entity.operable = false
          if entity.name == "locomotive" then
            if entity.schedule then
              entity.manual_mode = true
            end
            table.insert(global.this_puzzle_trains, entity)
          end
        end
        recreate_entities(global.this_puzzle)
        loop_trains(0)
      end,
      condition = function()
        return global.continue
      end
    },
    {
      init = function()
        set_goal("", false)
        set_info({text = {"chain-blue-stop"}})
        set_info({custom_function = add_run_trains_button, append = true})
        find_gui_recursive(player().gui, "reset_all").destroy()
        set_continue_button_style(function (button)
          if button.valid then
            button.enabled = true
          end
        end)
        clear_surface()
        global.this_puzzle = setup.chain_blue_stop.entities
        global.this_puzzle_param = nil
        global.this_puzzle_trains = {}
        for k, entity in pairs (global.this_puzzle) do
          entity.minable = false
          entity.operable = false
          if entity.name == "locomotive" then
            if entity.schedule then
              entity.manual_mode = true
            end
            table.insert(global.this_puzzle_trains, entity)
          end
        end
        recreate_entities(global.this_puzzle)
        loop_trains(0)
      end,
      condition = function()
        return global.continue
      end
    },
    {
      init = function()
        set_goal("", false)
        set_info({text = {"chain-red"}})
        set_info({custom_function = add_run_trains_button, append = true})
        find_gui_recursive(player().gui, "reset_all").destroy()
        set_continue_button_style(function (button)
          if button.valid then
            button.enabled = true
          end
        end)
        clear_surface()
        global.this_puzzle = setup.chain_red.entities
        global.this_puzzle_param = nil
        global.this_puzzle_trains = {}
        for k, entity in pairs (global.this_puzzle) do
          entity.minable = false
          entity.operable = false
          if entity.name == "locomotive" then
            if entity.schedule then
              entity.manual_mode = true
            end
            table.insert(global.this_puzzle_trains, entity)
          end
        end
        recreate_entities(global.this_puzzle)
        loop_trains(0)
      end,
      condition = function()
        return global.continue
      end
    },
    {
      init = function()
        clear_surface()
        set_goal("", false)
        set_info({text = {"deadlock-1"}})
        set_info({text = {"deadlock-2"}, append = true})
        set_info({custom_function = add_button, append = true})
        global.this_puzzle_trains = {}
        for k, entity in pairs (setup.deadlock_1.entities) do
          if entity.name == "locomotive" or entity.name == "fluid-wagon" then
            table.insert(global.this_puzzle_trains, entity)
          elseif entity.name == "rail-signal" then
            entity.minable = true
          end
        end
        global.this_puzzle = setup.deadlock_1.entities
        global.this_puzzle_param = setup.deadlock_1.param
        recreate_entities(global.this_puzzle, global.this_puzzle_param)
        loop_trains(9*60)
      end,
      condition = function()
        return global.continue
      end
    },
    {
      init = function()
        clear_surface()
        global.this_puzzle = setup.deadlock_1.entities
        global.this_puzzle_param = setup.deadlock_1.param
        global.this_puzzle_trains = {}
        global.this_puzzle_labels = {}
        clear_vis()
        for k, entity in pairs (global.this_puzzle) do
          if entity.name == "locomotive" or entity.name == "fluid-wagon" then
            table.insert(global.this_puzzle_trains, entity)
          elseif entity.name == "rail-signal" then
            entity.minable = true
          end
        end
        for k, entity in pairs (recreate_entities(global.this_puzzle, global.this_puzzle_param)) do
          if entity.name == "rail-signal" and
            (
              (
                entity.position.x == -4.5 and
                entity.position.y == 2.5
              )
              or
              (
                entity.position.x == -2.5 and
                entity.position.y == -2.5
              )
            )
          then
            entity.minable = true
            local X = entity.position.x
            local Y = entity.position.y
            local D = entity.direction
            entity.destroy()
            surface().create_entity{name = "rail-chain-signal", position = {X,Y}, direction = D}
            table.insert(global.this_puzzle_labels,{
              name = 'rail-chain-signal',
              position = {X,Y},
              locale = 'rail-chain-signal'
            })
          end
        end
        add_labels(global.this_puzzle_labels)
        set_goal()
        set_info({text = {"chain-signal-1"}})
        set_info({text = {"chain-signal-2"}, append = true})
        set_info({custom_function = add_button, append = true})
        loop_trains(8*60)
      end,
      condition = function()
        return global.continue
      end
    },
    {
      init = function()
        clear_surface()
        global.required_chain_signals = 4
        global.required_rail_signals = 0
        set_goal({"fix-intersection"})
        set_info({custom_function = add_run_trains_button})
        player().game_view_settings = {show_rail_block_visualisation = false}
        global.this_puzzle_trains = {}
        for k, entity in pairs (setup.deadlock_2.entities) do
          if entity.name == "locomotive" or entity.name == "fluid-wagon" then
            entity.manual_mode = true
            table.insert(global.this_puzzle_trains, entity)
          elseif entity.name == "rail-signal" then
            entity.minable = true
          end
        end
        global.this_puzzle = setup.deadlock_2.entities
        global.this_puzzle_param = setup.deadlock_2.param
        recreate_entities(global.this_puzzle, global.this_puzzle_param)
      end,
      condition = function()
        return puzzle_condition_red()
      end
    },
    {
      init = function()
        clear_surface()
        global.required_chain_signals = 8
        set_goal({"fix-intersection"})
        set_info({custom_function = add_run_trains_button})
        global.this_puzzle_trains = {}
        for k, entity in pairs (setup.intersection_1.entities) do
          if entity.name == "locomotive" or entity.name == "fluid-wagon" then
            entity.manual_mode = true
            table.insert(global.this_puzzle_trains, entity)
          elseif entity.name == "rail-signal" then
            entity.minable = true
          end
        end
        global.this_puzzle = setup.intersection_1.entities
        global.this_puzzle_param = setup.intersection_1.param
        recreate_entities(global.this_puzzle, global.this_puzzle_param)
      end,
      condition = function()
        return puzzle_condition_red()
      end
    },
    {
      init = function()
        clear_surface()
        global.required_chain_signals = 4
        set_goal({"fix-intersection"})
        set_info({custom_function = add_run_trains_button})
        global.this_puzzle_trains = {}
        for k, entity in pairs (setup.intersection_2.entities) do
          if entity.name == "locomotive" or entity.name == "fluid-wagon" then
            entity.manual_mode = true
            table.insert(global.this_puzzle_trains, entity)
          elseif entity.name == "rail-signal" then
            entity.minable = true
          end
        end
        global.this_puzzle = setup.intersection_2.entities
        global.this_puzzle_param = setup.intersection_2.param
        recreate_entities(global.this_puzzle, global.this_puzzle_param)
      end,
      condition = function()
        return puzzle_condition_red()
      end
    },
    {
      init = function()
        clear_surface()
        global.required_chain_signals = 12
        global.required_rail_signals = 12
        set_goal({"fix-intersection-2"})
        set_info({custom_function = add_run_trains_button})
        global.this_puzzle_trains = {}
        global.this_puzzle = setup.intersection_3.entities
        global.this_puzzle_param = setup.intersection_3.param
        for k, entity in pairs (global.this_puzzle) do
          if entity.name == "locomotive" or entity.name == "fluid-wagon" then
            entity.manual_mode = true
            table.insert(global.this_puzzle_trains, entity)
          elseif entity.name == "rail-signal" then
            entity.minable = true
          end
        end
        recreate_entities(global.this_puzzle, global.this_puzzle_param)
      end,
      condition = function()
        return puzzle_condition_all()
      end
    },
    {
      init = function()
        player().set_controller{type = defines.controllers.god}
        for k, entity in pairs (surface().find_entities()) do
          entity.minable = true
          entity.operable = true
          entity.rotatable = true
        end
        player().insert({name='rail',count=1000})
        player().insert({name='rail-signal',count=30})
        player().insert({name='rail-chain-signal',count=30})
        player().insert({name='train-stop',count=10})
        player().insert({name='locomotive',count=3})
        player().insert({name='cargo-wagon',count=3})
        player().insert({name='coal',count=100})
        player().set_quick_bar_slot(2,'rail-signal')
        player().set_quick_bar_slot(3,'rail')
        player().set_quick_bar_slot(4,'train-stop')
        player().set_quick_bar_slot(5,'locomotive')
        player().set_quick_bar_slot(6,'cargo-wagon')
        set_info{text = {"finish-info"}}
        set_info{custom_function = function(flow) add_button(flow).caption = {"finish"} end, append = true}
        set_goal(nil, false)
      end,
      condition = function()
        return global.continue
      end
    }
  }
}

story_init_helpers(story_table)

script.on_init(function()
  surface().always_day = true
  game.forces.player.manual_mining_speed_modifier = 4
  game.forces.player.disable_all_prototypes()
  global.story = story_init()
end)

script.on_event(defines.events.on_tick, function(event)
  story_update(global.story, event, "")
  limit_camera({0,0}, 20)
  loop_trains()
end)

script.on_event(defines.events.on_gui_click, function (event)
  story_update(global.story, event, "")
end)

script.on_event(defines.events.on_player_created, on_player_created)

story_gui_click = function(event)
  local element = event.element
  if not element.valid then return end
  local player = game.players[event.player_index]
  local name = element.name

  if name == "start_trains" then
    if not element.enabled then return end
    for k, train in pairs (surface().find_entities_filtered{name = "locomotive"}) do
      if train.train.schedule then
        train.train.manual_mode = false
      end
    end
    element.enabled = false
    global.save_inventory = game.create_inventory(100)
    for name, count in pairs (player.get_main_inventory().get_contents()) do
      global.save_inventory.insert({name = name, count = count})
    end
    player.clear_items_inside()

    player.set_controller{type = defines.controllers.ghost}
    return
  end

  if name == "reset_trains" then
    for k, train in pairs (surface().find_entities_filtered{name = "locomotive"}) do
      train.destroy()
    end
    for k, train in pairs (surface().find_entities_filtered{name = "fluid-wagon"}) do
      train.destroy()
    end
    recreate_entities(global.this_puzzle_trains, global.this_puzzle_param)
    for k, child in pairs (element.parent.children) do
      if child.name ~= "story_continue_button" then
        child.enabled = true
      end
    end
    if player.controller_type ~= defines.controllers.god then
      player.set_controller{type = defines.controllers.god}
      if global.save_inventory then
        for name, count in pairs (global.save_inventory.get_contents()) do
          player.insert({name = name, count = count})
        end
        global.save_inventory.destroy()
        global.save_inventory = nil
      end
    end
    return
  end

  if name == "reset_all" then
    clear_surface()
    recreate_entities(global.this_puzzle, global.this_puzzle_param)
    for k, child in pairs (element.parent.children) do
      if child.name ~= "story_continue_button" then
        child.enabled = true
      end
    end

    if player.controller_type ~= defines.controllers.god then
      player.set_controller{type = defines.controllers.god}
    end

    player.clear_items_inside()
    if global.required_chain_signals > 0 then player.insert{name = "rail-chain-signal", count = global.required_chain_signals} end
    if global.required_rail_signals > 0 then player.insert{name = "rail-signal", count = global.required_rail_signals} end
    return
  end

end

function clear_surface()
  local entities = surface().find_entities()
  for k, entity in pairs (entities) do
    if entity.valid and entity.name ~= "character" then
      entity.destroy()
    end
  end
  for k, entity in pairs (surface().find_entities()) do
    if entity.valid and entity.name ~= "character" then
      entity.destroy()
    end
  end
end

function add_run_trains_button(gui)
  gui.add{type = "line", direction = "horizontal"}
  local flow = gui.add{type = "table", column_count = 2}
  flow.style.horizontal_spacing = 2
  flow.style.vertical_spacing = 2
  flow.style.horizontally_stretchable = true
  local button = flow.add{type = "button", name = "start_trains", caption = {"start-trains"}}
  button.style.horizontally_stretchable = true
  local button = flow.add{type = "button", name = "reset_trains", caption = {"reset-trains"}}
  button.style.horizontally_stretchable = true
  local button = flow.add{type = "button", name = "reset_all", caption = {"reset-all"}}
  button.style.horizontally_stretchable = true
  local button = add_button(flow)
  button.style.horizontally_stretchable = true
  set_continue_button_style(function (button)
    if button.valid then
      button.enabled = false
    end
  end)
  local player = player()
  player.set_controller{type = defines.controllers.god}
  player.remove_item"rail-chain-signal"
  if global.required_chain_signals and global.required_chain_signals > 0 then
    player.insert{name = "rail-chain-signal", count = global.required_chain_signals}
  end
  if global.required_rail_signals and global.required_rail_signals > 0 then
    player.insert{name = "rail-signal", count = global.required_rail_signals}
  end
  global.intermission = 0
  global.loop_interval = 0
  global.loop_tick = nil
end

function puzzle_condition_red()
  if global.continue then return true end
  for k, train in pairs (surface().find_entities_filtered{name = "locomotive"}) do
    if train.train.speed ~= 0 then
      return false
    end
    if train.color == nil then
      if train.train.state ~= defines.train_state.wait_station then
        return false
      end
      if train.health ~= 1000 then
        return false
      end
    end
    if train.train.state == defines.train_state.no_path then
      return false
    end
  end
  for k, wagon in pairs (surface().find_entities_filtered{name = "fluid-wagon"}) do
    if wagon.health ~= 600 then
      return false
    end
  end
  global.intermission = global.intermission + 1
  if global.intermission == 90 then
    flash_goal()
    set_continue_button_style(function (button)
      if button.valid then
        button.enabled = true
      end
    end)
  end
end

function puzzle_condition_all()
  if global.continue then return true end
  for k, train in pairs (surface().find_entities_filtered{name = "locomotive"}) do
    if train.train.speed ~= 0 then
      return false
    end

    if train.train.state ~= defines.train_state.wait_station then
      return false
    end
    if train.health ~= 1000 then
      return false
    end

    if train.train.state == defines.train_state.no_path then
      return false
    end
  end
  for k, wagon in pairs (surface().find_entities_filtered{name = "fluid-wagon"}) do
    if wagon.health ~= 600 then
      return false
    end
  end
  global.intermission = global.intermission + 1
  if global.intermission == 90 then
    flash_goal()
    set_continue_button_style(function (button)
      if button.valid then
        button.enabled = true
      end
    end)
  end
end

function loop_trains(interval)
  if interval then
    global.loop_interval = interval
    global.loop_tick = game.tick + global.loop_interval
    return
  end
  if not global.loop_tick then return end
  if game.tick ~= global.loop_tick then return end
  for k, train in pairs (surface().find_entities_filtered{name = "locomotive"}) do
    train.destroy()
  end
  for k, train in pairs (surface().find_entities_filtered{name = "fluid-wagon"}) do
    train.destroy()
  end
  recreate_entities(global.this_puzzle_trains, global.this_puzzle_param)
  global.loop_tick = game.tick + global.loop_interval
end
