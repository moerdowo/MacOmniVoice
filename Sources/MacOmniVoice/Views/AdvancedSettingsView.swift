import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        // Bridge the app.settings into a local observable so SwiftUI tracks
        // its @Published changes inside this view.
        AdvancedSettingsBody(settings: app.settings)
    }
}

private struct AdvancedSettingsBody: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("Advanced settings", systemImage: "slider.horizontal.3")
                    .font(.headline)

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        labeledField("Language",
                                     hint: "BCP-47 code or name, blank = auto") {
                            TextField("en, zh, fr…", text: $settings.language)
                                .textFieldStyle(.roundedBorder)
                        }
                        labeledField("Instruct (voice design)",
                                     hint: "e.g. 'female, british accent'") {
                            TextField("blank = use reference audio", text: $settings.instruct)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    GridRow {
                        labeledField("Speed (× realtime)",
                                     hint: "> 1.0 faster, < 1.0 slower") {
                            sliderRow(value: $settings.speed, range: 0.5...2.0, step: 0.05, format: "%.2f")
                        }
                        labeledField("Duration override (s)",
                                     hint: "0 = auto") {
                            sliderRow(value: $settings.duration, range: 0...60, step: 0.5, format: "%.1f")
                        }
                    }

                    GridRow {
                        labeledField("Inference steps",
                                     hint: "Lower is faster, higher is cleaner") {
                            HStack {
                                Slider(value: Binding(
                                    get: { Double(settings.numStep) },
                                    set: { settings.numStep = Int($0.rounded()) }
                                ), in: 4...64, step: 1)
                                Text("\(settings.numStep)")
                                    .monospacedDigit().frame(width: 44, alignment: .trailing)
                            }
                        }
                        labeledField("Guidance scale (CFG)",
                                     hint: "How strongly to follow the prompt") {
                            sliderRow(value: $settings.guidanceScale, range: 0...10, step: 0.1, format: "%.1f")
                        }
                    }

                    GridRow {
                        labeledField("t-shift",
                                     hint: "Diffusion time-step skew") {
                            sliderRow(value: $settings.tShift, range: 0...1, step: 0.01, format: "%.2f")
                        }
                        labeledField("Layer penalty",
                                     hint: "Layer-skip penalty factor") {
                            sliderRow(value: $settings.layerPenaltyFactor, range: 0...10, step: 0.1, format: "%.1f")
                        }
                    }

                    GridRow {
                        labeledField("Position temperature", hint: "Sampling temp for position") {
                            sliderRow(value: $settings.positionTemperature, range: 0...10, step: 0.1, format: "%.1f")
                        }
                        labeledField("Class temperature", hint: "Sampling temp for class") {
                            sliderRow(value: $settings.classTemperature, range: 0...10, step: 0.1, format: "%.1f")
                        }
                    }

                    GridRow {
                        labeledField("Device", hint: "Override auto-detection") {
                            Picker("", selection: $settings.deviceOverride) {
                                Text("Auto").tag("")
                                Text("Apple Silicon (mps)").tag("mps")
                                Text("CPU").tag("cpu")
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        labeledField("Model id", hint: "HuggingFace repo id") {
                            TextField("k2-fsa/OmniVoice", text: $settings.modelId)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                Divider()

                HStack(spacing: 24) {
                    Toggle("Denoise output", isOn: $settings.denoise)
                    Toggle("Post-process output", isOn: $settings.postprocessOutput)
                    Toggle("Pre-process prompt", isOn: $settings.preprocessPrompt)
                    Spacer()
                    Toggle("Check for updates on launch", isOn: $settings.autoCheckUpdates)
                        .toggleStyle(.switch)
                }
                .toggleStyle(.checkbox)
            }
            .padding(8)
        }
    }

    private func sliderRow(value: Binding<Double>,
                           range: ClosedRange<Double>,
                           step: Double,
                           format: String) -> some View {
        HStack {
            Slider(value: value, in: range, step: step)
            Text(String(format: format, value.wrappedValue))
                .monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }

    private func labeledField<Content: View>(_ label: String,
                                             hint: String,
                                             @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout).bold()
            content()
            Text(hint).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
