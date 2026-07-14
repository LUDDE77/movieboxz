import SwiftUI

// MARK: - Top Bar Pills
// Custom tab navigation for tvOS (Segmented Control doesn't work on tvOS)
// Also works on iOS for consistent design

struct TopBarPills<SelectionValue: Hashable & CaseIterable & RawRepresentable>: View where SelectionValue.RawValue == String {
    @Binding var selection: SelectionValue
    @FocusState private var focusedOption: SelectionValue?
    @Namespace private var animation

    // Platform-specific sizes
    #if os(tvOS)
    private let fontSize: CGFloat = 31
    private let pillHeight: CGFloat = 60
    private let horizontalPadding: CGFloat = 30
    private let verticalPadding: CGFloat = 15
    private let spacing: CGFloat = 40
    #else
    private let fontSize: CGFloat = 16
    private let pillHeight: CGFloat = 44
    private let horizontalPadding: CGFloat = 20
    private let verticalPadding: CGFloat = 10
    private let spacing: CGFloat = 20
    #endif

    var body: some View {
        #if os(tvOS)
        // tvOS: Horizontal pills with focus engine
        HStack(spacing: spacing) {
            ForEach(Array(SelectionValue.allCases), id: \.self) { option in
                pillButton(for: option)
                    .focused($focusedOption, equals: option)
            }
        }
        .focusSection()
        .onChange(of: focusedOption) { oldValue, newValue in
            if let newValue = newValue {
                selection = newValue
            }
        }
        #else
        // iOS: Horizontal pills with tap interaction
        HStack(spacing: spacing) {
            ForEach(Array(SelectionValue.allCases), id: \.self) { option in
                pillButton(for: option)
            }
        }
        #endif
    }

    @ViewBuilder
    private func pillButton(for option: SelectionValue) -> some View {
        let isSelected = selection == option

        #if os(tvOS)
        let isFocusedHere = focusedOption == option

        Button {
            selection = option
        } label: {
            Text(option.rawValue)
                .font(.system(size: fontSize, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? .mbzGold : .mbzMuted)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.mbzGold.opacity(0.18))
                            .matchedGeometryEffect(id: "pill", in: animation)
                    }
                }
                .scaleEffect(isFocusedHere ? 1.1 : 1.0)
                .brightness(isFocusedHere ? 0.15 : 0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocusedHere)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        #else
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selection = option
            }
        } label: {
            Text(option.rawValue)
                .font(.system(size: fontSize, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? .mbzGold : .mbzMuted)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.mbzGold.opacity(0.18))
                            .matchedGeometryEffect(id: "pill", in: animation)
                    }
                }
        }
        .buttonStyle(.plain)
        #endif
    }
}

// MARK: - Preview

enum PreviewTab: String, CaseIterable {
    case myList = "My List"
    case watched = "Watched"
}

#Preview("tvOS Style") {
    struct PreviewWrapper: View {
        @State private var selection: PreviewTab = .myList

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 40) {
                    TopBarPills(selection: $selection)

                    Text("Selected: \(selection.rawValue)")
                        .font(.title)
                        .foregroundColor(.white)

                    Spacer()
                }
                .padding(.top, 100)
            }
        }
    }

    return PreviewWrapper()
        .preferredColorScheme(.dark)
}
