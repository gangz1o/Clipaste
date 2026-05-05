import SwiftUI

struct AIProviderIconView: View {
    let configuration: AIConfiguration
    var size: CGFloat = 14

    var body: some View {
        if let assetName = configuration.providerIconAssetName {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: size, weight: .regular))
                .frame(width: size, height: size)
        }
    }
}
