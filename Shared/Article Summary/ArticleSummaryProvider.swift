//
//  ArticleSummaryProvider.swift
//  NetNewsWire
//
//  Created by AI summary feature, 10/21/26.
//

import Foundation

/// Which summarizer the user selected in preferences.
enum ArticleSummaryProvider: Int, CaseIterable, Sendable {

	case appleLocal = 0
	case openAICompatible = 1

	var name: String {
		switch self {
		case .appleLocal:
			return NSLocalizedString("Apple Intelligence (Local)", comment: "Summaries provider")
		case .openAICompatible:
			return NSLocalizedString("OpenAI-compatible API", comment: "Summaries provider")
		}
	}

	var isOpenAICompatible: Bool {
		self == .openAICompatible
	}
}

/// Locally-owned, non-secret settings for the summary feature.
@MainActor struct ArticleSummarySettings {

	let provider: ArticleSummaryProvider
	let endpoint: String?
	let model: String?
}
