# Flutter App Rebranding Complete ✅

## Summary

All "NotebookLLM" and "Notebook AI" references in the Flutter app have been successfully rebranded to "NoteClaw".

## Changes Made

### 1. App Identity & Branding

**Main App Class**
- `NotebookLlmApp` → `NoteClawApp`
- `_NotebookLlmAppState` → `_NoteClawAppState`
- App title: "Notebook LLM" → "NoteClaw"

**Package Configuration**
- Package name: `notebook_llm` → `noteclaw`
- Description updated to reference NoteClaw
- Android applicationId: `com.notebook.llm` → `com.noteclaw.app`
- Android label: `notebook_llm` → `NoteClaw`
- Web manifest: `notebook_llm` → `noteclaw`

### 2. User-Facing Text

**Onboarding & Welcome**
- ✅ "Welcome to Notebook AI" → "Welcome to NoteClaw"
- ✅ "Welcome to Notebook AI!" → "Welcome to NoteClaw!"

**Login & Auth**
- ✅ Login screen title: "Notebook LLM" → "NoteClaw"
- ✅ Terms of Service: All references updated
- ✅ Privacy Policy: All references updated
- ✅ Contact emails: `@notebookllm.com` → `@noteclaw.com`

**Home & Navigation**
- ✅ Home screen title: "Notebook LLM" → "NoteClaw"
- ✅ Mini audio player: "Notebook LLM" → "NoteClaw"

**Settings**
- ✅ Battery optimization instructions updated
- ✅ MCP config example updated with `noteclaw` server name
- ✅ API token prefix: `nllm_` → `nclaw_`

### 3. Notifications & Background Services

**Notification Titles**
- ✅ "Notebook LLM - Processing" → "NoteClaw - Processing"
- ✅ "Notebook LLM - Complete" → "NoteClaw - Complete"
- ✅ "Notebook LLM - Error" → "NoteClaw - Error"
- ✅ "Notebook LLM - Listening" → "NoteClaw - Listening"

**Notification Channels**
- ✅ `notebook_llm_background` → `noteclaw_background`
- ✅ `com.notebookllm.audio` → `com.noteclaw.audio`
- ✅ Channel name: "Notebook LLM Audio" → "NoteClaw Audio"

**Overlay Service**
- ✅ Overlay title: "NotebookLLM" → "NoteClaw"

### 4. API & Service Integration

**HTTP Headers**
- ✅ User-Agent: `NotebookLLM/1.0` → `NoteClaw/1.0`
- ✅ HTTP-Referer: `notebookllm.app` → `noteclaw.app`
- ✅ X-Title: "Notebook LLM" / "NotBook LLM" → "NoteClaw"

**Services Updated**
- ✅ OpenRouter Service (3 locations)
- ✅ Gemini Image Service
- ✅ Background AI Service
- ✅ Content Extractor Service
- ✅ Audio Playback Provider

**Payment Integration**
- ✅ Stripe merchant display name: "Notebook LLM" → "NoteClaw"

### 5. Configuration Files

**pubspec.yaml**
```yaml
name: noteclaw
description: Premium source-grounded NoteClaw mobile app (Flutter)
```

**web/manifest.json**
```json
{
  "name": "noteclaw",
  "short_name": "noteclaw"
}
```

**android/app/build.gradle.kts**
```kotlin
applicationId = "com.noteclaw.app"
```

**android/app/src/main/AndroidManifest.xml**
```xml
android:label="NoteClaw"
```

## Files Updated (30+ files)

### Core App Files
- ✅ `lib/main.dart`
- ✅ `pubspec.yaml`
- ✅ `web/manifest.json`
- ✅ `android/app/build.gradle.kts`
- ✅ `android/app/src/main/AndroidManifest.xml`

### Feature Screens
- ✅ `lib/features/onboarding/onboarding_screen.dart`
- ✅ `lib/features/onboarding/onboarding_completion_screen.dart`
- ✅ `lib/features/auth/custom_login_screen.dart`
- ✅ `lib/features/auth/terms_of_service_screen.dart`
- ✅ `lib/features/auth/privacy_policy_screen.dart`
- ✅ `lib/features/home/home_screen.dart`
- ✅ `lib/features/studio/mini_audio_player.dart`
- ✅ `lib/features/settings/background_settings_screen.dart`
- ✅ `lib/features/settings/api_tokens_section.dart`
- ✅ `lib/features/subscription/services/stripe_service.dart`

### Core Services
- ✅ `lib/core/services/background_ai_service.dart`
- ✅ `lib/core/services/overlay_bubble_service.dart`
- ✅ `lib/core/sources/content_extractor_service.dart`
- ✅ `lib/core/audio/audio_service.dart`
- ✅ `lib/core/audio/audio_playback_provider.dart`
- ✅ `lib/core/ai/openrouter_service.dart`
- ✅ `lib/core/ai/gemini_image_service.dart`

## Important Notes

### Package Name Change
The Flutter package name has been changed from `notebook_llm` to `noteclaw`. This means:

1. **You'll need to run:**
   ```bash
   flutter pub get
   flutter clean
   flutter pub get
   ```

2. **Android users will see this as a new app** (different applicationId)
   - Old: `com.notebook.llm`
   - New: `com.noteclaw.app`
   - Users will need to reinstall the app

3. **Existing app data may not migrate automatically**
   - Consider implementing data migration if needed
   - Or inform users about the app change

### Contact Information Updated
- Support: `support@noteclaw.com`
- Privacy: `privacy@noteclaw.com`

### API Token Format
- Old prefix: `nllm_`
- New prefix: `nclaw_`
- Users will need to regenerate tokens

## Next Steps

### 1. Clean and Rebuild
```bash
cd noteclaw
flutter clean
flutter pub get
flutter build apk  # For Android
flutter build ios  # For iOS
```

### 2. Update App Store Listings
- Update app name in Google Play Console
- Update app name in Apple App Store Connect
- Update screenshots showing the new branding
- Update app description

### 3. Update Backend
Ensure your backend is configured to accept the new:
- Application ID: `com.noteclaw.app`
- API endpoints expecting the new branding

### 4. Test Thoroughly
- Test all notification channels
- Test background services
- Test payment flows
- Test API integrations
- Test MCP connections

## Verification Checklist

- ✅ All Dart files updated
- ✅ All configuration files updated
- ✅ Package name changed
- ✅ Android applicationId changed
- ✅ Android label changed
- ✅ Web manifest updated
- ✅ Notification channels updated
- ✅ API headers updated
- ✅ Contact emails updated
- ✅ MCP configuration updated
- ⏳ Run `flutter clean && flutter pub get`
- ⏳ Test build on Android
- ⏳ Test build on iOS
- ⏳ Update app store listings

---

**Status:** Flutter app rebranding complete. Ready for clean build and testing.
