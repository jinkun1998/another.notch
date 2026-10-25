import SwiftUI

struct ChatNotificationIndicator: View {
    let item: ExpandedItem
    let physicalNotchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            // Left wing: Service Icon + Sender Title
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.tint)

                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)

            // Center physical notch cutout
            Rectangle()
                .fill(.black)
                .frame(width: physicalNotchWidth)

            // Right wing: Message preview snippet
            HStack(spacing: 4) {
                Text(item.subtitle.isEmpty ? "New message" : item.subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 12)
        }
    }
}
