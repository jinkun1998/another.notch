//
//  HoverButton.swift
//  anotherNotch
//
//  Created by Kraigo on 04.09.2024.
//

import SwiftUI

struct HoverButton: View {
    let icon: String
    var iconColor: Color = .primary
    var scale: Image.Scale = .medium
    var showsHoverHighlight = true
    var accessibilityLabel: String?
    let action: () -> Void
    var contentTransition: ContentTransition = .symbolEffect
    
    @State private var isHovering = false

    var body: some View {
        let size = CGFloat(scale == .large ? 40 : 30)
        
        Button(action: {
            HapticFeedback.perform(.generic)
            action()
        }) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: size, height: size)
                .overlay {
                    Capsule()
                        .fill(showsHoverHighlight && isHovering ? Color.gray.opacity(0.2) : .clear)
                        .frame(width: size, height: size)
                        .overlay {
                            Image(systemName: icon)
                                .foregroundColor(iconColor)
                                .contentTransition(contentTransition)
                                .font(scale == .large ? .largeTitle : .body)
                        }
                }
                .liquidGlassControl(in: Capsule(), fallback: .black.opacity(0.45))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? icon)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) {
                isHovering = hovering
            }
        }
    }
}
