import AppKit

/// Card bodies are stored as RTF when they carry formatting, and as plain text
/// otherwise — so an unformatted note still reads normally straight out of psql,
/// and an empty editor stores "" rather than an empty RTF document.
enum RichText {
    static let bodyFont = NSFont.systemFont(ofSize: 14)
    static let ink = NSColor(white: 0.92, alpha: 1)

    static var base: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: ink]
    }

    static func isRTF(_ stored: String) -> Bool { stored.hasPrefix("{\\rtf") }

    static func attributed(from stored: String) -> NSAttributedString {
        guard !stored.isEmpty else { return NSAttributedString(string: "", attributes: base) }
        if isRTF(stored), let data = stored.data(using: .utf8),
           let parsed = NSAttributedString(rtf: data, documentAttributes: nil) {
            return normalise(parsed)
        }
        return NSAttributedString(string: stored, attributes: base)
    }

    /// Keep bold/italic/underline; force our size and colour, so text pasted from
    /// a browser can't land black-on-black or three sizes too big.
    static func normalise(_ input: NSAttributedString) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: input)
        let whole = NSRange(location: 0, length: out.length)

        out.enumerateAttribute(.font, in: whole) { value, range, _ in
            let existing = (value as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            var wanted: NSFontDescriptor.SymbolicTraits = []
            if existing.contains(.bold) { wanted.insert(.bold) }
            if existing.contains(.italic) { wanted.insert(.italic) }
            let descriptor = bodyFont.fontDescriptor.withSymbolicTraits(wanted)
            out.addAttribute(.font, value: NSFont(descriptor: descriptor, size: bodyFont.pointSize) ?? bodyFont,
                             range: range)
        }
        out.addAttribute(.foregroundColor, value: ink, range: whole)
        return out
    }

    static func stored(from attributed: NSAttributedString) -> String {
        guard !attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }

        // no formatting? keep it as readable plain text
        var formatted = false
        let whole = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttributes(in: whole) { attrs, _, stop in
            if attrs[.underlineStyle] != nil { formatted = true; stop.pointee = true }
            if let font = attrs[.font] as? NSFont,
               !font.fontDescriptor.symbolicTraits.intersection([.bold, .italic]).isEmpty {
                formatted = true; stop.pointee = true
            }
        }
        if !formatted && !attributed.string.contains("•") { return attributed.string }

        guard let data = attributed.rtf(from: whole, documentAttributes: [:]),
              let text = String(data: data, encoding: .utf8)
        else { return attributed.string }
        return text
    }
}

/// Cmd-B / I / U, since an accessory app has no Format menu to hang key
/// equivalents off.
final class FormattingTextView: NSTextView {
    weak var formatter: RichTextController?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.option) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": formatter?.bold();      return true
        case "i": formatter?.italic();    return true
        case "u": formatter?.underline(); return true
        default:  return super.performKeyEquivalent(with: event)
        }
    }
}

/// Lets the SwiftUI toolbar act on the text view underneath it.
@MainActor
final class RichTextController: ObservableObject {
    weak var textView: NSTextView?

    func bold()   { toggle(.bold) }
    func italic() { toggle(.italic) }

    private func toggle(_ trait: NSFontDescriptor.SymbolicTraits) {
        guard let view = textView, let storage = view.textStorage else { return }
        let range = view.selectedRange()

        // nothing selected: set what the next keystroke will be
        guard range.length > 0 else {
            var attrs = view.typingAttributes
            let font = (attrs[.font] as? NSFont) ?? RichText.bodyFont
            let on = !font.fontDescriptor.symbolicTraits.contains(trait)
            attrs[.font] = apply(trait, on: on, to: font)
            view.typingAttributes = attrs
            return
        }

        guard view.shouldChangeText(in: range, replacementString: nil) else { return }
        let leading = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        let turningOn = !(leading ?? RichText.bodyFont).fontDescriptor.symbolicTraits.contains(trait)

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, sub, _ in
            let font = (value as? NSFont) ?? RichText.bodyFont
            storage.addAttribute(.font, value: apply(trait, on: turningOn, to: font), range: sub)
        }
        storage.endEditing()
        view.didChangeText()
    }

    func underline() {
        guard let view = textView, let storage = view.textStorage else { return }
        let range = view.selectedRange()

        guard range.length > 0 else {
            var attrs = view.typingAttributes
            let on = (attrs[.underlineStyle] as? Int ?? 0) == 0
            attrs[.underlineStyle] = on ? NSUnderlineStyle.single.rawValue : 0
            view.typingAttributes = attrs
            return
        }

        guard view.shouldChangeText(in: range, replacementString: nil) else { return }
        let existing = storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
        storage.beginEditing()
        storage.addAttribute(.underlineStyle,
                             value: existing == 0 ? NSUnderlineStyle.single.rawValue : 0,
                             range: range)
        storage.endEditing()
        view.didChangeText()
    }

    /// Toggle "• " on every line the selection touches.
    func bullet() {
        guard let view = textView, let storage = view.textStorage else { return }
        let text = storage.string as NSString
        let paragraph = text.paragraphRange(for: view.selectedRange())
        let lines = text.substring(with: paragraph).components(separatedBy: "\n")

        let alreadyBulleted = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                                   .allSatisfy { $0.hasPrefix("• ") }
        let rewritten = lines.map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            return alreadyBulleted ? String(line.dropFirst(2)) : "• " + line
        }.joined(separator: "\n")

        guard view.shouldChangeText(in: paragraph, replacementString: rewritten) else { return }
        storage.replaceCharacters(in: paragraph, with: NSAttributedString(string: rewritten,
                                                                         attributes: RichText.base))
        view.didChangeText()
    }
}

private func apply(_ trait: NSFontDescriptor.SymbolicTraits, on: Bool, to font: NSFont) -> NSFont {
    var traits = font.fontDescriptor.symbolicTraits
    if on { traits.insert(trait) } else { traits.remove(trait) }
    return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
}

// MARK: - SwiftUI wrapper

import SwiftUI

struct RichTextEditor: NSViewRepresentable {
    @Binding var stored: String
    let controller: RichTextController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FormattingTextView()
        textView.formatter = controller
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = RichText.bodyFont
        textView.textColor = RichText.ink
        textView.insertionPointColor = .white
        textView.typingAttributes = RichText.base
        textView.textContainerInset = NSSize(width: 5, height: 6)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(RichText.attributed(from: stored))
        controller.textView = textView

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        // never overwrite what someone is in the middle of typing
        guard textView.window?.firstResponder !== textView,
              context.coordinator.lastEmitted != stored else { return }
        textView.textStorage?.setAttributedString(RichText.attributed(from: stored))
        context.coordinator.lastEmitted = stored
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: RichTextEditor
        var lastEmitted: String

        init(_ parent: RichTextEditor) {
            self.parent = parent
            self.lastEmitted = parent.stored
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let storage = textView.textStorage else { return }
            let value = RichText.stored(from: storage)
            lastEmitted = value
            parent.stored = value
        }

        /// Typing "- " or "* " at the start of a line turns it into a bullet.
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString text: String?) -> Bool {
            guard text == " " else { return true }
            let content = textView.string as NSString
            let paragraph = content.paragraphRange(for: range)
            let typedSoFar = NSRange(location: paragraph.location,
                                     length: range.location - paragraph.location)
            guard typedSoFar.length > 0 else { return true }
            let prefix = content.substring(with: typedSoFar)
            guard prefix == "-" || prefix == "*" else { return true }

            textView.insertText("• ", replacementRange: typedSoFar)
            return false          // we already consumed the space
        }

        /// Return inside a bullet continues the list; Return on an empty bullet ends it.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let text = textView.string as NSString
            let paragraph = text.paragraphRange(for: textView.selectedRange())
            let line = text.substring(with: paragraph).trimmingCharacters(in: .newlines)
            guard line.hasPrefix("•") else { return false }

            if line.trimmingCharacters(in: .whitespaces) == "•" {
                textView.insertText("", replacementRange: paragraph)   // drop the empty bullet
                return true
            }
            textView.insertText("\n• ", replacementRange: textView.selectedRange())
            return true
        }
    }
}
