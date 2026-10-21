//
//  AppDefaults+Shared.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 10/6/26.
//

import Foundation

private extension AppDefaults.Key {
	static let unreadCountDisplay = "unreadCountDisplay"
	static let markArticlesReadWhenSavedForLater = "markArticlesReadWhenSavedForLater"
}

extension AppDefaults {

	var unreadCountDisplay: UnreadCountDisplay {
		get {
			UnreadCountDisplay(rawValue: UserDefaults.standard.integer(forKey: Key.unreadCountDisplay)) ?? .count
		}
		set {
			UserDefaults.standard.set(newValue.rawValue, forKey: Key.unreadCountDisplay)
			NotificationCenter.default.post(name: .unreadCountDisplaySettingDidChange, object: self)
		}
	}

	/// Off by default: saving an article for later leaves its read status alone.
	var markArticlesReadWhenSavedForLater: Bool {
		get {
			UserDefaults.standard.bool(forKey: Key.markArticlesReadWhenSavedForLater)
		}
		set {
			UserDefaults.standard.set(newValue, forKey: Key.markArticlesReadWhenSavedForLater)
		}
	}
}
