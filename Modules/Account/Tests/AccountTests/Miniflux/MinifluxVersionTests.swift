//
//  MinifluxVersionTests.swift
//  AccountTests
//
//  Created by Dave Marquard on 7/8/26.
//  Copyright © 2026 Ranchero Software, LLC. All rights reserved.
//

import XCTest
import Secrets
@testable import Account

final class MinifluxVersionTests: XCTestCase {

	func testParsesSimpleVersionString() throws {
		let version = try XCTUnwrap(MinifluxVersion(string: "2.3.2"))
		XCTAssertGreaterThanOrEqual(version, MinifluxVersion(2, 3, 2))
		XCTAssertEqual(version, MinifluxVersion(2, 3, 2))
	}

	func testComparesNumericallyNotLexicographically() {
		XCTAssertGreaterThan(MinifluxVersion(2, 3, 10), MinifluxVersion(2, 3, 2))
	}

	func testOlderMinorVersionIsLess() {
		XCTAssertLessThan(MinifluxVersion(2, 2, 17), MinifluxVersion(2, 3, 2))
	}

	func testParsesNonNumericSuffixOnLastComponent() throws {
		let version = try XCTUnwrap(MinifluxVersion(string: "2.3.2-dev"))
		XCTAssertEqual(version, MinifluxVersion(2, 3, 2))
	}

	func testMissingComponentIsTreatedAsZero() throws {
		let version = try XCTUnwrap(MinifluxVersion(string: "2.3"))
		XCTAssertEqual(version, MinifluxVersion(2, 3, 0))
	}

	func testWhollyNonNumericStringFailsToParse() {
		XCTAssertNil(MinifluxVersion(string: "dev"))
	}

	func testNormalizesEndpointURLs() {
		let cases: [(input: String, expected: String?)] = [
			("miniflux.example.com", "https://miniflux.example.com"),
			("https://miniflux.example.com/", "https://miniflux.example.com"),
			("https://miniflux.example.com/v1/", "https://miniflux.example.com"),
			("https://miniflux.example.com/reader/v1///", "https://miniflux.example.com/reader"),
			("http://miniflux.example.com/reader", "http://miniflux.example.com/reader"),
			("ftp://miniflux.example.com", nil),
			("https://user:pass@miniflux.example.com", nil),
			("https://miniflux.example.com?token=secret", nil),
			("https:///v1", nil)
		]

		for testCase in cases {
			XCTAssertEqual(Miniflux.normalizedEndpointURL(from: testCase.input)?.absoluteString, testCase.expected, testCase.input)
		}
	}

	func testMinifluxIdentityCanOnlyStayOnSameServerAndUser() throws {
		let endpoint = try XCTUnwrap(URL(string: "https://miniflux.example.com"))
		let normalizedEndpoint = try XCTUnwrap(URL(string: "https://MINIFLUX.example.com/v1/"))
		let rootSlashEndpoint = try XCTUnwrap(URL(string: "https://miniflux.example.com/"))
		let otherEndpoint = try XCTUnwrap(URL(string: "https://other.example.com"))
		XCTAssertTrue(Miniflux.canReplaceIdentity(existingEndpoint: endpoint, existingUsername: "user", validatedEndpoint: normalizedEndpoint, validatedUsername: "user"))
		XCTAssertTrue(Miniflux.canReplaceIdentity(existingEndpoint: endpoint, existingUsername: "user", validatedEndpoint: rootSlashEndpoint, validatedUsername: "user"))
		XCTAssertFalse(Miniflux.canReplaceIdentity(existingEndpoint: endpoint, existingUsername: "user", validatedEndpoint: otherEndpoint, validatedUsername: "user"))
		XCTAssertFalse(Miniflux.canReplaceIdentity(existingEndpoint: endpoint, existingUsername: "user", validatedEndpoint: endpoint, validatedUsername: "other"))
		XCTAssertFalse(Miniflux.canReplaceIdentity(existingEndpoint: nil, existingUsername: nil, validatedEndpoint: endpoint, validatedUsername: "user"))
	}

	@MainActor func testMinifluxCredentialsUseFullEndpointKeychainIdentity() throws {
		let identifier = UUID().uuidString
		let username = "miniflux-\(identifier)"
		let first = TestAccountManager.shared.createAccount(type: .miniflux)
		let second = TestAccountManager.shared.createAccount(type: .miniflux)
		defer {
			TestAccountManager.shared.deleteAccount(first)
			TestAccountManager.shared.deleteAccount(second)
		}

		let firstEndpoint = try XCTUnwrap(Miniflux.normalizedEndpointURL(from: "https://miniflux-\(identifier).test/one"))
		let secondEndpoint = try XCTUnwrap(Miniflux.normalizedEndpointURL(from: "https://miniflux-\(identifier).test:8443/two"))
		try first.storeMinifluxCredentials(Credentials(type: .minifluxAPIToken, username: username, secret: "first-secret"), endpoint: firstEndpoint)
		try second.storeMinifluxCredentials(Credentials(type: .minifluxAPIToken, username: username, secret: "second-secret"), endpoint: secondEndpoint)

		XCTAssertEqual(try first.retrieveCredentials(type: .minifluxAPIToken)?.secret, "first-secret")
		XCTAssertEqual(try second.retrieveCredentials(type: .minifluxAPIToken)?.secret, "second-secret")
	}
}
