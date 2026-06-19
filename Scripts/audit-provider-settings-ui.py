#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit that usage provider configuration capabilities exposed by Core have matching settings UI entry points."
    )
    parser.add_argument(
        "--core",
        default="Sources/ConductorCore/Usage/UsageProviderConfigCapabilities.swift",
        help="Path to UsageProviderConfigCapabilities.swift.",
    )
    parser.add_argument(
        "--ui",
        default="Sources/ConductorApp/UI/UsageProvidersSettingsView.swift",
        help="Path to UsageProvidersSettingsView.swift.",
    )
    parser.add_argument(
        "--catalog",
        default="Sources/ConductorCore/Usage/UsageProviderCatalog.swift",
        help="Path to UsageProviderCatalog.swift.",
    )
    return parser.parse_args()


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def skip_string(text: str, index: int) -> int:
    quote = text[index]
    index += 1
    while index < len(text):
        char = text[index]
        if char == "\\":
            index += 2
            continue
        if char == quote:
            return index + 1
        index += 1
    raise ValueError("unterminated string literal")


def skip_comment(text: str, index: int) -> int:
    if text.startswith("//", index):
        newline = text.find("\n", index + 2)
        return len(text) if newline == -1 else newline + 1
    if text.startswith("/*", index):
        end = text.find("*/", index + 2)
        if end == -1:
            raise ValueError("unterminated block comment")
        return end + 2
    return index


def balanced_range(text: str, start: int, opener: str, closer: str) -> tuple[int, int]:
    if text[start] != opener:
        raise ValueError(f"expected {opener!r} at offset {start}")
    depth = 0
    index = start
    while index < len(text):
        skipped = skip_comment(text, index)
        if skipped != index:
            index = skipped
            continue
        char = text[index]
        if char in ('"', "'"):
            index = skip_string(text, index)
            continue
        if char == opener:
            depth += 1
        elif char == closer:
            depth -= 1
            if depth == 0:
                return start, index
        index += 1
    raise ValueError(f"unterminated {opener}{closer} block")


def assignment_bracket_body(text: str, name: str) -> str:
    marker = f"public static let {name}"
    index = text.find(marker)
    if index == -1:
        raise ValueError(f"Core assignment not found: {name}")
    equals = text.find("=", index)
    start = text.find("[", equals)
    if start == -1:
        raise ValueError(f"Core assignment bracket not found: {name}")
    _, end = balanced_range(text, start, "[", "]")
    return text[start + 1 : end]


def string_dictionary_keys(text: str, name: str) -> set[str]:
    body = assignment_bracket_body(text, name)
    return set(re.findall(r'"([A-Za-z0-9]+)"\s*:', body))


def nested_string_dictionary_keys(text: str, name: str) -> set[str]:
    body = assignment_bracket_body(text, name)
    keys: set[str] = set()
    index = 0
    while index < len(body):
        match = re.search(r'"([A-Za-z0-9]+)"\s*:\s*\[', body[index:])
        if not match:
            break
        provider_start = index + match.start()
        bracket_start = index + match.end() - 1
        _, bracket_end = balanced_range(body, bracket_start, "[", "]")
        provider_body = body[bracket_start + 1 : bracket_end]
        keys.update(re.findall(r'"([A-Za-z0-9]+)"\s*:', provider_body))
        index = bracket_end + 1
    return keys


def nested_string_dictionary_pairs(text: str, name: str) -> set[str]:
    body = assignment_bracket_body(text, name)
    pairs: set[str] = set()
    index = 0
    while index < len(body):
        match = re.search(r'"([A-Za-z0-9]+)"\s*:\s*\[', body[index:])
        if not match:
            break
        provider = match.group(1)
        bracket_start = index + match.end() - 1
        _, bracket_end = balanced_range(body, bracket_start, "[", "]")
        provider_body = body[bracket_start + 1 : bracket_end]
        for key in re.findall(r'"([A-Za-z0-9]+)"\s*:', provider_body):
            pairs.add(f"{provider}.{key}")
        index = bracket_end + 1
    return pairs


def cookie_capability_provider_keys(text: str) -> set[str]:
    providers = string_dictionary_keys(text, "cookieHeaderEnvironmentNames")
    providers.update({"codex", "copilot"})

    marker = "let cookieProviders: [String: String?]"
    index = text.find(marker)
    if index != -1:
        equals = text.find("=", index)
        start = text.find("[", equals)
        if start != -1:
            _, end = balanced_range(text, start, "[", "]")
            providers.update(re.findall(r'"([A-Za-z0-9]+)"\s*:', text[start:end]))

    providers.update(re.findall(
        r'support\["([A-Za-z0-9]+)"\]\s*=\s*UsageProviderTokenAccountSupport\(\s*injection:\s*\.cookieHeader',
        text,
        flags=re.S,
    ))
    return providers


def source_mode_provider_keys(text: str) -> set[str]:
    return string_dictionary_keys(text, "providerSourceModes")


def catalog_provider_keys(text: str) -> set[str]:
    return set(re.findall(r'UsageProviderEntry\(\s*id:\s*"([A-Za-z0-9]+)"', text, flags=re.S))


def ui_catalog_body(text: str) -> str:
    start = text.find("static func catalog(for provider:")
    end = text.find("private static let localCredentialProviders")
    if start == -1 or end == -1 or end <= start:
        raise ValueError("UsageProviderProfile.catalog body not found")
    return text[start:end]


def ui_provider_array_containing(catalog: str, field_marker: str) -> set[str]:
    index = catalog.find(field_marker)
    if index == -1:
        return set()
    before = catalog.rfind("if [", 0, index)
    after = catalog.find("].contains(provider.id)", before)
    if before == -1 or after == -1:
        return set()
    return set(re.findall(r'"([A-Za-z0-9]+)"', catalog[before:after]))


def ui_extra_keys(ui: str) -> set[str]:
    keys = set(re.findall(r'\.extra\("([A-Za-z0-9]+)"\)', ui))
    # These are rendered as toggles backed by extraFlagBinding rather than ProviderTextFieldRow.
    for key in re.findall(r'key:\s*"([A-Za-z0-9]+)"', ui):
        if f"extraFlagBinding(toggle.key" in ui and key == "requireProviderEndpointOverrides":
            keys.add(key)
    return keys


def provider_ids_from_condition(header: str) -> set[str]:
    providers = set(re.findall(r'provider\.id\s*==\s*"([A-Za-z0-9]+)"', header))
    for list_body in re.findall(r'\[([^\]]+)\]\.contains\(provider\.id\)', header):
        providers.update(re.findall(r'"([A-Za-z0-9]+)"', list_body))
    return providers


def ui_extra_pairs(ui: str) -> set[str]:
    pairs: set[str] = set()
    index = 0
    while True:
        index = ui.find("if ", index)
        if index == -1:
            break
        brace = ui.find("{", index)
        if brace == -1:
            break
        header = ui[index:brace]
        providers = provider_ids_from_condition(header)
        try:
            _, end = balanced_range(ui, brace, "{", "}")
        except ValueError:
            break
        if providers:
            body = ui[brace + 1 : end]
            keys = set(re.findall(r'\.extra\("([A-Za-z0-9]+)"\)', body))
            # Some boolean extras are rendered as ProviderToggleDescriptor keys and routed
            # through extraFlagBinding instead of ProviderTextFieldRow.
            if "extraFlagBinding(toggle.key" in ui:
                keys.update(re.findall(r'key:\s*"([A-Za-z0-9]+)"', body))
            for provider in providers:
                for key in keys:
                    pairs.add(f"{provider}.{key}")
        index = end + 1
    return pairs


def has_dynamic_api_key_ui(catalog: str) -> bool:
    return (
        "UsageProviderConfigCapabilities.environmentHints(providerID: provider.id)" in catalog
        and "let envVar = hints.apiKey.first" in catalog
        and "key: .apiKey" in catalog
        and "hints.apiKey.joined" in catalog
    )


def has_dynamic_source_ui(catalog: str) -> bool:
    return "Self.sourceOptions(for: provider)" in catalog and "profile.sourceOptions" in catalog


def has_dynamic_cookie_ui(catalog: str) -> bool:
    return (
        "UsageProviderConfigCapabilities.supportsCookieHeader(provider.id)" in catalog
        and "key: .cookieHeader" in catalog
        and "let cookieOptions: [ProviderOption] = isCookie" in catalog
    )


def has_dynamic_environment_field_ui(catalog: str, hint_name: str, field_marker: str) -> bool:
    return (
        "UsageProviderConfigCapabilities.environmentHints(providerID: provider.id)" in catalog
        and f"if !hints.{hint_name}.isEmpty" in catalog
        and field_marker in catalog
        and f"hints.{hint_name}.joined" in catalog
    )


def missing_environment_field_providers(
    core: str,
    catalog: str,
    capability_name: str,
    hint_name: str,
    field_marker: str,
) -> list[str]:
    providers = string_dictionary_keys(core, capability_name)
    if has_dynamic_environment_field_ui(catalog, hint_name, field_marker):
        return []
    return sorted(providers - ui_provider_array_containing(catalog, field_marker))


def main() -> int:
    args = parse_args()
    core_path = Path(args.core)
    ui_path = Path(args.ui)
    catalog_path = Path(args.catalog)
    core = read(core_path)
    ui = read(ui_path)
    provider_catalog = read(catalog_path)
    catalog = ui_catalog_body(ui)
    catalog_provider_ids = catalog_provider_keys(provider_catalog)
    source_mode_provider_ids = source_mode_provider_keys(provider_catalog)

    missing: dict[str, list[str]] = {
        "apiKeyDynamicUI": [] if has_dynamic_api_key_ui(catalog) else sorted(string_dictionary_keys(core, "apiKeyEnvironmentNames")),
        "sourceModeDynamicUI": [] if has_dynamic_source_ui(ui) else sorted(source_mode_provider_keys(provider_catalog)),
        "sourceModeCatalogCoverage": sorted(catalog_provider_ids - source_mode_provider_ids),
        "sourceModeUnknownProviders": sorted(source_mode_provider_ids - catalog_provider_ids),
        "baseURL": missing_environment_field_providers(
            core, catalog, "baseURLEnvironmentNames", "baseURL", "key: .baseURL"),
        "project": missing_environment_field_providers(
            core, catalog, "projectEnvironmentNames", "project", "key: .projectID"),
        "organization": missing_environment_field_providers(
            core, catalog, "organizationEnvironmentNames", "organization", "key: .organizationID"),
        "cookieDynamicUI": [] if has_dynamic_cookie_ui(catalog) else sorted(cookie_capability_provider_keys(core)),
        "extra": sorted(nested_string_dictionary_pairs(core, "extraEnvironmentNames") - ui_extra_pairs(ui)),
    }

    failures = {key: value for key, value in missing.items() if value}
    if failures:
        print("Provider settings UI audit failed:", file=sys.stderr)
        for category, values in failures.items():
            print(f"  {category}: {', '.join(values)}", file=sys.stderr)
        return 1

    print("Provider settings UI audit passed.")
    print(f"  API key providers: {len(string_dictionary_keys(core, 'apiKeyEnvironmentNames'))}")
    print(f"  Catalog providers: {len(catalog_provider_ids)}")
    print(f"  Source mode providers: {len(source_mode_provider_ids)}")
    print(f"  Base URL providers: {len(string_dictionary_keys(core, 'baseURLEnvironmentNames'))}")
    print(f"  Project providers: {len(string_dictionary_keys(core, 'projectEnvironmentNames'))}")
    print(f"  Organization providers: {len(string_dictionary_keys(core, 'organizationEnvironmentNames'))}")
    print(f"  Cookie capability providers: {len(cookie_capability_provider_keys(core))}")
    print(f"  Extra config keys: {len(nested_string_dictionary_keys(core, 'extraEnvironmentNames'))}")
    print(f"  Extra provider keys: {len(nested_string_dictionary_pairs(core, 'extraEnvironmentNames'))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
