local util = require('util')

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

local function patch_bbs_new(bb)
  return {
    count = 1,
    center = {
      x = (bb.left_top.x + bb.right_bottom.x) / 2,
      y = (bb.left_top.y + bb.right_bottom.y) / 2,
    }
  }
end

local function patch_bbs_len(bbs)
  return bbs.count
end

local function patch_bbs_center(bbs)
  return bbs.center
end

local function patch_bbs_concat(bbs1, bbs2)
  bbs1.center.x = (bbs1.center.x * bbs1.count + bbs2.center.x * bbs2.count) / (bbs1.count + bbs2.count)
  bbs1.center.y = (bbs1.center.y * bbs1.count + bbs2.center.y * bbs2.count) / (bbs1.count + bbs2.count)
  bbs1.count = bbs1.count + bbs2.count
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

local function patch_destroy_tag(patch)
  if patch.tag ~= nil and patch.tag.valid then
    patch.tag.destroy()
  end
  patch.tag = nil
end

local function patch_adjacent(patch, bb)
  -- TODO: use patch.prototype.resource_patch_search_radius once implemented
  -- https://forums.factorio.com/viewtopic.php?f=28&t=84405
  -- in vanilla is 3 for normal resources, 12 for oil
  local r = 3
  -- shitty heuristic to separate ore-like resources from oil-like resources
  if bb.right_bottom.x - bb.left_top.x > 1 or
    bb.right_bottom.y - bb.left_top.y > 1
  then
    r = 12
  end

  return
    math.floor(bb.left_top    .x) - r <= math.floor(patch.bb.right_bottom.x) + r and
    math.floor(bb.right_bottom.x) + r >= math.floor(patch.bb.left_top    .x) - r and
    math.ceil (bb.left_top    .y) - r <= math.ceil (patch.bb.right_bottom.y) + r and
    math.ceil (bb.right_bottom.y) + r >= math.ceil (patch.bb.left_top    .y) - r
end

local function patches_new()
  global.patches = {}
  global.next_patch_id = 0
end

local function patches_add(patch)
  local patches = global.patches

  if patches[patch.force.name] == nil then
    patches[patch.force.name] = {}
  end
  patches = patches[patch.force.name]

  if patches[patch.surface.name] == nil then
    patches[patch.surface.name] = {}
  end
  patches = patches[patch.surface.name]

  if patches.set == nil then
    patches.set = {}
  end
  local patches_set = patches.set
  patches_set[patch.id] = patch

  if patches.chunks == nil then
    patches.chunks = {}
  end
  local patches_chunks = patches.chunks

  local chunk_bb = bb_chunk(patch.bb)
  for x = chunk_bb.left_top.x,chunk_bb.right_bottom.x do
    if patches_chunks[x] == nil then
      patches_chunks[x] = {}
    end
    local patches_for_x = patches_chunks[x]
    for y = chunk_bb.left_top.y,chunk_bb.right_bottom.y do
      if patches_for_x[y] == nil then
        patches_for_x[y] = {}
      end
      local patches_for_xy = patches_for_x[y]
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
            if patches_set[patch.id] ~= nil and
              patch.prototype == prototype and
              patch_adjacent(patch, bb)
            then
              for_each(patch)
              patches_set[patch.id] = nil
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
              if patch_adjacent(patch, bb) then
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
  global.entity_queue = {}
  global.current_chunk = nil
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

local function translations_new()
  global.translations = {}
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

local function create_tag(patch)
  local tag = {}
  tag.position = patch_bbs_center(patch.bbs)
  tag.icon = get_resource_icon(patch.prototype)

  local name = nil
  if any_setting(patch.force.players, 'show-resource-name') then
    local translations = global.translations
    local translation = translations[patch.prototype.name]
    if translation == nil then
      -- no translation yet
      -- use the prototype name in the mean time
      name = patch.prototype.name

      -- TODO: player selection here could be improved
      -- currently, the first player in the force is used
      -- could be the player initiating the marking?

      -- select a player to translate the prototype name
      -- there must be at least one player because of the any_setting check
      local player = patch.force.players[next(patch.force.players)]

      -- make a new translation request for the localised name of the resource
      translations[patch.prototype.name] = {
        player = player,
        localised_string = patch.prototype.localised_name,
      }
      player.request_translation(patch.prototype.localised_name)
    elseif translation.result == nil then
      -- there is a pending translation request
      -- use the prototype name in the mean time
      name = patch.prototype.name
    else
      -- use the translated result
      name = translation.result
    end
  end

  local amount = nil
  if any_setting(patch.force.players, 'show-resource-amount') then
    if patch.prototype.infinite_resource then
      amount = math.floor(patch.amount
          / patch_bbs_len(patch.bbs)
          / patch.prototype.normal_resource_amount
          * 100) .. '%'
    else
      amount = util.format_number(patch.amount, true)
    end
  end

  if name ~= nil then
    if amount ~= nil then
      tag.text = name .. ' ' .. amount
    else
      tag.text = name
    end
  elseif amount ~= nil then
    tag.text = amount
  end

  if tag.icon ~= nil or tag.text ~= nil then
    -- clear existing tags very near the target position
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
    return patch.tag
  else
    return nil
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
      local tag = create_tag(patch)
      if tag ~= nil then
        patch.hidden = false
      end
    end
  end)
end

local function update_tag_text(opts)
  opts = opts or {}
  patches_for_each(opts.force, function(patch)
    -- don't update hidden patches
    -- or ones with the wrong resource
    if not patch.hidden and
      (opts.resource_name == nil or patch.prototype.name == opts.resource_name)
    then
      create_tag(patch)
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
  translations_new()
end)

script.on_configuration_changed(function()
  -- clear translations since prototypes may have changed
  translations_new()
  -- re-create all tags
  tag_all({ announce = true })
end)

script.on_event(defines.events.on_chunk_charted, function(event)
  chunks_add({
    position = event.position,
    force = event.force,
    surface = game.surfaces[event.surface_index],
  })
end)

script.on_event(defines.events.on_string_translated, function(event)
  local translations = global.translations

  if event.translated then
    -- find a pending translation request
    for resource_name, translation in pairs(translations) do
      -- must be same player and localised_string
      -- must be a different result than already stored (possibly nil)
      if translation.player.index == event.player_index and
        translation.result ~= event.result and
        table.compare(translation.localised_string, event.localised_string)
      then
        -- set the result
        translation.result = event.result
        -- update tags for this resource only
        -- updates for everyone on the force
        update_tag_text({
          resource_name = resource_name,
          force = translation.player.force,
        })
        break
      end
    end
  end
end)

local PROCESS_FREQUENCY = 1
local PROCESS_CHUNK_BATCH = 1000
local PROCESS_ENTITY_BATCH = 256

script.on_nth_tick(PROCESS_FREQUENCY, function()
  local chunks_processed_this_tick = 0
  local entities_processed_this_tick = 0
  while (not chunks_empty() or #global.entity_queue > 0) and
    chunks_processed_this_tick < PROCESS_CHUNK_BATCH and
    entities_processed_this_tick < PROCESS_ENTITY_BATCH
  do
    if #global.entity_queue > 0 then
      -- process entities from the current chunk
      local chunk = global.current_chunk

      local entities_to_process = math.min(#global.entity_queue, PROCESS_ENTITY_BATCH - entities_processed_this_tick)
      entities_processed_this_tick = entities_processed_this_tick + entities_to_process
      for idx = #global.entity_queue-entities_to_process+1,#global.entity_queue do
        -- pop an entity from the queue
        local resource_entity = global.entity_queue[idx]
        global.entity_queue[idx] = nil

        -- find and remove all patches the current entity is adjacent to
        -- and merge them into one
        local merged_patch = {
          id = global.next_patch_id,
          prototype = resource_entity.prototype,
          bbs = patch_bbs_new(resource_entity.bounding_box),
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
            patch_bbs_concat(merged_patch.bbs, patch.bbs)
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

      if #global.entity_queue == 0 then
        -- finished processing this chunk
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

        global.current_chunk = nil
      end
    else
      -- get next chunk to process
      local chunk = chunks_next()
      chunks_processed_this_tick = chunks_processed_this_tick + 1

      -- find all resources in chunk
      local resource_entities = chunk.surface.find_entities_filtered{
        area = chunk_area(chunk),
        type = 'resource',
      }

      if #resource_entities > 0 then
        global.current_chunk = chunk
        global.entity_queue = resource_entities
      end
    end
  end

  if entities_processed_this_tick > 0 then
    show_tags()
  end

  if announce_finish_processing ~= nil and
    chunks_empty() and
    #global.entity_queue == 0
  then
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
