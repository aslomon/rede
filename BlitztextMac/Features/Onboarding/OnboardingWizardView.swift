import SwiftUI

/// Root of the first-run wizard hosted in its own window — a real macOS wizard, not a settings
/// window: centered hero (icon tile + headline + subheadline) per step, the step's controls in a
/// constrained column underneath, brand-violet progress dots and a back/continue footer. "später"
/// floats quietly in the top-right corner.
struct OnboardingWizardView: View {
  @Bindable var appState: AppState
  @State private var viewModel: OnboardingViewModel
  /// Tracks direction for asymmetric push transitions.
  @State private var navigatingForward = true
  @Environment(\.colorScheme) private var colorScheme

  /// Closes the wizard window (the "später" link and the red close button share this path).
  let onClose: () -> Void
  /// Finishes onboarding, closes the window, and opens the popover settings.
  let onOpenSettings: () -> Void

  /// Step controls are constrained to a calm single column, Apple-setup-assistant style.
  private static let contentWidth: CGFloat = 440

  init(appState: AppState, onClose: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
    self.appState = appState
    self.onClose = onClose
    self.onOpenSettings = onOpenSettings
    _viewModel = State(initialValue: OnboardingViewModel(appState: appState))
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      VStack(spacing: 0) {
        ScrollView {
          // Hero + step controls move together as ONE page: .id per step gives the container a
          // fresh identity so the directional push transition covers the whole page.
          VStack(spacing: 0) {
            heroHeader
              .padding(.top, 52)
              .padding(.horizontal, 40)

            stepBody
              .frame(maxWidth: Self.contentWidth, alignment: .leading)
              .padding(.top, 24)
              .padding(.horizontal, 32)
              .padding(.bottom, 20)
          }
          .frame(maxWidth: .infinity)
          .id(viewModel.step)
          .transition(
            .asymmetric(
              insertion: .push(from: navigatingForward ? .trailing : .leading),
              removal: .push(from: navigatingForward ? .leading : .trailing)
            )
          )
        }

        footer
      }

      // Quiet escape hatch, out of the main flow (hidden on the last step — the footer offers
      // "zu den einstellungen" there).
      if !viewModel.isLastStep {
        Button("später") { onClose() }
          .buttonStyle(PopoverActionButtonStyle(.quiet))
          .padding(.top, 14)
          .padding(.trailing, 16)
      }
    }
    .frame(minWidth: 620, minHeight: 640)
    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: viewModel.step)
    // Glass backdrop for the entire wizard window.
    .blitztextSurface()
    // rede voice: SF Rounded across the whole wizard window, matching the popover root.
    // Monospaced runs (hotkeys, paths) opt out explicitly with .monospaced.
    .fontDesign(.rounded)
  }

  // MARK: - Hero (icon tile + headline + subheadline)

  private var heroHeader: some View {
    let step = viewModel.step
    return VStack(spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(MenuBarTokens.tintFill(step.accent, colorScheme: colorScheme))
          .frame(width: 64, height: 64)
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(
            MenuBarTokens.tintStroke(step.accent, colorScheme: colorScheme), lineWidth: 0.5
          )
          .frame(width: 64, height: 64)
        Image(systemName: step.systemImage)
          .font(.system(size: 26, weight: .semibold))
          .foregroundStyle(step.accent)
      }
      .accessibilityHidden(true)

      VStack(spacing: 4) {
        Text(step.headline)
          .font(.system(size: 21, weight: .bold, design: .rounded))
          .foregroundStyle(.primary)
        Text(step.subheadline)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 420)
      }
    }
  }

  // MARK: - Step body (controls only — the hero carries title + subtitle)

  @ViewBuilder
  private var stepBody: some View {
    switch viewModel.step {
    case .welcome:
      WelcomeStepView(appState: appState)
    case .installLocation:
      InstallLocationStepView()
    case .permissions:
      PermissionsStepView(appState: appState)
    case .processing:
      ProcessingStepView(appState: appState)
    case .models:
      ModelsStepView(appState: appState)
    case .modes:
      ModesStepView(appState: appState, viewModel: viewModel)
    case .hotkeys:
      HotkeysStepView(appState: appState)
    case .extras:
      ExtrasStepView(appState: appState)
    case .finish:
      FinishStepView(appState: appState, onOpenSettings: openSettings)
    }
  }

  // MARK: - Footer (back · progress dots · continue)

  private var footer: some View {
    ZStack {
      progressDots

      HStack(spacing: 12) {
        if !viewModel.isFirstStep {
          Button {
            back()
          } label: {
            Label("zurück", systemImage: "chevron.left")
          }
          .buttonStyle(PopoverActionButtonStyle(.secondary))
        }

        Spacer()

        if viewModel.isLastStep {
          Button("zu den einstellungen") { openSettings() }
            .buttonStyle(PopoverActionButtonStyle(.secondary))
        }

        primaryButton
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
  }

  /// Brand moment: the active dot is a wide rede-violet capsule, walked dots stay slightly darker
  /// than upcoming ones.
  private var progressDots: some View {
    HStack(spacing: 5) {
      ForEach(OnboardingViewModel.OnboardingStep.allCases) { step in
        Capsule(style: .continuous)
          .fill(dotColor(for: step))
          .frame(width: step == viewModel.step ? 18 : 5, height: 5)
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.step)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "Schritt \(viewModel.step.displayIndex) von \(OnboardingViewModel.stepCount)")
  }

  private func dotColor(for step: OnboardingViewModel.OnboardingStep) -> Color {
    if step == viewModel.step { return RedeBrand.violet }
    return Color.primary.opacity(step.rawValue < viewModel.step.rawValue ? 0.28 : 0.12)
  }

  // DESIGN.md: GlassProminentButtonStyle is the primary CTA in floating surfaces (pill, onboarding
  // footer) — prominent glass on macOS 26, PopoverActionButtonStyle(.primary) on 14–25.
  private var primaryButton: some View {
    Button {
      primaryAction()
    } label: {
      HStack(spacing: 5) {
        Text(viewModel.step.primaryActionLabel)
        if !viewModel.isLastStep {
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
        }
      }
    }
    .buttonStyle(GlassProminentButtonStyle())
    .disabled(!viewModel.canAdvance(appState))
    .modifier(DefaultActionShortcut(isEnabled: viewModel.canAdvance(appState)))
  }

  // MARK: - Actions

  private func back() {
    navigatingForward = false  // set direction before triggering step change
    viewModel.back()
  }

  private func primaryAction() {
    guard viewModel.canAdvance(appState) else { return }
    if viewModel.step == .modes {
      viewModel.persistPrompts(appState)
    }
    if viewModel.isLastStep {
      viewModel.finish(appState)
      onClose()
    } else {
      navigatingForward = true  // set direction before triggering step change
      viewModel.next()
    }
  }

  private func openSettings() {
    viewModel.finish(appState)
    onOpenSettings()
  }
}

/// Binds the Return key (`.defaultAction`) to the primary footer button only while it can advance,
/// so Esc/Return never fire a disabled step transition.
private struct DefaultActionShortcut: ViewModifier {
  let isEnabled: Bool

  func body(content: Content) -> some View {
    if isEnabled {
      content.keyboardShortcut(.defaultAction)
    } else {
      content
    }
  }
}
