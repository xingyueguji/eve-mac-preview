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
                    NumberControl(value: previews.framesPerSecond, range: 1...30, step: 1, unit: "fps")
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
                LabeledContent("Width") {
                    NumberControl(value: previews.defaultWidth, range: 100...1280, step: 10, onCommit: state.applyDefaultThumbnailSize)
                }
                LabeledContent("Height") {
                    NumberControl(value: previews.defaultHeight, range: 60...800, step: 10, onCommit: state.applyDefaultThumbnailSize)
                }
            } header: {
                Text("Size")
            } footer: {
                Text("Type a size, use − / +, or drag the slider. Changing it resizes every preview; you can still resize one preview by dragging its bottom-right corner.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: previews.snapsToGrid) {
                    Text("Snap to grid")
                    Text("Dragging moves a preview in grid steps, and resizing snaps to whole cells, so previews line up without fine adjustment.")
                }
                Group {
                    LabeledContent("Grid width") {
                        NumberControl(value: previews.gridWidth, range: 5...200, step: 5, showsSlider: false)
                    }
                    LabeledContent("Grid height") {
                        NumberControl(value: previews.gridHeight, range: 5...200, step: 5, showsSlider: false)
                    }
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
                        NumberControl(value: previews.label.fontSize, range: 8...32, step: 1)
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
