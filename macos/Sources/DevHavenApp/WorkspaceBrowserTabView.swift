import SwiftUI
import WebKit
import DevHavenCore

struct WorkspaceBrowserPaneItemView: View {
    let itemID: String
    let state: WorkspaceBrowserState
    @ObservedObject var model: WorkspaceBrowserHostModel
    let onFocusBrowserItem: () -> Void
    let isFocused: Bool
    @FocusState private var isAddressBarFocused: Bool
    @State private var addressBarText: String

    init(
        itemID: String,
        state: WorkspaceBrowserState,
        model: WorkspaceBrowserHostModel,
        isFocused: Bool,
        onFocusBrowserItem: @escaping () -> Void
    ) {
        self.itemID = itemID
        self.state = state
        self.model = model
        self.isFocused = isFocused
        self.onFocusBrowserItem = onFocusBrowserItem
        _addressBarText = State(initialValue: state.urlString)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            WorkspaceBrowserWebView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        activateBrowserContent()
                    }
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NativeTheme.window)
        .onAppear {
            model.setPointerInteractionHandler {
                activateBrowserContent()
            }
            syncAddressBarText()
            DispatchQueue.main.async {
                if isFocused {
                    focusPrimaryInput()
                }
            }
        }
        .onDisappear {
            model.setPointerInteractionHandler(nil)
        }
        .onChange(of: model.currentURLString) { _, _ in
            syncAddressBarText()
        }
        .onChange(of: state.urlString) { _, _ in
            syncAddressBarText()
        }
        .onChange(of: isFocused) { _, focused in
            guard focused else { return }
            DispatchQueue.main.async {
                focusPrimaryInput()
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            button(
                title: "后退",
                systemImage: "chevron.left",
                disabled: !model.canGoBack,
                action: {
                    activateBrowserContent()
                    model.goBack()
                }
            )
            button(
                title: "前进",
                systemImage: "chevron.right",
                disabled: !model.canGoForward,
                action: {
                    activateBrowserContent()
                    model.goForward()
                }
            )
            button(
                title: model.isLoading ? "停止加载" : "重新加载",
                systemImage: model.isLoading ? "xmark" : "arrow.clockwise",
                disabled: false,
                action: {
                    activateBrowserContent()
                    if model.isLoading {
                        model.stopLoading()
                    } else {
                        model.reload()
                    }
                }
            )

            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(NativeTheme.textSecondary)
                TextField("输入 URL 或搜索", text: $addressBarText)
                    .textFieldStyle(.plain)
                    .focused($isAddressBarFocused)
                    .onTapGesture {
                        onFocusBrowserItem()
                    }
                    .onSubmit {
                        model.navigate(to: addressBarText)
                        DispatchQueue.main.async {
                            model.focusWebView()
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NativeTheme.surface)
            .clipShape(.rect(cornerRadius: 10))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NativeTheme.window)
    }

    private func button(
        title: String,
        systemImage: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(disabled ? NativeTheme.textSecondary.opacity(0.5) : NativeTheme.textPrimary)
                .frame(width: 30, height: 30)
                .background(NativeTheme.surface)
                .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(title)
    }

    private func syncAddressBarText() {
        guard !isAddressBarFocused else {
            return
        }
        let candidate = model.currentURLString.isEmpty ? state.urlString : model.currentURLString
        guard addressBarText != candidate else {
            return
        }
        addressBarText = candidate
    }

    private func activateBrowserContent() {
        onFocusBrowserItem()
        DispatchQueue.main.async {
            model.focusWebView()
        }
    }

    private func focusPrimaryInput() {
        onFocusBrowserItem()
        if model.currentURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isAddressBarFocused = true
        } else {
            model.focusWebView()
        }
    }
}

private struct WorkspaceBrowserWebView: NSViewRepresentable {
    @ObservedObject var model: WorkspaceBrowserHostModel

    func makeNSView(context: Context) -> ContainerView {
        let view = ContainerView()
        view.host(model.webView)
        return view
    }

    func updateNSView(_ nsView: ContainerView, context: Context) {
        nsView.host(model.webView)
    }

    final class ContainerView: NSView {
        private weak var hostedWebView: WKWebView?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        func host(_ webView: WKWebView) {
            if hostedWebView !== webView {
                hostedWebView?.removeFromSuperview()
                hostedWebView = webView
                addSubview(webView)
            }
            webView.frame = bounds
            needsLayout = true
        }

        override func layout() {
            super.layout()
            hostedWebView?.frame = bounds
        }
    }
}
