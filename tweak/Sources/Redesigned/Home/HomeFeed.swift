// Home redesign: every section's shelf heading from the model behind Home's list, for the sections whose cells
// are not built yet. Spotify builds a section's views only as it nears the screen, so a heading a shelf further
// down has is not there to read (HomeShelves.m); the list's content snapshot holds every section's props.
//
// The path, from the page's controller (Home_EvoPageImpl.EvoLoadableResourceViewController, the list's
// delegate), by the stored properties' names (in the 9.1.78, 9.1.88 and 9.1.90 binaries' reflection strings):
//   collectionViewRenderer: Element_List.CollectionViewRenderer
//   .contentDataSource: Element_List.ContentDataSource (not the list's own dataSource, which is UIKit's diffable one)
//   .contentSnapshot: .sections, one per section of the list, each with .items (ItemIdentifier),
//                     and .items, ItemIdentifier -> Section.Item
//   Section.Item .item.configuration.props: Home_EvoPageImpl.HomeStructure, one case per kind (shelf: ShelfData,
//                                       recents: RecentsData, ...), its payload's .heading: HomeHeading?
//   HomeHeading                         .withText(text:...) or .enrichedHeading(text:..., enrichedTextRange:),
//                                       the range being the large part ("Chief Keef" in "More like Chief Keef")
// On 9.1.90: section 11 is .shelf, heading .withText("Your favorite artists"); section 12 .enrichedHeading("More
// like Alexis Weissenberg"), which SGRHomeShelfIdentity reads off the view as "More like …".
//
// Load only named strong Swift fields, not earlier siblings that may be unowned.
// On a different layout Top picks goes by the headings on screen. Main thread only.
import UIKit

@objc(SGRHomeFeed)
final class SGRHomeFeed: NSObject {
    private struct FieldKey: Hashable { let owner: ObjectIdentifier; let name: String }
    private enum Storage { case object(Ivar), swift, unavailable }
    private static var fields = [FieldKey: Storage]() // declaration only; nil values may become available later

    private static func ivar(_ object: AnyObject, _ name: String) -> AnyObject? {
        let owner: AnyClass = type(of: object)
        let key = FieldKey(owner: ObjectIdentifier(owner), name: name)
        if fields[key] == nil {
            if let slot = class_getInstanceVariable(owner, name), let encoding = ivar_getTypeEncoding(slot) {
                fields[key] = UInt8(bitPattern: encoding.pointee) == UInt8(ascii: "@") ? .object(slot) :
                    encoding.pointee == 0 ? .swift : .unavailable
            } else {
                fields[key] = .unavailable
            }
        }
        switch fields[key] {
        case .object(let slot): return object_getIvar(object, slot) as AnyObject?
        case .swift:
            guard let value = some(child(object, name)), type(of: value) is AnyClass else { return nil }
            return value as AnyObject
        default: return nil
        }
    }

    private static func child(_ value: Any, _ label: String) -> Any? {
        SGStoredField.child(value, label)
    }

    private static func some(_ value: Any?) -> Any? {
        guard let value else { return nil }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
    }

    // The heading's small line and its title, the way the view shows them: the large part is the title, the rest
    // the line over it ("More like" over "Chief Keef"); with no large part the whole text is the title. A range
    // past the text's end is not this text's, and the whole text is the title.
    static func parts(text: String, large: Range<String.Index>?) -> [String] {
        guard let large, large.upperBound <= text.endIndex else { return ["", text.trimmingCharacters(in: .whitespaces)] }
        let small = (text[..<large.lowerBound] + text[large.upperBound...]).trimmingCharacters(in: .whitespaces)
        return [small, text[large].trimmingCharacters(in: .whitespaces)]
    }

    private static func parts(props: Any) -> [String]? {
        let structure = Mirror(reflecting: props)
        guard structure.displayStyle == .enum, let payload = structure.children.first?.value,
              let heading = some(child(payload, "heading")),
              Mirror(reflecting: heading).displayStyle == .enum, let fields = Mirror(reflecting: heading).children.first?.value,
              let text = child(fields, "text") as? String else { return nil }
        return parts(text: text, large: some(child(fields, "enrichedTextRange")) as? Range<String.Index>)
    }

    // One entry per section: [enum case, [small line, title]], with an empty heading where it has none.
    // An unreadable item is NSNull; nil means the model is not where it was found.
    @objc(sectionsOf:) static func sections(of page: AnyObject?) -> NSArray? {
        sections(of: page, items: nil, generation: nil)
    }

    private static func objectGetter(_ owner: NSObject, _ name: String) -> NSObject? {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(object_getClass(owner), selector),
              method_getNumberOfArguments(method) == 2 else { return nil }
        let result = method_copyReturnType(method)
        defer { free(result) }
        guard strcmp(result, "@") == 0 else { return nil }
        return owner.perform(selector)?.takeUnretainedValue() as? NSObject
    }

    private static func generation(of snapshot: Any) -> NSObject? {
        guard let dataSourceSnapshot = child(snapshot, "dataSourceSnapshot"),
              let wrapper = child(dataSourceSnapshot, "_implWrapper"),
              let impl = child(wrapper, "impl") as? NSObject,
              let state = objectGetter(impl, "state") else { return nil }
        return objectGetter(state, "generationID")
    }

    // Identifiers can be reused with different props. Only the model that produced this snapshot may
    // classify it; a leading model keeps the prior generation, while a trailing model is unavailable.
    @objc(sectionsOf:items:generation:)
    static func sections(of page: AnyObject?, items identifiers: NSArray?, generation wanted: NSObject?) -> NSArray? {
        guard let page, let renderer = ivar(page, "collectionViewRenderer"),
              let source = ivar(renderer, "contentDataSource") else { return nil }
        let snapshot: Any?
        if let wanted {
            snapshot = ["contentSnapshot", "previousContentSnapshot"].compactMap { some(child(source, $0)) }
                .first { generation(of: $0)?.isEqual(wanted) == true }
        } else {
            snapshot = child(source, "contentSnapshot")
        }
        guard let snapshot,
              let sections = child(snapshot, "sections"),
              let items = child(snapshot, "items") else { return nil }
        var byItem: [AnyHashable: Any] = [:]
        let entries = Mirror(reflecting: items), sectionList = Mirror(reflecting: sections)
        guard entries.displayStyle == .dictionary, sectionList.displayStyle == .collection else { return nil }
        for pair in entries.children {
            let both = Mirror(reflecting: pair.value).children.map(\.value)
            if both.count == 2, let item = both[0] as? AnyHashable { byItem[item] = both[1] }
        }
        let firstItems: [Any?] = identifiers?.map { $0 } ?? sectionList.children.map {
            child($0.value, "items").flatMap {
                let list = Mirror(reflecting: $0)
                return list.displayStyle == .collection ? list.children.first?.value : nil
            }
        }
        let headings = firstItems.map { identifier -> Any in
            guard let first = identifier as? AnyHashable,
                  let entry = byItem[first], let item = child(entry, "item"),
                  let configuration = child(item, "configuration"), let props = child(configuration, "props"),
                  Mirror(reflecting: props).displayStyle == .enum else { return NSNull() }
            return [Mirror(reflecting: props).children.first?.label ?? "", parts(props: props) ?? []] as [Any]
        }
        return headings as NSArray
    }

    @objc(headingsOf:) static func headings(of page: AnyObject?) -> NSArray? {
        guard let sections = sections(of: page) else { return nil }
        return sections.map { entry -> Any in
            guard let fields = entry as? [Any], let heading = fields[1] as? [String], heading.count == 2 else { return NSNull() }
            return heading
        } as NSArray
    }
}
