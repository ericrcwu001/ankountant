import Foundation
import Testing
@testable import AnkiKit

@Suite("Learning feedback")
struct LearningFeedbackTests {
    @Test func feedbackDecodesWithDerivedStableId() throws {
        let json = """
        {
            "title": "Lease classification",
            "whyWrong": "You treated a finance lease as operating.",
            "correctApproach": "Test transfer, purchase option, term, PV, and specialization.",
            "remember": "Finance lease criteria are evaluated at commencement.",
            "sourceIds": ["review-front", "review-back"]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let first = try JSONDecoder().decode(LearningFeedback.self, from: data)
        let second = try JSONDecoder().decode(LearningFeedback.self, from: data)
        let expectedContent = """
        Lease classification

        You treated a finance lease as operating.

        Test transfer, purchase option, term, PV, and specialization.

        Finance lease criteria are evaluated at commencement.
        """

        #expect(first.id == second.id)
        #expect(first.content == expectedContent)
        #expect(first.title == "Lease classification")
        #expect(first.sourceIds == ["review-front", "review-back"])
    }

    @Test func reviewRequestUsesReadableFrontBackAndNoteSources() throws {
        let rendered = RenderedCard(
            frontHTML: "<div>Which&nbsp;amount?<br><b>Explain</b></div>",
            backHTML: "<p>Use &amp; answer &#x41;.</p>",
            cardCSS: ""
        )
        let note = NoteRecord(
            id: 1,
            guid: "guid",
            mid: 2,
            mod: 0,
            flds: "<b>Field&nbsp;1</b>\u{1f}&lt;quoted&gt;\u{1f} ",
            sfld: "Field 1",
            csum: 0
        )

        let request = buildReviewLearningFeedbackRequest(
            title: "Review feedback",
            renderedCard: rendered,
            note: note,
            userAnswer: "  typed   answer  "
        )

        #expect(request.question == "Which amount?\nExplain")
        #expect(request.correctAnswer == "Use & answer A.")
        #expect(request.userAnswer == "typed answer")
        #expect(request.sources.map(\.id) == ["review-front", "review-back", "note-field-1", "note-field-2"])
        #expect(request.sources.map(\.body) == [
            "Which amount?\nExplain",
            "Use & answer A.",
            "Field 1",
            "<quoted>",
        ])

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(LearningFeedbackRequest.self, from: encoded)
        #expect(decoded == request)
    }

    @Test func tbsRequestIncludesOnlyIncorrectStepAnswersAndContextSources() throws {
        let model = TbsModel(
            shape: .numeric,
            prompt: "Calculate <b>lease</b> liability.",
            exhibits: [
                Exhibit(
                    id: 0,
                    title: "Schedule",
                    body: "<p>Payment &amp; rate</p>",
                    kind: "table",
                    columns: ["Year", "Payment"],
                    rows: [["1", "100"]]
                ),
            ],
            steps: [
                RenderStep(id: "s1", label: "Cell 1", weight: 0.5),
                RenderStep(id: "s2", label: "Cell 2", weight: 0.5),
            ],
            section: "FAR"
        )
        let reveal = TbsRevealModel(
            steps: [
                StepReveal(id: "s1", label: "Cell 1", correctText: "100"),
                StepReveal(id: "s2", label: "Cell 2", correctText: "200"),
            ],
            source: "ASC 842-20-25-1",
            section: "FAR",
            schemaTag: "ds::leases::classification"
        )
        let result = buildTbsLearningFeedbackRequest(
            title: "TBS feedback",
            model: model,
            reveal: reveal,
            stepResults: [
                PerformanceStepResult(id: "s1", correct: false, weight: 0.5),
                PerformanceStepResult(id: "s2", correct: true, weight: 0.5),
            ],
            userAnswerText: "s1 = 80\ns2 = 200"
        )

        guard let request = result else {
            Issue.record("Expected a TBS learning feedback request.")
            return
        }

        #expect(request.question == "Calculate lease liability.")
        #expect(request.correctAnswer == "Cell 1: 100")
        #expect(!request.correctAnswer.contains("200"))
        #expect(request.userAnswer == "s1 = 80\ns2 = 200")
        #expect(request.sources.map(\.id) == ["tbs-prompt", "tbs-exhibit-0", "tbs-source", "tbs-schema", "tbs-section"])
        #expect(request.sources[1].body == "Payment & rate\nYear | Payment\n1 | 100")

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(LearningFeedbackRequest.self, from: encoded)
        #expect(decoded == request)
    }

    @Test func tbsRequestReturnsNilWithoutIncorrectSteps() {
        let model = TbsModel(
            shape: .numeric,
            prompt: "Prompt",
            exhibits: [],
            steps: [RenderStep(id: "s1", label: "Cell 1", weight: 1)]
        )
        let reveal = TbsRevealModel(
            steps: [StepReveal(id: "s1", label: "Cell 1", correctText: "100")],
            source: "Source",
            section: "FAR",
            schemaTag: "schema"
        )

        let request = buildTbsLearningFeedbackRequest(
            title: "TBS feedback",
            model: model,
            reveal: reveal,
            stepResults: [PerformanceStepResult(id: "s1", correct: true, weight: 1)],
            userAnswerText: "100"
        )

        #expect(request == nil)
    }

    @Test func tbsRequestReturnsNilWithoutSources() {
        let model = TbsModel(
            shape: .numeric,
            prompt: " ",
            exhibits: [],
            steps: [RenderStep(id: "s1", label: "Cell 1", weight: 1)]
        )
        let reveal = TbsRevealModel(
            steps: [StepReveal(id: "s1", label: "Cell 1", correctText: "100")],
            source: "",
            section: "",
            schemaTag: ""
        )

        let request = buildTbsLearningFeedbackRequest(
            title: "TBS feedback",
            model: model,
            reveal: reveal,
            stepResults: [PerformanceStepResult(id: "s1", correct: false, weight: 1)],
            userAnswerText: "80"
        )

        #expect(request == nil)
    }
}
