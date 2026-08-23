import ArgumentParser
import AudioToolbox
import CoreAudio
import Foundation

/// Controls which microphone Parrot opens without changing the system-wide
/// input selection.
enum AudioInputPreference: String, CaseIterable, ExpressibleByArgument {
    /// Avoid Bluetooth call mode when a built-in microphone is available.
    /// Otherwise, use the system-default input.
    case automatic

    /// Always follow the system-default input, including a Bluetooth headset.
    case system

    /// Always use the Mac's built-in microphone.
    case builtIn = "built-in"
}

struct AudioInputDevice {
    let id: AudioDeviceID
    let name: String
    let transportType: UInt32

    var isBluetooth: Bool {
        transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE
    }
}

enum AudioInputError: Error, LocalizedError {
    case noDefaultInput
    case noBuiltInInput
    case deviceEnumerationFailed(OSStatus)
    case propertyReadFailed(String, OSStatus)
    case inputNodeUnavailable
    case deviceSelectionFailed(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .noDefaultInput:
            return "no system-default audio input is available"
        case .noBuiltInInput:
            return "no built-in microphone is available"
        case .deviceEnumerationFailed(let status):
            return "could not enumerate audio devices (CoreAudio status \(status))"
        case .propertyReadFailed(let property, let status):
            return "could not read audio device \(property) (CoreAudio status \(status))"
        case .inputNodeUnavailable:
            return "the audio input node is unavailable"
        case .deviceSelectionFailed(let name, let status):
            return "could not select audio input \(name) (CoreAudio status \(status))"
        }
    }
}

enum AudioInputDevices {
    static func resolve(_ preference: AudioInputPreference) throws -> AudioInputDevice {
        let defaultInput = try defaultInputDevice()

        switch preference {
        case .system:
            return defaultInput
        case .builtIn:
            guard let builtIn = try allInputDevices().first(where: {
                $0.transportType == kAudioDeviceTransportTypeBuiltIn
            }) else {
                throw AudioInputError.noBuiltInInput
            }
            return builtIn
        case .automatic:
            guard defaultInput.isBluetooth else { return defaultInput }
            return try allInputDevices().first(where: {
                $0.transportType == kAudioDeviceTransportTypeBuiltIn
            }) ?? defaultInput
        }
    }

    static func select(_ device: AudioInputDevice, on audioUnit: AudioUnit?) throws {
        guard let audioUnit else { throw AudioInputError.inputNodeUnavailable }
        var deviceID = device.id
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioInputError.deviceSelectionFailed(device.name, status)
        }
    }

    private static func defaultInputDevice() throws -> AudioInputDevice {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw AudioInputError.noDefaultInput
        }
        return try describe(deviceID)
    }

    private static func allInputDevices() throws -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard status == noErr else {
            throw AudioInputError.deviceEnumerationFailed(status)
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(kAudioObjectUnknown), count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        )
        guard status == noErr else {
            throw AudioInputError.deviceEnumerationFailed(status)
        }

        return try deviceIDs.compactMap { deviceID in
            guard try hasInputStreams(deviceID) else { return nil }
            return try describe(deviceID)
        }
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr else {
            throw AudioInputError.propertyReadFailed("input streams", status)
        }
        return size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private static func describe(_ deviceID: AudioDeviceID) throws -> AudioInputDevice {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var status = AudioObjectGetPropertyData(
            deviceID,
            &nameAddress,
            0,
            nil,
            &nameSize,
            &unmanagedName
        )
        guard status == noErr, let name = unmanagedName?.takeUnretainedValue() else {
            throw AudioInputError.propertyReadFailed("name", status)
        }

        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        status = AudioObjectGetPropertyData(
            deviceID,
            &transportAddress,
            0,
            nil,
            &transportSize,
            &transportType
        )
        guard status == noErr else {
            throw AudioInputError.propertyReadFailed("transport type", status)
        }

        return AudioInputDevice(
            id: deviceID,
            name: name as String,
            transportType: transportType
        )
    }
}
