//
//  ArticleSummaryPanelViewController.swift
//  NetNewsWire
//
//  Created by AI summary feature, 10/21/26.
//

import AppKit

/// Temporary, in-memory panel shown in the top band of the macOS article detail while
/// a summary is loading or displayed. The band reserving its height lives in
/// `DetailContainerView.topContentPadding`; nothing here is persisted, and dismissing
/// the panel or changing articles cancels the work and clears the text.
final class ArticleSummaryPanelViewController: NSViewController {

	var onDismiss: (() -> Void)?

	private let titleLabel = NSTextField(labelWithString: "")
	private let spinner = NSProgressIndicator()
	private let bodyLabel = NSTextField(wrappingLabelWithString: "")
	private let dismissButton = NSButton()

	override func loadView() {
		let panelView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 140))
		panelView.wantsLayer = true
		panelView.layer?.cornerRadius = 8

		titleLabel.stringValue = NSLocalizedString("Article Summary", comment: "Summary panel title")
		titleLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize(for: .regular))

		spinner.isIndeterminate = true
		spinner.style = .spinning
		spinner.isDisplayedWhenStopped = false
		spinner.controlSize = .small
		spinner.widthAnchor.constraint(equalToConstant: 16).isActive = true

		bodyLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular))
		bodyLabel.textColor = .labelColor

		let symbolConfiguration = NSImage.SymbolConfiguration(textStyle: .body)
		let dismissImage = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: NSLocalizedString("Dismiss Summary", comment: "Dismiss summary button"))?.withSymbolConfiguration(symbolConfiguration)
		dismissButton.bezelStyle = .recessed
		dismissButton.isBordered = false
		dismissButton.image = dismissImage ?? NSImage()
		dismissButton.setAccessibilityLabel(NSLocalizedString("Dismiss Summary", comment: "Dismiss summary button"))
		dismissButton.setContentHuggingPriority(.required, for: .horizontal)
		dismissButton.action = #selector(dismissTapped)

		let topStack = NSStackView(views: [titleLabel, spinner, dismissButton])
		topStack.orientation = .horizontal
		topStack.alignment = .centerY
		topStack.spacing = 8
		topStack.translatesAutoresizingMaskIntoConstraints = false

		panelView.addSubview(topStack)
		panelView.addSubview(bodyLabel)
		topStack.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 12).isActive = true
		topStack.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -12).isActive = true
		topStack.topAnchor.constraint(equalTo: panelView.topAnchor, constant: 10).isActive = true
		bodyLabel.translatesAutoresizingMaskIntoConstraints = false
		bodyLabel.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 12).isActive = true
		bodyLabel.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -12).isActive = true
		bodyLabel.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 6).isActive = true
		bodyLabel.bottomAnchor.constraint(lessThanOrEqualTo: panelView.bottomAnchor, constant: -10).isActive = true

		view = panelView
	}

	func display(_ displayState: ArticleSummaryDisplayState) {
		switch displayState {
		case .idle:
			bodyLabel.stringValue = ""
			spinner.stopAnimation(nil)
		case .loading:
			bodyLabel.stringValue = ""
			spinner.startAnimation(nil)
		case .finished(let text, _):
			spinner.stopAnimation(nil)
			bodyLabel.stringValue = text
			bodyLabel.textColor = .labelColor
		case .failed(let errorDescription):
			spinner.stopAnimation(nil)
			bodyLabel.stringValue = errorDescription
			bodyLabel.textColor = .secondaryLabelColor
		}
	}

	@objc private func dismissTapped() {
		onDismiss?()
	}
}

#Preview("Summary Panel") {
	ArticleSummaryPanelViewController()
}
