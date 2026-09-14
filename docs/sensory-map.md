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

## Readout (`FlyKit/Behaviour.swift`)

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

Drive: `noise = asleep + (awake − asleep) · (0.4 + 0.6 · min(food, energy)) + excited · excitement`; asleep
= 1.0. Fed and rested walks (3.5); starving grooms (2.0); just petted turns (6.5); asleep is
silent and a touch still fires it. Integrated piecewise across sleep/wake crossings so a day
replayed in one call on launch (`FlyStore`) equals the same day frame by frame.

## Motion (`FlyKit/FlyMotion.swift`)

Unit-square arena, reflecting walls. walk 0.12 arena/s · turn 2.5 rad/s while creeping at
15% of walk · startle jump 0.9 arena/s with wings beating and legs at 2× gait · groom moves
legs only · rest and sleep do not move. Every number is an `init` parameter of `FlyMotion`.
`Fly` composes vitals, readout and motion into one step; tested in `FlyMotionTests`,
`FlyTests` and `VitalsTests`.

## Tiers (`FlyKit/SimulationTier.swift`)

eco 700 · standard 6 000 · full 139 255 neurons. Today every tier is synthetic (fan-out 12,
seeded); the receipt says `SYNTHETIC WIRING` until that changes. Above 4 096 spikes a step
the raster shows a sample across the range, not a prefix.
