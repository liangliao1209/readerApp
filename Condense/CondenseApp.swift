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
