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
            case .text, .folderSeparator:
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
        case .text, .folderSeparator: ""
        }
    }
}

/// Lays out its views in rows, wrapping to the next row when one does not fit.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 1
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.reduce(0) { $0 + $1.width } + spacing * CGFloat(max($0.count - 1, 0)) }.max() ?? 0
        let height = rows.map { $0.map(\.height).max() ?? 0 }.reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        var index = 0
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for size in row {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
                index += 1
            }
            y += (row.map(\.height).max() ?? 0) + lineSpacing
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [[CGSize]] {
        var rows: [[CGSize]] = [[]]
        var x: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(size)
            x += size.width + spacing
        }
        return rows
    }
}
