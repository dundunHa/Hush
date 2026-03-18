import Foundation
@testable import Hush
import Testing

struct StreamingPresentationPolicyTests {
    @Test("Production streaming policy caps the fastest visible rate at forty characters per second")
    func productionPolicyCapsFastestRateAtFortyCharactersPerSecond() {
        let policy = StreamingPresentationPolicy.production

        #expect(policy.initialRevealCharacters == 1)
        #expect(policy.minimumCharactersPerSecond == 20)
        #expect(policy.fastestCharactersPerSecond == 40)
        #expect(policy.targetBacklogLagSeconds == 2.0)
        #expect(policy.charactersPerSecond(forPendingCharacters: 1, isTerminalCatchUp: false) == 20)
        #expect(policy.charactersPerSecond(forPendingCharacters: 20, isTerminalCatchUp: false) == 20)
        #expect(policy.charactersPerSecond(forPendingCharacters: 30, isTerminalCatchUp: false) == 20)
        #expect(policy.charactersPerSecond(forPendingCharacters: 80, isTerminalCatchUp: false) == 40)
        #expect(policy.charactersPerSecond(forPendingCharacters: 200, isTerminalCatchUp: true) == 40)
        #expect(policy.terminalForceRevealAfter == nil)
    }

    @Test("Testing policy remains much faster than production")
    func ingPolicyRemainsFast() {
        let production = StreamingPresentationPolicy.production
        let testing = StreamingPresentationPolicy.testingFast

        #expect(testing.fastestCharactersPerSecond > production.fastestCharactersPerSecond)
        #expect(testing.revealTickInterval < production.revealTickInterval)
    }
}
