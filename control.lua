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

local function chunk_area_containing(position)
  local chunk_pos = {
    x = math.floor(position.x / 32),
    y = math.floor(position.y / 32),
  }
  return {
    left_top = {
      x = chunk_pos.x * 32,
      y = chunk_pos.y * 32,
    },
    right_bottom = {
      x = (chunk_pos.x + 1) * 32,
      y = (chunk_pos.y + 1) * 32,
    },
  }
end

local function bb_center(bb)
  return {
    x = (bb.left_top.x + bb.right_bottom.x) / 2,
    y = (bb.left_top.y + bb.right_bottom.y) / 2,
  }
end

local function bb_adjacent(bb1, bb2)
  local c1 = bb_center(bb1)
  local c2 = bb_center(bb2)
  local dx = c1.x - c2.x
  local dy = c1.y - c2.y
  return math.sqrt(dx * dx + dy * dy) <= 1
end

local function bbs_center(bbs)
    local center = { x = 0, y = 0 }
    for _, bb in pairs(bbs) do
      local c = bb_center(bb)
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

local function mark_resource_entity(force, surface, resource_entity)
  log('marking resource at ' .. serpent.block(resource_entity.bounding_box))
  local tag = {}
  tag.position = bb_center(resource_entity.bounding_box)
  tag.text = resource_entity.prototype.name
  tag.icon = get_resource_icon(resource_entity)
  log('adding tag ' .. serpent.block(tag))
  force.add_chart_tag(surface, tag)
end

local function mark_area(force, surface, area)
  -- TODO: include resources in surrounding (charted) chunks

  log('marking area ' .. serpent.block(area))

  -- find all resources in area
  resource_entities = surface.find_entities_filtered{
    area = area,
    type = 'resource',
  }

  -- collect all patches of the same resource in the area
  patches = {}
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

    -- remove all adjacent patches and merge them into one
    local merged_patch = {
      prototype = resource_entity.prototype,
      bbs = {},
    }
    for _, patch_idx in pairs(adjacent_patches) do
      local patch = table.remove(patches, patch_idx)
      merged_patch.bbs = list_concat(merged_patch.bbs, patch.bbs)
    end
    -- add the new entity
    table.insert(merged_patch.bbs, resource_entity.bounding_box)

    -- record the merged patch
    table.insert(patches, merged_patch)
  end

  -- now mark each patch
  for _, patch in pairs(patches) do
    local tag = {}
    tag.position = bbs_center(patch.bbs)
    tag.text = patch.prototype.name
    tag.icon = get_resource_icon(patch.prototype)

    log('adding tag ' .. serpent.block(tag))
    force.add_chart_tag(surface, tag)
  end
end

local function on_chunk_charted(event)
  mark_area(event.force, game.surfaces[event.surface_index], event.area)
end

-- script.on_event(defines.events.on_chunk_charted, on_chunk_charted)

commands.add_command('mark-current-area', '', function(event)
  local player = game.players[event.player_index]
  player.print('marking resources in your current chunk')
  local area = chunk_area_containing(player.position)
  mark_area(player.force, player.surface, area)
end)
