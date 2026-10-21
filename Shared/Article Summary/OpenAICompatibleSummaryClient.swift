//
//  OpenAICompatibleSummaryClient.swift
//  NetNewsWire
//
//  Created by AI summary feature, 10/21/26.
//

import Foundation
import os
import Secrets

/// Client for an OpenAI-compatible text generation API.
///
/// The endpoint string is treated as a base URL: `GET {base}/models` lists models
/// and `POST {base}/chat/completions` requests a summary. HTTPS is required except
/// for loopback hosts so local servers like Ollama work.
struct OpenAICompatibleSummaryClient {

	private static let logger = Logger(subsystem: Logger.nnwSubsystem, category: "OpenAICompatibleSummaryClient")

	static let keychainServer = "netnewswire.ai-summary"
	static let keychainUsername = "api-key"

	private let baseURL: URL
	private let apiKey: String
	private let model: String

	// MARK: - Validation

	/// Validates the raw endpoint string on its own: present, parseable, allowed scheme.
	/// Runs before any request is made, so nothing — not even model listing — sends
	/// a request with a bad scheme or host.
	static func validateEndpoint(_ endpoint: String?) throws -> URL {
		guard let endpoint, !endpoint.isEmpty else {
			throw ArticleSummaryError.missingConfiguration(NSLocalizedString("Enter an API endpoint in Settings.", comment: "Summary missing endpoint"))
		}
		guard let url = URL(string: endpoint), url.scheme?.isEmpty == false, url.host != nil else {
			throw ArticleSummaryError.invalidEndpoint("not a URL")
		}
		guard isAllowedScheme(url) else {
			throw ArticleSummaryError.invalidEndpoint("scheme")
		}
		return url
	}

	/// Validates raw settings; throws a recoverable settings error before anything is sent.
	static func validate(endpoint: String?, model: String?) throws -> OpenAICompatibleSummaryClient {
		let url = try validateEndpoint(endpoint)
		guard let model, !model.isEmpty else {
			throw ArticleSummaryError.missingConfiguration(NSLocalizedString("Choose or enter a model in Settings.", comment: "Summary missing model"))
		}
		return OpenAICompatibleSummaryClient(baseURL: url, apiKey: apiKey(), model: model)
	}

	/// Builds a client for an explicit user-initiated model listing. The model is not
	/// required — the point of the request is to discover models — but the endpoint
	/// scheme/host are still validated first.
	static func listModelsClient(endpoint: String?) throws -> OpenAICompatibleSummaryClient {
		let url = try validateEndpoint(endpoint)
		return OpenAICompatibleSummaryClient(baseURL: url, apiKey: apiKey(), model: "")
	}

	/// `true` if the endpoint alone is valid for a listing request.
	static func isEndpointValid(_ endpoint: String?) -> Bool {
		do {
			_ = try validateEndpoint(endpoint)
			return true
		} catch {
			return false
		}
	}

	static func isLoopbackHost(_ host: String) -> Bool {
		let normalized = host.lowercased().replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
		return normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1" || normalized.hasPrefix("::ffff:127.")
	}

	private static func isAllowedScheme(_ url: URL) -> Bool {
		switch url.scheme?.lowercased() {
		case "https":
			return true
		case "http":
			return isLoopbackHost(url.host ?? "")
		default:
			return false
		}
	}

	// MARK: - API

	/// Lists model ids. Runs only on an explicit user action; never sends article content.
	func listModels() async throws -> [String] {
		let modelsURL = baseURL.appending(path: "models")
		let request = Self.makeRequest(url: modelsURL, apiKey: apiKey)
		let (data, response) = try await Self.execute(request)
		guard Self.isSuccessfulHTTPResponse(response) else {
			throw Self.httpError(response)
		}
		let list = try Self.decodeJSON(ModelListResponse.self, from: data)
		let ids = list.data.map { $0.id }.filter { !$0.isEmpty }
		return ids.sorted()
	}

	/// Requests a summary of the given text. One network call, no retries.
	func summarize(title: String, text: String) async throws -> String {
		let chatURL = baseURL.appending(path: "chat/completions")
		var request = Self.makeRequest(url: chatURL, apiKey: apiKey)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.timeoutInterval = 90

		let instructions = NSLocalizedString("You summarize news articles. Reply in the same language as the article. Write 2-4 short sentences covering the main points. Plain text only.", comment: "Instruction for the article summarization model")

		let articleContent = title.isEmpty ? text : "Title: \(title)\n\n\(text)"
		let payload = ChatRequest(model: model, messages: [
			ChatMessage(role: "system", content: instructions),
			ChatMessage(role: "user", content: articleContent)
		])
		request.httpBody = try JSONEncoder().encode(payload)

		let (data, response) = try await Self.execute(request)
		guard Self.isSuccessfulHTTPResponse(response) else {
			throw Self.httpError(response)
		}
		let completion = try Self.decodeJSON(ChatResponse.self, from: data)
		guard let content = completion.choices.first?.message.content, !content.isEmpty else {
			throw ArticleSummaryError.malformedResponse
		}
		return content.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - Keychain

	private static func apiKey() -> String {
		do {
			let credentials = try CredentialsManager.retrieveCredentials(type: .basic, server: keychainServer, username: keychainUsername)
			return credentials?.secret ?? ""
		} catch {
			Self.logger.error("OpenAICompatibleSummaryClient: keychain read failed")
			return ""
		}
	}

	static func storeAPIKey(_ secret: String) throws {
		let credentials = Credentials(type: .basic, username: keychainUsername, secret: secret)
		try CredentialsManager.storeCredentials(credentials, server: keychainServer)
	}

	static func removeAPIKey() throws {
		try CredentialsManager.removeCredentials(type: .basic, server: keychainServer, username: keychainUsername)
	}

	// MARK: - Requests

	private static func makeRequest(url: URL, apiKey: String) -> URLRequest {
		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		request.timeoutInterval = 30
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		if !apiKey.isEmpty {
			request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
		}
		return request
	}

	private static func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
		do {
			let (data, urlResponse) = try await URLSession.shared.data(for: request)
			guard let httpResponse = urlResponse as? HTTPURLResponse else {
				throw ArticleSummaryError.network("no response")
			}
			return (data, httpResponse)
		} catch let error as ArticleSummaryError {
			throw error
		} catch {
			// Body-free and key-free: the raw error may embed the URL, never the secret or article text.
			let isCancellation = (error as? CancellationError) != nil || (error as? URLError)?.code == URLError.cancelled
			if isCancellation {
				throw CancellationError()
			}
			Self.logger.debug("OpenAICompatibleSummaryClient: transport failed")
			throw ArticleSummaryError.network("transport")
		}
	}

	private static func isSuccessfulHTTPResponse(_ response: HTTPURLResponse) -> Bool {
		(200..<300).contains(response.statusCode)
	}

	private static func httpError(_ response: HTTPURLResponse) -> ArticleSummaryError {
		logger.debug("OpenAICompatibleSummaryClient: HTTP status \(response.statusCode, privacy: .public)")
		return ArticleSummaryError.http(status: response.statusCode)
	}

	private static func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
		do {
			return try JSONDecoder().decode(type, from: data)
		} catch {
			throw ArticleSummaryError.malformedResponse
		}
	}
}

// MARK: - Response Codable

private struct ChatRequest: Encodable {
	let model: String
	let messages: [ChatMessage]
}

private struct ChatMessage: Codable {
	let role: String
	let content: String
}

private struct ChatResponse: Decodable {
	let choices: [Choice]

	struct Choice: Decodable {
		let message: ChatMessage
	}
}

private struct ModelListResponse: Decodable {
	let data: [ModelEntry]

	struct ModelEntry: Decodable {
		let id: String
	}
}
