--This is serialised on init.
local config = {}

local default_unit_waves = function()
return
  {
    ["small-biter"] =      {0,  7},
    ["medium-biter"] =     {5,  14},
    ["big-biter"] =        {12, nil},
    ["behemoth-biter"] =   {16, nil},

    ["small-spitter"] =    {3,  12},
    ["medium-spitter"] =   {7,  16},
    ["big-spitter"] =      {14, nil},
    ["behemoth-spitter"] = {18, nil}
  }
end

local default_prices = function()
  return
  {
    ["small-biter"] = 25,
    ["medium-biter"] = 125,
    ["big-biter"] = 350,
    ["behemoth-biter"] = 800,

    ["small-spitter"] = 35,
    ["medium-spitter"] = 140,
    ["big-spitter"] = 400,
    ["behemoth-spitter"] = 1000
  }
end

local default_bounties = function()
  return
  {
    ["small-worm-turret"] = 50,
    ["medium-worm-turret"] = 100,
    ["big-worm-turret"] = 250,
    ["behemoth-worm-turret"] = 500,

    ["biter-spawner"] = 250,
    ["spitter-spawner"] = 250
  }
end

local default_starting_items = function()
  return
  {
    ["iron-plate"] = 200,
    ["pipe"] = 200,
    ["pipe-to-ground"] = 50,
    ["copper-plate"] = 200,
    ["steel-plate"] = 200,
    ["iron-gear-wheel"] = 250,
    ["transport-belt"] = 600,
    ["underground-belt"] = 40,
    ["splitter"] = 40,
    ["gun-turret"] = 8,
    ["stone-wall"] = 50,
    ["repair-pack"] = 20,
    ["inserter"] = 100,
    ["burner-inserter"] = 50,
    ["small-electric-pole"] = 50,
    ["medium-electric-pole"] = 50,
    ["big-electric-pole"] = 15,
    ["burner-mining-drill"] = 50,
    ["electric-mining-drill"] = 50,
    ["stone-furnace"] = 35,
    ["steel-furnace"] = 20,
    ["electric-furnace"] = 8,
    ["assembling-machine-1"] = 50,
    ["assembling-machine-2"] = 20,
    ["assembling-machine-3"] = 8,
    ["electronic-circuit"] = 200,
    ["fast-inserter"] = 100,
    ["long-handed-inserter"] = 100,
    ["substation"] = 10,
    ["boiler"] = 10,
    ["offshore-pump"] = 1,
    ["steam-engine"] = 20,
    ["chemical-plant"] = 20,
    ["oil-refinery"] = 5,
    ["pumpjack"] = 10,
    ["small-lamp"] = 20
  }
end

local default_respawn_items = function()
  return
  {
    ["submachine-gun"] = 1,
    ["firearm-magazine"] = 40,
    ["shotgun"] = 1,
    ["shotgun-shell"] = 20,
    ["construction-robot"] = 10,
    ["modular-armor"] = 1,
    ["exoskeleton-equipment"] = 1,
    ["personal-roboport-mk2-equipment"] = 1,
    ["battery-equipment"] = 1,
    ["solar-panel-equipment"] = 11
  }
end

config.difficulties =
{

  easy =
  {
    starting_area_size = 2.25,
    day_settings =
    {
      ticks_per_day = 21600,
      dusk = 0.25,
      evening = 0.45,
      morning = 0.50,
      dawn = 0.70
    },
    starting_chest_items = default_starting_items(),
    respawn_items = default_respawn_items(),
    bounties = default_bounties(),
    unit_waves = default_unit_waves(),
    wave_power_function = "default",
    speed_multiplier_function = "default",
    starting_evolution_factor = 0.1,
    bounty_modifier = 1,
    unit_prices = default_prices()
  },

  normal =
  {
    starting_area_size = 1.75,
    day_settings =
    {
      ticks_per_day = 21600,
      dusk = 0.25,
      evening = 0.45,
      morning = 0.6,
      dawn = 0.75
    },
    starting_chest_items = default_starting_items(),
    respawn_items = default_respawn_items(),
    bounties = default_bounties(),
    unit_waves = default_unit_waves(),
    wave_power_function = "default",
    speed_multiplier_function = "default",
    starting_evolution_factor = 0.2,
    bounty_modifier = 1,
    unit_prices = default_prices()
  },

  hard =
  {
    starting_area_size = 1.5,
    day_settings =
    {
      ticks_per_day = 21600,
      dusk = 0.20,
      evening = 0.40,
      morning = 0.60,
      dawn = 0.80
    },
    starting_chest_items = default_starting_items(),
    respawn_items = default_respawn_items(),
    bounties = default_bounties(),
    unit_waves = default_unit_waves(),
    wave_power_function = "hard",
    speed_multiplier_function = "default",
    starting_evolution_factor = 0.4,
    bounty_modifier = 0.5,
    unit_prices = default_prices()
  }

}

config.map_gen_settings =
{
  autoplace_controls =
  {
    coal =
    {
      frequency = 1,
      richness = 2,
      size = 2
    },
    ["copper-ore"] =
    {
      frequency = 1,
      richness = 2,
      size = 2
    },
    ["crude-oil"] =
    {
      frequency = 2,
      richness = 2,
      size = 2
    },
    ["enemy-base"] =
    {
      frequency = 10,
      richness = 1,
      size = 1
    },
    ["iron-ore"] =
    {
      frequency = 1,
      richness = 2,
      size = 2
    },
    stone =
    {
      frequency = 1,
      richness = 2,
      size = 2
    },
    trees =
    {
      frequency = 4,
      richness = 1,
      size = 0.15
    },
    ["uranium-ore"] =
    {
      frequency = 3,
      richness = 2,
      size = 0.5
    }
  },
  autoplace_settings = {},
  cliff_settings =
  {
    cliff_elevation_0 = 25,
    cliff_elevation_interval = 20,
    name = "cliff",
    richness = 0.2
  },
  height = 2000000,
  property_expression_names =
  {
    elevation = "0_17-island"
  },
  research_queue_from_the_start = "after-victory",
  starting_area = 1.2,
  starting_points =
  {
    {
      x = 0, --(1024 / 2) - 64,
      y = 0
    }
  },
  terrain_segmentation = 1,
  water = 1,
  width = 2000000
}

config.infinite = false

return config
