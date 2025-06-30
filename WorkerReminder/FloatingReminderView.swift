import SwiftUI

struct CharWrappedText: NSViewRepresentable {
    let text: String
    let font: NSFont
    let textColor: NSColor
    
    func makeNSView(context: Context) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = textColor
        label.lineBreakMode = .byCharWrapping
        label.backgroundColor = .clear
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        return label
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.stringValue = text
    }
}

struct FloatingReminderView: View {
    @ObservedObject var model: ReminderOverlayModel
    
    // 宽度和高度范围限制
    let minWidth: CGFloat = 300
    let maxWidth: CGFloat = 400
    let maxHeight: CGFloat = 300
    
    @State private var textSize: CGSize = .zero
    
    // PreferenceKey 用于测量文本尺寸
    struct SizePreferenceKey: PreferenceKey {
        static var defaultValue: CGSize = .zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            let next = nextValue()
            value = CGSize(
                width: max(value.width, next.width),
                height: max(value.height, next.height)
            )
        }
    }
    
    var body: some View {
        CharWrappedText(
            text: model.message,
            font: NSFont.preferredFont(forTextStyle: .title2),
            textColor: .white
        )
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.8))
        )
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: SizePreferenceKey.self,
                                value: geo.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self) { size in
            textSize = CGSize(width: size.width,
                              height: size.height)
        }
        .frame(
            width: min(max(textSize.width, minWidth), maxWidth),
            height: min(textSize.height, maxHeight)
        )
    }
}
