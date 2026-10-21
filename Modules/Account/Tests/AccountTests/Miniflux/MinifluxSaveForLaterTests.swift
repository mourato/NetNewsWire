//
//  MinifluxSaveForLaterTests.swift
//  AccountTests
//
//  Copyright © 2026 Ranchero Software, LLC. All rights reserved.
//

import XCTest
import RSWeb
import Secrets
@testable import Account

@MainActor final class MinifluxSaveForLaterTests: XCTestCase {

	private static let saveURL = "https://miniflux.test/v1/entries/5001/save"

	override func setUp() {
		TestingURLProtocol.reset()
	}

	func testSaveEntryPostsToSaveEndpointWithoutTouchingBookmark() async throws {
		let accountSettings = AccountSettings(accountID: UUID().uuidString, dataFolder: NSTemporaryDirectory())
		accountSettings.endpointURL = URL(string: "https://miniflux.test")
		let caller = MinifluxAPICaller()
		caller.credentials = Credentials(type: .minifluxAPIToken, username: "", secret: "token")
		caller.accountSettings = accountSettings
		TestingURLProtocol.setResponse(.init(statusCode: 202), forURLContaining: "/v1/entries/5001/save", httpMethod: HTTPMethod.post)

		try await caller.saveEntry(entryID: 5001)

		XCTAssertEqual(TestingURLProtocol.requestCount(forURLContaining: Self.saveURL, httpMethod: HTTPMethod.post), 1)
		XCTAssertEqual(TestingURLProtocol.requestCount(forURLContaining: "/bookmark"), 0)
	}

	func testOnlyMinifluxSupportsSaveForLater() {
		let otherTypes: [AccountType] = [.onMyMac, .feedly, .feedbin, .newsBlur, .freshRSS, .inoreader, .bazQux, .theOldReader]
		for type in otherTypes {
			let account = TestAccountManager.shared.createAccount(type: type)
			defer { TestAccountManager.shared.deleteAccount(account) }
			XCTAssertFalse(account.supportsSaveForLater, "\(type) should not support Save for Later")
		}

		let miniflux = TestAccountManager.shared.createAccount(type: .miniflux)
		defer { TestAccountManager.shared.deleteAccount(miniflux) }
		XCTAssertTrue(miniflux.supportsSaveForLater)
	}

	func testUnsupportedAccountThrowsWithoutSending() async {
		let account = TestAccountManager.shared.createAccount(type: .onMyMac)
		defer { TestAccountManager.shared.deleteAccount(account) }

		do {
			try await account.saveArticlesForLater(articleIDs: ["5001"], markAsRead: true)
			XCTFail("Expected an unsupported error")
		} catch AccountError.saveForLaterNotSupported {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}
		XCTAssertEqual(TestingURLProtocol.requestCount(forURLContaining: "/save"), 0)
	}

	func testSuccessfulSaveLeavesArticleUnreadWhenNotMarkingRead() async throws {
		let account = await makeMinifluxAccountWithUnreadArticle()
		defer { TestAccountManager.shared.deleteAccount(account) }
		TestingURLProtocol.setResponse(.init(statusCode: 202), forURLContaining: "/v1/entries/5001/save", httpMethod: HTTPMethod.post)

		try await account.saveArticlesForLater(articleIDs: ["5001"], markAsRead: false)

		XCTAssertEqual(TestingURLProtocol.requestCount(forURLContaining: Self.saveURL, httpMethod: HTTPMethod.post), 1)
		let unreadArticleIDs = await account.fetchUnreadArticleIDsAsync()
		XCTAssertTrue(unreadArticleIDs.contains("5001"))
	}

	func testSuccessfulSaveMarksArticleReadWhenMarkingRead() async throws {
		let account = await makeMinifluxAccountWithUnreadArticle()
		defer { TestAccountManager.shared.deleteAccount(account) }
		TestingURLProtocol.setResponse(.init(statusCode: 202), forURLContaining: "/v1/entries/5001/save", httpMethod: HTTPMethod.post)

		try await account.saveArticlesForLater(articleIDs: ["5001"], markAsRead: true)

		let unreadArticleIDs = await account.fetchUnreadArticleIDsAsync()
		XCTAssertFalse(unreadArticleIDs.contains("5001"))
	}

	func testFailedSaveNeverMarksArticleRead() async {
		let account = await makeMinifluxAccountWithUnreadArticle()
		defer { TestAccountManager.shared.deleteAccount(account) }
		TestingURLProtocol.setResponse(.init(statusCode: 500), forURLContaining: "/v1/entries/5001/save", httpMethod: HTTPMethod.post)

		do {
			try await account.saveArticlesForLater(articleIDs: ["5001"], markAsRead: true)
			XCTFail("Expected the save to fail")
		} catch {
			guard case AccountError.wrappedError(let underlyingError, _, _, _) = error, case WebserviceError.httpError(let status, _) = underlyingError else {
				XCTFail("Expected a wrapped HTTP error, got \(error)")
				return
			}
			XCTAssertEqual(status, 500)
		}

		let unreadArticleIDs = await account.fetchUnreadArticleIDsAsync()
		XCTAssertTrue(unreadArticleIDs.contains("5001"))
	}
}

private extension MinifluxSaveForLaterTests {

	func makeMinifluxAccountWithUnreadArticle() async -> Account {
		let account = TestAccountManager.shared.createAccount(type: .miniflux)
		account.endpointURL = URL(string: "https://miniflux.test")
		await account.markAsUnreadAsync(articleIDs: ["5001"])
		return account
	}
}
