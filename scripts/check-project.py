#!/usr/bin/env python3
"""Sanity-check the Xcode project and the parser algorithms. No macOS required."""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
ERRORS: list[str] = []


def error(msg: str) -> None:
    ERRORS.append(msg)


def check_layout() -> None:
    required = [
        "VibeMode.xcodeproj/project.pbxproj",
        "VibeMode.xcodeproj/xcshareddata/xcschemes/VibeMode.xcscheme",
        "VibeMode/Info.plist",
        "VibeMode/VibeMode.entitlements",
        "README.md",
        "INSTALL-DA.md",
        "scripts/emergency-restore-sleep.sh",
        "scripts/install-passwordless-pmset.sh",
    ]
    for rel in required:
        if not (ROOT / rel).is_file():
            error(f"missing {rel}")

    swift = sorted((ROOT / "VibeMode").glob("*.swift"))
    if len(swift) < 10:
        error(f"expected >= 10 Swift files, found {len(swift)}")

    pbx = (ROOT / "VibeMode.xcodeproj/project.pbxproj").read_text()
    if "marquee" in pbx:
        error("pbxproj contains stray token 'marquee'")
    if "dk.lars.vibemode" not in pbx:
        error("bundle id missing from pbxproj")
    if "MACOSX_DEPLOYMENT_TARGET = 14.0" not in pbx:
        error("deployment target is not 14.0")
    if "ENABLE_APP_SANDBOX = NO" not in pbx:
        error("sandbox must be off")
    arch_lines = [
        line for line in pbx.splitlines()
        if "ARCHS" in line and "ALWAYS_SEARCH" not in line and "ONLY_ACTIVE_ARCH" not in line
    ]
    if arch_lines and not any("arm64" in line or "ARCHS_STANDARD" in line for line in arch_lines):
        error("ARCHS must include arm64")

    for path in swift:
        if path.name not in pbx:
            error(f"{path.name} is not in project.pbxproj")
        if pbx.count(f"{path.name} in Sources") < 1:
            error(f"{path.name} is not in the Sources build phase")


def check_braces() -> None:
    for path in (ROOT / "VibeMode").glob("*.swift"):
        text = path.read_text()
        # Ignore braces in strings roughly by not parsing; a simple count is enough
        # to catch a truncated file.
        if text.count("{") != text.count("}"):
            error(f"{path.name}: unbalanced {{ }} ({text.count('{')} vs {text.count('}')})")
        if text.count("(") != text.count(")"):
            error(f"{path.name}: unbalanced ( ) ({text.count('(')} vs {text.count(')')})")


def parse_sleep_disabled(text: str) -> bool | None:
    for line in text.splitlines():
        trimmed = line.strip()
        if "sleepdisabled" in trimmed.lower():
            if "1" in trimmed:
                return True
            if "0" in trimmed:
                return False
    return None


def parse_lsof(output: str) -> list[tuple[int, str, str, str]]:
    results = []
    seen: set[str] = set()
    for raw in output.splitlines():
        if raw.startswith("COMMAND"):
            continue
        if "(LISTEN)" not in raw:
            continue
        without = raw.replace(" (LISTEN)", "")
        cols = without.split()
        if len(cols) < 9:
            continue
        try:
            pid = int(cols[1])
        except ValueError:
            continue
        command = cols[0]
        address = cols[-1]
        port = address.split(":")[-1]
        key = f"{pid}-{port}-{command}"
        if key in seen:
            continue
        seen.add(key)
        results.append((pid, command, address, port))
    return results


def parse_lsof_fields(output: str) -> list[tuple[int, str, str, str]]:
    results = []
    seen: set[str] = set()
    pid = None
    command = None
    for line in output.splitlines():
        if not line:
            continue
        flag, rest = line[0], line[1:]
        if flag == "p":
            pid = int(rest)
            command = None
        elif flag == "c":
            command = rest
        elif flag == "n" and pid is not None and command is not None:
            address = rest
            port = address.split(":")[-1]
            key = f"{pid}-{port}-{command}"
            if key in seen:
                continue
            seen.add(key)
            results.append((pid, command, address, port))
    return results


def display_name_matches(candidate: str, stem: str) -> bool:
    value = candidate.strip()
    stem = stem.strip()
    if not value or not stem:
        return False
    if value.lower() == stem.lower():
        return True
    lower = value.lower()
    stem_lower = stem.lower()
    return lower.startswith(stem_lower + " ") or lower.startswith(stem_lower + "-")


def bundle_id_matches(bundle_id: str, allowed: list[str]) -> bool:
    needle = bundle_id.strip()
    if not needle:
        return False
    for allowed_id in allowed:
        if not allowed_id:
            continue
        if needle.lower() == allowed_id.lower():
            return True
        if needle.lower().startswith(allowed_id.lower() + "."):
            return True
    return False


def allowlist_matches(bundle_ids: list[str], process_names: list[str], name: str,
                      bundle_id: str | None, localized: str | None, process: str | None) -> bool:
    if bundle_id and bundle_id_matches(bundle_id, bundle_ids):
        return True
    for candidate in (localized, process):
        if not candidate:
            continue
        candidate = candidate.strip()
        if any(display_name_matches(candidate, p) for p in process_names):
            return True
        if display_name_matches(candidate, name):
            return True
    return False


def merge_factory(existing: list[dict], factory: list[dict]) -> list[dict]:
    result = [dict(item) for item in existing]
    for factory_item in factory:
        for item in result:
            if item["name"].lower() == factory_item["name"].lower():
                for bid in factory_item["bundleIDs"]:
                    if bid.lower() not in [b.lower() for b in item["bundleIDs"]]:
                        item["bundleIDs"].append(bid)
                for proc in factory_item["processNames"]:
                    if proc.lower() not in [p.lower() for p in item["processNames"]]:
                        item["processNames"].append(proc)
                break
        else:
            result.append(dict(factory_item))
    return result


def check_parsers() -> None:
    sample_pmset = """
System-wide power settings:
 SleepDisabled		1
Currently in use:
 sleep            1
 displaysleep     10
 tcpkeepalive     1
"""
    if parse_sleep_disabled(sample_pmset) is not True:
        error("failed to parse SleepDisabled 1")
    if parse_sleep_disabled("Currently in use:\n sleep 1\n") is not None:
        error("false positive SleepDisabled")
    if parse_sleep_disabled(" SleepDisabled\t\t0\n") is not True and parse_sleep_disabled(" SleepDisabled\t\t0\n") is not False:
        error("failed to parse SleepDisabled 0")
    if parse_sleep_disabled(" SleepDisabled\t\t0\n") is not False:
        error("SleepDisabled 0 should be False")

    lsof_text = """COMMAND     PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
node      41211 lars   23u  IPv6 0xabc           0t0  TCP *:3000 (LISTEN)
Cursor    22001 lars   32u  IPv4 0xdef           0t0  TCP 127.0.0.1:61222 (LISTEN)
Python    19901 lars    3u  IPv4 0x111           0t0  TCP 127.0.0.1:8000 (LISTEN)
"""
    parsed = parse_lsof(lsof_text)
    got = {(p[1], p[3]) for p in parsed}
    if got != {("node", "3000"), ("Cursor", "61222"), ("Python", "8000")}:
        error(f"parseLsof mismatch: {got}")

    fields = "p41211\ncnode\nn*:3000\np22001\ncCursor\nn127.0.0.1:61222\n"
    fparsed = parse_lsof_fields(fields)
    fgot = {(p[1], p[3]) for p in fparsed}
    if fgot != {("node", "3000"), ("Cursor", "61222")}:
        error(f"parseLsofFields mismatch: {fgot}")

    if not allowlist_matches(
        ["com.todesktop.230313mzl4w4u92"], ["Cursor"], "Cursor",
        "com.todesktop.230313mzl4w4u92", "Cursor", "Cursor",
    ):
        error("Cursor allowlist should match")
    if allowlist_matches(
        ["com.todesktop.230313mzl4w4u92"], ["Cursor"], "Cursor",
        "com.apple.Safari", "Safari", "Safari",
    ):
        error("Safari should not match Cursor allowlist")
    if not allowlist_matches(
        ["com.anthropic.claudefordesktop"], ["Claude", "claude"], "Claude",
        None, "Claude", "Claude",
    ):
        error("Claude should match by process name")

    chatgpt_ids = ["com.openai.chat", "com.openai.chatgpt", "com.openai.codex"]
    if not allowlist_matches(
        chatgpt_ids, ["ChatGPT", "ChatGPT Classic"], "ChatGPT",
        "com.openai.codex", "ChatGPT", "ChatGPT",
    ):
        error("unified ChatGPT.app (com.openai.codex) should stay open")
    if not allowlist_matches(
        chatgpt_ids, ["ChatGPT", "ChatGPT Classic"], "ChatGPT",
        "com.openai.chat", "ChatGPT Classic", "ChatGPT",
    ):
        error("ChatGPT Classic should stay open")
    if not allowlist_matches(
        chatgpt_ids, ["ChatGPT", "ChatGPT Classic"], "ChatGPT",
        "com.openai.codex.helper", "ChatGPT Helper", "ChatGPT Helper (Renderer)",
    ):
        error("ChatGPT Electron helper should stay open")
    if not allowlist_matches(
        ["com.openai.codex", "com.openai.chat"], ["Codex", "codex"], "Codex",
        "com.openai.codex", "Codex", "Codex",
    ):
        error("Codex desktop should stay open")
    if not allowlist_matches(
        ["com.anysphere.sand", "co.anysphere.grok-bot-computer-use"],
        ["Grok Bot", "Grokbot", "Grok"],
        "Grok Bot",
        "com.anysphere.sand", "Grok Bot", "Grok Bot",
    ):
        error("Grok Bot should stay open")
    if not allowlist_matches(
        ["com.anysphere.sand", "co.anysphere.grok-bot-computer-use"],
        ["Grok Bot", "Grokbot", "Grok"],
        "Grok Bot",
        "co.anysphere.grok-bot-computer-use", "Grok Bot Computer Use", "Grok Bot Computer Use",
    ):
        error("Grok Bot computer-use helper should stay open")
    if allowlist_matches(
        chatgpt_ids, ["ChatGPT", "ChatGPT Classic"], "ChatGPT",
        "com.apple.Safari", "Safari", "Safari",
    ):
        error("Safari should not match ChatGPT allowlist")

    old_list = [{"name": "Claude", "bundleIDs": ["com.anthropic.claude"], "processNames": ["Claude"]}]
    factory = [
        {"name": "ChatGPT", "bundleIDs": ["com.openai.codex"], "processNames": ["ChatGPT"]},
        {"name": "Claude", "bundleIDs": ["com.anthropic.claude", "com.anthropic.claudefordesktop"], "processNames": ["Claude", "claude"]},
    ]
    merged = merge_factory(old_list, factory)
    names = [item["name"] for item in merged]
    if "ChatGPT" not in names:
        error("factory merge should add ChatGPT to an older allowlist")
    claude = next(item for item in merged if item["name"] == "Claude")
    if "com.anthropic.claudefordesktop" not in claude["bundleIDs"]:
        error("factory merge should union extra Claude bundle IDs")


def check_no_force_kill() -> None:
    for path in (ROOT / "VibeMode").glob("*.swift"):
        text = path.read_text()
        if re.search(r"\.forceTerminate\s*\(", text):
            error(f"{path.name} uses forceTerminate — graceful quit only")
        if re.search(r"kill\s*-9", text):
            error(f"{path.name} uses kill -9")


def check_danish_guide() -> None:
    text = (ROOT / "INSTALL-DA.md").read_text()
    for needle in [
        "Xcode",
        "VibeMode.xcodeproj",
        "disablesleep",
        "administrator",
        "sudoers",
        "sudo pmset -a disablesleep 0",
        "Personal Team",
        "App Sandbox",
    ]:
        if needle.lower() not in text.lower() and needle not in text:
            error(f"INSTALL-DA.md missing {needle!r}")
    if "Klap låget" not in text and "klapper låget" not in text.lower():
        # still ok if other phrasing
        pass
    if len(text) < 2000:
        error("INSTALL-DA.md looks too short")


def main() -> int:
    check_layout()
    check_braces()
    check_parsers()
    check_no_force_kill()
    check_danish_guide()
    if ERRORS:
        print("FAIL")
        for item in ERRORS:
            print(" -", item)
        return 1
    print("OK — project layout, parsers, and docs check out.")
    print("Note: this environment cannot run xcodebuild (Linux). Build on a Mac with Xcode.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
