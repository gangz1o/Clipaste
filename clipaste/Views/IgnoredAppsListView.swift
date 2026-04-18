import SwiftUI

struct IgnoredAppsListView: View {
    let ignoredApps: [IgnoredAppItem]
    @Binding var selection: Set<String>

    var body: some View {
        ZStack {
            List(ignoredApps, selection: $selection) { ignoredApp in
                IgnoredAppRowView(ignoredApp: ignoredApp)
                    .tag(ignoredApp.bundleIdentifier)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)

            if ignoredApps.isEmpty {
                IgnoredAppsEmptyStateView()
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
