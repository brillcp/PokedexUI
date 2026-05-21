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

    init(maxAttempts: Int = 3) {
        self.maxAttempts = maxAttempts
    }

    var isAvailable: Bool {
        if case .available = model.availability { return true }
        return false
    }

    func generate(
        label: String,
        prompt: String,
        temperature: Double,
        instructions: Instructions
    ) async throws -> String {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            await waitForGenerationSlot()
            do {
                defer { isGenerating = false }
                let session = LanguageModelSession(model: model, instructions: instructions.text)
                let response = try await session.respond(to: prompt, options: .init(temperature: temperature)).content
                if attempt > 1 { print("[llm] \(label): retry \(attempt) succeeded") }
                return response
            } catch {
                isGenerating = false
                lastError = error
            }
        }
        throw lastError ?? CancellationError()
    }
}

// MARK: - Instructions

extension LanguageModelClient {
    /// Wraps an instruction blob loaded from the app bundle, with a
    /// hard-coded fallback when the resource file is missing.
    struct Instructions: Sendable {
        let text: String

        static let move = Instructions(resource: "BattleAIMoveInstructions",
                                       fallback: "You are an expert Pokemon battler.")
        static let opponent = Instructions(resource: "BattleAIOpponentInstructions",
                                           fallback: "You are a Pokemon battle matchmaker.")
        static let loadout = Instructions(resource: "BattleAILoadoutInstructions",
                                          fallback: "You are an expert Pokemon battler picking a loadout.")

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
