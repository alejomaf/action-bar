import AppKit
import SwiftUI

/// Lightweight async image loader using URLSession + an in-memory NSImage cache.
/// More reliable than `AsyncImage` inside `MenuBarExtra(.window)` panels, which
/// dispose of their view tree every time the user closes the popover.
@MainActor
final class AvatarImageCache {
    static let shared = AvatarImageCache()

    private let cache = NSCache<NSURL, NSImage>()
    private var inflight: [URL: Task<NSImage?, Never>] = [:]

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func load(_ url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        if let inflight = inflight[url] {
            return await inflight.value
        }

        let task = Task<NSImage?, Never> {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                return NSImage(data: data)
            } catch {
                return nil
            }
        }

        inflight[url] = task
        let image = await task.value
        inflight[url] = nil

        if let image {
            cache.setObject(image, forKey: url as NSURL)
        }
        return image
    }
}

/// Renders a remote avatar image using `AvatarImageCache`. Falls back to the
/// bundled logo while loading or when the URL is missing/unreachable.
struct RemoteAvatar: View {
    let url: URL?
    var fallbackImage: NSImage? = AvatarImageCache.bundledLogo

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let fallbackImage {
                Image(nsImage: fallbackImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(nsColor: .quaternaryLabelColor)
            }
        }
        .task(id: url) {
            await reload()
        }
    }

    private func reload() async {
        guard let url else {
            image = nil
            return
        }

        if let cached = AvatarImageCache.shared.image(for: url) {
            image = cached
            return
        }

        if let loaded = await AvatarImageCache.shared.load(url) {
            image = loaded
        }
    }
}

extension AvatarImageCache {
    static let bundledLogo: NSImage? = {
        guard let url = Bundle.module.url(forResource: "logo", withExtension: "jpg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}
