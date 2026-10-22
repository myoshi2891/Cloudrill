#!/usr/bin/env bash
# Swift パッケージの行カバレッジを集計する(DDD 7.6)。
#
#   scripts/coverage.sh <パッケージのパス> [最低値(%)]
#   例: scripts/coverage.sh packages/Domain 80
#
# swift test --enable-code-coverage を実行し、<パッケージ>/Sources のうち *TestSupport/ を除いたファイルの
# 行カバレッジを llvm-cov で集計する(Tests/、依存パッケージ、生成されたファイルは Sources の外なので対象外)。
# 最低値を指定し、それを下回ったら終了コード 1 で終わる。引数の誤りは終了コード 2。
#
# SwiftPM がテストの後に書き出す codecov/<パッケージ名>.json は、テストターゲットが複数あると
# 1 つのテストバンドルの分しか集計しないことがある。そのため、すべてのテストバンドルを llvm-cov に渡して集計する。
set -euo pipefail

usage() {
    echo "usage: $0 <package-path> [minimum-percent]" >&2
    exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage
package=$1
minimum=${2:-}
[[ -f "$package/Package.swift" ]] || { echo "error: $package/Package.swift がない" >&2; exit 2; }
[[ -z "$minimum" || "$minimum" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "error: 最低値は数値で指定する: $minimum" >&2; exit 2; }

if command -v xcrun >/dev/null 2>&1; then
    llvm_cov=(xcrun llvm-cov)
else
    llvm_cov=(llvm-cov)
fi

swift test --package-path "$package" --enable-code-coverage

bin_path=$(swift build --package-path "$package" --show-bin-path)
profdata="$bin_path/codecov/default.profdata"
[[ -f "$profdata" ]] || { echo "error: $profdata がない" >&2; exit 1; }

# テストバンドルの実行ファイル(macOS は *.xctest/Contents/MacOS/<名前>、Linux は *.xctest 自体)
objects=()
for bundle in "$bin_path"/*.xctest; do
    name=$(basename "$bundle" .xctest)
    if [[ -f "$bundle/Contents/MacOS/$name" ]]; then
        objects+=("$bundle/Contents/MacOS/$name")
    elif [[ -f "$bundle" ]]; then
        objects+=("$bundle")
    fi
done
[[ ${#objects[@]} -gt 0 ]] || { echo "error: $bin_path にテストバンドルがない" >&2; exit 1; }

# 最初のバイナリは位置引数、残りは -object で渡す(llvm-cov の引数の形)
cov_args=(-instr-profile "$profdata" -ignore-filename-regex 'TestSupport/' "${objects[0]}")
for object in "${objects[@]:1}"; do
    cov_args+=(-object "$object")
done
cov_args+=("$package/Sources")

"${llvm_cov[@]}" report "${cov_args[@]}"

# 比較には丸めない値を使い(79.996 を 80.00 に丸めて通さないため)、表示だけ小数 2 桁に丸める
percent=$("${llvm_cov[@]}" export -summary-only "${cov_args[@]}" | python3 -c '
import json, sys
lines = json.load(sys.stdin)["data"][0]["totals"]["lines"]
print(repr(float(lines["percent"])))
')
percent_display=$(printf '%.2f' "$percent")
echo "line coverage: ${percent_display}%"

if [[ -n "$minimum" ]] && ! awk -v p="$percent" -v m="$minimum" 'BEGIN { exit !(p >= m) }'; then
    echo "error: 行カバレッジ ${percent_display}% が最低値 ${minimum}% を下回った" >&2
    exit 1
fi
