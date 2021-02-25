local combat_technologies =
{
  "follower-robot-count",
  "energy-weapons-damage",
  "laser-shooting-speed",
  "physical-projectile-damage",
  "weapon-shooting-speed",
  "stronger-explosives",
  "refined-flammables",
  "artillery-shell-range",
  "artillery-shell-speed"
}

local make_modifier_list = function()
  local modifier_list =
  {
    character_modifiers =
    {
      character_running_speed_modifier = 0,
      character_health_bonus = 0,
      character_crafting_speed_modifier = 0,
      character_mining_speed_modifier = 0,
      character_build_distance_bonus = 0,
      character_reach_distance_bonus = 0
    },
    force_modifiers =
    {
      worker_robots_speed_modifier = 0,
      worker_robots_storage_bonus = 0,
      worker_robots_battery_modifier = 0,
      mining_drill_productivity_bonus = 0,
      inserter_stack_size_bonus = 0,
      stack_inserter_capacity_bonus = 0,
      laboratory_speed_modifier = 0,
      laboratory_productivity_bonus = 0,
      following_robots_lifetime_modifier = 0,
      maximum_following_robot_count = 0,
      train_braking_force_bonus = 0
    },
    turret_attack_modifier = {},
    ammo_damage_modifier ={},
    gun_speed_modifier = {}
  }
  local entities = game.entity_prototypes
  local turret_types =
  {
    ["ammo-turret"] = true,
    ["electric-turret"] = true,
    ["fluid-turret"] = true,
    ["artillery-turret"] = true,
    ["turret"] = true
  }
  for name, entity in pairs (entities) do
    if turret_types[entity.type] then
      modifier_list.turret_attack_modifier[name] = 0
    end
  end
  for name, ammo in pairs (game.ammo_category_prototypes) do
    modifier_list.ammo_damage_modifier[name] = 0
    modifier_list.gun_speed_modifier[name] = 0
  end
  return modifier_list
end

local balance = {script_data = {}}

balance.disable_combat_technologies = function(force)
  if balance.script_data.config.team_config.unlock_combat_research then return end --If true, then we want them to stay unlocked
  local tech = force.technologies
  for k, name in pairs (combat_technologies) do
    local i = 1
    repeat
      local full_name = name.."-"..i
      if tech[full_name] then
        tech[full_name].researched = false
      end
      i = i + 1
    until not tech[full_name]
  end
end

balance.apply_character_modifiers = function(player)
  local apply = function(player, name, modifier)
    player[name] = modifier
  end
  --Because some things want greater than 0, others wants greater than -1.
  --Better to just catch the error than making some complicated code.
  local modifier_list = balance.script_data.config.modifier_list or make_modifier_list()
  for name, modifier in pairs (modifier_list.character_modifiers) do
    local status, error = pcall(apply, player, name, modifier)
    if not status then
      log(name)
      log(error)
      modifier_list.character_modifiers[name] = 0
    end
  end
end

balance.init = function()
  balance.script_data.config.modifier_list = make_modifier_list()
end

balance.apply_combat_modifiers = function(force)

  local entities = game.entity_prototypes
  local modifier_list = balance.script_data.config.modifier_list or make_modifier_list()
  --This is the only one which needs to be at least 1...
  modifier_list.force_modifiers.maximum_following_robot_count = math.max(modifier_list.force_modifiers.maximum_following_robot_count, 1)

  for name, modifier in pairs (modifier_list.force_modifiers) do
    force[name] = force[name] + modifier
  end

  for name, modifier in pairs (modifier_list.turret_attack_modifier) do
    if entities[name] then
      force.set_turret_attack_modifier(name, force.get_turret_attack_modifier(name) + modifier)
    else
      log(name.." removed from turret attack modifiers, as it is not a valid turret prototype")
      modifier_list.turret_attack_modifier[name] = nil
    end
  end

  local ammo = game.ammo_category_prototypes

  for name, modifier in pairs (modifier_list.ammo_damage_modifier) do
    if ammo[name] then
      force.set_ammo_damage_modifier(name, force.get_ammo_damage_modifier(name) + modifier)
    else
      log(name.." removed from ammo damage modifiers, as it is not a valid turret prototype")
      modifier_list.ammo_damage_modifier[name] = nil
    end
  end

  for name, modifier in pairs (modifier_list.gun_speed_modifier) do
    if ammo[name] then
      force.set_gun_speed_modifier(name, force.get_gun_speed_modifier(name) + modifier)
    else
      modifier_list.gun_speed_modifier[name] = nil
    end
  end

end

return balance
