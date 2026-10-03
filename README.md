# Ebb

A calmer iPhone. iOS doesn't let apps replace the Home Screen, so Ebb builds one from widgets: your apps as plain text on a wallpaper that matches the widgets exactly, plus quiet clocks and progress widgets. The Ebb app is where you set it all up, along with a mindful pause before distracting apps and Screen Time blocking for work and focus.

## Features

- **App widgets**: up to 6 apps each, as plain text (medium and large). Taps open apps directly; apps with a mindful pause go through Ebb first. 2 app widgets free, 8 with Ebb Plus.
- **Clock**: Digital and Analog (free); Stacked, Words, and Day ring (Plus). Optional date and day progress bar. Small, medium, and large.
- **Year**: progress through today, this week, month, or year, as a percent, bar, dots, ring, or countdown.
- **Life**: share of an average life lived or remaining, from your birthday and sex (CDC 2023 US averages).
- **Time Saved**: hours given back from apps let go and focus sessions, as a number, breakdown, or "what it adds up to".
- **Time & Life** (Plus): time given back and life left in one large widget, made for the Today View (extra large on iPad).
- **Spacer**: an empty block in the widget color for laying out the Home Screen.
- **Colors and wallpaper**: one color for Ebb, every widget, and a matching wallpaper saved to Photos (Midnight and Paper built in, plus presets and custom colors).
- **Mindful pause**: a breathing countdown and an optional "what's this for?" before chosen apps.
- **Focus and blocking** (Screen Time): work periods that block everything except allowed apps, focus sessions with a strict mode, nightly wind-down, daily limits, and a "Take a breath" button on the block screen that unlocks an app for a set number of minutes.
- **Insights**: opens, let-gos, streaks, and stated reasons, kept on-device for 30 days.
- Setup dashboard with a checklist, guided walkthrough, and Settings.

Everything stays on the iPhone. There are no accounts, servers, or analytics.

## Requirements

- Xcode 27 or later
- iOS 26.2 or later
- An Apple Developer Program membership to use Screen Time blocking (Family Controls). Free personal teams can build and run everything else.

## Project structure

| Folder | What it is |
| --- | --- |
| `Ebb/` | The app: dashboard, setup, settings, focus, insights |
| `EbbWidget/` | Widget extension: Apps, Spacer, Clock, Year, Life, Time Saved, Open Ebb |
| `EbbMonitor/` | DeviceActivity monitor: starts and ends scheduled blocking |
| `EbbShield/` | Shield configuration: the block screen's look |
| `EbbShieldAction/` | Shield action: the block screen's "Take a breath" button |
| `Shared/` | Code shared by the app and all extensions (app group, colors, plan limits, progress math) |
| `SharedScreenTime/` | Code shared by the app and Screen Time extensions (shields, work periods) |
| `EbbTests/` | Unit tests |

## Signing

| | |
| --- | --- |
| Team ID | `69ML2GA87D` |
| App bundle ID | `mpbunce.Ebb` |
| Extensions | `mpbunce.Ebb.Widget`, `mpbunce.Ebb.Monitor`, `mpbunce.Ebb.Shield`, `mpbunce.Ebb.ShieldAction` |
| App group | `group.mpbunce.Ebb` |
| Capabilities | App Groups (all targets), Family Controls (app and Screen Time extensions) |

Signing is automatic. Family Controls works for development builds on a paid team. Before shipping to the App Store, request the Family Controls distribution entitlement from Apple.

## Running

**Simulator**: open `Ebb.xcodeproj`, choose an iPhone simulator, and press ⌘R. Screen Time blocking doesn't work in the simulator.

**iPhone**:
1. In Xcode › Settings › Accounts, sign in with the account for team `69ML2GA87D`.
2. On the iPhone, turn on Settings › Privacy & Security › Developer Mode.
3. Connect the iPhone, choose it as the run destination, and press ⌘R. If macOS asks for keychain access while signing, enter your Mac login password and choose **Always Allow**.

**Tests**:

```bash
xcodebuild test -project Ebb.xcodeproj -scheme Ebb -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:EbbTests
```

## Ebb Plus

A one-time, non-consumable in-app purchase with product ID `mpbunce.ebb.plus`, bought and restored in Settings › Ebb Plus. `Ebb/Store/PlusStore.swift` uses StoreKit 2 to check what's owned at launch and on every App Store update (including refunds), and sets `EbbPlus.isActive` in the App Group so the widgets see it too. Plan limits live in `Shared/Plan.swift`. Debug builds include a "Preview Plus features" toggle. `EbbTests/EbbPlus.storekit` is a local StoreKit configuration used by the purchase test.
