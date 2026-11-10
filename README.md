# HUMAN ERROR

A psychological horror investigation demo for Godot 4. You work for the Human
Verification Corporation. You read what people wrote, and decide whether a person wrote it.

- Engine: Godot 4.3 or newer (built and tested on 4.7.2), GDScript, Compatibility renderer
- Length: roughly 30-45 minutes, five in-game days, three endings
- Controls: mouse and keyboard

## Run it

1. Install Godot 4.3+ from https://godotengine.org
2. Open Godot, choose **Import**, and select `project.godot` in this folder.
   The first import takes a minute while photographs, fonts and sounds are processed.
3. Press **F5** (Run Project). The game starts at the main menu.

From a terminal:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

## How to play

- **Office.** Look around with `A`/`D`, the arrow keys, the edge buttons or by dragging with the
  right mouse button. Click an object (or face it and press `E`) to use it. `Esc` opens the pause menu.
  Sit at the computer to work; leave by the door once your shift has ended.
- **HVC TERMINAL.** Eight applications: Case Database, Message Archive, Employee Directory,
  Internal Email, System Monitor, Personal Notes, Terminal, Exit / Shutdown. Windows can be
  dragged by the title bar and resized from the bottom-right corner. `Esc` closes the top window.
- **Investigating.** Open the case in the *Verification Workbench*. Old messages and supporting
  files are on the left, the new questionnaire on the right. Click up to three lines, choose a
  category and press **Flag as evidence**. To show a contradiction, select the old line and the
  new line together. Every flag spends one of a limited number of *analysis requests*.
- **Deciding.** Submit one of four classifications. It is final and has consequences: for the
  person, for your clearance index, for the emails you receive and for the ending.
- Not every inconsistency means someone is an imitation. Each case contains misleading clues.

Progress saves automatically (after each flag, email, classification and day).
Settings: text size, master / music / effects volume, fullscreen, and switches to turn off
screen distortion, light flicker and visual noise. There are no strobing effects.

## Endings (spoilers)

The final case is your classification of UNKNOWN INSTANCE 07.

- **A - Compliance:** classify it CORRUPTED AI. Also reached by an inconclusive answer if you
  uncovered little and your clearance index is 55 or higher.
- **B - Contamination:** give it access to the restricted store in the day 5 conversation and do
  not condemn it; or verify it as human with high rapport without having uncovered the truth;
  or give an inconclusive answer with low clearance and little uncovered.
- **C - Human Error:** do not condemn it, do not give it access, and uncover at least two things
  about employee 0417 (your directory record, Sarah Bennett's manifest, the folder in the filing
  cabinet on day 5, asking it who you are, the 03:14 edit list, or 14+ confirmed findings).

The logic is in `GameManager.determine_ending()`.

## Project layout

```
scenes/        main_menu, transitions, office, desktop, investigation, dialogue, endings
scripts/       autoload/ (Game, Case, Character, Dialogue, Evidence, Audio managers)
               save/ (SaveManager)  managers/ (StoryDirector, ScreenFX, UI theme)
               interface/  investigation/  dialogue/  story/
ui/            windows/ (window frame + one script per application)  components/  icons/
data/          characters/  cases/  dialogue/  story_events/   <- all content, as JSON
assets/        photography/ (sources)  portraits/  environments/  fonts/  audio/  shaders/
tools/         generate_audio.py, process_photos.sh
tests/         automated checks
documentation/ ASSET_MANIFEST.md
```

### Adding content without touching code

- **A case:** add `data/cases/case_XXX.json` (copy an existing one). `CaseManager` validates it on
  load: at least five messages, five answers, three evidence entries, one misleading clue, and a
  consequence for each classification. Each evidence entry lists `match_sets`: the line ids a
  player must select together to confirm it.
- **A character:** add a JSON file in `data/characters/` and, to list them in the directory, an
  entry in `directory.json`.
- **Emails and scripted events:** `data/story_events/emails.json` and `events.json`. Each has a
  `trigger` (for example `result_closed:CASE_002`) and optional `requires` conditions.
- **Dialogue:** `data/dialogue/*.json`. Office objects look for `office_<object>_d<day>_<phase>`.
- **Per-day office changes:** `data/story_events/office.json`.

## Tests

```bash
# 360 logic and interface checks: data validation, three full playthroughs (one per ending),
# save/load round trip, consequences of wrong calls, every app, every setting
godot --headless --path . res://tests/test_runner.tscn

# drives the real scene changes: menu -> day card -> office -> desktop -> next day -> continue -> ending
godot --path . res://tests/flow_test.tscn

# renders every screen to PNG for visual review
godot --path . res://tests/screenshot_tour.tscn -- /some/output/folder
```

The tests use their own save files and never touch a real saved game.

## What was and was not verified

Verified on macOS with Godot 4.7.2: all scripts compile; all data validates; the three
automated playthroughs reach endings A, B and C; save and load restore state; the real scene
flow works end to end; every screen was rendered and reviewed.

Not verified: a complete playthrough by a human with mouse and keyboard, audio by ear (the
sounds are generated and load, but balance has not been listened to), Windows and Linux, and
exported builds. When exporting, add `*.json, *.md` to the export preset's non-resource filter
so the data files are included.

## Regenerating assets

```bash
python3 tools/generate_audio.py     # rewrites assets/audio/*.wav
bash tools/process_photos.sh        # rewrites portraits and environments (needs ImageMagick 7)
```

## Licenses

Photographs are CC0 / public domain from Wikimedia Commons, fonts are SIL OFL, audio is original.
Full details: `documentation/ASSET_MANIFEST.md`.
