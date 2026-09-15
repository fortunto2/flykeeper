# Sensory map — what is biology and what is ours

The connectome (once licensed and bundled) says which neurons connect to which. Nothing else
on screen comes from it. Every number below is an assumption of ours, kept in one place so it
can be argued with, and each was measured against the synthetic engine rather than guessed.

## The brain's drive (`connectome-core`, `mobile/fly-ios`)

The synthetic brain is alive through background `noise` in the LIF step, not a tonic
stimulus. A stimulus is sensory and is cleared when a touch ends; when the baseline was a
stimulus, the first touch silenced the brain for good (measured in the app, 2026-09-14).
Synaptic gain `weight_scale` 0.15, so noise gives a graded band instead of a switch.

Frame-mean activity (fraction of neurons firing per step, 700 neurons, seed 1), from
`cargo run -p connectome-core --example noise_sweep`:

| noise | activity | band |
|---|---|---|
| 1.0 | 0.000 | sleep |
| 1.5 | 0.002 | sleep |
| 2.0 | 0.010 | rest / groom edge |
| 2.5 | 0.025 | groom |
| 3.5 | 0.047 | walk (default awake) |
| 6.0 | 0.069 | turn |
| 8.0 | 0.079 | turn |

### The real brain (FlyWire FAFB v783, `examples/real_sweep.rs`)

Real weights are synapse counts, so the gain drops to `weight_scale` 0.02 (0.15 saturates
at 18%). Frame-mean activity over 138 584 cells, 3 732 460 edges:

| noise | activity | band |
|---|---|---|
| 0.5 | 0.000 | sleep (silent) |
| 1.0 | 0.030 | groom — the real graph self-sustains once kicked |
| 2.0 | 0.038 | groom (hungry) |
| 3.5 | 0.049 | walk (default awake) |
| 8.0 | 0.070 | turn (petted) |

Hence two arousal profiles (`Vitals.Arousal`): synthetic 1.0 / 3.5 / +3.0, FlyWire
0.5 / 3.5 / +4.5. The tier picks the profile; the fly does not know which wiring it has.
Parallel step (rayon): 1058–1362 steps/s on a 4-P-core Mac at the walk band; realtime is 1000.

## The readout on a real brain (`FlyKit/MotorCommand.swift`)

With the classification export loaded the app stops reading one number for the whole brain
and reads the **descending neurons** instead — the 1 290 cells that carry commands from a
fly's brain to its nerve cord, 638 left and 644 right.

| | |
|---|---|
| drive | mean descending rate ÷ 0.30, so a resting brain ambles at ~0.46 |
| steer | left/right asymmetry, resting bias removed, ÷ 0.015 |

Synthetic wiring has no sides to compare, so its readout says how hard (activity ÷ 0.07) and
never which way. Both produce the same `MotorCommand`, so which readout made it is settled
where it is built and travels no further.

Behaviour from the command: sleep ≤ 0.03 drive · startle at ≥ 0.5 with a touch · turn at
|steer| ≥ 0.45 · walk ≥ 0.35 · groom ≥ 0.12 · rest otherwise.

Measured on FAFB v783 (`connectome-core/examples/descending.rs`):

| stimulus | asymmetry shift | reaches the body? |
|---|---|---|
| nothing (resting bias) | +0.013 … +0.018 | it is a bias, not a command — subtracted |
| left bristles, 8.0 | −0.021 (noise 1.0) … −0.009 (noise 3.5) | yes |
| right bristles, 8.0 | +0.017 (noise 1.0) … +0.013 (noise 3.5) | yes |
| one eye, 6.0 to 60.0, whole or a quarter | 0.000 | **no** |
| olfactory, 20.0 | +0.003 | barely |

Two things follow. The resting halves are **not** equal: the right descending population sits
1.3–1.8% above the left with no input at all, so raw asymmetry is not steering and the app
learns the resting level and subtracts it. And a touch is audible only when the background is
quiet, which is why the real brain's awake arousal is 2.2 rather than the synthetic 3.5.

### The eye (`Services/Retina.swift`, `EyeCamera.swift`)

With the eye on, the camera drives the photoreceptors directly: 10 629 of them, each at the
place on its retina that cell looks from. The map comes from the cells' own positions
(`scripts/retina.py`): a retina is a curved sheet, and its two dominant directions are its two
retinal axes, so projecting onto them keeps neighbours as neighbours. That is order, not
optics — no claim is made about a fly's 270° field or its ommatidial angles.

**Photoreceptors adapt, and ours do too.** A real one responds to change in light rather than
to its level, which is exactly why a steady light measures 0.000 at the descending neurons.
Each cell keeps a running mean over 0.35 s and is driven by |luminance − mean| ÷ 0.25, up to
a current of 14. A static wall therefore produces almost nothing and a moving edge a lot. The
adaptation is real biology; that time constant and that gain are ours. It lives in
`FlyKit/Photoreceptors.swift` with the other assumptions, and is tested there.

The camera frame is reduced to **64 × 48** before sampling. A fly has about 700 ommatidia an
eye, so anything finer is thrown away by the retinal map anyway; each eye reads its own half
of the frame, so turning the phone sweeps one before the other.

**Light does not steer the fly, and the app does not pretend it does.** Driving 5 486
photoreceptors of one eye at ten times the strength of a touch, whole eye or a patch, moves
the descending neurons by 0.000. Partly that is four synapses of attenuation; mostly it is
that a *steady* light is not a steering cue for a fly either, whose visual system reads motion
and contrast. Two thirds of the cells we simulate are optic (90 459 of 137 518, 48.5% of all
synapses) and they fire — as scenery, not as eyes, until something gives them a moving image.

## Readout on synthetic wiring (`FlyKit/Behaviour.swift`)

`activity` = mean fraction of neurons firing per step over the last 16-step frame. A frame
mean, not a single step: one step of a 700-cell population flips the label at frame rate.

| activity | touch applied | behaviour |
|---|---|---|
| ≥ 0.07 | yes | startle |
| ≥ 0.07 | no | turn |
| ≥ 0.04 | | walk |
| ≥ 0.012 | | groom |
| ≤ 0.003 | | sleep |
| otherwise | | rest |

Descending-neuron populations would replace `activity` once the real graph is loaded.

## Touch (`FlyKit/Fly.swift`, `TouchStimulus.touch(neurons:)`)

8.0 into every tenth neuron for 250 simulation steps (250 ms at dt = 1 ms; a slow tier
gets the same number of steps, not a shorter touch). A fraction, not a fixed count, so the
touch is the same event on every tier. Measured through a frame mean in
`examples/touch_sweep.rs`:

| neurons | awake idle (max) | touched (mean) | asleep touched (mean) |
|---|---|---|---|
| 700 | 0.056 | 0.095 | 0.089 |
| 6 000 | 0.050 | 0.093 | 0.090 |
| 139 255 | 0.048 | 0.093 | 0.090 |

The engine expires the stimulus and reports `touched`, so the readout's "touch applied" is
the simulation's word, not a timer. On synthetic wiring the indices mean nothing; on the
real export they must map to mechanosensory afferents.

## Needs (`FlyKit/Vitals.swift`) — the tamagotchi contract

| quantity | full → empty | refill |
|---|---|---|
| food | 10 min | Feed |
| energy | 15 min awake | 4 min asleep |
| affection (mood) | 2 min | Pet (a touch) |
| excitement (brain drive) | 20 s | Pet (a touch) |

Sleep: lights off, or energy ≤ 0.1 (the fly falls asleep on its own; wakes at 0.9). A
touch turns the lights on and wakes it. Mood: asleep · happy (affection > 0.5) · hungry
(food < 0.3) · tired (energy < 0.3) · content.

Food is a morsel on the floor (`Fly.dropFood`), not a bar that jumps: the fly steers
towards it while its brain says walk, eats for 8 s within 0.05 of it (`EAT` on screen), and
a full fly still nibbles the whole morsel. Walking wanders (0.9 rad/s drift keyed on the gait)
instead of running wall to wall.

Drive: `noise = asleep + (awake − asleep) · vigour + excited · excitement`, where
`vigour = 0.35 + 0.65·energy + 0.4·(1 − food)·energy`, which is exactly 1 for a fed and
rested fly. **Hunger raises the drive and tiredness
lowers it**: a hungry animal forages, and the first version of this had it backwards, leaving
a starving colony sitting beside food it was too "sluggish" to reach. The hunger term is
scaled by energy, because a fly too tired to move is too tired to search. Asleep
= 1.0. Fed and rested walks (3.5); starving grooms (2.0); just petted turns (6.5); asleep is
silent and a touch still fires it. Integrated piecewise across sleep/wake crossings so a day
replayed in one call on launch (`FlyStore`) equals the same day frame by frame.

## Motion (`FlyKit/FlyMotion.swift`)

Turning under a descending command comes out as **saccades**: a straight run, then a 0.12 s
flick at 6.5 rad/s, triggered when |steer| passes 0.3. A walking fly's path is runs and flicks,
not a curve, and a heading that eases round reads as a toy however right the speed is.


Unit-square arena, reflecting walls. walk 0.12 arena/s · turn 2.5 rad/s while creeping at
15% of walk · startle jump 0.9 arena/s with wings beating and legs at 2× gait · groom moves
legs only · rest and sleep do not move. Every number is an `init` parameter of `FlyMotion`.
`Fly` composes vitals, readout and motion into one step; tested in `FlyMotionTests`,
`FlyTests` and `VitalsTests`.

## A colony (`Services/FlyBrainEngine.swift`)

Every fly runs its own brain over **one shared connectome**: 31 MB of wiring carried once,
about 2.8 MB of state per fly on the full export. So the ceiling is the processor, not memory.

| tier | flies |
|---|---|
| eco (synthetic 700) | 12 |
| Brain ≥20 | 4 |
| Full brain | 2 |

Flies whose centres come within **0.11 arena units** touch each other's mechanosensory
bristles, on the side the other one is on. The model is 0.15 units long, so they overlap
visibly before it fires; what matters is that this is a body width and *not* the 0.05 eating
reach, which is what it was at first — two flies could stand touching and feel nothing.
Flies more than 0.1 apart in height miss each other: one in the air is not bumping into one
on the floor. A new fly is put at the emptiest of 8 random spots in the middle 76% of the
arena, so a colony spreads instead of piling up, and starts between half and fully fed.
The rules are `FlyKit/Colony.swift`, tested in `ColonyTests`. That is the one sense measured to reach the
descending neurons, so a colony jostles through the real wiring rather than through a rule of
ours, and the receipt counts the contacts. Each fly gets its own seed, so the same wiring
lives a different life in each of them.

## Tiers (`FlyKit/SimulationTier.swift`)

eco 700 · standard 6 000 · full 139 255 neurons. Today every tier is synthetic (fan-out 12,
seeded); the receipt says `SYNTHETIC WIRING` until that changes. Above 4 096 spikes a step
the raster shows a sample across the range, not a prefix.
