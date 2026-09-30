import Foundation

/// Deterministic value noise over course space, so the mountainside at a given spot is the same
/// every time it is built - two course pieces that meet read the same heights along their shared
/// edge, and a rebuilt scene grows the same trees in the same places.
enum MountainNoise {
    /// Coordinates wrap at this many metres so noise inputs stay small on a 300 km climb; a
    /// wrap seam lands once every eight kilometres of course.
    static let period = 8_192.0

    static func hash(_ x: Int, _ y: Int, seed: UInt64 = 0) -> Double {
        var h = UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F
        h ^= seed &* 0x1656_67B1_9E37_79F9
        h = (h ^ (h >> 31)) &* 0xBF58_476D_1CE4_E5B9
        h = (h ^ (h >> 27)) &* 0x94D0_49BB_1331_11EB
        h ^= h >> 31
        return Double(h >> 11) / Double(UInt64(1) << 53)
    }

    /// Smooth noise in `-1...1`.
    static func value(_ x: Double, _ y: Double, seed: UInt64 = 0) -> Double {
        let wx = x.truncatingRemainder(dividingBy: period)
        let wy = y.truncatingRemainder(dividingBy: period)
        let xi = Int(wx.rounded(.down)), yi = Int(wy.rounded(.down))
        let xf = wx - Double(xi), yf = wy - Double(yi)
        let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
        let a = hash(xi, yi, seed: seed), b = hash(xi + 1, yi, seed: seed)
        let c = hash(xi, yi + 1, seed: seed), d = hash(xi + 1, yi + 1, seed: seed)
        return (a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v) * 2 - 1
    }

    /// Noise that repeats every `period` lattice cells in both directions, for seamless textures.
    static func periodicValue(_ x: Double, _ y: Double, period: Int, seed: UInt64 = 0) -> Double {
        let xi = Int(x.rounded(.down)), yi = Int(y.rounded(.down))
        let xf = x - Double(xi), yf = y - Double(yi)
        let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
        func lattice(_ a: Int, _ b: Int) -> Double {
            hash(((a % period) + period) % period, ((b % period) + period) % period, seed: seed)
        }
        let a = lattice(xi, yi), b = lattice(xi + 1, yi)
        let c = lattice(xi, yi + 1), d = lattice(xi + 1, yi + 1)
        return (a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v) * 2 - 1
    }

    static func fbm(_ x: Double, _ y: Double, octaves: Int = 4, seed: UInt64 = 0) -> Double {
        var sum = 0.0, amplitude = 0.5, frequency = 1.0
        for octave in 0..<octaves {
            sum += amplitude * value(x * frequency, y * frequency, seed: seed &+ UInt64(octave))
            frequency *= 2.03
            amplitude *= 0.5
        }
        return sum
    }
}
