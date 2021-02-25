
simple_entities =
  {
  ["tree"] = true,
  ["fish"] = true
  }

function save_map_data(distance)

  local data = "{\n  map_set_size = "..distance.."\n  map_set_tiles = \n  {\n"
  local tiles = {}
  for X = -distance, distance-1 do
    for Y = -distance, distance-1 do
      local tile = game.surfaces[1].get_tile(X, Y)
      local name = tile.name
      if name ~= "out-of-map" then
        if not tiles[name] then tiles[name] = {} end
        local X, Y = tile.position.x, tile.position.y
        if not tiles[name][X] then tiles[name][X] = {} end
        table.insert(tiles[name][X], Y)
      end
    end
  end

  for name, array in pairs (tiles) do
    data = data.."    [\""..name.."\"] = \n    {"
    for X, another in pairs (array) do
      if #another > 0 then
        data = data.."\n    [\""..X.."\"] = {"
        for k, Y in pairs (another) do
          data = data..Y..","
        end
        data = data.."},"
      end
    end
    data = data.."    },\n"
  end

  data = data.."\n  },\n  map_set_entities = \n  {\n"
  local entities = {}
  for k, entity in pairs (game.surfaces[1].find_entities({{-distance, -distance}, {distance-1, distance-1}})) do
    local name = entity.name
    local position = entity.position
    local direction = entity.direction
    local force = entity.force
    if not entities[name] then entities[name] = {} end
    if entity.name == "express-loader" then
      local loader_type = entity.loader_type
      table.insert(entities[name], "    {position = {"..position.x..", "..position.y.."}, force = \"player\", direction = "..direction..", type = \""..loader_type.."\"}, \n")
    elseif entity.type == "resource" then
      local amount = entity.amount
      table.insert(entities[name], "    {position = {"..position.x..", "..position.y.."}, amount = "..amount.."}, \n")
    elseif simple_entities[entity.type] then
      table.insert(entities[name], "    {position = {"..position.x..", "..position.y.."}}, \n")
    else
      table.insert(entities[name], "    {position = {"..position.x..", "..position.y.."}, force = \"player\", direction = "..direction.."}, \n")
    end
  end
  for name, array in pairs (entities) do
    data = data.."\n  [\""..name.."\"] = \n  {\n"
    for k, entity in pairs (array) do
      data = data..entity
    end
    data = data.."  },"
  end

  data = data.."\n  }\n}"
  game.write_file("tile_data.lua", data)
end

function clear_map(surface, area)
  if area then
    for k, entity in pairs (surface.find_entities(area)) do
      entity.destroy()
    end
  else
    for k, entity in pairs (surface.find_entities()) do
      entity.destroy()
    end
  end
end

function create_tiles(distance, tiles, offset_x, offset_y, gap)

  local count = 1
  local map_tiles = {}
  local chunks = {}

  local chunk_distance = math.ceil(distance / 32)
  local chunk_offset_x = math.floor(offset_x / 32)
  local chunk_offset_y = math.floor(offset_y / 32)
  for x = -chunk_distance, chunk_distance do
    for y = -chunk_distance, chunk_distance do
      table.insert(chunks, {x = x + chunk_offset_x, y = y + chunk_offset_y})
    end
  end

  for name, array_x in pairs (tiles) do
    for X, array_y in pairs (array_x) do
      for k, Y in pairs (array_y) do
        local x = X + offset_x
        local y = Y + offset_y
        map_tiles[count] = {name = name, position = {x, y}}
        count = count + 1
      end
    end
  end

  game.surfaces[1].set_tiles(map_tiles, true)
  game.surfaces[1].regenerate_decorative(nil, chunks)
end

function clear_tiles(distance, offset_x, offset_y, gap)

  local blank_tiles = {}
  local count = 1

  for X = -(distance + gap), (distance + gap) - 1 do
    for Y = -(distance + gap), (distance + gap) - 1 do
      blank_tiles[count] = {name = "out-of-map", position = {X + offset_x, Y + offset_y}}
      count = count + 1
    end
  end

  game.surfaces[1].set_tiles(blank_tiles, false)
end

function recreate_entities(entities, offset_x, offset_y, force, duration, script_data)
  if not script_data.chests then script_data.chests = {} end
  if not script_data.input_chests then script_data.input_chests = {} end

  if not entities or not force or not offset_x or not duration or not offset_y then return end
  local tick = game.tick
  local surface = game.surfaces[1]
  for name, array in pairs (entities) do
    for k, entity in pairs (array) do
      if (k + tick) % duration == 0 then
        local position = {entity.position[1] + offset_x, entity.position[2] + offset_y}
        if entity.amount then
          surface.create_entity{name = name, position = position, amount = entity.amount}
        elseif name == "stack-inserter" then
          local v = surface.create_entity{name = name, position = position, force = force, direction = entity.direction}
          v.destructible = false
          v.minable = false
          v.rotatable = false
        elseif name == "red-chest" then
          local v = surface.create_entity({force = force, name = name, position = position})
          v.destructible = false
          v.minable = false
          v.rotatable = false
          table.insert(script_data.chests, v)
        elseif name == "blue-chest" then
          local v = surface.create_entity({force = force, name = name, position = position})
          v.destructible = false
          v.minable = false
          v.rotatable = false
          v.operable = false
          table.insert(script_data.input_chests, v)
        elseif name == "electric-energy-interface" then
          local v = surface.create_entity({force = force, name = name, position = position})
          v.destructible = false
          v.minable = false
          v.rotatable = false
          v.operable = false
        elseif name == "big-electric-pole" then
          local v = surface.create_entity({force = force, name = name, position = position})
          v.destructible = false
          v.minable = false
          v.rotatable = false
        else
          surface.create_entity({force = force, name = name, position = position})
        end
      end
    end
  end
end