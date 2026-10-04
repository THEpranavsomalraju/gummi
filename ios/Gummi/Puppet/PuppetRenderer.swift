import Foundation

/// What the app asks of Gummi. Every renderer (3D now, a simpler fallback only if ever needed, D-25) takes the same input.
nonisolated struct PuppetInput: Equatable, Sendable {
    var mood: Mood = .calm
    /// True while chat tokens stream.
    var talking = false
    /// True while the agent or chat runs tools.
    var thinking = false
    /// Where the finger is, -1...1 on each axis (x right, y up), or nil when nobody is touching.
    var look: SIMD2<Float>? = nil
}

nonisolated enum PuppetReaction: Sendable {
    case tap
}

/// The contract between the app and a puppet renderer (ios/CLAUDE.md, D-25).
@MainActor
protocol PuppetRenderer: AnyObject {
    var input: PuppetInput { get set }
    func react(_ reaction: PuppetReaction)
    /// Frames per second the renderer is actually updating at.
    var framesPerSecond: Double { get }
}
