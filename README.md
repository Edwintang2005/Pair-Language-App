# Pair

An iPhone app for two people teaching each other their languages, five words at a time. One of you learns
German, the other learns Chinese. Each session gives you five words to learn from your partner and five to
teach them, along with teaching notes, examples and on-device pronunciation.

There's no server and no account. Everything ships inside the app, and each phone keeps its own progress.

## How it works

- **Today**: the current session. Your words stay hidden until you tap "I've been taught this". Your partner's
  words show everything plus a teaching tip. Finish the session on both phones to move on together.
- **Review**: spaced repetition for the words you've learned. Grading Again / Good / Easy schedules each word
  1 to 128 days out.
- **Words**: every session so far, in both languages, searchable.
- **Settings** (gear icon): switch language, set the session number if you get out of step, reset.

## Building

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
```

```bash
open Pair.xcodeproj
```

`project.yml` is the source of truth for the Xcode project. Re-run `xcodegen generate` after adding or
removing files.

### Installing on your phones

1. In `project.yml`, set `DEVELOPMENT_TEAM` to your Team ID and change `PRODUCT_BUNDLE_IDENTIFIER` to one you
   own (e.g. `com.yourname.pair`), then regenerate.
2. Plug in your phone, pick it as the run destination in Xcode, and run. Or archive and upload to TestFlight
   to install on your partner's phone.

### Tests

```bash
xcodebuild test -project Pair.xcodeproj -scheme Pair -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Content

Word lists live in `content/` and are bundled into the app as-is. See [content/FORMAT.md](content/FORMAT.md).
After editing, check them:

```bash
python3 tools/validate.py
```

Word IDs must never change once you're using the app, because review history is keyed by them.

The app icon is drawn by `tools/make_icon.swift`:

```bash
swift tools/make_icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```
