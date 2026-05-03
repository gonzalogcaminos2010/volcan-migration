<!--
SYNC IMPACT REPORT
==================
Version change: 0.0.0 (unfilled template) → 1.0.0
Bump rationale: MAJOR — first ratified constitution; all placeholder tokens replaced
with concrete, project-specific governance for Volcán Migration.

Modified principles (template slot → concrete principle):
- [PRINCIPLE_1_NAME] → I. Identidad y propósito
- [PRINCIPLE_2_NAME] → II. Licencia y modelo
- [PRINCIPLE_3_NAME] → III. Compatibilidad y stack
- [PRINCIPLE_4_NAME] → IV. Compliance WP.org (no negociable)
- [PRINCIPLE_5_NAME] → V. Seguridad (no negociable)

Added sections (beyond the 5-principle template):
- VI. Calidad de código
- VII. Internacionalización
- VIII. Privacidad y datos del usuario
- IX. Workflow de desarrollo
- X. Lo que el plugin NO hace (scope discipline)
- XI. Definición de "listo" (Definition of Done)
- Governance (formal amendment / versioning / compliance review)

Removed sections:
- Generic [SECTION_2_NAME] / [SECTION_3_NAME] placeholders (superseded by VI–XI).

Templates / artifacts requiring updates:
- ✅ .specify/templates/plan-template.md — "Constitution Check" gate references the
  constitution dynamically; no static edits required (per-feature gates derived at
  /speckit-plan time).
- ✅ .specify/templates/spec-template.md — generic, no constitution-coupled tokens.
- ✅ .specify/templates/tasks-template.md — generic; DoD from §XI applied per task at
  /speckit-tasks time.
- ✅ .claude/skills/speckit-*/SKILL.md — agent-neutral; no edits required.
- ⚠ README.md — currently a stub ("# volcan-migration"); recommended follow-up to
  describe the plugin per §I (not in scope of this constitution change).
- ⚠ CLAUDE.md — currently points to "the current plan" which does not exist yet;
  will be populated by the /speckit-plan workflow per §IX.

Follow-up TODOs:
- None. Ratification date set to 2026-05-03 (project inception).
-->

# Volcán Migration Constitution

> Este documento es la autoridad suprema del proyecto. Cualquier decisión en spec,
> plan, tasks o implementación debe respetar estas reglas. Si hay conflicto, gana la
> constitución. Solo se modifica con commit explícito y revisión.

## I. Identidad y propósito

- **Nombre público**: Volcán Migration
- **Slug WP.org**: `volcan-migration`
- **Text domain**: `volcan-migration`
- **Namespace PHP**: `VolcanMigration\`
- **Prefijo de funciones globales / hooks / opciones**: `volcanmig_`
- **Propósito**: Plugin libre y gratuito de WordPress que clona sitios completos
  (base de datos + archivos) usando Google Drive como almacenamiento. Alternativa
  libre a "All-in-One WP Migration" sin límites de tamaño y con Drive nativo.
- **Audiencia**: Administradores de WordPress, freelancers y agencias que necesitan
  migrar/respaldar sitios sin pagar extensiones premium.

## II. Licencia y modelo

- **Licencia del código**: GPLv2 o posterior (compatible WP.org).
- **Licencia de assets gráficos** (logo, banner, screenshots): GPLv2 o CC BY-SA 4.0.
- **Modelo**: 100% libre y gratuito, sin tier paid, sin upsells, sin licencias
  externas, sin telemetría.
- **Sin "phone home"**: el plugin NUNCA contacta servidores que no sean (a) Google
  Drive API y (b) WordPress.org para updates oficiales. Ningún tracking, analytics,
  ni servidor propio.

## III. Compatibilidad y stack

- **PHP mínimo**: 7.4. Probado hasta 8.3.
- **WordPress mínimo**: 6.0. Probado hasta la última estable al momento de cada
  release.
- **MySQL/MariaDB**: mínimo MySQL 5.7 / MariaDB 10.3.
- **Multisite**: soporte explícito desde el día uno, no se posterga.
- **Sin Composer en runtime**. Las dependencias se commitean al repo SVN ya scoped
  con PHP-Scoper bajo `VolcanMigration\Vendor\`.
- **Stack de dependencias**: mínimo viable. La única dependencia externa
  significativa es `google/apiclient`. Cualquier otra requiere justificación en el
  plan de la feature que la introduce.

## IV. Compliance WP.org (no negociable)

Estas reglas son las del WordPress Plugin Directory. Violarlas implica rechazo
automático y bloquea cualquier release.

- **GPL completo**. Todo código y asset MUST ser compatible GPL. Sin código
  propietario embebido.
- **No phone home sin opt-in**. Cualquier llamada externa MUST requerir
  consentimiento explícito del usuario.
- **Sin dependencias en runtime de Composer**. El usuario instala desde el
  dashboard, no corre comandos.
- **Sin conflictos de namespace**. Todas las dependencias MUST estar scoped con
  PHP-Scoper.
- **Plugin Check** MUST pasar sin warnings antes de cada release.
- **`readme.txt`** en formato WP.org (no Markdown), validado con Readme Validator.
- **Nombre del plugin** MUST NOT empezar con "WP", "WordPress", ni con marcas
  ajenas.
- **2FA habilitado** en la cuenta WP.org del autor (requisito desde 2024).
- **Sin minificación ni ofuscación** del código fuente distribuido.
- **Sin frameworks/librerías genéricas** que dupliquen funcionalidad de WP core.

## V. Seguridad (no negociable)

- **Capability check**: toda acción admin MUST requerir `manage_options` (o
  `manage_network_options` en multisite).
- **Nonces**: toda action AJAX, form submission y URL de acción MUST llevar nonce
  verificado.
- **Sanitización al input**: `sanitize_text_field`, `esc_url_raw`, `absint`, etc.
  Sin excepciones.
- **Escapado al output**: `esc_html`, `esc_attr`, `esc_url`, `wp_kses`. Sin
  excepciones.
- **Prepared statements**: toda query MUST usar `$wpdb->prepare()`. Cero
  concatenación SQL.
- **Validación de paths**: rechazar `../`, paths absolutos y symlinks fuera del
  directorio esperado en extracción de archivos (anti zip-slip).
- **Tokens OAuth cifrados** en `wp_options` usando una clave derivada de
  `AUTH_KEY` y `SECURE_AUTH_KEY`.
- **Logs sin secretos**: NUNCA loggear tokens, passwords, ni datos de DB sensibles.
- **`defined('ABSPATH') || exit;`** al inicio de cada archivo PHP.
- **Backup automático de la DB** antes de cualquier import. No negociable.

## VI. Calidad de código

- **WordPress Coding Standards** (PHPCS con `WordPress` ruleset) en CI.
- **PHPStan nivel 5** mínimo en CI.
- **PSR-4** para autoloading interno (sin chocar con la prohibición de Composer en
  runtime: el autoloader es propio).
- **Sin `error_log()`** en producción. Todo va al logger del plugin.
- **Sin `var_dump`, `print_r`, `die()`** debug en código mergeado.
- Comentarios en inglés. Strings de UI traducibles vía `__()` con text domain.
- **Tests unitarios** para clases críticas: `Database`, `Archiver`, `UrlReplacer`,
  `ChunkedUploader`. Mínimo **70% coverage** en estas.
- **Tests de integración mínimos**: export → import en sitio chico.

## VII. Internacionalización

- **Idioma fuente**: inglés (`en_US`) para strings de código.
- **Idiomas prioritarios para traducción**: `es_AR` (Rioplatense), `es_ES`, `pt_BR`.
- **Text domain**: `volcan-migration` en todas las funciones de traducción.
- **`.pot` actualizado** en cada release.
- **Sin strings hardcodeados** en UI.

## VIII. Privacidad y datos del usuario

- El plugin **no recolecta ningún dato del usuario**, ni siquiera anónimo.
- La conexión con Google Drive usa **OAuth con cliente del usuario** (Client ID /
  Secret propios). El plugin nunca ve credenciales del autor.
- Los backups generados se guardan **localmente y/o en el Drive del usuario**.
  Nunca pasan por servidores de terceros.
- **Política de privacidad explícita** en el `readme.txt` declarando lo anterior.

## IX. Workflow de desarrollo

- **Spec-Driven Development** con github/spec-kit:
  `constitution → specify → plan → tasks → implement`.
- **Repo público en GitHub** desde el día uno (`build in public`).
- **Branch principal**: `main`. Features en branches `feature/NNN-slug` generadas
  por spec-kit.
- **Conventional Commits** para mensajes (`feat:`, `fix:`, `docs:`, `chore:`,
  etc.).
- **CI con GitHub Actions**:
  - PHPCS (WordPress standards)
  - PHPStan
  - Plugin Check (acción oficial)
  - PHPUnit (cuando haya tests)
- **Releases vía tag semver** en GitHub. Sync manual a SVN de WP.org tras review
  aprobado.
- Cambios a la constitución requieren PR explícito con título `constitution:` y
  revisión.

## X. Lo que el plugin NO hace (scope discipline)

- **No** hace backups incrementales (al menos en v1.x).
- **No** soporta otros providers de cloud (Dropbox, S3, etc.) en v1.x. Drive only.
- **No** es un sistema de staging ni de gestión multi-sitio centralizado.
- **No** tiene panel de control en la nube.
- **No** tiene addons paid.

## XI. Definición de "listo" (Definition of Done)

Una feature está terminada cuando:

- El código pasa **PHPCS, PHPStan y Plugin Check sin warnings**.
- Hay **tests** para la lógica crítica de la feature.
- **Strings nuevos** están en inglés y son traducibles.
- **Documentación** (`readme.txt`, `CHANGELOG.md` y wiki si aplica) actualizada.
- **Probado manualmente** en al menos un sitio real.
- **Sin secretos, sin debug, sin código muerto.**
- **PR revisado y mergeado** a `main`.

## Governance

- Esta constitución es la **autoridad suprema** del proyecto. Toda decisión en
  `spec.md`, `plan.md`, `tasks.md` o implementación MUST respetar estas reglas.
  Ante conflicto, gana la constitución.
- **Procedimiento de enmienda**: cualquier cambio MUST presentarse en un Pull
  Request con título prefijado `constitution:`, descripción de la motivación, y
  review aprobado antes de mergear a `main`.
- **Política de versionado** (SemVer aplicado a la constitución):
  - **MAJOR**: cambios incompatibles que eliminan o redefinen principios
    existentes (ej. quitar la cláusula "no phone home").
  - **MINOR**: nueva sección o ampliación material de un principio existente.
  - **PATCH**: aclaraciones, correcciones de redacción, refinamientos no
    semánticos.
- **Revisión de cumplimiento**: todo PR de feature MUST verificar explícitamente
  compliance con esta constitución (especialmente §IV y §V, no negociables). El
  reviewer documenta el chequeo en la descripción del PR.
- **Justificación de complejidad**: cualquier desviación temporal de los
  principios MUST justificarse en `plan.md` bajo "Complexity Tracking" con la
  alternativa simple rechazada y la razón.
- **Guía de runtime**: `CLAUDE.md` y los planes de feature aportan guía operativa,
  pero NO pueden contradecir esta constitución.

**Version**: 1.0.0 | **Ratified**: 2026-05-03 | **Last Amended**: 2026-05-03
