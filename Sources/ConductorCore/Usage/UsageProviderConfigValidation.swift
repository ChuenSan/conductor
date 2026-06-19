import Foundation

public struct ConfigValidationIssue: Codable, Equatable, Sendable {
    public let severity: String
    public let provider: String?
    public let field: String?
    public let code: String
    public let message: String
}

public enum UsageProviderConfigValidator {
    public static func validate(_ config: AppConfig) -> [ConfigValidationIssue] {
        let known = Set(UsageProviderCatalog.all.map(\.id))
        let cookieSources = Set(["auto", "browser", "manual", "off"])
        var issues: [ConfigValidationIssue] = []
        validateProviderAliasList(
            config.usage.providerOrder,
            field: "providerOrder",
            knownProviderIDs: known,
            issues: &issues)
        validateProviderAliasList(
            config.usage.statusBarOverviewProviderIDs,
            field: "statusBarOverviewProviderIDs",
            knownProviderIDs: known,
            issues: &issues)
        validateProviderAliasList(
            config.usage.statusBarOverviewSelectionBasisIDs,
            field: "statusBarOverviewSelectionBasisIDs",
            knownProviderIDs: known,
            issues: &issues)
        for (id, providerConfig) in config.usage.providers.sorted(by: { $0.key < $1.key }) {
            let canonicalID = UsageProviderCatalog.canonicalProviderID(id)
            guard known.contains(id),
                  let entry = UsageProviderCatalog.entry(for: id)
            else {
                let message: String
                if canonicalID != id, known.contains(canonicalID) {
                    message = "Unknown provider alias. Use canonical provider ID `\(canonicalID)` instead of `\(id)` in config."
                } else {
                    message = "Unknown provider. Run `conductorctl config providers` to list valid IDs."
                }
                issues.append(ConfigValidationIssue(
                    severity: "error",
                    provider: id,
                    field: nil,
                    code: "unknown_provider",
                    message: message))
                continue
            }
            let supportsAPI = entry.supportsSourceMode("api")
            let supportsWebCookies = UsageProviderConfigCapabilities.supportsCookieHeader(id)
            let apiKey = nonEmpty(providerConfig.apiKey)
            let sourceMode = nonEmpty(providerConfig.sourceMode)?.lowercased()
            let cookieSource = nonEmpty(providerConfig.cookieSource)?.lowercased()
            let cookieHeader = nonEmpty(providerConfig.cookieHeader)
            let projectID = nonEmpty(providerConfig.projectID)
            let organizationID = nonEmpty(providerConfig.organizationID)

            if apiKey != nil,
               !UsageProviderConfigCapabilities.supportsAPIKey(id)
            {
                issues.append(ConfigValidationIssue(
                    severity: "warning",
                    provider: id,
                    field: "apiKey",
                    code: "api_key_unused",
                    message: "apiKey is set but \(id) does not support api source."))
            }
            if providerConfig.tokenAccounts?.accounts.isEmpty == false,
               !UsageProviderConfigCapabilities.supportsTokenAccounts(id)
            {
                issues.append(ConfigValidationIssue(
                    severity: "warning",
                    provider: id,
                    field: "tokenAccounts",
                    code: "token_accounts_unused",
                    message: "tokenAccounts are set but \(id) does not support token accounts."))
            }
            if projectID != nil,
               !providerSupportsProjectID(id)
            {
                issues.append(ConfigValidationIssue(
                    severity: "warning",
                    provider: id,
                    field: "projectID",
                    code: "workspace_unused",
                    message: "projectID is set but only \(projectIDProviderList) support project/workspace IDs."))
            }
            if organizationID != nil,
               !providerSupportsOrganizationID(id)
            {
                issues.append(ConfigValidationIssue(
                    severity: "warning",
                    provider: id,
                    field: "organizationID",
                    code: "organization_unused",
                    message: "organizationID is set but \(id) does not use organization IDs."))
            }
            if nonEmptyExtra("enterpriseHost", providerConfig) != nil,
               !providerSupportsExtra(id, key: "enterpriseHost")
            {
                issues.append(ConfigValidationIssue(
                    severity: "warning",
                    provider: id,
                    field: "extra.enterpriseHost",
                    code: "enterprise_host_unused",
                    message: "enterpriseHost is set but only \(enterpriseHostProviderList) support enterprise hosts."))
            }
            if nonEmptyExtra("secretKey", providerConfig) != nil {
                issues.append(ConfigValidationIssue(
                    severity: "warning",
                    provider: id,
                    field: "extra.secretKey",
                    code: "secret_key_unused",
                    message: "secretKey is not consumed by Conductor; use extra.awsSecretAccessKey for Bedrock."))
            }
            if nonEmptyExtra("awsSecretAccessKey", providerConfig) != nil,
               id != "bedrock"
            {
                issues.append(ConfigValidationIssue(
                    severity: "warning",
                    provider: id,
                    field: "extra.awsSecretAccessKey",
                    code: "secret_key_unused",
                    message: "awsSecretAccessKey is set but only bedrock uses AWS secret keys."))
            }
            if let region = nonEmptyExtra("region", providerConfig) {
                validateRegion(region, providerID: id, issues: &issues)
            }
            if nonEmptyExtra("awsRegion", providerConfig) != nil,
               id != "bedrock"
            {
                issues.append(ConfigValidationIssue(
                    severity: "warning",
                    provider: id,
                    field: "extra.awsRegion",
                    code: "region_unused",
                    message: "awsRegion is set but only bedrock uses AWS regions."))
            }
            if let source = sourceMode,
               !entry.supportsSourceMode(source)
            {
                issues.append(ConfigValidationIssue(
                    severity: "error",
                    provider: id,
                    field: "sourceMode",
                    code: "unsupported_source",
                    message: "Source \(source) is not supported for \(id). Expected one of: \(entry.sourceModes.joined(separator: ", "))."))
            }
            if sourceMode == "api", !supportsAPI {
                issues.append(ConfigValidationIssue(
                    severity: "error",
                    provider: id,
                    field: "sourceMode",
                    code: "api_source_unsupported",
                    message: "Source api is not supported for \(id)."))
            }
            if sourceMode == "api", apiKey == nil {
                issues.append(ConfigValidationIssue(
                    severity: "warning",
                    provider: id,
                    field: "apiKey",
                    code: "api_key_missing",
                    message: "Source api is selected but apiKey is missing for \(id)."))
            }
            if let source = cookieSource,
               !cookieSources.contains(source)
            {
                issues.append(ConfigValidationIssue(
                    severity: "error",
                    provider: id,
                    field: "cookieSource",
                    code: "invalid_cookie_source",
                    message: "Expected one of: \(cookieSources.sorted().joined(separator: ", "))."))
            }
            if cookieSource != nil, !supportsWebCookies {
                issues.append(ConfigValidationIssue(
                    severity: "warning",
                    provider: id,
                    field: "cookieSource",
                    code: "cookie_source_unused",
                    message: "cookieSource is set but \(id) does not use web cookies."))
            }
            if cookieHeader != nil, !supportsWebCookies {
                issues.append(ConfigValidationIssue(
                    severity: "warning",
                    provider: id,
                    field: "cookieHeader",
                    code: "cookie_header_unused",
                    message: "cookieHeader is set but \(id) does not use web cookies."))
            }
            if cookieSource == "manual", cookieHeader == nil {
                issues.append(ConfigValidationIssue(
                    severity: "warning",
                    provider: id,
                    field: "cookieHeader",
                    code: "cookie_header_missing",
                    message: "cookieSource manual is set but cookieHeader is missing for \(id)."))
            }
            if let rawURL = providerConfig.baseURL,
               !isValidBaseURL(rawURL)
            {
                issues.append(ConfigValidationIssue(
                    severity: "error",
                    provider: id,
                    field: "baseURL",
                    code: "invalid_base_url",
                    message: "Expected an http or https URL with a host."))
            }
            if id == "minimax" {
                validateMiniMaxEndpointOverrides(providerConfig, issues: &issues)
            } else if id == "qwen" {
                validateQwenEndpointOverrides(providerConfig, issues: &issues)
            } else if id == "alibabatokenplan" {
                validateAlibabaTokenPlanEndpointOverrides(providerConfig, issues: &issues)
            }
        }
        return issues
    }

    public static func issues(
        for providerID: String,
        in config: AppConfig
    ) -> [ConfigValidationIssue] {
        validate(config).filter { $0.provider == providerID }
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func nonEmptyExtra(_ key: String, _ config: UsageProviderConfig) -> String? {
        nonEmpty(config.extra[key])
    }

    private static func providerSupportsProjectID(_ providerID: String) -> Bool {
        !(UsageProviderConfigCapabilities.projectEnvironmentNames[providerID] ?? []).isEmpty
    }

    private static func providerSupportsOrganizationID(_ providerID: String) -> Bool {
        !(UsageProviderConfigCapabilities.organizationEnvironmentNames[providerID] ?? []).isEmpty
    }

    private static func providerSupportsExtra(_ providerID: String, key: String) -> Bool {
        UsageProviderConfigCapabilities.extraEnvironmentNames[providerID]?[key]?.isEmpty == false
    }

    private static var projectIDProviderList: String {
        formattedProviderList(UsageProviderConfigCapabilities.projectEnvironmentNames.keys.sorted())
    }

    private static var enterpriseHostProviderList: String {
        let providers = UsageProviderConfigCapabilities.extraEnvironmentNames
            .filter { $0.value["enterpriseHost"]?.isEmpty == false }
            .map(\.key)
            .sorted()
        return formattedProviderList(providers)
    }

    private static func formattedProviderList(_ providers: [String]) -> String {
        guard let last = providers.last else { return "no providers" }
        guard providers.count > 1 else { return last }
        return "\(providers.dropLast().joined(separator: ", ")), and \(last)"
    }

    private static func validateProviderAliasList(
        _ providerIDs: [String],
        field: String,
        knownProviderIDs: Set<String>,
        issues: inout [ConfigValidationIssue]
    ) {
        for raw in providerIDs {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !id.isEmpty else { continue }
            let canonicalID = UsageProviderCatalog.canonicalProviderID(id)
            if canonicalID == id || !knownProviderIDs.contains(canonicalID) {
                guard !knownProviderIDs.contains(id) else { continue }
                issues.append(ConfigValidationIssue(
                    severity: "warning",
                    provider: nil,
                    field: field,
                    code: "unknown_provider_in_list",
                    message: "\(field) contains unknown provider `\(id)` and it will be ignored. Run `conductorctl config providers` to list valid IDs."))
                continue
            }
            issues.append(ConfigValidationIssue(
                severity: "warning",
                provider: nil,
                field: field,
                code: "provider_alias_in_list",
                message: "\(field) contains provider alias `\(id)`; use canonical provider ID `\(canonicalID)` instead."))
        }
    }

    private static func validateRegion(
        _ region: String,
        providerID: String,
        issues: inout [ConfigValidationIssue]
    ) {
        switch providerID {
        case "glm":
            guard ["global", "bigmodel-cn"].contains(region.lowercased()) else {
                issues.append(ConfigValidationIssue(
                    severity: "error",
                    provider: providerID,
                    field: "extra.region",
                    code: "invalid_region",
                    message: "Region \(region) is not a valid z.ai region."))
                return
            }
        case "minimax":
            guard ["global", "cn"].contains(region.lowercased()) else {
                issues.append(ConfigValidationIssue(
                    severity: "error",
                    provider: providerID,
                    field: "extra.region",
                    code: "invalid_region",
                    message: "Region \(region) is not a valid MiniMax region."))
                return
            }
        case "moonshot":
            guard ["international", "china"].contains(region.lowercased()) else {
                issues.append(ConfigValidationIssue(
                    severity: "error",
                    provider: providerID,
                    field: "extra.region",
                    code: "invalid_region",
                    message: "Region \(region) is not a valid Moonshot region."))
                return
            }
        case "qwen":
            guard ["intl", "cn"].contains(region.lowercased()) else {
                issues.append(ConfigValidationIssue(
                    severity: "error",
                    provider: providerID,
                    field: "extra.region",
                    code: "invalid_region",
                    message: "Region \(region) is not a valid Alibaba Coding Plan region."))
                return
            }
        default:
            issues.append(ConfigValidationIssue(
                severity: "warning",
                provider: providerID,
                field: "extra.region",
                code: "region_unused",
                message: "region is set but \(providerID) does not use regions."))
        }
    }

    private static func isValidBaseURL(_ raw: String) -> Bool {
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false
        else { return false }
        return true
    }

    private static func validateQwenEndpointOverrides(
        _ config: UsageProviderConfig,
        issues: inout [ConfigValidationIssue]
    ) {
        if let baseURL = nonEmpty(config.baseURL),
           isValidBaseURL(baseURL),
           QwenUsageFetcher.normalizedHTTPSURL(from: baseURL) == nil
        {
            issues.append(ConfigValidationIssue(
                severity: "error",
                provider: "qwen",
                field: "baseURL",
                code: "invalid_endpoint_override",
                message: "Alibaba Coding Plan host override must be HTTPS and must not include user info."))
        }
        if let quotaURL = nonEmptyExtra("quotaURL", config),
           QwenUsageFetcher.normalizedHTTPSURL(from: quotaURL) == nil
        {
            issues.append(ConfigValidationIssue(
                severity: "error",
                provider: "qwen",
                field: "extra.quotaURL",
                code: "invalid_endpoint_override",
                message: "Alibaba Coding Plan quotaURL override must be HTTPS and must not include user info."))
        }
    }

    private static func validateAlibabaTokenPlanEndpointOverrides(
        _ config: UsageProviderConfig,
        issues: inout [ConfigValidationIssue]
    ) {
        if let baseURL = nonEmpty(config.baseURL),
           isValidBaseURL(baseURL),
           AlibabaTokenPlanUsageFetcher.normalizedHTTPSURL(from: baseURL) == nil
        {
            issues.append(ConfigValidationIssue(
                severity: "error",
                provider: "alibabatokenplan",
                field: "baseURL",
                code: "invalid_endpoint_override",
                message: "Alibaba Token Plan host override must be HTTPS and must not include user info."))
        }
        if let quotaURL = nonEmptyExtra("quotaURL", config),
           AlibabaTokenPlanUsageFetcher.normalizedHTTPSURL(from: quotaURL) == nil
        {
            issues.append(ConfigValidationIssue(
                severity: "error",
                provider: "alibabatokenplan",
                field: "extra.quotaURL",
                code: "invalid_endpoint_override",
                message: "Alibaba Token Plan quotaURL override must be HTTPS and must not include user info."))
        }
    }

    private static func validateMiniMaxEndpointOverrides(
        _ config: UsageProviderConfig,
        issues: inout [ConfigValidationIssue]
    ) {
        var env: [String: String] = [:]
        if let strict = nonEmptyExtra("requireProviderEndpointOverrides", config) {
            env["MINIMAX_REQUIRE_PROVIDER_ENDPOINT_OVERRIDES"] = strict
        }
        if let baseURL = nonEmpty(config.baseURL),
           isValidBaseURL(baseURL)
        {
            let isAllowed = MiniMaxUsageFetcher.normalizedHTTPSURL(from: baseURL)
                .map { MiniMaxUsageFetcher.isAllowedEndpointOverride($0, env: env) } ?? false
            if !isAllowed {
                issues.append(ConfigValidationIssue(
                    severity: "error",
                    provider: "minimax",
                    field: "baseURL",
                    code: "invalid_endpoint_override",
                    message: "MiniMax host override must be HTTPS, must not include user info, and must be MiniMax-owned when strict mode is enabled."))
            }
        }
        if let remainsURL = nonEmptyExtra("remainsURL", config) {
            let isAllowed = MiniMaxUsageFetcher.normalizedHTTPSURL(from: remainsURL)
                .map { MiniMaxUsageFetcher.isAllowedEndpointOverride($0, env: env) } ?? false
            if !isAllowed {
                issues.append(ConfigValidationIssue(
                    severity: "error",
                    provider: "minimax",
                    field: "extra.remainsURL",
                    code: "invalid_endpoint_override",
                    message: "MiniMax remainsURL override must be HTTPS, must not include user info, and must be MiniMax-owned when strict mode is enabled."))
            }
        }
        if let codingPlanURL = nonEmptyExtra("codingPlanURL", config) {
            let isAllowed = MiniMaxUsageFetcher.normalizedHTTPSURL(from: codingPlanURL)
                .map { MiniMaxUsageFetcher.isAllowedEndpointOverride($0, env: env) } ?? false
            if !isAllowed {
                issues.append(ConfigValidationIssue(
                    severity: "error",
                    provider: "minimax",
                    field: "extra.codingPlanURL",
                    code: "invalid_endpoint_override",
                    message: "MiniMax codingPlanURL override must be HTTPS, must not include user info, and must be MiniMax-owned when strict mode is enabled."))
            }
        }
        if let billingHistoryURL = nonEmptyExtra("billingHistoryURL", config) {
            let isAllowed = MiniMaxUsageFetcher.normalizedHTTPSURL(from: billingHistoryURL)
                .map { MiniMaxUsageFetcher.isAllowedEndpointOverride($0, env: env) } ?? false
            if !isAllowed {
                issues.append(ConfigValidationIssue(
                    severity: "error",
                    provider: "minimax",
                    field: "extra.billingHistoryURL",
                    code: "invalid_endpoint_override",
                    message: "MiniMax billingHistoryURL override must be HTTPS, must not include user info, and must be MiniMax-owned when strict mode is enabled."))
            }
        }
    }
}
