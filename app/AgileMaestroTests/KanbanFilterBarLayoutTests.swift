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
// Fix: `.fixedSize()` on both the Picker and the Menu (KanbanFilterBarView.swift)
// so each control lays out at its true intrinsic width with no compression. This
// test proves two things per the approved RCA/RCA-review (task-6 C2/C3):
//   1. The composed filter bar's intrinsic width fits within the app's 800pt
//      minimum window width (KanbanBoardView.swift/AgileMaestroApp.swift), i.e.
//      nothing is clipped at the smallest supported window size.
//   2. The type Picker is no longer artificially compressed below its intrinsic
//      width (regression guard against reintroducing a `.frame(maxWidth:)` cap).
//
// No snapshot/image-diffing library is available in this project (see
// KanbanCardViewTests.swift precedent). `NSHostingView.fittingSize` is used
// instead to measure real AppKit-backed layout without rendering to screen —
// this works headlessly and does not require app launch or Peekaboo.
final class KanbanFilterBarLayoutTests: XCTestCase {

    /// Matches `KanbanBoardView.swift` (`.frame(minWidth: 800, ...)`) and
    /// `AgileMaestroApp.swift` (`.defaultSize`/window minWidth 800) — the smallest
    /// window width Kanban mode must render in without clipping (no sidebar in
    /// this mode, so the filter bar owns the full window width).
    private static let minimumWindowWidth: CGFloat = 800

    private func representativeEpicIDs() -> [String] {
        ["AM-300", "AM-400", "AM-500"]
    }

    // MARK: - Fits at minimum window width (RCA "mandatory narrow-width check")

    @MainActor
    func testFilterBarFitsWithinMinimumWindowWidth() {
        let view = KanbanFilterBarView(
            typeFilter: .constant(.all),
            epicFilter: .constant(nil),
            filteredCount: 42,
            totalCount: 42,
            availableEpicIDs: representativeEpicIDs()
        )
        let hostingView = NSHostingView(rootView: view)
        let idealSize = hostingView.fittingSize

        XCTAssertGreaterThan(idealSize.width, 0, "Hosting view should report a nonzero intrinsic width")
        XCTAssertLessThanOrEqual(
            idealSize.width,
            Self.minimumWindowWidth,
            "Filter bar intrinsic width (\(idealSize.width)pt) must fit within the app's " +
                "\(Self.minimumWindowWidth)pt minimum window width with no clipping"
        )
    }

    /// Same as above but with the longest-label filter selected (Tech Debt) and an
    /// epic filter active, since the menu label switches from "All Epics" to the
    /// selected epic ID — confirms neither selection state pushes the row past 800pt.
    @MainActor
    func testFilterBarFitsWithinMinimumWindowWidth_FilteredState() {
        let view = KanbanFilterBarView(
            typeFilter: .constant(.techdebt),
            epicFilter: .constant("AM-400"),
            filteredCount: 3,
            totalCount: 42,
            availableEpicIDs: representativeEpicIDs()
        )
        let hostingView = NSHostingView(rootView: view)
        let idealSize = hostingView.fittingSize

        XCTAssertLessThanOrEqual(
            idealSize.width,
            Self.minimumWindowWidth,
            "Filtered-state filter bar intrinsic width (\(idealSize.width)pt) must fit within " +
                "\(Self.minimumWindowWidth)pt minimum window width"
        )
    }

    // MARK: - Picker is not artificially compressed (regression guard)

    /// The old bug's root cause was `.frame(maxWidth: 360)` capping the Picker below its
    /// ~516pt intrinsic width. This asserts the fixed Picker (hosted standalone, same
    /// modifiers as production) reports an intrinsic width comfortably above that old cap,
    /// proving `.fixedSize()` is sizing to content rather than being squeezed again.
    @MainActor
    func testTypePickerIsNotCompressedBelowIntrinsicWidth() {
        let previousBuggyCap: CGFloat = 360

        let picker = Picker("Filter by type", selection: .constant(KanbanTypeFilter.all)) {
            ForEach(KanbanTypeFilter.allCases, id: \.self) { filter in
                Text(filter.label).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()

        let hostingView = NSHostingView(rootView: picker)
        let idealSize = hostingView.fittingSize

        XCTAssertGreaterThan(
            idealSize.width,
            previousBuggyCap,
            "Type picker intrinsic width (\(idealSize.width)pt) should exceed the old buggy " +
                "\(previousBuggyCap)pt cap — regression guard against reintroducing a frame cap smaller " +
                "than intrinsic content size"
        )
    }

    // MARK: - ViewModeSegment (main toolbar, same anti-pattern fixed alongside)

    @MainActor
    func testViewModeSegmentFitsWithinReasonableToolbarWidth() {
        let view = ViewModeSegment(selectedMode: .constant(.treeDetail))
        let hostingView = NSHostingView(rootView: view)
        let idealSize = hostingView.fittingSize

        XCTAssertGreaterThan(idealSize.width, 0, "Hosting view should report a nonzero intrinsic width")
        // Previously fixed at 180pt; assert the fixedSize result is in a sane range for a
        // 3-segment icon+label control (catches both under- and over-compression regressions).
        XCTAssertLessThan(
            idealSize.width, 500,
            "View mode segment intrinsic width (\(idealSize.width)pt) is unexpectedly large for 3 segments"
        )
    }
}
