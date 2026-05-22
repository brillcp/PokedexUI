# Battle AI

On-device AI that picks moves, loadouts, and opponents for the bot side of
a battle. The LLM is a sprinkle on top of a deterministic heuristic, not the
core decision-maker — the game plays fine with the model unavailable.

## Architecture

Three decisions, each with the same shape:

| Decision | File | What it picks |
|---|---|---|
| In-battle move | `MoveAI.swift` | One of the AI's 4 moves each turn |
| Opponent | `OpponentAI.swift` | A Pokemon to face the player |
| Pre-battle loadout | `LoadoutAI.swift` | 4 moves from the AI's full pool |

Each per-decision file contains:

1. **Strategy** — deterministic heuristic fallback + post-pick corrections.
   Always runs.
2. **Prompt** — builds the LLM prompt and parses the model's reply.

The orchestrator `BattleAIService.swift` glues the two together via
`LanguageModelClient.decide(...)`: heuristic produces a fallback, prompt
runs the LLM, `Strategy.adjust` corrects the result. If the LLM is
unavailable or replies with junk, the adjusted heuristic fallback is
returned.

## Files

```
AI/
  BattleAIService.swift           ← protocol + actor façade
  LanguageModelClient.swift       ← Foundation Models wrapper + decide<T>
  MoveAI.swift                    ← MoveStrategy + MoveScoring + MovePrompt
  OpponentAI.swift                ← OpponentStrategy + OpponentPrompt
  LoadoutAI.swift                 ← LoadoutStrategy + LoadoutPrompt
  BattleContext.swift             ← shared MoveRow renderer + battle context
  OpponentCandidateSnapshot.swift ← Sendable Pokemon DTO for opponent pick
  LLMInstructions/                ← instruction .md files loaded at runtime
```

`BattleKit` (separate Swift package) owns the damage formula, type
effectiveness, status, and stat-stage mechanics. The AI module only does
strategy on top.

## Scoring weights

All heuristic scoring weights live in `MoveScoring.Weights` (in
`MoveAI.swift`) as a single named-constants block. Tune the AI by editing
that block, not by hunting magic numbers.

## How to add a new decision type

1. Add a new `*.swift` file alongside the existing AI files.
2. Mirror the Strategy + Prompt shape inside it.
3. Add a method to `BattleAIServiceProtocol`.
4. Implement using `client.decide(...)`.
