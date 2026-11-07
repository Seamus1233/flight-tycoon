"""
Single source of truth for every aircraft in SkyForge Tycoon.

Both the Blender model generator (blender/generate_aircraft.py) and the
Roblox config generator (tools/generate.py) read from this file.

Dimensions are real-world metres (length L, span S). Shape fields:
  nose     : "prop" | "intake" | "pointed" | "blunt" | "round" | "chine"
  props    : propeller count (0 = jet)
  jets     : rear exhaust nozzles in the fuselage
  pods     : engine pods under the wings
  wing     : "low" | "mid" | "high"
  sweep    : leading-edge sweep in degrees
  taper    : tip chord / root chord
  dihedral : degrees (negative = anhedral)
  tail     : "conv" | "t" | "twin" | "canted" | "delta" | "hbox" | "none"
  canard   : bool
  special  : "" | "twin_boom" | "flying_wing" | "blackbird" | "stealth_facet" | "rear_pods" | "swing"
  color    : RGB 0..1
  speed    : top speed km/h (drives in-game flight speed)
"""

ERAS = [
    {"id": 1, "name": "Propeller Age",   "years": "1935-1945", "color": (0.80, 0.62, 0.35)},
    {"id": 2, "name": "Jet Dawn",        "years": "1944-1955", "color": (0.60, 0.70, 0.78)},
    {"id": 3, "name": "Cold War",        "years": "1955-1970", "color": (0.55, 0.62, 0.45)},
    {"id": 4, "name": "Teen Series",     "years": "1970-1990", "color": (0.50, 0.56, 0.66)},
    {"id": 5, "name": "Generation 4.5",  "years": "1990-2010", "color": (0.40, 0.48, 0.60)},
    {"id": 6, "name": "Stealth Era",     "years": "2005-today", "color": (0.25, 0.27, 0.32)},
]

SILVER = (0.74, 0.76, 0.79)
OLIVE = (0.33, 0.37, 0.22)
NAVY = (0.12, 0.20, 0.38)
GREY = (0.52, 0.56, 0.60)
DARKGREY = (0.30, 0.32, 0.36)
LIGHTGREY = (0.68, 0.70, 0.72)
BLACK = (0.07, 0.07, 0.08)
GREEN = (0.30, 0.38, 0.28)
CAMO = (0.42, 0.40, 0.28)
BLUEGREY = (0.45, 0.52, 0.62)
SAND = (0.70, 0.62, 0.45)


def A(id, name, nation, era, role, L, S, speed, nose="pointed", props=0, jets=1, pods=0,
      wing="mid", sweep=35, taper=0.4, dihedral=0, tail="conv", canard=False,
      special="", color=GREY, premium=False, blurb=""):
    return dict(id=id, name=name, nation=nation, era=era, role=role, L=L, S=S, speed=speed,
                nose=nose, props=props, jets=jets, pods=pods, wing=wing, sweep=sweep,
                taper=taper, dihedral=dihedral, tail=tail, canard=canard, special=special,
                color=color, premium=premium, blurb=blurb)


# Progression order = list order. The last free aircraft is the F-22.
AIRCRAFT = [
    # ---------------- Era 1: Propeller Age ----------------
    A("p51", "P-51 Mustang", "USA", 1, "Fighter", 9.8, 11.3, 703, nose="prop", props=1, jets=0,
      wing="low", sweep=3, taper=0.5, dihedral=5, color=SILVER,
      blurb="The long-range escort that won the skies over Europe."),
    A("spitfire", "Supermarine Spitfire", "UK", 1, "Fighter", 9.1, 11.2, 595, nose="prop", props=1, jets=0,
      wing="low", sweep=2, taper=0.45, dihedral=6, color=GREEN,
      blurb="Elliptical wings and a Merlin engine."),
    A("bf109", "Messerschmitt Bf 109", "Germany", 1, "Fighter", 9.0, 9.9, 640, nose="prop", props=1, jets=0,
      wing="low", sweep=3, taper=0.5, dihedral=6, color=GREY,
      blurb="The most-produced fighter of the war."),
    A("zero", "Mitsubishi A6M Zero", "Japan", 1, "Fighter", 9.1, 12.0, 533, nose="prop", props=1, jets=0,
      wing="low", sweep=2, taper=0.5, dihedral=6, color=(0.72, 0.72, 0.62),
      blurb="Legendary range and agility."),
    A("p47", "P-47 Thunderbolt", "USA", 1, "Fighter-Bomber", 11.0, 12.4, 697, nose="prop", props=1, jets=0,
      wing="low", sweep=2, taper=0.55, dihedral=5, color=OLIVE,
      blurb="The 'Jug' - heavy, tough and fast in a dive."),
    A("f4u", "F4U Corsair", "USA", 1, "Naval Fighter", 10.2, 12.5, 717, nose="prop", props=1, jets=0,
      wing="low", sweep=2, taper=0.5, dihedral=9, color=NAVY,
      blurb="Inverted gull wings and a huge propeller."),
    A("fw190", "Focke-Wulf Fw 190", "Germany", 1, "Fighter", 9.0, 10.5, 685, nose="prop", props=1, jets=0,
      wing="low", sweep=3, taper=0.5, dihedral=5, color=(0.45, 0.48, 0.42),
      blurb="Radial-engined butcher bird."),
    A("p38", "P-38 Lightning", "USA", 1, "Heavy Fighter", 11.5, 15.9, 667, nose="round", props=2, jets=0,
      wing="mid", sweep=2, taper=0.5, dihedral=2, tail="none", special="twin_boom", color=SILVER,
      blurb="Twin booms, twin engines, fork-tailed devil."),
    A("b17", "B-17 Flying Fortress", "USA", 1, "Heavy Bomber", 22.7, 31.6, 462, nose="round", props=4, jets=0,
      wing="low", sweep=3, taper=0.4, dihedral=4, color=OLIVE,
      blurb="Bristling with guns, built to come home."),
    A("b29", "B-29 Superfortress", "USA", 1, "Strategic Bomber", 30.2, 43.1, 574, nose="round", props=4, jets=0,
      wing="mid", sweep=3, taper=0.35, dihedral=4, color=SILVER,
      blurb="Pressurised, high-altitude heavy bomber."),
    A("me262", "Messerschmitt Me 262", "Germany", 1, "Jet Fighter", 10.6, 12.6, 900, nose="pointed", props=0, jets=0, pods=2,
      wing="low", sweep=18, taper=0.45, dihedral=4, color=GREY,
      blurb="The world's first operational jet fighter."),

    # ---------------- Era 2: Jet Dawn ----------------
    A("f86", "F-86 Sabre", "USA", 2, "Jet Fighter", 11.4, 11.3, 1106, nose="intake", wing="low", sweep=35,
      taper=0.5, dihedral=3, color=SILVER, blurb="Swept-wing king of MiG Alley."),
    A("mig15", "MiG-15", "USSR", 2, "Jet Fighter", 10.1, 10.1, 1076, nose="intake", wing="mid", sweep=37,
      taper=0.55, dihedral=-2, tail="t", color=SILVER, blurb="Shocked the West over Korea."),
    A("hunter", "Hawker Hunter", "UK", 2, "Jet Fighter", 14.0, 10.3, 1150, nose="pointed", wing="mid", sweep=40,
      taper=0.4, dihedral=-1, color=GREEN, blurb="Graceful transonic interceptor."),
    A("f100", "F-100 Super Sabre", "USA", 2, "Fighter-Bomber", 15.2, 11.8, 1390, nose="intake", wing="low",
      sweep=45, taper=0.3, dihedral=0, color=SILVER, blurb="First US fighter supersonic in level flight."),
    A("f104", "F-104 Starfighter", "USA", 2, "Interceptor", 16.7, 6.6, 2137, nose="pointed", wing="mid", sweep=10,
      taper=0.4, dihedral=-10, tail="t", color=SILVER, blurb="The missile with a man in it."),
    A("b52", "B-52 Stratofortress", "USA", 2, "Strategic Bomber", 48.5, 56.4, 1047, nose="round", jets=0, pods=4,
      wing="high", sweep=35, taper=0.35, dihedral=-3, color=GREY, blurb="Seventy years and still flying."),

    # ---------------- Era 3: Cold War ----------------
    A("a4", "A-4 Skyhawk", "USA", 3, "Attack", 12.2, 8.4, 1083, nose="pointed", wing="low", sweep=33, taper=0.3,
      dihedral=0, color=GREY, blurb="Heinemann's Hot Rod."),
    A("mig21", "MiG-21 Fishbed", "USSR", 3, "Interceptor", 14.7, 7.2, 2175, nose="intake", wing="mid", sweep=57,
      taper=0.05, dihedral=-2, color=SILVER, blurb="The most-produced supersonic jet ever."),
    A("f4", "F-4 Phantom II", "USA", 3, "Multirole", 19.2, 11.7, 2370, nose="pointed", jets=2, wing="low",
      sweep=45, taper=0.3, dihedral=5, color=(0.45, 0.48, 0.40), blurb="Proof that a brick can fly with enough thrust."),
    A("mirage3", "Dassault Mirage III", "France", 3, "Interceptor", 15.0, 8.2, 2350, nose="pointed", wing="low",
      sweep=60, taper=0.03, dihedral=0, tail="delta", color=SILVER, blurb="Pure tailless delta elegance."),
    A("f105", "F-105 Thunderchief", "USA", 3, "Fighter-Bomber", 19.6, 10.7, 2208, nose="pointed", wing="mid",
      sweep=45, taper=0.4, dihedral=0, color=CAMO, blurb="The 'Thud' - fastest at low level."),
    A("harrier", "AV-8B Harrier II", "USA/UK", 3, "V/STOL Attack", 14.1, 9.3, 1083, nose="pointed", wing="high",
      sweep=35, taper=0.35, dihedral=-12, color=GREY, blurb="Takes off straight up."),
    A("sr71", "SR-71 Blackbird", "USA", 3, "Recon", 32.7, 16.9, 3540, nose="chine", jets=0, pods=2, wing="mid",
      sweep=60, taper=0.08, dihedral=0, tail="canted", special="blackbird", color=BLACK,
      blurb="Mach 3+. Outran every missile fired at it."),
    A("a10", "A-10 Thunderbolt II", "USA", 3, "Close Air Support", 16.3, 17.5, 706, nose="blunt", jets=0, wing="low",
      sweep=0, taper=0.65, dihedral=4, tail="hbox", special="rear_pods", color=DARKGREY,
      blurb="A flying cannon. BRRRT."),

    # ---------------- Era 4: Teen Series ----------------
    A("f14", "F-14 Tomcat", "USA", 4, "Naval Interceptor", 19.1, 19.5, 2485, nose="pointed", jets=2, wing="high",
      sweep=22, taper=0.35, dihedral=0, tail="twin", special="swing", color=LIGHTGREY,
      blurb="Swing wings, Phoenix missiles, carrier legend."),
    A("f15", "F-15 Eagle", "USA", 4, "Air Superiority", 19.4, 13.0, 2655, nose="pointed", jets=2, wing="high",
      sweep=45, taper=0.25, dihedral=-1, tail="twin", color=BLUEGREY,
      blurb="104 victories, zero losses in air combat."),
    A("f16", "F-16 Fighting Falcon", "USA", 4, "Multirole", 15.0, 9.96, 2120, nose="pointed", wing="mid",
      sweep=40, taper=0.23, dihedral=0, color=GREY, blurb="The Viper - fly-by-wire pioneer."),
    A("f18", "F/A-18 Hornet", "USA", 4, "Naval Multirole", 17.1, 12.3, 1915, nose="pointed", jets=2, wing="mid",
      sweep=26, taper=0.35, dihedral=-3, tail="canted", color=GREY, blurb="Workhorse of the carrier deck."),
    A("mig29", "MiG-29 Fulcrum", "USSR", 4, "Air Superiority", 17.3, 11.4, 2400, nose="pointed", jets=2, wing="mid",
      sweep=42, taper=0.25, dihedral=-2, tail="twin", color=BLUEGREY, blurb="Agile Soviet dogfighter."),
    A("su27", "Su-27 Flanker", "USSR", 4, "Air Superiority", 21.9, 14.7, 2500, nose="pointed", jets=2, wing="mid",
      sweep=42, taper=0.25, dihedral=-2, tail="twin", color=(0.55, 0.65, 0.75), blurb="Pulled the Cobra at Paris."),
    A("mirage2000", "Dassault Mirage 2000", "France", 4, "Multirole", 14.4, 9.1, 2336, nose="pointed", wing="low",
      sweep=58, taper=0.05, dihedral=0, tail="delta", color=GREY, blurb="Fly-by-wire delta reborn."),
    A("f117", "F-117 Nighthawk", "USA", 4, "Stealth Attack", 20.1, 13.2, 993, nose="chine", jets=2, wing="low",
      sweep=67, taper=0.05, dihedral=0, tail="canted", special="stealth_facet", color=BLACK,
      blurb="The first operational stealth aircraft."),
    A("b1b", "B-1B Lancer", "USA", 4, "Strategic Bomber", 44.5, 41.8, 1335, nose="pointed", jets=0, pods=2, wing="low",
      sweep=30, taper=0.3, dihedral=0, special="swing", color=DARKGREY, blurb="The Bone - supersonic heavy bomber."),
    A("b2", "B-2 Spirit", "USA", 4, "Stealth Bomber", 21.0, 52.4, 1010, nose="chine", jets=0, wing="mid",
      sweep=33, taper=0.1, dihedral=0, tail="none", special="flying_wing", color=DARKGREY,
      blurb="A $2 billion flying wing."),

    # ---------------- Era 5: Generation 4.5 ----------------
    A("f18e", "F/A-18E Super Hornet", "USA", 5, "Naval Multirole", 18.3, 13.6, 1915, nose="pointed", jets=2,
      wing="mid", sweep=28, taper=0.33, dihedral=-3, tail="canted", color=GREY, blurb="Bigger, longer, deadlier."),
    A("gripen", "JAS 39 Gripen", "Sweden", 5, "Multirole", 15.2, 8.4, 2204, nose="pointed", wing="mid", sweep=50,
      taper=0.1, dihedral=0, tail="delta", canard=True, color=GREY, blurb="Flies from public roads."),
    A("rafale", "Dassault Rafale", "France", 5, "Omnirole", 15.3, 10.9, 1912, nose="pointed", jets=2, wing="low",
      sweep=48, taper=0.1, dihedral=0, tail="delta", canard=True, color=DARKGREY, blurb="Does every mission."),
    A("typhoon", "Eurofighter Typhoon", "Europe", 5, "Air Superiority", 15.96, 10.95, 2495, nose="intake", jets=2,
      wing="low", sweep=53, taper=0.1, dihedral=0, tail="delta", canard=True, color=GREY,
      blurb="Supercruising canard-delta."),
    A("su35", "Su-35 Flanker-E", "Russia", 5, "Air Superiority", 21.9, 15.3, 2400, nose="pointed", jets=2, wing="mid",
      sweep=42, taper=0.25, dihedral=-2, tail="twin", color=(0.40, 0.50, 0.62),
      blurb="Thrust vectoring super-manoeuvrability."),
    A("f15ex", "F-15EX Eagle II", "USA", 5, "Multirole", 19.4, 13.0, 2655, nose="pointed", jets=2, wing="high",
      sweep=45, taper=0.25, dihedral=-1, tail="twin", color=DARKGREY, blurb="The Eagle, rebuilt for a new century."),

    # ---------------- Era 6: Stealth Era ----------------
    A("j20", "Chengdu J-20", "China", 6, "Stealth Fighter", 21.2, 13.5, 2100, nose="chine", jets=2, wing="mid",
      sweep=48, taper=0.1, dihedral=0, tail="canted", canard=True, color=DARKGREY, blurb="The Mighty Dragon."),
    A("su57", "Sukhoi Su-57", "Russia", 6, "Stealth Fighter", 20.1, 14.1, 2135, nose="chine", jets=2, wing="mid",
      sweep=48, taper=0.2, dihedral=0, tail="canted", color=(0.35, 0.40, 0.48), blurb="Felon - Russia's fifth gen."),
    A("f35", "F-35 Lightning II", "USA", 6, "Stealth Multirole", 15.7, 10.7, 1930, nose="chine", jets=1, wing="mid",
      sweep=34, taper=0.2, dihedral=0, tail="canted", color=(0.42, 0.44, 0.47),
      blurb="Sensor-fused stealth for a dozen air forces."),
    A("f22", "F-22 Raptor", "USA", 6, "Stealth Air Dominance", 18.9, 13.6, 2414, nose="chine", jets=2, wing="mid",
      sweep=42, taper=0.15, dihedral=0, tail="canted", color=(0.46, 0.48, 0.52),
      blurb="The apex predator. Supercruise and stealth."),

    # ---------------- Premium "Black Projects" (gamepass) ----------------
    A("b21", "B-21 Raider", "USA", 6, "Black Project Bomber", 16.0, 45.0, 1100, nose="chine", jets=0, wing="mid",
      sweep=35, taper=0.12, dihedral=0, tail="none", special="flying_wing", color=(0.22, 0.23, 0.26),
      premium=True, blurb="Classified next-generation stealth bomber."),
    A("f47", "F-47 NGAD", "USA", 6, "Black Project Fighter", 20.0, 13.0, 2600, nose="chine", jets=2, wing="mid",
      sweep=50, taper=0.1, dihedral=0, tail="none", canard=True, color=(0.20, 0.22, 0.25),
      premium=True, blurb="Sixth-generation air dominance."),
    A("sr72", "SR-72 Hypersonic", "USA", 6, "Black Project Recon", 30.0, 12.0, 7400, nose="chine", jets=0, pods=0,
      wing="mid", sweep=70, taper=0.03, dihedral=0, tail="canted", special="blackbird", color=(0.12, 0.12, 0.14),
      premium=True, blurb="Mach 6 hypersonic concept. Faster than anything."),
]

# Facilities you buy between aircraft. "bonus" = additive income bonus.
# gate=True means you cannot buy the next era's first aircraft without it.
FACILITIES = [
    # era, id, name, bonus, gate
    (1, "fence",          "Perimeter Fence",            0.00, False),
    (1, "tower",          "Control Tower",              0.10, False),
    (1, "fuel",           "Fuel Depot",                 0.10, False),
    (1, "jetlab",         "Jet Propulsion Lab",         0.10, True),
    (2, "radar",          "Radar Dome",                 0.15, False),
    (2, "robots",         "Assembly Robots",            0.15, False),
    (2, "windtunnel",     "Supersonic Wind Tunnel",     0.15, True),
    (3, "range",          "Missile Test Range",         0.20, False),
    (3, "shelters",       "Hardened Shelters",          0.20, False),
    (3, "avionics",       "Avionics Center",            0.20, True),
    (4, "runway2",        "Second Runway",              0.25, False),
    (4, "simulator",      "Flight Simulator Hall",      0.25, False),
    (4, "composites",     "Composite Materials Plant",  0.25, True),
    (5, "satellite",      "Satellite Uplink",           0.30, False),
    (5, "skunkworks",     "Skunk Works Lab",            0.30, True),
    (6, "stealthcoat",    "Stealth Coating Facility",   0.40, False),
    (6, "monument",       "Air Supremacy Monument",     0.50, False),
]
