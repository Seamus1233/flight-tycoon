# Handoff: continuing Flight Tycoon on a local machine

This project was built in a cloud session that had no access to Roblox Studio.
Nothing in it has been run in Studio yet. Read this first.

## State
- **Game code** (`src/`): written and syntax-checked (`tools/check_syntax.py`), never run in Studio.
  Expect a few runtime fixes on the first playtest.
- **Plots:** arched hangar + airfield, built in code by `src/server/Services/WorldBuilder.lua`.
  Layout numbers are in `src/shared/Layout.lua`. Not yet seen in Studio.
- **Economy:** `tools/aircraft_data.py` -> `tools/generate.py` regenerates `src/shared/Config/{Aircraft,Items,MeshParts}.lua`.
- **Monetization:** IDs in `src/shared/Config/Monetization.lua` are all 0 until the passes and products are created on the Creator Dashboard.
- **Models:**
  - P-51D and A-10: high-fidelity, made by `blender/hifi/` (`p51.py`, `a10.py`, `lib.py`, `generate_hifi.py`).
  - The other 46: low-poly placeholders from `blender/generate_aircraft.py`.
  - All of them are in `models/<id>/` as `.fbx`, `.obj`, `.blend` and `.parts.json`.
- **Studio side:** none of the meshes have been imported yet. Until they are, the game builds every aircraft out of Parts (`src/shared/AircraftBuilder.lua`).

## First things to do in Studio
1. Load the code with Rojo (`rojo serve` plus the Studio plugin), or with `python3 tools/build_place.py`
   and opening `build/SkyForgeTycoon.rbxlx`.
2. Turn on Game Settings -> Security -> Enable Studio Access to API Services.
3. Playtest. Fix anything in the Output window, then look at a plot: hangar, airfield, bays, pads.
4. Import `models/p51/p51.fbx` and `models/a10/a10.fbx`. Name each Model by its aircraft id and keep the
   part names (Body, Canopy, Gear...). Put them in `ReplicatedStorage/AircraftMeshes`. Check their scale,
   orientation, colours, how they sit parked, and that the gear disappears in flight.
5. Do a multi-client test (Test -> Clients and Servers): plot assignment, saving, purchases.

## Open work
- The user is reviewing the P-51 and A-10. If approved, build the other 46 the same way, one era at a time.
  Each `blender/hifi/<id>.py` follows the same pattern as the existing two.
- Blender: run with `blender -b --python blender/hifi/generate_hifi.py -- p51 a10`, or use the standalone `bpy`
  module on Python 3.11. Overlay renders also need Pillow and reference 3-views; Wikimedia Commons has
  public-domain ones.
- Sounds: the IDs in `src/client/Controllers/Effects.lua` (`Effects.Sounds`) are blank.

## Conventions
- Aircraft data lives in `tools/aircraft_data.py`, the single source of truth. Never edit the generated Config files by hand.
- Every Robux purchase is granted on the server, recorded by `PurchaseId`, and saved before it is acknowledged (`MonetizationService`).
- Display models stand on their gear using `GroundPitch` / `HasGear`. Parts named `Gear*` are removed in flight.
