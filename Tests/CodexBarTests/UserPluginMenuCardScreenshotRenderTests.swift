#if canImport(JavaScriptCore)
import AppKit
import CodexBarCore
import SwiftUI
import XCTest
@testable import CodexBar

/// Renders a public, synthetic user-plugin card without registry, account, Keychain, NSStatusBar,
/// or network access. Set the directory variable to retain the proof images outside temporary storage.
///
/// Run with:
///   CODEXBAR_PLUGIN_CARD_SCREENSHOT_DIR=.github/pr-proof \
///     swift test --filter UserPluginMenuCardScreenshotRenderTests
@MainActor
final class UserPluginMenuCardScreenshotRenderTests: XCTestCase {
    private static let width: CGFloat = 320
    private static let outerPadding: CGFloat = 16
    private static let now = Date(timeIntervalSince1970: 1_788_071_340)

    func test_R28_badgeUsesExactStyleAndHighlightedMonogramRemainsLegible() throws {
        XCTAssertEqual(UserPluginMenuBadgeStyle.size, 31, accuracy: 0.0001)
        XCTAssertEqual(UserPluginMenuBadgeStyle.cornerRadius, 9, accuracy: 0.0001)
        XCTAssertEqual(UserPluginMenuBadgeStyle.backgroundOpacity, 0.13, accuracy: 0.0001)
        XCTAssertEqual(UserPluginMenuBadgeStyle.strokeOpacity, 0.32, accuracy: 0.0001)
        XCTAssertEqual(UserPluginMenuBadgeStyle.strokeWidth, 1, accuracy: 0.0001)

        let semanticContrast = try Self.semanticHighlightContrast(appearance: .aqua)
        XCTAssertGreaterThanOrEqual(semanticContrast, 3)

        let fixture = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let render = try Self.renderCard(
            plugin: fixture.plugin,
            snapshot: Self.snapshot(),
            state: .highlighted)
        let badgeContrast = Self.badgeContrast(in: render)

        XCTAssertGreaterThanOrEqual(badgeContrast.maximumRatio, 3)
        XCTAssertGreaterThanOrEqual(badgeContrast.contrastingPixelCount, 4)
    }

    func test_R29_syntheticPluginCardWritesDistinctNonUniformLightDarkAndHighlightPNGs() throws {
        let outputDirectory = try Self.outputDirectory()
        let fixture = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let snapshot = try Self.snapshot()
        var renders: [RenderState: RenderedPNG] = [:]

        for state in RenderState.allCases {
            let render = try Self.renderCard(plugin: fixture.plugin, snapshot: snapshot, state: state)
            let url = outputDirectory.appendingPathComponent("token-monitor-plugin-card-\(state.rawValue).png")
            try render.data.write(to: url, options: .atomic)

            XCTAssertTrue(render.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
            XCTAssertGreaterThanOrEqual(render.bitmap.pixelsWide, 320)
            XCTAssertGreaterThan(render.bitmap.pixelsHigh, 160)
            XCTAssertLessThan(render.bitmap.pixelsHigh, 900)
            XCTAssertGreaterThan(Self.sampledRGBColorCount(in: render.bitmap), 8)
            XCTAssertEqual(try Data(contentsOf: url), render.data)
            renders[state] = render
            print("Wrote \(url.path)")
        }

        let light = try XCTUnwrap(renders[.light])
        let dark = try XCTUnwrap(renders[.dark])
        let highlighted = try XCTUnwrap(renders[.highlighted])
        XCTAssertEqual(light.bitmap.pixelsWide, dark.bitmap.pixelsWide)
        XCTAssertEqual(light.bitmap.pixelsHigh, dark.bitmap.pixelsHigh)
        XCTAssertEqual(light.bitmap.pixelsWide, highlighted.bitmap.pixelsWide)
        XCTAssertEqual(light.bitmap.pixelsHigh, highlighted.bitmap.pixelsHigh)
        XCTAssertGreaterThan(try Self.differingPixelFraction(light.bitmap, dark.bitmap), 0.25)
        XCTAssertGreaterThan(try Self.differingPixelFraction(light.bitmap, highlighted.bitmap), 0.25)
    }

    private enum RenderState: String, CaseIterable, Hashable {
        case light
        case dark
        case highlighted

        var appearance: NSAppearance.Name {
            self == .dark ? .darkAqua : .aqua
        }

        var isHighlighted: Bool {
            self == .highlighted
        }
    }

    private struct RenderedPNG {
        let data: Data
        let bitmap: NSBitmapImageRep
        let pointSize: CGSize
    }

    private static func fixture() throws -> (root: URL, plugin: UserProviderPlugin) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("UserPluginMenuCardScreenshotRenderTests-\(UUID().uuidString)", isDirectory: true)
        let providers = root.appendingPathComponent("providers", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: providers, withIntermediateDirectories: true)
        let fileURL = providers.appendingPathComponent("token-monitor.js")
        try Data(Self.pluginSource.utf8).write(to: fileURL, options: .atomic)

        let transport = ProviderHTTPTransportHandler { _ in
            throw OfflineFixtureError.unexpectedNetworkRequest
        }
        let loader = UserProviderPluginLoader(
            providersDirectory: providers,
            cacheDirectory: cache,
            transport: transport)
        return try (root, loader.load(fileURL: fileURL))
    }

    private static func snapshot() throws -> UsageSnapshot {
        try UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [ProviderDetailSection(rows: [
                ProviderDetailSection.Row(label: "Hoy", value: "1,25 M tokens", secondaryValue: "3,41 US$"),
                ProviderDetailSection.Row(
                    label: "Este mes",
                    value: "18,4 M tokens",
                    secondaryValue: "42,10 US$"),
                ProviderDetailSection.Row(
                    label: "Actualizado",
                    value: "hace 8 s",
                    secondaryValue: "26/08 · 08:29 UTC · 2 fuentes"),
            ])],
            updatedAt: self.now)
    }

    private static func outputDirectory() throws -> URL {
        let directory: URL = if let rawPath = ProcessInfo.processInfo
            .environment["CODEXBAR_PLUGIN_CARD_SCREENSHOT_DIR"],
            !rawPath.isEmpty
        {
            URL(
                fileURLWithPath: NSString(string: rawPath).expandingTildeInPath,
                isDirectory: true)
        } else {
            FileManager.default.temporaryDirectory.appendingPathComponent(
                "UserPluginMenuCardScreenshotRenderTests-R29-\(UUID().uuidString)",
                isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func renderCard(
        plugin: UserProviderPlugin,
        snapshot: UsageSnapshot,
        state: RenderState) throws
        -> RenderedPNG
    {
        let background = state.isHighlighted
            ? MenuHighlightStyle.selectionBackground(true)
            : Color(nsColor: .windowBackgroundColor)
        let view = AnyView(
            UserPluginMenuCardView(
                plugin: plugin,
                snapshot: snapshot,
                error: nil,
                isRefreshing: false,
                showUsed: true,
                width: self.width,
                onRefresh: {})
                .environment(\.menuItemHighlighted, state.isHighlighted)
                .padding(self.outerPadding)
                .background(background))
        return try self.renderedPNG(for: view, appearance: state.appearance)
    }

    private static func renderedPNG(for view: AnyView, appearance: NSAppearance.Name) throws -> RenderedPNG {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = try XCTUnwrap(NSAppearance(named: appearance))
        let size = hosting.fittingSize
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        let representation = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        return try RenderedPNG(
            data: data,
            bitmap: XCTUnwrap(NSBitmapImageRep(data: data)),
            pointSize: size)
    }

    private static func semanticHighlightContrast(appearance: NSAppearance.Name) throws -> Double {
        let appearance = try XCTUnwrap(NSAppearance(named: appearance))
        var foreground: NSColor?
        var background: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            foreground = NSColor(MenuHighlightStyle.primary(true)).usingColorSpace(.sRGB)
            background = NSColor(MenuHighlightStyle.selectionBackground(true)).usingColorSpace(.sRGB)
        }
        return try self.contrastRatio(
            self.relativeLuminance(XCTUnwrap(foreground)),
            self.relativeLuminance(XCTUnwrap(background)))
    }

    private static func badgeContrast(in render: RenderedPNG) -> (
        maximumRatio: Double,
        contrastingPixelCount: Int)
    {
        let scaleX = CGFloat(render.bitmap.pixelsWide) / render.pointSize.width
        let scaleY = CGFloat(render.bitmap.pixelsHigh) / render.pointSize.height
        let inset: CGFloat = 4
        let originX = self.outerPadding + UsageMenuCardLayout.horizontalPadding
        let originYFromTop = self.outerPadding + 8
        let minimumX = max(0, Int(((originX + inset) * scaleX).rounded(.down)))
        let maximumX = min(
            render.bitmap.pixelsWide,
            Int(((originX + UserPluginMenuBadgeStyle.size - inset) * scaleX).rounded(.up)))
        let minimumY = max(
            0,
            Int(((originYFromTop + inset) * scaleY).rounded(.down)))
        let maximumY = min(
            render.bitmap.pixelsHigh,
            Int(((originYFromTop + UserPluginMenuBadgeStyle.size - inset) * scaleY).rounded(.up)))
        var luminances: [Double] = []

        for y in minimumY..<maximumY {
            for x in minimumX..<maximumX {
                guard let color = render.bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                luminances.append(self.relativeLuminance(color))
            }
        }
        guard !luminances.isEmpty else { return (0, 0) }
        let background = luminances.sorted()[luminances.count / 2]
        let ratios = luminances.map { self.contrastRatio($0, background) }
        return (ratios.max() ?? 0, ratios.count(where: { $0 >= 3 }))
    }

    private static func sampledRGBColorCount(in bitmap: NSBitmapImageRep) -> Int {
        var colors: Set<UInt32> = []
        let xStep = max(1, bitmap.pixelsWide / 80)
        let yStep = max(1, bitmap.pixelsHigh / 80)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: yStep) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: xStep) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let red = UInt32((color.redComponent * 255).rounded())
                let green = UInt32((color.greenComponent * 255).rounded())
                let blue = UInt32((color.blueComponent * 255).rounded())
                colors.insert((red << 16) | (green << 8) | blue)
                if colors.count > 32 {
                    return colors.count
                }
            }
        }
        return colors.count
    }

    private static func differingPixelFraction(
        _ lhs: NSBitmapImageRep,
        _ rhs: NSBitmapImageRep) throws
        -> Double
    {
        guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return 1 }
        let bytesPerPixel = max(1, lhs.bitsPerPixel / 8)
        XCTAssertEqual(bytesPerPixel, max(1, rhs.bitsPerPixel / 8))
        let lhsBytes = try [UInt8](self.bitmapData(lhs))
        let rhsBytes = try [UInt8](self.bitmapData(rhs))
        var differingPixels = 0

        for y in 0..<lhs.pixelsHigh {
            for x in 0..<lhs.pixelsWide {
                let lhsOffset = y * lhs.bytesPerRow + x * bytesPerPixel
                let rhsOffset = y * rhs.bytesPerRow + x * bytesPerPixel
                if (0..<bytesPerPixel).contains(where: { channel in
                    lhsBytes[lhsOffset + channel] != rhsBytes[rhsOffset + channel]
                }) {
                    differingPixels += 1
                }
            }
        }
        return Double(differingPixels) / Double(lhs.pixelsWide * lhs.pixelsHigh)
    }

    private static func bitmapData(_ bitmap: NSBitmapImageRep) throws -> Data {
        let pointer = try XCTUnwrap(bitmap.bitmapData)
        return Data(bytes: pointer, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    private static func relativeLuminance(_ color: NSColor) -> Double {
        func linearize(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(color.redComponent)
            + 0.7152 * linearize(color.greenComponent)
            + 0.0722 * linearize(color.blueComponent)
    }

    private static func contrastRatio(_ lhs: Double, _ rhs: Double) -> Double {
        (max(lhs, rhs) + 0.05) / (min(lhs, rhs) + 0.05)
    }

    private static let pluginSource = """
    defineProvider({
      id: "token-monitor-proof",
      name: "Token Monitor",
      icon: { monogram: "TM", tint: "#167A3E" },
      endpoints: ["https://proof.invalid"],
      settings: [],
      fetchUsage() { return {}; },
    });
    """
}

private enum OfflineFixtureError: Error {
    case unexpectedNetworkRequest
}
#endif
