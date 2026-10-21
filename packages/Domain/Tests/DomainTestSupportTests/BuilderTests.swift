import Testing
import DomainModels
import DomainTestSupport

@Suite("ExamDefinitionBuilder")
struct ExamDefinitionBuilderTests {
    @Test("alphaLike は fixture の test-alpha と同じ形(ドメイン 6、120 分、55 問、ケースあり)")
    func alphaLike() {
        // Act
        let definition = ExamDefinitionBuilder.alphaLike().build()
        // Assert
        #expect(definition.domains.map(\.id) == [1, 2, 3, 4, 5, 6])
        #expect(definition.format.durationMinutes == 120)
        #expect(definition.format.mockExam.questionCount == 55)
        #expect(definition.features.caseStudies)
        #expect(definition.caseStudies.count == definition.format.mockExam.caseStudiesPerSet)
        #expect(definition.format.questionKinds == [.single, .multiple])
    }

    @Test("betaLike は fixture の test-beta と同じ形(ドメイン 4、90 分、40 問、ケースなし、single のみ)")
    func betaLike() {
        // Act
        let definition = ExamDefinitionBuilder.betaLike().build()
        // Assert
        #expect(definition.domains.map(\.id) == [1, 2, 3, 4])
        #expect(definition.format.durationMinutes == 90)
        #expect(definition.format.mockExam.questionCount == 40)
        #expect(!definition.features.caseStudies)
        #expect(definition.caseStudies.isEmpty)
        #expect(definition.format.mockExam.caseStudiesPerSet == 0)
        #expect(definition.format.questionKinds == [.single])
        #expect(definition.domainBySubObjective["NET.1"] == 2)
    }

    @Test("比重の合計が 1", arguments: [ExamDefinitionBuilder.alphaLike(), .betaLike()])
    func weightsSumToOne(builder: ExamDefinitionBuilder) {
        // Act
        let total = builder.build().domains.map(\.weight).reduce(0, +)
        // Assert
        #expect(approximatelyEqual(total, 1))
    }

    @Test("with でテストに関係する値だけを変えられる")
    func withOverridesValue() {
        // Act
        let definition = ExamDefinitionBuilder.betaLike().with(\.format.durationMinutes, 30).build()
        // Assert
        #expect(definition.format.durationMinutes == 30)
        #expect(definition.format.mockExam.questionCount == 40)
    }
}

@Suite("QuestionBuilder")
struct QuestionBuilderTests {
    @Test("multiple は指定した正解の選択肢を持つ")
    func multipleHasRequestedCorrectCount() {
        // Act
        let question = QuestionBuilder.multiple(count: 2, correct: ["a", "c"]).build()
        // Assert
        #expect(question.correctChoiceIDs == ["a", "c"])
        #expect(question.type == .multiple(count: 2))
    }

    @Test("single の既定値は正解 1 つで、選択肢は Schema の下限(4 つ)以上")
    func singleDefaults() {
        // Act
        let question = QuestionBuilder.single().build()
        // Assert
        #expect(question.type == .single)
        #expect(question.correctChoiceIDs == ["a"])
        #expect(question.choices.count >= 4)
    }

    @Test("with でテストに関係する値だけを変えられる")
    func withOverridesValue() {
        // Act
        let question = QuestionBuilder.single(correct: "b")
            .with(\.id, "Q-2.1-0001")
            .with(\.domain, 2)
            .with(\.subObjective, "2.1")
            .build()
        // Assert
        #expect(question.id == "Q-2.1-0001")
        #expect(question.domain == 2)
        #expect(question.subObjective == "2.1")
        #expect(question.correctChoiceIDs == ["b"])
    }
}
