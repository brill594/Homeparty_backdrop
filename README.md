# HomeParty Backdrop

HomeParty Backdrop is a Flutter macOS app for running event backdrops and program playback from a control UI.

It provides:
- a Control page for queueing and triggering playback,
- a Stage page for fullscreen display output,
- a separate always-on-top Playlist Manager window for live queue edits.

## Features

- Set a default background (image or video) that persists across app restarts.
- Add playable programs:
  - `Video` program: one video file.
  - `Image` program: one image file + one accompaniment audio file.
- Optional program metadata: title and artist.
- Queue supports add, edit, delete, and drag-reorder.
- Start playback in sequence (next item cycles through the queue).
- Auto-reset to default background when a program finishes:
  - video ends, or
  - image accompaniment audio ends.
- Import and export playlist JSON files.
- Bilingual UI: English and Simplified Chinese.
- User-configurable trigger keys for:
  - play next,
  - reset to default.

## Requirements

- macOS (project is currently configured for desktop macOS runtime)
- Flutter SDK compatible with `sdk: ^3.10.4` (see `pubspec.yaml`)
- Xcode command line tools for macOS Flutter builds

## Quick Start

```bash
flutter pub get
flutter run -d macos
```

## Build

```bash
flutter build macos
```

## How To Use

1. Launch the app.
2. In Control, click `Set default background`.
3. Add queue items from `Add playable file`.
4. Open Stage with `Open stage page`.
5. Trigger playback from:
   - the `Start playback (next item)` button, or
   - the configured playback trigger key.
6. Return to default background from:
   - `Switch to default background`, or
   - the configured reset key.

When Stage opens, the app also opens an always-on-top `Stage Playlist Manager` window for faster queue operations during playback.

## Keyboard Shortcuts

### Control Window

- Default playback trigger key: `N` (configurable)
- Default reset-to-default key: `B` (configurable)
- Trigger keys only fire on key-down with no modifier keys pressed.

### Stage Window

- `Space`: pause/resume video
- `F11`: enter fullscreen
- `Esc`: exit fullscreen

## Supported Media Formats

Configured in `lib/app_state.dart`.

### Images

`jpg`, `jpeg`, `png`, `webp`, `bmp`, `gif`, `heic`

### Videos

`mp4`, `mov`, `m4v`, `3gp`, `3g2`, `avi`, `asf`, `flv`, `f4v`, `mkv`,
`mpeg`, `mpg`, `m2ts`, `mts`, `m2v`, `ts`, `ogv`, `wmv`, `webm`

### Audio (for image programs)

`mp3`, `aac`, `m4a`, `wav`, `flac`, `ogg`

## Playlist File Format

Playlists are exported/imported as JSON.

Example:

```json
{
  "schemaVersion": 1,
  "exportedAt": "2026-02-22T14:00:00.000Z",
  "queue": [
    {
      "type": "video",
      "path": "/absolute/path/program.mp4",
      "audioPath": null,
      "title": "Opening",
      "artist": "Host"
    },
    {
      "type": "image",
      "path": "/absolute/path/slide.jpg",
      "audioPath": "/absolute/path/backing.mp3",
      "title": "Interlude",
      "artist": "Band"
    }
  ]
}
```

Notes:
- `schemaVersion` is currently `1`.
- The app can parse either:
  - full object payload with `queue`, or
  - a raw list of queue items.

## Persistence and Storage

- Locale preference is persisted with `shared_preferences`.
- Default media is copied into managed app storage so it remains available after restart.
- On macOS, managed files are stored under:
  - `~/Library/Application Support/homeparty_backdrop/defaults`

## Localization

- English (`en`)
- Simplified Chinese (`zh_CN`)

Language can be switched from the Control page app bar.

## Key Files

- `lib/main.dart`: app bootstrap, localization, trigger-key handling
- `lib/control_page.dart`: control UI and queue management
- `lib/stage_page.dart`: stage playback surface and fullscreen behavior
- `lib/playlist_manager_window.dart`: multi-window playlist manager
- `lib/app_state.dart`: core state, queue logic, persistence, format lists
- `lib/app_i18n.dart`: localization strings and language mapping
