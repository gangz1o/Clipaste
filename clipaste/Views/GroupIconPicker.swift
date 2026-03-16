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
    @Binding var selectedIcon: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = IconPickerViewModel()
    @State private var selectedCategoryIndex: Int = 0

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
                        vm.searchQuery = ""
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

            // ── Category tabs (hidden while searching) ──
            if !vm.isSearching {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(vm.categories.indices, id: \.self) { index in
                            let cat = vm.categories[index]
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedCategoryIndex = index
                                }
                            } label: {
                                Text(cat.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .foregroundStyle(selectedCategoryIndex == index ? .white : .primary)
                                    .background(
                                        Capsule()
                                            .fill(selectedCategoryIndex == index
                                                  ? Color.accentColor
                                                  : Color(nsColor: .controlBackgroundColor))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            } else {
                Spacer()
                    .frame(height: 8)
            }

            Divider()

            // ── Icon grid ──
            let displayedIcons = vm.isSearching
                ? vm.searchResults
                : vm.categories[selectedCategoryIndex].icons

            if displayedIcons.isEmpty {
                VStack(spacing: 10) {
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
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(displayedIcons) { item in
                            iconCell(item)
                        }
                    }
                    .padding(14)
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
            VStack(spacing: 0) {
                IconItemView(item: item, size: 22)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 52, height: 44)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor
                          : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.primary.opacity(0.06), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.displayName)
    }
}

// MARK: - Preview

#Preview {
    GroupIconPicker(selectedIcon: .constant("folder"))
}
