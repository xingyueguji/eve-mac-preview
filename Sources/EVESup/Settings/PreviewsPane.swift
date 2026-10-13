import EVESupCore
import SwiftUI

struct PreviewsPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let previews = $state.config.previews
        let current = state.config.previews

        Form {
            Section {
                Toggle("Show previews", isOn: previews.isEnabled)
                LabeledContent("Frame rate") {
                    HStack {
                        Slider(value: wholeNumbers(previews.framesPerSecond), in: 1...30)
                            .frame(width: 220)
                        Text("\(Int(current.framesPerSecond)) fps")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                Toggle("Show on every desktop and over full-screen EVE", isOn: previews.showsOnAllSpaces)
            } header: {
                Text("Previews")
            } footer: {
                if !state.permissions.screenRecording {
                    Label("Previews and character names need Screen Recording. Turn it on in General.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Text("Lower frame rates use less power. 10–15 fps is plenty for watching other clients.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                sizeSlider("Width", value: previews.defaultWidth, range: 100...640)
                sizeSlider("Height", value: previews.defaultHeight, range: 60...400)
            } header: {
                Text("Size")
            } footer: {
                Text("Changing the size resizes every preview. You can still resize one preview by dragging its bottom-right corner.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: previews.snapsToGrid) {
                    Text("Snap to grid")
                    Text("Dragging moves a preview in grid steps, and resizing snaps to whole cells, so previews line up without fine adjustment.")
                }
                LabeledContent("Grid size") {
                    HStack(spacing: 18) {
                        Stepper("Width \(Int(current.gridWidth)) pt", value: previews.gridWidth, in: 5...200, step: 5)
                        Stepper("Height \(Int(current.gridHeight)) pt", value: previews.gridHeight, in: 5...200, step: 5)
                    }
                    .monospacedDigit()
                }
                .disabled(!current.snapsToGrid)
                Toggle("Lock preview positions", isOn: previews.locksPositions)
                HStack {
                    Spacer()
                    Button("Align All Previews to Grid", action: state.alignPreviewsToGrid)
                        .disabled(!current.snapsToGrid)
                    Button("Rearrange Previews", action: state.rearrangePreviews)
                }
            } header: {
                Text("Position")
            } footer: {
                Text("The grid starts at the top-left of the screen, just below the menu bar. Align moves existing previews to the nearest grid point; Rearrange lines them all up in rows along the top.")
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Toggle(isOn: previews.isBorderless) {
                    Text("Borderless previews")
                    Text("Only the picture: no background, shadow or rounded corners.")
                }
                LabeledContent("Opacity when not in front") {
                    HStack {
                        Slider(value: previews.inactiveOpacity, in: 0.2...1)
                            .frame(width: 220)
                        Text("\(Int((current.inactiveOpacity * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                Toggle("Highlight the client you're on", isOn: previews.highlightsActive)
                ColorPicker("Highlight color", selection: color(\.highlightColor), supportsOpacity: false)
                    .disabled(!current.highlightsActive)
                LabeledContent("Highlight thickness") {
                    Stepper("\(Int(current.highlightThickness)) pt", value: previews.highlightThickness, in: 1...6, step: 1)
                }
                .disabled(!current.highlightsActive)
            }

            Section {
                Toggle("Show character name", isOn: previews.showsName)
                Group {
                    Picker("Font", selection: previews.label.fontFamily) {
                        Text("System").tag(String?.none)
                        Divider()
                        ForEach(NameLabelStyle.availableFamilies, id: \.self) { family in
                            Text(family).tag(String?.some(family))
                        }
                    }
                    LabeledContent("Text size") {
                        HStack {
                            Slider(value: wholeNumbers(previews.label.fontSize), in: 8...32)
                                .frame(width: 220)
                            Text("\(Int(current.label.fontSize)) pt")
                                .monospacedDigit()
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                    Toggle("Bold", isOn: previews.label.isBold)
                    ColorPicker("Text color", selection: color(\.label.color), supportsOpacity: false)
                    LabeledContent("Dark box behind the name") {
                        HStack {
                            Slider(value: previews.label.backgroundOpacity, in: 0...1)
                                .frame(width: 220)
                            Text(current.label.backgroundOpacity < 0.01 ? "Off" : "\(Int((current.label.backgroundOpacity * 100).rounded()))%")
                                .monospacedDigit()
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                    LabeledContent("Sample") {
                        LabelSample(style: current.label)
                    }
                }
                .disabled(!current.showsName)
            } header: {
                Text("Character name")
            } footer: {
                Text("Applies to the name on every preview. With the box off, the text gets a soft shadow so it stays readable.")
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Hide the preview of the client you're on", isOn: previews.hidesActiveClient)
                Toggle("Only show previews while EVE is in front", isOn: previews.onlyWhileEVEActive)
            }

            Section("Mouse") {
                MouseHelpRow(gesture: "Click", effect: "Switch to that client")
                MouseHelpRow(gesture: "⇧-click", effect: "Skip that client when cycling (click again to include it)")
                MouseHelpRow(gesture: "Drag", effect: "Move the preview")
                MouseHelpRow(gesture: "Drag bottom-right corner", effect: "Resize the preview")
                MouseHelpRow(gesture: "Right-click", effect: "More options, such as hiding a preview")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Previews")
    }

    private func sizeSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: wholeNumbers(value), in: range) { editing in
                    if !editing { state.applyDefaultThumbnailSize() }
                }
                .frame(width: 220)
                Text("\(Int(value.wrappedValue)) pt")
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }

    /// Rounds slider values. A stepped Slider would draw hundreds of tick marks.
    private func wholeNumbers(_ value: Binding<Double>) -> Binding<Double> {
        Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0.rounded() })
    }

    private func color(_ keyPath: WritableKeyPath<PreviewSettings, RGBAColor>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(state.config.previews[keyPath: keyPath])) },
            set: { state.config.previews[keyPath: keyPath] = RGBAColor(NSColor($0)) }
        )
    }
}

/// The character name drawn the way previews will draw it, over a mock scene.
private struct LabelSample: View {
    let style: NameLabelStyle

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.12, blue: 0.3), Color(red: 0.55, green: 0.78, blue: 0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text("Example Pilot")
                .font(Font(style.font as CTFont))
                .foregroundStyle(Color(nsColor: NSColor(style.color)))
                .shadow(color: .black.opacity(style.backgroundOpacity < 0.3 ? 0.9 : 0), radius: 1.5, y: 1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(style.backgroundOpacity), in: RoundedRectangle(cornerRadius: 4))
                .padding(4)
        }
        .frame(width: 240, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct MouseHelpRow: View {
    let gesture: String
    let effect: String

    var body: some View {
        LabeledContent(gesture) {
            Text(effect).foregroundStyle(.secondary)
        }
    }
}
