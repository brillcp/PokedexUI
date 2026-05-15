![icon](https://github.com/user-attachments/assets/5abf1763-b290-4f12-a661-986e58fbeaad)

![swift](https://img.shields.io/badge/Swift-6.0%2B-green)
![release](https://img.shields.io/github/v/release/brillcp/pokedexui)
![platforms](https://img.shields.io/badge/Platforms-iOS%2026%2B-blue)
![apple-intelligence](https://img.shields.io/badge/Apple%20Intelligence-FoundationModels-purple)
[![spm](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-green)](#swift-package-manager)
[![license](https://img.shields.io/github/license/brillcp/pokedexui)](/LICENSE)
![stars](https://img.shields.io/github/stars/brillcp/pokedexui?style=social)

# PokedexUI

PokedexUI is a SwiftUI showcase app for **Apple's on-device FoundationModels framework**, wrapped around the full [PokeAPI](https://pokeapi.co) dataset. It started as a clean reference implementation of MVVM, actor concurrency, and SwiftData persistence, and has grown into a working turn-based **Pokémon battle simulator** where the opponent's moves and loadout are picked by Apple Intelligence in real time.

Built by [Viktor Gidlöf](https://viktorgidlof.com).

<img height="800" alt="pokedex2026" src="https://github.com/user-attachments/assets/451ad765-9be9-4643-afc2-6baccf661e91" />

---

# Battle System ⚔️

The battle screen is a turn-based 1v1 simulator built on top of the real PokeAPI move and type data. Both sides commit to 4 hand-picked moves before the fight starts, then trade turns until one side faints. The Gen-V damage formula drives every hit (level 50, STAB, type effectiveness, crit roll, accuracy roll, burn penalty), and status effects (paralysis, burn, poison) tick at end-of-turn.

The opponent is driven entirely by **Apple's `FoundationModels` framework**, running fully on-device.

## What the AI does

PokedexUI uses `SystemLanguageModel.default` in three places:

1. **Opponent picking** ("Smart pick" button in the picker sheet)
   The model receives the player's name and types plus a roster of 60 candidate pokemon and returns a `pokedex id` representing a worthy matchup.
2. **Loadout selection** (background task during the loadout screen)
   The model receives the opponent's typing, the player's typing, and a 40-move sample of the opponent's full movepool with pre-computed type-effectiveness multipliers. It returns 4 zero-based indices — the moves the opponent brings into battle.
3. **Per-turn move selection** (every time the player commits a move)
   The model receives both combatants' current HP, status, and types, plus the opponent's 4 chosen moves with effectiveness multipliers, and returns the index of the move to play.

All three calls share one `LanguageModelSession` instance per battle (so the model has conversation memory across turns) and degrade gracefully to deterministic heuristics if Apple Intelligence isn't available on the device, the session is busy, or the model returns garbage. **The battle UI never blocks waiting on a model response.**

## How the prompts are built

`BattleAIPromptBuilder` constructs each prompt as a compact text snapshot. The model never has to recall the type chart from training: every damaging move row carries a pre-computed `×N vs defender` multiplier, so the model just compares numbers. Status moves are flagged explicitly. The system prompt lives in [`BattleAIInstructions.md`](PokedexUI/Features/Battle/AI/BattleAIInstructions.md) and is loaded once when the service initializes.

Structured output uses Apple's `@Generable` macro:

```swift
@Generable(description: "The opponent's chosen move for this turn.")
struct MoveChoice {
    @Guide(description: "Zero-based index of the chosen move in the provided list.")
    let index: Int
}
```

No JSON parsing, no string matching, no typo failures. The model returns a strongly-typed Swift struct.

## Why on-device?

- **Zero latency to the network** — every inference happens locally.
- **Free** — no API tokens, no rate limits.
- **Private** — battle state never leaves the device.
- **Available offline** — the app stays playable once the PokeAPI data is cached.

This is the kind of feature `FoundationModels` was built for: small, structured, latency-sensitive decisions on top of well-defined data.

---

# Architecture 🏛

PokedexUI is **Protocol-Oriented MVVM** with clear layer boundaries and aggressive actor isolation.

```
┌─────────────────────────────────────────────────────────┐
│  App/                                                   │
│    PokedexUIApp        AppContainer (composition root)  │
├─────────────────────────────────────────────────────────┤
│  Features/                                              │
│    Pokedex   PokemonDetail   Battle   Search            │
│    Bookmarks  Items                                     │
├─────────────────────────────────────────────────────────┤
│  Core/                                                  │
│    Domain/  (SwiftData @Models)                         │
│    Services/  (actor-backed networking and prefetchers) │
│    Storage/  (DataStorageReader @ModelActor)            │
│    Networking/  (APIService<Config> generic actor)      │
├─────────────────────────────────────────────────────────┤
│  DesignSystem/                                          │
│    Components/  Colors/  Modifiers/  Fonts              │
└─────────────────────────────────────────────────────────┘
```

## Concurrency model

Every long-lived worker is an actor unless it has to bind to SwiftUI directly:

| Type                       | Isolation                  | Why                                                          |
| -------------------------- | -------------------------- | ------------------------------------------------------------ |
| `BattleAIService`          | `actor`                    | Owns the `LanguageModelSession`, called from any context     |
| `SpriteLoader`             | `actor`                    | Image download + `URLCache` access                           |
| `ImageColorAnalyzer`       | `actor`                    | Pixel-scan pipeline, off the main thread                     |
| `AudioPlayer`              | `actor`                    | AVFoundation playback                                        |
| `EvolutionService`         | `actor`                    | Process-wide chain-id memo                                   |
| `MovePrefetcher`           | `actor`                    | One-shot background download                                 |
| `SpriteColorPrefetcher`    | `actor`                    | One-shot background analysis                                 |
| `DataStorageReader`        | `@ModelActor`              | Isolated SwiftData `ModelContext`                            |
| `APIService<Config>`       | `actor`                    | Generic network actor over `Requestable`                     |
| `TypeChartLoader`          | `@MainActor @Observable`   | `WeaknessGridView` reads its `chart` synchronously in body   |
| View models                | `@MainActor @Observable`   | SwiftUI binding                                              |
| `BattleEngine`             | `@MainActor`               | `withAnimation` callbacks see consistent state               |

The type chart is the only hybrid case: the loader stays on `MainActor` for SwiftUI binding, but it exposes a Sendable `TypeChart` value snapshot that the AI service and battle engine can read off-main with zero actor hops on the hot per-turn path.

## Dependency injection

A single `AppContainer` is the composition root. Every service, prefetcher, and long-lived worker is constructed there and handed to the view tree through one environment key:

```swift
@MainActor
final class AppContainer {
    let pokemonService:        PokemonServiceProtocol
    let moveService:           MoveServiceProtocol
    let battleAI:              BattleAIServiceProtocol
    let typeChart:             TypeChartLoader
    let movePrefetcher:        MovePrefetcher
    let spriteColorPrefetcher: SpriteColorPrefetcher
    let spriteLoader:          SpriteLoader
    let imageColorAnalyzer:    ImageColorAnalyzer
    let audioPlayer:           AudioPlayer
    // ...
    static let live = AppContainer()
}

@Environment(\.container) private var container
```

Tests and previews swap in a custom container with mocks; the rest of the app is unaware.

## Storage

Five `@Model` types, all deduped on a unique key:

- `PokemonSummary` (id-unique): id, name, bookmark flag, persisted dominant sprite color
- `Pokemon` (id-unique): full hydrated detail, stats, sprites, moves, species fields
- `MoveDetail` (name-unique): power, accuracy, type, damage class, ailment
- `TypeDetail` (name-unique): damage relations for the 18 elemental types
- `ItemData` (id-unique): item catalogue

The pokedex grid renders from `PokemonSummary` only — full `Pokemon` rows are hydrated lazily on tap and cached forever, since Pokémon data is immutable.

---

# Prefetchers 📥

Three background workers fill the on-disk cache at app launch so the UI never waits on the network.

| Prefetcher              | What it pulls                             | When             |
| ----------------------- | ----------------------------------------- | ---------------- |
| `TypeChartLoader`       | 18 type damage relations                  | App launch       |
| `MovePrefetcher`        | ~937 moves (full PokeAPI move catalogue)  | App launch, background priority |
| `SpriteColorPrefetcher` | Dominant color for every pokemon sprite   | App launch, background priority |

The pokedex grid itself paginates `/pokemon?offset=N&limit=200` in chunks of 200, so the first page lands well under a second. Subsequent app launches read everything from SwiftData with zero network calls.

Detail-view gradient colors are the most visible payoff: the sprite color prefetcher walks every `PokemonSummary` missing a `colorHex`, runs the image color analyzer, and persists the hex back to SwiftData. By the time the user taps any pokemon, the gradient renders on frame 1 with no compute pass.

---

# Battle UX flow 🎮

```
Detail view
   │ (tap Fight ⚡)
   ▼
Opponent picker sheet  ◄── Random / Smart pick (AI)
   │ (tap a candidate)
   ▼
Loadout screen
   │ • Hydrate both pokemon (cache or network)
   │ • Sample 40 moves per side
   │ • AI picks opponent's 4 (background task)
   │ • Player hand-picks own 4 from sorted movepool
   │ (tap Battle)
   ▼
Battle view
   • Arena renders frame 1 (state built in init)
   • Each turn: player taps move →
       AI picks opponent's move →
       Engine resolves both in speed order →
       Events animate (lunge, shake, damage, faint)
```

The AI's per-turn move pick runs while a "..." placeholder appears in the battle log, so the player always sees activity. The battle screen never holds the loadout sheet open: every preflight task either completes before the player commits, or runs lazily inside the battle view itself.

---

# Design System 🎨

Pixel font, gameboy-style aesthetic, glass effects:

- **`Chip`**: small inline pill used for type tags, generation badges, status pills, effectiveness markers. Always a 4-point corner radius (capsules look too modern next to the pixel font).
- **`MoveCell`**: shared between the battle move grid and the loadout move picker, switched via a `Mode` enum.
- **`TypeColor`**: centralized type → color map used by every move chip, type tag, and weakness grid row.
- **`PokedexGridView`**: 2-column or 3-column grid of `PokemonSummary` rows used by the pokedex, search, and bookmarks tabs.

---

# Dependencies 🔗

PokedexUI uses the [Networking](https://github.com/brillcp/Networking) package for all PokeAPI HTTP calls. It's a thin actor-based wrapper around `URLSession` with a generic `Requestable` protocol that drives every endpoint in the app. Read more about that [here](https://github.com/brillcp/Networking#readme).

```swift
dependencies: [
    .package(url: "https://github.com/brillcp/Networking.git", .upToNextMajor(from: "0.9.3"))
]
```

---

# Requirements ❗️

- Xcode 26+
- iOS 26+ (for the `FoundationModels` framework, `@Observable`, SwiftData lightweight migration)
- Swift 6+ (strict concurrency)
- Apple Intelligence enabled on the device for the AI features (graceful fallback to random/heuristic on devices without it)
