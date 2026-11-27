import Foundation
import SwiftShims

// Mirror.Children produces a *value* even when a caller only wants its label. Look up the
// name and ownership in the same runtime metadata Mirror uses, then ask for just that child.
@_silgen_name("swift_reflectionMirror_recursiveCount")
private func fieldCount(_ type: Any.Type) -> Int
@_silgen_name("swift_reflectionMirror_displayStyle")
private func storageStyle<T>(_ value: T) -> CChar
@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
private func fieldType(_ type: Any.Type, _ index: Int, _ field: UnsafeMutablePointer<_FieldReflectionMetadata>) -> Any.Type
private typealias FreeLabel = @convention(c) (UnsafePointer<CChar>?) -> Void
@_silgen_name("swift_reflectionMirror_subscript")
private func fieldValue<T>(_ value: T, _ type: Any.Type, _ index: Int,
                           _ label: UnsafeMutablePointer<UnsafePointer<CChar>?>,
                           _ free: UnsafeMutablePointer<FreeLabel?>) -> Any

private protocol OptionalField { static var wrapped: Any.Type { get } }
extension Optional: OptionalField { fileprivate static var wrapped: Any.Type { Wrapped.self } }

@objc(SGStoredField)
final class SGStoredField: NSObject {
    private typealias Location = (Any.Type, Int, Any.Type)
    private struct Key: Hashable { let type: ObjectIdentifier; let name: String }
    private static let lock = NSLock()
    // Store declarations (including absent ones), never an instance or a field value.
    private static var locations = [Key: Location?]()

    private static func locate(_ value: Any, _ name: String) -> Location? {
        let key = Key(type: ObjectIdentifier(type(of: value)), name: name)
        lock.lock()
        if let known = locations[key] { lock.unlock(); return known }
        lock.unlock()
        let found = find(value, name)
        lock.lock()
        locations[key] = .some(found)
        lock.unlock()
        return found
    }

    private static func find(_ value: Any, _ name: String) -> Location? {
        // An enum's child count depends on its *value*. Never query its fields by metatype,
        // even if CustomReflectable presents it as a struct.
        let style = UInt8(bitPattern: storageStyle(value))
        guard style == UInt8(ascii: "c") || style == UInt8(ascii: "s") || style == UInt8(ascii: "t") else { return nil }
        var owner: Any.Type? = type(of: value)
        while let current = owner {
            let parent: AnyClass? = (current as? AnyClass).flatMap { class_getSuperclass($0) }
            let start = parent.map(fieldCount) ?? 0
            let end = fieldCount(current)
            guard start <= end else { return nil }
            for i in start..<end {
                var field = _FieldReflectionMetadata()
                let type = fieldType(current, i, &field)
                defer { field.freeFunc?(field.name) }
                if let label = field.name, String(cString: label) == name {
                    return field.isStrong ? (current, i - start, type) : nil
                }
            }
            owner = parent
        }
        return nil
    }

    static func child(_ value: Any, _ name: String) -> Any? {
        guard let (owner, index, _) = locate(value, name) else { return nil }
        var label: UnsafePointer<CChar>?
        var free: FreeLabel?
        let result = fieldValue(value, owner, index, &label, &free)
        defer { free?(label) }
        return result
    }

    // Swift UIView? fields have an empty Objective-C ivar encoding. An empty encoding
    // alone must never authorize object_getIvar, even if the slot still has the old name.
    @objc(supportsField:on:ofClass:)
    static func supports(_ name: String, on object: AnyObject, of expected: AnyClass) -> Bool {
        guard let ivar = class_getInstanceVariable(type(of: object), name),
              let encoding = ivar_getTypeEncoding(ivar) else { return false }
        if UInt8(bitPattern: encoding.pointee) == UInt8(ascii: "@") { // @"Class" in Objective-C owners
            let declaration = String(cString: encoding)
            guard declaration.hasPrefix("@\""), declaration.hasSuffix("\""),
                  let cls = NSClassFromString(String(declaration.dropFirst(2).dropLast())) as? NSObject.Type
            else { return false }
            return cls.isSubclass(of: expected)
        }
        guard encoding.pointee == 0, let (_, _, type) = locate(object, name) else { return false }
        let base = (type as? OptionalField.Type)?.wrapped ?? type
        return (base as? NSObject.Type)?.isSubclass(of: expected) == true
    }

    @objc(field:on:ofClass:)
    static func objectField(_ name: String, on object: AnyObject, of expected: AnyClass) -> NSObject? {
        guard let ivar = class_getInstanceVariable(type(of: object), name),
              let encoding = ivar_getTypeEncoding(ivar) else { return nil }
        let value: NSObject?
        if UInt8(bitPattern: encoding.pointee) == UInt8(ascii: "@") {
            value = object_getIvar(object, ivar) as? NSObject
        } else {
            guard encoding.pointee == 0 else { return nil }
            value = child(object, name) as? NSObject
        }
        return value?.isKind(of: expected) == true ? value : nil
    }
}

// 9.1.90's CreativeWorkPageViewController keeps its identity here. Swift reflection reads the
// named fields without depending on offsets or importing Spotify's modules. A changed shape yields nil.
@objc(SGAlbumQueuePage)
public final class SGAlbumQueuePage: NSObject {
    @objc public static func albumURI(_ controller: AnyObject) -> String? {
        var value: Any = controller
        for field in ["template", "creativeWork", "uri"] {
            guard let next = SGStoredField.child(value, field) else { return nil }
            value = next
        }
        guard let url = value as? URL, url.absoluteString.hasPrefix("spotify:album:") else { return nil }
        return url.absoluteString
    }
}
