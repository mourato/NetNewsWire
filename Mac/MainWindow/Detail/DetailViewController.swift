//
//  DetailViewController.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 7/26/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import WebKit
import RSCore
import Articles
import RSWeb

enum DetailState: Equatable {
	case noSelection
	case multipleSelection
	case loading
	case article(Article, CGFloat?)
	case extracted(Article, ExtractedArticle, CGFloat?)
}

final class DetailViewController: NSViewController, WKUIDelegate {

	@IBOutlet var containerView: DetailContainerView!
	@IBOutlet var statusBarView: DetailStatusBarView!

	private lazy var regularWebViewController = createWebViewController()
	private var searchWebViewController: DetailWebViewController?

	var windowState: DetailWindowState {
		currentWebViewController.windowState
	}

	private var currentWebViewController: DetailWebViewController! {
		didSet {
			let webview = currentWebViewController.view
			if containerView.contentView === webview {
				return
			}
			statusBarView.mouseoverLink = nil
			containerView.contentView = webview
		}
	}

	private var currentSourceMode: TimelineSourceMode = .regular {
		didSet {
			currentWebViewController = webViewController(for: currentSourceMode)
		}
	}

	private var detailStateForRegular: DetailState = .noSelection {
		didSet {
			webViewController(for: .regular).state = detailStateForRegular
		}
	}

	private var detailStateForSearch: DetailState = .noSelection {
		didSet {
			webViewController(for: .search).state = detailStateForSearch
		}
	}

	/// Identity of the article shown for summarization purposes; accountID is part of
	/// it because articleIDs are only unique within an account.
	private struct ArticleIdentity: Equatable {
		let accountID: String
		let articleID: String

		init?(article: Article?) {
			guard let article else {
				return nil
			}
			self.accountID = article.accountID
			self.articleID = article.articleID
		}
	}

	private var summaryPanelController: ArticleSummaryPanelViewController?
	private var summaryArticleIdentity: ArticleIdentity?
	private let summaryRunner = ArticleSummaryRunner()
	private static let summaryPanelHeight: CGFloat = 150

	convenience init() {
		self.init(nibName: "DetailView", bundle: nil)
	}

	override func viewDidLoad() {
		currentWebViewController = regularWebViewController
	}

	// MARK: - API

	func setState(_ state: DetailState, mode: TimelineSourceMode) {
		// A different displayed article (or empty detail) invalidates any in-flight
		// or shown summary, including mode switches that swap the active web view.
		cancelSummaryIfDisplayedIdentityChanged(to: state)
		switch mode {
		case .regular:
			detailStateForRegular = state
		case .search:
			detailStateForSearch = state
		}
	}

	func showDetail(for mode: TimelineSourceMode) {
		currentSourceMode = mode
		// Switching between the regular and search web views may reveal a different
		// article; re-check what is now displayed.
		cancelSummaryIfDisplayedIdentityChanged(to: currentWebViewController.state)
	}

	func stopMediaPlayback() {
		currentWebViewController.stopMediaPlayback()
	}

	func fetchSelectedHTML(_ completion: @escaping (String?) -> Void) {
		currentWebViewController.fetchSelectedHTML(completion)
	}

	func canScrollDown() async -> Bool {
		await currentWebViewController.canScrollDown()
	}

	func canScrollUp() async -> Bool {
		await currentWebViewController.canScrollUp()
	}

	override func scrollPageDown(_ sender: Any?) {
		currentWebViewController.scrollPageDown(sender)
	}

	override func scrollPageUp(_ sender: Any?) {
		currentWebViewController.scrollPageUp(sender)
	}

	// MARK: - Navigation

	func focus() {
		guard let window = currentWebViewController.webView.window else {
			return
		}
		window.makeFirstResponderUnlessDescendantIsFirstResponder(currentWebViewController.webView)
	}

	// MARK: - Summaries

	private var currentArticle: Article? {
		viewIfLoaded == nil ? nil : currentWebViewController.article
	}

	var canSummarizeArticle: Bool {
		currentArticle != nil
	}

	@objc func summarizeArticle(_ sender: Any?) {
		guard let article = currentArticle else {
			return
		}
		summaryArticleIdentity = ArticleIdentity(article: article)
		summaryRunner.onStateChange = { [weak self] displayState in
			self?.handleSummaryStateChange(displayState)
		}
		summaryRunner.summarize(input: ArticleSummaryInput(article: article), settings: AppDefaults.shared.articleSummarySettings)
	}

	private func handleSummaryStateChange(_ displayState: ArticleSummaryDisplayState) {
		switch displayState {
		case .idle:
			tearDownSummaryPanel()
		default:
			let panel = ensureSummaryPanel()
			panel.display(displayState)
		}
	}

	private func ensureSummaryPanel() -> ArticleSummaryPanelViewController {
		if let summaryPanelController {
			return summaryPanelController
		}
		let panel = ArticleSummaryPanelViewController()
		summaryPanelController = panel
		addChild(panel)
		panel.view.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(panel.view, positioned: .above, relativeTo: nil)
		let safeArea = view.safeAreaLayoutGuide
		NSLayoutConstraint.activate([
			panel.view.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
			panel.view.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
			panel.view.topAnchor.constraint(equalTo: safeArea.topAnchor),
			panel.view.heightAnchor.constraint(equalToConstant: Self.summaryPanelHeight)
		])
		// The panel takes space above the article instead of covering its text.
		containerView.topContentPadding = Self.summaryPanelHeight
		panel.onDismiss = { [weak self] in
			self?.cancelSummary()
		}
		return panel
	}

	private func tearDownSummaryPanel() {
		summaryPanelController?.view.removeFromSuperview()
		summaryPanelController?.removeFromParent()
		summaryPanelController = nil
		containerView.topContentPadding = 0
	}

	private func cancelSummary() {
		summaryRunner.onStateChange = nil
		summaryRunner.cancel()
		tearDownSummaryPanel()
		summaryArticleIdentity = nil
	}

	private func cancelSummaryIfDisplayedIdentityChanged(to state: DetailState) {
		let displayedArticle: Article?
		switch state {
		case .article(let article, _), .extracted(let article, _, _):
			displayedArticle = article
		default:
			displayedArticle = nil
		}
		if ArticleIdentity(article: displayedArticle) != summaryArticleIdentity {
			cancelSummary()
		}
	}
}

// MARK: - NSMenuItemValidation

extension DetailViewController: NSMenuItemValidation {

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		if menuItem.action == #selector(summarizeArticle(_:)) {
			return canSummarizeArticle
		}
		return true
	}
}

// MARK: - DetailWebViewControllerDelegate

extension DetailViewController: DetailWebViewControllerDelegate {

	func mouseDidEnter(_ detailWebViewController: DetailWebViewController, link: String) {
		guard !link.isEmpty, detailWebViewController === currentWebViewController else {
			return
		}
		statusBarView.mouseoverLink = link
	}

	func mouseDidExit(_ detailWebViewController: DetailWebViewController) {
		guard detailWebViewController === currentWebViewController else {
			return
		}
		statusBarView.mouseoverLink = nil
	}
}

// MARK: - Private

private extension DetailViewController {

	func createWebViewController() -> DetailWebViewController {
		let controller = DetailWebViewController()
		controller.delegate = self
		controller.state = .noSelection
		return controller
	}

	func webViewController(for mode: TimelineSourceMode) -> DetailWebViewController {
		switch mode {
		case .regular:
			return regularWebViewController
		case .search:
			if searchWebViewController == nil {
				searchWebViewController = createWebViewController()
			}
			return searchWebViewController!
		}
	}
}
