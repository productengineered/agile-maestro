import SwiftUI

// MARK: - DirectoryHealthView
// Purpose: Dashboard showing directory health stats (agents, commands, skills, rules),
// last-updated timestamp, and an "Update Team Info" button.
//
// Layout: ScrollView → VStack(spacing: 0) — centered in the detail column.
// Stat chips: HStack of 4 StatChipView instances.
// Counter animation: SM-TEAM-005 — on .onAppear and on manifest reload,
//   @State displayValues animate from 0 to target using an async Task loop at 60fps.
//
// IS-TV-COUNTER-001: counter counts 0→target over 0.6s with easeOut curve.
// IS-TV-COUNTER-002: reduce motion — jump directly to final value.
// IS-TV-UPDATE-001: button swaps to ProgressView while updating, then restores.
//
// Timestamp accent flash: on successful update, timestamp text color flashes
//   .accentColor then fades to .tertiary over 0.5s.
struct DirectoryHealthView: View {
    let health: DirectoryHealth
    let generatedAt: String       // ISO8601 string from manifest
    let isUpdating: Bool
    let onUpdate: () async -> Void

    // MARK: - Counter Animation State (SM-TEAM-005 / IS-TV-COUNTER-001)
    // Each stat has a display value that counts from 0 to target.
    // Int does not conform to VectorArithmetic — SwiftUI cannot interpolate it via withAnimation.
    // Instead, an async Task fires updates at ~60fps for 0.6s and increments each counter
    // proportionally toward its target via an easeOut curve.
    // .contentTransition(.numericText()) on the Text provides the rolling digit visual.
    @State private var displayAgents: Int = 0
    @State private var displayCommands: Int = 0
    @State private var displaySkills: Int = 0
    @State private var displayRules: Int = 0
    @State private var animationTask: Task<Void, Never>?

    // Timestamp accent flash
    @State private var timestampFlash: Bool = false

    // IS-TV-COUNTER-002: reduce motion — skip counting animation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Computed

    private var formattedTimestamp: String {
        guard !generatedAt.isEmpty else { return "Unknown" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: generatedAt) {
            let relFormatter = RelativeDateTimeFormatter()
            relFormatter.unitsStyle = .abbreviated
            return relFormatter.localizedString(for: date, relativeTo: Date())
        }
        // Fallback: try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: generatedAt) {
            let relFormatter = RelativeDateTimeFormatter()
            relFormatter.unitsStyle = .abbreviated
            return relFormatter.localizedString(for: date, relativeTo: Date())
        }
        return generatedAt
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 48)

                // MARK: Section Header
                Text("DIRECTORY HEALTH")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.5)
                    .padding(.bottom, 32)
                    .accessibilityHidden(true)

                // MARK: Stat Chips Row
                HStack(spacing: 32) {
                    StatChipView(
                        displayValue: displayAgents,
                        label: "Agents",
                        symbolName: "person.3.fill"
                    )
                    StatChipView(
                        displayValue: displayCommands,
                        label: "Commands",
                        symbolName: "terminal"
                    )
                    StatChipView(
                        displayValue: displaySkills,
                        label: "Skills",
                        symbolName: "star.fill"
                    )
                    StatChipView(
                        displayValue: displayRules,
                        label: "Rules",
                        symbolName: "list.bullet.clipboard"
                    )
                }
                .padding(.bottom, 32)

                // MARK: Divider
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(maxWidth: 400)
                    .frame(height: 1)
                    .padding(.bottom, 24)

                // MARK: Timestamp Row
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)

                    Text("Last updated \(formattedTimestamp)")
                        .font(.caption)
                        // Timestamp flash: accent for 0.5s after refresh, then tertiary
                        .foregroundStyle(
                            timestampFlash
                                ? AnyShapeStyle(Color.accentColor)
                                : AnyShapeStyle(.tertiary)
                        )
                        .animation(.easeInOut(duration: 0.3), value: timestampFlash)
                        .accessibilityLabel("Last updated \(formattedTimestamp)")
                }
                .padding(.bottom, 24)

                // MARK: Update Button (IS-TV-UPDATE-001)
                Button {
                    Task { await onUpdate() }
                } label: {
                    HStack(spacing: 8) {
                        if isUpdating {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .symbolRenderingMode(.monochrome)
                                .symbolEffect(.rotate, isActive: isUpdating)
                        }
                        Text(isUpdating ? "Updating\u{2026}" : "Update Team Info")
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isUpdating)
                .animation(.easeInOut(duration: 0.3), value: isUpdating)
                .accessibilityLabel(isUpdating ? "Updating team info" : "Update team info")
                .accessibilityHint("Runs the manifest generation script to refresh team data")

                Spacer(minLength: 48)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
        }
        .onAppear {
            animateCounters()
        }
        .onChange(of: health) { _, _ in
            // Manifest reloaded — replay counter animation (SM-TEAM-005)
            animateCounters()
            // Flash timestamp accent color on successful refresh
            flashTimestamp()
        }
    }

    // MARK: - Counter Animation (SM-TEAM-005 / IS-TV-COUNTER-001)
    //
    // WHY NOT withAnimation: Int does not conform to VectorArithmetic. SwiftUI cannot
    // interpolate Int values with withAnimation — the value jumps directly to the target.
    // .contentTransition(.numericText()) only provides the rolling digit visual; it does
    // not drive the counting itself.
    //
    // CORRECT APPROACH: An async Task fires updates at ~60fps over 0.6 seconds.
    // Each tick computes the easeOut-curved fraction of elapsed time and sets each
    // display value to floor(eased * target). This produces a smooth 0→target count
    // that pairs with .contentTransition.
    //
    // IS-TV-COUNTER-002 (reduce motion): jump directly to final values, no loop.
    private func animateCounters() {
        // Reset to 0 before animating
        displayAgents = 0
        displayCommands = 0
        displaySkills = 0
        displayRules = 0

        // Cancel any in-progress animation
        animationTask?.cancel()

        if reduceMotion {
            // IS-TV-COUNTER-002: skip animation, jump to final values immediately
            displayAgents = health.agentCount
            displayCommands = health.commandCount
            displaySkills = health.skillCount
            displayRules = health.ruleCount
            return
        }

        let duration: TimeInterval = 0.6
        let startTime = Date()
        let targetAgents = health.agentCount
        let targetCommands = health.commandCount
        let targetSkills = health.skillCount
        let targetRules = health.ruleCount

        animationTask = Task { @MainActor in
            let intervalNanos: UInt64 = 16_666_667 // ~60fps (1/60s in nanoseconds)
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)
                let fraction = min(elapsed / duration, 1.0)

                // EaseOut curve: fraction = 1 - (1 - t)^2
                let eased = 1.0 - pow(1.0 - fraction, 2.0)

                displayAgents = Int(eased * Double(targetAgents))
                displayCommands = Int(eased * Double(targetCommands))
                displaySkills = Int(eased * Double(targetSkills))
                displayRules = Int(eased * Double(targetRules))

                if fraction >= 1.0 {
                    // Ensure exact final values (guard against floating-point rounding)
                    displayAgents = targetAgents
                    displayCommands = targetCommands
                    displaySkills = targetSkills
                    displayRules = targetRules
                    break
                }

                try? await Task.sleep(nanoseconds: intervalNanos)
            }
        }
    }

    // MARK: - Timestamp Flash

    private func flashTimestamp() {
        timestampFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.5)) {
                timestampFlash = false
            }
        }
    }
}

// MARK: - StatChipView
//
// Purpose: One health metric — large light-weight number over uppercase tracked label.
// Tier 2 Signature typography: 32pt .light for the number, 10pt .semibold uppercase for label.
// Size contrast: 3.2x (32pt / 10pt) — strong visual hierarchy.
// Background: .ultraThinMaterial in RoundedRectangle(cornerRadius: 12).
// Accessibility: combined label "[count] [label]" — children ignored.
struct StatChipView: View {
    let displayValue: Int
    let label: String
    let symbolName: String

    var body: some View {
        VStack(spacing: 6) {
            // MARK: Large Number (Tier 2 Signature)
            // .light weight for large display numbers per design system:
            // "ultraLight/light for large display text > 24pt"
            Text("\(displayValue)")
                .font(.system(size: 32, weight: .light))
                .monospacedDigit()
                .foregroundStyle(.primary)
                // .contentTransition provides rolling digit visual on each state update.
                // The parent drives displayValue via a Task loop (not withAnimation on Int).
                .contentTransition(.numericText(countsDown: false))
                .animation(.easeOut(duration: 0.08), value: displayValue)

            // MARK: Label (Tier 2 Signature — uppercase tracked small)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1.0)
        }
        .frame(minWidth: 72)
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        // MARK: Accessibility — chip announces as single element
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayValue) \(label)")
    }
}

// MARK: - Previews

#Preview("Directory Health \u{2014} Loaded") {
    DirectoryHealthView(
        health: DirectoryHealth(agentCount: 15, commandCount: 45, skillCount: 48, ruleCount: 15),
        generatedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-180)),
        isUpdating: false,
        onUpdate: {}
    )
    .frame(width: 800, height: 500)
    .preferredColorScheme(.dark)
}

#Preview("Directory Health \u{2014} Updating") {
    DirectoryHealthView(
        health: DirectoryHealth(agentCount: 15, commandCount: 45, skillCount: 48, ruleCount: 15),
        generatedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60)),
        isUpdating: true,
        onUpdate: {}
    )
    .frame(width: 800, height: 500)
    .preferredColorScheme(.dark)
}

#Preview("Directory Health \u{2014} Outdated") {
    DirectoryHealthView(
        health: DirectoryHealth(agentCount: 15, commandCount: 45, skillCount: 48, ruleCount: 15),
        generatedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600)),
        isUpdating: false,
        onUpdate: {}
    )
    .frame(width: 800, height: 500)
    .preferredColorScheme(.light)
}

#Preview("Stat Chip") {
    HStack(spacing: 24) {
        StatChipView(displayValue: 15, label: "Agents", symbolName: "person.3.fill")
        StatChipView(displayValue: 45, label: "Commands", symbolName: "terminal")
        StatChipView(displayValue: 48, label: "Skills", symbolName: "star.fill")
        StatChipView(displayValue: 15, label: "Rules", symbolName: "list.bullet.clipboard")
    }
    .padding(32)
    .preferredColorScheme(.dark)
}
