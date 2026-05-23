![icon](https://github.com/user-attachments/assets/d7a242d8-5392-4718-9b0a-4a4392f66d82)

![swift](https://img.shields.io/badge/Swift-5.0-green)
![release](https://img.shields.io/github/v/release/brillcp/pokedexui)
![platforms](https://img.shields.io/badge/Platforms-iOS%2026%2B-blue)
![apple-intelligence](https://img.shields.io/badge/Apple%20Intelligence-FoundationModels-purple)
[![spm](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-green)](#swift-package-manager)
[![license](https://img.shields.io/github/license/brillcp/pokedexui)](/LICENSE)
![stars](https://img.shields.io/github/stars/brillcp/pokedexui?style=social)

# PokedexUI

PokedexUI is a SwiftUI app built on top of the [PokeAPI](https://pokeapi.co), with a working turn-based Pokémon battle mode driven by **Apple's on-device FoundationModels framework**. Browse the dex, dig into a pokemon, pick a fight.

If you're a senior iOS engineer looking for a worked example of modern SwiftUI patterns (actors, `@Observable`, SwiftData, on-device AI integration), or someone earlier in their iOS journey trying to see how these pieces fit together in a real app, hopefully there's something here for you. Every feature is small enough to read end-to-end, and every public type plus every protocol member carries a doc comment explaining why it exists.

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
- ✅ **Type Safety**: generics, Sendable AI snapshots crossing actor boundaries, `@Attribute(.unique)` on every keyed cache entity (Pokemon by id, EvolutionChainEntity by chainId). Nested rows ride on cascade; `ItemData` is keyed by category title. Move and type data live in PokeBattleKit's own disk cache.
- ✅ **Reactive UI**: SwiftUI body re-renders driven entirely by `@Observable` view models.
- ✅ **On-Device AI**: Apple `FoundationModels` with `@Generable` structured output, `Tool`-based type/damage reasoning, and deterministic fallbacks via [PokeBattleKit](https://github.com/brillcp/PokeBattleKit) at every call site.

### SOLID Compliance Score: 0.94 / 1.0

- **S**ingle Responsibility: each service, prefetcher, and view model has one job. `BattleViewModel` is a thin conductor: cue timing delegated to `BattleAnimator`, AI move history to `BattleAIDriver`, log rendering to `BattleLogFormatter`.
- **O**pen/Closed: the `APIService<Config>` generic + `Requestable` protocol lets new endpoints be added without modifying the network layer. New AI capabilities slot into `BattleAIServiceProtocol` without touching the views.
- **L**iskov Substitution: every service is reached through its protocol on `AppContainer`, so previews and tests can swap the concrete actor for any conforming type without touching call sites.
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
| `BattleAIService`          | `actor`                    | Owns the `LanguageModelClient`, called from any context      |
| `SpriteLoader`             | `actor`                    | Image download + `URLCache` access                           |
| `ImageColorAnalyzer`       | `actor`                    | Pixel-scan pipeline, off the main thread                     |
| `AudioPlayer`              | `actor`                    | AVFoundation playback                                        |
| `EvolutionService`         | `actor`                    | Process-wide chain-id memo                                   |
| `DataStorageReader`        | `@ModelActor`              | Isolated SwiftData `ModelContext`                             |
| `APIService<Config>`       | `actor`                    | Generic network actor over `Requestable`                     |
| `BattleAnimator`           | `@MainActor @Observable`   | Owns cue mutation + `withAnimation` blocks for the arena     |
| View models                | `@MainActor @Observable`   | SwiftUI binding                                              |

The type chart lives in PokeBattleKit as a `Sendable` value type (`TypeChart`), initialized once at app launch via `PokeBattleKit.initialize()`. Views and AI read it through `PokeBattleKit.typeChart` with zero actor hops. `BattleEngine` is also a plain `Sendable` struct in PokeBattleKit, used on the main actor inside `BattleViewModel` but not isolated itself.

## Dependency injection

A single `AppContainer` is the composition root. Every service, prefetcher, and long-lived worker is constructed there and handed to the view tree through one environment key:

```swift
@MainActor
final class AppContainer {
    let pokemonService:     PokemonServiceProtocol
    let evolutionService:   EvolutionServiceProtocol
    let itemService:        ItemServiceProtocol
    let battleAI:           BattleAIServiceProtocol
    let spriteLoader:       SpriteLoading
    let imageColorAnalyzer: ImageColorAnalyzing
    let audioPlayer:        AudioPlaying
    static let live = AppContainer()
}

@Environment(\.container) private var container
```

Tests and previews swap in a custom container with mocks; the rest of the app is unaware.

## Storage

Three top-level `@Model` types, each deduped on a unique key. Nested rows (stats, abilities, sprites, etc.) live under their parent and ride on cascade delete.

- `Pokemon` (id-unique): full hydrated detail, stats, sprites, moves, species fields, bookmark flag
- `ItemData` (title-keyed): item catalogue bucketed by category title
- `EvolutionChainEntity` (chainId-unique): evolution chain rows keyed by chain id

Move and type effectiveness data are owned by PokeBattleKit, which caches them as JSON files on disk via its own `DiskCache`. The pokedex grid renders from `Pokemon` rows; full hydration runs once at app launch and is cached forever, since Pokemon data is immutable.

---

# Battle System ⚔️

The battle screen is a turn-based 1v1 simulator built on top of the real PokeAPI move and type data. Both sides commit to 4 hand-picked moves before the fight starts, then trade turns until one side faints. The Gen-V damage formula drives every hit (level 50, STAB, type effectiveness, crit roll, accuracy roll, burn penalty), and status effects (paralysis, burn, poison) tick at end-of-turn.

The opponent is driven entirely by **Apple's `FoundationModels` framework**, running fully on-device.

## What the AI does

PokedexUI uses `SystemLanguageModel.default` with **structured generation** (`@Generable`) and **tool use** (`Tool` protocol) for three decisions:

1. **Opponent picking** ("Smart pick" button in the picker sheet)
   The model receives the player's name, types, and BST plus a shuffled roster of up to 50 pre-filtered candidates with matchup annotations. It returns a structured `OpponentPickResult` with the chosen index.
2. **Loadout selection** (background task during the loadout screen)
   The model receives both combatants' typings and a shortlisted move pool. It can call `checkTypeEffectiveness` and `estimateDamage` tools to reason about coverage before returning a `LoadoutPickResult` with four move names.
3. **Per-turn move selection** (every time the player commits a move)
   The model receives both combatants' current HP, status, types, and the opponent's four moves. It can call `estimateDamage` to compare options and detect KOs, then returns a `MovePickResult` with the chosen move name.

Every call degrades gracefully to deterministic heuristics (in [PokeBattleKit](https://github.com/brillcp/PokeBattleKit)) if Apple Intelligence is unavailable, the session is busy, or the model returns an unresolvable result. **The battle UI never blocks waiting on a model response.**

## Structured generation and tools

Each AI decision uses `@Generable` structs for type-safe output instead of free-text parsing. The model returns typed results (`MovePickResult`, `LoadoutPickResult`, `OpponentPickResult`) that resolve directly to game objects by name or index lookup.

Two `Tool` conformances give the model access to game data it can't derive from training:

- **`CheckTypeTool`**: wraps the type chart to report effectiveness multipliers for any attacking type vs defending types.
- **`EstimateDamageTool`**: wraps the Gen-V damage calculator to return estimated damage, defender HP, and whether the hit would KO.

System instructions live in [`PokedexUI/Features/Battle/AI/LLMInstructions/`](PokedexUI/Features/Battle/AI/LLMInstructions/), split per task. Each is a single short paragraph guiding tool usage and tactical priorities.

## Deterministic strategy layer

The scoring, filtering, and post-pick correction logic lives in [PokeBattleKit](https://github.com/brillcp/PokeBattleKit) as pure deterministic code with no LLM dependency:

- **`MoveScoring`**: in-battle and loadout scoring with STAB, type effectiveness, priority, and escalating recency penalties to prevent move spamming.
- **`MoveStrategy`**: heuristic fallback pick and post-pick adjustments (immune repair, phase-aware switching, KO override, status redundancy).
- **`LoadoutStrategy`**: shortlisting, heuristic 4-move selection, fill (pad LLM partial picks to 4), and mild fairness handicapping.
- **`OpponentStrategy`**: BST-tolerant pool filtering, mutual-threat scoring, and heuristic best-opponent ranking.

Every `BattleAIService` method follows the same shape: PokeBattleKit computes a heuristic fallback, the LLM attempts a smarter pick via structured generation with tools, then PokeBattleKit runs post-pick corrections on whichever branch won.

## Tuning the AI

All scoring weights live in `MoveScoring.Weights` inside PokeBattleKit. They're public static properties, so you can read (and fork) them to experiment with AI behavior:

| Weight group | What it controls | Examples |
| --- | --- | --- |
| **Damage** | How much the AI values raw damage, KO potential, resisted hits | `koBonus` (55), `nearKOBonus` (18), `resistedMult` (0.4) |
| **Status** | Value of inflicting paralysis, burn, poison, sleep | `paralysisFaster` (28), `burnPhysical` (24), `sleep` (22) |
| **Stat changes** | Boost/debuff desirability based on matchup context | `statBoostMatching` (10), `statBoostSpeedSlow` (16) |
| **Recency** | Escalating penalties for repeating the same move | `repeatFirst` (18), `repeatSecond` (40), `repeatThird` (65) |
| **Low HP** | Survival instinct: healing and priority at low health | `lowHPHealBonus` (35), `lowHPPriorityBonus` (6) |

Raising `koBonus` makes the AI more aggressive. Lowering the recency penalties lets it spam its best move. Bumping `lowHPHealBonus` makes it play safer when hurt. The heuristic fallback and LLM post-pick adjustments both flow through these weights, so a single change affects both code paths.

## Why on-device?

- **Zero latency to the network**: every inference happens locally.
- **Free**: no API tokens, no rate limits.
- **Private**: battle state never leaves the device.
- **Available offline**: the app stays playable once the PokeAPI data is cached.

This is the kind of feature `FoundationModels` was built for: small, structured, latency-sensitive decisions on top of well-defined data.

---

# Data loading 📥

Background workers fill the on-disk cache at app launch so the UI never waits on the network.

| Worker                  | What it pulls                             | When             |
| ----------------------- | ----------------------------------------- | ---------------- |
| `PokeBattleKit`         | Type chart (18 type damage relations) + full move catalogue | App launch via `PokeBattleKit.initialize()` |
| `PokemonService`        | Full pokedex hydration (detail + species)  | App launch       |
| `EvolutionService`      | Evolution chains for hydrated pokemon     | App launch, background priority |

Sprite colors are resolved lazily on first display through `ImageColorAnalyzer` (an actor) and cached in-process by pokemon id, so a detail view that opens the same pokemon twice runs the pixel scan once. The pokedex grid pulls the full `/pokemon?limit=1150` index in a single request, then fans out detail + species fetches concurrently with progress ticks. Subsequent app launches read everything from SwiftData with zero network calls.

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
   │ • AI picks opponent's 4 from full movepool (background task)
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

The battle screen never holds the loadout sheet open: every preflight task either completes before the player commits, or runs lazily inside the battle view itself. The move grid is disabled while the AI resolves the opponent's pick so the player can't double-tap into a stale turn.

---

# Design System 🎨

Pixel font, gameboy-style aesthetic, glass effects:

- **`Chip`**: small inline pill used for type tags, generation badges, status pills, effectiveness markers. Always a 4-point corner radius (capsules look too modern next to the pixel font).
- **`MoveCell`**: shared between the battle move grid and the loadout move picker, switched via a `Mode` enum.
- **`TypeColor`**: centralized type → color map used by every move chip, type tag, and weakness grid row.
- **`PokedexGridView`**: 2-column or 3-column grid of `Pokemon` rows used by the pokedex, search, and bookmarks tabs.

---

# Dependencies 🔗

| Package | What it does |
| --- | --- |
| [Networking](https://github.com/brillcp/Networking) | Thin actor-based `URLSession` wrapper with a generic `Requestable` protocol driving every PokeAPI endpoint |
| [PokeBattleKit](https://github.com/brillcp/PokeBattleKit) | Standalone battle engine: damage calculator, type chart, move/combatant models, and deterministic AI strategies (scoring, heuristics, adjustments) |

```swift
dependencies: [
    .package(url: "https://github.com/brillcp/Networking.git", .upToNextMajor(from: "0.10.0")),
    .package(url: "https://github.com/brillcp/PokeBattleKit.git", .upToNextMinor(from: "0.1.1"))
]
```

---

# Requirements ❗️

- Xcode 26+
- iOS 26+ (for the `FoundationModels` framework, `@Observable`, SwiftData)
- Swift 5 language mode
- Apple Intelligence enabled on the device for the AI features (graceful fallback to deterministic heuristics on devices without it)
