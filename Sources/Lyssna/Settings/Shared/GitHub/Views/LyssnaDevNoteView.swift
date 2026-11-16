import SwiftUI

struct LyssnaDevNoteView: View {
    @State private var noteText: String?
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    
    var body: some View {
        NavigationView {
            contentView
                .navigationTitle("developer_note".localized)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button {
                        WindowHelper.shared.dismissCurrentViewController()
                    } label: {
                        Text("Done".uiKitLocalized)
                            .font(.headline)
                    }
                }
                .onAppear {
                    loadDevNote()
                }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if isLoading {
            ProgressView("Loading".uiKitLocalized)
        } else if let error = errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text("Failed to load developer note")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Retry") {
                    isLoading = true
                    errorMessage = nil
                    loadDevNote()
                }
            }
        } else if let text = noteText {
            ScrollView {
                Text(text)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("No developer note found")
                .foregroundColor(.gray)
        }
    }
    
    private func loadDevNote() {
        if let url = BundleHelper.shared.resourceURL("DeveloperNote", extension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            noteText = text
        } else {
            noteText = "Lyssna for iOS. Personal builds with custom lyrics, playback controls, and AirPlay receiver labels."
        }
        isLoading = false
    }
}
