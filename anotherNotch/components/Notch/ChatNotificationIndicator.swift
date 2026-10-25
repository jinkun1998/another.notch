import SwiftUI

struct ChatServiceIconView: View {
    let icon: String
    var size: CGFloat = 14

    var body: some View {
        if icon.lowercased().contains("messenger") || icon == "bubble.right.fill" {
            ZStack {
                Image(systemName: "bubble.right.fill")
                    .font(.system(size: size))
                    .foregroundStyle(Color(red: 0.0, green: 0.52, blue: 1.0))
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.46, weight: .black))
                    .rotationEffect(.degrees(72))
                    .foregroundStyle(.white)
                    .offset(x: -size * 0.04, y: -size * 0.04)
            }
            .frame(width: size, height: size)
        } else {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(serviceColor(for: icon))
        }
    }

    private func serviceColor(for icon: String) -> Color {
        switch icon {
        case "paperplane.fill": return Color(red: 0.16, green: 0.63, blue: 0.95)
        case "phone.bubble.fill": return Color(red: 0.15, green: 0.83, blue: 0.44)
        case "gamecontroller.fill": return Color(red: 0.35, green: 0.4, blue: 0.95)
        case "number": return Color(red: 0.89, green: 0.11, blue: 0.45)
        default: return .white
        }
    }
}

struct ChatNotificationIndicator: View {
    let item: ExpandedItem
    let physicalNotchWidth: CGFloat
    let topRowHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            // Row 1: Only the message service icon on the left wing
            HStack(spacing: 0) {
                HStack {
                    ChatServiceIconView(icon: item.icon, size: 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)

                // Physical Notch Cutout
                Rectangle()
                    .fill(.black)
                    .frame(width: physicalNotchWidth)

                // Right wing: Empty for symmetry
                Color.clear
                    .frame(maxWidth: .infinity)
            }
            .frame(height: topRowHeight)

            // Row 2: Full-width Message Content below notch (Sender: Body)
            HStack(spacing: 0) {
                if !item.title.isEmpty {
                    Text("\(item.title): ")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text(item.subtitle.isEmpty ? "New message" : item.subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 22)
        }
    }
}
