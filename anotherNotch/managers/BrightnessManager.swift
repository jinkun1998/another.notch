//  BrightnessManager.swift
//  anotherNotch
//
//  Created by JeanLouis on 08/22/24.

import AppKit

final class BrightnessManager: ObservableObject {
	static let shared = BrightnessManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var animatedBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			_ = await refreshBrightness(touchDate: false)
		}
	}

	@MainActor func setRelative(delta: Float) {
		Task { @MainActor in
			let starting = await client.currentScreenBrightness() ?? rawBrightness
			let target = max(0, min(1, starting + delta))
			let ok = await client.setScreenBrightness(target)
			if ok {
				publish(brightness: target, touchDate: true)
				AnotherNotchViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(target))
			} else {
				_ = await refreshBrightness(touchDate: false)
			}
		}
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		Task { @MainActor in
			let ok = await client.setScreenBrightness(clamped)
			if ok {
				publish(brightness: clamped, touchDate: true)
			} else {
				_ = await refreshBrightness(touchDate: false)
			}
		}
	}

	@MainActor private func refreshBrightness(touchDate: Bool) async -> Float? {
		guard let current = await client.currentScreenBrightness() else { return nil }
		publish(brightness: current, touchDate: touchDate)
		return current
	}

	@MainActor private func publish(brightness: Float, touchDate: Bool) {
		if rawBrightness != brightness || touchDate {
			if touchDate { lastChangeAt = Date() }
			rawBrightness = brightness
			animatedBrightness = brightness
		}
	}
}

// (DisplayServices helpers moved into XPC helper)

// MARK: - Keyboard Backlight Controller
final class KeyboardBacklightManager: ObservableObject {
	static let shared = KeyboardBacklightManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			if let current = await client.currentKeyboardBrightness() {
				publish(brightness: current, touchDate: false)
			}
		}
	}

	@MainActor func setRelative(delta: Float) {
		Task { @MainActor in
			let starting = await client.currentKeyboardBrightness() ?? rawBrightness
			let target = max(0, min(1, starting + delta))
			let ok = await client.setKeyboardBrightness(target)
			if ok {
				publish(brightness: target, touchDate: true)
			} else {
				refresh()
			}
			AnotherNotchViewCoordinator.shared.toggleSneakPeek(
				status: true,
				type: .backlight,
				value: CGFloat(target)
			)
		}
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		Task { @MainActor in
			let ok = await client.setKeyboardBrightness(clamped)
			if ok {
				publish(brightness: clamped, touchDate: true)
			} else {
				refresh()
			}
		}
	}

	private func publish(brightness: Float, touchDate: Bool) {
		DispatchQueue.main.async {
			if self.rawBrightness != brightness || touchDate {
				if touchDate { self.lastChangeAt = Date() }
				self.rawBrightness = brightness
			}
		}
	}
}
