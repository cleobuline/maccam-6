# MacCam-6

*A poetic cyberpunk citadel brings a 1987 machine back to life.*

MacCam-6 is a faithful reconstruction, in Cocoa/Objective-C + C, of **CAM-6** — the cellular automata machine designed by Tommaso Toffoli and Norman Margolus, documented in their book *Cellular Automata Machines* (MIT Press, 1987). This is not a decorative rehash: every mechanism (neighborhoods, reversibility, Margolus partitioning, cross-probes between half-machines) was transcribed and then **verified by computation**, often down to the exact pixel or bit, before being considered settled.

The project is the resurrection of an original MacCam written in THINK C on a 68000 Mac in the 1990s by [cleobuline](https://github.com/cleobuline), whose sources were lost. This version comes back to life thirty years later, with a level of rigor a 1990s machine never made easy to verify.

---

## Table of Contents

- [Why This Project](#why-this-project)
- [Feature Overview](#feature-overview)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Building](#building)
- [Getting Started](#getting-started)
- [The CAM-Forth Language](#the-cam-forth-language)
- [Neighborhoods](#neighborhoods)
- [Rule Bestiary](#rule-bestiary)
- [The FHP Gas (Chapter 16)](#the-fhp-gas-chapter-16)
- [Reversibility (Chapter 14)](#reversibility-chapter-14)
- [Video Export](#video-export)
- [Known Limitations](#known-limitations)
- [Roadmap](#roadmap)
- [Acknowledgments](#acknowledgments)

---

## Why This Project

In the 1980s, Toffoli and Margolus built a dedicated machine: a processor where every bit of memory knows only its immediate neighbors, updated in parallel, step by step, according to a programmable rule. It's the direct ancestor of everything we now call "cellular automata" — from Conway's Life to lattice-gas automata that simulate real fluids.

MacCam-6 recreates that machine on a modern Mac, with two goals that turned out to be inseparable throughout development: staying **faithful to the book** (to the point of literally transcribing 1987 Forth listings), and staying **honest about what actually works** — every claim in this README was tested before being written down.

## Feature Overview

- **A complete CAM-Forth interpreter**, faithful to the vocabulary of the book's Table 7.2
- **Every major neighborhood**: Moore, VonNeumann, Margolus (with PHASE, PHASE', HORZ/VERT), and a **pseudo-hexagonal** neighborhood (Chapter 16) not found in the book itself
- **CAM-A and CAM-B**, two coupled half-machines, both capable of Margolus partitioning (not just CAM-A)
- **Cross-probes** (`&CENTER`, `&CENTER'`) letting one half-machine read the other's state — including in Margolus mode
- **Automatic reversibility** (Chapter 14): the inverse table is computed after every compile, with a ⏪ button to run time backward
- **Programmable run-cycles** (§11.5) for custom phase sequences
- **A genuine FHP gas** (Chapter 16) with 6 directional channels, rest particles (FHP-II) for tunable viscosity, open edges, continuous wind
- **Twenty-plus rules** in the bestiary, from a simple Game of Life to an authentic lattice-gas noise generator running on CAM-B
- **H.264 video export**, with adjustable scale, freeze-on-pause, live-tracked time reversal, and automatic resync with any grid change during export
- **A full floating palette**: drawing tools (including an isotropic Spray for unbiased perturbations), plane selection, FHP settings, a per-plane clear menu

## Architecture

The engine's core is **pure C**, with no Apple dependency — compiled and tested independently of Cocoa throughout development.

```
cam_forth.h / cam_forth.c   → the CAM-Forth interpreter: VM, compiler, table builders
cam_core.h  / cam_core.c    → the simulation engine: Moore/VonNeumann LUT, Margolus (CAM-A + CAM-B),
                               hexagonal, reversibility, run-cycles
fhp.h       / fhp.c         → an independent subsystem: the real 6-direction FHP gas (Chapter 16)
```

The interface (Cocoa/Objective-C) stays a thin layer on top of this core:

```
CAMView.h/.m                    → NSView bitmap rendering, brush, image paste (N/USER)
CAMPalettePanel.h/.m            → floating palette (tools, planes, FHP settings, Clear menu)
Document.h/.m                   → NSDocument, simulation loop, video export
CAMEditorWindowController.h/.m  → secondary rule editor
```

This strict separation between the C core and the Cocoa interface isn't accidental: it allowed every mechanism (compilation, execution, reversibility) to be rigorously tested in an independent Linux environment, without ever needing to build the full app just to verify the underlying logic.

## Repository Structure

```
cam-8/
├── cam-8.xcodeproj/
└── cam-8/
    ├── cam_core.h / cam_core.c
    ├── cam_forth.h / cam_forth.c
    ├── fhp.h / fhp.c
    ├── CAMView.h / CAMView.m
    ├── CAMPalettePanel.h / CAMPalettePanel.m
    ├── Document.h / Document.m
    ├── CAMEditorWindowController.h / CAMEditorWindowController.m
    ├── AppDelegate.h / AppDelegate.m
    └── regles/
        ├── critters.rule
        ├── hpp-gas.rule
        ├── tm-gas.rule
        ├── bbm.rule
        ├── dendrite.rule
        ├── dendrite-noise.rule
        ├── gaz-murs.rule
        ├── tube-worms.rule
        ├── ising.rule
        ├── hex-diffuse.rule
        ├── 2d-brownian.rule
        ├── 2d-brownian-trace.rule
        └── ... (see the bestiary below)
```

## Building

Open `cam-8.xcodeproj` in Xcode (tested on Xcode 12.4, macOS Catalina, but no particular dependency on recent versions). Cmd+R to run.

To distribute the app to others, a DMG can be generated simply:

```bash
hdiutil create -volname "CAM-8" -srcfolder camdmg -ov -format UDZO CAM-8.dmg
```

Since the app isn't signed with a paid Apple Developer account, macOS will show an "unidentified developer" warning on first launch elsewhere — right-click → Open, or System Settings → Privacy & Security → Open Anyway.

## Getting Started

1. **Write or load a rule** in the text editor (see the bestiary below for ready-to-use examples)
2. **⚙️ Compile** to build the table
3. **Draw** an initial state (Pencil, Circle, Square, Eraser, Spray) or **Randomize** a seed
4. **▶ Play** to run the simulation; **⏸ Stop** to freeze; **⏪ Reverse** to run time backward if the rule is reversible
5. **🎬** to export as video

The floating palette groups every setting. Controls specific to the FHP gas (Wind, Open Edges, Viscosity, Isotropic Spray) stay hidden until the **Hexagonal Grid** checkbox is checked, so the interface isn't cluttered outside that context.

## The CAM-Forth Language

A typical rule:

```forth
N/MOORE
: LIFE 8SUM { 0 0 1 1 0 0 0 0 0 } CENTER AND
       8SUM { 0 0 0 1 0 0 0 0 0 } OR ;
MAKE-TABLE LIFE
```

### Neighborhood vocabulary
`CENTER CENTER' NORTH SOUTH EAST WEST N.EAST N.WEST S.EAST S.WEST` (Moore) · `NORTH' SOUTH' EAST' WEST'` (VonNeumann) · `CW CCW OPP CW' CCW' OPP'` (Margolus) · `PHASE PHASE' HORZ VERT PHASES` (pseudo-neighbors) · `RAND` (noise, Chapter 8) · `&CENTER &CENTER' &CENTERS &PHASE &PHASE' &PHASES &HORZ &VERT &HV` (cross-probes, CAM-A ↔ CAM-B)

### Operators
`+ - AND OR XOR NOT = <> > < 2* 2/ DUP DROP SWAP OVER IF ELSE THEN { }` (selection table) · `>PLN0 >PLN1 >PLN2 >PLN3 >PLNA >PLNB`

### Declarations
`N/MOORE N/VONN N/MARG N/MARG-PH N/MARG-HV N/HEX` · `CAM-A CAM-B` · `&/CENTERS &/PHASES &/HV` · `CYCLE ... END-CYCLE` · `MAKE-TABLE` (and the historical alias `MAKE-TABLE-MARGOLUS`)

A user-defined word (`: NAME ... ;`) can **shadow a built-in word** — explicitly verified: the user dictionary is checked before built-in words, allowing, for instance, `RAND` to be redefined so its noise comes from a different source entirely (see `dendrite-noise.rule`).

## Neighborhoods

| Declaration | Description | Table |
|---|---|---|
| `N/MOORE` | 8 neighbors + center, classic | 8192 entries |
| `N/VONN` | 4 orthogonal neighbors | 8192 entries |
| `N/MARG` | 2×2 Margolus block, alternating partition | 32768 entries* |
| `N/MARG-PH` | + PHASE (run-cycle) | same |
| `N/MARG-HV` | + HORZ/VERT (spatial parities) | same |
| `N/HEX` | Pseudo-hexagonal, brickwork offset (Chapter 16, not in the book) | 256 entries |

*Expanded on 7/6 from 2048 to 32768 entries to make room for the `&CENTER'` cross-probe nibble, needed for a faithful transcription of the Chapter 16 noise generator (see below). Each half-machine (CAM-A **and** CAM-B) can now run its own, fully independent Margolus table — an extension of the software port relative to 1980s hardware, where both modules were already symmetric by design.

## Rule Bestiary

| Rule | Chapter | Description |
|---|---|---|
| `critters.rule` | §12.8 | Invert + rotate 180° if 2 particles — classic Margolus |
| `hpp-gas.rule` | §12.3–12.4 | Diagonal gas with collisions, **reversible**, conserves mass and momentum |
| `tm-gas.rule` | §12.7 | H/V gas with collisions, phase-sensitive |
| `bbm.rule` | §18.2 | Billiard Ball Model, verbatim from the book |
| `annealing.rule` | §5.4 | Vichniac's twisted majority |
| `decay.rule` | §8 | Probabilistic extinction (`RAND`) |
| `diffusion.rule` | §15 | Block-wise random walk |
| `dendrite.rule` | §15.7 | DLA — diffusion-limited aggregation, frost on a painted seed |
| `dendrite-noise.rule` | §15.7 + §16 | **Faithful transcription** of pp. 167–168: the same DLA, but driven by a genuine lattice-gas noise generator (`STIR-SAMPLE-DELAY`) running on CAM-B, read via `&CENTER'` |
| `tube-worms.rule` | §9.3 | Tube worms — the flagship CAM-A/CAM-B rule, 2-bit timer |
| `brians-brain.rule` | — | 3 states, comet trail, CAM-A/CAM-B |
| `banks.rule` | §5.5 | Universal computer |
| `hglass.rule` | §5.6 | Puzzle rule, 32-entry VONN-INDEX table |
| `gaz-murs.rule` | §15.2 + §12.4 | HPP-GAS with indestructible walls painted on plane 1; **reversible**, even through the walls |
| `maree.rule` | §11.5 | 8-step palindromic cycle, custom run-cycle |
| `ising.rule` | §17 | Microcanonical Q2R, energy conserved exactly |
| `hex-diffuse.rule` | §16 | Test bench for the hexagonal neighborhood — isotropic diffusion, proven hexagonal growth |
| `2d-brownian.rule` | p. 156 | 2D Brownian motion via random rotation of Margolus blocks |
| `2d-brownian-trace.rule` | p. 156 | Same, with a permanent trace accumulated on plane 1 (`CENTER CENTER' OR`) |
| `parity-flip.rule` | ch. 8/11 | A TIME-TUNNEL variant, parity including CENTER itself |

`TIME-TUNNEL` (discrete wave equation, second order) is the rule loaded by default on startup.

## The FHP Gas (Chapter 16)

The genuine Frisch-Hasslacher-Pomeau gas lives in its own subsystem (`fhp.h/.c`), separate from the CAM-Forth engine: a single boolean cell can only represent density, never a particle *in motion* with a direction — hence the need for 6 independent directional channels per cell.

- **FHP-I**: 2-body collisions (head-on pair → random transverse axis) and 3-body collisions (deterministic rotation of symmetric triples, required to break a spurious conserved quantity that was freezing the gas into stationary bands)
- **FHP-II**: a 7th "rest" channel (0, 1, or 2 particles) — a head-on pair with zero net momentum can be absorbed into it, and conversely emit one back out. The conversion probability (**Viscosity**) is the missing knob FHP-I needed to tune dissipation
- **Open edges**: gas reaching the right edge exits the domain instead of wrapping back through the torus — essential for a wind-tunnel scene without spurious recirculation
- **Continuous West wind**: permanent reinjection along the left edge
- **Isotropic Spray**: a local perturbation spread evenly across all 6 directions, for observing a wave that genuinely damps out instead of being pushed by a wind

**Known limitation**: Margolus's square grid structurally resists damping (see below) — it's the true FHP gas, on its hexagonal lattice, that properly damps waves, not classic Margolus rules like `HPP-GAS`.

## Reversibility (Chapter 14)

After every compile, the engine automatically computes the inverse table and checks bijectivity (`cam_can_reverse()`). The exact conditions:

- No dispatch to plane 1 (`>PLN1`) — walls must remain eternal
- Independence from `RAND` and from cross-probes (`&CENTER'`) — a rule fed by external noise isn't mechanically invertible without also knowing that source's history
- **Bijection per plane-1 slice**: unlike an earlier, overly strict version, a rule may legitimately behave differently depending on whether a wall is present (e.g. `gaz-murs.rule`), as long as each individual behavior is itself a bijection

The bestiary's most spectacular demonstration: an `hpp-gas.rule` gas, fully thermalized and unrecognizable after 100 steps, returns **exactly**, bit for bit, to its initial state after 100 steps in reverse — cellular proof that apparent disorder never destroys information.

## Video Export

- **Adjustable scale** (`auto`, or an explicit value like `0.5`, `2`, `3`) — nearest-neighbor sampling, handling both upscaling and downscaling
- **Freeze on Stop**: the export keeps writing identical frames while the simulation is paused — useful for transition effects (freezing on a moment of recomposition)
- **Live-tracked ⏪**: works for both reversible Margolus rules and second-order rules (plane-swap, e.g. TIME-TUNNEL)
- **Automatic resync**: Compile, Randomize, Clear, and every brush stroke are reflected in an ongoing export, allowing several distinct simulations to be chained into a single continuous video
- **FHP mode supported**: a second export path clones the gas rather than the classic CAM grid

## Known Limitations

- **CAM-B cannot yet probe CAM-A back** — cross-probes only work one way (CAM-A reads CAM-B), wired for the one identified need so far (`dendrite-noise.rule`)
- **Wave damping on the square grid (Margolus/HPP)** structurally resists: two attempts at dissipative rules (`HPP-AMORTI`, `HPP-LOSSY`) did not produce clean, reproducible damping — FHP's hexagonal geometry remains the approach that actually works
- **A clean von Kármán vortex street** was never obtained with certainty on FHP, despite tunable viscosity — a weak, noisy signal was measured, not a clear, visible shedding pattern
- **The palette has no full dynamic collapse**: hiding the FHP controls leaves an empty gap in the middle of the window rather than perfectly tightening every section

## Roadmap

- Real-time population counters (Chapter 17)
- Probabilistic voting and genetic drift (Chapter 17, never built)
- Lichen-like growths, geometric patterns (Chapter 5)
- CAM-B → CAM-A cross-probes (the missing symmetry)
- FHP: a search for a regime that produces a genuine vortex street
- `camgen`: a headless generator, for Linux/VPS or a possible Windows port (the C core is already Cocoa-independent)

## Acknowledgments

To Tommaso Toffoli and Norman Margolus, whose 1987 book remains, nearly forty years later, precise enough that its listings can be transcribed word for word and made to run. And to the original MacCam of the 1990s, of which this version is the resurrection.

---

*Developed with Claude (Anthropic) as a technical implementation partner.*
