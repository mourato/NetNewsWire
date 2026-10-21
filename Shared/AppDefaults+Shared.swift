//
//  AppDefaults+Shared.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 10/6/26.
//

import Foundation

private extension AppDefaults.Key {
	static let unreadCountDisplay = "unreadCountDisplay"
	static let articleSummaryProvider = "articleSummaryProvider"
	static let articleSummaryEndpoint = "articleSummaryEndpoint"
	static let articleSummaryModel = "articleSummaryModel"
}

extension Notification.Name {
	static let articleSummarySettingsDidChange = Notification.Name("ArticleSummarySettingsDidChangeNotification")
}

extension AppDefaults {

	/// iOS keeps its app-group store; macOS uses standard defaults.
	fileprivate static var articleSettingsStore: UserDefaults {
#if os(macOS)
		return UserDefaults.standard
#else
		return AppDefaults.store
#endif
	}

	var unreadCountDisplay: UnreadCountDisplay {
		get {
			UnreadCountDisplay(rawValue: UserDefaults.standard.integer(forKey: Key.unreadCountDisplay)) ?? .count
		}
		set {
			UserDefaults.standard.set(newValue.rawValue, forKey: Key.unreadCountDisplay)
			NotificationCenter.default.post(name: .unreadCountDisplaySettingDidChange, object: self)
		}
	}

	// MARK: - Article Summaries

	/// The selected summarization provider. Defaults to the local Apple model on
	/// supported systems; never falls back automatically — the user chooses remote explicitly.
	var articleSummaryProvider: ArticleSummaryProvider {
		get {
			ArticleSummaryProvider(rawValue: AppDefaults.articleSettingsStore.integer(forKey: Key.articleSummaryProvider)) ?? .appleLocal
		}
		set {
			AppDefaults.articleSettingsStore.set(newValue.rawValue, forKey: Key.articleSummaryProvider)
			NotificationCenter.default.post(name: .articleSummarySettingsDidChange, object: self)
		}
	}

	/// Raw endpoint base URL string for the remote provider, or nil when unset.
	var articleSummaryEndpoint: String? {
		get {
			return AppDefaults.articleSettingsStore.string(forKey: Key.articleSummaryEndpoint)
		}
		set {
			if let newValue {
				AppDefaults.articleSettingsStore.set(newValue, forKey: Key.articleSummaryEndpoint)
			} else {
				AppDefaults.articleSettingsStore.removeObject(forKey: Key.articleSummaryEndpoint)
			}
			NotificationCenter.default.post(name: .articleSummarySettingsDidChange, object: self)
		}
	}

	/// Raw model identifier for the remote provider, or nil when unset.
	var articleSummaryModel: String? {
		get {
			return AppDefaults.articleSettingsStore.string(forKey: Key.articleSummaryModel)
		}
		set {
			if let newValue {
				AppDefaults.articleSettingsStore.set(newValue, forKey: Key.articleSummaryModel)
			} else {
				AppDefaults.articleSettingsStore.removeObject(forKey: Key.articleSummaryModel)
			}
			NotificationCenter.default.post(name: .articleSummarySettingsDidChange, object: self)
		}
	}

	@MainActor var articleSummarySettings: ArticleSummarySettings {
		ArticleSummarySettings(provider: articleSummaryProvider, endpoint: articleSummaryEndpoint, model: articleSummaryModel)
	}
}
