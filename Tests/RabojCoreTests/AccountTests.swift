import Foundation
import Testing
@testable import RabojCore

@Suite struct AccountTests {
    @Test func nextColorSkipsUsedColors() {
        #expect(AccountColor.next(after: []) == .blue)
        #expect(AccountColor.next(after: [.blue]) == .orange)
        #expect(AccountColor.next(after: [.blue, .orange]) == .teal)
    }

    @Test func nextColorCyclesWhenAllAreUsed() {
        let all = AccountColor.allCases
        #expect(AccountColor.next(after: all) == all[all.count % all.count])
    }

    @Test func severalAccountsOnTheSameProviderRoundTrip() throws {
        let accounts = [
            Account(provider: .claudeCode, label: "Work", color: .orange),
            Account(provider: .claudeCode, label: "Personal", color: .blue),
            Account(provider: .codex, label: "Codex", color: .teal),
        ]
        let decoded = try JSONDecoder().decode([Account].self, from: JSONEncoder().encode(accounts))
        #expect(decoded == accounts)
        #expect(decoded.filter { $0.provider == .claudeCode }.count == 2)
    }
}
