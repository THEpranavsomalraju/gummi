import Foundation
import simd
import UIKit

/// Per-mood posture and signature motion (CONTRACT section 9). All values blend smoothly between moods.
nonisolated struct MoodStyle: Equatable, Sendable {
    var bodyPitch: Float = 0
    var headPitch: Float = 0
    var headRoll: Float = 0
    /// Ears droop outward and down.
    var earDroop: Float = 0
    /// Arms lift away from the sides.
    var armSpread: Float = 0
    var puff: Float = 0
    var eyeOpen: Float = 1
    var eyeLookUp: Float = 0
    /// Hop height in meters and hops per second.
    var hopHeight: Float = 0
    var hopRate: Float = 0
    var swayAmount: Float = 0.035
    var breathAmount: Float = 0.018
    var breathRate: Float = 0.25
    var shiver: Float = 0
    /// Arm fanning amplitude (radians) for "high".
    var fan: Float = 0
    /// Raises the right arm toward the chin for "thinking".
    var rightArmRaise: Float = 0
    var nod: Float = 0
    var mouth: MouthShape = .smile
    var eyes: EyeShape = .open
    var browTilt: Float = 0
    var browRaise: Float = 0
    var blush: Float = 0
    var rimColor = SIMD3<Float>(0.55, 0.72, 0.96)
    var rimStrength: Float = 0.5

    static func of(_ mood: Mood) -> MoodStyle {
        var style = MoodStyle()
        style.rimColor = Self.rgb(Theme.moodColor(mood))
        switch mood {
        case .calm, .unknown:
            break
        case .rising:
            style.eyeOpen = 1.12
            style.hopHeight = 0.006
            style.hopRate = 1.2
            style.breathRate = 0.32
            style.browRaise = 0.7
            style.rimStrength = 0.7
        case .high:
            style.puff = 0.06
            style.armSpread = 0.35
            style.fan = 0.28
            style.eyeOpen = 1.15
            style.breathRate = 0.45
            style.mouth = .wavy
            style.browTilt = 0.8
            style.browRaise = 0.3
            style.rimStrength = 0.9
        case .dipping:
            style.bodyPitch = 0.08
            style.headPitch = 0.22
            style.earDroop = 0.35
            style.eyeOpen = 0.7
            style.swayAmount = 0.015
            style.breathRate = 0.18
            style.mouth = .flat
            style.browTilt = 0.5
            style.browRaise = -0.3
            style.rimStrength = 0.6
        case .low:
            style.shiver = 0.0025
            style.armSpread = -0.12
            style.earDroop = 0.25
            style.headPitch = 0.12
            style.mouth = .frown
            style.eyes = .small
            style.browTilt = 1
            style.browRaise = 0.2
            style.swayAmount = 0
            style.rimStrength = 0.8
        case .proud:
            style.bodyPitch = -0.1
            style.headPitch = -0.12
            style.puff = 0.03
            style.eyes = .sparkle
            style.mouth = .grin
            style.browRaise = 0.6
            style.blush = 1
            style.rimStrength = 1
        case .happy:
            style.hopHeight = 0.02
            style.hopRate = 2
            style.armSpread = 0.2
            style.mouth = .grin
            style.eyes = .happy
            style.browRaise = 0.5
            style.blush = 1
            style.rimStrength = 0.8
        case .sleepy:
            style.eyeOpen = 0.32
            style.eyes = .sleepy
            style.browTilt = 0.2
            style.browRaise = -0.6
            style.headPitch = 0.15
            style.headRoll = 0.12
            style.earDroop = 0.2
            style.nod = 0.12
            style.swayAmount = 0.02
            style.breathRate = 0.15
            style.rimStrength = 0.3
        case .thinking:
            style.eyeLookUp = 1
            style.headRoll = -0.16
            style.rightArmRaise = 1
            style.mouth = .flat
            style.browTilt = -0.5
            style.browRaise = 0.4
            style.rimStrength = 0.6
        }
        return style
    }

    /// Exponential approach toward `target`, reaching about 98% in 0.6 s.
    mutating func blend(toward target: MoodStyle, dt: Float, settle: Float = 0.6) {
        let k = 1 - exp(-dt * 4 / settle)
        func mix(_ a: inout Float, _ b: Float) { a += (b - a) * k }
        mix(&bodyPitch, target.bodyPitch); mix(&headPitch, target.headPitch); mix(&headRoll, target.headRoll)
        mix(&earDroop, target.earDroop); mix(&armSpread, target.armSpread); mix(&puff, target.puff)
        mix(&eyeOpen, target.eyeOpen); mix(&eyeLookUp, target.eyeLookUp); mix(&hopHeight, target.hopHeight)
        mix(&hopRate, target.hopRate); mix(&swayAmount, target.swayAmount); mix(&breathAmount, target.breathAmount)
        mix(&breathRate, target.breathRate); mix(&shiver, target.shiver); mix(&fan, target.fan)
        mix(&rightArmRaise, target.rightArmRaise); mix(&nod, target.nod); mix(&rimStrength, target.rimStrength)
        mix(&browTilt, target.browTilt); mix(&browRaise, target.browRaise); mix(&blush, target.blush)
        rimColor += (target.rimColor - rimColor) * k
        mouth = target.mouth
        eyes = target.eyes
    }

    private static func rgb(_ color: UIColor) -> SIMD3<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3(Float(r), Float(g), Float(b))
    }
}
