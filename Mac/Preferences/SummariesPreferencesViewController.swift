//
//  SummariesPreferencesViewController.swift
//  NetNewsWire
//
//  Created by AI summary feature, 10/21/26.
//

import AppKit
import Secrets

/// Preferences pane for on-demand article summaries: provider choice plus, for the
/// OpenAI-compatible remote provider, the endpoint, Keychain-stored API key, and model.
/// The key is stored only in Keychain; this pane keeps only the key's existence in
/// state, never the secret. The sole network request made here is an explicit GET of
/// /models when the user taps "List Models".
final class SummariesPreferencesViewController: NSViewController {

	private let providerRow = NSStackView()
	private let providerPopup = NSPopUpButton()
	private let localStatusLabel = NSTextField(wrappingLabelWithString: "")
	private let endpointRow = NSStackView()
	private let endpointField = NSTextField()
	private let apiKeyField = NSSecureTextField()
	private let saveKeyButton = NSButton()
	private let removeKeyButton = NSButton()
	private let modelRow = NSStackView()
	private let modelField = NSTextField()
	private let listModelsButton = NSButton()
	private let modelPopup = NSPopUpButton()
	private let statusLabel = NSTextField(wrappingLabelWithString: "")

	private var isListingModels = false {
		didSet {
			refreshControlStates()
		}
	}

	/// True when the endpoint alone passes scheme/host validation; model listing does
	/// not require a pre-set model.
	private var endpointIsListable: Bool {
		OpenAICompatibleSummaryClient.isEndpointValid(endpointField.stringValue)
	}

	private var keyExists: Bool {
		do {
			let credentials = try CredentialsManager.retrieveCredentials(type: .basic, server: OpenAICompatibleSummaryClient.keychainServer, username: OpenAICompatibleSummaryClient.keychainUsername)
			return credentials != nil
		} catch {
			return false
		}
	}

	override func loadView() {
		let paneView = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 384))

		let titleLabel = NSTextField(labelWithString: NSLocalizedString("Article Summaries", comment: "Summaries preferences title"))
		titleLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize(for: .large))

		let providerLabel = Self.makeFormLabel("Provider:")
		for provider in ArticleSummaryProvider.allCases {
			providerPopup.addItem(withTitle: provider.name)
		}
		providerPopup.target = self
		providerPopup.action = #selector(providerDidChange(_:))
		providerPopup.widthAnchor.constraint(equalToConstant: 240).isActive = true

		localStatusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		localStatusLabel.textColor = .secondaryLabelColor

		let endpointLabel = Self.makeFormLabel("API endpoint (base URL):")
		endpointField.placeholderString = NSLocalizedString("https://api.example.com/v1", comment: "Summaries endpoint placeholder")
		endpointField.usesSingleLineMode = true
		endpointField.delegate = self
		endpointField.widthAnchor.constraint(equalToConstant: 240).isActive = true

		let apiKeyLabel = Self.makeFormLabel("API key:")
		apiKeyField.placeholderString = NSLocalizedString("Key stored in Keychain", comment: "Summaries key placeholder")
		apiKeyField.usesSingleLineMode = true
		apiKeyField.widthAnchor.constraint(equalToConstant: 200).isActive = true

		saveKeyButton.title = NSLocalizedString("Save Key", comment: "Summaries save key button")
		saveKeyButton.bezelStyle = .rounded
		saveKeyButton.controlSize = .small
		saveKeyButton.target = self
		saveKeyButton.action = #selector(saveKey(_:))

		removeKeyButton.title = NSLocalizedString("Remove Key", comment: "Summaries remove key button")
		removeKeyButton.bezelStyle = .rounded
		removeKeyButton.controlSize = .small
		removeKeyButton.target = self
		removeKeyButton.action = #selector(removeKey(_:))

		let modelLabel = Self.makeFormLabel("Model:")
		modelField.usesSingleLineMode = true
		modelField.delegate = self
		modelField.placeholderString = NSLocalizedString("Model identifier", comment: "Summaries model field placeholder")
		modelField.widthAnchor.constraint(equalToConstant: 240).isActive = true

		listModelsButton.title = NSLocalizedString("List Models", comment: "Summaries list models button")
		listModelsButton.bezelStyle = .rounded
		listModelsButton.controlSize = .small
		listModelsButton.target = self
		listModelsButton.action = #selector(listModels(_:))

		modelPopup.target = self
		modelPopup.action = #selector(modelPopupDidChange(_:))
		modelPopup.widthAnchor.constraint(equalToConstant: 240).isActive = true
		modelPopup.isHidden = true

		let helpLabel = NSTextField(wrappingLabelWithString: NSLocalizedString("The key is stored in the macOS Keychain only. Summaries are generated only when you choose Summarize while reading an article, and are never stored or synced.", comment: "Summaries preferences help"))
		helpLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		helpLabel.textColor = .secondaryLabelColor

		statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		statusLabel.textColor = .secondaryLabelColor

		Self.fillFormRow(providerRow, label: providerLabel, controls: [providerPopup])
		Self.fillFormRow(endpointRow, label: endpointLabel, controls: [endpointField])
		Self.fillFormRow(modelRow, label: modelLabel, controls: [modelField])

		let keyRow = NSStackView(views: [apiKeyLabel, apiKeyField, saveKeyButton, removeKeyButton])
		keyRow.orientation = .horizontal
		keyRow.alignment = .centerY
		keyRow.spacing = 8
		apiKeyLabel.setContentHuggingPriority(.required, for: .horizontal)

		let stack = NSStackView(views: [titleLabel, providerRow, localStatusLabel, endpointRow, keyRow, modelRow, modelPopup, listModelsButton, helpLabel, statusLabel])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 10
		stack.translatesAutoresizingMaskIntoConstraints = false

		for row in [providerRow, endpointRow, modelRow] {
			row.spacing = 8
		}

		paneView.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: paneView.leadingAnchor, constant: 20),
			stack.trailingAnchor.constraint(lessThanOrEqualTo: paneView.trailingAnchor, constant: -20),
			stack.topAnchor.constraint(equalTo: paneView.topAnchor, constant: 20),
			stack.bottomAnchor.constraint(lessThanOrEqualTo: paneView.bottomAnchor, constant: -20)
		])

		view = paneView
		syncFields()
	}

	// MARK: - Actions

	@objc private func providerDidChange(_ sender: NSPopUpButton) {
		guard let provider = ArticleSummaryProvider(rawValue: sender.indexOfSelectedItem) else {
			return
		}
		AppDefaults.shared.articleSummaryProvider = provider
		syncFields()
	}

	@objc private func saveKey(_ sender: Any?) {
		let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !key.isEmpty else {
			return
		}
		do {
			try OpenAICompatibleSummaryClient.storeAPIKey(key)
			apiKeyField.stringValue = ""
			clearStatus()
			syncFields()
		} catch {
			showStatus(NSLocalizedString("The key could not be stored in the Keychain. Try again.", comment: "Summaries key error"))
		}
	}

	@objc private func removeKey(_ sender: Any?) {
		do {
			try OpenAICompatibleSummaryClient.removeAPIKey()
			clearStatus()
			syncFields()
		} catch {
			showStatus(NSLocalizedString("The key could not be removed from the Keychain. Try again.", comment: "Summaries key error"))
		}
	}

	/// Explicit user action: one GET of {base}/models. Runs only when tapped; the
	/// endpoint is validated before any request is made.
	@objc private func listModels(_ sender: Any?) {
		guard !isListingModels else {
			return
		}
		isListingModels = true
		let endpoint = endpointField.stringValue
		Task { @MainActor in
			defer {
				self.isListingModels = false
			}
			do {
				let client = try OpenAICompatibleSummaryClient.listModelsClient(endpoint: endpoint)
				let ids = try await client.listModels()
				self.fillModelPopup(ids)
				self.clearStatus()
			} catch {
				self.showStatus(NSLocalizedString("The server could not list models. Check the endpoint and key.", comment: "Summaries list models error"))
			}
		}
	}

	@objc private func modelPopupDidChange(_ sender: NSPopUpButton) {
		guard let model = sender.titleOfSelectedItem, !model.isEmpty else {
			return
		}
		AppDefaults.shared.articleSummaryModel = model
		modelField.stringValue = model
	}

	// MARK: - Private

	private static func makeFormLabel(_ text: String) -> NSTextField {
		let label = NSTextField(labelWithString: NSLocalizedString(text, comment: "Summaries preferences label"))
		label.alignment = .right
		label.setContentHuggingPriority(.required, for: .horizontal)
		return label
	}

	private static func fillFormRow(_ row: NSStackView, label: NSTextField, controls: [NSView]) {
		row.orientation = .horizontal
		row.alignment = .centerY
		row.spacing = 8
		row.translatesAutoresizingMaskIntoConstraints = false
		for control in controls {
			row.addArrangedSubview(control)
		}
		row.insertArrangedSubview(label, at: 0)
	}

	private func syncFields() {
		let provider = AppDefaults.shared.articleSummaryProvider
		let isRemote = provider == .openAICompatible

		providerPopup.selectItem(at: provider.rawValue)

		if let reason = AppleLocalSummarizer.unavailabilityReason() {
			localStatusLabel.stringValue = reason
		} else {
			localStatusLabel.stringValue = NSLocalizedString("Available on this Mac.", comment: "Summaries local model status")
		}
		localStatusLabel.isHidden = !isRemote

		endpointField.stringValue = AppDefaults.shared.articleSummaryEndpoint ?? ""
		modelField.stringValue = AppDefaults.shared.articleSummaryModel ?? ""
		endpointField.isEnabled = isRemote
		apiKeyField.isEnabled = isRemote
		modelField.isEnabled = isRemote

		endpointRow.isHidden = !isRemote
		modelRow.isHidden = !isRemote
		modelPopup.isHidden = true
		listModelsButton.isHidden = !isRemote

		refreshControlStates()
	}

	private func refreshControlStates() {
		saveKeyButton.isEnabled = !apiKeyField.stringValue.isEmpty
		removeKeyButton.isEnabled = keyExists
		listModelsButton.isEnabled = !isListingModels && endpointIsListable
		if isListingModels {
			showStatus(NSLocalizedString("Listing models", comment: "Summaries list models status"))
		}
	}

	private func fillModelPopup(_ ids: [String]) {
		modelPopup.removeAllItems()
		for id in ids {
			modelPopup.addItem(withTitle: id)
		}
		if let current = AppDefaults.shared.articleSummaryModel {
			modelPopup.selectItem(withTitle: current)
		}
		modelPopup.isHidden = !AppDefaults.shared.articleSummaryProvider.isOpenAICompatible || ids.isEmpty
	}

	private func showStatus(_ text: String) {
		statusLabel.stringValue = text
	}

	private func clearStatus() {
		statusLabel.stringValue = ""
	}
}

// MARK: - NSTextFieldDelegate

extension SummariesPreferencesViewController: NSTextFieldDelegate {

	func controlTextDidChange(_ obj: Notification) {
		guard let control = obj.object as? NSTextField else {
			return
		}
		let trimmed = control.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		if control === endpointField {
			AppDefaults.shared.articleSummaryEndpoint = trimmed.isEmpty ? nil : trimmed
		} else if control === modelField {
			AppDefaults.shared.articleSummaryModel = trimmed.isEmpty ? nil : trimmed
		}
		refreshControlStates()
	}
}
