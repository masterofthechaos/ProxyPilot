import AppKit
import Combine

enum ProxyPilotDockActivity: Equatable {
    case inactive
    case idle
    case processing
    case failed
}

struct ProxyPilotDockPresentation: Equatable {
    static let neutralMultiModelLabel = "MULTI MODEL"
    static let readyLabel = "READY"

    let activity: ProxyPilotDockActivity
    let modelLabel: String

    static func derive(
        isListening: Bool,
        pendingRequestCount: Int,
        activeModels: Set<String>,
        lastModelSeen: String,
        configuredModel: String,
        hasRecentFailure: Bool
    ) -> Self {
        guard isListening else {
            return Self(activity: .inactive, modelLabel: "")
        }

        if pendingRequestCount > 0 {
            let normalizedActiveModels = Set(
                activeModels
                    .map(ProxyPilotDockModelName.normalize)
                    .filter { !$0.isEmpty }
            )
            let label: String
            if normalizedActiveModels.count > 1 {
                label = neutralMultiModelLabel
            } else if let activeModel = normalizedActiveModels.first {
                label = activeModel
            } else {
                label = ProxyPilotDockModelName.normalize(lastModelSeen)
            }
            return Self(
                activity: .processing,
                modelLabel: label.isEmpty ? readyLabel : label
            )
        }

        let normalizedLastModel = ProxyPilotDockModelName.normalize(lastModelSeen)
        let normalizedConfiguredModel = ProxyPilotDockModelName.normalize(configuredModel)
        let label = normalizedLastModel.isEmpty ? normalizedConfiguredModel : normalizedLastModel
        return Self(
            activity: hasRecentFailure ? .failed : .idle,
            modelLabel: label.isEmpty ? readyLabel : label
        )
    }
}

enum ProxyPilotDockModelName {
    static let maximumInputCharacters = 256
    static let maximumLabelCharacters = 32

    static func normalize(_ rawValue: String) -> String {
        var value = String(rawValue.prefix(maximumInputCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }

        if value.lowercased().hasSuffix(":exacto") {
            value.removeLast(":exacto".count)
        }
        if let leaf = value.split(separator: "/", omittingEmptySubsequences: true).last {
            value = String(leaf)
        }

        value = value
            .replacingOccurrences(of: "_", with: "-")
            .uppercased()

        let supported = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._:+ ")
        value = String(value.map { supported.contains($0) ? $0 : " " })
        let normalized = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(normalized.prefix(maximumLabelCharacters))
    }
}

enum ProxyPilotDockLEDMatrix {
    static let dotPitch: CGFloat = 2.25
    static let glyphAdvance: CGFloat = dotPitch * 6

    static func textWidth(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return (CGFloat(text.count) * glyphAdvance) - dotPitch
    }

    static func rows(for character: Character) -> [String] {
        glyphs[character] ?? glyphs["?"]!
    }

    private static let glyphs: [Character: [String]] = [
        " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
        "?": ["01110", "10001", "00001", "00010", "00100", "00000", "00100"],
        "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
        "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
        "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
        "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
        "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
        "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
        "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
        "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
        "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
        "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
        "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
        "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
        "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
        "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
        "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
        "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
        "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
        "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
        "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
        "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
        "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
        "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
        "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
        "6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
        "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
        ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
        ":": ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
        "+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"]
    ]
}

@MainActor
final class ProxyPilotDockTileView: NSView {
    static let signRect = NSRect(x: 11, y: 9, width: 106, height: 23)
    static let signHorizontalInset: CGFloat = 6
    static let marqueeGap: CGFloat = 24

    var presentation = ProxyPilotDockPresentation(activity: .inactive, modelLabel: "") {
        didSet {
            if presentation.modelLabel != oldValue.modelLabel {
                scrollOffset = 0
            }
            updateAnimation()
            needsDisplay = true
        }
    }

    var reduceMotion = false {
        didSet {
            updateAnimation()
            needsDisplay = true
        }
    }

    private var animationTimer: Timer?
    private var animationPhase: CGFloat = 0
    private var scrollOffset: CGFloat = 0

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let icon = NSApp.applicationIconImage else { return }
        icon.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)

        guard presentation.activity != .inactive else { return }
        drawActivityPerimeter()
        drawSignHousing()
        drawModelLabel()
        drawStatusDot()
    }

    static func shouldAnimate(_ presentation: ProxyPilotDockPresentation, reduceMotion: Bool) -> Bool {
        presentation.activity == .processing && !reduceMotion
    }

    private var availableSignWidth: CGFloat {
        Self.signRect.width - (Self.signHorizontalInset * 2)
    }

    private var modelTextWidth: CGFloat {
        ProxyPilotDockLEDMatrix.textWidth(presentation.modelLabel)
    }

    private var shouldScrollModel: Bool {
        presentation.activity == .processing && modelTextWidth > availableSignWidth && !reduceMotion
    }

    private func updateAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        guard Self.shouldAnimate(presentation, reduceMotion: reduceMotion) else {
            animationPhase = 0
            scrollOffset = 0
            return
        }

        let timer = Timer(
            timeInterval: 1.0 / 20.0,
            target: self,
            selector: #selector(animationTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    @objc private func animationTick() {
        animationPhase = (animationPhase + 0.025).truncatingRemainder(dividingBy: 1)
        if shouldScrollModel {
            let cycleWidth = modelTextWidth + Self.marqueeGap
            scrollOffset += 0.65
            if scrollOffset >= cycleWidth {
                scrollOffset -= cycleWidth
            }
        }
        needsDisplay = true
        NSApp.dockTile.display()
    }

    private func drawActivityPerimeter() {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.43

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = 3.5
        NSColor.black.withAlphaComponent(0.30).setStroke()
        track.stroke()

        let arc = NSBezierPath()
        let startAngle: CGFloat
        let sweep: CGFloat
        let color: NSColor
        switch presentation.activity {
        case .inactive:
            return
        case .idle:
            startAngle = 200
            sweep = 140
            color = .systemGreen
        case .processing:
            startAngle = (animationPhase * 360) - 35
            sweep = reduceMotion ? 250 : 105
            color = NSColor(calibratedRed: 0.82, green: 0.28, blue: 1.0, alpha: 1.0)
        case .failed:
            startAngle = 190
            sweep = 160
            color = .systemRed
        }
        arc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: startAngle + sweep)
        arc.lineWidth = 4.5
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }

    private func drawSignHousing() {
        let housing = NSBezierPath(roundedRect: Self.signRect, xRadius: 5, yRadius: 5)
        NSColor.black.withAlphaComponent(0.88).setFill()
        housing.fill()

        let inner = NSBezierPath(roundedRect: Self.signRect.insetBy(dx: 2, dy: 2), xRadius: 3, yRadius: 3)
        NSColor(calibratedRed: 0.12, green: 0.055, blue: 0.012, alpha: 0.96).setFill()
        inner.fill()
        NSColor.systemOrange.withAlphaComponent(0.35).setStroke()
        inner.lineWidth = 1
        inner.stroke()
    }

    private func drawModelLabel() {
        let clipRect = Self.signRect.insetBy(dx: 3, dy: 3)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: clipRect, xRadius: 2, yRadius: 2).addClip()

        let y = Self.signRect.minY + 3.5
        if shouldScrollModel {
            let cycleWidth = modelTextWidth + Self.marqueeGap
            let firstX = Self.signRect.minX + Self.signHorizontalInset - scrollOffset
            drawLEDText(presentation.modelLabel, at: NSPoint(x: firstX, y: y))
            drawLEDText(presentation.modelLabel, at: NSPoint(x: firstX + cycleWidth, y: y))
        } else {
            let x = Self.signRect.midX - (modelTextWidth / 2)
            drawLEDText(presentation.modelLabel, at: NSPoint(x: x, y: y))
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawLEDText(_ text: String, at origin: NSPoint) {
        let dotDiameter: CGFloat = 1.55
        let litColor: NSColor = presentation.activity == .failed ? .systemRed : .systemOrange
        litColor.setFill()

        for (characterIndex, character) in text.enumerated() {
            let rows = ProxyPilotDockLEDMatrix.rows(for: character)
            let glyphX = origin.x + (CGFloat(characterIndex) * ProxyPilotDockLEDMatrix.glyphAdvance)
            for (rowIndex, row) in rows.enumerated() {
                for (columnIndex, bit) in row.enumerated() where bit == "1" {
                    let x = glyphX + (CGFloat(columnIndex) * ProxyPilotDockLEDMatrix.dotPitch)
                    let y = origin.y + (CGFloat(6 - rowIndex) * ProxyPilotDockLEDMatrix.dotPitch)
                    NSBezierPath(
                        ovalIn: NSRect(x: x, y: y, width: dotDiameter, height: dotDiameter)
                    ).fill()
                }
            }
        }
    }

    private func drawStatusDot() {
        let color: NSColor
        switch presentation.activity {
        case .inactive:
            return
        case .idle:
            color = .systemGreen
        case .processing:
            color = NSColor(calibratedRed: 0.82, green: 0.28, blue: 1.0, alpha: 1.0)
        case .failed:
            color = .systemRed
        }
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 108, y: 107, width: 9, height: 9)).fill()
    }

}

@MainActor
final class ProxyPilotDockTileController {
    static let failurePresentationDuration: TimeInterval = 3

    private let tileView = ProxyPilotDockTileView(
        frame: NSRect(x: 0, y: 0, width: 128, height: 128)
    )
    private var state: LocalProxyState?
    private var stateCancellable: AnyCancellable?
    private var accessibilityCancellable: AnyCancellable?
    private var failureExpiryTask: Task<Void, Never>?
    private var isInstalled = false

    static func shouldInstall(
        bundleIdentifier: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        // As of v1.11.6 the Dock Tile ships on both stable and alpha builds.
        // The bundleIdentifier argument is retained for API stability and
        // future channel-specific behavior, but no longer gates installation.
        environment["XCTestConfigurationFilePath"] == nil
    }

    func installIfEligible(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard Self.shouldInstall(bundleIdentifier: bundleIdentifier, environment: environment) else { return }
        tileView.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSApp.dockTile.contentView = tileView
        NSApp.dockTile.display()
        isInstalled = true

        accessibilityCancellable = NotificationCenter.default.publisher(
            for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            guard let self else { return }
            self.tileView.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            NSApp.dockTile.display()
        }
        refreshPresentation()
    }

    func bind(to state: LocalProxyState) {
        self.state = state
        stateCancellable = state.objectWillChange
            .debounce(for: .milliseconds(8), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.refreshPresentation()
            }
        refreshPresentation()
    }

    func restoreDefaultIcon() {
        failureExpiryTask?.cancel()
        failureExpiryTask = nil
        stateCancellable = nil
        accessibilityCancellable = nil
        guard isInstalled else { return }
        tileView.presentation = ProxyPilotDockPresentation(activity: .inactive, modelLabel: "")
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
        isInstalled = false
    }

    private func refreshPresentation() {
        guard isInstalled, let state else { return }
        let recentFailure: Bool
        let failureTimeRemaining: TimeInterval?
        if let lastFailureAt = state.lastFailureAt {
            let elapsed = Date().timeIntervalSince(lastFailureAt)
            recentFailure = elapsed < Self.failurePresentationDuration
            failureTimeRemaining = recentFailure ? Self.failurePresentationDuration - elapsed : nil
        } else {
            recentFailure = false
            failureTimeRemaining = nil
        }

        tileView.presentation = ProxyPilotDockPresentation.derive(
            isListening: state.isRunning,
            pendingRequestCount: state.pendingRequestCount,
            activeModels: state.activeModels,
            lastModelSeen: state.lastModelSeen,
            configuredModel: state.activeXcodeAgentModel,
            hasRecentFailure: recentFailure
        )
        NSApp.dockTile.display()

        failureExpiryTask?.cancel()
        failureExpiryTask = nil
        if let failureTimeRemaining, state.pendingRequestCount == 0 {
            failureExpiryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(failureTimeRemaining))
                guard !Task.isCancelled else { return }
                self?.refreshPresentation()
            }
        }
    }
}
