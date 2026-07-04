//
//  AccessibilityIdentifiers.swift
//  Shared test-selector identifiers for XCUITest (agent UAT Tier 2).
//
//  NOTE: this is for TEST SELECTORS, not VoiceOver. Provide a VoiceOver
//  .accessibilityLabel separately where users need one. See
//  .claude/skills/tooling/accessibility-identifiers/SKILL.md.
//
//  Grown incrementally per screen as AXID-instrumented views are added.
//  When the first XCUITest that queries these ids is written, add this file
//  to the AgileMaestroUITests target membership as well (currently app-target
//  only — no UI tests reference these ids yet).
//

/// Namespace for stable, screen-prefixed accessibility identifiers used by
/// XCUITest to locate interactive elements. Never encode user-facing copy in
/// these strings — they must stay valid across label/localization changes.
enum AXID {

    // MARK: - Empty New-Tab State (SCR-EMPTY, AM-803-2)

    /// "Choose a Product" CTA on a fresh/empty tab and its M-800-1 popover.
    enum EmptyTab {
        static let chooseProductButton = "emptyTab.chooseProductButton"
        static let newProductMenuItem = "emptyTab.newProductMenuItem"
        /// Dynamic row — key by the product's stable id, never array index.
        static func productRow(_ id: String) -> String { "emptyTab.productRow.\(id)" }
    }

    // MARK: - Product Chip Menu (toolbar, AM-803-2 additions)

    /// Toolbar product picker (`ProductChipMenu`) — existing switch-product
    /// rows plus the new "Open in New Tab" submenu (IS-TAB-OPEN-800-1).
    enum ProductChipMenu {
        static let openInNewTabMenu = "productChipMenu.openInNewTabMenu"
        static func productRow(_ id: String) -> String { "productChipMenu.productRow.\(id)" }
        static func openInNewTabRow(_ id: String) -> String { "productChipMenu.openInNewTabRow.\(id)" }
    }
}
