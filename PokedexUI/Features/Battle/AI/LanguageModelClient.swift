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

extension LanguageModelClient {
    func generate(
        prompt: String,
        temperature: Double,
        instructions: Instructions
    ) async throws -> String {
        var lastError: Error?
        for _ in 1 ... maxAttempts {
            await waitForGenerationSlot()
            do {
                defer { isGenerating = false }
                let session = LanguageModelSession(model: model, instructions: instructions.text)
                return try await session.respond(to: prompt, options: .init(temperature: temperature)).content
            } catch {
                isGenerating = false
                lastError = error
            }
        }
        throw lastError ?? CancellationError()
    }

    /// Run one battle decision: returns the adjusted fallback if the model
    /// is unavailable or the generation/parse cycle fails; otherwise
    /// returns the adjusted LLM pick. `adjust` runs against both branches
    /// so post-pick corrections always apply.
    func decide<Pick>(
        fallback: Pick,
        prompt: @autoclosure () -> String,
        temperature: Double,
        instructions: Instructions,
        parse: (String) -> Pick?,
        adjust: (Pick) -> Pick
    ) async -> Pick {
        guard isAvailable else { return adjust(fallback) }
        do {
            let raw = try await generate(prompt: prompt(), temperature: temperature, instructions: instructions)
            if let pick = parse(raw) { return adjust(pick) }
        } catch {}
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
            fallback: "You are an expert Pokemon battler."
        )
        static let opponent = Instructions(
            resource: "BattleAIOpponentInstructions",
            fallback: "You are a Pokemon battle matchmaker."
        )
        static let loadout = Instructions(
            resource: "BattleAILoadoutInstructions",
            fallback: "You are an expert Pokemon battler picking a loadout."
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
