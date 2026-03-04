import AppKit

enum MenuBarIcon {
    static func progressBar(utilization: Double, width: CGFloat = 28, height: CGFloat = 12) -> NSImage {
        let barHeight: CGFloat = 6
        let radius: CGFloat = 3
        let fraction = min(max(utilization / 100.0, 0), 1)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let barRect = NSRect(
                x: 0,
                y: (rect.height - barHeight) / 2,
                width: rect.width,
                height: barHeight
            )

            // Background
            let bgPath = NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius)
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
            bgPath.fill()

            // Foreground
            if fraction > 0 {
                let fillWidth = max(barRect.width * fraction, barHeight)
                let fillRect = NSRect(
                    x: barRect.origin.x,
                    y: barRect.origin.y,
                    width: min(fillWidth, barRect.width),
                    height: barHeight
                )
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
                statusColor(for: utilization).setFill()
                fillPath.fill()
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    private static func statusColor(for utilization: Double) -> NSColor {
        if utilization >= 80 { return .systemRed }
        if utilization >= 60 { return .systemOrange }
        return .systemGreen
    }
}
