import SwiftUI

struct GhosttySurfaceSearchOverlay: View {
    let surfaceView: GhosttyTerminalSurfaceView
    @Bindable var state: GhosttySurfaceState

    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchText: String

    init(surfaceView: GhosttyTerminalSurfaceView) {
        self.surfaceView = surfaceView
        self._state = Bindable(surfaceView.bridge.state)
        self._searchText = State(initialValue: surfaceView.bridge.state.searchNeedle ?? "")
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("搜索终端内容…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    navigateSearchNext()
                }

            matchLabel

            Button("上一个") {
                navigateSearchPrevious()
            }
            .buttonStyle(.borderless)

            Button("下一个") {
                navigateSearchNext()
            }
            .buttonStyle(.borderless)

            Button("关闭") {
                closeSearch()
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 8, y: 2)
        .padding(12)
        .onAppear {
            focusSearchField()
            emitSearch(searchText)
        }
        .onChange(of: searchText) { _, newValue in
            emitSearch(newValue)
        }
        .onChange(of: state.searchNeedle) { _, newValue in
            guard let newValue else {
                return
            }
            if newValue != searchText {
                searchText = newValue
            }
            focusSearchField()
        }
        .onChange(of: state.searchFocusCount) { _, _ in
            focusSearchField()
        }
        .onExitCommand {
            closeSearch()
        }
    }

    @ViewBuilder
    private var matchLabel: some View {
        if let selected = state.searchSelected {
            let totalLabel = state.searchTotal.map(String.init) ?? "?"
            Text("\(selected + 1)/\(totalLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let total = state.searchTotal {
            Text("-/\(total)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func emitSearch(_ needle: String) {
        surfaceView.performBindingAction("search:\(needle)")
    }

    private func navigateSearchNext() {
        surfaceView.performBindingAction("navigate_search:next")
    }

    private func navigateSearchPrevious() {
        surfaceView.performBindingAction("navigate_search:previous")
    }

    private func closeSearch() {
        surfaceView.performBindingAction("end_search")
        surfaceView.requestFocus()
    }

    private func focusSearchField() {
        isSearchFieldFocused = false
        Task { @MainActor in
            await Task.yield()
            isSearchFieldFocused = true
        }
    }
}
