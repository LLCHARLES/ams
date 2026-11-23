import UIKit

private enum Heading {
    case withText(text: String)
}
private struct Shelf {
    let heading: Heading?
}
private enum Props {
    case shelf(Shelf)
    case musicPreview(Shelf)
}
private struct Configuration {
    let props: Props
}
private struct Item {
    let configuration: Configuration
}
private struct Entry {
    let item: Item
}
private struct Section {
    let items: [Int]
}
private struct ContentSnapshot {
    let sections: [Section]
    let items: [Int: Entry]
    let dataSourceSnapshot: NSDiffableDataSourceSnapshot<Int, Int>
}
private final class ContentDataSource: NSObject {
    var contentSnapshot = ContentSnapshot(sections: [], items: [:], dataSourceSnapshot: .init())
    var previousContentSnapshot: ContentSnapshot?
}
private final class Renderer: NSObject {
    let contentDataSource = ContentDataSource()
}

@objc(ShelfFeedGeneration)
final class ShelfFeedGeneration: NSObject {
    fileprivate let model: ContentSnapshot
    @objc var snapshot: NSDiffableDataSourceSnapshotReference {
        model.dataSourceSnapshot as NSDiffableDataSourceSnapshotReference
    }
    fileprivate init(_ model: ContentSnapshot) { self.model = model }
}

// Only Spotify's model is a fixture. HomeFeed's ivar traversal, Swift reflection, enum and heading
// extraction are compiled unchanged into the executable, alongside UIKit's real diffable source.
@objc(ShelfFeedFixture)
final class ShelfFeedFixture: NSObject {
    @objc static func renderer() -> NSObject { Renderer() }

    @objc(generation:)
    static func generation(_ phase: Int) -> ShelfFeedGeneration {
        let ids = Array(0..<12)
        let props: Props = phase == 1 ? .musicPreview(Shelf(heading: nil)) : .shelf(Shelf(
            heading: .withText(text: phase == 0 ? "Hidden shelf" : "Visible shelf")))
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        for id in phase == 2 ? Array(ids.reversed()) : ids {
            snapshot.appendSections([id])
            snapshot.appendItems([id], toSection: id)
        }
        return ShelfFeedGeneration(ContentSnapshot(
            sections: ids.map { Section(items: [$0]) },
            items: Dictionary(uniqueKeysWithValues: ids.map {
                let itemProps = phase == 2 && $0 % 2 == 0
                    ? Props.shelf(Shelf(heading: .withText(text: "Hidden shelf"))) : props
                return ($0, Entry(item: Item(configuration: Configuration(props: itemProps))))
            }), dataSourceSnapshot: snapshot))
    }

    @objc(publish:renderer:)
    static func publish(_ generation: ShelfFeedGeneration, renderer: NSObject) {
        let source = (renderer as! Renderer).contentDataSource
        source.previousContentSnapshot = source.contentSnapshot
        source.contentSnapshot = generation.model
    }
}
