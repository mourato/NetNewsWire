//
//  Miniflux.swift
//  Account
//
//  Created by Dave Marquard on 7/7/26.
//  Copyright © 2026 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import os

public enum Miniflux {
	// Convention with this logger is to put "Miniflux: " at the beginning of each message.
	static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NetNewsWire", category: "Miniflux")

	public static func normalizedEndpointURL(from string: String) -> URL? {
		var value = string.trimmingWhitespace
		guard !value.isEmpty else {
			return nil
		}

		if !value.contains("://") {
			value = "https://" + value
		}

		guard var components = URLComponents(string: value),
			let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
			let host = components.host, !host.isEmpty,
			components.user == nil, components.password == nil,
			components.query == nil, components.fragment == nil else {
			return nil
		}

		components.scheme = scheme
		components.host = host.lowercased()
		components.path = components.path.replacingTrailingMinifluxAPIVersion()
		while components.path.count > 1, components.path.hasSuffix("/") {
			components.path.removeLast()
		}

		return components.url
	}

	public static func canReplaceIdentity(existingEndpoint: URL?, existingUsername: String?, validatedEndpoint: URL, validatedUsername: String) -> Bool {
		guard let existingEndpoint,
			let existingUsername,
			let normalizedExisting = normalizedEndpointURL(from: existingEndpoint.absoluteString),
			let normalizedValidated = normalizedEndpointURL(from: validatedEndpoint.absoluteString) else {
			return false
		}
		return normalizedExisting == normalizedValidated && existingUsername == validatedUsername
	}
}

private extension String {
	func replacingTrailingMinifluxAPIVersion() -> String {
		var path = self
		while path.count > 1, path.hasSuffix("/") {
			path.removeLast()
		}
		if path == "/" {
			return ""
		}
		if path == "/v1" {
			return ""
		}
		if path.hasSuffix("/v1") {
			path.removeLast(3)
		}
		return path
	}
}
