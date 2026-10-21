//
//  MinifluxError.swift
//  Account
//
//  Created by Dave Marquard on 7/7/26.
//  Copyright © 2026 Ranchero Software, LLC. All rights reserved.
//

import Foundation

// Miniflux error responses look like: {"error_message": "This feed already exists (feed_id: 123)"}
struct MinifluxErrorResponse: Decodable, Sendable {
	let errorMessage: String

	enum CodingKeys: String, CodingKey {
		case errorMessage = "error_message"
	}
}

enum MinifluxCredentialsError: LocalizedError {
	case identityChange

	var errorDescription: String? {
		NSLocalizedString("To change Miniflux server or user, create a new account.", comment: "Miniflux identity change")
	}
}

enum MinifluxError: LocalizedError {
	case serverVersionTooOld(foundVersion: String?)
	case serverError(message: String)
	case saveForLaterFailed(message: String)
	case saveForLaterNoServer
	case saveForLaterRequestFailed(error: Error)

	var errorDescription: String? {
		switch self {
		case .serverVersionTooOld(let foundVersion):
			guard let foundVersion else {
				return NSLocalizedString("NetNewsWire requires Miniflux 2.0.49 or later.", comment: "Server version too old")
			}
			let localizedText = NSLocalizedString("This Miniflux server is version %@, but NetNewsWire requires Miniflux 2.0.49 or later.", comment: "Server version too old")
			return NSString.localizedStringWithFormat(localizedText as NSString, foundVersion) as String
		case .serverError(let message):
			let localizedText = NSLocalizedString("The Miniflux server reported an error: %@", comment: "Server error")
			return NSString.localizedStringWithFormat(localizedText as NSString, message) as String
		case .saveForLaterFailed(let message):
			let localizedText = NSLocalizedString("The article couldn’t be saved for later. The Miniflux server reported: %@", comment: "Save for Later failed — server error message")
			return NSString.localizedStringWithFormat(localizedText as NSString, message) as String
		case .saveForLaterNoServer:
			return NSLocalizedString("The article couldn’t be saved for later because this account has no Miniflux server address. Re-enter the account’s credentials, or remove the account and add it again.", comment: "Save for Later failed — the account has no server address")
		case .saveForLaterRequestFailed(let error):
			let localizedText = NSLocalizedString("The article couldn’t be saved for later. %@", comment: "Save for Later failed — underlying error description")
			return NSString.localizedStringWithFormat(localizedText as NSString, error.localizedDescription) as String
		}
	}
}
