#if os(macOS) && canImport(WebKit)
import AppKit
import Foundation
import WebKit

@MainActor
enum OpenAIDashboardWebKitUsageFetcher {
    private static let usagePageURL = URL(string: "https://chatgpt.com/codex/cloud/settings/analytics#usage")!
    private static let dashboardAcceptLanguage = "en-US,en;q=0.9"
    private static let initialNavigationDelayNanoseconds: UInt64 = 1_200_000_000
    private static let pollDelayNanoseconds: UInt64 = 400_000_000

    static func fetch(
        cookieHeader: String,
        cookieSnapshots: [OpenAIDashboardCookieSnapshot] = [],
        accountEmail: String? = nil,
        timeout: TimeInterval = 35,
        debugDumpHTML: Bool = false,
        replaceExistingCookies: Bool = false,
        logger: (@Sendable (String) -> Void)? = nil
    ) async throws -> OpenAIDashboardSnapshot {
        let deadline = Date().addingTimeInterval(max(5, min(timeout, 90)))
        _ = NSApplication.shared

        OpenAIWebDebugLog.shared.updateStatus(L("正在加载 OpenAI dashboard…"))
        let store = OpenAIDashboardWebsiteDataStore.store(forAccountEmail: accountEmail)
        let cacheKey = OpenAIDashboardWebsiteDataStore.cacheKey(forAccountEmail: accountEmail)
        let cacheKeyLabel = cacheKey ?? "default"
        logger?("webkit install cookies snapshots=\(cookieSnapshots.count), replace=\(replaceExistingCookies), account=\(accountEmail ?? "unresolved")")
        await OpenAIDashboardWebsiteDataStore.installCookies(
            cookieSnapshots,
            fallbackCookieHeader: cookieHeader,
            in: store,
            forAccountEmail: accountEmail,
            replacingExistingCookies: replaceExistingCookies)

        logger?("webkit acquire cacheKey=\(cacheKeyLabel), timeout=\(max(1, min(deadline.timeIntervalSinceNow, 15)))")
        let lease = try await OpenAIDashboardWebViewCache.shared.acquire(
            websiteDataStore: store,
            cacheKey: cacheKey,
            usageURL: usagePageURL,
            navigationTimeout: max(1, min(deadline.timeIntervalSinceNow, 15)))
        let webView = lease.webView
        defer {
            lease.release()
        }

        try await Task.sleep(nanoseconds: initialNavigationDelayNanoseconds)

        var lastBody = ""
        var firstDashboardSignalAt: Date?
        var firstCodeReviewAt: Date?
        var creditsHeaderVisibleAt: Date?
        var usageBreakdownErrorFirstSeenAt: Date?
        var lastScrape: ScrapeResult?
        var lastHref: String?
        var lastFlags = ""
        var lastUsageBreakdownDebug: String?
        var lastUsageBreakdownError: String?
        var lastCreditsPurchaseURL: String?

        while Date() < deadline {
            try Task.checkCancellation()
            let scrape = try await scrape(webView: webView)
            lastScrape = scrape
            if !scrape.bodyText.isEmpty {
                lastBody = scrape.bodyText
            }
            if scrape.href != lastHref {
                logger?("webkit href=\(scrape.href ?? "unknown")")
                lastHref = scrape.href
            }
            let flags = statusFlags(for: scrape)
            if flags != lastFlags {
                logger?("webkit state \(flags)")
                lastFlags = flags
            }
            if scrape.usageBreakdownDebug != lastUsageBreakdownDebug {
                logger?("usage breakdown debug: \(scrape.usageBreakdownDebug ?? "none")")
                lastUsageBreakdownDebug = scrape.usageBreakdownDebug
            }
            if scrape.usageBreakdownError != lastUsageBreakdownError {
                if let error = scrape.usageBreakdownError, !error.isEmpty {
                    logger?("usage breakdown error: \(error)")
                }
                lastUsageBreakdownError = scrape.usageBreakdownError
            }
            if scrape.creditsPurchaseURL != lastCreditsPurchaseURL {
                if let url = scrape.creditsPurchaseURL, !url.isEmpty {
                    logger?("credits purchase url=\(url)")
                }
                lastCreditsPurchaseURL = scrape.creditsPurchaseURL
            }

            if scrape.loginRequired {
                if debugDumpHTML {
                    _ = await dumpDebugArtifacts(webView: webView, bodyText: scrape.bodyText, logger: logger)
                }
                OpenAIWebDebugLog.shared.updateStatus(L("OpenAI dashboard 需要重新登录。"))
                logger?("webkit login required")
                throw OpenAIDashboardUsageError.unauthorized
            }
            if scrape.cloudflareInterstitial {
                let sample = debugDumpHTML
                    ? await debugSample(
                        webView: webView,
                        bodyText: scrape.bodyText,
                        fallback: "Cloudflare challenge detected in WebKit dashboard.",
                        logger: logger)
                    : "Cloudflare challenge detected in WebKit dashboard."
                OpenAIWebDebugLog.shared.updateStatus(L("OpenAI dashboard 遇到 Cloudflare 检查。"))
                logger?("webkit cloudflare interstitial")
                throw OpenAIDashboardUsageError.noDashboardData(sample)
            }
            if shouldReloadUsageRoute(scrape) {
                OpenAIWebDebugLog.shared.updateStatus(L("正在切换到 OpenAI usage 页面…"))
                logger?("webkit reload usage route from \(scrape.href ?? "unknown")")
                loadUsagePage(in: webView)
                try await Task.sleep(nanoseconds: pollDelayNanoseconds)
                continue
            }

            let snapshot = makeSnapshot(from: scrape)
            if snapshot.hasReturnableData, firstDashboardSignalAt == nil {
                firstDashboardSignalAt = Date()
                logger?("webkit first dashboard signal")
            }
            if snapshot.codeReviewRemainingPercent != nil, firstCodeReviewAt == nil {
                firstCodeReviewAt = Date()
                logger?("webkit code review limit visible")
            }
            if scrape.creditsHeaderPresent, scrape.creditsHeaderInViewport, creditsHeaderVisibleAt == nil {
                creditsHeaderVisibleAt = Date()
                logger?("credits history header visible")
            }
            updateUsageBreakdownErrorState(
                usageBreakdown: snapshot.usageBreakdown,
                error: scrape.usageBreakdownError,
                firstSeenAt: &usageBreakdownErrorFirstSeenAt)

            if snapshot.hasReturnableData {
                if snapshot.creditEvents.isEmpty,
                   shouldWaitForCreditsHistory(
                       now: Date(),
                       dashboardSignalAt: firstDashboardSignalAt,
                       creditsHeaderVisibleAt: creditsHeaderVisibleAt,
                       scrape: scrape)
                {
                    OpenAIWebDebugLog.shared.updateStatus(L("正在等待 credits history 渲染…"))
                    logger?("waiting for credits history rows; rows=\(snapshot.creditEvents.count), scrolled=\(scrape.didScrollToCredits)")
                    try await Task.sleep(nanoseconds: pollDelayNanoseconds)
                    continue
                }

                if snapshot.usageBreakdown.isEmpty,
                   let error = scrape.usageBreakdownError,
                   !error.isEmpty,
                   shouldWaitForUsageBreakdownRecovery(.init(
                       now: Date(),
                       errorFirstSeenAt: usageBreakdownErrorFirstSeenAt))
                {
                    OpenAIWebDebugLog.shared.updateStatus(L("正在等待 usage breakdown 图表恢复…"))
                    logger?("waiting for usage breakdown recovery: \(error)")
                    try await Task.sleep(nanoseconds: pollDelayNanoseconds)
                    continue
                }

                if snapshot.codeReviewRemainingPercent != nil,
                   snapshot.usageBreakdown.isEmpty,
                   Date().timeIntervalSince(firstCodeReviewAt ?? Date()) < 6
                {
                    OpenAIWebDebugLog.shared.updateStatus(L("正在等待 usage breakdown 图表渲染…"))
                    logger?("waiting for usage breakdown after code review signal")
                    try await Task.sleep(nanoseconds: pollDelayNanoseconds)
                    continue
                }

                lease.setPreserveLoadedPageOnRelease(true)
                OpenAIWebDebugLog.shared.updateStatus(L("OpenAI dashboard 抓取完成。"))
                logger?("webkit snapshot ready: events=\(snapshot.creditEvents.count), usageBreakdown=\(snapshot.usageBreakdown.count), email=\(snapshot.signedInEmail ?? "unknown")")
                return snapshot
            }

            try await Task.sleep(nanoseconds: pollDelayNanoseconds)
        }

        let body = lastScrape?.usageBreakdownError ?? lastBody
        let sample = debugDumpHTML
            ? await debugSample(webView: webView, bodyText: lastBody, fallback: body, logger: logger)
            : body
        OpenAIWebDebugLog.shared.updateStatus(L("OpenAI dashboard 超时或没有可用数据。"))
        logger?("webkit no dashboard data before timeout; bodySampleLength=\(sample.count)")
        throw OpenAIDashboardUsageError.noDashboardData(sample)
    }

    private static func loadUsagePage(in webView: WKWebView) {
        var request = URLRequest(url: usagePageURL)
        request.setValue(dashboardAcceptLanguage, forHTTPHeaderField: "Accept-Language")
        _ = webView.load(request)
    }

    private static func scrape(webView: WKWebView) async throws -> ScrapeResult {
        let any = try await webView.evaluateJavaScript(scrapeScript)
        guard let dict = any as? [String: Any] else {
            return ScrapeResult()
        }

        var loginRequired = (dict["loginRequired"] as? Bool) ?? false
        let authStatus = (dict["authStatus"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let authStatus, !authStatus.isEmpty, authStatus.lowercased() != "logged_in" {
            loginRequired = true
        }

        return ScrapeResult(
            loginRequired: loginRequired,
            workspacePicker: (dict["workspacePicker"] as? Bool) ?? false,
            cloudflareInterstitial: (dict["cloudflareInterstitial"] as? Bool) ?? false,
            href: dict["href"] as? String,
            bodyText: (dict["bodyText"] as? String) ?? "",
            signedInEmail: (dict["signedInEmail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            accountPlan: (dict["accountPlan"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            creditsPurchaseURL: dict["creditsPurchaseURL"] as? String,
            rows: (dict["rows"] as? [[String]]) ?? [],
            usageBreakdown: (dict["usageBreakdownJSON"] as? String).map(OpenAIDashboardParser.parseUsageBreakdownJSON) ?? [],
            usageBreakdownDebug: dict["usageBreakdownDebug"] as? String,
            usageBreakdownError: dict["usageBreakdownError"] as? String,
            scrollHeight: (dict["scrollHeight"] as? NSNumber)?.doubleValue ?? 0,
            viewportHeight: (dict["viewportHeight"] as? NSNumber)?.doubleValue ?? 0,
            creditsHeaderPresent: (dict["creditsHeaderPresent"] as? Bool) ?? false,
            creditsHeaderInViewport: (dict["creditsHeaderInViewport"] as? Bool) ?? false,
            didScrollToCredits: (dict["didScrollToCredits"] as? Bool) ?? false)
    }

    private static func debugSample(
        webView: WKWebView,
        bodyText: String,
        fallback: String,
        logger: (@Sendable (String) -> Void)?
    ) async -> String {
        if let artifacts = await dumpDebugArtifacts(webView: webView, bodyText: bodyText, logger: logger) {
            return firstNonEmpty(
                "Debug HTML: \(artifacts.htmlPath)" + (artifacts.textPath.map { "; text: \($0)" } ?? ""),
                fallback) ?? fallback
        }
        return fallback
    }

    private static func dumpDebugArtifacts(
        webView: WKWebView,
        bodyText: String,
        logger: (@Sendable (String) -> Void)?
    ) async -> DebugArtifacts? {
        guard let html = try? await debugHTML(webView: webView), !html.isEmpty else {
            logger?("debug dump skipped: empty HTML")
            return nil
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let dir = FileManager.default.temporaryDirectory
        let htmlURL = dir.appendingPathComponent("codex-openai-dashboard-\(stamp).html")
        do {
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)
        } catch {
            logger?("debug dump failed: \(error.localizedDescription)")
            return nil
        }
        logger?("Dumped HTML: \(htmlURL.path)")

        var textPath: String?
        if !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let textURL = dir.appendingPathComponent("codex-openai-dashboard-\(stamp).txt")
            if (try? bodyText.write(to: textURL, atomically: true, encoding: .utf8)) != nil {
                textPath = textURL.path
                logger?("Dumped text: \(textURL.path)")
            }
        }
        return DebugArtifacts(htmlPath: htmlURL.path, textPath: textPath)
    }

    private static func debugHTML(webView: WKWebView) async throws -> String {
        let any = try await webView.evaluateJavaScript("document.documentElement ? document.documentElement.outerHTML : document.body.innerHTML")
        return (any as? String) ?? ""
    }

    private static func firstNonEmpty(_ candidates: String?...) -> String? {
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed?.isEmpty == false { return trimmed }
        }
        return nil
    }

    private static func makeSnapshot(from scrape: ScrapeResult) -> OpenAIDashboardSnapshot {
        let body = scrape.bodyText
        let rateLimits = OpenAIDashboardParser.parseRateLimits(bodyText: body)
        let codeReviewLimit = OpenAIDashboardParser.parseCodeReviewLimit(bodyText: body)
        let codeReviewRemaining = OpenAIDashboardParser.parseCodeReviewRemainingPercent(bodyText: body)
        let creditsRemaining = OpenAIDashboardParser.parseCreditsRemaining(bodyText: body)
        let events = OpenAIDashboardParser.parseCreditEvents(rows: scrape.rows)
        return OpenAIDashboardSnapshot(
            signedInEmail: scrape.signedInEmail,
            codeReviewRemainingPercent: codeReviewRemaining,
            codeReviewLimit: codeReviewLimit,
            creditEvents: events,
            dailyBreakdown: OpenAIDashboardSnapshot.makeDailyBreakdown(from: events, maxDays: 30),
            usageBreakdown: scrape.usageBreakdown,
            creditsPurchaseURL: scrape.creditsPurchaseURL,
            primaryLimit: rateLimits.primary,
            secondaryLimit: rateLimits.secondary,
            creditsRemaining: creditsRemaining,
            accountPlan: scrape.accountPlan,
            updatedAt: Date())
    }

    private static func shouldReloadUsageRoute(_ scrape: ScrapeResult) -> Bool {
        guard !scrape.workspacePicker, !scrape.loginRequired, !scrape.cloudflareInterstitial else { return false }
        guard let href = scrape.href, !href.isEmpty else { return false }
        let path = (URL(string: href)?.path ?? href).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return !(path.hasSuffix("codex/settings/usage")
            || path.hasSuffix("codex/cloud/settings/usage")
            || path.hasSuffix("codex/settings/analytics")
            || path.hasSuffix("codex/cloud/settings/analytics"))
    }

    private static func statusFlags(for scrape: ScrapeResult) -> String {
        [
            "login=\(scrape.loginRequired)",
            "workspace=\(scrape.workspacePicker)",
            "cloudflare=\(scrape.cloudflareInterstitial)",
            "creditsHeader=\(scrape.creditsHeaderPresent)",
            "creditsInView=\(scrape.creditsHeaderInViewport)",
            "rows=\(scrape.rows.count)",
            "usageBreakdown=\(scrape.usageBreakdown.count)",
            "scroll=\(Int(scrape.viewportHeight))/\(Int(scrape.scrollHeight))",
        ].joined(separator: " ")
    }

    private static func shouldWaitForCreditsHistory(
        now: Date,
        dashboardSignalAt: Date?,
        creditsHeaderVisibleAt: Date?,
        scrape: ScrapeResult
    ) -> Bool {
        if scrape.didScrollToCredits { return true }
        if scrape.creditsHeaderPresent, scrape.creditsHeaderInViewport {
            guard let creditsHeaderVisibleAt else { return true }
            return now.timeIntervalSince(creditsHeaderVisibleAt) < 2.5
        }
        if let dashboardSignalAt {
            return now.timeIntervalSince(dashboardSignalAt) < 6.5
        }
        return false
    }

    struct UsageBreakdownRecoveryContext {
        let now: Date
        let errorFirstSeenAt: Date?
    }

    static func shouldWaitForUsageBreakdownRecovery(_ context: UsageBreakdownRecoveryContext) -> Bool {
        guard let errorFirstSeenAt = context.errorFirstSeenAt else { return true }
        return context.now.timeIntervalSince(errorFirstSeenAt) < 4.0
    }

    private static func updateUsageBreakdownErrorState(
        usageBreakdown: [OpenAIDashboardDailyBreakdown],
        error: String?,
        firstSeenAt: inout Date?,
        now: Date = Date()
    ) {
        guard usageBreakdown.isEmpty,
              let error = error?.trimmingCharacters(in: .whitespacesAndNewlines),
              !error.isEmpty
        else {
            firstSeenAt = nil
            return
        }
        if firstSeenAt == nil { firstSeenAt = now }
    }

    private struct ScrapeResult {
        var loginRequired = false
        var workspacePicker = false
        var cloudflareInterstitial = false
        var href: String?
        var bodyText = ""
        var signedInEmail: String?
        var accountPlan: String?
        var creditsPurchaseURL: String?
        var rows: [[String]] = []
        var usageBreakdown: [OpenAIDashboardDailyBreakdown] = []
        var usageBreakdownDebug: String?
        var usageBreakdownError: String?
        var scrollHeight: Double = 0
        var viewportHeight: Double = 0
        var creditsHeaderPresent = false
        var creditsHeaderInViewport = false
        var didScrollToCredits = false
    }

    private struct DebugArtifacts {
        let htmlPath: String
        let textPath: String?
    }

    private static let scrapeScript = #"""
    (() => {
      const textOf = el => {
        const raw = el && (el.innerText || el.textContent) ? String(el.innerText || el.textContent) : '';
        return raw.trim();
      };
      const parseJSONScript = (id) => {
        try {
          const node = document.getElementById(id);
          const raw = node && node.textContent ? String(node.textContent) : '';
          return raw ? JSON.parse(raw) : null;
        } catch { return null; }
      };
      const findFirstEmail = (root) => {
        const queue = [root];
        let seen = 0;
        while (queue.length && seen < 3000) {
          const cur = queue.shift();
          seen++;
          if (!cur) continue;
          if (typeof cur === 'string') {
            const found = cur.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i);
            if (found) return found[0].toLowerCase();
            continue;
          }
          if (typeof cur !== 'object') continue;
          if (Array.isArray(cur)) {
            for (const item of cur) queue.push(item);
          } else {
            for (const [key, value] of Object.entries(cur)) {
              if (key.toLowerCase() === 'email' && typeof value === 'string' && value.includes('@')) {
                return value.trim().toLowerCase();
              }
              if (value && typeof value === 'object') queue.push(value);
              if (typeof value === 'string' && value.includes('@')) queue.push(value);
            }
          }
        }
        return null;
      };
      const cleanPlanName = raw => String(raw || '')
        .replace(/\b(claude|codex|account|plan)\b/gi, ' ')
        .replace(/[_-]/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
      const normalizePlanValue = (value) => {
        const trimmed = String(value || '').trim();
        if (!trimmed) return null;
        const lower = trimmed.toLowerCase();
        const allowed = ['free','plus','pro','team','enterprise','business','edu','education','gov','premium','essential'];
        if (!allowed.some(token => lower.includes(token))) return null;
        const cleaned = cleanPlanName(trimmed);
        return cleaned ? cleaned.split(' ').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ') : trimmed;
      };
      const findPlan = (root) => {
        if (!root || typeof root !== 'object') return null;
        const queue = [root];
        const seenObjects = typeof WeakSet !== 'undefined' ? new WeakSet() : null;
        let seen = 0;
        while (queue.length && seen < 6000) {
          const cur = queue.shift();
          seen++;
          if (!cur || typeof cur !== 'object') continue;
          if (seenObjects) {
            if (seenObjects.has(cur)) continue;
            seenObjects.add(cur);
          }
          for (const [key, value] of Object.entries(cur)) {
            const lower = key.toLowerCase();
            if (lower.includes('plan') || lower.includes('tier') || lower.includes('subscription')) {
              const direct = typeof value === 'string' ? normalizePlanValue(value) : null;
              const nested = value && typeof value === 'object'
                ? (normalizePlanValue(value.name) || normalizePlanValue(value.displayName) || normalizePlanValue(value.tier))
                : null;
              if (direct || nested) return direct || nested;
            }
            if (value && typeof value === 'object') queue.push(value);
          }
        }
        return null;
      };
      const reactPropsOf = (el) => {
        if (!el) return null;
        try {
          const keys = Object.keys(el);
          const propsKey = keys.find(k => k.startsWith('__reactProps$'));
          if (propsKey) return el[propsKey] || null;
          const fiberKey = keys.find(k => k.startsWith('__reactFiber$'));
          if (fiberKey) {
            const fiber = el[fiberKey];
            return (fiber && (fiber.memoizedProps || fiber.pendingProps)) || null;
          }
        } catch {}
        return null;
      };
      const reactFiberOf = (el) => {
        if (!el) return null;
        try {
          const key = Object.keys(el).find(k => k.startsWith('__reactFiber$'));
          return key ? el[key] : null;
        } catch { return null; }
      };
      const nestedBarMetaOf = (root) => {
        if (!root || typeof root !== 'object') return null;
        const queue = [root];
        const seen = typeof WeakSet !== 'undefined' ? new WeakSet() : null;
        let steps = 0;
        while (queue.length && steps < 250) {
          const cur = queue.shift();
          steps++;
          if (!cur || typeof cur !== 'object') continue;
          if (seen) {
            if (seen.has(cur)) continue;
            seen.add(cur);
          }
          if (cur.payload && (cur.dataKey || cur.name || cur.value !== undefined)) return cur;
          const values = Array.isArray(cur) ? cur : Object.values(cur);
          for (const value of values) {
            if (value && typeof value === 'object') queue.push(value);
          }
        }
        return null;
      };
      const barMetaFromElement = (el) => {
        const direct = reactPropsOf(el);
        if (direct && direct.payload && (direct.dataKey || direct.name || direct.value !== undefined)) return direct;
        const fiber = reactFiberOf(el);
        if (fiber) {
          let cur = fiber;
          for (let i = 0; i < 10 && cur; i++) {
            const props = (cur.memoizedProps || cur.pendingProps) || null;
            if (props && props.payload && (props.dataKey || props.name || props.value !== undefined)) return props;
            const nested = props ? nestedBarMetaOf(props) : null;
            if (nested) return nested;
            cur = cur.return || null;
          }
        }
        return direct ? nestedBarMetaOf(direct) : null;
      };
      const localDayKeyForDate = (date) => {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
      };
      const dayKeyFromPayload = (payload) => {
        if (!payload || typeof payload !== 'object') return null;
        for (const key of ['day','date','name','label','x','time','timestamp']) {
          const value = payload[key];
          if (typeof value === 'string') {
            const trimmed = value.trim();
            if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return trimmed;
            const iso = trimmed.match(/^(\d{4}-\d{2}-\d{2})/);
            if (iso) return iso[1];
          }
          if (typeof value === 'number' && Number.isFinite(value)) {
            const date = new Date(value);
            if (!isNaN(date.getTime())) return localDayKeyForDate(date);
          }
        }
        return null;
      };
      const isSkillUsageServiceKey = raw => String(raw || '').trim().toLowerCase().startsWith('skillusage:');
      const displayNameForUsageServiceKey = (raw) => {
        const key = String(raw || '').trim();
        if (!key || isSkillUsageServiceKey(key)) return null;
        const lower = key.toLowerCase();
        if (lower === 'cli') return 'CLI';
        if (lower === 'desktop') return 'Desktop';
        if (lower === 'vscode' || lower === 'vs code') return 'VS Code';
        if (lower.includes('github') && lower.includes('review')) return 'GitHub Code Review';
        if (key.toUpperCase() === key && key.length <= 6) return key;
        return lower.replace(/[_-]+/g, ' ').split(' ').filter(Boolean)
          .map(w => w.length <= 2 ? w.toUpperCase() : w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
      };
      const parseHexColor = (color) => {
        if (!color) return null;
        const c = String(color).trim().toLowerCase();
        if (c.startsWith('#')) return c.length === 4 ? '#' + c[1] + c[1] + c[2] + c[2] + c[3] + c[3] : c;
        const m = c.match(/^rgba?\(([^)]+)\)$/);
        if (!m) return c;
        const parts = m[1].split(',').map(x => parseFloat(x.trim())).filter(Number.isFinite);
        if (parts.length < 3) return c;
        const toHex = n => Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, '0');
        return '#' + toHex(parts[0]) + toHex(parts[1]) + toHex(parts[2]);
      };
      const usageChartRootForPath = path =>
        (path && path.closest && (path.closest('.recharts-wrapper') || path.closest('svg.recharts-surface') || path.closest('section'))) ||
        (path && path.parentElement) ||
        null;
      const usageBreakdownTitleScore = (title) => {
        const lower = String(title || '').trim().toLowerCase().replace(/\s+/g, ' ');
        if (lower === 'usage breakdown') return 1000000;
        if (lower.includes('usage breakdown')) return 900000;
        if (lower === 'personal usage') return 800000;
        if (lower.includes('threads') || lower.includes('turns') || lower.includes('client') ||
          lower.includes('skill') || lower.includes('invocation')) return -1000000;
        return 0;
      };
      const nearestChartTitleTextForRoot = (root) => {
        try {
          let ancestor = root && root.parentElement;
          for (let depth = 0; depth < 8 && ancestor; depth++) {
            const titles = Array.from(ancestor.querySelectorAll('h1,h2,h3,[role="heading"],div,span,p'))
              .filter(el => {
                const title = textOf(el);
                return title.length > 0 && title.length <= 80 && usageBreakdownTitleScore(title) !== 0 &&
                  Boolean(el.compareDocumentPosition(root) & Node.DOCUMENT_POSITION_FOLLOWING);
              });
            const best = titles.sort((a, b) => usageBreakdownTitleScore(textOf(b)) - usageBreakdownTitleScore(textOf(a)))[0];
            if (best) return textOf(best);
            ancestor = ancestor.parentElement;
          }
        } catch {}
        return '';
      };
      const legendMapForUsageChartRoot = (root) => {
        const legend = {};
        for (const scope of [root, root && root.parentElement, root && root.closest && root.closest('section')].filter(Boolean)) {
          for (const item of Array.from(scope.querySelectorAll('div[title]'))) {
            const title = String(item.getAttribute('title') || '').trim();
            const square = item.querySelector('div[style*="background-color"]');
            const color = parseHexColor(square && square.style ? square.style.backgroundColor : null);
            if (title && color) legend[color] = title;
          }
          if (Object.keys(legend).length > 0) break;
        }
        return legend;
      };
      const usageBreakdownJSON = (() => {
        try {
          if (window.__codexbarUsageBreakdownJSON) return window.__codexbarUsageBreakdownJSON;
          const paths = Array.from(document.querySelectorAll('g.recharts-bar-rectangle path.recharts-rectangle'));
          const roots = [];
          for (const path of paths) {
            const root = usageChartRootForPath(path);
            if (root && !roots.includes(root)) roots.push(root);
          }
          const candidates = roots.map(root => {
            const totalsByDay = {};
            const legend = legendMapForUsageChartRoot(root);
            const addValue = (day, service, value) => {
              if (!day || !service || isSkillUsageServiceKey(service)) return;
              const numeric = typeof value === 'number' ? value : parseFloat(String(value || '').replace(/,/g, ''));
              if (!Number.isFinite(numeric) || numeric <= 0) return;
              totalsByDay[day] = totalsByDay[day] || {};
              totalsByDay[day][service] = (totalsByDay[day][service] || 0) + numeric;
            };
            for (const path of paths.filter(path => usageChartRootForPath(path) === root)) {
              const meta = barMetaFromElement(path) || barMetaFromElement(path.parentElement);
              if (!meta) continue;
              const payload = meta.payload || null;
              const day = dayKeyFromPayload(payload);
              if (!day) continue;
              const values = payload && payload.values && typeof payload.values === 'object' ? payload.values : null;
              if (values) {
                for (const [key, value] of Object.entries(values)) {
                  addValue(day, displayNameForUsageServiceKey(key), value);
                }
                continue;
              }
              const fill = parseHexColor(meta.fill || path.getAttribute('fill'));
              addValue(day, (fill && legend[fill]) || displayNameForUsageServiceKey(meta.name || meta.dataKey), meta.value);
            }
            const breakdown = Object.keys(totalsByDay).sort((a, b) => b.localeCompare(a)).slice(0, 30).map(day => {
              const services = Object.keys(totalsByDay[day]).map(service => ({
                service,
                creditsUsed: totalsByDay[day][service]
              })).sort((a, b) => b.creditsUsed - a.creditsUsed || a.service.localeCompare(b.service));
              return {
                day,
                services,
                totalCreditsUsed: services.reduce((sum, item) => sum + (Number(item.creditsUsed) || 0), 0)
              };
            }).filter(day => day.totalCreditsUsed > 0);
            const title = nearestChartTitleTextForRoot(root);
            const titleScore = usageBreakdownTitleScore(title);
            return { breakdown, title, score: titleScore + breakdown.length * 1000 };
          }).filter(candidate => candidate.breakdown.length > 0 && usageBreakdownTitleScore(candidate.title) > 0)
            .sort((a, b) => b.score - a.score);
          const json = candidates[0] ? JSON.stringify(candidates[0].breakdown) : null;
          window.__codexbarUsageBreakdownJSON = json;
          window.__codexbarUsageBreakdownDebug = json ? null : JSON.stringify({
            pathCount: paths.length,
            chartCount: roots.length,
            error: paths.length > 0 ? 'No English usage breakdown chart title found.' : 'No Recharts usage bars found.'
          });
          return json;
        } catch (error) {
          window.__codexbarUsageBreakdownDebug = JSON.stringify({ error: String(error && error.message || error) });
          return null;
        }
      })();
      const usageBreakdownDebug = window.__codexbarUsageBreakdownDebug || null;
      const usageBreakdownError = (() => {
        try {
          if (!usageBreakdownDebug) return null;
          const parsed = JSON.parse(usageBreakdownDebug);
          return parsed && parsed.error ? String(parsed.error) : null;
        } catch { return null; }
      })();
      const bodyText = document.body ? String(document.body.innerText || '').trim() : '';
      const href = window.location ? String(window.location.href || '') : '';
      const title = document.title ? String(document.title || '') : '';
      const lower = bodyText.toLowerCase();
      const hasAuthInputs = Boolean(document.querySelector('input[type="email"],input[type="password"],input[name="username"]'));
      const loginCTA = lower.includes('sign in') || lower.includes('log in') ||
        lower.includes('continue with google') || lower.includes('continue with apple') ||
        lower.includes('continue with microsoft');
      const loginRequired = href.includes('/auth/') || href.includes('/login') ||
        (hasAuthInputs && loginCTA) || (!hasAuthInputs && loginCTA && href.includes('chatgpt.com'));
      const workspacePicker = bodyText.includes('Select a workspace');
      const cloudflareInterstitial = title.toLowerCase().includes('just a moment') ||
        lower.includes('checking your browser') || lower.includes('cloudflare');
      const scrollHeight = document.documentElement ? (document.documentElement.scrollHeight || 0) : 0;
      const viewportHeight = typeof window.innerHeight === 'number' ? window.innerHeight : 0;

      let rows = [];
      let creditsHeaderPresent = false;
      let creditsHeaderInViewport = false;
      let didScrollToCredits = false;
      try {
        const looksLikeCreditsEventRow = (cells) => {
          if (!cells || cells.length < 3) return false;
          return /\d{4}|\d{1,2}[\/.\-]\d{1,2}/.test(String(cells[0] || '')) && /\d/.test(String(cells[2] || ''));
        };
        const allTableRows = () => Array.from(document.querySelectorAll('tbody tr')).map(tr =>
          Array.from(tr.querySelectorAll('td')).map(td => textOf(td))).filter(looksLikeCreditsEventRow);
        const headings = Array.from(document.querySelectorAll('h1,h2,h3'));
        const header = headings.find(h => textOf(h).toLowerCase() === 'credits usage history');
        if (header) {
          creditsHeaderPresent = true;
          const rect = header.getBoundingClientRect();
          creditsHeaderInViewport = rect.top >= 0 && rect.top <= viewportHeight;
          const container = header.closest('section') || header.parentElement || document;
          const table = container.querySelector('table') || null;
          const scope = table || container;
          rows = Array.from(scope.querySelectorAll('tbody tr')).map(tr =>
            Array.from(tr.querySelectorAll('td')).map(td => textOf(td))).filter(row => row.length >= 3);
          if (rows.length === 0) rows = allTableRows();
          if (rows.length === 0 && !window.__conductorDidScrollToCredits) {
            window.__conductorDidScrollToCredits = true;
            header.scrollIntoView({ block: 'start', inline: 'nearest' });
            if (creditsHeaderInViewport) window.scrollBy(0, Math.max(220, viewportHeight * 0.6));
            didScrollToCredits = true;
          }
        } else if (!window.__conductorDidScrollToCredits && scrollHeight > viewportHeight * 1.5) {
          rows = allTableRows();
          if (rows.length > 0) {
            creditsHeaderPresent = true;
            creditsHeaderInViewport = true;
          } else {
            window.__conductorDidScrollToCredits = true;
            window.scrollTo(0, Math.max(0, scrollHeight - viewportHeight - 40));
            didScrollToCredits = true;
          }
        }
      } catch {}

      const normalizeHref = raw => {
        if (!raw) return null;
        const href = String(raw).trim();
        if (href.startsWith('http://') || href.startsWith('https://')) return href;
        if (href.startsWith('/')) return window.location.origin + href;
        return href ? window.location.origin + '/' + href : null;
      };
      const purchaseTextMatches = text => {
        const lower = String(text || '').trim().toLowerCase();
        return lower.includes('add more') ||
          (lower.includes('credit') && (lower.includes('buy') || lower.includes('add') ||
            lower.includes('purchase') || lower.includes('top up') || lower.includes('top-up')));
      };
      let creditsPurchaseURL = null;
      try {
        for (const node of Array.from(document.querySelectorAll('a, button'))) {
          const label = textOf(node) || node.getAttribute('aria-label') || node.getAttribute('title') || '';
          if (!purchaseTextMatches(label)) continue;
          const anchor = node.tagName && node.tagName.toLowerCase() === 'a' ? node : (node.closest ? node.closest('a') : null);
          const url = normalizeHref(anchor && anchor.getAttribute('href'));
          if (url && /credits|billing|purchase/i.test(url)) {
            creditsPurchaseURL = url;
            break;
          }
        }
      } catch {}

      const clientBootstrap = parseJSONScript('client-bootstrap');
      const nextData = parseJSONScript('__NEXT_DATA__');
      let signedInEmail = null;
      let authStatus = null;
      let accountPlan = null;
      try {
        authStatus = clientBootstrap && typeof clientBootstrap.authStatus === 'string' ? clientBootstrap.authStatus : null;
        signedInEmail = findFirstEmail(clientBootstrap) || findFirstEmail(nextData);
        accountPlan = findPlan(clientBootstrap) || findPlan(nextData);
        if (!signedInEmail) {
          const found = (bodyText.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/ig) || [])
            .map(x => String(x).trim().toLowerCase());
          if (found.length > 0) signedInEmail = Array.from(new Set(found))[0];
        }
      } catch {}

      return {
        loginRequired,
        workspacePicker,
        cloudflareInterstitial,
        href,
        bodyText,
        signedInEmail,
        authStatus,
        accountPlan,
        creditsPurchaseURL,
        rows,
        usageBreakdownJSON,
        usageBreakdownDebug,
        usageBreakdownError,
        scrollY: typeof window.scrollY === 'number' ? window.scrollY : 0,
        scrollHeight,
        viewportHeight,
        creditsHeaderPresent,
        creditsHeaderInViewport,
        didScrollToCredits
      };
    })();
    """#
}
#endif
