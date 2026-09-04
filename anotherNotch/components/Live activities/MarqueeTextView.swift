//
//  MarqueeTextView.swift
//  anotherNotch
//
//  Created by Richard Kunkli on 08/08/2024.
//

import SwiftUI

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct MeasureSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
        })
    }
}

struct MarqueeText: View {
    private let loopingSpacing: CGFloat = 20
    @Binding var text: String
    let font: Font
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let backgroundColor: Color
    let minDuration: Double
    let frameWidth: CGFloat
    let centerWhenFits: Bool
    
    @State private var animate = false
    @State private var textSize: CGSize = .zero
    @State private var offset: CGFloat = 0
    
    init(_ text: Binding<String>, font: Font = .body, nsFont: NSFont.TextStyle = .body, textColor: Color = .primary, backgroundColor: Color = .clear, minDuration: Double = 3.0, frameWidth: CGFloat = 200, centerWhenFits: Bool = false) {
        _text = text
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.minDuration = minDuration
        self.frameWidth = frameWidth
        self.centerWhenFits = centerWhenFits
    }
    
    var body: some View {
        GeometryReader { geometry in
            let viewportWidth = max(0, min(frameWidth, geometry.size.width))
            let needsScrolling = textSize.width > viewportWidth

            ZStack(alignment: .leading) {
                HStack(spacing: loopingSpacing) {
                    Text(text)
                    Text(text)
                        .opacity(needsScrolling ? 1 : 0)
                }
                .id(text)
                .font(font)
                .foregroundColor(textColor)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: self.animate ? offset : (centerWhenFits && !needsScrolling ? (textSize.width + loopingSpacing) / 2 : 0))
                .animation(
                    self.animate ?
                        .linear(duration: Double(textSize.width / 30))
                        .delay(minDuration)
                        .repeatForever(autoreverses: false) : .none,
                    value: self.animate
                )
                .background(backgroundColor)
                .modifier(MeasureSizeModifier())
                .onPreferenceChange(SizePreferenceKey.self) { size in
                    self.textSize = CGSize(width: size.width / 2, height: NSFont.preferredFont(forTextStyle: nsFont).pointSize)
                    self.animate = false
                    self.offset = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01){
                        if textSize.width > viewportWidth {
                            self.animate = true
                            self.offset = -(textSize.width + 10)
                            
                        }
                    }
                }
            }
            .frame(width: viewportWidth, alignment: centerWhenFits && !needsScrolling ? .center : .leading)
            .clipped()
        }
        .frame(height: textSize.height * 1.3)
        
    }
}
