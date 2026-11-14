import Foundation
import zlib

/// Preserve the HTTP content coding around the rewritten protobuf message.
/// zlib's gzip wrapper also verifies/rebuilds the CRC and uncompressed size.
enum SpotifyConnectContentCoding {
    static func decode(_ data: Data, gzip: Bool) -> Data? {
        transform(data, encoding: false, gzip: gzip, limit: 4 * 1024 * 1024)
    }

    static func encode(_ data: Data, gzip: Bool) -> Data? {
        transform(data, encoding: true, gzip: gzip, limit: 8 * 1024 * 1024)
    }

    private static func transform(_ data: Data, encoding: Bool, gzip: Bool, limit: Int) -> Data? {
        guard !data.isEmpty, data.count <= 4 * 1024 * 1024 else { return nil }
        var stream = z_stream()
        let windowBits: Int32 = gzip ? 31 : 15
        let status: Int32
        if encoding {
            status = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, windowBits,
                                  8, Z_DEFAULT_STRATEGY, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
        } else {
            status = inflateInit2_(&stream, windowBits, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
        }
        guard status == Z_OK else { return nil }
        defer {
            if encoding { deflateEnd(&stream) }
            else { inflateEnd(&stream) }
        }

        var input = [UInt8](data)
        return input.withUnsafeMutableBufferPointer { source -> Data? in
            stream.next_in = source.baseAddress
            stream.avail_in = uInt(source.count)
            var result = Data()
            let chunkSize = 32 * 1024
            var chunk = [UInt8](repeating: 0, count: chunkSize)
            while true {
                let before = stream.avail_in
                let code = chunk.withUnsafeMutableBufferPointer { output -> Int32 in
                    stream.next_out = output.baseAddress
                    stream.avail_out = uInt(output.count)
                    return encoding ? deflate(&stream, Z_FINISH) : inflate(&stream, Z_NO_FLUSH)
                }
                let produced = chunkSize - Int(stream.avail_out)
                guard produced <= limit - result.count else { return nil }
                result.append(contentsOf: chunk.prefix(produced))
                if code == Z_STREAM_END {
                    // Do not silently drop trailing bytes or another gzip member.
                    return stream.avail_in == 0 ? result : nil
                }
                guard code == Z_OK, produced > 0 || stream.avail_in < before else { return nil }
            }
        }
    }
}
