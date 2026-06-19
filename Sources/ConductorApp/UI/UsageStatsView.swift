import AppKit
import ConductorCore
import SwiftUI

/// Token 用量仪表盘：扫描 Claude / Codex 会话日志，按天 / 模型 / 项目聚合 token 与估算成本。
struct UsageStatsView: View {
    var onOpenManagement: () -> Void = {}
    /// 主题变 → 重渲染（AppStyle 跟随）。不观察的话切主题后停在旧配色。
    @ObservedObject private var configStore = ConfigStore.shared
    @State private var report: UsageReport?
    @State private var loading = false
    @State private var daysBack = 30
    @State private var daysBackText = "30"
    @State private var selectedDay: String?
    @State private var hoveredDay: String?
    @State private var contentWidthToken = 0
    @State private var contentHeightCache: [String: CGFloat] = [:]
    /// 按 CLI 过滤（nil = 全部）。所有区块跟随。
    @State private var sourceFilter: UsageSource?

    private static let claudeColor = Color(red: 0.85, green: 0.45, blue: 0.18)
    private static let codexColor = Color(red: 0.22, green: 0.62, blue: 0.40)
    private static let vertexAIColor = Color(red: 0.24, green: 0.48, blue: 0.92)
    private static let bedrockColor = Color(red: 0.95, green: 0.54, blue: 0.12)
    private static let dailyChartHeight: CGFloat = 96
    private static let dailyBarMaxHeight: CGFloat = 88
    private static let dailyPeakCapHeight: CGFloat = 4
    private static let dayDetailHeight: CGFloat = 184
    private static let dayDetailModelViewportHeight: CGFloat = 86
    private static let contentHeightCacheLimit = 64
    private static let contentHeightChangeThreshold: CGFloat = 1
    private static let contentWidthFingerprintBucket: CGFloat = 4

    static func color(for source: UsageSource) -> Color {
        switch source {
        case .claude: return claudeColor
        case .codex: return codexColor
        case .vertexai: return vertexAIColor
        case .bedrock: return bedrockColor
        }
    }

    private static func contentHeightTextScaleToken() -> Int {
        Int((NSFont.preferredFont(forTextStyle: .body).pointSize * 100).rounded())
    }

    private static func contentWidthFingerprintToken(_ width: CGFloat) -> Int {
        guard width.isFinite, width > 0 else { return 0 }
        return Int((width / contentWidthFingerprintBucket).rounded()) * Int(contentWidthFingerprintBucket)
    }

    private func cachedContentHeight(for fingerprint: String) -> CGFloat? {
        guard let height = contentHeightCache[fingerprint], height > 0 else { return nil }
        return height
    }

    private func recordContentHeight(_ height: CGFloat, for fingerprint: String) {
        guard height.isFinite, height > 0 else { return }
        if let cached = contentHeightCache[fingerprint],
           abs(cached - height) <= Self.contentHeightChangeThreshold
        {
            return
        }
        if contentHeightCache.count > Self.contentHeightCacheLimit {
            contentHeightCache.removeAll(keepingCapacity: true)
        }
        contentHeightCache[fingerprint] = height
    }

    private func contentHeightFingerprint(_ r: UsageReport?) -> String {
        var parts = [
            "width=\(contentWidthToken)",
            "scale=\(Self.contentHeightTextScaleToken())",
            "days=\(daysBack)",
            "source=\(sourceFilter?.rawValue ?? "all")",
            "loading=\(loading ? 1 : 0)",
        ]
        guard let r else {
            parts.append("report=nil")
            return parts.joined(separator: "|")
        }

        let months = filteredMonthRows(r).count
        let sessions = filteredSessionRows(r).count
        let projects = filteredProjectRows(r).count
        let models = filteredModelRows(r).count
        parts.append("daily=\(r.byDay.isEmpty ? 0 : filledDays(r).count)")
        parts.append("months=\(months)")
        parts.append("sessions=\(sessions)")
        parts.append("sourceBreakdown=\(sourceFilter == nil ? UsageSource.allCases.count : 0)")
        parts.append("projects=\(projects)")
        parts.append("models=\(models)")
        parts.append("sourceInfo=\(r.sourceInfo == nil ? 0 : 1)")
        return parts.joined(separator: "|")
    }

    var body: some View {
        let heightFingerprint = contentHeightFingerprint(report)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                rangePicker
                if loading && report == nil {
                    loadingRow
                } else if let report {
                    sourcePicker(report)
                    summaryTiles(report)
                    if !report.byDay.isEmpty { dailyChart(report) }
                    if !report.monthSummaries.isEmpty { monthSection(report) }
                    if !report.bySession.isEmpty { sessionSection(report) }
                    tokenComposition(report)
                    if sourceFilter == nil { sourceBreakdown(report) }
                    projectSection(report)
                    modelTable(report)
                    footnote(report)
                } else {
                    emptyRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(minHeight: cachedContentHeight(for: heightFingerprint), alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                ceil(proxy.size.height)
            } action: { newHeight in
                recordContentHeight(newHeight, for: heightFingerprint)
            }
        }
        .onGeometryChange(for: Int.self) { proxy in
            Self.contentWidthFingerprintToken(proxy.size.width)
        } action: { newValue in
            contentWidthToken = newValue
        }
        .onAppear { if report == nil { reload() } }
    }

    // MARK: - 按 CLI 过滤

    /// 当前过滤下的区间合计。
    private func filteredGrand(_ r: UsageReport) -> UsageTotals {
        sourceFilter.flatMap { r.bySource[$0] } ?? r.grand
    }

    /// 当前过滤下某天的合计。
    private func filteredDay(_ d: DailyUsage) -> UsageTotals {
        sourceFilter.flatMap { d.bySource[$0] ?? UsageTotals() } ?? d.totals
    }

    private func filteredSessions(_ r: UsageReport) -> Int {
        sourceFilter.flatMap { r.sessionsBySource[$0] } ?? r.sessionsScanned
    }

    private func sourcePicker(_ r: UsageReport) -> some View {
        ViewThatFits(in: .horizontal) {
            sourceChips(r, includeSpacer: true)
                .fixedSize(horizontal: true, vertical: false)
            ScrollView(.horizontal) {
                sourceChips(r, includeSpacer: false)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .scrollIndicators(.never)
        }
    }

    private func sourceChips(_ r: UsageReport, includeSpacer: Bool) -> some View {
        HStack(spacing: 5) {
            sourceChip(nil, label: L("全部"), cost: r.grand.costUSD)
            ForEach(UsageSource.allCases, id: \.self) { src in
                sourceChip(src, label: src.displayName, cost: r.bySource[src]?.costUSD ?? 0)
            }
            if includeSpacer { Spacer(minLength: 0) }
        }
    }

    private func sourceChip(_ src: UsageSource?, label: String, cost: Double) -> some View {
        let selected = sourceFilter == src
        return Button {
            sourceFilter = src
            selectedDay = nil
            hoveredDay = nil
        } label: {
            HStack(spacing: 4) {
                if let src {
                    Circle().fill(Self.color(for: src)).frame(width: 7, height: 7)
                }
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
                Text("$" + UsageNumber.money(cost))
                    .font(.system(size: 9.5, weight: .medium))
                    .opacity(0.75)
            }
            .foregroundStyle(selected ? AppStyle.theme.primarySolidText : AppStyle.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(selected ? AppStyle.accent : AppStyle.hoverFill))
        }
        .buttonStyle(PressScaleStyle())
    }

    // MARK: - 区间选择

    private var rangePicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                rangeTitleCluster
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                rangeControls(includeRefresh: true)
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    rangeTitleCluster
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    refreshButton
                        .disabled(loading)
                }
                ScrollView(.horizontal) {
                    rangeControls(includeRefresh: false)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .scrollIndicators(.never)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var rangeTitleCluster: some View {
        HStack(spacing: 8) {
            Text(L("Token 用量"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1)
            IconOnlyButton(
                systemName: "rectangle.3.group",
                help: L("打开用量管理"),
                size: 24,
                symbolSize: 10.5,
                tint: AppStyle.textTertiary,
                action: onOpenManagement)
        }
    }

    private func rangeControls(includeRefresh: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach([7, 30, 90], id: \.self) { d in
                daysBackButton(d)
            }
            customDaysField
            if includeRefresh {
                refreshButton
                    .disabled(loading)
            }
        }
    }

    private func daysBackButton(_ d: Int) -> some View {
        Button { setDaysBack(d) } label: {
            Text(L("%ld天", d))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(daysBack == d ? AppStyle.theme.primarySolidText : AppStyle.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(daysBack == d ? AppStyle.accent : AppStyle.hoverFill))
        }
        .buttonStyle(PressScaleStyle())
    }

    private var customDaysField: some View {
        HStack(spacing: 3) {
            TextField("", text: $daysBackText)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppStyle.textSecondary)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .frame(width: 34)
                .onSubmit { applyDaysBackText() }
            Text(L("天"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.hoverFill))
        .help(L("输入 1-365 天"))
    }

    private var refreshButton: some View {
        IconOnlyButton(
            systemName: "arrow.clockwise",
            help: L("刷新用量统计"),
            size: 24,
            symbolSize: 11,
            weight: .bold,
            tint: AppStyle.textSecondary,
            action: reload)
    }

    private func setDaysBack(_ value: Int) {
        daysBack = min(max(value, 1), 365)
        daysBackText = "\(daysBack)"
        selectedDay = nil
        hoveredDay = nil
        reload()
    }

    private func applyDaysBackText() {
        let value = Int(daysBackText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? daysBack
        setDaysBack(value)
    }

    // MARK: - 概览（含今日）

    private func summaryTiles(_ r: UsageReport) -> some View {
        let grand = filteredGrand(r)
        let today = Self.todayString()
        let todayUsage = r.byDay.first { $0.day == today }.map(filteredDay) ?? UsageTotals()
        let activeDays = r.byDay.filter { filteredDay($0).totalTokens > 0 }.count
        let avg = activeDays == 0 ? 0 : grand.costUSD / Double(activeDays)
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                statTile(L("今日成本"), "$" + UsageNumber.money(todayUsage.costUSD),
                         sub: tokenRequestLine(todayUsage), highlight: true)
                statTile(L("%ld天成本", daysBack), "$" + UsageNumber.money(grand.costUSD),
                         sub: L("日均 $%@", UsageNumber.money(avg)))
            }
            HStack(spacing: 10) {
                statTile(L("总 Token"), UsageNumber.compact(grand.totalTokens),
                         sub: requestLine(grand))
                statTile(L("会话数"), "\(filteredSessions(r))",
                         sub: L("活跃 %ld 天", activeDays))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statTile(_ label: String, _ value: String, sub: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(highlight ? AppStyle.accent : AppStyle.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
            Text(sub)
                .font(.system(size: 9.5))
                .foregroundStyle(AppStyle.textTertiary.opacity(0.8))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .toolsCard()
    }

    // MARK: - 每日堆叠柱状（按来源，可点选）

    private func dailyChart(_ r: UsageReport) -> some View {
        let days = filledDays(r)
        let maxCost = max(days.map { filteredDay($0).costUSD }.max() ?? 0, 0.0001)
        let activeDayKey = hoveredDay ?? selectedDay
        let peakDayKey = peakDayKey(days)
        return VStack(alignment: .leading, spacing: 8) {
            dailyChartHeader
            GeometryReader { geo in
                let spacing = chartSpacing(dayCount: days.count)
                let contentWidth = max(geo.size.width, minimumChartContentWidth(dayCount: days.count))
                let barWidth = chartBarWidth(dayCount: days.count, width: contentWidth, spacing: spacing)
                ScrollView(.horizontal) {
                    ZStack(alignment: .bottomLeading) {
                        if let band = selectionBandRect(
                            activeDayKey: activeDayKey,
                            days: days,
                            barWidth: barWidth,
                            spacing: spacing,
                            contentWidth: contentWidth)
                        {
                            Rectangle()
                                .fill(AppStyle.textPrimary.opacity(selectedDay == activeDayKey ? 0.10 : 0.06))
                                .frame(width: band.width, height: band.height)
                                .position(x: band.midX, y: band.midY)
                                .allowsHitTesting(false)
                        }
                        HStack(alignment: .bottom, spacing: spacing) {
                            ForEach(days) { day in
                                dayBar(
                                    day,
                                    maxCost: maxCost,
                                    activeDayKey: activeDayKey,
                                    isPeak: day.day == peakDayKey)
                                    .frame(width: barWidth)
                            }
                        }
                        .frame(width: contentWidth, height: Self.dailyChartHeight, alignment: .bottomLeading)
                        UsageChartMouseLocationReader(
                            onMoved: { location in
                                updateChartHover(
                                    location: location,
                                    days: days,
                                    barWidth: barWidth,
                                    spacing: spacing)
                            },
                            onClicked: { location in
                                toggleChartSelection(
                                    location: location,
                                    days: days,
                                    barWidth: barWidth,
                                    spacing: spacing)
                            })
                            .frame(width: contentWidth, height: Self.dailyChartHeight)
                    }
                    .frame(width: contentWidth, height: Self.dailyChartHeight, alignment: .bottomLeading)
                    .clipped()
                }
                .scrollIndicators(days.count > 90 ? .visible : .hidden)
                .frame(width: geo.size.width, height: Self.dailyChartHeight, alignment: .bottomLeading)
                .clipped()
                .onHover { hovering in
                    if !hovering {
                        hoveredDay = nil
                    }
                }
            }
            .frame(height: Self.dailyChartHeight, alignment: .bottom)
            HStack {
                Text(shortDay(days.first?.day ?? ""))
                Spacer()
                Text(shortDay(days.last?.day ?? ""))
            }
            .font(.system(size: 9))
            .foregroundStyle(AppStyle.textTertiary)

            if let activeDayKey, let day = days.first(where: { $0.day == activeDayKey }) {
                dayDetail(day)
            } else {
                dayDetailPlaceholder()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolsCard()
    }

    private var dailyChartHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                dailyChartTitle
                dailyChartLegend
                Spacer(minLength: 8)
                clearSelectedDayButton
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    dailyChartTitle
                    Spacer(minLength: 8)
                    clearSelectedDayButton
                }
                ScrollView(.horizontal) {
                    dailyChartLegend
                        .fixedSize(horizontal: true, vertical: false)
                }
                .scrollIndicators(.never)
            }
        }
    }

    private var dailyChartTitle: some View {
        Text(L("每日成本"))
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(AppStyle.textSecondary)
            .lineLimit(1)
    }

    private var dailyChartLegend: some View {
        HStack(spacing: 10) {
            if let f = sourceFilter {
                legendDot(Self.color(for: f), f.displayName)
            } else {
                ForEach(UsageSource.allCases, id: \.self) { source in
                    legendDot(Self.color(for: source), source.displayName)
                }
            }
        }
    }

    @ViewBuilder
    private var clearSelectedDayButton: some View {
        if selectedDay != nil {
            Button { selectedDay = nil } label: {
                Text(L("取消选中"))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        }
    }

    private func chartSpacing(dayCount: Int) -> CGFloat {
        if dayCount > 120 { return 0 }
        if dayCount > 45 { return 1 }
        return 2
    }

    private func chartBarWidth(dayCount: Int, width: CGFloat, spacing: CGFloat) -> CGFloat {
        guard dayCount > 0, width > 0 else { return 0 }
        let totalSpacing = spacing * CGFloat(max(dayCount - 1, 0))
        return max(0.6, (width - totalSpacing) / CGFloat(dayCount))
    }

    private func minimumChartContentWidth(dayCount: Int) -> CGFloat {
        if dayCount > 180 { return CGFloat(dayCount) * 2.8 }
        if dayCount > 90 { return CGFloat(dayCount) * 3.4 }
        if dayCount > 45 { return CGFloat(dayCount) * 4.0 }
        return 0
    }

    private func dayBar(_ day: DailyUsage, maxCost: Double, activeDayKey: String?, isPeak: Bool) -> some View {
        let dayTotals = filteredDay(day)
        let scale = Self.dailyBarMaxHeight / maxCost
        let totalHeight = max(dayTotals.costUSD * scale, dayTotals.costUSD > 0 ? 1.5 : 0)
        let isSelected = selectedDay == day.day
        let isHovered = hoveredDay == day.day
        let isActive = activeDayKey == day.day
        let dimmed = activeDayKey != nil && !isActive
        return Button {
            selectedDay = isSelected ? nil : day.day
            hoveredDay = nil
        } label: {
            VStack(spacing: 0) {
                ForEach(UsageSource.allCases, id: \.self) { source in
                    if sourceFilter == nil || sourceFilter == source {
                        let cost = day.bySource[source]?.costUSD ?? 0
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Self.color(for: source))
                            .frame(height: max(cost * scale, cost > 0 ? 1.5 : 0))
                    }
                }
                if dayTotals.costUSD == 0 {
                    Circle()
                        .fill(AppStyle.textTertiary.opacity(0.35))
                        .frame(width: 3, height: 3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(
                        isActive ? AppStyle.textPrimary.opacity(isSelected ? 0.72 : 0.42) : Color.clear,
                        lineWidth: isHovered || isSelected ? 1 : 0)
            }
            .overlay(alignment: .bottom) {
                if isPeak, dayTotals.costUSD > 0 {
                    let capHeight = min(Self.dailyPeakCapHeight, max(2, totalHeight * 0.12))
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(AppStyle.waitAmber)
                            .frame(height: capHeight)
                            .padding(.bottom, max(0, totalHeight - capHeight))
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .opacity(dimmed ? 0.35 : 1)
        .contentShape(Rectangle().inset(by: -4))
        .help(dayTooltip(day))
        .accessibilityLabel(L("成本图日期 %@", day.day))
        .accessibilityValue("$\(UsageNumber.money(dayTotals.costUSD)), \(tokenRequestLine(dayTotals))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func peakDayKey(_ days: [DailyUsage]) -> String? {
        days.max { lhs, rhs in
            filteredDay(lhs).costUSD < filteredDay(rhs).costUSD
        }
        .flatMap { filteredDay($0).costUSD > 0 ? $0.day : nil }
    }

    private func selectionBandRect(
        activeDayKey: String?,
        days: [DailyUsage],
        barWidth: CGFloat,
        spacing: CGFloat,
        contentWidth: CGFloat) -> CGRect?
    {
        guard let activeDayKey,
              let index = days.firstIndex(where: { $0.day == activeDayKey }) else { return nil }
        let step = barWidth + spacing
        let center = CGFloat(index) * step + barWidth / 2
        let previousCenter = index > 0 ? CGFloat(index - 1) * step + barWidth / 2 : nil
        let nextCenter = index + 1 < days.count ? CGFloat(index + 1) * step + barWidth / 2 : nil

        let rawLeft = previousCenter.map { ($0 + center) / 2 } ?? center - max(barWidth / 2, 4)
        let rawRight = nextCenter.map { ($0 + center) / 2 } ?? center + max(barWidth / 2, 4)
        let left = min(max(0, rawLeft), contentWidth)
        let right = min(max(0, rawRight), contentWidth)
        return CGRect(
            x: min(left, right),
            y: 0,
            width: max(1, abs(right - left)),
            height: Self.dailyChartHeight)
    }

    private func updateChartHover(
        location: CGPoint?,
        days: [DailyUsage],
        barWidth: CGFloat,
        spacing: CGFloat)
    {
        guard let key = nearestDayKey(location: location, days: days, barWidth: barWidth, spacing: spacing) else {
            if hoveredDay != nil { hoveredDay = nil }
            return
        }
        if hoveredDay != key { hoveredDay = key }
    }

    private func toggleChartSelection(
        location: CGPoint,
        days: [DailyUsage],
        barWidth: CGFloat,
        spacing: CGFloat)
    {
        guard let key = nearestDayKey(location: location, days: days, barWidth: barWidth, spacing: spacing) else {
            return
        }
        selectedDay = selectedDay == key ? nil : key
        hoveredDay = key
    }

    private func nearestDayKey(
        location: CGPoint?,
        days: [DailyUsage],
        barWidth: CGFloat,
        spacing: CGFloat) -> String?
    {
        guard let location, !days.isEmpty else { return nil }
        let step = max(barWidth + spacing, 0.1)
        let firstCenter = barWidth / 2
        let rawIndex = ((location.x - firstCenter) / step).rounded()
        let index = min(max(Int(rawIndex), 0), days.count - 1)
        return days[index].day
    }

    private func dayDetail(_ day: DailyUsage) -> some View {
        let total = filteredDay(day)
        let models = Array(filteredModelBreakdowns(day).prefix(8))
        let detailSources = UsageSource.allCases.filter { sourceFilter == nil || sourceFilter == $0 }
        return VStack(alignment: .leading, spacing: 4) {
            Text(day.day)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(AppStyle.textPrimary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 68), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 6)
            {
                detailItem(L("合计"), "$" + UsageNumber.money(total.costUSD),
                           tokenRequestLine(total))
                ForEach(detailSources, id: \.self) { source in
                    let totals = day.bySource[source] ?? UsageTotals()
                    detailItem(source.displayName, "$" + UsageNumber.money(totals.costUSD),
                               tokenRequestLine(totals), color: Self.color(for: source))
                }
            }
            if !models.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("模型"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textTertiary)
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(models, id: \.id) { model in
                                dayModelRow(model)
                            }
                        }
                    }
                    .scrollIndicators(models.count > 4 ? .visible : .hidden)
                    .frame(height: Self.dayDetailModelViewportHeight, alignment: .topLeading)
                }
                .padding(.top, 3)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.dayDetailHeight, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.hoverFill))
    }

    private func dayDetailPlaceholder() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("悬停或点击柱子查看每日明细"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
            Text(L("成本、Token、请求和 Top 模型会显示在这里"))
                .font(.system(size: 9.5))
                .foregroundStyle(AppStyle.textTertiary.opacity(0.82))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: Self.dayDetailHeight, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.hoverFill.opacity(0.62)))
    }

    private func dayModelRow(_ model: UsageModelBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    dayModelTitle(model)
                    Spacer(minLength: 8)
                    Text("$" + UsageNumber.money(model.totals.costUSD))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppStyle.textPrimary)
                    Text(tokenRequestLine(model.totals))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        dayModelTitle(model)
                        Spacer(minLength: 8)
                        Text("$" + UsageNumber.money(model.totals.costUSD))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppStyle.textPrimary)
                    }
                    Text(tokenRequestLine(model.totals))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
            }
            if let subtitle = modelModeSubtitle(model) {
                Text(subtitle)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 11)
            }
        }
        .frame(height: modelModeSubtitle(model) == nil ? 20 : 32, alignment: .topLeading)
    }

    private func dayModelTitle(_ model: UsageModelBreakdown) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Self.color(for: model.source))
                .frame(width: 5, height: 5)
            Text(model.model)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .layoutPriority(1)
    }

    private func dayTooltip(_ day: DailyUsage) -> String {
        let totals = filteredDay(day)
        var lines = [
            "\(day.day) · $\(UsageNumber.money(totals.costUSD)) · \(tokenRequestLine(totals))",
        ]
        let models = filteredModelBreakdowns(day).prefix(3)
        for model in models {
            lines.append("\(model.model) · $\(UsageNumber.money(model.totals.costUSD)) · \(tokenRequestLine(model.totals))")
        }
        return lines.joined(separator: "\n")
    }

    private func filteredModelBreakdowns(_ day: DailyUsage) -> [UsageModelBreakdown] {
        day.modelBreakdowns.filter { model in
            sourceFilter == nil || sourceFilter == model.source
        }
    }

    private func modelModeSubtitle(_ model: UsageModelBreakdown) -> String? {
        var parts: [String] = []
        if let label = ModelPricing.codexDisplayLabel(model.model) {
            parts.append(label)
        }
        if let cost = model.standardCostUSD {
            var text = "\(L("标准")) $" + UsageNumber.money(cost)
            if let tokens = model.standardTokens {
                text += " · \(UsageNumber.compact(tokens)) tok"
            }
            parts.append(text)
        }
        if let cost = model.priorityCostUSD {
            var text = "Fast $" + UsageNumber.money(cost)
            if let tokens = model.priorityTokens {
                text += " · \(UsageNumber.compact(tokens)) tok"
            }
            parts.append(text)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    private func detailItem(_ label: String, _ value: String, _ sub: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if let color { Circle().fill(color).frame(width: 6, height: 6) }
                Text(label).font(.system(size: 9.5, weight: .medium)).foregroundStyle(AppStyle.textTertiary)
            }
            Text(value).font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundStyle(AppStyle.textPrimary)
            Text(sub).font(.system(size: 9)).foregroundStyle(AppStyle.textTertiary)
        }
    }

    private func tokenRequestLine(_ totals: UsageTotals) -> String {
        guard totals.requestCount > 0 else {
            return UsageNumber.compact(totals.totalTokens) + " tok"
        }
        return L("%1$@ tok · %2$@ 请求",
                 UsageNumber.compact(totals.totalTokens),
                 UsageNumber.compact(totals.requestCount))
    }

    private func requestLine(_ totals: UsageTotals) -> String {
        guard totals.requestCount > 0 else {
            return L("输出 %@", UsageNumber.compact(totals.outputTokens))
        }
        return L("请求 %@", UsageNumber.compact(totals.requestCount))
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 9.5)).foregroundStyle(AppStyle.textTertiary)
        }
    }

    /// 把日期序列补满（无数据的天补 0），柱状图才有正确的时间轴。
    private func filledDays(_ r: UsageReport) -> [DailyUsage] {
        guard let first = r.byDay.first?.day, let last = r.byDay.last?.day,
              let start = Self.parseDay(first), let end = Self.parseDay(last) else { return r.byDay }
        let known = Dictionary(uniqueKeysWithValues: r.byDay.map { ($0.day, $0) })
        var out: [DailyUsage] = []
        var cur = start
        let cal = Calendar.current
        while cur <= end {
            let key = Self.dayString(cur)
            out.append(known[key] ?? DailyUsage(day: key, totals: UsageTotals(), bySource: [:]))
            guard let next = cal.date(byAdding: .day, value: 1, to: cur) else { break }
            cur = next
        }
        return out
    }

    // MARK: - 月度摘要

    private func filteredMonthRows(_ r: UsageReport) -> [(month: MonthlyUsage, totals: UsageTotals)] {
        r.monthSummaries
            .compactMap { month -> (month: MonthlyUsage, totals: UsageTotals)? in
                let totals = filteredMonth(month)
                return totals.totalTokens > 0 || totals.costUSD > 0 ? (month, totals) : nil
            }
            .suffix(12)
            .map { $0 }
    }

    private func monthSection(_ r: UsageReport) -> some View {
        let filtered = filteredMonthRows(r)
        let maxCost = max(filtered.map { $0.totals.costUSD }.max() ?? 0, 0.0001)
        return Group {
            if !filtered.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ToolsSectionLabel(L("按月份"))
                    ForEach(filtered, id: \.month.id) { item in
                        monthRow(item.month, totals: item.totals, maxCost: maxCost)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func filteredMonth(_ month: MonthlyUsage) -> UsageTotals {
        sourceFilter.flatMap { month.bySource[$0] ?? UsageTotals() } ?? month.totals
    }

    private func monthRow(_ month: MonthlyUsage, totals: UsageTotals, maxCost: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    monthTitle(month.month)
                    Spacer(minLength: 4)
                    trailingMetric(tokenRequestLine(totals))
                    costMetric(totals.costUSD, fontSize: 11)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        monthTitle(month.month)
                        Spacer(minLength: 4)
                        costMetric(totals.costUSD, fontSize: 11)
                    }
                    trailingMetric(tokenRequestLine(totals))
                }
            }
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(UsageSource.allCases, id: \.self) { src in
                        if sourceFilter == nil || sourceFilter == src {
                            let cost = sourceFilter == nil
                                ? (month.bySource[src]?.costUSD ?? 0) : totals.costUSD
                            Rectangle()
                                .fill(Self.color(for: src).opacity(0.75))
                                .frame(width: max(geo.size.width * CGFloat(cost / maxCost), cost > 0 ? 2 : 0))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.hoverFill.opacity(0.5)))
    }

    // MARK: - 会话摘要

    private func filteredSessionRows(_ r: UsageReport) -> [SessionUsage] {
        r.bySession
            .filter { sourceFilter == nil || $0.source == sourceFilter }
            .filter { $0.totals.totalTokens > 0 || $0.totals.costUSD > 0 }
            .prefix(8)
            .map { $0 }
    }

    private func sessionSection(_ r: UsageReport) -> some View {
        let items = filteredSessionRows(r)
        let maxCost = max(items.map { $0.totals.costUSD }.max() ?? 0, 0.0001)
        return Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ToolsSectionLabel(L("按会话"))
                    ForEach(items, id: \.id) { session in
                        sessionRow(session, maxCost: maxCost)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sessionRow(_ session: SessionUsage, maxCost: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    sessionTitle(session)
                    Spacer(minLength: 4)
                    if let last = session.lastActivity {
                        trailingMetric(last, monospaced: true)
                    }
                    costMetric(session.totals.costUSD, fontSize: 11)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        sessionTitle(session)
                        Spacer(minLength: 4)
                        costMetric(session.totals.costUSD, fontSize: 11)
                    }
                    if let last = session.lastActivity {
                        trailingMetric(last, monospaced: true)
                    }
                }
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.color(for: session.source).opacity(0.72))
                    .frame(width: max(geo.size.width * CGFloat(session.totals.costUSD / maxCost), 2))
            }
            .frame(height: 4)
            HStack(spacing: 8) {
                Text(session.project.isEmpty ? L("未知项目") : Self.shortPath(session.project))
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                Text(tokenRequestLine(session.totals))
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.hoverFill.opacity(0.5)))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Token 构成

    private func tokenComposition(_ r: UsageReport) -> some View {
        let g = filteredGrand(r)
        let parts: [(String, Int, Color)] = [
            (L("输入"), g.inputTokens, .blue),
            (L("输出"), g.outputTokens, .purple),
            (L("缓存写"), g.cacheCreationTokens, .teal),
            (L("缓存读"), g.cacheReadTokens, AppStyle.textTertiary.opacity(0.55)),
        ]
        let total = max(g.totalTokens, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("Token 构成"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(AppStyle.textSecondary)
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(parts, id: \.0) { part in
                        Rectangle()
                            .fill(part.2)
                            .frame(width: max(geo.size.width * CGFloat(part.1) / CGFloat(total), part.1 > 0 ? 2 : 0))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .frame(height: 10)
            HStack(spacing: 10) {
                ForEach(parts, id: \.0) { part in
                    HStack(spacing: 3) {
                        Circle().fill(part.2).frame(width: 6, height: 6)
                        Text("\(part.0) \(UsageNumber.compact(part.1))")
                            .font(.system(size: 9.5))
                            .foregroundStyle(AppStyle.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolsCard()
    }

    // MARK: - 按来源

    private func sourceBreakdown(_ r: UsageReport) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 154), spacing: 10, alignment: .top)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(UsageSource.allCases, id: \.self) { src in
                let t = r.bySource[src] ?? UsageTotals()
                let share = r.grand.costUSD > 0 ? t.costUSD / r.grand.costUSD : 0
                Button {
                    sourceFilter = src
                    selectedDay = nil
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Circle().fill(Self.color(for: src))
                                .frame(width: 7, height: 7)
                            Text(src.displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppStyle.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.0f%%", share * 100))
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(AppStyle.textTertiary)
                        }
                        Text("$" + UsageNumber.money(t.costUSD))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppStyle.accent)
                        Text(L("%1$@ tok · %2$@ 请求 · %3$ld 会话",
                               UsageNumber.compact(t.totalTokens),
                               UsageNumber.compact(t.requestCount),
                               r.sessionsBySource[src] ?? 0))
                            .font(.system(size: 10))
                            .foregroundStyle(AppStyle.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11).padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(AppStyle.hoverFill))
                    .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(PressScaleStyle())
                .help(L("只看 %@", src.displayName))
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 按项目

    private func filteredProjectRows(_ r: UsageReport) -> [(project: ProjectUsage, totals: UsageTotals)] {
        // 过滤后取该 CLI 在各项目的份额，重新排序，藏掉为 0 的。
        r.byProject
            .filter { !$0.path.isEmpty }
            .compactMap { p in
                let t = sourceFilter.flatMap { p.bySource[$0] } ?? p.totals
                return t.totalTokens > 0 ? (p, t) : nil
            }
            .sorted { $0.totals.costUSD > $1.totals.costUSD }
            .prefix(8)
            .map { $0 }
    }

    private func projectSection(_ r: UsageReport) -> some View {
        let items = filteredProjectRows(r)
        let maxCost = max(items.map { $0.totals.costUSD }.max() ?? 0, 0.0001)
        return Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ToolsSectionLabel(L("按项目"))
                    ForEach(items, id: \.project.id) { item in
                        projectRow(item.project, totals: item.totals, maxCost: maxCost)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func projectRow(_ p: ProjectUsage, totals: UsageTotals, maxCost: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    projectTitle(p.path)
                    Spacer(minLength: 4)
                    trailingMetric(UsageNumber.compact(totals.totalTokens) + " tok")
                    costMetric(totals.costUSD, fontSize: 11)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        projectTitle(p.path)
                        Spacer(minLength: 4)
                        costMetric(totals.costUSD, fontSize: 11)
                    }
                    trailingMetric(UsageNumber.compact(totals.totalTokens) + " tok")
                }
            }
            // 占比条：全部视图按来源双色堆叠；过滤后单色。
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(UsageSource.allCases, id: \.self) { src in
                        if sourceFilter == nil || sourceFilter == src {
                            let cost = sourceFilter == nil
                                ? (p.bySource[src]?.costUSD ?? 0) : totals.costUSD
                            Rectangle()
                                .fill(Self.color(for: src).opacity(0.75))
                                .frame(width: max(geo.size.width * CGFloat(cost / maxCost), cost > 0 ? 2 : 0))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.hoverFill.opacity(0.5)))
    }

    // MARK: - 按模型

    private func filteredModelRows(_ r: UsageReport) -> [ModelUsage] {
        sourceFilter.map { f in r.byModel.filter { $0.source == f } } ?? r.byModel
    }

    private func modelTable(_ r: UsageReport) -> some View {
        let models = filteredModelRows(r)
        let grandCost = filteredGrand(r).costUSD
        let maxCost = max(models.map { $0.totals.costUSD }.max() ?? 0, 0.0001)
        return VStack(alignment: .leading, spacing: 6) {
            ToolsSectionLabel(L("按模型"))
            ForEach(models) { m in
                VStack(alignment: .leading, spacing: 3) {
                    let percent = String(format: "%.0f%%", grandCost > 0 ? m.totals.costUSD / grandCost * 100 : 0)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            modelTitle(m.model, source: m.source)
                            Spacer(minLength: 4)
                            trailingMetric(percent)
                            costMetric(m.totals.costUSD, fontSize: 11.5)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                modelTitle(m.model, source: m.source)
                                Spacer(minLength: 4)
                                costMetric(m.totals.costUSD, fontSize: 11.5)
                            }
                            trailingMetric(percent)
                        }
                    }
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Self.color(for: m.source).opacity(0.7))
                            .frame(width: max(geo.size.width * CGFloat(m.totals.costUSD / maxCost), 2))
                    }
                    .frame(height: 4)
                    Text(L("输入 %@ · 输出 %@ · 缓存 %@ · 请求 %@",
                           UsageNumber.compact(m.totals.inputTokens),
                           UsageNumber.compact(m.totals.outputTokens),
                           UsageNumber.compact(m.totals.cacheReadTokens + m.totals.cacheCreationTokens),
                           UsageNumber.compact(m.totals.requestCount)))
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.hoverFill.opacity(0.5)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func monthTitle(_ month: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 9.5))
                .foregroundStyle(AppStyle.textTertiary)
            Text(Self.monthLabel(month))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .frame(minWidth: 0, alignment: .leading)
    }

    private func sessionTitle(_ session: SessionUsage) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Self.color(for: session.source))
                .frame(width: 7, height: 7)
            Text(Self.shortSession(session.session))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
        }
        .frame(minWidth: 0, alignment: .leading)
    }

    private func projectTitle(_ path: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 9.5))
                .foregroundStyle(AppStyle.textTertiary)
            Text(Self.shortPath(path))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1)
                .truncationMode(.head)
                .layoutPriority(1)
                .help(path)
        }
        .frame(minWidth: 0, alignment: .leading)
    }

    private func modelTitle(_ model: String, source: UsageSource) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Self.color(for: source))
                .frame(width: 7, height: 7)
            Text(model)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
        }
        .frame(minWidth: 0, alignment: .leading)
    }

    private func trailingMetric(_ text: String, monospaced: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium, design: monospaced ? .monospaced : .default))
            .foregroundStyle(AppStyle.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func costMetric(_ cost: Double, fontSize: CGFloat) -> some View {
        Text("$" + UsageNumber.money(cost))
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(AppStyle.textPrimary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minWidth: 48, alignment: .trailing)
    }

    private func footnote(_ r: UsageReport) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(loading ? L("更新中…") : L("更新于 %@", UsageRelative.text(r.generatedAt)))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
            if let sourceInfo = r.sourceInfo {
                Text(Self.sourceInfoText(sourceInfo))
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(L("成本按公开价目表估算，第三方代理/订阅实际计费可能不同。数据来自本机会话记录。"))
                .font(.system(size: 9.5))
                .foregroundStyle(AppStyle.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L("正在读取本机会话…")).font(.system(size: 12)).foregroundStyle(AppStyle.textSecondary)
            Spacer()
        }.padding(.vertical, 20)
    }

    private var emptyRow: some View {
        ToolEmptyState(
            icon: "chart.bar.xaxis",
            title: L("没有找到用量数据"),
            compact: true)
        .padding(.top, 8)
    }

    // MARK: - 加载

    private func reload() {
        let days = daysBack
        // 先显示缓存（秒开），再后台重扫更新。
        if let cached = UsageReportStore.load(daysBack: days) {
            report = cached
        } else {
            report = nil
        }
        loading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> UsageReport in
                await CostUsageFetcher().loadReportOrFallback(daysBack: days)
            }.value
            UsageReportStore.save(result, daysBack: days)
            await MainActor.run {
                if daysBack == days {
                    report = result
                    loading = false
                }
            }
        }
    }

    // MARK: - 日期工具

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func todayString() -> String { dayFormatter.string(from: Date()) }
    static func dayString(_ d: Date) -> String { dayFormatter.string(from: d) }
    static func parseDay(_ s: String) -> Date? { dayFormatter.date(from: s) }
    static func monthLabel(_ month: String) -> String { month }
    static func shortSession(_ session: String) -> String {
        guard session.count > 24 else { return session }
        return String(session.prefix(10)) + "…" + String(session.suffix(10))
    }

    static func sourceInfoText(_ info: UsageReportSourceInfo) -> String {
        var label = L("来源：%@", sourceLabel(info.source))
        if let age = info.cacheAgeSeconds {
            label += L(" · 缓存 %@", durationLabel(age))
        }
        return label
    }

    static func sourceLabel(_ source: UsageReportSource) -> String {
        switch source {
        case .directScan: return L("重新扫描")
        case .fileCacheScan: return L("文件缓存扫描")
        case .reportCache: return L("成本缓存")
        case .uiCache: return L("面板缓存")
        case .fallbackScan: return L("降级扫描")
        }
    }

    static func durationLabel(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        if value >= 86_400 { return L("%ld天", value / 86_400) }
        if value >= 3_600 { return L("%ld小时", value / 3_600) }
        if value >= 60 { return L("%ld分钟", value / 60) }
        return L("%ld秒", value)
    }

    /// 把绝对路径缩短为 `~/…/last/two`。
    static func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var p = path
        if p.hasPrefix(home) { p = "~" + p.dropFirst(home.count) }
        let parts = p.split(separator: "/")
        if parts.count > 3 {
            return (p.hasPrefix("~") ? "~/…/" : "/…/") + parts.suffix(2).joined(separator: "/")
        }
        return p
    }

    private func shortDay(_ day: String) -> String {
        day.count == 10 ? String(day.dropFirst(5)) : day   // MM-dd
    }
}

@MainActor
private struct UsageChartMouseLocationReader: NSViewRepresentable {
    let onMoved: (CGPoint?) -> Void
    let onClicked: (CGPoint) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMoved = onMoved
        view.onClicked = onClicked
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onMoved = onMoved
        nsView.onClicked = onClicked
    }

    final class TrackingView: NSView {
        var onMoved: ((CGPoint?) -> Void)?
        var onClicked: ((CGPoint) -> Void)?
        private var trackingArea: NSTrackingArea?

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
            updateTrackingAreas()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                owner: self,
                userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            onMoved?(convert(event.locationInWindow, from: nil))
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            onMoved?(convert(event.locationInWindow, from: nil))
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            onMoved?(nil)
        }

        override func mouseDown(with event: NSEvent) {
            onClicked?(convert(event.locationInWindow, from: nil))
        }

        override func scrollWheel(with event: NSEvent) {
            nextResponder?.scrollWheel(with: event)
        }
    }
}

/// 数字格式化（紧凑 token 数 + 金额）。
enum UsageNumber {
    static func compact(_ n: Int) -> String {
        let v = Double(n)
        if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.2fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fK", v / 1_000) }
        return "\(n)"
    }

    static func money(_ v: Double) -> String {
        if v >= 100 { return String(format: "%.0f", v) }
        if v >= 1 { return String(format: "%.2f", v) }
        return String(format: "%.3f", v)
    }
}

enum UsageRelative {
    static func text(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return L("刚刚") }
        if s < 3600 { return L("%ld 分钟前", s / 60) }
        if s < 86400 { return L("%ld 小时前", s / 3600) }
        return L("%ld 天前", s / 86400)
    }
}
