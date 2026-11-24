import SwiftUI

/// Open at login, which only works from an Applications folder. Elsewhere, StableBar's icon is dragged onto Applications,
/// as in a disk image's window, and the move reopens setup here with the switch on.
struct SetupLoginCard: View {
    let session: SetupSession
    /// Puts setup under Finder, for Show in Finder.
    let reveal: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.offscreenSnapshot) private var offscreen
    @Environment(\.colorScheme) private var colorScheme
    @State private var drag = CGSize.zero
    @State private var dragging = false
    @State private var dropped = false
    /// Counts the icon's landings in the folder, each of which bounces it.
    @State private var landings = 0
    @State private var celebrated: Bool

    init(session: SetupSession, reveal: @escaping () -> Void) {
        self.session = session
        self.reveal = reveal
        _celebrated = State(initialValue: !session.movedToApplications)
    }

    private static let icon = 64.0
    private static let trail = 150.0
    /// From the app's icon to the folder's, middle to middle.
    private static let reach = icon + trail
    private static let glow = Color(red: 1, green: 0.8, blue: 0.45)

    private var move: ApplicationMoveController { session.applicationMove }
    private var glass: GlassPalette { GlassPalette(colorScheme) }
    private var overFolder: Bool { dragging && hypot(drag.width - Self.reach, drag.height) < Self.icon * 0.75 }

    var body: some View {
        Group {
            if session.system.isInApplications() { toggle } else { install }
        }
        .background(glass.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private var toggle: some View {
        let on = session.opensAtLogin
        return HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(on ? .white : glass.ink.opacity(0.4))
                .frame(width: 26, height: 26)
                .background(on ? SettingsPalette.success : glass.ink.opacity(0.1), in: Circle())
                .background {
                    Circle().stroke(SettingsPalette.success, lineWidth: 2)
                        .scaleEffect(celebrated ? 2.4 : 1)
                        .opacity(celebrated || reduceMotion ? 0 : 1)
                }
                .scaleEffect(celebrated || reduceMotion ? 1 : 0.3)
                .opacity(celebrated ? 1 : 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(on ? "Opens at login" : "Open at login").font(.system(size: 13.5, weight: .semibold))
                Text("Starts StableBar when you log in.").font(.system(size: 12)).foregroundStyle(glass.ink.opacity(0.62))
            }
            .opacity(celebrated ? 1 : 0)
            .offset(x: celebrated || reduceMotion ? 0 : -10)
            Spacer(minLength: 12)
            Toggle("Open at login", isOn: Binding(get: { session.opensAtLogin }, set: { session.openAtLogin = $0 }))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(session.finished)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .task {
            guard !celebrated else { return }
            // Lets the reopened card settle before it celebrates.
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(duration: 0.7, bounce: 0.45)) { celebrated = true }
        }
    }

    private var install: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                app.zIndex(1)
                path
                folder
            }
            .disabled(dropped || move.isBusy)
            .accessibilityRepresentation { Button(move.action, action: drop) }
            Group {
                if move.isBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Moving and preparing to relaunch…")
                    }
                } else if let error = move.error {
                    Text(error).foregroundStyle(.orange).textSelection(.enabled)
                } else if let confirmation = move.confirmation {
                    Text(confirmation)
                } else {
                    Text("Drag StableBar to Applications to open it at login.").foregroundStyle(glass.ink.opacity(0.62))
                }
            }
            .font(.system(size: 12.5))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            if !move.isBusy && (move.error != nil || move.offer != nil) {
                HStack(spacing: 8) {
                    if move.offer != nil { Button("Cancel", action: move.cancel) }
                    Button(move.action, action: drop)
                    if move.error != nil { Button("Show in Finder") { reveal(); move.showInFinder() } }
                }
                .buttonStyle(GlassButtonStyle(selected: false, highlighted: true, size: .compact))
                .disabled(dropped)
            }
        }
        .padding(16)
    }

    private var app: some View {
        Image(nsImage: StableBarIcon.image)
            .resizable()
            .frame(width: Self.icon, height: Self.icon)
            .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.35)) {
                $0.scaleEffect(dropped && !reduceMotion ? 0.2 : overFolder ? 0.84 : dragging ? 1.12 : 1)
                    .shadow(color: .black.opacity(dragging ? 0.5 : 0.25), radius: dragging ? 14 : 4, y: dragging ? 10 : 2)
            }
            .offset(dropped && !reduceMotion ? CGSize(width: Self.reach, height: 0) : drag)
            .opacity(dropped ? 0 : 1)
            .linkPointer()
            // Unrestricted focus includes Tab without macOS's Keyboard navigation setting, as on setup's tiles.
            .focusable(!dropped && !move.isBusy)
            .onKeyPress(keys: [.space, .return], phases: .down) { _ in
                drop()
                return .handled
            }
            .onTapGesture(perform: drop)
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in
                    dragging = true
                    drag = value.translation
                }
                .onEnded { _ in
                    if overFolder {
                        drop()
                    } else {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.4)) {
                            drag = .zero
                            dragging = false
                        }
                    }
                })
    }

    /// Dots from the app to the folder, with a glint that runs along them while nothing happens.
    private var path: some View {
        let dots = HStack(spacing: 8) {
            ForEach(0..<10, id: \.self) { _ in Circle().frame(width: 4, height: 4) }
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
        }
        let run = 80.0
        return dots
            .foregroundStyle(overFolder ? Self.glow : glass.ink.opacity(dragging ? 0.5 : 0.25))
            .overlay {
                // The glint runs on its own forever, so a drawing that waits for the card to hold still leaves it out.
                if !reduceMotion && !offscreen && !dragging && !dropped {
                    Capsule().fill(Self.glow).frame(width: 36).blur(radius: 5)
                        .keyframeAnimator(initialValue: -run) { $0.offset(x: $1) } keyframes: { _ in
                            CubicKeyframe(run, duration: 1.4)
                            LinearKeyframe(run, duration: 1.2)
                        }
                        .mask(dots)
                }
            }
            .frame(width: Self.trail)
            .animation(.easeOut(duration: 0.2), value: overFolder)
    }

    private var folder: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: "/Applications"))
            .resizable()
            .frame(width: Self.icon, height: Self.icon)
            .background {
                Circle().fill(Self.glow.opacity(overFolder ? 0.45 : 0)).blur(radius: 16).scaleEffect(1.3)
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.4)) {
                $0.scaleEffect(overFolder ? 1.16 : 1)
                    .shadow(color: Self.glow.opacity(overFolder ? 0.7 : 0), radius: 12)
            }
            .keyframeAnimator(initialValue: 1.0, trigger: landings) { $0.scaleEffect($1) } keyframes: { _ in
                SpringKeyframe(1.2, duration: 0.14)
                SpringKeyframe(0.94, duration: 0.16)
                SpringKeyframe(1, duration: 0.3)
            }
            .linkPointer()
            .onTapGesture(perform: drop)
    }

    /// The move starts as the icon flies into the folder, which bounces. If it asks to confirm or fails, the icon comes
    /// back out. Starting at once keeps Done off while the move runs.
    private func drop() {
        // The icon stays in the folder until its flight and the move attempt finish.
        guard !dropped else { return }
        let flight = reduceMotion ? 0.25 : 0.3
        withAnimation(reduceMotion ? .easeOut(duration: flight) : .easeIn(duration: flight)) {
            dropped = true
            dragging = false
        } completion: {
            if !reduceMotion { landings += 1 }
        }
        Task {
            let landing = ContinuousClock.now + .seconds(flight)
            await move.proceed(resume: session.resumeAfterMoving)
            // A move that asks first returns at once; the icon still reaches the folder before it comes back out.
            try? await Task.sleep(until: landing)
            drag = .zero
            withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .spring(duration: 0.5, bounce: 0.3)) { dropped = false }
        }
    }
}
