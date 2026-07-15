import SwiftUI

// MARK: - Legal Document View
// Reusable, full-screen readable document used to present the Terms of Service
// and Privacy Policy verbatim from LegalContent. Presented as a .sheet on iOS
// and a .fullScreenCover on tvOS.

struct LegalDocumentView: View {
    let title: String
    let text: String

    @Environment(\.dismiss) private var dismiss
    @FocusState private var scrollFocused: Bool

    #if os(tvOS)
    private let edgePadding: CGFloat = 80
    private let titleSize: CGFloat = 56
    private let bodySize: CGFloat = 30
    private let lineSpacing: CGFloat = 12
    #else
    private let edgePadding: CGFloat = 20
    private let titleSize: CGFloat = 30
    private let bodySize: CGFloat = 17
    private let lineSpacing: CGFloat = 6
    #endif

    init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    var body: some View {
        ZStack {
            Color.mbzInk.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header: close button + title
                HStack(alignment: .center, spacing: 16) {
                    Text(title)
                        .font(.system(size: titleSize, weight: .heavy))
                        .foregroundColor(.mbzGold)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        #if os(tvOS)
                        HStack(spacing: 10) {
                            Image(systemName: "xmark")
                            Text("Done")
                        }
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.mbzScreen)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        #else
                        Text("Done")
                            .font(.headline)
                            .foregroundColor(.mbzGold)
                        #endif
                    }
                    #if os(tvOS)
                    .buttonStyle(FocusBorderButtonStyle(variant: .utility(cornerRadius: 12)))
                    #endif
                }
                .padding(.horizontal, edgePadding)
                .padding(.top, edgePadding)
                .padding(.bottom, edgePadding * 0.5)

                // Scrollable document body
                ScrollView {
                    Text(text)
                        .font(.system(size: bodySize))
                        .lineSpacing(lineSpacing)
                        .foregroundColor(.mbzScreen)
                        .frame(maxWidth: 900, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, edgePadding)
                        .padding(.bottom, edgePadding)
                }
                #if os(tvOS)
                .focusable(true)
                .focused($scrollFocused)
                #endif
            }
        }
        #if os(tvOS)
        .onExitCommand {
            dismiss()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                scrollFocused = true
            }
        }
        #endif
    }
}

#Preview {
    LegalDocumentView(title: "Terms of Service", text: LegalContent.termsOfService)
        .preferredColorScheme(.dark)
}
