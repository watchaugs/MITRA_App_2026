// ═══════════════════════════════════════════════════════════════════════════
// tr() ergonomics — one import, used in any ConsumerWidget / ConsumerState.
//
//   import '../../providers/tr_ext.dart';
//   ...
//   Text(context.tr(ref, 'home_greeting', 'Namaste'))
//
// WHY the fallback arg: the second string is the English default. It shows when
// the active language is English, or when a pack is missing that key — so the UI
// is NEVER blank, even for a half-translated language. Keep the English text as
// the fallback so nothing breaks if a key is ever removed from a pack.
//
// For {placeholders} use trp():
//   context.trp(ref, 'quiz_question_of', 'Question {current} of {total}',
//               {'current': '$i', 'total': '$n'})
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'translation_provider.dart';

/// Key for text that comes from data (tab lists, slides, error copy, dropdown
/// options, messages built outside widgets). Lower-case, every run of
/// non [a-z0-9] -> '_', trimmed, max 60 chars, prefixed 'txt_'.
/// tools/i18n uses the identical rule to build the locale entries.
String i18nTextKey(String english) {
  var k = english.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  k = k.replaceAll(RegExp(r'^_+|_+$'), '');
  if (k.length > 60) k = k.substring(0, 60);
  return 'txt_$k';
}

extension TrContext on BuildContext {
  /// Translate [key]; show [fallback] (English) if missing or lang is English.
  /// Watches the provider so the widget rebuilds when the language changes.
  String tr(WidgetRef ref, String key, String fallback) {
    ref.watch(translationProvider); // rebuild on language switch
    return ref.read(translationProvider.notifier).tr(key, fallback);
  }

  /// Translate text that comes from data, keyed by the English text itself.
  /// Unknown or already-translated text is returned unchanged.
  String trText(WidgetRef ref, String english) =>
      tr(ref, i18nTextKey(english), english);

  /// For plain functions that have a BuildContext but no WidgetRef (e.g. a
  /// top-level showDialog helper). One-shot read, no rebuild subscription.
  String trCtx(String key, String fallback) =>
      ProviderScope.containerOf(this, listen: false)
          .read(translationProvider.notifier)
          .tr(key, fallback);

  /// trCtx() with {placeholder} substitution.
  String trpCtx(String key, String fallback, Map<String, String> vars) {
    var s = trCtx(key, fallback);
    vars.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  /// Same as tr() but substitutes {name} placeholders from [vars].
  String trp(WidgetRef ref, String key, String fallback,
      Map<String, String> vars) {
    var s = tr(ref, key, fallback);
    vars.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }
}

/// One-shot translation for callbacks (onPressed, dialogs, snackbars), async
/// code and initState. Reads the current language without subscribing, and
/// never touches BuildContext, so it is safe after an `await`.
extension TrRef on WidgetRef {
  String trNow(String key, String fallback) =>
      read(translationProvider.notifier).tr(key, fallback);

  /// trText() without subscribing (callbacks / async code).
  String trTextNow(String english) => trNow(i18nTextKey(english), english);

  /// trNow() with {placeholder} substitution.
  String trpNow(String key, String fallback, Map<String, String> vars) {
    var s = trNow(key, fallback);
    vars.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }
}
