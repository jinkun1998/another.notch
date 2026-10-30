//
//  TabButton.swift
//  anotherNotch
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    var badgeCount: Int = 0
    var badgeText: String? = nil
    let onClick: () -> Void
    
    var body: some View {
        Button(action: onClick) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if badgeCount > 0 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 5, height: 5)
                        .offset(x: -2, y: 3)
                }
                if let badgeText = badgeText {
                    Text(badgeText)
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 2.5)
                        .padding(.vertical, 0.5)
                        .background(Color.orange)
                        .clipShape(Capsule())
                        .offset(x: badgeCount > 0 ? -8 : -2, y: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
