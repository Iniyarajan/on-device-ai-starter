import FoundationModels
import Observation

/// Everything an app should read before it shows an AI feature: availability, which model, how big a window.
/// This is the "handle unavailable first" rule from article 1, as a single observable object.
@Observable
@MainActor
final class ModelStatus {
    enum State: Equatable {
        case checking
        case available(variant: String, contextTokens: Int, capabilities: [String])
        case unavailable(reason: String, advice: String)
    }

    private(set) var state: State = .checking
    private(set) var cloud: String = "…"

    func refresh() {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            var caps: [String] = ["typed output", "tool calling"]   // guaranteed since iOS 26
            var variant = "Apple on-device model (iOS 26)"
            if #available(iOS 27.0, *) {
                caps = []
                if model.capabilities.contains(.guidedGeneration) { caps.append("typed output") }
                if model.capabilities.contains(.toolCalling) { caps.append("tool calling") }
                if model.capabilities.contains(.vision) { caps.append("image input") }
                if model.capabilities.contains(.reasoning) { caps.append("reasoning") }
                variant = model.variant.displayName
            }
            state = .available(variant: variant, contextTokens: model.contextSize, capabilities: caps)
        case .unavailable(let reason):
            state = .unavailable(reason: "\(reason)", advice: Self.advice(for: reason))
        }
        if #available(iOS 27.0, *) {
            let pcc = PrivateCloudComputeLanguageModel()
            cloud = pcc.isAvailable
                ? "available · reasoning: \(pcc.capabilities.contains(.reasoning)) · quota ok: \(!pcc.quotaUsage.isLimitReached) · needs the private-cloud-compute entitlement to call"
                : "unavailable (\(pcc.availability))"
        } else {
            cloud = "requires iOS 27"
        }
    }

    private static func advice(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: return "This device can't run Apple Intelligence. Route to a server model or hide the feature."
        case .appleIntelligenceNotEnabled: return "Ask the user to turn on Apple Intelligence in Settings, then retry."
        case .modelNotReady: return "The model is still downloading. Retry in a minute; don't block the UI."
        @unknown default: return "Unknown reason. Treat as unavailable."
        }
    }
}
