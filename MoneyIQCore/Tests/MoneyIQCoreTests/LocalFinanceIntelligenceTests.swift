import Testing
@testable import MoneyIQCore

@Test func promptUsesBoundedFactsAndQuestion() {
    let facts = (0..<30).map { "Fact \($0)" }
    let prompt = LocalFinanceIntelligence.prompt(facts: facts, question: "Where did I spend the most?")
    #expect(prompt.contains("Fact 23"))
    #expect(!prompt.contains("Fact 24"))
    #expect(prompt.contains("Where did I spend the most?"))
    #expect(prompt.contains("Do not invent transactions"))
}
