# Feature Specification: Volcán Migration v1.0 — Full-Site Migration vía Google Drive

**Feature Branch**: `001-full-site-migration`
**Created**: 2026-05-03
**Status**: Draft
**Input**: User description: "Volcán Migration es un plugin libre y gratuito de WordPress que permite migrar, clonar y respaldar un sitio WordPress completo (base de datos + archivos) usando Google Drive como almacenamiento de los backups. Es una alternativa libre al popular plugin 'All-in-One WP Migration' para usuarios que quieren usar su propio Google Drive como destino sin pagar la extensión premium y sin límites de tamaño de archivo."

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Configurar el plugin (Priority: P1)

Como administrador del sitio, quiero acceder a una pantalla de configuración del plugin desde el dashboard de WordPress donde pueda cargar mis credenciales de Google Cloud (Client ID y Secret), ver el estado de la conexión con Drive, conectar o desconectar la cuenta, y consultar el espacio disponible en mi Drive.

**Why this priority**: Es la puerta de entrada de cualquier flujo del plugin. Sin un lugar para introducir credenciales y verificar estado, ninguna otra historia puede ejecutarse. Define la primera experiencia del usuario y el punto único donde se concentran las acciones administrativas críticas.

**Independent Test**: Activar el plugin en una instalación limpia, navegar a su pantalla de configuración, completar Client ID y Secret de Google Cloud, ver que el plugin reconoce las credenciales como válidas y muestra el botón "Conectar Drive" habilitado.

**Acceptance Scenarios**:

1. **Given** el plugin recién activado y sin credenciales cargadas, **When** el administrador entra a la pantalla de configuración, **Then** ve los campos vacíos para Client ID y Secret, el estado de conexión "No conectado" y el botón de conectar deshabilitado.
2. **Given** credenciales válidas guardadas pero sin OAuth completado, **When** el administrador entra a la pantalla, **Then** ve "No conectado" y el botón "Conectar Drive" habilitado.
3. **Given** Drive ya conectado, **When** el administrador entra a la pantalla, **Then** ve el correo de la cuenta conectada, el espacio disponible en Drive (usado/total) y un botón "Desconectar".
4. **Given** Drive conectado, **When** el administrador hace clic en "Desconectar", **Then** se revoca el acceso, los tokens almacenados se eliminan, y el estado vuelve a "No conectado".

---

### User Story 2 — Conectar Google Drive (Priority: P1)

Como administrador del sitio, quiero autorizar al plugin a usar mi propio Google Drive mediante un flujo de consentimiento estándar de Google, para que los backups se suban a mi Drive y nadie más tenga acceso a ellos. Quiero poder revocar la autorización en cualquier momento desde el plugin.

**Why this priority**: Sin Drive conectado, las historias de upload, listado e import desde Drive no funcionan. Es el primer flujo "vivo" del plugin con una dependencia externa.

**Independent Test**: Con credenciales válidas cargadas (US1), hacer clic en "Conectar Drive", completar el consentimiento de Google en la ventana del navegador, y volver al plugin para ver que la conexión quedó establecida y persiste tras recargar la página.

**Acceptance Scenarios**:

1. **Given** credenciales válidas cargadas y sin Drive conectado, **When** el administrador inicia el flujo de conexión, **Then** se redirige a la pantalla de consentimiento de Google.
2. **Given** el administrador completa el consentimiento, **When** Google redirige al sitio, **Then** el plugin almacena los tokens de manera segura y muestra el estado "Conectado a `<email>`".
3. **Given** Drive conectado, **When** el administrador hace clic en "Desconectar", **Then** los tokens se eliminan localmente y el plugin revoca el acceso en Google.
4. **Given** una sesión ya autorizada cuyo token expiró, **When** se ejecuta una operación que requiere Drive, **Then** el plugin renueva el token automáticamente sin pedir intervención del usuario.

---

### User Story 3 — Exportar el sitio completo (Priority: P1)

Como administrador, quiero generar un único archivo de migración que contenga toda la base de datos y los archivos relevantes del sitio (uploads, themes, plugins, mu-plugins) para poder migrarlo o respaldarlo. Quiero ver el progreso en tiempo real, opcionalmente excluir secciones (por ejemplo, omitir los uploads), y poder cancelar si el proceso se demora demasiado.

**Why this priority**: El export es la mitad del valor central del producto. Es funcional de forma independiente: produce un archivo descargable localmente aun cuando Drive no esté conectado.

**Independent Test**: Lanzar un export en un sitio de prueba con contenido conocido, ver el indicador de progreso avanzar, esperar a que termine y comprobar que se generó un archivo único válido que se puede descargar al disco local.

**Acceptance Scenarios**:

1. **Given** un sitio con base de datos y archivos en `wp-content`, **When** el administrador inicia un export con todas las opciones por defecto, **Then** se produce un archivo único que contiene la base de datos y los directorios `uploads`, `themes`, `plugins` y `mu-plugins` con su estructura preservada.
2. **Given** un export en curso, **When** el administrador revisa la pantalla, **Then** ve un indicador de progreso (porcentaje o pasos), el tamaño acumulado y el paso actual (DB, archivos, empaquetado).
3. **Given** un export en curso, **When** el administrador hace clic en "Cancelar", **Then** la operación se detiene en el siguiente punto seguro, los archivos temporales se borran, y se registra la cancelación en el log.
4. **Given** un sitio con uploads pesados, **When** el administrador desmarca "Incluir uploads" antes de exportar, **Then** el archivo resultante no contiene `wp-content/uploads`.
5. **Given** un sitio de hasta 5 GB en un hosting compartido típico (256 MB de memoria PHP, 300 s de `max_execution_time`), **When** se ejecuta un export, **Then** completa exitosamente sin agotar memoria ni timeout.

---

### User Story 4 — Subir el backup al Drive (Priority: P1)

Como administrador, quiero que el archivo de export se suba automáticamente a una carpeta dedicada al sitio dentro de mi Google Drive, sin que el tamaño del archivo me bloquee, incluso si pesa varios gigabytes. Quiero que la subida pueda reanudarse si la conexión se interrumpe brevemente.

**Why this priority**: Es lo que diferencia al plugin de cualquier otro export local. Sin upload a Drive el plugin sería sólo un exportador.

**Independent Test**: Generar un export pequeño (~50 MB) y comprobar que aparece en una carpeta dedicada del Drive del usuario. Repetir con un archivo grande (>2 GB) cortando la red durante la subida y verificar que reanuda en lugar de reiniciar.

**Acceptance Scenarios**:

1. **Given** Drive conectado y un export terminado, **When** se ejecuta la subida, **Then** el archivo aparece en una carpeta del Drive del usuario asociada al sitio actual, con su nombre y timestamp.
2. **Given** una subida en curso, **When** la conexión se interrumpe por hasta 30 segundos, **Then** la subida se reanuda automáticamente sin perder progreso al recuperarse la conexión.
3. **Given** una subida en curso, **When** el administrador la cancela, **Then** los fragmentos parciales se eliminan del Drive y la operación queda registrada como cancelada.
4. **Given** un archivo de varios gigabytes, **When** se ejecuta la subida, **Then** completa exitosamente sin requerir más memoria de la disponible en el hosting.
5. **Given** Drive sin espacio suficiente, **When** se intenta subir, **Then** el plugin detecta la situación antes de empezar y muestra un mensaje claro indicando cuánto espacio falta.

---

### User Story 5 — Listar y gestionar backups en Drive (Priority: P1)

Como administrador, quiero ver desde el plugin todos los backups que tengo guardados en el Drive del sitio, con su fecha y tamaño, y poder descargarlos al disco local, marcarlos para importarlos, o eliminarlos sin tener que abrir la web de Drive.

**Why this priority**: Sin esta vista, el usuario tiene que ir manualmente al Drive para gestionar archivos, rompiendo la promesa de "todo desde el dashboard de WordPress" del producto.

**Independent Test**: Con uno o más backups previos en el Drive del sitio, abrir la pestaña de backups y verificar que aparecen listados con fecha, tamaño y acciones disponibles.

**Acceptance Scenarios**:

1. **Given** Drive conectado y dos o más backups en la carpeta del sitio, **When** el administrador entra a la sección de backups, **Then** ve la lista con nombre, fecha y tamaño de cada uno, ordenada por fecha descendente.
2. **Given** un backup listado, **When** el administrador hace clic en "Descargar", **Then** se descarga el archivo al disco local.
3. **Given** un backup listado, **When** el administrador hace clic en "Eliminar" y confirma, **Then** el archivo se borra del Drive y desaparece de la lista.
4. **Given** un backup listado, **When** el administrador hace clic en "Importar", **Then** comienza el flujo de importación (US6) sobre ese archivo.
5. **Given** la carpeta del sitio en Drive vacía, **When** el administrador entra a la sección, **Then** ve un mensaje claro de "No hay backups todavía" en lugar de una lista en blanco.

---

### User Story 6 — Importar un backup desde Drive (Priority: P1)

Como administrador, quiero seleccionar un backup almacenado en mi Drive y restaurarlo sobre la instalación actual de WordPress (la misma del export o una distinta), con reemplazo automático de las URLs del sitio para que todo siga funcionando aunque el dominio o el subdirectorio cambien. Antes de modificar la base de datos, el plugin debe respaldarla automáticamente por las dudas.

**Why this priority**: Es la otra mitad del valor central. Sin import el plugin no clona ni migra nada.

**Independent Test**: Tomar un backup de un sitio A y restaurarlo en una instalación B con dominio distinto. Verificar que el sitio B queda funcional al primer login, con URLs actualizadas y enlaces internos correctos.

**Acceptance Scenarios**:

1. **Given** un backup listado en Drive, **When** el administrador inicia el import, **Then** el plugin primero genera y guarda un backup de seguridad de la base de datos actual.
2. **Given** el import en curso, **When** se reemplazan las URLs en la base de datos, **Then** los valores serializados (arrays/objetos PHP) se preservan sin corromperse.
3. **Given** un import donde origen y destino comparten URL, **When** termina la operación, **Then** el sitio queda funcional sin pasos manuales adicionales.
4. **Given** un import con cambio de dominio (`origen.com` → `destino.com`), **When** termina la operación, **Then** todas las referencias internas (incluyendo `siteurl`, `home`, contenido y options) apuntan al nuevo dominio.
5. **Given** un import con cambio de subdirectorio (`destino.com/old` → `destino.com/new`), **When** termina la operación, **Then** los enlaces internos resuelven correctamente al nuevo path.
6. **Given** un fallo durante el import (corte de red, error de DB), **When** ocurre el error, **Then** el plugin ofrece restaurar el backup de seguridad creado al inicio del proceso.

---

### User Story 7 — Importar un backup desde la PC (Priority: P2)

Como administrador, quiero alternativamente subir un archivo de backup directamente desde mi computadora al plugin (sin pasar por Drive), sin estar limitado por el `upload_max_filesize` del servidor.

**Why this priority**: Cubre el caso de quien recibe un backup por correo o mensajería y aún no lo subió a su Drive. Es comodidad, no flujo principal.

**Independent Test**: Tomar un archivo de backup ya generado, subirlo desde el navegador en la pantalla del plugin, y verificar que el plugin lo acepta y desencadena el flujo de import (US6) sobre él.

**Acceptance Scenarios**:

1. **Given** un archivo de backup en el disco local del administrador, **When** lo selecciona en la opción "Importar desde mi PC", **Then** el navegador comienza a subirlo al servidor del sitio en fragmentos sin error de "archivo demasiado grande".
2. **Given** una subida desde PC interrumpida, **When** se reanuda, **Then** continúa desde el último fragmento exitoso.
3. **Given** una subida desde PC completa, **When** termina, **Then** el flujo de import (US6) arranca automáticamente sobre ese archivo.
4. **Given** un archivo de backup con formato inválido, **When** termina la subida y empieza la validación, **Then** el plugin rechaza el import con un mensaje claro y elimina el archivo subido.

---

### User Story 8 — Funcionar en multisite (Priority: P2)

Como administrador de red, quiero que el plugin opere correctamente tanto en sitios individuales como en instalaciones multisite, respetando los permisos correspondientes a cada nivel.

**Why this priority**: Multisite es un compromiso constitucional desde v1.0 (§III). No es una historia con UI propia distinta sino una restricción sobre todas las anteriores.

**Independent Test**: Activar el plugin en una red multisite, ejecutar un export desde un subsitio como super-administrador y verificar que el archivo resultante contiene sólo los datos de ese subsitio (no toda la red).

**Acceptance Scenarios**:

1. **Given** una instalación single-site, **When** se accede al plugin, **Then** las acciones requieren la capability `manage_options`.
2. **Given** una instalación multisite, **When** se accede a las funciones de export/import desde un subsitio, **Then** las acciones requieren la capability `manage_network_options`.
3. **Given** un export desde un subsitio en multisite, **When** termina, **Then** el archivo contiene únicamente las tablas y archivos correspondientes a ese subsitio.
4. **Given** un import en un subsitio multisite con prefijo de tabla distinto al origen, **When** termina, **Then** el plugin ajusta los prefijos para que el subsitio destino quede funcional.

---

### User Story 9 — Ver logs de operaciones (Priority: P2)

Como administrador, quiero un log detallado de cada export e import (con timestamps, archivos procesados, errores) para diagnosticar problemas o validar que un backup terminó bien.

**Why this priority**: Crítico para soporte y diagnóstico, pero no bloquea la funcionalidad principal de migración.

**Independent Test**: Ejecutar un export y un import. Abrir la pestaña de logs y verificar que cada operación generó una entrada con su timeline detallado.

**Acceptance Scenarios**:

1. **Given** un export terminado, **When** se entra a la pestaña de logs, **Then** se ve una entrada con fecha de inicio, fecha de fin, archivos incluidos y resultado.
2. **Given** un import con un error a mitad del proceso, **When** se revisa el log, **Then** se ve el error con suficiente detalle para identificar la causa, sin exponer secretos (tokens, passwords).
3. **Given** logs acumulados de varias semanas, **When** el plugin detecta logs viejos, **Then** los rota o purga según la política configurada para no consumir espacio indefinidamente.
4. **Given** un log con varias entradas, **When** el administrador descarga los logs, **Then** obtiene un archivo de texto con todas las entradas en formato cronológico.

---

### Edge Cases

- ¿Qué pasa si el sitio destino tiene una versión mayor de WordPress incompatible con la del backup? El plugin advierte explícitamente y rechaza el import (la migración entre versiones mayores incompatibles está fuera de alcance, §X de la constitución).
- ¿Qué pasa si dos administradores inician operaciones simultáneas (export + import) sobre el mismo sitio? El plugin permite una única operación de migración a la vez por sitio; el segundo intento se rechaza con un mensaje claro.
- ¿Qué pasa si Drive devuelve un error temporal (5xx) durante upload o listado? El plugin reintenta con backoff exponencial; si los reintentos se agotan, el error se registra y se notifica al administrador.
- ¿Qué pasa si los tokens OAuth se invalidan unilateralmente desde la consola de Google? La próxima operación falla con un mensaje claro pidiendo reconectar.
- ¿Qué pasa si `wp-content/uploads` contiene un archivo cuyo path tras descomprimirse intentaría salir del directorio destino (zip-slip)? El extractor lo rechaza y aborta el import.
- ¿Qué pasa si la base de datos del backup contiene tablas con prefijo distinto al destino? El import ajusta los prefijos durante la restauración.
- ¿Qué pasa si el plugin se desactiva en mitad de un import? Al reactivarse, el plugin detecta el estado interrumpido y ofrece resumir desde el último checkpoint o restaurar el backup de seguridad.
- ¿Qué pasa si el administrador modifica las credenciales de Google Cloud después de haber conectado Drive? Los tokens existentes se invalidan y se le pide reconectar.

## Requirements *(mandatory)*

### Functional Requirements

**Configuración y conexión**

- **FR-001**: El plugin MUST exponer una pantalla de configuración accesible desde el menú de administración del dashboard.
- **FR-002**: El plugin MUST permitir guardar Client ID y Secret de Google Cloud provistos por el usuario.
- **FR-003**: El plugin MUST iniciar un flujo OAuth estándar contra Google que pida consentimiento explícito al usuario.
- **FR-004**: El plugin MUST persistir los tokens de acceso y refresco de manera cifrada de modo que un volcado de la base de datos por sí solo no permita reutilizarlos sin acceso al servidor.
- **FR-005**: El plugin MUST renovar tokens expirados de forma transparente sin interacción del usuario.
- **FR-006**: El plugin MUST permitir desconectar Drive, lo que elimina los tokens locales y revoca el acceso en Google.
- **FR-007**: El plugin MUST mostrar el estado de conexión, el correo de la cuenta conectada y el espacio total/disponible en Drive cuando esté conectado.

**Export**

- **FR-010**: El plugin MUST generar un archivo único de migración que contenga la base de datos y los directorios `uploads`, `themes`, `plugins` y `mu-plugins`.
- **FR-011**: El plugin MUST permitir excluir cualquiera de los directorios anteriores antes de iniciar el export.
- **FR-012**: El plugin MUST mostrar progreso en tiempo real (paso actual y porcentaje o tamaño acumulado) mientras se ejecuta el export.
- **FR-013**: El plugin MUST permitir cancelar un export en curso dejando el sitio en estado consistente y limpiando archivos temporales.
- **FR-014**: El plugin MUST trabajar por chunks de modo que un export de hasta 5 GB en hosting compartido típico (256 MB memoria PHP, 300 s `max_execution_time`) complete sin agotar recursos.
- **FR-015**: El plugin MUST excluir del export `wp-config.php` por defecto, por contener configuración específica del entorno y secretos.

**Upload a Drive**

- **FR-020**: El plugin MUST subir el archivo de export a una carpeta dedicada al sitio en el Drive del usuario.
- **FR-021**: El plugin MUST realizar la subida en modo reanudable, de manera que una desconexión transitoria de hasta 30 segundos no obligue a recomenzar.
- **FR-022**: El plugin MUST permitir cancelar una subida y, al cancelar, eliminar los fragmentos parciales del Drive.
- **FR-023**: El plugin MUST verificar antes de iniciar la subida que el espacio disponible en Drive sea suficiente, abortando con mensaje claro en caso contrario.
- **FR-024**: El plugin MUST mostrar progreso de la subida (porcentaje y velocidad efectiva).

**Listado y gestión en Drive**

- **FR-030**: El plugin MUST listar los backups almacenados en la carpeta de Drive del sitio actual con nombre, fecha y tamaño.
- **FR-031**: El plugin MUST permitir descargar al disco local, eliminar e iniciar import de cualquier backup listado.
- **FR-032**: El plugin MUST mostrar un mensaje claro cuando no haya backups en la carpeta del sitio.

**Import**

- **FR-040**: El plugin MUST generar un backup de seguridad de la base de datos actual antes de modificar nada durante un import.
- **FR-041**: El plugin MUST extraer los archivos del backup validando los paths para prevenir zip-slip y otras formas de escape de directorio.
- **FR-042**: El plugin MUST reemplazar las referencias de URL del sitio (incluyendo `siteurl`, `home` y referencias en contenido) preservando integridad de valores serializados (arrays y objetos PHP).
- **FR-043**: El plugin MUST manejar correctamente los tres escenarios canónicos de import: (a) misma URL, (b) cambio de dominio, (c) cambio de subdirectorio.
- **FR-044**: El plugin MUST ajustar los prefijos de tabla cuando origen y destino difieran.
- **FR-045**: El plugin MUST ofrecer la restauración del backup de seguridad si un import falla a mitad de proceso.
- **FR-046**: El plugin MUST permitir importar un backup subiéndolo directamente desde la PC del administrador, sin estar limitado por `upload_max_filesize`.
- **FR-047**: El plugin MUST validar el formato del archivo de backup antes de empezar la importación, rechazando archivos inválidos con mensaje claro.

**Multisite**

- **FR-050**: El plugin MUST funcionar en instalaciones single-site requiriendo capability `manage_options` para sus acciones administrativas.
- **FR-051**: El plugin MUST funcionar en instalaciones multisite requiriendo capability `manage_network_options` para sus acciones administrativas.
- **FR-052**: El plugin MUST permitir export/import a nivel de subsitio individual en multisite, sin afectar otros subsitios.

**Logs y observabilidad**

- **FR-060**: El plugin MUST registrar cada operación de export e import con timestamp de inicio, timestamp de fin, archivos procesados, resultado (éxito/error/cancelado) y detalle de errores cuando ocurran.
- **FR-061**: El plugin MUST garantizar que ningún log contenga secretos (tokens, passwords, datos sensibles de DB).
- **FR-062**: El plugin MUST exponer una vista de logs en el dashboard y permitir descargarlos en un archivo de texto.
- **FR-063**: El plugin MUST rotar o purgar logs antiguos según una política conservadora para evitar crecimiento ilimitado.

**Restricciones globales (heredadas de la constitución)**

- **FR-070**: El plugin MUST NOT realizar llamadas de red salvo a la API de Google Drive y a WordPress.org para actualizaciones oficiales.
- **FR-071**: El plugin MUST NOT recolectar telemetría ni datos del usuario, ni siquiera anónimos.
- **FR-072**: El plugin MUST permitir instalación y operación sin acceso a la línea de comandos del servidor.
- **FR-073**: El plugin MUST pasar el "Plugin Check" oficial de WordPress.org sin errores ni warnings.

### Key Entities

- **Sitio (Site)**: Una instalación de WordPress (single-site o un subsitio dentro de un multisite) sobre la cual operan export e import. Identifica la carpeta de backups en Drive.
- **Backup / Migration Archive**: Archivo único producido por un export que contiene la base de datos y un subconjunto seleccionable de los directorios `wp-content/{uploads,themes,plugins,mu-plugins}`. Tiene fecha de creación, tamaño, sitio de origen y, opcionalmente, comentario del administrador.
- **Conexión a Drive**: Vínculo OAuth entre el sitio y la cuenta de Drive del administrador. Tiene estado (conectada/desconectada), correo del titular, tokens cifrados y carpeta raíz dedicada al sitio.
- **Operación**: Una ejecución de export, upload, import, descarga o eliminación. Tiene tipo, estado (en curso, completada, cancelada, fallida), timestamps de inicio/fin, progreso y resultado.
- **Log Entry**: Registro estructurado asociado a una operación, con timestamp, nivel, mensaje y referencia a la operación correspondiente.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un administrador no técnico completa el flujo "instalar plugin → conectar Drive → exportar → ver backup en Drive" en menos de 15 minutos sin asistencia, partiendo de un sitio donde el plugin no estaba instalado.
- **SC-002**: El plugin completa exitosamente un export de un sitio de hasta 5 GB en un hosting compartido típico (256 MB memoria PHP, 300 s `max_execution_time`) en al menos 95 % de las corridas en un panel de hostings de prueba representativos.
- **SC-003**: Una subida a Drive sobrevive a una desconexión transitoria de hasta 30 segundos y reanuda automáticamente, en al menos 95 % de las pruebas con interrupción simulada.
- **SC-004**: Un import deja el sitio destino funcional al primer intento (sin pasos manuales) en los tres escenarios canónicos (misma URL, cambio de dominio, cambio de subdirectorio) en al menos 99 % de las pruebas con sitios de referencia.
- **SC-005**: El reemplazo de URLs no corrompe valores serializados en 100 % de los casos verificados con un set de fixtures que incluye arrays anidados, objetos PHP y URLs encadenadas.
- **SC-006**: La pantalla del plugin no realiza ninguna llamada de red a hosts distintos de los de Google y WordPress.org en 100 % de las verificaciones de auditoría de tráfico.
- **SC-007**: El plugin pasa el "Plugin Check" oficial de WordPress.org sin errores ni warnings en cada release.
- **SC-008**: Si el plugin se desactiva o se interrumpe a mitad de un import, el administrador puede restaurar el sitio al estado previo en menos de 5 minutos a partir del backup de seguridad automático.
- **SC-009**: Un administrador puede identificar la causa de un fallo de operación a partir de los logs en menos de 10 minutos en al menos 80 % de los escenarios de error simulados.
- **SC-010**: El plugin opera correctamente en al menos las dos versiones más recientes de WordPress y en PHP 7.4, 8.0, 8.1, 8.2 y 8.3 en la suite de tests de compatibilidad.

## Assumptions

- **Credenciales de Google Cloud**: El usuario crea su propio proyecto en Google Cloud Console y obtiene Client ID y Secret. El plugin no embebe credenciales del autor del plugin (alineado con §VIII de la constitución).
- **Alcance de OAuth**: El plugin solicita el alcance mínimo necesario para crear, listar y leer sólo los archivos producidos por el propio plugin en el Drive del usuario, sin pedir acceso al resto de su Drive.
- **Carpeta de Drive**: El plugin crea y mantiene una carpeta dedicada al sitio actual cuyo nombre se deriva del dominio o del nombre del sitio. Si el usuario la mueve manualmente desde la web de Drive, el plugin la vuelve a localizar por su identificador único.
- **Idiomas de la UI**: El idioma fuente del código y de los strings es inglés (`en_US`). Las traducciones prioritarias son `es_AR`, `es_ES` y `pt_BR` (§VII de la constitución).
- **Usuarios**: La audiencia primaria son administradores con permisos de `manage_options` (single-site) o `manage_network_options` (multisite). No hay rol de usuario "no administrador" para este plugin.
- **Concurrencia**: Sólo una operación de migración por sitio se ejecuta a la vez. Un segundo intento simultáneo se rechaza con mensaje claro.
- **Cancelación**: La cancelación se honra en el siguiente "punto seguro" (entre chunks) y nunca deja al sitio en estado inconsistente; los temporales se limpian.
- **Política de retención de logs**: Los logs antiguos se rotan o purgan después de un umbral conservador (por ejemplo, 90 días o 50 entradas, lo que ocurra primero) para no consumir espacio indefinidamente.
- **Versiones incompatibles**: La migración entre versiones mayores incompatibles de WordPress (por ejemplo, 4.x → 6.x) está explícitamente fuera de alcance (§X de la constitución); el plugin advierte y rechaza esos imports.
- **Encriptación de los backups**: Los backups en Drive no se cifran adicionalmente más allá del HTTPS de Drive y la propiedad privada del Drive del usuario (§X de la constitución; encriptación opcional queda para versiones posteriores).
- **Sin scheduler**: Backups programados / cron quedan fuera de v1.x (§X de la constitución).

## Out of Scope (v1.x)

- Backups incrementales.
- Otros providers de cloud (Dropbox, S3, OneDrive, etc.).
- Backups programados o ejecutados por cron.
- Sitios de staging o gestión multi-sitio centralizada.
- Cifrado adicional de los archivos de backup.
- Migración entre versiones mayores incompatibles de WordPress.
