import SwiftUI
import SwiftData

@main
struct CondenseApp: App {

    let container: ModelContainer
    @State private var pipeline: ContentPipeline
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let schema = Schema([Article.self, SummaryLevel.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            self.container = container
            // 演示模式（-demoContent）：空库时注入示例文章，供 UI 测试与截图
            // 在 body 渲染前同步写入 mainContext，LibraryView 的 @Query 首次读取即可命中
            DemoContent.seedIfNeeded(context: container.mainContext)
            _pipeline = State(initialValue: ContentPipeline(context: container.mainContext))
        } catch {
            fatalError("无法创建 SwiftData 容器: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(pipeline)
                // 回到前台时拉取 Share Extension 写入的待处理分享
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task { await pipeline.pullSharedInbox() }
                }
        }
        .modelContainer(container)
    }
}
