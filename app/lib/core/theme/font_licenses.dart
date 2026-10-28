import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _fontLicensesRegistered = false;

/// Registers local asset fonts (Fredoka & Nunito) under SIL Open Font License 1.1
/// with Flutter's [LicenseRegistry] so they appear in [showLicensePage].
void registerFontLicenses() {
  if (_fontLicensesRegistered) return;
  _fontLicensesRegistered = true;

  LicenseRegistry.addLicense(() async* {
    try {
      final oflText = await rootBundle.loadString('assets/fonts/OFL.txt');
      yield LicenseEntryWithLineBreaks(['Fredoka'], oflText);
    } catch (_) {
      yield const LicenseEntryWithLineBreaks(
        ['Fredoka'],
        'SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007\n'
        'Copyright (c) 2016 The Fredoka Project Authors.\n'
        'Licensed under the SIL Open Font License, Version 1.1.',
      );
    }

    yield const LicenseEntryWithLineBreaks(
      ['Nunito'],
      'SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007\n'
      'Copyright (c) 2014, Vernon Adams (vern@newtypography.co.uk).\n'
      'Licensed under the SIL Open Font License, Version 1.1 (http://scripts.sil.org/OFL).',
    );
  });
}

