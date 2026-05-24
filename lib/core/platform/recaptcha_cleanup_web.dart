// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Oculta visualmente los artefactos de reCAPTCHA tras resolver el challenge,
/// de modo que no bloqueen pointer-events sobre el canvas de Flutter.
///
/// **Importante: oculta, no elimina.** El script de Google reCAPTCHA tiene
/// callbacks diferidos (setTimeout) que se ejecutan DESPUÉS de que Firebase
/// dispara `codeSent`. Esos callbacks acceden a `element.style` sobre los
/// elementos del challenge — si los hubiéramos removido del DOM, el acceso
/// devolvería null y lanzaría `TypeError: Cannot read properties of null
/// (reading 'style')`, lo que pausa el debugger en DevTools y aparenta un
/// freeze de la app.
///
/// Aplicar `display:none` + `pointer-events:none` los saca de la pila visual
/// y de hit-testing, pero permite que reCAPTCHA siga accediendo a sus
/// propiedades sin crashear.
void clearRecaptchaWidgets() {
  try {
    const selectors = [
      '[id^="recaptcha"]',
      'iframe[src*="recaptcha"]',
    ];
    for (final sel in selectors) {
      for (final el in html.document.querySelectorAll(sel)) {
        if (el is html.HtmlElement) {
          el.style.display = 'none';
          el.style.pointerEvents = 'none';
        }
      }
    }

    // Backdrop del challenge: div con z-index gigante (>999999) que Google
    // inyecta como hijo directo de <body>. Mismo tratamiento: ocultar sin
    // eliminar para no romper los setTimeout internos de reCAPTCHA.
    final body = html.document.body;
    if (body != null) {
      for (final child in List<html.Element>.from(body.children)) {
        if (child is! html.HtmlElement) continue;
        final rawZi =
            child.getComputedStyle().getPropertyValue('z-index');
        final zi = int.tryParse(rawZi.trim()) ?? 0;
        if (zi > 999999) {
          child.style.display = 'none';
          child.style.pointerEvents = 'none';
        }
      }
    }
  } catch (_) {}
}
