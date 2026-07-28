import Foundation

/// ChatGPT Credits rate card published by OpenAI.
///
/// Rates are credits per one million tokens. The subscription's remaining
/// percentage still comes from `account/rateLimits/read`; this calculator is
/// only for attributing local token activity to the same Credits unit.
enum OpenAIChatGPTCreditCalculator {
    struct Rate: Sendable, Equatable {
        let input: Double
        let cachedInput: Double
        let output: Double
    }

    static func rate(for model: String) -> Rate? {
        let value = model.lowercased()
        if value.contains("gpt-5.6-sol") { return Rate(input: 125, cachedInput: 12.5, output: 750) }
        if value.contains("gpt-5.6-terra") { return Rate(input: 62.5, cachedInput: 6.25, output: 375) }
        if value.contains("gpt-5.6-luna") { return Rate(input: 25, cachedInput: 2.5, output: 150) }
        if value.contains("gpt-5.5") { return Rate(input: 125, cachedInput: 12.5, output: 750) }
        if value.contains("gpt-5.4-mini") || value.contains("gpt-5.4 mini") {
            return Rate(input: 18.75, cachedInput: 1.875, output: 113)
        }
        if value.contains("gpt-5.4") { return Rate(input: 62.5, cachedInput: 6.25, output: 375) }
        return nil
    }

    static func credits(
        uncachedInputTokens: Int64,
        cachedInputTokens: Int64,
        outputTokens: Int64,
        model: String,
        serviceTier: String?
    ) -> Double? {
        guard let rate = rate(for: model) else { return nil }
        let base = (
            Double(max(0, uncachedInputTokens)) * rate.input
                + Double(max(0, cachedInputTokens)) * rate.cachedInput
                + Double(max(0, outputTokens)) * rate.output
        ) / 1_000_000
        return base * speedMultiplier(model: model, serviceTier: serviceTier)
    }

    private static func speedMultiplier(model: String, serviceTier: String?) -> Double {
        guard serviceTier?.lowercased() == "fast" else { return 1 }
        let value = model.lowercased()
        if value.contains("gpt-5.6") || value.contains("gpt-5.5") { return 2.5 }
        if value.contains("gpt-5.4") { return 2 }
        return 1
    }
}
