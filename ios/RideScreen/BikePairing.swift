// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import NetworkExtension
import Security
import SwiftUI

struct BikePairing: Identifiable {
    let id = UUID()
    let ssid: String
    let password: String
    let suggestedName: String
    let modelID: String?
    let mac: String?

    static func parse(_ raw: String) -> Result<BikePairing, BikePairingError> {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: #"(?i)^CARBIT[0-9A-F]{12}$"#, options: .regularExpression) != nil {
            return .failure(.phoneHotspot)
        }

        guard let components = URLComponents(string: value),
              let items = components.queryItems, !items.isEmpty else {
            return .failure(.notPairingQR)
        }

        var fields: [String: String] = [:]
        for item in items {
            fields[item.name.lowercased()] = item.value ?? ""
        }

        let ssid = fields["ssid"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = fields["pwd"] ?? ""
        let action = Int(fields["action"] ?? "") ?? 0

        if (action & 128) != 0 || (ssid.isEmpty && fields["bm"] != nil) {
            return .failure(.phoneHotspot)
        }
        if (action & 8) != 0 && (action & 3) == 0 {
            return .failure(.p2pOnly)
        }
        guard (action & 3) != 0 else { return .failure(.notAccessPoint) }
        guard !ssid.isEmpty, !password.isEmpty else { return .failure(.missingCredentials) }
        guard ssid.utf8.count <= 32,
              !ssid.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              password.utf8.count <= 64 else {
            return .failure(.invalidCredentials)
        }

        let name = fields["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mac = fields["mac"] ?? fields["bm"]
        return .success(BikePairing(
            ssid: ssid,
            password: password,
            suggestedName: (name?.isEmpty == false ? name : nil) ?? ssid,
            modelID: fields["modelid"],
            mac: mac
        ))
    }
}

enum BikePairingError: LocalizedError {
    case notPairingQR
    case phoneHotspot
    case p2pOnly
    case notAccessPoint
    case missingCredentials
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .notPairingQR:
            return "This QR code does not contain a supported bike Wi-Fi pairing link. Open the MotoPlay or EasyConnect pairing QR on the dash and try again."
        case .phoneHotspot:
            return "This dash expects the phone to provide a hotspot. That connection mode is not part of this iPhone setup yet."
        case .p2pOnly:
            return "This QR code uses Wi-Fi Direct. This first iPhone setup supports Wi-Fi access points only."
        case .notAccessPoint:
            return "This QR code does not advertise a Wi-Fi access point for the iPhone to join."
        case .missingCredentials:
            return "The pairing QR is missing its Wi-Fi name or password. Keep the MotoPlay or EasyConnect pairing code visible and scan again."
        case .invalidCredentials:
            return "The Wi-Fi details in this QR code are outside the supported limits."
        }
    }
}

struct Bike: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let ssid: String
    let modelID: String?
    let mac: String?
    let addedAt: Date
}

@MainActor
final class BikeStore: ObservableObject {
    @Published private(set) var bikes: [Bike] = []
    @Published private(set) var errorMessage: String?

    private let fileURL: URL
    private let credentials = BikeCredentialStore()
    private var canWrite = true

    init() {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        fileURL = supportDirectory.appendingPathComponent("RideScreen", isDirectory: true)
            .appendingPathComponent("bikes.json")
        load()
    }

    func add(_ pairing: BikePairing, name: String) throws -> Bike {
        guard canWrite else { throw BikeStoreError.readOnly }
        let bike = Bike(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? pairing.suggestedName
                : name.trimmingCharacters(in: .whitespacesAndNewlines),
            ssid: pairing.ssid,
            modelID: pairing.modelID,
            mac: pairing.mac,
            addedAt: .now
        )
        try credentials.save(pairing.password, for: bike.id)
        do {
            try persist(bikes + [bike])
            bikes.append(bike)
            errorMessage = nil
            return bike
        } catch {
            try? credentials.delete(for: bike.id)
            throw error
        }
    }

    func password(for bike: Bike) throws -> String {
        try credentials.load(for: bike.id)
    }

    func remove(_ bike: Bike) throws {
        guard canWrite else { throw BikeStoreError.readOnly }
        let updated = bikes.filter { $0.id != bike.id }
        try persist(updated)
        bikes = updated
        try? credentials.delete(for: bike.id)
        errorMessage = nil
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            bikes = try JSONDecoder().decode([Bike].self, from: Data(contentsOf: fileURL))
        } catch {
            canWrite = false
            errorMessage = "Saved bikes could not be read. The existing file was left untouched."
        }
    }

    private func persist(_ candidate: [Bike]) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(candidate).write(to: fileURL, options: .atomic)
        } catch {
            errorMessage = "Saved bikes could not be written. Your previous bike list was left untouched."
            throw BikeStoreError.persistenceFailed
        }
    }
}

private enum BikeStoreError: LocalizedError {
    case readOnly
    case persistenceFailed
    case credentialUnavailable
    case keychain(Int32)

    var errorDescription: String? {
        switch self {
        case .readOnly:
            return "Saved bikes are read-only because the existing bike file could not be read."
        case .persistenceFailed:
            return "The bike could not be saved. The previous bike list was preserved."
        case .credentialUnavailable:
            return "The saved Wi-Fi password is unavailable. Scan the bike QR again."
        case .keychain(let status):
            return "The Wi-Fi password could not be stored securely (Keychain error \(status))."
        }
    }
}

private struct BikeCredentialStore {
    private let service = Bundle.main.bundleIdentifier ?? "dev.zanderp.opencfmoto.ios"

    func save(_ password: String, for id: UUID) throws {
        let query = baseQuery(for: id)
        let attributes: [String: Any] = [kSecValueData as String: Data(password.utf8)]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(password.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw BikeStoreError.keychain(status) }
        } else if updateStatus != errSecSuccess {
            throw BikeStoreError.keychain(updateStatus)
        }
    }

    func load(for id: UUID) throws -> String {
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            if status != errSecSuccess { throw BikeStoreError.keychain(status) }
            throw BikeStoreError.credentialUnavailable
        }
        return password
    }

    func delete(for id: UUID) throws {
        let status = SecItemDelete(baseQuery(for: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BikeStoreError.keychain(status)
        }
    }

    private func baseQuery(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
    }
}

enum BikeWiFiResult {
    case accepted
    case alreadyAssociated
    case failed(String)

    var message: String {
        switch self {
        case .accepted:
            return "iOS accepted the Wi-Fi setup request. This does not confirm a connection to the bike display."
        case .alreadyAssociated:
            return "iOS reports that this iPhone is already on the bike Wi-Fi. The bike display link is not checked yet."
        case .failed(let message):
            return message
        }
    }
}

enum BikeWiFiConnector {
    static func join(ssid: String, password: String) async -> BikeWiFiResult {
        let configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
        configuration.joinOnce = false
        return await withCheckedContinuation { continuation in
            NEHotspotConfigurationManager.shared.apply(configuration) { error in
                guard let error else {
                    continuation.resume(returning: .accepted)
                    return
                }
                let nsError = error as NSError
                if nsError.domain == NEHotspotConfigurationErrorDomain,
                   nsError.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
                    continuation.resume(returning: .alreadyAssociated)
                } else {
                    continuation.resume(returning: .failed(Self.message(for: nsError)))
                }
            }
        }
    }

    static func remove(ssid: String) {
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
    }

    private static func message(for error: NSError) -> String {
        guard error.domain == NEHotspotConfigurationErrorDomain,
              let code = NEHotspotConfigurationError(rawValue: error.code) else {
            return "iOS could not add this Wi-Fi network (\(error.domain), code \(error.code)). Try Manual Wi-Fi setup."
        }
        switch code {
        case .userDenied:
            return "The iOS Wi-Fi request was declined (code \(error.code)). Try again or use Manual Wi-Fi setup."
        case .invalidWPAPassphrase, .invalidWEPPassphrase, .invalidSSID:
            return "iOS rejected the Wi-Fi details (code \(error.code)). Check the bike QR code and try Manual Wi-Fi setup."
        case .applicationIsNotInForeground:
            return "RideScreen must stay in the foreground to request Wi-Fi (code \(error.code)). Try again or use Manual Wi-Fi setup."
        default:
            return "iOS could not add this Wi-Fi network (code \(error.code)). Try Manual Wi-Fi setup."
        }
    }
}
