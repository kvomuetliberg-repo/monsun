# monsun

A 16-tap rhythm delay and a 64-tooth comb resonator for norns, played from grid 128 and arc 4. It is modelled on the published feature set of the Intellijel / Cylonix Rainmaker. It is an independent script, not an official emulation.

## Install

1. Copy the `monsun` folder into `dust/code/` on norns.
   - SMB: `smb://norns.local/dust` (user `we`, password `sleep`).
   - Or: `scp -r monsun we@norns.local:~/dust/code/`.
2. Restart norns, or run `;restart` in maiden, so the new engine compiles.
3. Connect grid and arc, then open **SELECT > monsun**.

monsun starts on preset 1, *drizzle*, and processes the line inputs. To hear it without an input:
- choose PARAMETERS > MIX / SOURCE > source > **demo** (a 32 s drum, bass, pad and pluck loop); or
- press **K3** to ping; or
- go to the COMB page and play the keyboard.

## Grid

Row 8 is the same on every page:

| keys | function |
|---|---|
| 1–4 | pages: TAPS, RHYTHM, COMB, PRESETS |
| 5–10 | page keys (see below) |
| 11 | RAMP: the next of 8 shapes across all 16 taps (rising, falling, V, peak, odd/even, saw ×2, saw ×4, random walk) |
| 12 | RANDOM: the current tap parameter on TAPS, the chosen destination elsewhere |
| 13 | PING: noise burst into the input (on COMB: pluck). ALT + PING clears both buffers |
| 14 | FREEZE: loop the buffer at the feedback time |
| 15 | REVERSE: play the buffer backwards |
| 16 | ALT (hold) |

**TAPS.** The 16 columns are the 16 taps.
- Rows 1–6 are faders for the parameter chosen with keys 5–10: LEVEL, PAN, CUTOFF, Q, PITCH, TYPE. Press across columns to draw a shape.
  - Pitch rows set +12, +7, +5, 0, −5, −12 semitones.
  - Type rows 3–6 set high, band, low pass, off.
- Row 7 mutes taps. Each key flashes when its tap fires.
- ALT + row 7 selects the tap the arc edits.

**RHYTHM.**

| row | keys 1–16 |
|---|---|
| 1 | groove: straight, swing, hard swing, reverse swing, alt swing, accelerando, ritardando, waltz, half swing, roller coaster, quintuple, random A/B/C, early refl, late refl |
| 2 | groove amount, from straight on the left |
| 3 | 1–8: grid (1, 2, 3, 4, 6, 8, 12, 16 taps per beat) · 9–16: beat length (1/4, 1/3, 1/2, 2/3, 1, 3/2, 2, 4 beats) |
| 4 | 1–4: stack (1, 2, 4, 8 taps share one time) · 9–16: delay-time LFO (off, sine, triangle, vibrato 1, vibrato 2, down chirp, up chirp, random) |
| 5 | feedback tap. Press the lit key again for ALL taps; ALT + key for COMB SIZE |
| 6 | 1–12: feedback pitch −12, −7, −5, −3, 0, +3, +4, +5, +7, +12, +19, +24 |
| 7 | slip −8 … +7: push the feedback earlier or later |
| 8 | 5 tap tempo · 6 clock sync / free time · 7 pans left/right · 8 delay on · 9 feedback 0 · 10 global pitch 0 |

**COMB.**

| row | keys |
|---|---|
| 1 | tooth pattern: uniform, flat middle, early, fibonacci, flat comb, late, rev fibonacci, ess, and random versions of each |
| 2 | density: 4 … 64 teeth |
| 3 | 1–4 slope (flat, rising, falling, rise/fall) · 5–8 feedback type (guitar, sitar, clarinet, raw) · 9–12 routing (delay > comb, comb > delay, parallel, split L/R) · 13–14 size from pitch/keys, or follow the delay · 15 glide · 16 pluck |
| 4–7 | keyboard in fourths, with C marked. Tunes the comb and plucks it; ALT + key tunes without plucking. Playing always brings the comb into the mix |
| 8 | 5 octave − · 6 octave + · 7 pluck · 8 exciter (noise / pulse) · 9 comb on · 10 comb feedback 0 |

Density keeps the last teeth. Tooth 64 is the comb size and sets the note, so low densities (1–16) sound most like a string. All 64 evenly spaced teeth cancel the note into a high shimmer.

**PRESETS.**
- Rows 1–6 are 96 slots; 1–12 are factory presets. Press a slot to recall it, morphing over the morph time.
- To save, hold SAVE (key 10) or ALT and press a slot.
- For the crossfade, hold SET A (key 6) or SET B (key 7) and press a slot. Arc ring 1 then crossfades between them.
- Row 7 chooses what RANDOM changes: groove times, mutes, levels, pans, cutoffs, Qs, pitches, comb, delay globals, all taps, all delay, taps + delay, comb + delay, everything, any one.
- Key 5 cycles the morph time (off, ½ beat, 1 beat, 1 bar, 4 bars). Key 8 clears the buffers.

## Arc

The arc follows the grid page. Hold ALT for fine steps.

| page | ring 1 | ring 2 | ring 3 | ring 4 |
|---|---|---|---|---|
| TAPS | select tap | its value | global pitch (±24) | dry/wet |
| RHYTHM | beat length or free time | groove amount | feedback | tone (LP ‹ flat › HP) |
| COMB | pitch | comb feedback | density | delay ‹› comb |
| PRESETS | A ↔ B | LFO depth | LFO rate | grain size |

## norns

- **E1** changes the screen page:
  - **TAPS:** the taps on a time line. Height is level, the dot is pan, a mark shows the feedback tap.
  - **RHYTHM:** the delay settings.
  - **COMB:** the 64 teeth and the note.
  - **MIX:** meters and the source.
- **E2** selects; **E3** changes. On TAPS, E2 picks the tap and E3 changes the current tap parameter.
- **K2** freeze. **K3** ping; on the COMB page it plucks.

## MIDI

Notes play the comb: the note tunes it and velocity sets the pluck. Set the device and channel under PARAMETERS > MIDI.

To sync to MIDI clock, set the norns CLOCK source to MIDI. Every parameter can be mapped to a MIDI CC with norns' MAP.

## Presets

1. drizzle
2. swing dub
3. octave rain
4. chord stack
5. accelerando
6. filter sweep
7. random dust
8. waltz echo
9. comb strings
10. sitar drone
11. clarinet reed
12. cloud comb

Saved presets live in `dust/data/monsun/presets.data`.

## How it differs from the module

- The 16 taps read a mono mix of the input and are panned one by one. That halves the CPU and still sounds wide; the dry signal stays stereo.
- There is no ping-pong. With one mono buffer there's no left/right feedback to swap. RHYTHM row 8, key 7 sets the taps hard left and right instead.
- Pitch shifting uses two crossfading grains per tap, with a selectable grain size (5–671 ms). Sustained tones have the typical granular flutter.
- No CV. Use the arc, MIDI and norns MAP instead.

## Tested before shipping

**The SuperCollider engine**, rendered offline and booted in a norns-like context:
- Tap times are exact to 0.1 ms.
- Comb notes are in tune from 110 to 1500 Hz for all four feedback types.
- Feedback at 100% stays bounded, even pitched ±1 octave. Freeze holds and reverse works.
- All four routings, the bypasses, ping, pluck and file loading work, and all 40 engine commands respond.
- Each synth stays within norns' default of 64 wire buffers.

**The script** ran with the real norns libraries against a browser version of the same engine:
- every grid page, the arc, encoders, keys, MIDI, presets, morphing and the A/B crossfade;
- a 3000-action random stress test with no errors and no runaway levels.

**CPU:** about 4–5% of one 2.8 GHz server core. That is about twice the raum reverb, so expect roughly 35–50% on a norns with a Pi CM3, and less on a Pi 4 based shield. Pitched taps and density 64 cost the most.

**Not yet confirmed:** behaviour on real norns hardware.

## Files and license

- `extras/`: browser simulator, concept page and cheat sheet (PDF). Not needed on norns.
- `LICENSE`: GPL-3.0.
