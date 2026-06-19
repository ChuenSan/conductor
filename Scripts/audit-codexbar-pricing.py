#!/usr/bin/env python3
from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path
from typing import Any


PER_MILLION = 1_000_000


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare Conductor built-in usage pricing against CodexBar's vendored CostUsagePricing table."
    )
    parser.add_argument(
        "--codexbar",
        default="/tmp/codexbar-audit",
        help="Path to the CodexBar checkout or its CostUsagePricing.swift file.",
    )
    parser.add_argument(
        "--conductor",
        default="Sources/ConductorCore/Usage/AgentUsageStats.swift",
        help="Path to Conductor's AgentUsageStats.swift.",
    )
    return parser.parse_args()


def resolve_codexbar_pricing(path_value: str) -> Path:
    path = Path(path_value)
    if path.is_file():
        return path
    candidate = path / "Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift"
    if candidate.is_file():
        return candidate
    raise FileNotFoundError(f"CodexBar pricing file not found under {path}")


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
        if text.startswith("//", index) or text.startswith("/*", index):
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


def extract_bracket_body(text: str, marker: str) -> str:
    marker_index = text.find(marker)
    if marker_index == -1:
        raise ValueError(f"marker not found: {marker}")
    equals = text.find("=", marker_index)
    if equals == -1:
        raise ValueError(f"dictionary assignment not found after marker: {marker}")
    start = text.find("[", equals)
    if start == -1:
        raise ValueError(f"dictionary bracket not found after marker: {marker}")
    _, end = balanced_range(text, start, "[", "]")
    return text[start + 1 : end]


def extract_brace_body(text: str, marker: str) -> str:
    marker_index = text.find(marker)
    if marker_index == -1:
        raise ValueError(f"marker not found: {marker}")
    start = text.find("{", marker_index)
    if start == -1:
        raise ValueError(f"function body not found after marker: {marker}")
    _, end = balanced_range(text, start, "{", "}")
    return text[start + 1 : end]


def split_top_level(text: str, separator: str = ",") -> list[str]:
    parts: list[str] = []
    start = 0
    index = 0
    depth_round = 0
    depth_square = 0
    depth_curly = 0
    while index < len(text):
        if text.startswith("//", index) or text.startswith("/*", index):
            skipped = skip_comment(text, index)
            if skipped != index:
                index = skipped
                continue
        char = text[index]
        if char in ('"', "'"):
            index = skip_string(text, index)
            continue
        if char == "(":
            depth_round += 1
        elif char == ")":
            depth_round -= 1
        elif char == "[":
            depth_square += 1
        elif char == "]":
            depth_square -= 1
        elif char == "{":
            depth_curly += 1
        elif char == "}":
            depth_curly -= 1
        elif (
            char == separator
            and depth_round == 0
            and depth_square == 0
            and depth_curly == 0
        ):
            parts.append(text[start:index].strip())
            start = index + 1
        index += 1
    tail = text[start:].strip()
    if tail:
        parts.append(tail)
    return parts


def read_key(text: str, start: int) -> tuple[str, int]:
    if text[start] != '"':
        raise ValueError(f"expected string key at offset {start}")
    index = start + 1
    key_chars: list[str] = []
    while index < len(text):
        char = text[index]
        if char == "\\":
            if index + 1 >= len(text):
                raise ValueError("unterminated escape in dictionary key")
            key_chars.append(text[index + 1])
            index += 2
            continue
        if char == '"':
            return "".join(key_chars), index + 1
        key_chars.append(char)
        index += 1
    raise ValueError("unterminated dictionary key")


def read_expression_until_comma(text: str, start: int) -> tuple[str, int]:
    index = start
    depth_round = 0
    depth_square = 0
    depth_curly = 0
    while index < len(text):
        if text.startswith("//", index) or text.startswith("/*", index):
            skipped = skip_comment(text, index)
            if skipped != index:
                index = skipped
                continue
        char = text[index]
        if char in ('"', "'"):
            index = skip_string(text, index)
            continue
        if char == "(":
            depth_round += 1
        elif char == ")":
            depth_round -= 1
        elif char == "[":
            depth_square += 1
        elif char == "]":
            depth_square -= 1
        elif char == "{":
            depth_curly += 1
        elif char == "}":
            depth_curly -= 1
        elif (
            char == ","
            and depth_round == 0
            and depth_square == 0
            and depth_curly == 0
        ):
            return text[start:index].strip(), index + 1
        index += 1
    return text[start:].strip(), len(text)


def parse_swift_dictionary(body: str) -> dict[str, str]:
    entries: dict[str, str] = {}
    index = 0
    while index < len(body):
        if body.startswith("//", index) or body.startswith("/*", index):
            skipped = skip_comment(body, index)
            if skipped != index:
                index = skipped
                continue
        if body[index] != '"':
            index += 1
            continue
        key, index = read_key(body, index)
        while index < len(body) and body[index].isspace():
            index += 1
        if index >= len(body) or body[index] != ":":
            raise ValueError(f"missing ':' after dictionary key {key!r}")
        index += 1
        while index < len(body) and body[index].isspace():
            index += 1
        expression, index = read_expression_until_comma(body, index)
        entries[key] = expression
    return entries


def parse_value(value: str) -> Any:
    value = value.strip()
    if value == "nil":
        return None
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    if value.startswith("Date("):
        match = re.search(r"timeIntervalSince1970:\s*([0-9_]+)", value)
        if match:
            return int(match.group(1).replace("_", ""))
    number = value.replace("_", "")
    if re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", number):
        if "." in number or "e" in number.lower():
            return float(number)
        return int(number)
    return value


def parse_constructor(expression: str, constants: dict[str, dict[str, Any]] | None = None) -> dict[str, Any]:
    constants = constants or {}
    expression = expression.strip()
    if expression in constants:
        return dict(constants[expression])
    open_index = expression.find("(")
    if open_index == -1 or not expression.endswith(")"):
        raise ValueError(f"unsupported constructor expression: {expression}")
    inner = expression[open_index + 1 : -1]
    args: dict[str, Any] = {}
    for item in split_top_level(inner):
        if not item:
            continue
        name, separator, value = item.partition(":")
        if not separator:
            raise ValueError(f"constructor argument has no name: {item}")
        args[name.strip()] = parse_value(value)
    return args


def parse_constructor_constant(text: str, name: str) -> dict[str, Any]:
    marker = f"private static let {name}"
    marker_index = text.find(marker)
    if marker_index == -1:
        raise ValueError(f"constant not found: {name}")
    equals = text.find("=", marker_index)
    if equals == -1:
        raise ValueError(f"constant assignment not found: {name}")
    start = equals + 1
    while start < len(text) and text[start].isspace():
        start += 1
    open_index = text.find("(", start)
    if open_index == -1:
        raise ValueError(f"constant constructor not found: {name}")
    _, close_index = balanced_range(text, open_index, "(", ")")
    expression = text[start : close_index + 1]
    return parse_constructor(expression)


def parse_dictionary_constructors(
    text: str,
    marker: str,
    constants: dict[str, dict[str, Any]] | None = None,
) -> dict[str, dict[str, Any]]:
    body = extract_bracket_body(text, marker)
    raw_entries = parse_swift_dictionary(body)
    return {
        key: parse_constructor(expression, constants)
        for key, expression in raw_entries.items()
    }


def parse_integer_constant(text: str, name: str) -> int:
    pattern = rf"private static let {re.escape(name)}\s*=\s*([0-9_]+)"
    match = re.search(pattern, text)
    if not match:
        raise ValueError(f"integer constant not found: {name}")
    return int(match.group(1).replace("_", ""))


def parse_cutoff(text: str) -> int:
    match = re.search(
        r"private static let claudeFullContextStandardPricingCutoff\s*=\s*Date\(timeIntervalSince1970:\s*([0-9_]+)\)",
        text,
    )
    if not match:
        raise ValueError("claudeFullContextStandardPricingCutoff not found")
    return int(match.group(1).replace("_", ""))


def parse_conductor_priority(text: str) -> dict[str, dict[str, Any]]:
    body = extract_brace_body(text, "public static func codexPriorityForModel")
    results: dict[str, dict[str, Any]] = {}
    for match in re.finditer(r'case\s+"([^"]+)":', body):
        key = match.group(1)
        return_index = body.find("return", match.end())
        if return_index == -1:
            raise ValueError(f"priority case has no return: {key}")
        expr_start = body.find("ModelPricing", return_index)
        if expr_start == -1:
            raise ValueError(f"priority case has no ModelPricing return: {key}")
        open_index = body.find("(", expr_start)
        _, close_index = balanced_range(body, open_index, "(", ")")
        expression = body[expr_start : close_index + 1]
        results[key] = parse_constructor(expression)
    return results


def optional_per_million(value: Any) -> Any:
    if value is None:
        return None
    return float(value) * PER_MILLION


def codex_expected(pricing: dict[str, Any]) -> dict[str, Any]:
    input_per_m = optional_per_million(pricing["inputCostPerToken"])
    output_per_m = optional_per_million(pricing["outputCostPerToken"])
    cache_read_rate = pricing["cacheReadInputCostPerToken"]
    cache_read_per_m = optional_per_million(
        cache_read_rate if cache_read_rate is not None else pricing["inputCostPerToken"]
    )
    input_above = pricing.get("inputCostPerTokenAboveThreshold")
    output_above = pricing.get("outputCostPerTokenAboveThreshold")
    cache_read_above = pricing.get("cacheReadInputCostPerTokenAboveThreshold")
    return {
        "inputPerM": input_per_m,
        "outputPerM": output_per_m,
        "cacheWritePerM": input_per_m,
        "cacheReadPerM": cache_read_per_m,
        "thresholdTokens": pricing.get("thresholdTokens"),
        "inputPerMAboveThreshold": optional_per_million(input_above),
        "outputPerMAboveThreshold": optional_per_million(output_above),
        "cacheWritePerMAboveThreshold": optional_per_million(input_above),
        "cacheReadPerMAboveThreshold": optional_per_million(cache_read_above),
        "displayLabel": pricing.get("displayLabel"),
    }


def codex_priority_expected(pricing: dict[str, Any]) -> dict[str, Any] | None:
    input_rate = pricing.get("priorityInputCostPerToken")
    output_rate = pricing.get("priorityOutputCostPerToken")
    if input_rate is None or output_rate is None:
        return None
    cache_read_rate = pricing.get("priorityCacheReadInputCostPerToken")
    return {
        "inputPerM": optional_per_million(input_rate),
        "outputPerM": optional_per_million(output_rate),
        "cacheWritePerM": optional_per_million(input_rate),
        "cacheReadPerM": optional_per_million(cache_read_rate if cache_read_rate is not None else input_rate),
    }


def claude_expected(pricing: dict[str, Any]) -> dict[str, Any]:
    return {
        "inputPerM": optional_per_million(pricing["inputCostPerToken"]),
        "outputPerM": optional_per_million(pricing["outputCostPerToken"]),
        "cacheWritePerM": optional_per_million(pricing["cacheCreationInputCostPerToken"]),
        "cacheReadPerM": optional_per_million(pricing["cacheReadInputCostPerToken"]),
        "thresholdTokens": pricing.get("thresholdTokens"),
        "inputPerMAboveThreshold": optional_per_million(pricing.get("inputCostPerTokenAboveThreshold")),
        "outputPerMAboveThreshold": optional_per_million(pricing.get("outputCostPerTokenAboveThreshold")),
        "cacheWritePerMAboveThreshold": optional_per_million(
            pricing.get("cacheCreationInputCostPerTokenAboveThreshold")
        ),
        "cacheReadPerMAboveThreshold": optional_per_million(
            pricing.get("cacheReadInputCostPerTokenAboveThreshold")
        ),
    }


def values_match(actual: Any, expected: Any) -> bool:
    if actual is None or expected is None:
        return actual is expected
    if isinstance(actual, (int, float)) and isinstance(expected, (int, float)):
        return math.isclose(float(actual), float(expected), rel_tol=1e-12, abs_tol=1e-12)
    return actual == expected


def format_value(value: Any) -> str:
    if isinstance(value, float):
        return f"{value:.17g}"
    return repr(value)


def compare_sets(label: str, actual: set[str], expected: set[str], errors: list[str]) -> None:
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    for key in missing:
        errors.append(f"{label}: missing {key}")
    for key in extra:
        errors.append(f"{label}: extra {key}")


def compare_pricing(
    label: str,
    actual_by_model: dict[str, dict[str, Any]],
    expected_by_model: dict[str, dict[str, Any]],
    fields: list[str],
    errors: list[str],
) -> None:
    compare_sets(label, set(actual_by_model), set(expected_by_model), errors)
    for model in sorted(set(actual_by_model) & set(expected_by_model)):
        actual = actual_by_model[model]
        expected = expected_by_model[model]
        for field in fields:
            if not values_match(actual.get(field), expected.get(field)):
                errors.append(
                    f"{label} {model}.{field}: actual {format_value(actual.get(field))}, "
                    f"expected {format_value(expected.get(field))}"
                )


def main() -> int:
    args = parse_args()
    conductor_file = Path(args.conductor)
    codexbar_file = resolve_codexbar_pricing(args.codexbar)

    conductor_text = conductor_file.read_text(encoding="utf-8")
    codexbar_text = codexbar_file.read_text(encoding="utf-8")

    conductor_constants = {
        "claudeSonnet4LongContextPricing": parse_constructor_constant(
            conductor_text,
            "claudeSonnet4LongContextPricing",
        )
    }

    codexbar_codex = parse_dictionary_constructors(codexbar_text, "private static let codex:")
    codexbar_claude = parse_dictionary_constructors(codexbar_text, "private static let claude:")
    codexbar_claude_historical = parse_dictionary_constructors(
        codexbar_text,
        "private static let claudeHistoricalLongContext",
    )

    conductor_codex = parse_dictionary_constructors(conductor_text, "private static let codexBuiltinPricing")
    conductor_claude = parse_dictionary_constructors(
        conductor_text,
        "private static let claudeBuiltinPricing",
        conductor_constants,
    )
    conductor_claude_historical = parse_dictionary_constructors(
        conductor_text,
        "private static let claudeHistoricalLongContextPricing",
    )
    conductor_priority = parse_conductor_priority(conductor_text)

    expected_codex = {model: codex_expected(pricing) for model, pricing in codexbar_codex.items()}
    expected_claude = {model: claude_expected(pricing) for model, pricing in codexbar_claude.items()}
    expected_claude_historical = {
        model: claude_expected(pricing)
        for model, pricing in codexbar_claude_historical.items()
    }
    expected_priority = {
        model: expected
        for model, pricing in codexbar_codex.items()
        if (expected := codex_priority_expected(pricing)) is not None
    }

    errors: list[str] = []

    if parse_integer_constant(conductor_text, "codexPriorityInputTokenLimit") != parse_integer_constant(
        codexbar_text,
        "codexPriorityInputTokenLimit",
    ):
        errors.append("codexPriorityInputTokenLimit differs")

    if parse_cutoff(conductor_text) != parse_cutoff(codexbar_text):
        errors.append("claudeFullContextStandardPricingCutoff differs")

    pricing_fields = [
        "inputPerM",
        "outputPerM",
        "cacheWritePerM",
        "cacheReadPerM",
        "thresholdTokens",
        "inputPerMAboveThreshold",
        "outputPerMAboveThreshold",
        "cacheWritePerMAboveThreshold",
        "cacheReadPerMAboveThreshold",
        "displayLabel",
    ]
    claude_fields = [field for field in pricing_fields if field != "displayLabel"]
    priority_fields = ["inputPerM", "outputPerM", "cacheWritePerM", "cacheReadPerM"]

    compare_pricing("codex", conductor_codex, expected_codex, pricing_fields, errors)
    compare_pricing("codex-priority", conductor_priority, expected_priority, priority_fields, errors)
    compare_pricing("claude", conductor_claude, expected_claude, claude_fields, errors)
    compare_pricing(
        "claude-historical",
        conductor_claude_historical,
        expected_claude_historical,
        claude_fields,
        errors,
    )

    if errors:
        print("CodexBar pricing audit failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print("CodexBar pricing audit passed.")
    print(f"  Codex models: {len(expected_codex)}")
    print(f"  Codex priority models: {len(expected_priority)}")
    print(f"  Claude models: {len(expected_claude)}")
    print(f"  Claude historical models: {len(expected_claude_historical)}")
    print(f"  Source: {codexbar_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
