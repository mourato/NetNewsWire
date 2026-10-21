//
//  DetailContainerView.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 2/12/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import AppKit

final class DetailContainerView: NSView {

	@IBOutlet var detailStatusBarView: DetailStatusBarView!

	var contentViewConstraints: [NSLayoutConstraint]?

	/// Space reserved at the top of the container for a temporary summary panel.
	/// The web view starts below it while the panel is visible, so the panel takes
	/// space instead of covering article content.
	var topContentPadding: CGFloat = 0 {
		didSet {
			guard topContentPadding != oldValue, let contentViewConstraints else {
				return
			}
			for constraint in contentViewConstraints where constraint.firstAttribute == .top && constraint.firstItem === contentView {
				constraint.constant = topContentPadding
			}
		}
	}

	var contentView: NSView? {
		didSet {
			if contentView == oldValue {
				return
			}

			if let currentConstraints = contentViewConstraints {
				NSLayoutConstraint.deactivate(currentConstraints)
			}
			contentViewConstraints = nil
			oldValue?.removeFromSuperviewWithoutNeedingDisplay()

			if let contentView = contentView {
				contentView.translatesAutoresizingMaskIntoConstraints = false
				addSubview(contentView, positioned: .below, relativeTo: detailStatusBarView)
				// Leading and trailing follow the safe area so the article view doesn’t extend under the sidebar
				// in column layout on macOS 26. Top stays at the edge: the web view handles the toolbar itself.
				let constraints = [
					contentView.topAnchor.constraint(equalTo: topAnchor, constant: topContentPadding),
					contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
					contentView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
					contentView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor)
				]
				NSLayoutConstraint.activate(constraints)
				contentViewConstraints = constraints
			}
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		NSColor.controlBackgroundColor.set()
		let r = dirtyRect.intersection(bounds)
		r.fill()
	}
}
