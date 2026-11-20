import Foundation

/// Lê capacidade e metadados dos volumes montados.
public enum VolumeService {
    private static let keys: [URLResourceKey] = [
        .volumeNameKey,
        .volumeUUIDStringKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsInternalKey,
        .volumeIsEjectableKey,
        .volumeIsLocalKey,
        .volumeIsBrowsableKey,
    ]

    /// Volumes visíveis ao usuário, com o de inicialização primeiro.
    public static func mountedVolumes() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls.compactMap(read)
            .sorted { lhs, rhs in
                if lhs.isRoot != rhs.isRoot { return lhs.isRoot }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// Volume de inicialização ("/").
    public static func rootVolume() -> VolumeInfo? {
        read(URL(fileURLWithPath: "/"))
    }

    static func read(_ url: URL) -> VolumeInfo? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)),
              let total = values.volumeTotalCapacity, total > 0 else { return nil }
        if values.volumeIsBrowsable == false { return nil }

        let available = Int64(values.volumeAvailableCapacity ?? 0)
        let important = values.volumeAvailableCapacityForImportantUsage ?? available
        let isRoot = url.standardizedFileURL.path == "/"

        return VolumeInfo(
            id: values.volumeUUIDString ?? url.path,
            name: values.volumeName ?? url.lastPathComponent,
            url: url,
            totalBytes: Int64(total),
            availableBytes: available,
            availableImportantBytes: important,
            isRoot: isRoot,
            isInternal: values.volumeIsInternal ?? false,
            isEjectable: values.volumeIsEjectable ?? false,
            isLocal: values.volumeIsLocal ?? true
        )
    }
}
