import SwiftUI

@main
struct OnDeviceAISampleApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

/// Three tabs, one per experiment. Launch arguments pick a tab and auto-run it
/// so the simulator can be screenshotted without tapping:  -tab triage -autorun
struct RootView: View {
    @State private var tab: Screen = Screen(rawValue: LaunchArguments.value("-tab") ?? "") ?? .status

    enum Screen: String { case status, triage, notice }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Status", systemImage: "cpu", value: .status) { AvailabilityView() }
            Tab("Triage", systemImage: "tray.full", value: .triage) { TriageView() }
            Tab("Notice", systemImage: "doc.text.viewfinder", value: .notice) { NoticeView() }
        }
    }
}

enum LaunchArguments {
    static func value(_ flag: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    static var autorun: Bool { CommandLine.arguments.contains("-autorun") }
}
