-- Optional campaign safety admission. Consumers call this before claiming or
-- removing a flyer so a no-Pokemon return never consumes shared world state.

local M = {}

function M.admit(mod, source)
  if type(mod) ~= "table" or type(mod.find) ~= "function" then return true end
  local okFind, found = pcall(mod.find, "rby_shared_campaign")
  if not okFind then
    if mod.log and mod.log.warn then
      mod.log:warn("campaign sky admission lookup failed; preserving flyer (%s)",
        tostring(found))
    end
    return false, found
  end
  local api = okFind and found and found.exports
  local provider = api and api.wildEncounterAdmission
  if type(provider) ~= "function" then return true end
  local ok, decision, why = pcall(provider, source)
  if not ok or type(decision) ~= "table" then
    local reason = ok and why or decision
    if mod.log and mod.log.warn then
      mod.log:warn("campaign sky admission failed; preserving flyer (%s)",
        tostring(reason))
    end
    return false, reason or "campaign sky admission failed"
  end
  if decision.allow == true then return true, decision end
  return false, decision
end

return M
