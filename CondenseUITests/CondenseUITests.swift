import XCTest

/// 演示流程 UI 测试：
/// 以 -demoContent 启动 → 书库出现演示文章 → 进入阅读页 →
/// 逐级上推压缩 bar → 每级截屏存为 XCTAttachment
final class CondenseUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demoContent"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testDemoFlow() throws {
        // 1. 书库应出现两篇演示文章
        let firstCard = app.buttons["articleCard"].firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 10), "书库未出现演示文章")
        XCTAssertTrue(app.staticTexts["注意力经济：你的专注力正在被明码标价"].exists)
        takeScreenshot(named: "library")

        // 2. 点进第一篇（排序按创建时间倒序，第一篇是「注意力经济」）
        firstCard.tap()

        // 3. 阅读页出现正文（level 0 全文）
        let content = app.descendants(matching: .any)["readerContent"].firstMatch
        guard content.waitForExistence(timeout: 5) else {
            print(app.debugDescription)
            XCTFail("阅读页内容未出现")
            return
        }
        XCTAssertTrue(app.staticTexts["全文"].waitForExistence(timeout: 3), "初始级别应为「全文」")

        let bar = app.descendants(matching: .any)["compressBar"].firstMatch
        guard bar.waitForExistence(timeout: 5) else {
            print(app.debugDescription)
            XCTFail("压缩 bar 未出现")
            return
        }

        // 4. 逐级上推压缩 bar，断言级别标签变化并截屏
        // CompressBar 每 64pt 提升一级；每次拖拽 90pt（≈1.4 级），松手吸附后恰好 +1 级
        let expectedLabels = ["章节要点", "段落摘要", "三句话", "一句话"]
        for (index, label) in expectedLabels.enumerated() {
            dragCompressBarUp(bar)
            let levelLabel = app.staticTexts["compressLevelLabel"]
            XCTAssertTrue(
                waitForLabel(label, element: levelLabel, timeout: 5),
                "第 \(index + 1) 次拖拽后级别应为「\(label)」，实际为「\(levelLabel.label)」"
            )
            takeScreenshot(named: "level\(index + 1)-\(label)")
        }
    }

    // MARK: - 辅助

    /// 以带 velocity 的 coordinate 拖拽模拟上推手势（DragGesture minimumDistance: 0）
    private func dragCompressBarUp(_ bar: XCUIElement) {
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: -90))
        start.press(forDuration: 0.15, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0.1)
    }

    /// 等待级别标签文本变化（XCUITest 的 label 断言需要轮询，不能用 predicate 查 staticText 的 label）
    private func waitForLabel(_ expected: String, element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.label == expected { return true }
            usleep(100_000)
        }
        return element.exists && element.label == expected
    }

    private func takeScreenshot(named name: String) {
        // 等待动画稳定，避免截到过渡帧
        usleep(400_000)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
