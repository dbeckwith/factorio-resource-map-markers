-- clear all global data since the format was changed
for key, _ in pairs(global) do
  global[key] = nil
end

-- setup new globals
global.patches = {}
global.next_patch_id = 0
global.chunks = {
  queue = {},
  searched = {},
  head = nil,
}
global.entity_queue = {}
global.current_chunk = nil
