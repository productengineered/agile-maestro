import XCTest
@testable import AgileMaestro

final class MarkdownSectionParserTests: XCTestCase {

    // MARK: - Happy-Path Tests

    func testExtractsSingleSection() {
        let markdown = """
        ## What
        Build the service layer.
        """
        let result = MarkdownSectionParser.extractSection(named: "What", from: markdown)
        XCTAssertEqual(result, "Build the service layer.")
    }

    func testExtractsFirstOfMultipleSections() {
        let markdown = """
        ## Intro
        Hello

        ## Detail
        World
        """
        let intro = MarkdownSectionParser.extractSection(named: "Intro", from: markdown)
        let detail = MarkdownSectionParser.extractSection(named: "Detail", from: markdown)

        XCTAssertEqual(intro, "Hello")
        XCTAssertEqual(detail, "World")
    }

    func testExtractsMultilineSectionBody() {
        let markdown = """
        ## Summary
        Line one.
        Line two.
        Line three.

        ## Next
        Done.
        """
        let result = MarkdownSectionParser.extractSection(named: "Summary", from: markdown)
        XCTAssertEqual(result, "Line one.\nLine two.\nLine three.")
    }

    func testTrimsLeadingAndTrailingWhitespace() {
        let markdown = "## Section\n\n  Content with surrounding whitespace.  \n\n## End\n"
        let result = MarkdownSectionParser.extractSection(named: "Section", from: markdown)
        XCTAssertEqual(result, "Content with surrounding whitespace.")
    }

    // MARK: - Missing / Edge Cases

    func testReturnsNilForMissingSection() {
        let markdown = "## Existing\nSome content."
        let result = MarkdownSectionParser.extractSection(named: "Missing", from: markdown)
        XCTAssertNil(result)
    }

    func testEmptyInputReturnsNil() {
        let result = MarkdownSectionParser.extractSection(named: "Anything", from: "")
        XCTAssertNil(result)
    }

    func testNoHeadersReturnsNil() {
        let markdown = "This is plain text with no level-2 headers at all."
        let result = MarkdownSectionParser.extractSection(named: "Plain", from: markdown)
        XCTAssertNil(result)
    }

    func testLeadingContentBeforeFirstHeaderIsDiscarded() {
        let markdown = """
        preamble text that should be ignored
        ## A
        content A
        """
        let result = MarkdownSectionParser.extractSection(named: "A", from: markdown)
        XCTAssertEqual(result, "content A")
    }

    func testSectionWithEmptyBodyReturnsNil() {
        let markdown = """
        ## Empty

        ## Next
        content
        """
        let result = MarkdownSectionParser.extractSection(named: "Empty", from: markdown)
        XCTAssertNil(result, "A section with only whitespace body should return nil")
    }

    func testCaseSensitiveHeadingMatch() {
        let markdown = "## what\nlower-case content."
        let wrongCase = MarkdownSectionParser.extractSection(named: "What", from: markdown)
        let correctCase = MarkdownSectionParser.extractSection(named: "what", from: markdown)

        XCTAssertNil(wrongCase, "Section names are case-sensitive")
        XCTAssertEqual(correctCase, "lower-case content.")
    }

    func testPartialHeadingDoesNotMatch() {
        let markdown = "## Overview Section\nSome content."
        // "Overview" alone should not match "## Overview Section"
        let result = MarkdownSectionParser.extractSection(named: "Overview", from: markdown)
        XCTAssertNil(result)
    }
}
