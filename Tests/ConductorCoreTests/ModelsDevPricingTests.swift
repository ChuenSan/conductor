import XCTest
@testable import ConductorCore

final class ModelsDevPricingTests: XCTestCase {
    func testParsesModelsDevCatalogAndNormalizesProviderModels() throws {
        let catalog = try Self.catalog()

        XCTAssertEqual(catalog.providers["openai"]?.name, "OpenAI")
        XCTAssertEqual(catalog.providers["anthropic"]?.models["claude-sonnet-4-6"]?.cost?.cacheWrite, 3.75)
        XCTAssertEqual(catalog.providers["anthropic"]?.models["claude-sonnet-4-6"]?.limit?.context, 1_000_000)

        let lookup = try XCTUnwrap(catalog.pricing(
            providerID: "anthropic",
            modelID: "us.anthropic.claude-sonnet-4-6"))
        XCTAssertEqual(lookup.normalizedModelID, "claude-sonnet-4-6")
        XCTAssertEqual(lookup.pricing.inputCostPerM, 3)
        XCTAssertEqual(lookup.pricing.thresholdTokens, 200_000)
        XCTAssertEqual(lookup.pricing.outputCostPerMAboveThreshold, 22.5)
    }

    func testCacheLookupAndModelPricingUseModelsDevPrice() throws {
        let root = try Self.cacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        ModelsDevCache.save(catalog: try Self.catalog(), fetchedAt: Date(), cacheRoot: root)

        let lookup = try XCTUnwrap(ModelsDevPricingPipeline.lookup(
            providerID: "openai",
            modelID: "gpt-test-cached",
            cacheRoot: root))
        XCTAssertEqual(lookup.pricing.inputCostPerM, 0.15)
        XCTAssertEqual(lookup.pricing.outputCostPerM, 0.60)

        let pricing = ModelPricing.forModel("gpt-test-cached", cacheRoot: root)
        XCTAssertEqual(pricing.inputPerM, 0.15)
        XCTAssertEqual(pricing.outputPerM, 0.60)
        XCTAssertEqual(pricing.cacheReadPerM, 0.015)
        XCTAssertEqual(pricing.cost(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0), 0.75)
    }

    func testCostUsagePricingFacadeMatchesCodexBarCodexPricing() throws {
        let cost = try XCTUnwrap(CostUsagePricing.codexCostUSD(
            model: "openai/gpt-5.2-codex-2026-01-15",
            inputTokens: 100,
            cachedInputTokens: 20,
            outputTokens: 10))
        let expected = (80.0 * 1.75e-6) + (20.0 * 1.75e-7) + (10.0 * 1.4e-5)
        XCTAssertEqual(cost, expected, accuracy: 1e-12)
        XCTAssertEqual(
            CostUsagePricing.codexDisplayLabel(model: "openai/gpt-5.3-codex-spark-2026-02-01"),
            "Research Preview")
        XCTAssertNil(CostUsagePricing.codexCostUSD(
            model: "unknown-codex-preview",
            inputTokens: 100,
            cachedInputTokens: 0,
            outputTokens: 10))
    }

    func testCostUsagePricingFacadeMatchesCodexBarPriorityPricing() throws {
        let cost = try XCTUnwrap(CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.4-mini",
            inputTokens: 100,
            cachedInputTokens: 20,
            outputTokens: 10))
        let expected = (80.0 * 1.5e-6) + (20.0 * 0.15e-6) + (10.0 * 9e-6)
        XCTAssertEqual(cost, expected, accuracy: 1e-12)
        XCTAssertNil(CostUsagePricing.codexPriorityCostUSD(
            model: "gpt-5.5",
            inputTokens: 272_001,
            outputTokens: 10))
    }

    func testCostUsagePricingFacadeMatchesCodexBarClaudeHistoricalPricing() throws {
        let beforeCutoff = Date(timeIntervalSince1970: 1_773_359_999)
        let afterCutoff = Date(timeIntervalSince1970: 1_773_360_000)

        let historical = try XCTUnwrap(CostUsagePricing.claudeCostUSD(
            model: "anthropic.claude-sonnet-4-6-v1:0",
            inputTokens: 200_001,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 10,
            pricingDate: beforeCutoff))
        let current = try XCTUnwrap(CostUsagePricing.claudeCostUSD(
            model: "anthropic.claude-sonnet-4-6-v1:0",
            inputTokens: 200_001,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 10,
            pricingDate: afterCutoff))

        XCTAssertEqual(historical, (200_001.0 * 6 + 10.0 * 22.5) / 1_000_000, accuracy: 1e-12)
        XCTAssertEqual(current, (200_001.0 * 3 + 10.0 * 15) / 1_000_000, accuracy: 1e-12)
        XCTAssertNil(CostUsagePricing.claudeCostUSD(
            model: "not-a-claude-model",
            inputTokens: 1,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 1))
    }

    func testStaleCacheRemainsReadable() throws {
        let root = try Self.cacheRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let old = Date(timeIntervalSince1970: 1)
        ModelsDevCache.save(catalog: try Self.catalog(), fetchedAt: old, cacheRoot: root)
        let loaded = ModelsDevCache.load(
            now: old.addingTimeInterval(ModelsDevCache.ttlSeconds + 1),
            cacheRoot: root)

        XCTAssertNotNil(loaded.artifact)
        XCTAssertTrue(loaded.isStale)
        XCTAssertNil(loaded.error)
    }

    private static func cacheRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-modelsdev-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func catalog() throws -> ModelsDevCatalog {
        try JSONDecoder().decode(ModelsDevCatalog.self, from: Data("""
        {
          "openai": {
            "id": "openai",
            "name": "OpenAI",
            "models": {
              "gpt-test-cached": {
                "id": "gpt-test-cached",
                "cost": {
                  "input": 0.15,
                  "output": 0.60,
                  "cache_read": 0.015
                }
              }
            }
          },
          "anthropic": {
            "id": "anthropic",
            "name": "Anthropic",
            "models": {
              "claude-sonnet-4-6": {
                "id": "claude-sonnet-4-6",
                "cost": {
                  "input": 3,
                  "output": 15,
                  "cache_read": 0.3,
                  "cache_write": 3.75,
                  "context_over_200k": {
                    "input": 6,
                    "output": 22.5,
                    "cache_read": 0.6,
                    "cache_write": 7.5
                  }
                },
                "limit": { "context": 1000000 }
              }
            }
          }
        }
        """.utf8))
    }
}
