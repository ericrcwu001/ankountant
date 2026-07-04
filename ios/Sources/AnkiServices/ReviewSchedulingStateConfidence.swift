public import AnkiKit
import AnkiProto
public import Foundation
import SwiftProtobuf

public enum ReviewSchedulingStateConfidenceError: Error, Equatable, LocalizedError {
    case invalidCustomData(String)
    case nonObjectCustomData

    public var errorDescription: String? {
        switch self {
        case let .invalidCustomData(message):
            "Review scheduling custom data is invalid JSON: \(message)"
        case .nonObjectCustomData:
            "Review scheduling custom data must be a JSON object."
        }
    }
}

public extension ReviewSchedulingStates {
    func recordingConfidence(_ confidence: String?) throws -> ReviewSchedulingStates {
        guard let confidence = confidence?.trimmingCharacters(in: .whitespacesAndNewlines),
              !confidence.isEmpty else {
            return self
        }

        var customData = try currentCustomDataDictionary()
        customData["cf"] = confidence
        let encodedCustomData = try encodeCustomData(customData)

        return ReviewSchedulingStates(
            current: current,
            again: try again.withCustomData(encodedCustomData),
            hard: try hard.withCustomData(encodedCustomData),
            good: try good.withCustomData(encodedCustomData),
            easy: try easy.withCustomData(encodedCustomData)
        )
    }

    private func currentCustomDataDictionary() throws -> [String: Any] {
        try current.customDataDictionary()
    }
}

private extension SchedulingStateToken {
    func withCustomData(_ customData: String) throws -> SchedulingStateToken {
        var state = try Anki_Scheduler_SchedulingState(serializedBytes: bytes)
        state.customData = customData
        return SchedulingStateToken(try state.serializedData())
    }

    func customDataDictionary() throws -> [String: Any] {
        let state = try Anki_Scheduler_SchedulingState(serializedBytes: bytes)
        guard !state.customData.isEmpty else { return [:] }
        let data = Data(state.customData.utf8)
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any] else {
                throw ReviewSchedulingStateConfidenceError.nonObjectCustomData
            }
            return dictionary
        } catch let error as ReviewSchedulingStateConfidenceError {
            throw error
        } catch {
            throw ReviewSchedulingStateConfidenceError.invalidCustomData(error.localizedDescription)
        }
    }
}

private func encodeCustomData(_ customData: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: customData, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}
