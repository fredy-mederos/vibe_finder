// Presses a button or a menu item of one running copy of Vibe Finder through accessibility, by its
// label: a group's header ("Today"), "Move to Trash", "Collapse All Groups", a dialog's button. No
// mouse is moved and the copy doesn't need to be in front, so it can't land on another app's window.
// Usage: swift scripts/press.swift <process id> [label]      (without a label, lists what can be pressed)
import ApplicationServices

guard CommandLine.arguments.count > 1, let pid = Int32(CommandLine.arguments[1]) else {
    print("usage: swift scripts/press.swift <process id> [label]")
    exit(1)
}
let wanted = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

struct Pressable {
    let label: String
    let element: AXUIElement
    /// It belongs to a dialog on top of the window, which is where a click would go first.
    let inDialog: Bool
}

/// Every button, menu item and picker segment under an element, with the text it goes by.
func pressables(under element: AXUIElement, inDialog: Bool = false, depth: Int = 0) -> [Pressable] {
    guard depth < 40 else { return [] }
    var found: [Pressable] = []
    let role = attribute(element, kAXRoleAttribute) as? String
    let inDialog = inDialog || role == kAXSheetRole
    // Radio buttons are what the segments of a picker are.
    if role == kAXButtonRole || role == kAXMenuItemRole || role == kAXRadioButtonRole {
        let names = [kAXDescriptionAttribute, kAXTitleAttribute].compactMap { attribute(element, $0) as? String }
        if let label = names.first(where: { !$0.isEmpty }) { found.append(Pressable(label: label, element: element, inDialog: inDialog)) }
    }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        found += pressables(under: child, inDialog: inDialog, depth: depth + 1)
    }
    return found
}

let all = pressables(under: AXUIElementCreateApplication(pid))
guard let wanted else {
    all.forEach { print($0.inDialog ? "\($0.label)  (dialog)" : $0.label) }
    exit(0)
}
// With a dialog up, its buttons are the ones meant.
let candidates = all.contains(where: \.inDialog) ? all.filter(\.inDialog) : all
guard let match = candidates.first(where: { $0.label == wanted }) ?? candidates.first(where: { $0.label.localizedCaseInsensitiveContains(wanted) }) else {
    print("nothing to press labeled \(wanted); there are: \(candidates.map(\.label).joined(separator: ", "))")
    exit(1)
}
let result = AXUIElementPerformAction(match.element, kAXPressAction as CFString)
print(result == .success ? "pressed \(match.label)" : "couldn't press \(match.label) (\(result.rawValue))")
exit(result == .success ? 0 : 1)
