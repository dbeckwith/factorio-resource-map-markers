local math2d = require('math2d')
local util = require('util')

local function get_or_set(t, k, init)
  local v = t[k]
  if v == nil then
    v = init
    t[k] = v
  end
  return v
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
  for idx, el in list_reverse_pairs(t) do
    if f(el) then
      table.remove(t, idx)
    end
  end
end

local function list_concat(l1, l2)
  if #l1 == 0 then
    return l2
  else
    for _, bb in ipairs(l2) do
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

local function bb_chunk(bb)
  return {
    left_top = {
      x = math.floor(bb.left_top.x / 32),
      y = math.floor(bb.left_top.y / 32),
    },
    right_bottom = {
      x = math.floor(bb.right_bottom.x / 32),
      y = math.floor(bb.right_bottom.y / 32),
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

local function patch_destroy_tag(patch)
  if patch.tag ~= nil and patch.tag.valid then
    patch.tag.destroy()
  end
  patch.tag = nil
end

local function patch_adjacent(patch, bb, exact)
  -- TODO: use patch.prototype.resource_patch_search_radius once implemented
  -- https://forums.factorio.com/viewtopic.php?f=28&t=84405
  -- in vanilla is 3 for normal resources, 12 for oil
  local r = 3

  bb = bb_expand(bb_quantize(bb), r)

  local function adjacent(bb1, bb2)
    bb2 = bb_quantize(bb2)
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

local function patches_new()
  global.patches = {}
  global.next_patch_id = 0
end

local function patches_add(patch)
  local patches = global.patches
  patches = get_or_set(patches, patch.force.name, {})
  patches = get_or_set(patches, patch.surface.name, {})

  local patches_set = get_or_set(patches, 'set', {})
  patches_set[patch.id] = patch

  local patches_chunks = get_or_set(patches, 'chunks', {})
  local chunk_bb = bb_chunk(patch.bb)
  for x = chunk_bb.left_top.x,chunk_bb.right_bottom.x do
    local patches_for_x = get_or_set(patches_chunks, x, {})
    for y = chunk_bb.left_top.y,chunk_bb.right_bottom.y do
      local patches_for_xy = get_or_set(patches_for_x, y, {})
      patches_for_xy[patch.id] = patch
    end
  end
end

local function patches_remove_adjacent(force, surface, prototype, bb, for_each)
  local patches = global.patches
  patches = patches[force.name]
  if patches == nil then return end
  patches = patches[surface.name]
  if patches == nil then return end

  local patches_set = patches.set
  local patches_chunks = patches.chunks
  local chunk_bb = bb_chunk(bb)
  for x = chunk_bb.left_top.x-1,chunk_bb.right_bottom.x+1 do
    local patches_for_x = patches_chunks[x]
    if patches_for_x ~= nil then
      for y = chunk_bb.left_top.y-1,chunk_bb.right_bottom.y+1 do
        local patches_for_xy = patches_for_x[y]
        if patches_for_xy ~= nil then
          for _, patch in pairs(patches_for_xy) do
            if patches_set[patch.id] ~= nil then
              if patch.prototype == prototype and
                patch_adjacent(patch, bb, false)
              then
                for_each(patch)
                patches_set[patch.id] = nil
              end
            end
            if patches_set[patch.id] == nil then
              patches_for_xy[patch.id] = nil
            end
          end
        end
      end
    end
  end
end

local function patches_any_adjacent_chunk(chunk)
  local patches = global.patches
  patches = patches[chunk.force.name]
  if patches == nil then return end
  patches = patches[chunk.surface.name]
  if patches == nil then return end

  local patches_chunks = patches.chunks
  local bb = chunk_area(chunk)
  local patches_already_processed = {}
  for x = chunk.position.x-1,chunk.position.x+1 do
    local patches_for_x = patches_chunks[x]
    if patches_for_x ~= nil then
      for y = chunk.position.y-1,chunk.position.y+1 do
        local patches_for_xy = patches_for_x[y]
        if patches_for_xy ~= nil then
          for _, patch in pairs(patches_for_xy) do
            if patches_already_processed[patch.id] == nil then
              if patch_adjacent(patch, bb, false) then
                return true
              end
            else
              patches_already_processed[patch.id] = true
            end
          end
        end
      end
    end
  end

  return false
end

local function patches_remove_force(force)
  global.patches[force.name] = nil
end

local function patches_for_each(force, for_each)
  local patches = global.patches
  if force ~= nil then
    patches = {patches[force.name]}
  end
  for _, patches in pairs(patches) do
    for _, patches in pairs(patches) do
      for _, patch in pairs(patches.set) do
        for_each(patch)
      end
    end
  end
end

local function chunk_key(chunk)
  return chunk.force.name .. ':' ..
    chunk.surface.name .. ':' ..
    chunk.position.x .. ':' ..
    chunk.position.y
end

local function chunks_new()
  global.chunks = {
    queue = {},
    searched = {},
    head = nil,
  }
end

local function chunks_empty()
  return global.chunks.head == nil
end

local function chunks_add(chunk)
  local key = chunk_key(chunk)
  if global.chunks.queue[key] == nil and global.chunks.searched[key] == nil then
    global.chunks.queue[key] = chunk

    chunk.next = global.chunks.head
    global.chunks.head = key
  end
  -- TODO: if already in queue, bring to front
end

local function chunks_next()
  local chunk = global.chunks.queue[global.chunks.head]
  global.chunks.queue[global.chunks.head] = nil
  global.chunks.searched[global.chunks.head] = chunk

  global.chunks.head = chunk.next
  chunk.next = nil

  return chunk
end

local function chunks_contains(chunk)
  local key = chunk_key(chunk)
  return global.chunks.queue[key] ~= nil or global.chunks.searched[key] ~= nil
end

local function chunks_remove_force(force)
  local prev_key = nil
  local key = global.chunks.head
  while key ~= nil do
    local chunk = global.chunks.queue[key]
    if chunk.force == force then
      global.chunks.queue[key] = nil

      if key == global.chunks.head then
        global.chunks.head = chunk.next
      else
        global.chunks.queue[prev_key].next = chunk.next
      end
    else
      prev_key = key
    end
    key = chunk.next
  end
  for key, chunk in pairs(global.chunks.searched) do
    if chunk.force == force then
      global.chunks.searched[key] = nil
    end
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
  if resource_prototype.mineable_properties == nil then
    return nil
  end
  for _, product in ipairs(resource_prototype.mineable_properties.products) do
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
      player.print({'command.resource-map-markers.hide-notice'})
    end
  end
  patches_for_each(opts.force, function(patch)
    patch.hidden = true
    patch_destroy_tag(patch)
  end)
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
      player.print({'command.resource-map-markers.show-notice'})
    end
  end
  patches_for_each(opts.force, function(patch)
    local add = false
    if patch.hidden then
      add = opts.recreate_invalid
    elseif patch.tag == nil then
      add = true
    elseif opts.recreate_invalid and not patch.tag.valid then
      add = true
    else
      add = false
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

      if tag.icon ~= nil or tag.text ~= nil then
        local existing_tag_area = {
          left_top = {
            x = math.floor(tag.position.x),
            y = math.floor(tag.position.y),
          },
          right_bottom = {
            x = math.floor(tag.position.x) + 1,
            y = math.floor(tag.position.y) + 1,
          },
        }
        local existing_tags = patch.force.find_chart_tags(
          patch.surface,
          existing_tag_area)
        for _, existing_tag in pairs(existing_tags) do
          existing_tag.destroy()
        end
        patch.tag = patch.force.add_chart_tag(patch.surface, tag)
        patch.hidden = false
      end
    end
  end)
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
      player.print({'command.resource-map-markers.clear-notice'})
    end
  end
  hide_tags({ force = opts.force })
  if opts.force == nil then
    patches_new()
    chunks_new()
  else
    patches_remove_force(opts.force)
    chunks_remove_force(opts.force)
  end
end

local announce_finish_processing = nil

local function tag_all(opts)
  opts = opts or {}
  clear_tags({ force = opts.force })
  local forces = {}
  if opts.force ~= nil then
    forces = {opts.force}
  else
    forces = game.forces
  end
  if opts.announce then
    announce_finish_processing = {}
  end
  for _, force in pairs(forces) do
    if opts.announce then
      for _, player in pairs(force.players) do
        player.print({'command.resource-map-markers.mark-notice'})
        table.insert(announce_finish_processing, player)
      end
    end
    for _, surface in pairs(game.surfaces) do
      for chunk in surface.get_chunks() do
        if force.is_chunk_charted(surface, chunk) then
          chunks_add({
            position = chunk,
            force = force,
            surface = surface,
          })
        end
      end
    end
  end
end

script.on_init(function()
  patches_new()
  chunks_new()
end)

script.on_configuration_changed(function()
  tag_all({ announce = true })
end)

script.on_event(defines.events.on_chunk_charted, function(event)
  chunks_add({
    position = event.position,
    force = event.force,
    surface = game.surfaces[event.surface_index],
  })
end)

local PROCESS_FREQUENCY = 1
local PROCESS_TOTAL_BATCH = 100
local PROCESS_NONEMPTY_BATCH = 1

script.on_nth_tick(PROCESS_FREQUENCY, function()
  local chunks_processed_this_tick = 0
  local nonempty_chunks_processed_this_tick = 0
  while not chunks_empty() and
    chunks_processed_this_tick < PROCESS_TOTAL_BATCH and
    nonempty_chunks_processed_this_tick < PROCESS_NONEMPTY_BATCH
  do
    -- get next chunk to process
    local chunk = chunks_next()
    chunks_processed_this_tick = chunks_processed_this_tick + 1

    -- find all resources in chunk
    local resource_entities = chunk.surface.find_entities_filtered{
      area = chunk_area(chunk),
      type = 'resource',
    }

    if #resource_entities ~= 0 then
      nonempty_chunks_processed_this_tick = nonempty_chunks_processed_this_tick + 1

      for _, resource_entity in ipairs(resource_entities) do
        -- find and remove all patches the current entity is adjacent to
        -- and merge them into one
        local merged_patch = {
          id = global.next_patch_id,
          prototype = resource_entity.prototype,
          bbs = {resource_entity.bounding_box},
          bb = resource_entity.bounding_box,
          amount = resource_entity.amount,
          force = chunk.force,
          surface = chunk.surface,
        }
        global.next_patch_id = global.next_patch_id + 1
        patches_remove_adjacent(
          chunk.force,
          chunk.surface,
          resource_entity.prototype,
          resource_entity.bounding_box,
          function(patch)
            merged_patch.bbs = list_concat(merged_patch.bbs, patch.bbs)
            merged_patch.bb = merge_bbs(merged_patch.bb, patch.bb)
            merged_patch.amount = merged_patch.amount + patch.amount

            -- don't need to bother with prototype, force, and surface
            -- since they are the same

            -- clear the tag of the existing patch if it had one
            -- one will be created for the merged patch later
            patch_destroy_tag(patch)
          end)

        -- record the merged patch
        patches_add(merged_patch)
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
          not chunks_contains(neighbor_chunk)
        then
          -- see if any patches are adjacent to the neighboring chunk
          if patches_any_adjacent_chunk(neighbor_chunk) then
            chunks_add(neighbor_chunk)
          end
        end
      end
    end
  end

  if nonempty_chunks_processed_this_tick > 0 then
    show_tags()
  end

  if announce_finish_processing ~= nil and chunks_processed_this_tick > 0 and chunks_empty() then
    for _, player in ipairs(announce_finish_processing) do
      player.print({'command.resource-map-markers.mark-finished-notice'})
    end
    announce_finish_processing = nil
  end
end)

commands.add_command(
  'resource-map-markers',
  {'command.resource-map-markers.help'},
  function(event)
    local player = game.players[event.player_index]
    local args = util.split_whitespace(event.parameter)
    if #args == 0 then
      player.print({'command.resource-map-markers.help'})
    elseif args[1] == 'mark' then
      tag_all({ force = player.force, announce = true })
    elseif args[1] == 'clear' then
      clear_tags({ force = player.force, announce = true })
    elseif args[1] == 'hide' then
      hide_tags({ force = player.force, announce = true })
    elseif args[1] == 'show' then
      show_tags({ recreate_invalid = true, force = player.force, announce = true })
    elseif args[1] == 'mark-here' then
      player.print({'command.resource-map-markers.mark-here-notice'})
      chunks_add({
        position = chunk_containing(player.position),
        force = player.force,
        surface = player.surface,
      })
    else
      player.print({'command.resource-map-markers.bad-subcommand', args[1]})
    end
  end)
