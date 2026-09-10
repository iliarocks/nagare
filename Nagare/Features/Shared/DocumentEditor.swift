import SwiftUI
#if os(macOS)
import AppKit
#endif

enum NagareEditorField: Hashable {
    case title
    case notes
}


struct NagareEditableTitle: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
#if os(macOS)
        TextField(placeholder, text: $text)
#else
        TextField(placeholder, text: $text, axis: .vertical)
#endif
    }
}

struct NagareDocumentEditor: View {
    let placeholder: String
    @Binding var text: String

    private let accessibilityIdentifier: String
    private let focus: FocusState<NagareEditorField?>.Binding?
    private let bottomScrollContentMargin: CGFloat

    init(
        _ placeholder: String = "Notes",
        text: Binding<String>,
        accessibilityIdentifier: String,
        focus: FocusState<NagareEditorField?>.Binding? = nil,
        bottomScrollContentMargin: CGFloat = 0
    ) {
        self.placeholder = placeholder
        _text = text
        self.accessibilityIdentifier = accessibilityIdentifier
        self.focus = focus
        self.bottomScrollContentMargin = bottomScrollContentMargin
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            editor

            if text.isEmpty {
                Text(placeholder)
                    .nagareDocumentPlaceholderStyle()
            }
        }
        .padding(.horizontal, -5)
    }

    @ViewBuilder
    private var editor: some View {
        if let focus {
            styledEditor
                .focused(focus, equals: .notes)
        } else {
            styledEditor
        }
    }

    private var styledEditor: some View {
        TextEditor(text: $text)
            .textEditorStyle(.plain)
            .nagareDocumentEditorStyle()
            .nagareBottomScrollContentMargin(bottomScrollContentMargin)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}

enum NagareDocumentBottomFade {
    static let height: CGFloat = 64
    static let scrollContentMargin: CGFloat = height + 16
}

struct NagareDocumentComposerLayout<Title: View, Document: View>: View {
    let bottomPadding: CGFloat
    @ViewBuilder let title: () -> Title
    @ViewBuilder let document: () -> Document

    init(
        bottomPadding: CGFloat = 16,
        @ViewBuilder title: @escaping () -> Title,
        @ViewBuilder document: @escaping () -> Document
    ) {
        self.bottomPadding = bottomPadding
        self.title = title
        self.document = document
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            title()
                .frame(maxWidth: .infinity, alignment: .leading)

            document()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, bottomPadding)
    }
}


#if os(macOS)
private struct NagareInitialFocusReset: NSViewRepresentable {
    func makeNSView(context: Context) -> ResetView {
        ResetView()
    }

    func updateNSView(_ nsView: ResetView, context: Context) {}

    final class ResetView: NSView {
        private var hasResetFocus = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !hasResetFocus else { return }
            hasResetFocus = true
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(nil)
            }
        }
    }
}
#endif


extension View {
    @ViewBuilder
    func nagareEditorBodyFont() -> some View {
#if os(macOS)
        font(.system(size: 14))
#else
        font(.body)
#endif
    }

    @ViewBuilder
    func nagareDocumentEditorStyle() -> some View {
        scrollContentBackground(.hidden)
            .nagareEditorBodyFont()
    }

    @ViewBuilder
    func nagareDocumentPlaceholderStyle() -> some View {
        nagareEditorBodyFont()
            .foregroundStyle(.tertiary)
#if os(macOS)
            .padding(.horizontal, 5)
#else
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
#endif
            .allowsHitTesting(false)
    }

    @ViewBuilder
    func nagareComposerFrame(
        width: CGFloat,
        height: CGFloat
    ) -> some View {
#if os(macOS)
        frame(width: width, height: height)
#else
        self
#endif
    }

    @ViewBuilder
    func nagareDocumentSheetFrame() -> some View {
#if os(macOS)
        frame(width: 620, height: 400)
#else
        self
#endif
    }

    @ViewBuilder
    func nagareAvoidsInitialFocus() -> some View {
#if os(macOS)
        background(NagareInitialFocusReset())
#else
        self
#endif
    }

    func nagareDocumentBottomFade() -> some View {
        ignoresSafeArea(.container, edges: .bottom)
            .mask {
                VStack(spacing: 0) {
                    Color.black

                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: NagareDocumentBottomFade.height)
                }
            }
    }
}
