import AppKit

/// 캐릭터마다 모든 자세를 한 장에 모아 그린다 (새 동물을 그릴 때 확인용).
/// `ClawdPet --render-species <폴더>` → <폴더>/<캐릭터>.png
/// 윗줄: Touch Bar 크게 보기(검은 바탕, 높이 30pt 안에 팻말까지 들어오는지), 아랫줄: 화면 위(밝은 바탕, 테두리)
enum SpeciesSheet {
    private struct Pose {
        let name: String
        var frame = ClawdSprite.Frame()
        var heat: CGFloat = 0
        var sign = false
    }

    private static var poses: [Pose] {
        typealias F = ClawdSprite.Frame
        return [
            Pose(name: "stand"),
            Pose(name: "walk A", frame: F(legs: .stepA)),
            Pose(name: "walk B", frame: F(legs: .stepB)),
            Pose(name: "look", frame: F(look: -1)),
            Pose(name: "right", frame: F(look: 1, facing: 1)),
            Pose(name: "cheer", frame: F(armsUp: true, eyes: .happy)),
            Pose(name: "jump", frame: F(armsUp: true, legs: .tucked)),
            Pose(name: "rest", frame: F(sitting: true)),
            Pose(name: "sleep", frame: F(sitting: true, eyes: .closed)),
            Pose(name: "think", frame: F(eyes: .up)),
            Pose(name: "study", frame: F(sitting: true, prop: .book(page: 0))),
            Pose(name: "page", frame: F(sitting: true, prop: .book(page: 1))),
            Pose(name: "craft", frame: F(sitting: true, prop: .laptop(typing: 0))),
            Pose(name: "lift up", frame: F(armsUp: true, eyes: .closed, prop: .dumbbell(up: true))),
            Pose(name: "lift dn", frame: F(armsUp: true, prop: .dumbbell(up: false))),
            Pose(name: "clock", frame: F(armsUp: true, prop: .holdSign), sign: true),
            Pose(name: "loud", frame: F(armsUp: true, eyes: .frustrated, prop: .holdSign), sign: true),
            Pose(name: "bright", frame: F(armsUp: true, prop: .holdSign, shades: 1), sign: true),
            Pose(name: "tired", frame: F(eyes: .tired)),
            Pose(name: "furious", frame: F(eyes: .frustrated), heat: 1),
            Pose(name: "graze", frame: F(eyes: .closed, headDown: 5)),
        ]
    }

    static func write(to directory: String) {
        let dir = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for species in Species.allCases {
            let url = dir.appendingPathComponent("\(species.rawValue).png")
            if let data = render(species) { try? data.write(to: url) }
            print("species → \(url.path)")
        }
    }

    private static func render(_ species: Species) -> Data? {
        let list = poses
        let cellWidth: CGFloat = max(70, species.width(4) + 12), barHeight: CGFloat = 30, deskHeight: CGFloat = 90, labelHeight: CGFloat = 12
        let size = NSSize(width: cellWidth * CGFloat(list.count), height: barHeight + deskHeight + labelHeight)
        let zoom: CGFloat = 4
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * zoom), pixelsHigh: Int(size.height * zoom),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }
        ctx.interpolationQuality = .none

        // 바탕: 위는 Touch Bar(검정), 아래는 밝은 화면
        ctx.setFillColor(CGColor(gray: 0.93, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: deskHeight + labelHeight, width: size.width, height: barHeight))

        let font = NSFont.systemFont(ofSize: 7)
        for (i, pose) in list.enumerated() {
            let center = cellWidth * (CGFloat(i) + 0.5)
            // Touch Bar 크게 보기 (px 2)
            draw(pose, species: species, px: 2, centerX: center, bottom: deskHeight + labelHeight, outline: false, in: ctx)
            // 화면 위 크게 (px 4)
            draw(pose, species: species, px: 4, centerX: center, bottom: labelHeight + 6, outline: true, in: ctx)
            let text = NSAttributedString(string: pose.name, attributes: [.font: font, .foregroundColor: NSColor.darkGray])
            text.draw(at: NSPoint(x: center - text.size().width / 2, y: 1))
        }
        return rep.representation(using: .png, properties: [:])
    }

    private static func draw(_ pose: Pose, species: Species, px: CGFloat, centerX: CGFloat, bottom: CGFloat, outline: Bool, in ctx: CGContext) {
        species.draw(pose.frame, in: ctx, centerX: centerX, bottom: bottom, px: px, scale: 4, heat: pose.heat, outline: outline)
        guard pose.sign else { return }
        // 렌더러와 같은 자리·크기의 팻말 (시계 팻말 21칸 × 7칸)
        let sp = max(1, (px * 0.75 * 2).rounded() / 2)
        let headTop = species.signBottom(petBottom: bottom, petTop: bottom + species.height(px), px: px)
        let width = 21 * sp
        let box = CGRect(x: centerX + species.signOffset(facing: pose.frame.facing, px: px) - width / 2, y: headTop - 0.5, width: width, height: 7 * sp)
        ctx.setFillColor(Palette.sign)
        ctx.fill([box.insetBy(dx: sp, dy: 0), box.insetBy(dx: 0, dy: sp)])
        PixelFont.draw("4:22", in: ctx, left: box.minX + 4 * sp, bottom: box.minY + sp, px: sp, color: Palette.signInk)
    }
}
