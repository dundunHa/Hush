import SwiftUI

private struct LeadingPaneBorderMask: View {
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    private var leadingMaskWidth: CGFloat {
        max(topRadius, bottomRadius) + 2
    }

    var body: some View {
        if bottomRadius > 0 {
            Rectangle()
                .frame(width: leadingMaskWidth)
        } else if topRadius > 0 {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .frame(width: 2)

                Rectangle()
                    .frame(width: topRadius + 2)
                    .padding(.bottom, 1)
            }
        } else {
            Rectangle()
                .frame(width: 1)
        }
    }
}

struct LeadingPaneBorder: View {
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    let color: Color

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )

        shape
            .strokeBorder(color, lineWidth: 1)
            .mask(alignment: .leading) {
                LeadingPaneBorderMask(topRadius: topRadius, bottomRadius: bottomRadius)
            }
    }
}
