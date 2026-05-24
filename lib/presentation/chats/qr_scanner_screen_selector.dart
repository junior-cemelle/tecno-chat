// Selector condicional: mobile_scanner en nativo, stub en web.
export 'qr_scanner_screen.dart'
    if (dart.library.html) 'qr_scanner_screen_web.dart';
