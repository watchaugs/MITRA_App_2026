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

extension TrContext on BuildContext {
  /// Translate [key]; show [fallback] (English) if missing or lang is English.
  /// Watches the provider so the widget rebuilds when the language changes.
  String tr(WidgetRef ref, String key, String fallback) {
    ref.watch(translationProvider); // rebuild on language switch
    return ref.read(translationProvider.notifier).tr(key, fallback);
  }

  /// Same as tr() but substitutes {name} placeholders from [vars].
  String trp(WidgetRef ref, String key, String fallback,
      Map<String, String> vars) {
    var s = tr(ref, key, fallback);
    vars.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }
}
