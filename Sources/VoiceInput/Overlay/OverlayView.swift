import SwiftUI

struct OverlayView: View {
    private let barHeights: [CGFloat] = [10, 18, 28, 20, 34, 24, 15, 26, 12]

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 4, height: height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 16))
    }
}
