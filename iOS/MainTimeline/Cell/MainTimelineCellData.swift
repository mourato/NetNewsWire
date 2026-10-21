//
//  MainTimelineCellData.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 2/6/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

import UIKit
import Articles
import Images

@MainActor struct MainTimelineCellData {

	private static let noText = NSLocalizedString("(No Text)", comment: "No Text")

	let accountID: String
	let articleID: String
	let title: String
	let attributedTitle: NSAttributedString
	let summary: String
	let dateString: String
	let feedName: String
	let byline: String
	let showFeedName: ShowFeedName
	let thumbnailImage: IconImage? // article thumbnail, or a fallback feed icon/avatar/favicon
	let showsThumbnail: Bool // Make space even when thumbnail is nil
	let read: Bool
	let starred: Bool
	let numberOfLines: Int

	init(article: Article, showFeedName: ShowFeedName, feedName: String?, byline: String?, thumbnailImage: IconImage?, showsThumbnail: Bool, numberOfLines: Int) {

		self.accountID = article.accountID
		self.articleID = article.articleID
		self.title = ArticleStringFormatter.shared.truncatedTitle(article)
		self.attributedTitle = ArticleStringFormatter.shared.attributedTruncatedTitle(article)

		let truncatedSummary = ArticleStringFormatter.shared.truncatedSummary(article)
		if self.title.isEmpty && truncatedSummary.isEmpty {
			self.summary = Self.noText
		} else {
			self.summary = truncatedSummary
		}

		self.dateString = ArticleStringFormatter.shared.dateString(article.logicalDatePublished)

		if let feedName = feedName {
			self.feedName = ArticleStringFormatter.shared.truncatedFeedName(feedName)
		} else {
			self.feedName = ""
		}

		if let byline = byline {
			self.byline = byline
		} else {
			self.byline = ""
		}

		self.showFeedName = showFeedName

		self.thumbnailImage = thumbnailImage
		self.showsThumbnail = showsThumbnail

		self.read = article.status.read
		self.starred = article.status.starred
		self.numberOfLines = numberOfLines

	}

	init() { // Empty
		self.accountID = ""
		self.articleID = ""
		self.title = ""
		self.attributedTitle = NSAttributedString()
		self.summary = ""
		self.dateString = ""
		self.feedName = ""
		self.byline = ""
		self.showFeedName = .none
		self.thumbnailImage = nil
		self.showsThumbnail = false
		self.read = true
		self.starred = false
		self.numberOfLines = 0
	}

}
