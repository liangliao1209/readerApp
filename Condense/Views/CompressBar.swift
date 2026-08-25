import SwiftUI

/// 核心交互：底部贯穿屏幕的压缩 bar。
/// 手指向上推，内容随手势在 0-4 五个压缩级别间连续切换；
/// 松手后吸附到最近的级别。
struct CompressBar: View {

    @Binding var compression: Double
    @Binding var displayedLevel: Int

    /// 每上推多少 pt 提升一级
    private let pointsPerLevel: Double = 64

    @State private var isDragging = false
    @State private var dragBase: Double = 0

    var body: some View {
        VStack(spacing: 10) {
            // 当前级别标签
            Text(SummaryLevel.label(for: displayedLevel))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.2), value: displayedLevel)

            HStack(spacing: 14) {
                LevelIndicator(level: displayedLevel)

                Spacer()

                Image(systemName: "chevron.up.2")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("上推压缩")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        // 让整条 bar（含底部留白）都可拖动
        .contentShape(Rectangle())
        .gesture(dragGesture)
        // 拖动时轻微放大，提示可交互
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .animation(.spring(duration: 0.25), value: isDragging)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragBase = compression
                }
                // 上推 translation.height 为负 → 压缩级别上升
                let raw = dragBase - Double(value.translation.height) / pointsPerLevel
                compression = min(max(raw, 0), 4)
                // 吸附阈值：越过 0.6 才进入下一级，避免边界抖动
                displayedLevel = min(max(Int(floor(compression + 0.4)), 0), 4)
            }
            .onEnded { _ in
                isDragging = false
                let snapped = min(max(Int(compression.rounded()), 0), 4)
                withAnimation(.spring(duration: 0.3)) {
                    compression = Double(snapped)
                    displayedLevel = snapped
                }
            }
    }
}
