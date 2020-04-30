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

local function list_reverse_pairs(t)
  local i = #t + 1
  return function()
    i = i - 1
    if i > 0 then
      return i, t[i]
    end
  end
end

local function list_remove_if(t, f)
  local idxs = {}
  for idx, el in pairs(t) do
    if f(el) then
      table.insert(idxs, idx)
    end
  end
  for _, idx in list_reverse_pairs(idxs) do
    table.remove(t, idx)
  end
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

local function any_setting(players, setting)
  for _, player in pairs(players) do
    if player.mod_settings['sonaxaton-resource-map-markers-' .. setting].value then
      return true
    end
  end
  return false
end

local function get_resource_icon(resource_prototype)
  for _, product in pairs(resource_prototype.mineable_properties.products) do
    return {
      type = product.type,
      name = product.name,
    }
  end
end

local function hide_tags(opts)
  opts = opts or {}
  if opts.announce then
    local players = {}
    if opts.force ~= nil then
      players = opts.force.players
    else
      players = game.players
    end
    for _, player in pairs(players) do
      player.print('hiding resource markers')
    end
  end
  for _, patch in pairs(global.patches) do
    if (opts.force == nil or patch.force == opts.force) and patch.tag ~= nil then
      patch.tag.destroy()
      patch.tag = nil
    end
  end
end

local function show_tags(opts)
  opts = opts or {}
  if opts.announce then
    local players = {}
    if opts.force ~= nil then
      players = opts.force.players
    else
      players = game.players
    end
    for _, player in pairs(players) do
      player.print('showing hidden resource markers')
    end
  end
  for _, patch in pairs(global.patches) do
    local add = false
    if opts.force ~= nil and patch.force ~= opts.force then
      add = false
    else
      if patch.tag == nil then
        add = true
      else
        if opts.recreate_invalid and not patch.tag.valid then
          add = true
        else
          add = false
        end
      end
    end
    if add then
      local tag = {}
      tag.position = bbs_center(patch.bbs)
      tag.icon = get_resource_icon(patch.prototype)

      local name = nil
      if any_setting(patch.force.players, 'show-resource-name') then
        name = patch.prototype.name
      end
      local amount = nil
      if any_setting(patch.force.players, 'show-resource-amount') then
        if patch.prototype.infinite_resource then
          amount = math.floor(patch.amount
              / #patch.bbs
              / patch.prototype.normal_resource_amount
              * 100) .. '%'
        else
          amount = util.format_number(patch.amount, true)
        end
      end
      if name ~= nil then
        if amount ~= nil then
          tag.text = patch.prototype.name .. ' ' .. amount
        else
          tag.text = name
        end
      elseif amount ~= nil then
        tag.text = amount
      end

      patch.tag = patch.force.add_chart_tag(patch.surface, tag)
    end
  end
end

local function clear_tags(opts)
  opts = opts or {}
  if opts.announce then
    local players = {}
    if opts.force ~= nil then
      players = opts.force.players
    else
      players = game.players
    end
    for _, player in pairs(players) do
      player.print('clearing resource markers')
    end
  end
  hide_tags({ force = opts.force })
  if opts.force == nil then
    global.patches = {}
    global.searched_chunks = {}
    global.chunks_to_search = {}
  else
    list_remove_if(global.patches,
      function(patch) return patch.force == opts.force end)
    list_remove_if(global.searched_chunks,
      function(chunk) return chunk.force == opts.force end)
    list_remove_if(global.chunks_to_search,
      function(chunk) return chunk.force == opts.force end)
  end
end

local function tag_chunks(chunks)
  -- look at all chunks from input that haven't been searched already
  for _, chunk in pairs(chunks) do
    if not chunks_contains(global.searched_chunks, chunk) then
      table.insert(global.chunks_to_search, chunk)
    end
  end
end

local function tag_all(opts)
  opts = opts or {}
  clear_tags({ force = opts.force })
  local forces = {}
  if opts.force ~= nil then
    forces = {opts.force}
  else
    forces = game.forces
  end
  local chunks = {}
  for _, force in pairs(forces) do
    if opts.announce then
      for _, player in pairs(force.players) do
        player.print('marking resources in all surfaces')
      end
    end
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

local PROCESS_FREQUENCY = 10
local PROCESS_BATCH = 100

script.on_nth_tick(PROCESS_FREQUENCY, function()
  local any_new_patches = false
  local chunks_processed_this_tick = 0
  while #global.chunks_to_search ~= 0 and
    chunks_processed_this_tick < PROCESS_BATCH do
    chunks_processed_this_tick = chunks_processed_this_tick + 1

    local chunk = table.remove(global.chunks_to_search)

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

      -- remove all adjacent patches and merge them into one
      local merged_patch = {
        prototype = resource_entity.prototype,
        bbs = {resource_entity.bounding_box},
        bb = resource_entity.bounding_box,
        amount = resource_entity.amount,
        force = chunk.force,
        surface = chunk.surface,
      }
      for _, patch_idx in list_reverse_pairs(adjacent_patches) do
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
            table.insert(global.chunks_to_search, neighbor_chunk)
            break
          end
        end
      end
    end
  end

  if any_new_patches then
    show_tags()
  end
end)

-- TODO: command help

commands.add_command('resource-map-markers', '', function(event)
  local player = game.players[event.player_index]
  local args = util.split_whitespace(event.parameter)
  if #args == 0 then
    player.print('a sub-command is required: mark, clear, hide, show, or mark-here')
  elseif args[1] == 'mark' then
    tag_all({ force = player.force, announce = true })
  elseif args[1] == 'clear' then
    clear_tags({ force = player.force, announce = true })
  elseif args[1] == 'hide' then
    hide_tags({ force = player.force, announce = true })
  elseif args[1] == 'show' then
    show_tags({ recreate_invalid = true, force = player.force, announce = true })
  elseif args[1] == 'mark-here' then
    player.print('marking resources in your current chunk')
    tag_chunks({{
      position = chunk_containing(player.position),
      force = player.force,
      surface = player.surface,
    }})
  else
    player.print(string.format(
      'unrecognized resource-map-markers command %q',
      args[1]))
    player.print('valid sub-commands are: mark, clear, hide, show, or mark-here')
  end
end)
