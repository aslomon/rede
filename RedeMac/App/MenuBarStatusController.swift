import AppKit

enum MenuBarStatus: Equatable {
    case idle
    case recording(WorkflowType)
    case processing(WorkflowType)
    case success(WorkflowType?)
    case error(WorkflowType?)
}

@MainActor
final class MenuBarStatusController {
    private weak var button: NSStatusBarButton?
    private var animationTimer: Timer?
    private var animationFrame = 0
    private var currentStatus: MenuBarStatus = .idle

    func attach(to button: NSStatusBarButton) {
        self.button = button
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        renderCurrentStatus()
    }

    func update(to status: MenuBarStatus) {
        currentStatus = status
        animationFrame = 0
        configureAnimationIfNeeded()
        renderCurrentStatus()
    }

    private func configureAnimationIfNeeded() {
        stopAnimation()

        switch currentStatus {
        case .recording:
            startAnimation(interval: 0.12)
        case .processing:
            startAnimation(interval: 0.18)
        default:
            break
        }
    }

    private func startAnimation(interval: TimeInterval) {
        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(animationTimer!, forMode: .common)
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func tick() {
        animationFrame = (animationFrame + 1) % 4
        renderCurrentStatus()
    }

    private func renderCurrentStatus() {
        guard let button else { return }
        button.image = MenuBarStatusIconRenderer.makeImage(for: currentStatus, frame: animationFrame)
        button.image?.isTemplate = true
        button.toolTip = tooltip(for: currentStatus)
    }

    private func tooltip(for status: MenuBarStatus) -> String {
        switch status {
        case .idle:
            return "rede ist bereit"
        case .recording(let type):
            return "\(type.displayName): Aufnahme läuft"
        case .processing(let type):
            return "\(type.displayName): Verarbeitung läuft"
        case .success(let type):
            if let type {
                return "\(type.displayName): Fertig"
            }
            return "rede: Fertig"
        case .error(let type):
            if let type {
                return "\(type.displayName): Fehler"
            }
            return "rede: Fehler"
        }
    }

    deinit {
        animationTimer?.invalidate()
    }
}

private enum MenuBarStatusIconRenderer {
    static func makeImage(for status: MenuBarStatus, frame: Int) -> NSImage {
        if case .idle = status, let baseImage = baseTemplateImage() {
            return baseImage
        }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            drawBaseIcon(in: bounds)

            switch status {
            case .recording, .processing:
                drawActiveDot(in: bounds, frame: frame)
            case .success:
                drawBadge(systemName: "checkmark", in: bounds, fillOpacity: 1.0)
            case .error:
                drawBadge(systemName: "exclamationmark", in: bounds, fillOpacity: 1.0)
            default:
                break
            }

            return true
        }
        image.isTemplate = true
        image.size = size
        return image
    }

    private static func drawBaseIcon(in bounds: CGRect) {
        if let baseImage = baseTemplateImage() {
            baseImage.draw(
                in: bounds,
                from: CGRect(origin: .zero, size: baseImage.size),
                operation: .sourceOver,
                fraction: 1.0
            )
            return
        }

        drawFallbackBaseIcon(in: bounds)
    }

    private static func drawFallbackBaseIcon(in bounds: CGRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY + 0.3)
        let capsule = CGRect(x: center.x - 3.0, y: center.y - 5.3, width: 6.0, height: 9.2)
        let stem = CGRect(x: center.x - 0.75, y: bounds.minY + 3.0, width: 1.5, height: 3.1)
        let base = CGRect(x: center.x - 3.4, y: bounds.minY + 2.2, width: 6.8, height: 1.4)

        NSColor.black.setStroke()
        let micPath = NSBezierPath(roundedRect: capsule, xRadius: 3.0, yRadius: 3.0)
        micPath.lineWidth = 1.55
        micPath.stroke()

        NSColor.black.setFill()
        NSBezierPath(roundedRect: stem, xRadius: 0.75, yRadius: 0.75).fill()
        NSBezierPath(roundedRect: base, xRadius: 0.7, yRadius: 0.7).fill()
    }

    private static func drawActiveDot(in bounds: CGRect, frame: Int) {
        let dotSize: CGFloat = 4.8
        let dotRect = CGRect(
            x: bounds.maxX - dotSize - 1.4,
            y: bounds.minY + 1.2,
            width: dotSize,
            height: dotSize
        )
        let pulse = [0.42, 0.62, 0.82, 0.62][frame % 4]
        let haloRect = dotRect.insetBy(dx: -1.45, dy: -1.45)
        let haloPath = NSBezierPath(ovalIn: haloRect)
        NSColor.black.withAlphaComponent(pulse * 0.35).setStroke()
        haloPath.lineWidth = 1.0
        haloPath.stroke()

        let dotPath = NSBezierPath(ovalIn: dotRect)
        NSColor.black.withAlphaComponent(0.95).setFill()
        dotPath.fill()
    }

    private static func drawBadge(systemName: String, in bounds: CGRect, fillOpacity: CGFloat) {
        let badgeSize: CGFloat = 7.5
        let badgeRect = CGRect(
            x: bounds.maxX - badgeSize - 0.8,
            y: bounds.minY + 0.8,
            width: badgeSize,
            height: badgeSize
        )

        let badgePath = NSBezierPath(ovalIn: badgeRect)
        NSColor.black.withAlphaComponent(fillOpacity).setFill()
        badgePath.fill()

        guard let symbol = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: nil
        ) else {
            return
        }

        let config = NSImage.SymbolConfiguration(pointSize: 5.5, weight: .bold)
        let configuredSymbol = symbol.withSymbolConfiguration(config) ?? symbol
        let symbolRect = badgeRect.insetBy(dx: 1.2, dy: 1.2)
        configuredSymbol.draw(
            in: symbolRect,
            from: .zero,
            operation: .destinationOut,
            fraction: 1.0
        )
    }

    private static func baseTemplateImage() -> NSImage? {
        guard let image = NSImage(named: "menubar_icon") else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
