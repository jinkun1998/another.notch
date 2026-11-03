import SwiftUI

struct AirDropHUD: View {
    let transfer: AirDropIncomingTransfer
    var isClosing: Bool = false
    let physicalNotchWidth: CGFloat
    let topRowHeight: CGFloat
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Physical notch top clearance
            Rectangle()
                .fill(Color.clear)
                .frame(height: topRowHeight)

            // Dynamic Island expanded content
            VStack(spacing: 14) {
                // Main Row: Left icon + text info, Right preview thumbnail
                HStack(alignment: .center, spacing: 14) {
                    // AirDrop Icon with overlapping avatar
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color.cyan.opacity(0.24))
                            .frame(width: 44, height: 44)
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.cyan)
                            .frame(width: 44, height: 44)

                        // Avatar badge at bottom-right
                        ZStack {
                            Circle()
                                .fill(Color(white: 0.12))
                                .frame(width: 20, height: 20)
                            Circle()
                                .fill(Color(red: 0.98, green: 0.82, blue: 0.28))
                                .frame(width: 17, height: 17)
                            Image(systemName: "person.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.85))
                        }
                        .offset(x: 3, y: 3)
                    }

                    // Sender & message
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("AirDrop")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)

                            Text("Beta")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 1.5)
                                .padding(.horizontal, 5)
                                .background(Color(nsColor: .secondarySystemFill))
                                .clipShape(Capsule())
                        }

                        Text(subtitleText)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    // Right Thumbnail Preview (Larger)
                    previewThumbnail
                }

                // Action Area: Buttons or Transfer Status
                switch transfer.status {
                case .prompt:
                    HStack(spacing: 12) {
                        Button(action: onDecline) {
                            Text("Decline")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .liquidGlassControl(in: Capsule(), fallback: Color.white.opacity(0.18))
                        }
                        .buttonStyle(.plain)

                        Button(action: onAccept) {
                            Text("Accept")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .liquidGlassControl(in: Capsule(), fallback: Color(red: 0.0, green: 0.48, blue: 1.0))
                        }
                        .buttonStyle(.plain)
                    }

                case .transferring:
                    HStack(spacing: 12) {
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.18))
                                .frame(height: 7)
                            Capsule()
                                .fill(Color.cyan)
                                .frame(width: max(10, 280 * CGFloat(transfer.progress)), height: 7)
                        }
                        Text("\(Int(transfer.progress * 100))%")
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.cyan)
                    }
                    .frame(height: 36)

                case .completed:
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.green)
                        Text("Saved to Downloads")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))

                        Spacer()

                        Button(action: {
                            if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Text("Open")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .liquidGlassControl(in: Capsule(), fallback: Color.white.opacity(0.2))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(height: 36)

                case .declined, .failed:
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                        Text("Transfer declined")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 36)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .opacity(isClosing ? 0 : 1)
            .animation(.easeOut(duration: 0.12), value: isClosing)
        }
    }

    private var subtitleText: String {
        let desc = transfer.itemsDescription
        let lower = desc.lowercased()
        if lower.contains("would like to") || lower.contains("wants to") || lower.contains("sent") || lower.contains("đã gửi") || lower.contains("muốn chia sẻ") {
            return desc
        }
        if transfer.status == .completed {
            return "\(transfer.senderName) sent \(desc.lowercased())"
        }
        return "\(transfer.senderName) would like to share \(desc.lowercased())"
    }

    @ViewBuilder
    private var previewThumbnail: some View {
        if let img = transfer.previewImage {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                )
        } else {
            let desc = transfer.itemsDescription.lowercased()
            let icon: String = {
                if desc.contains("video") || desc.contains("movie") || desc.contains("phim") {
                    return "video.fill"
                } else if desc.contains("photo") || desc.contains("image") || desc.contains("ảnh") {
                    return "photo.on.rectangle.angled"
                } else if desc.contains("doc") || desc.contains("pdf") || desc.contains("file") || desc.contains("tệp") {
                    return "doc.fill"
                } else {
                    return "doc.on.doc.fill"
                }
            }()

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.25, green: 0.25, blue: 0.45), Color(red: 0.18, green: 0.15, blue: 0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 78, height: 78)

                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .liquidGlassControl(in: RoundedRectangle(cornerRadius: 16, style: .continuous), fallback: Color.clear)
        }
    }
}
