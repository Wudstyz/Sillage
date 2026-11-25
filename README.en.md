<div align="center">

<img src="docs/icon-256.png" width="128" alt="Sillage icon">

# Sillage

**Your calendar, plus a record of what you actually did with your day.**

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-lightgrey) ![MIT License](https://img.shields.io/badge/license-MIT-green)

[Version française](README.md)

<img src="docs/screenshots/01-journee.png" width="760" alt="Sillage: a day timeline, planned on the left, actual on the right">

<br>

<img src="docs/screenshots/02-semaine.png" width="374" alt="Week view"> <img src="docs/screenshots/03-mois.png" width="374" alt="Month view">

</div>

Sillage is a free, open-source Mac app that combines a **calendar** with a **log of your day**.

- **Plan** your appointments: the doctor, a meeting… whatever happens, from this time to that time, you're there.
- **Start a task** the moment you begin it (“I start the app at 4:34 PM”). You don't need to know when it will end: it stays *running* and keeps growing on the timeline until you stop it.
- **Do several things at once**: simultaneous tasks sit side by side.
- **In the evening, look back at your day**: from this time to that time, shower, lunch, the website, the appointment, bedtime. Planned (dashed) and actual (solid) face each other, with a **per-category summary**.

Everything stays **on your Mac**: no account, no network, no data sent anywhere.

## Usage

| I want to… | I do… |
|---|---|
| Start a task now | Left panel: title, category, **Démarrer maintenant** (Start now) |
| Repeat an appointment (physio every Wednesday, rent every month…) | In the sheet: **Répéter** (Repeat: day, week with chosen weekdays, month, year), “every N”, “until”. Each occurrence stays individually editable, movable and honorable; series are automatically extended one year ahead |
| Delete a series | Open an occurrence → **Supprimer** (Delete) → “this occurrence only” or “this and following” (what was already lived is kept) |
| Be warned before an appointment | In the sheet: **Rappel** (Reminder: at start, 5 min, 15 min, 1 h, 1 day before): macOS notification, even with the window closed |
| Launch a common activity (shower, meal, sleep, commute, break, sport) | One click on a **shortcut** |
| Switch from one task to the next | “Terminer la tâche en cours” checkbox (on by default) |
| Stop a running task | ■ button under “En cours” (Running) |
| Tell I've arrived at an appointment | Right-click the appointment → **J'y suis** (“I'm here”): the real task starts and the timeline shows how early or late you were |
| Add an appointment | **+ → Rendez-vous prévu** (⌘N) |
| Log something already done (shower, lunch…) | **+ → Activité passée** (⇧⌘N) |
| Create a range directly | **Drag** in an empty part of the timeline (Prévu or Réel column), snapped to 15 minutes |
| Move an activity | **Drag** the block |
| Change its duration | **Stretch** the bottom edge of the block |
| Fix a forgotten time | Click the block on the timeline |
| Act without opening the window | **Menu bar**: the running task and its timer are shown there; the panel shows the next appointment (with **J'y suis**), lets you stop a task, start one or use a shortcut. Closing the window keeps Sillage running; **Quitter** (Quit) stops it |
| Change view | **Day / Week / Month** (selector top right, ⌘1 ⌘2 ⌘3). **Week** shows seven days side by side, planned dashed and actual solid; **month** shows one cell per day with its appointments and a **colour bar** of the time actually spent. Click a day to open it. The sidebar summary follows the displayed period |
| Navigate | ‹ › or ⌘← ⌘→ (one day, week or month depending on the view); today: ⌘T |

Data lives in `~/Library/Application Support/Sillage/data.json` (readable JSON, atomic writes). One copy per day is kept in `Sauvegardes/` (14 days). If the file ever becomes unreadable it is set aside (`data.corrompu-…`) and never overwritten. A task left “running” for more than 12 h is flagged as forgotten. The interface is currently in French.

## Install

1. Download `Sillage.dmg` from [Releases](../../releases) and drag **Sillage** into *Applications*.
2. The app isn't signed by Apple: on first launch, right-click the app → **Open** → **Open**.

## Build it yourself

Requires Xcode or its command-line tools (macOS 13+, Apple Silicon).

```bash
./build_app.sh   # builds, generates the icon, assembles dist/Sillage.app
./make_dmg.sh    # creates dist/Sillage.dmg
swift test       # core tests
```

The core (`SillageCore`) is separate from the SwiftUI interface (`SillageApp`); no third-party library.

## Ideas for later

- Export / import (JSON, iCal) and reading your existing calendars
- Custom categories and shortcuts
- Global keyboard shortcut to start / stop a task
- End-of-day summary

## License

[MIT](LICENSE): free to use, modify and redistribute. © Damien POLLET (Wudstyz)
