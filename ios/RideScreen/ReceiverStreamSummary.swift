// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum ReceiverStreamFraming: String, Equatable {
    case annexB
    case unknown
}

struct ReceiverStreamSummary: Equatable {
    let statusCode: Int?
    let contentType: String?
    let bytesObserved: Int
    let framing: ReceiverStreamFraming
    let nalTypeCounts: [Int: Int]

    static func inspect(
        _ data: Data,
        headers: [String: String],
        statusCode: Int?
    ) -> ReceiverStreamSummary {
        let contentType = headers.first { key, _ in
            key.caseInsensitiveCompare("Content-Type") == .orderedSame
        }?.value
            .split(separator: ";", maxSplits: 1)
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        let bytes = [UInt8](data)
        var counts: [Int: Int] = [:]
        var index = 0
        while index + 3 < bytes.count {
            let headerIndex: Int?
            let prefixLength: Int
            if index + 4 < bytes.count,
               bytes[index] == 0, bytes[index + 1] == 0,
               bytes[index + 2] == 0, bytes[index + 3] == 1 {
                prefixLength = 4
                headerIndex = index + 4
            } else if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
                prefixLength = 3
                headerIndex = index + 3
            } else {
                index += 1
                continue
            }

            if let headerIndex, headerIndex < bytes.count {
                let type = Int(bytes[headerIndex] & 0x1F)
                if (1...23).contains(type) {
                    counts[type, default: 0] += 1
                }
            }
            index += prefixLength
        }

        return ReceiverStreamSummary(
            statusCode: statusCode,
            contentType: contentType,
            bytesObserved: data.count,
            framing: counts.isEmpty ? .unknown : .annexB,
            nalTypeCounts: counts
        )
    }
}
