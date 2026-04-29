import SwiftUI
import Highlightr

struct StatusPill: View {
    @EnvironmentObject var workspace: Workspace
    @AppStorage(PreferenceKeys.windowGlass) private var windowGlass: Bool = false
    @State private var showOptions = false

    var body: some View {
        if let doc = workspace.activeDocument {
            Button(action: { showOptions.toggle() }) {
                HStack(spacing: 10) {
                    Text(doc.language.uppercased())
                    Capsule().fill(.secondary.opacity(0.4)).frame(width: 1, height: 10)
                    Text(indentLabel(doc.indentation))
                    Capsule().fill(.secondary.opacity(0.4)).frame(width: 1, height: 10)
                    Text(doc.lineEnding.rawValue)
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .modifier(StatusPillSurface(useGlass: windowGlass))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showOptions, arrowEdge: .bottom) {
                FormatOptionsView(document: doc)
            }
        }
    }

    private func indentLabel(_ indent: Indentation) -> String {
        "\(indent.kind.label): \(indent.width)"
    }
}

private struct FormatOptionsView: View {
    @ObservedObject var document: Document

    @AppStorage("default.indent.kind") private var defaultKind: String = Indentation.Kind.spaces.rawValue
    @AppStorage("default.indent.width") private var defaultWidth: Int = 4
    @AppStorage("default.lineEnding") private var defaultEOL: String = LineEnding.lf.rawValue

    @State private var workingKind: Indentation.Kind = .spaces
    @State private var workingWidth: Int = 4
    @State private var workingEOL: LineEnding = .lf

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("File format")
                .font(.system(size: 13, weight: .semibold))

            HStack {
                Text("Language")
                Spacer()
                Picker("", selection: $document.language) {
                    ForEach(SupportedLanguages.all, id: \.id) { lang in
                        Text(lang.label).tag(lang.id)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            VStack(alignment: .leading, spacing: 8) {
                Picker("Indentation", selection: $workingKind) {
                    ForEach(Indentation.Kind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 6) {
                    Text("Width")
                    Spacer()
                    Text("\(workingWidth)")
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 18, alignment: .trailing)
                    Stepper("", value: $workingWidth, in: 1...8)
                        .labelsHidden()
                }

                Picker("Line endings", selection: $workingEOL) {
                    ForEach(LineEnding.allCases) { eol in
                        Text(eol.rawValue).tag(eol)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Reformat document") {
                    document.reformat(
                        eol: workingEOL,
                        indentation: Indentation(kind: workingKind, width: workingWidth)
                    )
                }
                .buttonStyle(.borderedProminent)

                Button("Apply") {
                    document.indentation = Indentation(kind: workingKind, width: workingWidth)
                    document.lineEnding = workingEOL
                }
            }

            Divider()

            Button("Save as defaults for new files") {
                defaultKind = workingKind.rawValue
                defaultWidth = workingWidth
                defaultEOL = workingEOL.rawValue
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            workingKind = document.indentation.kind
            workingWidth = document.indentation.width
            workingEOL = document.lineEnding
        }
    }
}

/// Cached, sorted list of Highlightr-supported languages plus a plaintext entry.
enum SupportedLanguages {
    struct Entry: Hashable {
        let id: String
        let label: String
    }

    static let all: [Entry] = {
        var entries: [Entry] = [Entry(id: "plaintext", label: "Plain Text")]
        let langs = (Highlightr()?.supportedLanguages() ?? []).sorted()
        entries.append(contentsOf: langs.map { Entry(id: $0, label: prettyLabel(for: $0)) })
        return entries
    }()

    private static func prettyLabel(for raw: String) -> String {
        switch raw {
        case "javascript": return "JavaScript"
        case "typescript": return "TypeScript"
        case "objectivec": return "Objective-C"
        case "objectivec_plain": return "Objective-C"
        case "cpp": return "C++"
        case "csharp": return "C#"
        case "json": return "JSON"
        case "yaml": return "YAML"
        case "xml": return "XML"
        case "css": return "CSS"
        case "scss": return "SCSS"
        case "html": return "HTML"
        case "sql": return "SQL"
        default: return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }
}

/// Pill surface — picks Liquid Glass refraction (Glass on) or
/// `.ultraThinMaterial` (Glass off). Both keep the same hairline border
/// + drop shadow shape so the pill silhouette doesn't shift between
/// modes; glass uses a lighter shadow since refraction already implies
/// depth.
private struct StatusPillSurface: ViewModifier {
    let useGlass: Bool

    func body(content: Content) -> some View {
        if useGlass {
            content
                .glassEffect(.regular, in: .capsule)
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        }
    }
}
