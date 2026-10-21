//
//  AppleLocalSummarizer.swift
//  NetNewsWire
//
//  Created by AI summary feature, 10/21/26.
//

import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Wrapper for the Apple on-device Foundation Models summarizer.
///
/// Compiled only when the SDK ships FoundationModels; every entry point is
/// additionally gated on iOS 26 / macOS 26 and on real device/model availability.
/// There is no automatic fallback to the remote provider.
enum AppleLocalSummarizer {

	private static let logger = Logger(subsystem: Logger.nnwSubsystem, category: "AppleLocalSummarizer")

	/// A user-facing description of why the local model is unavailable, or nil when usable.
	static func unavailabilityReason() -> String? {
		#if canImport(FoundationModels)
		guard #available(iOS 26.0, macOS 26.0, *) else {
			return NSLocalizedString("Requires iOS or macOS 26.", comment: "Summaries local model unavailable")
		}
		return availabilityState()
		#else
		return NSLocalizedString("Requires iOS or macOS 26.", comment: "Summaries local model unavailable")
		#endif
	}

	/// Nil when the local model can run, or a localized reason why it cannot.
	static func summarize(title: String, text: String) async throws -> String {
		#if canImport(FoundationModels)
		guard #available(iOS 26.0, macOS 26.0, *) else {
			throw ArticleSummaryError.localModelUnavailable(reason: NSLocalizedString("Requires iOS or macOS 26.", comment: "Summaries local model unavailable"))
		}
		if let reason = availabilityState() {
			throw ArticleSummaryError.localModelUnavailable(reason: reason)
		}

		let instructions = NSLocalizedString("You summarize news articles. Reply in the same language as the article. Write 2-4 short sentences covering the main points. Plain text only.", comment: "Instruction for the article summarization model")
		let articleContent = title.isEmpty ? text : "Title: \(title)\n\n\(text)"

		do {
			let session = LanguageModelSession(instructions: instructions)
			let response = try await session.respond(to: articleContent)
			let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !content.isEmpty else {
				throw ArticleSummaryError.malformedResponse
			}
			return content
		} catch let error as ArticleSummaryError {
			throw error
		} catch {
			logger.debug("AppleLocalSummarizer: generation failed")
			throw ArticleSummaryError.malformedResponse
		}
		#else
		throw ArticleSummaryError.localModelUnavailable(reason: NSLocalizedString("Requires iOS or macOS 26.", comment: "Summaries local model unavailable"))
		#endif
	}

	// MARK: - Private

	#if canImport(FoundationModels)
	@available(iOS 26.0, macOS 26.0, *)
	private static func availabilityState() -> String? {
		let model = SystemLanguageModel.default
		switch model.availability {
		case .available:
			return nil
		case .unavailable(let reason):
			logger.debug("AppleLocalSummarizer: model unavailable")
			switch reason {
			case .deviceNotEligible:
				return NSLocalizedString("This device does not support Apple Intelligence.", comment: "Summaries local model unavailable")
			case .appleIntelligenceNotEnabled:
				return NSLocalizedString("Apple Intelligence is not enabled in system settings.", comment: "Summaries local model unavailable")
			case .modelNotReady:
				return NSLocalizedString("The on-device model is still downloading.", comment: "Summaries local model unavailable")
			@unknown default:
				return NSLocalizedString("The on-device model is not available.", comment: "Summaries local model unavailable")
			}
		@unknown default:
			logger.debug("AppleLocalSummarizer: unknown availability")
			return NSLocalizedString("The on-device model is not available.", comment: "Summaries local model unavailable")
		}
	}
	#endif
}
