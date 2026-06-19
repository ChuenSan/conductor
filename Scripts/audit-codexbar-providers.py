#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ast
import re
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare Conductor's usage provider catalog against CodexBar provider registry."
    )
    parser.add_argument(
        "--codexbar",
        default="/tmp/codexbar-audit",
        help="Path to the CodexBar checkout.",
    )
    parser.add_argument(
        "--conductor",
        default="Sources/ConductorCore/Usage/UsageProviderCatalog.swift",
        help="Path to Conductor's UsageProviderCatalog.swift.",
    )
    parser.add_argument(
        "--capabilities",
        default="Sources/ConductorCore/Usage/UsageProviderConfigCapabilities.swift",
        help="Path to Conductor's UsageProviderConfigCapabilities.swift.",
    )
    return parser.parse_args()


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def resolve_codexbar_root(path_value: str) -> Path:
    root = Path(path_value)
    if (root / "Sources/CodexBarCore/Providers/Providers.swift").is_file():
        return root
    raise FileNotFoundError(f"CodexBar checkout not found: {root}")


def enum_cases(text: str, enum_name: str) -> list[str]:
    match = re.search(
        rf"public enum {re.escape(enum_name)}:[^{{]+{{(?P<body>.*?)\n}}",
        text,
        flags=re.S,
    )
    if not match:
        raise ValueError(f"enum not found: {enum_name}")
    body = match.group("body")
    return re.findall(r"^\s*case\s+([A-Za-z0-9_]+)\b", body, flags=re.M)


def matching_close(text: str, open_index: int, open_char: str = "(", close_char: str = ")") -> int:
    depth = 0
    in_string = False
    escaped = False
    for index in range(open_index, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == open_char:
            depth += 1
        elif char == close_char:
            depth -= 1
            if depth == 0:
                return index
    raise ValueError(f"unbalanced {open_char}{close_char} block")


def call_bodies(text: str, marker: str) -> list[str]:
    bodies: list[str] = []
    start = 0
    while True:
        index = text.find(marker, start)
        if index == -1:
            break
        open_index = index + len(marker) - 1
        close_index = matching_close(text, open_index)
        bodies.append(text[open_index + 1 : close_index])
        start = close_index + 1
    return bodies


def split_top_level_arguments(body: str) -> list[str]:
    arguments: list[str] = []
    stack: list[str] = []
    start = 0
    in_string = False
    escaped = False
    opens = {"(": ")", "[": "]", "{": "}"}
    closes = {")": "(", "]": "[", "}": "{"}
    for index, char in enumerate(body):
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char in opens:
            stack.append(char)
        elif char in closes and stack:
            stack.pop()
        elif char == "," and not stack:
            argument = body[start:index].strip()
            if argument:
                arguments.append(argument)
            start = index + 1
    tail = body[start:].strip()
    if tail:
        arguments.append(tail)
    return arguments


def top_level_colon(argument: str) -> int:
    stack: list[str] = []
    in_string = False
    escaped = False
    for index, char in enumerate(argument):
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char in "([{":
            stack.append(char)
        elif char in ")]}" and stack:
            stack.pop()
        elif char == ":" and not stack:
            return index
    return -1


def named_arguments(body: str) -> dict[str, str]:
    arguments: dict[str, str] = {}
    for argument in split_top_level_arguments(body):
        colon = top_level_colon(argument)
        if colon <= 0:
            continue
        arguments[argument[:colon].strip()] = argument[colon + 1 :].strip()
    return arguments


COMPUTED_STRING_VALUES = {
    "AlibabaCodingPlanAPIRegion.international.dashboardURL.absoluteString":
        "https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan#/efm/coding_plan",
    "AlibabaTokenPlanUsageFetcher.dashboardURL.absoluteString":
        "https://bailian.console.aliyun.com/cn-beijing?tab=plan#/efm/subscription/token-plan",
    "ZaiAPIRegion.global.dashboardURL.absoluteString":
        "https://z.ai/manage-apikey/coding-plan/personal/my-plan",
    "CopilotUsageFetcher.tokenEnvironmentKey": "COPILOT_API_TOKEN",
    "CopilotUsageFetcher.enterpriseHostEnvironmentKey": "COPILOT_ENTERPRISE_HOST",
}


def swift_value(expression: str | None, default: object | None = None) -> object | None:
    if expression is None:
        return default
    expression = expression.strip()
    if expression == "nil":
        return None
    if expression == "true":
        return True
    if expression == "false":
        return False
    if expression in COMPUTED_STRING_VALUES:
        return COMPUTED_STRING_VALUES[expression]
    if expression.startswith('"') and expression.endswith('"'):
        return ast.literal_eval(expression)
    return f"<unsupported:{expression}>"


def swift_string_constants(text: str) -> dict[str, str]:
    constants: dict[str, str] = {}
    for name, value in re.findall(
        r"(?:public|private|internal)?\s*static let\s+([A-Za-z0-9_]+)\s*(?::[^=]+)?=\s*(\"(?:\\.|[^\"])*\")",
        text,
    ):
        constants[name] = ast.literal_eval(value)
    return constants


def swift_string_value(expression: str, constants: dict[str, str] | None = None) -> str:
    expression = expression.strip()
    if expression.startswith('"') and expression.endswith('"'):
        return ast.literal_eval(expression)
    if expression in COMPUTED_STRING_VALUES:
        value = COMPUTED_STRING_VALUES[expression]
        if isinstance(value, str):
            return value
    if constants is not None and expression.startswith("Self."):
        name = expression.removeprefix("Self.").strip()
        if name in constants:
            return constants[name]
    raise ValueError(f"unsupported Swift string expression: {expression}")


def swift_string_array_literal(expression: str, constants: dict[str, str] | None = None) -> list[str]:
    expression = expression.strip()
    if not expression.startswith("["):
        raise ValueError(f"expected Swift string array literal, got: {expression}")
    close_index = matching_close(expression, 0, "[", "]")
    body = expression[1:close_index]
    return [swift_string_value(item, constants) for item in split_top_level_arguments(body)]


def swift_static_string_array(text: str, name: str) -> list[str]:
    match = re.search(rf"static let\s+{re.escape(name)}\s*(?::[^=]+)?=\s*\[", text)
    if not match:
        raise ValueError(f"Swift string array not found: {name}")
    open_index = match.end() - 1
    body = text[open_index : matching_close(text, open_index, "[", "]") + 1]
    return swift_string_array_literal(body, swift_string_constants(text))


def swift_static_dict_body(text: str, name: str) -> str:
    match = re.search(rf"public static let\s+{re.escape(name)}\s*:[^=]+=\s*\[", text)
    if not match:
        raise ValueError(f"Swift dictionary not found: {name}")
    open_index = match.end() - 1
    return text[open_index + 1 : matching_close(text, open_index, "[", "]")]


def swift_string_dict(text: str, name: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for entry in split_top_level_arguments(swift_static_dict_body(text, name)):
        colon = top_level_colon(entry)
        if colon <= 0:
            continue
        key = swift_string_value(entry[:colon])
        values[key] = swift_string_value(entry[colon + 1 :])
    return values


def swift_string_array_dict(text: str, name: str) -> dict[str, list[str]]:
    values: dict[str, list[str]] = {}
    for entry in split_top_level_arguments(swift_static_dict_body(text, name)):
        colon = top_level_colon(entry)
        if colon <= 0:
            continue
        key = swift_string_value(entry[:colon])
        values[key] = swift_string_array_literal(entry[colon + 1 :])
    return values


def swift_nested_string_array_dict(text: str, name: str) -> dict[str, dict[str, list[str]]]:
    values: dict[str, dict[str, list[str]]] = {}
    for entry in split_top_level_arguments(swift_static_dict_body(text, name)):
        colon = top_level_colon(entry)
        if colon <= 0:
            continue
        provider = swift_string_value(entry[:colon])
        nested_expression = entry[colon + 1 :].strip()
        if not nested_expression.startswith("["):
            raise ValueError(f"expected nested Swift dictionary for {provider}, got: {nested_expression}")
        close_index = matching_close(nested_expression, 0, "[", "]")
        nested_body = nested_expression[1:close_index]
        nested_values: dict[str, list[str]] = {}
        for nested_entry in split_top_level_arguments(nested_body):
            nested_colon = top_level_colon(nested_entry)
            if nested_colon <= 0:
                continue
            key = swift_string_value(nested_entry[:nested_colon])
            nested_values[key] = swift_string_array_literal(nested_entry[nested_colon + 1 :])
        values[provider] = nested_values
    return values


def swift_enum_case(expression: str | None) -> str | None:
    if expression is None:
        return None
    match = re.fullmatch(r"\.([A-Za-z0-9_]+)", expression.strip())
    return match.group(1) if match else None


def conductor_provider_metadata(text: str) -> dict[str, dict[str, object | None]]:
    metadata: dict[str, dict[str, object | None]] = {}
    for body in call_bodies(text, "UsageProviderEntry("):
        arguments = named_arguments(body)
        provider_id = swift_value(arguments.get("id"))
        if not isinstance(provider_id, str):
            continue
        metadata[provider_id] = {
            "name": swift_value(arguments.get("name")),
            "defaultEnabled": swift_value(arguments.get("defaultEnabled"), False),
            "statusPageURL": swift_value(arguments.get("statusPageURL")),
            "statusLinkURL": swift_value(arguments.get("statusLinkURL")),
            "dashboardURL": swift_value(arguments.get("dashboardURL")),
            "subscriptionDashboardURL": swift_value(arguments.get("subscriptionDashboardURL")),
            "changelogURL": swift_value(arguments.get("changelogURL")),
            "googleWorkspaceStatusProductID": swift_value(arguments.get("googleWorkspaceStatusProductID")),
        }
    for provider_id, display_metadata in conductor_provider_display_metadata(text).items():
        metadata.setdefault(provider_id, {}).update(display_metadata)
    return metadata


def conductor_provider_display_metadata(text: str) -> dict[str, dict[str, object | None]]:
    match = re.search(
        r"public static let providerDisplayMetadata:\s*\[String:\s*UsageProviderDisplayMetadata\]\s*=\s*\[",
        text,
    )
    if not match:
        raise ValueError("Conductor providerDisplayMetadata not found")
    open_index = match.end() - 1
    body = text[open_index + 1 : matching_close(text, open_index, "[", "]")]
    metadata: dict[str, dict[str, object | None]] = {}
    for provider_id, call_body in re.findall(
        r'"([^"]+)"\s*:\s*UsageProviderDisplayMetadata\((.*?)\),\s*(?=\n\s*(?:"|\]))',
        body + "\n    ]",
        flags=re.S,
    ):
        arguments = named_arguments(call_body)
        metadata[provider_id] = {
            "sessionLabel": swift_value(arguments.get("sessionLabel")),
            "weeklyLabel": swift_value(arguments.get("weeklyLabel")),
            "opusLabel": swift_value(arguments.get("opusLabel")),
            "supportsOpus": swift_value(arguments.get("supportsOpus"), False),
            "supportsCredits": swift_value(arguments.get("supportsCredits"), False),
            "creditsHint": swift_value(arguments.get("creditsHint"), ""),
            "toggleTitle": swift_value(arguments.get("toggleTitle")),
            "cliName": swift_value(arguments.get("cliName")),
            "isPrimaryProvider": swift_value(arguments.get("isPrimaryProvider"), False),
            "usesAccountFallback": swift_value(arguments.get("usesAccountFallback"), False),
        }
    return metadata


def codexbar_provider_metadata(provider_root: Path) -> dict[str, dict[str, object | None]]:
    metadata: dict[str, dict[str, object | None]] = {}
    for path in sorted(provider_root.glob("**/*ProviderDescriptor.swift")):
        text = read(path)
        marker = "ProviderMetadata("
        index = text.find(marker)
        if index == -1:
            continue
        open_index = index + len(marker) - 1
        body = text[open_index + 1 : matching_close(text, open_index)]
        arguments = named_arguments(body)
        provider_id = swift_enum_case(arguments.get("id"))
        if provider_id is None:
            continue
        metadata[provider_id] = {
            "displayName": swift_value(arguments.get("displayName")),
            "sessionLabel": swift_value(arguments.get("sessionLabel")),
            "weeklyLabel": swift_value(arguments.get("weeklyLabel")),
            "opusLabel": swift_value(arguments.get("opusLabel")),
            "supportsOpus": swift_value(arguments.get("supportsOpus")),
            "supportsCredits": swift_value(arguments.get("supportsCredits")),
            "creditsHint": swift_value(arguments.get("creditsHint")),
            "toggleTitle": swift_value(arguments.get("toggleTitle")),
            "cliName": swift_value(arguments.get("cliName")),
            "defaultEnabled": swift_value(arguments.get("defaultEnabled")),
            "isPrimaryProvider": swift_value(arguments.get("isPrimaryProvider"), False),
            "usesAccountFallback": swift_value(arguments.get("usesAccountFallback"), False),
            "statusPageURL": swift_value(arguments.get("statusPageURL")),
            "statusLinkURL": swift_value(arguments.get("statusLinkURL")),
            "dashboardURL": swift_value(arguments.get("dashboardURL")),
            "subscriptionDashboardURL": swift_value(arguments.get("subscriptionDashboardURL")),
            "changelogURL": swift_value(arguments.get("changelogURL")),
            "statusWorkspaceProductID": swift_value(arguments.get("statusWorkspaceProductID")),
        }
    return metadata


CODEXBAR_API_KEY_ENV_SOURCES = {
    "alibaba": ("Alibaba/AlibabaCodingPlanSettingsReader.swift", "apiTokenEnvironmentKeys"),
    "amp": ("Amp/AmpSettingsReader.swift", "apiTokenKey"),
    "azureopenai": ("AzureOpenAI/AzureOpenAISettingsReader.swift", "apiKeyEnvironmentKey"),
    "chutes": ("Chutes/ChutesSettingsReader.swift", "apiKeyEnvironmentKey"),
    "claude": ("Claude/ClaudeAdminAPISettingsReader.swift", "apiKeyEnvironmentKeys"),
    "crof": ("Crof/CrofSettingsReader.swift", "apiKeyEnvironmentKeys"),
    "deepgram": ("Deepgram/DeepgramSettingsReader.swift", "apiKeyEnvironmentKey"),
    "deepseek": ("DeepSeek/DeepSeekSettingsReader.swift", "apiKeyEnvironmentKeys"),
    "doubao": ("Doubao/DoubaoSettingsReader.swift", "apiKeyEnvironmentKeys"),
    "elevenlabs": ("ElevenLabs/ElevenLabsSettingsReader.swift", "apiKeyEnvironmentKeys"),
    "groq": ("Groq/GroqSettingsReader.swift", "apiKeyEnvironmentKey"),
    "kimi": ("Kimi/KimiSettingsReader.swift", "apiKeyEnvironmentKeys"),
    "kimik2": ("KimiK2/KimiK2SettingsReader.swift", "apiKeyEnvironmentKeys"),
    "kilo": ("Kilo/KiloSettingsReader.swift", "apiTokenKey"),
    "litellm": ("LiteLLM/LiteLLMSettingsReader.swift", "apiKeyEnvironmentKey"),
    "llmproxy": ("LLMProxy/LLMProxySettingsReader.swift", "apiKeyEnvironmentKey"),
    "minimax": ("MiniMax/MiniMaxAPISettingsReader.swift", "apiTokenEnvironmentKeys"),
    "moonshot": ("Moonshot/MoonshotSettingsReader.swift", "apiKeyEnvironmentKeys"),
    "ollama": ("Ollama/OllamaUsageFetcher.swift", "apiKeyEnvironmentKeys"),
    "openai": ("OpenAI/OpenAIAPISettingsReader.swift", "apiKeyEnvironmentKeys"),
    "openrouter": ("OpenRouter/OpenRouterSettingsReader.swift", "envKey"),
    "poe": ("Poe/PoeSettingsReader.swift", "apiKeyEnvironmentKey"),
    "synthetic": ("Synthetic/SyntheticSettingsReader.swift", "apiKeyKey"),
    "venice": ("Venice/VeniceSettingsReader.swift", "apiKeyEnvironmentKeys"),
    "warp": ("Warp/WarpSettingsReader.swift", "apiKeyEnvironmentKeys"),
    "zai": ("Zai/ZaiSettingsReader.swift", "apiTokenKey"),
}


CODEXBAR_BASE_URL_ENV_SOURCES = {
    "alibaba": ("Alibaba/AlibabaCodingPlanSettingsReader.swift", "hostKey"),
    "alibabatokenplan": ("Alibaba/AlibabaTokenPlanSettingsReader.swift", "hostKey"),
    "azureopenai": ("AzureOpenAI/AzureOpenAISettingsReader.swift", "endpointEnvironmentKey"),
    "chutes": ("Chutes/ChutesSettingsReader.swift", "apiURLEnvironmentKey"),
    "elevenlabs": ("ElevenLabs/ElevenLabsSettingsReader.swift", "apiURLEnvironmentKey"),
    "groq": ("Groq/GroqSettingsReader.swift", "apiURLEnvironmentKey"),
    "kimi": ("Kimi/KimiSettingsReader.swift", "codeAPIBaseURLEnvironmentKey"),
    "litellm": ("LiteLLM/LiteLLMSettingsReader.swift", "baseURLEnvironmentKey"),
    "llmproxy": ("LLMProxy/LLMProxySettingsReader.swift", "baseURLEnvironmentKey"),
    "minimax": ("MiniMax/MiniMaxSettingsReader.swift", "hostKey"),
    "zai": ("Zai/ZaiSettingsReader.swift", "apiHostKey"),
}


CODEXBAR_COOKIE_ENV_CONSTANT_SOURCES = {
    "alibaba": ("Alibaba/AlibabaCodingPlanSettingsReader.swift", "cookieHeaderKey"),
    "alibabatokenplan": ("Alibaba/AlibabaTokenPlanSettingsReader.swift", "cookieHeaderKey"),
    "minimax": ("MiniMax/MiniMaxSettingsReader.swift", "cookieHeaderKeys"),
}


CODEXBAR_COOKIE_ENV_LITERAL_VALUES = {
    "manus": [
        "MANUS_SESSION_TOKEN",
        "manus_session_token",
        "MANUS_SESSION_ID",
        "manus_session_id",
        "MANUS_COOKIE",
        "manus_cookie",
    ],
    "perplexity": [
        "PERPLEXITY_SESSION_TOKEN",
        "perplexity_session_token",
        "PERPLEXITY_COOKIE",
    ],
}


CODEXBAR_PROJECT_ENV_SOURCES = {
    "azureopenai": ("AzureOpenAI/AzureOpenAISettingsReader.swift", "deploymentNameEnvironmentKey"),
    "deepgram": ("Deepgram/DeepgramSettingsReader.swift", "projectIDEnvironmentKey"),
    "openai": ("OpenAI/OpenAIAPISettingsReader.swift", "projectIDEnvironmentKey"),
}


CODEXBAR_EXTRA_ENV_SOURCES = {
    ("alibaba", "quotaURL"): ("Alibaba/AlibabaCodingPlanSettingsReader.swift", "quotaURLKey"),
    ("alibaba", "requireProviderEndpointOverrides"):
        ("Alibaba/AlibabaCodingPlanSettingsReader.swift", "requireProviderEndpointOverridesKey"),
    ("alibabatokenplan", "quotaURL"): ("Alibaba/AlibabaTokenPlanSettingsReader.swift", "quotaURLKey"),
    ("azureopenai", "apiVersion"): ("AzureOpenAI/AzureOpenAISettingsReader.swift", "apiVersionEnvironmentKey"),
    ("glm", "quotaURL"): ("Zai/ZaiSettingsReader.swift", "quotaURLKey"),
    ("minimax", "codingPlanURL"): ("MiniMax/MiniMaxSettingsReader.swift", "codingPlanURLKey"),
    ("minimax", "remainsURL"): ("MiniMax/MiniMaxSettingsReader.swift", "remainsURLKey"),
    ("minimax", "billingHistoryURL"): ("MiniMax/MiniMaxSettingsReader.swift", "billingHistoryURLKey"),
    ("minimax", "requireProviderEndpointOverrides"):
        ("MiniMax/MiniMaxSettingsReader.swift", "requireProviderEndpointOverridesKey"),
    ("moonshot", "region"): ("Moonshot/MoonshotSettingsReader.swift", "regionEnvironmentKey"),
    ("openrouter", "httpReferer"): ("OpenRouter/OpenRouterUsageStats.swift", "httpRefererEnvKey"),
    ("openrouter", "clientTitle"): ("OpenRouter/OpenRouterUsageStats.swift", "clientTitleEnvKey"),
}


def codexbar_string_constant_list(provider_root: Path, sources: dict[str, tuple[str, str]]) -> dict[str, list[str]]:
    values: dict[str, list[str]] = {}
    for provider_id, (relative_path, symbol_name) in sources.items():
        text = read(provider_root / relative_path)
        if symbol_name.endswith("Keys"):
            values[provider_id] = swift_static_string_array(text, symbol_name)
        else:
            constants = swift_string_constants(text)
            if symbol_name not in constants:
                raise ValueError(f"Swift string constant not found: {relative_path} {symbol_name}")
            values[provider_id] = [constants[symbol_name]]
    return values


def codexbar_extra_environment_lists(provider_root: Path) -> dict[tuple[str, str], list[str]]:
    values: dict[tuple[str, str], list[str]] = {}
    for key, (relative_path, symbol_name) in CODEXBAR_EXTRA_ENV_SOURCES.items():
        text = read(provider_root / relative_path)
        constants = swift_string_constants(text)
        if symbol_name not in constants:
            raise ValueError(f"Swift string constant not found: {relative_path} {symbol_name}")
        values[key] = [constants[symbol_name]]
    return values


def conductor_api_key_environment_lists(text: str) -> dict[str, list[str]]:
    primaries = swift_string_dict(text, "apiKeyEnvironmentNames")
    aliases = swift_string_array_dict(text, "apiKeyAliases")
    return {
        provider_id: [primary] + aliases.get(provider_id, [])
        for provider_id, primary in primaries.items()
    }


def conductor_base_url_environment_lists(text: str) -> dict[str, list[str]]:
    return {
        provider_id: [name]
        for provider_id, name in swift_string_dict(text, "baseURLEnvironmentNames").items()
    }


def codexbar_cookie_environment_lists(provider_root: Path) -> dict[str, list[str]]:
    values = codexbar_string_constant_list(provider_root, CODEXBAR_COOKIE_ENV_CONSTANT_SOURCES)
    values.update(CODEXBAR_COOKIE_ENV_LITERAL_VALUES)
    return values


def conductor_cookie_environment_lists(text: str) -> dict[str, list[str]]:
    return swift_string_array_dict(text, "cookieHeaderEnvironmentNames")


def conductor_project_environment_lists(text: str) -> dict[str, list[str]]:
    return swift_string_array_dict(text, "projectEnvironmentNames")


def conductor_extra_environment_lists(text: str) -> dict[tuple[str, str], list[str]]:
    nested = swift_nested_string_array_dict(text, "extraEnvironmentNames")
    return {
        (provider_id, key): names
        for provider_id, values in nested.items()
        for key, names in values.items()
    }


def conductor_aliases(text: str) -> dict[str, str]:
    match = re.search(
        r"public static let providerAliases:\s*\[String:\s*String\]\s*=\s*\[(?P<body>.*?)\n\s*\]",
        text,
        flags=re.S,
    )
    if not match:
        raise ValueError("Conductor providerAliases not found")
    return dict(re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', match.group("body")))


def conductor_source_modes(text: str) -> dict[str, set[str]]:
    match = re.search(
        r"public static let providerSourceModes:\s*\[String:\s*\[String\]\]\s*=\s*\[(?P<body>.*?)\n\s*\]",
        text,
        flags=re.S,
    )
    if not match:
        raise ValueError("Conductor providerSourceModes not found")
    modes: dict[str, set[str]] = {}
    for provider, raw_modes in re.findall(r'"([^"]+)"\s*:\s*\[([^\]]*)\]', match.group("body")):
        modes[provider] = set(re.findall(r'"([^"]+)"', raw_modes))
    return modes


def codexbar_descriptor_provider_ids(text: str) -> set[str]:
    match = re.search(
        r"private static let descriptorsByID:\s*\[UsageProvider:\s*ProviderDescriptor\]\s*=\s*\[(?P<body>.*?)\n\s*\]",
        text,
        flags=re.S,
    )
    if not match:
        raise ValueError("CodexBar descriptorsByID not found")
    return set(re.findall(r"\.([A-Za-z0-9_]+)\s*:", match.group("body")))


def codexbar_source_modes(provider_root: Path) -> dict[str, set[str]]:
    modes: dict[str, set[str]] = {}
    for path in sorted(provider_root.glob("**/*ProviderDescriptor.swift")):
        text = read(path)
        id_match = re.search(r"id:\s*\.([A-Za-z0-9_]+)\s*,", text)
        if not id_match:
            continue
        provider = id_match.group(1)
        mode_match = re.search(r"sourceModes:\s*\[([^\]]*)\]", text, flags=re.S)
        if mode_match:
            modes[provider] = set(re.findall(r"\.([A-Za-z0-9_]+)", mode_match.group(1)))
        elif re.search(r"fetchPlan:\s*\.apiToken\s*\(", text):
            modes[provider] = {"auto", "api"}
        else:
            continue
    return modes


def canonical(provider: str, aliases: dict[str, str]) -> str:
    return aliases.get(provider, provider)


METADATA_FIELDS = [
    ("displayName", "name"),
    ("sessionLabel", "sessionLabel"),
    ("weeklyLabel", "weeklyLabel"),
    ("opusLabel", "opusLabel"),
    ("supportsOpus", "supportsOpus"),
    ("supportsCredits", "supportsCredits"),
    ("creditsHint", "creditsHint"),
    ("toggleTitle", "toggleTitle"),
    ("cliName", "cliName"),
    ("defaultEnabled", "defaultEnabled"),
    ("isPrimaryProvider", "isPrimaryProvider"),
    ("usesAccountFallback", "usesAccountFallback"),
    ("statusPageURL", "statusPageURL"),
    ("statusLinkURL", "statusLinkURL"),
    ("dashboardURL", "dashboardURL"),
    ("subscriptionDashboardURL", "subscriptionDashboardURL"),
    ("changelogURL", "changelogURL"),
    ("statusWorkspaceProductID", "googleWorkspaceStatusProductID"),
]


REQUIRED_PROVIDER_ALIASES = {
    "alibaba": "qwen",
    "zai": "glm",
}


def main() -> int:
    args = parse_args()
    codexbar_root = resolve_codexbar_root(args.codexbar)
    conductor_text = read(Path(args.conductor))
    capabilities_text = read(Path(args.capabilities))
    providers_text = read(codexbar_root / "Sources/CodexBarCore/Providers/Providers.swift")
    descriptor_text = read(codexbar_root / "Sources/CodexBarCore/Providers/ProviderDescriptor.swift")

    aliases = conductor_aliases(conductor_text)
    conductor_metadata = conductor_provider_metadata(conductor_text)
    conductor_ids = set(conductor_metadata)
    conductor_modes = conductor_source_modes(conductor_text)
    conductor_api_key_envs = conductor_api_key_environment_lists(capabilities_text)
    conductor_base_url_envs = conductor_base_url_environment_lists(capabilities_text)
    conductor_cookie_envs = conductor_cookie_environment_lists(capabilities_text)
    conductor_project_envs = conductor_project_environment_lists(capabilities_text)
    conductor_extra_envs = conductor_extra_environment_lists(capabilities_text)

    codexbar_cases = set(enum_cases(providers_text, "UsageProvider"))
    codexbar_descriptor_ids = codexbar_descriptor_provider_ids(descriptor_text)
    codexbar_modes = codexbar_source_modes(codexbar_root / "Sources/CodexBarCore/Providers")
    codexbar_metadata = codexbar_provider_metadata(codexbar_root / "Sources/CodexBarCore/Providers")
    provider_root = codexbar_root / "Sources/CodexBarCore/Providers"
    codexbar_api_key_envs = codexbar_string_constant_list(provider_root, CODEXBAR_API_KEY_ENV_SOURCES)
    codexbar_base_url_envs = codexbar_string_constant_list(provider_root, CODEXBAR_BASE_URL_ENV_SOURCES)
    codexbar_cookie_envs = codexbar_cookie_environment_lists(provider_root)
    codexbar_project_envs = codexbar_string_constant_list(provider_root, CODEXBAR_PROJECT_ENV_SOURCES)
    codexbar_extra_envs = codexbar_extra_environment_lists(provider_root)
    codexbar_canonical_ids = {canonical(provider, aliases) for provider in codexbar_cases}

    errors: list[str] = []

    for alias, expected_target in sorted(REQUIRED_PROVIDER_ALIASES.items()):
        actual_target = aliases.get(alias)
        if actual_target != expected_target:
            errors.append(
                f"provider alias {alias}: expected {expected_target}, "
                f"Conductor has {actual_target or '(missing)'}"
            )
        if alias not in codexbar_cases:
            errors.append(f"provider alias {alias}: CodexBar UsageProvider case is missing")
        if expected_target not in conductor_ids:
            errors.append(f"provider alias {alias}: target {expected_target} is missing from Conductor catalog")

    missing_descriptors = sorted(codexbar_cases - codexbar_descriptor_ids)
    extra_descriptors = sorted(codexbar_descriptor_ids - codexbar_cases)
    for provider in missing_descriptors:
        errors.append(f"CodexBar registry: missing descriptor for {provider}")
    for provider in extra_descriptors:
        errors.append(f"CodexBar registry: descriptor for unknown provider {provider}")

    missing_conductor = sorted(codexbar_canonical_ids - conductor_ids)
    for provider in missing_conductor:
        original = sorted(p for p in codexbar_cases if canonical(p, aliases) == provider)
        errors.append(f"Conductor catalog: missing provider {provider} (CodexBar {', '.join(original)})")

    for provider in sorted(codexbar_cases):
        conductor_id = canonical(provider, aliases)
        if conductor_id not in conductor_ids:
            continue
        expected_modes = codexbar_modes.get(provider, set())
        actual_modes = conductor_modes.get(conductor_id, set())
        if actual_modes != expected_modes:
            errors.append(
                f"sourceModes {provider}->{conductor_id}: expected exact "
                f"{', '.join(sorted(expected_modes)) or '(none)'}; "
                f"Conductor has {', '.join(sorted(actual_modes)) or '(none)'}"
            )

        expected_metadata = codexbar_metadata.get(provider)
        actual_metadata = conductor_metadata.get(conductor_id)
        if expected_metadata is None:
            errors.append(f"CodexBar metadata: missing parsed metadata for {provider}")
            continue
        if actual_metadata is None:
            errors.append(f"Conductor metadata: missing parsed metadata for {conductor_id}")
            continue
        for codexbar_field, conductor_field in METADATA_FIELDS:
            expected = expected_metadata.get(codexbar_field)
            actual = actual_metadata.get(conductor_field)
            if isinstance(expected, str) and expected.startswith("<unsupported:"):
                errors.append(
                    f"CodexBar metadata {provider}.{codexbar_field}: unsupported expression {expected}"
                )
                continue
            if isinstance(actual, str) and actual.startswith("<unsupported:"):
                errors.append(
                    f"Conductor metadata {conductor_id}.{conductor_field}: unsupported expression {actual}"
                )
                continue
            if expected != actual:
                errors.append(
                    f"metadata {provider}->{conductor_id} {codexbar_field}/{conductor_field}: "
                    f"CodexBar {expected!r}, Conductor {actual!r}"
                )

    for provider, expected_envs in sorted(codexbar_api_key_envs.items()):
        conductor_id = canonical(provider, aliases)
        actual_envs = conductor_api_key_envs.get(conductor_id)
        if actual_envs is None:
            errors.append(
                f"api-key env {provider}->{conductor_id}: CodexBar has {expected_envs!r}, "
                "Conductor has no API key environment hints"
            )
            continue
        if actual_envs != expected_envs:
            errors.append(
                f"api-key env {provider}->{conductor_id}: expected exact {expected_envs!r}; "
                f"Conductor has {actual_envs!r}"
            )

    for provider, expected_envs in sorted(codexbar_base_url_envs.items()):
        conductor_id = canonical(provider, aliases)
        actual_envs = conductor_base_url_envs.get(conductor_id)
        if actual_envs is None:
            errors.append(
                f"base-url env {provider}->{conductor_id}: CodexBar has {expected_envs!r}, "
                "Conductor has no base URL environment hints"
            )
            continue
        if actual_envs != expected_envs:
            errors.append(
                f"base-url env {provider}->{conductor_id}: expected exact {expected_envs!r}; "
                f"Conductor has {actual_envs!r}"
            )

    for provider, expected_envs in sorted(codexbar_cookie_envs.items()):
        conductor_id = canonical(provider, aliases)
        actual_envs = conductor_cookie_envs.get(conductor_id)
        if actual_envs is None:
            errors.append(
                f"cookie env {provider}->{conductor_id}: CodexBar has {expected_envs!r}, "
                "Conductor has no cookie environment hints"
            )
            continue
        if actual_envs != expected_envs:
            errors.append(
                f"cookie env {provider}->{conductor_id}: expected exact {expected_envs!r}; "
                f"Conductor has {actual_envs!r}"
            )

    for provider, expected_envs in sorted(codexbar_project_envs.items()):
        conductor_id = canonical(provider, aliases)
        actual_envs = conductor_project_envs.get(conductor_id)
        if actual_envs is None:
            errors.append(
                f"project env {provider}->{conductor_id}: CodexBar has {expected_envs!r}, "
                "Conductor has no project environment hints"
            )
            continue
        if actual_envs != expected_envs:
            errors.append(
                f"project env {provider}->{conductor_id}: expected exact {expected_envs!r}; "
                f"Conductor has {actual_envs!r}"
            )

    for (provider, key), expected_envs in sorted(codexbar_extra_envs.items()):
        conductor_id = canonical(provider, aliases)
        actual_envs = conductor_extra_envs.get((conductor_id, key))
        if actual_envs is None:
            errors.append(
                f"extra env {provider}->{conductor_id}.{key}: CodexBar has {expected_envs!r}, "
                "Conductor has no matching extra environment hints"
            )
            continue
        if actual_envs != expected_envs:
            errors.append(
                f"extra env {provider}->{conductor_id}.{key}: expected exact {expected_envs!r}; "
                f"Conductor has {actual_envs!r}"
            )

    if errors:
        print("CodexBar provider audit failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    aliased = {
        provider: canonical(provider, aliases)
        for provider in sorted(codexbar_cases)
        if provider != canonical(provider, aliases)
    }
    print("CodexBar provider audit passed.")
    print(f"  CodexBar providers: {len(codexbar_cases)}")
    print(f"  Conductor providers: {len(conductor_ids)}")
    print(f"  Canonical aliases: {', '.join(f'{k}->{v}' for k, v in aliased.items()) or 'none'}")
    print(f"  Metadata fields audited: {len(METADATA_FIELDS)}")
    print(f"  Source modes audited: {len(codexbar_modes)}")
    print(f"  API key env lists audited: {len(codexbar_api_key_envs)}")
    print(f"  Base URL env lists audited: {len(codexbar_base_url_envs)}")
    print(f"  Cookie env lists audited: {len(codexbar_cookie_envs)}")
    print(f"  Project env lists audited: {len(codexbar_project_envs)}")
    print(f"  Extra env lists audited: {len(codexbar_extra_envs)}")
    print(f"  Source: {codexbar_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
