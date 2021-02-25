local util = require("util")

local debug = true
function util.debug_error(string)
  if not debug then return end
  error(string)
end

function util.set_technologies_enabled(force, technology_list)
  local technologies = force.technologies
  for name, bool in pairs (technology_list) do
    local tech = technologies[name]
    if tech then
      tech.enabled = true
    else
      util.debug_error("Not a real technology "..name)
    end
  end
end

function util.set_technologies_researched(force, technology_list)
  local technologies = force.technologies
  for name, bool in pairs (technology_list) do
    local tech = technologies[name]
    if tech then
      tech.enabled = true
      tech.researched = true
    else
      util.debug_error("Not a real technology "..name)
    end
  end
end

function util.set_recipes(force, recipe_list)
  local recipes = force.recipes
  for name, bool in pairs (recipe_list) do
    local recipe = recipes[name]
    if recipe then
      recipe.enabled = bool
    else
      util.debug_error("Not a real recipe "..name)
    end
  end
end

function util.difficulty_number(easy, normal, hard)

  if game.difficulty == defines.difficulty.easy then
    return easy
  end

  if game.difficulty == defines.difficulty.normal then
    return normal
  end

  if game.difficulty == defines.difficulty.hard then
    return hard
  end

  error("Unknown difficulty: "..game.difficulty)

end

function util.verify_techs(force)
  local technologies = force.technologies
  for k, tech in pairs (technologies) do
    if tech.enabled then
      for name, prerequisite in pairs (tech.prerequisites) do
        if not prerequisite.enabled then
          game.print("Prerequisite  for "..tech.name.." not enabled "..name)
        end
      end
    end
  end
end

function util.think_string(string)
  return {"", "[img=entity/character][color=orange]", {"engineer-title"}, ": [/color]", string}
end

return util