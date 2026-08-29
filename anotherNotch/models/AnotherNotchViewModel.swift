//
//  AnotherNotchViewModel.swift
//  anotherNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import Defaults
import SwiftUI

class AnotherNotchViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = AnotherNotchViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: AnotherNotchAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed {
        didSet {
            NotificationCenter.default.post(name: .notchContentSizeChanged, object: self)
        }
    }

    @Published var dragDetectorTargeting: Bool = false
    @Published var generalDropTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    var cancellables: Set<AnyCancellable> = []
    
    @Published var hideOnClosed: Bool = false

    @Published var edgeAutoOpenActive: Bool = false
    @Published var isHoveringCalendar: Bool = false
    @Published var isBatteryPopoverActive: Bool = false

    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize() {
        didSet {
            NotificationCenter.default.post(name: .notchContentSizeChanged, object: self)
        }
    }
    @Published var closedViewportSize: CGSize = getClosedNotchSize() {
        didSet {
            NotificationCenter.default.post(name: .notchContentSizeChanged, object: self)
        }
    }
    @Published var isClosingTransition = false {
        didSet {
            NotificationCenter.default.post(name: .notchContentSizeChanged, object: self)
        }
    }
    @Published var openingNotchSize: CGSize?
    @Published var closedNotchSize: CGSize = getClosedNotchSize()
    
    deinit {
        destroy()
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screenUUID: String? = nil) {
        animation = animationLibrary.animation

        super.init()
        
        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize
        closedViewportSize = notchSize

        Publishers.CombineLatest3($dropZoneTargeting, $dragDetectorTargeting, $generalDropTargeting)
            .map { shelf, drag, general in
                shelf || drag || general
            }
            .assign(to: \.anyDropZoneTargeting, on: self)
            .store(in: &cancellables)
        
        setupDetectorObserver()
    }
    
    private func setupDetectorObserver() {
        // Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()

        // Publisher for the current screen UUID (non-nil, distinct)
        let screenPublisher = $screenUUID
            .compactMap { $0 }
            .removeDuplicates()

        // Publisher for fullscreen status dictionary
        let fullscreenStatusPublisher = detector.$fullscreenStatus
            .removeDuplicates()

        // Combine all three: screen UUID, fullscreen status, and enabled setting
        Publishers.CombineLatest3(screenPublisher, fullscreenStatusPublisher, enabledPublisher)
            .map { screenUUID, fullscreenStatus, enabled in
                let isFullscreen = fullscreenStatus[screenUUID] ?? false
                return enabled && isFullscreen
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(.smooth) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return 0
        }

        if notchState == .open { return 0 }

        let menuBarHeight = currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight

        if currentHeight == 0 { return 0 }

        return max(0, menuBarHeight - currentHeight)
    }

    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        let screenFrame = getScreenFrame(screenUUID)
        if let frame = screenFrame {
            let interactionSize = notchState == .closed ? closedViewportSize : notchSize
            let baseY = frame.maxY - interactionSize.height
            let baseX = frame.midX - interactionSize.width / 2

            return position.y >= baseY && position.x >= baseX && position.x <= baseX + interactionSize.width
        }
        
        return false
    }

    func open() {
        openingNotchSize = closedViewportSize
        isClosingTransition = false
        self.notchState = .open
        self.notchSize = openNotchSize(for: coordinator.currentView, screenUUID: self.screenUUID)
        
        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()
    }

    func close() {
        // Do not close while a share picker or sharing service is active
        if SharingStateManager.shared.preventNotchClose {
            return
        }
        guard notchState == .open else {
            return
        }
        let closedSize = getClosedNotchSize(screenUUID: self.screenUUID)
        isClosingTransition = true
        self.closedNotchSize = closedSize
        self.notchState = .closed
        self.notchSize = closedSize
        self.isBatteryPopoverActive = false
        self.edgeAutoOpenActive = false

        if !coordinator.openLastTabByDefault {
            coordinator.currentView = .home
        } else if FeatureModuleRegistry.shared.isAvailable(.shelf),
                  !ShelfStateViewModel.shared.isEmpty,
                  Defaults[.openShelfByDefault]
        {
            coordinator.currentView = .shelf
        }
    }

    func closeHello() {
        Task { @MainActor in
            withAnimation(animationLibrary.animation) {
                coordinator.helloAnimationRunning = false
            }
            NotificationCenter.default.post(name: .welcomeAnimationDidFinish, object: nil)
        }
    }
}
