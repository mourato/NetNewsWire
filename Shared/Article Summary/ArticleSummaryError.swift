//
//  ArticleSummaryError.swift
//  NetNewsWire
//
//  Created by AI summary feature, 10/21/26.
//

import Foundation

/// Errors shown in the summary panel. Never carries the article text or the API key.
enum ArticleSummaryError: Error, LocalizedError, Equatable {

	/// The local Apple model is not available on this OS or device.
	case localModelUnavailable(reason: String)
	/// Remote provider is not configured well enough to attempt a request.
	case missingConfiguration(String)
	/// Endpoint failed validation (scheme/host) before sending anything.
	case invalidEndpoint(String)
	/// Keychain access failed.
	case credential(String)
	/// Network failure (connection, timeout).
	case network(String)
	/// HTTP status on the remote API. Carries the status code only.
	case http(status: Int)
	/// Response body wasn't understood.
	case malformedResponse

	var errorDescription: String? {
		NSLocalizedString("Article Summarization Failed", comment: "Summary error title") + "\n" + detailText
	}

	private var detailText: String {
		switch self {
		case .localModelUnavailable(let reason):
			return reason
		case .missingConfiguration(let detail):
			return detail
		case .invalidEndpoint:
			return NSLocalizedString("The API endpoint is invalid. Use a base URL starting with https:// — http:// is allowed only for local addresses.", comment: "Summary endpoint error")
		case .credential:
			return NSLocalizedString("The API key could not be read. Re-enter it in Settings.", comment: "Summary credential error")
		case .network:
			return NSLocalizedString("The request could not reach the server. Check your connection and try again.", comment: "Summary network error")
		case .http(let status):
			switch status {
			case 401, 403:
				return String(format: NSLocalizedString("The server rejected the API key (HTTP %@). Check the key in Settings.", comment: "Summary auth error"), String(status))
			case 404:
				return NSLocalizedString("The server returned 404. Check the endpoint base URL and the model name.", comment: "Summary not-found error")
			case 429:
				return NSLocalizedString("The server returned 429 (rate limit). Try again after a pause.", comment: "Summary rate-limit error")
			default:
				return String(format: NSLocalizedString("The server returned HTTP %@.", comment: "Summary generic HTTP error"), String(status))
			}
		case .malformedResponse:
			return NSLocalizedString("The server response was not understood.", comment: "Summary malformed response error")
		}
	}
}
