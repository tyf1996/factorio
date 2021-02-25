local config = {}

config.starting_money = 10000

config.prices_param =
{
  ingredient_exponent = 1,
  normalise = function(number)
    local factor = math.log(number, 2)
    return math.floor(number / factor)
  end
}

config.starting_equipment =
{
  ["submachine-gun"] = 1,
  ["piercing-rounds-magazine"] = 100,
  ["rocket-launcher"] = 1,
  ["rocket"] = 100,
  ["construction-robot"] = 25,
  ["power-armor"] = 1,
  ["fusion-reactor-equipment"] = 1,
  ["exoskeleton-equipment"] = 1,
  ["personal-roboport-mk2-equipment"] = 1,
  ["energy-shield-equipment"] = 2,
  ["battery-equipment"] = 3,
  ["solar-panel-equipment"] = 7
}

config.starting_evolution_factor = 0.8

return config