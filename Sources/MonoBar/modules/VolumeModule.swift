import CoreAudio
import Darwin
import Foundation

@MainActor
extension BarModel {
    func refreshAudioState() {
        outputVolume = readVolume(isInput: false)
        inputVolume = readVolume(isInput: true)
        outputMuted = readMute(isInput: false)
        inputMuted = readMute(isInput: true)
    }

    func adjustVolume(_ target: String, by delta: Int) {
        let isInput = target == "input"
        guard isInput || target == "output", delta != 0,
              let current = readVolume(isInput: isInput) else { return }
        let next = min(100, max(0, current + delta))
        guard setVolume(Float32(next) / 100, isInput: isInput) else { return }
        if isInput { inputVolume = next } else { outputVolume = next }
        notifyChange()
    }

    func volumeValues(isInput: Bool) -> [ModuleValue] {
        let action = isInput ? "toggle:mute-input" : "toggle:mute-output"
        let scrollAction = isInput ? "volume:input" : "volume:output"
        let muted = isInput ? inputMuted == true : outputMuted == true
        let symbol = isInput
            ? (muted ? "mic.slash.fill" : "mic.fill")
            : (muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        let level = isInput ? inputVolume : outputVolume
        let icon = ModuleValue(text: "", action: action, spacingAfter: 3, symbolName: symbol, scrollAction: scrollAction)
        let value = ModuleValue(text: level.map { "\($0)%" } ?? "—", action: action, scrollAction: scrollAction)
        return [icon, value]
    }

    func defaultAudioDevice(isInput: Bool) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    func readVolume(isInput: Bool) -> Int? {
        guard let device = defaultAudioDevice(isInput: isInput) else { return nil }
        let scope = audioScope(isInput: isInput)
        let main = kAudioObjectPropertyElementMain
        let channels = [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)]
        let scalar: Float32
        if let master = readScalar(device, scope: scope, element: main) {
            scalar = master
        } else {
            let channelValues = channels.compactMap { readScalar(device, scope: scope, element: $0) }
            guard !channelValues.isEmpty else { return nil }
            scalar = channelValues.reduce(0, +) / Float32(channelValues.count)
        }
        return Int((min(1, max(0, scalar)) * 100).rounded())
    }

    func setVolume(_ scalar: Float32, isInput: Bool) -> Bool {
        guard let device = defaultAudioDevice(isInput: isInput) else { return false }
        let scope = audioScope(isInput: isInput)
        if setScalar(scalar, device: device, scope: scope, element: kAudioObjectPropertyElementMain) {
            return true
        }
        let channels = [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)]
        return channels.reduce(false) { succeeded, element in
            setScalar(scalar, device: device, scope: scope, element: element) || succeeded
        }
    }

    func readScalar(_ device: AudioDeviceID, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Float32? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
        var scalar: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &scalar)
        return status == noErr ? scalar : nil
    }

    func setScalar(_ scalar: Float32, device: AudioDeviceID, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value = scalar
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        return status == noErr
    }

    func audioScope(isInput: Bool) -> AudioObjectPropertyScope {
        isInput ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
    }

    func readMute(isInput: Bool) -> Bool? {
        guard let device = defaultAudioDevice(isInput: isInput) else { return nil }
        let scope = audioScope(isInput: isInput)
        if let main = readMute(device, scope: scope, element: kAudioObjectPropertyElementMain) { return main }
        let channelValues = [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)]
            .compactMap { readMute(device, scope: scope, element: $0) }
        return channelValues.isEmpty ? nil : channelValues.allSatisfy { $0 }
    }

    func readMute(_ device: AudioDeviceID, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Bool? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: scope, mElement: element)
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        return status == noErr ? muted != 0 : nil
    }

    func toggleMute(isInput: Bool) {
        guard let device = defaultAudioDevice(isInput: isInput),
              let current = readMute(isInput: isInput) else { return }
        let muted: UInt32 = current ? 0 : 1
        let scope = audioScope(isInput: isInput)
        guard setMute(muted, device: device, scope: scope, element: kAudioObjectPropertyElementMain)
                || setMuteChannels(muted, device: device, scope: scope) else { return }
        if isInput { inputMuted = muted != 0 } else { outputMuted = muted != 0 }
        notifyChange()
    }

    func setMuteChannels(_ muted: UInt32, device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        let channels = [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)]
        return channels.reduce(false) { succeeded, element in
            setMute(muted, device: device, scope: scope, element: element) || succeeded
        }
    }

    func setMute(_ muted: UInt32, device: AudioDeviceID, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: scope, mElement: element)
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value = muted
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        return status == noErr
    }
}
