import AppKit

enum Renderer {
    private static let thoughtFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    private static let bubbleTitleFont = NSFont.systemFont(ofSize: 11, weight: .bold)
    private static let bubbleFont = NSFont.systemFont(ofSize: 11, weight: .medium)

    static func draw(_ world: Playground, in ctx: CGContext, size: CGSize, scale: CGFloat) {
        if !world.transparent {
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
        }

        let px = world.px
        let smallPx = max(1, (px * 0.75 * scale).rounded() / scale)
        if world.waterLevel != nil { drawWater(world, size: size, in: ctx, scale: scale, front: false) }

        for treat in world.treats {
            switch treat.kind {
            case .grass:
                continue   // 풀은 동물 앞에 그린다
            case .crumb:
                PixelArt.drawCrumb(left: treat.grown, in: ctx, centerX: treat.x, bottom: treat.y, px: smallPx, scale: scale)
                continue
            case .flake:
                continue   // 물고기밥은 수면 위에 (물 앞)
            case .spark:
                break
            }
            let twinkle = Int(treat.age / 0.25) % 4 == 0
            PixelArt.draw(PixelArt.spark, size: (7, 7), in: ctx, centerX: treat.x, centerY: treat.y + 3.5 * smallPx,
                          px: smallPx, color: twinkle ? Palette.treatGlow : Palette.treat, scale: scale)
        }

        for pet in world.pets {
            pet.bubbleFrame = nil
            var frame = pet.frame
            var centerX = pet.x + pet.shake
            let holding = world.gauge.flatMap { $0.holder == ObjectIdentifier(pet) ? $0 : nil }
            if let holding {
                frame = holdingFrame(frame, holding)
                // 시끄러우면 덜덜 떤다
                if holding.kind == .volume, holding.level > 0.8 { centerX += (Int(pet.time / 0.05) % 2 == 0 ? -0.5 : 0.5) * px }
            }
            // 헤엄치는 녀석은 물속에서 둥실둥실
            let bottom = pet.y + world.swimLift(pet, sitting: frame.sitting)
            world.species.draw(frame, in: ctx, centerX: centerX, bottom: bottom, px: px, scale: scale, heat: pet.heat, outline: world.transparent)
            if pet.mood == .furious, Int(pet.time / 0.4) % 2 == 0 {
                // 머리 옆 💢
                let top = bottom + (frame.sitting ? world.sittingHeight : world.spriteHeight)
                PixelArt.draw(PixelArt.anger, size: (5, 5), in: ctx, centerX: centerX + world.species.headSide(facing: pet.facing) * world.spriteWidth * 0.39, centerY: top - smallPx,
                              px: smallPx, color: Palette.anger, scale: scale)
            }
            if let holding {
                drawGaugeSign(holding, centerX: centerX + world.species.signOffset(facing: pet.facing, px: px),
                              headTop: world.species.signBottom(petBottom: bottom, petTop: bottom + world.spriteHeight, px: px),
                              world: world, in: ctx, scale: scale)
                if holding.kind == .volume { drawNoise(level: holding.level, centerX: centerX, bottom: bottom, time: pet.time, world: world, in: ctx, scale: scale) }
            } else if pet.showsClock {
                let headTop = world.species.signBottom(petBottom: bottom, petTop: bottom + (frame.sitting ? world.sittingHeight : world.spriteHeight), px: px)
                drawClockSign(centerX: centerX + world.species.signOffset(facing: pet.facing, px: px), headTop: headTop, world: world, in: ctx, scale: scale)
            }
            if let thought = pet.thought { drawThought(thought, for: pet, world: world) }
        }

        // 물 표면은 물고기 앞에: 뛰어오를 때 물을 가르는 것처럼
        if world.waterLevel != nil { drawWater(world, size: size, in: ctx, scale: scale, front: true) }
        // 물고기밥은 수면 위에 둥둥
        for treat in world.treats where treat.kind == .flake {
            PixelArt.drawFlake(in: ctx, centerX: treat.x, bottom: treat.y - smallPx, px: smallPx, scale: scale)
        }

        // 양의 풀떼기: 뜯는 입이 풀에 묻혀 보이게 동물 앞에
        for treat in world.treats where treat.kind == .grass {
            PixelArt.drawGrass(grown: treat.grown, in: ctx, centerX: treat.x, bottom: treat.y, px: smallPx, scale: scale)
        }

        for p in world.particles {
            ctx.saveGState()
            ctx.setAlpha(p.alpha)
            switch p.kind {
            case .heart:
                PixelArt.draw(PixelArt.heart, size: (5, 4), in: ctx, centerX: p.x, centerY: p.y,
                              px: smallPx, color: Palette.heart, scale: scale)
            case .dust, .sweat, .steam:
                switch p.kind {
                case .sweat: ctx.setFillColor(Palette.sweat)
                case .steam: ctx.setFillColor(Palette.steam)
                default: ctx.setFillColor(Palette.dust)
                }
                ctx.fill(CGRect(x: ClawdSprite.snap(p.x, scale), y: ClawdSprite.snap(p.y, scale), width: smallPx, height: smallPx))
            case .text(let s, let color, let fontSize):
                let str = NSAttributedString(string: s, attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: color,
                ])
                let sz = str.size()
                str.draw(at: CGPoint(x: p.x - sz.width / 2, y: p.y))
            }
            ctx.restoreGState()
        }

        // 말풍선은 맨 위에. 확인 요청 → 완료 알림 → 아이디어 순으로 자리를 잡고, 서로 겹치지 않게 한다.
        func priority(_ pet: Clawd) -> Int {
            switch pet.activity {
            case .call: return 0
            case .announce: return 1
            default: return 2
            }
        }
        var occupied: [CGRect] = []
        for pet in world.pets.filter({ $0.bubble != nil }).sorted(by: { priority($0) < priority($1) }) {
            if let bubble = pet.bubble { drawBubble(bubble, for: pet, world: world, occupied: &occupied, in: ctx) }
        }
    }

    // MARK: - 레벨 바를 든 Clawd

    /// 바를 머리 위로 받쳐 들고, 소리가 클수록 괴로워하고, 화면이 밝을수록 선글라스가 짙어진다
    private static func holdingFrame(_ base: ClawdSprite.Frame, _ gauge: Playground.Gauge) -> ClawdSprite.Frame {
        var f = base
        f.armsUp = true
        f.prop = .holdSign
        f.sitting = false
        if f.legs == .tucked { f.legs = .stand }
        let level = CGFloat(gauge.level)
        switch gauge.kind {
        case .muted:
            f.eyes = .closed                                    // 조용~
        case .volume:
            f.eyes = level > 0.8 ? .frustrated : level > 0.55 ? .tired : level < 0.25 ? .happy : .open
        case .brightness:
            f.eyes = level < 0.15 ? .tired : .open             // 어두우면 눈이 가물가물
            f.shades = level > 0.2 ? (level - 0.2) / 0.8 : 0
        }
        return f
    }

    /// 출렁이는 강물. 뒤(front: false)엔 물 몸통·물살·자갈을, 앞(front: true)엔
    /// 물속에 있는 것들을 물빛으로 살짝 덮고 반짝이는 수면 한 줄을 그린다 (물 밖으로 나온 부분만 또렷하게)
    /// xOffset: 이 그림이 Touch Bar에서 놀이터보다 얼마나 오른쪽에 있는지 (밝기·소리 키 뒤 물결이 이어지게)
    static func drawWater(_ world: Playground, size: CGSize, in ctx: CGContext, scale: CGFloat, front: Bool, xOffset: CGFloat = 0) {
        let step = max(1, (world.px * 0.75 * scale).rounded() / scale)   // 물 픽셀 크기
        func snap(_ v: CGFloat) -> CGFloat { ClawdSprite.snap((v / step).rounded() * step, scale) }
        // 열마다 수면 높이
        var columns: [(x: CGFloat, top: CGFloat)] = []
        var x: CGFloat = 0
        while x < size.width {
            guard let surface = world.waterSurface(at: x + xOffset + step / 2) else { return }
            columns.append((x, snap(surface)))
            x += step
        }
        func fill(_ color: CGColor, _ rects: [CGRect]) {
            ctx.setFillColor(color)
            ctx.fill(rects)
        }

        if front {
            fill(CGColor(srgbRed: 0.42, green: 0.78, blue: 1, alpha: 0.24), columns.map { CGRect(x: $0.x, y: 0, width: step, height: $0.top - step) })
            fill(CGColor(srgbRed: 0.82, green: 0.95, blue: 1, alpha: 0.9), columns.map { CGRect(x: $0.x, y: $0.top - step, width: step, height: step) })
            return
        }

        // 깊이별 띠: 바닥은 짙고 수면 쪽은 밝다
        let bands: [(from: CGFloat, to: CGFloat, color: CGColor)] = [
            (0, 0.35, CGColor(srgbRed: 0.13, green: 0.42, blue: 0.68, alpha: 1)),
            (0.35, 0.7, CGColor(srgbRed: 0.19, green: 0.53, blue: 0.8, alpha: 1)),
            (0.7, 1, CGColor(srgbRed: 0.26, green: 0.63, blue: 0.88, alpha: 1)),
        ]
        for band in bands {
            fill(band.color, columns.map { col in
                let lo = snap(col.top * band.from), hi = band.to >= 1 ? col.top - 2 * step : snap(col.top * band.to)
                return CGRect(x: col.x, y: lo, width: step, height: max(0, hi - lo))
            })
        }
        fill(CGColor(srgbRed: 0.5, green: 0.8, blue: 0.95, alpha: 1), columns.map { CGRect(x: $0.x, y: $0.top - 2 * step, width: step, height: step) })

        // 물살: 하류(오른쪽)로 흘러가는 밝은 줄무늬. 누가 강을 거슬러 오를 땐 더 빠르고 진하게
        let count = max(4, Int(size.width / 30))
        var streaks: [CGRect] = []
        for i in 0..<count {
            let seed = CGFloat((i * 7919) % 997) / 997
            let speed = 0.6 + seed * 0.8
            let span = size.width + 40
            let sx = (CGFloat(i) * 30 + seed * 60 + world.flow * speed + xOffset).truncatingRemainder(dividingBy: span) - 20
            let surface = snap(world.waterSurface(at: sx + xOffset) ?? 0)
            let rows = max(1, surface / step - 6)
            let y = (2 + (seed * rows).rounded(.down)) * step
            streaks.append(CGRect(x: snap(sx), y: y, width: CGFloat(3 + (i * 31) % 4) * step, height: step))
        }
        fill(CGColor(srgbRed: 0.66, green: 0.88, blue: 1, alpha: 0.18 + 0.45 * world.current), streaks)
    }

    private static let speakerIcon = ClawdSprite.cells(["..#....", ".##.#..", "###..#.", ".##.#..", "..#...."])
    private static let mutedIcon = ClawdSprite.cells(["..#....", ".##.#.#", "###..#.", ".##.#.#", "..#...."])
    private static let sunIcon = ClawdSprite.cells(["#.#.#", ".###.", "#####", ".###.", "#.#.#"])

    /// 머리 위 팻말: 아이콘 + 16칸 바 (macOS 밝기·소리 단계와 같은 16칸)
    private static func drawGaugeSign(_ gauge: Playground.Gauge, centerX: CGFloat, headTop: CGFloat, world: Playground,
                                      in ctx: CGContext, scale: CGFloat) {
        let sp = max(1, (world.px * 0.75 * scale).rounded() / scale)
        let icon: [(Int, Int)]
        switch gauge.kind {
        case .brightness: icon = sunIcon
        case .volume: icon = speakerIcon
        case .muted: icon = mutedIcon
        }
        let iconWidth = (icon.map(\.0).max() ?? 0) + 1
        let cells = 2 + iconWidth + 2 + 16 + 2
        let box = CGRect(x: ClawdSprite.snap(centerX - CGFloat(cells) * sp / 2, scale), y: ClawdSprite.snap(headTop - 0.5, scale),
                         width: CGFloat(cells) * sp, height: 7 * sp)
        ctx.setFillColor(Palette.sign)
        ctx.fill([box.insetBy(dx: sp, dy: 0), box.insetBy(dx: 0, dy: sp)])
        ctx.setFillColor(Palette.signInk)
        ctx.fill(icon.map { CGRect(x: box.minX + CGFloat(2 + $0.0) * sp, y: box.minY + CGFloat(5 - $0.1) * sp, width: sp, height: sp) })
        let filled = gauge.kind == .muted ? 0 : Int((gauge.level * 16).rounded())
        let fill = gauge.kind == .brightness ? Palette.treat : Palette.clawd
        for i in 0..<16 {
            ctx.setFillColor(i < filled ? fill : CGColor(gray: 0.78, alpha: 1))
            ctx.fill(CGRect(x: box.minX + CGFloat(2 + iconWidth + 2 + i) * sp, y: box.minY + 2 * sp, width: sp, height: 3 * sp))
        }
    }

    /// 소리가 클수록 머리 양옆에 소리 줄이 늘어난다 ( ))) )
    private static func drawNoise(level: Float, centerX: CGFloat, bottom: CGFloat, time: Double, world: Playground,
                                  in ctx: CGContext, scale: CGFloat) {
        let count = level > 0.8 ? 3 : level > 0.55 ? 2 : level > 0.3 ? 1 : 0
        guard count > 0 else { return }
        let sp = max(1, (world.px * 0.5 * scale).rounded() / scale)
        let wiggle = CGFloat(Int(time / 0.12) % 2) * sp
        let midY = bottom + world.spriteHeight * 0.6
        ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
        for i in 0..<count {
            let offset = world.spriteWidth / 2 + sp * 2 + CGFloat(i) * sp * 3 + wiggle
            for side in [-1.0, 1.0] as [CGFloat] {
                let x = ClawdSprite.snap(centerX + side * offset, scale)
                // ( 또는 ) 모양 세 칸
                ctx.fill([CGRect(x: x, y: midY - sp, width: sp, height: sp * 3),
                          CGRect(x: x - side * sp, y: midY - sp * 2, width: sp, height: sp),
                          CGRect(x: x - side * sp, y: midY + sp * 2, width: sp, height: sp)])
            }
        }
    }

    private static let grumpyText = NSColor(srgbRed: 1.0, green: 0.6, blue: 0.55, alpha: 1)

    /// 시스템 설정이 12시간제인지
    private static let twelveHour = (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")

    /// 머리 위로 든 시계 팻말. 가운데 : 가 1초마다 깜빡인다.
    private static func drawClockSign(centerX: CGFloat, headTop: CGFloat, world: Playground, in ctx: CGContext, scale: CGFloat) {
        let now = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        var hour = now.hour ?? 0
        if twelveHour { hour = hour % 12 == 0 ? 12 : hour % 12 }
        let colon = (now.second ?? 0) % 2 == 0 ? ":" : " "
        let text = (twelveHour ? "\(hour)" : String(format: "%02d", hour)) + colon + String(format: "%02d", now.minute ?? 0)

        // 팻말 픽셀은 몸보다 조금 작게. 폭은 양손이 가장자리를 받치도록 맞춘다.
        let sp = max(1, (world.px * 0.75 * scale).rounded() / scale)
        let textWidth = CGFloat(PixelFont.width(text)) * sp
        let width = CGFloat(max(17, PixelFont.width(text)) + 4) * sp
        let height = 7 * sp
        let box = CGRect(x: ClawdSprite.snap(centerX - width / 2, scale), y: ClawdSprite.snap(headTop - 0.5, scale),
                         width: width, height: height)
        // 모서리 한 칸씩 깎은 픽셀 팻말
        ctx.setFillColor(Palette.sign)
        ctx.fill([box.insetBy(dx: sp, dy: 0), box.insetBy(dx: 0, dy: sp)])
        PixelFont.draw(text, in: ctx, left: ClawdSprite.snap(box.midX - textWidth / 2, scale), bottom: box.minY + sp,
                       px: sp, color: Palette.signInk)
    }

    private static func drawThought(_ thought: Clawd.Thought, for pet: Clawd, world: Playground) {
        let text = NSMutableAttributedString(string: thought.glyph + " ", attributes: [
            .font: thoughtFont, .foregroundColor: Palette.accent,
        ])
        text.append(NSAttributedString(string: thought.text, attributes: [
            .font: thoughtFont, .foregroundColor: thought.grumpy ? grumpyText : Palette.text,
        ]))
        let size = text.size()
        let gap: CGFloat = 4
        let half = world.spriteWidth / 2
        let fitsRight = pet.x + half + gap + size.width <= world.width
        let x = fitsRight ? pet.x + half + gap : pet.x - half - gap - size.width
        let y = (world.spriteHeight - size.height) / 2 + 1
        if world.transparent {
            // 메뉴 막대처럼 밝을 수도 있는 바탕에서도 읽히게 어두운 받침을 깐다
            let backdrop = CGRect(x: x - 4, y: y - 1, width: size.width + 8, height: size.height + 2)
            NSColor(white: 0.1, alpha: 0.8).setFill()
            NSBezierPath(roundedRect: backdrop, xRadius: backdrop.height / 2, yRadius: backdrop.height / 2).fill()
        }
        text.draw(at: CGPoint(x: x, y: y))
    }

    /// Clawd 옆에 꼬리 달린 말풍선. 글이 길면 풍선 안에서 흘러간다.
    private static func drawBubble(_ bubble: (speech: Clawd.Speech, age: Double), for pet: Clawd,
                                   world: Playground, occupied: inout [CGRect], in ctx: CGContext) {
        let text = NSMutableAttributedString(string: bubble.speech.title + " ", attributes: [
            .font: bubbleTitleFont, .foregroundColor: Palette.accent,
        ])
        text.append(NSAttributedString(string: bubble.speech.text, attributes: [
            .font: bubbleFont, .foregroundColor: Palette.bubbleText,
        ]))
        let textSize = text.size()

        let half = world.spriteWidth / 2
        let gap: CGFloat = 3, tail: CGFloat = 5, pad: CGFloat = 7, margin: CGFloat = 2
        let rightStart = pet.x + half + gap + tail
        let leftEnd = pet.x - half - gap - tail
        // 화면 끝이나 이미 자리 잡은 말풍선에 닿기 전까지의 빈자리
        func room(from start: CGFloat, toward direction: CGFloat) -> CGFloat {
            var end = direction > 0 ? world.width - margin : margin
            for other in occupied {
                if direction > 0, other.maxX > start { end = min(end, other.minX < start ? start : other.minX - 4) }
                if direction < 0, other.minX < start { end = max(end, other.maxX > start ? start : other.maxX + 4) }
            }
            return max(0, abs(end - start))
        }
        let rightRoom = room(from: rightStart, toward: 1)
        let leftRoom = room(from: leftEnd, toward: -1)
        let needed = (textSize.width + pad * 2).rounded(.up)
        let onRight = rightRoom >= needed || rightRoom >= leftRoom
        let width = min(needed, (onRight ? rightRoom : leftRoom).rounded(.down))
        guard width >= 50 else { return }   // 자리가 없으면 다른 말풍선이 사라질 때까지 기다린다
        let height: CGFloat = 22
        let box = CGRect(x: (onRight ? rightStart : leftEnd - width).rounded(),
                         y: ((world.height - height) / 2).rounded(), width: width, height: height)
        pet.bubbleFrame = box
        occupied.append(box)

        ctx.saveGState()
        ctx.setAlpha(CGFloat(min(1, bubble.age / 0.15)))

        let shape = CGPath(roundedRect: box, cornerWidth: 7, cornerHeight: 7, transform: nil)
        ctx.addPath(shape)
        ctx.setFillColor(Palette.bubbleFill)
        ctx.fillPath()
        ctx.addPath(shape)
        ctx.setStrokeColor(Palette.clawd)
        ctx.setLineWidth(1)
        ctx.strokePath()

        // 꼬리: 테두리 일부를 덮어 풍선과 이어지게
        let edge = onRight ? box.minX : box.maxX
        let dir: CGFloat = onRight ? -1 : 1
        let top = CGPoint(x: edge, y: box.minY + 12)
        let bottom = CGPoint(x: edge, y: box.minY + 6)
        let tip = CGPoint(x: edge + dir * tail, y: box.minY + 3)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: edge - dir, y: top.y))
        ctx.addLine(to: tip)
        ctx.addLine(to: CGPoint(x: edge - dir, y: bottom.y))
        ctx.closePath()
        ctx.fillPath()
        ctx.beginPath()
        ctx.move(to: top)
        ctx.addLine(to: tip)
        ctx.addLine(to: bottom)
        ctx.strokePath()

        ctx.clip(to: box.insetBy(dx: pad - 3, dy: 1))
        let textY = box.minY + (height - textSize.height) / 2
        if needed <= width {
            text.draw(at: CGPoint(x: box.minX + pad, y: textY))
        } else {
            let travel = textSize.width + 36
            let offset = (CGFloat(max(0, bubble.age - 1.2)) * 45).truncatingRemainder(dividingBy: travel)
            text.draw(at: CGPoint(x: box.minX + pad - offset, y: textY))
            text.draw(at: CGPoint(x: box.minX + pad - offset + travel, y: textY))
        }
        ctx.restoreGState()
    }
}

/// Touch Bar에 들어가는 놀이터 뷰. 터치(또는 미리보기 창에서는 마우스)로 Clawd와 놀 수 있다.
final class PlaygroundView: NSView {
    let world: Playground
    /// 이만큼 쓰고 싶지만, Touch Bar에 자리가 모자라면 남는 만큼만 쓴다
    var preferredWidth: CGFloat = 685 {
        didSet {
            widthWish.constant = preferredWidth
            widthCap.constant = preferredWidth
        }
    }
    /// 같은 아이템 안에서 옆 뷰(밝기·소리 버튼)가 차지하는 폭
    var reservedWidth: CGFloat = 0
    private lazy var widthWish = widthAnchor.constraint(equalToConstant: preferredWidth)
    private lazy var widthCap = widthAnchor.constraint(lessThanOrEqualToConstant: preferredWidth)
    /// Touch Bar에 붙었다/떨어졌다를 알려준다 (닫기 버튼으로 내려간 경우 포함)
    var onVisibilityChange: ((Bool) -> Void)?
    /// 화면 위 모드: 매 프레임 세계를 갱신한 뒤 창을 옮길 수 있게 알려 준다
    var onTick: (() -> Void)?
    /// Clawd를 오른쪽 클릭했을 때 (화면 위 모드의 메뉴)
    var onContextMenu: ((Clawd, NSEvent) -> Void)?

    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0

    private struct Grip {
        weak var pet: Clawd?
        let startX: CGFloat
        var dragging = false
        let since = CACurrentMediaTime()
        var nextPat = CACurrentMediaTime() + 0.5   // 0.5초 넘게 누르고 있으면 쓰다듬기 시작
    }
    private var grips: [AnyHashable: Grip] = [:]

    init(world: Playground) {
        self.world = world
        super.init(frame: NSRect(x: 0, y: 0, width: 685, height: 30))
        allowedTouchTypes = [.direct]
        translatesAutoresizingMaskIntoConstraints = false
        widthWish.priority = .defaultLow
        NSLayoutConstraint.activate([
            widthWish, widthCap,
            widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 30) }

    /// Touch Bar가 실제로 내준 폭보다 넓으면 통째로 안 보이므로, 받은 폭에 맞춰 줄인다.
    override func layout() {
        super.layout()
        var ancestor = superview
        while let view = ancestor, String(describing: type(of: view)) != "NSTouchBarView" { ancestor = view.superview }
        guard let barView = ancestor else { return }
        let available = (barView.bounds.width - reservedWidth).rounded(.down)
        if available >= 160 && widthCap.constant > available {
            widthCap.constant = available
            widthWish.constant = available
        }
    }
    override var acceptsFirstResponder: Bool { true }
    /// 다른 앱을 쓰다가 바로 눌러도 첫 클릭이 Clawd에게 간다
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { start() } else { stop() }
        onVisibilityChange?(window != nil)
    }

    func start() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 다른 화면 위에 겹친 창(메뉴 막대)은 클릭을 그대로 통과시키고,
    /// 마우스가 Clawd나 말풍선 위에 있을 때만 받는다.
    private func updateClickThrough() {
        guard let window else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let overPet = world.pets.contains { pet in
            (abs(pet.x - point.x) <= world.spriteWidth / 2 + 2 && point.y <= pet.y + world.spriteHeight + 2)
                || (pet.bubbleFrame?.contains(point) ?? false)
        }
        let ignore = !overPet && grips.isEmpty
        if window.ignoresMouseEvents != ignore { window.ignoresMouseEvents = ignore }
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 1.0 / 20.0)
        lastTick = now
        if bounds.width > 40 { world.width = bounds.width }
        world.update(dt)
        // 끌지 않고 꾹 누르고 있으면 계속 쓰다듬는다 (하트가 연달아)
        for (key, grip) in grips where !grip.dragging && now >= grip.nextPat {
            guard let pet = grip.pet else { continue }
            pet.pat(in: world)
            var g = grip
            g.nextPat = now + 0.45
            grips[key] = g
        }
        onTick?()
        needsDisplay = true
        if world.transparent { updateClickThrough() }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        Renderer.draw(world, in: ctx, size: bounds.size, scale: window?.backingScaleFactor ?? 2)
    }

    // MARK: - 입력 (Touch Bar 터치와 마우스를 같은 방식으로 처리)

    private func press(_ key: AnyHashable, at x: CGFloat) {
        if let pet = world.pet(at: x) {
            grips[key] = Grip(pet: pet, startX: x)
        } else {
            world.dropTreat(at: x)
            grips[key] = Grip(pet: nil, startX: x)
        }
    }

    private func move(_ key: AnyHashable, to x: CGFloat) {
        guard var grip = grips[key], let pet = grip.pet else { return }
        if !grip.dragging && abs(x - grip.startX) > 5 {
            grip.dragging = true
            pet.grab(in: world)
        }
        if grip.dragging { pet.drag(to: x, in: world) }
        grips[key] = grip
    }

    private func lift(_ key: AnyHashable) {
        guard let grip = grips.removeValue(forKey: key), let pet = grip.pet else { return }
        if grip.dragging { pet.release(in: world) } else { pet.poke(in: world) }
    }

    private func touchKey(_ touch: NSTouch) -> AnyHashable {
        if let identity = touch.identity as? NSObject { return AnyHashable(identity) }
        return AnyHashable(ObjectIdentifier(touch))
    }

    override func touchesBegan(with event: NSEvent) {
        for touch in event.touches(matching: .began, in: self) {
            press(touchKey(touch), at: touch.location(in: self).x)
        }
    }

    override func touchesMoved(with event: NSEvent) {
        for touch in event.touches(matching: .moved, in: self) {
            move(touchKey(touch), to: touch.location(in: self).x)
        }
    }

    override func touchesEnded(with event: NSEvent) {
        for touch in event.touches(matching: .ended, in: self) {
            lift(touchKey(touch))
        }
    }

    override func touchesCancelled(with event: NSEvent) {
        for touch in event.touches(matching: .cancelled, in: self) {
            lift(touchKey(touch))
        }
    }

    override func mouseDown(with event: NSEvent) {
        press("mouse", at: convert(event.locationInWindow, from: nil).x)
    }

    override func mouseDragged(with event: NSEvent) {
        move("mouse", to: convert(event.locationInWindow, from: nil).x)
    }

    override func mouseUp(with event: NSEvent) {
        lift("mouse")
    }

    override func rightMouseDown(with event: NSEvent) {
        if let pet = world.pet(at: convert(event.locationInWindow, from: nil).x), let onContextMenu {
            onContextMenu(pet, event)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

/// Touch Bar의 밝기·소리 버튼 다섯 개를 한 줄로
final class ControlPad: NSView {
    static let gap: CGFloat = 8
    static func width(buttonWidth: CGFloat, count: Int) -> CGFloat { buttonWidth * CGFloat(count) + gap * CGFloat(count - 1) }

    init(buttons: [NSButton], buttonWidth: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        var previous: NSView?
        for button in buttons {
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: buttonWidth),
                button.centerYAnchor.constraint(equalTo: centerYAnchor),
                previous.map { button.leadingAnchor.constraint(equalTo: $0.trailingAnchor, constant: Self.gap) }
                    ?? button.leadingAnchor.constraint(equalTo: leadingAnchor),
            ])
            previous = button
        }
        widthAnchor.constraint(equalToConstant: Self.width(buttonWidth: buttonWidth, count: buttons.count)).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Touch Bar의 놀이터 아이템. 놀이터 바로 옆에 밝기·소리 버튼이 올 땐 한 아이템에 붙인다
/// (아이템 사이 빈틈이 없어서, 헤엄치는 캐릭터의 강물이 버튼 뒤까지 끊기지 않고 이어진다)
final class BarContainer: NSView {
    private let playground: PlaygroundView
    private var pad: NSView?
    private var layoutConstraints: [NSLayoutConstraint] = []
    private var timer: Timer?

    init(playground: PlaygroundView) {
        self.playground = playground
        super.init(frame: NSRect(x: 0, y: 0, width: 685, height: 30))
        addSubview(playground)
        setPad(nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 30) }

    /// 버튼을 붙이거나 뗀다 (Touch Bar에 다시 올리기 전에)
    func setPad(_ newPad: NSView?) {
        NSLayoutConstraint.deactivate(layoutConstraints)
        if pad !== newPad { pad?.removeFromSuperview() }
        pad = newPad
        var constraints = [
            playground.leadingAnchor.constraint(equalTo: leadingAnchor),
            playground.topAnchor.constraint(equalTo: topAnchor),
            playground.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        if let newPad {
            if newPad.superview !== self { newPad.removeFromSuperview(); addSubview(newPad) }
            constraints += [
                newPad.leadingAnchor.constraint(equalTo: playground.trailingAnchor, constant: ControlPad.gap),
                newPad.trailingAnchor.constraint(equalTo: trailingAnchor),
                newPad.centerYAnchor.constraint(equalTo: centerYAnchor),
            ]
            playground.reservedWidth = newPad.fittingSize.width + ControlPad.gap
        } else {
            constraints.append(playground.trailingAnchor.constraint(equalTo: trailingAnchor))
            playground.reservedWidth = 0
        }
        layoutConstraints = constraints
        NSLayoutConstraint.activate(constraints)
        needsDisplay = true
        updateTimer()
    }

    private var hasWater: Bool { pad != nil && playground.world.waterLevel != nil }

    /// 캐릭터가 바뀌면 물을 켜고 끈다
    func refresh() {
        needsDisplay = true
        updateTimer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTimer()
    }

    private func updateTimer() {
        let animate = hasWater && window != nil
        if animate, timer == nil {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.needsDisplay = true }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !animate {
            timer?.invalidate()
            timer = nil
        }
    }

    /// 놀이터 오른쪽 틈과 버튼 뒤에 같은 강물을 그린다 (놀이터와 같은 x 좌표라 물결이 그대로 이어진다)
    override func draw(_ dirtyRect: NSRect) {
        guard hasWater, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let scale = window?.backingScaleFactor ?? 2
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(bounds)
        Renderer.drawWater(playground.world, size: bounds.size, in: ctx, scale: scale, front: false)
        Renderer.drawWater(playground.world, size: bounds.size, in: ctx, scale: scale, front: true)
    }
}
