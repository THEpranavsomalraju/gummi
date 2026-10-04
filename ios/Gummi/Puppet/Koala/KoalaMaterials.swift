import Metal
import RealityKit
import UIKit

/// Lime jelly with a wet surface and colored light transmitted through its volume.
/// The environment and Metal library are shared by every puppet, including the walk screen.
enum KoalaMaterials {
    private static let library = MTLCreateSystemDefaultDevice()?.makeDefaultLibrary()
    private static let environmentImage = studioEnvironmentImage()
    static let environment: EnvironmentResource? = {
        guard let image = environmentImage else { return nil }
        return try? EnvironmentResource(equirectangular: image)
    }()
    private static let transmissionTexture: TextureResource? = {
        guard let image = environmentImage else { return nil }
        return try? TextureResource(image: image, options: .init(semantic: .color))
    }()

    static func jelly(translucent: Bool = false) -> any RealityKit.Material {
        guard let library, let transmissionTexture,
              var material = try? CustomMaterial(surfaceShader: .init(named: "gummiJellySurface", in: library),
                                                  lightingModel: .clearcoat) else {
            return jellyFallback(translucent: translucent)
        }
        material.custom.texture = .init(transmissionTexture)
        material.custom.value = SIMD4(translucent ? 0.72 : 1, 0, 0, 0)
        // The normal look uses environment transmission with opaque depth: the six overlapping
        // animated pieces stay seamless. The playground's Shell switch still exposes alpha blending.
        if translucent { material.blending = .transparent(opacity: .init(floatLiteral: 1)) }
        return material
    }

    /// Keep a glossy lime material if Metal or the environment is unavailable.
    private static func jellyFallback(translucent: Bool) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.38, green: 0.64, blue: 0.065, alpha: 1))
        material.metallic = .init(floatLiteral: 0)
        material.roughness = .init(floatLiteral: 0.12)
        material.specular = .init(floatLiteral: 0.6)
        material.clearcoat = .init(floatLiteral: 1)
        material.clearcoatRoughness = .init(floatLiteral: 0.045)
        if translucent {
            material.blending = .transparent(opacity: .init(floatLiteral: 0.74))
        }
        return material
    }

    /// Retained for the mesh's optional core; the jelly shader supplies the volume shading.
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
        material.baseColor = .init(tint: UIColor(red: 0.58, green: 0.72, blue: 0.22, alpha: 1))
        material.metallic = .init(floatLiteral: 0)
        material.roughness = .init(floatLiteral: 0.19)
        material.clearcoat = .init(floatLiteral: 1)
        material.clearcoatRoughness = .init(floatLiteral: 0.06)
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

    /// A warm room with a large divided window and a tall fill card. Its dark lower hemisphere
    /// gives the jelly depth; the window panes produce recognizable reflections as Gummi turns.
    private static func studioEnvironmentImage() -> CGImage? {
        let width = 1024, height = 512
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let colors = [UIColor(red: 0.08, green: 0.10, blue: 0.05, alpha: 1).cgColor,
                      UIColor(red: 0.28, green: 0.30, blue: 0.22, alpha: 1).cgColor,
                      UIColor(red: 0.44, green: 0.48, blue: 0.36, alpha: 1).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors,
                                     locations: [0, 0.48, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        }
        context.setFillColor(UIColor(red: 1, green: 0.99, blue: 0.93, alpha: 1).cgColor)
        for row in 0..<3 {
            for column in 0..<3 {
                context.fill(CGRect(x: 660 + column * 41, y: 290 + row * 43, width: 35, height: 37))
            }
        }
        context.setFillColor(UIColor(white: 0.84, alpha: 1).cgColor)
        context.fill(CGRect(x: 220, y: 255, width: 26, height: 155))
        context.setFillColor(UIColor(white: 0.62, alpha: 1).cgColor)
        context.fill(CGRect(x: 455, y: 365, width: 150, height: 32))
        return context.makeImage()
    }
}
