import Foundation
import os

struct Track: Codable { var title, artist, uri: String }
struct State: Codable {
    var line = "lyrics", nextLine = "", title = "", artist = ""
    var translation: String?, cover: Data?
    var tracks: [Track] = []
}
var encodes = 0
struct CountingEncoder {
    func encode(_ state: State) throws -> Data {
        encodes += 1
        return try JSONEncoder().encode(state)
    }
}
let log = Logger(), maxStateBytes = 3800
func budget(_ state: inout State) -> Bool {
    // PRODUCTION BUDGET
    return true
}
func check(_ state: inout State, _ expected: (Int) -> Bool) {
    encodes = 0
    guard budget(&state), expected(encodes), let data = try? JSONEncoder().encode(state), data.count <= maxStateBytes else {
        fputs("FAIL activity budget: \(encodes) encodings\n", stderr)
        exit(1)
    }
}
var small = State()
check(&small) { $0 == 1 }
small.cover = Data(repeating: 0, count: 4000)
check(&small) { $0 == 2 }
guard small.cover == nil, small.line == "lyrics" else { exit(1) }
small.line = String(repeating: "🎵\"\\", count: 1000)
small.tracks = [Track(title: "next", artist: "", uri: "spotify:track:next")]
check(&small) { $0 > 1 }
guard !small.line.isEmpty, small.tracks.first?.uri == "spotify:track:next" else { exit(1) }
print("PASS activity encoded sizes, cover removal and escaped UTF-8 trimming")
