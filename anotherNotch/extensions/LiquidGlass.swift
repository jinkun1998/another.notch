import SwiftUI

struct LiquidGlassSurface<EffectShape: Shape>: View {
    let shape: EffectShape
    var opacity: CGFloat = 0.8
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            shape
                .fill(.white.opacity(0.01))
                .glassEffect(.regular, in: shape)
                .overlay { shape.stroke(.white.opacity(0.28), lineWidth: 1) }
                .opacity(opacity)
        } else {
            shape
                .fill(.black.opacity(0.2))
                .overlay { shape.stroke(.white.opacity(0.16), lineWidth: 1) }
        }
    }
}

struct LiquidGlassEdge<EffectShape: Shape>: View {
    let shape: EffectShape
    var topInset: CGFloat = 0
    var opacity: CGFloat = 0.8
    var rimWidth: CGFloat = 10
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        Group {
            if #available(macOS 26.0, *), !reduceTransparency {
                shape
                    .fill(.white.opacity(0.01))
                    .glassEffect(.regular, in: shape)
                    .compositingGroup()
                    .mask { shape.stroke(.white, lineWidth: rimWidth) }
                    .overlay { shape.stroke(.white.opacity(0.32), lineWidth: 1) }
                    .opacity(opacity)
            } else {
                shape.stroke(.white.opacity(0.16), lineWidth: 1)
            }
        }
        .mask(alignment: .bottom) {
            Rectangle().padding(.top, topInset)
        }
    }
}

private struct LiquidGlassControlModifier<ControlShape: Shape>: ViewModifier {
    let shape: ControlShape
    let interactive: Bool
    let fallback: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content.background(shape.fill(fallback))
        }
    }
}

extension View {
    func liquidGlassControl<ControlShape: Shape>(
        in shape: ControlShape,
        interactive: Bool = true,
        fallback: Color = .black
    ) -> some View {
        modifier(LiquidGlassControlModifier(
            shape: shape,
            interactive: interactive,
            fallback: fallback
        ))
    }
}
