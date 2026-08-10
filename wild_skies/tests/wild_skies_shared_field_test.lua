-- Protocol-normalized SKY field: stable export/import and deferred atomic claim.
package.path = "./?.lua;./?/init.lua;" .. package.path

local os = require("os")
local T = require("tests.modkit")
local Data = require("src.core.Data"); Data:load()

local ow = {
  entities = {}, camera = { x = 0, y = 0 },
  player = { cellX = 15, cellY = 15, px = 240, py = 240 },
  map = { id = "ROUTE_1", widthCells = 30, heightCells = 30,
    inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < 30 and y < 30 end,
    isWalkableCell = function() return true end },
}
local Game = { data = Data, overworld = ow,
  renderer = { worldViewSize = function() return 160, 144 end },
  mods = { exports = {} },
}
package.loaded["src.core.Game"] = Game
Data.sprites = Data.sprites or {}
Data.sprites.SPRITE_BIRD = Data.sprites.SPRITE_BIRD
  or { image = "fixture_bird.png", frames = 6 }

local run = T.sdk.loadMod(os.getenv("MOD_DIR") or "mods/wild_skies", { data = Data })
T.eq(#run.errors, 0, "loads clean")
local api = run.loader.exports.wild_skies
local id
for _ = 1, 8 do id = api.spawnFlyer("PIDGEY", 7); if id then break end end
T.check(id ~= nil, "fixture flyer spawned")
local f = ow.entities[#ow.entities]
f.px, f.py, f.alt, f.cellX, f.cellY = 160, 96, 56, 10, 6
f.facing, f.mode, f.bold, f.t = "right", "roam", true, 1

local snap = api.sharedSkyFieldSnapshot("ROUTE_1")
T.eq(snap.domain, "SKY", "snapshot names its normalized domain")
T.eq(snap.spawns[1].id, id, "stable flyer id exported")
T.eq(snap.spawns[1].alt, 56, "altitude exported")

local claims = 0
Game.mods.exports.rby_mmo = { claimSharedSkyField = function(map, claimId)
  claims = claims + 1
  return map == "ROUTE_1" and claimId == id
end }
snap.revision, snap.localAuthority = 1, true
T.check(api.applySharedSkyFieldSnapshot(snap), "authority echo enables shared mode")
local activeAuthorityMarker = f.sharedReplica
local offscreen = { domain = "SKY", map = "ROUTE_3", revision = 1,
  localAuthority = false, spawns = {} }
T.check(api.applySharedSkyFieldSnapshot(offscreen),
  "an off-screen field snapshot is cached")
T.eq(f.sharedReplica, activeAuthorityMarker,
  "an off-screen lease cannot demote the active map authority")
T.eq(api.takeFlyer(10, 6, 1), nil, "shared contact waits for hub permission")
T.eq(claims, 1, "the exact stable flyer is claimed once")
T.eq(api.takeFlyer(10, 6, 1), nil, "duplicate contact stays pending")
T.eq(claims, 1, "pending contact does not emit duplicate claims")
T.check(api.denySharedSkyFieldContact("ROUTE_1", id),
  "explicit denial releases the pending claim")
T.eq(#ow.entities, 1, "denial preserves the canonical flyer")

snap.localAuthority = false
snap.spawns[1].x, snap.spawns[1].y, snap.spawns[1].alt = 176, 112, 64
T.check(api.applySharedSkyFieldSnapshot(snap), "replica accepts canonical movement")
T.eq(#ow.entities, 1, "replica reconciliation preserves render identity")
local liveReplica = ow.entities[1]
snap.localAuthority = true
T.check(api.applySharedSkyFieldSnapshot(snap),
  "the remaining player can inherit authority over a replica")
T.eq(liveReplica.sharedReplica, false,
  "authority inheritance promotes the replica to full movement state")
T.check(type(liveReplica.speed) == "number" and liveReplica.speed > 0,
  "the promoted authority has a nonzero flight speed")
snap.localAuthority = false
T.check(api.applySharedSkyFieldSnapshot(snap),
  "the promoted flyer can return to replica presentation")
local staleReplica = { wildSkiesFlyer = true, id = liveReplica.id }
ow.entities = { staleReplica }
T.check(api.applySharedSkyFieldSnapshot(snap),
  "a post-battle canonical echo reasserts live render identities")
T.eq(#ow.entities, 1, "post-battle entity reconciliation keeps one flyer")
T.check(ow.entities[1] == liveReplica,
  "a restored stale flyer is replaced by the live canonical replica")
local neighborMap = { id = "ROUTE_2", widthCells = 30, heightCells = 30,
  def = { tileset = "OVERWORLD" },
  inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < 30 and y < 30 end,
  isWalkableCell = function() return true end }
ow.neighbors = { { map = neighborMap, ox = 480, oy = 0 } }
ow.ghosts = {}
local neighborIds = api.sharedSkyNeighborMaps()
T.eq(neighborIds[1], "ROUTE_2",
  "Wild Skies exposes the engine-resident seam neighbor for prewarming")
local neighborSnap = api.sharedSkyFieldSnapshot("ROUTE_2")
T.check(neighborSnap and #neighborSnap.spawns > 0,
  "an authority can seed a visible resident-neighbor sky")
neighborSnap.localAuthority = false
T.check(api.applySharedSkyFieldSnapshot(neighborSnap),
  "the canonical neighbor snapshot projects without changing active maps")
T.eq(#ow.ghosts, #neighborSnap.spawns,
  "every prewarmed neighbor flyer occupies the engine ghost surface")
T.check(ow.ghosts[1].wildSkiesSharedGhost == true,
  "neighbor flyers are visual-only until their map becomes current")
T.check(api.clearSharedSkyField(), "party end clears normalized sky state")
T.eq(#ow.entities, 0, "shared replicas do not leak into solo play")
T.eq(#ow.ghosts, 0, "shared neighbor flyers do not leak into solo play")

run.release()
T.finish("wild_skies_shared_field")
