// Selector: usa la implementación nativa en mobile, stub vacío en web.
export 'media_kit_init_mobile.dart'
    if (dart.library.html) 'media_kit_init_stub.dart';
