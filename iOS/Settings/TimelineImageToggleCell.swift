//
//  TimelineImageToggleCell.swift
//  NetNewsWire-iOS
//
//  Created by AI summary feature, 10/21/26.
//

import UIKit
import RSCore

/// Toggle for showing the article image thumbnail in the timeline.
final class TimelineImageToggleCell: UICollectionViewCell {

	static let reuseIdentifier = "TimelineImageToggleCell"

	let toggle = UISwitch(frame: .zero)
	let label = NonIntrinsicLabel()

	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		let stack = UIStackView(arrangedSubviews: [label, toggle])
		stack.axis = .horizontal
		stack.alignment = .center
		stack.distribution = .fill
		stack.spacing = UIStackView.spacingUseDefault
		stack.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
			stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
			stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
		])

		toggle.isOn = AppDefaults.shared.timelineShowsArticleImage
		toggle.addTarget(self, action: #selector(toggleDidChange(_:)), for: .valueChanged)
		toggle.accessibilityLabel = NSLocalizedString("Show Article Images", comment: "Show Article Images")

		label.text = NSLocalizedString("Show Article Images", comment: "Show Article Images")
		label.numberOfLines = 0
		label.adjustsFontForContentSizeCategory = true
		label.isAccessibilityElement = false
		label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
		toggle.setContentHuggingPriority(.required, for: .horizontal)
	}

	@objc private func toggleDidChange(_ sender: UISwitch) {
		AppDefaults.shared.timelineShowsArticleImage = sender.isOn
	}
}

#Preview("Article Image Toggle") {
	let cell = TimelineImageToggleCell()
	cell.backgroundColor = .systemBackground
	cell.frame = CGRect(x: 0, y: 0, width: 320, height: 44)
	return cell
}
