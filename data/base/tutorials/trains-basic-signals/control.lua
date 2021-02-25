require "story"
local setups = require "basic-signals"

local clear_vis = function()
  for _, id in pairs(global.render_ids) do
    rendering.destroy(id)
  end
end

local add_labels = function(label_data)
  for _, data in pairs(label_data) do
    local matching_ents = surface().find_entities_filtered({name=data.name,position=data.position})
    if #matching_ents>0 then
      for _, ent in pairs(matching_ents) do
        local label_id = rendering.draw_text({
          surface = surface(),
          target = ent,
          target_offset = data.offset or {0,1},
          color = {1,1,1},
          text = {"label."..data.locale},
          alignment = 'center'
        })
        table.insert(global.render_ids,label_id)
      end
    end
  end
end

local signal_color_chart = function(gui_element)
  local signal_table = gui_element.add({
    type = 'table',
    column_count = 2,
    vertical_centering = false
  })
  local red = signal_table.add({type = 'label',caption = {'red'},})
  red.style.width = 60
  local r_means = signal_table.add({type = 'label',caption = {'red-means'},})
  r_means.style.single_line = false
  signal_table.add({type = 'label',caption = {'yellow'},})
  local y_means = signal_table.add({type = 'label',caption = {'yellow-means'},})
  y_means.style.single_line = false
  signal_table.add({type = 'label',caption = {'green'},})
  local g_means = signal_table.add({type = 'label',caption = {'green-means'},})
  g_means.style.single_line = false
  signal_table.style.width = 300
  signal_table.style.vertical_align = 'top'
end

local set_continue_button_state = function(state)
  set_continue_button_style(function (button)
    if button.valid then
      button.enabled = state
    end
  end)
  global.completed = state
end

local function clear_surface()
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

local setup_player = function(stacks)
  global.required_items = stacks or {}
end

local reset_player = function()
  player().set_controller{type = defines.controllers.god}
  for _, stack in pairs(global.required_items) do
    local needed_count = stack.count - #game.surfaces[1].find_entities_filtered({name=stack.name})
    if needed_count > 0 then
      player().insert({
        name=stack.name,
        count = needed_count
      })
    end
  end
end

local set_locomotive_references = function()
  global.active_locomotives = {}
  for _, entity in pairs(game.surfaces[1].find_entities_filtered({name='locomotive'})) do
    if entity.name == 'locomotive' then
      global.active_locomotives[entity.backer_name] = entity
    end
  end
end

local reset_trains = function()
  clear_vis()
  for k, train in pairs (surface().find_entities_filtered{name = "locomotive"}) do
    train.destroy()
  end
  for k, train in pairs (surface().find_entities_filtered{name = "fluid-wagon"}) do
    train.destroy()
  end
  recreate_entities(global.this_puzzle_trains,global.this_puzzle_param)
  reset_player()
  set_locomotive_references()
  add_labels(global.this_puzzle_labels)
end

local reset_puzzle = function()
  clear_surface()
  clear_vis()
  recreate_entities(global.this_puzzle,global.this_puzzle_param)
  reset_player()
  set_locomotive_references()
  add_labels(global.this_puzzle_labels)
  set_continue_button_state(false)
end

local setup_puzzle = function(puzzle,param)
  if puzzle then
    global.this_puzzle = puzzle
    global.this_puzzle_param = param or {}
    global.this_puzzle_labels = {}
    global.this_puzzle_trains = {}
    for _, data in pairs(puzzle) do
      if data.label then
        table.insert(global.this_puzzle_labels,{
          name = data.name,
          position = data.position,
          offset = data.label_offset or {0,1},
          locale = data.label
        })
      end
      data.minable = false
      data.operable = false
      if data.name == "locomotive" then
        if data.schedule then
          data.manual_mode = true
        end
        table.insert(global.this_puzzle_trains, data)
      end
    end
  end
  reset_puzzle()
end

local story_gui_click = function(event)
  local element = event.element
  if not element.valid then return end
  local player = game.players[event.player_index]
  local name = element.name
  if name == "start_trains" then
    if not element.enabled then return end
    for _, locomotive in pairs (global.active_locomotives) do
      if locomotive.train.schedule then
        locomotive.train.manual_mode = false
      end
    end
    element.enabled = false
    player.set_controller{type = defines.controllers.ghost}
    return
  end
  if name == "reset_trains" then
    reset_trains()
    for k, child in pairs (element.parent.children) do
      if child.name ~= "story_continue_button" then
        child.enabled = true
      end
    end
    return
  end
  if name == "reset_all" then
    reset_puzzle()
    for k, child in pairs (element.parent.children) do
      if child.name ~= "story_continue_button" then
        child.enabled = true
      end
    end
    return
  end
end

local function add_run_trains_button(gui)
  local flow = gui.add{type = "table", column_count = 10}
  flow.style.horizontal_spacing = 2
  local button = flow.add{type = "button", name = "start_trains", caption = {"start-trains"}}
  local button = flow.add{type = "button", name = "reset_trains", caption = {"reset-trains"}}
  local button = flow.add{type = "button", name = "reset_all", caption = {"reset-all"}}
  add_button(flow)
  set_continue_button_style(function (button)
    if button.valid then
      button.enabled = false
    end
  end)
  global.intermission = 0
  global.loop_interval = 0
  global.loop_tick = nil
end

local function find_signal_connection_side(rail, signal)
    if rail.get_rail_segment_entity(defines.rail_direction.front, false) == signal then
        return defines.rail_direction.front, false
    elseif rail.get_rail_segment_entity(defines.rail_direction.front, true) == signal then
        return defines.rail_direction.front, true
    elseif rail.get_rail_segment_entity(defines.rail_direction.back, false) == signal then
        return defines.rail_direction.back, false
    elseif rail.get_rail_segment_entity(defines.rail_direction.back, true) == signal then
        return defines.rail_direction.back, true
    else
        assert(false)
    end
end

local get_signal_rails = function(signal)
  assert(signal and (signal.type == "rail-signal" or signal.type == "rail-chain-signal"))
  local rails = signal.get_connected_rails()
  if #rails == 0 then
    return {to={},from={}}
  else
    local rail_direction, in_else_out = find_signal_connection_side(rails[1], signal)
    local otherRails = {}
    for _,connection_direction in pairs{defines.rail_connection_direction.left, defines.rail_connection_direction.straight, defines.rail_connection_direction.right} do
      local rail = rails[1].get_connected_rail{rail_direction=rail_direction, rail_connection_direction=connection_direction}
      if rail then
        table.insert(otherRails, rail)
      end
    end
    local from
    local to
    if in_else_out then
      from = otherRails
      to = rails
    else
      from = rails
      to = otherRails
    end
    return {
      to = to,
      from = from
    }
  end
end

local set_trains_automatic = function()
  for _, locomotive in pairs(global.active_locomotives) do
    if locomotive.train.schedule then
      locomotive.train.manual_mode = false
    end
  end
end

local disable_loop_trains = function()
  global.loop_tick = nil
  global.loop_interval = nil
end

local loop_trains = function(interval)
  if interval then
    global.loop_interval = interval
    global.loop_tick = game.ticks_played + global.loop_interval
    set_trains_automatic()
    return
  end
  if not global.loop_tick then return end
  if game.ticks_played < global.loop_tick then return end
  reset_trains()
  set_trains_automatic()
  global.loop_tick = game.ticks_played + global.loop_interval
end

local render_blocks = function(start_x, end_x, render_y)
  local signals = player().surface.find_entities_filtered({
    name = 'rail-signal'
  })
  local blocks = {}
  for i=1, #signals+1 do
    table.insert(blocks,{
      (signals[i-1] and signals[i-1].position.x) or start_x,
      (signals[i] and signals[i].position.x) or end_x
    })
  end
  clear_vis()
  for index, block in pairs(blocks) do
    local center_x = block[1] + (block[2]-block[1])/2
    local new_id = rendering.draw_text({
      text = "Block "..index,
      surface = surface(),
      target = {center_x,render_y},
      alignment = "center",
      color = {1,0.6,0}
    })
    table.insert(global.render_ids,new_id)
    local text_width = (block[2]-block[1]/2)
    local left_line_id = rendering.draw_line({
      color = {1,0.6,0},
      width = 2,
      from = {block[1]+0.2,render_y},
      to = {center_x,render_y},
      surface = surface()
    })
    table.insert(global.render_ids,left_line_id)
    local right_line_id = rendering.draw_line({
      color = {1,0.6,0},
      width = 2,
      from = {center_x,render_y},
      to = {block[2]-0.2,render_y},
      surface = surface()
    })
    table.insert(global.render_ids,right_line_id)
  end
end

local find_blocks_from_rails = function(rails)
  local blocks = {}
  local result = {}
  for _, rail in pairs(rails) do
    local start_rail = rail.get_rail_segment_end(defines.rail_direction.front)
    local end_rail = rail.get_rail_segment_end(defines.rail_direction.back)
    local id = start_rail.position.x..","..start_rail.position.y..","..end_rail.position.x..","..end_rail.position.y
    if blocks[id] then
    
    else
      blocks[id] = 1
      table.insert(result,{
        start_rail = start_rail,
        end_rail = end_rail
      })
    end
  end
  
  return result
end

local render_segment = function(start_rail,end_rail,id,offset)
  local width = end_rail.position.x - start_rail.position.x
  local height = end_rail.position.y - start_rail.position.y
  local center = {
    x = start_rail.position.x + width/2,
    y = start_rail.position.y + height/2
  }
  local name = {"label.block", id}
  local offset = offset or {0,0}
  local left_point = {
      x = start_rail.position.x + width/10 + offset[1],
      y = start_rail.position.y + offset[2]
    }
  local right_point = {
      x = end_rail.position.x - width/10 + offset[1],
      y = end_rail.position.y + offset[2]
    }
  local new_id = rendering.draw_text({
    text = name,
    surface = surface(),
    target = {center.x+offset[1],center.y+offset[2]},
    alignment = "center",
    color = {1,1,1}
  })
  table.insert(global.render_ids,new_id)
  --local left_line_id = rendering.draw_line({
  --  color = {1,0.6,0},
  --  width = 2,
  --  from = left_point,
  --  to = {center.x+offset[1],center.y+offset[2]},
  --  surface = surface()
  --})
  --table.insert(global.render_ids,left_line_id)
  --local right_line_id = rendering.draw_line({
  --  color = {1,0.6,0},
  --  width = 2,
  --  from = {center.x+offset[1],center.y+offset[2]},
  --  to = right_point,
  --  surface = surface()
  --})
  --table.insert(global.render_ids,right_line_id)
  --local circle_id = rendering.draw_circle({
  --  surface = surface(),
  --  color = {1,0.6,0},
  --  target = left_point,
  --  radius = 0.1,
  --  filled = true
  --})
  --table.insert(global.render_ids,circle_id)
  --local circle_id_2 = rendering.draw_circle({
  --  surface = surface(),
  --  color = {1,0.6,0},
  --  target = right_point,
  --  radius = 0.1,
  --  filled = true
  --})
  --table.insert(global.render_ids,circle_id_2)
end

local render_signal_read_location = function(signal,offset,blocks)
  local connected_rail = signal.get_connected_rails()
  local rail_pairs = get_signal_rails(signal)
  if #rail_pairs.to == 0 then
    local new_id = rendering.draw_text({
      text = {'label.no-block'},
      surface = surface(),
      target = signal,
      target_offset = offset,
      alignment = "center",
      color = {1,1,1,1}
    })
    table.insert(global.render_ids,new_id)
    return
  end
  local rail_x = rail_pairs.to[1].position.x
  for id, block in pairs(blocks) do
    if rail_x <= block.start_rail.position.x and rail_x >= block.end_rail.position.x then
      local new_id = rendering.draw_text({
        text = {'label.reading-block',id},
        surface = surface(),
        target = signal,
        target_offset = offset,
        alignment = "center",
        color = {1,1,1,1}
      })
      table.insert(global.render_ids,new_id)
    end
  end
end

local story_table = {
  {
    {
      init = function()
        player().set_quick_bar_slot(1,'rail-signal')
        player().set_quick_bar_slot(2,'cargo-wagon')
        if player().character then
          player().character.destroy()
        end
      end
    },
    {
      init = function()
        setup_player({})
        setup_puzzle(setups.straight_crash)
        set_info({text = {"trains-dont-see-trains"}})
        set_info({custom_function = add_button, append = true})
        loop_trains(3*60)
      end,
      condition = function(event)
        return global.continue
      end,
      action = function()
        set_info()
      end
    },
    {
      name = 'player-makes-a-block',
      init = function()
        setup_player({{name='rail-signal',count=1}})
        setup_puzzle(setups.empty_straight)
        set_info({text={"signals-split-rail"}})
        set_info({text={"place-signal-goal"},append=true})
        disable_loop_trains()
        player().game_view_settings = {show_rail_block_visualisation = true}
      end,
      update = function(event)
        if global.update_vis then
          clear_vis()
          local rails = surface().find_entities_filtered({name='straight-rail'})
          local blocks = find_blocks_from_rails(rails)
          for index, block in pairs(blocks) do
            render_segment(block.start_rail,block.end_rail,index,{0,0.7})
          end
          global.update_vis = false
        end
        if event.name == defines.events.on_built_entity or event.name == defines.events.on_player_mined_entity then
          global.update_vis = true
        end
      end,
      condition = function(event)
        return global.update_vis == false and surface().count_entities_filtered({name='rail-signal'}) > 0
      end,
      action = function()
        set_info()
      end
    },
    {
      name = 'place-second-signal',
      init = function()
        setup_player({{name='rail-signal',count=2}})
        reset_player()
        set_info({text={"see-block-split"}})
        set_info({text={"second-signal-goal"},append=true})
        global.update_vis = false
      end,
      update = function(event)
        if global.update_vis then
          clear_vis()
          local rails = surface().find_entities_filtered({name='straight-rail'})
          local blocks = find_blocks_from_rails(rails)
          for index, block in pairs(blocks) do
            render_segment(block.start_rail,block.end_rail,index,{0,0.7})
          end
          global.update_vis = false
        end
        if event.name == defines.events.on_built_entity or event.name == defines.events.on_player_mined_entity then
          global.update_vis = true
        end
      end,
      condition = function(event)
        return global.update_vis == false and surface().count_entities_filtered({name='rail-signal'}) > 1
      end,
      action = function()
        set_info()
      end
    },
    {
      name = 'show-signal-direction',
      init = function()
        setup_player({{name='rail-signal',count=2}})
        reset_player()
        set_info({text = {'signal-direction'}})
        set_info({text = {'hover-signal'},append=true})
        set_info({text = {'signal-direction-goal'},append=true})
        set_info({custom_function = add_button, append = true},false)
        set_continue_button_state(false)
        global.update_vis = true
        global.button_added = false
        global.completed = false
      end,
      update = function(event)
        if global.update_vis then
          clear_vis()
          local rails = surface().find_entities_filtered({name='straight-rail'})
          local signals = surface().find_entities_filtered({name='rail-signal'})
          local blocks = find_blocks_from_rails(rails)
          for index, block in pairs(blocks) do
            render_segment(block.start_rail,block.end_rail,index,{0,0.7})
          end
          for _, signal in pairs(signals) do
            render_signal_read_location(signal,(signal.position.y > 0 and {0,1}) or {0,-1}, blocks)
          end
          global.update_vis = false
        end
        if event.name == defines.events.on_built_entity or event.name == defines.events.on_player_mined_entity then
          global.update_vis = true
          if global.completed == false and event.created_entity and event.created_entity.name == 'rail-signal' then
            set_continue_button_state(true)
            global.completed = true
          end
        end
      end,
      condition = function(event)
        return global.continue and global.update_vis == false
      end,
      action = function()
        clear_vis()
        set_info()
        global.completed = false
      end
    },
    {
      condition = story_elapsed_check(0.1)
    },
    {
      name = 'show-signal-color',
      init = function()
        setup_player({{name='rail-signal',count=2},{name='cargo-wagon',count=1}})
        reset_player()
        set_info({text = {'signals-read-ahead'}})
        set_info({custom_function = signal_color_chart, append = true})
        set_info({text = {'place-wagon-goal'},append=true})
        set_info({custom_function = add_button, append = true},false)
        set_continue_button_state(false)
        global.update_vis = true
        global.button_added = false
      end,
      update = function(event)
        if global.update_vis then
          clear_vis()
          local rails = surface().find_entities_filtered({name='straight-rail'})
          local signals = surface().find_entities_filtered({name='rail-signal'})
          local blocks = find_blocks_from_rails(rails)
          for index, block in pairs(blocks) do
            render_segment(block.start_rail,block.end_rail,index,{0,0.7})
          end
          for _, signal in pairs(signals) do
            render_signal_read_location(signal,(signal.position.y > 0 and {0,1}) or {0,-1}, blocks)
          end
          global.update_vis = false
        end
        if event.name == defines.events.on_built_entity or event.name == defines.events.on_player_mined_entity then
          global.update_vis = true
          if global.completed == false and event.created_entity and event.created_entity.name == 'cargo-wagon' then
            set_continue_button_state(true)
            global.completed = true
          end
        end
      end,
      condition = function(event)
        return global.continue and global.update_vis == false
      end,
      action = function()
        clear_vis()
        set_info()
        global.completed = false
      end
    },
    {
      condition = story_elapsed_check(0.1)
    },
    {
      init = function()
        player().set_quick_bar_slot(1,'rail-signal')
        setup_player({{name='rail-signal',count=3}})
        setup_puzzle(setups.isolate_train)
        set_info({text = {"go-around-info"}})
        set_info({text = {"go-around-goal"},append = true})
        set_info({custom_function = add_run_trains_button, append = true})
      end,
      update = function()
        if global.completed == false and global.active_locomotives['Red'] and global.active_locomotives['Red'].train.state == defines.train_state.wait_station then
          set_continue_button_state(true)
        end
      end,
      condition = function()
        return global.continue
      end,
      action = function()
        set_info()
        global.completed = false
      end
    },
    {
      condition = story_elapsed_check(0.1)
    },
    {
      init = function()
        player().set_quick_bar_slot(1,'rail-signal')
        setup_player({{name='rail-signal',count=4}})
        setup_puzzle(setups.oncoming)
        set_info({text={"oncoming-goal"}})
        set_info({text = {"oncoming-info"},append=true})
        set_info({custom_function = add_run_trains_button, append = true})
      end,
      update = function()
        if global.completed == false and global.active_locomotives['Red'] and global.active_locomotives['Red'].train.state == defines.train_state.wait_station
                and global.active_locomotives['Cyan'] and global.active_locomotives['Cyan'].train.state == defines.train_state.wait_station then
          set_continue_button_state(true)
        end
      end,
      condition = function()
        return global.continue
      end,
      action = function()
        set_info()
        global.completed = false
      end
    },
    {
      condition = story_elapsed_check(0.1)
    },
    {
      init = function(event)
        setup_player({{name='rail-signal',count=4}})
        setup_puzzle(setups.lower_track, {offset = {0,-8}})
        set_info({text={"siding-signals-info"}})
        set_info({text = {"siding-signals-goal"},append=true})
        set_info({custom_function = add_run_trains_button, append = true})
      end,
      update = function()
        if global.completed == false and global.active_locomotives['Red'] and global.active_locomotives['Red'].train.state == defines.train_state.wait_station then
          set_continue_button_state(true)
        end
      end,
      condition = function(event)
        return global.continue
      end,
      action = function()
        set_info()
        global.completed = false
      end
    },
    {
      condition = story_elapsed_check(0.1)
    },
    {
      init = function(event)
        setup_player({{name='rail-signal',count=4}})
        setup_puzzle(setups.two_way,{offset = {6, -16}})
        set_info({text={"proceed-goal"}})
        set_info({custom_function = add_run_trains_button, append = true})
      end,
      update = function()
        if global.completed == false and global.active_locomotives['Red'] and global.active_locomotives['Red'].train.state == defines.train_state.wait_station then
          set_continue_button_state(true)
        end
      end,
      condition = function(event)
        return global.continue
      end,
      action = function()
        set_goal()
        set_info()
        global.completed = false
      end
    },
    {
      init = function()
        setup_player({{name='rail-signal',count=3}})
        setup_puzzle(setups.crossroads,{offset = {0, 46}})
        reset_player()
        set_info({text={"proceed-goal"}})
        set_info({custom_function = add_run_trains_button, append = true})
      end,
      update = function()
        if global.completed == false and global.active_locomotives['Red'] and global.active_locomotives['Red'].train.state == defines.train_state.wait_station then
          set_continue_button_state(true)
        end
      end,
      condition = function(event)
        return global.continue
      end,
      action = function()
        set_goal()
        set_info()
        global.completed = false
      end
    },
    {
      init = function()
        reset_player()
        for k, entity in pairs (surface().find_entities()) do
          entity.minable = true
          entity.operable = true
          entity.rotatable = true
        end
        player().insert({name='rail',count=1000})
        player().insert({name='rail-signal',count=30})
        player().insert({name='train-stop',count=10})
        player().insert({name='locomotive',count=3})
        player().insert({name='cargo-wagon',count=3})
        player().insert({name='coal',count=100})
        player().set_quick_bar_slot(2,'rail')
        player().set_quick_bar_slot(3,'train-stop')
        player().set_quick_bar_slot(4,'locomotive')
        player().set_quick_bar_slot(5,'cargo-wagon')
        player().set_quick_bar_slot(6,'coal')
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

local on_player_created = function(event)
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
  local old_character = player.character
  player.character = nil
  old_character.destroy()
end

story_init_helpers(story_table)

script.on_init(function()
  game.forces.player.manual_mining_speed_modifier = 4
  game.forces.player.disable_all_prototypes()
  surface().always_day = true
  global.story = story_init(story_table)
  global.render_ids = {}
  global.update_vis = true
  limit_camera({0,0}, 0)
end)

script.on_event(defines.events.on_tick, function(event)
  story_update(global.story, event, "")
  loop_trains()
end)

script.on_event(defines.events.on_gui_click, function(event)
  story_update(global.story, event, "")
  story_gui_click(event)
end)

script.on_event(defines.events.on_built_entity, function(event)
  story_update(global.story, event, "")
end)

script.on_event(defines.events.on_player_mined_entity, function(event)
  story_update(global.story, event, "")
end)

script.on_event(defines.events.on_player_created, on_player_created)
