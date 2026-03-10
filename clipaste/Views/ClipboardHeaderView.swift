import SwiftUI

struct ClipboardHeaderView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    @FocusState var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // 左侧区域 (分组标签栏)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // “全部”标签
                    Button(action: {
                        viewModel.selectGroup(nil)
                    }) {
                        Text("全部")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .foregroundColor(viewModel.selectedGroupID == nil ? .white : .primary)
                            .background(
                                Group {
                                    if viewModel.selectedGroupID == nil {
                                        Color.accentColor
                                    } else {
                                        Color.clear.background(.regularMaterial)
                                    }
                                }
                            )
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)

                    // 遍历渲染各个分组标签
                    ForEach(viewModel.groups) { group in
                        Button(action: {
                            viewModel.selectGroup(group.id)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: group.iconName)
                                    .font(.system(size: 13))
                                Text(group.name)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .foregroundColor(viewModel.selectedGroupID == group.id ? .white : .primary)
                            .background(
                                Group {
                                    if viewModel.selectedGroupID == group.id {
                                        Color.accentColor
                                    } else {
                                        Color.clear.background(.regularMaterial)
                                    }
                                }
                            )
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                        }
                        .buttonStyle(.plain)
                    }

                    // 添加新分组按钮
                    Button(action: {
                        viewModel.addNewGroup()
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 28, height: 28)
                            .background(Color.clear.background(.regularMaterial))
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
            }

            Spacer()

            // 右侧区域 (精致搜索框)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("搜索剪贴板...", text: $viewModel.searchText)
                    .font(.system(size: 13))
                    .textFieldStyle(PlainTextFieldStyle())
                    .autocorrectionDisabled(true)
                    .disableAutocorrection(true)
                    .focused($isSearchFocused)

                if !viewModel.searchText.isEmpty {
                    Button(action: {
                        viewModel.searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .frame(width: 240)
            .background(Color.clear.background(.regularMaterial))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    let dummyViewModel = ClipboardViewModel(clipboardMonitor: nil)
    return ClipboardHeaderView(viewModel: dummyViewModel)
        .frame(width: 600)
}
