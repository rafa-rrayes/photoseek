# DejaVi

A Raycast-style semantic photo search app for macOS. Search your Photos library using natural language — find photos by what's *in* them, not by tags or filenames.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5-orange) ![No Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

## How It Works

DejaVi indexes your photo library by generating AI embeddings (via Gemini) for each image, then performs cosine similarity search against your natural language queries. Type "sunset on the beach" and get visually matching photos ranked by similarity score.

## Features

- **Semantic search** — find photos by describing what's in them
- **Menu bar app** — lives in your menu bar, out of the way
- **Bulk actions** — multi-select to favorite, delete, or organize into albums
- **Fast** — in-memory vector search with Accelerate framework (vDSP)
- **Zero dependencies** — pure Swift, system frameworks only
- **Incremental indexing** — only processes new photos

## Requirements

- macOS 14 (Sonoma) or later
- A [Gemini API key](https://aistudio.google.com/apikey)

## Getting Started

### Build

```bash
./build.sh
```

This produces a `.app` bundle you can move to `/Applications`.

```bash
open build/DejaVi.app
```

### Setup

1. Launch DejaVi — it appears in your menu bar
2. Open Settings and enter your Gemini API key
3. Click **Index Photos** to start indexing your library
4. Click the menu bar icon to search

By default, DejaVi indexes from `~/Pictures/Photos Library.photoslibrary/originals`.

## Architecture

```
User query → Gemini embedding (768-dim) → cosine similarity vs indexed photos → ranked results
```

| Component | Role |
|---|---|
| `VectorStore` | SQLite-backed vector database with in-memory search |
| `GeminiClient` | Generates text/image embeddings via Gemini API |
| `SearchViewModel` | Core state management with debounced search |
| `PanelController` | Floating NSPanel for search UI |
| `ImageCache` | NSCache-based thumbnail caching (100MB limit) |
| `PhotosActions` | Photos.app integration via AppleScript + PhotoKit |

## Tech Stack

- SwiftUI + AppKit (NSPanel, NSCache)
- SQLite3 for vector storage
- Accelerate framework for vector math
- Photos framework + AppleScript for photo management
- Gemini Embedding API (`gemini-embedding-2-preview`)

## License

MIT
