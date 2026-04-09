import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DevHavenCore

struct MainContentView: View {
    private enum FocusableField: Hashable {
        case search
    }

    private enum ProjectListMetrics {
        static let projectColumnWidth: CGFloat = 250
        static let notesColumnWidth: CGFloat = 280
        static let gitSummaryColumnWidth: CGFloat = 220
        static let dateColumnWidth: CGFloat = 96
        static let statusColumnWidth: CGFloat = 74
    }

    @Bindable var viewModel: NativeAppViewModel
    @State private var isFilterPopoverPresented = false
    @State private var isDirectoryDropTargeted = false
    @State private var isDirectoryDropActionDialogPresented = false
    @State private var pendingDroppedDirectoryURLs: [URL] = []
    @FocusState private var focusedField: FocusableField?

    private let listColumns = [
        GridItem(.flexible(minimum: 220), spacing: 14),
        GridItem(.flexible(minimum: 220), spacing: 14),
        GridItem(.flexible(minimum: 220), spacing: 14),
        GridItem(.flexible(minimum: 220), spacing: 14),
    ]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(NativeTheme.surface)

            if viewModel.filteredProjects.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    if viewModel.projectListViewMode == .card {
                        LazyVGrid(columns: listColumns, spacing: 16) {
                            ForEach(viewModel.filteredProjects) { project in
                                projectCard(project)
                            }
                        }
                        .padding(18)
                    } else {
                        LazyVStack(spacing: 6) {
                            projectListHeader
                            ForEach(viewModel.filteredProjects) { project in
                                projectRow(project)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                }
                .background(NativeTheme.window)
            }
        }
        .overlay {
            if isDirectoryDropTargeted {
                directoryDropOverlay
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isDirectoryDropTargeted)
        .confirmationDialog(
            "导入拖入的文件夹",
            isPresented: $isDirectoryDropActionDialogPresented,
            titleVisibility: .visible
        ) {
            Button("添加工作目录（扫描项目）") {
                submitDroppedDirectoryImport(.addDirectory)
            }
            Button("直接添加为项目") {
                submitDroppedDirectoryImport(.addProjects)
            }
            Button("取消", role: .cancel) {
                clearPendingDroppedDirectories()
            }
        } message: {
            Text(directoryDropConfirmationMessage)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDirectoryDropTargeted, perform: handleDirectoryDrop)
        .onAppear {
            requestInitialSearchFocus()
        }
        .onChange(of: isDirectoryDropActionDialogPresented) { _, isPresented in
            if !isPresented {
                pendingDroppedDirectoryURLs = []
            }
        }
    }

    private var directoryDropOverlay: some View {
        ZStack {
            NativeTheme.window.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(NativeTheme.accent)
                Text("拖入文件夹以导入项目")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                Text("松开后可选择扫描目录，或直接把文件夹添加为项目。")
                    .font(.callout)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .background(NativeTheme.surface.opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        NativeTheme.accent.opacity(0.95),
                        style: StrokeStyle(lineWidth: 2, dash: [10, 8])
                    )
            )
            .clipShape(.rect(cornerRadius: 18))
            .padding(28)
        }
        .allowsHitTesting(false)
    }

    private var directoryDropConfirmationMessage: String {
        switch pendingDroppedDirectoryURLs.count {
        case 0:
            "请选择导入方式。"
        case 1:
            "将导入 1 个文件夹：\(pendingDroppedDirectoryURLs[0].lastPathComponent)"
        default:
            "将导入 \(pendingDroppedDirectoryURLs.count) 个文件夹。"
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                toolbarIcon("waveform.path.ecg", action: { viewModel.revealDashboard() })
                toolbarIcon("terminal", action: { viewModel.enterOrResumeWorkspace() })
                toolbarIcon("gearshape", action: { viewModel.revealSettings() })
                refreshProjectCatalogButton

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(NativeTheme.textSecondary)
                    TextField("搜索项目、备注...", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                        .foregroundStyle(NativeTheme.textPrimary)
                        .focused($focusedField, equals: .search)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(NativeTheme.elevated)
                .clipShape(.rect(cornerRadius: 10))
                .frame(maxWidth: 360)

                Spacer(minLength: 10)

                Button {
                    isFilterPopoverPresented.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("筛选")
                        if activeFilterCount > 0 {
                            Text("\(activeFilterCount)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(NativeTheme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(NativeTheme.accent.opacity(0.14))
                                .clipShape(.capsule)
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(activeFilterCount > 0 ? NativeTheme.textPrimary : NativeTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(NativeTheme.elevated)
                    .clipShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isFilterPopoverPresented, arrowEdge: .top) {
                    filterPopover
                }

                Picker("视图模式", selection: Binding(
                    get: { viewModel.projectListViewMode },
                    set: { viewModel.updateProjectListViewMode($0) }
                )) {
                    Label("卡片", systemImage: "square.grid.2x2.fill").tag(ProjectListViewMode.card)
                    Label("列表", systemImage: "list.bullet").tag(ProjectListViewMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            if let filterSummaryText {
                HStack(spacing: 10) {
                    Label(filterSummaryText, systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                        .lineLimit(1)
                    Button("恢复默认") {
                        resetProjectFilters()
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(NativeTheme.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(NativeTheme.elevated.opacity(0.82))
                .clipShape(.rect(cornerRadius: 10))
            }
        }
    }

    private var refreshProjectCatalogButton: some View {
        Button(action: viewModel.refresh) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(NativeTheme.elevated)

                if viewModel.isRefreshingProjectCatalog {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                        .foregroundStyle(NativeTheme.textSecondary)
                }
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(viewModel.isRefreshingProjectCatalog)
        .help(viewModel.isRefreshingProjectCatalog ? "正在刷新项目列表" : "刷新项目")
        .accessibilityLabel(viewModel.isRefreshingProjectCatalog ? "正在刷新项目列表" : "刷新项目")
    }

    private var emptyStateView: some View {
        Group {
            if viewModel.isDirectProjectsDirectorySelected {
                ContentUnavailableView(
                    "当前没有直接添加项目",
                    systemImage: "square.stack.3d.up",
                    description: Text("可通过目录操作中的“直接添加为项目”导入项目。")
                )
            } else if viewModel.visibleProjects.isEmpty {
                if viewModel.recycleBinItems.isEmpty {
                    ContentUnavailableView(
                        "暂未添加项目目录",
                        systemImage: "folder.badge.plus",
                        description: Text("请添加工作目录或直接导入项目。")
                    )
                } else {
                    ContentUnavailableView(
                        "当前没有可见项目",
                        systemImage: "trash",
                        description: Text("可在回收站恢复隐藏项目。")
                    )
                }
            } else {
                ContentUnavailableView(
                    "没有匹配项目",
                    systemImage: "magnifyingglass",
                    description: Text("可以搜索项目名 / 路径 / 备注 / 标签 / Git 摘要，或者切换目录 / 标签 / Git 筛选。")
                )
            }
        }
        .foregroundStyle(NativeTheme.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleDirectoryDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else {
            return false
        }

        Task { @MainActor in
            let droppedURLs = await loadDroppedFileURLs(from: fileProviders)
            let directoryURLs = droppedURLs.filter {
                $0.hasDirectoryPath || Self.isDirectoryURL($0)
            }
            guard !directoryURLs.isEmpty else {
                viewModel.errorMessage = "仅支持拖入文件夹目录。"
                return
            }
            pendingDroppedDirectoryURLs = uniqueStandardizedDirectoryURLs(directoryURLs)
            isDirectoryDropActionDialogPresented = !pendingDroppedDirectoryURLs.isEmpty
        }
        return true
    }

    @MainActor
    private func submitDroppedDirectoryImport(_ action: ProjectDirectoryImportAction) {
        let urls = pendingDroppedDirectoryURLs
        clearPendingDroppedDirectories()
        guard !urls.isEmpty else {
            return
        }

        ProjectImportDiagnostics.shared.recordImporterCallback(
            action: action.diagnosticsAction,
            urlCount: urls.count
        )
        Task { @MainActor in
            await ProjectDirectoryImportSupport.withSecurityScopedAccess(urls, action: action) {
                await ProjectDirectoryImportSupport.performImport(
                    urls: urls,
                    action: action,
                    viewModel: viewModel
                )
            }
        }
    }

    private func clearPendingDroppedDirectories() {
        pendingDroppedDirectoryURLs = []
        isDirectoryDropActionDialogPresented = false
    }

    private func loadDroppedFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls = [URL]()
        for provider in providers {
            if let url = await loadDroppedFileURL(from: provider) {
                urls.append(url)
            }
        }
        return urls
    }

    private func loadDroppedFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                continuation.resume(returning: Self.resolveDroppedFileURL(from: item))
            }
        }
    }

    private func uniqueStandardizedDirectoryURLs(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        return urls.compactMap { url in
            let standardizedURL = url.standardizedFileURL
            let path = standardizedURL.path()
            guard !path.isEmpty, seenPaths.insert(path).inserted else {
                return nil
            }
            return standardizedURL
        }
    }

    private nonisolated static func isDirectoryURL(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        guard let resourceValues = try? url.resourceValues(forKeys: keys) else {
            return false
        }
        return resourceValues.isDirectory == true
    }

    private nonisolated static func resolveDroppedFileURL(from item: NSSecureCoding?) -> URL? {
        switch item {
        case let url as URL:
            url
        case let nsURL as NSURL:
            nsURL as URL
        case let data as Data:
            URL(dataRepresentation: data, relativeTo: nil)
        case let string as String:
            URL(string: string)
        default:
            nil
        }
    }

    private func projectCard(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(projectSearchHighlightedText(project.name, query: viewModel.searchQuery))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 10)
                HStack(spacing: 10) {
                    cardActionIcon("folder") { openInFinder(project.path) }
                    cardActionIcon(viewModel.snapshot.appState.favoriteProjectPaths.contains(project.path) ? "star.fill" : "star") {
                        viewModel.toggleProjectFavorite(project.path)
                    }
                    cardActionIcon("trash") { viewModel.moveProjectToRecycleBin(project.path) }
                    if viewModel.isDirectProjectsDirectorySelected {
                        cardActionIcon("minus.circle") { viewModel.removeDirectProject(project.path) }
                    }
                }
            }

            Text(projectSearchHighlightedText("~/\(compactDisplayPath(project.path))", query: viewModel.searchQuery))
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
                .lineLimit(1)

            if let notesSummary = project.notesSummary {
                Text(projectSearchHighlightedText(notesSummary, query: viewModel.searchQuery))
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textPrimary.opacity(0.82))
                    .lineLimit(2)
            }

            HStack {
                Label(dateString(project.mtime), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
                Spacer()
                if project.gitCommits > 0 {
                    Text("\(project.gitCommits) 次提交")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(NativeTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(NativeTheme.accent.opacity(0.14))
                        .clipShape(.rect(cornerRadius: 8))
                } else if project.isGitRepository {
                    Text("Git 项目")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.accent)
                } else {
                    Text("非 Git 项目")
                        .font(.caption)
                        .foregroundStyle(NativeTheme.textSecondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(NativeTheme.elevated)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isProjectDetailSelectionActive(project) ? NativeTheme.accent.opacity(0.8) : NativeTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 14))
        .contentShape(.rect(cornerRadius: 14))
        .onTapGesture(count: 2) {
            viewModel.enterWorkspace(project.path)
        }
        .onTapGesture {
            viewModel.selectProject(project.path)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .help("单击查看详情，双击进入工作区")
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(projectSearchHighlightedText(project.name, query: viewModel.searchQuery))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NativeTheme.textPrimary)
                    .lineLimit(1)
                Text(projectSearchHighlightedText(project.path, query: viewModel.searchQuery))
                    .font(.caption2)
                    .foregroundStyle(NativeTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: ProjectListMetrics.projectColumnWidth, alignment: .leading)

            projectRowNotesColumn(project)

            Text(projectSearchHighlightedText(project.isGitRepository ? (project.gitLastCommitMessage ?? "暂无提交摘要") : "--", query: viewModel.searchQuery))
                .font(.caption2)
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(width: ProjectListMetrics.gitSummaryColumnWidth, alignment: .leading)
                .lineLimit(2)
            Text(dateString(project.mtime))
                .font(.caption2)
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(width: ProjectListMetrics.dateColumnWidth, alignment: .leading)

            projectRowStatusBadge(project)
                .frame(width: ProjectListMetrics.statusColumnWidth, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                rowActionIcon("folder") { openInFinder(project.path) }
                rowActionIcon(viewModel.snapshot.appState.favoriteProjectPaths.contains(project.path) ? "star.fill" : "star") {
                    viewModel.toggleProjectFavorite(project.path)
                }
                rowActionIcon("trash") { viewModel.moveProjectToRecycleBin(project.path) }
                if viewModel.isDirectProjectsDirectorySelected {
                    rowActionIcon("minus.circle") { viewModel.removeDirectProject(project.path) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isProjectDetailSelectionActive(project) ? NativeTheme.accent.opacity(0.12) : Color.clear)
        .clipShape(.rect(cornerRadius: 10))
        .contentShape(.rect(cornerRadius: 10))
        .onTapGesture(count: 2) {
            viewModel.enterWorkspace(project.path)
        }
        .onTapGesture {
            viewModel.selectProject(project.path)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .help("单击查看详情，双击进入工作区")
    }

    private var projectListHeader: some View {
        HStack(spacing: 12) {
            sortableProjectListHeaderLabel(
                projectColumnTitle,
                isActive: isNameSortActive,
                action: { toggleSort(for: .name) }
            )
                .frame(width: ProjectListMetrics.projectColumnWidth, alignment: .leading)
            projectListHeaderLabel("备注")
                .frame(width: ProjectListMetrics.notesColumnWidth, alignment: .leading)
            projectListHeaderLabel("Git 摘要")
                .frame(width: ProjectListMetrics.gitSummaryColumnWidth, alignment: .leading)
            sortableProjectListHeaderLabel(
                modifiedColumnTitle,
                isActive: isModifiedTimeSortActive,
                action: { toggleSort(for: .modifiedTime) }
            )
                .frame(width: ProjectListMetrics.dateColumnWidth, alignment: .leading)
            projectListHeaderLabel("状态")
                .frame(width: ProjectListMetrics.statusColumnWidth, alignment: .leading)
            Spacer(minLength: 0)
            projectListHeaderLabel("操作")
                .frame(width: 110, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    private func projectListHeaderLabel(_ title: String, isActive: Bool = false) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isActive ? NativeTheme.textPrimary : NativeTheme.textSecondary)
            .textCase(.uppercase)
    }

    private func sortableProjectListHeaderLabel(
        _ title: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                projectListHeaderLabel(title, isActive: isActive)
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isActive ? NativeTheme.accent : NativeTheme.textSecondary.opacity(0.6))
            }
            .contentShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("点击切换排序")
    }

    private func projectRowNotesColumn(_ project: Project) -> some View {
        let notesSummary = project.notesSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Group {
            if let notesSummary, !notesSummary.isEmpty {
                Text(projectSearchHighlightedText(notesSummary, query: viewModel.searchQuery))
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textPrimary.opacity(0.86))
                    .lineLimit(2)
            } else {
                Text("暂无备注")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary.opacity(0.78))
                    .lineLimit(1)
            }
        }
        .frame(width: ProjectListMetrics.notesColumnWidth, alignment: .leading)
    }

    private func projectRowStatusBadge(_ project: Project) -> some View {
        let title: String
        let foreground: Color
        let background: Color

        if project.gitCommits > 0 {
            title = "\(project.gitCommits) 提交"
            foreground = NativeTheme.accent
            background = NativeTheme.accent.opacity(0.14)
        } else if project.isGitRepository {
            title = "Git"
            foreground = NativeTheme.accent
            background = NativeTheme.accent.opacity(0.14)
        } else {
            title = "非 Git"
            foreground = NativeTheme.textSecondary
            background = NativeTheme.surface
        }

        return Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(background)
            .clipShape(.rect(cornerRadius: 8))
    }

    private func toolbarIcon(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body)
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background(NativeTheme.elevated)
                .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func isProjectDetailSelectionActive(_ project: Project) -> Bool {
        guard !viewModel.isWorkspacePresented else {
            return false
        }
        return viewModel.selectedProject?.path == project.path
    }

    private var activeFilterCount: Int {
        var count = 0
        if viewModel.selectedGitFilter != .all {
            count += 1
        }
        if viewModel.selectedDateFilter != .all {
            count += 1
        }
        if viewModel.projectListSortOrder != .defaultOrder {
            count += 1
        }
        return count
    }

    private var filterSummaryText: String? {
        guard activeFilterCount > 0 else {
            return nil
        }

        var parts: [String] = []
        if viewModel.selectedGitFilter != .all {
            parts.append(viewModel.selectedGitFilter.title)
        }
        if viewModel.selectedDateFilter != .all {
            parts.append(viewModel.selectedDateFilter.title)
        }
        if viewModel.projectListSortOrder != .defaultOrder {
            parts.append(viewModel.projectListSortOrder.title)
        }
        return parts.joined(separator: " · ")
    }

    private var isNameSortActive: Bool {
        viewModel.projectListSortOrder == .nameAscending
            || viewModel.projectListSortOrder == .nameDescending
    }

    private var isModifiedTimeSortActive: Bool {
        viewModel.projectListSortOrder == .modifiedNewestFirst
            || viewModel.projectListSortOrder == .modifiedOldestFirst
    }

    private var projectColumnTitle: String {
        switch viewModel.projectListSortOrder {
        case .nameAscending:
            return "项目 ↑"
        case .nameDescending:
            return "项目 ↓"
        default:
            return "项目"
        }
    }

    private var modifiedColumnTitle: String {
        switch viewModel.projectListSortOrder {
        case .modifiedNewestFirst:
            return "修改时间 ↓"
        case .modifiedOldestFirst:
            return "修改时间 ↑"
        default:
            return "修改时间"
        }
    }

    private var filterPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("筛选与排序")
                    .font(.headline)
                    .foregroundStyle(NativeTheme.textPrimary)
                Text("把筛选条件和排序放到一个地方，平时让顶部更干净。")
                    .font(.caption)
                    .foregroundStyle(NativeTheme.textSecondary)
            }

            filterSection(title: "项目类型") {
                ForEach(NativeGitFilter.allCases) { filter in
                    filterOptionButton(
                        title: filter.title,
                        isSelected: viewModel.selectedGitFilter == filter
                    ) {
                        viewModel.updateGitFilter(filter)
                    }
                }
            }

            filterSection(title: "时间范围") {
                ForEach(NativeDateFilter.allCases) { filter in
                    filterOptionButton(
                        title: filter.title,
                        isSelected: viewModel.selectedDateFilter == filter
                    ) {
                        viewModel.updateDateFilter(filter)
                    }
                }
            }

            filterSection(title: "排序") {
                ForEach(ProjectListSortOrder.allCases) { order in
                    filterOptionButton(
                        title: order.title,
                        isSelected: viewModel.projectListSortOrder == order
                    ) {
                        viewModel.updateProjectListSortOrder(order)
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button("恢复默认") {
                    resetProjectFilters()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(NativeTheme.accent)

                Spacer(minLength: 0)

                Button("完成") {
                    isFilterPopoverPresented = false
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeTheme.accent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(NativeTheme.window)
    }

    private func filterSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeTheme.textSecondary)
            content()
        }
    }

    private func filterOptionButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? NativeTheme.accent : NativeTheme.textSecondary.opacity(0.7))
                Text(title)
                    .foregroundStyle(NativeTheme.textPrimary)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? NativeTheme.accent.opacity(0.12) : NativeTheme.elevated)
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func resetProjectFilters() {
        viewModel.updateGitFilter(.all)
        viewModel.updateDateFilter(.all)
        viewModel.updateProjectListSortOrder(.defaultOrder)
    }

    private func toggleSort(for column: ProjectListSortableColumn) {
        viewModel.updateProjectListSortOrder(viewModel.projectListSortOrder.toggled(for: column))
    }

    private func requestInitialSearchFocus() {
        DispatchQueue.main.async {
            focusedField = .search
        }
    }

    private func cardActionIcon(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption)
                .foregroundStyle(NativeTheme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func rowActionIcon(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption2)
                .foregroundStyle(NativeTheme.textSecondary)
                .frame(width: 26, height: 26)
                .background(NativeTheme.elevated)
                .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func compactDisplayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return path.replacingOccurrences(of: home + "/", with: "")
        }
        return path
    }

    private func dateString(_ swiftDate: SwiftDate) -> String {
        guard let date = swiftDateToDate(swiftDate) else {
            return "--"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }

    private func openInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
