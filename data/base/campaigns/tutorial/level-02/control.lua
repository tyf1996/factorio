require("story")
require('util')

local think = function(thought)
  game.players[1].print({"","[img=entity/character][color=orange]",{"engineer-title"},": [/color]",{"think-"..thought}})
end

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

local on_player_created = function(event)
  local player = game.players[event.player_index]
  player.disable_recipe_groups()
  player.disable_recipe_subgroups()
  player.minimap_enabled = false
  player.force.disable_all_prototypes()
  player.force.disable_research()
  player.surface.always_day = true -- Don't bother the player with night in this early mission

  local recipe_list = player.force.recipes
  recipe_list["iron-plate"].enabled = true
  recipe_list["copper-plate"].enabled = true
  recipe_list["stone-furnace"].enabled = true
  recipe_list["wooden-chest"].enabled = true
  recipe_list["iron-gear-wheel"].enabled = true
  recipe_list["burner-mining-drill"].enabled = true
  recipe_list["transport-belt"].enabled = true
  recipe_list["burner-inserter"].enabled = true
  game.players[1].clear_recipe_notifications()
  if player.character then
    player.character.insert{name = "coal", count = 20}
  end

end

local init = function()

  global.story = story_init()
  game.map_settings.pollution.enabled = false

  global.inserter_chest = game.get_entity_by_tag("inserter-chest")  or error("Inserter chest missing")
  global.inserter_chest_position = global.inserter_chest.position
  global.inserter_chest_position.energy = 0

  global.inserter_furnace = game.get_entity_by_tag("inserter-furnace") or error("Inserter furnace missing")
  global.inserter_furnace_position = global.inserter_furnace.position
end

function check_for_player_death(event)
  if event.name == defines.events.on_player_died then
    game.set_game_state({game_finished=true, player_won=false, can_continue=false})
  end
end

local story_table =
{
  ["update-functions"]=
  {
   ["check-inserter-1"]=
   function(event, story)
     if not global.inserter_chest.valid then
       story_jump_to(story, "build-the-accidentally-mined-inserter")
     end
   end,
   ["check-inserter-2"]=
   function(event, story)
     if not global.inserter_furnace.valid then
       story_jump_to(story, "build-the-accidentally-mined-inserter-2")
     end
   end
  },
  {
    {
      init = function(event, story)
        story_add_update(story, "check-inserter-1")
      end,
      condition = story_elapsed_check(3),
      action = function()
        think("found-mining-site")
      end
    },
    {
      condition = story_elapsed_check(4),
      action = function()
        think("robotic-arm")
      end
    },
    {
      condition = story_elapsed_check(4.6),
      action =
      function(event,story)
        if global.inserter_chest.energy > 0 then
          story_jump_to(story,"inserter-explaination")
        else
          story_show_message_dialog{text={"msg-inserter-no-power"},
                                    point_to={type="entity", entity=global.inserter_chest}}
        end
      end
    },
    {
      condition = story_elapsed_check(1),
      action =
      function()
        set_goal({"goal-open-machine-gui"})
        game.players[1].set_gui_arrow({type="entity", entity=global.inserter_chest})
      end
    },
    {
      name = "wait-to-open-inserter-1",
      condition = function() return global.inserter_chest == game.players[1].opened end,
      action =
      function()
        set_goal({"goal-insert-fuel-into-inserter-1"})
        game.players[1].clear_gui_arrow()
      end
    },
    {
      condition = function() return global.inserter_chest.energy > 0 end,
      action = function()
        set_goal({"goal-close-inserter-gui"})
      end
    },
    {
      name = 'inserter-explaination',
      condition = function() return game.players[1].opened == nil end,
      action =
      function()
        set_goal("")
          story_show_message_dialog{text={"msg-inserter-introduction-1"},
                                 image = "inserter-explanation.png",
                                 point_to={type="entity", entity=global.inserter_chest}}
      end
    },
    {
      action =
      function(event, story)
          story_show_message_dialog{text={"msg-inserter-introduction-2"},
                                 image = "inserter-usage-explanation.png",
                                 point_to={type="entity", entity=global.inserter_chest}}
        story_remove_update(story, "check-inserter-1")
        game.players[1].game_view_settings.update_entity_selection = true
      end
    },
    {
      condition = story_elapsed_check(5),
      action = function()
        local pistol_chest = game.get_entity_by_tag('pistol-chest')
        if pistol_chest and pistol_chest.valid then
          set_goal({"goal-inspect-chest"})
          global.arrow = game.players[1].surface.create_entity{name="orange-arrow-with-circle", position = pistol_chest.position}
        end
      end
    },
    {

      condition = function()
        local pistol_chest = game.get_entity_by_tag('pistol-chest')
        return pistol_chest == nil or (pistol_chest.get_inventory(defines.inventory.chest).is_empty() and
        game.players[1].cursor_stack.valid_for_read == false)
      end,
      action = function()
        if global.arrow then global.arrow.destroy() end
        set_goal({"goal-close-inventory"})
      end
    },
    {
      condition = function()
        return game.players[1].opened == nil
      end,
      action = function()
        think("chest-content-useful")
        set_goal("")
      end
    },
    {
      condition = story_elapsed_check(2),
      action = function()
        if not (game.players[1].character.get_inventory(defines.inventory.character_guns)[1].valid_for_read and
          game.players[1].character.get_inventory(defines.inventory.character_guns)[1].name == "pistol") then
          story_show_message_dialog
          {
            text = {"msg-gun-equipment"},
            point_to =
            {
              type = "item_stack",
              inventory_index = defines.inventory.character_guns,
              item_stack_index = 1,
              source = "player-equipment-bar"
            }
          }
        end
      end
    },
    {
      condition = story_elapsed_check(0.5),
      action = function()
        if not (game.players[1].character.get_inventory(defines.inventory.character_guns)[1].valid_for_read and
          game.players[1].character.get_inventory(defines.inventory.character_guns)[1].name == "pistol") then
          set_goal({"goal-equip-gun"})
          game.players[1].set_gui_arrow{type = "item_stack", inventory_index = defines.inventory.character_guns, item_stack_index = 1, source="player-equipment-bar"}
        end
      end
    },
    {
      condition = function() return game.players[1].character.get_inventory(defines.inventory.character_guns)[1].valid_for_read and
          game.players[1].character.get_inventory(defines.inventory.character_guns)[1].name == "pistol" end,
      action = function()
        if game.players[1].character.get_inventory(defines.inventory.character_ammo).get_item_count("firearm-magazine") == 0 then
          set_goal({"goal-equip-ammo"})
          game.players[1].set_gui_arrow{type = "item_stack", inventory_index = defines.inventory.character_ammo, item_stack_index = 1, source="player-equipment-bar"}
        end
      end
    },
    {
      condition = function() return game.players[1].character.get_inventory(defines.inventory.character_ammo)[1].valid_for_read and
          game.players[1].character.get_inventory(defines.inventory.character_ammo)[1].name == "firearm-magazine" end,
      action = function()
        set_goal("")
        game.players[1].character.clear_gui_arrow()
      end
    },
    {
      init = function()
        set_goal({"goal-close-inventory"})
      end,
      condition = function()
        return game.players[1].opened == nil and game.players[1].opened_self == false
      end,
      action = function()
        set_goal("")
        if game.players[1].surface.count_entities_filtered({name='small-biter'}) < 2 then
          local pos = {
            x=0,
            y=game.players[1].surface.map_gen_settings.height/-2
          }
          for k=1,4 do
            game.players[1].surface.create_entity({
              name='small-biter',
              position=game.players[1].surface.find_non_colliding_position('small-biter',pos,5,0.1)
            })
          end
        end
      end
    },
    {
      condition = story_elapsed_check(2),
      action =
      function()
        think("creepers-coming")
        game.players[1].character.clear_gui_arrow()
      end
    },
    {
      condition = story_elapsed_check(3),
      action = function()
        story_show_message_dialog
        {
          text = {"msg-shooting"},
          point_to = {type = "entity", entity = game.players[1].character}
        }
        global.biters_killed = 0
      end
    },
    {
      condition = story_elapsed_check(1.5),
      action = function()
        set_goal({"kill-creepers"})
      end
    },
    {
      init = function()
        game.surfaces[1].create_entity({name='small-biter',position={x=-51,y=-55}})
        game.surfaces[1].create_entity({name='small-biter',position={x=-55,y=-55}})

        game.players[1].surface.set_multi_command
        {
          command =
          {
            type=defines.command.attack,
            target=game.players[1].character,
            distraction=defines.distraction.none
          },
          unit_count = 2
        }
      end,
      update = function(event)
        if event.name == defines.events.on_entity_died and
           event.entity.name == "small-biter" then
          global.biters_killed = global.biters_killed + 1
        end
      end,
      condition = function() return global.biters_killed >= 2 end,
      action = function()
        set_goal("")
        think("creepers-dead")
      end
    },
    {
      condition = story_elapsed_check(3),
      action = function()
        set_goal("")
        think("prepare")
      end
    },
    {
      init = function(event, story) story_add_update(story, "check-inserter-2") end,
      condition = story_elapsed_check(5),
      action = function(event, story)
        if global.inserter_furnace.direction == defines.direction.east then
          story_jump_to(story,"more-machines")
        else
          story_show_message_dialog
          {
            text = {"msg-inserter-2-reversed"},
            point_to = {type="entity", entity = global.inserter_furnace}
          }
        end
      end
    },
    {
      condition = story_elapsed_check(0.5),
      action = function()
        game.players[1].set_gui_arrow({type="entity", entity=global.inserter_furnace})
        set_goal({"goal-rotate-inserter-2"})
      end
    },
    {
      name = "wait-to-rotate-inserter-2",
      condition = function()
          return global.inserter_furnace.drop_target ~= nil and
                 global.inserter_furnace.drop_target.name == "stone-furnace"
        end,
      action = function(event, story)
        set_goal("")
        game.players[1].clear_gui_arrow()
        think("inserter2-working")
        story_remove_update(story, "check-inserter-2")
      end
    },
    {
      condition = story_elapsed_check(3),
      action = function()
        game.players[1].clear_gui_arrow()
        story_show_message_dialog
        {
          text = {"msg-rotations-explained"},
          point_to = {type = "entity", entity = game.players[1].character}
        }
      end
    },
    {
      name = 'more-machines',
      condition = story_elapsed_check(3),
      action = function()
        think("need-more-machines")
      end
    },
    {
      condition = story_elapsed_check(4)
    },
    {
      init = function(event, story)
        global.mined_stone_count = 0
        story_remove_update(story, "check-inserter-1")
        story_remove_update(story, "check-inserter-2")
      end,
      update = (function()
        --jesus...
        --yeah i know what you mean...
        local only_update = false

        return function(event)

          progress = event.name == defines.events.on_built_entity and
                     (event.created_entity.name == "burner-mining-drill" or
                      event.created_entity.name == "stone-furnace")

          if event.name == defines.events.on_player_mined_item and
             event.item_stack.name == "stone" then
             global.mined_stone_count = global.mined_stone_count + 1
          end

          if global.mined_stone_count >= 5 and global.advice_to_mine_stone == nil then
            think("automated-stone-mining")
            global.advice_to_mine_stone = true
          end

          set_goal
          (
            {
              "goal-build-machines",
              game.players[1].force.get_entity_count("burner-mining-drill"),
              10,
              game.players[1].force.get_entity_count("stone-furnace"),
              5
            },
            true
          )

          only_update = true
        end
      end)(),
      condition = function()
        return game.players[1].force.get_entity_count("burner-mining-drill") >= 10 and
               game.players[1].force.get_entity_count("stone-furnace") >= 5
      end,
      action = function()
        think("got-machines")
        set_goal("")
      end
    },
    {
      condition = story_elapsed_check(5),
      action = function()
        think("need-more-resources")
      end
    },
    {
      update = (function()
        local only_update = false
        return function(event)
          local iron_plate_count = game.players[1].character.get_item_count("iron-plate")
          local copperplatecount = game.players[1].character.get_item_count("copper-plate")
          local coal_count = game.players[1].character.get_item_count("coal")
          set_goal
          (
            {
              "goal-get-resources",
              iron_plate_count,
              150,
              copperplatecount,
              50,
              coal_count,
              75
            },
            only_update
          )
          only_update = true
        end
      end)(),
      condition = function()
        return game.players[1].character.get_item_count("iron-plate") >= 150 and
               game.players[1].character.get_item_count("copper-plate") >= 50 and
               game.players[1].character.get_item_count("coal") >= 75
      end,
      action = function()
        think("got-resources-1")
        set_goal("")
      end
    },
    {
      condition = story_elapsed_check(5),
      action = function()
        think("time-to-move-on")
      end
    },
    {
      condition = story_elapsed_check(5),
      action = function()
        game.set_game_state({game_finished=true, player_won=true, can_continue=true,next_level='level-03'})
      end
    }
  },
  {
    {
     name = "build-the-accidentally-mined-inserter",
     init = function(event, story)
       story_remove_update(story, "check-inserter-1")
     end,
     action = function()
       story_show_message_dialog
       {
         text={"msg-mined-inserter-instead-of-open"},
         point_to = {type = "position", position = global.inserter_chest_position}}
       set_arrow({name="orange-arrow-with-circle", position = global.inserter_chest_position})
     end
    },
    {
      action = function()
        set_goal({"goal-build-inserter-back"})
      end
    },
    {
      condition = function(event)
        if event.name == defines.events.on_built_entity and
           event.created_entity.name == "burner-inserter" then

          if not (event.created_entity.position.x == global.inserter_chest_position.x and
            event.created_entity.position.y == global.inserter_chest_position.y) then
            story_show_message_dialog
            {
              text = {"msg-inserter-1-wrong-position"},
              point_to = {type = "entity", entity = event.created_entity}
            }
            return false
          else
            event.created_entity.direction = defines.direction.west
            global.inserter_chest = event.created_entity
            return true
          end
        end
      end,
      action = function(event, story)
        set_arrow()
        story_jump_to(story, "wait-to-open-inserter-1")
        story_add_update(story, "check-inserter-1")
      end
    }
  },
  {
    {
     name = "build-the-accidentally-mined-inserter-2",
     init = function(event, story)
       story_remove_update(story, "check-inserter-2")
     end,
     action = function()
       story_show_message_dialog
       {
         text = {"msg-mined-inserter-instead-of-open-2"},
         point_to = {type="position", position = global.inserter_furnace_position}
       }
       set_arrow({name="orange-arrow-with-circle", position = global.inserter_furnace_position})
     end
    },
    {
      action = function()
        set_goal({"goal-build-inserter-back"})
      end
    },
    {
      condition = function(event)
        if event.name == defines.events.on_built_entity and
           event.created_entity.name == "burner-inserter" then

          if not table.compare(event.created_entity.position, global.inserter_furnace_position or {0,0}) then
            story_show_message_dialog
            {
              text = {"msg-inserter-2-wrong-position"},
              point_to = {type = "entity", entity = event.created_entity}
            }
            return false
          end

          global.inserter_furnace = event.created_entity
          return true
        end
      end,
      action = function(event, story)
        set_arrow()
        story_jump_to(story, "wait-to-rotate-inserter-2")
        story_add_update(story, "check-inserter-2")
      end
    }
  }
}

story_init_helpers(story_table)

local story_events =
{
  defines.events.on_tick,
  defines.events.on_entity_died,
  defines.events.on_built_entity,
  defines.events.on_player_mined_item,
  defines.events.on_player_died
}

script.on_event(story_events, function(event)
  if game.players[1].character then
    check_for_player_death(event)
    story_update(global.story, event, "level-03")
  end
end)

script.on_init(init)

script.on_event(defines.events.on_player_created, function(event)
  on_player_created(event)
end)