import ArgumentParser
import CoreGraphics

/// Push-to-talk keys supported by the command line interface.
enum Hotkey: String, CaseIterable, ExpressibleByArgument {
    case fn
    case leftControl = "left-control"
    case rightControl = "right-control"

    var mask: CGEventFlags {
        switch self {
        case .fn: return .maskSecondaryFn
        case .leftControl, .rightControl: return .maskControl
        }
    }

    /// Left and right Control share a modifier flag, so use the physical keycode
    /// to keep the unselected side available for normal shortcuts.
    var keycode: Int64? {
        switch self {
        case .fn: return nil
        case .leftControl: return 59
        case .rightControl: return 62
        }
    }

    var displayName: String {
        switch self {
        case .fn: return "Fn"
        case .leftControl: return "Left Control"
        case .rightControl: return "Right Control"
        }
    }
}
