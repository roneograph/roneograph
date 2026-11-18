import ScannerKit
import SwiftUI

/// The file name as labeled parts: green for what the name gives, gray for what the format adds.
struct FileNameParts: View {
    let segments: [FileNameSegment]

    var body: some View {
        FlowLayout {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                part(segment)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segments.map(\.text).joined())
    }

    @ViewBuilder
    private func part(_ segment: FileNameSegment) -> some View {
        VStack(spacing: 2) {
            switch segment.source {
            case .text:
                Text(segment.text == " " ? "\u{00A0}" : segment.text).font(.callout.monospaced()).foregroundStyle(.secondary)
                Text(" ").font(.caption2)
            case .name where segment.text.isEmpty:
                Text("nothing to add")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.tint, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])))
                label(segment.source)
            default:
                Text(segment.text)
                    .font(.callout.monospaced())
                    .foregroundStyle(segment.source == .name ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(segment.source == .name ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.fill.tertiary), in: RoundedRectangle(cornerRadius: 4))
                label(segment.source)
            }
        }
    }

    private func label(_ source: FileNameSegment.Source) -> some View {
        Text(source.title)
            .font(.caption2.weight(source == .name ? .semibold : .regular))
            .textCase(.uppercase)
            .foregroundStyle(source == .name ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }
}

private extension FileNameSegment.Source {
    var title: String {
        switch self {
        case .name: "name"
        case .date: "date"
        case .category: "category"
        case .issuer: "issuer"
        case .number: "number"
        case .text: ""
        }
    }
}
