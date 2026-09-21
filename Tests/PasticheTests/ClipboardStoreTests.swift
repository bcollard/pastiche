import XCTest
@testable import Pastiche

/// Uses a temporary folder, never the real history.
@MainActor
final class ClipboardStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastiche-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> ClipboardStore {
        ClipboardStore(settings: .shared, directory: directory)
    }

    private func texts(_ store: ClipboardStore) -> [String] {
        store.items.compactMap(\.text)
    }

    /// Newest first: copying a, b, c gives [c, b, a].
    private func storeWithABC() -> ClipboardStore {
        let store = makeStore()
        for text in ["a", "b", "c"] { store.addText(text, source: nil) }
        return store
    }

    func testNewestCopyIsFirst() {
        XCTAssertEqual(texts(storeWithABC()), ["c", "b", "a"])
    }

    func testMoveToTopPutsTheItemFirst() throws {
        let store = storeWithABC()
        let oldest = try XCTUnwrap(store.items.last)
        store.moveToTop(oldest)
        XCTAssertEqual(texts(store), ["a", "c", "b"])
    }

    func testMoveToTopKeepsEveryItemAndTheCount() throws {
        let store = storeWithABC()
        store.moveToTop(try XCTUnwrap(store.items.last))
        XCTAssertEqual(store.items.count, 3)
        XCTAssertEqual(Set(texts(store)), ["a", "b", "c"])
    }

    func testMoveToTopOfTheFirstItemChangesNothing() throws {
        let store = storeWithABC()
        store.moveToTop(try XCTUnwrap(store.items.first))
        XCTAssertEqual(texts(store), ["c", "b", "a"])
    }

    func testMoveToTopSurvivesARestart() throws {
        let store = storeWithABC()
        store.moveToTop(try XCTUnwrap(store.items.last))
        store.save()
        XCTAssertEqual(texts(makeStore()), ["a", "c", "b"])
    }

    func testCopyingTheSameTextAgainAlsoMovesItToTheTop() {
        let store = storeWithABC()
        store.addText("a", source: nil)
        XCTAssertEqual(texts(store), ["a", "c", "b"])
    }
}
