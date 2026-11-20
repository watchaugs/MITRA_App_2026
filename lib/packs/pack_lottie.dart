// Built-in animation, unless a content pack replaces it (splash, confetti,
// waving hands, AR globe). A downloaded animation that can't be read falls
// back to the built-in one, so the screen never goes blank.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';

import 'pack_store.dart';

Widget packLottie(
  String asset, {
  Animation<double>? controller,
  bool? repeat,
  double? width,
  double? height,
  BoxFit? fit,
  ImageErrorWidgetBuilder? errorBuilder,
  void Function(LottieComposition)? onLoaded,
  LottieDecoder? decoder,
}) {
  Widget builtIn() => Lottie.asset(
        asset,
        controller: controller,
        repeat: repeat,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: errorBuilder,
        onLoaded: onLoaded,
        decoder: decoder,
      );
  final path = PackStore.instance.lottiePath(asset);
  if (path == null) return builtIn();
  return Lottie.file(
    File(path), // plain Lottie JSON from the pack
    controller: controller,
    repeat: repeat,
    width: width,
    height: height,
    fit: fit,
    onLoaded: onLoaded,
    errorBuilder: (context, error, stack) => builtIn(),
  );
}
