import AppKit
import ScreenCaptureKit

enum ScreenCapture {
    /// Captures the display under the mouse (excluding our own overlay) and draws numbered
    /// "set-of-marks" boxes for each element, so the model can tie pixels to element IDs.
    /// Returns PNG data plus the display's frame in AX coordinates.
    static func captureAnnotated(elements: [UIElement]) async throws -> (png: Data, axFrame: CGRect) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "GhostCursor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Display not found"])
        }
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])

        // Downscale so the long edge is ~1456px: plenty for UI, keeps tokens and latency down.
        let scale = min(1.0, 1456.0 / max(screen.frame.width, screen.frame.height))
        let config = SCStreamConfiguration()
        config.width = Int(screen.frame.width * scale)
        config.height = Int(screen.frame.height * scale)
        config.showsCursor = false

        let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let axFrame = AXScanner.axFrame(of: screen)
        let png = annotate(cg, elements: elements, axFrame: axFrame, scale: scale)
        return (png, axFrame)
    }

    private static func annotate(_ image: CGImage, elements: [UIElement], axFrame: CGRect, scale: CGFloat) -> Data {
        let w = image.width, h = image.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Flip so we can draw in top-left coordinates like AX.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 10),
            .foregroundColor: NSColor.white,
        ]
        for el in elements where axFrame.intersects(el.frame) {
            let r = CGRect(x: (el.frame.minX - axFrame.minX) * scale, y: (el.frame.minY - axFrame.minY) * scale,
                           width: el.frame.width * scale, height: el.frame.height * scale)
            ctx.setStrokeColor(NSColor.systemPink.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(r)
            let tag = NSAttributedString(string: "\(el.id)", attributes: attrs)
            let ts = tag.size()
            let tagRect = CGRect(x: r.minX, y: max(0, r.minY - ts.height), width: ts.width + 4, height: ts.height)
            ctx.setFillColor(NSColor.systemPink.withAlphaComponent(0.85).cgColor)
            ctx.fill(tagRect)
            tag.draw(at: CGPoint(x: tagRect.minX + 2, y: tagRect.minY))
        }
        NSGraphicsContext.restoreGraphicsState()

        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
