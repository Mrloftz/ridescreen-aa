#!/usr/bin/env python3
"""Check that the native CarPlay scene is registered in the iOS target."""

from pathlib import Path
import plistlib


ROOT = Path(__file__).resolve().parents[2]
INFO_PLIST = ROOT / "ios/RideScreen/Info.plist"
ENTITLEMENTS = ROOT / "ios/RideScreen/RideScreen.entitlements"
PROJECT = ROOT / "ios/RideScreen.xcodeproj/project.pbxproj"
SCENE_SOURCE = ROOT / "ios/RideScreen/CarPlaySceneDelegate.swift"
THEME_SOURCE = ROOT / "ios/RideScreen/RideScreenTheme.swift"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


with INFO_PLIST.open("rb") as source:
    info = plistlib.load(source)

scene_manifest = info.get("UIApplicationSceneManifest", {})
scene_configurations = scene_manifest.get("UISceneConfigurations", {})
carplay_scenes = scene_configurations.get(
    "CPTemplateApplicationSceneSessionRoleApplication", []
)
require(len(carplay_scenes) == 1, "expected exactly one CarPlay application scene")
require(
    carplay_scenes[0].get("UISceneClassName") == "CPTemplateApplicationScene",
    "CarPlay scene class is not registered",
)
require(
    carplay_scenes[0].get("UISceneDelegateClassName")
    == "$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate",
    "CarPlay scene delegate is not registered",
)

with ENTITLEMENTS.open("rb") as source:
    entitlements = plistlib.load(source)
require(
    entitlements.get("com.apple.developer.carplay-maps") is True,
    "CarPlay Maps entitlement is missing",
)

project = PROJECT.read_text(encoding="utf-8")
require(SCENE_SOURCE.is_file(), "CarPlay scene delegate source is missing")
require(
    "CarPlaySceneDelegate.swift in Sources" in project,
    "CarPlay scene delegate is not compiled into the app target",
)
scene_source = SCENE_SOURCE.read_text(encoding="utf-8")
recenter_method = scene_source.split("func recenterOnRider()", 1)[-1].split("\n    }", 1)[0]
require(
    "setUserTrackingMode(.follow, animated: true)" in recenter_method,
    "recenter action must restore continuous rider tracking",
)
theme_source = THEME_SOURCE.read_text(encoding="utf-8")
require(
    '.custom("ArchivoBlack-Regular", size: size, relativeTo: .largeTitle)' in theme_source,
    "display font must use the Font.custom size: API label",
)

print("CarPlaySceneConfigurationTests passed")
