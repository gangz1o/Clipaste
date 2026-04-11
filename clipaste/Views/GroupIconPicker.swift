import SwiftUI

// MARK: - Icon Render Helper (View Layer render engine)

/// Renders an IconItem correctly regardless of whether it is a SF Symbol or a local asset.
struct IconItemView: View {
    let item: IconItem
    var size: CGFloat = 22

    @ViewBuilder
    var body: some View {
        if item.type == .system {
            Image(systemName: item.name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(item.name)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Main Picker

/// Grouped icon picker supporting both SF Symbols and local custom Assets.
struct GroupIconPicker: View {
    @Binding var selectedIcon: String?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = IconPickerViewModel()

    private let columns = [GridItem(.adaptive(minimum: 52), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──
            Text("Choose an Icon")
                .font(.headline)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // ── Search bar ──
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))

                TextField("Search icons…", text: $vm.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .autocorrectionDisabled()

                if !vm.searchQuery.isEmpty {
                    Button {
                        vm.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            Divider()

            // ── Icon grid ──
            if vm.displayedIcons.isEmpty {
                VStack(spacing: 10) {
                    clearIconButton

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.quaternary)
                    Text("No icons found")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        clearIconButton

                        ForEach(vm.displayedIcons) { item in
                            iconCell(item)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 300, height: 380)
    }

    // MARK: - Cell

    @ViewBuilder
    private func iconCell(_ item: IconItem) -> some View {
        let isSelected = selectedIcon == item.name

        Button {
            selectedIcon = item.name
            dismiss()
        } label: {
            IconItemView(item: item, size: 18)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle()) // ensure the hit target is still decent
        }
        .buttonStyle(.plain)
        .help(item.displayName)
    }

    private var clearIconButton: some View {
        let isSelected = selectedIcon == nil

        return Button {
            selectedIcon = nil
            dismiss()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.18))
                    )

                Image(systemName: "square.dashed")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 32, height: 32)
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("No Icon")
    }
}

// MARK: - Preview

#Preview {
    GroupIconPicker(selectedIcon: .constant(nil))
}
