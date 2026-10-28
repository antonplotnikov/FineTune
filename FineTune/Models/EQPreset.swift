import Foundation

enum EQPreset: String, CaseIterable, Identifiable {
    // Utility
    case flat
    case bassBoost
    case bassCut
    case trebleBoost
    // Speech
    case vocalClarity
    case podcast
    case spokenWord
    // Listening
    case loudness
    case lateNight
    case smallSpeakers
    // Music
    case rock
    case pop
    case electronic
    case jazz
    case classical
    case hipHop
    case rnb
    case deep
    case acoustic
    // Media
    case movie
    // Games
    case fpsFootsteps
    case competitive
    case immersive
    case mobaRpg
    case voiceChat
    // Games (parametric)
    case footstepsPro
    case competitivePro
    case cinematicPro
    case voiceChatPro
    case gunfireTamer

    var id: String { rawValue }

    // MARK: - Categories

    enum Category: String, CaseIterable, Identifiable {
        case utility = "Utility"
        case speech = "Speech"
        case listening = "Listening"
        case music = "Music"
        case media = "Media"
        case games = "Games"

        var id: String { rawValue }
    }

    var category: Category {
        switch self {
        case .flat, .bassBoost, .bassCut, .trebleBoost:
            return .utility
        case .vocalClarity, .podcast, .spokenWord:
            return .speech
        case .loudness, .lateNight, .smallSpeakers:
            return .listening
        case .rock, .pop, .electronic, .jazz, .classical, .hipHop, .rnb, .deep, .acoustic:
            return .music
        case .movie:
            return .media
        case .fpsFootsteps, .competitive, .immersive, .mobaRpg, .voiceChat,
             .footstepsPro, .competitivePro, .cinematicPro, .voiceChatPro, .gunfireTamer:
            return .games
        }
    }

    static func presets(for category: Category) -> [EQPreset] {
        allCases.filter { $0.category == category }
    }

    var name: String {
        switch self {
        case .flat: return "Flat"
        case .bassBoost: return "Bass Boost"
        case .bassCut: return "Bass Cut"
        case .trebleBoost: return "Treble Boost"
        case .vocalClarity: return "Vocal Clarity"
        case .podcast: return "Podcast"
        case .spokenWord: return "Spoken Word"
        case .loudness: return "Loudness"
        case .lateNight: return "Late Night"
        case .smallSpeakers: return "Small Speakers"
        case .rock: return "Rock"
        case .pop: return "Pop"
        case .electronic: return "Electronic"
        case .jazz: return "Jazz"
        case .classical: return "Classical"
        case .hipHop: return "Hip-Hop"
        case .rnb: return "R&B"
        case .deep: return "Deep"
        case .acoustic: return "Acoustic"
        case .movie: return "Movie"
        case .fpsFootsteps: return "FPS Footsteps"
        case .competitive: return "Competitive"
        case .immersive: return "Immersive"
        case .mobaRpg: return "MOBA / RPG"
        case .voiceChat: return "Voice Chat"
        case .footstepsPro: return "Footsteps Pro"
        case .competitivePro: return "Competitive Pro"
        case .cinematicPro: return "Cinematic Pro"
        case .voiceChatPro: return "Voice Chat Pro"
        case .gunfireTamer: return "Gunfire Tamer"
        }
    }

    // Bands: 31, 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k
    var settings: EQSettings {
        switch self {
        // MARK: - Utility
        case .flat:
            // All neutral
            return EQSettings(bandGains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        case .bassBoost:
            // Boost lows, cut 250Hz to prevent muddiness
            return EQSettings(bandGains: [6, 6, 5, -1, 0, 0, 0, 0, 0, 0])
        case .bassCut:
            // Reduce low end
            return EQSettings(bandGains: [-6, -5, -4, -2, 0, 0, 0, 0, 0, 0])
        case .trebleBoost:
            // Gentle rise into highs for clarity and air
            return EQSettings(bandGains: [0, 0, 0, 0, 0, 0, 2, 4, 5, 6])

        // MARK: - Speech
        case .vocalClarity:
            // Cut rumble & muddiness, boost presence (2-4kHz)
            return EQSettings(bandGains: [-4, -2, -1, -3, 0, 2, 4, 4, 1, 0])
        case .podcast:
            // Optimized for speech with some music/effects
            return EQSettings(bandGains: [-6, -4, -2, -1, 0, 2, 4, 3, 1, 0])
        case .spokenWord:
            // Audiobooks, lectures - aggressive bass cut, max intelligibility
            return EQSettings(bandGains: [-8, -6, -3, -2, 0, 2, 4, 4, 2, 0])

        // MARK: - Listening
        case .loudness:
            // "Smile curve" - boost lows & highs for low-volume listening
            return EQSettings(bandGains: [5, 4, 2, 0, -2, -2, 0, 2, 4, 5])
        case .lateNight:
            // Neighbor-friendly: heavy bass cut, presence boost
            return EQSettings(bandGains: [-6, -4, -2, 0, 0, 1, 2, 2, 1, 0])
        case .smallSpeakers:
            // Laptop/MacBook speakers: boost reproducible bass, add clarity
            return EQSettings(bandGains: [3, 4, 5, 2, 0, 1, 2, 2, 1, 0])

        // MARK: - Music
        case .rock:
            // Punchy bass, forward guitars & vocals
            return EQSettings(bandGains: [4, 3, 2, 0, -1, 0, 2, 3, 2, 1])
        case .pop:
            // Bright, punchy, vocal-forward
            return EQSettings(bandGains: [3, 3, 2, 0, -1, 1, 2, 3, 3, 4])
        case .electronic:
            // Heavy sub-bass, scooped mids, crisp highs
            return EQSettings(bandGains: [7, 6, 4, 0, -2, -2, 1, 3, 4, 3])
        case .jazz:
            // Warm lows, smooth mids, gentle highs
            return EQSettings(bandGains: [3, 2, 1, 0, 0, 0, 1, 2, 2, 1])
        case .classical:
            // Nearly flat, gentle high "air" for detail
            return EQSettings(bandGains: [0, 0, 0, 0, 0, 0, 1, 2, 2, 2])
        case .hipHop:
            // Heavy sub-bass for 808s, crisp highs for hi-hats
            return EQSettings(bandGains: [6, 5, 4, 0, -1, 0, 2, 3, 4, 3])
        case .rnb:
            // Warm bass, recessed mids, smooth vocals
            return EQSettings(bandGains: [4, 4, 3, 1, -1, 0, 2, 3, 3, 2])
        case .deep:
            // Deep house, ambient, lo-fi: sub-bass, scooped mids
            return EQSettings(bandGains: [5, 6, 4, 1, -2, -2, 0, 1, 2, 1])
        case .acoustic:
            // Warm low-mids, natural sparkle
            return EQSettings(bandGains: [0, 1, 2, 2, 1, 0, 1, 2, 2, 1])

        // MARK: - Media
        case .movie:
            // Cinematic: bass rumble, dialogue clarity, effects detail
            return EQSettings(bandGains: [4, 4, 3, -1, -1, 1, 3, 3, 2, 1])

        // MARK: - Games
        case .fpsFootsteps:
            // Cut explosion/rumble energy, lift the 2-8 kHz footstep and reload band
            return EQSettings(bandGains: [-8, -6, -3, -1, 0, 2, 5, 6, 4, 1])
        case .competitive:
            // Maximum positional clarity: heavy low cut, forward upper mids and air
            return EQSettings(bandGains: [-12, -9, -5, -2, 0, 1.5, 4.5, 6, 4, 1])
        case .immersive:
            // Wide, cinematic: weighty low end with open highs for ambience
            return EQSettings(bandGains: [6, 5, 3, 0, -1, 0, 2, 3, 4, 4])
        case .mobaRpg:
            // Keep spell/ability cues and music balanced without harshness
            return EQSettings(bandGains: [3, 3, 2, 0, 0, 1, 3, 3, 2, 1])
        case .voiceChat:
            // Teammate intelligibility over game audio: speech presence, reduced rumble
            return EQSettings(bandGains: [-8, -6, -3, 0, 2, 4, 5, 3, 0, -2])

        // MARK: - Games (parametric)
        case .footstepsPro:
            // Steep rumble cut, scooped low-mids, two narrow lifts on the footstep/gear-rustle band
            return EQSettings(mode: .parametric, parametricBands: ParametricBand.preset([
                (.highPass, 70, 0, 0.7), (.lowShelf, 200, -5, 0.7), (.peaking, 2500, 4, 1.2),
                (.peaking, 4500, 5, 1.5), (.highShelf, 9000, 2.5, 0.7),
            ]), preampDB: -6.5)
        case .competitivePro:
            // Surgical positional clarity: tight low cut, narrow presence peaks, mild air
            return EQSettings(mode: .parametric, parametricBands: ParametricBand.preset([
                (.highPass, 90, 0, 0.8), (.peaking, 250, -4, 1.0), (.peaking, 1200, 2, 1.0),
                (.peaking, 3000, 5, 1.6), (.peaking, 6000, 4, 2.0), (.highShelf, 10000, 1.5, 0.7),
            ]), preampDB: -6.5)
        case .cinematicPro:
            // Weighty sub-bass shelf, cleared low-mids, open top end for story-driven games
            return EQSettings(mode: .parametric, parametricBands: ParametricBand.preset([
                (.lowShelf, 80, 5, 0.7), (.peaking, 300, -2, 1.0), (.peaking, 3000, 1.5, 0.9),
                (.highShelf, 9000, 4, 0.7),
            ]), preampDB: -5.5)
        case .voiceChatPro:
            // Teammate speech first: rumble and hiss out, presence in
            return EQSettings(mode: .parametric, parametricBands: ParametricBand.preset([
                (.highPass, 100, 0, 0.7), (.peaking, 200, -3, 1.0), (.peaking, 1500, 3, 1.0),
                (.peaking, 3500, 4, 1.4), (.lowPass, 12000, 0, 0.7),
            ]), preampDB: -4.7)
        case .gunfireTamer:
            // Tames harsh gunfire/explosion peaks while keeping the low end full
            return EQSettings(mode: .parametric, parametricBands: ParametricBand.preset([
                (.lowShelf, 120, 2, 0.7), (.peaking, 2000, -3, 1.8), (.peaking, 4000, -4, 2.0),
                (.highShelf, 7000, -3, 0.7),
            ]), preampDB: -2)
        }
    }
}
