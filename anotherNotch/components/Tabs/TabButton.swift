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
