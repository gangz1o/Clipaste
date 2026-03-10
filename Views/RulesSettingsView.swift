import SwiftUI

struct RulesSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var selection: Set<ExcludedApp.ID> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("不要记录以下应用的剪贴板内容：")
                .font(.headline)
            
            List(selection: $selection) {
                ForEach(viewModel.excludedApps) { app in
                    HStack {
                        if let iconData = app.iconData, let nsImage = NSImage(data: iconData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "app.dashed")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(app.name)
                            .font(.body)
                    }
                    .tag(app.id) // Needed for selection to work correctly
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 150)
            
            HStack {
                Button(action: {
                    viewModel.addExcludedApp()
                }) {
                    Image(systemName: "plus")
                    Text("添加应用")
                }
                
                Button(action: {
                    // Extract IndexSet from the selected UUIDs
                    let indexes = viewModel.excludedApps.enumerated()
                        .filter { selection.contains($0.element.id) }
                        .map { $0.offset }
                    
                    viewModel.removeExcludedApp(at: IndexSet(indexes))
                    selection.removeAll()
                }) {
                    Image(systemName: "minus")
                    Text("移除")
                }
                .disabled(selection.isEmpty)
                
                Spacer()
            }
            .padding(.top, 5)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    RulesSettingsView()
        .environmentObject(SettingsViewModel())
}
