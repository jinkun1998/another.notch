//
//  MusicControllerSelectionView.swift
//  anotherNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI
import Defaults


struct MusicControllerSelectionView: View {
    let onContinue: () -> Void

    @Default(.mediaController) var mediaController
    
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
    
    @State private var selectedMediaController: MediaControllerType = Defaults[.mediaController]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Choose a Music Source")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 24)

            Text("Select the music source you want to use. You can change this later in the app settings.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: 12) {
                    if !AnotherMusicController.isInstalled {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundColor(.effectiveAccent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Recommended: anotherMusic")
                                    .font(.subheadline.bold())
                                Text("Dedicated player for notch Live Activity, synced lyrics, and AutoMix.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Get App") {
                                NSWorkspace.shared.open(AnotherMusicController.downloadURL)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(12)
                        .background(Color.effectiveAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.effectiveAccent.opacity(0.25), lineWidth: 1)
                        )
                    }

                    ForEach(availableMediaControllers) { controller in
                        ControllerOptionView(
                            controller: controller,
                            isSelected: self.selectedMediaController == controller
                        )
                        .onTapGesture {
                            self.selectedMediaController = controller
                        }
                    }
                }
                .padding()
            }
            //Disable scroll if there are 4 or fewer to avoid unnecessary scroll behavior
            .scrollDisabled(availableMediaControllers.count <= 4)

//            Spacer()

            Button("Continue", action: {
                self.mediaController = self.selectedMediaController
                NotificationCenter.default.post(
                    name: Notification.Name.mediaControllerChanged,
                    object: nil
                )
                onContinue()
            })
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingBackground())
    }
}

struct ControllerOptionView: View {
    let controller: MediaControllerType
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundColor(isSelected ? .effectiveAccent : .secondary.opacity(0.5))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(controller.rawValue))
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(LocalizedStringKey(controller.description))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if controller == .youtubeMusic, let url = URL(string: "https://github.com/pear-devs/pear-desktop") {
                    Link("View on GitHub: pear-devs/pear-desktop", destination: url)
                        .font(.subheadline)
                        .foregroundColor(Color(nsColor: .linkColor))
                        .padding(.top, 2)
                }

                if controller == .anotherMusic {
                    if !AnotherMusicController.isInstalled {
                        Button {
                            NSWorkspace.shared.open(AnotherMusicController.downloadURL)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle")
                                Text("Download on GitHub (Free)")
                            }
                            .font(.subheadline)
                            .foregroundColor(Color.effectiveAccent)
                            .padding(.top, 2)
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("Installed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 2)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .liquidGlassControl(
            in: RoundedRectangle(cornerRadius: 12, style: .continuous),
            fallback: isSelected ? Color.effectiveAccent.opacity(0.15) : .clear
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.effectiveAccent : Color.secondary.opacity(0.3), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }
}


extension MediaControllerType {
    var description: String {
        switch self {
        case .nowPlaying:
            return "Works with most media apps, including browsers, to detect what's playing. Note: This may be removed in a future macOS version."
        case .anotherMusic:
            return "Connects directly to anotherMusic with full controls, favorites, volume, and AutoMix."
        case .spotify:
            return "Connects directly to the Spotify app."
        case .appleMusic:
            return "Connects directly to the Apple Music app."
        case .youtubeMusic:
            return "Requires a third-party client with API plugin enabled."
        }
    }
}

#Preview {
    MusicControllerSelectionView(onContinue: {})
        .frame(width: 400, height: 600)
}
