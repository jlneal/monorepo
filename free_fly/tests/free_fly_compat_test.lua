package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local root = os.getenv("MOD_DIR") or "mods/free_fly"
local FlightInput = assert(loadfile(root .. "/lib/FlightInput.lua"))()
local VoxelProvider = assert(loadfile(root .. "/lib/VoxelProvider.lua"))()
local ConvoyVisibility = assert(loadfile(root .. "/lib/ConvoyVisibility.lua"))()

local requested = 0
local input = { pressQueue = { "up", "b" } }
T.check(FlightInput.capture(input, true, function() requested = requested + 1 end),
  "semantic B queue edge requests landing")
T.eq(requested, 1, "landing callback runs once")
T.eq(#input.pressQueue, 2, "capture leaves the engine input edge intact")
T.check(not FlightInput.capture({ pressQueue = { "x" } }, true, function() end),
  "physical keys are not confused with semantic actions")
T.check(not FlightInput.capture(input, false, function() requested = 99 end),
  "grounded input cannot request landing")
T.eq(requested, 1, "grounded B does not run the callback")

local original = { require = function() end }
local fork = { require = function() end }
T.eq(VoxelProvider.lib({ mods = { exports = {
  DRAMATIC_SHAPE = { lib = original },
} } }), original, "original Dramatic Shape provider resolves")
T.eq(VoxelProvider.lib({ mods = { exports = {
  BATTLE_ART_VOXEL_FORK = { lib = fork },
} } }), fork, "battle-art fork provider resolves")
T.eq(VoxelProvider.lib({ mods = { exports = {
  DRAMATIC_SHAPE = { lib = original },
  BATTLE_ART_VOXEL_FORK = { lib = fork },
} } }), original, "original provider wins when both are active")
T.eq(VoxelProvider.lib({}), nil, "missing voxel provider is safe")

local a = { pokepcTrailer = true }
local b = { pokepcTrailer = true }
local remote = { pokepcTrailer = true, mmoRemoteFollower = true }
local villager = {}
local ow = {
  pokepcTrailers = { a, b },
  npcs = { villager, a, remote, b },
  entities = { a, villager, b, remote },
}
T.eq(ConvoyVisibility.hide(ow), 2, "the complete local convoy is hidden")
T.eq(#ow.pokepcTrailers, 2, "hidden trailers retain authoritative history")
T.eq(#ow.npcs, 2, "only local trailers leave the NPC draw list")
T.eq(#ow.entities, 2, "only local trailers leave the entity draw list")
T.check(ow.npcs[1] == villager and ow.npcs[2] == remote,
  "villagers and remote followers remain visible")
T.eq(ConvoyVisibility.restore(ow), 2, "landing restores the local convoy")
T.eq(#ow.npcs, 4, "restored NPC list has one copy per trailer")
T.eq(#ow.entities, 4, "restored entity list has one copy per trailer")
ConvoyVisibility.restore(ow)
T.eq(#ow.npcs, 4, "repeated restoration cannot duplicate trailers")
T.eq(#ow.entities, 4, "entity restoration is also idempotent")

local queued = { pokepcTrailer = true, _wildsDoorQueued = true }
local doorway = { pokepcTrailers = { queued }, npcs = { queued }, entities = { queued } }
ConvoyVisibility.hide(doorway)
ConvoyVisibility.restore(doorway)
T.eq(#doorway.entities, 0, "landing does not materialize a door-queued trailer")
T.check(queued.__freeFlyConvoyHidden == nil, "door-queued hide marker is cleared")

local oldSeamTrailer = {
  pokepcTrailer = true, _wildsDoorQueued = true,
  __freeFlyConvoyHidden = true,
}
local seamLanding = {
  pokepcTrailers = { oldSeamTrailer }, npcs = {}, entities = {},
}
local rebuiltTrailer = { pokepcTrailer = true }
local rebuilt = 0
T.check(ConvoyVisibility.rebuildAndRestore(seamLanding, function()
  rebuilt = rebuilt + 1
  seamLanding.pokepcTrailers = { rebuiltTrailer }
  seamLanding.npcs = { rebuiltTrailer }
  seamLanding.entities = { rebuiltTrailer }
end), "landing after a seam accepts Wilds' authoritative convoy rebuild")
T.eq(rebuilt, 1, "the follower owner is asked to rebuild exactly once")
T.check(seamLanding.entities[1] == rebuiltTrailer,
  "the rebuilt follower is visible immediately on landing")
T.eq(#seamLanding.entities, 1,
  "the obsolete seam-queued follower is not resurrected")

local airborne = true
local calls = 0
local control = {
  update = function(self, game, state)
    calls = calls + 1
    -- Wilds reconciliation happens late and puts its trailer back.
    state.npcs[#state.npcs + 1] = a
    state.entities[#state.entities + 1] = a
    return "updated", "detail"
  end,
}
ow.npcs, ow.entities = { villager }, { villager }
T.check(ConvoyVisibility.installControlBridge(control, function() return airborne end),
  "Wilds control bridge installs")
local ra, rb = control:update({}, ow)
T.eq(ra, "updated", "bridge preserves first update result")
T.eq(rb, "detail", "bridge preserves second update result")
T.eq(calls, 1, "bridge calls Wilds update exactly once")
T.eq(#ow.entities, 1, "bridge hides a trailer re-added late by Wilds")
airborne = false
control:update({}, ow)
T.eq(#ow.entities, 2, "grounded Wilds reconciliation remains visible")

T.finish("free_fly_compat")
