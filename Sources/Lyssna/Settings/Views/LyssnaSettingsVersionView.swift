import SwiftUI

/// Personal builds retain their version label without advertising upstream releases.
struct LyssnaSettingsVersionView: View {
    @State private var isPresentingContributorsSheet = false

    var body: some View {
        Section {
            Button("\("contributors".localized)...") {
                isPresentingContributorsSheet = true
            }
            .foregroundColor(.gray)
            .font(.subheadline.weight(.semibold))
        } footer: {
            Text("Lyssna \(Lyssna.version)")
        }
        .sheet(isPresented: $isPresentingContributorsSheet) {
            LyssnaContributorsSheetView()
        }
    }
}
