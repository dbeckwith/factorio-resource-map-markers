local math2d = require('math2d')
local util = require('util')

local function list_contains(l, e)
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

local function chunk_position_containing(position)
  return {
    x = math.floor(position.x / 32),
    y = math.floor(position.y / 32),
  }
end

local function chunk_area(chunk_position)
  return {
    left_top = {
      x = chunk_position.x * 32,
      y = chunk_position.y * 32,
    },
    right_bottom = {
      x = (chunk_position.x + 1) * 32,
      y = (chunk_position.y + 1) * 32,
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

local function mark_chunk(force, surface, chunk_position)
  log('marking chunk ' .. chunk_position.x .. ',' .. chunk_position.y)

  -- collect all patches of the same resource
  local patches = {}

  -- search through chunks
  local chunks_to_search = {chunk_position}
  local searched_chunks = {}
  while #chunks_to_search ~= 0 do
    local chunk_position = table.remove(chunks_to_search)

    log('searching chunk ' .. chunk_position.x .. ',' .. chunk_position.y)

    -- this is the origin chunk if we haven't searched anything yet
    local is_origin_chunk = #searched_chunks == 0

    -- mark this chunk as searched
    table.insert(searched_chunks, chunk_position)

    -- find all resources in chunk
    local resource_entities = surface.find_entities_filtered{
      area = chunk_area(chunk_position),
      type = 'resource',
    }
    for _, resource_entity in pairs(resource_entities) do
      -- find the index of all patches the current entity is adjacent to
      local adjacent_patches = {}
      for patch_idx, patch in pairs(patches) do
        -- only consider patches with the same resource
        if resource_entity.prototype == patch.prototype then
          -- if the current entity is adjacent to any of the bounding boxes in
          -- the patch, record the patch index
          for _, patch_bb in pairs(patch.bbs) do
            if bb_adjacent(resource_entity.bounding_box, patch_bb) then
              table.insert(adjacent_patches, patch_idx)
              break
            end
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
    for neighbor_chunk_position in cardinal_neighbors(chunk_position) do
      if not list_contains(searched_chunks, neighbor_chunk_position) then
        -- see if any patches are adjacent to the neighboring chunk
        for _, patch in pairs(patches) do
          if bb_adjacent(chunk_area(neighbor_chunk_position), patch.bb) then
            table.insert(chunks_to_search, neighbor_chunk_position)
            break
          end
        end
      end
    end
  end

  -- mark each patch
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

-- script.on_event(defines.events.on_chunk_charted, function(event)
--   mark_chunk(event.force, game.surfaces[event.surface_index], event.position)
-- end)

commands.add_command('mark-current-chunk', '', function(event)
  local player = game.players[event.player_index]
  player.print('marking resources in your current chunk')
  local chunk_position = chunk_position_containing(player.position)
  mark_chunk(player.force, player.surface, chunk_position)
end)
