# Lychee the Hungry Bunny

*A Very Serious Rabbit Simulator* — a cozy-chaotic 3D pet rabbit game built with **Godot 4**.

You are Lychee, a hungry house rabbit. Survive one full day: eat the hay, drink the water,
land your poops in the litter box, manage your bladder, outmaneuver Potato and Gravy,
shake the gate when the hay runs out, and look innocent when the human checks the pen.

## How to launch the game on macOS

There is no `.exe` in this repo — it's a **Godot project** (all code, zero binary assets),
so you run it with the Godot engine itself.

Run this command from the repo folder:

```sh
godot --path .
```

This requires **Godot 4.3 or newer**. The Homebrew install below adds the `godot`
command automatically.

**Install Godot 4**

With Homebrew:

```sh
brew install --cask godot
```

Or download Godot for macOS from https://godotengine.org/download and move `Godot.app`
to `/Applications`.

If macOS blocks the downloaded app on first launch, open **System Settings → Privacy &
Security** and allow Godot, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Godot.app
```

**Alternative run command**

If `godot` is not on your `PATH`, launch the app directly from this repo folder:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

Alternatively, open the Godot Project Manager, click **Import**, choose this folder's
`project.godot`, then press **F5** or click **Run Project** in the editor.

**Making a standalone macOS app:** in the Godot editor go to **Project → Export...**,
install the export templates when prompted, add a **macOS** preset, and click
**Export Project**. That produces a macOS app bundle you can run outside the editor.

### Windows notes

Install Godot 4.3 or newer:

```powershell
winget install --id GodotEngine.GodotEngine
```

winget installs it to a path like:

```
%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64.exe
```

(Or download it from https://godotengine.org/download — it's a single portable exe.)

Run the game from the repo folder:

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64.exe" --path .
```

Or, if `godot` is on your PATH: `godot --path .`

**Making a standalone .exe:** in the Godot editor go to **Project → Export...**, install the
export templates when prompted, add a **Windows Desktop** preset, and click *Export Project*.
That produces a shippable `LycheeTheHungryBunny.exe`.

## Controls

| Input | Action |
|---|---|
| WASD / Arrows | Hop |
| Shift | Zoomies (sprint hops) |
| Space | Binky |
| E | Eat hay / drink / squat for **POOP TIME** / shake the gate |
| F | Dramatic ragdoll flop (lowers suspicion; try it on the bed) |
| Esc | Pause menu (settings, quit to menu) |
| R | Back to the title screen after the day ends |

## What's in the game

- **Title screen** with How to Play and settings (resolution presets 1080p/1440p/4K,
  crisp UI scaling 1x–3x with apply/confirm/revert, saved to `user://settings.cfg`)
- One 5-minute day: Morning → Midday → Afternoon → Evening → Night with shifting light
- **Meters:** hunger, water, poop, bladder, suspicion
- **Poop QTE:** when the poop meter fills, time slows — reach the litter box, squat (E),
  and hit 3 timed key prompts. 3/3 in the box = LEGENDARY POOP (+150)
- **Pee:** drinking fills the bladder; hold E to pee — litter box or puddle of shame
- **The human:** checks the pen on a timer; visible messes raise suspicion; flop for the
  Cute Defense; max suspicion = busted (−150, evidence cleaned)
- **Hay economy:** the rack visibly empties as all three bunnies eat. Shake the front gate
  (E ×3) to call for a refill — but do it while the rack is over half full and the human
  gets annoyed (+15 suspicion)
- **GI stasis:** run hunger to zero and movement is halved until you eat
- **Rivals:** Potato (fast, sneaky) and Gravy (slow, ravenous, black). Nudge them off the
  hay for +10 — they'll shove you right back
- **Ragdoll flops**, a bed with a ramp (+15 comfort flop), a collidable cardboard tunnel
  (+15 per run-through), solid cardboard boxes, and a pushable ball
- **All audio synthesized in code** — SFX (hops, munches, plops, trickles, rattles...) and
  an adaptive 16-step music sequencer that shifts mood with the game state (calm, sneaky,
  urgent, human-is-looking, zoomies, lullaby)
- End-of-day stats and a silly title: Lord of the Litter Box, The Poop Sniper,
  Puddle Bandit, Carpet Criminal, Supreme Loaf...

## Roadmap (from the design brief)

- Stress and energy meters, Sniff Vision
- Treat time events, forbidden objects, mischief scoring
- More bunnies and a bond/rivalry system
- More rooms: living room, kitchen, hallway, bedroom
