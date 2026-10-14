#!/usr/bin/env python3
"""Applies Almanac's platform requirements on top of `flutter create` output.

* Android: Health Connect needs minSdk 26.
* iOS: HealthKit usage strings (the app itself is Android-first; see README).
Safe to run repeatedly."""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def patch_gradle():
    for name in ("android/app/build.gradle.kts", "android/app/build.gradle"):
        path = os.path.join(ROOT, name)
        if not os.path.isfile(path):
            continue
        with open(path) as f:
            src = f.read()
        out = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 26", src)
        out = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 26", out)
        if out != src:
            with open(path, "w") as f:
                f.write(out)
            print("patched minSdk 26 in", name)
        else:
            print("minSdk already customised in", name)


def patch_gradle_properties():
    path = os.path.join(ROOT, "android/gradle.properties")
    if not os.path.isfile(path):
        return
    with open(path) as f:
        src = f.read()
    if "android.useAndroidX" not in src:
        with open(path, "a") as f:
            f.write("\nandroid.useAndroidX=true\n")
        print("patched gradle.properties")


def patch_ios():
    path = os.path.join(ROOT, "ios/Runner/Info.plist")
    if not os.path.isfile(path):
        return
    with open(path) as f:
        src = f.read()
    if "NSHealthShareUsageDescription" in src:
        return
    keys = (
        "\t<key>NSHealthShareUsageDescription</key>\n"
        "\t<string>Almanac reads sleep, heart, activity and nutrition data to explain it in plain words. It stays on this device.</string>\n"
        "\t<key>NSHealthUpdateUsageDescription</key>\n"
        "\t<string>Almanac does not write health data.</string>\n"
    )
    idx = src.rfind("</dict>")
    if idx == -1:
        return
    with open(path, "w") as f:
        f.write(src[:idx] + keys + src[idx:])
    print("patched iOS Info.plist")


if __name__ == "__main__":
    patch_gradle()
    patch_gradle_properties()
    patch_ios()
