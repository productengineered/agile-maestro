import AppKit
import SwiftUI
import XCTest
@testable import AgileMaestro

// MARK: - KanbanFilterBarLayoutTests
//
// Regression coverage for task-6 (Bug 6, AM-800): the Kanban type-filter segmented
// Picker was capped with `.frame(maxWidth: 360)`, smaller than its ~516pt intrinsic
// width (6 segments incl. "Tech Debt"). The AppKit-backed segmented control rendered
// at full intrinsic width anyway, centered within the 360pt frame — clipping the
// first segment at the window's left edge and overlapping the "All Epics" Menu.
//
// Fix: `.fixedSize()` on the type Picker (KanbanFilterBarView.swift), plus a bounded,
// middle-truncated label on the epic Menu (unlike the Picker, the Menu's label is
// unbounded free-form project data — `.fixedSize()` there would reintroduce the same
// bug class for a long epic name, which is what CodeRabbit's C11 review caught).
//
// IMPORTANT — why the *previous* version of this test file was rejected (code review
// C10/C12, CodeRabbit C11): it only ever measured `NSHostingView.fittingSize`, i.e.
// SwiftUI's *negotiated ideal size* under an unconstrained/nil proposal. That
// measurement is exactly what the original bug hid from: `.frame(maxWidth: 360)`'s
// `sizeThatFits` reports a size clamped to ~360pt for an *unconstrained* query, even
// though the real `NSSegmentedControl` — which refuses to compress below the width
// needed to show all 6 un-truncated segment labels — is *placed* at its full ~516pt
// width when given a real, finite proposal, centered within the 360pt slot the parent
// HStack allocated. That produced the real, on-screen negative x-origin (left-edge
// clipping) and menu overlap seen in the bug screenshot, none of which `fittingSize`
// reports. A test built only on `fittingSize` therefore passes identically whether the
// bug is present or fixed (confirmed empirically — see task-6 fix comment for the
// revert-and-rerun evidence).
//
// This rewrite instead hosts the PRODUCTION `KanbanFilterBarView` in an offscreen
// (never made key, never ordered front — no app launch, no screen capture) `NSWindow`
// at a REAL, finite width (800pt — the app's minimum window width), forces a full
// AppKit layout pass, and inspects the segmented control's and epic Menu's actual
// *placed* frames — converted into the hosting view's coordinate space via
// `NSView.convert(_:to:)`, since a found subview's own `.frame` is relative to its
// immediate superview, not the root. This is the same signal a human sees on screen,
// and is empirically proven (task-6 fix comment) to fail against the pre-fix
// `.frame(maxWidth: 360)` / unbounded-Menu-label code and pass against the fix.
final class KanbanFilterBarLayoutTests: XCTestCase {

    /// Matches `KanbanBoardView.swift` (`.frame(minWidth: 800, ...)`) and
    /// `AgileMaestroApp.swift` (`.defaultSize`/window minWidth 800) — the smallest
    /// window width Kanban mode must render in without clipping (no sidebar in
    /// this mode, so the filter bar owns the full window/content width).
    private static let minimumWindowWidth: CGFloat = 800

    /// The old, rejected `.frame(maxWidth: 360)` cap on the type Picker.
    private static let previousBuggyPickerCap: CGFloat = 360

    /// The old, rejected `.frame(width: 180)` cap on `ViewModeSegment`.
    private static let previousBuggyViewModeSegmentWidth: CGFloat = 180

    /// Generous upper bound on the epic Menu's real rendered width — comfortably above
    /// `KanbanFilterBarView.epicLabelMaxWidth` (140pt) plus chevron/native-chrome
    /// padding, but far below what an *unbounded* very-long epic name would render at
    /// (proven empirically to run past 1000pt — see task-6 fix comment).
    private static let epicMenuMaxRealWidth: CGFloat = 220

    private var hostedWindows: [NSWindow] = []

    override func tearDown() {
        hostedWindows.removeAll()
        super.tearDown()
    }

    private func representativeEpicIDs() -> [String] {
        ["AM-300", "AM-400", "AM-500"]
    }

    // MARK: - Hosting helpers

    /// Hosts `view` in an offscreen `NSWindow` (never made key, never ordered front — no
    /// app launch, no screen capture) and forces a full AppKit layout pass, so
    /// AppKit-backed SwiftUI controls (e.g. the segmented Picker's real
    /// `NSSegmentedControl`, the epic Menu's real `NSPopUpButton`) get real, placed
    /// frames rather than just SwiftUI's negotiated `sizeThatFits` result.
    /// Returns both the hosting view and the window; the window is retained by the test
    /// property `hostedWindows` to prevent deallocation during assertions.
    @MainActor
    private func hostAndLayout<V: View>(
        _ view: V,
        width: CGFloat,
        height: CGFloat = 60
    ) -> (NSHostingView<V>, NSWindow) {
        let hostingView = NSHostingView(rootView: view)
        let contentRect = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.frame = contentRect

        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        hostedWindows.append(window)
        return (hostingView, window)
    }

    /// Recursively searches `view`'s real (post-layout) subview tree for the first
    /// view of type `T`, matched by public AppKit ancestor type (not by private class
    /// name, which SwiftUI's AppKit bridging changes across macOS versions).
    private func findSubview<T: NSView>(ofType type: T.Type, in view: NSView) -> T? {
        if let match = view as? T {
            return match
        }
        for subview in view.subviews {
            if let found = findSubview(ofType: type, in: subview) {
                return found
            }
        }
        return nil
    }

    /// A found subview's own `.frame` is relative to its *immediate superview*, not the
    /// root hosting view — so two views nested at different depths aren't directly
    /// comparable via raw `.frame`. This converts into the hosting view's coordinate
    /// space, which is what actually determines on-screen overlap/clipping.
    private func rootRelativeFrame(of view: NSView, in hostingView: NSView) -> NSRect {
        view.convert(view.bounds, to: hostingView)
    }

    // MARK: - Type picker: real rendered frame must not overflow

    @MainActor
    func testTypePickerRealFrameDoesNotOverflowAtMinimumWindowWidth() throws {
        let view = KanbanFilterBarView(
            typeFilter: .constant(.all),
            epicFilter: .constant(nil),
            filteredCount: 42,
            totalCount: 42,
            availableEpicIDs: representativeEpicIDs()
        )
        let (hostingView, _) = hostAndLayout(view, width: Self.minimumWindowWidth)

        let segmentedControl = try XCTUnwrap(
            findSubview(ofType: NSSegmentedControl.self, in: hostingView),
            "Expected to find the real NSSegmentedControl backing the type Picker in the " +
                "production view's layout tree"
        )
        let realFrame = rootRelativeFrame(of: segmentedControl, in: hostingView)

        XCTAssertGreaterThan(
            realFrame.width,
            Self.previousBuggyPickerCap,
            "Segmented control's real rendered width (\(realFrame.width)pt) should exceed the old " +
                "buggy \(Self.previousBuggyPickerCap)pt cap — it must not be compressed"
        )
        XCTAssertGreaterThanOrEqual(
            realFrame.minX,
            0,
            "Segmented control's real x-origin (\(realFrame.minX)) must not be negative — a " +
                "negative origin is exactly the left-edge clipping seen in the bug screenshot " +
                "(the old `.frame(maxWidth: 360)` centered the oversized control, pushing it off " +
                "the leading edge)"
        )
        XCTAssertLessThanOrEqual(
            realFrame.maxX,
            hostingView.bounds.width,
            "Segmented control's real right edge (\(realFrame.maxX)) must not extend past the " +
                "filter bar's own width (\(hostingView.bounds.width))"
        )
    }

    /// Same assertions with the longest type label (Tech Debt) and an epic filter active —
    /// the selection state most likely to widen the row.
    @MainActor
    func testTypePickerRealFrameDoesNotOverflowInFilteredState() throws {
        let view = KanbanFilterBarView(
            typeFilter: .constant(.techdebt),
            epicFilter: .constant("AM-400"),
            filteredCount: 3,
            totalCount: 42,
            availableEpicIDs: representativeEpicIDs()
        )
        let (hostingView, _) = hostAndLayout(view, width: Self.minimumWindowWidth)

        let segmentedControl = try XCTUnwrap(
            findSubview(ofType: NSSegmentedControl.self, in: hostingView),
            "Expected to find the real NSSegmentedControl in the filtered-state layout tree"
        )
        let realFrame = rootRelativeFrame(of: segmentedControl, in: hostingView)

        XCTAssertGreaterThanOrEqual(
            realFrame.minX,
            0,
            "Filtered-state segmented control must not clip past the leading edge (real minX: \(realFrame.minX))"
        )
        XCTAssertLessThanOrEqual(
            realFrame.maxX,
            hostingView.bounds.width,
            "Filtered-state segmented control must not extend past the filter bar width (real maxX: \(realFrame.maxX))"
        )
    }

    // MARK: - Type picker and epic Menu must not overlap (the exact bug symptom)

    @MainActor
    func testTypePickerAndEpicMenuDoNotOverlap() throws {
        let view = KanbanFilterBarView(
            typeFilter: .constant(.all),
            epicFilter: .constant(nil),
            filteredCount: 42,
            totalCount: 42,
            availableEpicIDs: representativeEpicIDs()
        )
        let (hostingView, _) = hostAndLayout(view, width: Self.minimumWindowWidth)

        let segmentedControl = try XCTUnwrap(
            findSubview(ofType: NSSegmentedControl.self, in: hostingView),
            "Expected to find the real NSSegmentedControl"
        )
        let epicMenu = try XCTUnwrap(
            findSubview(ofType: NSPopUpButton.self, in: hostingView),
            "Expected to find the real NSPopUpButton backing the epic Menu"
        )

        let pickerFrame = rootRelativeFrame(of: segmentedControl, in: hostingView)
        let menuFrame = rootRelativeFrame(of: epicMenu, in: hostingView)

        XCTAssertLessThanOrEqual(
            pickerFrame.maxX,
            menuFrame.minX,
            "Type picker (real maxX: \(pickerFrame.maxX)) must not overlap the epic Menu (real " +
                "minX: \(menuFrame.minX)) — this is the exact visual bug from the screenshot " +
                "(\"Tech Debt\" drawn over \"All Epics ⌄\")"
        )
    }

    // MARK: - Epic Menu label: bounded real width for very long epic IDs (CodeRabbit C11 #1)

    @MainActor
    func testEpicMenuLabelStaysBoundedForVeryLongEpicNames() throws {
        let veryLongEpicID = "CASHFLOW-705-1-" +
            String(repeating: "migrate-legacy-reporting-pipeline-", count: 6)
        let view = KanbanFilterBarView(
            typeFilter: .constant(.all),
            epicFilter: .constant(veryLongEpicID),
            filteredCount: 3,
            totalCount: 42,
            availableEpicIDs: [veryLongEpicID]
        )
        let (hostingView, _) = hostAndLayout(view, width: Self.minimumWindowWidth)

        let segmentedControl = try XCTUnwrap(
            findSubview(ofType: NSSegmentedControl.self, in: hostingView),
            "Expected to find the real NSSegmentedControl"
        )
        let epicMenu = try XCTUnwrap(
            findSubview(ofType: NSPopUpButton.self, in: hostingView),
            "Expected to find the real NSPopUpButton backing the epic Menu, even with a " +
                "\(veryLongEpicID.count)-character epic name"
        )

        let pickerFrame = rootRelativeFrame(of: segmentedControl, in: hostingView)
        let menuFrame = rootRelativeFrame(of: epicMenu, in: hostingView)

        // Unbounded (pre-truncation) code renders the Menu at a width that grows with the
        // epic name's character count (proven empirically to exceed 1000pt for this
        // 219-character name). With `.lineLimit(1)` + `.truncationMode(.middle)` +
        // `.frame(maxWidth: epicLabelMaxWidth)` applied, the real rendered width stays
        // bounded regardless of string length.
        XCTAssertLessThanOrEqual(
            menuFrame.width,
            Self.epicMenuMaxRealWidth,
            "Epic Menu's real rendered width (\(menuFrame.width)pt) for a " +
                "\(veryLongEpicID.count)-character epic name must stay bounded near " +
                "epicLabelMaxWidth — it must truncate, not grow unbounded"
        )
        XCTAssertLessThanOrEqual(
            menuFrame.maxX,
            hostingView.bounds.width,
            "Epic Menu's real right edge (\(menuFrame.maxX)) must not extend past the filter bar's " +
                "own width (\(hostingView.bounds.width)) even with a very long epic name"
        )
        XCTAssertLessThanOrEqual(
            pickerFrame.maxX,
            menuFrame.minX,
            "Type picker must not overlap the epic Menu even with a very long epic name"
        )
    }

    // MARK: - ViewModeSegment (main toolbar, same anti-pattern fixed alongside)

    @MainActor
    func testViewModeSegmentFitsWithinReasonableToolbarWidth() {
        let view = ViewModeSegment(selectedMode: .constant(.treeDetail))
        let hostingView = NSHostingView(rootView: view)
        let idealSize = hostingView.fittingSize

        XCTAssertGreaterThan(
            idealSize.width,
            Self.previousBuggyViewModeSegmentWidth,
            "View mode segment intrinsic width (\(idealSize.width)pt) regressed to (or below) the " +
                "old fixed \(Self.previousBuggyViewModeSegmentWidth)pt cap — this must exceed it to " +
                "prove the control is sizing to its own intrinsic content, not being squeezed"
        )
        XCTAssertLessThan(
            idealSize.width,
            500,
            "View mode segment intrinsic width (\(idealSize.width)pt) is unexpectedly large for 3 segments"
        )
    }
}
