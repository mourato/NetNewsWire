//
//  ArticleSummaryPanelView.swift
//  NetNewsWire-iOS
//
//  Created by AI summary feature, 10/21/26.
//

import UIKit

/// Temporary, in-memory panel pinned to the top of the article screen while a summary
/// is loading or displayed. Nothing here is persisted; dismissing the panel or
/// changing articles cancels the work and clears the text.
final class ArticleSummaryPanelView: UIView {

	private let titleLabel = UILabel()
	private let spinner = UIActivityIndicatorView(style: .medium)
	private let bodyLabel = UILabel()
	private let dismissButton = UIButton(type: .system)

	var onDismiss: (() -> Void)?

	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		backgroundColor = .secondarySystemGroupedBackground

		let hairline = UIView()
		hairline.backgroundColor = .separator
		hairline.translatesAutoresizingMaskIntoConstraints = false
		addSubview(hairline)
		NSLayoutConstraint.activate([
			hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
			hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
			hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
			hairline.heightAnchor.constraint(equalToConstant: 1.0 / max(1.0, UIScreen.main.scale))
		])

		let headerStack = UIStackView(arrangedSubviews: [titleLabel, spinner, dismissButton])
		headerStack.axis = .horizontal
		headerStack.alignment = .center
		headerStack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(headerStack)
		NSLayoutConstraint.activate([
			headerStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
			headerStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
			headerStack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor, constant: 6)
		])

		titleLabel.text = NSLocalizedString("Article Summary", comment: "Summary panel title")
		titleLabel.font = .preferredFont(forTextStyle: .headline)
		titleLabel.adjustsFontForContentSizeCategory = true
		titleLabel.isAccessibilityElement = false

		spinner.hidesWhenStopped = true
		spinner.isAccessibilityElement = false

		let symbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body)
		dismissButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: symbolConfiguration), for: .normal)
		dismissButton.tintColor = .secondaryLabel
		dismissButton.accessibilityLabel = NSLocalizedString("Dismiss Summary", comment: "Dismiss summary button")
		dismissButton.setContentHuggingPriority(.required, for: .horizontal)
		dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)

		bodyLabel.font = .preferredFont(forTextStyle: .body)
		bodyLabel.adjustsFontForContentSizeCategory = true
		bodyLabel.numberOfLines = 0
		bodyLabel.isAccessibilityElement = false // The panel itself is read as one element
		bodyLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(bodyLabel)
		NSLayoutConstraint.activate([
			bodyLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
			bodyLabel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
			bodyLabel.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 6),
			bodyLabel.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor)
		])
	}

	var headerText: String {
		get {
			titleLabel.text ?? ""
		}
		set {
			titleLabel.text = newValue
		}
	}

	func display(_ displayState: ArticleSummaryDisplayState) {
		switch displayState {
		case .idle:
			bodyLabel.text = ""
			spinner.stopAnimating()
		case .loading:
			bodyLabel.text = ""
			spinner.startAnimating()
		case .finished(let text, _):
			spinner.stopAnimating()
			bodyLabel.text = text
			bodyLabel.textColor = .label
		case .failed(let errorDescription):
			spinner.stopAnimating()
			bodyLabel.text = errorDescription
			bodyLabel.textColor = .secondaryLabel
		}
	}

	@objc private func dismissTapped() {
		onDismiss?()
	}
}

#Preview("Summary Panel") {
	let loadingPanel = ArticleSummaryPanelView()
	loadingPanel.display(.loading)
	let finishedPanel = ArticleSummaryPanelView()
	finishedPanel.display(.finished(text: "Bree was the chief village of Bree-land, a small country whose chief claim to fame was its aluminum siding industry.", providerName: "EXAMPLE"))
	let failedPanel = ArticleSummaryPanelView()
	failedPanel.display(.failed(errorDescription: "Summarization failed"))

	let stack = UIStackView(arrangedSubviews: [loadingPanel, finishedPanel, failedPanel, ArticleSummaryPanelView()])
	stack.axis = .vertical
	stack.distribution = .fillEqually
	return stack
}
