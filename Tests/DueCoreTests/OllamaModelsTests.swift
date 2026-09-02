import XCTest
@testable import DueCore

final class OllamaModelsTests: XCTestCase {
    func testPrefersNewestKnownFamily() {
        let installed = ["gemma3:27b", "qwen3.6:35b-a3b-nvfp4", "qwen3:30b"]
        XCTAssertEqual(OllamaModels.preferred(from: installed), "qwen3.6:35b-a3b-nvfp4")
    }

    func testSkipsEmbeddingModels() {
        let installed = ["embeddinggemma:latest", "qwen3-embedding:0.6b", "gemma3:27b"]
        XCTAssertEqual(OllamaModels.preferred(from: installed), "gemma3:27b")
    }

    func testBareQwen3RanksBelowGemma() {
        // qwen3 (non-.6) leaks reasoning into its output; prefer families that don't.
        XCTAssertEqual(OllamaModels.preferred(from: ["qwen3:30b", "gemma4:e4b-mlx"]), "gemma4:e4b-mlx")
    }

    func testUnknownModelIsLastResortFallback() {
        XCTAssertEqual(OllamaModels.preferred(from: ["muse-glimmer:30b-mlx"]), "muse-glimmer:30b-mlx")
    }

    func testEmptyOrEmbeddingOnlyIsNil() {
        XCTAssertNil(OllamaModels.preferred(from: []))
        XCTAssertNil(OllamaModels.preferred(from: ["embeddinggemma:latest"]))
    }

    func testVisionPrefersMultimodalFamiliesOnly() {
        XCTAssertEqual(
            OllamaModels.preferredVision(from: ["qwen3.6:35b-a3b-nvfp4", "gemma3:27b", "gemma4:e4b-mlx"]),
            "gemma4:e4b-mlx"
        )
        XCTAssertNil(OllamaModels.preferredVision(from: ["qwen3.6:35b-a3b-nvfp4", "muse-glimmer:30b-mlx"]),
                     "text-only models never get images")
    }

    func testSettingsRoundTripsNotesAIModel() throws {
        var settings = DueSettings()
        XCTAssertEqual(settings.notesAIModel, "auto")
        settings.notesAIModel = "gemma3:27b"
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DueSettings.self, from: data)
        XCTAssertEqual(decoded.notesAIModel, "gemma3:27b")
        // Old files without the field decode to the default.
        let old = try JSONDecoder().decode(DueSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(old.notesAIModel, "auto")
    }
}
