import AppKit
import ConductorCore
import SwiftUI

/// Skills Manager：中央库 + 多 Agent 同步 + 本机发现。
/// 后端来自 ConductorCore.SkillManagerEngine；旧 SkillCatalog 仍保留给兼容测试。
struct SkillsManagerView: View {
    @ObservedObject private var configStore = ConfigStore.shared
    @State private var engine: SkillManagerEngine?
    @State private var skills: [ManagedSkill] = []
    @State private var tools: [SkillToolInfo] = []
    @State private var presets: [SkillPreset] = []
    @State private var presetSummaries: [SkillPresetSummary] = []
    @State private var projects: [SkillProject] = []
    @State private var projectTargets: [SkillProjectTargetRecord] = []
    @State private var projectSkills: [String: [ProjectSkillInfo]] = [:]
    @State private var auditEntries: [SkillAuditEntry] = []
    @State private var scanResult: SkillScanResult?
    @State private var selectedSection: SkillManagerSection = .command
    @State private var query = ""
    @State private var syncMode = "symlink"
    @State private var newPresetName = ""
    @State private var tagDraft = ""
    @State private var sourceFilters: Set<String> = []
    @State private var tagFilters: Set<String> = []
    @State private var skillsShQuery = ""
    @State private var skillsShBoard = "hot"
    @State private var skillsShSkills: [SkillsShSkill] = []
    @State private var skillsShLoading = false
    @State private var skillsShError: String?
    @State private var gitInstallURL = ""
    @State private var gitInstallSubdirectory = ""
    @State private var gitInstallRef = ""
    @State private var selectedSkillIDs: Set<String> = []
    @State private var loading = false
    @State private var loadingText = ""
    @State private var expandedSkillID: String?
    @State private var inspectedSkillID: String?
    @State private var detailSkillID: String?
    @State private var detailTab: SkillDetailTab = .overview
    @State private var expandedPresetID: String?
    @State private var expandedProjectID: String?
    @State private var skillDocuments: [String: SkillDocument] = [:]
    @State private var skillFiles: [String: [SkillFileInfo]] = [:]
    @State private var skillDiffs: [String: SkillSourceDiff] = [:]
    @State private var error: String?
    @State private var pendingDelete: ManagedSkill?
    @State private var pendingBatchDelete = false
    @State private var pendingPresetDelete: SkillPreset?
    @State private var pendingProjectDelete: SkillProject?

    private var availableTools: [SkillToolInfo] {
        tools
            .filter { $0.enabled && ($0.installed || $0.isCustom || $0.hasPathOverride) }
            .sorted(by: toolSort)
    }

    private var projectTools: [SkillToolInfo] {
        tools
            .filter { $0.enabled && $0.projectRelativeSkillsDir?.isEmpty == false }
            .sorted(by: toolSort)
    }

    private var filteredSkills: [ManagedSkill] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return skills.filter { skill in
            if !sourceFilters.isEmpty, !sourceFilters.contains(skill.sourceType.rawValue) {
                return false
            }
            if !tagFilters.isEmpty {
                let tagSet = Set(skill.tags)
                if tagFilters.contains("__untagged__") {
                    if !skill.tags.isEmpty && tagFilters.isDisjoint(with: tagSet) {
                        return false
                    }
                } else if tagFilters.isDisjoint(with: tagSet) {
                    return false
                }
            }
            guard !q.isEmpty else { return true }
            return skill.name.lowercased().contains(q) ||
                (skill.description ?? "").lowercased().contains(q) ||
                skill.tags.joined(separator: " ").lowercased().contains(q)
        }
    }

    private var allTags: [String] {
        Array(Set(skills.flatMap(\.tags))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var sourceTypesInUse: [String] {
        Array(Set(skills.map { $0.sourceType.rawValue })).sorted()
    }

    private var commandTools: [SkillToolInfo] {
        Array(availableTools.prefix(3))
    }

    private var inspectedSkill: ManagedSkill? {
        if let inspectedSkillID,
           let skill = skills.first(where: { $0.id == inspectedSkillID }) {
            return skill
        }
        return filteredSkills.first ?? skills.first
    }

    private var detailSkill: ManagedSkill? {
        guard let detailSkillID else { return nil }
        return skills.first { $0.id == detailSkillID }
    }

    private var unsyncedSkillsCount: Int {
        skills.filter(\.targets.isEmpty).count
    }

    private var attentionSkillsCount: Int {
        skills.filter { ["update_available", "source_missing", "error"].contains($0.updateStatus) }.count
    }

    private var sourceProblemSkillsCount: Int {
        skills.filter { ["source_missing", "error"].contains($0.updateStatus) }.count
    }

    private var deployedTargetCount: Int {
        skills.reduce(0) { $0 + $1.targets.count }
    }

    private var maxDeploymentSlots: Int {
        max(0, skills.count * availableTools.count)
    }

    private var deploymentCoveragePercent: Int {
        guard maxDeploymentSlots > 0 else { return 0 }
        return Int((Double(deployedTargetCount) / Double(maxDeploymentSlots) * 100).rounded())
    }

    private var sourceBackedSkillsCount: Int {
        skills.filter(canRefreshFromSource).count
    }

    private var commandTasks: [SkillCommandTask] {
        var tasks: [SkillCommandTask] = []
        if skills.isEmpty {
            tasks.append(SkillCommandTask(
                id: "market",
                icon: "sparkles",
                title: "skills.sh",
                detail: L("从市场挑选第一批 Skill"),
                count: nil,
                tint: AppStyle.accent,
                action: .market))
            tasks.append(SkillCommandTask(
                id: "import",
                icon: "folder.badge.plus",
                title: L("导入本地"),
                detail: L("收纳已有目录或 bundle"),
                count: nil,
                tint: AppStyle.textSecondary,
                action: .importLocal))
        }
        if scanResult == nil {
            tasks.append(SkillCommandTask(
                id: "scan",
                icon: "scope",
                title: L("扫描本机"),
                detail: L("发现 Codex / Claude / 自定义 Agent 里的旧 Skill"),
                count: nil,
                tint: .orange,
                action: .scan))
        }
        if availableTools.isEmpty {
            tasks.append(SkillCommandTask(
                id: "agents",
                icon: "cpu",
                title: "Agents",
                detail: L("启用或添加可接收 Skill 的工具"),
                count: nil,
                tint: AppStyle.accent,
                action: .agents))
        }
        if unsyncedSkillsCount > 0, !availableTools.isEmpty {
            tasks.append(SkillCommandTask(
                id: "sync-unsynced",
                icon: "arrow.triangle.2.circlepath",
                title: L("分发未同步"),
                detail: L("把还没进入 Agent 的 Skill 推过去"),
                count: unsyncedSkillsCount,
                tint: AppStyle.accent,
                action: .syncUnsynced))
        }
        if !updatableSkills.isEmpty {
            tasks.append(SkillCommandTask(
                id: "update",
                icon: "arrow.down.circle",
                title: L("更新可用"),
                detail: L("刷新已经确认有新版的 Skill"),
                count: updatableSkills.count,
                tint: .orange,
                action: .updateAvailable))
        }
        if sourceProblemSkillsCount > 0 {
            tasks.append(SkillCommandTask(
                id: "source-problems",
                icon: "exclamationmark.triangle",
                title: L("来源异常"),
                detail: L("重新绑定或解除失效来源"),
                count: sourceProblemSkillsCount,
                tint: .red,
                action: .library))
        }
        if tasks.isEmpty {
            tasks.append(SkillCommandTask(
                id: "healthy",
                icon: "checkmark.seal",
                title: L("状态稳定"),
                detail: L("可以检查来源更新或继续整理标签"),
                count: nil,
                tint: AppStyle.accent,
                action: .checkUpdates))
        }
        return Array(tasks.prefix(5))
    }

    private var installedSkillsshRefs: Set<String> {
        Set(skills.compactMap { skill in
            skill.sourceType == .skillssh ? skill.sourceRef : nil
        })
    }

    private var filteredGroups: [DiscoveredSkillGroup] {
        let groups = scanResult?.groups ?? []
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return groups }
        return groups.filter {
            $0.name.lowercased().contains(q) ||
                $0.locations.contains { $0.tool.lowercased().contains(q) || $0.foundPath.lowercased().contains(q) }
        }
    }

    private var filteredPresets: [SkillPreset] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return presets }
        let skillByID = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0.name.lowercased()) })
        return presets.filter { preset in
            preset.name.lowercased().contains(q) ||
                (preset.description ?? "").lowercased().contains(q) ||
                preset.skills.contains { item in
                    skillByID[item.skillID]?.contains(q) == true
                }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            sectionTabs
            Divider().overlay(AppStyle.separator)
            content
        }
        .onAppear { if engine == nil { reload() } }
        .sheet(isPresented: Binding(
            get: { detailSkill != nil },
            set: { if !$0 { detailSkillID = nil } }
        )) {
            if let skill = detailSkill {
                SkillDetailCockpit(
                    skill: skill,
                    tools: availableTools,
                    document: skillDocuments[skill.id],
                    files: skillFiles[skill.id] ?? [],
                    sourceDiff: skillDiffs[skill.id],
                    auditEntries: auditEntries.filter { entry in
                        entry.skillID == skill.id || entry.skillName == skill.name
                    },
                    readinessItems: readinessItems(for: skill),
                    selectedTab: $detailTab,
                    syncMode: syncModeLabel,
                    canRefreshFromSource: canRefreshFromSource(skill),
                    onClose: { detailSkillID = nil },
                    onSyncAll: { syncAll(skill) },
                    onToggleTool: { tool, enabled in
                        toggle(skill: skill, tool: tool, enabled: enabled)
                    },
                    onCheckUpdate: { checkSkillUpdate(skill) },
                    onRefreshSource: { refreshSkillFromSource(skill) },
                    onReveal: { reveal(skill.centralPath) },
                    onDelete: {
                        detailSkillID = nil
                        pendingDelete = skill
                    },
                    onLoadDetails: { loadSkillDetails(skill) })
                    .frame(minWidth: 880, idealWidth: 980, minHeight: 620, idealHeight: 720)
            }
        }
        .alert(L("删除 Skill？"), isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button(L("取消"), role: .cancel) { pendingDelete = nil }
            Button(L("删除"), role: .destructive) {
                if let skill = pendingDelete { delete(skill) }
                pendingDelete = nil
            }
        } message: {
            Text(L("会从中央库删除该 Skill，并移除由 Conductor 管理的同步目标。"))
        }
        .alert(L("删除选中的 Skills？"), isPresented: $pendingBatchDelete) {
            Button(L("取消"), role: .cancel) { pendingBatchDelete = false }
            Button(L("删除"), role: .destructive) {
                deleteSelectedSkills()
                pendingBatchDelete = false
            }
        } message: {
            Text(L("会删除选中的 Skills，并移除由 Conductor 管理的同步目标。"))
        }
        .alert(L("删除 Preset？"), isPresented: Binding(
            get: { pendingPresetDelete != nil },
            set: { if !$0 { pendingPresetDelete = nil } }
        )) {
            Button(L("取消"), role: .cancel) { pendingPresetDelete = nil }
            Button(L("删除"), role: .destructive) {
                if let preset = pendingPresetDelete { deletePreset(preset) }
                pendingPresetDelete = nil
            }
        } message: {
            Text(L("只删除 Preset 分组，不删除中央库里的 Skills。"))
        }
        .alert(L("移除项目？"), isPresented: Binding(
            get: { pendingProjectDelete != nil },
            set: { if !$0 { pendingProjectDelete = nil } }
        )) {
            Button(L("取消"), role: .cancel) { pendingProjectDelete = nil }
            Button(L("移除"), role: .destructive) {
                if let project = pendingProjectDelete { deleteProject(project) }
                pendingProjectDelete = nil
            }
        } message: {
            Text(L("只从 Conductor 移除这个项目记录，不删除项目目录。"))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                searchField
                Picker("", selection: $syncMode) {
                    Text(L("软链")).tag("symlink")
                    Text(L("复制")).tag("copy")
                }
                .pickerStyle(.segmented)
                .frame(width: 94)
                .help(L("同步模式"))

                iconButton("folder.badge.plus", help: L("从本地目录导入 Skill"), action: importLocal)
                iconButton("folder.badge.gearshape", help: L("添加项目工作区"), action: addProject)
                iconButton("scope", help: L("扫描本机已有 Skills")) { reload(scan: true) }
                iconButton("arrow.clockwise", help: L("刷新")) { reload() }
                    .disabled(loading)
            }

            HStack(spacing: 6) {
                metricChip(title: L("中央库"), value: "\(skills.count)")
                metricChip(title: "Presets", value: "\(presets.count)")
                metricChip(title: L("项目"), value: "\(projects.count)")
                metricChip(title: L("可同步 Agent"), value: "\(availableTools.count)")
                metricChip(title: L("已同步目标"), value: "\(skills.reduce(0) { $0 + $1.targets.count })")
                if !updatableSkills.isEmpty {
                    metricChip(title: L("可更新"), value: "\(updatableSkills.count)")
                }
                if let scanResult {
                    metricChip(title: L("发现"), value: "\(scanResult.skillsFound)")
                }
                Spacer()
                if loading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(loadingText)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(AppStyle.textTertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
            TextField(L("搜索 skill / agent / 路径"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(AppStyle.textPrimary)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                .buttonStyle(.plain)
                .help(L("清空搜索"))
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.hoverFill))
    }

    private var sectionTabs: some View {
        HStack(spacing: 6) {
            ForEach(SkillManagerSection.allCases) { section in
                let selected = selectedSection == section
                Button {
                    withAnimation(Motion.snappy) { selectedSection = section }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: section.icon)
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(section.title)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(selected ? .white : AppStyle.textSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? AppStyle.accent : AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if let error {
                    StatusLine(icon: "exclamationmark.triangle.fill", text: error, color: .red)
                }

                switch selectedSection {
                case .command:
                    commandCenterContent
                case .library:
                    libraryContent
                case .presets:
                    presetsContent
                case .projects:
                    projectsContent
                case .agents:
                    agentsContent
                case .activity:
                    activityContent
                case .discovered:
                    discoveredContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private var commandCenterContent: some View {
        Group {
            if loading && skills.isEmpty {
                loadingRow
            } else {
                commandQuickBar
                if !selectedSkillIDs.isEmpty {
                    commandSelectionTray
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                commandLibraryPanel
                commandInspectorPanel
            }
        }
        .animation(Motion.expand, value: selectedSkillIDs.isEmpty)
        .animation(Motion.snappy, value: unsyncedSkillsCount)
        .animation(Motion.snappy, value: updatableSkills.count)
    }

    private var commandQuickBar: some View {
        HStack(spacing: 8) {
            compactCommandButton(
                title: L("导入"),
                icon: "folder.badge.plus",
                color: AppStyle.accent,
                action: importLocal)
            compactCommandButton(
                title: L("扫描"),
                icon: "scope",
                color: .orange) {
                    reload(scan: true)
                }
            compactCommandButton(
                title: "skills.sh",
                icon: "sparkles",
                color: AppStyle.accent) {
                    selectedSection = .discovered
                    if skillsShSkills.isEmpty { loadSkillsShMarket() }
                }
            compactCommandButton(
                title: "Agents",
                icon: "cpu",
                color: AppStyle.textSecondary) {
                    selectedSection = .agents
                }

            Spacer(minLength: 8)

            if unsyncedSkillsCount > 0, !availableTools.isEmpty {
                compactCommandButton(
                    title: L("分发 %ld", unsyncedSkillsCount),
                    icon: "arrow.triangle.2.circlepath",
                    color: .orange,
                    action: syncUnsyncedSkills)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if !updatableSkills.isEmpty {
                compactCommandButton(
                    title: L("更新 %ld", updatableSkills.count),
                    icon: "arrow.down.circle",
                    color: .orange,
                    action: updateAvailableSkills)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            compactCommandButton(
                title: L("检查"),
                icon: "checkmark.seal",
                color: AppStyle.textTertiary,
                action: checkAllSkillUpdates)
                .disabled(skills.allSatisfy { !canRefreshFromSource($0) })
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .toolsCard(cornerRadius: Radius.sm + 2)
    }

    private func compactCommandButton(title: String,
                                      icon: String,
                                      color: Color,
                                      action: @escaping () -> Void) -> some View {
        SkillToolbarButton(title: title, icon: icon, color: color, action: action)
    }

    private var commandRunway: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
            commandActionTile(
                icon: "sparkles",
                title: "skills.sh",
                value: skillsShSkills.isEmpty ? L("市场") : L("%ld 项", skillsShSkills.count),
                color: AppStyle.accent) {
                    selectedSection = .discovered
                    if skillsShSkills.isEmpty { loadSkillsShMarket() }
                }
            commandActionTile(
                icon: "scope",
                title: L("扫描"),
                value: scanResult.map { L("%ld 个", $0.skillsFound) } ?? L("本机"),
                color: .orange) {
                    reload(scan: true)
                }
            commandActionTile(
                icon: "folder.badge.plus",
                title: L("导入"),
                value: L("目录 / Zip"),
                color: AppStyle.textSecondary,
                action: importLocal)
            commandActionTile(
                icon: "cpu",
                title: "Agents",
                value: L("%ld 可用", availableTools.count),
                color: AppStyle.accent) {
                    selectedSection = .agents
                }
            commandActionTile(
                icon: "exclamationmark.triangle",
                title: L("待处理"),
                value: "\(attentionSkillsCount + unsyncedSkillsCount)",
                color: attentionSkillsCount > 0 ? .orange : AppStyle.textTertiary) {
                    selectedSection = .library
                }
        }
    }

    private func commandActionTile(icon: String,
                                   title: String,
                                   value: String,
                                   color: Color,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(color.opacity(0.12)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(value)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppStyle.hoverFill.opacity(0.72)))
        }
        .buttonStyle(PressScaleStyle())
    }

    private var commandWorkflowPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            commandPanelHeader(
                icon: "point.topleft.down.curvedto.point.bottomright.up",
                title: L("Mission Control"),
                value: "\(deploymentCoveragePercent)%")

            HStack(spacing: 7) {
                commandStageItem(
                    icon: "sparkles",
                    title: L("发现"),
                    value: scanResult.map { L("%ld 项", $0.skillsFound) } ?? (skillsShSkills.isEmpty ? L("待启动") : L("%ld 项", skillsShSkills.count)),
                    active: skills.isEmpty || scanResult == nil) {
                        selectedSection = .discovered
                        if skillsShSkills.isEmpty { loadSkillsShMarket() }
                    }
                commandStageConnector(active: !skills.isEmpty)
                commandStageItem(
                    icon: "square.stack.3d.up",
                    title: L("收纳"),
                    value: L("%ld Skills", skills.count),
                    active: !skills.isEmpty) {
                        selectedSection = .library
                    }
                commandStageConnector(active: deployedTargetCount > 0)
                commandStageItem(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: L("分发"),
                    value: maxDeploymentSlots == 0 ? L("待配置") : L("%ld / %ld", deployedTargetCount, maxDeploymentSlots),
                    active: unsyncedSkillsCount == 0 && deployedTargetCount > 0) {
                        selectedSection = .library
                    }
                commandStageConnector(active: attentionSkillsCount == 0 && !skills.isEmpty)
                commandStageItem(
                    icon: "checkmark.seal",
                    title: L("维护"),
                    value: attentionSkillsCount == 0 ? L("稳定") : L("%ld 待处理", attentionSkillsCount),
                    active: attentionSkillsCount == 0 && !skills.isEmpty) {
                        if attentionSkillsCount == 0 {
                            checkAllSkillUpdates()
                        } else {
                            selectedSection = .library
                        }
                    }
            }

            HStack(spacing: 7) {
                commandSignal(title: L("覆盖率"), value: maxDeploymentSlots == 0 ? "--" : "\(deploymentCoveragePercent)%", color: AppStyle.accent)
                commandSignal(title: L("来源"), value: "\(sourceBackedSkillsCount)/\(skills.count)", color: sourceProblemSkillsCount > 0 ? .orange : AppStyle.textSecondary)
                commandSignal(title: L("未分发"), value: "\(unsyncedSkillsCount)", color: unsyncedSkillsCount > 0 ? .orange : AppStyle.accent)
                commandSignal(title: L("选中"), value: "\(selectedSkillIDs.count)", color: selectedSkillIDs.isEmpty ? AppStyle.textTertiary : AppStyle.accent)
            }
        }
        .padding(11)
        .toolsCard(cornerRadius: Radius.sm + 2)
    }

    private func commandStageItem(icon: String,
                                  title: String,
                                  value: String,
                                  active: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(active ? AppStyle.accent : AppStyle.textTertiary)
                    Text(title)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .lineLimit(1)
                }
                Text(value)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(active ? AppStyle.textPrimary : AppStyle.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(active ? AppStyle.accent.opacity(0.12) : AppStyle.hoverFill.opacity(0.54)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(active ? AppStyle.accent.opacity(0.28) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func commandStageConnector(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(active ? AppStyle.accent.opacity(0.45) : AppStyle.separator.opacity(0.85))
            .frame(width: 16, height: 3)
    }

    private func commandSignal(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(AppStyle.textTertiary)
            Text(value)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(AppStyle.hoverFill.opacity(0.52)))
    }

    private var commandSelectionTray: some View {
        HStack(spacing: 8) {
            Label(L("已选 %ld", selectedSkillIDs.count), systemImage: "checklist")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppStyle.textSecondary)
            Spacer()
            Button {
                syncSelectedSkills()
            } label: {
                Label(L("同步选中"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(selectedSkillIDs.isEmpty)
            Button {
                exportSelectedSkills()
            } label: {
                Label(L("导出"), systemImage: "square.and.arrow.up")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(selectedSkillIDs.isEmpty)
            Button {
                selectedSkillIDs.removeAll()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(L("清空选择"))
        }
        .foregroundStyle(AppStyle.textSecondary)
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AppStyle.hoverFill.opacity(0.58)))
    }

    private var commandLibraryPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            commandPanelHeader(
                icon: "square.stack.3d.up",
                title: "Skills",
                value: "\(filteredSkills.count)")

            if filteredSkills.isEmpty {
                compactEmpty(icon: "tray", title: L("没有 Skill"))
            } else {
                ForEach(filteredSkills.prefix(8)) { skill in
                    commandSkillRow(skill)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity))
                }
                if filteredSkills.count > 8 {
                    Button {
                        selectedSection = .library
                    } label: {
                        HStack(spacing: 6) {
                            Text(L("查看全部 %ld 个", filteredSkills.count))
                                .font(.system(size: 10.5, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(AppStyle.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(11)
        .toolsCard(cornerRadius: Radius.sm + 2)
        .animation(Motion.expand, value: filteredSkills.map(\.id).joined(separator: "|"))
    }

    private func commandSkillRow(_ skill: ManagedSkill) -> some View {
        let active = inspectedSkill?.id == skill.id
        return SkillCommandRow(
            skill: skill,
            active: active,
            healthColor: skillHealthColor(skill)) {
                withAnimation(Motion.snappy) {
                    inspectSkill(skill)
                }
            }
    }

    private var commandInspectorPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            commandPanelHeader(
                icon: "sidebar.right",
                title: L("当前 Skill"),
                value: inspectedSkill?.name ?? L("未选择"))

            if let skill = inspectedSkill {
                inspectorBody(skill)
                    .id(skill.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                compactEmpty(icon: "cursorarrow.click", title: L("选择一个 Skill"))
                    .transition(.opacity)
            }
        }
        .padding(11)
        .toolsCard(cornerRadius: Radius.sm + 2)
        .animation(Motion.expand, value: inspectedSkill?.id)
    }

    private func inspectorBody(_ skill: ManagedSkill) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1)
                    tinyBadge(skill.sourceType.rawValue, color: AppStyle.textTertiary)
                }
                Text((skill.description?.isEmpty == false) ? skill.description! : collapsedPath(skill.centralPath))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                Button { openSkillDetail(skill) } label: {
                    Label(L("详情"), systemImage: "rectangle.and.text.magnifyingglass")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.accent))
                }
                .buttonStyle(PressScaleStyle())
                .help(L("打开 Skill 详情控制台"))

                Button { syncAll(skill) } label: {
                    Label(L("同步"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())

                if canRefreshFromSource(skill) {
                    iconButton("magnifyingglass.circle", help: L("检查更新")) {
                        checkSkillUpdate(skill)
                    }
                    iconButton("arrow.clockwise.circle", help: L("刷新来源")) {
                        refreshSkillFromSource(skill)
                    }
                }
                iconButton("folder", help: L("在 Finder 显示")) { reveal(skill.centralPath) }
                iconButton("trash", help: L("删除"), destructive: true) { pendingDelete = skill }
            }

            inspectorStatusGrid(skill)
            inspectorReadiness(skill)
            inspectorQuickDeployment(skill)
        }
    }

    private func inspectorStatusGrid(_ skill: ManagedSkill) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                statusPill(title: L("Agent"), value: "\(skill.targets.count)", color: skill.targets.isEmpty ? AppStyle.textTertiary : AppStyle.accent)
                statusPill(title: L("标签"), value: "\(skill.tags.count)", color: AppStyle.textTertiary)
                statusPill(title: L("更新"), value: inspectorUpdateLabel(skill), color: skillHealthColor(skill))
            }
            if !skill.tags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(skill.tags.prefix(6), id: \.self) { tag in
                        tinyBadge(tag, color: AppStyle.textTertiary)
                    }
                }
            }
        }
    }

    private func inspectorReadiness(_ skill: ManagedSkill) -> some View {
        let items = readinessItems(for: skill)
        let readyCount = items.filter(\.ready).count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(L("就绪检查"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                Spacer()
                Text("\(readyCount)/\(items.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(readyCount == items.count ? AppStyle.accent : .orange)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
            ], spacing: 6) {
                ForEach(items) { item in
                    readinessTile(item)
                }
            }
        }
    }

    private func readinessTile(_ item: SkillReadinessItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.ready ? "checkmark.circle.fill" : item.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(item.ready ? AppStyle.accent : item.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(1)
                Text(item.detail)
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(item.ready ? AppStyle.accent.opacity(0.10) : AppStyle.hoverFill.opacity(0.54)))
        .animation(Motion.snappy, value: item.ready)
    }

    private func inspectorQuickDeployment(_ skill: ManagedSkill) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(L("部署"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                Spacer()
                Button {
                    openSkillDetail(skill, tab: .deploy)
                } label: {
                    Label(L("矩阵"), systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                .buttonStyle(.plain)
                .help(L("打开完整部署矩阵"))
            }

            if availableTools.isEmpty {
                compactEmpty(icon: "cpu", title: L("没有可用 Agent"))
                    .frame(height: 56)
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 74), spacing: 6),
                ], spacing: 6) {
                    ForEach(Array(availableTools.prefix(6))) { tool in
                        let synced = skill.targets.contains { $0.tool == tool.key }
                        Button {
                            toggle(skill: skill, tool: tool, enabled: !synced)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: synced ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 9.5, weight: .semibold))
                                Text(tool.displayName)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(synced ? .white : AppStyle.textSecondary)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(synced ? AppStyle.accent : AppStyle.hoverFill.opacity(0.64)))
                        }
                        .buttonStyle(PressScaleStyle())
                        .help(synced ? L("移除同步") : L("同步到该 Agent"))
                    }
                }
            }
        }
    }

    private func commandPanelHeader(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(AppStyle.accent)
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppStyle.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)
        }
    }

    private func compactEmpty(icon: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(AppStyle.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AppStyle.hoverFill.opacity(0.45)))
    }

    private func statusPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(AppStyle.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AppStyle.hoverFill.opacity(0.52)))
    }

    private func skillHealthColor(_ skill: ManagedSkill) -> Color {
        switch skill.updateStatus {
        case "update_available": return .orange
        case "source_missing", "error": return .red
        default:
            return skill.targets.isEmpty ? AppStyle.textTertiary : AppStyle.accent
        }
    }

    private func inspectorUpdateLabel(_ skill: ManagedSkill) -> String {
        switch skill.updateStatus {
        case "current": return L("最新")
        case "update_available": return L("可更新")
        case "source_missing": return L("失效")
        case "error": return L("错误")
        default: return L("未知")
        }
    }

    private func readinessItems(for skill: ManagedSkill) -> [SkillReadinessItem] {
        let files = skillFiles[skill.id] ?? []
        let hasKnownSkillDocument = skillDocuments[skill.id] != nil ||
            files.contains { $0.relativePath.lowercased() == "skill.md" }
        let hasDescription = skill.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let sourceProblem = ["source_missing", "error"].contains(skill.updateStatus)
        let canRefresh = canRefreshFromSource(skill)

        return [
            SkillReadinessItem(
                id: "document",
                title: "SKILL.md",
                detail: hasKnownSkillDocument ? L("已识别") : L("待读取"),
                ready: hasKnownSkillDocument,
                icon: "doc.text.magnifyingglass",
                color: .orange),
            SkillReadinessItem(
                id: "description",
                title: L("摘要"),
                detail: hasDescription ? L("清晰") : L("缺少描述"),
                ready: hasDescription,
                icon: "text.alignleft",
                color: .orange),
            SkillReadinessItem(
                id: "deployment",
                title: L("分发"),
                detail: skill.targets.isEmpty ? L("未同步") : L("%ld Agent", skill.targets.count),
                ready: !skill.targets.isEmpty,
                icon: "arrow.triangle.2.circlepath",
                color: .orange),
            SkillReadinessItem(
                id: "source",
                title: L("来源"),
                detail: sourceProblem ? inspectorUpdateLabel(skill) : (canRefresh ? L("可维护") : L("静态")),
                ready: !sourceProblem,
                icon: "link.badge.plus",
                color: sourceProblem ? .red : AppStyle.textTertiary),
            SkillReadinessItem(
                id: "tags",
                title: L("分类"),
                detail: skill.tags.isEmpty ? L("未打标签") : L("%ld 标签", skill.tags.count),
                ready: !skill.tags.isEmpty,
                icon: "tag",
                color: AppStyle.textTertiary),
        ]
    }

    @ViewBuilder
    private var libraryContent: some View {
        if loading && skills.isEmpty {
            loadingRow
        } else if filteredSkills.isEmpty {
            emptyState(
                icon: "tray",
                title: query.isEmpty ? L("中央库还没有 Skill") : L("没有匹配的 Skill"),
                detail: L("从本地目录导入，或先扫描本机已有 Agent Skills 再纳入管理。"))
        } else {
            libraryFilterBar
            libraryBatchToolbar
            ForEach(filteredSkills) { skill in
                ManagedSkillRow(
                    skill: skill,
                    tools: Array(availableTools.prefix(14)),
                    expanded: expandedSkillID == skill.id,
                    selected: selectedSkillIDs.contains(skill.id),
                    document: skillDocuments[skill.id],
                    files: skillFiles[skill.id] ?? [],
                    sourceDiff: skillDiffs[skill.id],
                    syncMode: syncModeLabel,
                    onExpand: {
                        toggleSkillExpansion(skill)
                    },
                    onSelect: { toggleSkillSelection(skill.id) },
                    onOpenDetail: { openSkillDetail(skill) },
                    onToggleTool: { tool, enabled in
                        toggle(skill: skill, tool: tool, enabled: enabled)
                    },
                    onSyncAll: { syncAll(skill) },
                    onCheckUpdate: { checkSkillUpdate(skill) },
                    onRefreshSource: { refreshSkillFromSource(skill) },
                    onRelinkSource: { relinkSkillSource(skill) },
                    onDetachSource: { detachSkillSource(skill) },
                    onReveal: { reveal(skill.centralPath) },
                    onDelete: { pendingDelete = skill })
            }
        }
    }

    private var libraryFilterBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !sourceTypesInUse.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(sourceTypesInUse, id: \.self) { source in
                            filterChip(
                                title: source == "skillssh" ? "skills.sh" : source,
                                active: sourceFilters.contains(source),
                                color: AppStyle.accent) {
                                    toggleString(source, in: &sourceFilters)
                                }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.never)
            }

            if !allTags.isEmpty || skills.contains(where: { $0.tags.isEmpty }) {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        if skills.contains(where: { $0.tags.isEmpty }) {
                            filterChip(
                                title: L("未打标签"),
                                active: tagFilters.contains("__untagged__"),
                                color: .orange) {
                                    toggleString("__untagged__", in: &tagFilters)
                                }
                        }
                        ForEach(allTags, id: \.self) { tag in
                            filterChip(
                                title: tag,
                                active: tagFilters.contains(tag),
                                color: AppStyle.textTertiary) {
                                    toggleString(tag, in: &tagFilters)
                                }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .toolsCard(cornerRadius: Radius.sm + 2)
    }

    private var libraryBatchToolbar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button {
                    selectAllFilteredSkills()
                } label: {
                    Label(L("全选"), systemImage: "checklist")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())

                Button {
                    selectedSkillIDs.removeAll()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
                .help(L("清空选择"))

                tinyBadge(L("已选 %ld", selectedSkillIDs.count), color: selectedSkillIDs.isEmpty ? AppStyle.textTertiary : AppStyle.accent)

                Button {
                    syncSelectedSkills()
                } label: {
                    Label(L("同步"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(selectedSkillIDs.isEmpty)

                Button {
                    refreshSelectedSkills()
                } label: {
                    Label(L("刷新来源"), systemImage: "arrow.clockwise.circle")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!selectedSkills.contains(where: canRefreshFromSource))

                Button {
                    updateAvailableSkills()
                } label: {
                    Label(L("更新可用"), systemImage: "arrow.down.circle")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(updatableSkills.isEmpty)

                Button {
                    checkAllSkillUpdates()
                } label: {
                    Label(L("检查全部"), systemImage: "checkmark.seal")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(skills.allSatisfy { !canRefreshFromSource($0) })

                Button {
                    checkSelectedSkillUpdates()
                } label: {
                    Label(L("检查更新"), systemImage: "magnifyingglass.circle")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!selectedSkills.contains(where: canRefreshFromSource))

                Button {
                    exportSelectedSkills()
                } label: {
                    Label(L("导出"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(selectedSkillIDs.isEmpty)

                TextField(L("标签"), text: $tagDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppStyle.textPrimary)
                    .padding(.horizontal, 8)
                    .frame(width: 150, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.hoverFill))

                Button {
                    applyTagToSelection(add: true)
                } label: {
                    Label(L("添加"), systemImage: "tag.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(canApplyTag ? AppStyle.accent : AppStyle.textTertiary.opacity(0.55)))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!canApplyTag)

                Button {
                    applyTagToSelection(add: false)
                } label: {
                    Label(L("移除"), systemImage: "tag.slash")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!canApplyTag)

                Button {
                    pendingBatchDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color(red: 0.92, green: 0.34, blue: 0.34))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
                .help(L("删除选中"))
                .disabled(selectedSkillIDs.isEmpty)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
        .toolsCard(cornerRadius: Radius.sm + 2)
    }

    private var canApplyTag: Bool {
        !selectedSkillIDs.isEmpty && !tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedSkills: [ManagedSkill] {
        skills.filter { selectedSkillIDs.contains($0.id) }
    }

    private var updatableSkills: [ManagedSkill] {
        skills.filter { $0.updateStatus == "update_available" && canRefreshFromSource($0) }
    }

    @ViewBuilder
    private var presetsContent: some View {
        presetCreator

        if filteredPresets.isEmpty {
            emptyState(
                icon: "rectangle.stack.badge.plus",
                title: query.isEmpty ? L("还没有 Preset") : L("没有匹配的 Preset"),
                detail: L("Preset 是一组可复用 Skills，能一键同步到当前可用 Agents。"))
        } else {
            ForEach(filteredPresets) { preset in
                PresetRow(
                    preset: preset,
                    summary: presetSummaries.first { $0.id == preset.id },
                    skills: skills,
                    expanded: expandedPresetID == preset.id,
                    onExpand: {
                        withAnimation(Motion.expand) {
                            expandedPresetID = expandedPresetID == preset.id ? nil : preset.id
                        }
                    },
                    onApply: { applyPreset(preset) },
                    onRemove: { removePreset(preset) },
                    onDelete: { pendingPresetDelete = preset },
                    onToggleSkill: { skill, enabled in
                        togglePresetSkill(preset: preset, skill: skill, enabled: enabled)
                    },
                    onMoveSkill: { skill, offset in
                        movePresetSkill(preset: preset, skill: skill, offset: offset)
                    })
            }
        }
    }

    private var presetCreator: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
            TextField(L("新 Preset 名称"), text: $newPresetName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(AppStyle.textPrimary)
            Button {
                createPreset()
            } label: {
                Label(L("创建"), systemImage: "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(canCreatePreset ? AppStyle.accent : AppStyle.textTertiary.opacity(0.55)))
            }
            .buttonStyle(PressScaleStyle())
            .disabled(!canCreatePreset)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .toolsCard(cornerRadius: Radius.sm + 2)
    }

    private var canCreatePreset: Bool {
        !newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var projectsContent: some View {
        HStack(spacing: 8) {
            Button(action: addProject) {
                Label(L("添加项目"), systemImage: "folder.badge.gearshape")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.accent))
            }
            .buttonStyle(PressScaleStyle())
            Spacer()
        }

        if projects.isEmpty {
            emptyState(
                icon: "folder.badge.gearshape",
                title: L("还没有项目工作区"),
                detail: L("添加一个项目目录后，可以把中央库 Skills 同步到该项目的 .codex/.claude 等本地目录。"))
        } else {
            ForEach(projects) { project in
                ProjectWorkspaceRow(
                    project: project,
                    projectSkills: projectSkills[project.id] ?? [],
                    centralSkills: skills,
                    presets: presets,
                    tools: Array(projectTools.prefix(12)),
                    targets: projectTargets.filter { $0.projectID == project.id },
                    expanded: expandedProjectID == project.id,
                    onExpand: {
                        withAnimation(Motion.expand) {
                            expandedProjectID = expandedProjectID == project.id ? nil : project.id
                        }
                    },
                    onReveal: { reveal(project.path) },
                    onDelete: { pendingProjectDelete = project },
                    onToggleSkill: { skill, tool, enabled in
                        toggleProjectSkill(project: project, skill: skill, tool: tool, enabled: enabled)
                    },
                    onApplyPreset: { preset in
                        applyPresetToProject(preset: preset, project: project)
                    },
                    onRemovePreset: { preset in
                        removePresetFromProject(preset: preset, project: project)
                    })
            }
        }
    }

    @ViewBuilder
    private var agentsContent: some View {
        HStack(spacing: 8) {
            Button(action: addCustomAgent) {
                Label(L("添加自定义 Agent"), systemImage: "plus.circle")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.accent))
            }
            .buttonStyle(PressScaleStyle())
            Spacer()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .toolsCard(cornerRadius: Radius.sm + 2)

        if tools.isEmpty {
            loadingRow
        } else {
            ForEach(tools.sorted(by: toolSort)) { tool in
                SkillToolRow(
                    tool: tool,
                    syncedCount: skills.filter { skill in
                        skill.targets.contains { $0.tool == tool.key }
                    }.count,
                    onToggleEnabled: { toggleToolEnabled(tool) },
                    onReveal: { reveal(tool.skillsDirectory) })
            }
        }
    }

    @ViewBuilder
    private var activityContent: some View {
        if auditEntries.isEmpty {
            emptyState(
                icon: "clock.arrow.circlepath",
                title: L("还没有活动记录"),
                detail: L("导入、同步、刷新、删除、标签和 Agent 状态变化会出现在这里。"))
        } else {
            ForEach(auditEntries) { entry in
                SkillAuditRow(entry: entry)
            }
        }
    }

    @ViewBuilder
    private var discoveredContent: some View {
        skillsShMarketPanel
        gitInstallPanel
        if scanResult != nil {
            discoveryToolbar
        }

        if scanResult == nil {
            emptyState(
                icon: "scope",
                title: L("还没有扫描"),
                detail: L("扫描会查找各 Agent 目录里不是由 Conductor 管理的 Skills。"))
            Button { reload(scan: true) } label: {
                Label(L("开始扫描"), systemImage: "scope")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.accent))
            }
            .buttonStyle(PressScaleStyle())
        } else if filteredGroups.isEmpty {
            emptyState(
                icon: "checkmark.circle",
                title: query.isEmpty ? L("没有发现外部 Skill") : L("发现结果无匹配"),
                detail: L("已经同步到中央库的目标会自动跳过。"))
        } else {
            ForEach(filteredGroups) { group in
                DiscoveredSkillGroupRow(
                    group: group,
                    onImport: { importDiscovered(group) },
                    onReveal: { path in reveal(path) })
            }
        }
    }

    private var discoveryToolbar: some View {
        HStack(spacing: 8) {
            Button { reload(scan: true) } label: {
                Label(L("重新扫描"), systemImage: "scope")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.hoverFill))
            }
            .buttonStyle(PressScaleStyle())

            Button { importAllDiscovered() } label: {
                Label(L("全部导入"), systemImage: "square.and.arrow.down.on.square")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(canImportAllDiscovered ? AppStyle.accent : AppStyle.textTertiary.opacity(0.55)))
            }
            .buttonStyle(PressScaleStyle())
            .disabled(!canImportAllDiscovered)

            if let scanResult {
                tinyBadge(L("发现 %ld", scanResult.skillsFound), color: AppStyle.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .toolsCard(cornerRadius: Radius.sm + 2)
    }

    private var canImportAllDiscovered: Bool {
        filteredGroups.contains { !$0.imported }
    }

    private var skillsShMarketPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                Text("skills.sh")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                Picker("", selection: $skillsShBoard) {
                    Text(L("热门")).tag("hot")
                    Text(L("趋势")).tag("trending")
                    Text(L("全部")).tag("alltime")
                }
                .pickerStyle(.segmented)
                .frame(width: 132)
                Spacer()
                Button {
                    loadSkillsShMarket()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
                .help(L("刷新 skills.sh"))
                .disabled(skillsShLoading)
            }

            HStack(spacing: 8) {
                TextField(L("搜索 skills.sh"), text: $skillsShQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppStyle.textPrimary)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.hoverFill))
                    .onSubmit { loadSkillsShMarket() }
                Button {
                    loadSkillsShMarket()
                } label: {
                    Label(L("搜索"), systemImage: "magnifyingglass")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.accent))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(skillsShLoading)
            }

            if skillsShLoading {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(L("正在加载 skills.sh…"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppStyle.textTertiary)
                    Spacer()
                }
            } else if let skillsShError {
                StatusLine(icon: "exclamationmark.triangle.fill", text: skillsShError, color: .orange)
            } else if skillsShSkills.isEmpty {
                Text(L("加载榜单或搜索后，可以直接安装远程 Skill。"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textTertiary)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(skillsShSkills.prefix(16)) { skill in
                        SkillsShMarketRow(
                            skill: skill,
                            installed: installedSkillsshRefs.contains(skill.id),
                            onInstall: { installSkillssh(skill) })
                    }
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .toolsCard(cornerRadius: Radius.sm + 2)
        .onAppear {
            if skillsShSkills.isEmpty, !skillsShLoading {
                loadSkillsShMarket()
            }
        }
    }

    private var gitInstallPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "git.branch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                Text(L("从 Git 安装 Skill"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                Spacer()
                Button {
                    installGitSkill()
                } label: {
                    Label(L("安装"), systemImage: "square.and.arrow.down")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(canInstallGitSkill ? AppStyle.accent : AppStyle.textTertiary.opacity(0.55)))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!canInstallGitSkill)
            }

            TextField("https://github.com/org/repo.git", text: $gitInstallURL)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(AppStyle.textPrimary)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.hoverFill))

            HStack(spacing: 8) {
                TextField(L("子目录，可空"), text: $gitInstallSubdirectory)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(AppStyle.textPrimary)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.hoverFill))
                TextField("branch / tag / sha", text: $gitInstallRef)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(AppStyle.textPrimary)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.hoverFill))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .toolsCard(cornerRadius: Radius.sm + 2)
    }

    private var canInstallGitSkill: Bool {
        !gitInstallURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(loadingText.isEmpty ? L("正在加载 Skills Manager…") : loadingText)
                .font(.system(size: 12))
                .foregroundStyle(AppStyle.textSecondary)
            Spacer()
        }
        .padding(.vertical, 20)
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AppStyle.textPrimary)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(AppStyle.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .toolsCard(cornerRadius: Radius.sm + 2)
    }

    private func reload(scan: Bool = false) {
        do {
            let engine = try ensureEngine()
            loading = true
            error = nil
            loadingText = scan ? L("正在扫描本机 Skills…") : L("正在刷新 Skills…")

            Task {
                do {
                    let payload = try await Task.detached(priority: .userInitiated) {
                        let result = scan ? try engine.scanLocalSkills() : nil
                        let projects = engine.listProjects()
                        return SkillManagerPayload(
                            skills: engine.listSkills(),
                            tools: engine.tools(),
                            presets: engine.listPresets(),
                            presetSummaries: engine.presetSummaries(),
                            projects: projects,
                            projectTargets: engine.listProjectTargets(),
                            projectSkills: Dictionary(
                                uniqueKeysWithValues: projects.map {
                                    ($0.id, engine.readProjectSkills(projectID: $0.id))
                                }),
                            auditEntries: engine.listAudit(limit: 140),
                            scanResult: result)
                    }.value
                    await MainActor.run {
                        skills = payload.skills
                        tools = payload.tools
                        presets = payload.presets
                        presetSummaries = payload.presetSummaries
                        projects = payload.projects
                        projectTargets = payload.projectTargets
                        projectSkills = payload.projectSkills
                        auditEntries = payload.auditEntries
                        selectedSkillIDs = selectedSkillIDs.intersection(Set(payload.skills.map(\.id)))
                        if let inspectedSkillID,
                           !payload.skills.contains(where: { $0.id == inspectedSkillID }) {
                            self.inspectedSkillID = payload.skills.first?.id
                        } else if inspectedSkillID == nil {
                            inspectedSkillID = payload.skills.first?.id
                        }
                        if let result = payload.scanResult { scanResult = result }
                        loading = false
                        loadingText = ""
                    }
                } catch {
                    await MainActor.run {
                        self.error = error.localizedDescription
                        loading = false
                        loadingText = ""
                    }
                }
            }
        } catch {
            self.error = error.localizedDescription
            loading = false
            loadingText = ""
        }
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = L("添加")
        panel.message = L("选择要管理项目级 Skills 的项目目录")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        let bookmarks = Dictionary(
            urls.compactMap { url in
                SecurityScopedBookmarks.bookmarkData(for: url).map { (url.path, $0) }
            },
            uniquingKeysWith: { first, _ in first })

        run(L("正在添加项目…")) { engine in
            for url in urls {
                _ = try engine.addProject(
                    path: url,
                    bookmarkData: bookmarks[url.path])
            }
        }
    }

    private func importLocal() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = L("导入")
        panel.message = L("选择 Skill 目录、包含多个 Skills 的父目录，或 .zip 包")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        let bookmarks = Dictionary(
            urls.compactMap { url in
                SecurityScopedBookmarks.bookmarkData(for: url).map { (url.path, $0) }
            },
            uniquingKeysWith: { first, _ in first })

        run(L("正在导入本地 Skills…")) { engine in
            for url in urls {
                _ = try engine.importSkillBundle(
                    source: url,
                    sourceBookmarkData: bookmarks[url.path])
            }
        }
    }

    private func addCustomAgent() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("选择")
        panel.message = L("选择这个 Agent 的 skills 目录")
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }

        let alert = NSAlert()
        alert.messageText = L("自定义 Agent")
        alert.informativeText = L("给这个 skills 目录起一个显示名称。")
        alert.addButton(withTitle: L("添加"))
        alert.addButton(withTitle: L("取消"))
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = url.deletingLastPathComponent().lastPathComponent.isEmpty
            ? url.lastPathComponent
            : url.deletingLastPathComponent().lastPathComponent
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let bookmarkData = SecurityScopedBookmarks.bookmarkData(for: url)
        run(L("正在添加自定义 Agent…")) { engine in
            try engine.addCustomTool(
                key: name,
                displayName: name,
                skillsDirectory: url,
                bookmarkData: bookmarkData)
        }
    }

    private func exportSelectedSkills() {
        let ids = Array(selectedSkillIDs)
        guard !ids.isEmpty else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = L("导出")
        panel.nameFieldStringValue = "skills-bundle.zip"
        panel.message = L("导出选中的 Skills，包含 manifest、标签和来源信息")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        run(L("正在导出 Skill Bundle…")) { engine in
            _ = try engine.exportSkillBundle(skillIDs: ids, to: url)
        }
    }

    private func installGitSkill() {
        let remote = gitInstallURL
        let subdirectory = gitInstallSubdirectory
        let ref = gitInstallRef
        run(L("正在从 Git 安装 Skill…")) { engine in
            _ = try engine.installGitSkills(
                repositoryURL: remote,
                subdirectory: subdirectory.isEmpty ? nil : subdirectory,
                ref: ref.isEmpty ? nil : ref)
        }
    }

    private func importDiscovered(_ group: DiscoveredSkillGroup) {
        guard let id = group.locations.first?.id else { return }
        run(L("正在导入发现的 Skill…"), scanAfter: true) { engine in
            _ = try engine.importDiscoveredSkill(recordID: id, name: group.name)
        }
    }

    private func importAllDiscovered() {
        run(L("正在导入全部发现 Skills…"), scanAfter: true) { engine in
            _ = try engine.importAllDiscoveredSkills()
        }
    }

    private func loadSkillsShMarket() {
        do {
            let engine = try ensureEngine()
            let query = skillsShQuery
            let board = skillsShBoard
            skillsShLoading = true
            skillsShError = nil
            Task {
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            return try engine.fetchSkillsShLeaderboard(board: board)
                        }
                        return try engine.searchSkillsSh(query: trimmed, limit: 60)
                    }.value
                    await MainActor.run {
                        skillsShSkills = result
                        skillsShLoading = false
                    }
                } catch {
                    await MainActor.run {
                        skillsShError = error.localizedDescription
                        skillsShLoading = false
                    }
                }
            }
        } catch {
            skillsShError = error.localizedDescription
        }
    }

    private func installSkillssh(_ skill: SkillsShSkill) {
        run(L("正在从 skills.sh 安装 Skill…")) { engine in
            _ = try engine.installSkillsshSkill(source: skill.source, skillID: skill.skillID)
        }
    }

    private func runCommandTask(_ action: SkillCommandAction) {
        switch action {
        case .market:
            selectedSection = .discovered
            if skillsShSkills.isEmpty { loadSkillsShMarket() }
        case .importLocal:
            importLocal()
        case .scan:
            reload(scan: true)
        case .agents:
            selectedSection = .agents
        case .syncUnsynced:
            syncUnsyncedSkills()
        case .updateAvailable:
            updateAvailableSkills()
        case .library:
            let problemIDs = skills
                .filter { ["source_missing", "error"].contains($0.updateStatus) }
                .map(\.id)
            if !problemIDs.isEmpty {
                selectedSkillIDs = Set(problemIDs)
                if let first = skills.first(where: { problemIDs.contains($0.id) }) {
                    inspectSkill(first)
                }
            }
            selectedSection = .library
        case .checkUpdates:
            checkAllSkillUpdates()
        }
    }

    private func toggleString(_ value: String, in set: inout Set<String>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func inspectSkill(_ skill: ManagedSkill) {
        inspectedSkillID = skill.id
        if skillDocuments[skill.id] == nil {
            loadSkillDetails(skill)
        }
    }

    private func openSkillDetail(_ skill: ManagedSkill, tab: SkillDetailTab = .overview) {
        inspectedSkillID = skill.id
        detailSkillID = skill.id
        detailTab = tab
        if skillDocuments[skill.id] == nil {
            loadSkillDetails(skill)
        }
    }

    private func toggleSkillExpansion(_ skill: ManagedSkill) {
        let opening = expandedSkillID != skill.id
        withAnimation(Motion.expand) {
            expandedSkillID = opening ? skill.id : nil
        }
        if opening {
            inspectedSkillID = skill.id
            loadSkillDetails(skill)
        }
    }

    private func loadSkillDetails(_ skill: ManagedSkill) {
        do {
            let engine = try ensureEngine()
            Task {
                do {
                    let details = try await Task.detached(priority: .userInitiated) {
                        (
                            try engine.readSkillDocument(skillID: skill.id),
                            try engine.listSkillFiles(skillID: skill.id),
                            skill.updateStatus == "update_available"
                                ? try? engine.readSkillSourceDiff(skillID: skill.id)
                                : nil
                        )
                    }.value
                    await MainActor.run {
                        skillDocuments[skill.id] = details.0
                        skillFiles[skill.id] = details.1
                        skillDiffs[skill.id] = details.2
                    }
                } catch {
                    await MainActor.run {
                        skillDocuments[skill.id] = nil
                        skillFiles[skill.id] = []
                        skillDiffs[skill.id] = nil
                    }
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refreshSkillFromSource(_ skill: ManagedSkill) {
        run(L("正在从来源刷新 Skill…")) { engine in
            _ = try engine.refreshSkillFromSource(id: skill.id)
        }
        skillDocuments[skill.id] = nil
        skillFiles[skill.id] = []
        skillDiffs[skill.id] = nil
    }

    private func checkSkillUpdate(_ skill: ManagedSkill) {
        run(L("正在检查 Skill 更新…")) { engine in
            _ = try engine.checkSkillUpdate(id: skill.id)
        }
    }

    private func relinkSkillSource(_ skill: ManagedSkill) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("绑定")
        panel.message = L("选择新的 Skill 来源目录、父目录或 .zip 包")
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        let bookmarkData = SecurityScopedBookmarks.bookmarkData(for: url)

        run(L("正在重新绑定来源…")) { engine in
            _ = try engine.relinkSkillSource(
                id: skill.id,
                source: url,
                sourceBookmarkData: bookmarkData)
        }
    }

    private func detachSkillSource(_ skill: ManagedSkill) {
        run(L("正在解除来源绑定…")) { engine in
            _ = try engine.detachSkillSource(id: skill.id)
        }
    }

    private func syncSelectedSkills() {
        let mode = selectedSyncMode
        let ids = Array(selectedSkillIDs)
        let toolKeys = availableTools.map(\.key)
        run(L("正在批量同步 Skills…")) { engine in
            for id in ids {
                for toolKey in toolKeys {
                    _ = try engine.syncSkill(id: id, toTool: toolKey, mode: mode)
                }
            }
        }
    }

    private func syncUnsyncedSkills() {
        let mode = selectedSyncMode
        let ids = skills.filter(\.targets.isEmpty).map(\.id)
        let toolKeys = availableTools.map(\.key)
        guard !ids.isEmpty, !toolKeys.isEmpty else { return }
        run(L("正在分发未同步 Skills…")) { engine in
            for id in ids {
                for toolKey in toolKeys {
                    _ = try engine.syncSkill(id: id, toTool: toolKey, mode: mode)
                }
            }
        }
    }

    private func refreshSelectedSkills() {
        let ids = selectedSkills
            .filter(canRefreshFromSource)
            .map(\.id)
        guard !ids.isEmpty else { return }
        run(L("正在批量刷新来源…")) { engine in
            for id in ids {
                _ = try engine.refreshSkillFromSource(id: id)
            }
        }
        for id in ids {
            skillDocuments[id] = nil
            skillFiles[id] = []
            skillDiffs[id] = nil
        }
    }

    private func checkSelectedSkillUpdates() {
        let ids = selectedSkills
            .filter(canRefreshFromSource)
            .map(\.id)
        guard !ids.isEmpty else { return }
        run(L("正在批量检查更新…")) { engine in
            _ = try engine.checkSkillUpdates(ids: ids)
        }
    }

    private func checkAllSkillUpdates() {
        let ids = skills
            .filter(canRefreshFromSource)
            .map(\.id)
        guard !ids.isEmpty else { return }
        run(L("正在检查全部 Skill 更新…")) { engine in
            _ = try engine.checkSkillUpdates(ids: ids)
        }
    }

    private func updateAvailableSkills() {
        let ids = updatableSkills.map(\.id)
        guard !ids.isEmpty else { return }
        run(L("正在更新可用 Skills…")) { engine in
            for id in ids {
                _ = try engine.refreshSkillFromSource(id: id)
            }
        }
        for id in ids {
            skillDocuments[id] = nil
            skillFiles[id] = []
            skillDiffs[id] = nil
        }
    }

    private func deleteSelectedSkills() {
        let ids = Array(selectedSkillIDs)
        guard !ids.isEmpty else { return }
        run(L("正在批量删除 Skills…"), scanAfter: true) { engine in
            for id in ids {
                try engine.deleteSkill(id: id)
            }
        }
        selectedSkillIDs.removeAll()
    }

    private func canRefreshFromSource(_ skill: ManagedSkill) -> Bool {
        switch skill.sourceType {
        case .local, .imported, .git, .skillssh:
            return skill.sourceRef?.isEmpty == false
        }
    }

    private func toggleSkillSelection(_ skillID: String) {
        if selectedSkillIDs.contains(skillID) {
            selectedSkillIDs.remove(skillID)
        } else {
            selectedSkillIDs.insert(skillID)
        }
    }

    private func selectAllFilteredSkills() {
        selectedSkillIDs.formUnion(filteredSkills.map(\.id))
    }

    private func applyTagToSelection(add: Bool) {
        let tag = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = Array(selectedSkillIDs)
        guard !tag.isEmpty, !ids.isEmpty else { return }
        run(add ? L("正在添加标签…") : L("正在移除标签…")) { engine in
            if add {
                try engine.addTag(tag, toSkillIDs: ids)
            } else {
                try engine.removeTag(tag, fromSkillIDs: ids)
            }
        }
    }

    private func createPreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newPresetName = ""
        run(L("正在创建 Preset…")) { engine in
            _ = try engine.createPreset(name: name)
        }
    }

    private func deletePreset(_ preset: SkillPreset) {
        run(L("正在删除 Preset…")) { engine in
            try engine.deletePreset(id: preset.id)
        }
    }

    private func togglePresetSkill(preset: SkillPreset, skill: ManagedSkill, enabled: Bool) {
        run(enabled ? L("正在加入 Preset…") : L("正在移出 Preset…")) { engine in
            if enabled {
                _ = try engine.addSkillToPreset(presetID: preset.id, skillID: skill.id)
            } else {
                _ = try engine.removeSkillFromPreset(presetID: preset.id, skillID: skill.id)
            }
        }
    }

    private func movePresetSkill(preset: SkillPreset, skill: ManagedSkill, offset: Int) {
        run(L("正在调整 Preset 顺序…")) { engine in
            _ = try engine.moveSkillInPreset(
                presetID: preset.id,
                skillID: skill.id,
                offset: offset)
        }
    }

    private func applyPreset(_ preset: SkillPreset) {
        let mode = selectedSyncMode
        let toolKeys = availableTools.map(\.key)
        run(L("正在应用 Preset…")) { engine in
            _ = try engine.applyPreset(id: preset.id, toTools: toolKeys, mode: mode)
        }
    }

    private func removePreset(_ preset: SkillPreset) {
        let toolKeys = availableTools.map(\.key)
        run(L("正在移除 Preset 同步…")) { engine in
            try engine.removePreset(id: preset.id, fromTools: toolKeys)
        }
    }

    private func deleteProject(_ project: SkillProject) {
        run(L("正在移除项目…")) { engine in
            try engine.deleteProject(id: project.id)
        }
    }

    private func toggleProjectSkill(project: SkillProject,
                                    skill: ManagedSkill,
                                    tool: SkillToolInfo,
                                    enabled: Bool) {
        let mode = selectedSyncMode
        run(enabled ? L("正在同步到项目…") : L("正在移除项目同步…")) { engine in
            if enabled {
                _ = try engine.syncSkillToProject(
                    skillID: skill.id,
                    projectID: project.id,
                    toolKey: tool.key,
                    mode: mode)
            } else {
                try engine.unsyncSkillFromProject(
                    skillID: skill.id,
                    projectID: project.id,
                    toolKey: tool.key)
            }
        }
    }

    private func applyPresetToProject(preset: SkillPreset, project: SkillProject) {
        let mode = selectedSyncMode
        let toolKeys = projectTools.map(\.key)
        run(L("正在应用 Preset 到项目…")) { engine in
            _ = try engine.applyPresetToProject(
                presetID: preset.id,
                projectID: project.id,
                toolKeys: toolKeys,
                mode: mode)
        }
    }

    private func removePresetFromProject(preset: SkillPreset, project: SkillProject) {
        let toolKeys = projectTools.map(\.key)
        run(L("正在移除项目 Preset…")) { engine in
            try engine.removePresetFromProject(
                presetID: preset.id,
                projectID: project.id,
                toolKeys: toolKeys)
        }
    }

    private func toggle(skill: ManagedSkill, tool: SkillToolInfo, enabled: Bool) {
        let mode = selectedSyncMode
        run(enabled ? L("正在同步 Skill…") : L("正在移除同步…")) { engine in
            if enabled {
                _ = try engine.syncSkill(id: skill.id, toTool: tool.key, mode: mode)
            } else {
                try engine.unsyncSkill(id: skill.id, fromTool: tool.key)
            }
        }
    }

    private func toggleToolEnabled(_ tool: SkillToolInfo) {
        run(tool.enabled ? L("正在停用 Agent…") : L("正在启用 Agent…")) { engine in
            try engine.setToolEnabled(tool.key, enabled: !tool.enabled)
        }
    }

    private func syncAll(_ skill: ManagedSkill) {
        let mode = selectedSyncMode
        let toolKeys = availableTools.map(\.key)
        run(L("正在同步到所有可用 Agent…")) { engine in
            for toolKey in toolKeys {
                _ = try engine.syncSkill(id: skill.id, toTool: toolKey, mode: mode)
            }
        }
    }

    private func delete(_ skill: ManagedSkill) {
        run(L("正在删除 Skill…"), scanAfter: true) { engine in
            try engine.deleteSkill(id: skill.id)
        }
    }

    private func run(_ message: String,
                     scanAfter: Bool = false,
                     operation: @escaping @Sendable (SkillManagerEngine) throws -> Void) {
        do {
            let engine = try ensureEngine()
            loading = true
            loadingText = message
            error = nil

            Task {
                do {
                    let payload = try await Task.detached(priority: .userInitiated) {
                        try operation(engine)
                        let result = scanAfter ? try engine.scanLocalSkills() : nil
                        let projects = engine.listProjects()
                        return SkillManagerPayload(
                            skills: engine.listSkills(),
                            tools: engine.tools(),
                            presets: engine.listPresets(),
                            presetSummaries: engine.presetSummaries(),
                            projects: projects,
                            projectTargets: engine.listProjectTargets(),
                            projectSkills: Dictionary(
                                uniqueKeysWithValues: projects.map {
                                    ($0.id, engine.readProjectSkills(projectID: $0.id))
                                }),
                            auditEntries: engine.listAudit(limit: 140),
                            scanResult: result)
                    }.value
                    await MainActor.run {
                        skills = payload.skills
                        tools = payload.tools
                        presets = payload.presets
                        presetSummaries = payload.presetSummaries
                        projects = payload.projects
                        projectTargets = payload.projectTargets
                        projectSkills = payload.projectSkills
                        auditEntries = payload.auditEntries
                        selectedSkillIDs = selectedSkillIDs.intersection(Set(payload.skills.map(\.id)))
                        if let inspectedSkillID,
                           !payload.skills.contains(where: { $0.id == inspectedSkillID }) {
                            self.inspectedSkillID = payload.skills.first?.id
                        } else if inspectedSkillID == nil {
                            inspectedSkillID = payload.skills.first?.id
                        }
                        if let result = payload.scanResult { scanResult = result }
                        loading = false
                        loadingText = ""
                    }
                } catch {
                    await MainActor.run {
                        self.error = error.localizedDescription
                        loading = false
                        loadingText = ""
                    }
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func ensureEngine() throws -> SkillManagerEngine {
        if let engine { return engine }
        let created = try SkillManagerEngine()
        engine = created
        return created
    }

    private var selectedSyncMode: SkillTargetRecord.Mode {
        syncMode == "copy" ? .copy : .symlink
    }

    private var syncModeLabel: String {
        selectedSyncMode == .copy ? L("复制") : L("软链")
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func iconButton(_ icon: String,
                            help: String,
                            destructive: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(destructive ? Color(red: 0.92, green: 0.34, blue: 0.34) : AppStyle.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(AppStyle.hoverFill))
        }
        .buttonStyle(PressScaleStyle())
        .help(help)
    }

    private func metricChip(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
            Text(value)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(AppStyle.textSecondary)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.hoverFill))
    }

    private func filterChip(title: String,
                            active: Bool,
                            color: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? .white : AppStyle.textSecondary)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(active ? color : AppStyle.hoverFill))
        }
        .buttonStyle(PressScaleStyle())
    }

    private func toolSort(_ lhs: SkillToolInfo, _ rhs: SkillToolInfo) -> Bool {
        if lhs.installed != rhs.installed { return lhs.installed && !rhs.installed }
        if lhs.category != rhs.category { return lhs.category.rawValue < rhs.category.rawValue }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}

private enum SkillManagerSection: String, CaseIterable, Identifiable {
    case command
    case library
    case presets
    case projects
    case agents
    case activity
    case discovered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .command: return L("工作台")
        case .library: return L("技能库")
        case .presets: return "Presets"
        case .projects: return L("项目")
        case .agents: return "Agents"
        case .activity: return L("活动")
        case .discovered: return L("发现")
        }
    }

    var icon: String {
        switch self {
        case .command: return "rectangle.3.group"
        case .library: return "square.stack.3d.up"
        case .presets: return "rectangle.stack.badge.plus"
        case .projects: return "folder.badge.gearshape"
        case .agents: return "cpu"
        case .activity: return "clock.arrow.circlepath"
        case .discovered: return "scope"
        }
    }
}

private enum SkillDetailTab: String, CaseIterable, Identifiable {
    case overview
    case deploy
    case docs
    case source
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L("总览")
        case .deploy: return L("部署")
        case .docs: return L("文档")
        case .source: return L("来源")
        case .activity: return L("活动")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .deploy: return "point.3.connected.trianglepath.dotted"
        case .docs: return "doc.text.magnifyingglass"
        case .source: return "link"
        case .activity: return "clock.arrow.circlepath"
        }
    }
}

private enum SkillCommandAction {
    case market
    case importLocal
    case scan
    case agents
    case syncUnsynced
    case updateAvailable
    case library
    case checkUpdates
}

private struct SkillCommandTask: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let count: Int?
    let tint: Color
    let action: SkillCommandAction
}

private struct SkillReadinessItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let ready: Bool
    let icon: String
    let color: Color
}

private enum SkillCueAction {
    case overview
    case deploy
    case docs
    case source
    case loadDetails
    case checkUpdate
}

private struct SkillActionCue {
    let icon: String
    let title: String
    let detail: String
    let color: Color
    let actionTitle: String
    let action: SkillCueAction
}

private enum SkillPipelineState {
    case ready
    case attention
    case error

    var symbol: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .attention: return "circle.dashed"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    @MainActor
    var color: Color {
        switch self {
        case .ready: return AppStyle.accent
        case .attention: return .orange
        case .error: return .red
        }
    }
}

private struct SkillPipelineStep: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let state: SkillPipelineState
}

private struct SkillActionCuePanel: View {
    let cue: SkillActionCue
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: cue.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(cue.color)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(cue.color.opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                Text(cue.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                Text(cue.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Label(cue.actionTitle, systemImage: "arrow.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(cue.color))
            }
            .buttonStyle(PressScaleStyle())
            .help(cue.actionTitle)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(cue.color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(cue.color.opacity(0.22), lineWidth: 1))
        .animation(Motion.snappy, value: cue.title)
    }
}

private struct SkillPipeline: View {
    let steps: [SkillPipelineStep]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                SkillPipelineNode(step: step)
                    .frame(maxWidth: .infinity)
                if index < steps.count - 1 {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(step.state.color.opacity(0.45))
                        .frame(width: 22, height: 3)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AppStyle.hoverFill.opacity(0.40)))
        .animation(Motion.expand, value: steps.map { "\($0.id):\($0.detail)" }.joined(separator: "|"))
    }
}

private struct SkillPipelineNode: View {
    let step: SkillPipelineStep

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: step.state.symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(step.state.color)
                Image(systemName: step.icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textTertiary)
                Spacer(minLength: 0)
            }
            Text(step.title)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1)
            Text(step.detail)
                .font(.system(size: 9.5))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(step.state.color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(step.state.color.opacity(0.16), lineWidth: 1))
        .animation(Motion.snappy, value: step.detail)
    }
}

private struct SkillToolbarButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AppStyle.hoverFill.opacity(hovering ? 0.82 : 0.58)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(color.opacity(hovering ? 0.22 : 0), lineWidth: 1))
                .offset(y: hovering ? -1 : 0)
                .shadow(color: color.opacity(hovering ? 0.12 : 0), radius: 8, y: 3)
        }
        .buttonStyle(PressScaleStyle())
        .help(title)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

private struct SkillCommandRow: View {
    let skill: ManagedSkill
    let active: Bool
    let healthColor: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(active ? AppStyle.accent : healthColor)
                    .frame(width: active ? 4 : 2, height: active ? 42 : 8)
                    .padding(.top, active ? 0 : 5)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(skill.name)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                        if skill.updateStatus == "update_available" {
                            tinyBadge(L("可更新"), color: .orange)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    Text((skill.description?.isEmpty == false) ? skill.description! : collapsedPath(skill.centralPath))
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        tinyBadge(skill.sourceType.rawValue, color: AppStyle.textTertiary)
                        tinyBadge(L("%ld Agent", skill.targets.count), color: skill.targets.isEmpty ? AppStyle.textTertiary : AppStyle.accent)
                    }
                }
                Spacer(minLength: 2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(active || hovering ? AppStyle.accent : AppStyle.textTertiary.opacity(0.45))
                    .padding(.top, 4)
                    .opacity(active || hovering ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(active ? AppStyle.accent.opacity(0.14) : AppStyle.hoverFill.opacity(hovering ? 0.68 : 0.52)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(active ? AppStyle.accent.opacity(0.35) : healthColor.opacity(hovering ? 0.18 : 0), lineWidth: 1)
            )
            .offset(x: hovering && !active ? 2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .animation(Motion.snappy, value: active)
        .animation(Motion.snappy, value: skill.updateStatus)
    }
}

private struct SkillDetailCockpit: View {
    let skill: ManagedSkill
    let tools: [SkillToolInfo]
    let document: SkillDocument?
    let files: [SkillFileInfo]
    let sourceDiff: SkillSourceDiff?
    let auditEntries: [SkillAuditEntry]
    let readinessItems: [SkillReadinessItem]
    @Binding var selectedTab: SkillDetailTab
    let syncMode: String
    let canRefreshFromSource: Bool
    let onClose: () -> Void
    let onSyncAll: () -> Void
    let onToggleTool: (SkillToolInfo, Bool) -> Void
    let onCheckUpdate: () -> Void
    let onRefreshSource: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void
    let onLoadDetails: () -> Void

    private var targetByTool: [String: SkillTargetRecord] {
        Dictionary(skill.targets.map { ($0.tool, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var readinessScore: Double {
        guard !readinessItems.isEmpty else { return 0 }
        return Double(readinessItems.filter(\.ready).count) / Double(readinessItems.count)
    }

    private var readinessLabel: String {
        "\(Int((readinessScore * 100).rounded()))%"
    }

    private var healthColor: Color {
        switch skill.updateStatus {
        case "update_available": return .orange
        case "source_missing", "error": return .red
        default:
            return skill.targets.isEmpty ? AppStyle.textTertiary : AppStyle.accent
        }
    }

    private var updateLabel: String {
        switch skill.updateStatus {
        case "current": return L("最新")
        case "update_available": return L("可更新")
        case "source_missing": return L("来源失效")
        case "error": return L("检查失败")
        case "unsupported": return L("不支持更新")
        default: return L("未知")
        }
    }

    private var sortedFiles: [SkillFileInfo] {
        files.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
    }

    private var deploymentCoverage: Double {
        guard !tools.isEmpty else { return 0 }
        return Double(skill.targets.count) / Double(tools.count)
    }

    private var deploymentCoverageLabel: String {
        guard !tools.isEmpty else { return "--" }
        return "\(Int((deploymentCoverage * 100).rounded()))%"
    }

    private var totalFileBytes: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    private var fileProfileSegments: [SkillProfileSegment] {
        let markdown = files.filter { isMarkdownFile($0.relativePath) }.count
        let code = files.filter { isCodeFile($0.relativePath) }.count
        let assets = files.filter { isAssetFile($0.relativePath) }.count
        let other = max(0, files.count - markdown - code - assets)
        return [
            SkillProfileSegment(title: L("文档"), count: markdown, color: AppStyle.accent),
            SkillProfileSegment(title: L("代码"), count: code, color: .orange),
            SkillProfileSegment(title: L("资产"), count: assets, color: Color(red: 0.58, green: 0.48, blue: 0.92)),
            SkillProfileSegment(title: L("其他"), count: other, color: AppStyle.textTertiary),
        ].filter { $0.count > 0 }
    }

    private var documentKnown: Bool {
        document != nil || files.contains { $0.relativePath.lowercased() == "skill.md" }
    }

    private var sourceProblem: Bool {
        ["source_missing", "error"].contains(skill.updateStatus)
    }

    private var nextCue: SkillActionCue {
        if sourceProblem {
            return SkillActionCue(
                icon: "exclamationmark.triangle.fill",
                title: L("来源需要处理"),
                detail: skill.lastCheckError?.isEmpty == false ? skill.lastCheckError! : L("这个 Skill 的来源不可用或更新检查失败，先进入来源页确认绑定信息。"),
                color: .red,
                actionTitle: L("查看来源"),
                action: .source)
        }
        if skill.updateStatus == "update_available" {
            return SkillActionCue(
                icon: "arrow.down.circle.fill",
                title: L("发现可更新版本"),
                detail: L("来源里已有新版内容，可以先看差异再决定刷新中央库。"),
                color: .orange,
                actionTitle: L("查看差异"),
                action: .source)
        }
        if !documentKnown {
            return SkillActionCue(
                icon: "doc.text.magnifyingglass",
                title: L("先读取 Skill 文档"),
                detail: L("读取 SKILL.md 和文件清单后，就绪检查、文档预览和来源差异会更完整。"),
                color: AppStyle.accent,
                actionTitle: L("读取文档"),
                action: .loadDetails)
        }
        if skill.targets.isEmpty {
            return SkillActionCue(
                icon: "point.3.connected.trianglepath.dotted",
                title: L("还没有分发到 Agent"),
                detail: L("这个 Skill 已进入中央库，但还没有同步到任何可用 Agent。"),
                color: .orange,
                actionTitle: L("打开部署"),
                action: .deploy)
        }
        if readinessScore < 1 {
            return SkillActionCue(
                icon: "wrench.and.screwdriver.fill",
                title: L("还有整理项"),
                detail: L("就绪检查里仍有可优化项目，优先补齐描述、标签或来源状态。"),
                color: .orange,
                actionTitle: L("看检查项"),
                action: .overview)
        }
        return SkillActionCue(
            icon: "checkmark.seal.fill",
            title: L("状态稳定"),
            detail: L("文档、来源和部署状态都健康，可以定期检查更新。"),
            color: AppStyle.accent,
            actionTitle: L("检查更新"),
            action: .checkUpdate)
    }

    private var pipelineSteps: [SkillPipelineStep] {
        [
            SkillPipelineStep(
                id: "docs",
                title: L("文档"),
                detail: documentKnown ? L("已读取") : L("待读取"),
                icon: "doc.text",
                state: documentKnown ? .ready : .attention),
            SkillPipelineStep(
                id: "source",
                title: L("来源"),
                detail: sourceProblem ? updateLabel : (canRefreshFromSource ? L("可维护") : L("静态")),
                icon: "link",
                state: sourceProblem ? .error : .ready),
            SkillPipelineStep(
                id: "deploy",
                title: L("分发"),
                detail: skill.targets.isEmpty ? L("未分发") : L("%ld Agent", skill.targets.count),
                icon: "point.3.connected.trianglepath.dotted",
                state: skill.targets.isEmpty ? .attention : .ready),
            SkillPipelineStep(
                id: "maintain",
                title: L("维护"),
                detail: skill.updateStatus == "update_available" ? L("可更新") : updateLabel,
                icon: "checkmark.seal",
                state: skill.updateStatus == "update_available" ? .attention : (sourceProblem ? .error : .ready)),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(AppStyle.separator.opacity(0.18))
                .frame(height: 1)
            HStack(spacing: 0) {
                tabRail
                    .frame(width: 164)
                Rectangle()
                    .fill(AppStyle.separator.opacity(0.14))
                    .frame(width: 1)
                ScrollView {
                    selectedContent
                        .id(selectedTab)
                        .padding(16)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .scrollIndicators(.never)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(Motion.panel, value: selectedTab)
        .animation(Motion.snappy, value: skill.targets.count)
        .animation(Motion.snappy, value: skill.updateStatus)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(healthColor.opacity(0.13))
                    Image(systemName: sourceIcon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(healthColor)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Text(skill.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                        tinyBadge(skill.sourceType.rawValue, color: AppStyle.textTertiary)
                        tinyBadge(updateLabel, color: healthColor)
                        if skill.targets.isEmpty {
                            tinyBadge(L("未分发"), color: .orange)
                        } else {
                            tinyBadge(L("%ld Agent", skill.targets.count), color: AppStyle.accent)
                        }
                    }
                    Text((skill.description?.isEmpty == false) ? skill.description! : collapsedPath(skill.centralPath))
                        .font(.system(size: 12))
                        .foregroundStyle(AppStyle.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                SkillScoreDial(
                    value: readinessScore,
                    label: readinessLabel,
                    caption: L("就绪"),
                    color: readinessScore >= 1 ? AppStyle.accent : healthColor)

                HStack(spacing: 4) {
                    iconButton("folder", help: L("在 Finder 显示"), action: onReveal)
                    iconButton("trash", help: L("删除 Skill"), destructive: true, action: onDelete)
                    iconButton("xmark", help: L("关闭"), action: onClose)
                }
            }

            HStack(spacing: 8) {
                cockpitActionButton(
                    title: L("同步全部"),
                    icon: "arrow.triangle.2.circlepath",
                    primary: true,
                    action: onSyncAll)

                if canRefreshFromSource {
                    cockpitActionButton(
                        title: L("检查更新"),
                        icon: "magnifyingglass.circle",
                        primary: false,
                        action: onCheckUpdate)
                    cockpitActionButton(
                        title: L("刷新来源"),
                        icon: "arrow.clockwise.circle",
                        primary: false,
                        action: onRefreshSource)
                }

                cockpitActionButton(
                    title: L("读取文档"),
                    icon: "doc.text.magnifyingglass",
                    primary: false,
                    action: onLoadDetails)

                Spacer()

                Text(collapsedPath(skill.centralPath))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(18)
    }

    private var tabRail: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SkillDetailTab.allCases) { tab in
                Button {
                    withAnimation(Motion.snappy) { selectedTab = tab }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11.5, weight: .semibold))
                            .frame(width: 17)
                        Text(tab.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let value = tabValue(tab) {
                            Text(value)
                                .font(.system(size: 8.8, weight: .bold))
                                .foregroundStyle(selectedTab == tab ? .white.opacity(0.86) : tabValueColor(tab))
                                .padding(.horizontal, 5)
                                .frame(height: 17)
                                .background(Capsule().fill((selectedTab == tab ? Color.white : tabValueColor(tab)).opacity(0.13)))
                        }
                    }
                    .foregroundStyle(selectedTab == tab ? .white : AppStyle.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selectedTab == tab ? AppStyle.accent : Color.clear))
                }
                .buttonStyle(.plain)
                .help(tabValue(tab).map { "\(tab.title) \($0)" } ?? tab.title)
                .animation(Motion.snappy, value: selectedTab)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                SkillRailStat(title: L("同步模式"), value: syncMode, color: AppStyle.textSecondary)
                SkillRailStat(title: L("文件"), value: "\(files.count)", color: AppStyle.textSecondary)
                SkillRailStat(title: L("最近检查"), value: skill.lastCheckedAt.map { $0.formatted(date: .numeric, time: .shortened) } ?? "--", color: AppStyle.textTertiary)
            }
        }
        .padding(12)
        .background(AppStyle.hoverFill.opacity(0.14))
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .overview:
            overviewContent
        case .deploy:
            deployContent
        case .docs:
            docsContent
        case .source:
            sourceContent
        case .activity:
            activityContent
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkillActionCuePanel(cue: nextCue) {
                runCueAction(nextCue.action)
            }

            SkillPipeline(steps: pipelineSteps)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150), spacing: 10),
            ], spacing: 10) {
                SkillMetricTile(
                    icon: "checkmark.seal",
                    title: L("健康度"),
                    value: readinessLabel,
                    detail: L("%ld / %ld 项就绪", readinessItems.filter(\.ready).count, readinessItems.count),
                    color: readinessScore >= 1 ? AppStyle.accent : .orange)
                SkillMetricTile(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: L("部署"),
                    value: L("%ld / %ld", skill.targets.count, tools.count),
                    detail: skill.targets.isEmpty ? L("尚未进入 Agent") : L("已分发"),
                    color: skill.targets.isEmpty ? .orange : AppStyle.accent)
                SkillMetricTile(
                    icon: "arrow.down.circle",
                    title: L("更新"),
                    value: updateLabel,
                    detail: skill.lastCheckError?.isEmpty == false ? skill.lastCheckError! : (skill.lastCheckedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? L("未检查")),
                    color: healthColor)
                SkillMetricTile(
                    icon: "doc.on.doc",
                    title: L("内容"),
                    value: L("%ld 文件", files.count),
                    detail: document?.filename ?? "SKILL.md",
                    color: AppStyle.textSecondary)
            }

            SkillCockpitPanel(icon: "waveform.path.ecg", title: L("就绪检查")) {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 180), spacing: 8),
                ], spacing: 8) {
                    ForEach(readinessItems) { item in
                        SkillReadinessCard(item: item)
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                sourceBlueprint
                deploymentSnapshot
            }
        }
    }

    private var deployContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                cockpitActionButton(
                    title: L("同步到所有可用 Agent"),
                    icon: "arrow.triangle.2.circlepath",
                    primary: true,
                    action: onSyncAll)
                tinyBadge("\(L("当前模式")) \(syncMode)", color: AppStyle.textTertiary)
                Spacer()
            }

            SkillCoverageStrip(
                icon: "antenna.radiowaves.left.and.right",
                title: L("部署覆盖率"),
                value: deploymentCoverageLabel,
                detail: tools.isEmpty
                    ? L("还没有可用 Agent")
                    : L("%ld 个已同步，%ld 个待同步", skill.targets.count, max(0, tools.count - skill.targets.count)),
                color: skill.targets.isEmpty ? .orange : AppStyle.accent,
                progress: tools.isEmpty ? nil : deploymentCoverage)

            SkillCockpitPanel(icon: "point.3.connected.trianglepath.dotted", title: L("Agent 部署矩阵")) {
                if tools.isEmpty {
                    emptyCockpitState(icon: "cpu", title: L("没有可用 Agent"))
                } else {
                    VStack(spacing: 7) {
                        ForEach(tools) { tool in
                            SkillDeploymentLane(
                                tool: tool,
                                target: targetByTool[tool.key],
                                onToggle: {
                                    onToggleTool(tool, targetByTool[tool.key] == nil)
                                })
                        }
                    }
                }
            }
        }
    }

    private var docsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkillFileProfilePanel(
                documentKnown: documentKnown,
                totalFiles: files.count,
                totalBytes: totalFileBytes,
                segments: fileProfileSegments,
                onLoadDetails: onLoadDetails)

            HStack(alignment: .top, spacing: 12) {
                SkillCockpitPanel(icon: "doc.text.magnifyingglass", title: document?.filename ?? "SKILL.md") {
                    if let document {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                tinyBadge(byteCount(Int64(document.content.utf8.count)), color: AppStyle.textTertiary)
                                if document.truncated {
                                    tinyBadge(L("已截断"), color: .orange)
                                }
                                Spacer()
                                Button(action: onLoadDetails) {
                                    Label(L("重读"), systemImage: "arrow.clockwise")
                                        .font(.system(size: 10.5, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                            }
                            ScrollView {
                                Text(String(document.content.prefix(10_000)))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(AppStyle.textSecondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                            }
                            .frame(minHeight: 360)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppStyle.hoverFill.opacity(0.50)))
                        }
                    } else {
                        Button(action: onLoadDetails) {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 22, weight: .semibold))
                                Text(L("读取 SKILL.md"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(AppStyle.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppStyle.hoverFill.opacity(0.50)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)

                SkillCockpitPanel(icon: "doc.on.doc", title: L("文件")) {
                    if sortedFiles.isEmpty {
                        emptyCockpitState(icon: "folder", title: L("尚未读取文件列表"))
                    } else {
                        VStack(spacing: 5) {
                            ForEach(Array(sortedFiles.prefix(28))) { file in
                                SkillFileListRow(file: file)
                            }
                            if sortedFiles.count > 28 {
                                Text(L("还有 %ld 个文件", sortedFiles.count - 28))
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppStyle.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(width: 290)
            }
        }
    }

    private var sourceContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            sourceBlueprint

            if let sourceDiff {
                SkillDiffStatsPanel(entries: sourceDiff.entries)
            }

            SkillCockpitPanel(icon: "arrow.left.arrow.right", title: L("来源差异")) {
                if let sourceDiff {
                    if sourceDiff.entries.isEmpty {
                        emptyCockpitState(icon: "checkmark.seal", title: L("来源与中央库一致"))
                    } else {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 6) {
                                tinyBadge(collapsedPath(sourceDiff.sourcePath), color: AppStyle.textTertiary)
                                tinyBadge(L("%ld 个文件", sourceDiff.entries.count), color: .orange)
                                Spacer()
                            }

                            ForEach(Array(sourceDiff.entries.prefix(10))) { entry in
                                SkillDiffSummaryRow(entry: entry)
                            }

                            if let firstText = sourceDiff.entries.first(where: {
                                $0.originalContent != nil || $0.updatedContent != nil
                            }) {
                                SkillDiffPreview(entry: firstText)
                            }
                        }
                    }
                } else if skill.updateStatus == "update_available" {
                    Button(action: onLoadDetails) {
                        Label(L("读取来源差异"), systemImage: "arrow.left.arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppStyle.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppStyle.hoverFill.opacity(0.50)))
                    }
                    .buttonStyle(.plain)
                } else {
                    emptyCockpitState(icon: "checkmark.seal", title: L("暂无可展示差异"))
                }
            }
        }
    }

    private var activityContent: some View {
        SkillCockpitPanel(icon: "clock.arrow.circlepath", title: L("Skill 活动")) {
            if auditEntries.isEmpty {
                emptyCockpitState(icon: "clock", title: L("这个 Skill 暂无活动记录"))
            } else {
                VStack(spacing: 8) {
                    ForEach(auditEntries.prefix(32)) { entry in
                        SkillActivityLine(entry: entry)
                    }
                }
            }
        }
    }

    private var sourceBlueprint: some View {
        SkillCockpitPanel(icon: "link", title: L("来源与标识")) {
            VStack(spacing: 8) {
                SkillKeyValueRow(label: L("中央库"), value: collapsedPath(skill.centralPath))
                SkillKeyValueRow(label: L("来源类型"), value: skill.sourceType.rawValue)
                if let sourceRef = skill.sourceRef {
                    SkillKeyValueRow(label: "source", value: sourceRef)
                }
                if let sourceSubpath = skill.sourceSubpath {
                    SkillKeyValueRow(label: "subpath", value: sourceSubpath)
                }
                if let sourceBranch = skill.sourceBranch {
                    SkillKeyValueRow(label: "ref", value: sourceBranch)
                }
                if let sourceRevision = skill.sourceRevision {
                    SkillKeyValueRow(label: "rev", value: String(sourceRevision.prefix(12)))
                }
                if let remoteRevision = skill.remoteRevision {
                    SkillKeyValueRow(label: "remote", value: String(remoteRevision.prefix(12)))
                }
                if let contentHash = skill.contentHash {
                    SkillKeyValueRow(label: "hash", value: String(contentHash.prefix(12)))
                }
                SkillKeyValueRow(label: L("状态"), value: "\(skill.status) / \(updateLabel)")
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
    }

    private var deploymentSnapshot: some View {
        SkillCockpitPanel(icon: "cpu", title: L("部署快照")) {
            if skill.targets.isEmpty {
                emptyCockpitState(icon: "point.3.connected.trianglepath.dotted", title: L("尚未分发"))
            } else {
                VStack(spacing: 6) {
                    ForEach(skill.targets.prefix(6)) { target in
                        HStack(spacing: 7) {
                            Image(systemName: target.status == "ok" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(target.status == "ok" ? AppStyle.accent : .orange)
                            Text(target.tool)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(AppStyle.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(target.mode.rawValue)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(AppStyle.textTertiary)
                        }
                        Text(collapsedPath(target.targetPath))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(AppStyle.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if skill.targets.count > 6 {
                        Text(L("还有 %ld 个目标", skill.targets.count - 6))
                            .font(.system(size: 10))
                            .foregroundStyle(AppStyle.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(width: 260)
    }

    private var sourceIcon: String {
        switch skill.sourceType {
        case .git: return "git.branch"
        case .skillssh: return "sparkles"
        case .local: return "folder"
        case .imported: return "archivebox"
        }
    }

    private func cockpitActionButton(title: String,
                                     icon: String,
                                     primary: Bool,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(primary ? .white : AppStyle.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(primary ? AppStyle.accent : AppStyle.hoverFill))
        }
        .buttonStyle(PressScaleStyle())
        .help(title)
    }

    private func tabValue(_ tab: SkillDetailTab) -> String? {
        switch tab {
        case .overview:
            return readinessLabel
        case .deploy:
            return tools.isEmpty ? nil : "\(skill.targets.count)/\(tools.count)"
        case .docs:
            return files.isEmpty ? (document == nil ? nil : "1") : "\(files.count)"
        case .source:
            return ["update_available", "source_missing", "error"].contains(skill.updateStatus) ? updateLabel : nil
        case .activity:
            return auditEntries.isEmpty ? nil : "\(auditEntries.count)"
        }
    }

    private func tabValueColor(_ tab: SkillDetailTab) -> Color {
        switch tab {
        case .overview:
            return readinessScore >= 1 ? AppStyle.accent : .orange
        case .deploy:
            return skill.targets.isEmpty ? .orange : AppStyle.accent
        case .docs:
            return documentKnown ? AppStyle.accent : AppStyle.textTertiary
        case .source:
            return healthColor
        case .activity:
            return AppStyle.textTertiary
        }
    }

    private func isMarkdownFile(_ path: String) -> Bool {
        ["md", "markdown", "mdx", "txt"].contains(fileExtension(path))
    }

    private func isCodeFile(_ path: String) -> Bool {
        ["swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "java", "kt", "sh", "zsh", "json", "yaml", "yml", "toml"].contains(fileExtension(path))
    }

    private func isAssetFile(_ path: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "svg", "pdf", "mp3", "wav", "mp4", "mov"].contains(fileExtension(path))
    }

    private func fileExtension(_ path: String) -> String {
        (path as NSString).pathExtension.lowercased()
    }

    private func runCueAction(_ action: SkillCueAction) {
        switch action {
        case .overview:
            selectedTab = .overview
        case .deploy:
            selectedTab = .deploy
        case .docs:
            selectedTab = .docs
        case .source:
            selectedTab = .source
            if skill.updateStatus == "update_available" {
                onLoadDetails()
            }
        case .loadDetails:
            selectedTab = .docs
            onLoadDetails()
        case .checkUpdate:
            onCheckUpdate()
        }
    }

    private func emptyCockpitState(icon: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(AppStyle.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 118)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AppStyle.hoverFill.opacity(0.45)))
    }
}

private struct SkillProfileSegment: Identifiable {
    let title: String
    let count: Int
    let color: Color

    var id: String { title }
}

private struct SkillCoverageStrip: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let color: Color
    let progress: Double?

    private var normalizedProgress: Double {
        min(max(progress ?? 0, 0), 1)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.12)))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppStyle.textTertiary)
                    Text(value)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(AppStyle.hoverFill)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color)
                            .frame(width: proxy.size.width * CGFloat(normalizedProgress))
                    }
                }
                .frame(height: 6)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AppStyle.hoverFill.opacity(0.40)))
        .animation(Motion.panel, value: normalizedProgress)
        .animation(Motion.snappy, value: value)
    }
}

private struct SkillFileProfilePanel: View {
    let documentKnown: Bool
    let totalFiles: Int
    let totalBytes: Int64
    let segments: [SkillProfileSegment]
    let onLoadDetails: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: documentKnown ? "doc.text.fill" : "doc.text.magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(documentKnown ? AppStyle.accent : .orange)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill((documentKnown ? AppStyle.accent : Color.orange).opacity(0.12)))

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(documentKnown ? L("文件画像") : L("等待读取文件画像"))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                    tinyBadge(L("%ld 文件", totalFiles), color: totalFiles == 0 ? AppStyle.textTertiary : AppStyle.accent)
                    if totalBytes > 0 {
                        tinyBadge(byteCount(totalBytes), color: AppStyle.textTertiary)
                    }
                    Spacer()
                    Button(action: onLoadDetails) {
                        Label(documentKnown ? L("刷新画像") : L("读取"), systemImage: "arrow.clockwise")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help(documentKnown ? L("刷新文件画像") : L("读取文件画像"))
                }

                if segments.isEmpty {
                    Text(L("读取 SKILL.md 后会展示文档、代码、资产等结构占比。"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                } else {
                    SkillSegmentBar(segments: segments)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AppStyle.hoverFill.opacity(0.40)))
    }
}

private struct SkillSegmentBar: View {
    let segments: [SkillProfileSegment]

    private var total: Int {
        max(segments.reduce(0) { $0 + $1.count }, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(segments) { segment in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(segment.color)
                            .frame(width: max(6, proxy.size.width * CGFloat(segment.count) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 7)
            .animation(Motion.panel, value: segments.map { "\($0.id):\($0.count)" }.joined(separator: "|"))

            HStack(spacing: 8) {
                ForEach(segments) { segment in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(segment.color)
                            .frame(width: 6, height: 6)
                        Text("\(segment.title) \(segment.count)")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textTertiary)
                            .lineLimit(1)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}

private struct SkillDiffStatsPanel: View {
    let entries: [SkillSourceDiffEntry]

    private var segments: [SkillProfileSegment] {
        [
            SkillProfileSegment(title: L("新增"), count: count("added"), color: AppStyle.accent),
            SkillProfileSegment(title: L("修改"), count: count("modified"), color: .orange),
            SkillProfileSegment(title: L("删除"), count: count("removed"), color: .red),
        ].filter { $0.count > 0 }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entries.isEmpty ? "checkmark.seal.fill" : "arrow.left.arrow.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(entries.isEmpty ? AppStyle.accent : .orange)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill((entries.isEmpty ? AppStyle.accent : Color.orange).opacity(0.12)))

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(entries.isEmpty ? L("来源一致") : L("差异分布"))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                    tinyBadge(L("%ld 文件", entries.count), color: entries.isEmpty ? AppStyle.accent : .orange)
                    Spacer()
                }
                if segments.isEmpty {
                    Text(L("中央库和来源当前没有文件级差异。"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppStyle.textTertiary)
                } else {
                    SkillSegmentBar(segments: segments)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AppStyle.hoverFill.opacity(0.40)))
    }

    private func count(_ status: String) -> Int {
        entries.filter { $0.status == status }.count
    }
}

private struct SkillCockpitPanel<Content: View>: View {
    let icon: String
    let title: String
    let content: Content

    init(icon: String,
         title: String,
         @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            content
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AppStyle.theme.isDark ? Color.white.opacity(0.04) : Color.white.opacity(0.74)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(AppStyle.separator.opacity(0.22), lineWidth: 1))
    }
}

private struct SkillScoreDial: View {
    let value: Double
    let label: String
    let caption: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppStyle.hoverFill, lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                Text(caption)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textTertiary)
            }
        }
        .frame(width: 58, height: 58)
        .animation(Motion.panel, value: value)
        .animation(Motion.snappy, value: label)
    }
}

private struct SkillRailStat: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppStyle.textTertiary)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AppStyle.hoverFill.opacity(0.55)))
    }
}

private struct SkillMetricTile: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(color.opacity(0.12)))
                Text(title)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                Spacer()
            }
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(2)
        }
        .padding(11)
        .frame(minHeight: 108, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AppStyle.hoverFill.opacity(0.46)))
    }
}

private struct SkillReadinessCard: View {
    let item: SkillReadinessItem

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: item.ready ? "checkmark.circle.fill" : item.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.ready ? AppStyle.accent : item.color)
                .frame(width: 28, height: 28)
                .background(Circle().fill((item.ready ? AppStyle.accent : item.color).opacity(0.11)))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                Text(item.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(item.ready ? AppStyle.accent.opacity(0.09) : AppStyle.hoverFill.opacity(0.52)))
    }
}

private struct SkillDeploymentLane: View {
    let tool: SkillToolInfo
    let target: SkillTargetRecord?
    let onToggle: () -> Void
    @State private var hovering = false

    private var synced: Bool { target != nil }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: synced ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(synced ? AppStyle.accent : AppStyle.textTertiary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(tool.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                        tinyBadge(tool.category.rawValue, color: AppStyle.textTertiary)
                        if tool.isCustom {
                            tinyBadge(L("自定义"), color: AppStyle.accent)
                        }
                        if !tool.installed {
                            tinyBadge(L("未检测"), color: .orange)
                        }
                    }
                    Text(target.map { "\($0.mode.rawValue) · \(collapsedPath($0.targetPath))" } ?? collapsedPath(tool.skillsDirectory))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if let target, target.status != "ok" {
                    tinyBadge(target.status, color: .orange)
                }
                Image(systemName: synced ? "minus.circle" : "arrow.right.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.textTertiary)
                    .opacity(hovering || synced ? 1 : 0.55)
            }
            .padding(.horizontal, 10)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(synced ? AppStyle.accent.opacity(hovering ? 0.13 : 0.09) : AppStyle.hoverFill.opacity(hovering ? 0.66 : 0.48)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(synced ? AppStyle.accent.opacity(hovering ? 0.28 : 0.14) : AppStyle.separator.opacity(hovering ? 0.7 : 0), lineWidth: 1))
            .offset(x: hovering ? 2 : 0)
        }
        .buttonStyle(.plain)
        .help(synced ? L("移除同步") : L("同步到该 Agent"))
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .animation(Motion.snappy, value: synced)
    }
}

private struct SkillFileListRow: View {
    let file: SkillFileInfo

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "doc.text")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.relativePath)
                    .font(.system(size: 9.8, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let modifiedAt = file.modifiedAt {
                    Text(modifiedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 8.8))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(byteCount(file.size))
                .font(.system(size: 9))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AppStyle.hoverFill.opacity(0.42)))
    }
}

private struct SkillDiffSummaryRow: View {
    let entry: SkillSourceDiffEntry

    var body: some View {
        HStack(spacing: 8) {
            tinyBadge(diffStatusLabel(entry.status), color: diffStatusColor(entry.status))
            Text(entry.relativePath)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if entry.originalKind != "text" || entry.updatedKind != "text" {
                Text([entry.originalKind, entry.updatedKind]
                    .filter { $0 != "missing" }
                    .joined(separator: " -> "))
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AppStyle.hoverFill.opacity(0.45)))
    }
}

private struct SkillDiffPreview: View {
    let entry: SkillSourceDiffEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(entry.relativePath)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(alignment: .top, spacing: 8) {
                diffColumn(title: L("中央库"), content: entry.originalContent)
                diffColumn(title: L("来源"), content: entry.updatedContent)
            }
        }
    }

    private func diffColumn(title: String, content: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
            ScrollView {
                Text(String((content ?? L("不存在")).prefix(3_000)))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(AppStyle.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 210)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppStyle.hoverFill.opacity(0.50)))
        }
    }
}

private struct SkillActivityLine: View {
    let entry: SkillAuditEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(skillAuditActionLabel(entry.action))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1)
                    if let tool = entry.tool {
                        tinyBadge(tool, color: AppStyle.textTertiary)
                    }
                    if !entry.success {
                        tinyBadge(L("失败"), color: .red)
                    }
                    Spacer()
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 9.8, design: .monospaced))
                        .foregroundStyle(AppStyle.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AppStyle.hoverFill.opacity(0.42)))
    }

    private var color: Color {
        if !entry.success { return .red }
        switch entry.action {
        case "delete", "unsync", "project_unsync", "tag_remove", "tool_disable", "preset_delete":
            return .orange
        default:
            return AppStyle.accent
        }
    }
}

private struct SkillKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(AppStyle.textTertiary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SkillManagerPayload: Sendable {
    var skills: [ManagedSkill]
    var tools: [SkillToolInfo]
    var presets: [SkillPreset]
    var presetSummaries: [SkillPresetSummary]
    var projects: [SkillProject]
    var projectTargets: [SkillProjectTargetRecord]
    var projectSkills: [String: [ProjectSkillInfo]]
    var auditEntries: [SkillAuditEntry]
    var scanResult: SkillScanResult?
}

private struct ManagedSkillRow: View {
    let skill: ManagedSkill
    let tools: [SkillToolInfo]
    let expanded: Bool
    let selected: Bool
    let document: SkillDocument?
    let files: [SkillFileInfo]
    let sourceDiff: SkillSourceDiff?
    let syncMode: String
    let onExpand: () -> Void
    let onSelect: () -> Void
    let onOpenDetail: () -> Void
    let onToggleTool: (SkillToolInfo, Bool) -> Void
    let onSyncAll: () -> Void
    let onCheckUpdate: () -> Void
    let onRefreshSource: () -> Void
    let onRelinkSource: () -> Void
    let onDetachSource: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(skill.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                        sourceBadge
                        if skill.targets.isEmpty {
                            tinyBadge(L("未同步"), color: AppStyle.textTertiary)
                        } else {
                            tinyBadge(L("已同步 %ld", skill.targets.count), color: AppStyle.accent)
                        }
                        if let updateLabel {
                            tinyBadge(updateLabel, color: updateColor)
                        }
                    }
                    Text((skill.description?.isEmpty == false) ? skill.description! : L("无描述"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppStyle.textSecondary)
                        .lineLimit(expanded ? nil : 2)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onExpand)
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    iconButton(selected ? "checkmark.square.fill" : "square", help: L("选择"), action: onSelect)
                    iconButton("rectangle.and.text.magnifyingglass", help: L("打开详情控制台"), action: onOpenDetail)
                    iconButton("arrow.triangle.2.circlepath", help: L("同步到所有可用 Agent"), action: onSyncAll)
                    if canRefreshFromSource {
                        iconButton("magnifyingglass.circle", help: L("检查更新"), action: onCheckUpdate)
                        iconButton("arrow.clockwise.circle", help: L("从来源刷新"), action: onRefreshSource)
                    }
                    iconButton("folder", help: L("在 Finder 显示"), action: onReveal)
                    iconButton("trash", help: L("删除"), destructive: true, action: onDelete)
                    iconButton(expanded ? "chevron.up" : "chevron.down", help: L("展开"), action: onExpand)
                }
            }

            if !skill.tags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(skill.tags.prefix(8), id: \.self) { tag in
                        tinyBadge(tag, color: AppStyle.textTertiary)
                    }
                    if skill.tags.count > 8 {
                        tinyBadge("+\(skill.tags.count - 8)", color: AppStyle.textTertiary)
                    }
                }
            }

            if !tools.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(tools) { tool in
                            toolToggle(tool)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.never)
            } else {
                Text(L("未检测到可用 Agent。后续可在设置里添加自定义 Skills 目录。"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textTertiary)
            }

            if expanded {
                Divider().overlay(AppStyle.separator)
                VStack(alignment: .leading, spacing: 5) {
                    metaRow(L("中央库"), collapsedPath(skill.centralPath))
                    metaRow(L("来源"), skill.sourceType.rawValue)
                    if let sourceRef = skill.sourceRef {
                        metaRow("source", sourceRef)
                    }
                    if let sourceSubpath = skill.sourceSubpath {
                        metaRow("subpath", sourceSubpath)
                    }
                    if let sourceBranch = skill.sourceBranch {
                        metaRow("ref", sourceBranch)
                    }
                    if let sourceRevision = skill.sourceRevision {
                        metaRow("rev", String(sourceRevision.prefix(12)))
                    }
                    if let remoteRevision = skill.remoteRevision {
                        metaRow("remote", String(remoteRevision.prefix(12)))
                    }
                    metaRow(L("更新状态"), updateLabel ?? L("未知"))
                    if let lastCheckedAt = skill.lastCheckedAt {
                        metaRow(L("上次检查"), lastCheckedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let lastCheckError = skill.lastCheckError, !lastCheckError.isEmpty {
                        metaRow(L("检查错误"), lastCheckError)
                    }
                    if let contentHash = skill.contentHash {
                        metaRow("hash", String(contentHash.prefix(12)))
                    }
                    HStack(spacing: 5) {
                        iconButton("link", help: L("重新绑定来源"), action: onRelinkSource)
                        if canRefreshFromSource {
                            iconButton("link.slash", help: L("解除来源绑定"), action: onDetachSource)
                        }
                    }
                    metaRow(L("同步模式"), syncMode)
                    if !skill.targets.isEmpty {
                        ForEach(skill.targets) { target in
                            metaRow(target.tool, "\(target.mode.rawValue) · \(collapsedPath(target.targetPath))")
                        }
                    }
                }
                skillDocumentPreview
                sourceDiffPreview
                skillFilesPreview
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .toolsCard(cornerRadius: Radius.sm + 2)
    }

    private func toolToggle(_ tool: SkillToolInfo) -> some View {
        let synced = skill.targets.contains { $0.tool == tool.key }
        return Button {
            onToggleTool(tool, !synced)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: synced ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .semibold))
                Text(tool.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(synced ? .white : AppStyle.textSecondary)
            .padding(.horizontal, 7)
            .frame(height: 23)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(synced ? AppStyle.accent : AppStyle.hoverFill))
        }
        .buttonStyle(PressScaleStyle())
        .help(synced ? L("点击移除同步") : L("点击同步到该 Agent"))
    }

    private var sourceBadge: some View {
        tinyBadge(skill.sourceType.rawValue, color: AppStyle.textTertiary)
    }

    private var canRefreshFromSource: Bool {
        switch skill.sourceType {
        case .local, .imported, .git, .skillssh:
            return skill.sourceRef?.isEmpty == false
        }
    }

    private var updateLabel: String? {
        switch skill.updateStatus {
        case "current": return L("已是最新")
        case "update_available": return L("可更新")
        case "source_missing": return L("来源失效")
        case "error": return L("检查失败")
        case "unsupported": return L("不支持更新")
        default: return nil
        }
    }

    private var updateColor: Color {
        switch skill.updateStatus {
        case "current": return AppStyle.accent
        case "update_available": return .orange
        case "source_missing", "error": return .red
        default: return AppStyle.textTertiary
        }
    }

    @ViewBuilder
    private var skillDocumentPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(document?.filename ?? "SKILL.md")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                if document?.truncated == true {
                    tinyBadge(L("已截断"), color: .orange)
                }
                Spacer()
            }
            if let document {
                ScrollView {
                    Text(document.content)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppStyle.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 180)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AppStyle.hoverFill.opacity(0.55)))
            } else {
                Text(L("展开后会读取 Skill 文档。"))
                    .font(.system(size: 10))
                    .foregroundStyle(AppStyle.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var skillFilesPreview: some View {
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(L("文件"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                ForEach(files.prefix(10)) { file in
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textTertiary)
                        Text(file.relativePath)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(AppStyle.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(byteCount(file.size))
                            .font(.system(size: 9))
                            .foregroundStyle(AppStyle.textTertiary)
                    }
                }
                if files.count > 10 {
                    Text(L("还有 %ld 个文件", files.count - 10))
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppStyle.textTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var sourceDiffPreview: some View {
        if skill.updateStatus == "update_available" {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(L("来源差异"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                    if let sourceDiff {
                        tinyBadge(L("%ld 个文件", sourceDiff.entries.count), color: .orange)
                    }
                    Spacer()
                }
                if let sourceDiff {
                    if sourceDiff.entries.isEmpty {
                        Text(L("文件内容未发现差异。"))
                            .font(.system(size: 10))
                            .foregroundStyle(AppStyle.textTertiary)
                    } else {
                        ForEach(sourceDiff.entries.prefix(8)) { entry in
                            diffEntryRow(entry)
                        }
                        if let firstText = sourceDiff.entries.first(where: {
                            $0.originalContent != nil || $0.updatedContent != nil
                        }) {
                            diffTextPreview(firstText)
                        }
                    }
                } else {
                    Text(L("展开后会尝试读取来源差异。"))
                        .font(.system(size: 10))
                        .foregroundStyle(AppStyle.textTertiary)
                }
            }
        }
    }

    private func diffEntryRow(_ entry: SkillSourceDiffEntry) -> some View {
        HStack(spacing: 6) {
            tinyBadge(diffStatusLabel(entry.status), color: diffStatusColor(entry.status))
            Text(entry.relativePath)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if entry.originalKind != "text" || entry.updatedKind != "text" {
                Text([entry.originalKind, entry.updatedKind]
                    .filter { $0 != "missing" }
                    .joined(separator: " -> "))
                    .font(.system(size: 9))
                    .foregroundStyle(AppStyle.textTertiary)
            }
        }
    }

    private func diffTextPreview(_ entry: SkillSourceDiffEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.relativePath)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)
            HStack(alignment: .top, spacing: 6) {
                diffTextColumn(title: L("中央库"), content: entry.originalContent)
                diffTextColumn(title: L("来源"), content: entry.updatedContent)
            }
        }
    }

    private func diffTextColumn(title: String, content: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
            ScrollView {
                Text((content ?? L("不存在")).prefix(2_000))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppStyle.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .frame(maxHeight: 110)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppStyle.hoverFill.opacity(0.55)))
        }
    }

    private func diffStatusLabel(_ status: String) -> String {
        switch status {
        case "added": return L("新增")
        case "removed": return L("删除")
        case "modified": return L("修改")
        default: return status
        }
    }

    private func diffStatusColor(_ status: String) -> Color {
        switch status {
        case "added": return AppStyle.accent
        case "removed": return .red
        case "modified": return .orange
        default: return AppStyle.textTertiary
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(AppStyle.textSecondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

private struct PresetRow: View {
    let preset: SkillPreset
    let summary: SkillPresetSummary?
    let skills: [ManagedSkill]
    let expanded: Bool
    let onExpand: () -> Void
    let onApply: () -> Void
    let onRemove: () -> Void
    let onDelete: () -> Void
    let onToggleSkill: (ManagedSkill, Bool) -> Void
    let onMoveSkill: (ManagedSkill, Int) -> Void

    private var includedIDs: Set<String> {
        Set(preset.skills.map(\.skillID))
    }

    private var orderedIncludedSkills: [ManagedSkill] {
        let order = Dictionary(uniqueKeysWithValues: preset.skills.map { ($0.skillID, $0.order) })
        return skills
            .filter { includedIDs.contains($0.id) }
            .sorted { (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max) }
    }

    private var presetSkillRows: [ManagedSkill] {
        orderedIncludedSkills + skills
            .filter { !includedIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(preset.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                        tinyBadge(L("%ld 个 Skill", preset.skills.count), color: AppStyle.textTertiary)
                        if let healthLabel {
                            tinyBadge(healthLabel, color: statusColor)
                        }
                    }
                    Text((preset.description?.isEmpty == false) ? preset.description! : L("一键应用这组 Skills 到可用 Agent。"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppStyle.textSecondary)
                        .lineLimit(2)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onExpand)

                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    iconButton("play.fill", help: L("应用 Preset"), action: onApply)
                    iconButton("minus.circle", help: L("移除 Preset 同步"), action: onRemove)
                    iconButton("trash", help: L("删除 Preset"), destructive: true, action: onDelete)
                    iconButton(expanded ? "chevron.up" : "chevron.down", help: L("展开"), action: onExpand)
                }
            }

            if !orderedIncludedSkills.isEmpty {
                HStack(spacing: 5) {
                    ForEach(orderedIncludedSkills.prefix(8)) { skill in
                        tinyBadge(skill.name, color: AppStyle.textTertiary)
                    }
                    if orderedIncludedSkills.count > 8 {
                        tinyBadge("+\(orderedIncludedSkills.count - 8)", color: AppStyle.textTertiary)
                    }
                }
            }

            if expanded {
                Divider().overlay(AppStyle.separator)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("勾选这个 Preset 包含的 Skills"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                    if skills.isEmpty {
                        Text(L("中央库还没有 Skill。先导入或扫描发现。"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(AppStyle.textTertiary)
                    } else {
                        ForEach(presetSkillRows) { skill in
                            skillToggle(skill)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .toolsCard(cornerRadius: Radius.sm + 2)
    }

    private func skillToggle(_ skill: ManagedSkill) -> some View {
        let included = includedIDs.contains(skill.id)
        let index = orderedIncludedSkills.firstIndex(where: { $0.id == skill.id })
        return HStack(spacing: 6) {
            Button {
                onToggleSkill(skill, !included)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: included ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(included ? AppStyle.accent : AppStyle.textTertiary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                        Text((skill.description?.isEmpty == false) ? skill.description! : collapsedPath(skill.centralPath))
                            .font(.system(size: 9.5))
                            .foregroundStyle(AppStyle.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if !skill.targets.isEmpty {
                        tinyBadge(L("已同步 %ld", skill.targets.count), color: AppStyle.accent)
                    }
                }
            }
            .buttonStyle(.plain)

            if let index {
                Button {
                    onMoveSkill(skill, -1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(index == 0 ? AppStyle.textTertiary.opacity(0.45) : AppStyle.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(index == 0)
                .help(L("上移"))

                Button {
                    onMoveSkill(skill, 1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(index >= orderedIncludedSkills.count - 1 ? AppStyle.textTertiary.opacity(0.45) : AppStyle.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(index >= orderedIncludedSkills.count - 1)
                .help(L("下移"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(included ? AppStyle.hoverFill : AppStyle.hoverFill.opacity(0.45)))
    }

    private var healthLabel: String? {
        guard let summary, summary.totalPairs > 0 else { return nil }
        if summary.syncedPairs >= summary.totalPairs { return L("已应用") }
        if summary.syncedPairs > 0 { return "\(summary.syncedPairs)/\(summary.totalPairs)" }
        return L("未应用")
    }

    private var statusIcon: String {
        guard let summary, summary.totalPairs > 0 else { return "rectangle.stack" }
        if summary.syncedPairs >= summary.totalPairs { return "checkmark.circle.fill" }
        if summary.syncedPairs > 0 { return "circle.lefthalf.filled" }
        return "circle"
    }

    private var statusColor: Color {
        guard let summary, summary.totalPairs > 0 else { return AppStyle.textTertiary }
        if summary.syncedPairs >= summary.totalPairs { return AppStyle.accent }
        if summary.syncedPairs > 0 { return .orange }
        return AppStyle.textTertiary
    }
}

private struct ProjectWorkspaceRow: View {
    let project: SkillProject
    let projectSkills: [ProjectSkillInfo]
    let centralSkills: [ManagedSkill]
    let presets: [SkillPreset]
    let tools: [SkillToolInfo]
    let targets: [SkillProjectTargetRecord]
    let expanded: Bool
    let onExpand: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void
    let onToggleSkill: (ManagedSkill, SkillToolInfo, Bool) -> Void
    let onApplyPreset: (SkillPreset) -> Void
    let onRemovePreset: (SkillPreset) -> Void

    private var targetPairs: Set<String> {
        Set(targets.map { "\($0.skillID)|\($0.tool)" })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(project.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                        tinyBadge(L("%ld 个项目 Skill", projectSkills.count), color: AppStyle.textTertiary)
                        if !targets.isEmpty {
                            tinyBadge(L("同步 %ld", targets.count), color: AppStyle.accent)
                        }
                    }
                    Text(collapsedPath(project.path))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onExpand)

                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    iconButton("folder", help: L("在 Finder 显示"), action: onReveal)
                    iconButton("trash", help: L("移除项目"), destructive: true, action: onDelete)
                    iconButton(expanded ? "chevron.up" : "chevron.down", help: L("展开"), action: onExpand)
                }
            }

            if !tools.isEmpty {
                HStack(spacing: 5) {
                    ForEach(tools.prefix(8)) { tool in
                        tinyBadge(tool.displayName, color: AppStyle.textTertiary)
                    }
                    if tools.count > 8 {
                        tinyBadge("+\(tools.count - 8)", color: AppStyle.textTertiary)
                    }
                }
            }

            if expanded {
                Divider().overlay(AppStyle.separator)
                VStack(alignment: .leading, spacing: 10) {
                    presetControls
                    centralSkillControls
                    projectSkillList
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .toolsCard(cornerRadius: Radius.sm + 2)
    }

    @ViewBuilder
    private var presetControls: some View {
        if !presets.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Preset 到项目"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(presets) { preset in
                            HStack(spacing: 4) {
                                Button { onApplyPreset(preset) } label: {
                                    Label(preset.name, systemImage: "play.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .frame(height: 23)
                                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(AppStyle.accent))
                                }
                                .buttonStyle(PressScaleStyle())
                                Button { onRemovePreset(preset) } label: {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(AppStyle.textSecondary)
                                        .frame(width: 23, height: 23)
                                        .background(Circle().fill(AppStyle.hoverFill))
                                }
                                .buttonStyle(PressScaleStyle())
                                .help(L("移除这个 Preset 在项目里的同步"))
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.never)
            }
        }
    }

    @ViewBuilder
    private var centralSkillControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("中央库 Skills 到项目"))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppStyle.textSecondary)
            if centralSkills.isEmpty {
                Text(L("中央库还没有 Skill。"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textTertiary)
            } else if tools.isEmpty {
                Text(L("没有支持项目级目录的 Agent。"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textTertiary)
            } else {
                ForEach(centralSkills) { skill in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(skill.name)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                        ScrollView(.horizontal) {
                            HStack(spacing: 5) {
                                ForEach(tools) { tool in
                                    projectToolToggle(skill: skill, tool: tool)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                        .scrollIndicators(.never)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppStyle.hoverFill.opacity(0.45)))
                }
            }
        }
    }

    @ViewBuilder
    private var projectSkillList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("项目实际存在的 Skills"))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppStyle.textSecondary)
            if projectSkills.isEmpty {
                Text(L("这个项目目录里还没有扫描到项目级 Skills。"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textTertiary)
            } else {
                ForEach(projectSkills.prefix(12)) { skill in
                    HStack(spacing: 6) {
                        tinyBadge(skill.toolDisplayName, color: AppStyle.textTertiary)
                        Text(skill.name)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                        tinyBadge(statusLabel(skill.syncStatus), color: statusColor(skill.syncStatus))
                        Spacer()
                    }
                }
                if projectSkills.count > 12 {
                    Text(L("还有 %ld 个项目 Skill", projectSkills.count - 12))
                        .font(.system(size: 10))
                        .foregroundStyle(AppStyle.textTertiary)
                }
            }
        }
    }

    private func projectToolToggle(skill: ManagedSkill, tool: SkillToolInfo) -> some View {
        let synced = targetPairs.contains("\(skill.id)|\(tool.key)")
        return Button {
            onToggleSkill(skill, tool, !synced)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: synced ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(tool.displayName)
                    .font(.system(size: 9.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(synced ? .white : AppStyle.textSecondary)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(synced ? AppStyle.accent : AppStyle.hoverFill))
        }
        .buttonStyle(PressScaleStyle())
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "in_sync": return L("同步")
        case "diverged": return L("差异")
        default: return L("项目")
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "in_sync": return AppStyle.accent
        case "diverged": return .orange
        default: return AppStyle.textTertiary
        }
    }
}

private struct SkillToolRow: View {
    let tool: SkillToolInfo
    let syncedCount: Int
    let onToggleEnabled: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tool.installed ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tool.installed ? AppStyle.accent : AppStyle.textTertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(tool.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                    tinyBadge(tool.category.rawValue, color: AppStyle.textTertiary)
                    if tool.isCustom { tinyBadge(L("自定义"), color: AppStyle.accent) }
                    if !tool.enabled { tinyBadge(L("停用"), color: .red) }
                }
                Text(collapsedPath(tool.skillsDirectory))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(L("已同步 %ld 个 Skill", syncedCount))
                    .font(.system(size: 10))
                    .foregroundStyle(AppStyle.textSecondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Button(action: onToggleEnabled) {
                    Image(systemName: tool.enabled ? "pause.circle" : "play.circle")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
                .help(tool.enabled ? L("停用 Agent") : L("启用 Agent"))

                Button(action: onReveal) {
                    Image(systemName: "folder")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
                .help(L("在 Finder 显示"))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .toolsCard(cornerRadius: Radius.sm + 2)
    }
}

private struct SkillAuditRow: View {
    let entry: SkillAuditEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18, height: 20)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(actionLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                    if let skillName = entry.skillName {
                        tinyBadge(skillName, color: AppStyle.textTertiary)
                    }
                    if let tool = entry.tool {
                        tinyBadge(tool, color: AppStyle.textTertiary)
                    }
                    if !entry.success {
                        tinyBadge(L("失败"), color: .red)
                    }
                    Spacer(minLength: 6)
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppStyle.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .toolsCard(cornerRadius: Radius.sm + 2)
    }

    private var actionLabel: String {
        switch entry.action {
        case "install": return L("安装 Skill")
        case "bundle_export": return L("导出 Bundle")
        case "bundle_import": return L("导入 Bundle")
        case "sync": return L("同步到 Agent")
        case "unsync": return L("移除 Agent 同步")
        case "project_sync": return L("同步到项目")
        case "project_unsync": return L("移除项目同步")
        case "refresh": return L("刷新来源")
        case "check_update": return L("检查更新")
        case "relink_source": return L("重新绑定来源")
        case "detach_source": return L("解除来源绑定")
        case "delete": return L("删除 Skill")
        case "tag_add": return L("添加标签")
        case "tag_remove": return L("移除标签")
        case "set_tags": return L("设置标签")
        case "tool_enable": return L("启用 Agent")
        case "tool_disable": return L("停用 Agent")
        case "tool_custom_add": return L("添加自定义 Agent")
        case "preset_create": return L("创建 Preset")
        case "preset_delete": return L("删除 Preset")
        case "preset_reorder": return L("调整 Preset 顺序")
        case "scan": return L("扫描本机")
        default: return entry.action
        }
    }

    private var icon: String {
        if !entry.success { return "exclamationmark.triangle.fill" }
        switch entry.action {
        case "install", "bundle_import": return "square.and.arrow.down"
        case "bundle_export": return "square.and.arrow.up"
        case "sync", "project_sync": return "arrow.triangle.2.circlepath"
        case "unsync", "project_unsync": return "minus.circle"
        case "refresh", "check_update": return "arrow.clockwise.circle"
        case "delete": return "trash"
        case "tag_add", "tag_remove", "set_tags": return "tag"
        case "tool_enable", "tool_disable", "tool_custom_add": return "cpu"
        case "preset_create", "preset_delete", "preset_reorder": return "rectangle.stack"
        case "scan": return "scope"
        default: return "clock"
        }
    }

    private var color: Color {
        if !entry.success { return .red }
        switch entry.action {
        case "delete", "unsync", "project_unsync", "tag_remove", "tool_disable", "preset_delete":
            return .orange
        default:
            return AppStyle.accent
        }
    }
}

private struct SkillsShMarketRow: View {
    let skill: SkillsShSkill
    let installed: Bool
    let onInstall: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: installed ? "checkmark.seal.fill" : "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(installed ? AppStyle.accent : AppStyle.textTertiary)
                .frame(width: 16, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1)
                    tinyBadge(skill.source, color: AppStyle.textTertiary)
                    if skill.installs > 0 {
                        tinyBadge("\(skill.installs)", color: AppStyle.textTertiary)
                    }
                    if installed {
                        tinyBadge(L("已安装"), color: AppStyle.accent)
                    }
                }
                Text(skill.skillID)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)
            Button(action: onInstall) {
                Label(installed ? L("更新") : L("安装"), systemImage: "square.and.arrow.down")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppStyle.accent))
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AppStyle.hoverFill.opacity(0.45)))
    }
}

private struct DiscoveredSkillGroupRow: View {
    let group: DiscoveredSkillGroup
    let onImport: () -> Void
    let onReveal: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: group.imported ? "checkmark.seal.fill" : "sparkle.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(group.imported ? AppStyle.accent : AppStyle.textTertiary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(group.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                        tinyBadge(L("%ld 处", group.locations.count), color: AppStyle.textTertiary)
                        if group.imported { tinyBadge(L("已导入"), color: AppStyle.accent) }
                    }
                    if let fingerprint = group.fingerprint {
                        Text(fingerprint)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(AppStyle.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Button(action: onImport) {
                    Label(group.imported ? L("更新") : L("导入"), systemImage: "square.and.arrow.down")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.accent))
                }
                .buttonStyle(PressScaleStyle())
            }

            ForEach(group.locations) { location in
                HStack(spacing: 6) {
                    tinyBadge(location.tool, color: AppStyle.textTertiary)
                    Text(collapsedPath(location.foundPath))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(AppStyle.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button { onReveal(location.foundPath) } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textSecondary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(AppStyle.hoverFill))
                    }
                    .buttonStyle(.plain)
                    .help(L("在 Finder 显示"))
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .toolsCard(cornerRadius: Radius.sm + 2)
    }
}

private struct StatusLine: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text).font(.system(size: 11))
            Spacer()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.10)))
    }
}

@MainActor
private func tinyBadge(_ text: String, color: Color) -> some View {
    Text(text)
        .font(.system(size: 8.5, weight: .bold))
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
}

@MainActor
private func iconButton(_ icon: String,
                        help: String,
                        destructive: Bool = false,
                        action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: icon)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(destructive ? Color(red: 0.92, green: 0.34, blue: 0.34) : AppStyle.textSecondary)
            .frame(width: 24, height: 24)
            .background(Circle().fill(AppStyle.hoverFill))
    }
    .buttonStyle(PressScaleStyle())
    .help(help)
}

private func diffStatusLabel(_ status: String) -> String {
    switch status {
    case "added": return L("新增")
    case "removed": return L("删除")
    case "modified": return L("修改")
    default: return status
    }
}

@MainActor
private func diffStatusColor(_ status: String) -> Color {
    switch status {
    case "added": return AppStyle.accent
    case "removed": return .red
    case "modified": return .orange
    default: return AppStyle.textTertiary
    }
}

private func skillAuditActionLabel(_ action: String) -> String {
    switch action {
    case "install": return L("安装 Skill")
    case "bundle_export": return L("导出 Bundle")
    case "bundle_import": return L("导入 Bundle")
    case "sync": return L("同步到 Agent")
    case "unsync": return L("移除 Agent 同步")
    case "project_sync": return L("同步到项目")
    case "project_unsync": return L("移除项目同步")
    case "refresh": return L("刷新来源")
    case "check_update": return L("检查更新")
    case "relink_source": return L("重新绑定来源")
    case "detach_source": return L("解除来源绑定")
    case "delete": return L("删除 Skill")
    case "tag_add": return L("添加标签")
    case "tag_remove": return L("移除标签")
    case "set_tags": return L("设置标签")
    case "tool_enable": return L("启用 Agent")
    case "tool_disable": return L("停用 Agent")
    case "tool_custom_add": return L("添加自定义 Agent")
    case "preset_create": return L("创建 Preset")
    case "preset_delete": return L("删除 Preset")
    case "preset_reorder": return L("调整 Preset 顺序")
    case "scan": return L("扫描本机")
    default: return action
    }
}

private func collapsedPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path == home { return "~" }
    if path.hasPrefix(home + "/") {
        return "~" + path.dropFirst(home.count)
    }
    return path
}

private func byteCount(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
