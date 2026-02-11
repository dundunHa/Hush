# 05 — 技术选型（AppKit Single Path）

## 当前选型

- 聊天容器：SwiftUI (`ChatDetailPane` + `ComposerDock`)
- 会话列表渲染：AppKit (`HotScenePool` + `ConversationViewController` + `MessageTableView`)
- 富文本引擎：TextKit (`NSAttributedString` + `NSTextView`)
- Markdown 解析：`swift-markdown`
- 公式渲染：`SwiftMath` + `MathSegmenter` + `MathRenderCache`

## 为什么固定为 AppKit 单路径

- 降低维护成本：避免双路由下的行为分叉与测试重复。
- 提升稳定性：会话切换、流式更新、滚动跟随语义在同一实现内收敛。
- 更易优化：表格增量更新、cell 去重、near-viewport prewarm 都能在同一热路径演进。

## 成本与约束

- AppKit/SwiftUI 边界调试复杂度高于纯 SwiftUI。
- rich render 仍受主线程安全边界约束，需要持续靠缓存与调度降压。
- 任何优化都必须保持 Markdown/LaTeX/表格行为一致，不允许语义回退。

## 备选方案（保留记录）

- 全 SwiftUI 文本栈：实现简单，但复杂富文本和性能控制上限不足。
- WebView 渲染：表达能力强，但集成与资源成本高。
- 自研排版引擎：控制力高，但维护成本不可接受。
