//
//  SummarySettingsView.swift
//  NetNewsWire-iOS
//
//  Created by AI summary feature, 10/21/26.
//

import SwiftUI
import Secrets

/// Provider and model configuration for on-demand article summaries.
///
/// The API key lives only in Keychain through `CredentialsManager`; this view keeps
/// a boolean about the key's existence in observable state, never the secret itself.
/// The only network request made here is an explicit GET of the remote /models
/// endpoint, run when the user taps "List Models".
struct SummarySettingsView: View {

	@State private var provider = AppDefaults.shared.articleSummaryProvider
	@State private var endpoint = AppDefaults.shared.articleSummaryEndpoint ?? ""
	@State private var model = AppDefaults.shared.articleSummaryModel ?? ""
	@State private var apiKeyDraft = ""
	@State private var availableModels: [String] = []
	@State private var isListingModels = false
	@State private var keyExists = AppDefaults.shared.hasSummaryAPIKey
	@State private var keyStatusText: String?
	@State private var alertTitle = ""
	@State private var alertMessage = ""
	@State private var showingAlert = false

	var body: some View {
		Form {
			Section {
				Picker("Provider", selection: $provider) {
					ForEach(ArticleSummaryProvider.allCases, id: \.self) { candidate in
						Text(candidate.name).tag(candidate)
					}
				}
				.onChange(of: provider) { _, newValue in
					AppDefaults.shared.articleSummaryProvider = newValue
				}

				if provider == .appleLocal {
					Text(AppleLocalSummarizer.unavailabilityReason() ?? NSLocalizedString("Available on this device.", comment: "Summaries local model status"))
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			} header: {
				Text("Provider")
			}

			if provider == .openAICompatible {
				remoteSection
			}
		}
		.navigationTitle(Text("Article Summaries"))
		.alert(alertTitle, isPresented: $showingAlert) {
			Button("OK") {}
		} message: {
			Text(alertMessage)
		}
	}

	private var remoteSection: some View {
		Section {
			TextField("API Endpoint (base URL)", text: $endpoint)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
				.keyboardType(.URL)
				.onChange(of: endpoint) { _, newValue in
					let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
					AppDefaults.shared.articleSummaryEndpoint = trimmed.isEmpty ? nil : trimmed
				}

			Text("The endpoint is a base URL, for example https://api.openai.com/v1 or http://localhost:11434/v1 for Ollama.")
				.font(.footnote)
				.foregroundStyle(.secondary)

			SecureField("API Key", text: $apiKeyDraft)

			HStack {
				Button("Save Key") {
					saveKey()
				}
				.disabled(apiKeyDraft.isEmpty)

				Button("Remove Key") {
					removeKey()
				}
				.disabled(!keyExists)
			}
			.buttonStyle(.borderless)

			if let keyStatusText {
				Text(keyStatusText)
					.font(.footnote)
					.foregroundStyle(.secondary)
			}

			TextField("Model", text: $model)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
				.onChange(of: model) { _, newValue in
					AppDefaults.shared.articleSummaryModel = newValue.isEmpty ? nil : newValue
				}

			Button {
				listModels()
			} label: {
				if isListingModels {
					ProgressView()
				} else {
					Text("List Models")
				}
			}
			.disabled(isListingModels || !OpenAICompatibleSummaryClient.isEndpointValid(endpoint))

			if !availableModels.isEmpty {
				Picker("Choose Model", selection: $model) {
					ForEach(availableModels, id: \.self) { candidate in
						Text(candidate).tag(candidate)
					}
				}
			}
		} header: {
			Text("Remote Provider")
		} footer: {
			Text("The key stays in this device's Keychain. Summaries are generated only when you tap Summarize while reading an article, and are never stored or synced.")
		}
	}

	// MARK: - Actions

	private func saveKey() {
		guard !apiKeyDraft.isEmpty else {
			return
		}
		do {
			try OpenAICompatibleSummaryClient.storeAPIKey(apiKeyDraft)
			apiKeyDraft = ""
			keyExists = true
			keyStatusText = NSLocalizedString("Key stored in Keychain.", comment: "Summary key saved")
		} catch {
			showAlert(NSLocalizedString("Could Not Save Key", comment: "Summary key error"), message: localizedCredentialMessage())
		}
	}

	private func removeKey() {
		do {
			try OpenAICompatibleSummaryClient.removeAPIKey()
			keyExists = false
			availableModels = []
			keyStatusText = NSLocalizedString("Key removed.", comment: "Summary key removed")
		} catch {
			showAlert(NSLocalizedString("Could Not Remove Key", comment: "Summary key error"), message: localizedCredentialMessage())
		}
	}

	/// Explicit user action: one GET of {base}/models. Runs only when tapped; the
	/// endpoint is validated (HTTPS, or HTTP only for loopback) before any request.
	private func listModels() {
		guard !isListingModels else {
			return
		}
		isListingModels = true
		Task { @MainActor in
			defer {
				isListingModels = false
			}
			do {
				let client = try OpenAICompatibleSummaryClient.listModelsClient(endpoint: endpoint)
				let ids = try await client.listModels()
				availableModels = ids
				if let first = ids.first, model.isEmpty {
					model = first
					AppDefaults.shared.articleSummaryModel = first
				}
			} catch {
				availableModels = []
				showAlert(NSLocalizedString("Could Not List Models", comment: "Summary list models error title"), message: error.localizedDescription)
			}
		}
	}

	private func showAlert(_ title: String, message: String) {
		alertTitle = title
		alertMessage = message
		showingAlert = true
	}

	private func localizedCredentialMessage() -> String {
		NSLocalizedString("The key could not be updated in the Keychain. Try again.", comment: "Summary credential error")
	}
}

extension AppDefaults {

	/// True when a summary key is stored in Keychain. The secret itself is never
	/// kept in observable state.
	@MainActor var hasSummaryAPIKey: Bool {
		do {
			let credentials = try CredentialsManager.retrieveCredentials(type: .basic, server: OpenAICompatibleSummaryClient.keychainServer, username: OpenAICompatibleSummaryClient.keychainUsername)
			return credentials != nil
		} catch {
			return false
		}
	}
}

#Preview("Summary Settings") {
	NavigationStack {
		SummarySettingsView()
	}
}
