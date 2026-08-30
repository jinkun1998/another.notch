//
//  PermissionsRequestView.swift
//  anotherNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI

struct PermissionRequestView: View {
    let icon: Image
    let title: String
    let description: String
    let privacyNote: String?
    var isGranted: Bool = false
    var hasRequested: Bool = false
    let onAllow: () -> Void
    var onOpenSettings: (() -> Void)? = nil
    let onSkip: () -> Void
    var onContinue: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 70, height: 56)
                    .foregroundColor(isGranted ? .green : .effectiveAccent)

                if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.green)
                        .offset(x: 28, y: 20)
                }
            }
            .padding(.top, 28)

            Text(title)
                .font(.title)
                .fontWeight(.semibold)

            Text(description)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let privacyNote = privacyNote {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.secondary)
                    Text(privacyNote)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.bottom, 4)
                .padding(.horizontal)
            }

            if isGranted {
                Text("Access Granted")
                    .font(.subheadline.bold())
                    .foregroundColor(.green)
            } else if hasRequested {
                Text("Please grant access in System Settings.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                if isGranted {
                    Button("Continue") {
                        (onContinue ?? onSkip)()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if hasRequested {
                    Button("Not Now") {
                        onSkip()
                    }
                    .buttonStyle(.bordered)

                    Button("Open Settings") {
                        if let onOpenSettings {
                            onOpenSettings()
                        } else {
                            onAllow()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Continue") {
                        (onContinue ?? onSkip)()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Not Now") {
                        onSkip()
                    }
                    .buttonStyle(.bordered)

                    Button("Allow Access") {
                        onAllow()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(OnboardingBackground())
    }
}
