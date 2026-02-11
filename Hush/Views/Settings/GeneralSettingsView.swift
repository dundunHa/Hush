import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HushSpacing.xl) {
                Text("General")
                    .font(HushTypography.heading)

                concurrencySection
            }
            .padding(HushSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var concurrencySection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Text("Concurrency")
                .font(HushTypography.captionBold)
                .foregroundStyle(HushColors.secondaryText)

            HStack(spacing: HushSpacing.md) {
                Text("Max concurrent requests")
                    .font(HushTypography.body)

                Spacer(minLength: 0)

                Picker("", selection: $container.settings.maxConcurrentRequests) {
                    ForEach(1 ... 5, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            Text("Maximum number of conversations that can stream responses simultaneously.")
                .font(HushTypography.caption)
                .foregroundStyle(HushColors.secondaryText)
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: HushColors.cardBackground,
            stroke: HushColors.subtleStroke
        )
    }
}
