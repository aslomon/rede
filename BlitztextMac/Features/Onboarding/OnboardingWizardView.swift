import SwiftUI

/// Root of the first-run wizard hosted in its own window. The wizard is a setup journey: each step
/// has one decision/status, visible buttons, and compact progress.
struct OnboardingWizardView: View {
  @Bindable var appState: AppState
  @State private var viewModel: OnboardingViewModel
  /// Tracks direction for asymmetric push transitions.
  @State private var navigatingForward = true

  /// Closes the wizard window (the "später" link and the red close button share this path).
  let onClose: () -> Void
  /// Finishes onboarding, closes the window, and opens the popover settings.
  let onOpenSettings: () -> Void

  init(appState: AppState, onClose: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
    self.appState = appState
    self.onClose = onClose
    self.onOpenSettings = onOpenSettings
    _viewModel = State(initialValue: OnboardingViewModel(appState: appState))
  }

  var body: some View {
    HStack(spacing: 0) {
      // Persistent brand rail (uniform across all steps) instead of a per-page top header.
      sidebar
      Divider().opacity(0.5)

      VStack(spacing: 0) {
        ScrollView {
          stepBody
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Asymmetric directional push transition (change 5)
            .transition(
              .asymmetric(
                insertion: .push(from: navigatingForward ? .trailing : .leading),
                removal: .push(from: navigatingForward ? .leading : .trailing)
              )
            )
        }
        footer
      }
    }
    .frame(minWidth: 680, minHeight: 520)
    // Replaced .easeInOut(duration: 0.18) with spring (change 5)
    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: viewModel.step)
    // Glass backdrop for the entire wizard window (change 1)
    .blitztextSurface()
    // rede voice: SF Rounded across the whole wizard window, matching the popover root.
    // Monospaced runs (hotkeys, paths) opt out explicitly with .monospaced.
    .fontDesign(.rounded)
  }

  // MARK: - Sidebar (brand rail)

  /// Left rail: the rede wordmark + the full step list with the current step highlighted and
  /// completed steps check-marked. Replaces the old top header + segmented progress so the wizard
  /// reads as one uniform surface, not a page with a header.
  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        BrandMark(size: 20)
        Wordmark(size: 16)
      }
      .padding(.bottom, 24)

      VStack(alignment: .leading, spacing: 2) {
        ForEach(OnboardingViewModel.OnboardingStep.allCases) { step in
          stepRailRow(step)
        }
      }

      Spacer(minLength: 16)

      Text("schritt \(viewModel.step.displayIndex) von \(OnboardingViewModel.stepCount)")
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
    }
    // Extra top padding clears the floating traffic lights (full-size-content title bar).
    .padding(.horizontal, 20)
    .padding(.top, 38)
    .padding(.bottom, 20)
    .frame(width: 196)
    .frame(maxHeight: .infinity, alignment: .topLeading)
  }

  private func stepRailRow(_ step: OnboardingViewModel.OnboardingStep) -> some View {
    let isActive = step == viewModel.step
    let isPast = step.rawValue < viewModel.step.rawValue
    return HStack(spacing: 10) {
      ZStack {
        Circle()
          .fill(isActive ? step.accent.opacity(0.18) : Color.clear)
          .frame(width: 24, height: 24)
        Image(systemName: isPast ? "checkmark" : step.systemImage)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(
            isActive
              ? AnyShapeStyle(step.accent)
              : (isPast ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)))
      }
      Text(step.title)
        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
        .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
      Spacer(minLength: 0)
    }
    .padding(.vertical, 5)
    .padding(.horizontal, 8)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(isActive ? Color.primary.opacity(0.05) : Color.clear)
    )
    .animation(.easeInOut(duration: 0.2), value: viewModel.step)
  }

  // MARK: - Step body

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

  // MARK: - Footer

  private var footer: some View {
    HStack(spacing: 12) {
      if !viewModel.isFirstStep {
        Button {
          back()
        } label: {
          Label("zurück", systemImage: "chevron.left")
        }
        .buttonStyle(PopoverActionButtonStyle(.secondary))
        .font(.system(size: 12, weight: .medium))
      }

      Spacer()

      if viewModel.isLastStep {
        // On the Finish step: replace 'später' with 'zu den einstellungen' (change 4)
        Button("zu den einstellungen") { openSettings() }
          .buttonStyle(PopoverActionButtonStyle(.secondary))
          .font(.system(size: 11.5))
      } else {
        // On all other steps: keep 'später' but remove .cancelAction shortcut (change 3)
        Button("später") { onClose() }
          .buttonStyle(PopoverActionButtonStyle(.quiet))
          .font(.system(size: 11.5))
        // Note: .keyboardShortcut(.cancelAction) intentionally removed so Esc does not
        // close the wizard while a TextField is focused on the welcome step.
      }

      primaryButton
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
  }

  // DESIGN.md: GlassProminentButtonStyle is the primary CTA in floating surfaces (pill, onboarding
  // footer) — prominent glass on macOS 26, PopoverActionButtonStyle(.primary) on 14–25.
  private var primaryButton: some View {
    Button {
      primaryAction()
    } label: {
      Text(viewModel.step.primaryActionLabel)
        .font(.system(size: 12.5, weight: .semibold))
    }
    .buttonStyle(GlassProminentButtonStyle())
    .disabled(!viewModel.canAdvance(appState))
    .modifier(DefaultActionShortcut(isEnabled: viewModel.canAdvance(appState)))
  }

  // MARK: - Actions

  private func back() {
    navigatingForward = false  // set direction before triggering step change (change 5)
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
      navigatingForward = true  // set direction before triggering step change (change 5)
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
