/// Picks a climber's avatar colour from a palette, the same one on every launch.
///
/// `String.hashValue` is reseeded for every process, so a palette indexed by it
/// gave the same climber a different avatar colour each time the app opened.
enum StableAvatarPalette {
    /// FNV-1a over the id's UTF-8 bytes, reduced to `0..<count`.
    static func index(for id: String, count: Int) -> Int {
        guard count > 0 else { return 0 }

        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(count))
    }
}
