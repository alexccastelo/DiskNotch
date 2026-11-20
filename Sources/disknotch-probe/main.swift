import StorageCore

// Ferramenta de linha de comando para conferir a leitura dos volumes.
for v in VolumeService.mountedVolumes() {
    let tag = v.isRoot ? " (inicialização)" : (v.isEjectable ? " (ejetável)" : "")
    print("\(v.name)\(tag) — \(v.url.path)")
    print("  total:    \(ByteFormat.string(v.totalBytes))")
    print("  usado:    \(ByteFormat.string(v.usedBytes))  (\(Int(v.usedFraction * 100))%)")
    print("  livre:    \(ByteFormat.string(v.freeBytes))  [compacto: \(ByteFormat.compact(v.freeBytes))]")
    print("  purgável: \(ByteFormat.string(v.purgeableBytes))")
    print("  nível:    \(v.level)")
}
