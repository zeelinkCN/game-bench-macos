import AppKit

enum CoverCache {
    private static let cache=NSCache<NSString,NSImage>()
    static func image(_ path: String) -> NSImage? {
        if let image=cache.object(forKey:path as NSString) { return image }
        guard let image=NSImage(contentsOfFile:path) else { return nil }
        cache.setObject(image,forKey:path as NSString)
        return image
    }
}
