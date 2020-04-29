local math2d = require('math2d')
local util = require('util')

local function chunks_contains(l, e)
  for _, e2 in pairs(l) do
    if e.x == e2.x and e.y == e2.y then
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

local function bb_expand(bb, r)
  return {
    left_top = {
      x = bb.left_top.x - r,
      y = bb.left_top.y - r,
    },
    right_bottom = {
      x = bb.right_bottom.x + r,
      y = bb.right_bottom.y + r,
    },
  }
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

local function patch_adjacent(patch, bb, exact)
  -- TODO: use patch.prototype.resource_patch_search_radius once implemented
  -- https://forums.factorio.com/viewtopic.php?f=28&t=84405
  -- in vanilla is 3 for normal resources, 12 for oil
  local r = 3

  bb = bb_quantize(bb)

  local function adjacent(bb1, bb2)
    bb2 = bb_expand(bb_quantize(bb2), r)
    return
      bb1.left_top.x <= bb2.right_bottom.x and
      bb1.right_bottom.x >= bb2.left_top.x and
      bb1.left_top.y <= bb2.right_bottom.y and
      bb1.right_bottom.y >= bb2.left_top.y
  end

  -- quick check: the bb must at least be adjacent to
  -- the patch's surrounding bb
  if not adjacent(bb, patch.bb) then
    return false
  end

  if exact then
    -- slow check: the bb must be adjacent to any of the bbs in the patch
    for _, patch_bb in pairs(patch.bbs) do
      if adjacent(bb, patch_bb) then
        return true
      end
    end
    return false
  else
    return true
  end
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

local function hide_tags()
  for _, patch in pairs(global.patches) do
    if patch.tag ~= nil then
      patch.tag.destroy()
      patch.tag = nil
    end
  end
end

local function show_tags()
  for _, patch in pairs(global.patches) do
    if patch.tag == nil or not patch.tag.valid then
      local tag = {}
      tag.position = bbs_center(patch.bbs)
      local amount = nil
      if patch.prototype.infinite_resource then
        amount = math.floor(patch.amount
            / #patch.bbs
            / patch.prototype.normal_resource_amount
            * 100) .. '%'
      else
        amount = util.format_number(patch.amount, true)
      end
      tag.text = string.format('%s - %s',
        patch.prototype.name,
        amount)
      tag.icon = get_resource_icon(patch.prototype)

      log('adding tag ' .. serpent.block(tag))
      patch.tag = patch.force.add_chart_tag(patch.surface, tag)
    end
  end
end

local function clear_tags()
  hide_tags()
  global.patches = {}
  global.searched_chunks = {}
end

local function fmt_chunks(chunks)
  local s = ''
  for _, chunk in pairs(chunks) do
    if s ~= '' then
      s = s .. ', '
    end
    s = s .. '(' .. chunk.x .. ',' .. chunk.y .. ')'
  end
  return s
end

local function tag_chunks(force, surface, chunks)
  log(string.format('tagging %d chunks on %s for %s: %s',
    #chunks,
    surface.name,
    force.name,
    fmt_chunks(chunks)))

  -- TODO: distribute work over multiple ticks
  -- could make a work queue of chunks or something that's processed periodically

  -- list of all connected resource entities of the same type
  local patches = global.patches

  -- list of chunks that have already been looked at
  local searched_chunks = global.searched_chunks

  -- list of chunks that need to be looked at
  local chunks_to_search = {}
  -- look at all chunks from input that haven't been searched already
  for _, chunk in pairs(chunks) do
    if not chunks_contains(searched_chunks, chunk) then
      table.insert(chunks_to_search, chunk)
    end
  end

  -- search chunks
  while #chunks_to_search ~= 0 do
    log('chunks_to_search: ' .. fmt_chunks(chunks_to_search))
    log('searched_chunks: ' .. fmt_chunks(searched_chunks))

    local chunk = table.remove(chunks_to_search)

    log('searching chunk ' .. chunk.x .. ',' .. chunk.y)

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
        -- only consider patches with the same resource, force, and surface
        if resource_entity.prototype == patch.prototype and
          force == patch.force and
          surface == patch.surface then
          -- if the current entity is adjacent to the patch,
          -- record the patch index
          if patch_adjacent(patch, resource_entity.bounding_box, true) then
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
        amount = resource_entity.amount,
        force = force,
        surface = surface
      }
      for _, patch_idx in pairs(adjacent_patches) do
        local patch = table.remove(patches, patch_idx)

        merged_patch.bbs = list_concat(merged_patch.bbs, patch.bbs)
        merged_patch.bb = merge_bbs(merged_patch.bb, patch.bb)
        merged_patch.amount = merged_patch.amount + patch.amount

        -- don't need to bother with prototype, force, and surface,
        -- they will be the same

        -- clear the tag of the existing patch if it had one
        -- one will be created for the merged patch later
        if patch.tag ~= nil then
          patch.tag.destroy()
          patch.tag = nil
        end
      end

      -- record the merged patch
      table.insert(patches, merged_patch)
    end

    -- find any neighboring chunks that have patches up against them
    -- and make sure they get searched as well
    for neighbor_chunk in cardinal_neighbors(chunk) do
      -- only look at charted chunks that haven't been visited yet
      if force.is_chunk_charted(surface, neighbor_chunk) and
        -- TODO: make array-set structure to optimize this
        not chunks_contains(searched_chunks, neighbor_chunk) and
        not chunks_contains(chunks_to_search, neighbor_chunk) then
        -- see if any patches are adjacent to the neighboring chunk
        for _, patch in pairs(patches) do
          if patch_adjacent(patch, chunk_area(neighbor_chunk), false) then
            log('adding neighbor chunk ' .. neighbor_chunk.x .. ',' .. neighbor_chunk.y)
            table.insert(chunks_to_search, neighbor_chunk)
            break
          end
        end
      end
    end
  end

  show_tags()
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

script.on_init(function()
  global.patches = {}
  global.searched_chunks = {}
end)

script.on_configuration_changed(function()
  tag_all()
end)

script.on_event(defines.events.on_chunk_charted, function(event)
  local surface = game.surfaces[event.surface_index]
  tag_chunks(event.force, surface, {event.position})
end)

-- TODO: command help

commands.add_command('resource-map-markers', '', function(event)
  local player = game.players[event.player_index]
  local args = util.split_whitespace(event.parameter)
  if #args == 0 then
    player.print('a sub-command is required: mark-all, clear-all, hide, show, or mark-here')
  elseif args[1] == 'mark-all' then
    player.print('marking all resources in all surfaces')
    tag_all()
  elseif args[1] == 'clear-all' then
    player.print('clearing resource markers')
    clear_tags()
  elseif args[1] == 'hide' then
    player.print('hiding resource markers')
    hide_tags()
  elseif args[1] == 'show' then
    player.print('showing hidden resource markers')
    show_tags()
  elseif args[1] == 'mark-here' then
    player.print('marking resources in your current chunk')
    local chunk = chunk_containing(player.position)
    tag_chunks(player.force, player.surface, {chunk})
  else
    player.print(string.format(
      'unrecognized resource-map-markers command %q',
      args[1]))
    player.print('valid sub-commands are: mark-all, clear-all, hide, show, or mark-here')
  end
end)

-- TODO: mod settings
-- hide resource name
-- hide patch amount
-- configure chunks processed per tick?
