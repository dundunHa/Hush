import AppKit
import Foundation

#if DEBUG
    extension AppContainer {
        func runAutomationScenarioIfNeeded() {
            guard !Self.didStartAutomationScenario else { return }
            guard let raw = automationScenarioValue(), !raw.isEmpty else { return }

            Self.didStartAutomationScenario = true
            Task(priority: .utility) { @MainActor [weak self] in
                guard let self else { return }
                await self.runAutomationScenario(raw)
            }
        }

        private static var didStartAutomationScenario: Bool = false

        private func automationScenarioValue() -> String? {
            if let raw = ProcessInfo.processInfo.environment["HUSH_AUTOMATION_SCENARIO"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !raw.isEmpty
            {
                return raw
            }

            let arguments = ProcessInfo.processInfo.arguments

            if let index = arguments.firstIndex(of: "--automation-scenario"),
               arguments.indices.contains(index + 1)
            {
                let raw = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                return raw.isEmpty ? nil : raw
            }

            if let argument = arguments.first(where: { $0.hasPrefix("--automation-scenario=") }) {
                let raw = String(argument.dropFirst("--automation-scenario=".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return raw.isEmpty ? nil : raw
            }

            return nil
        }

        private func runAutomationScenario(_ rawScenario: String) async {
            let scenario = rawScenario.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch scenario {
            case "hot-scene-memory":
                await runHotSceneMemoryAutomation()
            case "quickbar-layout":
                runQuickBarLayoutAutomation(showsComplexAssistantReply: false)
            case "quickbar-layout-complex":
                runQuickBarLayoutAutomation(showsComplexAssistantReply: true)
            default:
                return
            }
        }

        private func runHotSceneMemoryAutomation() async {
            guard let persistence else { return }
            let now = Date.now

            func seedConversation(_ conversationId: String, prefix: String) {
                for index in 1 ... 18 {
                    let content = """
                    # \(prefix)\(index)

                    Inline math: $E=mc^2$

                    | a | b | c |
                    |---|---|---|
                    | 1 | 2 | 3 |
                    | 4 | 5 | 6 |
                    | 7 | 8 | 9 |
                    """
                    try? persistence.persistSystemMessage(
                        ChatMessage(role: .assistant, content: content),
                        conversationId: conversationId,
                        status: .completed
                    )
                }
            }

            guard let conversationA = try? persistence.createNewConversation(),
                  let conversationB = try? persistence.createNewConversation(),
                  let conversationC = try? persistence.createNewConversation()
            else { return }

            seedConversation(conversationA, prefix: "A")
            seedConversation(conversationB, prefix: "B")
            seedConversation(conversationC, prefix: "C")

            sidebarThreads = [
                ConversationSidebarThread(id: conversationA, title: "A", lastActivityAt: now),
                ConversationSidebarThread(id: conversationB, title: "B", lastActivityAt: now),
                ConversationSidebarThread(id: conversationC, title: "C", lastActivityAt: now)
            ]

            activateConversation(conversationId: conversationA)
            _ = await waitForAutomationReady(conversationId: conversationA, timeout: .seconds(10))
            try? await Task.sleep(for: .seconds(automationSeconds(for: "HUSH_AUTOMATION_BASELINE_HOLD_S", default: 8)))

            activateConversation(conversationId: conversationB)
            _ = await waitForAutomationReady(conversationId: conversationB, timeout: .seconds(10))
            await Task.yield()

            activateConversation(conversationId: conversationC)
            _ = await waitForAutomationReady(conversationId: conversationC, timeout: .seconds(10))
            try? await Task.sleep(for: .seconds(automationSeconds(for: "HUSH_AUTOMATION_HOT_HOLD_S", default: 14)))

            if automationBool(for: "HUSH_AUTOMATION_EXIT", default: false) {
                NSApp.terminate(nil)
            }
        }

        private func runQuickBarLayoutAutomation(showsComplexAssistantReply: Bool) {
            settings.providerConfigurations = [.mockDefault()]
            settings.selectedProviderID = "mock"
            settings.selectedModelID = "mock-text-1"

            let base = Date.now
            let messages = [
                ChatMessage(
                    role: .user,
                    content: "QuickBar 里用户消息右侧留白看起来比 assistant 左侧更窄，帮我看一下。",
                    createdAt: base.addingTimeInterval(-32)
                ),
                ChatMessage(
                    role: .assistant,
                    content: showsComplexAssistantReply
                        ? """
                        我先把 QuickBar 这里的复杂回复也放进同一个发布态检查里：

                        - 对比 mirrored lane 和 full-width card 的切换
                        - 确认 markdown 列表不会被误压进窄 bubble
                        - 检查 transcript 和 composer 的整体呼吸感
                        """
                        : """
                        我先对比消息容器、文本对齐和 transcript surface 的横向 inset，确认问题是出在 QuickBar 外层宽度，还是单条消息内部的布局约束。
                        """,
                    createdAt: base.addingTimeInterval(-12)
                )
            ]

            configureQuickBarPreview(
                conversationId: "quickbar-layout-automation",
                messages: messages,
                draft: "",
                isExpanded: true,
                isSending: false,
                showQuickBar: true,
                providerID: "mock",
                modelID: "mock-text-1"
            )
        }

        private func waitForAutomationReady(conversationId: String, timeout: Duration) async -> Bool {
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                if activeConversationId == conversationId, statusMessage == "Ready" {
                    return true
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return false
        }

        private func automationSeconds(for key: String, default fallback: Double) -> Double {
            guard let raw = ProcessInfo.processInfo.environment[key]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !raw.isEmpty,
                let seconds = Double(raw)
            else {
                return fallback
            }
            return max(0, seconds)
        }

        private func automationBool(for key: String, default fallback: Bool) -> Bool {
            guard let raw = ProcessInfo.processInfo.environment[key]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            else {
                return fallback
            }
            if raw == "1" || raw == "true" || raw == "yes" { return true }
            if raw == "0" || raw == "false" || raw == "no" { return false }
            return fallback
        }
    }
#endif
