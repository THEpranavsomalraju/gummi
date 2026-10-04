import RealityKit
import UIKit

/// Gummi's materials. Metallic stays 0 everywhere: the gummy look comes from a glossy clear coat,
/// a soft sheen, and a faint inner glow over the eucalyptus base.
enum KoalaMaterials {
    static func jelly(translucent: Bool = false) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: Theme.jelly)
        material.metallic = .init(floatLiteral: 0)
        material.roughness = .init(floatLiteral: 0.32)
        material.clearcoat = .init(floatLiteral: 1)
        material.clearcoatRoughness = .init(floatLiteral: 0.06)
        material.emissiveColor = .init(color: Theme.jelly)
        material.emissiveIntensity = 0.12
        if translucent {
            material.blending = .transparent(opacity: .init(floatLiteral: 0.82))
        }
        return material
    }

    /// The darker core shown through the translucent shell experiment.
    static func core() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.20, green: 0.42, blue: 0.30, alpha: 1))
        material.roughness = .init(floatLiteral: 0.5)
        material.metallic = .init(floatLiteral: 0)
        return material
    }

    static func innerEar() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.80, green: 0.93, blue: 0.85, alpha: 1))
        material.metallic = .init(floatLiteral: 0)
        material.roughness = .init(floatLiteral: 0.4)
        material.clearcoat = .init(floatLiteral: 0.6)
        return material
    }

    /// Eyes, nose, and mouth: deep glossy green-black.
    static func feature(lightness: CGFloat = 0.08) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: lightness, green: lightness * 1.6, blue: lightness * 1.25, alpha: 1))
        material.metallic = .init(floatLiteral: 0)
        material.roughness = .init(floatLiteral: 0.15)
        material.clearcoat = .init(floatLiteral: 1)
        material.clearcoatRoughness = .init(floatLiteral: 0.03)
        material.faceCulling = .none
        return material
    }

    static func highlight() -> UnlitMaterial {
        UnlitMaterial(color: .white)
    }
}
