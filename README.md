# PhotoSeek

Search your Apple Photos library by describing what's in the picture, from a Spotlight-style panel in the macOS menu bar.

<!-- TODO: add a screenshot or GIF of the search panel here (e.g. docs/screenshot.png). -->

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![iOS 17+](https://img.shields.io/badge/iOS-17%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5-orange) ![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

Type "sunset on the beach" or "dog in the snow" and get matching photos and videos, ranked by similarity. No tagging, no filenames.

## How it works

1. **Indexing.** PhotoSeek reads each photo in your Photos library, downsizes it to at most 768 px, encodes it as JPEG, and sends it to Google's Gemini embedding API (`gemini-embedding-2-preview`). The API returns a 768-dimensional vector for that image.
2. **Storage.** The vector is stored locally in a SQLite database (`photos` and `videos` tables, vector as a BLOB) next to the photo's UUID, filename, date and path. It lives at `~/Library/Application Support/PhotoSeek/photoseek.db`.
3. **Searching.** Your query text is sent to the same API to get a vector in the same space. PhotoSeek then compares it against every stored vector by cosine similarity in memory (Accelerate/vDSP) and shows the top results. Searching needs one API call per query; the comparison itself is local.

Videos are supported too: the first 2 minutes of each video are uploaded to the Gemini Files API, embedded, and the uploaded copy is deleted afterwards. Video indexing can be turned off in Settings.

On macOS, the folders to index are configurable in Settings (default: the `originals` folder inside your Photos library). Indexing is incremental: photos already in the database are skipped.

## Privacy: read this before indexing

**Your photos leave your machine.** To compute embeddings, a downsized JPEG of every indexed photo (and the first 2 minutes of every indexed video) is sent to Google's Gemini API using your API key. Every search query is also sent to Google. Google's terms for the Gemini API and your account type (free vs. paid tier) decide how that data may be retained or used, so check them before indexing anything sensitive. PhotoSeek has no server of its own and does no analytics or telemetry; the only network traffic is to `generativelanguage.googleapis.com`.

Stored locally:

- The embedding database described above (vectors plus filename, date and path; no image data).
- Your API key, saved as a file with `0600` permissions at `~/Library/Application Support/PhotoSeek/`. It is **not** kept in the Keychain and is not encrypted. Anyone with access to your user account can read it.

## Requirements

- macOS 14 (Sonoma) or later (the iOS app targets iOS 17+)
- A [Gemini API key](https://aistudio.google.com/apikey), which you enter in Settings. No key is bundled with the app or the source.
- Permission to read your Photos library. The app reads `~/Pictures/Photos Library.photoslibrary` directly from disk (so it asks you to select that library once) and uses the Photos framework for actions like favoriting, deleting and adding to albums.
- Swift 6 toolchain / Xcode 16 to build from source.

## Quickstart

```bash
git clone https://github.com/rafa-rrayes/photoseek.git
cd photoseek
ARCHS=arm64 ./build.sh      # omit ARCHS for a universal arm64 + x86_64 build
open build/PhotoSeek.app
```

`build.sh` produces `build/PhotoSeek.app` and a DMG. If a Developer ID Application certificate is in your keychain it signs with it; otherwise the result is unsigned and you may need to right-click > Open the first time. Set `SIGNING_IDENTITY` and `NOTARY_PROFILE` to sign and notarize explicitly (see the header of `build.sh`).

For development, `swift build` and `swift run PhotoSeekMac` also work.

Then:

1. Launch PhotoSeek. It runs as a menu bar app with no Dock icon.
2. Open Settings, paste your Gemini API key, and grant access to your Photos library when asked.
3. Start indexing. A large library takes a while and makes many API calls, which may count against your Gemini quota or bill.
4. Click the menu bar icon and choose **Search Photos** to open the search panel.

### iOS

The iOS app shares the same core library and supports background indexing. Its Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
open PhotoSeek.xcodeproj
```

Set your own development team in Xcode, and change the bundle identifier (`com.rafa.dejavi`, a legacy ID from the maintainer's App Store Connect setup that you cannot sign with) to one you own before running on a device. The simulator build compiles with `CODE_SIGNING_ALLOWED=NO`.

## Keyboard shortcuts and controls

There is no global hotkey. Open the panel from the menu bar icon.

| Action | Control |
|---|---|
| Dismiss the search panel | `Esc` |
| Quit (menu bar menu) | `Cmd+Q` |

The panel supports multi-select for bulk favorite, delete and add-to-album, and a photo info popover. Settings include launch at login, video indexing, whether to include iCloud-only items (off by default, since they must be downloaded), and showing similarity percentages.

## Architecture

```
Sources/
  PhotoSeekCore/   shared logic: Gemini client, SQLite vector store, search/indexing view model, settings
  PhotoSeekMac/    macOS menu bar app (SwiftUI + AppKit NSPanel)
  PhotoSeekiOS/    iOS app (SwiftUI), built via project.yml / XcodeGen
```

| Component | Role |
|---|---|
| `GeminiClient` | Embedding calls, plus Files API upload for videos |
| `VectorStore` | SQLite storage and in-memory cosine search |
| `SearchViewModel` | Debounced search, indexing with 5 concurrent requests and retry on rate limits |
| `EmbeddingPreparer` | Resizes and JPEG-encodes images, slices videos |
| `PanelController` | Floating search panel on macOS |

There are no third-party dependencies, only system frameworks.

## Limitations and status

- Pre-release software. Expect rough edges and no stability guarantees.
- Requires internet access and a Gemini API key; the embedding model is a preview model and Google may change or retire it. Changing models would require re-indexing.
- The macOS app reads the Photos library files directly and runs without the App Sandbox (needed for the AppleScript/Photos integration).
- Only the first 2 minutes of a video are embedded.
- The API key is stored in a plain file, not the Keychain (see Privacy).
- There are no automated tests yet.

## License

[MIT](LICENSE)
