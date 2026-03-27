import AppKit
import Carbon
import CoreText
import GhosttyKit
import DevHavenCore
import QuartzCore

@MainActor
final class GhosttyTerminalSurfaceView: NSView {
    private struct ScrollbarState {
        let total: UInt64
        let offset: UInt64
        let length: UInt64
    }

    let runtime: GhosttyRuntime
    let request: WorkspaceTerminalLaunchRequest
    let bridge: GhosttySurfaceBridge
    let extraEnvironment: [String: String]
    var onFocusChange: ((Bool) -> Void)?

    nonisolated(unsafe) private(set) var surface: ghostty_surface_t?
    private var surfaceRef: GhosttyRuntime.SurfaceReference?
    private var callbackContext: GhosttySurfaceCallbackContext?
    private var cellSize: NSSize = .zero
    private var backingCellSizeInPixels: NSSize = .zero
    private var attachmentState = GhosttySurfaceAttachmentState()
    private var trackingAreaRef: NSTrackingArea?
    private var keyTextAccumulator: [String]?
    private var markedText = NSMutableAttributedString()
    private var lastPerformKeyEvent: TimeInterval?
    private var focused = false
    private var lastScrollbar: ScrollbarState?
    private var focusRequestTask: Task<Void, Never>?
    var initializationError: Error?
    weak var scrollWrapper: GhosttySurfaceScrollView? {
        didSet {
            if let lastScrollbar {
                scrollWrapper?.updateScrollbar(
                    total: lastScrollbar.total,
                    offset: lastScrollbar.offset,
                    length: lastScrollbar.length
                )
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }

    init(
        runtime: GhosttyRuntime,
        request: WorkspaceTerminalLaunchRequest,
        bridge: GhosttySurfaceBridge,
        extraEnvironment: [String: String]
    ) {
        self.runtime = runtime
        self.request = request
        self.bridge = bridge
        self.extraEnvironment = extraEnvironment
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 640))

        do {
            let callbackContext = GhosttySurfaceCallbackContext(bridge: bridge)
            let surface = try runtime.createSurface(
                for: self,
                bridge: bridge,
                callbackContext: callbackContext,
                request: request,
                extraEnvironment: extraEnvironment
            )
            self.surface = surface
            self.callbackContext = callbackContext
            self.surfaceRef = runtime.registerSurface(
                surface,
                callbackContext: callbackContext
            )
        } catch {
            initializationError = error
        }
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        focusRequestTask?.cancel()
    }

    func tearDown() {
        cancelPendingFocusRequest()
        resignOwnedFirstResponderIfNeeded()
        callbackContext?.invalidate()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
            self.trackingAreaRef = nil
        }
        if let surfaceRef {
            runtime.unregisterSurface(surfaceRef)
            self.surfaceRef = nil
        }
        if let surface {
            ghostty_surface_free(surface)
            self.surface = nil
        }
        bridge.surface = nil
        bridge.surfaceView = nil
        callbackContext = nil
        scrollWrapper = nil
        lastScrollbar = nil
        focused = false
        attachmentState.prepareForContainerReuse()
    }

    func applyLatestModelState() {
        updateSurfaceMetrics()
    }

    func prepareForContainerReuse() {
        GhosttySurfaceLifecycleDiagnostics.shared.recordPrepareForContainerReuse(
            request: request,
            hasWindow: hasAttachedWindow,
            firstResponderOwned: ownsWindowFirstResponder,
            isSurfaceFocused: isCurrentlyFocused
        )
        cancelPendingFocusRequest()
        resignOwnedFirstResponderIfNeeded()
        focused = false
        attachmentState.prepareForContainerReuse()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let trackingAreaRef = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingAreaRef)
        self.trackingAreaRef = trackingAreaRef
    }

    override func layout() {
        super.layout()
        updateSurfaceMetrics()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelPendingFocusRequest()
        }
        updateSurfaceMetrics()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }
        updateSurfaceMetrics()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            cancelPendingFocusRequest()
            focusDidChange(true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            focusDidChange(false)
        }
        return result
    }

    func focusDidChange(_ focused: Bool) {
        guard surface != nil else { return }
        guard self.focused != focused else { return }
        self.focused = focused
        setSurfaceFocus(focused)
        onFocusChange?(focused)
    }

    private func setSurfaceFocus(_ focused: Bool) {
        guard let surface else { return }
        guard attachmentState.lastSurfaceFocus != focused else { return }
        attachmentState.lastSurfaceFocus = focused
        ghostty_surface_set_focus(surface, focused)
    }

    func requestFocus() {
        scheduleFocusRequest(delay: 0.05)
    }

    func setOcclusion(_ visible: Bool) {
        guard let surface else { return }
        guard attachmentState.lastOcclusion != visible else { return }
        attachmentState.lastOcclusion = visible
        ghostty_surface_set_occlusion(surface, visible)
    }

    private func cancelPendingFocusRequest() {
        focusRequestTask?.cancel()
        focusRequestTask = nil
    }

    private func scheduleFocusRequest(
        from previous: GhosttyTerminalSurfaceView? = nil,
        delay: TimeInterval
    ) {
        let maxDelay: TimeInterval = 0.5
        guard delay <= maxDelay else { return }
        let canRetryAfterThisAttempt = delay < maxDelay
        let nextDelay = min(delay * 2, maxDelay)
        focusRequestTask?.cancel()
        focusRequestTask = Task { @MainActor [weak self, weak previous] in
            guard let self else { return }
            try? await ContinuousClock().sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard let window = self.window else {
                guard self.surface != nil else {
                    self.focusRequestTask = nil
                    return
                }
                self.scheduleFocusRequest(from: previous, delay: nextDelay)
                return
            }
            if let previous, previous !== self {
                _ = previous.resignFirstResponder()
            }
            guard !Task.isCancelled else { return }
            if window.firstResponder === self {
                self.focusRequestTask = nil
                return
            }
            let didFocus = window.makeFirstResponder(self)
            if didFocus || self.surface == nil {
                self.focusRequestTask = nil
                return
            }
            guard canRetryAfterThisAttempt else {
                self.focusRequestTask = nil
                return
            }
            self.scheduleFocusRequest(from: previous, delay: nextDelay)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS)
    }

    override func mouseUp(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let surface else {
            super.rightMouseDown(with: event)
            return
        }
        if ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, event.ghosttyMods) {
            sendMousePosition(event)
            return
        }
        super.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else {
            super.rightMouseUp(with: event)
            return
        }
        if ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, event.ghosttyMods) {
            sendMousePosition(event)
            return
        }
        super.rightMouseUp(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        switch event.type {
        case .rightMouseDown:
            break
        case .leftMouseDown:
            guard event.modifierFlags.contains(.control) else { return nil }
            guard let surface else { return nil }
            guard !ghostty_surface_mouse_captured(surface) else { return nil }
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, event.ghosttyMods)
        default:
            return nil
        }

        guard let surface else { return nil }
        guard !ghostty_surface_mouse_captured(surface) else { return nil }
        window?.makeFirstResponder(self)

        let menu = NSMenu()
        if ghostty_surface_has_selection(surface) {
            menu.addItem(contextMenuItem(title: "Copy", action: #selector(copy(_:))))
        }
        menu.addItem(contextMenuItem(title: "Paste", action: #selector(paste(_:))))
        menu.addItem(.separator())
        menu.addItem(contextMenuItem(title: "Select All", action: #selector(selectAll(_:))))
        return menu
    }

    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS)
    }

    override func otherMouseUp(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE)
    }

    override func mouseMoved(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func mouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        let input = GhosttySurfaceScrollInput.make(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
            momentumPhase: event.momentumPhase
        )
        ghostty_surface_mouse_scroll(surface, input.deltaX, input.deltaY, input.mods)
    }

    override func keyDown(with event: NSEvent) {
        guard surface != nil else {
            interpretKeyEvents([event])
            return
        }

        let translationEvent = translatedEvent(for: event) ?? event
        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        let markedTextBefore = hasMarkedText()
        let keyboardIDBefore = markedTextBefore ? nil : keyboardLayoutID()

        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }
        lastPerformKeyEvent = nil
        interpretKeyEvents([translationEvent])

        if !markedTextBefore, keyboardIDBefore != keyboardLayoutID() {
            return
        }

        syncPreedit(clearIfNeeded: markedTextBefore)

        if let keyTextAccumulator, !keyTextAccumulator.isEmpty {
            for text in keyTextAccumulator {
                _ = sendKeyAction(
                    action,
                    event: event,
                    translationEvent: translationEvent,
                    text: text
                )
            }
            return
        }

        _ = sendKeyAction(
            action,
            event: event,
            translationEvent: translationEvent,
            text: translationEvent.ghosttyCharacters,
            composing: hasMarkedText() || markedTextBefore
        )
    }

    override func keyUp(with event: NSEvent) {
        _ = sendKeyAction(GHOSTTY_ACTION_RELEASE, event: event)
    }

    override func flagsChanged(with event: NSEvent) {
        let modifierMask: UInt32
        switch event.keyCode {
        case 0x39:
            modifierMask = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C:
            modifierMask = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E:
            modifierMask = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D:
            modifierMask = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36:
            modifierMask = GHOSTTY_MODS_SUPER.rawValue
        default:
            return
        }

        if hasMarkedText() {
            return
        }

        let mods = event.ghosttyMods
        var action = GHOSTTY_ACTION_RELEASE
        if (mods.rawValue & modifierMask) != 0 {
            let sidePressed: Bool
            switch event.keyCode {
            case 0x3C:
                sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERSHIFTKEYMASK) != 0
            case 0x3E:
                sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0
            case 0x3D:
                sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERALTKEYMASK) != 0
            case 0x36:
                sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0
            default:
                sidePressed = true
            }
            if sidePressed {
                action = GHOSTTY_ACTION_PRESS
            }
        }

        _ = sendKeyAction(action, event: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard let surface else { return false }
        guard focused else { return false }

        if GhosttySurfaceMenuShortcutRoutingPolicy.shouldAttemptMenuBeforeBindings(for: event),
           let menu = NSApp.mainMenu,
           menu.performKeyEquivalent(with: event) {
            return true
        }

        if let bindingFlags = bindingFlags(for: event, surface: surface) {
            if GhosttySurfaceMenuShortcutRoutingPolicy.shouldAttemptMenuAfterBinding(bindingFlags),
               let menu = NSApp.mainMenu,
               menu.performKeyEquivalent(with: event) {
                return true
            }
            keyDown(with: event)
            return true
        }

        guard let equivalent = equivalentKey(for: event) else {
            return false
        }

        guard let finalEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: event.locationInWindow,
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: equivalent,
            charactersIgnoringModifiers: equivalent,
            isARepeat: event.isARepeat,
            keyCode: event.keyCode
        ) else {
            return false
        }

        keyDown(with: finalEvent)
        return true
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        _ = replacementRange
        guard NSApp.currentEvent != nil else { return }
        guard surface != nil else { return }

        let text: String
        switch string {
        case let value as NSAttributedString:
            text = value.string
        case let value as String:
            text = value
        default:
            return
        }

        unmarkText()

        if var keyTextAccumulator {
            keyTextAccumulator.append(text)
            self.keyTextAccumulator = keyTextAccumulator
            return
        }

        debugSendText(text)
    }

    override func doCommand(by selector: Selector) {
        if let lastPerformKeyEvent,
           let current = NSApp.currentEvent,
           lastPerformKeyEvent == current.timestamp {
            NSApp.sendEvent(current)
            return
        }

        switch selector {
        case #selector(moveToBeginningOfDocument(_:)):
            performBindingAction("scroll_to_top")
        case #selector(moveToEndOfDocument(_:)):
            performBindingAction("scroll_to_bottom")
        default:
            break
        }
    }

    @IBAction func copy(_ sender: Any?) {
        performBindingAction("copy_to_clipboard")
    }

    @IBAction func paste(_ sender: Any?) {
        performBindingAction("paste_from_clipboard")
    }

    @IBAction func pasteSelection(_ sender: Any?) {
        performBindingAction("paste_from_selection")
    }

    @IBAction override func selectAll(_ sender: Any?) {
        performBindingAction("select_all")
    }

    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else {
            return NSRange()
        }
        return NSRange(location: 0, length: markedText.length)
    }

    func selectedRange() -> NSRange {
        guard let surface else {
            return NSRange()
        }

        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else {
            return NSRange()
        }
        defer { ghostty_surface_free_text(surface, &text) }
        return NSRange(location: Int(text.offset_start), length: Int(text.offset_len))
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        _ = selectedRange
        _ = replacementRange

        switch string {
        case let value as NSAttributedString:
            markedText = NSMutableAttributedString(attributedString: value)
        case let value as String:
            markedText = NSMutableAttributedString(string: value)
        default:
            return
        }

        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func unmarkText() {
        guard markedText.length > 0 else {
            return
        }
        markedText.mutableString.setString("")
        syncPreedit()
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSAttributedString? {
        guard let surface else { return nil }
        guard range.length > 0 else { return nil }

        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }

        var attributes: [NSAttributedString.Key: Any] = [:]
        if let fontRaw = ghostty_surface_quicklook_font(surface) {
            let font = Unmanaged<CTFont>.fromOpaque(fontRaw)
            attributes[.font] = font.takeUnretainedValue()
            font.release()
        }

        return NSAttributedString(
            string: String(cString: text.text),
            attributes: attributes
        )
    }

    func characterIndex(for point: NSPoint) -> Int {
        _ = point
        return 0
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range

        guard let surface else {
            return NSRect(x: frame.origin.x, y: frame.origin.y, width: 0, height: 0)
        }

        var x: Double = 0
        var y: Double = 0
        var width: Double = cellSize.width
        var height: Double = cellSize.height

        if range.length > 0, range != selectedRange() {
            var text = ghostty_text_s()
            if ghostty_surface_read_selection(surface, &text) {
                x = text.tl_px_x - 2
                y = text.tl_px_y + 2
                ghostty_surface_free_text(surface, &text)
            } else {
                ghostty_surface_ime_point(surface, &x, &y, &width, &height)
            }
        } else {
            ghostty_surface_ime_point(surface, &x, &y, &width, &height)
        }

        if range.length == 0, width > 0 {
            width = 0
            x += cellSize.width * Double(range.location + range.length)
        }

        let viewRect = NSMakeRect(
            x,
            frame.size.height - y,
            width,
            max(height, cellSize.height)
        )
        let windowRect = convert(viewRect, to: nil)
        guard let window else {
            return windowRect
        }
        return window.convertToScreen(windowRect)
    }

    func updateCellSize(_ backingCellSize: NSSize) {
        backingCellSizeInPixels = backingCellSize
        cellSize = convertFromBacking(backingCellSize)
        scrollWrapper?.updateSurfaceSize()
    }

    func updateScrollbar(total: UInt64, offset: UInt64, length: UInt64) {
        lastScrollbar = ScrollbarState(total: total, offset: offset, length: length)
        scrollWrapper?.updateScrollbar(total: total, offset: offset, length: length)
    }

    func currentCellSize() -> NSSize {
        cellSize
    }

    func updateSurfaceSize() {
        updateSurfaceMetrics()
    }

    private func updateSurfaceMetrics() {
        guard let surface else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        ghostty_surface_set_content_scale(surface, scale, scale)
        let lastBackingSize = attachmentState.lastBackingSize
        let backingSize = convertToBacking(bounds.size)
        let decision = GhosttySurfaceResizePolicy.resizeDecision(
            lastBackingSize: lastBackingSize,
            newBackingSize: backingSize,
            cellSizeInPixels: backingCellSizeInPixels
        )
        GhosttySurfaceLifecycleDiagnostics.shared.recordResizeDecision(
            request: request,
            lastBackingSize: lastBackingSize,
            newBackingSize: backingSize,
            cellSizeInPixels: backingCellSizeInPixels,
            applied: decision != nil,
            targetWidth: decision?.width,
            targetHeight: decision?.height
        )
        guard let decision else {
            return
        }
        attachmentState.lastBackingSize = backingSize
        ghostty_surface_set_size(surface, decision.width, decision.height)
    }

    private func sendKeyAction(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        translationEvent: NSEvent? = nil,
        text: String? = nil,
        composing: Bool = false
    ) -> Bool {
        guard let surface else { return false }
        var keyEvent = event.ghosttyKeyEvent(action, translationMods: translationEvent?.modifierFlags)
        keyEvent.composing = composing
        if let text,
           let first = text.utf8.first,
           first >= 0x20 {
            return text.withCString { pointer in
                keyEvent.text = pointer
                return ghostty_surface_key(surface, keyEvent)
            }
        }

        return ghostty_surface_key(surface, keyEvent)
    }

    private func translatedEvent(for event: NSEvent) -> NSEvent? {
        guard let surface else { return nil }

        let translationModsGhostty = eventModifierFlags(
            from: ghostty_surface_key_translation_mods(
                surface,
                event.ghosttyMods
            )
        )

        var translationMods = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translationModsGhostty.contains(flag) {
                translationMods.insert(flag)
            } else {
                translationMods.remove(flag)
            }
        }

        guard translationMods != event.modifierFlags else {
            return event
        }

        return NSEvent.keyEvent(
            with: event.type,
            location: event.locationInWindow,
            modifierFlags: translationMods,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: event.characters(byApplyingModifiers: translationMods) ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            isARepeat: event.isARepeat,
            keyCode: event.keyCode
        ) ?? event
    }

    private func sendMouseButton(_ event: NSEvent, state: ghostty_input_mouse_state_e) {
        guard let surface else { return }
        ghostty_surface_mouse_button(
            surface,
            state,
            event.ghosttyMouseButton,
            event.ghosttyMods
        )
        sendMousePosition(event)
    }

    private func sendMousePosition(_ event: NSEvent) {
        guard let surface else { return }
        let localPoint = convert(event.locationInWindow, from: nil)
        let point = GhosttySurfaceMousePosition.map(localPoint: localPoint, boundsHeight: bounds.height)
        ghostty_surface_mouse_pos(surface, point.x, point.y, event.ghosttyMods)
    }

    private func resignOwnedFirstResponderIfNeeded() {
        guard let window else {
            return
        }
        guard ownsWindowFirstResponder else {
            return
        }
        _ = window.makeFirstResponder(nil)
    }

    var hasAttachedWindow: Bool {
        window != nil
    }

    var windowIsKeyWindowForDiagnostics: Bool {
        window?.isKeyWindow ?? false
    }

    var ownsWindowFirstResponder: Bool {
        guard let window,
              let firstResponder = window.firstResponder as? NSView
        else {
            return false
        }
        return firstResponder === self || firstResponder.isDescendant(of: self)
    }

    func debugVisibleText() -> String {
        guard let surface else { return "" }
        var text = ghostty_text_s()
        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: GHOSTTY_POINT_SCREEN,
                coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                x: 0,
                y: 0
            ),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_SCREEN,
                coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                x: 0,
                y: 0
            ),
            rectangle: false
        )
        guard ghostty_surface_read_text(surface, selection, &text) else {
            return ""
        }
        defer { ghostty_surface_free_text(surface, &text) }
        return String(cString: text.text)
    }

    func debugSendText(_ text: String) {
        guard let surface else { return }
        let bytes = text.utf8CString
        guard bytes.count > 1 else { return }
        text.withCString { pointer in
            ghostty_surface_text(surface, pointer, UInt(bytes.count - 1))
        }
    }

    func debugHandleProcessClosed(processAlive: Bool) {
        bridge.closeSurface(processAlive: processAlive)
    }

    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }

        if markedText.length > 0 {
            let value = markedText.string
            let len = value.utf8CString.count
            guard len > 0 else { return }
            value.withCString { pointer in
                ghostty_surface_preedit(surface, pointer, UInt(len - 1))
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    private func keyboardLayoutID() -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        let value = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue()
        return value as String
    }

    private var isSurfaceFocused: Bool {
        focused
    }

    var isCurrentlyFocused: Bool {
        isSurfaceFocused
    }

    private func bindingFlags(
        for event: NSEvent,
        surface: ghostty_surface_t
    ) -> ghostty_binding_flags_e? {
        var keyEvent = event.ghosttyKeyEvent(
            GHOSTTY_ACTION_PRESS,
            translationMods: event.modifierFlags
        )
        var flags = ghostty_binding_flags_e(0)
        let isBinding = (event.characters ?? "").withCString { pointer in
            keyEvent.text = pointer
            return ghostty_surface_key_is_binding(surface, keyEvent, &flags)
        }
        return isBinding ? flags : nil
    }

    private func contextMenuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func equivalentKey(for event: NSEvent) -> String? {
        switch event.charactersIgnoringModifiers {
        case "\r":
            guard event.modifierFlags.contains(.control) else { return nil }
            return "\r"
        case "/":
            guard event.modifierFlags.contains(.control) else { return nil }
            guard event.modifierFlags.isDisjoint(with: [.shift, .command, .option]) else {
                return nil
            }
            return "_"
        default:
            if event.timestamp == 0 { return nil }
            if !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) {
                lastPerformKeyEvent = nil
                return nil
            }
            if let lastPerformKeyEvent {
                self.lastPerformKeyEvent = nil
                if lastPerformKeyEvent == event.timestamp {
                    return event.characters ?? ""
                }
            }
            lastPerformKeyEvent = event.timestamp
            return nil
        }
    }

    func performBindingAction(_ action: String) {
        guard let surface else { return }
        _ = action.withCString { pointer in
            ghostty_surface_binding_action(
                surface,
                pointer,
                UInt(action.lengthOfBytes(using: .utf8))
            )
        }
    }
}

extension GhosttyTerminalSurfaceView: @preconcurrency NSTextInputClient {}

struct GhosttyTerminalSurfaceConfiguration {
    var workingDirectory: String?
    var environmentVariables: [String: String]

    init(
        workingDirectory: String?,
        environmentVariables: [String: String]
    ) {
        self.workingDirectory = workingDirectory
        self.environmentVariables = environmentVariables
    }

    @MainActor
    func withCValue<T>(
        view: GhosttyTerminalSurfaceView,
        callbackContext: GhosttySurfaceCallbackContext,
        _ body: (inout ghostty_surface_config_s) throws -> T
    ) rethrows -> T {
        var configuration = ghostty_surface_config_new()
        configuration.userdata = Unmanaged.passUnretained(callbackContext).toOpaque()
        configuration.platform_tag = GHOSTTY_PLATFORM_MACOS
        configuration.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(view).toOpaque()
            )
        )
        configuration.scale_factor = Double(view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        configuration.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        let keys = Array(environmentVariables.keys)
        let values = keys.map { environmentVariables[$0] ?? "" }

        return try workingDirectory.withCString { workingDirectoryPointer in
            configuration.working_directory = workingDirectoryPointer
            return try keys.withCStrings { keyPointers in
                return try values.withCStrings { valuePointers in
                    var envVars = Array<ghostty_env_var_s>()
                    envVars.reserveCapacity(keys.count)
                    for index in 0..<keys.count {
                        envVars.append(
                            ghostty_env_var_s(
                                key: keyPointers[index],
                                value: valuePointers[index]
                            )
                        )
                    }

                    let envVarCount = envVars.count
                    return try envVars.withUnsafeMutableBufferPointer { buffer in
                        configuration.env_vars = buffer.baseAddress
                        configuration.env_var_count = envVarCount
                        return try body(&configuration)
                    }
                }
            }
        }
    }
}

extension Optional where Wrapped == String {
    func withCString<T>(_ body: (UnsafePointer<Int8>?) throws -> T) rethrows -> T {
        if let value = self {
            return try value.withCString(body)
        }
        return try body(nil)
    }
}

extension Array where Element == String {
    func withCStrings<T>(_ body: ([UnsafePointer<Int8>?]) throws -> T) rethrows -> T {
        if isEmpty {
            return try body([])
        }

        func helper(
            index: Int,
            accumulated: [UnsafePointer<Int8>?]
        ) throws -> T {
            if index == count {
                return try body(accumulated)
            }

            return try self[index].withCString { pointer in
                var accumulated = accumulated
                accumulated.append(pointer)
                return try helper(index: index + 1, accumulated: accumulated)
            }
        }

        return try helper(index: 0, accumulated: [])
    }
}

extension NSEvent {
    func ghosttyKeyEvent(
        _ action: ghostty_input_action_e,
        translationMods: NSEvent.ModifierFlags? = nil
    ) -> ghostty_input_key_s {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.keycode = UInt32(keyCode)
        keyEvent.mods = ghosttyMods
        keyEvent.consumed_mods = Self.ghosttyMods(
            from: (translationMods ?? modifierFlags).subtracting([.control, .command])
        )
        keyEvent.text = nil
        keyEvent.composing = false
        keyEvent.unshifted_codepoint = 0
        if type == .keyDown || type == .keyUp,
           let chars = characters(byApplyingModifiers: []),
           let scalar = chars.unicodeScalars.first {
            keyEvent.unshifted_codepoint = scalar.value
        }
        return keyEvent
    }

    var ghosttyMods: ghostty_input_mods_e {
        Self.ghosttyMods(from: modifierFlags)
    }

    static func ghosttyMods(from modifierFlags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var rawValue: UInt32 = GHOSTTY_MODS_NONE.rawValue
        if modifierFlags.contains(.shift) { rawValue |= GHOSTTY_MODS_SHIFT.rawValue }
        if modifierFlags.contains(.control) { rawValue |= GHOSTTY_MODS_CTRL.rawValue }
        if modifierFlags.contains(.option) { rawValue |= GHOSTTY_MODS_ALT.rawValue }
        if modifierFlags.contains(.command) { rawValue |= GHOSTTY_MODS_SUPER.rawValue }
        if modifierFlags.contains(.capsLock) { rawValue |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue)
    }

    var ghosttyMouseButton: ghostty_input_mouse_button_e {
        switch buttonNumber {
        case 0:
            return GHOSTTY_MOUSE_LEFT
        case 1:
            return GHOSTTY_MOUSE_RIGHT
        case 2:
            return GHOSTTY_MOUSE_MIDDLE
        case 3:
            return GHOSTTY_MOUSE_FOUR
        case 4:
            return GHOSTTY_MOUSE_FIVE
        default:
            return GHOSTTY_MOUSE_UNKNOWN
        }
    }

    var ghosttyCharacters: String? {
        guard let characters else {
            return nil
        }

        if characters.count == 1,
           let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return characters
    }
}

func eventModifierFlags(from mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
    if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
    if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
    if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
    if mods.rawValue & GHOSTTY_MODS_CAPS.rawValue != 0 { flags.insert(.capsLock) }
    return flags
}
