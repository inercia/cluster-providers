#!/usr/bin/env bash

set -e
set -o pipefail

TOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -r "$TEST_DIR"' EXIT

mkdir "$TEST_DIR/bin" "$TEST_DIR/install"
# Isolate PATH so a locally installed k3d or Docker cannot affect these tests.
for tool in bash dirname whoami uname grep cut cp rm; do
    ln -s "$(command -v "$tool")" "$TEST_DIR/bin/$tool"
done
ln -s "$TOP_DIR/tests/fixtures/k3d-curl.sh" "$TEST_DIR/bin/curl"

export PATH="$TEST_DIR/bin"
export EXE_DIR="$TEST_DIR/install"
export CLUSTER_PROVIDER=k3d
export TEST_CURL_LOG="$TEST_DIR/curl.log"
export TEST_INSTALL_LOG="$TEST_DIR/install.log"
export TEST_K3D_FIXTURE="$TOP_DIR/tests/fixtures/k3d.sh"
unset K3D_VERSION GITHUB_ACTION

mock_install() {
    printf '%s|%s\n' "$TAG" "$K3D_INSTALL_DIR" >> "$TEST_INSTALL_LOG"
    [ "${TEST_INSTALL_FAIL:-0}" = 0 ] || return 1
    [ "${TEST_INSTALL_MISSING:-0}" = 0 ] || return 0
    cp "$TEST_K3D_FIXTURE" "$K3D_INSTALL_DIR/k3d"
}
docker() {
    # get-env can inspect containers, but never needs a real Docker daemon.
    return 1
}
export -f mock_install docker

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    grep -Fq -- "$2" "$1" || fail "expected '$2' in $1"
}

run_provider() {
    bash "$TOP_DIR/providers.sh" "$1" > "$TEST_DIR/output" 2>&1
}

expect_failure() {
    if run_provider "$1"; then
        fail "expected $1 to fail"
    fi
    assert_contains "$TEST_DIR/output" "$2"
}

run_provider setup
assert_contains "$TEST_INSTALL_LOG" "v5.2.0|$EXE_DIR"
assert_contains "$TEST_CURL_LOG" "-fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh"
run_provider get-env
assert_contains "$TEST_DIR/output" "K3D_VERSION='v5.2.0'"

rm "$EXE_DIR/k3d"
export K3D_VERSION=v5.8.3
run_provider setup
assert_contains "$TEST_INSTALL_LOG" "v5.8.3|$EXE_DIR"
run_provider get-env
assert_contains "$TEST_DIR/output" "K3D_VERSION='v5.8.3'"
export GITHUB_ACTION=k3d-setup-test
export GITHUB_ENV="$TEST_DIR/github-env"
run_provider get-env
assert_contains "$GITHUB_ENV" "K3D_VERSION=v5.8.3"
unset GITHUB_ACTION GITHUB_ENV

# The sourced API also inherits the exported caller version.
rm "$EXE_DIR/k3d"
export K3D_VERSION=v5.9.0
bash -c 'source "$1/providers.sh"; cluster_provider setup' _ "$TOP_DIR" > "$TEST_DIR/output" 2>&1
assert_contains "$TEST_INSTALL_LOG" "v5.9.0|$EXE_DIR"

before=$(< "$TEST_INSTALL_LOG")
run_provider setup
[ "$before" = "$(< "$TEST_INSTALL_LOG")" ] || fail "reinstalled an existing binary"

curl_before=$(< "$TEST_CURL_LOG")
for version in '' latest 5.8.3 v5.8 'v5.8.3 bad' 'v5.8.3/other' 'v5.8.3-'; do
    export K3D_VERSION="$version"
    expect_failure setup "FATAL: invalid K3D_VERSION"
    expect_failure get-env "FATAL: invalid K3D_VERSION"
done
[ "$before" = "$(< "$TEST_INSTALL_LOG")" ] || fail "installed an invalid version"
[ "$curl_before" = "$(< "$TEST_CURL_LOG")" ] || fail "downloaded for an invalid version"

rm "$EXE_DIR/k3d"
export K3D_VERSION=v5.8.0-rc.1
run_provider setup
assert_contains "$TEST_INSTALL_LOG" "v5.8.0-rc.1|$EXE_DIR"
rm "$EXE_DIR/k3d"

before=$(< "$TEST_INSTALL_LOG")
export TEST_CURL_FAIL=1
expect_failure setup "FATAL: could not download K3D"
[ "$before" = "$(< "$TEST_INSTALL_LOG")" ] || fail "executed a partial download"
unset TEST_CURL_FAIL

export TEST_INSTALL_FAIL=1
expect_failure setup "FATAL: could not install k3d version v5.8.0-rc.1"
unset TEST_INSTALL_FAIL

export TEST_INSTALL_MISSING=1
expect_failure setup "FATAL: could not install k3d"
unset TEST_INSTALL_MISSING

expect_failure create "TAG='v5.8.0-rc.1'"
printf 'k3d setup tests passed\n'
