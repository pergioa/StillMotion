import AppKit
import ColorSync

struct DisplayDescriptor: Identifiable, Equatable {
    let id: String
    let name: String
    let isMain: Bool
    let isBuiltIn: Bool

    var symbolName: String {
        isBuiltIn ? "laptopcomputer" : "display"
    }

    static func currentDisplays() -> [DisplayDescriptor] {
        let screens = NSScreen.screens
        let nameCounts = Dictionary(grouping: screens, by: \.localizedName).mapValues(\.count)
        var nameIndexes: [String: Int] = [:]

        return screens.compactMap { screen in
            guard let displayID = screen.displayID, let persistentID = screen.persistentDisplayID else {
                return nil
            }

            let baseName = screen.localizedName
            nameIndexes[baseName, default: 0] += 1
            let numberedName = nameCounts[baseName, default: 0] > 1
                ? "\(baseName) \(nameIndexes[baseName, default: 1])"
                : baseName
            let isMain = displayID == CGMainDisplayID()
            return DisplayDescriptor(
                id: persistentID,
                name: isMain ? "\(numberedName) (Main Display)" : numberedName,
                isMain: isMain,
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0
            )
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    var persistentDisplayID: String? {
        guard
            let displayID,
            let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
