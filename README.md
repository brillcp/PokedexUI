![icon](https://github.com/user-attachments/assets/d7a242d8-5392-4718-9b0a-4a4392f66d82)

![swift](https://img.shields.io/badge/Swift-6.0%2B-green)
![release](https://img.shields.io/github/v/release/brillcp/pokedexui)
![platforms](https://img.shields.io/badge/Platforms-iOS%2026%2B-blue)
![apple-intelligence](https://img.shields.io/badge/Apple%20Intelligence-FoundationModels-purple)
[![spm](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-green)](#swift-package-manager)
[![license](https://img.shields.io/github/license/brillcp/pokedexui)](/LICENSE)
![stars](https://img.shields.io/github/stars/brillcp/pokedexui?style=social)

# PokedexUI

PokedexUI is a SwiftUI app built on top of the [PokeAPI](https://pokeapi.co), with a working turn-based Pokémon battle mode driven by **Apple's on-device FoundationModels framework**. Browse the dex, dig into a pokemon, pick a fight.

It's meant as a reference codebase. If you're a senior iOS engineer looking for a worked example of modern SwiftUI patterns (actors, `@Observable`, SwiftData, on-device AI integration), or someone earlier in their iOS journey trying to see how these pieces fit together in a real app, hopefully there's something here for you. Every feature is small enough to read end-to-end, and every type has a doc comment explaining why it exists.

Built by [Viktor Gidlöf](https://viktorgidlof.com).

<img height="800" alt="pokedex2026" src="https://github.com/user-attachments/assets/7a3be5ca-9b71-4107-9544-91738bb5291c" />

---


# Architecture 🏛

PokedexUI is **Protocol-Oriented MVVM** with clear layer boundaries and aggressive actor isolation.

## Key architectural benefits

- ✅ **Protocol-Oriented**: every layer depends on abstractions, enabling DI and easy testing.
- ✅ **Generic Networking**: one `APIService<Config>` actor over a `Requestable` protocol drives every PokeAPI endpoint.
- ✅ **Storage-First**: SwiftData is the source of truth; the network is a backfill mechanism.
- ✅ **Actor-Based Concurrency**: every long-lived worker is an actor; SwiftUI-bound types are `@MainActor @Observable`.
- ✅ **Clean Separation**: App / Features / Core / DesignSystem layers with one-way dependencies (App can see everything, Core depends on nothing).
- ✅ **Type Safety**: generics, `@Generable` AI outputs, `@Attribute(.unique)` on every top-level cache entity (Pokemon, MoveDetail, TypeDetail, ItemData, EvolutionChainEntity). Nested rows ride on cascade.
- ✅ **Reactive UI**: SwiftUI body re-renders driven entirely by `@Observable` view models.
- ✅ **On-Device AI**: Apple `FoundationModels` integrated with structured output and deterministic fallbacks.

### SOLID Compliance Score: 0.94 / 1.0

- **S**ingle Responsibility: each service, prefetcher, and view model has one job. `BattleViewModel` is a thin conductor (~80 LOC) that delegates cue timing to `BattleAnimator`, AI history to `OpponentBrain`, log rendering to `BattleLogFormatter`, and round playback to its own `+Round` extension.
- **O**pen/Closed: the `APIService<Config>` generic + `Requestable` protocol lets new endpoints be added without modifying the network layer. New AI capabilities slot into `BattleAIServiceProtocol` without touching the views.
- **L**iskov Substitution: every protocol has at least one concrete implementation plus a mock used in previews. Substitution is the default path.
- **I**nterface Segregation: each view model exposes only the surface its view needs. `BattleView` reads cues off `viewModel.animator`, log text off `viewModel.log`; `BattleSetupView` reads pool + selection state. No god-protocol shared across consumers.
- **D**ependency Inversion: `AppContainer` is the single composition root. Views read services via `@Environment(\.container)`; no `static let shared` lookups in feature code.

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
| `DataStorageReader`        | `@ModelActor`              | Isolated SwiftData `ModelContext`                            |
| `APIService<Config>`       | `actor`                    | Generic network actor over `Requestable`                     |
| `TypeChartLoader`          | `@MainActor @Observable`   | `WeaknessGridView` reads its `chart` synchronously in body   |
| `BattleAnimator`           | `@MainActor @Observable`   | Owns cue mutation + `withAnimation` blocks for the arena    |
| View models                | `@MainActor @Observable`   | SwiftUI binding                                              |
| `BattleEngine`             | `@MainActor`               | `withAnimation` callbacks see consistent state               |

The type chart is the only hybrid case: the loader stays on `MainActor` for SwiftUI binding, but it exposes a Sendable `TypeChart` value snapshot that the AI service and battle engine can read off-main with zero actor hops on the hot per-turn path.

## Dependency injection

A single `AppContainer` is the composition root. Every service, prefetcher, and long-lived worker is constructed there and handed to the view tree through one environment key:

```swift
@MainActor
final class AppContainer {
    let pokemonService:     PokemonServiceProtocol
    let evolutionService:   EvolutionServiceProtocol
    let itemService:        ItemServiceProtocol
    let battleAI:           BattleAIServiceProtocol
    let typeChart:          TypeChartLoader
    let movePrefetcher:     MovePrefetcher
    let spriteLoader:       SpriteLoader
    let imageColorAnalyzer: ImageColorAnalyzer
    let audioPlayer:        AudioPlayer
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

The pokedex grid renders from `PokemonSummary` only; full `Pokemon` rows are loaded lazily on tap and cached forever, since Pokémon data is immutable.

---

# Battle System ⚔️

The battle screen is a turn-based 1v1 simulator built on top of the real PokeAPI move and type data. Both sides commit to 4 hand-picked moves before the fight starts, then trade turns until one side faints. The Gen-V damage formula drives every hit (level 50, STAB, type effectiveness, crit roll, accuracy roll, burn penalty), and status effects (paralysis, burn, poison) tick at end-of-turn.

The opponent is driven entirely by **Apple's `FoundationModels` framework**, running fully on-device.

## What the AI does

PokedexUI uses `SystemLanguageModel.default` in three places:

1. **Opponent picking** ("Smart pick" button in the picker sheet)
   The model receives the player's name and types plus a roster of 60 candidate pokemon and returns a `pokedex id` representing a worthy matchup.
2. **Loadout selection** (background task during the loadout screen)
   The model receives the opponent's typing, the player's typing, and a 40-move sample of the opponent's full movepool with pre-computed type-effectiveness multipliers. It returns 4 zero-based indices: the moves the opponent brings into battle.
3. **Per-turn move selection** (every time the player commits a move)
   The model receives both combatants' current HP, status, and types, plus the opponent's 4 chosen moves with effectiveness multipliers, and returns the index of the move to play.

All three calls share one `LanguageModelSession` instance per battle (so the model has conversation memory across turns) and degrade gracefully to deterministic heuristics if Apple Intelligence isn't available on the device, the session is busy, or the model returns garbage. **The battle UI never blocks waiting on a model response.**

## How the prompts are built

`BattleAIPromptBuilder` constructs each prompt as a compact text snapshot. The model never has to recall the type chart from training: every damaging move row carries a pre-computed `×N vs defender` multiplier, so the model just compares numbers. Status moves are flagged explicitly. System prompts live in [`PokedexUI/Features/Battle/AI/`](PokedexUI/Features/Battle/AI/), split per task: [`BattleAIMoveInstructions.md`](PokedexUI/Features/Battle/AI/BattleAIMoveInstructions.md), [`BattleAILoadoutInstructions.md`](PokedexUI/Features/Battle/AI/BattleAILoadoutInstructions.md), [`BattleAIOpponentInstructions.md`](PokedexUI/Features/Battle/AI/BattleAIOpponentInstructions.md). Each is loaded once when its session initializes.

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

- **Zero latency to the network**: every inference happens locally.
- **Free**: no API tokens, no rate limits.
- **Private**: battle state never leaves the device.
- **Available offline**: the app stays playable once the PokeAPI data is cached.

This is the kind of feature `FoundationModels` was built for: small, structured, latency-sensitive decisions on top of well-defined data.

---

# Prefetchers 📥

Three background workers fill the on-disk cache at app launch so the UI never waits on the network.

| Prefetcher              | What it pulls                             | When             |
| ----------------------- | ----------------------------------------- | ---------------- |
| `TypeChartLoader`       | 18 type damage relations                  | App launch       |
| `MovePrefetcher`        | ~937 moves (full PokeAPI move catalogue)  | App launch, background priority |
| `EvolutionService`      | Evolution chains for hydrated pokemon     | App launch, background priority |

Sprite colors are resolved lazily on first display through `ImageColorAnalyzer` (an actor) and cached in-process by pokemon id, so a detail view that opens the same pokemon twice runs the pixel scan once. The pokedex grid itself paginates `/pokemon?offset=N&limit=200` in chunks of 200, so the first page lands well under a second. Subsequent app launches read everything from SwiftData with zero network calls.

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
