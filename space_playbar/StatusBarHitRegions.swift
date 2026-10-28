import Foundation
import CoreGraphics

enum StatusBarClickTarget: String {
    case source, backward, playPause, forward
}

enum StatusBarHitRegions {
    /// Use the full menu-bar height, including padding above/below an icon.
    /// Horizontal cuts follow actual layout frames rather than a fixed app name width.
    nonisolated static func target(at point: CGPoint, in bounds: CGRect, idle: Bool,
                                  backward: CGRect, playPause: CGRect, forward: CGRect) -> StatusBarClickTarget? {
        guard bounds.contains(point) else { return nil }
        if idle { return .source }
        guard backward.width > 0, playPause.width > 0, forward.width > 0 else { return nil }
        let sourceEnd = backward.minX - 0.5
        let backwardEnd = (backward.maxX + playPause.minX) / 2
        let playEnd = (playPause.maxX + forward.minX) / 2
        switch point.x {
        case ..<sourceEnd: return .source
        case ..<backwardEnd: return .backward
        case ..<playEnd: return .playPause
        default: return .forward
        }
    }
}
