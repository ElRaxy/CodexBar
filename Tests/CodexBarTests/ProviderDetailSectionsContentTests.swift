import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct ProviderDetailSectionsContentTests {
    @Test
    func `snapshot details flow into menu model without affecting empty snapshots`() throws {
        let details = try [Self.section(kind: .bars)]
        let populated = UsageMenuCardView.Model.make(Self.input(details: details))
        let empty = UsageMenuCardView.Model.make(Self.input(details: []))

        #expect(populated.providerDetails == details)
        #expect(populated.hasUsageContent)
        #expect(empty.providerDetails.isEmpty)
    }

    @Test(arguments: [ProviderDetailSection.Chart.Kind.bars, .line])
    func `generic detail renderer lays out rows and chart kinds`(kind: ProviderDetailSection.Chart.Kind) throws {
        let view = try ProviderDetailSectionsContent(sections: [Self.section(kind: kind)], chartColor: .blue)
        let size = NSHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: 280, height: CGFloat.greatestFiniteMagnitude))

        #expect(size.width > 0)
        #expect(size.height > 58)
    }

    @Test
    func `R27 standard layout stays pixel equivalent to the frozen legacy renderer`() throws {
        for (fixtureName, sections) in try Self.r27Fixtures() {
            for (appearance, highlighted) in Self.r27Appearances {
                let expected = try Self.renderedBitmap(
                    AnyView(R27LegacyProviderDetailSectionsContent(sections: sections, chartColor: .green)),
                    appearance: appearance,
                    highlighted: highlighted)
                let actual = try Self.renderedBitmap(
                    AnyView(ProviderDetailSectionsContent(
                        sections: sections,
                        chartColor: .green,
                        layout: .standard)),
                    appearance: appearance,
                    highlighted: highlighted)

                let context = "R27 \(fixtureName), \(appearance.rawValue), highlighted=\(highlighted)"
                #expect(actual.pointSize == expected.pointSize, "\(context): point size")
                #expect(actual.pixelsWide == expected.pixelsWide, "\(context): pixel width")
                #expect(actual.pixelsHigh == expected.pixelsHigh, "\(context): pixel height")
                #expect(actual.bytes.count == expected.bytes.count, "\(context): byte count")
                #expect(Self.differingByteCount(actual.bytes, expected.bytes) == 0, "\(context): pixel bytes")
            }
        }
    }

    @Test
    func `R27 plugin summary adds exact row padding and only between-row dividers`() throws {
        let row = try ProviderDetailSection.Row(label: "Today", value: "1.25M tokens")
        let secondRow = try ProviderDetailSection.Row(label: "Month", value: "18.4M tokens")
        let chart = try Self.chart(kind: .bars)
        let singleRow = try [ProviderDetailSection(rows: [row])]
        let titleAndRow = try [ProviderDetailSection(title: "Usage", rows: [row])]
        let twoRows = try [ProviderDetailSection(rows: [row, secondRow])]
        let chartWithoutRows = try [ProviderDetailSection(chart: chart)]
        let rowsAndChart = try [ProviderDetailSection(rows: [row, secondRow], chart: chart)]
        let multipleSections = try [
            ProviderDetailSection(title: "Current", rows: [row]),
            ProviderDetailSection(title: "History", rows: [row, secondRow], chart: chart),
        ]

        let singleRowDelta = Self.layoutHeightDelta(sections: singleRow)
        let twoRowDelta = Self.layoutHeightDelta(sections: twoRows)

        #expect(abs(singleRowDelta - 16) < 0.001)
        #expect(abs(twoRowDelta - 27) < 0.001)
        #expect(abs(Self.layoutHeightDelta(sections: titleAndRow) - singleRowDelta) < 0.001)
        #expect(abs(Self.layoutHeightDelta(sections: chartWithoutRows)) < 0.001)
        #expect(abs(Self.layoutHeightDelta(sections: rowsAndChart) - twoRowDelta) < 0.001)
        #expect(abs(Self.layoutHeightDelta(sections: multipleSections) - (singleRowDelta + twoRowDelta)) < 0.001)
    }

    private static func section(kind: ProviderDetailSection.Chart.Kind) throws -> ProviderDetailSection {
        try ProviderDetailSection(
            title: "Usage",
            rows: [ProviderDetailSection.Row(label: "Requests", value: "42", secondaryValue: "Today")],
            chart: ProviderDetailSection.Chart(
                kind: kind,
                title: "Daily",
                unit: "tokens",
                points: [
                    ProviderDetailSection.Chart.Point(label: "Mon", value: 12),
                    ProviderDetailSection.Chart.Point(label: "Tue", value: 24),
                ]))
    }

    private static func chart(kind: ProviderDetailSection.Chart.Kind) throws -> ProviderDetailSection.Chart {
        try ProviderDetailSection.Chart(
            kind: kind,
            title: "Daily",
            unit: "tokens",
            points: [
                ProviderDetailSection.Chart.Point(label: "Mon", value: 12),
                ProviderDetailSection.Chart.Point(label: "Tue", value: 24),
            ])
    }

    private static func r27Fixtures() throws -> [(String, [ProviderDetailSection])] {
        let primary = try ProviderDetailSection.Row(
            label: "Requests",
            value: "42",
            secondaryValue: "Today")
        let secondary = try ProviderDetailSection.Row(label: "Tokens", value: "1.25M")
        return try [
            ("empty rows", [ProviderDetailSection()]),
            ("title and rows", [ProviderDetailSection(title: "Usage", rows: [primary, secondary])]),
            ("chart without rows", [ProviderDetailSection(chart: Self.chart(kind: .bars))]),
            ("rows and chart", [ProviderDetailSection(
                title: "History",
                rows: [primary, secondary],
                chart: Self.chart(kind: .line))]),
            ("multiple sections", [
                ProviderDetailSection(title: "Usage", rows: [primary]),
                ProviderDetailSection(rows: [secondary], chart: Self.chart(kind: .bars)),
            ]),
        ]
    }

    private static let r27Appearances: [(NSAppearance.Name, Bool)] = [
        (.aqua, false),
        (.darkAqua, false),
        (.aqua, true),
    ]

    private static func layoutHeightDelta(sections: [ProviderDetailSection]) -> CGFloat {
        let standard = self.layoutSize(sections: sections, layout: .standard)
        let pluginSummary = self.layoutSize(sections: sections, layout: .pluginSummary)
        return pluginSummary.height - standard.height
    }

    private static func layoutSize(
        sections: [ProviderDetailSection],
        layout: ProviderDetailSectionsContent.Layout) -> CGSize
    {
        NSHostingController(rootView: ProviderDetailSectionsContent(
            sections: sections,
            chartColor: .green,
            layout: layout))
            .sizeThatFits(in: CGSize(width: 280, height: CGFloat.greatestFiniteMagnitude))
    }

    private struct RenderedBitmap {
        let pointSize: CGSize
        let pixelsWide: Int
        let pixelsHigh: Int
        let bytes: Data
    }

    private static func renderedBitmap(
        _ content: AnyView,
        appearance: NSAppearance.Name,
        highlighted: Bool) throws
        -> RenderedBitmap
    {
        let background = highlighted
            ? MenuHighlightStyle.selectionBackground(true)
            : Color(nsColor: .windowBackgroundColor)
        let view = AnyView(
            content
                .environment(\.menuItemHighlighted, highlighted)
                .frame(width: 280)
                .padding(12)
                .background(background))
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = try #require(NSAppearance(named: appearance))
        let size = hosting.fittingSize
        #expect(size.width > 0)
        #expect(size.height > 0)
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.appearance = hosting.appearance
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        let representation = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0))
        representation.size = size
        let context = try #require(NSGraphicsContext(bitmapImageRep: representation))
        try #require(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
            hosting.displayIgnoringOpacity(hosting.bounds, in: context)
        }
        let bitmapData = try #require(representation.bitmapData)
        let bytes = Data(bytes: bitmapData, count: representation.bytesPerRow * representation.pixelsHigh)
        return RenderedBitmap(
            pointSize: size,
            pixelsWide: representation.pixelsWide,
            pixelsHigh: representation.pixelsHigh,
            bytes: bytes)
    }

    private static func differingByteCount(_ lhs: Data, _ rhs: Data) -> Int {
        zip(lhs, rhs).reduce(into: 0) { count, pair in
            if pair.0 != pair.1 {
                count += 1
            }
        }
    }

    private static func input(details: [ProviderDetailSection]) -> UsageMenuCardView.Model.Input {
        let provider: UsageProvider = .synthetic
        return UsageMenuCardView.Model.Input(
            provider: provider,
            metadata: ProviderDescriptorRegistry.descriptor(for: provider).metadata,
            snapshot: UsageSnapshot(
                primary: nil,
                secondary: nil,
                details: details,
                updatedAt: Date()),
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: Date())
    }
}

/// Frozen copy of the pre-F7 renderer. It is deliberately independent from the new layout switch so
/// `.standard` must continue to produce the same pixels for first-party cards.
private struct R27LegacyProviderDetailSectionsContent: View {
    let sections: [ProviderDetailSection]
    let chartColor: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(self.sections.enumerated()), id: \.offset) { index, section in
                if index > 0 {
                    Divider()
                }
                self.section(section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(_ section: ProviderDetailSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = section.title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .textCase(.uppercase)
                    .lineLimit(1)
            }
            ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.label)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(row.value)
                            .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                            .fontWeight(.medium)
                        if let secondaryValue = row.secondaryValue {
                            Text(secondaryValue)
                                .font(.caption2)
                                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        }
                    }
                }
                .font(.caption)
                .lineLimit(1)
            }
            if let chart = section.chart {
                R27LegacyProviderDetailChartContent(chart: chart, color: self.chartColor)
            }
        }
    }
}

private struct R27LegacyProviderDetailChartContent: View {
    let chart: ProviderDetailSection.Chart
    let color: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if self.chart.title != nil || self.chart.unit != nil {
                HStack(spacing: 6) {
                    if let title = self.chart.title {
                        Text(title)
                            .font(.caption2.weight(.semibold))
                    }
                    Spacer(minLength: 0)
                    if let unit = self.chart.unit {
                        Text(unit)
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(1)
            }
            Group {
                switch self.chart.kind {
                case .bars:
                    self.bars
                case .line:
                    self.line
                }
            }
            .frame(height: 58)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(self.accessibilityLabel)
        }
    }

    private var bars: some View {
        GeometryReader { geometry in
            let scale = UsageChartScale(values: self.chart.points.map(\.value))
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(self.chart.points.enumerated()), id: \.offset) { _, point in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(self.fillColor(value: point.value, scale: scale))
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.height(value: point.value, scale: scale, available: geometry.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .overlay(alignment: .bottomLeading) {
                Rectangle()
                    .fill(MenuHighlightStyle.secondary(self.isHighlighted).opacity(0.22))
                    .frame(height: 1)
            }
        }
    }

    private var line: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let scale = UsageChartScale(values: self.chart.points.map(\.value))
                let points = self.chart.points.enumerated().map { index, point in
                    let x = self.chart.points.count == 1
                        ? size.width / 2
                        : size.width * CGFloat(index) / CGFloat(self.chart.points.count - 1)
                    let y = size.height * (1 - CGFloat(scale.fraction(for: point.value)))
                    return CGPoint(x: x, y: y)
                }
                guard let first = points.first else { return }
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
                context.stroke(
                    path,
                    with: .color(self.isHighlighted ? .white.opacity(0.82) : self.color),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                for point in points {
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)),
                        with: .color(self.isHighlighted ? .white : self.color))
                }
            }
            .overlay(alignment: .bottomLeading) {
                Rectangle()
                    .fill(MenuHighlightStyle.secondary(self.isHighlighted).opacity(0.22))
                    .frame(height: 1)
            }
        }
    }

    private var accessibilityLabel: String {
        let title = self.chart.title.map { "\($0): " } ?? ""
        let unit = self.chart.unit.map { " \($0)" } ?? ""
        let points = self.chart.points.map { "\($0.label) \($0.value)\(unit)" }.joined(separator: ", ")
        return title + points
    }

    private func fillColor(value: Double, scale: UsageChartScale) -> Color {
        let ratio = max(0.18, scale.fraction(for: value))
        if self.isHighlighted {
            return Color.white.opacity(0.55 + ratio * 0.35)
        }
        return self.color.opacity(0.42 + ratio * 0.58)
    }

    private static func height(value: Double, scale: UsageChartScale, available: CGFloat) -> CGFloat {
        let ratio = scale.fraction(for: value)
        guard ratio > 0 else { return 1 }
        return max(3, CGFloat(ratio) * available)
    }
}
