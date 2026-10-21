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

		XCTAssertEqual(TestingURLProtocol.requestCount(forURLContaining: Self.saveURL, httpMethod: HTTPMethod.post), 1)
		let unreadArticleIDs = await account.fetchUnreadArticleIDsAsync()
		XCTAssertFalse(unreadArticleIDs.contains("5001"))
	}

	func testSavingSeveralArticlesPostsOncePerArticle() async throws {
		let account = await makeMinifluxAccount(unreadArticleIDs: ["5001", "5002", "5003"])
		defer { TestAccountManager.shared.deleteAccount(account) }
		TestingURLProtocol.setResponse(.init(statusCode: 202), forURLContaining: "/save", httpMethod: HTTPMethod.post)

		try await account.saveArticlesForLater(articleIDs: ["5001", "5002", "5003"], markAsRead: false)

		XCTAssertEqual(TestingURLProtocol.requestCount(forURLContaining: "/save", httpMethod: HTTPMethod.post), 3)
		for entryID in ["5001", "5002", "5003"] {
			XCTAssertEqual(TestingURLProtocol.requestCount(forURLContaining: "/v1/entries/\(entryID)/save", httpMethod: HTTPMethod.post), 1, "Entry \(entryID)")
		}
	}

	func testNonNumericArticleIDThrowsWithoutSendingOrMarkingRead() async {
		let account = await makeMinifluxAccount(unreadArticleIDs: ["5001", "not-an-entry"])
		defer { TestAccountManager.shared.deleteAccount(account) }

		do {
			try await account.saveArticlesForLater(articleIDs: ["5001", "not-an-entry"], markAsRead: true)
			XCTFail("Expected an invalid parameter error")
		} catch AccountError.invalidParameter {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}

		XCTAssertEqual(TestingURLProtocol.requestCount(forURLContaining: "/save"), 0)
		let unreadArticleIDs = await account.fetchUnreadArticleIDsAsync()
		XCTAssertTrue(unreadArticleIDs.contains("5001"))
		XCTAssertTrue(unreadArticleIDs.contains("not-an-entry"))
	}

	/// Marking more than the status batch threshold read sends statuses right away;
	/// a failing status send must not turn the completed save into a failure.
	func testMarkReadFailureAfterSuccessfulSaveStillSucceeds() async throws {
		let articleIDs = Set((6001...6101).map { String($0) })
		let account = await makeMinifluxAccount(unreadArticleIDs: articleIDs)
		defer { TestAccountManager.shared.deleteAccount(account) }
		TestingURLProtocol.setResponse(.init(statusCode: 202), forURLContaining: "/save", httpMethod: HTTPMethod.post)
		TestingURLProtocol.setResponse(.init(statusCode: 500), forURLContaining: "/v1/entries", httpMethod: HTTPMethod.put)

		try await account.saveArticlesForLater(articleIDs: articleIDs, markAsRead: true)

		XCTAssertEqual(TestingURLProtocol.requestCount(forURLContaining: "/save", httpMethod: HTTPMethod.post), articleIDs.count)
		XCTAssertGreaterThan(TestingURLProtocol.requestCount(forURLContaining: "/v1/entries", httpMethod: HTTPMethod.put), 0, "The status send should have been attempted and failed")
		let unreadArticleIDs = await account.fetchUnreadArticleIDsAsync()
		XCTAssertTrue(unreadArticleIDs.isDisjoint(with: articleIDs))
	}

	func testServerErrorMessageIsSurfacedWhenSaveIsRejected() async {
		let account = await makeMinifluxAccountWithUnreadArticle()
		defer { TestAccountManager.shared.deleteAccount(account) }
		let body = Data(#"{"error_message":"server says no"}"#.utf8)
		TestingURLProtocol.setResponse(.init(statusCode: 400, data: body), forURLContaining: "/v1/entries/5001/save", httpMethod: HTTPMethod.post)

		do {
			try await account.saveArticlesForLater(articleIDs: ["5001"], markAsRead: true)
			XCTFail("Expected the save to fail")
		} catch MinifluxError.saveForLaterFailed(let message) {
			XCTAssertEqual(message, "server says no")
		} catch {
			XCTFail("Unexpected error: \(error)")
		}

		let unreadArticleIDs = await account.fetchUnreadArticleIDsAsync()
		XCTAssertTrue(unreadArticleIDs.contains("5001"))
	}

	func testUnauthorizedSaveSurfacesCredentialsErrorAndLeavesArticleUnread() async {
		await assertSaveFailureSurfacesCredentialsError(statusCode: HTTPResponseCode.unauthorized)
	}

	func testForbiddenSaveSurfacesCredentialsErrorAndLeavesArticleUnread() async {
		await assertSaveFailureSurfacesCredentialsError(statusCode: HTTPResponseCode.forbidden)
	}

	func testFailedSaveSurfacesSaveErrorAndNeverMarksArticleRead() async {
		let account = await makeMinifluxAccountWithUnreadArticle()
		defer { TestAccountManager.shared.deleteAccount(account) }
		TestingURLProtocol.setResponse(.init(statusCode: 500), forURLContaining: "/v1/entries/5001/save", httpMethod: HTTPMethod.post)

		do {
			try await account.saveArticlesForLater(articleIDs: ["5001"], markAsRead: true)
			XCTFail("Expected the save to fail")
		} catch {
			XCTAssertFalse(error is AccountError, "A save failure must not use the sync error wrapper")
			XCTAssertEqual(error.localizedDescription, "The article couldn’t be saved for later. HTTP 500: internal server error")
			XCTAssertFalse(error.localizedDescription.contains("syncing"))
			guard case MinifluxError.saveForLaterRequestFailed(let underlyingError) = error, case WebserviceError.httpError(let status, _) = underlyingError else {
				XCTFail("Expected a save-for-later HTTP error, got \(error)")
				return
			}
			XCTAssertEqual(status, 500)
		}

		XCTAssertEqual(TestingURLProtocol.requestCount(forURLContaining: Self.saveURL, httpMethod: HTTPMethod.post), 1)
		let unreadArticleIDs = await account.fetchUnreadArticleIDsAsync()
		XCTAssertTrue(unreadArticleIDs.contains("5001"))
	}

	func testMissingServerAddressThrowsWithoutSendingOrMarkingRead() async {
		let account = TestAccountManager.shared.createAccount(type: .miniflux)
		defer { TestAccountManager.shared.deleteAccount(account) }
		await account.markAsUnreadAsync(articleIDs: ["5001"])
		TestingURLProtocol.setResponse(.init(statusCode: 202), forURLContaining: "/save", httpMethod: HTTPMethod.post)

		do {
			try await account.saveArticlesForLater(articleIDs: ["5001"], markAsRead: true)
			XCTFail("Expected a missing server error")
		} catch MinifluxError.saveForLaterNoServer {
			XCTAssertEqual(MinifluxError.saveForLaterNoServer.localizedDescription, "The article couldn’t be saved for later because this account has no Miniflux server address. Re-enter the account’s credentials, or remove the account and add it again.")
		} catch {
			XCTFail("Unexpected error: \(error)")
		}

		XCTAssertEqual(TestingURLProtocol.requestCount(forURLContaining: "/save"), 0)
		let unreadArticleIDs = await account.fetchUnreadArticleIDsAsync()
		XCTAssertTrue(unreadArticleIDs.contains("5001"))
	}
}

private extension MinifluxSaveForLaterTests {

	func assertSaveFailureSurfacesCredentialsError(statusCode: Int) async {
		let account = await makeMinifluxAccountWithUnreadArticle()
		defer { TestAccountManager.shared.deleteAccount(account) }
		let body = Data(#"{"error_message":"credentials rejected"}"#.utf8)
		TestingURLProtocol.setResponse(.init(statusCode: statusCode, data: body), forURLContaining: "/v1/entries/5001/save", httpMethod: HTTPMethod.post)

		do {
			try await account.saveArticlesForLater(articleIDs: ["5001"], markAsRead: true)
			XCTFail("Expected the save to fail")
		} catch let error as AccountError {
			XCTAssertTrue(error.isCredentialsError)
			XCTAssertEqual(error.errorDescription, "Your “\(account.nameForDisplay)” credentials are invalid or expired.")
			XCTAssertEqual(error.recoverySuggestion, "Please update your credentials for this account, or ensure that your account with this service is still valid.")
			guard case AccountError.wrappedError(let underlyingError, _, _, _) = error else {
				XCTFail("Expected a wrapped credentials error, got \(error)")
				return
			}
			guard case WebserviceError.httpError(let actualStatusCode, _) = underlyingError else {
				XCTFail("Expected a wrapped HTTP error, got \(underlyingError)")
				return
			}
			XCTAssertEqual(actualStatusCode, statusCode)
		} catch MinifluxError.saveForLaterFailed(let message) {
			XCTFail("Expected the credentials error, got saveForLaterFailed: \(message)")
		} catch {
			XCTFail("Unexpected error: \(error)")
		}

		let unreadArticleIDs = await account.fetchUnreadArticleIDsAsync()
		XCTAssertTrue(unreadArticleIDs.contains("5001"))
	}

	func makeMinifluxAccountWithUnreadArticle() async -> Account {
		await makeMinifluxAccount(unreadArticleIDs: ["5001"])
	}

	func makeMinifluxAccount(unreadArticleIDs: Set<String>) async -> Account {
		let account = TestAccountManager.shared.createAccount(type: .miniflux)
		account.endpointURL = URL(string: "https://miniflux.test")
		await account.markAsUnreadAsync(articleIDs: unreadArticleIDs)
		return account
	}
}
