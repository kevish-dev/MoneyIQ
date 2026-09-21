import SwiftUI
import PhotosUI
import MoneyIQCore

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Renders a `UserAccount`'s avatar — a photo takes priority over an emoji,
/// which takes priority over initials-on-a-tinted-circle (the previous,
/// only look) as the final fallback. Used everywhere an avatar shows up:
/// the profile toolbar button, the Profile screen's header, etc.
struct AvatarView: View {
    let account: UserAccount?
    var diameter: CGFloat = 40

    var body: some View {
        Group {
            if let data = account?.avatarImageData, let image = platformImage(from: data) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
            } else if let emoji = account?.avatarEmoji, !emoji.isEmpty {
                Circle()
                    .fill(AppTheme.accent.opacity(0.15))
                    .frame(width: diameter, height: diameter)
                    .overlay {
                        Text(emoji)
                            .font(.system(size: diameter * 0.55))
                    }
            } else {
                Circle()
                    .fill(AppTheme.accent.opacity(0.15))
                    .frame(width: diameter, height: diameter)
                    .overlay {
                        Text(initials)
                            .font(.system(size: diameter * 0.4, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
            }
        }
    }

    private var initials: String {
        guard let account else { return "" }
        let first = account.firstName.first.map(String.init) ?? ""
        let last = account.lastName.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }
}

func platformImage(from data: Data) -> Image? {
    #if os(iOS)
    guard let uiImage = UIImage(data: data) else { return nil }
    return Image(uiImage: uiImage)
    #elseif os(macOS)
    guard let nsImage = NSImage(data: data) else { return nil }
    return Image(nsImage: nsImage)
    #endif
}

/// Downscales + compresses a picked photo before it goes into SwiftData —
/// avatars don't need to be full camera resolution, and this keeps the
/// store lean. Runs off the main actor since `PhotosPickerItem` loading is
/// already async.
func resizedAvatarData(from data: Data, maxDimension: CGFloat = 320) -> Data? {
    #if os(iOS)
    guard let image = UIImage(data: data) else { return nil }
    let scale = min(1, maxDimension / max(image.size.width, image.size.height))
    let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: newSize)
    let resized = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: newSize))
    }
    return resized.jpegData(compressionQuality: 0.85)
    #elseif os(macOS)
    guard let image = NSImage(data: data) else { return nil }
    let scale = min(1, maxDimension / max(image.size.width, image.size.height))
    let newSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    let resized = NSImage(size: newSize)
    resized.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: newSize))
    resized.unlockFocus()
    guard let tiffData = resized.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
    return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    #endif
}

/// Sheet for choosing a photo, an emoji, or resetting back to initials —
/// opened by tapping the avatar on the Profile screen.
struct AvatarPickerView: View {
    @Bindable var account: UserAccount

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var customEmoji: String = ""
    @State private var isLoadingPhoto = false

    private let emojiChoices = [
        "😀", "😎", "🤠", "🥳", "🤓", "😇", "🥸", "🤖",
        "👻", "😺", "🐶", "🐱", "🦊", "🐼", "🐵", "🐸",
        "🦁", "🐯", "🐨", "🐰", "🦄", "🐷", "🐔", "🐢",
        "⚡️", "🔥", "🌟", "🎯", "💰", "💸", "🚀", "🎓"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        AvatarView(account: account, diameter: 96)
                        Spacer()
                    }
                    .padding(.vertical, AppTheme.Spacing.small)
                }
                .listRowBackground(Color.clear)

                Section {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(isLoadingPhoto ? "Loading…" : "Choose Photo", systemImage: "photo.on.rectangle")
                    }
                    .disabled(isLoadingPhoto)
                } header: {
                    Text("Photo")
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(emojiChoices, id: \.self) { emoji in
                            emojiButton(emoji)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.xs)

                    HStack {
                        Text("Or type any emoji")
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("🙂", text: $customEmoji)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .onChange(of: customEmoji) { _, newValue in
                                guard let last = newValue.last else { return }
                                setEmoji(String(last))
                            }
                    }
                } header: {
                    Text("Emoji")
                }

                if account.avatarImageData != nil || account.avatarEmoji != nil {
                    Section {
                        Button("Remove Avatar", role: .destructive) {
                            account.avatarImageData = nil
                            account.avatarEmoji = nil
                            save()
                        }
                    }
                }
            }
            .navigationTitle("Avatar")
            .compactFormLayout()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task { await handlePicked(newItem) }
            }
        }
    }

    /// Extracted from the LazyVGrid's ForEach closure — the inline ternary
    /// background there was pushing the surrounding expression past the
    /// type-checker's time budget (same class of issue as HomeView's).
    private func emojiButton(_ emoji: String) -> some View {
        let isSelected = account.avatarEmoji == emoji
        return Button {
            setEmoji(emoji)
        } label: {
            Text(emoji)
                .font(.title2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(backgroundColor(isSelected: isSelected), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func backgroundColor(isSelected: Bool) -> Color {
        isSelected ? AppTheme.accent.opacity(0.18) : .clear
    }

    private func setEmoji(_ emoji: String) {
        account.avatarEmoji = emoji
        account.avatarImageData = nil
        save()
    }

    private func handlePicked(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let resized = resizedAvatarData(from: data) else { return }
        account.avatarImageData = resized
        account.avatarEmoji = nil
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("MoneyIQ: failed to save avatar: \(error)")
        }
    }
}
