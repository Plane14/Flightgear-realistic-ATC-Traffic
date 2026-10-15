# ATC-AI-Traffic (FlightGear addon)

An addon that **interfaces with and upgrades FlightGear's built-in AI Traffic
Manager and ATC/AI systems** with more features and more realistic behaviour — and
that additionally offers a generic worldwide traffic **generator** and (optional)
**live real-world traffic from adsb.lol**. It also adds **procedurally synthesised**
radio / engine / gear / proximity sounds and a Canvas radar.

It is implemented entirely in **NASAL** (no compiled code, no build step) and
ships as a standard FlightGear addon. It builds *on top of* FlightGear's own
systems rather than replacing them: it reads the same navigation databases the
sim uses (`airportinfo()`, `apt.dat`/NavCache, groundnet/threshold/rwyuse data,
SID/STAR/approach procedures, ILS, ATC comms) and drives the AI aircraft that
FlightGear's traffic manager already creates.

---

## 1. Requirements

- FlightGear **2020.3 or newer** (modern addon framework + the FlightGear Nasal
  `http` module for the optional live traffic).
- No other addons required. Works with the stock `fgdata` aircraft / AI models,
  ground networks and procedures.

---

## 2. Install

The addon lives in the folder `atc-ai-traffic/` (it contains
`addon-metadata.xml`). Point FlightGear at it with `--addon`:

```bash
fgfs --addon=/absolute/path/to/atc-ai-traffic
```

or, in the FlightGear Launcher, add the folder to **Add-on → Add-on package
folders** and enable **ATC-AI-Traffic**.

On startup the addon loads all its NASAL modules into the namespace `ATCAI`,
seeds its config under `/sim/atc-ai-traffic/…`, and waits for the
flight-dynamics model before starting.

---

## 3. What it does to the *default* FlightGear traffic & ATC

FlightGear's built-in traffic creates AI aircraft under `/ai/models/aircraft[n]`
and flies them via flightplans, ground networks and runway-use data. This addon
**enhances that real system** (cooperatively — it never deletes or reposition the
stock traffic except to gently steer it) and layers an ATC experience on top:

- **Active runway, for real.** Each tick it derives the active runway from the
  live wind (best headwind, cross/tailwind aware), knows whether the runway has
  an ILS, and matches FlightGear's own runway/groundnet data.
- **Realistic approaches (the headline upgrade).** Aircraft that are clearly
  *arriving* near you are steered down the **localizer** and a **3° glideslope**
  toward the active runway, tapered to the aircraft category's approach speed.
  Uses the real runway geometry + ILS from the sim, not a hard-coded profile.
- **Realistic departures (optional, off by default).** Fresh low departures are
  flown out on the runway heading with a proper climb profile and climb speed,
  so departure gaps and winds look right.
- **SID/STAR/approach awareness.** It reads the airport's published procedures
  via `airportinfo()` to describe and (on the radar) draw the approach path.
- **ATC frequencies.** It exposes the real **tower / ground / approach / ATIS**
  frequencies of the nearest airport from the sim's own comm data (`apt.dat`).
- **Controller-style advisories.** Plain-language `TRAFFIC` calls with clock
  position and relative altitude, arrival/departure classification, `SEPARATION`
  alerts, and an **ATIS-style readout** (`<ICAO> ATIS: arr rwy 28L, wind 230/18
  kt, QNH 2995, TEMP 17`). Advisory-only — it never touches your aircraft.
- **Behaviour & sound.** Proximity engine/flyby/gear sounds and quiet radio
  squelch/chatter ambience near an ATC airport, plus a Canvas radar HUD that
  draws your traffic, the active runway, the extended centreline and the
  approach track.

> FlightGear core does not ship a full interactive ATC voice application (that's
> external tools like ATC-pie/FGCom, which are separate programs). This addon
> gives you an ATC *feel from inside the sim* by computing that data from
> FlightGear's own databases and adding an advisory + approach-assist layer.

### Three traffic sources

Set `/sim/atc-ai-traffic/source` (or use the **Tools → ATC-AI-Traffic** menu):

| source       | behaviour |
|--------------|-----------|
| `fg-traffic` | **(default)** Attach to the aircraft FlightGear's own Traffic Manager creates and **upgrade** them with the ATC/behaviour above. |
| `generator`  | Spawn generic worldwide traffic in a ring around you and steer it realistically through the AI flight controls. Useful where the default traffic is inactive. |
| `adsb`       | Optional **live real-world traffic** from adsb.lol within `radius-nm` of your position. |

The source can be changed at any time; switching away from a source drops the
aircraft that source owned and leaves the rest alone.

### How the aircraft move (realistic behaviour)

Owned/live aircraft are FlightGear **AI objects** driven through the AI
controller only:

```
/ai/models/aircraft[N]/controls/flight/lateral-mode   = hdg
/ai/models/aircraft[N]/controls/flight/vertical-mode  = alt
/ai/models/aircraft[N]/controls/flight/target-hdg / target-alt / target-spd
```

so turns bank, the aircraft pitch to climb/descend and speed ramps naturally via
the built-in AI flight model. Per-category profiles (heavy jet / jet / turboprop
/ piston / helicopter — cruise & approach speeds, climb/descent rates, ceilings,
3° glideslope) are in `nasal/Behavior.nas`.

---

## 4. adsb.lol (optional live traffic)

adsb.lol is a free, community ADS-B aggregator (kind of a community
FlightAware). No API key required. The addon calls:

```
GET {api-base}/v2/lat/{lat}/lon/{lon}/dist/{nm}
```

`{nm}` is `radius-nm` (capped at **250** by the service). Each aircraft record
is mapped from its ICAO type (`t`) to a FlightGear model via `Models.nas`,
placed at its real `lat/lon/alt`, and steered to follow the real `track`,
`alt_baro` and `gs`. Aircraft reporting `alt_baro: "ground"` are skipped.

**Be respectful** — the addon polls no faster than
`/sim/atc-ai-traffic/adsb/poll-interval-sec` (default **30 s**); don't set it
below 10 s.

Enable it via the menu, or:

```bash
setprop('/sim/atc-ai-traffic/source', 'adsb')
setprop('/sim/atc-ai-traffic/adsb/enabled', 1)
```

If the FlightGear `http` module is unavailable (very old builds) the addon logs
that and gracefully disables `adsb`; the other sources keep working.

---

## 5. Sounds

All sound effects are **procedurally synthesised** by
`Tools/generate_sounds.py` (Python standard library only) — no copyrighted /
sampled audio. Plain 16-bit PCM mono `.wav` files in `Sounds/`, played with
FlightGear's `play-audio-sample` fgcommand.

| token       | triggered when                          |
|-------------|-----------------------------------------|
| `squelch`   | a radio opens                           |
| `chatter`   | ATC radio ambience near an airport      |
| `engine`    | a nearby aircraft (volume ∝ closeness)  |
| `flyby`     | a fast aircraft passes very close       |
| `gear``/`stall`/`alarm`/`beacon` | proximity / alert / marker cues |
| `ui-click`  | menu / panel feedback                   |

Customise via settings
(`/sim/atc-ai-traffic/sound/{enabled, master-volume, proximity-enabled, max-distance-nm}`)
or by replacing any `Sounds/<token>.wav` with your own file of the same name
(see `Sounds/CREDITS.md`). Regenerate the whole set with **either** interpreter
(standard library only, deterministic):

```
python3 Tools/generate_sounds.py      # or: node Tools/generate_sounds.js
```

> **Note:** the `Sounds/*.wav` are *generated build artifacts* and may not be
> present in every copy of the repository. If they are missing, the addon still
> loads and runs — the only effect is silence plus a one‑time, actionable log
> message ("No .wav samples found ... run Tools/generate_sounds.js"). Run the
> generator once (Node or Python — both dependency‑free) and they are loaded
> automatically on subsequent starts. No code change is required.

---

## 6. Aircraft models (ICAO → model)

`nasal/Models.nas` maps ~147 ICAO type designators (A320, B738, A333, E175,
DH8D, C172, H60, KC135, …) to FlightGear model paths, and assigns a category +
performance class. Resolution is **best-effort**: FlightGear silently skips a
missing model, and a fallback chain always ends in a guaranteed path
(`Models/Geometry/glider.ac`). For the widest coverage make sure the relevant
`Aircraft/…` and `AI/Aircraft/…` models are installed (they ship with a normal
FlightGear install). When `generator` is used, `TrafficParser` harvests model
paths that already exist in your FlightGear from the stock `AI/Traffic/**`
files. Extend the map by editing the `table` hash in `Models.nas`.

---

## 7. Configuration reference (`/sim/atc-ai-traffic/…`)

| path                        | type   | default              | meaning |
|-----------------------------|--------|----------------------|---------|
| `enabled`                   | bool   | true                 | master on/off |
| `source`                    | string | fg-traffic           | fg-traffic / generator / adsb |
| `max-aircraft`              | int    | 60                   | cap on managed/owned aircraft |
| `radius-nm`                 | int    | 120                  | generator ring / adsb radius (≤250) |
| `cruise-fl`                 | int    | 180                  | cruise flight level for generated traffic |
| `min-sep-nm`                | float  | 3                    | (reserved) separation hint |
| `debug`                     | bool   | false                | verbose debug logging |
| `upgrade.enabled`           | bool   | true                 | enable the ATC behaviour upgrade on default traffic |
| `upgrade.assist-approach`   | bool   | true                 | steer arrivals down localizer + glideslope |
| `upgrade.assist-departure`  | bool   | false                | steer departures on runway heading + climb |
| `upgrade.range-nm`          | float  | 14                   | radius (nm) around you in which the upgrade applies |
| `adsb.enabled`              | bool   | false                | allow the adsb source |
| `adsb/api-base`             | string | https://api.adsb.lol | API base URL |
| `adsb/poll-interval-sec`    | int    | 30                   | minimum seconds between polls |
| `atc.enabled`               | bool   | true                 | advisories, ATIS, radio ambience |
| `atc/advisory-range-nm`     | int    | 12                   | range for TRAFFIC advisories |
| `sound/enabled`             | bool   | true                 | master sound gate |
| `sound/master-volume`       | float  | 0.7                  | 0..1 master volume |
| `sound/proximity-enabled`   | bool   | true                 | distance-based engine/flyby sounds |
| `sound/max-distance-nm`     | float  | 8                    | hearing range for proximity |

Override on the command line, e.g.
`--prop:/sim/atc-ai-traffic/source=adsb`.

---

## 8. Menu (Tools → ATC-AI-Traffic)

- Toggle Traffic Radar
- Traffic source: default FlightGear / generator / adsb.lol (live)
- Toggle traffic upgrade (ATC approach assist)
- Toggle sound
- About / help

---

## 9. How it fits together

```
addon-main.nas       loads into namespace ATCAI and starts on FDM init
  Config.nas         owns /sim/atc-ai-traffic (defaults + typed getters)
  Utils.nas          math / geodesy (haversine, bearings, destination) + formatting
  JSON.nas           minimal recursive-descent JSON parser (for adsb.lol)
  Models.nas         ICAO type -> FG model path, category, performance class
  Sounds.nas         play-audio-sample wrapper over the procedural WAVs
  AIAircraft.nas     create/attach an AI aircraft + steer via controls/flight
  Behavior.nas       realistic cruise/approach/climb targets per category
  TrafficParser.nas  harvest model paths / registrations from stock AI/Traffic
  AdsbSource.nas     OPTIONAL adsb.lol client (feature-detects http module)
  Procedures.nas     airportinfo() data: runways, wind, ILS, freqs, approach tracks
  TrafficManager.nas orchestrator: sources, spawning, upgrade steering, sound
  ATC.nas            the controller: active runway, TWR/GND/APP/ATIS, advisories,
                     separation alerts, approach/departure guidance for default traffic
  HUD.nas            Canvas radar: traffic, active runway, centreline, approach track
```

Each library file defines exactly one namespace symbol; they reference each
other by bare name at call time, so the load order only matters in that every
module must be loaded before `TrafficManager.start()` runs (guaranteed by
`addon-main.nas`).

### Interfacing with the default system — what we read/write

- **Read:** `/ai/models/aircraft[n]/{position,orientation,velocities,callsign}`,
  `/environment/*wind*`, `airportinfo()` (runways, ILS, comms, procedures). Ground
  movement, runways and scheduling remain FlightGear's own
  (`groundnet.xml`, `threshold.xml`, `rwyuse.xml`, traffic schedules) — we don't
  duplicate them.
- **Write (cooperatively):** only `/ai/models/aircraft[n]/controls/flight/*`
  approach/departure targets for aircraft near you, re-applied each tick so it
  composes with the sim rather than fighting it. We never write to the user's own
  aircraft or to FlightGear's asset/config files.

---

## 10. Troubleshooting

- **Nothing to upgrade with the default install** → the default source only
  augments traffic FlightGear already creates: use a traffic scenario / enable
  AI traffic (e.g. via the traffic dialog, `--ai-scenario=` or a multiplayer
  configured airport), then fly near it. Or set `source=generator`.
- **No adsb aircraft** → set `debug=true`, `source=adsb`, confirm your `http`
  module loads, and confirm your area has coverage.
- **Models not showing** → install/extend the AI aircraft models (see §6).
- **No sound** → `/sim/sound/enabled` and `/sim/atc-ai-traffic/sound/enabled`
  must both be on and the `Sounds/*.wav` must exist.
- **Approach assist not obvious** → it is intentionally cooperative and only
  applies within `upgrade.range-nm` to aircraft that look like arrivals; with a
  very small stock traffic count you may see it rarely. Increase range or use
  `generator`.

---

## 11. License

GPL-2.0-or-later. See `LICENSE`. Sounds are procedurally generated and
attribution-free (see `Sounds/CREDITS.md`). FlightGear itself is GPL; this addon
runs inside FlightGear and is therefore distributed GPL-compatible.
