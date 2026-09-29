#!/usr/bin/env python3
"""Assemble embedded cmux's Chinese resources without modifying upstream catalogs.

cmux's main target uses Bundle.main, whereas Swift packages use Bundle.module.
Keep both resource locations usable, including when running through SwiftPM.
"""

import argparse
from collections import Counter
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

MACOS = Path(__file__).resolve().parent.parent
OVERRIDES = MACOS / "CmuxEmbeddedIntegration/Localization"
LANGUAGE = "zh-Hans"


def placeholders(value):
    return Counter(re.findall(r"%(?:\d+\$)?([-+ #0]*\d*(?:\.\d+)?(?:ll|l|z)?[@diuoxXfFeEgGcs])", value.replace("%%", "")))


def compile_catalog(strings, destination):
    with tempfile.TemporaryDirectory(prefix="devhaven-localization-") as temporary:
        catalog = Path(temporary) / "Localizable.xcstrings"
        catalog.write_text(json.dumps({"sourceLanguage": "en", "version": "1.0", "strings": strings}))
        destination.mkdir(parents=True, exist_ok=True)
        subprocess.run(["xcrun", "xcstringstool", "compile", str(catalog),
                        "--language", LANGUAGE, "--output-directory", str(destination)], check=True)


def translated_entry(value):
    return {"localizations": {LANGUAGE: {"stringUnit": {"state": "translated", "value": value}}}}


def prepare(source, products, framework):
    # Merge package catalogs too: some package call sites also use Bundle.main.
    strings = {}
    catalogs = sorted(path for platform in ("macOS", "Shared")
                      for path in (source / "Packages" / platform).rglob("Localizable.xcstrings"))
    catalogs.append(source / "Resources/Localizable.xcstrings")
    for catalog in catalogs:
        strings.update(json.loads(catalog.read_text())["strings"])

    overrides = json.loads((OVERRIDES / "Main.json").read_text())
    for key, value in (overrides["preserved"] | overrides["translations"]).items():
        if key not in strings:
            raise ValueError(f"Obsolete localization override: {key}")
        english = strings[key]["localizations"]["en"]["stringUnit"]["value"]
        if key in overrides["preserved"] and english != value:
            raise ValueError(f"Review changed upstream brand/command text: {key}")
        if placeholders(english) != placeholders(value):
            raise ValueError(f"Format placeholders changed: {key}")
        strings[key]["localizations"][LANGUAGE] = translated_entry(value)["localizations"][LANGUAGE]
    missing = [key for key, value in strings.items() if LANGUAGE not in value.get("localizations", {})]
    if missing:
        raise ValueError(f"Missing Chinese translations: {missing}")
    for key, value in overrides["literals"].items():
        if placeholders(key) != placeholders(value):
            raise ValueError(f"Literal format placeholders changed: {key}")
        strings[key] = translated_entry(value)

    resources = framework / "Resources"
    compile_catalog(strings, resources)

    # Xcode builds these beside the framework. Ship them inside it so BundleFinder
    # can find package resources on machines without the build checkout.
    bundles = sorted(products.glob("*.bundle"))
    if not any(bundle.name == "Bonsplit_Bonsplit.bundle" for bundle in bundles):
        raise ValueError("Missing Bonsplit resource bundle in Xcode products")
    for bundle in bundles:
        target = resources / bundle.name
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(bundle, target, symlinks=True)

    bonsplit = resources / "Bonsplit_Bonsplit.bundle/Contents/Resources"
    english = plistlib.loads(subprocess.check_output([
        "plutil", "-convert", "xml1", "-o", "-", str(bonsplit / "en.lproj/Localizable.strings")]))
    chinese = json.loads((OVERRIDES / "Bonsplit.json").read_text())
    if english.keys() != chinese.keys():
        raise ValueError("Bonsplit localization keys changed; update Bonsplit.json")
    for key, value in chinese.items():
        if placeholders(english[key]) != placeholders(value):
            raise ValueError(f"Bonsplit format placeholders changed: {key}")
    compile_catalog({key: translated_entry(value) for key, value in chinese.items()}, bonsplit)
    print(f"Prepared {len(strings)} cmux and {len(chinese)} tab-bar Chinese strings; {len(bundles)} package bundles")


def install(framework, destination):
    source = framework / f"Resources/{LANGUAGE}.lproj"
    if not (source / "Localizable.strings").is_file():
        raise ValueError(f"Missing compiled cmux Chinese resources: {source}")
    target = destination / source.name
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target)
    print(f"Installed cmux host localization: {target}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)
    build = subparsers.add_parser("prepare")
    build.add_argument("--source", type=Path, required=True)
    build.add_argument("--products", type=Path, required=True)
    build.add_argument("--framework", type=Path, required=True)
    copy = subparsers.add_parser("install")
    copy.add_argument("--framework", type=Path, required=True)
    copy.add_argument("--destination", type=Path, required=True)
    args = vars(parser.parse_args())
    action = args.pop("action")
    {"prepare": prepare, "install": install}[action](**args)
