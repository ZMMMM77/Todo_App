import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Explicit wrapper avoids the SDK 27 State macro dependency in Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>

struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var completed = false
    var createdAt = Date()
}

@MainActor
final class TaskStore: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var errorMessage: String?
    @Published var deletedTask: TaskItem?
    private var deletedIndex = 0
    private var writable = true
    let directory: URL
    let file: URL
    var remaining: Int { tasks.filter { !$0.completed }.count }
    init(dataDirectory: URL? = nil) {
        directory = dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ToDo App", isDirectory: true)
        file = directory.appendingPathComponent("tasks.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                tasks = try JSONDecoder().decode([TaskItem].self, from: Data(contentsOf: file))
            }
        } catch {
            writable = false
            errorMessage = "无法读取本地任务。为保护原文件，已暂停修改。\n\(error.localizedDescription)\n\(file.path)"
        }
    }
    func commit(_ next: [TaskItem]) {
        guard writable else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(next)
            try data.write(to: file, options: .atomic)
            tasks = next
        } catch { errorMessage = "保存失败，修改未写入。请检查磁盘空间和文件权限。\n\(error.localizedDescription)" }
    }
    func add(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        commit(tasks + [TaskItem(title: title)])
    }
    func rename(_ id: UUID, _ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let i = tasks.firstIndex(where: { $0.id == id }), tasks[i].title != title else { return }
        var next = tasks; next[i].title = title; commit(next)
    }
    func toggle(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        var next = tasks; next[i].completed.toggle(); commit(next)
    }
    func delete(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let item = tasks[i]
        var next = tasks; next.remove(at: i); commit(next)
        if !tasks.contains(where: { $0.id == id }) { deletedTask = item; deletedIndex = i }
    }
    func undoDelete() {
        guard let item = deletedTask else { return }
        var next = tasks; next.insert(item, at: min(deletedIndex, next.count)); commit(next)
        if tasks.contains(where: { $0.id == item.id }) { deletedTask = nil }
    }
    func move(_ id: UUID, before target: UUID) {
        guard id != target, let from = tasks.firstIndex(where: { $0.id == id }), tasks.contains(where: { $0.id == target }) else { return }
        var next = tasks; let item = next.remove(at: from)
        guard let to = next.firstIndex(where: { $0.id == target }) else { return }
        next.insert(item, at: to); commit(next)
    }
    func moveBy(_ id: UUID, offset: Int) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let peers = tasks.filter { $0.completed == tasks[i].completed }
        guard let p = peers.firstIndex(where: { $0.id == id }), peers.indices.contains(p + offset), let other = tasks.firstIndex(where: { $0.id == peers[p + offset].id }) else { return }
        var next = tasks; next.swapAt(i, other); commit(next)
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, ObservableObject, NSWindowDelegate {
    @Published var expanded = false
    @Published var visualExpanded = false
    private var transitioning = false
    @Published var pinned = false
    @Published var editing = false {
        didSet {
            if editing {
                NSApp.activate(ignoringOtherApps: true)
                panel?.makeKeyAndOrderFront(nil)
            }
        }
    }
    var panel: FloatingPanel!
    private var pending: DispatchWorkItem?
    private var anchor = NSPoint.zero
    private let ballSize = NSSize(width: 40, height: 40)
    private var pointerTimer: Timer?
    private var pointerInside = false
    private var suppressUntilExit = false
    private let expandedSize = NSSize(width: 352, height: 500)
    private var movingFrame = false
    func build(store: TaskStore) {
        let screen = NSScreen.main!.visibleFrame
        let defaults = UserDefaults.standard
        // Move the original large bubble to the new compact upper-right position once.
        if defaults.integer(forKey: "orbLayoutVersion") < 2 {
            defaults.set(screen.maxX - 8, forKey: "orbX")
            defaults.set(screen.maxY - 8, forKey: "orbY")
            defaults.set(2, forKey: "orbLayoutVersion")
        }
        anchor = NSPoint(x: defaults.object(forKey: "orbX") as? Double ?? screen.maxX - 8,
                         y: defaults.object(forKey: "orbY") as? Double ?? screen.maxY - 8)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(NSPoint(x: anchor.x - 20, y: anchor.y - 20)) }) {
            anchor = NSPoint(x: screen.maxX - 8, y: screen.maxY - 8)
        }
        panel = FloatingPanel(contentRect: NSRect(x: anchor.x - 40, y: anchor.y - 40, width: 40, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: TodoView(store: store, controller: self))
        panel.orderFrontRegardless()
        // Window geometry is authoritative, including after SwiftUI changes its size.
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
    }
    func checkPointer() {
        guard panel.isVisible, !transitioning, NSEvent.pressedMouseButtons == 0 else { return }
        let inside = panel.frame.contains(NSEvent.mouseLocation)
        if suppressUntilExit {
            if !inside { suppressUntilExit = false; pointerInside = false }
            return
        }
        if inside != pointerInside {
            pointerInside = inside
            hover(inside)
        }
    }
    func hover(_ inside: Bool) {
        pending?.cancel()
        guard !pinned && !suppressUntilExit else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.pinned else { return }
                self.setExpanded(inside)
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.25 : 0.55), execute: work)
    }
    func setExpanded(_ value: Bool) {
        guard value != expanded, !transitioning else { return }
        pending?.cancel()
        if !value {
            // End editing before removing the row views so the latest text is saved.
            panel.makeFirstResponder(nil)
            editing = false
        }
        let size = value ? expandedSize : ballSize
        let screen = NSScreen.screens.first { $0.visibleFrame.contains(NSPoint(x: anchor.x - 20, y: anchor.y - 20)) } ?? NSScreen.main!
        let bounds = screen.visibleFrame
        var frame = NSRect(x: anchor.x - size.width, y: anchor.y - size.height, width: size.width, height: size.height)
        frame.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - size.width)
        frame.origin.y = min(max(frame.minY, bounds.minY), bounds.maxY - size.height)
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.0 : (value ? 0.36 : 0.28)
        transitioning = true
        if value {
            // Enlarge the transparent host first; only the glass surface animates.
            movingFrame = true
            panel.setFrame(frame, display: true)
            movingFrame = false
            expanded = true
        }
        let destination = frame
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(.timingCurve(0.22, 0.0, 0.18, 1.0, duration: duration)) {
                self.visualExpanded = value
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.03) { [weak self] in
                guard let self else { return }
                if !value {
                    self.expanded = false
                    self.movingFrame = true
                    self.panel.setFrame(destination, display: true)
                    self.movingFrame = false
                    self.panel.resignKey()
                }
                self.transitioning = false
                self.pointerInside = true
                self.checkPointer()
            }
        }
    }

    func togglePin() {
        pinned.toggle()
        if pinned { pending?.cancel(); setExpanded(true) }
        else { hover(panel.frame.contains(NSEvent.mouseLocation)) }
    }
    func collapse() {
        pinned = false
        suppressUntilExit = true
        setExpanded(false)
    }
    func windowDidResignKey(_ notification: Notification) {
        if expanded && !pinned { hover(false) }
    }
    func reveal() {
        suppressUntilExit = false
        panel.orderFrontRegardless()
        setExpanded(true)
        pointerInside = true
    }
    func windowDidMove(_ notification: Notification) {
        guard !movingFrame else { return }
        anchor = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
        UserDefaults.standard.set(anchor.x, forKey: "orbX")
        UserDefaults.standard.set(anchor.y, forKey: "orbY")
    }
}

struct DragHandle: NSViewRepresentable {
    var excludedTrailing: CGFloat = 0
    final class Handle: NSView {
        var excludedTrailing: CGFloat = 0
        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            guard bounds.contains(local) else { return nil }
            if excludedTrailing > 0 && local.x >= bounds.maxX - excludedTrailing { return nil }
            return super.hitTest(point)
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override var mouseDownCanMoveWindow: Bool { true }
    }
    func makeNSView(context: Context) -> Handle {
        let view = Handle(); view.excludedTrailing = excludedTrailing; return view
    }
    func updateNSView(_ view: Handle, context: Context) { view.excludedTrailing = excludedTrailing }
}

struct TaskRow: View {
    let item: TaskItem
    @ObservedObject var store: TaskStore
    @ObservedObject var controller: PanelController
    @ViewState private var draft: String = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 10) {
            Button { store.toggle(item.id) } label: {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(item.completed ? Color.accentColor : Color.secondary)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(item.completed ? "恢复任务" : "完成任务")
            TextField("任务", text: $draft)
                .textFieldStyle(.plain).font(.system(size: 13))
                .strikethrough(item.completed && !focused)
                .foregroundStyle(item.completed ? .secondary : .primary)
                .focused($focused)
                .onSubmit { store.rename(item.id, draft); focused = false }
            Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(.tertiary)
                .frame(width: 28, height: 32).contentShape(Rectangle())
                .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
                .help("拖动排序；右键可移动或删除")
        }
        .padding(.vertical, 9).padding(.horizontal, 10)
        .background(.primary.opacity(focused ? 0.06 : 0.025), in: RoundedRectangle(cornerRadius: 11))
        .onAppear { draft = item.title }
        .onDisappear { store.rename(item.id, draft) }
        .onChange(of: item.title) { _, title in if !focused { draft = title } }
        .onChange(of: focused) { _, value in
            controller.editing = value
            if !value { store.rename(item.id, draft); draft = store.tasks.first(where: { $0.id == item.id })?.title ?? draft }
        }
        .contextMenu {
            Button("上移") { store.moveBy(item.id, offset: -1) }
            Button("下移") { store.moveBy(item.id, offset: 1) }
            Divider()
            Button("删除", role: .destructive) { store.delete(item.id) }
        }
        .dropDestination(for: String.self) { strings, _ in
            guard let value = strings.first, let id = UUID(uuidString: value) else { return false }
            store.move(id, before: item.id); return true
        }
    }
}

struct TodoView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var controller: PanelController
    @ViewState private var newTitle = ""
    @ViewState private var showCompleted = false
    @FocusState private var adding: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .frame(width: controller.visualExpanded ? 334 : 22,
                       height: controller.visualExpanded ? 482 : 22)
                .glassEffect(.regular, in: .rect(cornerRadius: controller.visualExpanded ? 28 : 11))
                .overlay(alignment: .topTrailing) {
                    if controller.expanded {
                        expandedView
                            .opacity(controller.visualExpanded ? 1 : 0)
                            
                            .allowsHitTesting(controller.visualExpanded)
                    }
                }
            if !controller.expanded {
            ZStack {
                Text(store.remaining == 0 ? "✓" : "\(store.remaining)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .allowsHitTesting(false)
                DragHandle()
            }
            .frame(width: 22, height: 22)
            .opacity(controller.visualExpanded ? 0 : 1)
            .allowsHitTesting(!controller.expanded)
            .accessibilityLabel("待办，\(store.remaining) 项未完成。悬停展开")
            .help("悬停查看待办 · 拖动调整位置")
            .onTapGesture { controller.reveal() }
            }
        }
        .padding(9)
        .contentShape(Rectangle())
        .gesture(TapGesture().onEnded { controller.reveal() }, including: controller.expanded ? .subviews : .all)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .onChange(of: adding) { _, value in controller.editing = value }
        .alert("本地数据提示", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
            Button("打开数据文件夹") { NSWorkspace.shared.open(store.directory) }
        } message: { Text(store.errorMessage ?? "") }
    }
    var expandedView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("待办").font(.system(size: 21, weight: .semibold))
                    Text(Date.now, format: .dateTime.month(.wide).day().weekday(.wide))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.allowsHitTesting(false)
                Spacer().allowsHitTesting(false)
                Button { controller.togglePin() } label: {
                    Image(systemName: controller.pinned ? "pin.fill" : "pin").frame(width: 36, height: 36).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(controller.pinned ? Color.accentColor : .secondary)
                    .help(controller.pinned ? "取消固定" : "固定面板")
                    .accessibilityLabel(controller.pinned ? "取消固定" : "固定面板")
                Button { adding = false; controller.collapse() } label: {
                    Image(systemName: "minus").frame(width: 36, height: 36).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(.secondary).help("收起").accessibilityLabel("收起")
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .overlay { DragHandle(excludedTrailing: 108) }
            .padding(.horizontal, -20)
            .padding(.top, -16)
            HStack {
                Text("待完成").font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(store.remaining)").font(.system(size: 11, weight: .medium, design: .rounded))
            }.foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    if store.remaining == 0 {
                        VStack(spacing: 12) {
                            Image(systemName: "sun.max").font(.system(size: 28, weight: .ultraLight))
                            Text("给今天留一点空间").font(.system(size: 13, weight: .medium))
                            Text("在下面记下一件想做的事").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 44).foregroundStyle(.secondary)
                    }
                    ForEach(store.tasks.filter { !$0.completed }) { item in
                        TaskRow(item: item, store: store, controller: controller)
                    }
                    if store.tasks.contains(where: \.completed) {
                        VStack(spacing: 6) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { showCompleted.toggle() }
                            } label: {
                                HStack {
                                    Image(systemName: "chevron.right")
                                        .rotationEffect(.degrees(showCompleted ? 90 : 0))
                                    Text("已完成 · \(store.tasks.count - store.remaining)")
                                    Spacer()
                                }
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            .accessibilityLabel(showCompleted ? "收起已完成" : "展开已完成")
                            if showCompleted {
                                ForEach(store.tasks.filter(\.completed)) { item in
                                    TaskRow(item: item, store: store, controller: controller)
                                }
                            }
                        }.padding(.top, 12)
                    }
                }
            }.scrollIndicators(.hidden)
            if store.deletedTask != nil {
                HStack {
                    Text("已删除任务").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button { store.undoDelete() } label: { Text("撤销").frame(minWidth: 44, minHeight: 32).contentShape(Rectangle()) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.accentColor)
                }
            }
            HStack(spacing: 8) {
                Button {
                    controller.editing = true
                    adding = true
                } label: {
                    Image(systemName: "plus").foregroundStyle(.secondary)
                        .frame(width: 28, height: 32).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("输入新待办")
                TextField("添加一件待办…", text: $newTitle)
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($adding)
                    .onSubmit(addTask)
                if !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: addTask) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)).frame(width: 32, height: 32).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel("添加任务")
                }
            }.frame(minHeight: 32).padding(.horizontal, 12).padding(.vertical, 6)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                controller.editing = true
                adding = true
            })
            HStack(spacing: 4) {
                Image(systemName: "internaldrive").font(.system(size: 9))
                Text("仅存储在此 Mac").font(.system(size: 10))
                Spacer()
                Text("拖动顶部移动").font(.system(size: 10))
            }.foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 334, height: 482)
    }
    func addTask() {
        let count = store.tasks.count
        store.add(newTitle)
        if store.tasks.count > count { newTitle = "" }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = TaskStore()
    let controller = PanelController()
    var statusItem: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller.build(store: store)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "ToDo App")
        let menu = NSMenu()
        for (title, action, key) in [("显示待办", #selector(show), ""), ("隐藏悬浮球", #selector(hide), ""), ("打开本地数据文件夹", #selector(openData), ""), ("退出 ToDo App", #selector(quit), "q")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self; menu.addItem(item)
        }
        statusItem.menu = menu
        if store.errorMessage != nil { controller.reveal() }
    }
    @objc func show() { controller.reveal() }
    @objc func hide() { controller.panel.orderOut(nil) }
    @objc func openData() { NSWorkspace.shared.open(store.directory) }
    @objc func quit() { NSApp.terminate(nil) }
}
if CommandLine.arguments.contains("--self-test") {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("todo-tests-" + UUID().uuidString)
    let test = TaskStore(dataDirectory: temp)
    test.add("  测试任务  "); test.add("第二项"); test.add("   ")
    precondition(test.tasks.count == 2 && test.tasks[0].title == "测试任务")
    let id = test.tasks[0].id
    test.rename(id, "已编辑"); test.toggle(id)
    precondition(test.remaining == 1)
    let loaded = TaskStore(dataDirectory: temp)
    precondition(loaded.tasks == test.tasks)
    test.delete(id); precondition(test.tasks.count == 1)
    test.undoDelete(); precondition(test.tasks.count == 2 && test.tasks[0].id == id)
    test.toggle(id); test.moveBy(id, offset: 1)
    precondition(test.tasks[1].id == id)
    test.move(id, before: test.tasks[0].id)
    precondition(test.tasks[0].id == id)
    try! Data("invalid json".utf8).write(to: test.file)
    let damaged = TaskStore(dataDirectory: temp)
    precondition(damaged.errorMessage != nil)
    damaged.add("must not overwrite")
    precondition(String(data: try! Data(contentsOf: damaged.file), encoding: .utf8) == "invalid json")
    try! FileManager.default.removeItem(at: temp)
    print("PASS: add, trim, rename, completion, persistence, delete/undo, sorting, corrupt-file protection")
    exit(0)
}
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
