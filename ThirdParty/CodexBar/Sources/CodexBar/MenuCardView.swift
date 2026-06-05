import AppKit
import CodexBarCore
import SwiftUI

/// SwiftUI card used inside the NSMenu to mirror Apple's rich menu panels.
struct UsageMenuCardView: View {
    struct Model {
        enum PercentStyle: String {
            case left
            case used

            var labelSuffix: String {
                switch self {
                case .left: "left"
                case .used: "used"
                }
            }

            var accessibilityLabel: String {
                switch self {
                case .left: codexBarLocalizedDisplayText("Usage remaining")
                case .used: codexBarLocalizedDisplayText("Usage used")
                }
            }
        }

        struct Metric: Identifiable {
            let id: String
            let title: String
            let percent: Double
            let percentStyle: PercentStyle
            let statusText: String?
            let resetText: String?
            let detailText: String?
            let detailLeftText: String?
            let detailRightText: String?
            let pacePercent: Double?
            let paceOnTop: Bool
            let warningMarkerPercents: [Double]
            let cardStyle: Bool

            init(
                id: String,
                title: String,
                percent: Double,
                percentStyle: PercentStyle,
                statusText: String? = nil,
                resetText: String?,
                detailText: String?,
                detailLeftText: String?,
                detailRightText: String?,
                pacePercent: Double?,
                paceOnTop: Bool,
                warningMarkerPercents: [Double] = [],
                cardStyle: Bool = false)
            {
                self.id = id
                self.title = title
                self.percent = percent
                self.percentStyle = percentStyle
                self.statusText = statusText
                self.resetText = resetText
                self.detailText = detailText
                self.detailLeftText = detailLeftText
                self.detailRightText = detailRightText
                self.pacePercent = pacePercent
                self.paceOnTop = paceOnTop
                self.warningMarkerPercents = warningMarkerPercents
                self.cardStyle = cardStyle
            }

            var percentLabel: String {
                codexBarLocalizedDisplayText(String(format: "%.0f%% %@", self.percent, self.percentStyle.labelSuffix))
            }
        }

        enum SubtitleStyle {
            case info
            case loading
            case error
        }

        struct TokenUsageSection {
            let sessionLine: String
            let monthLine: String
            let hintLine: String?
            let errorLine: String?
            let errorCopyText: String?
        }

        struct ProviderCostSection {
            let title: String
            let percentUsed: Double?
            let spendLine: String
            let percentLine: String?
        }

        let provider: UsageProvider
        let providerName: String
        let email: String
        let subtitleText: String
        let subtitleStyle: SubtitleStyle
        let planText: String?
        let metrics: [Metric]
        let usageNotes: [String]
        let openAIAPIUsage: OpenAIAPIUsageSnapshot?
        let inlineUsageDashboard: InlineUsageDashboardModel?
        let creditsText: String?
        let creditsRemaining: Double?
        let creditsHintText: String?
        let creditsHintCopyText: String?
        let providerCost: ProviderCostSection?
        let tokenUsage: TokenUsageSection?
        let placeholder: String?
        let progressColor: Color
    }

    let model: Model
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    static func popupMetricTitle(provider: UsageProvider, metric: Model.Metric) -> String {
        if provider == .openrouter, metric.id == "primary" {
            return "API key limit"
        }
        return metric.title
    }

    @ViewBuilder
    var body: some View {
        if let style = ConductorUsageMenuStyle.current {
            ConductorUsageMenuCardView(
                model: self.model,
                width: self.width,
                style: style,
                isHighlighted: self.isHighlighted)
        } else {
            self.defaultBody
        }
    }

    private var defaultBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            UsageMenuCardHeaderView(model: self.model)

            if self.hasDetails {
                Divider()
            }

            if self.model.metrics.isEmpty {
                if let dashboard = self.model.inlineUsageDashboard {
                    InlineUsageDashboardContent(model: dashboard)
                } else if !self.model.usageNotes.isEmpty {
                    UsageNotesContent(notes: self.model.usageNotes)
                } else if let placeholder = self.model.placeholder {
                    Text(codexBarLocalizedDisplayText(placeholder))
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .font(.subheadline)
                }
            } else {
                let hasUsage = self.model.hasUsageContent
                let hasCredits = self.model.creditsText != nil
                let hasProviderCost = self.model.providerCost != nil
                let hasCost = self.model.tokenUsage != nil || hasProviderCost

                VStack(alignment: .leading, spacing: 12) {
                    if hasUsage {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(self.model.metrics, id: \.id) { metric in
                                MetricRow(
                                    metric: metric,
                                    title: Self.popupMetricTitle(provider: self.model.provider, metric: metric),
                                    progressColor: self.model.progressColor)
                            }
                            if let dashboard = self.model.inlineUsageDashboard {
                                InlineUsageDashboardContent(model: dashboard)
                            } else if !self.model.usageNotes.isEmpty {
                                UsageNotesContent(notes: self.model.usageNotes)
                            }
                        }
                    }
                    if hasUsage, hasCredits || hasCost {
                        Divider()
                    }
                    if let credits = self.model.creditsText {
                        CreditsBarContent(
                            creditsText: credits,
                            creditsRemaining: self.model.creditsRemaining,
                            hintText: self.model.creditsHintText,
                            hintCopyText: self.model.creditsHintCopyText,
                            progressColor: self.model.progressColor)
                    }
                    if hasCredits, hasCost {
                        Divider()
                    }
                    if let providerCost = self.model.providerCost {
                        ProviderCostContent(
                            section: providerCost,
                            progressColor: self.model.progressColor)
                    }
                    if hasProviderCost, self.model.tokenUsage != nil {
                        Divider()
                    }
                    if let tokenUsage = self.model.tokenUsage {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("cost_header_estimated"))
                                .font(.body)
                                .fontWeight(.medium)
                            Text(codexBarLocalizedDisplayText(tokenUsage.sessionLine))
                                .font(.footnote)
                            Text(codexBarLocalizedDisplayText(tokenUsage.monthLine))
                                .font(.footnote)
                            if let hint = tokenUsage.hintLine, !hint.isEmpty {
                                Text(codexBarLocalizedDisplayText(hint))
                                    .font(.footnote)
                                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                                    .lineLimit(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let error = tokenUsage.errorLine, !error.isEmpty {
                                Text(codexBarLocalizedDisplayText(error))
                                    .font(.footnote)
                                    .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
                                    .lineLimit(4)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .overlay {
                                        ClickToCopyOverlay(copyText: tokenUsage.errorCopyText ?? error)
                                    }
                            }
                        }
                    }
                }
                .padding(.bottom, self.model.creditsText == nil ? 6 : 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 2)
        .frame(width: self.width, alignment: .leading)
    }

    private var hasDetails: Bool {
        self.model.hasUsageContent ||
            self.model.tokenUsage != nil ||
            self.model.providerCost != nil
    }
}

private struct ConductorUsageMenuCardView: View {
    let model: UsageMenuCardView.Model
    let width: CGFloat
    let style: ConductorUsagePanelStyle
    let isHighlighted: Bool

    private var detailBlocks: [ConductorUsageDetailBlock] {
        var blocks: [ConductorUsageDetailBlock] = []
        if let credits = model.creditsText {
            blocks.append(.init(
                title: L("Credits"),
                value: credits,
                detail: model.creditsHintText,
                percent: model.creditsRemaining.map { min(100, max(0, ($0 / 1000) * 100)) },
                icon: "creditcard"))
        }
        if let providerCost = model.providerCost {
            blocks.append(.init(
                title: providerCost.title,
                value: providerCost.spendLine,
                detail: providerCost.percentLine,
                percent: providerCost.percentUsed,
                icon: "chart.line.uptrend.xyaxis"))
        }
        if let tokenUsage = model.tokenUsage {
            blocks.append(.init(
                title: L("cost_header_estimated"),
                value: tokenUsage.sessionLine,
                detail: tokenUsage.monthLine,
                percent: nil,
                icon: "number"))
        }
        return blocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !model.metrics.isEmpty {
                VStack(spacing: 8) {
                    ForEach(model.metrics, id: \.id) { metric in
                        ConductorUsageMetricTile(
                            metric: metric,
                            title: UsageMenuCardView.popupMetricTitle(provider: model.provider, metric: metric),
                            progressColor: model.progressColor,
                            style: style,
                            isHighlighted: isHighlighted)
                    }
                }
            } else if let dashboard = model.inlineUsageDashboard {
                InlineUsageDashboardContent(model: dashboard)
                    .padding(10)
                    .background(detailSurface)
            } else if !model.usageNotes.isEmpty {
                UsageNotesContent(notes: model.usageNotes)
                    .padding(10)
                    .background(detailSurface)
            } else if let placeholder = model.placeholder {
                Text(codexBarLocalizedDisplayText(placeholder))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(style.secondaryText)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(detailSurface)
            }

            if !detailBlocks.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8)
                {
                    ForEach(detailBlocks) { block in
                        ConductorUsageDetailTile(
                            block: block,
                            progressColor: model.progressColor,
                            style: style)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: width, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(style.controlStrongFill.opacity(style.usesDarkChrome ? 0.34 : 0.48))
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(style.secondaryText)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.providerName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(style.primaryText)
                        .lineLimit(1)
                    if let plan = model.planText {
                        Text(codexBarLocalizedDisplayText(plan))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(style.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(style.controlStrongFill.opacity(style.usesDarkChrome ? 0.20 : 0.30))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }

                Text(codexBarLocalizedDisplayText(model.subtitleText))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(model.subtitleStyle == .error ? 3 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            if !model.email.isEmpty {
                Text(model.email)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(style.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 118, alignment: .trailing)
            }
        }
    }

    private var subtitleColor: Color {
        switch model.subtitleStyle {
        case .error:
            Color(nsColor: .systemRed)
        case .loading:
            style.secondaryText
        case .info:
            style.secondaryText
        }
    }

    private var detailSurface: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(style.controlFill.opacity(style.usesDarkChrome ? 0.22 : 0.30))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(style.stroke.opacity(0.14), lineWidth: 0.7)
            }
    }
}

private struct ConductorUsageMetricTile: View {
    let metric: UsageMenuCardView.Model.Metric
    let title: String
    let progressColor: Color
    let style: ConductorUsagePanelStyle
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(codexBarLocalizedDisplayText(title))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(style.primaryText)
                    .lineLimit(1)
                Spacer()
                if let resetText = metric.resetText {
                    Text(codexBarLocalizedDisplayText(resetText))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(style.tertiaryText)
                        .lineLimit(1)
                }
            }

            if let statusText = metric.statusText {
                Text(codexBarLocalizedDisplayText(statusText))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)
            } else {
                ConductorUsageMiniProgress(
                    percent: metric.percent,
                    pacePercent: metric.pacePercent,
                    warningMarkerPercents: metric.warningMarkerPercents,
                    tint: isHighlighted ? style.emphasis : progressColor,
                    style: style)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(metric.percentLabel)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(style.primaryText)
                    Spacer()
                    if let detailRight = metric.detailRightText {
                        Text(codexBarLocalizedDisplayText(detailRight))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(style.tertiaryText)
                            .lineLimit(1)
                    } else if let detail = metric.detailText {
                        Text(codexBarLocalizedDisplayText(detail))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(style.tertiaryText)
                            .lineLimit(1)
                    }
                }
                if let detailLeft = metric.detailLeftText {
                    Text(codexBarLocalizedDisplayText(detailLeft))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(style.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(9)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(style.controlFill.opacity(style.usesDarkChrome ? 0.18 : 0.26))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(style.stroke.opacity(0.14), lineWidth: 0.7)
        }
    }
}

private struct ConductorUsageDetailBlock: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String?
    let percent: Double?
    let icon: String
}

private struct ConductorUsageDetailTile: View {
    let block: ConductorUsageDetailBlock
    let progressColor: Color
    let style: ConductorUsagePanelStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: block.icon)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(style.emphasis)
                    .frame(width: 12)
                Text(codexBarLocalizedDisplayText(block.title))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)
            }
            Text(codexBarLocalizedDisplayText(block.value))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(style.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let percent = block.percent {
                ConductorUsageMiniProgress(percent: percent, tint: progressColor, style: style)
                    .frame(height: 4)
            }
            if let detail = block.detail, !detail.isEmpty {
                Text(codexBarLocalizedDisplayText(detail))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(style.tertiaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(style.controlStrongFill.opacity(style.usesDarkChrome ? 0.15 : 0.24))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(style.stroke.opacity(0.12), lineWidth: 0.7)
        }
    }
}

private struct ConductorUsageMiniProgress: View {
    let percent: Double
    var pacePercent: Double?
    var warningMarkerPercents: [Double]
    let tint: Color
    let style: ConductorUsagePanelStyle

    init(
        percent: Double,
        pacePercent: Double? = nil,
        warningMarkerPercents: [Double] = [],
        tint: Color,
        style: ConductorUsagePanelStyle)
    {
        self.percent = percent
        self.pacePercent = pacePercent
        self.warningMarkerPercents = warningMarkerPercents
        self.tint = tint
        self.style = style
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(style.controlStrongFill.opacity(style.usesDarkChrome ? 0.54 : 0.64))
                Capsule()
                    .fill(tint.opacity(style.usesDarkChrome ? 0.78 : 0.68))
                    .frame(width: width * clamped(percent) / 100)
                ForEach(Array(warningMarkerPercents.enumerated()), id: \.offset) { _, marker in
                    Rectangle()
                        .fill(style.primaryText.opacity(0.62))
                        .frame(width: 1, height: height)
                        .offset(x: max(0, min(width - 1, width * clamped(marker) / 100)))
                }
                if let pacePercent {
                    Circle()
                        .fill(style.primaryText.opacity(0.85))
                        .frame(width: 5, height: 5)
                        .offset(x: max(0, min(width - 5, width * clamped(pacePercent) / 100 - 2.5)))
                }
            }
        }
        .frame(height: 6)
    }

    private func clamped(_ value: Double) -> CGFloat {
        CGFloat(min(100, max(0, value)))
    }
}

private struct ConductorUsageMenuCircuitOverlay: View {
    let style: ConductorUsagePanelStyle

    var body: some View {
        Canvas { context, size in
            let color = style.emphasis.opacity(style.usesDarkChrome ? 0.22 : 0.20)
            var path = Path()
            path.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.30))
            path.addLine(to: CGPoint(x: size.width * 0.46, y: size.height * 0.30))
            path.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.52))
            path.addLine(to: CGPoint(x: size.width * 0.92, y: size.height * 0.52))
            context.stroke(path, with: .color(color), lineWidth: 1)
            for point in [
                CGPoint(x: size.width * 0.08, y: size.height * 0.30),
                CGPoint(x: size.width * 0.46, y: size.height * 0.30),
                CGPoint(x: size.width * 0.62, y: size.height * 0.52),
                CGPoint(x: size.width * 0.92, y: size.height * 0.52),
            ] {
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
                    with: .color(color))
            }
        }
    }
}

private struct UsageMenuCardHeaderView: View {
    let model: UsageMenuCardView.Model
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(self.model.providerName).font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                Spacer()
                Text(self.model.email).font(.subheadline)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1).truncationMode(.middle)
            }
            let subtitleAlignment: VerticalAlignment = self.model.subtitleStyle == .error ? .top : .firstTextBaseline
            HStack(alignment: subtitleAlignment) {
                Text(codexBarLocalizedDisplayText(self.model.subtitleText))
                    .font(.footnote)
                    .foregroundStyle(self.subtitleColor)
                    .lineLimit(self.model.subtitleStyle == .error ? 4 : 1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .padding(.bottom, self.model.subtitleStyle == .error ? 4 : 0)
                Spacer()
                if self.model.subtitleStyle == .error, !self.model.subtitleText.isEmpty {
                    CopyIconButton(copyText: self.model.subtitleText, isHighlighted: self.isHighlighted)
                }
                if let plan = self.model.planText {
                    Text(codexBarLocalizedDisplayText(plan))
                        .font(.footnote)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }
            }
        }
    }

    private var subtitleColor: Color {
        switch self.model.subtitleStyle {
        case .info: MenuHighlightStyle.secondary(self.isHighlighted)
        case .loading: MenuHighlightStyle.secondary(self.isHighlighted)
        case .error: MenuHighlightStyle.error(self.isHighlighted)
        }
    }
}

private struct CopyIconButton: View {
    let copyText: String
    let isHighlighted: Bool

    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            self.copyToPasteboard()
            ConductorUsageMotion.perform(ConductorUsageMotion.press) {
                self.didCopy = true
            }
            self.resetTask?.cancel()
            self.resetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.9))
                ConductorUsageMotion.perform(ConductorUsageMotion.contentSwap) {
                    self.didCopy = false
                }
            }
        } label: {
            Image(systemName: self.didCopy ? "checkmark" : "doc.on.doc")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help(codexBarLocalizedDisplayText(self.didCopy ? "Copied" : "Copy error"))
        .accessibilityLabel(codexBarLocalizedDisplayText(self.didCopy ? "Copied" : "Copy error"))
    }

    private func copyToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(self.copyText, forType: .string)
    }
}

private struct ProviderCostContent: View {
    let section: UsageMenuCardView.Model.ProviderCostSection
    let progressColor: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(codexBarLocalizedDisplayText(self.section.title))
                .font(.body)
                .fontWeight(.medium)
            if let percentUsed = self.section.percentUsed {
                UsageProgressBar(
                    percent: percentUsed,
                    tint: self.progressColor,
                    accessibilityLabel: codexBarLocalizedDisplayText("Extra usage spent"))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(codexBarLocalizedDisplayText(self.section.spendLine))
                    .font(.footnote)
                Spacer()
                if let percentLine = self.section.percentLine {
                    Text(codexBarLocalizedDisplayText(percentLine))
                        .font(.footnote)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                }
            }
        }
    }
}

private struct MetricRow: View {
    let metric: UsageMenuCardView.Model.Metric
    let title: String
    let progressColor: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(codexBarLocalizedDisplayText(self.title))
                .font(.body)
                .fontWeight(.medium)
            if let statusText = self.metric.statusText {
                Text(codexBarLocalizedDisplayText(statusText))
                    .font(.footnote)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
            } else {
                UsageProgressBar(
                    percent: self.metric.percent,
                    tint: self.progressColor,
                    accessibilityLabel: self.metric.percentStyle.accessibilityLabel,
                    pacePercent: self.metric.pacePercent,
                    paceOnTop: self.metric.paceOnTop,
                    warningMarkerPercents: self.metric.warningMarkerPercents)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(self.metric.percentLabel)
                            .font(.footnote)
                            .lineLimit(1)
                        Spacer()
                        if let rightLabel = self.metric.resetText {
                            Text(codexBarLocalizedDisplayText(rightLabel))
                                .font(.footnote)
                                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                                .lineLimit(1)
                        }
                    }
                    if self.metric.detailLeftText != nil || self.metric.detailRightText != nil {
                        HStack(alignment: .firstTextBaseline) {
                            if let detailLeft = self.metric.detailLeftText {
                                Text(codexBarLocalizedDisplayText(detailLeft))
                                    .font(.footnote)
                                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let detailRight = self.metric.detailRightText {
                                Text(codexBarLocalizedDisplayText(detailRight))
                                    .font(.footnote)
                                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let detail = self.metric.detailText {
                    Text(codexBarLocalizedDisplayText(detail))
                        .font(.footnote)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(self.metric.cardStyle ? 10 : 0)
        .background(self.metric.cardStyle ? Color.secondary.opacity(self.isHighlighted ? 0.2 : 0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: self.metric.cardStyle ? 10 : 0))
    }
}

private struct UsageNotesContent: View {
    let notes: [String]
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(self.notes.enumerated()), id: \.offset) { _, note in
                Text(codexBarLocalizedDisplayText(note))
                    .font(.footnote)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UsageMenuSectionBreak: View {
    var body: some View {
        if ConductorUsageMenuStyle.current != nil {
            Color.clear
                .frame(height: 4)
        } else {
            Divider()
        }
    }
}

struct UsageMenuCardHeaderSectionView: View {
    let model: UsageMenuCardView.Model
    let showDivider: Bool
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            UsageMenuCardHeaderView(model: self.model)

            if self.showDivider {
                UsageMenuSectionBreak()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, self.model.subtitleStyle == .error ? 2 : 0)
        .frame(width: self.width, alignment: .leading)
    }
}

struct UsageMenuCardUsageSectionView: View {
    let model: UsageMenuCardView.Model
    let showBottomDivider: Bool
    let bottomPadding: CGFloat
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if self.model.metrics.isEmpty {
                if let dashboard = self.model.inlineUsageDashboard {
                    InlineUsageDashboardContent(model: dashboard)
                } else if !self.model.usageNotes.isEmpty {
                    UsageNotesContent(notes: self.model.usageNotes)
                } else if let placeholder = self.model.placeholder {
                    Text(codexBarLocalizedDisplayText(placeholder))
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .font(.subheadline)
                }
            } else {
                ForEach(self.model.metrics, id: \.id) { metric in
                    MetricRow(
                        metric: metric,
                        title: UsageMenuCardView.popupMetricTitle(provider: self.model.provider, metric: metric),
                        progressColor: self.model.progressColor)
                }
                if let dashboard = self.model.inlineUsageDashboard {
                    InlineUsageDashboardContent(model: dashboard)
                } else if !self.model.usageNotes.isEmpty {
                    UsageNotesContent(notes: self.model.usageNotes)
                }
            }
            if self.showBottomDivider {
                UsageMenuSectionBreak()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, self.bottomPadding)
        .frame(width: self.width, alignment: .leading)
    }
}

struct UsageMenuCardCreditsSectionView: View {
    let model: UsageMenuCardView.Model
    let showBottomDivider: Bool
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let width: CGFloat

    var body: some View {
        if let credits = self.model.creditsText {
            VStack(alignment: .leading, spacing: 6) {
                CreditsBarContent(
                    creditsText: credits,
                    creditsRemaining: self.model.creditsRemaining,
                    hintText: self.model.creditsHintText,
                    hintCopyText: self.model.creditsHintCopyText,
                    progressColor: self.model.progressColor)
                if self.showBottomDivider {
                    UsageMenuSectionBreak()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, self.topPadding)
            .padding(.bottom, self.bottomPadding)
            .frame(width: self.width, alignment: .leading)
        }
    }
}

private struct CreditsBarContent: View {
    private static let fullScaleTokens: Double = 1000

    let creditsText: String
    let creditsRemaining: Double?
    let hintText: String?
    let hintCopyText: String?
    let progressColor: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    private var percentLeft: Double? {
        guard let creditsRemaining else { return nil }
        let percent = (creditsRemaining / Self.fullScaleTokens) * 100
        return min(100, max(0, percent))
    }

    private var scaleText: String {
        let scale = UsageFormatter.tokenCountString(Int(Self.fullScaleTokens))
        return codexBarLocalizedDisplayText("\(scale) tokens")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Credits"))
                .font(.body)
                .fontWeight(.medium)
            if let percentLeft {
                UsageProgressBar(
                    percent: percentLeft,
                    tint: self.progressColor,
                    accessibilityLabel: codexBarLocalizedDisplayText("Credits remaining"))
                HStack(alignment: .firstTextBaseline) {
                    Text(codexBarLocalizedDisplayText(self.creditsText))
                        .font(.caption)
                    Spacer()
                    Text(self.scaleText)
                        .font(.caption)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                }
            } else {
                Text(codexBarLocalizedDisplayText(self.creditsText))
                    .font(.caption)
            }
            if let hintText, !hintText.isEmpty {
                Text(codexBarLocalizedDisplayText(hintText))
                    .font(.footnote)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay {
                        ClickToCopyOverlay(copyText: self.hintCopyText ?? hintText)
                    }
            }
        }
    }
}

struct UsageMenuCardCostSectionView: View {
    let model: UsageMenuCardView.Model
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        let hasTokenCost = self.model.tokenUsage != nil
        return Group {
            if hasTokenCost {
                VStack(alignment: .leading, spacing: 10) {
                    if let tokenUsage = self.model.tokenUsage {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("cost_header_estimated"))
                                .font(.body)
                                .fontWeight(.medium)
                            Text(codexBarLocalizedDisplayText(tokenUsage.sessionLine))
                                .font(.caption)
                            Text(codexBarLocalizedDisplayText(tokenUsage.monthLine))
                                .font(.caption)
                            if let hint = tokenUsage.hintLine, !hint.isEmpty {
                                Text(codexBarLocalizedDisplayText(hint))
                                    .font(.footnote)
                                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                                    .lineLimit(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let error = tokenUsage.errorLine, !error.isEmpty {
                                Text(codexBarLocalizedDisplayText(error))
                                    .font(.footnote)
                                    .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
                                    .lineLimit(4)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .overlay {
                                        ClickToCopyOverlay(copyText: tokenUsage.errorCopyText ?? error)
                                    }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, self.topPadding)
                .padding(.bottom, self.bottomPadding)
                .frame(width: self.width, alignment: .leading)
            }
        }
    }
}

struct UsageMenuCardExtraUsageSectionView: View {
    let model: UsageMenuCardView.Model
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let width: CGFloat

    var body: some View {
        Group {
            if let providerCost = self.model.providerCost {
                ProviderCostContent(
                    section: providerCost,
                    progressColor: self.model.progressColor)
                    .padding(.horizontal, 16)
                    .padding(.top, self.topPadding)
                    .padding(.bottom, self.bottomPadding)
                    .frame(width: self.width, alignment: .leading)
            }
        }
    }
}

// MARK: - Model factory

extension UsageMenuCardView.Model {
    struct Input {
        let provider: UsageProvider
        let metadata: ProviderMetadata
        let snapshot: UsageSnapshot?
        let codexProjection: CodexConsumerProjection?
        let credits: CreditsSnapshot?
        let creditsError: String?
        let dashboard: OpenAIDashboardSnapshot?
        let dashboardError: String?
        let tokenSnapshot: CostUsageTokenSnapshot?
        let tokenError: String?
        let account: AccountInfo
        let isRefreshing: Bool
        let lastError: String?
        let usageBarsShowUsed: Bool
        let resetTimeDisplayStyle: ResetTimeDisplayStyle
        let tokenCostUsageEnabled: Bool
        let showOptionalCreditsAndExtraUsage: Bool
        let sourceLabel: String?
        let kiloAutoMode: Bool
        let hidePersonalInfo: Bool
        let weeklyPace: UsagePace?
        let quotaWarningThresholds: [QuotaWarningWindow: [Int]]
        let workDaysPerWeek: Int?
        let now: Date

        init(
            provider: UsageProvider,
            metadata: ProviderMetadata,
            snapshot: UsageSnapshot?,
            codexProjection: CodexConsumerProjection? = nil,
            credits: CreditsSnapshot?,
            creditsError: String?,
            dashboard: OpenAIDashboardSnapshot?,
            dashboardError: String?,
            tokenSnapshot: CostUsageTokenSnapshot?,
            tokenError: String?,
            account: AccountInfo,
            isRefreshing: Bool,
            lastError: String?,
            usageBarsShowUsed: Bool,
            resetTimeDisplayStyle: ResetTimeDisplayStyle,
            tokenCostUsageEnabled: Bool,
            showOptionalCreditsAndExtraUsage: Bool,
            sourceLabel: String? = nil,
            kiloAutoMode: Bool = false,
            hidePersonalInfo: Bool,
            weeklyPace: UsagePace? = nil,
            quotaWarningThresholds: [QuotaWarningWindow: [Int]] = [:],
            workDaysPerWeek: Int? = nil,
            now: Date)
        {
            self.provider = provider
            self.metadata = metadata
            self.snapshot = snapshot
            self.codexProjection = codexProjection
            self.credits = credits
            self.creditsError = creditsError
            self.dashboard = dashboard
            self.dashboardError = dashboardError
            self.tokenSnapshot = tokenSnapshot
            self.tokenError = tokenError
            self.account = account
            self.isRefreshing = isRefreshing
            self.lastError = lastError
            self.usageBarsShowUsed = usageBarsShowUsed
            self.resetTimeDisplayStyle = resetTimeDisplayStyle
            self.tokenCostUsageEnabled = tokenCostUsageEnabled
            self.showOptionalCreditsAndExtraUsage = showOptionalCreditsAndExtraUsage
            self.sourceLabel = sourceLabel
            self.kiloAutoMode = kiloAutoMode
            self.hidePersonalInfo = hidePersonalInfo
            self.weeklyPace = weeklyPace
            self.quotaWarningThresholds = quotaWarningThresholds
            self.workDaysPerWeek = workDaysPerWeek
            self.now = now
        }
    }

    static func make(_ input: Input) -> UsageMenuCardView.Model {
        let planText = Self.plan(
            for: input.provider,
            snapshot: input.snapshot,
            account: input.account,
            metadata: input.metadata)
        let metrics = Self.metrics(input: input)
        let openAIAPIUsage = input.snapshot?.openAIAPIUsage
        let inlineUsageDashboard = Self.inlineUsageDashboard(input: input)
        let usageNotes = Self.usageNotes(input: input)
        let creditsText: String? = if input.provider == .openrouter {
            nil
        } else if input.codexProjection != nil, !input.showOptionalCreditsAndExtraUsage {
            nil
        } else {
            Self.creditsLine(metadata: input.metadata, credits: input.credits, error: input.creditsError)
        }
        let isClaudeAdminAPI = input.provider == .claude &&
            input.snapshot?.identity?.loginMethod == "Admin API"
        let hidesOptionalProviderCost = ((input.provider == .claude && !isClaudeAdminAPI) ||
            input.provider == .factory ||
            input.provider == .opencodego) &&
            !input.showOptionalCreditsAndExtraUsage
        let providerCost: ProviderCostSection? = if hidesOptionalProviderCost ||
            (input.provider == .openai && openAIAPIUsage != nil)
        {
            nil
        } else {
            Self.providerCostSection(provider: input.provider, cost: input.snapshot?.providerCost)
        }
        let tokenUsage = Self.tokenUsageSection(
            provider: input.provider,
            enabled: input.tokenCostUsageEnabled,
            snapshot: input.tokenSnapshot,
            error: input.tokenError)
        let subtitle = Self.subtitle(
            snapshot: input.snapshot,
            isRefreshing: input.isRefreshing,
            lastError: Self.lastError(input: input),
            now: input.now)
        let redacted = Self.redactedText(input: input, subtitle: subtitle)
        let placeholder = Self.placeholder(input: input)

        return UsageMenuCardView.Model(
            provider: input.provider,
            providerName: input.metadata.displayName,
            email: redacted.email,
            subtitleText: redacted.subtitleText,
            subtitleStyle: subtitle.style,
            planText: planText,
            metrics: metrics,
            usageNotes: usageNotes,
            openAIAPIUsage: openAIAPIUsage,
            inlineUsageDashboard: inlineUsageDashboard,
            creditsText: creditsText,
            creditsRemaining: input.credits?.remaining,
            creditsHintText: redacted.creditsHintText,
            creditsHintCopyText: redacted.creditsHintCopyText,
            providerCost: providerCost,
            tokenUsage: tokenUsage,
            placeholder: placeholder,
            progressColor: Self.progressColor(for: input.provider))
    }

    private static func usageNotes(input: Input) -> [String] {
        if input.provider == .kiro {
            return kiroUsageNotes(input: input)
        }

        if input.provider == .kilo {
            var notes = Self.kiloLoginDetails(snapshot: input.snapshot)
            let resolvedSource = input.sourceLabel?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if input.kiloAutoMode,
               resolvedSource == "cli",
               !notes.contains(where: { $0.caseInsensitiveCompare("Using CLI fallback") == .orderedSame })
            {
                notes.append("Using CLI fallback")
            }
            return notes
        }

        if input.provider == .mimo, input.snapshot != nil {
            return [
                "Balance updates in near-real time (up to 5 min lag)",
                "Daily billing data finalizes at 07:00 UTC",
            ]
        }

        if let notes = apiProviderUsageNotes(input: input) {
            return notes
        }

        guard input.provider == .openrouter,
              let openRouter = input.snapshot?.openRouterUsage
        else {
            return []
        }

        var notes = Self.openRouterSpendNotes(openRouter)
        switch openRouter.keyQuotaStatus {
        case .available:
            break
        case .noLimitConfigured:
            notes.append("No limit set for the API key")
        case .unavailable:
            notes.append("API key limit unavailable right now")
        }
        return notes
    }

    private static func openRouterSpendNotes(_ usage: OpenRouterUsageSnapshot) -> [String] {
        var parts: [String] = []
        if let daily = usage.keyUsageDaily {
            parts.append("Today: \(Self.openRouterCurrencyString(daily))")
        }
        if let weekly = usage.keyUsageWeekly {
            parts.append("This week: \(Self.openRouterCurrencyString(weekly))")
        }
        guard !parts.isEmpty else { return [] }
        return [parts.joined(separator: " · ")]
    }

    private static func openRouterCurrencyString(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private static func email(
        for provider: UsageProvider,
        snapshot: UsageSnapshot?,
        account: AccountInfo,
        metadata: ProviderMetadata) -> String
    {
        if let email = snapshot?.accountEmail(for: provider), !email.isEmpty { return email }
        if metadata.usesAccountFallback,
           let email = account.email, !email.isEmpty
        {
            return email
        }
        return ""
    }

    private static func plan(
        for provider: UsageProvider,
        snapshot: UsageSnapshot?,
        account: AccountInfo,
        metadata: ProviderMetadata) -> String?
    {
        if provider == .kiro,
           let plan = kiroPlan(snapshot: snapshot)
        {
            return plan
        }
        if provider == .kilo {
            guard let pass = self.kiloLoginPass(snapshot: snapshot) else {
                return nil
            }
            return self.planDisplay(pass, for: provider)
        }
        if let plan = snapshot?.loginMethod(for: provider), !plan.isEmpty {
            return self.planDisplay(plan, for: provider)
        }
        if metadata.usesAccountFallback,
           let plan = account.plan, !plan.isEmpty
        {
            return Self.planDisplay(plan, for: provider)
        }
        return nil
    }

    private static func planDisplay(_ text: String, for provider: UsageProvider) -> String {
        let cleaned = if provider == .codex {
            CodexPlanFormatting.displayName(text) ?? UsageFormatter.cleanPlanName(text)
        } else {
            UsageFormatter.cleanPlanName(text)
        }
        return cleaned.isEmpty ? text : cleaned
    }

    private static func kiloLoginPass(snapshot: UsageSnapshot?) -> String? {
        self.kiloLoginParts(snapshot: snapshot).pass
    }

    private static func kiloLoginDetails(snapshot: UsageSnapshot?) -> [String] {
        self.kiloLoginParts(snapshot: snapshot).details
    }

    private static func kiloLoginParts(snapshot: UsageSnapshot?) -> (pass: String?, details: [String]) {
        guard let loginMethod = snapshot?.loginMethod(for: .kilo) else {
            return (nil, [])
        }
        let parts = loginMethod
            .components(separatedBy: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            return (nil, [])
        }
        let first = parts[0]
        if self.isKiloActivitySegment(first) {
            return (nil, parts)
        }
        return (first, Array(parts.dropFirst()))
    }

    private static func isKiloActivitySegment(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("auto top-up:")
    }

    private static func subtitle(
        snapshot: UsageSnapshot?,
        isRefreshing: Bool,
        lastError: String?,
        now: Date) -> (text: String, style: SubtitleStyle)
    {
        if let lastError, !lastError.isEmpty {
            return (lastError.trimmingCharacters(in: .whitespacesAndNewlines), .error)
        }

        if isRefreshing, snapshot == nil {
            return ("Refreshing...", .loading)
        }

        if let updated = snapshot?.updatedAt {
            return (UsageFormatter.updatedString(from: updated, now: now), .info)
        }

        return ("Not fetched yet", .info)
    }

    private struct RedactedText {
        let email: String
        let subtitleText: String
        let creditsHintText: String?
        let creditsHintCopyText: String?
    }

    private static func redactedText(
        input: Input,
        subtitle: (text: String, style: SubtitleStyle)) -> RedactedText
    {
        let email = PersonalInfoRedactor.redactEmail(
            Self.email(
                for: input.provider,
                snapshot: input.snapshot,
                account: input.account,
                metadata: input.metadata),
            isEnabled: input.hidePersonalInfo)
        let rawSubtitleText = PersonalInfoRedactor.redactEmails(in: subtitle.text, isEnabled: input.hidePersonalInfo)
            ?? subtitle.text
        let subtitleText = CodexBarDisplayBrand.userFacing(rawSubtitleText)
        let creditsHintText = PersonalInfoRedactor.redactEmails(
            in: Self.dashboardHint(error: input.dashboardError),
            isEnabled: input.hidePersonalInfo)
        let creditsHintCopyText = Self.creditsHintCopyText(
            dashboardError: input.dashboardError,
            hidePersonalInfo: input.hidePersonalInfo)
        return RedactedText(
            email: email,
            subtitleText: subtitleText,
            creditsHintText: creditsHintText,
            creditsHintCopyText: creditsHintCopyText)
    }

    private static func creditsHintCopyText(dashboardError: String?, hidePersonalInfo: Bool) -> String? {
        guard let dashboardError, !dashboardError.isEmpty else { return nil }
        return hidePersonalInfo ? "" : dashboardError
    }

    private static func metrics(input: Input) -> [Metric] {
        guard let snapshot = input.snapshot else { return [] }
        if input.provider == .antigravity {
            return Self.antigravityMetrics(input: input, snapshot: snapshot)
        }
        if input.provider == .minimax {
            if let minimaxUsage = snapshot.minimaxUsage {
                if let services = minimaxUsage.services, !services.isEmpty {
                    return Self.minimaxMetrics(services: services, input: input)
                }
            }
        }
        var metrics: [Metric] = []
        let percentStyle: PercentStyle = input.usageBarsShowUsed ? .used : .left
        let zaiUsage = input.provider == .zai ? snapshot.zaiUsage : nil
        let zaiTokenDetail = Self.zaiLimitDetailText(limit: zaiUsage?.tokenLimit)
        let zaiTimeDetail = Self.zaiLimitDetailText(limit: zaiUsage?.timeLimit)
        let zaiSessionDetail = Self.zaiLimitDetailText(limit: zaiUsage?.sessionTokenLimit)
        let openRouterQuotaDetail = Self.openRouterQuotaDetail(provider: input.provider, snapshot: snapshot)
        let labels = Self.rateWindowLabels(input: input, snapshot: snapshot)
        if input.provider == .codex, let codexProjection = input.codexProjection {
            metrics.append(contentsOf: Self.codexRateMetrics(
                input: input,
                projection: codexProjection,
                percentStyle: percentStyle))
        } else if let primary = snapshot.primary {
            metrics.append(Self.primaryMetric(
                input: input,
                primary: primary,
                percentStyle: percentStyle,
                title: labels.primary,
                zaiTokenDetail: zaiTokenDetail,
                openRouterQuotaDetail: openRouterQuotaDetail))
        }
        if input.provider != .codex, let weekly = snapshot.secondary {
            metrics.append(Self.secondaryMetric(
                input: input,
                weekly: weekly,
                percentStyle: percentStyle,
                title: labels.secondary,
                zaiTimeDetail: zaiTimeDetail))
        }
        if labels.showsTertiary, let opus = snapshot.tertiary {
            var tertiaryDetailText: String?
            if input.provider == .alibaba || input.provider == .alibabatokenplan,
               let detail = opus.resetDescription,
               !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                tertiaryDetailText = detail
            }
            if input.provider == .zai, let detail = zaiSessionDetail {
                tertiaryDetailText = detail
            }
            // Perplexity purchased credits don't reset; show balance without "Resets" prefix.
            let opusResetText: String? = input.provider == .perplexity
                ? opus.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
                : Self.resetText(for: opus, style: input.resetTimeDisplayStyle, now: input.now)
            metrics.append(Metric(
                id: "tertiary",
                title: labels.tertiary,
                percent: Self.clamped(input.usageBarsShowUsed ? opus.usedPercent : opus.remainingPercent),
                percentStyle: percentStyle,
                resetText: opusResetText,
                detailText: tertiaryDetailText,
                detailLeftText: nil,
                detailRightText: nil,
                pacePercent: nil,
                paceOnTop: true,
                warningMarkerPercents: Self.warningMarkerPercents(
                    thresholds: input.quotaWarningThresholds[.weekly],
                    showUsed: input.usageBarsShowUsed)))
        }
        if let extraRateWindows = snapshot.extraRateWindows {
            metrics.append(contentsOf: extraRateWindows.map { namedWindow in
                Metric(
                    id: namedWindow.id,
                    title: namedWindow.title,
                    percent: Self.clamped(
                        input.usageBarsShowUsed
                            ? namedWindow.window.usedPercent
                            : namedWindow.window.remainingPercent),
                    percentStyle: percentStyle,
                    resetText: Self.resetText(
                        for: namedWindow.window,
                        style: input.resetTimeDisplayStyle,
                        now: input.now),
                    detailText: nil,
                    detailLeftText: nil,
                    detailRightText: nil,
                    pacePercent: nil,
                    paceOnTop: true)
            })
        }
        if input.provider == .kilo,
           metrics.contains(where: { $0.id == "primary" }),
           metrics.contains(where: { $0.id == "secondary" })
        {
            metrics.sort { lhs, rhs in
                let kiloOrder: [String: Int] = [
                    "secondary": 0,
                    "primary": 1,
                ]
                return (kiloOrder[lhs.id] ?? Int.max) < (kiloOrder[rhs.id] ?? Int.max)
            }
        }

        if let codexProjection = input.codexProjection,
           codexProjection.supplementalMetrics.contains(.codeReview),
           let remaining = codexProjection.remainingPercent(for: .codeReview)
        {
            let percent = input.usageBarsShowUsed ? (100 - remaining) : remaining
            let resetText = codexProjection.limitWindow(for: .codeReview).flatMap {
                Self.resetText(for: $0, style: input.resetTimeDisplayStyle, now: input.now)
            }
            metrics.append(Metric(
                id: "code-review",
                title: "Code review",
                percent: Self.clamped(percent),
                percentStyle: percentStyle,
                resetText: resetText,
                detailText: nil,
                detailLeftText: nil,
                detailRightText: nil,
                pacePercent: nil,
                paceOnTop: true))
        }
        return metrics
    }

    private static func rateWindowLabels(
        input: Input,
        snapshot: UsageSnapshot) -> (primary: String, secondary: String, tertiary: String, showsTertiary: Bool)
    {
        if input.provider == .factory, snapshot.tertiary != nil {
            return ("5-hour", "Weekly", "Monthly", true)
        }
        return (
            input.metadata.sessionLabel,
            input.metadata.weeklyLabel,
            input.metadata.opusLabel ?? "Sonnet",
            input.metadata.supportsOpus)
    }

    private static func primaryMetric(
        input: Input,
        primary: RateWindow,
        percentStyle: PercentStyle,
        title: String? = nil,
        zaiTokenDetail: String?,
        openRouterQuotaDetail: String?) -> Metric
    {
        var primaryDetailText: String? = input.provider == .zai ? zaiTokenDetail : nil
        var primaryResetText = Self.resetText(for: primary, style: input.resetTimeDisplayStyle, now: input.now)
        var primaryDetailLeft: String?
        var primaryDetailRight: String?
        if input.provider == .crof,
           let detail = primary.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty
        {
            primaryDetailRight = detail
        }
        if input.provider == .openrouter,
           let openRouterQuotaDetail
        {
            primaryResetText = openRouterQuotaDetail
        }
        if input.provider == .copilot,
           let detail = primary.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty
        {
            primaryDetailLeft = detail
        }
        if input.provider == .warp || input.provider == .kilo || input.provider == .mimo || input.provider == .deepseek,
           let detail = primary.resetDescription,
           !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            primaryDetailText = detail
        }
        if input.provider == .kiro,
           let kiroUsage = input.snapshot?.kiroUsage,
           kiroUsage.creditsTotal > 0
        {
            let remaining = UsageFormatter.kiroCreditNumber(kiroUsage.creditsRemaining)
            let total = UsageFormatter.kiroCreditNumber(kiroUsage.creditsTotal)
            primaryDetailLeft = "\(remaining) of \(total) credits left"
        }
        if input.provider == .alibaba || input.provider == .alibabatokenplan || input.provider == .mistral || input
            .provider == .manus,
            let detail = primary.resetDescription,
            !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            primaryDetailText = detail
            if input.provider == .manus { primaryResetText = nil }
        }
        if [.warp, .kilo, .mimo, .deepseek].contains(input.provider), primary.resetsAt == nil {
            primaryResetText = nil
        }
        // Abacus: show credits as detail, compute pace on the primary monthly window
        var primaryPacePercent: Double?
        var primaryPaceOnTop = true
        if let paceDetail = Self.sessionPaceDetail(
            provider: input.provider,
            window: primary,
            now: input.now,
            showUsed: input.usageBarsShowUsed)
        {
            primaryDetailLeft = paceDetail.leftLabel
            primaryDetailRight = paceDetail.rightLabel
            primaryPacePercent = paceDetail.pacePercent
            primaryPaceOnTop = paceDetail.paceOnTop
        }
        if input.provider == .abacus {
            if let detail = primary.resetDescription,
               !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                primaryDetailText = detail
            }
            if primary.resetsAt == nil {
                primaryResetText = nil
            }
            if let pace = input.weeklyPace {
                let paceDetail = Self.weeklyPaceDetail(
                    window: primary,
                    now: input.now,
                    pace: pace,
                    showUsed: input.usageBarsShowUsed)
                if let paceDetail {
                    primaryDetailLeft = paceDetail.leftLabel
                    primaryDetailRight = paceDetail.rightLabel
                    primaryPacePercent = paceDetail.pacePercent
                    primaryPaceOnTop = paceDetail.paceOnTop
                }
            }
        }
        if input.provider == .synthetic,
           let regen = Self.syntheticRollingRegenDetail(
               window: primary,
               now: input.now,
               showUsed: input.usageBarsShowUsed)
        {
            primaryResetText = regen.resetText
            primaryDetailLeft = regen.pace.leftLabel
            primaryDetailRight = regen.pace.rightLabel
            primaryPacePercent = regen.pace.pacePercent
            primaryPaceOnTop = regen.pace.paceOnTop
        }
        let primaryStatusText = input.provider == .deepseek ? primaryDetailText : nil
        if input.provider == .deepseek {
            primaryDetailText = nil
        }
        return Metric(
            id: "primary",
            title: title ?? input.metadata.sessionLabel,
            percent: Self.clamped(
                input.usageBarsShowUsed ? primary.usedPercent : primary.remainingPercent),
            percentStyle: percentStyle,
            statusText: primaryStatusText,
            resetText: primaryResetText,
            detailText: primaryDetailText,
            detailLeftText: primaryDetailLeft,
            detailRightText: primaryDetailRight,
            pacePercent: primaryPacePercent,
            paceOnTop: primaryPaceOnTop,
            warningMarkerPercents: Self.warningMarkerPercents(
                thresholds: input.quotaWarningThresholds[.session],
                showUsed: input.usageBarsShowUsed))
    }

    private static func secondaryMetric(
        input: Input,
        weekly: RateWindow,
        percentStyle: PercentStyle,
        title: String? = nil,
        zaiTimeDetail: String?) -> Metric
    {
        var paceDetail = Self.weeklyPaceDetail(
            window: weekly,
            now: input.now,
            pace: input.weeklyPace,
            showUsed: input.usageBarsShowUsed)
        var weeklyResetText = Self.resetText(for: weekly, style: input.resetTimeDisplayStyle, now: input.now)
        var weeklyDetailText: String? = input.provider == .zai ? zaiTimeDetail : nil
        if input.provider == .warp,
           let detail = weekly.resetDescription,
           !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            weeklyResetText = nil
            weeklyDetailText = detail
        }
        if input.provider == .kilo,
           let detail = weekly.resetDescription,
           !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            weeklyDetailText = detail
            if weekly.resetsAt == nil {
                weeklyResetText = nil
            }
        }
        if input.provider == .kiro,
           let kiroUsage = input.snapshot?.kiroUsage,
           let remaining = kiroUsage.bonusCreditsRemaining,
           let total = kiroUsage.bonusCreditsTotal
        {
            let remainingText = UsageFormatter.kiroCreditNumber(remaining)
            let totalText = UsageFormatter.kiroCreditNumber(total)
            paceDetail = PaceDetail(
                leftLabel: "\(remainingText) of \(totalText) bonus credits left",
                rightLabel: nil,
                pacePercent: nil,
                paceOnTop: true)
        }
        if input.provider == .alibaba || input.provider == .alibabatokenplan,
           let detail = weekly.resetDescription,
           !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            weeklyDetailText = detail
        }
        if input.provider == .manus,
           let detail = weekly.resetDescription,
           !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            weeklyDetailText = detail
        }
        if input.provider == .crof,
           let detail = weekly.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty
        {
            weeklyResetText = detail
        }
        if input.provider == .copilot,
           let detail = weekly.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty
        {
            paceDetail = PaceDetail(leftLabel: detail, rightLabel: nil, pacePercent: nil, paceOnTop: true)
        }
        // Perplexity bonus credits don't reset; show balance without "Resets" prefix.
        if input.provider == .perplexity,
           let detail = weekly.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty
        {
            weeklyResetText = detail
        }
        if input.provider == .synthetic,
           let regen = Self.syntheticRegenDetail(
               weekly: weekly,
               cost: input.snapshot?.providerCost,
               now: input.now,
               showUsed: input.usageBarsShowUsed)
        {
            weeklyResetText = regen.resetText
            paceDetail = regen.pace
        }
        return Metric(
            id: "secondary",
            title: title ?? input.metadata.weeklyLabel,
            percent: Self.clamped(input.usageBarsShowUsed ? weekly.usedPercent : weekly.remainingPercent),
            percentStyle: percentStyle,
            resetText: weeklyResetText,
            detailText: weeklyDetailText,
            detailLeftText: paceDetail?.leftLabel,
            detailRightText: paceDetail?.rightLabel,
            pacePercent: paceDetail?.pacePercent,
            paceOnTop: paceDetail?.paceOnTop ?? true,
            warningMarkerPercents: Self.weeklyMarkerPercents(input: input, windowMinutes: weekly.windowMinutes))
    }

    private static func codexRateMetrics(
        input: Input,
        projection: CodexConsumerProjection,
        percentStyle: PercentStyle) -> [Metric]
    {
        projection.visibleRateLanes.compactMap { lane in
            guard let window = projection.rateWindow(for: lane) else { return nil }

            let title: String
            let id: String
            let paceDetail: PaceDetail?
            switch lane {
            case .session:
                title = input.metadata.sessionLabel
                id = "primary"
                paceDetail = Self.sessionPaceDetail(
                    provider: input.provider,
                    window: window,
                    now: input.now,
                    showUsed: input.usageBarsShowUsed)
            case .weekly:
                title = input.metadata.weeklyLabel
                id = "secondary"
                paceDetail = Self.weeklyPaceDetail(
                    window: window,
                    now: input.now,
                    pace: input.weeklyPace
                        ?? UsagePace.weekly(window: window, now: input.now, defaultWindowMinutes: 10080)
                        .flatMap { $0.expectedUsedPercent >= 3 ? $0 : nil },
                    showUsed: input.usageBarsShowUsed)
            }

            return Metric(
                id: id,
                title: title,
                percent: Self.clamped(input.usageBarsShowUsed ? window.usedPercent : window.remainingPercent),
                percentStyle: percentStyle,
                resetText: Self.resetText(for: window, style: input.resetTimeDisplayStyle, now: input.now),
                detailText: nil,
                detailLeftText: paceDetail?.leftLabel,
                detailRightText: paceDetail?.rightLabel,
                pacePercent: paceDetail?.pacePercent,
                paceOnTop: paceDetail?.paceOnTop ?? true,
                warningMarkerPercents: Self.codexLaneMarkerPercents(
                    input: input,
                    lane: lane,
                    windowMinutes: window.windowMinutes))
        }
    }

    private static func antigravityMetrics(input: Input, snapshot: UsageSnapshot) -> [Metric] {
        let percentStyle: PercentStyle = input.usageBarsShowUsed ? .used : .left
        return [
            Self.antigravityMetric(
                id: "primary",
                title: input.metadata.sessionLabel,
                window: snapshot.primary,
                input: input,
                percentStyle: percentStyle),
            Self.antigravityMetric(
                id: "secondary",
                title: input.metadata.weeklyLabel,
                window: snapshot.secondary,
                input: input,
                percentStyle: percentStyle),
            Self.antigravityMetric(
                id: "tertiary",
                title: input.metadata.opusLabel ?? "Gemini Flash",
                window: snapshot.tertiary,
                input: input,
                percentStyle: percentStyle),
        ]
    }

    private static func antigravityMetric(
        id: String,
        title: String,
        window: RateWindow?,
        input: Input,
        percentStyle: PercentStyle) -> Metric
    {
        guard let window else {
            let placeholderPercent = input.usageBarsShowUsed ? 100.0 : 0.0
            return Metric(
                id: id,
                title: title,
                percent: placeholderPercent,
                percentStyle: percentStyle,
                statusText: nil,
                resetText: nil,
                detailText: nil,
                detailLeftText: nil,
                detailRightText: nil,
                pacePercent: nil,
                paceOnTop: true)
        }
        let percent = input.usageBarsShowUsed ? window.usedPercent : window.remainingPercent
        return Metric(
            id: id,
            title: title,
            percent: Self.clamped(percent),
            percentStyle: percentStyle,
            resetText: Self.resetText(for: window, style: input.resetTimeDisplayStyle, now: input.now),
            detailText: nil,
            detailLeftText: nil,
            detailRightText: nil,
            pacePercent: nil,
            paceOnTop: true)
    }

    private static func zaiLimitDetailText(limit: ZaiLimitEntry?) -> String? {
        guard let limit else { return nil }

        if let currentValue = limit.currentValue,
           let usage = limit.usage,
           let remaining = limit.remaining
        {
            let currentStr = UsageFormatter.tokenCountString(currentValue)
            let usageStr = UsageFormatter.tokenCountString(usage)
            let remainingStr = UsageFormatter.tokenCountString(remaining)
            return "\(currentStr) / \(usageStr) (\(remainingStr) remaining)"
        }

        return nil
    }

    private static func openRouterQuotaDetail(provider: UsageProvider, snapshot: UsageSnapshot) -> String? {
        guard provider == .openrouter,
              let usage = snapshot.openRouterUsage,
              usage.hasValidKeyQuota,
              let keyRemaining = usage.keyRemaining,
              let keyLimit = usage.keyLimit
        else {
            return nil
        }

        let remaining = UsageFormatter.usdString(keyRemaining)
        let limit = UsageFormatter.usdString(keyLimit)
        return "\(remaining)/\(limit) left"
    }

    private static func syntheticRegenDetail(
        weekly: RateWindow,
        cost: ProviderCostSnapshot?,
        now: Date,
        showUsed: Bool) -> (resetText: String, pace: PaceDetail)?
    {
        guard let cost,
              cost.limit > 0,
              let nextRegenAmount = cost.nextRegenAmount,
              nextRegenAmount > 0,
              let resetsAt = weekly.resetsAt
        else { return nil }

        let countdown = UsageFormatter.resetCountdownDescription(from: resetsAt, now: now)
        let resetText = "Regenerates \(countdown)"

        let nextRegenPercent = (nextRegenAmount / cost.limit) * 100
        let afterNextRegenRemaining = min(100, weekly.remainingPercent + nextRegenPercent)
        let afterNextRegen = showUsed ? max(0, 100 - afterNextRegenRemaining) : afterNextRegenRemaining
        let suffix = showUsed ? "used after next regen" : "after next regen"
        let ticksToFull = max(0, cost.used) / nextRegenAmount
        let left = String(format: "%.0f%% %@", afterNextRegen, suffix)
        let right = if ticksToFull <= 0.1 {
            "Near full"
        } else if ticksToFull < 1.5 {
            "Full in ~1 regen"
        } else {
            String(format: "Full in ~%.0f regens", ceil(ticksToFull))
        }
        return (resetText, PaceDetail(leftLabel: left, rightLabel: right, pacePercent: nil, paceOnTop: true))
    }

    private static func syntheticRollingRegenDetail(
        window: RateWindow,
        now: Date,
        showUsed: Bool) -> (resetText: String, pace: PaceDetail)?
    {
        guard let resetsAt = window.resetsAt,
              let nextRegenPercent = window.nextRegenPercent,
              nextRegenPercent > 0
        else { return nil }

        let countdown = UsageFormatter.resetCountdownDescription(from: resetsAt, now: now)
        let resetText = "Regenerates \(countdown)"

        let afterNextRegenRemaining = min(100, window.remainingPercent + nextRegenPercent)
        let afterNextRegen = showUsed ? max(0, 100 - afterNextRegenRemaining) : afterNextRegenRemaining
        let suffix = showUsed ? "used after next regen" : "after next regen"
        let left = String(format: "%.0f%% %@", afterNextRegen, suffix)

        let missingPercent = max(0, window.usedPercent)
        let ticksToFull = missingPercent / nextRegenPercent
        let right = if ticksToFull <= 0.1 {
            "Near full"
        } else if ticksToFull < 1.5 {
            "Full in ~1 regen"
        } else {
            String(format: "Full in ~%.0f regens", ceil(ticksToFull))
        }

        return (resetText, PaceDetail(leftLabel: left, rightLabel: right, pacePercent: nil, paceOnTop: true))
    }

    private static func dashboardHint(error: String?) -> String? {
        guard let error, !error.isEmpty else { return nil }
        return error
    }
}
