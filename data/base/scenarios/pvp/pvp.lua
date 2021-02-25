local mod_gui = require("mod-gui")
local util = require("util")
local get_walkable_tile = util.get_walkable_tile
local balance = require("balance")
local config = require("config")
local production_score = require("production-score")
local kill_score = require("kill-score")
local insert = table.insert

local script_data =
{
  gui_actions = {},
  team_players = {},
  elements =
  {
    config = {},
    balance = {},
    import = {},
    admin = {},
    admin_button = {},
    spectate_button = {},
    join = {},
    progress_bar = {},
    team_frame = {},
    team_list_button = {},
    production_score_frame = {},
    production_score_inner_frame = {},
    recipe_frame = {},
    recipe_button = {},
    inventory = {},
    space_race_frame = {},
    kill_score_frame = {},
    oil_harvest_frame = {},
    team_tab = {},
    game_tab = {}
  },
  setup_finished = false,
  ready_players = {},
  config = {},
  round_number = 0,
  selected_recipe = {},
  random = nil,
  team_names = {}
}

local statistics_period = 150 -- Seconds

local events =
{
  on_round_end = script.generate_event_name(),
  on_round_start = script.generate_event_name(),
  on_team_lost = script.generate_event_name(),
  on_team_won = script.generate_event_name(),
  on_player_joined_team = script.generate_event_name()
}

get_starting_area_radius = function(as_tiles)
  local surface = game.surfaces[1]
  local radius = math.ceil(surface.get_starting_area_radius() / 32)
  if as_tiles then
    return radius * 32
  end
  return radius
end

local lobby_name = "Lobby"
local get_lobby_surface = function()
  if game.surfaces[lobby_name] then return game.surfaces[lobby_name] end
  local surface = game.create_surface(lobby_name, {width = 1, height = 1})
  surface.set_tiles({{name = "out-of-map", position = {1,1}}})
  return surface
end

local is_in_map = function(width, height, position)
  return position.x >= -width
    and position.x < width
    and position.y >= -height
    and position.y < height
end

function create_spawn_positions()
  local settings = game.surfaces[1].map_gen_settings
  local width = settings.width
  local height = settings.height
  local height_scale = height / width
  local radius = get_starting_area_radius() + 1
  local diameter = radius * 32 * 2 * math.sqrt(2)
  local count = #script_data.config.teams
  if count == 1 then
    local positions =
    {
      {x = 0, y = 0}
    }
    script_data.spawn_offset = positions[1]
    script_data.spawn_positions = positions
    return positions
  end
  local angle = math.pi / count
  local hypotenuse = math.abs(math.sin(angle) * diameter)
  if hypotenuse < 0.01 then hypotenuse = diameter end
  --local min_distance = math.ceil((radius - 1) * 32) * (#script_data.config.teams)
  local min_distance = math.ceil(diameter * (diameter/hypotenuse))
  local displacement = script_data.config.team_config.average_team_displacement
  if displacement < min_distance then
    script_data.config.team_config.average_team_displacement = min_distance
    displacement = min_distance
  end

  local mag = displacement + (radius * 32)
  local y_scale = 1
  if mag > (height / 2) then
    --circle too tall
    y_scale = height_scale
  end
  local x_scale = 1
  if mag > (width / 2) then
    --circle too wide
    x_scale = 1 / height_scale
  end
  local random = script_data.random
  local horizontal_offset = (width > 10000 and (width / displacement) * 10) or 0
  local vertical_offset =  (height > 10000 and (height / displacement) * 10) or 0
  script_data.spawn_offset =
  {
    x = math.floor(0.5 + random(math.floor(-horizontal_offset), math.floor(horizontal_offset)) / 32) * 32,
    y = math.floor(0.5 + random(math.floor(-vertical_offset), math.floor(vertical_offset)) / 32) * 32
  }

  local distance = 0.5 * displacement
  local positions = {}

  local rotation_offset = (script_data.random() * (math.pi * 2))
  for k = 1, count do
    local rotation = rotation_offset + ((k * 2 * math.pi) / count)
    local X = (math.cos(rotation) * distance * x_scale) / 32
    if X > 0 then
      X = 32 * (math.floor(X))
    else
      X = 32 * (math.ceil(X))
    end
    local Y = (math.sin(rotation) * distance * y_scale) / 32
    if Y > 0 then
      Y = 32 * (math.floor(Y))
    else
      Y = 32 * (math.ceil(Y))
    end
    positions[k] = {x = X + script_data.spawn_offset.x, y = Y + script_data.spawn_offset.y}
  end

  script_data.spawn_positions = positions
  return positions
end

function create_next_surface()
  local name = "battle_surface_1"
  if game.surfaces[name] ~= nil then
    name = "battle_surface_2"
  end
  script_data.round_number = script_data.round_number + 1
  local settings = game.surfaces[1].map_gen_settings
  settings.starting_points = create_spawn_positions()
  settings.seed = script_data.config.game_config.seed
  script_data.surface = game.create_surface(name, settings)
  script_data.surface.always_day = script_data.config.team_config.always_day
end

function destroy_player_gui(player)
  local elements = script_data.elements
  local index = player.index
  for name, guis in pairs (elements) do
    local frame = guis[index]
    if frame and frame.valid then
      deregister_gui(frame)
      frame.destroy()
    end
    guis[index] = nil
  end
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

local red = function(str)
  return "[color=1,0.2,0.2]"..str.."[/color]"
end

local green = function(str)
  return "[color=0.2,1,0.2]"..str.."[/color]"
end

function add_team_to_new_flow(team, flow, current_team, admin)
  local frame = flow.add{type = "frame", direction = "vertical", style = "bordered_frame"}
  frame.style.horizontally_stretchable = true

  local title_flow = frame.add{type = "flow", direction = "horizontal"}
  title_flow.style.vertical_align = "center"

  local show_flow = title_flow.add{type = "flow", style = "slot_table_spacing_horizontal_flow"}

  local label = show_flow.add{type = "label", caption = team.name, style = "caption_label"}
  label.style.font_color = get_color(team, true)

  add_pusher(show_flow)

  if admin then
    local edit_flow = title_flow.add{type = "flow", style = "slot_table_spacing_horizontal_flow", visible = false}
    edit_flow.style.horizontally_squashable = true
    local textfield = edit_flow.add{type = "textfield", text = team.name}
    textfield.style.width = 150
    local color_drop = edit_flow.add{type = "drop-down"}
    local index = 1
    for k, color in pairs (script_data.config.colors) do
      color_drop.add_item({"color."..color.name})
      if color.name == team.color then
        index = k
      end
    end
    color_drop.selected_index = index
    add_pusher(edit_flow)
    local textfield_confirm = edit_flow.add{type = "sprite-button", style = "item_and_count_select_confirm", sprite = "utility/confirm_slot"}
    textfield_confirm.style.padding = 2
    textfield_confirm.style.margin = 0
    local textfield_cancel = edit_flow.add{type = "sprite-button", style = "tool_button_red", sprite = "utility/reset"}
    local edit_button = title_flow.add{type = "sprite-button", style = "tool_button", sprite = "utility/rename_icon_small_black"}
    local line = title_flow.add{type = "line", direction = "vertical"}
    line.style.height = 32
    line.style.vertically_stretchable = false
    local delete_button = title_flow.add{type = "sprite-button", style = "tool_button_red", sprite = "utility/trash", enabled = #script_data.config.teams > 1}
    register_gui_action(textfield_cancel, {type = "cancel_rename", edit_flow = edit_flow, show_flow = show_flow, buttons = {edit_button, delete_button}})
    register_gui_action(edit_button, {type = "rename_team", edit_flow = edit_flow, show_flow = show_flow, buttons = {edit_button, delete_button}})
    register_gui_action(delete_button, {type = "remove_team", team = team, frame = frame})
    register_gui_action(textfield_confirm, {type = "confirm_rename", textfield = textfield, team = team, dropdown = color_drop})
  end

  local line = frame.add{type = "line", direction = "horizontal"}

  local team_table = frame.add{type = "table", column_count = 2}

  team_table.add{type = "label", caption = {"", {"team"}, {"colon"}}, style = "description_label"}

  if admin then
    local drop_down = team_table.add{type = "drop-down"}
    local selected_index = 1
    drop_down.add_item({"no-team"})
    drop_down.add_item({"random-team"})
    for k = 1, #script_data.config.teams do
      drop_down.add_item(k)
      if k == team.team then
        selected_index = k + 2
      end
    end
    drop_down.selected_index = selected_index
    register_gui_action(drop_down, {type = "team_drop_down", team = team})
  else
    local caption
    if team.team == "-" then
      caption = {"no-team"}
    elseif team.team == "?" then
      caption = {"random-team"}
    else
      caption = team.team
    end
    team_table.add{type = "label", caption = caption}
  end

  local label = team_table.add{type = "label", caption = {"members"}, style = "description_label"}
  label.style.minimal_width = 150

  local ready = ""
  local first_ready = true
  local ready_data = script_data.ready_players

  local limit = script_data.config.team_config.max_players
  limit = (limit > 0 and limit) or math.huge
  local player_count = 0
  for k, member in pairs (team.members or {}) do
    player_count = player_count + 1
    if player_count > limit then
      team.members[k] = nil
      ready_data[k] = nil
      script_data.team_players[k] = nil
    else
      if first_ready then
        first_ready = false
      else
        ready = ready..", "
      end
      if ready_data[k] then
        ready = ready .. green(member.name)
      else
        ready = ready .. red(member.name)
      end
    end
  end
  if ready == "" then
    ready = {"none"}
  end
  local label = team_table.add{type = "label", caption = ready, style = "description_label"}
  label.style.single_line = false
  label.style.maximal_width = 400
  local within_limit = player_count < limit
  if within_limit and (not current_team or current_team ~= team) then
    local join_team = frame.add{type = "button", caption = {"join-team"}}
    join_team.style.font = "default"
    join_team.style.height = 24
    join_team.style.top_padding = 0
    join_team.style.bottom_padding = 0
    register_gui_action(join_team, {type = "join_team", team = team})
  end
  if current_team == team then
    local leave_team = frame.add{type = "button", caption = {"leave-team"}}
    leave_team.style.font = "default"
    leave_team.style.height = 24
    leave_team.style.top_padding = 0
    leave_team.style.bottom_padding = 0
    register_gui_action(leave_team, {type = "leave_team"})
  end

end

refresh_config = function(excluded_player_index)
  for k, player in pairs (game.connected_players) do
    if player.index ~= excluded_player_index then
      update_game_tab(player)
      update_team_tab(player)
      update_balance_tab(player)
      update_inventory_tab(player)
    end
  end
end

local name_allowed = function(name, team)
  if name == "" then return false end
  for k, other_team in pairs (script_data.config.teams) do
    if other_team.name == name then
      if other_team ~= team then
        return false
      end
    end
  end
  return true
end

local is_text_valid = function(text, strict)
  if text == "" then return false end
  local number = tonumber(text)
  if not number then return false end
  if number < 0 then return false end
  if number > 4294967295 then return false end
  if strict then return number >= 100 and number <= 254000 end
  return true
end

local check_all_ready = function()
  local all_ready = true
  for k, player in pairs (game.connected_players) do
    if not script_data.ready_players[player.index] then
      all_ready = false
      break
    end
  end
  if all_ready then
    start_all_ready_preparations()
  elseif script_data.ready_start_tick then
    script_data.ready_start_tick = nil
    game.print({"ready-cancelled"})
  end
end

update_inventory_tab = function(player)
  local group = script_data.elements.inventory[player.index]
  if not (group and group.valid) then return end
  group.clear()
  local admin = player.admin
  local config = script_data.config
  local types =
  {
    {name = {"equipment"}, list = config.equipment_list, option = config.starting_equipment},
    {name = {"chest"}, list = config.inventory_list, option = config.starting_chest}
  }
  for k, param in pairs (types) do
    local data = param.list
    local options = param.option
    if data and options then
      local inner = group.add{type = "frame", style = "bordered_frame", direction = "vertical"}
      inner.style.minimal_width = 500
      local top_flow = inner.add{type = "flow"}
      top_flow.add{type = "label", caption = param.name, style = "caption_label"}
      top_flow.style.vertical_align = "center"
      add_pusher(top_flow)
      local selected = options.selected
      if admin then
        local dropdown = top_flow.add{type = "drop-down"}
        dropdown.style.horizontally_stretchable = true
        register_gui_action(dropdown, {type = "starting_item_dropdown_changed", options = options})
        local index = 1
        for k, option in pairs (options.options) do
          if option == selected then index = k end
          dropdown.add_item({option})
        end
        dropdown.selected_index = index
      else
        top_flow.add{type = "label", caption = {selected}}
      end
      local scroll = inner.add{type = "scroll-pane", style = "scroll_pane_in_shallow_frame"}
      scroll.style.margin = 4
      local items = data[selected]
      if not items then return end
      if next(items) then
        local prototypes = game.item_prototypes
        local item_table = scroll.add{type = "table", column_count = 2, style = "bordered_table"}
        item_table.style.horizontally_stretchable = true
        for name, count in pairs (items) do
          local prototype = prototypes[name]
          if prototype then
            local flow = item_table.add{type = "flow"}
            flow.style.vertical_align = "center"
            if admin then
              local elem = flow.add{type = "choose-elem-button", elem_type = "item", style = "slot_button_in_shallow_frame"}
              elem.elem_value = name
              register_gui_action(elem, {type = "starting_item_elem_changed", items = items, previous = name})
            else
              local sprite = flow.add{type = "sprite", sprite = "item/"..name, style = "small_text_image"}
            end
            flow.add{type = "label", caption = prototype.localised_name}
            add_pusher(flow)
            if admin then
              local text = flow.add{type = "textfield", text = count, numeric = true, allow_decimal = false, allow_negative = false, style = "slider_value_textfield"}
              register_gui_action(text, {type = "starting_item_textfield_changed", items = items, key = name})
            else
              flow.add{type = "label", caption = count}
            end
          end
        end
      end

      if admin then
        local elem = inner.add{type = "choose-elem-button", elem_type = "item", style = "slot_button_in_shallow_frame"}
        --local pusher = scroll.add{type = "empty-widget"}
        --pusher.style.vertically_stretchable = true
        register_gui_action(elem, {type = "starting_item_elem_changed", items = items})
      end
    end
  end

end

add_starting_chest_tab = function(tab_pane)
  local tab = tab_pane.add{type = "tab", caption = {"starting-items"}}
  local group = tab_pane.add{type = "flow"}
  tab_pane.add_tab(tab, group)
  local player = game.get_player(tab_pane.player_index)
  script_data.elements.inventory[player.index] = group
  update_inventory_tab(player)
end

local set_team = function(player_index, team)
  local current_team = script_data.team_players[player_index]
  if current_team then
    current_team.members[player_index] = nil
  end
  if team then
    team.members[player_index] = game.get_player(player_index)
    script_data.team_players[player_index] = team
  else
    script_data.team_players[player_index] = nil
  end
  script_data.ready_players[player_index] = nil
end

local gui_functions =
{
  new_team = function(event, param)
    local name
    repeat name = game.backer_names[math.random(#game.backer_names)]
    until name_allowed(name)
    local team =
    {
      name = name,
      color = script_data.config.colors[math.random(#script_data.config.colors)].name,
      members = {},
      team = "-"
    }
    insert(script_data.config.teams, team)
    refresh_config()
  end,
  remove_team = function(event, param)
    if #script_data.config.teams == 1 then
      return
    end
    for k, team in pairs (script_data.config.teams) do
      if team == param.team then
        table.remove(script_data.config.teams, k)
        for k, members in pairs (team.members) do
          script_data.ready_players[k] = nil
          script_data.team_players[k] = nil
        end
        break
      end
    end
    refresh_config()
  end,
  rename_team = function(event, param)
    param.edit_flow.visible = true
    param.show_flow.visible = false
    for k, button in pairs (param.buttons) do
      button.enabled = false
    end
  end,
  cancel_rename = function(event, param)
    param.edit_flow.visible = false
    param.show_flow.visible = true
    for k, button in pairs (param.buttons) do
      button.enabled = true
    end
  end,
  confirm_rename = function(event, param)
    local name = param.textfield.text
    if not name_allowed(name, param.team) then
      game.players[event.player_index].print("Name not allowed") --[[TODO locale]]
      return
    end
    param.team.name = name
    param.team.color = script_data.config.colors[param.dropdown.selected_index].name
    refresh_config()
  end,
  join_team = function(event, param)
    set_team(event.player_index, param.team)
    refresh_config()
    check_all_ready()
  end,
  leave_team = function(event, param)
    set_team(event.player_index)
    refresh_config()
    check_all_ready()
  end,
  team_drop_down = function(event, param)
    local gui = event.element
    if not (gui and gui.valid) then return end
    if event.name ~= defines.events.on_gui_selection_state_changed then return end
    local index
    if gui.selected_index == 1 then
      index = "-"
    elseif gui.selected_index == 2 then
      index = "?"
    else
      index = gui.selected_index - 2
    end
    param.team.team = index
    refresh_config(event.player_index)
  end,
  config_text_value_changed = function(event, param)
    if event.name ~= defines.events.on_gui_text_changed then return end
    local textfield = event.element
    if not (textfield and textfield.valid) then return end
    local text = textfield.text
    local valid = is_text_valid(text)
    if not valid then
      textfield.style = "invalid_value_textfield"
      textfield.style.horizontal_align = "center"
      return
    end
    textfield.style = "slider_value_textfield"
    param.config[param.key] = tonumber(text)
    refresh_config(event.player_index)
  end,
  config_dropdown_value_changed = function(event, param)
    if event.name ~= defines.events.on_gui_selection_state_changed then return end
    local dropdown = event.element
    if not (dropdown and dropdown.valid) then return end
    param.value.selected = param.value.options[dropdown.selected_index]
    refresh_config(event.player_index)
  end,
  config_boolean_changed = function(event, param)
    if event.name ~= defines.events.on_gui_checked_state_changed then return end
    local check = event.element
    if not (check and check.valid) then return end
    param.config[param.key] = check.state
    refresh_config(event.player_index)
  end,
  victory_config_boolean_changed = function(event, param)
    if event.name ~= defines.events.on_gui_checked_state_changed then return end
    local check = event.element
    if not (check and check.valid) then return end
    param.config[param.key].active = check.state
    refresh_config(event.player_index)
  end,
  start_round = function(event, param)
    start_round()
  end,
  ready_up = function(event, param)
    if event.name ~= defines.events.on_gui_checked_state_changed then return end
    local checkbox = event.element
    if not (checkbox and checkbox.valid) then return end
    local player = game.players[event.player_index]
    if checkbox.state then
      script_data.ready_players[event.player_index] = true
      game.print({"player-is-ready", player.name})
    else
      script_data.ready_players[event.player_index] = nil
      game.print({"player-is-not-ready", player.name})
    end
    refresh_config()
    check_all_ready()
  end,
  toggle_balance_options = function(event, param)
    toggle_balance_options_gui(game.players[event.player_index])
  end,
  reset_balance_options = function(event, param)
    for name, modifiers in pairs (script_data.config.modifier_list) do
      for key, value in pairs (modifiers) do
        modifiers[key] = 0
      end
    end
    refresh_config()
  end,
  balance_textfield_changed = function(event, param)
    if event.name ~= defines.events.on_gui_text_changed then return end
    local textfield = event.element
    if not (textfield and textfield.valid) then return end
    local text = textfield.text
    text = text:gsub("%%", "")
    local valid = is_text_valid(text, param.no_below_100)
    if not valid then
      textfield.style = "invalid_value_textfield"
      textfield.style.horizontal_align = "center"
      return
    end
    textfield.style = "slider_value_textfield"
    local value = (text - 100) / 100
    script_data.config.modifier_list[param.modifier][param.key] = value
    refresh_config(event.player_index)
  end,
  pvp_import = function(event, param)
    local player = game.players[event.player_index]
    if not (player and player.valid) then return end
    local gui = player.gui.screen
    local frame = gui.add{type = "frame", caption = {"gui-blueprint-library.import-string"}, direction = "vertical"}
    frame.auto_center = true

    local old = script_data.elements.import[player.index]
    if (old and old.valid) then old.destroy() end

    script_data.elements.import[player.index] = frame
    local textfield = frame.add{type = "text-box"}
    textfield.word_wrap = true
    textfield.style.height = player.display_resolution.height * 0.6 / player.display_scale
    textfield.style.width = player.display_resolution.width * 0.6 / player.display_scale
    local flow = frame.add{type = "flow", direction = "horizontal", style = "dialog_buttons_horizontal_flow"}
    register_gui_action
    (
      flow.add{type = "button", caption = {"gui.close"}, style = "dialog_button"},
      {type = "import_export_close", frame = frame}
    )
    local pusher = flow.add{type = "empty-widget", style = "draggable_space"}
    pusher.style.horizontally_stretchable = true
    pusher.style.vertically_stretchable = true
    pusher.drag_target = frame
    local confirm_button = flow.add{type = "button", caption = {"gui-blueprint-library.import"}, style = "confirm_button"}
    confirm_button.style.minimal_width = 250
    register_gui_action
    (
      confirm_button,
      {type = "import_confirm", frame = frame, textfield = textfield}
    )
  end,
  import_confirm = function(event, param)
    local player = game.players[event.player_index]
    if not (player and player.valid) then return end
    local gui = player.gui.center
    local frame = param.frame
    if not (frame and frame.valid) then return end
    local textfield = param.textfield
    if not (textfield and textfield.valid) then return end
    local text = textfield.text
    if text == "" then player.print({"import-failed"}) return end
    local new_config = game.json_to_table(game.decode_string(text))
    if not new_config then
      player.print({"import-failed"})
      return
    end
    for k, v in pairs (new_config) do
      script_data.config[k] = v
    end

    local default_config = config.get_config()
    --We don't want to always append the new starting items to the default ones, so just clear them here.
    default_config.inventory_list = {}
    default_config.equipment_list = {}

    recursive_data_check(default_config, script_data.config)

    refresh_config()
    deregister_gui(frame)
    frame.destroy()
    script_data.elements.import[player.index] = nil
    player.print({"import-success"})
    log("Pvp config import success")
  end,
  pvp_export = function(event, param)
    local player = game.players[event.player_index]
    if not (player and player.valid) then return end
    local gui = player.gui.screen
    local frame = gui.add{type = "frame", caption = {"gui.export-to-string"}, direction = "vertical"}
    frame.auto_center = true

    local old = script_data.elements.import[player.index]
    if (old and old.valid) then old.destroy() end

    script_data.elements.import[player.index] = frame
    local textfield = frame.add{type = "text-box"}
    textfield.word_wrap = true
    textfield.read_only = true
    textfield.style.height = player.display_resolution.height * 0.6 / player.display_scale
    textfield.style.width = player.display_resolution.width * 0.6 / player.display_scale
    local config = script_data.config
    local data =
    {
      game_config = config.game_config,
      team_config = config.team_config,
      modifier_list = config.modifier_list,
      teams = config.teams,
      disabled_items = config.disabled_items,
      inventory_list = config.inventory_list,
      equipment_list = config.equipment_list,
      victory = config.victory,
      starting_equipment = config.starting_equipment,
      starting_chest = config.starting_chest
    }
    textfield.text = game.encode_string(game.table_to_json(data))
    local flow = frame.add{type = "flow", style = "dialog_buttons_horizontal_flow"}
    register_gui_action
    (
      flow.add{type = "button", caption = {"gui.close"}, style = "dialog_button"},
      {type = "import_export_close", frame = frame}
    )
    local pusher = flow.add{type = "empty-widget", style = "draggable_space_with_no_right_margin"}
    pusher.style.horizontally_stretchable = true
    pusher.style.vertically_stretchable = true
    pusher.drag_target = frame
  end,
  import_export_close = function(event, param)
    local frame = param.frame
    if not (frame and frame.valid) then return end
    deregister_gui(frame)
    frame.destroy()
    script_data.elements.import[event.player_index] = nil
  end,
  starting_chest = function(event, param)
    toggle_starting_chest_gui(game.players[event.player_index])
  end,
  starting_item_textfield_changed = function(event, param)
    if event.name ~= defines.events.on_gui_text_changed then return end
    local textfield = event.element
    if not (textfield and textfield.valid) then return end
    local text = textfield.text
    local valid = is_text_valid(text)
    if not valid then
      textfield.style = "invalid_value_textfield"
      textfield.style.horizontal_align = "center"
      return
    end
    textfield.style = "slider_value_textfield"
    param.items[param.key] = tonumber(text)
    refresh_config(event.player_index)
  end,
  starting_item_elem_changed = function(event, param)
    if event.name ~= defines.events.on_gui_elem_changed then return end
    local element = event.element
    if not (element and element.valid) then return end
    local items = param.items
    local previous = param.previous
    if previous then
      items[param.previous] = nil
    end
    local name = element.elem_value
    if name then
      if items[name] then
        game.players[event.player_index].print("No doofus, its already there")
      else
        items[name] = game.item_prototypes[name].stack_size
      end
    end
    refresh_config()
  end,
  starting_item_dropdown_changed = function(event, param)
    if event.name ~= defines.events.on_gui_selection_state_changed then return end
    local dropdown = event.element
    if not (dropdown and dropdown.valid) then return end
    local data = param.options
    data.selected = data.options[dropdown.selected_index]
    refresh_config()
  end,
  disable_elem_changed = function(event, param)
    if event.name ~= defines.events.on_gui_elem_changed then return end

    local gui = event.element
    local player = game.players[event.player_index]
    if not (player and player.valid and gui and gui.valid) then return end
    local parent = gui.parent
    if not script_data.config.disabled_items then
      script_data.config.disabled_items = {}
    end
    local items = script_data.config.disabled_items
    local value = gui.elem_value
    if not value then
      local map = {}
      for k, child in pairs (parent.children) do
        if child.elem_value then
          map[child.elem_value] = true
        end
      end
      for item, bool in pairs (items) do
        if not map[item] then
          items[item] = nil
        end
      end
      deregister_gui(gui)
      gui.destroy()
      return
    end

    if items[value] then
      if items[value] ~= gui.index then
        gui.elem_value = nil
        player.print({"duplicate-disable"})
      end
    else
      items[value] = gui.index
      register_gui_action(parent.add{type = "choose-elem-button", elem_type = "item", style = "recipe_slot_button"}, {type = "disable_elem_changed"})
    end
    script_data.config.disabled_items = items
    refresh_config(event.player_index)
  end,
  join_spectator = function(event, param)
    local frame = param.frame
    if (frame and frame.valid) then
      deregister_gui(frame)
      frame.destroy()
    end
    spectator_join(game.players[event.player_index])
  end,
  join_random = function(event, param)
    local frame = param.frame
    if (frame and frame.valid) then
      deregister_gui(frame)
      frame.destroy()
    end
    local player = game.get_player(event.player_index)
    local teams = get_eligible_teams(player)
    if not teams then return end
    local team = teams[math.random(#teams)]

    set_player(player, team)

    for k, other_player in pairs (game.connected_players) do
      choose_joining_gui(other_player)
      choose_joining_gui(other_player)
      update_team_list_frame(other_player)
    end
  end,
  admin_button = function(event, param)
    local gui = event.element
    local player = game.players[event.player_index]
    local frame = script_data.elements.admin[event.player_index]
    if (frame and frame.valid) then
      frame.visible = not frame.visible
      return
    end
    local flow = mod_gui.get_frame_flow(player)
    local frame = flow.add{type = "frame", style = mod_gui.frame_style, caption = {"admin"}, direction = "vertical"}
    script_data.elements.admin[player.index] = frame
    frame.visible = true
    local inner = frame.add{type = "frame", direction = "vertical", style = "window_content_frame_deep"}
    register_gui_action(inner.add{type = "button", caption = {"end-round"}, tooltip = {"end-round-tooltip"}}, {type = "admin_end_round"})
    register_gui_action(inner.add{type = "button", caption = {"reroll-round"}, tooltip = {"reroll-round-tooltip"}}, {type = "admin_reroll_round"})
    register_gui_action(inner.add{type = "button", caption = {"restart-round"}, tooltip = {"restart-round-tooltip"}}, {type = "admin_restart_round"})
    register_gui_action(inner.add{type = "button", caption = {"admin-change-team"}, tooltip = {"admin-change-team-tooltip"}}, {type = "spectator_join_team_button"})
  end,
  admin_end_round = function(event, param)
    end_round(game.players[event.player_index])
  end,
  admin_reroll_round = function(event, param)
    game.print({"round-rerolled"})
    end_round()
    script_data.config.game_config.seed = math.random(2^32) - 1
    start_round()
    return
  end,
  admin_restart_round = function(event, param)
    game.print({"round-restarted"})
    end_round()
    start_round()
    return
  end,
  spectator_join_team_button = function(event, param)
    choose_joining_gui(game.players[event.player_index])
  end,
  pick_team = function(event, param)
    local gui = event.element
    local player = game.players[event.player_index]
    if not (gui and gui.valid and player and player.valid) then return end
    local team = param.team
    if not team then return end
    set_player(player, team)

    for k, other_player in pairs (game.connected_players) do
      choose_joining_gui(other_player)
      choose_joining_gui(other_player)
      update_team_list_frame(other_player)
    end

  end,
  list_teams_button = function(event, param)
    local player = game.players[event.player_index]
    if not (player and player.valid) then return end
    local frame = script_data.elements.team_frame[player.index]
    if frame and frame.valid then
      frame.destroy()
      script_data.elements.team_frame[player.index] = nil
      return
    end
    local flow = mod_gui.get_frame_flow(player)
    frame = flow.add{type = "frame", style = mod_gui.frame_style, caption = {"teams"}, direction = "vertical"}
    frame.style.vertically_stretchable = false
    script_data.elements.team_frame[player.index] = frame
    update_team_list_frame(player)
  end,
  production_score_button = function(event, param)
    local gui = event.element
    local player = game.players[event.player_index]
    local frame = script_data.elements.production_score_frame[player.index]
    if frame and frame.valid then
      deregister_gui(frame)
      script_data.elements.production_score_frame[player.index] = nil
      frame.destroy()
      return
    end
    local flow = mod_gui.get_frame_flow(player)
    frame = flow.add{type = "frame", style = mod_gui.frame_style, caption = {"production_score"}, direction = "vertical"}
    script_data.elements.production_score_frame[player.index] = frame
    frame.style.vertically_stretchable = false
    local inner_frame = frame.add{type = "frame", style = "inside_shallow_frame", direction = "vertical"}
    script_data.elements.production_score_inner_frame[player.index] = inner_frame
    local flow = frame.add{type = "flow", direction = "horizontal"}
    flow.add{type = "label", caption = {"", {"recipe-calculator"}, {"colon"}}}
    local recipe_button = flow.add{type = "choose-elem-button", elem_type = "recipe", style = "slot_button"}
    register_gui_action(recipe_button, {type = "recipe_picker_elem_changed", frame = frame})
    script_data.elements.recipe_button[player.index] = recipe_button
    flow.style.vertical_align = "center"
    update_production_score_frame(player)
    recipe_picker_elem_update(player)
  end,
  recipe_picker_elem_changed = function(event, param)
    if event.name ~= defines.events.on_gui_elem_changed then return end
    local elem_button = event.element
    if not (elem_button and elem_button.valid) then return end
    local player = game.players[event.player_index]
    if not (player and player.valid) then return end
    script_data.selected_recipe[player.index] = elem_button.elem_value
    recipe_picker_elem_update(player)
  end,
  calculator_button_press = function(event, param)
    on_calculator_button_press(event, param)
  end,
  space_race_button = function(event, param)
    local player = game.players[event.player_index]
    local frame = script_data.elements.space_race_frame[player.index]
    if frame and frame.valid then
      frame.destroy()
      script_data.elements.space_race_frame[player.index] = nil
      return
    end
    local flow = mod_gui.get_frame_flow(player)
    frame = flow.add{type = "frame", style = mod_gui.frame_style, caption = {"space_race"}, direction = "vertical"}
    frame.style.vertically_stretchable = false
    script_data.elements.space_race_frame[player.index] = frame
    update_space_race_frame(player)
  end,
  kill_score_button = function(event, param)
    local player = game.players[event.player_index]
    local frame = script_data.elements.kill_score_frame[player.index]
    if frame and frame.valid then
      frame.destroy()
      script_data.elements.kill_score_frame[player.index] = nil
      return
    end
    local flow = mod_gui.get_frame_flow(player)
    frame = flow.add{type = "frame", style = mod_gui.frame_style, caption = {"kill_score"}, direction = "vertical"}
    frame.style.vertically_stretchable = false
    script_data.elements.kill_score_frame[player.index] = frame
    update_kill_score_frame(player)
  end,
  oil_harvest_button = function(event, param)
    local player = game.players[event.player_index]
    local frame = script_data.elements.oil_harvest_frame[player.index]
    if (frame and frame.valid) then
      frame.destroy()
      script_data.elements.oil_harvest_frame[player.index] = nil
      return
    end
    local flow = mod_gui.get_frame_flow(player)
    frame = flow.add{type = "frame", style = mod_gui.frame_style, caption = {"oil_harvest"}, direction = "vertical"}
    frame.style.vertically_stretchable = false
    script_data.elements.oil_harvest_frame[player.index] = frame
    update_oil_harvest_frame(player)
  end
}

function start_all_ready_preparations()
  local seconds = 10
  game.print({"everybody-ready", seconds})
  script_data.ready_start_tick = game.tick + (seconds * 60)
end

function add_new_config_gui(config_data, flow, admin)
  local bool_flow = flow.add{type = "flow", direction = "vertical"}
  bool_flow.style.horizontally_stretchable = true
  --local bottom_frame = flow.add{type = "frame", style = "bordered_frame_bottom"}
  local other_flow = flow.add{type = "table", column_count = 1, style = "bordered_table"}
  --other_flow.style.column_alignments[2] = "right"
  --other_flow.style.column_alignments[1] = "right"
  --other_flow.style.maximal_width = 350
  local items = game.item_prototypes
  for name, value in pairs (config_data) do
    if type(value) == "boolean" then
      local check = bool_flow.add{type = "checkbox", state = value, caption = config.localised_names[name] or {name}, ignored_by_interaction = not admin, tooltip = config.localised_tooltips[name] or {name.."_tooltip"}}
      register_gui_action(check, {type = "config_boolean_changed", config = config_data, key = name})
    end
    if tonumber(value) then
      local flow = other_flow.add{type = "table", column_count = 2}
      flow.style.column_alignments[2] = "right"
      local label = flow.add{type = "label", caption = config.localised_names[name] or {name}, tooltip = config.localised_tooltips[name] or {name.."_tooltip"}}
      label.style.horizontally_stretchable = true
      --local pusher = flow.add{type = "empty-widget"}
      --pusher.style.horizontally_stretchable = true
      if admin then
        text = flow.add{type = "textfield", text = value, numeric = true, allow_negative = false, allow_decimal = true, style = "slider_value_textfield"}
        text.style.maximal_width = 100
        register_gui_action(text, {type = "config_text_value_changed", config = config_data, key = name})
      else
        flow.add{type = "label", caption = value}
      end
    end
    if type(value) == "table" then
      local flow = other_flow.add{type = "table", column_count = 2}
      flow.style.column_alignments[2] = "right"

      local label = flow.add{type = "label", caption = config.localised_names[name] or {name}, tooltip = config.localised_tooltips[name] or {name.."_tooltip"}}
      label.style.horizontally_stretchable = true

      --local pusher = flow.add{type = "empty-widget"}
      --pusher.style.horizontally_stretchable = true
      if admin then
        local menu = flow.add{type = "drop-down", enabled = admin}
        register_gui_action(menu, {type = "config_dropdown_value_changed", value = value})
        local index
        for j, option in pairs (value.options) do
          if items[option] then
            menu.add_item(items[option].localised_name)
          else
            menu.add_item({option})
          end
          if option == value.selected then index = j end
        end
        menu.selected_index = index or 1
      else
        flow.add{type = "label", caption = (items[value.selected] and items[value.selected].localised_name) or {value.selected}}
      end
    end
  end
  local pusher = other_flow.add{type = "empty-widget"}
  pusher.style.vertically_stretchable = true
end

function add_victory_gui(config_data, flow, admin)
  local flow = flow.add{type = "table", column_count = 1, style = "bordered_table"}
  flow.style.width = 500
  flow.style.column_alignments[1] = "left"

  flow.add{type = "label", caption = {"victory-conditions"}, style = "caption_label"}
  for name, victory in pairs (config_data) do

    local inner_flow = flow.add{type = "flow"}
    inner_flow.style.height = 28
    inner_flow.style.vertical_align = "center"

    local check = inner_flow.add{type = "checkbox", state = victory.active, caption = config.localised_names[name] or {name}, ignored_by_interaction = not admin, tooltip = config.localised_tooltips[name] or {name.."_tooltip"}}
    check.style.width = 150
    check.style.vertical_align = "center"
    register_gui_action(check, {type = "victory_config_boolean_changed", config = config_data, key = name})

    for extra_name, extra in pairs (victory) do
      if extra_name ~= "active" then

        add_pusher(inner_flow)
        local line = inner_flow.add{type = "line", direction = "vertical"}
        line.style.vertically_stretchable = true

        local label = inner_flow.add{type = "label", caption = config.localised_names[extra_name] or {extra_name}, tooltip = config.localised_tooltips[extra_name] or {extra_name.."_tooltip"}}
        label.style.width = 180

        if admin then
          text = inner_flow.add{type = "textfield", text = extra, numeric = true, allow_negative = false, allow_decimal = false, style = "slider_value_textfield"}
          register_gui_action(text, {type = "config_text_value_changed", config = victory, key = extra_name})
        else
          inner_flow.add{type = "label", caption = extra}
        end

      end
    end

  end
end

function add_team_tab(tab_pane)
  local tab = tab_pane.add{type = "tab", caption = {"team-settings"}}
  local group = tab_pane.add{type = "flow"}
  tab_pane.add_tab(tab, group)
  local player = game.get_player(tab_pane.player_index)
  script_data.elements.team_tab[player.index] = group
  update_team_tab(player)
end

function update_team_tab(player)
  local admin = player.admin
  local holding_table_1 = script_data.elements.team_tab[player.index]
  if not (holding_table_1 and holding_table_1.valid) then return end
  holding_table_1.clear()

  local team_lobby = holding_table_1.add{type = "flow", direction = "vertical"}
  team_lobby.style.vertically_stretchable = true

  local title_flow = team_lobby.add{type = "frame", style = "bordered_frame"}
  title_flow.style.vertical_align = "center"
  local label = title_flow.add{type = "label", caption = {"teams"}, style = "caption_label"}
  label.style.height = 28
  label.style.vertical_align = "center"

  if admin then
    add_pusher(title_flow)
    local button = title_flow.add{type = "button", caption = {"add-team"}, tooltip = {"add-team-tooltip"}, enabled = #script_data.config.teams < 24}
    register_gui_action(button, {type = "new_team", frame = flow})
  end

  local scroll = team_lobby.add{type = "scroll-pane", direction = "vertical", style = "scroll_pane_in_shallow_frame"}
  scroll.style.maximal_height = 440 + 20
  local current_team = script_data.team_players[player.index]

  for k, team in pairs (script_data.config.teams) do
    add_team_to_new_flow(team, scroll, current_team, admin)
  end

  local ready_data = script_data.ready_players
  local str = ""
  local first = true
  for k, player in pairs (game.connected_players) do
    if not script_data.team_players[player.index] then
      if first then
        first = false
      else
        str = str.. ", "
      end
      if ready_data[player.index] then
        str = str .. green(player.name)
      else
        str = str .. red(player.name)
      end
    end
  end

  if first then str = {"none"} end

  local pusher = team_lobby.add{type = "empty-widget"}
  pusher.style.vertically_stretchable = true
  local bottom_frame = team_lobby.add{type = "frame", style = "bordered_frame"}
  bottom_frame.add{type = "label", caption = {"unassigned-players",  str}}
  bottom_frame.style.horizontally_stretchable = true

  local team_settings = holding_table_1.add{type = "frame", direction = "vertical", style = "bordered_frame"}
  team_settings.add{type = "label", caption = {"team-settings"}, style = "caption_label"}
  team_settings.style.vertically_stretchable = true
  team_settings.style.horizontally_stretchable = true
  local line = team_settings.add{type = "line", direction = "horizontal"}
  line.style.horizontally_stretchable = true

  add_new_config_gui(script_data.config.team_config, team_settings, admin)

end

function add_game_tab(tab_pane)
  local tab = tab_pane.add{type = "tab", caption = {"game-settings"}}
  local group = tab_pane.add{type = "flow"}
  tab_pane.add_tab(tab, group)
  local player = game.get_player(tab_pane.player_index)
  script_data.elements.game_tab[player.index] = group
  update_game_tab(player)
end

function update_game_tab(player)
  local admin = player.admin
  local holding_table_2 = script_data.elements.game_tab[player.index]
  if not (holding_table_2 and holding_table_2.valid) then return end
  holding_table_2.clear()
  local game_settings = holding_table_2.add{type = "table", column_count = 1, style = "bordered_table"}
  game_settings.add{type = "label", caption = {"game-settings"}, style = "caption_label"}
  game_settings.style.vertically_stretchable = true
  game_settings.style.horizontally_stretchable = true
  local inner_table = game_settings.add{type = "flow", column_count = 2}

  add_new_config_gui(script_data.config.game_config, inner_table, admin)

  local other_flow = holding_table_2.add{type = "flow", direction = "vertical"}
  other_flow.style.vertically_stretchable = true
  other_flow.style.horizontally_stretchable = false

  local victory = other_flow.add{type = "flow", direction = "vertical"}
  --victory.style.vertically_stretchable = true
  add_victory_gui(script_data.config.victory, victory, admin)
  local disable_items = other_flow.add{type = "flow"}
  disable_items.style.vertically_stretchable = true
  disable_items.style.horizontally_stretchable = true
  create_disable_frame(disable_items)

end

function create_config_gui(player)
  if not (player and player.valid and player.connected) then return end
  local old = script_data.elements.config[player.index]
  if (old and old.valid) then
    deregister_gui(old)
    old.destroy()
  end
  local admin = player.admin
  local gui = player.gui.screen
  local upper_frame = gui.add{type = "frame", caption = {"pvp-configuration"}, direction = "vertical"}
  --upper_frame.style.minimal_width = player.display_resolution.width * 0.75 / player.display_scale
  script_data.elements.config[player.index] = upper_frame
  upper_frame.style.vertically_stretchable = false
  local deep = upper_frame.add{type = "frame", style = "inside_deep_frame_for_tabs", direction = "vertical"}
  local tab_pane = deep.add{type = "tabbed-pane"}
  tab_pane.style.horizontally_stretchable = true
  tab_pane.selected_tab_index = 1
  tab_pane.style.maximal_height = 1080 * 0.8
  add_team_tab(tab_pane)
  add_game_tab(tab_pane)
  add_balance_tab(tab_pane)
  add_starting_chest_tab(tab_pane)

  local footer = deep.add{type = "frame", style = "subfooter_frame"}
  footer.style.horizontally_stretchable = true
  if admin then
    register_gui_action(footer.add{type = "sprite-button", sprite = "utility/import", tooltip = {"gui-blueprint-library.import-string"}, style = "tool_button"}, {type = "pvp_import"})
  end
  register_gui_action(footer.add{type = "sprite-button", sprite = "utility/export", tooltip = {"gui.export-to-string"}, style = "tool_button"}, {type = "pvp_export"})

  local button_flow = upper_frame.add{type = "flow", style = "dialog_buttons_horizontal_flow"}
  button_flow.style.vertical_align = "center"

  local pusher = button_flow.add{type = "empty-widget", style = "draggable_space_with_no_left_margin"}
  pusher.style.horizontally_stretchable = true
  pusher.style.vertically_stretchable = true
  pusher.drag_target = upper_frame
  local ready = script_data.ready_players[player.index] or false
  local ready_up = button_flow.add{type = "checkbox", caption = {"ready"}, state = ready}
  ready_up.style.right_padding = 8

  register_gui_action(ready_up, {type = "ready_up"})
  local start_button = button_flow.add{type = "button", style = "confirm_button", caption = {"start-round"}, enabled = admin}
  start_button.style.minimal_width = 250
  register_gui_action(start_button, {type = "start_round"})
  upper_frame.auto_center = true
end

function end_round(admin)
  destroy_config_for_all()
  for k, player in pairs (game.players) do
    player.force = game.forces.player
    player.tag = ""
    destroy_player_gui(player)
    if player.connected then
      if player.ticks_to_respawn then
        player.ticks_to_respawn = nil
      end
      local character = player.character
      player.character = nil
      if character then character.destroy() end
      player.set_controller{type = defines.controllers.spectator}
      player.teleport({0,1000}, get_lobby_surface())
      create_config_gui(player)
    end
  end
  if script_data.surface and script_data.surface.valid then
    game.delete_surface(script_data.surface)
  end
  if admin then
    game.print({"admin-ended-round", admin.name})
  end
  script_data.setup_finished = false
  script_data.check_starting_area_generation = false
  script_data.average_score = nil
  script_data.scores = nil
  script_data.exclusion_map = nil
  script_data.protected_teams = nil
  script_data.check_base_exclusion = nil
  script_data.oil_harvest_scores = nil
  script_data.production_scores = nil
  script_data.rocket_scores = nil
  script_data.kill_scores = nil
  script_data.last_defcon_tick = nil
  script_data.next_defcon_tech = nil
  script_data.silos = nil
  script.raise_event(events.on_round_end, {})
end

game_mode_buttons = function() return
  {
    ["production_score"] = {type = "button", caption = {"production_score"}, action = "production_score_button", style = mod_gui.button_style},
    ["oil_harvest"] = {type = "button", caption = {"oil_harvest"}, action = "oil_harvest_button", style = mod_gui.button_style},
    ["kill_score"] = {type = "button", caption = {"kill_score"}, action = "kill_score_button", style = mod_gui.button_style},
    ["space_race"] = {type = "button", caption = {"space_race"}, action = "space_race_button", style = mod_gui.button_style}
  }
end

function init_player_gui(player)
  destroy_player_gui(player)

  if script_data.progress then
    update_progress_bar()
    return
  end

  if script_data.setup_finished == false then
    create_config_gui(player)
    return
  end

  if player.force.name == "player" then
    choose_joining_gui(player)
    return
  end

  local button_flow = mod_gui.get_button_flow(player)

  local list_teams_button = button_flow.add{type = "button", caption = {"teams"}, style = mod_gui.button_style}
  register_gui_action(list_teams_button, {type = "list_teams_button"})
  script_data.elements.team_list_button[player.index] = list_teams_button

  for name, button in pairs (game_mode_buttons()) do
    if not script_data.elements[name] then
      script_data.elements[name] = {}
    end
    if script_data.config.victory[name].active then
      local element = button_flow.add(button)
      register_gui_action(element, {type = button.action})
      script_data.elements[name][player.index] = element
    end
  end

  if player.admin then
    local admin_button = button_flow.add{type = "button", caption = {"admin"}, style = mod_gui.button_style}
    register_gui_action(admin_button, {type = "admin_button"})
    script_data.elements.admin_button[player.index] = admin_button
  end

  if player.force.name == "neutral" then
    local spectate_button = button_flow.add{type = "button", caption = {"join-team"}, style = mod_gui.button_style}
    register_gui_action(spectate_button, {type = "spectator_join_team_button"})
    script_data.elements.spectate_button[player.index] = spectate_button
  end

end

function get_color(team, lighten)
  local index = script_data.config.color_map[team.color]
  if not index then
    --Unknown color
    team.color = script_data.config.colors[math.random(#script_data.config.colors)].name
    index = script_data.config.color_map[team.color]
  end
  local c = script_data.config.colors[index].color
  if lighten then
    return {r = 1 - (1 - c.r) * 0.5, g = 1 - (1 - c.g) * 0.5, b = 1 - (1 - c.b) * 0.5, a = 1}
  end
  return c
end

function add_player_list_gui(force, gui)
  if not (force and force.valid) then return end
  if #force.players == 0 then
    gui.add{type = "label", caption = {"none"}}
    return
  end
  local scroll = gui.add{type = "scroll-pane", style = "scroll_pane_in_shallow_frame"}
  scroll.style.maximal_height = 120
  local name_table = scroll.add{type = "table", column_count = 1}
  name_table.style.vertical_spacing = 0
  local added = {}
  local first = true
  if #force.connected_players > 0 then
    local online_names = ""
    for k, player in pairs (force.connected_players) do
      if not first then
        online_names = online_names..", "
      end
      first = false
      online_names = online_names..player.name
      added[player.name] = true
    end
    local online_label = name_table.add{type = "label", caption = {"online", online_names}}
    online_label.style.single_line = false
    online_label.style.maximal_width = 180
  end
  first = true
  if #force.players > #force.connected_players then
    local offline_names = ""
    for k, player in pairs (force.players) do
      if not added[player.name] then
      if not first then
        offline_names = offline_names..", "
      end
      first = false
      offline_names = offline_names..player.name
      added[player.name] = true
      end
    end
    local offline_label = name_table.add{type = "label", caption = {"offline", offline_names}}
    offline_label.style.single_line = false
    offline_label.style.font_color = {r = 0.7, g = 0.7, b = 0.7}
    offline_label.style.maximal_width = 180
  end
end

function set_player(player, team, mute)
  local force = game.forces[team.name]
  local old_force = player.force
  local surface = script_data.surface
  if not surface.valid then return end
  local position = surface.find_non_colliding_position("character", force.get_spawn_position(surface), get_starting_area_radius(true), 2)
  if not position then
    player.print({"cant-find-position"})
    choose_joining_gui(player)
    return
  end
  local character = player.surface == surface and player.character
  if character then
    character.teleport(position)
  else
    character = surface.create_entity{name = "character", position = position, force = force}
  end
  player.force = force
  player.teleport(position, surface)

  player.character = nil
  player.set_controller
  {
    type = defines.controllers.character,
    character = character
  }

  player.color = get_color(team)
  player.chat_color = get_color(team, true)
  player.tag = "["..force.name.."]"

  init_player_gui(player)
  set_team(player.index, team)

  for k, other_player in pairs (game.connected_players) do
    choose_joining_gui(other_player)
    choose_joining_gui(other_player)
    update_team_list_frame(other_player)
  end

  local artillery_remote = script_data.config.prototypes.artillery_remote
  if script_data.config.game_config.team_artillery and script_data.config.game_config.give_artillery_remote and game.item_prototypes[artillery_remote] then
    player.insert(artillery_remote)
  end
  config.give_equipment(player)
  balance.apply_character_modifiers(player)

  if not mute then
    game.print({"joined", player.name, player.force.name})
  end

  check_force_protection(force)
  check_force_protection(old_force)
  script.raise_event(events.on_player_joined_team, {player_index = player.index, team = team, force = force})
end

function choose_joining_gui(player)
  local frame = script_data.elements.join[player.index]
  if (frame and frame.valid) then
    deregister_gui(frame)
    frame.destroy()
    return
  end
  local teams = get_eligible_teams(player)
  if not teams then return end
  local gui = player.gui.screen
  local frame = gui.add{type = "frame", direction = "vertical"}

  local title_flow = frame.add{type = "flow", direction = "horizontal"}
  title_flow.style.horizontally_stretchable = true
  title_flow.style.horizontal_spacing = 8

  local title_label = title_flow.add{type = "label", caption = {"pick-join"}, style = "frame_title"}
  title_label.drag_target = frame

  local title_pusher = title_flow.add{type = "empty-widget", style = "draggable_space_header"}
  title_pusher.style.height = 24
  title_pusher.style.horizontally_stretchable = true
  title_pusher.drag_target = frame

  --If they are on player force, it means they aren't on a proper team already, don't let them close the choose team frame.
  if player.force.name ~= "player" then
    local title_close_button = title_flow.add{type = "sprite-button", style = "frame_action_button", sprite = "utility/close_white"}
    register_gui_action(title_close_button, {type = "spectator_join_team_button"})
  end

  script_data.elements.join[player.index] = frame
  local inner_frame = frame.add{type = "frame", style = "inside_shallow_frame", direction = "vertical"}
  local pick_join_table = inner_frame.add{type = "table", column_count = 4, style = "bordered_table"}
  pick_join_table.style.margin = 4
  pick_join_table.style.column_alignments[2] = "center"
  pick_join_table.style.column_alignments[3] = "center"
  pick_join_table.add{type = "label", caption = {"team-name"}}.style.font = "default-semibold"
  pick_join_table.add{type = "label", caption = {"players"}}.style.font = "default-semibold"
  pick_join_table.add{type = "label", caption = {"team-number"}}.style.font = "default-semibold"
  pick_join_table.add{type = "label"}
  for k, team in pairs (teams) do
    local force = game.forces[team.name]
    if force then
      local name = pick_join_table.add{type = "label", caption = force.name}
      name.style.font = "default-semibold"
      name.style.font_color = get_color(team, true)
      add_player_list_gui(force, pick_join_table)
      local caption
      if tonumber(team.team) then
        caption = team.team
      elseif team.team:find("?") then
        caption = team.team:gsub("?", "")
      else
        caption = team.team
      end
      pick_join_table.add{type = "label", caption = caption}
      local join_button = pick_join_table.add{type = "button", caption = {"join"}}
      register_gui_action(join_button, {type = "pick_team", team = team})
    end
  end
  local button_flow = frame.add{type = "flow", direction = "horizontal", style = "dialog_buttons_horizontal_flow"}
  register_gui_action(button_flow.add{type = "button", caption = {"join-spectator"}}, {type = "join_spectator", frame = frame})
  register_gui_action(button_flow.add{type = "button", caption = {"join-random"}}, {type = "join_random", frame = frame})
  local drag = button_flow.add{type = "empty-widget", style = "draggable_space_with_no_right_margin"}
  drag.style.horizontally_stretchable = true
  drag.style.vertically_stretchable = true
  drag.drag_target = frame
  frame.auto_center = true
end

function update_balance_tab(player)
  local inner = script_data.elements.balance[player.index]
  if not (inner and inner.valid) then return end
  inner.clear()
  local scrollpane = inner.add{type = "scroll-pane", style = "scroll_pane_in_shallow_frame"}
  local big_table = scrollpane.add{type = "table", column_count = 5, direction = "horizontal"}
  big_table.style.horizontally_stretchable = true
  local entities = game.entity_prototypes
  local ammos = game.ammo_category_prototypes
  local admin = player.admin
  local modifier_list = script_data.config.modifier_list
  if not modifier_list then
    balance.init()
    modifier_list = script_data.config.modifier_list
  end
  for modifier_name, array in pairs (modifier_list) do
    local flow = big_table.add{type = "table", style = "bordered_table", column_count = 1}
    flow.style.vertically_stretchable = true
    flow.style.horizontally_stretchable = true
    flow.add{type = "label", style = "caption_label", caption = {modifier_name}}
    local inner = flow.add{type = "flow", direction = "vertical"}
    inner.style.vertically_stretchable = true
    local table = inner.add{type = "table", column_count = 2}
    table.style.column_alignments[1] = "left"
    table.style.column_alignments[2] = "right"
    for name, modifier in pairs (array) do
      if modifier_name == "ammo_damage_modifier" then
        local string = "ammo-category-name."..name
        table.add{type = "label", caption = ammos[name].localised_name}
      elseif modifier_name == "gun_speed_modifier" then
        table.add{type = "label", caption = ammos[name].localised_name}
      elseif modifier_name == "turret_attack_modifier" then
        table.add{type = "label", caption = entities[name].localised_name}
      elseif modifier_name == "character_modifiers" then
        table.add{type = "label", caption = {name}}
      elseif modifier_name == "force_modifiers" then
        table.add{type = "label", caption = {name}}
      end
      if admin then
        local input = table.add{type = "textfield", numeric = true, allow_decimal = true, allow_negative = false, style = "slider_value_textfield"}
        register_gui_action(input, {type = "balance_textfield_changed", modifier = modifier_name, key = name, no_below_100 = (modifier_name == "force_modifiers")})
        input.text = tostring((modifier * 100) + 100).."%"
        input.style.maximal_width = 60
      else
        table.add{type = "label", caption = tostring((modifier * 100) + 100).."%"}
      end
    end
  end
end

function add_balance_tab(tab_pane)
  local tab = tab_pane.add{type = "tab", caption = {"balance-options"}}
  local inner = tab_pane.add{type = "flow"}
  inner.style.horizontally_stretchable = true
  tab_pane.add_tab(tab, inner)
  local player = game.get_player(tab_pane.player_index)
  script_data.elements.balance[player.index] = inner
  update_balance_tab(player)
end

function create_disable_frame(gui)
  local inner = gui.add{type = "table", style = "bordered_table", column_count = 1}
  inner.add{type = "label", caption = {"disabled-items"}, style = "caption_label"}
  local frame = inner.add{type = "frame", style = "filter_scroll_pane_background_frame"}
  frame.style.width = 12 * 40
  local disable_table = frame.add{type = "table", column_count = 12, style = "filter_slot_table"}
  local items = game.item_prototypes
  local player = game.players[gui.player_index]
  local admin = player.admin
  if script_data.config.disabled_items then
    for item, bool in pairs (script_data.config.disabled_items) do
      local prototype = items[item]
      if prototype then
        if admin then
          local choose = disable_table.add{type = "choose-elem-button", elem_type = "item", style = "recipe_slot_button"}
          choose.elem_value = item
          register_gui_action(choose, {type = "disable_elem_changed"})
        else
          local icon = disable_table.add{type = "sprite", sprite = "item/"..item, tooltip = prototype.localised_name}
          icon.style.width = 32
          icon.style.height = 32
        end
      end
    end
  end
  if admin then
    local choose = disable_table.add{type = "choose-elem-button", elem_type = "item", style = "recipe_slot_button"}
    register_gui_action(choose, {type = "disable_elem_changed"})
  end
end

function start_round()

  game.reset_time_played()

  destroy_config_for_all()

  script_data.random = game.create_random_generator(script_data.config.game_config.seed)
  script_data.ready_start_tick = nil
  script_data.setup_finished = false
  script_data.team_won = false

  create_next_surface()
  setup_teams()
  chart_starting_area_for_force_spawns()
  set_evolution_factor()
  set_difficulty()

end

function get_eligible_teams(player)
  local limit = script_data.config.team_config.max_players
  local teams = {}
  for k, team in pairs (script_data.config.teams) do
    local force = game.forces[team.name]
    if force then
      if limit <= 0 or #force.connected_players < limit or player.admin then
        insert(teams, team)
      end
    end
  end
  if #teams == 0 then
    spectator_join(player)
    player.print({"no-space-available"})
    return
  end
  return teams
end

function destroy_config_for_all()

  for name, frames in pairs (script_data.elements) do
    for k, frame in pairs (frames) do
      if (frame and frame.valid) then
        deregister_gui(frame)
        frame.destroy()
      end
    end
    script_data.elements[name] = {}
  end

  script_data.ready_players = {}
end

function set_evolution_factor()
  local n = script_data.config.team_config.evolution_factor
  if n >= 1 then
    n = 1
  end
  if n <= 0 then
    n = 0
  end
  for k, force in pairs (game.forces) do
    force.evolution_factor = n
  end
  script_data.config.team_config.evolution_factor = n
end

function set_difficulty()
  game.difficulty_settings.technology_price_multiplier = script_data.config.team_config.technology_price_multiplier or 1
end

function spectator_join(player)
  local character = player.character
  player.set_controller{type = defines.controllers.spectator}
  if character then character.die() end
  player.force = "neutral"
  player.teleport(script_data.spawn_offset, script_data.surface)
  player.tag = ""
  player.chat_color = {r = 1, g = 1, b = 1, a = 1}
  init_player_gui(player)
  game.print({"joined-spectator", player.name})
  set_team(player.index)
end

function update_team_list_frame(player)
  if not (player and player.valid) then return end
  local frame = script_data.elements.team_frame[player.index]
  if not (frame and frame.valid) then return end
  frame.clear()
  local inner = frame.add{type = "frame", style = "inside_shallow_frame"}
  local team_table = inner.add{type = "table", column_count = 2, style = "bordered_table"}
  team_table.style.margin = 4
  team_table.add{type = "label", caption = {"team-name"}, style = "bold_label"}
  team_table.add{type = "label", caption = {"players"}, style = "bold_label"}
  for k, team in pairs (script_data.config.teams) do
    local force = game.forces[team.name]
    if force then
      local label = team_table.add{type = "label", caption = team.name, style = "description_label"}
      label.style.font_color = get_color(team, true)
      add_player_list_gui(force, team_table)
    end
  end
end

function format_time(ticks)
  local hours = math.floor(ticks / (60 * 60 * 60))
  ticks = ticks - hours * (60 * 60 * 60)
  local minutes = math.floor(ticks / (60 * 60))
  ticks = ticks - minutes * (60 * 60)
  local seconds = math.floor(ticks / 60)
  if hours > 0 then
    return string.format("%d:%02d:%02d", hours, minutes, seconds)
  else
    return string.format("%d:%02d", minutes, seconds)
  end
end

function get_time_left()
  if not script_data.round_start_tick then return "Invalid" end
  if not script_data.config.game_config.time_limit then return "Invalid" end
  return format_time((math.max(script_data.round_start_tick + (script_data.config.game_config.time_limit * 60 * 60) - game.tick, 0)))
end

function update_production_score_frame(player)
  local frame = script_data.elements.production_score_inner_frame[player.index]
  if not (frame and frame.valid) then return end
  frame.clear()

  local subheader = frame.add{type = "frame", style = "subheader_frame"}
  subheader.style.horizontally_stretchable = true
  subheader.style.vertical_align = "center"
  if script_data.config.victory.production_score.required_production_score > 0 then
    subheader.add{type = "label", style = "subheader_label", caption = {"", {"required_production_score"}, {"colon"}, " ", util.format_number(script_data.config.victory.production_score.required_production_score)}}
  end
  if script_data.config.game_config.time_limit > 0 then
    if next(subheader.children) then
      subheader.add{type = "line", direction = "vertical"}
    end
    subheader.add{type = "label", style = not next(subheader.children) and "subheader_label" or nil, caption = {"time_left", get_time_left()}}
  end
  if not next(subheader.children) then subheader.destroy() end

  local information_table = frame.add{type = "table", column_count = 4, style = "bordered_table"}
  information_table.style.margin = 4
  information_table.style.column_alignments[3] = "right"
  information_table.style.column_alignments[4] = "right"

  for k, caption in pairs ({"", "team-name", "score", "score_per_minute"}) do
    local label = information_table.add{type = "label", caption = {caption}, tooltip = {caption.."_tooltip"}}
    label.style.font = "default-bold"
  end
  local team_map = {}
  for k, team in pairs (script_data.config.teams) do
    team_map[team.name] = team
  end
  local average_score = script_data.average_score
  if not average_score then return end
  local rank = 1
  for name, score in spairs (script_data.production_scores, function(t, a, b) return t[b] < t[a] end) do
    if not average_score[name] then
      average_score = nil
      return
    end
    if team_map[name] then
      local position = information_table.add{type = "label", caption = "#"..rank}
      if name == player.force.name then
        position.style.font = "default-semibold"
        position.style.font_color = {r = 1, g = 1}
      end
      local label = information_table.add{type = "label", caption = name}
      label.style.font = "default-semibold"
      label.style.font_color = get_color(team_map[name], true)
      information_table.add{type = "label", caption = util.format_number(score)}
      local delta_score = (score - (average_score[name] / statistics_period)) * (60 / statistics_period) * 2
      local delta_label = information_table.add{type = "label", caption = util.format_number(math.floor(delta_score))}
      if delta_score < 0 then
        delta_label.style.font_color = {r = 1, g = 0.2, b = 0.2}
      end
      rank = rank + 1
    end
  end
end

function update_oil_harvest_frame(player)

  local frame = script_data.elements.oil_harvest_frame[player.index]
  if not (frame and frame.valid) then
    return
  end
  frame.clear()

  local inner_frame = frame.add{type = "frame", style = "inside_shallow_frame", direction = "vertical"}

  local subheader = inner_frame.add{type = "frame", style = "subheader_frame"}
  subheader.style.horizontally_stretchable = true
  subheader.style.vertical_align = "center"

  if script_data.config.victory.oil_harvest.required_oil > 0 then
    subheader.add{type = "label", style = "subheader_label", caption = {"", {"required_oil"}, {"colon"}, " ", util.format_number(script_data.config.victory.oil_harvest.required_oil)}}
  end

  if script_data.config.game_config.time_limit > 0 then
    if next(subheader.children) then
      subheader.add{type = "line", direction = "vertical"}
    end
    subheader.add{type = "label", style = not next(subheader.children) and "subheader_label" or nil, caption = {"time_left", get_time_left()}}
  end

  if not next(subheader.children) then subheader.destroy() end

  local information_table = inner_frame.add{type = "table", column_count = 3, style = "bordered_table"}
  information_table.style.margin = 4
  information_table.style.column_alignments[3] = "right"

  for k, caption in pairs ({"", "team-name", "oil_harvest"}) do
    local label = information_table.add{type = "label", caption = {caption}}
    label.style.font = "default-bold"
  end
  local team_map = {}
  for k, team in pairs (script_data.config.teams) do
    team_map[team.name] = team
  end
  if not script_data.oil_harvest_scores then
    script_data.oil_harvest_scores = {}
  end
  local rank = 1
  for name, score in spairs (script_data.oil_harvest_scores, function(t, a, b) return t[b] < t[a] end) do
    if team_map[name] then
      local position = information_table.add{type = "label", caption = "#"..rank}
      if name == player.force.name then
        position.style.font = "default-semibold"
        position.style.font_color = {r = 1, g = 1}
      end
      local label = information_table.add{type = "label", caption = name}
      label.style.font = "default-semibold"
      label.style.font_color = get_color(team_map[name], true)
      information_table.add{type = "label", caption = util.format_number(math.floor(score))}
      rank = rank + 1
    end
  end
end

function update_kill_score_frame(player)

  local frame = script_data.elements.kill_score_frame[player.index]
  if not (frame and frame.valid) then
    return
  end
  frame.clear()

  local inner_frame = frame.add{type = "frame", style = "inside_shallow_frame", direction = "vertical"}

  local subheader = inner_frame.add{type = "frame", style = "subheader_frame"}
  subheader.style.horizontally_stretchable = true

  if script_data.config.victory.kill_score.required_kill_score > 0 then
    subheader.add{type = "label", style = "subheader_label", caption = {"", {"required_kill_score"}, {"colon"}, " ", util.format_number(script_data.config.victory.kill_score.required_kill_score)}}
  end

  if script_data.config.game_config.time_limit > 0 then
    if next(subheader.children) then
      subheader.add{type = "line", direction = "vertical"}
    end
    subheader.add{type = "label", style = not next(subheader.children) and "subheader_label" or nil, caption = {"time_left", get_time_left()}}
  end

  if not next(subheader.children) then subheader.destroy() end

  local information_table = inner_frame.add{type = "table", column_count = 3, style = "bordered_table"}
  information_table.style.margin = 4
  information_table.style.column_alignments[3] = "right"

  for k, caption in pairs ({"", "team-name", "kill_score"}) do
    local label = information_table.add{type = "label", caption = {caption}}
    label.style.font = "default-bold"
  end
  local team_map = {}
  for k, team in pairs (script_data.config.teams) do
    team_map[team.name] = team
  end
  local scores = get_kill_scores()
  local rank = 1
  for name, score in spairs (scores, function(t, a, b) return t[b] < t[a] end) do
    if team_map[name] then
      local position = information_table.add{type = "label", caption = "#"..rank}
      if name == player.force.name then
        position.style.font = "default-semibold"
        position.style.font_color = {r = 1, g = 1}
      end
      local label = information_table.add{type = "label", caption = name}
      label.style.font = "default-semibold"
      label.style.font_color = get_color(team_map[name], true)
      information_table.add{type = "label", caption = util.format_number(math.floor(score))}
      rank = rank + 1
    end
  end
end

function update_space_race_frame(player)
  local frame = script_data.elements.space_race_frame[player.index]
  if not (frame and frame.valid) then
    return
  end
  frame.clear()

  local inner_frame = frame.add{type = "frame", style = "inside_shallow_frame", direction = "vertical"}

  local subheader = inner_frame.add{type = "frame", style = "subheader_frame"}
  subheader.style.horizontally_stretchable = true
  subheader.style.vertical_align = "center"

  if script_data.config.victory.space_race.required_rockets_sent > 0 then
    subheader.add{type = "label", style = "subheader_label", caption = {"", {"required_rockets_sent"}, {"colon"}, " ", util.format_number(script_data.config.victory.space_race.required_rockets_sent)}}
  end

  if script_data.config.game_config.time_limit > 0 then
    if next(subheader.children) then
      subheader.add{type = "line", direction = "vertical"}
    end
    subheader.add{type = "label", style = not next(subheader.children) and "subheader_label" or nil, caption = {"time_left", get_time_left()}}
  end

  if not next(subheader.children) then subheader.destroy() end

  local information_table = inner_frame.add{type = "table", column_count = 3, style = "bordered_table"}
  information_table.style.margin = 4
  information_table.style.column_alignments[3] = "right"

  for k, caption in pairs ({"", "team-name", "rockets_sent"}) do
    local label = information_table.add{type = "label", caption = {caption}}
    label.style.font = "default-bold"
  end
  local colors = {}
  local team_map = {}
  for k, team in pairs (script_data.config.teams) do
    colors[team.name] = get_color(team, true)
    team_map[team.name] = team
  end
  local rank = 1

  for name, score in spairs (get_rocket_scores(), function(t, a, b) return t[b] < t[a] end) do
    if team_map[name] then
      local position = information_table.add{type = "label", caption = "#"..rank}
      if name == player.force.name then
        position.style.font = "default-semibold"
        position.style.font_color = {r = 1, g = 1}
      end
      local label = information_table.add{type = "label", caption = name}
      label.style.font = "default-semibold"
      label.style.font_color = colors[name]
      information_table.add{type = "label", caption = util.format_number(score)}
      rank = rank + 1
    end
  end
end

function update_teams_names()
  local names = {}
  for k, team in pairs (script_data.config.teams) do
    names[team.name] = true
  end
  script_data.team_names = names
end

function setup_teams()

  local old_team_names = script_data.team_names
  update_teams_names()

  for name, bool in pairs (old_team_names) do
    if not script_data.team_names[name] then
      game.merge_forces(name, "player")
    end
  end

  for k, team in pairs (script_data.config.teams) do
    local new_team
    if game.forces[team.name] then
      new_team = game.forces[team.name]
    else
      new_team = game.create_force(team.name)
    end
    new_team.reset()
    new_team.set_spawn_position(script_data.spawn_positions[k], script_data.surface)
    set_random_team(team)
  end
  for k, team in pairs (script_data.config.teams) do
    local force = game.forces[team.name]
    set_diplomacy(team)
    setup_research(force)
    balance.disable_combat_technologies(force)
    force.reset_technology_effects()
    balance.apply_combat_modifiers(force)
  end
  disable_items_for_all()
end

function disable_items_for_all()
  if not script_data.config.disabled_items then return end
  local items = game.item_prototypes
  local recipes = game.recipe_prototypes
  local product_map = {}
  for k, recipe in pairs (recipes) do
    for k, product in pairs (recipe.products) do
      if not product_map[product.name] then
        product_map[product.name] = {}
      end
      insert(product_map[product.name], recipe)
    end
  end

  local recipes_to_disable = {}
  for name, k in pairs (script_data.config.disabled_items) do
    local mapping = product_map[name]
    if mapping then
      for k, recipe in pairs (mapping) do
        recipes_to_disable[recipe.name] = true
      end
    end
  end
  for k, force in pairs (game.forces) do
    for name, bool in pairs (recipes_to_disable) do
      force.recipes[name].enabled = false
    end
  end
end

function check_technology_for_disabled_items(event)
  if not script_data.config.disabled_items then return end
  local disabled_items = script_data.config.disabled_items
  local technology = event.research
  local recipes = technology.force.recipes
  for k, effect in pairs (technology.effects) do
    if effect.type == "unlock-recipe" then
      for k, product in pairs (recipes[effect.recipe].products) do
        if disabled_items[product.name] then
          recipes[effect.recipe].enabled = false
        end
      end
    end
  end
end

function set_random_team(team)
  if tonumber(team.team) then return end
  if team.team == "-" then return end
  team.team = "?"..math.random(#script_data.config.teams)
end

function set_diplomacy(team)
  local force = game.forces[team.name]
  if not force or not force.valid then return end
  local team_number
  if tonumber(team.team) then
    team_number = team.team
  elseif team.team:find("?") then
    team_number = team.team:gsub("?", "")
    team_number = tonumber(team_number)
  else
    team_number = "Don't match me"
  end
  for k, other_team in pairs (script_data.config.teams) do
    if game.forces[other_team.name] then
      local other_number
      if tonumber(other_team.team) then
        other_number = other_team.team
      elseif other_team.team:find("?") then
        other_number = other_team.team:gsub("?", "")
        other_number = tonumber(other_number)
      else
        other_number = "Okay i won't match"
      end
      if other_number == team_number then
        force.set_cease_fire(other_team.name, true)
        force.set_friend(other_team.name, true)
      else
        force.set_cease_fire(other_team.name, false)
        force.set_friend(other_team.name, false)
      end
    end
  end
end

function set_team_together_spawns(surface)
  local grouping = {}
  for k, team in pairs (script_data.config.teams) do
    local team_number
    if tonumber(team.team) then
      team_number = team.team
    elseif team.team:find("?") then
      team_number = team.team:gsub("?", "")
      team_number = tonumber(team_number)
    else
      team_number = "-"
    end
    if tonumber(team_number) then
      if not grouping[team_number] then
        grouping[team_number] = {}
      end
      insert(grouping[team_number], team.name)
    else
      if not grouping.no_group then
        grouping.no_group = {}
      end
      insert(grouping.no_group, team.name)
    end
  end
  local count = 1
  for k, group in pairs (grouping) do
    for j, team_name in pairs (group) do
      local force = game.forces[team_name]
      if force then
        local position = script_data.spawn_positions[count]
        if position then
          force.set_spawn_position(position, surface)
          count = count + 1
        end
      end
    end
  end
end

function chart_starting_area_for_force_spawns()
  --Delay by 1 tick so the GUI can update
  script_data.chart_chunks = 1 + game.tick + (#script_data.config.teams)
  script_data.progress = 0
  update_progress_bar()
end

function clear_biters(surface, area)
  for k, entity in pairs(surface.find_entities_filtered{force = "enemy", area = area}) do
    entity.destroy()
  end
end

function clear_cliffs(surface, area)
  for k, entity in pairs(surface.find_entities_filtered{type = "cliff", area = area}) do
    entity.destroy()
  end
end

function check_starting_area_chunks_are_generated()
  if not script_data.chart_chunks then return end
  local index = script_data.chart_chunks - game.tick
  local surface = script_data.surface
  if index == 0 then
    script_data.progress = 0.99
    script_data.chart_chunks = nil
    script_data.finish_setup = game.tick + (#script_data.config.teams)
    update_progress_bar()
    return
  end
  local team = script_data.config.teams[index]
  if not team then return end
  local name = team.name
  local force = game.forces[name]
  if not force then return end
  script_data.progress = (#script_data.config.teams - index) / #script_data.config.teams
  update_progress_bar()
  local surface = script_data.surface
  local radius = get_starting_area_radius() + 3
  local size = radius * 32
  local origin = force.get_spawn_position(surface)
  local area = {{origin.x - size, origin.y - size},{origin.x + (size - 32), origin.y + (size - 32)}}
  surface.request_to_generate_chunks(origin, radius)
  surface.force_generate_chunk_requests()
  clear_biters(surface, area)
  clear_cliffs(surface, area)
end

function check_player_color()
  for k, team in pairs (script_data.config.teams) do
    local force = game.forces[team.name]
    if force then
      local color = get_color(team)
      for k, player in pairs (force.connected_players) do
        local player_color = player.color
        for c, v in pairs (color) do
          if math.abs(player_color[c] - v) > 0.1 then
            game.print({"player-color-changed-back", player.name})
            player.color = color
            player.chat_color = get_color(team, true)
            break
          end
        end
      end
    end
  end
end

function check_no_rush()
  if not script_data.end_no_rush then return end
  if game.tick > script_data.end_no_rush then
    if script_data.config.game_config.no_rush_time > 0 then
      game.print({"no-rush-ends"})
    end
    script_data.end_no_rush = nil
    script_data.surface.peaceful_mode = script_data.peaceful_mode
    game.forces.enemy.kill_all_units()
    return
  end
end

function check_player_no_rush(player)
  if not script_data.end_no_rush then return end
  local force = player.force
  if not is_ignored_force(force.name) then
    local origin = force.get_spawn_position(player.surface)
    local Xo = origin.x
    local Yo = origin.y
    local position = player.position
    local radius = get_starting_area_radius(true)
    local Xp = position.x
    local Yp = position.y
    if Xp > (Xo + radius) then
      Xp = Xo + radius
    elseif Xp < (Xo - radius) then
      Xp = Xo - radius
    end
    if Yp > (Yo + radius) then
      Yp = Yo + radius
    elseif Yp < (Yo - radius) then
      Yp = Yo - radius
    end
    if position.x ~= Xp or position.y ~= Yp then
      local new_position = {x = Xp, y = Yp}
      local vehicle = player.vehicle
      if vehicle then
        if not vehicle.teleport(new_position) then
          player.driving = false
        end
        vehicle.orientation = vehicle.orientation + 0.5
      else
        player.teleport(new_position)
      end
      local time_left = math.ceil((script_data.end_no_rush-game.tick) / 3600)
      player.print({"no-rush-teleport", time_left})
    end
  end
end

function check_update_production_score()
  if not script_data.config.victory.production_score.active then return end
  local tick = game.tick
  if script_data.team_won then return end
  local new_scores = production_score.get_production_scores(script_data.price_list)
  local scale = statistics_period / 60
  local index = tick % (60 * statistics_period)

  if not (script_data.scores and script_data.average_score) then
    local average_score = {}
    local scores = {}
    for name, score in pairs (new_scores) do
      scores[name] = {}
      average_score[name] = score * statistics_period
      for k = 0, statistics_period do
        scores[name][k * 60] = score
      end
    end
    script_data.scores = scores
    script_data.average_score = average_score
  end

  local scores = script_data.scores
  local average_score = script_data.average_score
  for name, score in pairs (new_scores) do
    local team_score = scores[name] or {}
    local old_amount = team_score[index]
    if old_amount then
      average_score[name] = (average_score[name] + score) - old_amount
      scores[name][index] = score
    else
      --Something went wrong, reinitialize it next update
      script_data.scores = nil
      script_data.average_score = nil
      return check_update_production_score()
    end
  end

  script_data.production_scores = new_scores

  for k, player in pairs (game.connected_players) do
    update_production_score_frame(player)
  end
  local required = script_data.config.victory.production_score.required_production_score
  if required > 0 then
    for team_name, score in pairs (script_data.production_scores) do
      if score >= required then
        team_won(team_name)
      end
    end
  end
  if script_data.config.game_config.time_limit > 0 and tick > script_data.round_start_tick + (script_data.config.game_config.time_limit * 60 * 60) then
    local winner = {"none"}
    local winning_score = 0
    for team_name, score in pairs (script_data.production_scores) do
      if score > winning_score then
        winner = team_name
        winning_score = score
      end
    end
    team_won(winner)
  end
end

function check_update_oil_harvest_score()
  if script_data.team_won then return end
  if not script_data.config.victory.oil_harvest.active then return end
  local fluid_to_check = script_data.config.prototypes.oil or ""
  if not game.fluid_prototypes[fluid_to_check] then
    log("Disabling oil harvest check as "..fluid_to_check.." is not a valid fluid")
    script_data.config.victory.oil_harvest.active = false
    return
  end
  local scores = {}
  for force_name, force in pairs (game.forces) do
    local statistics = force.fluid_production_statistics
    local input = statistics.get_input_count(fluid_to_check)
    --local output = statistics.get_output_count(fluid_to_check)
    scores[force_name] = input
  end
  script_data.oil_harvest_scores = scores
  for k, player in pairs (game.connected_players) do
    update_oil_harvest_frame(player)
  end
  local required = script_data.config.victory.oil_harvest.required_oil
  if required > 0 then
    for team_name, score in pairs (script_data.oil_harvest_scores) do
      if score >= required then
        team_won(team_name)
      end
    end
  end
  if script_data.config.game_config.time_limit > 0 and game.tick > (script_data.round_start_tick + (script_data.config.game_config.time_limit * 60 * 60)) then
    local winner = {"none"}
    local winning_score = 0
    for team_name, score in pairs (script_data.oil_harvest_scores) do
      if score > winning_score then
        winner = team_name
        winning_score = score
      end
    end
    team_won(winner)
  end
end
function check_update_kill_score()
  if script_data.team_won then return end
  if not script_data.config.victory.kill_score.active then return end
  local scores = get_kill_scores()

  for k, player in pairs (game.connected_players) do
    update_kill_score_frame(player)
  end

  local required = script_data.config.victory.kill_score.required_kill_score
  if required > 0 then
    for team_name, score in pairs (scores) do
      if score >= required then
        team_won(team_name)
      end
    end
  end

  if script_data.config.game_config.time_limit > 0 and game.tick > (script_data.round_start_tick + (script_data.config.game_config.time_limit * 60 * 60)) then
    local winner = {"none"}
    local winning_score = 0
    for team_name, score in pairs (scores) do
      if score > winning_score then
        winner = team_name
        winning_score = score
      end
    end
    team_won(winner)
  end
end

function check_update_space_race_score()
  if script_data.team_won then return end
  if not script_data.config.victory.space_race.active then return end

  local scores = get_rocket_scores()
  for k, player in pairs (game.connected_players) do
    update_space_race_frame(player)
  end

  local required = script_data.config.victory.space_race.required_rockets_sent
  if required > 0 then
    for team_name, score in pairs (scores) do
      if score >= required then
        team_won(team_name)
      end
    end
  end
  if script_data.config.game_config.time_limit > 0 and game.tick > (script_data.round_start_tick + (script_data.config.game_config.time_limit * 60 * 60)) then
    local winner = {"none"}
    local winning_score = 0
    for team_name, score in pairs (scores) do
      if score > winning_score then
        winner = team_name
        winning_score = score
      end
    end
    team_won(winner)
  end
end

function finish_setup()
  if not script_data.finish_setup then return end
  local index = script_data.finish_setup - game.tick
  local surface = script_data.surface
  if index == 0 then
    final_setup_step()
    return
  end
  local name = script_data.config.teams[index].name
  if not name then return end
  local force = game.forces[name]
  if not force then return end
  duplicate_starting_area_entities(index)
  force.chart(surface, get_force_area(force))
  if script_data.config.game_config.reveal_team_positions then
    for name, other_force in pairs (game.forces) do
      if not is_ignored_force(name) then
        force.chart(surface, get_force_area(other_force))
      end
    end
  end
  create_silo_for_force(force)
  create_wall_for_force(force)
  create_moat_for_force(force)
  create_starting_chest(force)
  create_starting_turrets(force)
  create_starting_artillery(force)
  protect_force_area(force)
  force.friendly_fire = script_data.config.team_config.friendly_fire
  force.share_chart = true
end

function get_kill_scores()
  if script_data.kill_scores then return script_data.kill_scores end
  local scores = {}
  for k, force in pairs (game.forces) do
    scores[force.name] = 0
  end
  script_data.kill_scores = scores
  return scores
end

function get_rocket_scores()
  if script_data.rocket_scores then return script_data.rocket_scores end
  local scores = {}
  for k, force in pairs (game.forces) do
    scores[force.name] = 0
  end
  script_data.rocket_scores = scores
  return scores
end

function final_setup_step()
  script_data.progress = 1
  update_progress_bar()
  create_exclusion_map()
  script_data.progress = nil
  local surface = script_data.surface
  script_data.finish_setup = nil
  game.print({"map-ready"})
  script_data.setup_finished = true
  script_data.round_start_tick = game.tick
  for k, player in pairs (game.connected_players) do
    destroy_player_gui(player)
    player.teleport({0, 1000}, get_lobby_surface())
    local team = script_data.team_players[player.index]
    if team and script_data.team_names[team.name] and game.forces[team.name] then
      set_player(player, team, true)
    else
      script_data.team_players[player.index] = nil
      choose_joining_gui(player)
    end
  end
  if script_data.config.game_config.no_rush_time then
    script_data.end_no_rush = game.tick + (script_data.config.game_config.no_rush_time * 60 * 60)
    if script_data.config.game_config.no_rush_time > 0 then
      script_data.peaceful_mode = script_data.surface.peaceful_mode
      script_data.surface.peaceful_mode = true
      game.forces.enemy.kill_all_units()
      game.print({"no-rush-begins", script_data.config.game_config.no_rush_time})
    end
  end
  if script_data.config.game_config.base_exclusion_time then
    if script_data.config.game_config.base_exclusion_time > 0 then
      script_data.check_base_exclusion = true
      game.print({"base-exclusion-begins", script_data.config.game_config.base_exclusion_time})
    end
  end
  if script_data.config.game_config.reveal_map_center then
    local radius = (script_data.config.team_config.average_team_displacement / 2) + get_starting_area_radius(true)
    local origin = script_data.spawn_offset
    local area = {{origin.x - radius, origin.y - radius}, {origin.x + (radius - 32), origin.y + (radius - 32)}}
    for k, force in pairs (game.forces) do
      force.chart(surface, area)
    end
  end
  script_data.oil_harvest_scores = {}
  script_data.production_scores = {}
  get_rocket_scores()
  get_kill_scores()
  if script_data.config.victory.production_score.active then
    script_data.price_list = script_data.price_list or production_score.generate_price_list()
  end
  if script_data.config.team_config.defcon_mode then
    defcon_research()
  end

  script.raise_event(events.on_round_start, {})

end

function check_force_protection(force)
  if not script_data.config.game_config.protect_empty_teams then return end
  if not (force and force.valid) then return end
  if is_ignored_force(force.name) then return end
  if not script_data.protected_teams then script_data.protected_teams = {} end
  local protected = script_data.protected_teams[force.name] ~= nil
  local should_protect = #force.connected_players == 0
  if protected and should_protect then return end
  if (not protected) and (not should_protect) then return end
  if protected and (not should_protect) then
    unprotect_force_area(force)
    return
  end
  if (not protected) and should_protect then
    protect_force_area(force)
    check_base_exclusion()
    return
  end
end

function protect_force_area(force)
  if not script_data.config.game_config.protect_empty_teams then return end
  local surface = script_data.surface
  if not (surface and surface.valid) then return end
  local non_destructible = {}
  for k, entity in pairs (surface.find_entities_filtered{force = force, area = get_force_area(force)}) do
    if entity.destructible == false and entity.unit_number then
      non_destructible[entity.unit_number] = true
    end
    entity.destructible = false
  end
  if not script_data.protected_teams then
    script_data.protected_teams = {}
  end
  script_data.protected_teams[force.name] = non_destructible
end

function unprotect_force_area(force)
  if not script_data.config.game_config.protect_empty_teams then return end
  local surface = script_data.surface
  if not (surface and surface.valid) then return end
  if not script_data.protected_teams then
    script_data.protected_teams = {}
  end
  local entities = script_data.protected_teams[force.name] or {}
  for k, entity in pairs (surface.find_entities_filtered{force = force, area = get_force_area(force)}) do
    if (not entity.unit_number) or (not entities[entity.unit_number]) then
      entity.destructible = true
    end
  end
  script_data.protected_teams[force.name] = nil
end

function get_force_area(force)
  if not (force and force.valid) then return end
  local surface = script_data.surface
  if not (surface and surface.valid) then return end
  local radius = get_starting_area_radius(true)
  local origin = force.get_spawn_position(surface)
  return {{origin.x - radius, origin.y - radius}, {origin.x + (radius - 1), origin.y + (radius - 1)}}
end

function update_progress_bar()
  if not script_data.progress then return end
  local percent = script_data.progress
  local finished = (percent >=1)
  function update_bar_gui(player)
    local frame = script_data.elements.progress_bar[player.index]
    if frame and frame.valid then
      script_data.elements.progress_bar[player.index] = nil
      frame.destroy()
    end
    if finished then return end
    local frame = player.gui.center.add{type = "frame", caption = {"progress-bar"}}
    script_data.elements.progress_bar[player.index] = frame
    frame.add{type = "progressbar", size = 100, value = percent}
  end
  for k, player in pairs (game.connected_players) do
    update_bar_gui(player)
  end
  if finished then
    script_data.progress = nil
    script_data.setup_duration = nil
    script_data.finish_tick = nil
  end
end

function create_silo_for_force(force)
  if not script_data.config.victory.last_silo_standing.active then return end
  if not (force and force.valid) then return end
  local surface = script_data.surface
  local origin = force.get_spawn_position(surface)
  local offset = script_data.config.silo_offset
  local silo_position = {x = origin.x + (offset.x or offset[1]), y = origin.y + (offset.y or offset[2])}
  local silo_name = script_data.config.prototypes.silo
  if not game.entity_prototypes[silo_name] then log("Silo not created as "..silo_name.." is not a valid entity prototype") return end
  local silo = surface.create_entity{name = silo_name, position = silo_position, force = force, raise_built = true, create_build_effect_smoke = false}
  --Event is sent, so some mod could kill the silo
  if not (silo and silo.valid) then return end

  silo.minable = false
  if silo.supports_backer_name() then
    silo.backer_name = force.name
  end
  if not script_data.silos then script_data.silos = {} end
  script_data.silos[force.name] = silo

  local tile_name = script_data.config.prototypes.tile_2
  if not game.tile_prototypes[tile_name] then tile_name = get_walkable_tile() end

  local tiles_2 = {}
  local box = silo.bounding_box
  local x1, x2, y1, y2 =
    math.floor(box.left_top.x) - 1,
    math.floor(box.right_bottom.x) + 1,
    math.floor(box.left_top.y) - 1,
    math.floor(box.right_bottom.y) + 1
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

function setup_research(force)
  if not script_data.config.team_config.research_level then return end
  if not (force and force.valid) then return end
  local tier = script_data.config.team_config.research_level.selected
  local index
  local set = (tier ~= "none")
  for k, name in pairs (script_data.config.team_config.research_level.options) do
    if script_data.config.research_ingredient_list[name] ~= nil then
      script_data.config.research_ingredient_list[name] = set
    end
    if name == tier then set = false end
  end
  --[[Unlocks all research, and then unenables them based on a blacklist]]
  force.research_all_technologies()
  for k, technology in pairs (force.technologies) do
    for j, ingredient in pairs (technology.research_unit_ingredients) do
      if not script_data.config.research_ingredient_list[ingredient.name] then
        technology.researched = false
        break
      end
    end
  end
end

function create_starting_turrets(force)
  if not script_data.config.game_config.team_turrets then return end
  if not (force and force.valid) then return end
  local turret_name = script_data.config.prototypes.turret
  if not game.entity_prototypes[turret_name] then return end

  local ammo_name
  if script_data.config.game_config.turret_ammunition then
    ammo_name = script_data.config.game_config.turret_ammunition.selected
  end
  local insert = insert
  local direction = defines.direction
  local surface = script_data.surface
  local height = surface.map_gen_settings.height / 2
  local width = surface.map_gen_settings.width / 2
  local origin = force.get_spawn_position(surface)
  local radius = get_starting_area_radius(true) - 18 --[[radius in tiles]]
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
  local tile_name = script_data.config.prototypes.tile_2
  if not game.tile_prototypes[tile_name] then tile_name = get_walkable_tile() end
  local stack
  if ammo_name and game.item_prototypes[ammo_name] then
    stack = {name = ammo_name, count = 20}
  end
  local find_entities_filtered = surface.find_entities_filtered
  local neutral = game.forces.neutral
  local destroy_params = {do_cliff_correction = true}
  local floor = math.floor
  local create_entity = surface.create_entity
  for k, position in pairs (positions) do
    if is_in_map(width, height, position) then
      local turret = create_entity{name = turret_name, position = position, force = force, direction = position.direction, create_build_effect_smoke = false}
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

function create_starting_artillery(force)
  if not script_data.config.game_config.team_artillery then return end
  if not (force and force.valid) then return end
  local turret_name = script_data.config.prototypes.artillery
  if not (turret_name and game.entity_prototypes[turret_name]) then return end
  local ammo_name = script_data.config.prototypes.artillery_ammo
  if not (ammo_name and game.item_prototypes[ammo_name]) then return end
  local surface = script_data.surface
  local height = surface.map_gen_settings.height / 2
  local width = surface.map_gen_settings.width / 2
  local origin = force.get_spawn_position(surface)
  local radius = get_starting_area_radius() - 1 --[[radius in chunks]]
  if radius < 1 then return end
  local positions = {}
  local tile_positions = {}
  for x = -radius, 0 do
    if x == -radius then
      for y = -radius, 0 do
        insert(positions, {x = 1 + origin.x + 32 * x, y = 1 + origin.y + 32 * y})
      end
    else
      insert(positions, {x = 1 + origin.x + 32 * x, y = 1 + origin.y - radius * 32})
    end
  end
  for x = 1, radius do
    if x == radius then
      for y = -radius, -1 do
        insert(positions, {x = -2 + origin.x + 32 * x, y = 1 + origin.y + 32 * y})
      end
    else
      insert(positions, {x = -2 + origin.x + 32 * x, y = 1 + origin.y - radius * 32})
    end
  end
  for x = -radius, -1 do
    if x == -radius then
      for y = 1, radius do
        insert(positions, {x = 1 + origin.x + 32 * x, y = -2 + origin.y + 32 * y})
      end
    else
      insert(positions, {x = 1 + origin.x + 32 * x, y = -2 + origin.y + radius * 32})
    end
  end
  for x = 0, radius do
    if x == radius then
      for y = 0, radius do
        insert(positions, {x = -2 + origin.x + 32*  x, y = -2 + origin.y + 32 * y})
      end
    else
      insert(positions, {x = -2 + origin.x + 32 * x, y = -2 + origin.y + radius * 32})
    end
  end
  local stack = {name = ammo_name, count = 20}
  local tiles = {}
  local tile_name = script_data.config.prototypes.tile_2
  if not game.tile_prototypes[tile_name] then tile_name = get_walkable_tile() end
  local floor = math.floor
  for k, position in pairs (positions) do
    if is_in_map(width, height, position) then
      local turret = surface.create_entity{name = turret_name, position = position, force = force, direction = position.direction, create_build_effect_smoke = false}
      local box = turret.bounding_box
      for k, entity in pairs (surface.find_entities_filtered{area = turret.bounding_box, force = "neutral"}) do
        entity.destroy({do_cliff_correction = true})
      end
      turret.insert(stack)
      for x = floor(box.left_top.x), floor(box.right_bottom.x) do
        for y = floor(box.left_top.y), floor(box.right_bottom.y) do
          insert(tiles, {name = tile_name, position = {x, y}})
        end
      end
    end
  end
  set_tiles_safe(surface, tiles)
end

function create_moat_for_force(force)
  if not script_data.config.game_config.team_moat then
    return
  end

  local tile_name = script_data.config.prototypes.moat
  if not game.tile_prototypes[tile_name] then
    return
  end

  if not force.valid then return end
  local surface = script_data.surface
  local height = surface.map_gen_settings.height / 2
  local width = surface.map_gen_settings.width / 2
  local origin = force.get_spawn_position(surface)
  local radius = get_starting_area_radius(true)

  local tiles = {}
  local water_radius = radius + 6
  for X = -water_radius, water_radius - 1 do
    if X >= 18 or X < -18 then
      for k = 0, 11 do
        insert(tiles, {name = tile_name, position = {x = origin.x + X, y = origin.y - water_radius + k}})
        insert(tiles, {name = tile_name, position = {x = origin.x + X, y = origin.y + (water_radius-1) - k}})
        insert(tiles, {name = tile_name, position = {x = origin.x - water_radius + k, y = origin.y + X}})
        insert(tiles, {name = tile_name, position = {x = origin.x + (water_radius-1) - k, y = origin.y + X}})
      end
    end
  end

  surface.set_tiles(tiles)

  local cliff_radius = radius - 6

  --The corners

  surface.create_entity{name = "cliff", position = {x = origin.x - cliff_radius, y = origin.y - cliff_radius}, cliff_orientation = "east-to-south"}
  surface.create_entity{name = "cliff", position = {x = origin.x + cliff_radius, y = origin.y - cliff_radius}, cliff_orientation = "south-to-west"}
  surface.create_entity{name = "cliff", position = {x = origin.x - cliff_radius, y = origin.y + cliff_radius}, cliff_orientation = "north-to-east"}
  surface.create_entity{name = "cliff", position = {x = origin.x + cliff_radius, y = origin.y + cliff_radius}, cliff_orientation = "west-to-north"}

  --The lengths

  for k = -(cliff_radius - 4), (cliff_radius - 4), 4 do

    if k >= 20 or k < -20 then
      surface.create_entity{name = "cliff", position = {x = origin.x + k, y = origin.y - cliff_radius}, cliff_orientation = "east-to-west"}
      surface.create_entity{name = "cliff", position = {x = origin.x + k, y = origin.y + cliff_radius}, cliff_orientation = "west-to-east"}
      surface.create_entity{name = "cliff", position = {x = origin.x - cliff_radius, y = origin.y + k }, cliff_orientation = "north-to-south"}
      surface.create_entity{name = "cliff", position = {x = origin.x + cliff_radius, y = origin.y + k}, cliff_orientation = "south-to-north"}
    end
  end

  -- The openings

  --Bottom
  surface.create_entity{name = "cliff", position = {x = origin.x - 18, y = origin.y + cliff_radius}, cliff_orientation = "west-to-south"}
  surface.create_entity{name = "cliff", position = {x = origin.x - 18, y = origin.y + cliff_radius + 4}, cliff_orientation = "north-to-south"}
  surface.create_entity{name = "cliff", position = {x = origin.x - 18, y = origin.y + cliff_radius + 8}, cliff_orientation = "north-to-south"}
  surface.create_entity{name = "cliff", position = {x = origin.x - 18, y = origin.y + cliff_radius + 12}, cliff_orientation = "north-to-none"}

  surface.create_entity{name = "cliff", position = {x = origin.x + 18, y = origin.y + cliff_radius}, cliff_orientation = "south-to-east"}
  surface.create_entity{name = "cliff", position = {x = origin.x + 18, y = origin.y + cliff_radius + 4}, cliff_orientation = "south-to-north"}
  surface.create_entity{name = "cliff", position = {x = origin.x + 18, y = origin.y + cliff_radius + 8}, cliff_orientation = "south-to-north"}
  surface.create_entity{name = "cliff", position = {x = origin.x + 18, y = origin.y + cliff_radius + 12}, cliff_orientation = "none-to-north"}

  --Top
  surface.create_entity{name = "cliff", position = {x = origin.x - 18, y = origin.y - cliff_radius}, cliff_orientation = "north-to-west"}
  surface.create_entity{name = "cliff", position = {x = origin.x - 18, y = origin.y - cliff_radius - 4}, cliff_orientation = "north-to-south"}
  surface.create_entity{name = "cliff", position = {x = origin.x - 18, y = origin.y - cliff_radius - 8}, cliff_orientation = "north-to-south"}
  surface.create_entity{name = "cliff", position = {x = origin.x - 18, y = origin.y - cliff_radius - 12}, cliff_orientation = "none-to-south"}

  surface.create_entity{name = "cliff", position = {x = origin.x + 18, y = origin.y - cliff_radius}, cliff_orientation = "east-to-north"}
  surface.create_entity{name = "cliff", position = {x = origin.x + 18, y = origin.y - cliff_radius - 4}, cliff_orientation = "south-to-north"}
  surface.create_entity{name = "cliff", position = {x = origin.x + 18, y = origin.y - cliff_radius - 8}, cliff_orientation = "south-to-north"}
  surface.create_entity{name = "cliff", position = {x = origin.x + 18, y = origin.y - cliff_radius - 12}, cliff_orientation = "south-to-none"}

  --Right
  surface.create_entity{name = "cliff", position = {x = origin.x + cliff_radius, y = origin.y - 18}, cliff_orientation = "east-to-north"}
  surface.create_entity{name = "cliff", position = {x = origin.x + cliff_radius + 4, y = origin.y - 18}, cliff_orientation = "east-to-west"}
  surface.create_entity{name = "cliff", position = {x = origin.x + cliff_radius + 8, y = origin.y - 18}, cliff_orientation = "east-to-west"}
  surface.create_entity{name = "cliff", position = {x = origin.x + cliff_radius + 12, y = origin.y - 18}, cliff_orientation = "none-to-west"}

  surface.create_entity{name = "cliff", position = {x = origin.x + cliff_radius, y = origin.y + 18}, cliff_orientation = "south-to-east"}
  surface.create_entity{name = "cliff", position = {x = origin.x + cliff_radius + 4, y = origin.y + 18}, cliff_orientation = "west-to-east"}
  surface.create_entity{name = "cliff", position = {x = origin.x + cliff_radius + 8, y = origin.y + 18}, cliff_orientation = "west-to-east"}
  surface.create_entity{name = "cliff", position = {x = origin.x + cliff_radius + 12, y = origin.y + 18}, cliff_orientation = "west-to-none"}

  --Left
  surface.create_entity{name = "cliff", position = {x = origin.x - cliff_radius, y = origin.y - 18}, cliff_orientation = "north-to-west"}
  surface.create_entity{name = "cliff", position = {x = origin.x - cliff_radius -  4, y = origin.y - 18}, cliff_orientation = "east-to-west"}
  surface.create_entity{name = "cliff", position = {x = origin.x - cliff_radius - 8, y = origin.y - 18}, cliff_orientation = "east-to-west"}
  surface.create_entity{name = "cliff", position = {x = origin.x - cliff_radius - 12, y = origin.y - 18}, cliff_orientation = "east-to-none"}

  surface.create_entity{name = "cliff", position = {x = origin.x - cliff_radius, y = origin.y + 18}, cliff_orientation = "west-to-south"}
  surface.create_entity{name = "cliff", position = {x = origin.x - cliff_radius - 4, y = origin.y + 18}, cliff_orientation = "west-to-east"}
  surface.create_entity{name = "cliff", position = {x = origin.x - cliff_radius - 8, y = origin.y + 18}, cliff_orientation = "west-to-east"}
  surface.create_entity{name = "cliff", position = {x = origin.x - cliff_radius - 12, y = origin.y + 18}, cliff_orientation = "none-to-east"}

end

function create_wall_for_force(force)
  if not script_data.config.game_config.team_walls then return end
  if not force.valid then return end
  local surface = script_data.surface
  local height = surface.map_gen_settings.height / 2
  local width = surface.map_gen_settings.width / 2
  local origin = force.get_spawn_position(surface)
  local radius = get_starting_area_radius(true) - 11
  if radius < 2 then return end
  local perimeter_top = {}
  local perimeter_bottom = {}
  local perimeter_left = {}
  local perimeter_right = {}
  local tiles = {}
  local insert = insert
  for X = -radius, radius - 1 do
    insert(perimeter_top, {x = origin.x + X, y = origin.y - radius})
    insert(perimeter_bottom, {x = origin.x + X, y = origin.y + (radius-1)})
  end
  for Y = -radius, radius - 1 do
    insert(perimeter_left, {x = origin.x - radius, y = origin.y + Y})
    insert(perimeter_right, {x = origin.x + (radius-1), y = origin.y + Y})
  end
  local tile_name = script_data.config.prototypes.tile_1
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
  local wall_name = script_data.config.prototypes.wall
  local gate_name = script_data.config.prototypes.gate
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
    if is_in_map(width, height, position) then
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
    if is_in_map(width, height, position) then
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
    if is_in_map(width, height, position) then
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
    if is_in_map(width, height, position) then
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

function spairs(t, order)
  local keys = {}
  for k in pairs(t) do keys[#keys+1] = k end
  if order then
    table.sort(keys, function(a, b) return order(t, a, b) end)
  else
    table.sort(keys)
  end
  local i = 0
  return function()
    i = i + 1
    if keys[i] then
      return keys[i], t[keys[i]]
    end
  end
end

function areas_overlap(area_1, area_2)
  local left_top = area_1[1]
  local right_bottom = area_1[2]
  local x1 = area_2[1][1]
  local x2 = area_2[2][1]
  local y1 = area_2[1][2]
  local y2 = area_2[2][2]
  if x1 > left_top[1] and x1 < right_bottom[1] then return true end
  if x2 > left_top[1] and x2 < right_bottom[1] then return true end
  if y1 > left_top[2] and y1 < right_bottom[2] then return true end
  if y2 > left_top[2] and y2 < right_bottom[2] then return true end
  return false
end

function duplicate_starting_area_entities(index)
  if not script_data.config.team_config.duplicate_starting_area_entities then return end
  if index == 1 then return end --Index 1 is the copy force... so we don't copy anything...
  local copy_team = script_data.config.teams[1]
  if not copy_team then return end
  local force = game.forces[copy_team.name]
  if not force then return end
  local destination_team = script_data.config.teams[index]
  local destination_force = game.forces[destination_team.name]
  if not destination_force then return end
  local surface = script_data.surface
  local origin_spawn = force.get_spawn_position(surface)
  local radius = get_starting_area_radius(true) --[[radius in tiles]]
  local copy_area = {{origin_spawn.x - radius, origin_spawn.y - radius}, {origin_spawn.x + radius, origin_spawn.y + radius}}
  local destination_spawn = destination_force.get_spawn_position(surface)
  local destination_area = {{destination_spawn.x - radius, destination_spawn.y - radius}, {destination_spawn.x + radius, destination_spawn.y + radius}}

  local tile_name = get_walkable_tile()
  local top_count = 0
  for name, tile in pairs (game.tile_prototypes) do
    if not tile.collision_mask["resource-layer"] then
      local count = surface.count_tiles_filtered{name = name, area = destination_area}
      if count > top_count then
        top_count = count
        tile_name = name
      end
    end
  end

  local offset_x = destination_spawn.x - origin_spawn.x
  local offset_y = destination_spawn.y - origin_spawn.y

  --Fill in current water in destination area
  local set_tiles = {}
  local tile_count = 0
  for k, tile in pairs (surface.find_tiles_filtered{area = destination_area, collision_mask = "resource-layer"}) do
    tile_count = tile_count + 1
    set_tiles[tile_count] = {name = tile_name, position = {x = tile.position.x, y = tile.position.y}}
  end
  surface.set_tiles(set_tiles)

  --Copy water from copy area
  local set_water = {}
  local water_count = 0
  for k, tile in pairs (surface.find_tiles_filtered{area = copy_area, collision_mask = "resource-layer"}) do
    water_count = water_count + 1
    set_water[water_count] = {name = tile.name, position = {x = tile.position.x + offset_x, y = tile.position.y + offset_y}}
  end
  surface.set_tiles(set_water)

  local success = pcall(surface.clone_area,
  {
    source_area = copy_area,
    destination_area = destination_area,
    clone_entities = true,
    clear_destination = true,
    clone_tiles = false,
    clone_decoratives = true
  })

  if not success then
    game.print({"duplicate-failed"})
    log("Duplicating failed, probably due to poor map conditions")
  end

end

function create_starting_chest(force)
  if not (force and force.valid) then return end
  if not script_data.config.starting_chest then return end
  local value = script_data.config.starting_chest.selected
  local multiplier = script_data.config.team_config.starting_chest_multiplier
  if not (multiplier > 0) then return end
  local inventory = script_data.config.inventory_list[value]
  if not inventory then return end
  if not (table_size(inventory) > 0) then return end
  local surface = script_data.surface
  local chest_name = script_data.config.prototypes.chest
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
  local origin = force.get_spawn_position(surface)
  local offset = script_data.config.chest_offset
  origin.x = origin.x + offset.x
  origin.y = origin.y + offset.y
  local index = 1
  local position = {x = origin.x + get_chest_offset(index).x * size, y = origin.y + get_chest_offset(index).y * size}
  local chest = surface.create_entity{name = chest_name, position = position, force = force, create_build_effect_smoke = false}
  for k, v in pairs (surface.find_entities_filtered{force = "neutral", area = chest.bounding_box}) do
    v.destroy()
  end
  local tiles = {}
  local grass = {}
  local tile_name = script_data.config.prototypes.tile_1
  if not game.tile_prototypes[tile_name] then tile_name = get_walkable_tile() end
  insert(tiles, {name = tile_name, position = {x = position.x, y = position.y}})
  chest.destructible = false
  local items = game.item_prototypes
  for name, count in pairs (inventory) do
    if items[name] then
      local count_to_insert = math.ceil(count * multiplier)
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

function set_tiles_safe(surface, tiles)
  local grass = get_walkable_tile()
  local grass_tiles = {}
  for k, tile in pairs (tiles) do
    grass_tiles[k] = {position = {x = (tile.position.x or tile.position[1]), y = (tile.position.y or tile.position[2])}, name = grass}
  end
  surface.set_tiles(grass_tiles, false)
  surface.set_tiles(tiles)
end

function create_exclusion_map()
  local surface = script_data.surface
  if not (surface and surface.valid) then return end
  local exclusion_map = {}
  local radius = get_starting_area_radius() --[[radius in chunks]]
  for k, team in pairs (script_data.config.teams) do
    local name = team.name
    local force = game.forces[name]
    if force then
      local origin = force.get_spawn_position(surface)
      local Xo = math.floor(origin.x / 32)
      local Yo = math.floor(origin.y / 32)
      for X = -radius, radius - 1 do
        Xb = X + Xo
        if not exclusion_map[Xb] then exclusion_map[Xb] = {} end
        for Y = -radius, radius - 1 do
          local Yb = Y + Yo
          exclusion_map[Xb][Yb] = name
        end
      end
    end
  end
  script_data.exclusion_map = exclusion_map
end

function check_base_exclusion()
  if not (script_data.check_base_exclusion or script_data.protected_teams) then return end

  if script_data.check_base_exclusion and game.tick > (script_data.round_start_tick + (script_data.config.game_config.base_exclusion_time * 60 * 60)) then
    script_data.check_base_exclusion = nil
    game.print({"base-exclusion-ends"})
  end

end

function check_player_base_exclusion(player)
  if not (script_data.check_base_exclusion or script_data.protected_teams) then return end

  if not is_ignored_force(player.force.name) then
    check_player_exclusion(player, get_chunk_map_position(player.position))
  end
end

function get_chunk_map_position(position)
  local map = script_data.exclusion_map
  local chunk_x = math.floor(position.x / 32)
  local chunk_y = math.floor(position.y / 32)
  if map[chunk_x] then
    return map[chunk_x][chunk_y]
  end
end

function is_ignored_force(name)
  return not script_data.team_names[name]
end

function check_player_exclusion(player, force_name)
  if not force_name then return end
  local force = game.forces[force_name]
  if not (force and force.valid and player and player.valid) then return end
  if force == player.force or force.get_friend(player.force) then return end
  if not (script_data.check_base_exclusion or (script_data.protected_teams and script_data.protected_teams[force_name])) then return end
  local surface = script_data.surface
  local origin = force.get_spawn_position(surface)
  local radius = get_starting_area_radius(true) --[[radius in tiles]]
  local position = {x = player.position.x, y = player.position.y}
  local vector = {x = 0, y = 0}

  if position.x < origin.x then
    vector.x = (origin.x - radius) - position.x
  elseif position.x > origin.x then
    vector.x = (origin.x + radius) - position.x
  end

  if position.y < origin.y then
    vector.y = (origin.y - radius) - position.y
  elseif position.y > origin.y then
    vector.y = (origin.y + radius) - position.y
  end

  if math.abs(vector.x) < math.abs(vector.y) then
    vector.y = 0
  else
    vector.x = 0
  end

  local new_position = {x = position.x + vector.x, y = position.y + vector.y}
  local vehicle = player.vehicle
  if vehicle then
    if not vehicle.teleport(new_position) then
      player.driving = false
    end
    vehicle.orientation = vehicle.orientation + 0.5
  else
    player.teleport(new_position)
  end

  if script_data.check_base_exclusion then
    local time_left = math.ceil((script_data.round_start_tick + (script_data.config.game_config.base_exclusion_time * 60 * 60) - game.tick) / 3600)
    player.print({"base-exclusion-teleport", time_left})
  else
    player.print({"protected-base-area"})
  end

end

local should_start = function()
  if script_data.ready_start_tick and script_data.ready_start_tick <= game.tick then
    return true
  end

  if not script_data.team_won then return false end
  local time = script_data.config.game_config.auto_new_round_time
  if not (time > 0) then return false end
  if game.tick < (script_data.config.game_config.auto_new_round_time * 60 * 60) + script_data.team_won then return false end
  return true
end

function check_restart_round()
  if not should_start() then return end
  end_round()
  start_round()
end

function team_won(name)
  script_data.team_won = game.tick
  if script_data.config.game_config.auto_new_round_time > 0 then
    game.print({"team-won-auto", name, script_data.config.game_config.auto_new_round_time})
  else
    game.print({"team-won", name})
  end
  script.raise_event(events.on_team_won, {name = name})
end

function offset_respawn_position(player)
  --This is to help the spawn camping situations.
  if not (player and player.valid and player.character) then return end
  local surface = player.surface
  local origin = player.force.get_spawn_position(surface)
  local radius = get_starting_area_radius(true) - 32
  if not (radius > 0) then return end
  local random_position = {origin.x + math.random(-radius, radius), origin.y + math.random(-radius, radius)}
  local position = surface.find_non_colliding_position(player.character.name, random_position, 32, 1)
  if not position then return end
  player.teleport(position)
end

function recursive_data_check(new_data, old_data)
  for k, data in pairs (new_data) do
    if old_data[k] == nil then
      old_data[k] = data
    elseif type(data) ~= type(old_data[k]) then
      old_data[k] = data
    elseif type(data) == "table" then
      recursive_data_check(new_data[k], old_data[k])
    end
  end
end

function check_cursor_for_disabled_items(event)
  if not script_data.config.disabled_items then return end
  local player = game.players[event.player_index]
  if not (player and player.valid) then return end
  local stack = player.cursor_stack
  if (stack and stack.valid_for_read) then
    if script_data.config.disabled_items[stack.name] then
      stack.clear()
    end
  end
end

function recipe_picker_elem_update(player)
  if not (player and player.valid) then return end
  local production_score_frame = script_data.elements.production_score_frame[player.index]
  if not (production_score_frame and production_score_frame.valid) then return end

  local recipe_frame = script_data.elements.recipe_frame[player.index]
  if recipe_frame and recipe_frame.valid then
    deregister_gui(recipe_frame)
    recipe_frame.destroy()
    script_data.elements.recipe_frame[player.index] = nil
  end

  local elem_value = script_data.selected_recipe[player.index]
  local elem_button = script_data.elements.recipe_button[player.index]
  if (elem_button and elem_button.valid) then
    elem_button.elem_value = elem_value
  end

  if not elem_value then return end

  local recipe = player.force.recipes[elem_value]
  local recipe_frame = production_score_frame.add{type = "frame", direction = "vertical", style = "inside_shallow_frame"}
  script_data.elements.recipe_frame[player.index] = recipe_frame
  local title_flow = recipe_frame.add{type = "flow"}
  title_flow.style.horizontal_align = "center"
  title_flow.style.horizontally_stretchable = true
  title_flow.add{type = "label", caption = recipe.localised_name, style = "caption_label"}
  local table = recipe_frame.add{type = "table", column_count = 2, style = "bordered_table"}
  table.style.margin = 4
  table.style.column_alignments[1] = "center"
  table.style.column_alignments[2] = "center"
  table.add{type = "label", caption = {"ingredients"}, style = "bold_label"}
  table.add{type = "label", caption = {"products"}, style = "bold_label"}
  local ingredients = recipe.ingredients
  local products = recipe.products
  local prices = script_data.price_list
  local cost = 0
  local gain = 0
  local prototypes =
  {
    fluid = game.fluid_prototypes,
    item = game.item_prototypes
  }
  for k = 1, math.max(#ingredients, #products) do
    local ingredient = ingredients[k]
    local flow = table.add{type = "flow", direction = "horizontal"}
    if k == 1 then
      flow.style.top_padding = 8
    end
    flow.style.vertical_align = "center"
    if ingredient then
      local ingredient_price = prices[ingredient.name] or 0
      local calculator_button = flow.add
      {
        type = "sprite-button",
        sprite = ingredient.type.."/"..ingredient.name,
        number = ingredient.amount,
        style = "transparent_slot",
        tooltip = {"", "1 ", prototypes[ingredient.type][ingredient.name].localised_name, " = ", util.format_number(math.floor(ingredient_price * 100) / 100)}
      }
      register_gui_action(calculator_button, {type = "calculator_button_press", elem_type = ingredient.type, elem_name = ingredient.name})
      local price = ingredient.amount * ingredient_price or 0
      add_pusher(flow)
      flow.add{type = "label", caption = util.format_number(math.floor(price * 100) / 100)}
      cost = cost + price
    end
    local product = products[k]
    flow = table.add{type = "flow", direction = "horizontal"}
    if k == 1 then
      flow.style.top_padding = 8
    end
    flow.style.vertical_align = "center"
    if product then
      local amount = util.product_amount(product)
      local product_price = prices[product.name] or 0
      local calculator_button = flow.add
      {
        type = "sprite-button",
        sprite = product.type.."/"..product.name,
        number = amount,
        style = "transparent_slot",
        tooltip = {"", "1 ", prototypes[product.type][product.name].localised_name, " = ", util.format_number(math.floor(product_price * 100) / 100)},
        show_percent_for_small_numbers = true
      }
      register_gui_action(calculator_button, {type = "calculator_button_press", elem_type = product.type, elem_name = product.name})
      add_pusher(flow)
      local price = amount * product_price or 0
      flow.add{type = "label", caption = util.format_number(math.floor(price * 100) / 100)}
      gain = gain + price
    end
  end
  local cost_flow = table.add{type = "flow"}
  cost_flow.add{type = "label", caption = {"", {"cost"}, {"colon"}}}
  add_pusher(cost_flow)
  cost_flow.add{type = "label", caption = util.format_number(math.floor(cost * 100) / 100)}
  local gain_flow = table.add{type = "flow"}
  gain_flow.add{type = "label", caption = {"", {"gain"}, {"colon"}}}
  add_pusher(gain_flow)
  gain_flow.add{type = "label", caption = util.format_number(math.floor(gain * 100) / 100)}
  table.add{type = "flow"}
  local total_flow = table.add{type = "flow"}
  total_flow.add{type = "label", caption = {"", {"total"}, {"colon"}}, style = "bold_label"}
  add_pusher(total_flow)
  local total = total_flow.add{type = "label", caption = util.format_number(math.floor((gain-cost) * 100) / 100), style = "bold_label"}
  if cost > gain then
    total.style.font_color = {r = 1, g = 0.3, b = 0.3}
  end

end

function add_pusher(gui)
  local pusher = gui.add{type = "flow"}
  pusher.style.horizontally_stretchable = true
end

function check_on_built_protection(event)
  if not script_data.config.game_config.enemy_building_restriction then return end
  local entity = event.created_entity
  local player = game.players[event.player_index]
  if not (entity and entity.valid and player and player.valid) then return end
  local force = entity.force
  local name = get_chunk_map_position(entity.position)
  if not name then return end
  if force.name == name then return end
  local other_force = game.forces[name]
  if not other_force then return end
  if other_force.get_friend(force) then return end
  if not player.mine_entity(entity, true) then
    entity.destroy()
  end
  player.print({"enemy-building-restriction"})
end

function check_defcon()
  if not script_data.config.team_config.defcon_mode then return end
  local defcon_tick = script_data.last_defcon_tick
  if not defcon_tick then
    defcon_research()
    return
  end
  local current_tick = game.tick
  local duration = math.max(60, (script_data.config.team_config.defcon_timer * 60 * 60))
  local tick_of_defcon = defcon_tick + duration
  local progress = math.max(0, math.min(1, 1 - (tick_of_defcon - current_tick) / duration))
  local tech = script_data.next_defcon_tech
  if tech and tech.valid then
    for k, team in pairs (script_data.config.teams) do
      local force = game.forces[team.name]
      if force then
        if (not force.current_research) or (force.current_research.name ~= tech.name) then
          force.cancel_current_research()
          force.add_research(tech)
        end
        if force.current_research then
          --If they have labs, it might research it between the defcon updates...
          force.research_progress = progress
        end
      end
    end
  end
  if current_tick >= tick_of_defcon then
    defcon_research()
  end
end

recursive_technology_prerequisite = function(tech)
  for name, prerequisite in pairs (tech.prerequisites) do
    if not prerequisite.researched then
      return recursive_technology_prerequisite(prerequisite)
    end
  end
  return tech
end

function defcon_research()
  script_data.last_defcon_tick = game.tick
  local tech = script_data.next_defcon_tech
  if tech and tech.valid then
    for k, team in pairs (script_data.config.teams) do
      local force = game.forces[team.name]
      if force then
        local tech = force.technologies[tech.name]
        if tech then
          tech.researched = true
        end
      end
    end
    local sound = "utility/research_completed"
    if game.is_valid_sound_path(sound) then
      game.play_sound({path = sound})
    end
    game.print({"defcon-unlock", tech.localised_name}, {r = 1, g = 0.5, b = 0.5})
  end

  local force
  for k, team in pairs (script_data.config.teams) do
    force = game.forces[team.name]
    if force and force.valid then
      break
    end
  end
  if not force then return end
  local available_techs = {}
  for name, tech in pairs (force.technologies) do
    if tech.enabled and tech.researched == false then
      insert(available_techs, tech)
    end
  end
  if #available_techs == 0 then return end
  local random_tech = available_techs[math.random(#available_techs)]
  if not random_tech then return end
  random_tech = recursive_technology_prerequisite(random_tech)
  script_data.next_defcon_tech = game.technology_prototypes[random_tech.name]
  for k, team in pairs (script_data.config.teams) do
    local force = game.forces[team.name]
    if force then
      force.add_research(script_data.next_defcon_tech)
    end
  end
end

function check_neutral_chests(event)
  if not script_data.config.game_config.neutral_chests then return end
  local entity = event.created_entity
  if not (entity and entity.valid) then return end
  if entity.type == "container" then
    entity.force = "neutral"
  end
end

function on_calculator_button_press(event, param)
  local gui = event.element
  if not (gui and gui.valid) then return end
  local player = game.players[event.player_index]
  if not (player and player.valid) then return end
  local type = param.elem_type
  local elem_name = param.elem_name
  local items = game.item_prototypes
  local fluids = game.fluid_prototypes
  local recipes = game.recipe_prototypes
  if type == "item" then
    if not items[elem_name] then return end
  elseif type == "fluid" then
    if not fluids[elem_name] then return end
  else
    return
  end
  local selected = script_data.selected_recipe[player.index]
  local candidates = {}
  for name, recipe in pairs (recipes) do
    for k, product in pairs (recipe.products) do
      if product.type == type and product.name == elem_name then
        insert(candidates, name)
      end
    end
  end
  if #candidates == 0 then return end
  local index = 0
  for k, name in pairs (candidates) do
    if name == selected then
      index = k
      break
    end
  end
  local recipe_name = candidates[index + 1] or candidates[1]
  if not recipe_name then return end
  script_data.selected_recipe[player.index] = recipe_name
  recipe_picker_elem_update(player)
end

function generic_gui_event(event)
  local gui = event.element
  if not (gui and gui.valid) then return end
  local player_gui_actions = script_data.gui_actions[gui.player_index]
  if not player_gui_actions then return end
  local action = player_gui_actions[gui.index]
  if action then
    gui_functions[action.type](event, action)
    return true
  end
end

local on_rocket_launched = function(event)
  if not script_data.config.victory.space_race.active then return end
  local sent = get_rocket_scores()
  local name = event.rocket.force.name
  sent[name] = sent[name] + 1
  check_update_space_race_score()
end

local check_last_silo_standing_victory = function(event)
  if script_data.team_won then return end
  if not script_data.config.victory.last_silo_standing.active then return end
  local silo = event.entity
  if not (silo and silo.valid and silo.name == (script_data.config.prototypes.silo or "") ) then
    return
  end
  local killing_force = event.force
  local force = silo.force
  if not script_data.silos then return end
  script_data.silos[force.name] = nil
  if killing_force then
    game.print({"silo-destroyed", force.name, killing_force.name})
  else
    game.print({"silo-destroyed", force.name, {"neutral"}})
  end
  script.raise_event(events.on_team_lost, {name = force.name})

  for k, player in pairs (force.players) do
    local character = player.character
    if character then
      player.character = nil
      character.die()
    end
    player.force = "neutral"
    player.set_controller{type = defines.controllers.spectator}
  end

  game.merge_forces(force, "neutral")

  local index = 0
  local winner_name = {"none"}
  for name, listed_silo in pairs (script_data.silos) do
    if (listed_silo and listed_silo.valid) then
      index = index + 1
      winner_name = name
    end
  end

  if index == 1  then
    team_won(winner_name)
    return
  end

  if index == 0 then
    -- All silos are destroyed, which can happen with only 1 team
    -- So we just set the victory tick manually.
    script_data.team_won = game.tick
    return
  end

end

local update_kill_score = function(event)
  if not script_data.config.victory.kill_score.active then return end
  local entity = event.entity
  if not (entity and entity.valid) then return end

  local cause_force = event.force
  if not (cause_force and cause_force.valid) then return end

  local scores = get_kill_scores()
  local prices = script_data.entity_prices
  if not prices then
    prices = kill_score.generate_entity_prices()
    script_data.entity_prices = prices
  end

  local force_name = cause_force.name
  scores[force_name] = scores[force_name] + (prices[entity.name] or 0)

end

local on_entity_died = function(event)
  update_kill_score(event)
  check_last_silo_standing_victory(event)
end

local on_player_joined_game = function(event)
  local player = game.players[event.player_index]
  if not (player and player.valid) then return end
  player.spectator = true
  init_player_gui(player)

  if not script_data.setup_finished then
    refresh_config(player.index)
  end

  if player.force.name ~= "player" then
    --If they are not on the player force, they have already picked a team this round.
    check_force_protection(player.force)
    for k, other_player in pairs (game.connected_players) do
      update_team_list_frame(other_player)
    end
    return
  end
  local character = player.character
  player.character = nil
  if character then character.destroy() end
  player.set_controller{type = defines.controllers.spectator}
  player.teleport({0, 1000}, get_lobby_surface())
end

local on_player_left_game = function(event)
  local player = game.players[event.player_index]

  if script_data.setup_finished then
    for k, player in pairs (game.connected_players) do
      local gui = player.gui.center
      choose_joining_gui(player)
      choose_joining_gui(player)
      update_team_list_frame(player)
    end
    check_force_protection(force)
  else
    refresh_config(event.player_index)
  end

  destroy_player_gui(player)
end

local on_tick = function(event)
  if script_data.setup_finished == false then
    check_starting_area_chunks_are_generated()
    finish_setup()
  end
end

local on_player_respawned = function(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  if script_data.setup_finished == true then
    config.give_equipment(player)
    offset_respawn_position(player)
    balance.apply_character_modifiers(player)
  else
    if player.character then
      player.character.destroy()
    end
  end
end

local on_research_finished = function(event)
  check_technology_for_disabled_items(event)
end

local on_player_cursor_stack_changed = function(event)
  check_cursor_for_disabled_items(event)
end

local on_built_entity = function(event)
  check_on_built_protection(event)
  check_neutral_chests(event)
end

local on_robot_built_entity = function(event)
  check_neutral_chests(event)
end

local on_research_started = function(event)
  if script_data.config.team_config.defcon_mode then
    local tech = script_data.next_defcon_tech
    local research = event.research
    local force = research.force
    if not is_ignored_force(force.name) then
      if tech and tech.valid and research.name ~= tech.name then
        force.cancel_current_research()
        force.add_research(tech)
      end
    end
  end
end

local on_player_event_refresh_gui = function(event)
  init_player_gui(game.get_player(event.player_index))
end

local on_forces_merged = function (event)
  create_exclusion_map()
end

local on_player_changed_position = function(event)
  local player = game.players[event.player_index]
  check_player_base_exclusion(player)
  check_player_no_rush(player)
end

local check_spectator_chart = function()
  local force = game.forces.neutral
  if not (force and force.valid) then return end
  local surface = script_data.surface
  if not (surface and surface.valid) then return end
  force.chart_all(script_data.surface)
end

function destroy_016_player_guis()
  for k, player in pairs (game.players) do
    local button_flow = mod_gui.get_button_flow(player)
    for k, name in pairs (
      {
        "objective_button", "diplomacy_button", "admin_button",
        "silo_gui_sprite_button", "production_score_button", "oil_harvest_button",
        "space_race_button", "spectator_join_team_button", "list_teams_button"
      }) do
      if button_flow[name] then
        button_flow[name].destroy()
      end
    end
    local frame_flow = mod_gui.get_frame_flow(player)
    for k, name in pairs (
      {
        "objective_frame", "admin_button", "admin_frame",
        "silo_gui_frame", "production_score_frame", "oil_harvest_frame",
        "space_race_frame", "team_list"
      }) do
      if frame_flow[name] then
        frame_flow[name].destroy()
      end
    end
    local center_gui = player.gui.center
    for k, name in pairs ({"diplomacy_frame", "progress_bar", "random_join_frame", "pick_join_frame", "auto_assign_frame"}) do
      if center_gui[name] then
        center_gui[name].destroy()
      end
    end
  end
end

local pvp = {}

pvp.events =
{
  [defines.events.on_built_entity] = on_built_entity,
  [defines.events.on_robot_built_entity] = on_robot_built_entity,
  [defines.events.on_chunk_generated] = on_chunk_generated,
  [defines.events.on_entity_died] = on_entity_died,
  [defines.events.on_forces_merged] = on_forces_merged,

  [defines.events.on_gui_checked_state_changed] = generic_gui_event,
  [defines.events.on_gui_click] = generic_gui_event,
  [defines.events.on_gui_closed] = generic_gui_event,
  [defines.events.on_gui_elem_changed] = generic_gui_event,
  [defines.events.on_gui_selection_state_changed] = generic_gui_event,
  [defines.events.on_gui_text_changed] = generic_gui_event,

  [defines.events.on_player_joined_game] = on_player_joined_game,
  [defines.events.on_player_left_game] = on_player_left_game,
  [defines.events.on_player_respawned] = on_player_respawned,
  [defines.events.on_player_changed_position] = on_player_changed_position,
  [defines.events.on_player_cursor_stack_changed] = on_player_cursor_stack_changed,

  [defines.events.on_player_demoted] = on_player_event_refresh_gui,
  [defines.events.on_player_display_resolution_changed] = on_player_event_refresh_gui,
  [defines.events.on_player_display_scale_changed] = on_player_event_refresh_gui,
  [defines.events.on_player_promoted] = on_player_event_refresh_gui,
  [defines.events.on_player_changed_force] = on_player_event_refresh_gui,

  [defines.events.on_research_finished] = on_research_finished,
  [defines.events.on_research_started] = on_research_started,

  [defines.events.on_rocket_launched] = on_rocket_launched,
  [defines.events.on_tick] = on_tick
}

pvp.add_remote_interface = function()
  remote.add_interface("pvp",
  {
    get_event_name = function(name)
      return events[name]
    end,
    get_events = function()
      return events
    end,
    get_teams = function()
      return script_data.config.teams
    end,
    get_config = function()
      return script_data.config
    end,
    set_config = function(array)
      log("PvP global config set by remote call - Can expect script errors after this point.")
      for k, v in pairs (array) do
        script_data.config[k] = v
      end
    end
  })
end

pvp.on_nth_tick =
{
  [60] = function(event)
    if script_data.setup_finished == true then
      check_no_rush()
      check_update_production_score()
      check_update_oil_harvest_score()
      check_update_space_race_score()
      check_update_kill_score()
      check_base_exclusion()
      check_defcon()
    end
    check_restart_round()
  end,
  [300] = function(event)
    if script_data.setup_finished == true then
      check_player_color()
      check_spectator_chart()
    end
  end
}

pvp.on_load = function()
  script_data = global.pvp or script_data
  balance.script_data = script_data
  config.script_data = script_data
end

pvp.on_init = function()
  if global.pvp then
    --Init was already run, just do the on_load.
    pvp.on_load()
    return
  end
  script_data.config = config.get_config()
  global.pvp = script_data
  balance.script_data = script_data
  config.script_data = script_data
  balance.init()
  script_data.config.game_config.seed = game.surfaces[1].map_gen_settings.seed
  for k, force in pairs (game.forces) do
    force.disable_all_prototypes()
    force.disable_research()
  end
end

pvp.on_configuration_changed = function(data)
  if not global.pvp and global.surface and global.teams then
    --Was made in 0.16, do some basic data migration
    local pvp = global
    global = {pvp = pvp}
    recursive_data_check(script_data, global.pvp)
    script_data = global.pvp
    script_data.config = config.get_config()
    local config = script_data.config
    config.teams = script_data.teams
    script_data.teams = nil
    destroy_016_player_guis()
    balance.script_data = script_data
    config.script_data = script_data
  end
  recursive_data_check(config.get_config(), script_data.config)

  script_data.random = script_data.random or game.create_random_generator()
  update_teams_names()

  --[[
    if game.forces.spectator then
      game.merge_forces("spectator", "neutral")
    end
  ]]

  script_data.elements.team_tab = script_data.elements.team_tab or {}
  script_data.elements.game_tab = script_data.elements.game_tab or {}

end

return pvp
