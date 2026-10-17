import AppKit

/// 설정 창의 한 줄. 값은 그때그때 AppDelegate에서 읽고 바꿔서, 메뉴·Touch Bar와 어긋나지 않는다.
struct SettingRow {
    struct Option {
        var title: String
        var image: NSImage? = nil
        var value: String
    }
    struct Action {
        var title: () -> String
        var run: () -> Void
    }
    enum Control {
        case toggle(String, get: () -> Bool, set: (Bool) -> Void)
        case popup([Option], get: () -> String, set: (String) -> Void)
        /// 라디오 단추 하나. 같은 get을 쓰는 줄끼리 한 묶음
        case radio(Option, get: () -> String, set: (String) -> Void)
        /// 상태 한 줄과 버튼들 (연결, 한도 맞추기)
        case actions(status: (() -> String)?, [Action])
    }

    /// 왼쪽 이름. 같은 묶음의 둘째 줄부터는 비운다
    var label = ""
    var control: Control
    var note: (() -> String?)? = nil
    var enabled: () -> Bool = { true }
}

struct SettingsPane {
    var title: String
    var symbol: String
    var rows: [SettingRow]
}

/// 메뉴 막대 메뉴의 "설정…": 일반 · Touch Bar · Claude 탭.
/// 언어를 바꾸면 새 말로 다시 짠다.
final class SettingsWindow: NSObject, NSWindowDelegate, NSToolbarDelegate {
    private let makePanes: () -> [SettingsPane]
    private var panes: [SettingsPane] = []
    private var views: [NSView] = []
    private var window: NSWindow?
    private var selected = 0
    /// 컨트롤마다 지금 값·켜짐을 다시 읽어 오는 것들
    private var refreshers: [() -> Void] = []
    /// 컨트롤의 target은 약하게 잡히므로 여기서 붙잡아 둔다
    private var targets: [ClosureTarget] = []
    private static let width: CGFloat = 520

    init(panes: @escaping () -> [SettingsPane]) {
        makePanes = panes
    }

    /// tab: 몇 번째 탭을 열지 (없으면 마지막에 본 탭)
    func show(tab: Int? = nil) {
        if window == nil { build() }
        if let tab, tab != selected { select(tab, animate: false) }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 언어가 바뀌었을 때: 열려 있으면 같은 탭으로 다시 짓고, 닫혀 있으면 다음에 열 때 새로 짓는다
    func rebuild() {
        guard let window else { return }
        let reopen = window.isVisible
        let origin = window.frame.origin
        window.delegate = nil
        window.orderOut(nil)
        self.window = nil
        guard reopen else { return }
        build()
        self.window?.setFrameTopLeftPoint(NSPoint(x: origin.x, y: window.frame.maxY))
        show()
    }

    func refresh() {
        refreshers.forEach { $0() }
        // 설명 줄이 나타나거나 사라지면 창 높이도 따라간다
        if let view = window?.contentView, views.contains(where: { $0 === view }) { fit(view, animate: false) }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }

    // MARK: - 창

    private func build() {
        panes = makePanes()
        refreshers = []
        targets = []
        views = panes.map(makePaneView)
        selected = min(selected, panes.count - 1)

        let window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
                               styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = self
        let toolbar = NSToolbar(identifier: "ClawdSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        if #available(macOS 11, *) { window.toolbarStyle = .preference }
        self.window = window
        select(selected, animate: false)
        window.center()
    }

    private func select(_ index: Int, animate: Bool) {
        guard let window, views.indices.contains(index) else { return }
        selected = index
        window.toolbar?.selectedItemIdentifier = itemID(index)
        window.title = panes[index].title
        // 값과 설명 줄을 먼저 채워야 높이를 제대로 잰다
        window.contentView = NSView()
        refresh()
        fit(views[index], animate: animate)
        window.contentView = views[index]
    }

    /// 위쪽 모서리를 고정한 채 탭 내용에 맞춰 창 높이를 바꾼다
    private func fit(_ view: NSView, animate: Bool) {
        guard let window else { return }
        let content = NSRect(x: 0, y: 0, width: Self.width, height: view.fittingSize.height)
        var frame = window.frameRect(forContentRect: content)
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true, animate: animate && window.isVisible)
    }

    private func itemID(_ index: Int) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("pane\(index)")
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { panes.indices.map(itemID) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { panes.indices.map(itemID) }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { panes.indices.map(itemID) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let index = panes.indices.first(where: { itemID($0) == id }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = panes[index].title
        item.image = NSImage(systemSymbolName: panes[index].symbol, accessibilityDescription: panes[index].title)
        item.target = self
        item.action = #selector(toolbarSelect(_:))
        item.tag = index
        return item
    }

    @objc private func toolbarSelect(_ sender: NSToolbarItem) {
        select(sender.tag, animate: true)
    }

    // MARK: - 탭 내용

    private func makePaneView(_ pane: SettingsPane) -> NSView {
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.column(at: 0).width = 150
        for (i, row) in pane.rows.enumerated() {
            let label = NSTextField(labelWithString: row.label.isEmpty ? "" : row.label + ":")
            let gridRow = grid.addRow(with: [label, makeControl(row)])
            gridRow.rowAlignment = .firstBaseline
            // 새 묶음이 시작하면 조금 띄운다
            if i > 0 && !row.label.isEmpty { gridRow.topPadding = 8 }
            if let note = row.note { addNote(note, for: row, to: grid) }
        }
        grid.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.width),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -22),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
        ])
        return container
    }

    private func target(_ run: @escaping (Any) -> Void) -> ClosureTarget {
        let target = ClosureTarget(run: { [weak self] sender in
            run(sender)
            self?.refresh()   // 하나를 바꾸면 다른 줄의 켜짐도 달라질 수 있다
        })
        targets.append(target)
        return target
    }

    private func makeControl(_ row: SettingRow) -> NSView {
        var controls: [NSControl] = []
        let main: NSView
        switch row.control {
        case let .toggle(title, get, set):
            let box = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            let t = target { _ in set(box.state == .on) }
            box.target = t
            box.action = #selector(ClosureTarget.fire(_:))
            refreshers.append { box.state = get() ? .on : .off }
            controls = [box]
            main = box

        case let .popup(options, get, set):
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            for option in options {
                popup.addItem(withTitle: option.title)
                popup.lastItem?.image = option.image
                popup.lastItem?.representedObject = option.value
            }
            let t = target { _ in
                if let value = popup.selectedItem?.representedObject as? String { set(value) }
            }
            popup.target = t
            popup.action = #selector(ClosureTarget.fire(_:))
            refreshers.append {
                let value = get()
                if let item = popup.itemArray.first(where: { $0.representedObject as? String == value }) { popup.select(item) }
            }
            controls = [popup]
            main = popup

        case let .radio(option, get, set):
            let radio = NSButton(radioButtonWithTitle: option.title, target: nil, action: nil)
            let t = target { _ in set(option.value) }
            radio.target = t
            radio.action = #selector(ClosureTarget.fire(_:))
            refreshers.append { radio.state = get() == option.value ? .on : .off }
            controls = [radio]
            main = radio

        case let .actions(status, actions):
            let stack = NSStackView()
            stack.spacing = 8
            if let status {
                let label = NSTextField(labelWithString: status())
                refreshers.append { label.stringValue = status() }
                stack.addArrangedSubview(label)
            }
            for action in actions {
                let button = NSButton(title: action.title(), target: nil, action: nil)
                button.bezelStyle = .rounded
                let t = target { _ in action.run() }
                button.target = t
                button.action = #selector(ClosureTarget.fire(_:))
                refreshers.append { button.title = action.title() }
                stack.addArrangedSubview(button)
                controls.append(button)
            }
            main = stack
        }

        let enabled = row.enabled
        refreshers.append { let on = enabled(); controls.forEach { $0.isEnabled = on } }
        return main
    }

    /// 설명은 컨트롤 아래 줄에 작은 회색 글씨로. 할 말이 없으면 줄째 숨긴다
    private func addNote(_ note: @escaping () -> String?, for row: SettingRow, to grid: NSGridView) {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = Self.width - 220
        // 체크박스·라디오는 글자 시작에 맞춰 들여 쓴다
        var indent: CGFloat = 0
        switch row.control {
        case .toggle, .radio: indent = 20
        default: break
        }
        let box = NSView()
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: indent),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            label.topAnchor.constraint(equalTo: box.topAnchor),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        let gridRow = grid.addRow(with: [NSGridCell.emptyContentView, box])
        gridRow.topPadding = -5
        refreshers.append {
            let text = note() ?? ""
            label.stringValue = text
            gridRow.isHidden = text.isEmpty
        }
    }
}

/// NSControl의 target-action을 클로저로
final class ClosureTarget: NSObject {
    let run: (Any) -> Void
    init(run: @escaping (Any) -> Void) { self.run = run }
    @objc func fire(_ sender: Any) { run(sender) }
}

/// 메뉴 막대가 없는 앱이라 ⌘W를 직접 받는다
final class KeyWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
