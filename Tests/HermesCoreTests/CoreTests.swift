import XCTest
@testable import HermesCore
final class CoreTests: XCTestCase {
    func testAutomaticPrefersDesktop() { XCTAssertEqual(LaunchResolver.resolve(.automatic, desktop: true, cli: true), .desktop) }
    func testAutomaticUsesCLI() { XCTAssertEqual(LaunchResolver.resolve(.automatic, desktop: false, cli: true), .cli) }
    func testExplicitNeverFallsBack() { XCTAssertEqual(LaunchResolver.resolve(.desktop, desktop: false, cli: true), .setup) }
    func testMissingGoesToSetup() { XCTAssertEqual(LaunchResolver.resolve(.automatic, desktop: false, cli: false), .setup) }
    func testDiscordURL() throws { XCTAssertEqual(try DestinationValidator.validate("https://discord.com/channels/@me/123", kind: .discord).path, "/channels/@me/123") }
    func testRejectsLookalike() { XCTAssertThrowsError(try DestinationValidator.validate("https://discord.com.evil.org/channels/a/b", kind: .discord)) }
    func testRejectsCredentials() { XCTAssertThrowsError(try DestinationValidator.validate("https://user:secret@example.com", kind: .dashboard)) }
    func testRejectsHTTP() { XCTAssertThrowsError(try DestinationValidator.validate("http://example.com", kind: .dashboard)) }
    func testTelegram() throws { XCTAssertEqual(try DestinationValidator.validate("https://t.me/hermes_bot", kind: .telegram).host, "t.me") }
    func testRejectsEmptyTelegramPath() { XCTAssertThrowsError(try DestinationValidator.validate("https://t.me/", kind: .telegram)) }
    func testStableIdentityRoundTrip() throws {
        let item = Destination(name: "Personal", kind: .discord, url: URL(string: "https://discord.com/channels/@me/123")!)
        XCTAssertEqual(try JSONDecoder().decode(Destination.self, from: JSONEncoder().encode(item)), item)
    }
}
