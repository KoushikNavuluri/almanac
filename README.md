<p align="center">
  <img src="assets/branding/icon.svg" width="120" alt="Almanac icon" />
</p>

<h1 align="center">ALMANAC</h1>
<p align="center"><b>Your body's weather report.</b><br/>A local-first, AI-powered health companion for Android (Flutter). No account. No backend. Your own Gemini key.</p>

---

Almanac reads your **Health Connect** data (Fitbit sleep, HRV, resting heart rate, SpO2, respiration, steps, plus Cravin' meals and caffeine) and turns it into a sky: the sun's height is your readiness, clouds are short sleep and late dinners. Then it explains what the numbers mean in plain language, surfaces patterns, and suggests 7-day experiments you can actually run.

## Features

- **Today**: readiness sky, plain-language forecast, three things that mattered today.
- **Discover**: pattern cards computed on-device (late dinner vs deep sleep, weekend jet lag, caffeine cutoff, post-lunch walk vs steps), plus a daily fun fact about your body.
- **Ask**: chat with your data. Gemini answers with your aggregates as context; a local brain answers when no key is set or you're offline.
- **Almanac**: every metric with a 30-day chart, your personal normal, and a "what this means" explainer.
- **Experiments**: kitchen (dinner by 8:30), walk (10 min after lunch), chai (last chai by 3), weekend (same alarm). Daily check-ins, before/after result.
- **Me**: AI key, sharing controls, request log, export (JSON/CSV via share sheet), sample-data mode, wipe everything.
- Error, empty, loading and offline states everywhere. Reduced-motion respected.

## Privacy architecture

| Stays on the phone, always | Sent to Gemini (only when you ask for AI) | Never sent |
|---|---|---|
| Raw Health Connect records | Daily aggregates for the last 7/14/30 days (you choose) | Raw heart-rate samples, timestamps of individual readings |
| Your history, experiments, chat | 30-day normals + computed patterns | Your name, device IDs, location |
| API key (Android Keystore via `flutter_secure_storage`) | Categories you enabled: sleep, heart, steps, food | Meal names and body weight (unless you opt in) |
| | | Crisis/emergency messages (handled locally, points to Tele-MANAS 14416 / 112) |

- Settings → **Privacy** shows the **exact JSON payload** before anything leaves the device.
- Every AI request is logged locally (time, size, categories) so you can audit it.
- Heads up: on Gemini's **free tier**, Google may use prompts to improve its products. Use a paid-tier key if that matters to you. The app says this in-line.
- `android:allowBackup="false"`; app data is excluded from cloud backups.

## BYOK: bring your own Gemini key

1. Get a key at <https://aistudio.google.com/apikey>.
2. In the app: **Me → AI & key → Paste key → Verify**. Almanac calls the models endpoint, then lets you pick a model (default `gemini-3.8-flash`).
3. Update or remove the key any time. No key = everything still works with the on-device brain.

## Quick start

Requires Flutter (stable, Dart ≥ 3.8), Android SDK, Python 3 with Pillow (`pip install pillow`).

```bash
git clone https://github.com/KoushikNavuluri/almanac.git
cd almanac
bash tool/bootstrap.sh     # generates missing platform files, patches minSdk/HealthKit strings, renders icons, pub get
flutter run                # on a phone with Health Connect
flutter build apk --release
```

`bootstrap.sh` only fills in files that aren't committed; the committed Android manifest, `MainActivity` (FlutterFragmentActivity), adaptive icon, splash and themes are kept.

## CI (one manual step)

The workflow lives at `ci/build-apk.yml` because the push token lacked `workflow` scope. To enable it:

```bash
mkdir -p .github/workflows && git mv ci/build-apk.yml .github/workflows/build-apk.yml
git commit -m "ci: enable APK build" && git push
```

It runs analyze + tests, builds a release APK, uploads it as an artifact, and publishes a rolling `nightly` release.

## Health Connect mapping

| Metric | Health Connect type | Typical source |
|---|---|---|
| Sleep total / deep / REM / light / awake | `SLEEP_SESSION`, `SLEEP_DEEP`, `SLEEP_REM`, `SLEEP_LIGHT`, `SLEEP_AWAKE` | Fitbit |
| HRV | `HEART_RATE_VARIABILITY_RMSSD` | Fitbit |
| Resting heart rate | `RESTING_HEART_RATE` | Fitbit |
| SpO2, respiration | `BLOOD_OXYGEN`, `RESPIRATORY_RATE` | Fitbit |
| Steps, active minutes | `STEPS`, `EXERCISE_TIME` | Fitbit |
| Meals, calories, protein, caffeine | `NUTRITION` | Cravin' |
| Weight (opt-in) | `WEIGHT` | any |

Almanac requests the **history** permission to read 30 days back (Health Connect otherwise limits reads to 30 days from install).

## Project structure

```
lib/
  ai/        gemini_client, health_context (privacy payload), ai_service, local_brain, chat_models
  data/      health_source (Health Connect), local_store (JSON + KeyVault), sample_data
  domain/    metrics, insights (patterns, readiness), export
  models/    day_record
  screens/   today, discover, ask, almanac, metric, experiment, me, ai_settings, privacy, onboarding, shell, connect_flow
  state/     app_controller (AppScope)
  theme/     tokens (Bebas Neue / Merriweather, navy · teal · sun · crimson)
  widgets/   sky, charts, common
android/     committed overrides (manifest, MainActivity, icons, splash, themes)
assets/branding/icon.svg
tool/        bootstrap.sh, patch_android.py, make_icons.py
ci/          build-apk.yml
test/        unit + widget tests
```

## Known limitations

- **Android first.** iOS builds but is untested; enable the HealthKit capability in Xcode first.
- Fitbit's sync to Health Connect varies by metric and firmware; missing metrics show as "not synced" rather than zero.
- Release builds use debug signing until you add a keystore (`android/key.properties`).
- Almanac is not a medical device. It explains trends; it doesn't diagnose.

## License

MIT