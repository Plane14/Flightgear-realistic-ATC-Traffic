# Sound Credits

All `.wav` files in this directory are **procedurally synthesized** by the addon's
own generator. They contain **no copyrighted, sampled, or third-party material** —
every sample is generated from scratch with pure math (sines, filtered noise, and
envelopes). You are free to use, modify, and redistribute these sounds.

## Format

Each file is a standard audio file:

- **16-bit PCM**, **MONO**, **22050 Hz** sample rate
- `.wav` (RIFF) container

Keeping this exact format matters — FlightGear's `play-audio-sample` command
expects 16-bit mono WAV. If you need to change a length, regenerate rather than
re-encode (re-encoding can introduce format or channel surprises).

## Regenerating

The sounds are produced by a single standard-library-only generator, provided in
two equivalent forms so you can use whichever interpreter you have:

```
# Python 3 (standard library only)
python3 Tools/generate_sounds.py

# ...or Node.js (equivalent, standard library only)
node Tools/generate_sounds.js
```

Running either rewrites every `.wav` in this folder. Both scripts are
deterministic (fixed random seed), so repeated runs produce identical output.

## The bundled samples

Each sound name below is the *token* passed to `ATCAI.Sounds.play(token)` /
`playScaled(token, ratio)`:

| Token        | File            | Purpose                                             |
|--------------|-----------------|-----------------------------------------------------|
| `ui-click`   | ui-click.wav    | UI feedback click / blip                            |
| `squelch`    | squelch.wav     | Radio squelch open burst                            |
| `call-tone`  | call-tone.wav   | Two-tone radio open/close tone                      |
| `chatter`    | chatter.wav     | Distant muffled radio "speech" ambience             |
| `engine`     | engine.wav      | Engine whine (looping/proximity layer)              |
| `flyby`      | flyby.wav       | Doppler aircraft fly-by                             |
| `gear`       | gear.wav        | Landing-gear mechanical thunk                       |
| `stall`      | stall.wav       | Intermittent stall-warning ding                     |
| `alarm`      | alarm.wav       | Repeating multi-beep alarm                          |
| `beacon`     | beacon.wav      | Marker-beacon-style morse tone                      |

## Customizing

You may replace **any** `.wav` here with your own file, as long as it uses the
**same filename** and remains a **16-bit PCM MONO** WAV (recommended 22050 Hz).
Drop the replacement in, and the addon will use it — no code changes needed.
