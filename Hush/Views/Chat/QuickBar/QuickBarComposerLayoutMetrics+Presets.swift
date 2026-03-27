import SwiftUI

extension QuickBarComposerLayoutMetrics {
    static func `for`(layoutStyle: QuickBarComposerLayoutStyle) -> Self {
        switch layoutStyle {
        case .compact:
            QuickBarComposerLayoutMetrics(
                shellCornerRadius: 34,
                shellHorizontalInset: 18,
                shellTopInset: 16,
                shellBottomInset: 14,
                editorMinHeight: 78,
                editorMaxHeight: 116,
                editorHorizontalPadding: 0,
                editorVerticalPadding: 2,
                placeholderHorizontalInset: 6,
                placeholderTopInset: 6,
                placeholderFontSize: 17,
                editorSurfaceHorizontalInset: 0,
                editorSurfaceVerticalInset: 0,
                toolbarTopPadding: 8,
                toolbarHorizontalInset: 0,
                toolbarBottomPadding: 0,
                toolbarMinHeight: 52,
                toolbarSpacing: 10,
                controlHitSize: 44,
                providerLabelFontSize: 16,
                modelIconSize: 15,
                modelLabelFontSize: 16,
                modelChevronSize: 11,
                capsuleHorizontalPadding: 14,
                capsuleVisualHeight: 36,
                sendButtonHitSize: 44,
                sendButtonVisualSize: 40,
                sendIconSize: 17
            )
        case .expanded:
            QuickBarComposerLayoutMetrics(
                shellCornerRadius: 18,
                shellHorizontalInset: 0,
                shellTopInset: 2,
                shellBottomInset: 0,
                editorMinHeight: 46,
                editorMaxHeight: 64,
                editorHorizontalPadding: 2,
                editorVerticalPadding: 0,
                placeholderHorizontalInset: 4,
                placeholderTopInset: 1,
                placeholderFontSize: 15,
                editorSurfaceHorizontalInset: 3,
                editorSurfaceVerticalInset: 2,
                toolbarTopPadding: 2,
                toolbarHorizontalInset: 3,
                toolbarBottomPadding: 1,
                toolbarMinHeight: 34,
                toolbarSpacing: 6,
                controlHitSize: 36,
                providerLabelFontSize: 13,
                modelIconSize: 14,
                modelLabelFontSize: 13,
                modelChevronSize: 10,
                capsuleHorizontalPadding: 10,
                capsuleVisualHeight: 26,
                sendButtonHitSize: 36,
                sendButtonVisualSize: 30,
                sendIconSize: 15
            )
        }
    }
}
