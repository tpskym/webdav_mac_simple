import AppKit
import SwiftUI

/// Устанавливает doubleAction на NSTableView, которому принадлежит этот view.
/// Размещается как .background на List — не влияет на выделение строк.
struct TableDoubleClickSetup: NSViewRepresentable {
    /// Вызывается при двойном клике; передаёт индекс кликнутой строки.
    var onDoubleClick: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDoubleClick: onDoubleClick) }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDoubleClick = onDoubleClick
        // Запускаем поиск после того, как иерархия View построена
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if let tv = Self.findTableView(in: window.contentView!) {
                tv.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
                tv.target = context.coordinator
            }
        }
    }

    private static func findTableView(in root: NSView) -> NSTableView? {
        if let tv = root as? NSTableView { return tv }
        for sub in root.subviews {
            if let tv = findTableView(in: sub) { return tv }
        }
        return nil
    }

    final class Coordinator: NSObject {
        var onDoubleClick: (Int) -> Void
        init(onDoubleClick: @escaping (Int) -> Void) { self.onDoubleClick = onDoubleClick }

        @objc func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0 else { return }
            onDoubleClick(row)
        }
    }
}
