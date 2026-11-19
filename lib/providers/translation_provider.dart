import 'package:flutter/services.dart'
    show rootBundle; // ✨ Required to read local bundled files
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// --- The State Object (Unchanged) ---
class TranslationState {
  final String langCode;
  final Map<String, dynamic> strings;
  final bool isLoading; // Renamed from isDownloading

  TranslationState({
    this.langCode = 'en',
    this.strings = const {},
    this.isLoading = false,
  });

  TranslationState copyWith({
    String? langCode,
    Map<String, dynamic>? strings,
    bool? isLoading,
  }) {
    return TranslationState(
      langCode: langCode ?? this.langCode,
      strings: strings ?? this.strings,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// --- The Offline Engine ---
class TranslationNotifier extends Notifier<TranslationState> {
  @override
  TranslationState build() {
    _loadCachedLanguage();
    return TranslationState();
  }

  // Load the signed-in student's saved language on app startup. Signed out
  // (intro, sign-in) the app is always English: another language appears only
  // after the student picks it on the language page.
  Future<void> _loadCachedLanguage() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) return;
    } catch (_) {
      return; // Firebase not ready → English; sign-in restores the choice
    }
    await restoreSaved();
  }

  /// The language this student picked (kept with their data on this phone by
  /// DeviceOwner), or English when they haven't picked one. Called after
  /// sign-in, once their data is in place.
  Future<void> restoreSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString('app_lang') ?? 'en';
    if (savedLang == 'en') {
      showEnglish();
    } else if (savedLang != state.langCode) {
      await loadLanguagePack(savedLang);
    }
  }

  /// English on screen without forgetting the student's choice (sign-out).
  void showEnglish() {
    if (state.langCode != 'en' || state.strings.isNotEmpty) {
      state = TranslationState();
    }
  }

  // ✨ The core function triggered by your Language Selection screen
  Future<bool> loadLanguagePack(String langCode) async {
    state = state.copyWith(isLoading: true);

    try {
      // 1. Read the JSON file directly from the local app bundle
      final jsonString =
          await rootBundle.loadString('assets/locales/$langCode.json');
      final decodedMap = jsonDecode(jsonString);

      // 2. Save the preference so the app remembers it next time
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_lang', langCode);

      // 3. Update the live app UI instantly
      state = state.copyWith(
        langCode: langCode,
        strings: decodedMap,
        isLoading: false,
      );
      return true;
    } catch (e) {
      // Fallback to English if the file is missing or corrupted
      state = state.copyWith(isLoading: false, langCode: 'en', strings: {});
      return false;
    }
  }

  // Helper method to actually translate text in your UI
  String tr(String key, [String fallback = '']) {
    if (state.langCode == 'en') return fallback.isNotEmpty ? fallback : key;
    return state.strings[key] ?? fallback;
  }
}

final translationProvider =
    NotifierProvider<TranslationNotifier, TranslationState>(
  TranslationNotifier.new,
);
