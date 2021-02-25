local util = require("util")
require("story")

local spawn_position = {-37, 55}

local think = function(thought)
  game.players[1].print({"","[img=entity/character][color=orange]",{"engineer-title"},": [/color]",{"think-"..thought}})
end

local msg = function(msg)
  game.players[1].print({"","[img=entity/radar][color=green]",{"computer-title"},": [/color]",{"msg-"..msg}})
end

local on_player_created = function(event)

  local player = game.players[1]

  player.disable_recipe_groups()
  player.disable_recipe_subgroups()
  player.minimap_enabled = false
  player.force.disable_all_prototypes()
  player.force.disable_research()

  local recipe_list = player.force.recipes
  recipe_list["iron-plate"].enabled = true
  recipe_list["copper-plate"].enabled = true
  recipe_list["stone-furnace"].enabled = true
  recipe_list["iron-stick"].enabled = true
  recipe_list["wooden-chest"].enabled = true
  recipe_list["iron-gear-wheel"].enabled = true
  recipe_list["burner-mining-drill"].enabled = true
  recipe_list["transport-belt"].enabled = true
  recipe_list["burner-inserter"].enabled = true
  recipe_list["pipe"].enabled = true
  recipe_list["pipe-to-ground"].enabled = true
  recipe_list["boiler"].enabled = true
  recipe_list["steam-engine"].enabled = true
  recipe_list["electronic-circuit"].enabled = true
  recipe_list["copper-cable"].enabled = true
  recipe_list["pistol"].enabled = true
  recipe_list["firearm-magazine"].enabled = true
  recipe_list["light-armor"].enabled = true
  game.players[1].clear_recipe_notifications()

  local character = player.character
  character.insert{name = "iron-plate", count = 20}
  character.insert{name = "copper-plate", count = 15}
  character.insert{name = "coal", count = 20}
  character.insert{name = "transport-belt", count = 50}
  character.insert{name = "electric-mining-drill", count = 2}
  character.insert{name = "inserter", count = 10}
  character.insert{name = "stone-furnace", count = 10}
  character.insert{name = "pistol", count = 1}
  character.insert{name = "firearm-magazine", count = 5}
end

local story_table =
{
  {
    {
      condition = story_elapsed_check(3),
      action = function()
        think('find-ship')
      end
    },
    {
      condition = story_elapsed_check(5),
      action = function()
        think('use-radar')
      end
    },
    {
      condition = story_elapsed_check(5),
      action = function()
        think('simple-setup')
      end
    },
    {
     condition = story_elapsed_check(3),
     action =
     function()
      game.players[1].force.recipes["offshore-pump"].enabled = true
     end
    },
    {
     init =
     function()
       if global.pump == nil or not global.pump.valid then
         set_goal({"goal-build-pump"})
       else
         return true
       end
     end,
     condition =
     function(event)
        if event.name == defines.events.on_built_entity and
           event.created_entity.name == "offshore-pump" then
          return true
        end
        return false
      end
    },

    {
      condition = story_elapsed_check(1),
      action = function()
        if (not global.boiler.fluidbox[1] or
            global.boiler.fluidbox[1].amount < 0.01) then
          set_goal({"goal-connect-boiler-to-water"})
        end
      end
    },
    {
      condition = function()
        if global.boiler.fluidbox then
          return (global.boiler.fluidbox[1] ~= nil)
        end
      end,
      action = function()
          set_goal("")
      end
    },
    {
      condition = story_elapsed_check(3),
      init=
      function()
        if (global.boiler.energy <= 0.1) then
          set_goal({"goal-fuel-into-boiler"})
        end
      end
    },
    {
      condition = function() return global.boiler.energy > 0.1 end,
      action = function()
          set_goal({"goal-connect-boiler-to-steam-engine"})
      end
    },
    {
      condition = function() return
        global.steam_engine.fluidbox[1] and
        global.steam_engine.fluidbox[1].amount > 0 end,
      action = function()
          set_goal("")
      end
    },
    {
      condition = story_elapsed_check(2),
      action = function()
        if (global.steam_engine.energy <= 0.1) then
          story_show_message_dialog{text={"msg-cold-water"},
                                 point_to={type="entity", entity=global.steam_engine}}
        end
      end
    },

    {
      condition = story_elapsed_check(3),
      action = function() end
    },
    {
      condition = function() return not game.players[1].opened end,
      action = function()
        think('electricity-setup')
      end
    },
    {
      condition = story_elapsed_check(3),
      action = function()
        local recipe_list = game.players[1].force.recipes
        recipe_list["small-electric-pole"].enabled = true
        recipe_list["electric-mining-drill"].enabled = true
        recipe_list["inserter"].enabled = true
        set_goal({"goal-power-electric-mining-drill"})
      end
    },
    {
      condition = function() return global.mining_drill.energy > 0 end,
      action = function()
        set_goal("")
      end
    },
    {
      condition = story_elapsed_check(3),
      action = function()
        think('piece-of-cake')
        --game.print({"think-piece-of-cake"})
      end
    },

    {
      condition = story_elapsed_check(7),
      action = function()
        think('factory-instruction')
        for index, entity in pairs(global.intro_entities) do
          entity.minable = true
          entity.destructible = true
        end
        local recipe_list = game.players[1].force.recipes
        recipe_list["assembling-machine-1"].enabled = true
      end
    },
    {
      condition = story_elapsed_check(5),
      action = function()
        think('get-to-work')
        --game.print({"think-get-to-work"})
      end
    },
    {
      condition = story_elapsed_check(5),
      action = function()
        think('beware-of-creepers')
        --game.print({"think-beware-of-creepers"})
      end
    },
    {
      init = function()
        set_goal({"goal-build-radars",0,3})
        global.radars = 0
        local recipe_list = game.players[1].force.recipes
        recipe_list["radar"].enabled = true
      end,
      update = function(event)
        manage_attacks(event.tick)
        check_light()
        check_machine_gun()
        check_ammo(event.tick)

        if event.name == defines.events.on_entity_died and event.entity.name == 'radar' then
          global.radars = global.radars - 1
          set_goal({"goal-build-radars",global.radars,3},true)
        elseif event.name == defines.events.on_built_entity and event.created_entity.name == 'radar' then
          global.radars = global.radars + 1
          set_goal({"goal-build-radars",global.radars,3})
        elseif event.name == defines.events.on_player_mined_entity and event.entity.name =='radar' then
          global.radars = global.radars - 1
          set_goal({"goal-build-radars",global.radars,3},true)
        elseif event.name == defines.events.on_entity_damaged and event.entity.name =='radar' and global.radar_damaged == nil and event.force.name == 'enemy' and event.cause then
          global.damaging_biter = event.cause
          global.radar_damaged = true
          story_show_message_dialog
          {
            text={"msg-radar-under-attack"},
            point_to={type="entity", entity=event.entity}
          }
        end

        if event.name == defines.events.on_built_entity and event.created_entity.name == 'burner-mining-drill' and not global.explained_electric_mining then
          think('electric-mining')
          global.explained_electric_mining = true
        end

        if global.radar_damaged and global.repair_pack_given == nil and (global.damaging_biter == nil or global.damaging_biter.valid == false) then
          think('repair-pack')
          local recipe_list = game.players[1].force.recipes
          recipe_list["repair-pack"].enabled = true
          global.repair_pack_given = true
        end

        if global.radars == 1 and not global.explained_radar_function then
          story_show_message_dialog{text = {"msg-start-with-radars-1"}}
          global.explained_radar_function = true
        end

        if global.radars == 2 and not global.explained_power_need then
          story_show_message_dialog{text = {"msg-start-with-radars-2"}}
          global.explained_power_need = true
        end

      end,
      condition = function(event)
        return global.radars >= 3
      end
    },
    {
      action = function()
        if global.gun_turret_gained == nil then
          global.gun_turret_gained = true
          game.players[1].force.recipes["gun-turret"].enabled = true
        end
        story_show_message_dialog{text = {"msg-protect-radars"}}
      end
    },
    {
      condition = story_elapsed_check(5),
      action = function()
        global.sectors_scanned = 0;
      end
    },
    {
      init = function()
        set_goal({"goal-radar-progress",global.sectors_scanned,50})
      end,
      update = function(event)
        manage_attacks(event.tick)
        check_light()
        check_machine_gun()
        check_ammo(event.tick)
        check_player_being_lazy()

        scanned = (event.name == defines.events.on_sector_scanned)
        if scanned then
          global.sectors_scanned = global.sectors_scanned + 1
          set_goal({"goal-radar-progress",global.sectors_scanned,50},global.sectors_scanned < 50)
        elseif event.name == defines.events.on_entity_damaged and event.entity.name =='radar' and global.radar_damaged == nil and event.force.name == 'enemy' and event.cause then
          global.damaging_biter = event.cause
          global.radar_damaged = true
          story_show_message_dialog
          {
            text={"msg-radar-under-attack"},
            point_to={type="entity", entity=event.entity}
          }
        end

        if global.radar_damaged and global.repair_pack_given == nil and (global.damaging_biter == nil or global.damaging_biter.valid == false) then
          think('repair-pack')
          local recipe_list = game.players[1].force.recipes
          recipe_list["repair-pack"].enabled = true
          global.repair_pack_given = true
        end

      end,
      condition = function()
        return global.sectors_scanned >= 50
      end
    },
    {
      condition = story_elapsed_check(4),
      action = function()
        msg('sector-scan-completed')
        set_goal("",true)
      end
    },
    {
      condition = story_elapsed_check(4),
      action = function()
        msg('ship-wreck-located')
      end
    },
    {
      condition = story_elapsed_check(4),
      action = function()
        think('explore-ship-wreck')
      end
    },
    {
      condition = story_elapsed_check(4),
      action = function()
        game.set_game_state({game_finished=true, player_won=true, can_continue=false, next_level = "level-04"})
      end
    }
  }
}

story_init_helpers(story_table)

function manage_attacks(tick)
  -- set default value of last_attack_at, it contains tick of the last attack
  if global.last_attack_at == nil then
    global.last_attack_at = 0
  end
  -- set default value of attack count
  if global.attack_count == nil then
    global.attack_count = 4
  end
  -- set default of attack_frequency, it specifies how many seconds between attacks
  if global.attack_frequency == nil then
    global.attack_frequency = 180
  end
  if tick - global.last_attack_at > 60 * global.attack_frequency then
    global.last_attack_at = tick
    local radars = game.players[1].surface.find_entities_filtered({name='radar'})
    if #radars > 0 then
      game.players[1].surface.set_multi_command
      {
        command =
        {
          type=defines.command.attack,
          target=game.players[1].character,
          distraction=defines.distraction.by_enemy
        },
        unit_count = global.attack_count - 1
      }
      game.players[1].surface.set_multi_command
      {
        command =
        {
          type=defines.command.attack,
          target=radars[math.random(1,#radars)],
          distraction=defines.distraction.by_enemy
        },
        unit_count = 1
      }
    else
      game.players[1].surface.set_multi_command
      {
        command =
        {
          type=defines.command.attack,
          target=game.players[1].character,
          distraction=defines.distraction.by_enemy
        },
        unit_count = global.attack_count
      }
    end

    global.attack_count = global.attack_count + 1

    -- Give the player submachine gun when 6 creepers start to attack
    if global.attack_count >= 6 and global.submachine_gained == nil then -- 6 min
      global.submachine_gained = true
      think('need-better-weapon')
      local recipe_list = game.players[1].force.recipes
      recipe_list["submachine-gun"].enabled = true
      return
    end
  end
end

-- Gives lamp to the player when it gets dark
function check_light()
  if game.surfaces['nauvis'].darkness > 0.5 and
     global.lampallowed == nil then
    global.lampallowed = true
    think('need-light')
    --story_show_message_dialog{text = {"msg-need-light"}}
    local recipe_list = game.players[1].force.recipes
    recipe_list["small-lamp"].enabled = true
  end
end

function check_player_being_lazy()
  if not global.explained_no_lazy and global.sectors_scanned > 10 then
    if game.surfaces[1].count_entities_filtered({name='radar'}) == 3 then
      think('build-more-radars')
      global.explained_no_lazy = true
    end
  end
end

function check_ammo(tick)
  if not global.explained_ammo and tick % 120 == 0 then
    if game.players[1].character.get_item_count("firearm-magazine") < 4 and game.players[1].in_combat == false then
      think("craft-more-ammo")
      global.explained_ammo = true
    end
  end
end

function check_machine_gun()
  if global.submachine_gained and
     global.submachine_built == nil and
     game.players[1].character.get_item_count("submachine-gun") > 0 then
    global.submachine_built = true
    story_show_message_dialog{text = {"msg-active-gun"}}
    return
  end

  if global.submachine_built and
     global.submachine_equipped == nil and
     game.players[1].character.get_inventory(defines.inventory.character_guns).get_item_count("submachine-gun") > 0 then
    global.submachine_equipped = true
    story_show_message_dialog{text = {"msg-change-active-gun"}}
  end
end

function check_for_player_death(event)
  if event.name == defines.events.on_player_died then
    game.set_game_state({game_finished=true, player_won=false, can_continue=false})
  end
end

local init = function()
  global.story = story_init()
  game.map_settings.pollution.enabled = false
  game.map_settings.enemy_expansion.enabled = false
  game.forces.enemy.evolution_factor = 0
  game.map_settings.enemy_evolution.enabled = false

  --game.forces.player.set_spawn_position(spawn_position, game.surfaces[1])

  global.mining_drill = game.get_entity_by_tag("mining-drill")
  global.steam_engine = game.get_entity_by_tag("steam-engine")
  global.boiler = game.get_entity_by_tag("boiler")

  local entities =
  {
    global.mining_drill,
    global.steam_engine,
    global.boiler
  }

  for index, entity in pairs(entities) do
    entity.minable = false
    entity.destructible = false
  end

  global.intro_entities = entities
end

local story_events =
{
  defines.events.on_tick,
  defines.events.on_sector_scanned,
  defines.events.on_built_entity,
  defines.events.on_player_mined_entity,
  defines.events.on_entity_died,
  defines.events.on_entity_damaged,
  defines.events.on_player_died
}

script.on_event(story_events, function(event)
  if game.players[1].character then
    check_for_player_death(event)
    story_update(global.story, event, "level-04")
  end
end)

script.on_init(init)

script.on_event(defines.events.on_player_created, function(event)
  on_player_created(event)
end)