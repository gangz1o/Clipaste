import SwiftUI

struct GroupIconView: View {
    let iconName: String?
    var size: CGFloat = 14

    var body: some View {
        if let iconName = ClipboardGroupIconName.normalize(iconName) {
            if IconPickerViewModel.customIconNames.contains(iconName) {
                Image(iconName)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            }
        }
    }
}

struct GroupMenuLabel: View {
    let title: String
    let iconName: String?

    var body: some View {
        HStack(spacing: 6) {
            GroupIconView(iconName: iconName, size: 13)
            Text(verbatim: title)
        }
    }
}
