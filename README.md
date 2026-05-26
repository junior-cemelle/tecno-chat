# TecNM Chat

Clon de WhatsApp orientado a la comunidad académica del Tecnológico Nacional de
México campus Celaya. La aplicación integra mensajería en tiempo real,
llamadas de voz/video, sistema de stories, consumo de datos académicos del
backend institucional (SII) y un módulo de asesorías entre alumnos.

Diseñada como aplicación principalmente **web**, con soporte funcional para
Android/iOS donde aplica.

---

## Capturas de pantalla

Las capturas viven en `docs/screenshots/<N>.png`, una por bloque funcional.

| #  | Bloque                            | Pantalla representativa             |
|----|-----------------------------------|--------------------------------------|
| 1  | Login y onboarding                | Login con tabs alumno/profesor       |
| 2  | Chats privados                    | Detalle de chat 1-a-1                |
| 3  | Grupos                            | Detalle de grupo                     |
| 4  | Chats de asesoría                 | Detalle con banner descriptivo       |
| 5  | Llamadas                          | Llamada activa (voz o video)         |
| 6  | Perfil                            | Perfil propio                        |
| 7  | Integración SII                   | Inicio académico (dashboard)         |
| 8  | Asesorías                         | Mis asesorías (asesor) o dashboard del gerente |
| 9  | Stories                           | Crear story                          |
| 10 | Sidebar / shell                   | Sidebar web                          |

---

## Stack tecnológico

### Framework y lenguaje
- **Flutter 3.38.x** (canal stable) — UI cross-platform
- **Dart 3.10.x**

### Estado y navegación
- **Riverpod 3.x** (`flutter_riverpod`) — providers reactivos para auth,
  Firestore streams, datos del SII y asesorías
- **go_router** — `StatefulShellRoute.indexedStack` para tabs persistentes
  (Chats, Grupos, Asesorías, Llamadas, Perfil + SII para alumnos)

### Backend (Firebase)
- **Firebase Authentication** — Email/Password, Phone OTP, Google OAuth,
  vinculación de proveedores post-registro
- **Cloud Firestore** — persistencia de usuarios, chats, mensajes, grupos,
  asesorías, solicitudes y llamadas; security rules basadas en rol
- **Firebase Hosting** — distribución del build web

### Servicios externos
- **Supabase Storage** — almacenamiento de avatares, media de chat
  (imágenes/videos/audio/GIFs) y CVs en PDF de las asesorías
- **Agora RTC Engine 6.5.x** — llamadas de voz y video con SDK web vía
  `iris-web-rtc`
- **Cloudflare Worker** — proxy CORS hacia el backend del SII
  (`https://sii.celaya.tecnm.mx/api/`) para sortear la falta de headers
  CORS desde el navegador
- **SII (TecNM Celaya)** — fuente única de verdad para datos académicos
  de alumnos (kárdex, calificaciones, horarios, perfil)

### Bibliotecas Flutter relevantes
| Paquete                | Uso                                              |
|------------------------|--------------------------------------------------|
| `cloud_firestore`      | Acceso a Firestore                               |
| `firebase_auth`        | Autenticación                                    |
| `supabase_flutter`     | Cliente Supabase Storage                         |
| `agora_rtc_engine`     | Llamadas WebRTC                                  |
| `google_sign_in`       | OAuth Google                                     |
| `image_picker`         | Selección de fotos/videos (móvil)                |
| `file_picker`          | Selección de PDF (CV de asesoría)                |
| `record` / `audioplayers` | Grabación y reproducción de audio (mensajes) |
| `permission_handler`   | Permisos CAMERA/MIC en mobile                    |
| `shared_preferences`   | Persistencia del JWT del SII                     |
| `flutter_svg`          | Iconos vectoriales (Google logo, etc.)           |
| `google_fonts`         | Tipografía Poppins                               |
| `intl`                 | Formato de fechas localizadas                    |

---

## Funcionalidades

### Autenticación
Captura: [1](docs/screenshots/1.png).

- **Alumnos**: login con credenciales del SII. La primera vez crea
  automáticamente la cuenta Firebase con la misma contraseña y persiste un
  perfil parcial (nombre, número de control, foto institucional, semestre).
  Los datos académicos no se duplican en Firestore — se consumen on-demand
  con el JWT del SII.
- **Profesores**: registro y login con email/contraseña directamente en
  Firebase (no pasan por el SII).
- **Teléfono / Google**: solo para login posterior. Se vinculan desde
  *Perfil → Cuentas vinculadas* tras haber registrado el correo.
- **Botón dev** (`Crear / entrar con cuenta dev` en la pantalla de login):
  permite crear o reingresar a cuentas de alumno dummy sin validar SII —
  pensado para pruebas y presentación. **Debe ocultarse en producción**
  envolviendo el bloque en `if (kDebugMode) ...[` (ver
  `lib/presentation/auth/login_screen.dart`).

### Chats privados
Captura: [2](docs/screenshots/2.png).

- Chats 1-a-1 con texto, imágenes, videos, audios (Opus en web/AAC en mobile),
  GIFs y emojis con picker integrado
- Lista con scroll-to-bottom, marca de leído, último mensaje y formato
  relativo de tiempo
- Layout **split view** en web: lista de conversaciones + panel de detalle
  lado a lado (similar a WhatsApp Web)

### Grupos
Captura: [3](docs/screenshots/3.png).

- Solo profesores pueden crearlos; cualquier usuario puede ser miembro
- Avatar de grupo, nombre, descripción y administración de miembros
- Mismo motor de mensajería que los chats privados (texto + media +
  reproducción inline)

### Chats de asesoría
Captura: [4](docs/screenshots/4.png).

- Sección independiente en el sidebar — no se mezcla con chats ni grupos
- Badge identificativo en lista y appbar; banner persistente con la
  materia, semestre objetivo y capacidad
- Se crean perezosamente cuando el asesor acepta a su primer alumno (ver
  bloque de Asesorías)

### Llamadas (Agora)
Captura: [5](docs/screenshots/5.png).

- Voz y video, soporte WebRTC en navegador y nativo en móvil
- Pantalla de llamada entrante con aceptar/rechazar
- Mute/cámara toggle, indicador de conectado
- Solo aplican a chats privados — grupos y asesorías no las exponen

### Stories / Avisos institucionales
Captura: [9](docs/screenshots/9.png).

- Solo profesores pueden publicar stories
- Cualquier alumno las ve y se marca como visto al abrirlas

### Integración con el SII
Captura: [7](docs/screenshots/7.png).

Accesible desde el sidebar para alumnos. Cuatro vistas:
- **Inicio académico** — dashboard con anillo de avance, promedios
  (ponderado/aritmético), distribución de materias y métricas de créditos
- **Calificaciones** — selector de periodo + cards por materia con cada
  parcial coloreado según rango (rojo <60, naranja 60-69, verde 70+)
- **Kárdex** — historial agrupado por semestre con ExpansionTile, mini
  barras apiladas aprobadas/reprobadas y badge de promedio
- **Horarios** — grid semanal (días × horas) con bloques posicionados
  absolutamente; cada materia recibe color estable

Manejo automático de sesión expirada con flujo de **reconexión**: si el
JWT muere, el usuario reingresa solo la contraseña sin cerrar sesión.

### Asesorías entre alumnos
Captura: [8](docs/screenshots/8.png).

Sistema completo de tutorías académicas:

**Roles:**
- **Asesor**: alumno de 4º semestre o superior que se postula
- **Consultante**: cualquier alumno que busca asesoría en una materia
- **Gerente de Asesorías**: profesor con flag `isAsesoriaManager: true`
  (se configura manualmente en Firestore Console)

**Flujo:**
1. Alumno postula como asesor con materia + motivos + CV PDF
2. Gerente revisa solicitud y aprueba fijando semestre objetivo y capacidad
3. Otros alumnos buscan asesorías por materia y envían solicitud
4. Asesor acepta/rechaza solicitudes. Al aceptar al primer alumno se crea
   el chat grupal de asesoría (creación perezosa)
5. Cuando se cumple el objetivo, el asesor marca la asesoría como
   completada
6. El gerente da el visto bueno → estado finalizado

**Reglas duras** (validadas server-side por las security rules y
client-side en `AsesoriaService`):
- Capacidad es fija total — los cupos consumidos no se liberan
- Un asesor solo puede tener una asesoría activa por materia
- Solo el asesor puede aceptar/rechazar solicitudes
- Solo el gerente puede aprobar/finalizar

### Perfil
Captura: [6](docs/screenshots/6.png).

- Edición de carrera, semestre, departamento (profesores), avatar
- Sección de cuentas vinculadas (vincular/desvincular teléfono y Google)
- QR personal compartible para que otros te agreguen
- Entradas contextuales a Asesorías según rol

### Layout y sidebar
Captura: [10](docs/screenshots/10.png).

- Sidebar colapsable estilo glassmorphism en web; bottom navigation en móvil
- Pestañas filtradas por rol: alumnos ven los 4 tabs SII adicionales;
  profesores solo Chats, Grupos, Asesorías, Llamadas y Perfil
- Separadores visuales agrupan las secciones (comunicación / académico /
  perfil)

---

## Estructura de pantallas

| Ruta                          | Pantalla                          | Acceso                          | Captura |
|-------------------------------|-----------------------------------|---------------------------------|---------|
| `/login`                      | Login con tabs alumno/profesor    | Pública                         | 1       |
| `/otp`                        | Verificación OTP                  | Pública (con verificationId)    | 1       |
| `/setup`                      | Setup de perfil post-registro     | Autenticado, sin perfil         | 1       |
| `/chats`                      | Lista de chats privados           | Autenticado                     | 2       |
| `/chats/:chatId`              | Detalle de chat                   | Participante                    | 2       |
| `/groups`                     | Lista de grupos                   | Autenticado                     | 3       |
| `/groups/:chatId`             | Detalle de grupo                  | Participante                    | 3       |
| `/asesoria-chats`             | Lista de chats de asesoría        | Participante en alguna          | 4       |
| `/asesoria-chats/:chatId`     | Detalle de chat de asesoría       | Participante                    | 4       |
| `/calls`                      | Historial de llamadas             | Autenticado                     | 5       |
| `/call`                       | Pantalla de llamada activa        | Llamada en curso                | 5       |
| `/incoming-call`              | Llamada entrante                  | Receptor                        | 5       |
| `/profile`                    | Perfil propio                     | Autenticado                     | 6       |
| `/profile/edit`               | Editar perfil                     | Dueño                           | 6       |
| `/sii/dashboard`              | Inicio académico                  | Alumno                          | 7       |
| `/sii/calificaciones`         | Calificaciones por periodo        | Alumno                          | 7       |
| `/sii/kardex`                 | Kárdex histórico                  | Alumno                          | 7       |
| `/sii/horarios`               | Horario semanal                   | Alumno                          | 7       |
| `/asesorias/apply`            | Postular como asesor              | Alumno ≥4º sem                  | 8       |
| `/asesorias/browse`           | Buscar asesorías                  | Alumno                          | 8       |
| `/asesorias/mine`             | Mis asesorías (asesor)            | Alumno                          | 8       |
| `/asesorias/manage`           | Dashboard del gerente             | Profesor con `isAsesoriaManager`| 8       |
| `/create-group`               | Crear grupo                       | Profesor                        | 3       |
| `/group-info/:chatId`         | Info/ajustes de grupo             | Miembro                         | 3       |
| `/create-story`               | Crear story                       | Profesor                        | 9       |

---

## Estructura del código

```
lib/
├── core/
│   ├── constants/         # AppAssets, paths
│   ├── platform/          # conditional imports web/mobile (camera, download, recaptcha)
│   ├── theme/             # colores y theming
│   └── widgets/           # widgets compartidos (AvatarWidget, etc.)
├── data/
│   ├── models/            # ChatModel, UserModel, AsesoriaModels, SiiModels, …
│   └── services/          # AuthService, SiiApiService, AsesoriaService, StorageService, …
├── presentation/
│   ├── auth/              # LoginScreen, OtpScreen, ProfileSetupScreen
│   ├── chats/             # ChatsScreen, ChatDetailScreen, ChatsSplitView
│   ├── groups/            # GroupsScreen, CreateGroupScreen, GroupInfoScreen
│   ├── asesorias/         # ApplyAdvisor, Browse, MyAsesorias, ManagerDashboard, …
│   ├── sii/               # SiiDashboard, SiiCalificaciones, SiiKardex, SiiHorarios
│   ├── calls/             # CallScreen, IncomingCallScreen, CallsScreen
│   ├── stories/           # CreateStoryScreen
│   ├── profile/           # ProfileScreen, EditProfileScreen
│   └── shell/             # MainShell (sidebar) y app_router
├── providers/             # providers Riverpod por dominio (auth, firestore, sii, asesoria, …)
└── main.dart              # entry point — inicializa Firebase, Supabase y SiiTokenStorage
```

---

## Configuración previa para correr el proyecto

### Cuentas/proyectos externos requeridos
1. **Proyecto Firebase** con Authentication (Email/Password, Phone, Google),
   Cloud Firestore y Hosting habilitados
2. **Proyecto Supabase** con un bucket público `chat-media`
3. **Proyecto Agora** (App ID público)
4. **Cuenta Cloudflare** con un Worker desplegado que reenvíe a
   `https://sii.celaya.tecnm.mx/api/` con headers CORS

### Configuración local

Clonar el repo y luego:

```bash
flutter pub get
```

#### Firebase
Generar la config de Firebase con FlutterFire CLI:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Esto crea `lib/firebase_options.dart` y registra los clientes web/Android/iOS
en tu proyecto. **No commitear** `firebase_options.dart` si el repo es
público — añadirlo a `.gitignore`.

#### Supabase
En `lib/main.dart` (o un archivo de constantes) están la URL y la anon key
del proyecto. Reemplazar por las propias.

#### Agora
En `web/index.html` se carga el SDK de iris-web-rtc. El App ID se inyecta
desde el código Dart. Buscar en el repo dónde está hardcodeado y reemplazar
por tu propio App ID.

#### Cloudflare Worker
El worker que proxea al SII está documentado en la sección "CORS Worker"
abajo. Su URL se configura en
`lib/data/services/sii_api_service.dart` en la constante `_webProxyOrigin`.

#### Firestore rules
Ver `firestore.rules` (o publicar manualmente desde la consola de Firebase).
Las reglas críticas son las de `users`, `chats`, `messages`, `asesorias`,
`asesoria_requests`, `calls` y `stories`. La rule de creación de `chats`
debe contemplar los tres tipos: `private`, `group` (solo profesores) y
`asesoria` (verificando que el creador sea el `advisorUid` del doc
vinculado).

---

## Ejecutar y construir

### Desarrollo local (web)

```bash
flutter run -d chrome
```

Si el puerto cambia entre ejecuciones, agrega a "Authorized JavaScript
origins" del cliente OAuth de Google para que Google Sign-In siga
funcionando.

### Build de producción web

```bash
flutter build web --release
```

El resultado queda en `build/web/`. Toma 1-3 min la primera vez,
incremental en builds posteriores.

### Tree-shaking del botón dev (post-presentación)

El botón "Crear / entrar con cuenta dev" en `/login` está temporalmente
visible en cualquier build. Para excluirlo del bundle de producción:

1. En `lib/presentation/auth/login_screen.dart`, restaurar el import:
   ```dart
   import 'package:flutter/foundation.dart' show kDebugMode;
   ```
2. Envolver el bloque del botón en `if (kDebugMode) ...[` (busca el
   comentario `// ── Botón DEV ───`)

Tras ese cambio, `flutter build web --release` recortará el botón y todo
su árbol del bundle.

---

## CORS Worker para el SII

El backend del SII no envía headers CORS, lo que bloquea las requests
desde el navegador. La aplicación enruta sus llamadas a través de un
Cloudflare Worker propio.

Código del worker (deploy via dashboard de Cloudflare → Workers & Pages →
Create application → Hello World):

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url);
    const target = `https://sii.celaya.tecnm.mx/api${url.pathname}${url.search}`;

    const upstream = await fetch(target, {
      method: request.method,
      headers: request.headers,
      body: ['GET', 'HEAD'].includes(request.method)
        ? null
        : await request.arrayBuffer(),
    });

    const res = new Response(upstream.body, upstream);
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    return res;
  },
};
```

Su URL se configura en
`lib/data/services/sii_api_service.dart` → `_webProxyOrigin`.

Free tier de Cloudflare: 100k requests/día, suficiente para uso académico.

---

## Despliegue a Firebase Hosting

### Setup inicial (una vez)

```bash
npm install -g firebase-tools
firebase login
firebase init hosting
```

Cuando pregunte:
- Public directory: `build/web`
- Configure as a single-page app: **YES** (crítico para go_router)
- Set up automatic builds with GitHub: a discreción

El archivo `firebase.json` debe quedar así:

```json
{
  "hosting": {
    "public": "build/web",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [
      { "source": "**", "destination": "/index.html" }
    ]
  }
}
```

### Publicar / re-publicar la web actualizada

Cada vez que hagas un cambio al código y quieras subirlo:

```bash
flutter build web --release
firebase deploy --only hosting
```

Salida típica:
```
Hosting URL: https://<tu-proyecto>.web.app
```

Tarda ~30-60s después del primer build.

### Configuraciones a verificar en Firebase Console post-deploy

| Sección                                  | Qué revisar                                      |
|------------------------------------------|--------------------------------------------------|
| Authentication → Settings → Authorized domains | Añadir `<proyecto>.web.app` y `<proyecto>.firebaseapp.com` |
| Authentication → Sign-in method          | Email/Password, Phone y Google habilitados       |
| Phone Auth → reCAPTCHA                   | Dominios autorizados incluyen el dominio público |
| Firestore → Rules                        | Las reglas en producción son las actuales        |
| Cloud Functions                          | No aplica (no se usan en este proyecto)          |

### Supabase Storage post-deploy

- Bucket `chat-media` debe tener policies que permitan lectura pública para
  que los avatares y PDFs sean accesibles desde el dominio nuevo
- Verificar que no haya restricción por Origin en Storage → Settings

### Cloudflare Worker post-deploy

- El worker tiene CORS abierto (`*`), funciona desde cualquier dominio
- Para producción real, considerar restringir el `Access-Control-Allow-Origin`
  al dominio público de Firebase Hosting

---

## Pruebas mínimas tras un despliegue (smoke test)

1. Login con email/password (alumno SII real) — confirma que el proxy
   Cloudflare responde y el JWT se guarda
2. Login por teléfono — verifica reCAPTCHA + SMS
3. Crear cuenta dev → entrar
4. Enviar un mensaje de texto y una imagen
5. Llamada de voz entre dos cuentas — confirma WebRTC y Agora
6. Subir avatar desde *Editar perfil* — verifica Supabase upload
7. Como alumno ≥4º sem: postular como asesor con PDF — verifica upload de
   CV y creación del doc
8. Como gerente: aprobar la asesoría
9. Como otro alumno: buscar la asesoría y solicitar
10. Como asesor: aceptar al solicitante — verifica creación perezosa del
    chat de asesoría y que aparezca en el tab correspondiente

Si algo falla, abrir DevTools → Console: los errores de CORS, permisos
Firestore o auth se diagnostican rápidamente desde ahí.

---

## Notas operacionales

### Promover a un profesor como Gerente de Asesorías
Manualmente desde Firestore Console:
1. Ir a `users/{uid del profesor}`
2. Añadir campo `isAsesoriaManager: true` (booleano)
3. El profesor verá la sección "Gestión de asesorías" en su perfil tras
   recargar la app

### Limpiar cuentas dev tras la presentación
1. Firebase Console → Authentication → eliminar el usuario
2. Firestore Console → `users/{uid}` → eliminar el doc
3. Si la cuenta tenía chats: eliminar también `chats/{chatIds}` y los
   `chats/{id}/messages/*`

### Limitaciones conocidas
- El proxy SII de Cloudflare pasa credenciales (email+password) por un
  tercero. Aceptable en demos académicas, no apto para producción real
  sin restricciones de origen
- Las llamadas Agora consumen del plan gratuito (limitado por minutos/mes)
- Los stories no expiran automáticamente — habría que añadir un job que
  borre los antiguos
