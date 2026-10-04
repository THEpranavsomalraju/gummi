import RealityKit
import UIKit

/// Gummi's materials. Metallic stays 0 everywhere: the gummy look comes from a glossy clear coat,
/// a soft sheen, and a faint inner glow over the eucalyptus base.
enum KoalaMaterials {
    static func jelly(translucent: Bool = false) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: Theme.jelly)
        material.metallic = .init(floatLiteral: 0)
        // Broad, soft highlights instead of mirror dots: rougher base, softer clear coat.
        material.roughness = .init(floatLiteral: 0.42)
        material.specular = .init(floatLiteral: 0.6)
        material.clearcoat = .init(floatLiteral: 0.8)
        material.clearcoatRoughness = .init(floatLiteral: 0.26)
        // A gentle glow from inside, like light caught in candy.
        material.emissiveColor = .init(color: Theme.jelly)
        material.emissiveIntensity = 0.22
        if translucent {
            material.blending = .transparent(opacity: .init(floatLiteral: 0.74))
        }
        return material
    }

    /// The glowing core seen through the translucent shell experiment.
    static func core() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: Theme.jelly)
        material.roughness = .init(floatLiteral: 0.6)
        material.metallic = .init(floatLiteral: 0)
        material.emissiveColor = .init(color: Theme.jelly)
        material.emissiveIntensity = 0.6
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
        var material = UnlitMaterial(color: .white)
        material.faceCulling = .none
        return material
    }

    /// Soft pink cheeks, a little see-through.
    static func blush() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 1.0, green: 0.55, blue: 0.62, alpha: 1))
        material.metallic = .init(floatLiteral: 0)
        material.roughness = .init(floatLiteral: 0.8)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.6))
        material.faceCulling = .none
        return material
    }

    static func tongue() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.95, green: 0.45, blue: 0.5, alpha: 1))
        material.metallic = .init(floatLiteral: 0)
        material.roughness = .init(floatLiteral: 0.35)
        material.clearcoat = .init(floatLiteral: 0.6)
        material.faceCulling = .none
        return material
    }
}
