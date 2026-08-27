//
//  AnotherNotchExtrasMenu.swift
//  anotherNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import SwiftUI

private struct NotchActionButton: View {
    let action: () -> Void
    let icon: Image
    let title: String

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                icon.resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20)
                Text(title)
                    .font(.body)
            }
            .frame(width: 70, height: 70)
            .liquidGlassControl(in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.5), radius: 10)
        .accessibilityLabel(title)
    }
}

struct AnotherNotchExtrasMenu: View {
    @ObservedObject var vm: AnotherNotchViewModel
    
    var body: some View {
        HStack(spacing: 20)  {
            hide
            settings
            close
        }
    }
    
    private var github: some View {
        NotchActionButton(
            action: {
                if let url = URL(string: "https://github.com/jinkun1998/another.notch") {
                    NSWorkspace.shared.open(url)
                }
            },
            icon: Image(.github),
            title: "Checkout"
        )
    }
    
    private var settings: some View {
        NotchActionButton(
            action: SettingsWindowController.present,
            icon: Image(systemName: "gear"),
            title: "Settings"
        )
    }
    
    private var hide: some View {
        NotchActionButton(
            action: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    //vm.openMusic()
                }
            },
            icon: Image(systemName: "arrow.down.forward.and.arrow.up.backward"),
            title: "Hide"
        )
    }
    
    private var close: some View {
        NotchActionButton(
            action: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        NSApp.terminate(nil)
                    }
                }
            },
            icon: Image(systemName: "xmark"),
            title: "Exit"
        )
    }
}


#Preview {
    AnotherNotchExtrasMenu(vm: .init())
}
