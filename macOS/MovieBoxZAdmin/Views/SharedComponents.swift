//
//  SharedComponents.swift
//  MovieBoxZAdmin
//
//  Shared UI components used across multiple views
//

import SwiftUI

// MARK: - Status Badge
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let label: String
    let value: String
    let labelWidth: CGFloat
    let showColon: Bool

    init(label: String, value: String, labelWidth: CGFloat = 100, showColon: Bool = false) {
        self.label = label
        self.value = value
        self.labelWidth = labelWidth
        self.showColon = showColon
    }

    var body: some View {
        HStack {
            Text(showColon ? "\(label):" : label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .font(.body)
            Spacer()
        }
    }
}
