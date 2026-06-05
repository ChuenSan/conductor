import AppKit
import CodexBarCore
import SwiftUI

public struct ConductorUsagePanelStyle: @unchecked Sendable {
    public let panelBase: Color
    public let panelWash: Color
    public let controlFill: Color
    public let controlStrongFill: Color
    public let stroke: Color
    public let separator: Color
    public let emphasis: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let tertiaryText: Color
    public let usesDarkChrome: Bool

    public init(
        panelBase: Color,
        panelWash: Color,
        controlFill: Color,
        controlStrongFill: Color,
        stroke: Color,
        separator: Color,
        emphasis: Color,
        primaryText: Color,
        secondaryText: Color,
        tertiaryText: Color,
        usesDarkChrome: Bool)
    {
        self.panelBase = panelBase
        self.panelWash = panelWash
        self.controlFill = controlFill
        self.controlStrongFill = controlStrongFill
        self.stroke = stroke
        self.separator = separator
        self.emphasis = emphasis
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
        self.usesDarkChrome = usesDarkChrome
    }

    public static let fallback = ConductorUsagePanelStyle(
        panelBase: Color(nsColor: .windowBackgroundColor),
        panelWash: Color.primary.opacity(0.010),
        controlFill: Color.primary.opacity(0.020),
        controlStrongFill: Color.primary.opacity(0.032),
        stroke: Color.primary.opacity(0.075),
        separator: Color.primary.opacity(0.040),
        emphasis: .accentColor,
        primaryText: .primary,
        secondaryText: .secondary,
        tertiaryText: Color(nsColor: .tertiaryLabelColor),
        usesDarkChrome: false)
}

@MainActor
public enum ConductorUsageFeature {
    public static var openSettingsHandler: (@MainActor () -> Void)?
    nonisolated(unsafe) private static var hostLanguageIdentifierOverride: String?
    nonisolated(unsafe) private static var hostLanguageIdentifierOverrideConfigured = false

    public static func configureOpenSettings(_ handler: (@MainActor () -> Void)?) {
        openSettingsHandler = handler
    }

    public static func configureHostLanguageIdentifier(_ languageIdentifier: String?) {
        hostLanguageIdentifierOverride = languageIdentifier
        hostLanguageIdentifierOverrideConfigured = true
        CodexBarEmbeddedRuntime.shared.applyHostLanguageOverride()
    }

    public static func configureHostMenuStyle(_ style: ConductorUsagePanelStyle) {
        ConductorUsageMenuStyle.configure(style)
        CodexBarEmbeddedRuntime.shared.applyHostMenuStyleOverride()
    }

    public static func openTokenRecords(
        style: ConductorUsagePanelStyle = .fallback,
        languageIdentifier: String? = nil)
    {
        if let languageIdentifier {
            configureHostLanguageIdentifier(languageIdentifier)
        }
        let runtime = CodexBarEmbeddedRuntime.shared
        if !runtime.isRunning {
            runtime.start()
        }
        runtime.openTokenRecordsWindow(style: style, languageIdentifier: languageIdentifier)
    }

    static func openHostSettings() {
        openSettingsHandler?()
    }

    nonisolated static var hasHostLanguageIdentifierOverride: Bool {
        hostLanguageIdentifierOverrideConfigured
    }

    nonisolated static var currentHostLanguageIdentifier: String? {
        hostLanguageIdentifierOverride
    }
}

func conductorTokenRecordsText(_ zh: String, _ en: String, languageIdentifier: String? = nil) -> String {
    let configured = languageIdentifier != nil || ConductorUsageFeature.hasHostLanguageIdentifierOverride
    let override = languageIdentifier ?? ConductorUsageFeature.currentHostLanguageIdentifier
    let language = if configured {
        (override?.isEmpty == false ? override : Locale.preferredLanguages.first)?.lowercased() ?? ""
    } else {
        Locale.preferredLanguages.first?.lowercased() ?? ""
    }
    return language.hasPrefix("zh") ? zh : en
}

extension ConductorUsagePanelStyle {
    var colorScheme: ColorScheme {
        usesDarkChrome ? .dark : .light
    }
}

@MainActor
struct ConductorTokenRecordsWindowView: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    let statusController: StatusItemController
    let style: ConductorUsagePanelStyle
    let languageIdentifier: String?
    @State private var selectedProvider: UsageProvider = .codex
    @State private var expandedCompanionPanelIDs: Set<String> = []

    private let tokenRecordProviders: [UsageProvider] = [.codex, .claude, .vertexai, .bedrock]

    var body: some View {
        let providers = displayProviders
        let provider = currentProvider(from: providers)
        let snapshot = store.tokenSnapshot(for: provider)
        let error = store.tokenError(for: provider)
        let isRefreshing = store.isTokenRefreshInFlight(for: provider)

        panelSurface {
            VStack(spacing: 0) {
                header(provider: provider, providers: providers, isRefreshing: isRefreshing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(ConductorWindowDragRegion())

                panelDivider
                    .padding(.horizontal, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        let overviewModel = statusController.menuCardModel(for: provider)
                        if let model = overviewModel {
                            usageOverviewCard(model, provider: provider)
                        }
                        usageActionDeck(provider: provider, model: overviewModel)
                        usageCompanionPanels(provider: provider)

                        if shouldShowTokenHistory(provider: provider, snapshot: snapshot, error: error, isRefreshing: isRefreshing) {
                            if let snapshot, !snapshot.daily.isEmpty {
                                summary(snapshot: snapshot)
                                chart(provider: provider, snapshot: snapshot)
                                records(snapshot: snapshot)
                            } else {
                                emptyState(provider: provider, error: error, isRefreshing: isRefreshing)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .environment(\.colorScheme, style.colorScheme)
        .preferredColorScheme(style.colorScheme)
        .tint(style.emphasis)
        .accentColor(style.emphasis)
        .background(Color.clear)
        .onAppear {
            normalizeSelection(providers)
            CodexBarEmbeddedRuntime.shared.refreshTokenRecords(provider: provider)
        }
        .onChange(of: providerIDs(providers)) { _, _ in
            normalizeSelection(providers)
        }
        .onExitCommand {
            CodexBarEmbeddedRuntime.shared.closeTokenRecordsWindow()
        }
    }

    private func usageOverviewCard(_ model: UsageMenuCardView.Model, provider: UsageProvider) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            usageOverviewHeader(model, provider: provider)

            if model.hasUsageContent {
                usageOverviewContent(model)
            }

            usageOverviewInsights(model)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(style.controlFill.opacity(style.usesDarkChrome ? 0.30 : 0.42))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(style.stroke.opacity(0.30), lineWidth: 0.7)
        }
    }

    private func usageOverviewHeader(_ model: UsageMenuCardView.Model, provider: UsageProvider) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.secondaryText)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.providerName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(style.primaryText)
                        .lineLimit(1)
                    if let plan = model.planText, !plan.isEmpty {
                        overviewChip(localized(plan))
                    }
                    Spacer(minLength: 0)
                }

                Text(localized(model.subtitleText))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(model.subtitleStyle == .error ? Color(nsColor: .systemRed) : style.secondaryText)
                    .lineLimit(model.subtitleStyle == .error ? 3 : 1)
                    .fixedSize(horizontal: false, vertical: true)

                if !model.email.isEmpty {
                    Text(model.email)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(style.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.providerName), \(localized(model.subtitleText))")
    }

    private func overviewChip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(style.secondaryText)
            .lineLimit(1)
            .frame(height: 18)
    }

    @ViewBuilder
    private func usageOverviewContent(_ model: UsageMenuCardView.Model) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.metrics.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250), spacing: 8)],
                    alignment: .leading,
                    spacing: 8)
                {
                    ForEach(model.metrics, id: \.id) { metric in
                        ConductorUsageMetricTile(
                            metric: metric,
                            provider: model.provider,
                            progressColor: model.progressColor,
                            style: style)
                    }
                }
            }

            if let dashboard = model.inlineUsageDashboard {
                ConductorInlineUsageDashboardCard(model: dashboard, style: style)
            } else if !model.usageNotes.isEmpty {
                overviewPanel {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(model.usageNotes.enumerated()), id: \.offset) { _, note in
                            Text(localized(note))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(style.secondaryText)
                                .lineLimit(2)
                        }
                    }
                    .padding(10)
                }
            } else if model.metrics.isEmpty, let placeholder = model.placeholder {
                overviewInfoRow(
                    systemName: "info.circle",
                    title: t("状态", "State"),
                    primary: localized(placeholder),
                    secondary: nil)
            }
        }
    }

    private func usageMetricCard(
        _ metric: UsageMenuCardView.Model.Metric,
        provider: UsageProvider,
        progressColor: Color) -> some View
    {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(localized(UsageMenuCardView.popupMetricTitle(provider: provider, metric: metric)))
                        .font(.system(size: 12.2, weight: .semibold))
                        .foregroundStyle(style.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                    Spacer(minLength: 0)
                    if metric.statusText == nil {
                        Text(metric.percentLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(style.secondaryText)
                            .lineLimit(1)
                    }
                }

                if let statusText = metric.statusText {
                    Text(localized(statusText))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(style.secondaryText)
                        .lineLimit(2)
                } else {
                    overviewProgressBar(
                        percent: metric.percent,
                        tint: progressColor,
                        pacePercent: metric.pacePercent,
                        paceOnTop: metric.paceOnTop,
                        warningMarkerPercents: metric.warningMarkerPercents)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let detailLeft = metric.detailLeftText {
                            Text(localized(detailLeft))
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(style.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if let resetText = metric.resetText {
                            Text(localized(resetText))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(style.tertiaryText)
                                .lineLimit(1)
                        }
                    }

                    if let detailText = metric.detailText {
                        Text(localized(detailText))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(style.tertiaryText)
                            .lineLimit(1)
                    }

                    if let detailRight = metric.detailRightText {
                        Text(localized(detailRight))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(style.tertiaryText)
                            .lineLimit(1)
                    }
                }
            }
        }
        .groupBoxStyle(.automatic)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
    }

    private func overviewProgressBar(
        percent: Double,
        tint: Color,
        pacePercent: Double?,
        paceOnTop: Bool,
        warningMarkerPercents: [Double]) -> some View
    {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clamped = max(0, min(100, percent))
            let fillWidth = width * clamped / 100
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(style.separator.opacity(style.usesDarkChrome ? 0.36 : 0.28))
                Capsule()
                    .fill(tint.opacity(style.usesDarkChrome ? 0.82 : 0.74))
                    .frame(width: fillWidth)
                if let pacePercent {
                    Rectangle()
                        .fill((paceOnTop ? style.emphasis : Color(nsColor: .systemOrange)).opacity(0.78))
                        .frame(width: 1.5, height: 10)
                        .offset(x: markerOffset(width: width, percent: pacePercent, markerWidth: 1.5))
                }
                ForEach(Array(warningMarkerPercents.enumerated()), id: \.offset) { _, marker in
                    Rectangle()
                        .fill(Color(nsColor: .systemRed).opacity(0.70))
                        .frame(width: 1, height: 8)
                        .offset(x: markerOffset(width: width, percent: marker, markerWidth: 1))
                }
            }
        }
        .frame(height: 6)
        .accessibilityLabel(t("用量进度", "Usage progress"))
        .accessibilityValue(String(format: "%.0f%%", percent))
    }

    @ViewBuilder
    private func usageOverviewInsights(_ model: UsageMenuCardView.Model) -> some View {
        let hasCredits = model.creditsText != nil
        let hasCost = model.providerCost != nil || model.tokenUsage != nil
        if hasCredits || hasCost {
            VStack(alignment: .leading, spacing: 8) {
                if let creditsText = model.creditsText {
                    ConductorSignalInfoCard(
                        systemName: "creditcard",
                        title: t("额度", "Credits"),
                        primary: localized(creditsText),
                        secondary: model.creditsHintText.map { localized($0) },
                        style: style)
                }

                if let providerCost = model.providerCost {
                    overviewCostRow(providerCost)
                }

                if let tokenUsage = model.tokenUsage {
                    overviewTokenUsageRow(tokenUsage)
                }
            }
        }
    }

    private func overviewCostRow(_ section: UsageMenuCardView.Model.ProviderCostSection) -> some View {
        ConductorCostSignalCard(section: section, style: style)
    }

    private func overviewTokenUsageRow(_ section: UsageMenuCardView.Model.TokenUsageSection) -> some View {
        ConductorTokenUsageSignalCard(section: section, style: style)
    }

    private func overviewInfoRow(
        systemName: String,
        title: String,
        primary: String,
        secondary: String?) -> some View
    {
        ConductorSignalInfoCard(
            systemName: systemName,
            title: title,
            primary: primary,
            secondary: secondary,
            style: style)
    }

    private func overviewInfoHeader(systemName: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(style.emphasis)
                .frame(width: 15)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(style.secondaryText)
                .lineLimit(1)
        }
    }

    private func overviewPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(style.controlFill.opacity(style.usesDarkChrome ? 0.46 : 0.62))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(style.stroke.opacity(0.38), lineWidth: 0.7)
            }
    }

    private func usageActionDeck(provider: UsageProvider, model: UsageMenuCardView.Model?) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: 8, alignment: .top)],
            alignment: .leading,
            spacing: 8)
        {
            ConductorUsageActionTile(
                title: t("刷新当前", "Refresh current"),
                subtitle: t("同步当前来源的记录和本地状态", "Sync records and local state for this source"),
                systemName: "arrow.clockwise",
                style: style)
            {
                CodexBarEmbeddedRuntime.shared.refreshTokenRecords(provider: provider)
            }

            if ProviderCatalog.implementation(for: provider)?.supportsLoginFlow == true {
                ConductorUsageActionTile(
                    title: accountActionTitle(provider: provider, model: model),
                    subtitle: accountActionSubtitle(provider: provider),
                    systemName: "person.crop.circle.badge.plus",
                    style: style)
                {
                    runAccountAction(provider: provider)
                }
            }

            if statusController.dashboardURL(for: provider) != nil {
                ConductorUsageActionTile(
                    title: t("用量后台", "Usage Dashboard"),
                    subtitle: t("打开服务商控制台", "Open the provider dashboard"),
                    systemName: "chart.bar.xaxis",
                    style: style)
                {
                    openDashboard(provider: provider)
                }
            }

            if hasStatusPage(provider: provider) {
                ConductorUsageActionTile(
                    title: t("状态页", "Status Page"),
                    subtitle: t("查看服务可用性", "Check service availability"),
                    systemName: "waveform.path.ecg",
                    style: style)
                {
                    openStatusPage(provider: provider)
                }
            }

            if provider == .codex, model?.creditsText != nil || store.openAIDashboard?.creditsPurchaseURL != nil {
                ConductorUsageActionTile(
                    title: t("购买额度", "Buy Credits"),
                    subtitle: t("进入额度购买流程", "Open the credits purchase flow"),
                    systemName: "plus.circle",
                    style: style)
                {
                    openCredits(provider: provider)
                }
            }
        }
    }

    @ViewBuilder
    private func usageCompanionPanels(provider: UsageProvider) -> some View {
        if shouldShowPlanUtilization(provider: provider) {
            let panelID = companionPanelID("plan", provider: provider)
            ConductorExpandableInsightPanel(
                title: t("订阅使用趋势", "Subscription Utilization"),
                subtitle: t("按小时记录的配额水位", "Hourly plan utilization samples"),
                systemName: "waveform.path.ecg.rectangle",
                style: style,
                isExpanded: expansionBinding(for: panelID))
            {
                ConductorUsageSummaryChip(
                    title: t("序列", "Series"),
                    value: "\(store.planUtilizationHistory(for: provider).count)",
                    style: style)
                ConductorUsageSummaryChip(
                    title: t("来源", "Source"),
                    value: providerName(provider),
                    style: style)
            } content: {
                ConductorEmbeddedChartPanel(
                    title: t("订阅使用趋势", "Subscription Utilization"),
                    subtitle: t("按小时记录的配额水位", "Hourly plan utilization samples"),
                    systemName: "waveform.path.ecg.rectangle",
                    style: style,
                    minHeight: 220,
                    showsHeader: false,
                    usesChrome: false)
                { width in
                    PlanUtilizationHistoryChartMenuView(
                        provider: provider,
                        histories: store.planUtilizationHistory(for: provider),
                        snapshot: store.snapshot(for: provider),
                        width: width)
                }
            }
        }

        if let footprint = store.storageFootprint(for: provider) {
            let panelID = companionPanelID("storage", provider: provider)
            ConductorExpandableInsightPanel(
                title: t("本地存储", "Storage"),
                subtitle: t("本地数据、缓存和清理建议", "Local data, cache, and cleanup ideas"),
                systemName: "externaldrive",
                style: style,
                isExpanded: expansionBinding(for: panelID))
            {
                ConductorUsageSummaryChip(
                    title: t("总量", "Total"),
                    value: UsageFormatter.byteCountString(footprint.totalBytes),
                    style: style)
                ConductorUsageSummaryChip(
                    title: t("项目", "Items"),
                    value: "\(footprint.components.count)",
                    style: style)
            } content: {
                ConductorStorageFootprintPanel(
                    footprint: footprint,
                    style: style,
                    showsHeader: false,
                    usesChrome: false)
            }
        }

        if provider == .codex, let breakdown = codexUsageBreakdown, !breakdown.isEmpty {
            let panelID = companionPanelID("usageBreakdown", provider: provider)
            ConductorExpandableInsightPanel(
                title: t("用量构成", "Usage Breakdown"),
                subtitle: t("按服务拆分的每日消耗", "Daily usage split by service"),
                systemName: "square.stack.3d.up",
                style: style,
                isExpanded: expansionBinding(for: panelID))
            {
                ConductorUsageSummaryChip(
                    title: t("天数", "Days"),
                    value: "\(breakdown.count)",
                    style: style)
                ConductorUsageSummaryChip(
                    title: t("服务", "Services"),
                    value: "\(usageBreakdownServiceCount(breakdown))",
                    style: style)
            } content: {
                ConductorEmbeddedChartPanel(
                    title: t("用量构成", "Usage Breakdown"),
                    subtitle: t("按服务拆分的每日消耗", "Daily usage split by service"),
                    systemName: "square.stack.3d.up",
                    style: style,
                    minHeight: 190,
                    showsHeader: false,
                    usesChrome: false)
                { width in
                    UsageBreakdownChartMenuView(breakdown: breakdown, width: width)
                }
            }
        }

        if provider == .codex, let breakdown = store.openAIDashboard?.dailyBreakdown, !breakdown.isEmpty {
            let panelID = companionPanelID("credits", provider: provider)
            ConductorExpandableInsightPanel(
                title: t("额度历史", "Credits History"),
                subtitle: t("每日额度消耗轨迹", "Daily credits burn"),
                systemName: "chart.bar.doc.horizontal",
                style: style,
                isExpanded: expansionBinding(for: panelID))
            {
                ConductorUsageSummaryChip(
                    title: t("天数", "Days"),
                    value: "\(breakdown.count)",
                    style: style)
                ConductorUsageSummaryChip(
                    title: t("峰值", "Peak"),
                    value: creditsPeakText(breakdown),
                    style: style)
            } content: {
                ConductorEmbeddedChartPanel(
                    title: t("额度历史", "Credits History"),
                    subtitle: t("每日额度消耗轨迹", "Daily credits burn"),
                    systemName: "chart.bar.doc.horizontal",
                    style: style,
                    minHeight: 190,
                    showsHeader: false,
                    usesChrome: false)
                { width in
                    CreditsHistoryChartMenuView(breakdown: breakdown, width: width)
                }
            }
        }

        if provider == .openai,
           let snapshot = store.snapshot(for: provider)?.openAIAPIUsage,
           !snapshot.daily.isEmpty
        {
            let panelID = companionPanelID("api", provider: provider)
            ConductorExpandableInsightPanel(
                title: t("API 用量", "API Usage"),
                subtitle: t("费用、请求和 Token 趋势", "Spend, requests, and token trends"),
                systemName: "server.rack",
                style: style,
                isExpanded: expansionBinding(for: panelID))
            {
                ConductorUsageSummaryChip(
                    title: snapshot.historyWindowLabel,
                    value: UsageFormatter.usdString(snapshot.last30Days.costUSD),
                    style: style)
                ConductorUsageSummaryChip(
                    title: t("请求", "Requests"),
                    value: UsageFormatter.tokenCountString(snapshot.last30Days.requests),
                    style: style)
            } content: {
                ConductorEmbeddedChartPanel(
                    title: t("API 用量", "API Usage"),
                    subtitle: t("费用、请求和 Token 趋势", "Spend, requests, and token trends"),
                    systemName: "server.rack",
                    style: style,
                    minHeight: 270,
                    showsHeader: false,
                    usesChrome: false)
                { width in
                    OpenAIAPIUsageChartMenuView(snapshot: snapshot, width: width)
                }
            }
        }
    }

    private var codexUsageBreakdown: [OpenAIDashboardDailyBreakdown]? {
        guard let breakdown = store.openAIDashboard?.usageBreakdown else { return nil }
        return OpenAIDashboardDailyBreakdown.removingSkillUsageServices(from: breakdown)
    }

    private func shouldShowPlanUtilization(provider: UsageProvider) -> Bool {
        store.supportsPlanUtilizationHistory(for: provider) &&
            !store.shouldHidePlanUtilizationMenuItem(for: provider)
    }

    private func hasStatusPage(provider: UsageProvider) -> Bool {
        let meta = store.metadata(for: provider)
        return meta.statusPageURL != nil || meta.statusLinkURL != nil
    }

    private func companionPanelID(_ kind: String, provider: UsageProvider) -> String {
        "\(provider.rawValue).\(kind)"
    }

    private func expansionBinding(for panelID: String) -> Binding<Bool> {
        Binding(
            get: { expandedCompanionPanelIDs.contains(panelID) },
            set: { isExpanded in
                if isExpanded {
                    expandedCompanionPanelIDs.insert(panelID)
                } else {
                    expandedCompanionPanelIDs.remove(panelID)
                }
            })
    }

    private func usageBreakdownServiceCount(_ breakdown: [OpenAIDashboardDailyBreakdown]) -> Int {
        let services = breakdown.flatMap(\.services).map(\.service)
        return Set(services).count
    }

    private func creditsPeakText(_ breakdown: [OpenAIDashboardDailyBreakdown]) -> String {
        let peak = breakdown.map(\.totalCreditsUsed).max() ?? 0
        return String(format: "%.1f", peak)
    }

    private func accountActionTitle(provider: UsageProvider, model: UsageMenuCardView.Model?) -> String {
        if let model, !model.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return t("切换账户", "Switch Account")
        }
        if let email = store.snapshot(for: provider)?.accountEmail(for: provider),
           !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return t("切换账户", "Switch Account")
        }
        return t("添加账户", "Add Account")
    }

    private func accountActionSubtitle(provider: UsageProvider) -> String {
        if let subtitle = statusController.switchAccountSubtitle(for: provider) {
            return localized(subtitle)
        }
        return t("连接或更换当前来源", "Connect or change this source")
    }

    private func runAccountAction(provider: UsageProvider) {
        let item = NSMenuItem()
        item.representedObject = provider.rawValue
        statusController.lastMenuProvider = provider
        statusController.runSwitchAccount(item)
    }

    private func openDashboard(provider: UsageProvider) {
        statusController.lastMenuProvider = provider
        statusController.openDashboard()
    }

    private func openStatusPage(provider: UsageProvider) {
        statusController.lastMenuProvider = provider
        statusController.openStatusPage()
    }

    private func openCredits(provider: UsageProvider) {
        statusController.lastMenuProvider = provider
        statusController.openCreditsPurchase()
    }

    private func shouldShowTokenHistory(
        provider: UsageProvider,
        snapshot: CostUsageTokenSnapshot?,
        error: String?,
        isRefreshing: Bool) -> Bool
    {
        tokenRecordProviders.contains(provider) ||
            snapshot != nil ||
            error != nil ||
            isRefreshing
    }

    private var displayProviders: [UsageProvider] {
        _ = settings.menuObservationToken
        _ = store.menuObservationToken

        let enabledProviders = store.enabledProvidersForDisplay()
        let tokenProviders = tokenRecordProviders.filter { provider in
            store.tokenSnapshot(for: provider) != nil ||
                store.tokenError(for: provider) != nil ||
                store.isTokenRefreshInFlight(for: provider) ||
                store.isEnabled(provider)
        }
        let providers = enabledProviders + tokenProviders.filter { !enabledProviders.contains($0) }
        return providers.isEmpty ? [.codex] : providers
    }

    private func header(provider: UsageProvider, providers: [UsageProvider], isRefreshing: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "chart.bar.fill")
                .accessibilityHidden(true)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.emphasis.opacity(0.92))
                .frame(width: 24, height: 24)
                .background(style.controlFill)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(conductorTokenRecordsText("Token 记录", "Token Records"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(style.primaryText)
                    .lineLimit(1)
                Text(providerName(provider))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(style.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 10)

            if providers.count > 1 {
                providerMenu(provider: provider, providers: providers)
            }

            panelIconButton(
                systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise",
                help: conductorTokenRecordsText("刷新", "Refresh"),
                disabled: isRefreshing)
            {
                CodexBarEmbeddedRuntime.shared.refreshTokenRecords(provider: provider)
            }

            panelIconButton(systemName: "gearshape", help: conductorTokenRecordsText("设置", "Settings")) {
                CodexBarEmbeddedRuntime.shared.openTokenRecordSettings()
            }

            panelIconButton(systemName: "xmark", help: conductorTokenRecordsText("关闭", "Close")) {
                CodexBarEmbeddedRuntime.shared.closeTokenRecordsWindow()
            }
        }
    }

    private func providerMenu(provider: UsageProvider, providers: [UsageProvider]) -> some View {
        Menu {
            ForEach(providers, id: \.self) { option in
                Button(providerName(option)) {
                    selectedProvider = option
                    CodexBarEmbeddedRuntime.shared.refreshTokenRecords(provider: option)
                }
            }
        } label: {
            Label(providerName(provider), systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .help(conductorTokenRecordsText("切换来源", "Switch Source"))
    }

    private func panelIconButton(
        systemName: String,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(help, systemImage: systemName)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(help)
    }

    private func summary(snapshot: CostUsageTokenSnapshot) -> some View {
        ConductorTokenSnapshotSummary(snapshot: snapshot, style: style)
    }

    private func summaryTile(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(style.tertiaryText)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(style.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(subtitle)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(style.tertiaryText)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(style.controlFill.opacity(style.usesDarkChrome ? 0.62 : 0.78))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(style.stroke.opacity(0.46), lineWidth: 0.7)
        }
    }

    private func chart(provider: UsageProvider, snapshot: CostUsageTokenSnapshot) -> some View {
        ConductorTokenHistoryPanel(
            provider: provider,
            daily: snapshot.daily,
            totalCostUSD: snapshot.last30DaysCostUSD,
            historyDays: snapshot.historyDays,
            style: style)
    }

    private func records(snapshot: CostUsageTokenSnapshot) -> some View {
        let entries = recentEntries(snapshot)
        return ConductorTokenTimeline(entries: entries, style: style)
    }

    private func recordRow(_ entry: CostUsageDailyReport.Entry) -> some View {
        HStack(spacing: 12) {
            Text(entry.date)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.primaryText)
                .frame(width: 86, alignment: .leading)

            tokenPill(title: conductorTokenRecordsText("输入", "In"), value: entry.inputTokens)
            tokenPill(title: conductorTokenRecordsText("输出", "Out"), value: entry.outputTokens)
            tokenPill(title: conductorTokenRecordsText("缓存", "Cache"), value: cacheTokens(entry))

            Spacer(minLength: 8)

            Text(totalTokens(entry).map(UsageFormatter.tokenCountString) ?? "--")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.primaryText)
                .frame(width: 64, alignment: .trailing)

            Text(entry.costUSD.map(UsageFormatter.usdString) ?? "--")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.secondaryText)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func tokenPill(title: String, value: Int?) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(style.tertiaryText)
            Text(value.map(UsageFormatter.tokenCountString) ?? "--")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(style.secondaryText)
        }
        .frame(width: 74, alignment: .leading)
    }

    private func emptyState(provider: UsageProvider, error: String?, isRefreshing: Bool) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(style.emphasis.opacity(style.usesDarkChrome ? 0.20 : 0.14))
                Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "doc.text.magnifyingglass")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(style.emphasis)
            }
            .frame(width: 58, height: 58)

            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .tint(style.emphasis)
            }

            Text(emptyTitle(error: error, isRefreshing: isRefreshing))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(style.primaryText)
                .lineLimit(1)

            if let error, !error.isEmpty, !isRefreshing {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(style.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 8) {
                filledPanelButton(title: conductorTokenRecordsText("刷新", "Refresh")) {
                    CodexBarEmbeddedRuntime.shared.refreshTokenRecords(provider: provider)
                }
                filledPanelButton(title: conductorTokenRecordsText("设置", "Settings")) {
                    CodexBarEmbeddedRuntime.shared.openTokenRecordSettings()
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 330)
    }

    private func filledPanelButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(style.separator.opacity(0.84))
            .frame(height: 1)
    }

    private func panelSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return content()
            .background {
                shape
                    .fill(style.panelBase)
                    .overlay {
                        shape.fill(style.panelWash.opacity(style.usesDarkChrome ? 0.72 : 0.90))
                    }
                    .overlay(alignment: .topLeading) {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(style.usesDarkChrome ? 0.018 : 0.028),
                                Color.white.opacity(style.usesDarkChrome ? 0.006 : 0.010),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing)
                            .clipShape(shape)
                    }
            }
            .clipShape(shape)
            .overlay {
                shape
                    .stroke(style.stroke.opacity(0.82), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
    }

    private func emptyTitle(error: String?, isRefreshing: Bool) -> String {
        if isRefreshing {
            return conductorTokenRecordsText("正在读取 Token 记录", "Reading token records")
        }
        if error != nil {
            return conductorTokenRecordsText("暂无 Token 记录", "No token records")
        }
        return conductorTokenRecordsText("暂无 Token 记录", "No token records")
    }

    private func recentEntries(_ snapshot: CostUsageTokenSnapshot) -> [CostUsageDailyReport.Entry] {
        Array(snapshot.daily.sorted { $0.date > $1.date }.prefix(30))
    }

    private func cacheTokens(_ entry: CostUsageDailyReport.Entry) -> Int? {
        let values = [entry.cacheReadTokens, entry.cacheCreationTokens].compactMap(\.self)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private func totalTokens(_ entry: CostUsageDailyReport.Entry) -> Int? {
        if let totalTokens = entry.totalTokens {
            return totalTokens
        }
        let values = [
            entry.inputTokens,
            entry.outputTokens,
            entry.cacheReadTokens,
            entry.cacheCreationTokens,
        ].compactMap(\.self)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private func providerName(_ provider: UsageProvider) -> String {
        ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
    }

    private func currentProvider(from providers: [UsageProvider]) -> UsageProvider {
        providers.contains(selectedProvider) ? selectedProvider : (providers.first ?? .codex)
    }

    private func normalizeSelection(_ providers: [UsageProvider]) {
        guard !providers.contains(selectedProvider), let first = providers.first else { return }
        selectedProvider = first
    }

    private func providerIDs(_ providers: [UsageProvider]) -> String {
        providers.map(\.rawValue).joined(separator: ",")
    }

    private func localized(_ text: String) -> String {
        codexBarLocalizedDisplayText(text)
    }

    private func t(_ zh: String, _ en: String) -> String {
        conductorTokenRecordsText(zh, en, languageIdentifier: languageIdentifier)
    }

    private func markerOffset(width: CGFloat, percent: Double, markerWidth: CGFloat) -> CGFloat {
        let clamped = max(0, min(100, percent))
        return max(0, min(width - markerWidth, width * clamped / 100))
    }
}

private struct ConductorWindowDragRegion: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        ConductorWindowDragNSView()
    }

    func updateNSView(_: NSView, context _: Context) {}
}

private final class ConductorWindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }
}

private struct ConductorUsageActionTile: View {
    let title: String
    let subtitle: String
    let systemName: String
    let style: ConductorUsagePanelStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(style.emphasis)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(style.primaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10.2, weight: .medium))
                        .foregroundStyle(style.tertiaryText)
                        .lineLimit(2)
                }
                .layoutPriority(1)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(style.emphasis)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

private struct ConductorUsageSummaryChip: View {
    let title: String
    let value: String
    let style: ConductorUsagePanelStyle

    var body: some View {
        HStack(spacing: 5) {
            Text(codexBarLocalizedDisplayText(title))
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(style.tertiaryText)
                .lineLimit(1)
            Text(codexBarLocalizedDisplayText(value))
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(style.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
    }
}

private struct ConductorExpandableInsightPanel<Summary: View, Content: View>: View {
    let title: String
    let subtitle: String
    let systemName: String
    let style: ConductorUsagePanelStyle
    @Binding var isExpanded: Bool
    private let summary: () -> Summary
    private let content: () -> Content

    init(
        title: String,
        subtitle: String,
        systemName: String,
        style: ConductorUsagePanelStyle,
        isExpanded: Binding<Bool>,
        @ViewBuilder summary: @escaping () -> Summary,
        @ViewBuilder content: @escaping () -> Content)
    {
        self.title = title
        self.subtitle = subtitle
        self.systemName = systemName
        self.style = style
        self._isExpanded = isExpanded
        self.summary = summary
        self.content = content
    }

    private var expansion: Binding<Bool> {
        Binding {
            isExpanded
        } set: { newValue in
            guard newValue != isExpanded else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isExpanded = newValue
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: expansion) {
                Rectangle()
                    .fill(style.separator.opacity(0.50))
                    .frame(height: 1)
                    .padding(.vertical, 10)

                content()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity))
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(style.emphasis.opacity(isExpanded ? 0.18 : 0.12))
                            Image(systemName: systemName)
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundStyle(style.emphasis)
                                .accessibilityHidden(true)
                        }
                        .frame(width: 34, height: 34)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(.system(size: 12.4, weight: .bold))
                                .foregroundStyle(style.primaryText)
                                .lineLimit(1)
                            Text(subtitle)
                                .font(.system(size: 10.3, weight: .medium))
                                .foregroundStyle(style.tertiaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .layoutPriority(1)
                    }

                    HStack(spacing: 6) {
                        summary()
                    }
                    .padding(.leading, 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
            }
            .tint(style.tertiaryText)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded
                ? conductorTokenRecordsText("已展开", "Expanded")
                : conductorTokenRecordsText("已收起", "Collapsed"))
        }
        .padding(.bottom, isExpanded ? 12 : 0)
        .padding(.trailing, 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(style.controlFill.opacity(isExpanded ? 0.46 : 0.34))
                .overlay(alignment: .topTrailing) {
                    ConductorUsageCircuitOverlay(style: style)
                        .opacity(isExpanded ? 0.16 : 0.10)
                        .frame(width: 180, height: 86)
                        .allowsHitTesting(false)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(style.stroke.opacity(isExpanded ? 0.42 : 0.24), lineWidth: 0.7)
        }
    }
}

private struct ConductorEmbeddedChartPanel<Content: View>: View {
    let title: String
    let subtitle: String
    let systemName: String
    let style: ConductorUsagePanelStyle
    let minHeight: CGFloat
    let showsHeader: Bool
    let usesChrome: Bool
    private let content: (CGFloat) -> Content

    init(
        title: String,
        subtitle: String,
        systemName: String,
        style: ConductorUsagePanelStyle,
        minHeight: CGFloat,
        showsHeader: Bool = true,
        usesChrome: Bool = true,
        @ViewBuilder content: @escaping (CGFloat) -> Content)
    {
        self.title = title
        self.subtitle = subtitle
        self.systemName = systemName
        self.style = style
        self.minHeight = minHeight
        self.showsHeader = showsHeader
        self.usesChrome = usesChrome
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if usesChrome {
            panelContent
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(style.controlFill.opacity(style.usesDarkChrome ? 0.38 : 0.56))
                        .overlay(alignment: .topTrailing) {
                            ConductorUsageCircuitOverlay(style: style)
                                .opacity(style.usesDarkChrome ? 0.22 : 0.14)
                                .frame(width: 190, height: 96)
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(style.stroke.opacity(0.34), lineWidth: 0.7)
                }
                .environment(\.colorScheme, style.colorScheme)
                .tint(style.emphasis)
        } else {
            panelContent
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                .environment(\.colorScheme, style.colorScheme)
                .tint(style.emphasis)
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                panelHeader
            }

            GeometryReader { proxy in
                content(max(280, proxy.size.width - 4))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: chartHeight)
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(style.emphasis)
                .frame(width: 26, height: 26)
                .background(style.controlStrongFill.opacity(style.usesDarkChrome ? 0.46 : 0.66))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(style.primaryText)
                Text(subtitle)
                    .font(.system(size: 10.3, weight: .medium))
                    .foregroundStyle(style.tertiaryText)
            }
            Spacer(minLength: 0)
        }
    }

    private var chartHeight: CGFloat {
        max(140, minHeight - (showsHeader ? 68 : 0))
    }
}

private struct ConductorStorageFootprintPanel: View {
    let footprint: ProviderStorageFootprint
    let style: ConductorUsagePanelStyle
    let showsHeader: Bool
    let usesChrome: Bool
    @State private var revealed = false

    init(
        footprint: ProviderStorageFootprint,
        style: ConductorUsagePanelStyle,
        showsHeader: Bool = true,
        usesChrome: Bool = true)
    {
        self.footprint = footprint
        self.style = style
        self.showsHeader = showsHeader
        self.usesChrome = usesChrome
    }

    private var visibleComponents: [ProviderStorageFootprint.Component] {
        Array(footprint.components.prefix(6))
    }

    private var visibleRecommendations: [ProviderStorageRecommendation] {
        Array(footprint.cleanupRecommendations.prefix(3))
    }

    private var maxBytes: Int64 {
        max(visibleComponents.map(\.totalBytes).max() ?? 0, 1)
    }

    var body: some View {
        if usesChrome {
            content
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(style.controlFill.opacity(style.usesDarkChrome ? 0.38 : 0.56))
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(style.stroke.opacity(0.34), lineWidth: 0.7)
                }
                .onAppear {
                    withAnimation(.spring(response: 0.58, dampingFraction: 0.86)) {
                        revealed = true
                    }
                }
        } else {
            content
                .onAppear {
                    withAnimation(.spring(response: 0.58, dampingFraction: 0.86)) {
                        revealed = true
                    }
                }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                header
            }

            if visibleComponents.isEmpty {
                Text(conductorTokenRecordsText("没有发现本地数据", "No local data found"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(style.secondaryText)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(visibleComponents.enumerated()), id: \.element.id) { index, component in
                        componentRow(component, index: index)
                    }
                }
            }

            if footprint.components.count > visibleComponents.count {
                Text(conductorTokenRecordsText(
                    "还有 \(footprint.components.count - visibleComponents.count) 项",
                    "\(footprint.components.count - visibleComponents.count) more items"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(style.tertiaryText)
            }

            if !visibleRecommendations.isEmpty {
                Rectangle()
                    .fill(style.separator.opacity(0.62))
                    .frame(height: 1)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 7) {
                    Text(conductorTokenRecordsText("清理建议", "Cleanup Ideas"))
                        .font(.system(size: 11.2, weight: .bold))
                        .foregroundStyle(style.secondaryText)
                    ForEach(visibleRecommendations) { recommendation in
                        recommendationRow(recommendation)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(style.emphasis)
                .frame(width: 26, height: 26)
                .background(style.controlStrongFill.opacity(style.usesDarkChrome ? 0.46 : 0.66))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(conductorTokenRecordsText("本地存储", "Storage"))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(style.primaryText)
                Text("\(ProviderDescriptorRegistry.descriptor(for: footprint.provider).metadata.displayName) · \(UsageFormatter.byteCountString(footprint.totalBytes))")
                    .font(.system(size: 10.3, weight: .medium))
                    .foregroundStyle(style.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func componentRow(_ component: ProviderStorageFootprint.Component, index: Int) -> some View {
        let fraction = CGFloat(max(0, min(1, Double(component.totalBytes) / Double(maxBytes))))
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(component.path)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(component.path)
                    .layoutPriority(1)
                StoragePathCopyButton(path: component.path)
                Text(UsageFormatter.byteCountString(component.totalBytes))
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(style.primaryText)
                    .lineLimit(1)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(style.separator.opacity(style.usesDarkChrome ? 0.34 : 0.26))
                    Capsule()
                        .fill(storageFill(index: index))
                        .frame(width: revealed ? max(3, proxy.size.width * fraction) : 3)
                }
            }
            .frame(height: 5)
        }
    }

    private func recommendationRow(_ recommendation: ProviderStorageRecommendation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(style.emphasis)
                .frame(width: 20, height: 20)
                .background(style.controlStrongFill.opacity(0.54))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(codexBarLocalizedDisplayText(recommendation.title))
                        .font(.system(size: 10.6, weight: .bold))
                        .foregroundStyle(style.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(UsageFormatter.byteCountString(recommendation.bytes))
                        .font(.system(size: 10.2, weight: .semibold, design: .rounded))
                        .foregroundStyle(style.secondaryText)
                        .lineLimit(1)
                }
                Text(codexBarLocalizedDisplayText(recommendation.consequence))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(style.tertiaryText)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(style.controlStrongFill.opacity(style.usesDarkChrome ? 0.30 : 0.42))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func storageFill(index: Int) -> Color {
        let accents = [
            style.emphasis,
            Color(nsColor: .systemTeal),
            Color(nsColor: .systemIndigo),
            Color(nsColor: .systemOrange),
        ]
        return accents[index % accents.count].opacity(style.usesDarkChrome ? 0.82 : 0.74)
    }
}

private struct ConductorSignalInfoCard: View {
    let systemName: String
    let title: String
    let primary: String
    let secondary: String?
    let style: ConductorUsagePanelStyle

    var body: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(style.secondaryText)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(style.tertiaryText)
                        .lineLimit(1)
                    Text(primary)
                        .font(.system(size: 12.2, weight: .bold, design: .rounded))
                        .foregroundStyle(style.primaryText)
                        .lineLimit(1)
                    if let secondary, !secondary.isEmpty {
                        Text(secondary)
                            .font(.system(size: 10.2, weight: .medium))
                            .foregroundStyle(style.secondaryText)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 6)
            }
        }
        .groupBoxStyle(.automatic)
    }
}

private struct ConductorCostSignalCard: View {
    let section: UsageMenuCardView.Model.ProviderCostSection
    let style: ConductorUsagePanelStyle
    @State private var revealed = false

    var body: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 12) {
                ConductorMiniArc(
                    percent: section.percentUsed ?? 0,
                    style: style,
                    revealed: revealed)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 5) {
                    Text(codexBarLocalizedDisplayText(section.title))
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(style.tertiaryText)
                        .lineLimit(1)
                    Text(codexBarLocalizedDisplayText(section.spendLine))
                        .font(.system(size: 12.4, weight: .bold, design: .rounded))
                        .foregroundStyle(style.primaryText)
                        .lineLimit(1)
                    if let percentLine = section.percentLine {
                        Text(codexBarLocalizedDisplayText(percentLine))
                            .font(.system(size: 10.2, weight: .medium))
                            .foregroundStyle(style.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                ConductorMicroRail(
                    percent: section.percentUsed ?? 0,
                    style: style,
                    revealed: revealed)
                    .frame(width: 110, height: 26)
            }
        }
        .groupBoxStyle(.automatic)
        .onAppear {
            withAnimation(.spring(response: 0.58, dampingFraction: 0.84).delay(0.05)) {
                revealed = true
            }
        }
    }
}

private struct ConductorTokenUsageSignalCard: View {
    let section: UsageMenuCardView.Model.TokenUsageSection
    let style: ConductorUsagePanelStyle

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(style.secondaryText)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                    Text(codexBarLocalizedDisplayText(L("cost_header_estimated")))
                        .font(.system(size: 10.8, weight: .bold))
                        .foregroundStyle(style.tertiaryText)
                    Spacer()
                }

                HStack(spacing: 7) {
                    ConductorTokenLinePill(text: section.sessionLine, style: style, prominent: true)
                    ConductorTokenLinePill(text: section.monthLine, style: style, prominent: false)
                }

                if let hint = section.hintLine, !hint.isEmpty {
                    Text(codexBarLocalizedDisplayText(hint))
                        .font(.system(size: 10.2, weight: .medium))
                        .foregroundStyle(style.secondaryText)
                        .lineLimit(2)
                }

                if let error = section.errorLine, !error.isEmpty {
                    Text(codexBarLocalizedDisplayText(error))
                        .font(.system(size: 10.2, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .systemRed))
                        .lineLimit(2)
                }
            }
        }
        .groupBoxStyle(.automatic)
    }
}

private struct ConductorTokenLinePill: View {
    let text: String
    let style: ConductorUsagePanelStyle
    let prominent: Bool

    var body: some View {
        Text(codexBarLocalizedDisplayText(text))
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(prominent ? style.primaryText : style.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    }
}

private struct ConductorTokenSnapshotSummary: View {
    let snapshot: CostUsageTokenSnapshot
    let style: ConductorUsagePanelStyle
    @State private var revealed = false

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ConductorSummaryNode(
                title: conductorTokenRecordsText("\(snapshot.historyDays) 天", "\(snapshot.historyDays)d"),
                value: snapshot.last30DaysCostUSD.map(UsageFormatter.usdString) ?? "--",
                subtitle: conductorTokenRecordsText("费用", "Cost"),
                index: 0,
                revealed: revealed,
                style: style)
            ConductorSummaryNode(
                title: conductorTokenRecordsText("Token 数", "Tokens"),
                value: snapshot.last30DaysTokens.map(UsageFormatter.tokenCountString) ?? "--",
                subtitle: conductorTokenRecordsText("总量", "Total"),
                index: 1,
                revealed: revealed,
                style: style)
            ConductorSummaryNode(
                title: conductorTokenRecordsText("记录", "Records"),
                value: "\(snapshot.daily.count)",
                subtitle: conductorTokenRecordsText("天", "Days"),
                index: 2,
                revealed: revealed,
                style: style)
            ConductorSummaryNode(
                title: conductorTokenRecordsText("更新", "Updated"),
                value: snapshot.updatedAt.formatted(date: .numeric, time: .shortened),
                subtitle: conductorTokenRecordsText("本地", "Local"),
                index: 3,
                revealed: revealed,
                style: style)
        }
        .onAppear {
            withAnimation(.spring(response: 0.58, dampingFraction: 0.82)) {
                revealed = true
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)]
    }
}

private struct ConductorSummaryNode: View {
    let title: String
    let value: String
    let subtitle: String
    let index: Int
    let revealed: Bool
    let style: ConductorUsagePanelStyle

    var body: some View {
        GroupBox {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .stroke(style.separator.opacity(0.28), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: revealed ? ringAmount : 0)
                        .stroke(style.emphasis.opacity(0.82), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .fill(style.emphasis.opacity(0.16))
                        .frame(width: 9, height: 9)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(style.tertiaryText)
                        .lineLimit(1)
                    Text(value)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(style.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(subtitle)
                        .font(.system(size: 9.8, weight: .medium))
                        .foregroundStyle(style.tertiaryText)
                        .lineLimit(1)
                }
            }
        }
        .groupBoxStyle(.automatic)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    }

    private var ringAmount: Double {
        [0.28, 0.46, 0.64, 0.82][index % 4]
    }
}

private struct ConductorTokenHistoryPanel: View {
    let provider: UsageProvider
    let daily: [CostUsageDailyReport.Entry]
    let totalCostUSD: Double?
    let historyDays: Int
    let style: ConductorUsagePanelStyle
    @State private var revealed = false
    @State private var sweep = false

    var body: some View {
        let entries = Array(daily.suffix(max(1, min(historyDays, 45))))
        let maxCost = max(entries.compactMap(\.costUSD).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(conductorTokenRecordsText("消耗曲线", "Usage curve"))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(style.primaryText)
                Spacer()
                if let totalCostUSD {
                    Text(estimatedTotalText(totalCostUSD))
                        .font(.system(size: 10.2, weight: .semibold))
                        .foregroundStyle(style.tertiaryText)
                        .lineLimit(1)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(entries.enumerated()), id: \.element.date) { index, entry in
                            let cost = entry.costUSD ?? 0
                            let ratio = max(0, min(1, cost / maxCost))
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(historyBarFill(ratio: ratio, isPeak: cost == maxCost))
                                .frame(maxWidth: .infinity)
                                .frame(height: revealed ? max(5, ratio * 106) : 5)
                                .animation(
                                    .spring(response: 0.64, dampingFraction: 0.84)
                                        .delay(Double(index) * 0.010),
                                    value: revealed)
                                .accessibilityLabel("\(entry.date): \(entry.costUSD.map(UsageFormatter.usdString) ?? "--")")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 14)
                    .padding(.bottom, 20)

                    ConductorHistoryRibbon(entries: entries, maxCost: maxCost, style: style, revealed: revealed)
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
                        .padding(.bottom, 20)

                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(style.usesDarkChrome ? 0.11 : 0.18),
                            Color.white.opacity(0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing)
                        .frame(width: 104)
                        .offset(x: sweep ? proxy.size.width + 40 : -128)
                        .allowsHitTesting(false)

                    HStack {
                        Text(entries.first?.date.suffix(5) ?? "")
                        Spacer()
                        Text(entries.last?.date.suffix(5) ?? "")
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(style.tertiaryText)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 3)
                }
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(style.controlStrongFill.opacity(style.usesDarkChrome ? 0.34 : 0.48))
                        .overlay {
                            VStack(spacing: 0) {
                                ForEach(0..<5, id: \.self) { _ in
                                    Rectangle()
                                        .fill(style.separator.opacity(style.usesDarkChrome ? 0.14 : 0.11))
                                        .frame(height: 1)
                                    Spacer(minLength: 0)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 16)
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .frame(height: 152)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(style.controlFill.opacity(style.usesDarkChrome ? 0.40 : 0.58))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(style.stroke.opacity(0.34), lineWidth: 0.7)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            withAnimation(.spring(response: 0.70, dampingFraction: 0.86).delay(0.04)) {
                revealed = true
            }
            withAnimation(.linear(duration: 4.2).repeatForever(autoreverses: false)) {
                sweep = true
            }
        }
    }

    private func estimatedTotalText(_ total: Double) -> String {
        let window = historyDays == 1
            ? conductorTokenRecordsText("今日", "today")
            : conductorTokenRecordsText("\(historyDays) 天", "\(historyDays)d")
        return "\(window) · \(UsageFormatter.usdString(total))"
    }

    private func historyBarFill(ratio: Double, isPeak: Bool) -> LinearGradient {
        let base = Color(red: 0.82, green: 0.55, blue: 0.25)
        let top = isPeak ? Color(nsColor: .systemYellow) : style.emphasis.opacity(0.78)
        return LinearGradient(
            colors: [
                base.opacity(0.30 + ratio * 0.22),
                top.opacity(0.52 + ratio * 0.42),
            ],
            startPoint: .bottom,
            endPoint: .top)
    }
}

private struct ConductorHistoryRibbon: View {
    let entries: [CostUsageDailyReport.Entry]
    let maxCost: Double
    let style: ConductorUsagePanelStyle
    let revealed: Bool

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard entries.count > 1 else { return }
                let count = max(entries.count - 1, 1)
                for index in entries.indices {
                    let cost = entries[index].costUSD ?? 0
                    let ratio = CGFloat(max(0, min(1, cost / maxCost)))
                    let point = CGPoint(
                        x: CGFloat(index) / CGFloat(count) * proxy.size.width,
                        y: (1 - ratio) * proxy.size.height)
                    if index == entries.startIndex {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
            }
            .trim(from: 0, to: revealed ? 1 : 0)
            .stroke(
                style.primaryText.opacity(style.usesDarkChrome ? 0.32 : 0.24),
                style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            .animation(.easeOut(duration: 0.72).delay(0.16), value: revealed)
        }
    }
}

private struct ConductorTokenTimeline: View {
    let entries: [CostUsageDailyReport.Entry]
    let style: ConductorUsagePanelStyle
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(conductorTokenRecordsText("明细", "Details"))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(style.primaryText)
                Spacer()
                Text("\(entries.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(style.tertiaryText)
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(style.controlStrongFill.opacity(style.usesDarkChrome ? 0.42 : 0.58))
                    .clipShape(Capsule())
            }

            VStack(spacing: 7) {
                ForEach(Array(entries.prefix(18).enumerated()), id: \.element.date) { index, entry in
                    ConductorTokenTimelineRow(
                        entry: entry,
                        index: index,
                        revealed: revealed,
                        style: style)
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(style.controlFill.opacity(style.usesDarkChrome ? 0.38 : 0.54))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(style.stroke.opacity(0.32), lineWidth: 0.7)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.84)) {
                revealed = true
            }
        }
    }
}

private struct ConductorTokenTimelineRow: View {
    let entry: CostUsageDailyReport.Entry
    let index: Int
    let revealed: Bool
    let style: ConductorUsagePanelStyle

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 3) {
                Circle()
                    .fill(style.emphasis.opacity(0.75))
                    .frame(width: 7, height: 7)
                Rectangle()
                    .fill(style.separator.opacity(0.28))
                    .frame(width: 1, height: 28)
            }
            .opacity(revealed ? 1 : 0)
            .animation(.easeOut(duration: 0.22).delay(Double(index) * 0.018), value: revealed)

            Text(entry.date)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(style.primaryText)
                .frame(width: 78, alignment: .leading)

            HStack(spacing: 5) {
                tokenCapsule(title: conductorTokenRecordsText("入", "In"), value: entry.inputTokens)
                tokenCapsule(title: conductorTokenRecordsText("出", "Out"), value: entry.outputTokens)
                tokenCapsule(title: conductorTokenRecordsText("缓存", "Cache"), value: cacheTokens(entry))
            }

            Spacer(minLength: 6)

            Text(totalTokens(entry).map(UsageFormatter.tokenCountString) ?? "--")
                .font(.system(size: 11.2, weight: .bold, design: .rounded))
                .foregroundStyle(style.primaryText)
                .frame(width: 64, alignment: .trailing)

            Text(entry.costUSD.map(UsageFormatter.usdString) ?? "--")
                .font(.system(size: 11.2, weight: .bold, design: .rounded))
                .foregroundStyle(style.secondaryText)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(style.controlStrongFill.opacity(style.usesDarkChrome ? 0.30 : 0.44))
        }
        .offset(x: revealed ? 0 : 8)
        .opacity(revealed ? 1 : 0)
        .animation(.spring(response: 0.46, dampingFraction: 0.84).delay(Double(index) * 0.018), value: revealed)
    }

    private func tokenCapsule(title: String, value: Int?) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 9.2, weight: .bold))
                .foregroundStyle(style.tertiaryText)
            Text(value.map(UsageFormatter.tokenCountString) ?? "--")
                .font(.system(size: 10.2, weight: .bold, design: .rounded))
                .foregroundStyle(style.secondaryText)
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(style.controlFill.opacity(style.usesDarkChrome ? 0.44 : 0.62))
        .clipShape(Capsule())
    }

    private func cacheTokens(_ entry: CostUsageDailyReport.Entry) -> Int? {
        let values = [entry.cacheReadTokens, entry.cacheCreationTokens].compactMap(\.self)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private func totalTokens(_ entry: CostUsageDailyReport.Entry) -> Int? {
        if let totalTokens = entry.totalTokens {
            return totalTokens
        }
        let values = [
            entry.inputTokens,
            entry.outputTokens,
            entry.cacheReadTokens,
            entry.cacheCreationTokens,
        ].compactMap(\.self)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }
}

private struct ConductorMiniArc: View {
    let percent: Double
    let style: ConductorUsagePanelStyle
    let revealed: Bool

    var body: some View {
        let clamped = max(0, min(100, percent))
        ZStack {
            Circle()
                .stroke(style.separator.opacity(0.26), lineWidth: 5)
            Circle()
                .trim(from: 0, to: revealed ? clamped / 100 : 0)
                .stroke(style.emphasis.opacity(0.84), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(clamped.rounded()))")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(style.primaryText)
        }
    }
}

private struct ConductorMicroRail: View {
    let percent: Double
    let style: ConductorUsagePanelStyle
    let revealed: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<16, id: \.self) { index in
                let threshold = Double(index + 1) / 16 * 100
                let active = threshold <= max(0, min(100, percent)) * (revealed ? 1 : 0)
                Capsule()
                    .fill(active ? style.emphasis.opacity(0.48 + Double(index % 4) * 0.10) : style.separator.opacity(0.24))
                    .frame(maxWidth: .infinity)
                    .frame(height: active ? CGFloat([8, 15, 11, 20][index % 4]) : 6)
            }
        }
    }
}

private struct ConductorUsageMetricTile: View {
    let metric: UsageMenuCardView.Model.Metric
    let provider: UsageProvider
    let progressColor: Color
    let style: ConductorUsagePanelStyle
    @State private var revealed = false

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                ConductorGaugeDial(
                    percent: metric.statusText == nil ? metric.percent : 0,
                    tint: progressColor,
                    style: style,
                    revealed: revealed)
                    .frame(width: 74, height: 74)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(codexBarLocalizedDisplayText(
                            UsageMenuCardView.popupMetricTitle(provider: provider, metric: metric)))
                            .font(.system(size: 12.2, weight: .bold))
                            .foregroundStyle(style.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Spacer(minLength: 0)
                        if metric.statusText == nil {
                            Text(metric.percentLabel)
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(style.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    if let statusText = metric.statusText {
                        Text(codexBarLocalizedDisplayText(statusText))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(style.secondaryText)
                            .lineLimit(2)
                    } else {
                        ConductorSegmentedUsageTrack(
                            percent: metric.percent,
                            tint: progressColor,
                            pacePercent: metric.pacePercent,
                            warningMarkerPercents: metric.warningMarkerPercents,
                            style: style,
                            revealed: revealed)
                            .frame(height: 18)

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if let detailLeft = metric.detailLeftText {
                                Text(codexBarLocalizedDisplayText(detailLeft))
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(style.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if let resetText = metric.resetText {
                                Text(codexBarLocalizedDisplayText(resetText))
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(style.tertiaryText)
                                    .lineLimit(1)
                            }
                        }

                        if let detailText = metric.detailText {
                            Text(codexBarLocalizedDisplayText(detailText))
                                .font(.system(size: 10.2, weight: .medium))
                                .foregroundStyle(style.tertiaryText)
                                .lineLimit(1)
                        }

                        if let detailRight = metric.detailRightText {
                            Text(codexBarLocalizedDisplayText(detailRight))
                                .font(.system(size: 10.2, weight: .medium))
                                .foregroundStyle(style.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .groupBoxStyle(.automatic)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .onAppear {
            withAnimation(.spring(response: 0.58, dampingFraction: 0.82).delay(0.05)) {
                revealed = true
            }
        }
    }
}

private struct ConductorGaugeDial: View {
    let percent: Double
    let tint: Color
    let style: ConductorUsagePanelStyle
    let revealed: Bool

    var body: some View {
        let clamped = max(0, min(100, percent))
        ZStack {
            Circle()
                .stroke(style.separator.opacity(style.usesDarkChrome ? 0.34 : 0.26), lineWidth: 7)

            Circle()
                .trim(from: 0, to: revealed ? clamped / 100 : 0)
                .stroke(
                    AngularGradient(
                        colors: [
                            tint.opacity(0.48),
                            tint,
                            style.emphasis.opacity(0.92),
                        ],
                        center: .center),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: 0.02, to: 0.13)
                .stroke(style.primaryText.opacity(style.usesDarkChrome ? 0.28 : 0.20), lineWidth: 1.2)
                .rotationEffect(.degrees(revealed ? 210 : 120))
                .animation(.linear(duration: 5).repeatForever(autoreverses: false), value: revealed)

            VStack(spacing: 0) {
                Text("\(Int(clamped.rounded()))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(style.primaryText)
                    .lineLimit(1)
                Text("%")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(style.tertiaryText)
                    .offset(y: -1)
            }
        }
        .accessibilityLabel(conductorTokenRecordsText("用量百分比", "Usage percentage"))
        .accessibilityValue("\(Int(clamped.rounded()))%")
    }
}

private struct ConductorSegmentedUsageTrack: View {
    let percent: Double
    let tint: Color
    let pacePercent: Double?
    let warningMarkerPercents: [Double]
    let style: ConductorUsagePanelStyle
    let revealed: Bool

    private let segmentCount = 30

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<segmentCount, id: \.self) { index in
                        let segmentLimit = Double(index + 1) / Double(segmentCount) * 100
                        let active = segmentLimit <= max(0, min(100, percent)) * (revealed ? 1 : 0)
                        Capsule()
                            .fill(active ? tint.opacity(activeOpacity(index)) : style.separator.opacity(0.28))
                            .frame(maxWidth: .infinity)
                            .frame(height: active ? segmentHeight(index) : 7)
                    }
                }

                if let pacePercent {
                    Capsule()
                        .fill(style.primaryText.opacity(0.52))
                        .frame(width: 3, height: 18)
                        .offset(x: markerOffset(width: proxy.size.width, percent: pacePercent, markerWidth: 3))
                        .shadow(color: style.primaryText.opacity(0.20), radius: 3, y: 1)
                }

                ForEach(Array(warningMarkerPercents.enumerated()), id: \.offset) { _, marker in
                    Capsule()
                        .fill(Color(nsColor: .systemRed).opacity(0.76))
                        .frame(width: 2, height: 16)
                        .offset(x: markerOffset(width: proxy.size.width, percent: marker, markerWidth: 2))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityLabel(conductorTokenRecordsText("用量轨道", "Usage rail"))
        .accessibilityValue(String(format: "%.0f%%", percent))
    }

    private func activeOpacity(_ index: Int) -> Double {
        0.50 + Double(index % 5) * 0.08
    }

    private func segmentHeight(_ index: Int) -> CGFloat {
        [8, 11, 14, 10, 16, 12][index % 6]
    }

    private func markerOffset(width: CGFloat, percent: Double, markerWidth: CGFloat) -> CGFloat {
        let clamped = max(0, min(100, percent))
        return max(0, min(width - markerWidth, width * clamped / 100))
    }
}

private struct ConductorInlineUsageDashboardCard: View {
    let model: InlineUsageDashboardModel
    let style: ConductorUsagePanelStyle
    @State private var revealed = false
    @State private var sweep = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
                ForEach(Array(model.kpis.prefix(4).enumerated()), id: \.offset) { _, kpi in
                    ConductorDashboardKPI(kpi: kpi, style: style)
                }
            }

            ConductorUsageBarscape(
                model: model,
                style: style,
                revealed: revealed,
                sweep: sweep)
                .frame(height: 112)
                .accessibilityLabel(model.accessibilityLabel)

            if !model.detailLines.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(model.detailLines.prefix(3).enumerated()), id: \.offset) { _, line in
                        Text(codexBarLocalizedDisplayText(line))
                            .font(.system(size: 10.2, weight: .semibold))
                            .foregroundStyle(style.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(style.controlStrongFill.opacity(style.usesDarkChrome ? 0.46 : 0.62))
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(style.controlFill.opacity(style.usesDarkChrome ? 0.42 : 0.60))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(style.stroke.opacity(0.34), lineWidth: 0.7)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.86).delay(0.08)) {
                revealed = true
            }
            withAnimation(.linear(duration: 3.8).repeatForever(autoreverses: false)) {
                sweep = true
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 118), spacing: 7, alignment: .leading)]
    }
}

private struct ConductorDashboardKPI: View {
    let kpi: InlineUsageDashboardModel.KPI
    let style: ConductorUsagePanelStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(codexBarLocalizedDisplayText(kpi.title))
                .font(.system(size: 10.2, weight: .bold))
                .foregroundStyle(style.tertiaryText)
                .lineLimit(1)

            Text(kpi.value)
                .font(.system(size: kpi.emphasis ? 16 : 13, weight: .bold, design: .rounded))
                .foregroundStyle(kpi.emphasis ? style.primaryText : style.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(kpi.emphasis
                    ? style.controlStrongFill.opacity(style.usesDarkChrome ? 0.62 : 0.78)
                    : style.controlStrongFill.opacity(style.usesDarkChrome ? 0.32 : 0.48))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(kpi.emphasis ? style.emphasis : style.separator.opacity(0.54))
                        .frame(width: 3)
                        .padding(.vertical, 7)
                }
        }
    }
}

private struct ConductorUsageBarscape: View {
    let model: InlineUsageDashboardModel
    let style: ConductorUsagePanelStyle
    let revealed: Bool
    let sweep: Bool

    var body: some View {
        let points = Array(model.points.suffix(34))
        let maxValue = max(points.map(\.value).max() ?? 0, 1)
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                bars(points: points, maxValue: maxValue)
                    .padding(.horizontal, 8)
                    .padding(.top, 14)
                    .padding(.bottom, 18)

                trendLine(points: points, maxValue: maxValue)
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
                    .padding(.bottom, 18)

                baselineLabels(points: points)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(style.usesDarkChrome ? 0.12 : 0.20),
                        Color.white.opacity(0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing)
                    .frame(width: 90)
                    .offset(x: sweep ? proxy.size.width + 30 : -120)
                    .allowsHitTesting(false)
            }
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(style.controlStrongFill.opacity(style.usesDarkChrome ? 0.34 : 0.46))
                    .overlay {
                        VStack(spacing: 0) {
                            ForEach(0..<4, id: \.self) { _ in
                                Rectangle()
                                    .fill(style.separator.opacity(style.usesDarkChrome ? 0.16 : 0.12))
                                    .frame(height: 1)
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 15)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private func bars(points: [InlineUsageDashboardModel.Point], maxValue: Double) -> some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                let ratio = max(0, min(1, point.value / maxValue))
                Capsule()
                    .fill(barFill(ratio: ratio, isPeak: point.value == maxValue))
                    .frame(maxWidth: .infinity)
                    .frame(height: revealed ? max(4, ratio * 72) : 4)
                    .animation(
                        .spring(response: 0.60, dampingFraction: 0.82)
                            .delay(Double(index) * 0.012),
                        value: revealed)
                    .accessibilityLabel(point.accessibilityValue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func trendLine(points: [InlineUsageDashboardModel.Point], maxValue: Double) -> some View {
        GeometryReader { proxy in
            Path { path in
                guard points.count > 1 else { return }
                let count = max(points.count - 1, 1)
                for index in points.indices {
                    let point = points[index]
                    let x = CGFloat(index) / CGFloat(count) * proxy.size.width
                    let ratio = CGFloat(max(0, min(1, point.value / maxValue)))
                    let y = (1 - ratio) * proxy.size.height
                    if index == points.startIndex {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .trim(from: 0, to: revealed ? 1 : 0)
            .stroke(
                style.emphasis.opacity(style.usesDarkChrome ? 0.45 : 0.34),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            .animation(.easeOut(duration: 0.7).delay(0.12), value: revealed)
        }
    }

    private func baselineLabels(points: [InlineUsageDashboardModel.Point]) -> some View {
        HStack {
            if let first = points.first {
                Text(first.label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(style.tertiaryText)
            }
            Spacer()
            if let last = points.last {
                Text(last.label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(style.tertiaryText)
            }
        }
    }

    private func barFill(ratio: Double, isPeak: Bool) -> LinearGradient {
        let base: Color = switch model.valueStyle {
        case .currencyUSD, .currency:
            Color(red: 0.82, green: 0.55, blue: 0.25)
        case .tokens:
            style.emphasis
        }
        let top = isPeak ? Color(nsColor: .systemYellow) : base.opacity(0.96)
        return LinearGradient(
            colors: [
                base.opacity(0.36 + ratio * 0.28),
                top.opacity(0.64 + ratio * 0.34),
            ],
            startPoint: .bottom,
            endPoint: .top)
    }
}

private struct ConductorUsageCircuitOverlay: View {
    let style: ConductorUsagePanelStyle

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = proxy.size.height
                for index in 0..<7 {
                    let y = CGFloat(index) / 6 * height
                    path.move(to: CGPoint(x: width * 0.16, y: y))
                    path.addLine(to: CGPoint(x: width, y: min(height, y + height * 0.22)))
                }
                for index in 0..<5 {
                    let x = CGFloat(index) / 4 * width
                    path.move(to: CGPoint(x: x, y: height * 0.10))
                    path.addLine(to: CGPoint(x: min(width, x + width * 0.22), y: height))
                }
            }
            .stroke(style.stroke.opacity(0.62), lineWidth: 0.7)
        }
    }
}
