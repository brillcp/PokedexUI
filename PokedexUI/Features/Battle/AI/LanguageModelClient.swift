import Foundation
import FoundationModels

/// Owns the on-device Foundation Models session, generation retries, and
/// per-decision instruction text. Concurrent calls into `generate(...)`
/// are serialised via an internal slot mutex so the underlying model
/// is never asked to produce two responses at once.
actor LanguageModelClient {
    private let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    private var isGenerating = false
    private let maxAttempts: Int

    var isAvailable: Bool {
        if case .available = model.availability { return true }
        return false
    }

    init(maxAttempts: Int = 3) {
        self.maxAttempts = maxAttempts
    }
}

// MARK: - Structured Generation

extension LanguageModelClient {

    /// Generate a structured result using @Generable with optional tools.
    func generate<T: Generable>(
        prompt: String,
        generating type: T.Type,
        tools: [any Tool],
        temperature: Double,
        instructions: Instructions
    ) async throws -> T {
        var lastError: Error?
        for _ in 1 ... maxAttempts {
            await waitForGenerationSlot()
            do {
                defer { isGenerating = false }
                let session = LanguageModelSession(model: model, tools: tools, instructions: instructions.text)
                return try await session.respond(
                    to: prompt,
                    generating: type,
                    options: .init(temperature: temperature)
                ).content
            } catch {
                isGenerating = false
                lastError = error
            }
        }
        throw lastError ?? CancellationError()
    }

    /// Structured decision: tries @Generable generation with tools,
    /// falls back to heuristic if the model is unavailable or fails.
    func decide<Pick, Result: Generable>(
        fallback: Pick,
        prompt: @autoclosure () -> String,
        generating type: Result.Type,
        tools: [any Tool],
        temperature: Double,
        instructions: Instructions,
        resolve: (Result) -> Pick?,
        adjust: (Pick) -> Pick
    ) async -> Pick {
        guard isAvailable else {
            aiLog("LLM unavailable, using heuristic fallback")
            return adjust(fallback)
        }
        do {
            let promptText = prompt()
            aiLog("PROMPT:\n\(promptText)")
            let result = try await generate(
                prompt: promptText, generating: type, tools: tools,
                temperature: temperature, instructions: instructions
            )
            aiLog("LLM RESULT: \(result)")
            if let pick = resolve(result) {
                let adjusted = adjust(pick)
                aiLog("LLM pick accepted")
                return adjusted
            }
            aiLog("LLM resolve failed, using fallback")
        } catch {
            aiLog("LLM error: \(error), using fallback")
        }
        return adjust(fallback)
    }
}

// MARK: - Instructions

extension LanguageModelClient {
    /// Wraps an instruction blob loaded from the app bundle, with a
    /// hard-coded fallback when the resource file is missing.
    struct Instructions: Sendable {
        let text: String

        static let move = Instructions(
            resource: "BattleAIMoveInstructions",
            fallback: "You are an expert Pokemon battler. Use the tools to check type effectiveness and estimate damage before picking a move."
        )
        static let opponent = Instructions(
            resource: "BattleAIOpponentInstructions",
            fallback: "You are a Pokemon battle matchmaker. Pick a fair and interesting opponent."
        )
        static let loadout = Instructions(
            resource: "BattleAILoadoutInstructions",
            fallback: "You are an expert Pokemon battler picking a loadout. Use tools to evaluate type matchups. Pick 4 moves with good coverage."
        )

        private init(resource: String, fallback: String) {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "md"),
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else {
                self.text = fallback
                return
            }
            self.text = text
        }
    }
}

// MARK: - Private
private extension LanguageModelClient {
    func waitForGenerationSlot() async {
        while isGenerating {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        isGenerating = true
    }
}
