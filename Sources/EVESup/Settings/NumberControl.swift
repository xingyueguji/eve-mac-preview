import SwiftUI

/// A whole number you can drag with a slider, type into the box, or nudge with − / +.
///
/// Typed values apply on Return or when the box loses focus, and are clamped
/// to the range. `onCommit` runs after a typed or stepped change, or when the
/// slider is released, so expensive updates don't run on every slider tick.
struct NumberControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var unit = "pt"
    var showsSlider = true
    var onCommit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            if showsSlider {
                Slider(value: Binding(get: { value }, set: { value = $0.rounded() }), in: range) { editing in
                    if !editing { onCommit() }
                }
                .frame(width: 180)
            }
            TextField("", value: Binding(get: { value }, set: apply), format: .number.precision(.fractionLength(0)).grouping(.never))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 58)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
            Stepper("", value: Binding(get: { value }, set: apply), in: range, step: step)
                .labelsHidden()
        }
    }

    private func apply(_ newValue: Double) {
        let clamped = min(max(newValue.rounded(), range.lowerBound), range.upperBound)
        let changed = clamped != value
        // Assign even when unchanged, so an out-of-range entry snaps back in the box.
        value = clamped
        if changed { onCommit() }
    }
}
