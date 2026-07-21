import Foundation

public enum DiskSpace {
    public static let defaultMargin: Int64 = 1_073_741_824   // keep 1 GB free

    /// `required == 0` means unknown → allow (verification catches a bad result later).
    public static func fits(requiredBytes required: Int64, availableBytes available: Int64,
                            marginBytes margin: Int64 = defaultMargin) -> Bool {
        required <= 0 || available - required >= margin
    }

    /// Free space on the volume backing `url` for important usage, or nil if unknown.
    public static func availableBytes(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }
}
