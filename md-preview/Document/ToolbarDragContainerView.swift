//
//  ToolbarDragContainerView.swift
//  md-preview
//
//  The drag surface a custom-view toolbar item would otherwise not have.
//

import Cocoa

/// Hosts a control inside a toolbar item and keeps the rest of that item's cell
/// working as window-drag chrome.
///
/// AppKit starts a window drag only from a view that leaves the mouse-down
/// unhandled, and every `NSControl` handles it. A toolbar assembled out of
/// custom control views therefore has almost no drag surface left: on the stock
/// layout the only regions that still move the window are the `.flexibleSpace`
/// and `.space` items, which is why the window can be grabbed beside the
/// sidebar button and essentially nowhere else.
///
/// The cell is claimed for hit-testing only — the view keeps its natural size.
/// Growing the view instead is the obvious approach and it is wrong: on macOS
/// 26 the glass capsule behind a toolbar group (`NSToolbarPlatterView`) is
/// sized from the item view, so a container stretched to a 52pt cell drags the
/// capsule from 36pt to 52pt with it and the group renders as a fat slab beside
/// its correctly-sized neighbours. Overriding `hitTest` decouples the rectangle
/// we take mouse-downs from off the rectangle AppKit paints glass into.
final class ToolbarDragContainerView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // In the customization palette the item is a draggable template, not
        // chrome — moving the window there would eat the drag that reorders it.
        guard window?.toolbar?.customizationPaletteIsRunning != true else {
            super.mouseDown(with: event)
            return
        }
        window?.performDrag(with: event)
    }

    /// Claims the whole item cell, not just the control's own frame. The hosted
    /// control still wins wherever it actually is, so clicks are unaffected.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let hit = super.hitTest(point) { return hit }
        guard let superview, superview.bounds.contains(point) else { return nil }
        return self
    }
}
