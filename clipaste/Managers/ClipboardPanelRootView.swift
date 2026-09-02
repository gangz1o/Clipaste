import AppKit
import SwiftUI
import SwiftData

struct ClipboardPanelRootView: View {
    @EnvironmentObject private var preferencesStore: AppPreferencesStore
    @Environment(ClipboardRuntimeStore.self) private var runtimeStore
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .auto
    @State private var viewModel = ClipboardViewModel()

    var body: some View {
        ClipboardMainView(viewModel: viewModel)
            .environmentObject(preferencesStore)
            .environment(runtimeStore)
            .modelContainer(runtimeStore.container)
            .id("\(runtimeStore.rootIdentity)-\(appLanguage.rawValue)")
            .environment(\.locale, appLanguage.resolvedLocale)
    }
}
