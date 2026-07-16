//
//  CelebrationSoundManager.swift
//  AscendApp
//

import AVFoundation
import Foundation
import QuartzCore

@MainActor
final class CelebrationSoundManager {
    static let shared = CelebrationSoundManager()

    private enum SoundName: String, CaseIterable {
        case countTick = "count_tick_a"
        case statLand = "stat_land"
        case tracePulse = "trace_pulse"
        case lightningStrike = "lightning_strike"
        case coreExplosion = "core_explosion"
    }

    private let engine = AVAudioEngine()
    private let countPlayer = AVAudioPlayerNode()
    private let tracePlayer = AVAudioPlayerNode()
    private let impactPlayer = AVAudioPlayerNode()

    private var buffers: [SoundName: AVAudioPCMBuffer] = [:]
    private var isPrepared = false
    private var lastTracePulseTime: CFTimeInterval = 0

    private init() {}

    func playCountTick() {
        play(.countTick, on: countPlayer, interrupts: true)
    }

    func playStatLand() {
        play(.statLand, on: impactPlayer, interrupts: true)
    }

    func playTracePulse(progress _: Double) {
        // Trace pulse is called rapidly; throttle so it reads as a sweep and avoids audio spam.
        let now = CACurrentMediaTime()
        guard now - lastTracePulseTime >= 0.11 else { return }
        lastTracePulseTime = now
        play(.tracePulse, on: tracePlayer, interrupts: true)
    }

    func playLightningStrike() {
        play(.lightningStrike, on: impactPlayer, interrupts: true)
    }

    func playElectricExplosion() {
        play(.coreExplosion, on: impactPlayer, interrupts: true)
    }

    func playCelebrationCompletion() {
        // Intentionally empty for now. We are only trying the provided files.
    }

    private func play(_ sound: SoundName, on player: AVAudioPlayerNode, interrupts: Bool) {
        prepareIfNeeded()
        guard isPrepared, let buffer = buffers[sound] else { return }

        if !player.isPlaying {
            player.play()
        }

        let options: AVAudioPlayerNodeBufferOptions = interrupts ? [.interrupts] : []
        player.scheduleBuffer(buffer, at: nil, options: options, completionHandler: nil)
    }

    private func prepareIfNeeded() {
        guard !isPrepared else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            for sound in SoundName.allCases {
                if let buffer = try loadBuffer(named: sound.rawValue) {
                    buffers[sound] = buffer
                }
            }

            guard buffers[.countTick] != nil else {
                #if DEBUG
                debugLog("CelebrationSoundManager: required count tick file missing")
                #endif
                return
            }

            let countFormat = buffers[.countTick]!.format
            let traceFormat = buffers[.tracePulse]?.format ?? countFormat
            let impactFormat = buffers[.lightningStrike]?.format
                ?? buffers[.coreExplosion]?.format
                ?? buffers[.statLand]?.format
                ?? countFormat

            engine.attach(countPlayer)
            engine.attach(tracePlayer)
            engine.attach(impactPlayer)
            engine.connect(countPlayer, to: engine.mainMixerNode, format: countFormat)
            engine.connect(tracePlayer, to: engine.mainMixerNode, format: traceFormat)
            engine.connect(impactPlayer, to: engine.mainMixerNode, format: impactFormat)
            try engine.start()
            isPrepared = true
        } catch {
            isPrepared = false
            #if DEBUG
            debugLog("CelebrationSoundManager failed to start: \(error)")
            #endif
        }
    }

    private func loadBuffer(named name: String) throws -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Resources/Audio/Celebration")
            ?? Bundle.main.url(forResource: name, withExtension: "wav") else {
            return nil
        }

        let file = try AVAudioFile(forReading: url)
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount)
        else {
            return nil
        }

        try file.read(into: buffer)
        return buffer
    }
}
