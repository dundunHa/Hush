import SwiftUI

struct CardStyle: ViewModifier {
    let background: Color
    let stroke: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(background, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(stroke, lineWidth: 1))
    }
}

extension View {
    func cardStyle(
        background: Color,
        stroke: Color,
        cornerRadius: CGFloat = HushSpacing.cardCornerRadius
    ) -> some View {
        modifier(CardStyle(background: background, stroke: stroke, cornerRadius: cornerRadius))
    }
}
