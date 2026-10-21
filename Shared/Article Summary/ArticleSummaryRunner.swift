//
//  ArticleSummaryRunner.swift
//  NetNewsWire
//
//  Created by AI summary feature, 10/21/26.
//

import Foundation
import Articles
import os

/// One article's summary, built from the article model only — never stored or synced.
@MainActor struct ArticleSummaryInput {

	let articleID: String
	let title: String
	let text: String

	init(articleID: String, title: String, text: String) {
		self.articleID = articleID
		self.title = ArticleSummaryInput.prepareTitle(title)
		self.text = ArticleSummaryInput.prepareText(text)
	}

	/// Builds the input from an article: contentText, else summary, else plain text of contentHTML.
	init(article: Article) {
		self.articleID = article.articleID
		self.title = article.title ?? ""

		let rawText: String
		if let contentText = article.contentText, !contentText.isEmpty {
			rawText = contentText
		} else if let summary = article.summary, !summary.isEmpty {
			rawText = summary
		} else if let contentHTML = article.contentHTML, !contentHTML.isEmpty {
			rawText = ArticleSummaryInput.plainText(fromHTML: contentHTML)
		} else {
			rawText = ""
		}
		self.text = ArticleSummaryInput.prepareText(rawText)
	}

	var isEmpty: Bool {
		text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.isEmpty
	}

	// MARK: - Private

	private static func prepareTitle(_ title: String) -> String {
		title.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private static func prepareText(_ text: String) -> String {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		let maximumLength = 20_000
		guard trimmed.count > maximumLength else {
			return trimmed
		}
		// Bound the request payload without logging or retaining more content than needed.
		return String(trimmed.prefix(maximumLength))
	}

	/// Lightweight tag stripping for the rare articles that only carry contentHTML.
	/// Not a full parse — enough to give the model readable text.
	static func plainText(fromHTML html: String) -> String {
		var working = html
		for tag in ["script", "style", "head"] {
			let pattern = "(?is)<" + tag + "[^>]*>.*?</" + tag + "\\s*>"
			let regex = try? NSRegularExpression(pattern: pattern)
			if let regex {
				let fullRange = NSRange(location: 0, length: working.utf16.count)
				working = regex.stringByReplacingMatches(in: working, range: fullRange, withTemplate: " ")
			}
		}
		let tagPattern = try? NSRegularExpression(pattern: "(?U)<[^>]+>|&[a-z]+;|&#\\d+;")
		if let tagPattern {
			let fullRange = NSRange(location: 0, length: working.utf16.count)
			working = tagPattern.stringByReplacingMatches(in: working, range: fullRange, withTemplate: " ")
		}
		let whitespacePattern = try? NSRegularExpression(pattern: "\\s+")
		if let whitespacePattern {
			let fullRange = NSRange(location: 0, length: working.utf16.count)
			working = whitespacePattern.stringByReplacingMatches(in: working, range: fullRange, withTemplate: " ")
		}
		return working.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

/// In-memory display state of one article's summary. Never persisted.
@MainActor enum ArticleSummaryDisplayState: Equatable {

	case idle
	case loading
	case finished(text: String, providerName: String)
	case failed(errorDescription: String)
}

/// Runs exactly one summary generation per displayed article.
///
/// - The request configuration and the article text are snapshotted before the first
///   await, so later preference changes never affect an in-flight request.
/// - The result is discarded unless the displayed article identity still matches and
///   the task was not cancelled.
/// - Callers clear the summary on article change/close via `cancel()`.
@MainActor final class ArticleSummaryRunner {

	// Each request carries an ownership token: a stale or cancelled completion may
	// neither publish a summary nor clear a newer request's task handle.
	private struct RunningTask {
		let token: UUID
		let handle: Task<Void, Never>
	}

	private var runningTask: RunningTask?
	private var runningArticleID: String?

	// MARK: - API

	var displayState: ArticleSummaryDisplayState = .idle {
		didSet {
			onStateChange?(displayState)
		}
	}

	var onStateChange: ((ArticleSummaryDisplayState) -> Void)?

	func summarize(input: ArticleSummaryInput, settings: ArticleSummarySettings) {
		// One active request per displayed article.
		guard runningTask == nil else {
			return
		}
		guard !input.isEmpty else {
			displayState = .failed(errorDescription: NSLocalizedString("This article has no text to summarize.", comment: "Summary empty article"))
			return
		}

		// Snapshot everything the request needs before the first await.
		let snapshotArticleID = input.articleID
		let snapshotSettings = settings
		let token = UUID()
		runningArticleID = snapshotArticleID
		let requestTask = Task { [weak self] in
			let result = await ArticleSummaryRunner.results(input: input, settings: snapshotSettings)
			guard let self else {
				return
			}
			// An old completion that lost ownership (cancelled, replaced, or cleared)
			// leaves the slot and any newer request untouched.
			guard let current = self.runningTask, current.token == token else {
				return
			}
			self.runningTask = nil
			// Stale or cancelled results publish nothing.
			guard !Task.isCancelled, self.runningArticleID == snapshotArticleID else {
				return
			}
			switch result {
			case .success(let summary):
				self.displayState = .finished(text: summary, providerName: snapshotSettings.provider.name)
			case .failure(let error) where error is CancellationError:
				// Cancelled work leaves no summary behind; a retry requires a new tap.
				return
			case .failure(let error):
				self.displayState = .failed(errorDescription: error.localizedDescription)
			}
		}
		runningTask = RunningTask(token: token, handle: requestTask)
		displayState = .loading
	}

	func cancel() {
		runningTask?.handle.cancel()
		runningTask = nil
		runningArticleID = nil
		displayState = .idle
	}

	// MARK: - Private

	private static func results(input: ArticleSummaryInput, settings: ArticleSummarySettings) async -> Result<String, Error> {
		do {
			let summary: String
			switch settings.provider {
			case .appleLocal:
				summary = try await AppleLocalSummarizer.summarize(title: input.title, text: input.text)
			case .openAICompatible:
				let client = try OpenAICompatibleSummaryClient.validate(endpoint: settings.endpoint, model: settings.model)
				summary = try await client.summarize(title: input.title, text: input.text)
			}
			return .success(summary)
		} catch {
			return .failure(error)
		}
	}
}
