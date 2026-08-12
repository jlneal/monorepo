local Admission = assert(loadfile("wild_skies/lib/campaign_admission.lua"))()
local calls, warnings = 0, 0
local mod = { log = { warn = function() warnings = warnings + 1 end } }
function mod.find(id)
  assert(id == "rby_shared_campaign")
  return { exports = { wildEncounterAdmission = function(source)
    calls = calls + 1; assert(source == "sky")
    return { allow = false, handled = true, consumeEncounter = false }
  end } }
end
local allowed, decision = Admission.admit(mod, "sky")
assert(not allowed and decision.handled and decision.consumeEncounter == false,
  "an unprepared journey preserves the flyer before claim or despawn")
assert(calls == 1, "one sky contact asks campaign policy exactly once")
mod.find = function() return nil end
assert(Admission.admit(mod, "sky") == true,
  "an install without campaign content keeps native Wild Skies behavior")
mod.find = function() error("broken lookup") end
assert(Admission.admit(mod, "sky") == false and warnings == 1,
  "provider failures preserve the flyer and report the compatibility fault")
print("Wild Skies campaign admission: 4 assertions passed")
