local math2d = require('math2d')
local util = require('util')

local function contains(l, e)
  for _, e2 in pairs(l) do
    if table.compare(e, e2) then
      return true
    end
  end
  return false
end

local function list_concat(l1, l2)
  if #l1 == 0 then
    return l2
  else
    for _, bb in pairs(l2) do
      table.insert(l1, bb)
    end
    return l1
  end
end

local function remove_if(t, f)
  local keys = {}
  for key, el in pairs(t) do
    if f(el) then
      table.insert(keys, key)
    end
  end
  for _, key in pairs(keys) do
    table.remove(t, key)
  end
end

local function merge_bbs(bb1, bb2)
  if bb1 == nil then
    return bb2
  elseif bb2 == nil then
    return bb1
  else
    return {
      left_top = {
        x = math.min(bb1.left_top.x, bb2.left_top.x),
        y = math.min(bb1.left_top.y, bb2.left_top.y),
      },
      right_bottom = {
        x = math.max(bb1.right_bottom.x, bb2.right_bottom.x),
        y = math.max(bb1.right_bottom.y, bb2.right_bottom.y),
      },
    }
  end
end

local function cardinal_neighbors(p)
  local i = 0
  return function()
    i = i + 1
    if i == 1 then
      return { x = p.x - 1, y = p.y }
    elseif i == 2 then
      return { x = p.x + 1, y = p.y }
    elseif i == 3 then
      return { x = p.x, y = p.y - 1 }
    elseif i == 4 then
      return { x = p.x, y = p.y + 1 }
    end
  end
end

local function chunk_containing(position)
  return {
    x = math.floor(position.x / 32),
    y = math.floor(position.y / 32),
  }
end

local function chunk_area(chunk)
  return {
    left_top = {
      x = chunk.x * 32,
      y = chunk.y * 32,
    },
    right_bottom = {
      x = (chunk.x + 1) * 32,
      y = (chunk.y + 1) * 32,
    },
  }
end

local function bb_center(bb)
  return {
    x = (bb.left_top.x + bb.right_bottom.x) / 2,
    y = (bb.left_top.y + bb.right_bottom.y) / 2,
  }
end

local function bb_quantize(bb)
  return {
    left_top = {
      x = math.floor(bb.left_top.x),
      y = math.floor(bb.left_top.y),
    },
    right_bottom = {
      x = math.ceil(bb.right_bottom.x),
      y = math.ceil(bb.right_bottom.y),
    },
  }
end

local function bb_adjacent(bb1, bb2)
  bb1 = bb_quantize(bb1)
  bb2 = bb_quantize(bb2)
  return
    bb1.left_top.x <= bb2.right_bottom.x and
    bb1.right_bottom.x >= bb2.left_top.x and
    bb1.left_top.y <= bb2.right_bottom.y and
    bb1.right_bottom.y >= bb2.left_top.y
end

local function bbs_center(bbs)
    local center = { x = 0, y = 0 }
    for _, bb in pairs(bbs) do
      local c = math2d.bounding_box.get_centre(bb)
      center.x = center.x + c.x
      center.y = center.y + c.y
    end
    center.x = center.x / #bbs
    center.y = center.y / #bbs
    return center
end

local function get_resource_icon(resource_prototype)
  -- TODO: select best product for icon
  for _, product in pairs(resource_prototype.mineable_properties.products) do
    return {
      type = product.type,
      name = product.name,
    }
  end
end

local function add_tag(force, surface, tag)
  log('adding tag ' .. serpent.block(tag))

  if global['tags'] == nil then
    global['tags'] = {}
  end

  local key = tag.icon.type .. ':' ..
    tag.icon.name .. ':' ..
    math.floor(tag.position.x) .. ':' ..
    math.floor(tag.position.y)
  if global['tags'][key] ~= nil then
    global['tags'][key].destroy()
  end

  global['tags'][key] = force.add_chart_tag(surface, tag)
end

local function clear_tags()
  if global['tags'] == nil then
    global['tags'] = {}
  end

  for _, tag in pairs(global['tags']) do
    tag.destroy()
  end

  global['tags'] = {}
end

local function tag_chunks(force, surface, chunks)
  local chunks_str = ''
  for _, chunk in pairs(chunks) do
    if chunks_str ~= '' then
      chunks_str = chunks_str .. ', '
    end
    chunks_str = chunks_str .. '(' .. chunk.x .. ',' .. chunk.y .. ')'
  end
  log('tagging ' .. #chunks .. ' chunks: ' .. chunks_str)

  -- TODO: group oil-like resources that are near to each other
  -- might want to do the same for normal resources as well

  -- FIXME: startup only marks a few things
  -- seems to be caused by chunks charting sequentially
  -- need to handle when a chunk next to an existing patch
  -- reveals more of the patch

  -- FIXME: total amounts disagree with builtin hovertext
  -- mark-here seems correct, mark-all seems to be doubled

  -- TODO: distribute work over multiple ticks
  -- could make a work queue of chunks or something that's processed periodically

  -- collect all patches of the same resource
  local patches = {}

  local function patch_adjacent(patch, bb)
    -- quick check: the bb must at least be adjacent to
    -- the patch's surrounding bb
    if not bb_adjacent(bb, patch.bb) then
      return false
    end
    -- slow check: the bb must be adjacent to any of the bbs in the patch
    for _, patch_bb in pairs(patch.bbs) do
      if bb_adjacent(bb, patch_bb) then
        return true
      end
    end
    return false
  end

  -- search through chunks
  local chunks_to_search = table.deepcopy(chunks)
  local searched_chunks = {}
  while #chunks_to_search ~= 0 do
    local chunk = table.remove(chunks_to_search)

    log('searching chunk ' .. chunk.x .. ',' .. chunk.y)

    -- if we've searched fewer than N chunks, this is an origin chunk
    local is_origin_chunk = #searched_chunks < #chunks

    -- mark this chunk as searched
    table.insert(searched_chunks, chunk)

    -- find all resources in chunk
    local resource_entities = surface.find_entities_filtered{
      area = chunk_area(chunk),
      type = 'resource',
    }
    for _, resource_entity in pairs(resource_entities) do
      -- find the index of all patches the current entity is adjacent to
      local adjacent_patches = {}
      for patch_idx, patch in pairs(patches) do
        -- only consider patches with the same resource
        if resource_entity.prototype == patch.prototype then
          -- if the current entity is adjacent to the patch,
          -- record the patch index
          if patch_adjacent(patch, resource_entity.bounding_box) then
            table.insert(adjacent_patches, patch_idx)
          end
        end
      end

      -- sort the indexes in reverse order since we will be removing them all
      -- from the patches list
      table.sort(adjacent_patches, function(i, j) return i > j end)

      -- TODO: optimize case of only one adjacent patch

      -- remove all adjacent patches and merge them into one
      local merged_patch = {
        prototype = resource_entity.prototype,
        bbs = {resource_entity.bounding_box},
        bb = resource_entity.bounding_box,
        in_origin_chunk = is_origin_chunk,
        amount = resource_entity.amount,
      }
      for _, patch_idx in pairs(adjacent_patches) do
        local patch = table.remove(patches, patch_idx)

        merged_patch.bbs = list_concat(merged_patch.bbs, patch.bbs)
        merged_patch.bb = merge_bbs(merged_patch.bb, patch.bb)
        merged_patch.in_origin_chunk = merged_patch.in_origin_chunk or
          patch.in_origin_chunk
        merged_patch.amount = merged_patch.amount + patch.amount
      end

      -- record the merged patch
      table.insert(patches, merged_patch)
    end

    -- remove any patches that aren't in the origin chunk
    remove_if(patches, function(patch) return not patch.in_origin_chunk end)

    -- find any neighboring chunks that have patches up against them
    -- and make sure they get searched as well
    for neighbor_chunk in cardinal_neighbors(chunk) do
      -- only look at charted chunks that haven't been visited yet
      if force.is_chunk_charted(surface, neighbor_chunk) and
        not contains(searched_chunks, neighbor_chunk) and
        not contains(chunks_to_search, neighbor_chunk) then
        -- see if any patches are adjacent to the neighboring chunk
        for _, patch in pairs(patches) do
          if bb_adjacent(chunk_area(neighbor_chunk), patch.bb) then
            table.insert(chunks_to_search, neighbor_chunk)
            break
          end
        end
      end
    end
  end

  -- tag each patch
  for _, patch in pairs(patches) do
    local tag = {}
    tag.position = bbs_center(patch.bbs)
    local amount = nil
    if patch.prototype.infinite_resource then
      amount = math.floor(patch.amount
          / #patch.bbs
          / patch.prototype.normal_resource_amount
          * 100) .. '%'
    else
      amount = util.format_number(patch.amount)
    end
    tag.text = string.format('%s - %s',
      patch.prototype.name,
      amount)
    tag.icon = get_resource_icon(patch.prototype)

    add_tag(force, surface, tag)
  end
end

local function tag_all()
  clear_tags()
  for _, force in pairs(game.forces) do
    for _, surface in pairs(game.surfaces) do
      local chunks = {}
      for chunk in surface.get_chunks() do
        if force.is_chunk_charted(surface, chunk) then
          table.insert(chunks, chunk)
        end
      end
      tag_chunks(force, surface, chunks)
    end
  end
end

script.on_configuration_changed(function()
  tag_all()
end)

script.on_event(defines.events.on_chunk_charted, function(event)
  -- TODO: what existing tags need to be cleared?
  local surface = game.surfaces[event.surface_index]
  tag_chunks(event.force, surface, {event.position})
end)

-- TODO: command help
-- TODO: command to hide/show markers without regenerating

commands.add_command('resource-map-markers', '', function(event)
  local player = game.players[event.player_index]
  local args = util.split_whitespace(event.parameter)
  if #args == 0 then
    player.print('a sub-command is required: mark-all, clear-all, or mark-here')
  elseif args[1] == 'mark-all' then
    player.print('marking all resources in all surfaces')
    tag_all()
  elseif args[1] == 'clear-all' then
    player.print('clearing resource markers')
    clear_tags()
  elseif args[1] == 'mark-here' then
  -- TODO: what existing tags need to be cleared?
    player.print('marking resources in your current chunk')
    local chunk = chunk_containing(player.position)
    tag_chunks(player.force, player.surface, {chunk})
  else
    player.print(string.format(
      'unrecognized resource-map-markers command %q',
      args[1]))
    player.print('valid sub-commands are: mark-all, clear-all, or mark-here')
  end
end)
