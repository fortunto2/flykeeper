import Foundation

/// A cursor over one of the app's small packed files (`.frt`, `.fsk`). Written once because
/// it was written twice: both readers open-coded the magic check and walked byte offsets by
/// hand, and neither bounds-checked after the header, so a truncated file read past the end
/// of its own buffer.
final class PackedReader {
    private let data: Data
    private var offset: Int

    init?(url: URL, magic: String) {
        guard let data = try? Data(contentsOf: url),
              data.count >= magic.utf8.count,
              data.prefix(magic.utf8.count) == Data(magic.utf8) else { return nil }
        self.data = data
        offset = magic.utf8.count
    }

    var remaining: Int { data.count - offset }

    func u32() -> UInt32? { read(UInt32.self) }
    func f32() -> Float? { read(Float.self) }

    private func read<T>(_ type: T.Type) -> T? {
        let size = MemoryLayout<T>.size
        guard remaining >= size else { return nil }
        defer { offset += size }
        return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
    }
}
