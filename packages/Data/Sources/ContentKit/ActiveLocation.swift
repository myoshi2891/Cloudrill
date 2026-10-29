/// 呼び出し側で存在・パス・版を確認した候補から、有効なパックを選ぶ純粋関数。
/// SemVer の優先順位が同じなら installed を維持する（build metadata は順位に影響しない）。
func resolveActiveLocation(bundled: PackLocation?, installed: PackLocation?) -> PackLocation? {
    guard let installed else { return bundled }
    if let bundled,
       let bundledVersion = SemanticVersion(bundled.version),
       let installedVersion = SemanticVersion(installed.version), bundledVersion > installedVersion {
        return bundled
    }
    return installed
}
