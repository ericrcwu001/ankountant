import XCTest
import UIKit
@testable import AnkountantApp

final class CardWebViewTests: XCTestCase {
    // DEFERRED: fork's testMediaBaseTagPointsAtMediaRoot tests CardWebView.mediaBaseTag(for: URL)
    // using file:// URLs. Our codebase uses CardAssetPath.mediaBaseTag() with the ankountant-asset://
    // custom URL scheme (no file-path parameter). The method doesn't exist in our CardWebView.
    // See AnkountantCardWebTests/CardAssetPathTests.swift for coverage of our mediaBaseTag() variant.

    // DEFERRED: fork's testCardWrapperFileUsesHiddenFileInMediaRoot tests
    // CardWebView.cardWrapperFileURL(in:), which doesn't exist in our codebase.
    // Our architecture loads HTML via webView.loadHTMLString(_:baseURL:) with a custom
    // URL scheme handler (CardAssetScheme) rather than writing an on-disk wrapper file.

    @MainActor
    func testParseCSSColorAcceptsValidHexAndRGB() {
        assertColor(CardWebViewCoordinator.parseCSSColor("#0f8"), red: 0, green: 1, blue: 0.533, alpha: 1)
        assertColor(CardWebViewCoordinator.parseCSSColor("#33669980"), red: 0.2, green: 0.4, blue: 0.6, alpha: 0.502)
        assertColor(CardWebViewCoordinator.parseCSSColor("rgba(255, 128, 0, .5)"), red: 1, green: 0.502, blue: 0, alpha: 0.5)
    }

    @MainActor
    func testParseCSSColorRejectsMalformedValues() {
        XCTAssertNil(CardWebViewCoordinator.parseCSSColor("#ggg"))
        XCTAssertNil(CardWebViewCoordinator.parseCSSColor("#12"))
        XCTAssertNil(CardWebViewCoordinator.parseCSSColor("rgba(10, 20, 30, 1.2.3)"))
        XCTAssertNil(CardWebViewCoordinator.parseCSSColor("rgb(10, 20, 30) trailing"))
    }

    @MainActor
    func testExpandSoundTagsBuildsAudioElement() {
        let html = CardWebView.expandSoundTags(
            "<p>[sound:clip one.mp3]</p>",
            isDarkMode: false,
            showReplayButtons: false
        )

        XCTAssertTrue(html.contains("<audio"))
        XCTAssertTrue(html.contains("src=\"clip%20one.mp3\""))
        XCTAssertFalse(html.contains("[sound:"))
    }

    @MainActor
    func testExpandTTSTagsBuildsEscapedReplayButton() {
        let html = CardWebView.expandTTSTags(
            in: #"[anki:tts lang=ja_JP voices=Kyoko speed=1.25]5 < 6 & "quote"[/anki:tts]"#,
            isDarkMode: false,
            showReplayButtons: true
        )

        XCTAssertTrue(html.contains("data-tts-text=\"5 &lt; 6 &amp; &quot;quote&quot;\""))
        XCTAssertTrue(html.contains("data-tts-lang=\"ja_JP\""))
        XCTAssertTrue(html.contains("data-tts-voices=\"Kyoko\""))
        XCTAssertTrue(html.contains("data-tts-speed=\"1.25\""))
        XCTAssertFalse(html.contains("[anki:tts"))
    }

    @MainActor
    func testDeferCardScriptsDisablesExecutionAndPreservesAttributes() {
        let html = CardWebView.deferCardScripts(
            in: #"<script type="text/javascript" async data-card="front">run()</script>"#
        )

        XCTAssertTrue(html.contains(#"type="application/x-ankountant-card-script""#))
        XCTAssertTrue(html.contains(#"data-ankountant-card-script="1""#))
        XCTAssertTrue(html.contains(#"async data-card="front""#))
        XCTAssertFalse(html.contains(#"type="text/javascript""#))
    }

    @MainActor
    func testParseTTSAttributesLowercasesKeys() {
        XCTAssertEqual(
            CardWebView.parseTTSAttributes("LANG=ja_JP voices=Kyoko speed=1.25"),
            ["lang": "ja_JP", "voices": "Kyoko", "speed": "1.25"]
        )
    }

    private func assertColor(
        _ color: UIColor?,
        red expectedRed: CGFloat,
        green expectedGreen: CGFloat,
        blue expectedBlue: CGFloat,
        alpha expectedAlpha: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let color else {
            XCTFail("Expected color", file: file, line: line)
            return
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            XCTFail("Expected RGB color", file: file, line: line)
            return
        }

        XCTAssertEqual(red, expectedRed, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(green, expectedGreen, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(blue, expectedBlue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(alpha, expectedAlpha, accuracy: 0.001, file: file, line: line)
    }
}
