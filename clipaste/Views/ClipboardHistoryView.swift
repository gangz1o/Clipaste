import SwiftUI
import SwiftData

struct ClipboardHistoryView: View {
    var body: some View {
        ClipboardMainView()
            .environmentObject(ClipboardRuntimeStore.shared)
            .modelContainer(ClipboardRuntimeStore.shared.container)
            .id(ClipboardRuntimeStore.shared.rootIdentity)
    }
}

// Helper wrapper for NSVisualEffectView to get the correct background blur
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

#Preview {
    ClipboardHistoryView()
}
