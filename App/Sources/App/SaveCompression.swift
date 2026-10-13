// Gearforge — LZFSE save compression via Apple's Compression framework (absent on Linux typecheck builds).

import Foundation
import FactoryCore
#if canImport(Compression)
import Compression

struct LZFSECompressor: SaveCompressor {
    func compress(_ bytes: [UInt8]) -> [UInt8] {
        guard !bytes.isEmpty else { return [] }
        let cap = bytes.count + 4096
        var out = [UInt8](repeating: 0, count: cap)
        let n = bytes.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                compression_encode_buffer(dst.baseAddress!, cap, src.baseAddress!, bytes.count, nil, COMPRESSION_LZFSE)
            }
        }
        return n > 0 ? Array(out[0..<n]) : []
    }

    func decompress(_ bytes: [UInt8]) throws -> [UInt8] {
        var cap = max(1 << 16, bytes.count * 6)
        while cap < 1 << 30 {
            var out = [UInt8](repeating: 0, count: cap)
            let n = bytes.withUnsafeBufferPointer { src in
                out.withUnsafeMutableBufferPointer { dst in
                    compression_decode_buffer(dst.baseAddress!, cap, src.baseAddress!, bytes.count, nil, COMPRESSION_LZFSE)
                }
            }
            if n == 0 { throw SaveError.decompressionFailed("lzfse") }
            if n < cap { return Array(out[0..<n]) }
            cap *= 2
        }
        throw SaveError.decompressionFailed("too large")
    }
}

func makeCompressor() -> SaveCompressor? { LZFSECompressor() }
#else
func makeCompressor() -> SaveCompressor? { nil }
#endif
