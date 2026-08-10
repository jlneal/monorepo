-- Hide Wilds' local trailer convoy without destroying its trail history.
-- pokepcTrailers remains authoritative; only the two engine render/update
-- lists change, so landing can restore the same objects in the same places.
local M = {}

local function removeIdentity(list, wanted)
  for i = #(list or {}), 1, -1 do
    if wanted[list[i]] then table.remove(list, i) end
  end
end

local function contains(list, value)
  for _, row in ipairs(list or {}) do
    if row == value then return true end
  end
  return false
end

function M.hide(ow)
  local wanted, count = {}, 0
  for _, npc in ipairs((ow and ow.pokepcTrailers) or {}) do
    if npc and npc.pokepcTrailer == true and npc.mmoRemoteFollower ~= true then
      npc.__freeFlyConvoyHidden = true
      wanted[npc], count = true, count + 1
    end
  end
  if count == 0 then return 0 end
  removeIdentity(ow.npcs, wanted)
  removeIdentity(ow.entities, wanted)
  return count
end

function M.restore(ow)
  local count = 0
  for _, npc in ipairs((ow and ow.pokepcTrailers) or {}) do
    if npc and npc.pokepcTrailer == true and npc.mmoRemoteFollower ~= true
       and npc.__freeFlyConvoyHidden == true then
      -- Door entries deliberately keep queued trailers outside both engine
      -- lists until there is room to emerge.  Flight must not materialize
      -- them early merely because the player landed during that handoff.
      if not npc._wildsDoorQueued then
        if not contains(ow.npcs, npc) then table.insert(ow.npcs, npc) end
        if not contains(ow.entities, npc) then table.insert(ow.entities, npc) end
      end
      npc.__freeFlyConvoyHidden = nil
      count = count + 1
    end
  end
  return count
end

-- Crossing a seam in flight can leave Wilds' old trailer objects queued in
-- the previous transition space.  Let Wilds rebuild from its authoritative
-- party state before restoring, rather than trying to reinterpret those
-- private queue markers here.
function M.rebuildAndRestore(ow, rebuild)
  if type(rebuild) == "function" then
    local ok, err = pcall(rebuild)
    if not ok then return false, err end
  end
  M.restore(ow)
  return true
end

-- Wilds reconciles its authoritative trailer list after Free Fly's supported
-- input-step heartbeat.  Wrap that public follower-control object once so its
-- final act each frame is to suppress the local convoy while airborne.  The
-- predicate is stored on the object (rather than captured permanently), which
-- keeps F5/hot reload from consulting an obsolete Free Fly state table.
function M.installControlBridge(control, isFlying)
  if type(control) ~= "table" or type(control.update) ~= "function" then
    return false
  end
  control.__freeFlyVisibilityPredicate = isFlying
  if control.__freeFlyVisibilityWrapped then return true end
  control.__freeFlyVisibilityWrapped = true
  control.__freeFlyVisibilityOrigUpdate = control.update
  control.update = function(self, game, ow, ...)
    local a, b, c, d = self.__freeFlyVisibilityOrigUpdate(self, game, ow, ...)
    local predicate = self.__freeFlyVisibilityPredicate
    local ok, active = pcall(predicate or function() return false end)
    if ok and active == true then M.hide(ow) end
    return a, b, c, d
  end
  return true
end

return M
