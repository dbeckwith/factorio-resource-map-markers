local math2d = require('math2d')
local util = require('util')

local function chunks_contains(chunks, chunk)
  for _, chunk2 in pairs(chunks) do
    if chunk.position.x == chunk2.position.x and
      chunk.position.y == chunk2.position.y then
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
      x = chunk.position.x * 32,
      y = chunk.position.y * 32,
    },
    right_bottom = {
      x = (chunk.position.x + 1) * 32,
      y = (chunk.position.y + 1) * 32,
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

local function show_tags(recreate_invalid)
  for _, patch in pairs(global.patches) do
    local add = false
    if patch.tag == nil then
      add = true
    else
      if recreate_invalid and not patch.tag.valid then
        add = true
      else
        add = false
      end
    end
    if add then
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
    s = s .. '(' .. chunk.position.x .. ',' .. chunk.position.y .. ')'
  end
  return s
end

local function tag_chunks(chunks)
  log(string.format('tagging %d chunks: %s',
    #chunks,
    fmt_chunks(chunks)))

  -- look at all chunks from input that haven't been searched already
  for _, chunk in pairs(chunks) do
    if not chunks_contains(global.searched_chunks, chunk) then
      table.insert(global.chunks_to_search, chunk)
    end
  end
end

local function tag_all()
  clear_tags()
  local chunks = {}
  for _, force in pairs(game.forces) do
    for _, surface in pairs(game.surfaces) do
      for chunk in surface.get_chunks() do
        if force.is_chunk_charted(surface, chunk) then
          table.insert(chunks, {
            position = chunk,
            force = force,
            surface = surface,
          })
        end
      end
    end
  end
  tag_chunks(chunks)
end

script.on_init(function()
  -- list of all connected resource entities of the same type
  global.patches = {}
  -- list of chunks that have already been looked at
  global.searched_chunks = {}
  -- list of chunks that need to be looked at
  global.chunks_to_search = {}
end)

script.on_configuration_changed(function()
  tag_all()
end)

script.on_event(defines.events.on_chunk_charted, function(event)
  tag_chunks({{
    position = event.position,
    force = event.force,
    surface = game.surfaces[event.surface_index],
  }})
end)

local PROCESS_FREQUENCY = 1
local PROCESS_BATCH = 1

script.on_nth_tick(PROCESS_FREQUENCY, function()
  local any_new_patches = false
  local chunks_processed_this_tick = 0
  while #global.chunks_to_search ~= 0 and
    chunks_processed_this_tick < PROCESS_BATCH do
    chunks_processed_this_tick = chunks_processed_this_tick + 1

    log('chunks_to_search: ' .. fmt_chunks(global.chunks_to_search))
    log('searched_chunks: ' .. fmt_chunks(global.searched_chunks))

    local chunk = table.remove(global.chunks_to_search)

    log('searching chunk ' .. chunk.position.x .. ',' .. chunk.position.y)

    -- mark this chunk as searched
    table.insert(global.searched_chunks, chunk)

    -- find all resources in chunk
    local resource_entities = chunk.surface.find_entities_filtered{
      area = chunk_area(chunk),
      type = 'resource',
    }
    for _, resource_entity in pairs(resource_entities) do
      -- find the index of all patches the current entity is adjacent to
      local adjacent_patches = {}
      for patch_idx, patch in pairs(global.patches) do
        -- only consider patches with the same resource, force, and surface
        if resource_entity.prototype == patch.prototype and
          chunk.force == patch.force and
          chunk.surface == patch.surface then
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
        force = chunk.force,
        surface = chunk.surface,
      }
      for _, patch_idx in pairs(adjacent_patches) do
        local patch = table.remove(global.patches, patch_idx)

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
      table.insert(global.patches, merged_patch)
      any_new_patches = true
    end

    -- find any neighboring chunks that have patches up against them
    -- and make sure they get searched as well
    for neighbor_chunk in cardinal_neighbors(chunk.position) do
      neighbor_chunk = {
        position = neighbor_chunk,
        force = chunk.force,
        surface = chunk.surface,
      }
      -- only look at charted chunks that haven't been visited yet
      if neighbor_chunk.force.is_chunk_charted(
          neighbor_chunk.surface,
          neighbor_chunk.position) and
        -- TODO: make array-set structure to optimize this
        not chunks_contains(global.searched_chunks, neighbor_chunk) and
        not chunks_contains(global.chunks_to_search, neighbor_chunk) then
        -- see if any patches are adjacent to the neighboring chunk
        for _, patch in pairs(global.patches) do
          if patch_adjacent(patch, chunk_area(neighbor_chunk), false) then
            log('adding neighbor chunk ' .. neighbor_chunk.x .. ',' .. neighbor_chunk.y)
            table.insert(global.chunks_to_search, neighbor_chunk)
            break
          end
        end
      end
    end
  end

  if any_new_patches then
    show_tags(false)
  end
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
    show_tags(true)
  elseif args[1] == 'mark-here' then
    player.print('marking resources in your current chunk')
    local chunk =
    tag_chunks({{
      position = chunk_containing(player.position),
      force = player.force,
      surface = player.surface,
    }})
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
