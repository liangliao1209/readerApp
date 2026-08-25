import SwiftUI

/// 压缩级别指示器：5 段胶囊，当前级高亮
struct LevelIndicator: View {

    let level: Int
    var count: Int = 5

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index <= level ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: index == level ? 22 : 10, height: 8)
                    .animation(.spring(duration: 0.25), value: level)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("压缩级别：\(SummaryLevel.label(for: level))")
    }
}

#Preview {
    VStack(spacing: 16) {
        LevelIndicator(level: 0)
        LevelIndicator(level: 2)
        LevelIndicator(level: 4)
    }
    .padding()
}
