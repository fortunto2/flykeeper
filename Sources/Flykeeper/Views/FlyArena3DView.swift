import SwiftUI
import RealityKit
import Metal
import FlyKit

/// The fly in a glass cube, its brain as a raster on the floor. RealityKit rather than a
/// Canvas because the same scene graph becomes augmented reality by switching the camera to
/// spatial tracking, and a LiDAR mesh of the room drops in as one more entity.
struct FlyArena3DView: View {
    let pose: FlyPose
    let behaviour: Behaviour
    let spikes: [UInt32]
    let neurons: Int
    /// A morsel on the floor, in arena coordinates.
    var food: Food?
    /// Cell positions in µm for a real brain; empty for synthetic wiring.
    var positions: [SIMD3<Float>] = []
    /// Running firing rate per cell, for the heat map.
    var rates: [Float] = []
    var lightsOn = true
    /// Which half of the arena was tapped. The view that owns the space is the one that can
    /// answer that; passing a width out to the caller only creates a value to get stale.
    var onTouch: (TouchSide) -> Void = { _ in }

    @State private var scene = ArenaScene()
    /// Orbit camera: drag to turn, pinch to zoom. Angles in radians about the cube's centre.
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0.45
    @State private var distance: Float = 1.8
    @State private var dragLast: CGSize?
    @State private var pinchStart: Float?

    var body: some View {
        GeometryReader { geo in
            scene3D
                .contentShape(Rectangle())
                .onTapGesture { onTouch($0.x < geo.size.width / 2 ? .left : .right) }
        }
    }

    private var scene3D: some View {
        RealityView { content in
            content.add(scene.root)
            // The modelled fly, if the asset loads; the procedural one underneath stays as
            // the fallback, so a missing or broken USDZ is a plainer fly, not an empty cube.
            if let model = try? await Entity(named: "Fly") {
                scene.adopt(model)
            }
            if let shell = try? await Entity(named: "BrainShell") {
                scene.adoptShell(shell)
            }
        } update: { _ in
            scene.setCamera(yaw: yaw, pitch: pitch, distance: distance)
            scene.apply(pose: pose, behaviour: behaviour, lightsOn: lightsOn)
            scene.showFood(food)
            scene.showBrain(positions: positions)
            scene.updateRaster(spikes: spikes, neurons: neurons)
            scene.cloud?.update(rates: rates)
            scene.wires?.update(rates: rates)
        }
        .background(.black, in: RoundedRectangle(cornerRadius: 16))
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { g in
                    let last = dragLast ?? .zero
                    yaw -= Float(g.translation.width - last.width) * 0.008
                    pitch = min(max(pitch + Float(g.translation.height - last.height) * 0.008, -0.1), 1.35)
                    dragLast = g.translation
                }
                .onEnded { _ in dragLast = nil }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { g in
                    let start = pinchStart ?? distance
                    pinchStart = start
                    distance = min(max(start / Float(g.magnification), 0.5), 4)
                }
                .onEnded { _ in pinchStart = nil }
        )
        .accessibilityElement()
        .accessibilityLabel("Fly, \(behaviour.rawValue)")
        .accessibilityHint("Touches the fly")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("arena")
        .accessibilityAction { onTouch(.both) }
    }
}

/// Owns the entities so per-frame updates move them instead of rebuilding the scene.
@MainActor
final class ArenaScene {
    let root = Entity()
    private let fly = Entity()
    private let camera = PerspectiveCamera()
    /// Draw order for the two translucent things: shell first, cells on top. Without it
    /// RealityKit re-sorts them by distance every frame and the brain's middle flickers.
    private let translucent = ModelSortGroup()
    private let morsel: Entity = {
        // A banana-ish morsel: three yellow beads on a curve.
        let e = Entity()
        let mat = SimpleMaterial(color: UIColor(red: 0.95, green: 0.8, blue: 0.2, alpha: 1), roughness: 0.5, isMetallic: false)
        for (i, off) in [SIMD3<Float>(-0.03, 0.012, 0), [0, 0.02, 0], [0.03, 0.012, 0]].enumerated() {
            let bead = ModelEntity(mesh: .generateSphere(radius: i == 1 ? 0.018 : 0.014), materials: [mat])
            bead.position = off
            e.addChild(bead)
        }
        e.isEnabled = false
        return e
    }()
    /// What the orbit turns about: the middle of the cube, where the brain hangs.
    static let focus: SIMD3<Float> = [0, 0.5, 0]
    private let floor: ModelEntity
    private let wings: [ModelEntity]
    private let legs: [ModelEntity]
    private let eyes: [ModelEntity]
    private let bodyParts: [ModelEntity]
    private var rasterTick = 0
    /// The real brain, floating in the back of the cube, when a tier has anatomy.
    private(set) var cloud: BrainCloud?
    private(set) var wires: BrainWires?
    private var cloudCells = -1
    /// The loaded model's parts, when `adopt` succeeded; nil means the procedural fly.
    private var modelWings: [ModelEntity] = []
    private var modelEyes: ModelEntity?
    private var usingModel = false

    /// Cube is 1 unit; the fly is this long. A pet, not a specimen: big enough to read.
    private static let flySize: Float = 0.2

    init() {
        // Floor carries the raster texture; walls are edges only, so the fly is visible from
        // any angle and the cube still reads as a box.
        floor = ModelEntity(mesh: .generatePlane(width: 1, depth: 1), materials: [UnlitMaterial(color: .black)])
        root.addChild(floor)
        for edge in Self.cubeEdges() { root.addChild(edge) }

        let s = Self.flySize
        let bodyColor = UIColor(red: 0.3, green: 0.23, blue: 0.16, alpha: 1)
        func part(_ radius: Float, scale: SIMD3<Float>, at: SIMD3<Float>, color: UIColor) -> ModelEntity {
            let e = ModelEntity(mesh: .generateSphere(radius: radius),
                                materials: [SimpleMaterial(color: color, roughness: 0.6, isMetallic: false)])
            e.scale = scale
            e.position = at
            return e
        }
        let abdomen = part(s * 0.3, scale: [1.7, 1, 1], at: [-s * 0.4, 0, 0], color: bodyColor)
        let thorax = part(s * 0.3, scale: [1, 1, 1], at: [s * 0.1, s * 0.05, 0], color: bodyColor.lighter)
        let head = part(s * 0.22, scale: [1, 1, 1], at: [s * 0.5, s * 0.05, 0], color: bodyColor)
        bodyParts = [abdomen, thorax, head]
        eyes = [-1, 1].map { side in
            part(s * 0.1, scale: [1, 1, 1], at: [s * 0.62, s * 0.1, Float(side) * s * 0.14], color: .red)
        }
        wings = [-1, 1].map { side in
            let w = ModelEntity(mesh: .generateBox(size: [s * 1.1, s * 0.01, s * 0.32], cornerRadius: s * 0.1),
                                materials: [SimpleMaterial(color: UIColor.white.withAlphaComponent(0.45), roughness: 0.2, isMetallic: false)])
            w.position = [-s * 0.35, s * 0.32, Float(side) * s * 0.2]
            return w
        }
        legs = (0..<6).map { i in
            let side: Float = i < 3 ? -1 : 1
            let l = ModelEntity(mesh: .generateBox(size: [s * 0.04, s * 0.04, s * 0.7]),
                                materials: [SimpleMaterial(color: .gray, roughness: 0.8, isMetallic: false)])
            l.position = [Float(i % 3 - 1) * s * 0.3, -s * 0.1, side * s * 0.35]
            return l
        }
        for e in bodyParts + eyes + wings + legs { fly.addChild(e) }
        root.addChild(fly)
        root.addChild(morsel)

        // Orbit camera; `setCamera` places it every frame. A key light so the body has shape.
        camera.camera.fieldOfViewInDegrees = 50
        root.addChild(camera)
        let sun = DirectionalLight()
        sun.light.intensity = 3000
        sun.look(at: [0, 0, 0], from: [0.6, 1.5, 0.8], relativeTo: nil)
        root.addChild(sun)
    }

    func setCamera(yaw: Float, pitch: Float, distance: Float) {
        let offset = SIMD3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * distance
        camera.look(at: Self.focus, from: Self.focus + offset, relativeTo: nil)
    }

    /// The brain's surface, a glass shell around the cells. Kept hidden until a real brain
    /// is loaded, then placed with the cloud's own µm → scene mapping.
    private var shell: Entity?

    func adoptShell(_ shell: Entity) {
        guard let device = MTLCreateSystemDefaultDevice(), let library = device.makeDefaultLibrary(),
              var glass = try? CustomMaterial(surfaceShader: .init(named: "shellSurface", in: library),
                                              lightingModel: .unlit) else { return }
        glass.blending = .transparent(opacity: .init(floatLiteral: 1))
        glass.writesDepth = false
        glass.faceCulling = .none
        func paint(_ e: Entity) {
            if let m = e as? ModelEntity {
                m.model?.materials = [glass]
                m.components.set(ModelSortGroupComponent(group: translucent, order: 0))
            }
            for child in e.children { paint(child) }
        }
        paint(shell)
        shell.isEnabled = false
        root.addChild(shell)
        self.shell = shell
        placeShell()
    }

    private func placeShell() {
        guard let shell else { return }
        guard let cloud else { shell.isEnabled = false; return }
        let s = cloud.scale
        shell.scale = [s, -s, s]
        shell.position = cloud.centre - cloud.mid * SIMD3(s, -s, s)
        shell.isEnabled = true
    }

    /// Build (or drop) the point cloud when the loaded brain changes. Keyed on cell count:
    /// positions are static per engine, and comparing 138k vectors a frame is waste.
    func showBrain(positions: [SIMD3<Float>]) {
        guard positions.count != cloudCells else { return }
        cloudCells = positions.count
        cloud?.root.removeFromParent()
        cloud = BrainCloud(positions: positions, extent: 0.75, centre: Self.focus)
        wires?.root.removeFromParent()
        wires = nil
        if let cloud {
            root.addChild(cloud.root)
            cloud.model?.components.set(ModelSortGroupComponent(group: translucent, order: 1))
            // Arbors of a subset of cells, when the export ships them.
            if let url = Bundle.main.url(forResource: "fafb-v783-skeletons", withExtension: "fsk"),
               let w = BrainWires(url: url, mid: cloud.mid, scale: cloud.scale, centre: cloud.centre) {
                root.addChild(w.root)
                w.model?.components.set(ModelSortGroupComponent(group: translucent, order: 2))
                wires = w
            }
        }
        placeShell()
    }

    func showFood(_ food: Food?) {
        guard let food else { morsel.isEnabled = false; return }
        morsel.isEnabled = true
        morsel.position = [Float(food.x - 0.5), 0, Float(food.y - 0.5)]
    }

    /// Swap the procedural parts for the modelled fly. The model faces +x at ~0.045 units
    /// long (the converter turns it that way), so it takes the same transform the parts did.
    func adopt(_ model: Entity) {
        let bounds = model.visualBounds(relativeTo: nil)
        let length = max(bounds.extents.x, 0.001)
        model.scale = .init(repeating: Self.flySize * 1.2 / length)
        model.position = [0, -bounds.min.y * model.scale.y, 0]
        modelWings = ["Wings_L", "Wings_R"].compactMap { model.findEntity(named: $0) as? ModelEntity }
        modelEyes = model.findEntity(named: "Eyes") as? ModelEntity
        for e in bodyParts + eyes + wings + legs { e.isEnabled = false }
        fly.addChild(model)
        usingModel = true
    }

    func apply(pose: FlyPose, behaviour: Behaviour, lightsOn: Bool) {
        let s = Self.flySize
        fly.position = [Float(pose.x - 0.5), Float(pose.z * 0.85) + s * 0.35, Float(pose.y - 0.5)]
        // 2D heading is x→y; y is the cube's z, so that is a rotation about the up axis by -heading.
        fly.orientation = simd_quatf(angle: Float(-pose.heading), axis: [0, 1, 0])
        // Alternating tripod gait: legs 0,2,4 swing while 1,3,5 stance.
        for (i, leg) in legs.enumerated() {
            let phase = Float(pose.legPhase) + (i % 2 == 0 ? 0 : .pi)
            let side: Float = i < 3 ? -1 : 1
            leg.orientation = simd_quatf(angle: sin(phase) * 0.45, axis: [0, 1, 0])
                * simd_quatf(angle: side * 0.9, axis: [1, 0, 0])
        }
        // Wings: folded flat at rest, a fast flutter while beating.
        let flutter = pose.wingBeat > 0 ? Float(sin(Date().timeIntervalSinceReferenceDate * 90)) * 0.7 : 0
        for (i, wing) in wings.enumerated() {
            let side: Float = i == 0 ? -1 : 1
            wing.orientation = simd_quatf(angle: side * (0.25 + Float(pose.wingBeat) * 0.5), axis: [0, 1, 0])
                * simd_quatf(angle: flutter * side, axis: [1, 0, 0])
        }
        let eyeColor: UIColor = behaviour == .sleep ? .darkGray : .red
        for eye in eyes { eye.model?.materials = [SimpleMaterial(color: eyeColor, roughness: 0.3, isMetallic: false)] }
        if usingModel {
            // The model's wings pivot at their roots (baked by the converter): flap about the
            // body's long axis, mirrored, and lift a little more while beating.
            for (i, wing) in modelWings.enumerated() {
                let side: Float = i == 0 ? 1 : -1
                wing.orientation = simd_quatf(angle: side * (flutter + Float(pose.wingBeat) * 0.3), axis: [1, 0, 0])
            }
            modelEyes?.model?.materials = [SimpleMaterial(color: eyeColor, roughness: 0.3, isMetallic: false)]
            // A walking fly bobs; a sleeping one sits lower.
            let bob = pose.isAirborne ? 0 : Float(sin(pose.legPhase)) * s * 0.03
            fly.position.y += bob - (behaviour == .sleep ? s * 0.05 : 0)
        }
        // Tint only modulates the raster texture; on a floor that has none yet it would
        // paint the whole plane white.
        if var m = floor.model?.materials.first as? UnlitMaterial, m.color.texture != nil {
            m.color.tint = lightsOn ? .white : UIColor(red: 0.3, green: 0.3, blue: 0.6, alpha: 1)
            floor.model?.materials = [m]
        }
    }

    /// Lit neurons as a small bitmap on the floor, refreshed every third frame: a texture is
    /// cheaper than thousands of entities and still the engine's own spike buffer.
    func updateRaster(spikes: [UInt32], neurons: Int) {
        rasterTick += 1
        // An empty spike list still draws (a dark floor): a silent brain is a picture too.
        guard neurons > 0, rasterTick % 3 == 0 else { return }
        let cols = max(1, Int(Double(neurons).squareRoot().rounded(.up)))
        let rows = max(1, (neurons + cols - 1) / cols)
        var px = [UInt8](repeating: 0, count: cols * rows * 4)
        for i in stride(from: 3, to: px.count, by: 4) { px[i] = 255 }
        for idx in spikes {
            let i = Int(idx)
            guard i < cols * rows else { continue }
            let o = i * 4
            px[o] = 40; px[o + 1] = 190; px[o + 2] = 220
        }
        guard let ctx = CGContext(data: &px, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: cols * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = ctx.makeImage(),
              let texture = try? TextureResource(image: image, options: .init(semantic: .color)) else { return }
        var m = UnlitMaterial()
        m.color = .init(tint: (floor.model?.materials.first as? UnlitMaterial)?.color.tint ?? .white,
                        texture: .init(texture, sampler: Self.crispSampler))
        floor.model?.materials = [m]
    }

    /// Nearest-neighbour sampling: one neuron is one square, not a blur.
    private static let crispSampler: MaterialParameters.Texture.Sampler = {
        let d = MTLSamplerDescriptor()
        d.minFilter = .nearest
        d.magFilter = .nearest
        d.mipFilter = .notMipmapped
        return .init(d)
    }()

    private static func cubeEdges() -> [ModelEntity] {
        let t: Float = 0.004
        let mat = UnlitMaterial(color: UIColor.white.withAlphaComponent(0.35))
        var edges: [ModelEntity] = []
        for y in [Float(0), 1] {
            for zz in [Float(-0.5), 0.5] {
                let e = ModelEntity(mesh: .generateBox(size: [1, t, t]), materials: [mat])
                e.position = [0, y, zz]
                edges.append(e)
                let f = ModelEntity(mesh: .generateBox(size: [t, t, 1]), materials: [mat])
                f.position = [zz, y, 0]
                edges.append(f)
            }
        }
        for x in [Float(-0.5), 0.5] {
            for zz in [Float(-0.5), 0.5] {
                let e = ModelEntity(mesh: .generateBox(size: [t, 1, t]), materials: [mat])
                e.position = [x, 0.5, zz]
                edges.append(e)
            }
        }
        return edges
    }
}

private extension UIColor {
    var lighter: UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: min(b * 1.25, 1), alpha: a)
    }
}
