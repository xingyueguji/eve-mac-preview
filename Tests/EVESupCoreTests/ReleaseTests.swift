import XCTest
@testable import EVESupCore

final class ReleaseTests: XCTestCase {
    func testVersionParsingAndOrder() throws {
        let v = try XCTUnwrap(AppVersion("v0.2.1"))
        XCTAssertEqual(v.description, "0.2.1")
        XCTAssertTrue(try XCTUnwrap(AppVersion("0.1.1")) < v)
        XCTAssertTrue(v < (try XCTUnwrap(AppVersion("0.10.0"))))
        XCTAssertEqual(AppVersion("1.0"), AppVersion("1.0.0"))
        XCTAssertEqual(AppVersion("2.0.0-beta"), AppVersion("2.0.0"))
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion("1..2"))
    }

    func testDecodesGitHubReleaseAndFindsTheZip() throws {
        let json = """
        {
          "tag_name": "v0.2.1",
          "html_url": "https://github.com/xingyueguji/eve-mac-preview/releases/tag/v0.2.1",
          "body": "Notes",
          "draft": false,
          "assets": [
            {"name": "EVESup-0.2.1.dmg", "browser_download_url": "https://example.com/EVESup-0.2.1.dmg"},
            {"name": "EVESup-0.2.1.zip", "browser_download_url": "https://example.com/EVESup-0.2.1.zip"}
          ]
        }
        """
        let release = try JSONDecoder().decode(ReleaseInfo.self, from: Data(json.utf8))
        XCTAssertEqual(release.version, AppVersion("0.2.1"))
        XCTAssertEqual(release.updateArchive?.name, "EVESup-0.2.1.zip")
        XCTAssertEqual(release.updateArchive?.downloadURL.absoluteString, "https://example.com/EVESup-0.2.1.zip")
    }

    func testReleaseWithoutZipHasNoUpdateArchive() throws {
        let json = #"{"tag_name": "v0.1.1", "html_url": "https://example.com/r", "assets": [{"name": "EVESup-0.1.1.dmg", "browser_download_url": "https://example.com/d.dmg"}]}"#
        let release = try JSONDecoder().decode(ReleaseInfo.self, from: Data(json.utf8))
        XCTAssertNil(release.updateArchive)
        XCTAssertNil(release.notes)
    }
}
