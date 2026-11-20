import AppKit
import SwiftUI

/// Painel sem borda e não ativável, fixado sobre o notch.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Cria e posiciona o painel do notch. Reposiciona ao trocar de tela ou de resolução.
@MainActor
final class NotchPanelController {
    private var panel: NotchPanel?
    private let model: StorageModel
    private let openSettings: () -> Void
    private var state: NotchState?
    private var screenObserver: NSObjectProtocol?
    private var mouseMonitors: [Any] = []

    init(model: StorageModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }

        // A janela é maior que a forma desenhada. Fora da forma ela ignora o mouse,
        // para não roubar cliques das janelas logo abaixo do notch.
        // O monitor global vê o mouse sobre outros apps e o local vê o mouse sobre o painel.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMousePassThrough() }
        }) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updateMousePassThrough() }
            return event
        }) { mouseMonitors.append(local) }
    }

    /// Retângulo (em coordenadas de tela) da forma visível no momento.
    private var activeRect: CGRect? {
        guard let state, let screen = targetScreen else { return nil }
        let size = state.isExpanded ? NotchGeometry.expandedSize : state.geometry.collapsedSize
        let offset = state.isExpanded ? 0 : state.geometry.collapsedOffsetX
        return CGRect(x: screen.frame.midX - size.width / 2 + offset,
                      y: screen.frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    private func updateMousePassThrough() {
        guard let panel, let rect = activeRect else { return }
        let inside = rect.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        if panel == nil { build() }
        layout()
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    /// Tela com notch, se houver; senão a principal.
    private var targetScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    static let sideKey = "notchSide"

    static var side: NotchSide {
        NotchSide(rawValue: UserDefaults.standard.string(forKey: sideKey) ?? "") ?? .left
    }

    func setSide(_ side: NotchSide) {
        UserDefaults.standard.set(side.rawValue, forKey: Self.sideKey)
        layout()
    }

    static func geometry(for screen: NSScreen) -> NotchGeometry {
        let top = screen.safeAreaInsets.top
        if top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return NotchGeometry(notchWidth: width, notchHeight: top, hasNotch: true, side: side)
        }
        // Sem notch (monitor externo): uma "pílula" virtual da altura da barra de menus.
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(notchWidth: 120, notchHeight: max(24, menuBar), hasNotch: false, side: side)
    }

    private func build() {
        guard let screen = targetScreen else { return }
        let state = NotchState(geometry: Self.geometry(for: screen))
        self.state = state

        let panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true

        let root = NotchView(state: state, model: model, openSettings: openSettings)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
    }

    /// A janela tem sempre o tamanho expandido. As áreas transparentes deixam o clique passar.
    private func layout() {
        guard let panel, let state, let screen = targetScreen else { return }
        state.geometry = Self.geometry(for: screen)
        let size = CGSize(width: NotchGeometry.expandedSize.width + 40,
                          height: NotchGeometry.expandedSize.height + 30)
        let origin = CGPoint(x: screen.frame.midX - size.width / 2,
                             y: screen.frame.maxY - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }
}
