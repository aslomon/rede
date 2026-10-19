import SwiftUI

/// Dismissible inline offer in the Models tab: move online rewrite modes to the recommended model.
/// Never silent: nothing changes until the button is pressed, and "nicht jetzt" is remembered.
struct RecommendedModelOfferBanner: View {
  @Bindable var appState: AppState

  private var isVisible: Bool {
    RecommendedModelOffer.isVisible(
      modes: appState.appSettings.modes,
      dismissedOffers: appState.appSettings.dismissedModelOffers,
      onlineRewriteReady: !appState.appSettings.secureLocalModeEnabled && appState.hasOpenAIKey)
  }

  var body: some View {
    if isVisible {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
          Image(systemName: "sparkles")
            .font(.system(size: 11, weight: .semibold))
          Text("GPT-6 Luna für deine rewrite-modi")
            .font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(RedeBrand.violet)

        Text(
          "sehr schnell und günstig. wenn du magst, stellt rede deine online-modi darauf um. "
            + "du kannst jeden modus danach wieder auf ein anderes modell setzen."
        )
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 8) {
          Button {
            appState.appSettings.modes = RecommendedModelOffer.adopting(appState.appSettings.modes)
            dismiss()
          } label: {
            Label("für rewrite-modi übernehmen", systemImage: "checkmark")
          }
          .buttonStyle(PopoverActionButtonStyle(.primary))

          Button("nicht jetzt") { dismiss() }
            .buttonStyle(PopoverActionButtonStyle(.quiet))
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .tintBanner(RedeBrand.violet)
    }
  }

  private func dismiss() {
    appState.appSettings.dismissedModelOffers = RecommendedModelOffer.dismissing(
      appState.appSettings.dismissedModelOffers)
  }
}
