# ROADMAP de LiveLift

Objetivo: que quien ya usa Phoenix LiveView pueda **mover partes de su interfaz al
cliente, a elección**, escribiendo lo mismo que ya sabe, y llegar por etapas a
capacidades parecidas a las de Hologram sin reescribir su aplicación.

Las duraciones son estimaciones gruesas para una sola persona y son muy inciertas.
Orden de magnitud hasta 1.0: 7 a 10 meses.

## Estado de ejecución

**Fase activa: 5, Funciones con la sintaxis de siempre. Próxima entrega:
temporizadores.** Las fases S, 0, 1, 2, 3 y 4 están cerradas. La fase 8 es
opcional y posterior a 1.0.

**Estados:** `Hecho` significa funcionalidad implementada, documentada y
probada en su alcance; `En curso` es la única entrega activa; `En espera`
depende de una entrega anterior; `Bloqueada` depende de cerrar otra fase.
Una funcionalidad hecha no cierra su fase: la puerta de aceptación requiere
verificar el conjunto completo. No se calcula un porcentaje a partir de checks.

| Orden | Entrega | Estado | Para cerrarla |
|---|---|---|---|
| 2.1 | Spikes, superficie nativa, plantillas, decimales, `case`, `cond`, `defp` y `\|>` | Hecho | Commits y pruebas descritos en fase 2 |
| 2.2 | `Enum.find`, `reduce`, `sort_by`, `count`, `join`, `flat_map`, `with_index` | Hecho | Paridad y rechazos por operación |
| 2.3a | `String.downcase` y `String.split` | Hecho | Paridad Unicode, demo y límites documentados |
| 2.3b | `String.replace` | Hecho | Semántica, paridad, rechazos, demo y benchmarks |
| 2.4a | Proyecciones `Map.keys` y `Map.values` | Hecho | Conteo y nombres ordenados con paridad; rechazos con ubicación |
| 2.4b | Operaciones `List` | Hecho | Edición por índice y borrado exacto con paridad |
| 2.5 | IR y normalización del compilador | Hecho | Pipes y condicionales normalizados, tipos de prueba y paridad |
| 2.6 | Regresión integral y puerta 2 | Hecho | Tres casos, paridad, tres navegadores, benchmarks |
| 3.1 | Orden de acciones e idempotencia del servidor | Hecho | Duplicados y entrega fuera de orden sin perder acciones |
| 3.2 | Reconexión y conflictos | Hecho | Reintentos y política de conflictos con límites |
| 3.3 | Pruebas caóticas y puerta 3 | Hecho | Convergencia y acciones aplicadas exactamente una vez |
| 4.1 | Medición nativa y render por dependencias | Hecho | Línea base de Chromium y trabajo de DOM medido |
| 4.2 | Diff con clave y agrupación de renders | Hecho | Foco, identidad y presupuesto de un frame |
| 4.3 | Carga por isla y puerta 4 | Hecho | Assets y presupuesto total verificados |
| 5.1 | Temporizadores | **En curso** | API nativa, ciclo de vida y paridad |
| 5.2 | Validación con Ecto.Changeset | En espera | Formularios y errores equivalentes |
| 5.3 | Comandos JS locales y lista permitida | En espera | Comandos compatibles y límites verificados |
| 5.4 | Persistencia local y puerta 5 | En espera | Restauración, límites y regresión integral |
| 6 | Migración y experiencia | Bloqueada por 5 | Instalación y medición en otra app |
| 7 y 1.0 | Seguridad y operación | Bloqueada por 6 | Compatibilidad, revisión y apps reales |

**Regla de avance:** cerrar y commitear la primera entrega activa antes de
empezar la siguiente. Cada commit de funcionalidad incluye semántica,
paridad, rechazo cercano y documentación. Una regresión o un problema de
seguridad interrumpe la cola hasta corregirse. La puerta cambia de estado
solo con evidencia reproducible. `take`, `drop` y `uniq` pasaron antes de fijar
esta cola; los detalles de fases 3–7 son inventario adelantado.

## Puertas de aceptación

Las casillas de las fases siguientes registran trabajo individual, **no** la
aceptación de una fase. Se cierra una puerta solo cuando se cumplen todos sus
criterios y se conserva evidencia reproducible. El trabajo adelantado de fases
posteriores queda registrado abajo y no cambia este orden.

| Paso | Puerta de aceptación | Estado | Próximo bloqueo |
|---|---|---|---|
| S y 0 | Spikes documentados; semántica, render y arnés de paridad base verificados | Cerrada | Ninguno |
| 1. Superficie LiveView | Instalación y migración reproducibles; componente servidor/cliente con diff de dos líneas; fallos de compilación accionables; S5 en navegador | Cerrada | Ninguno |
| 2. Subconjunto publicado | Tres casos de aceptación sin escapes; paridad Elixir/JS y navegador para cada forma admitida; rechazos precisos para el resto | Cerrada | Ninguno |
| 3. Sincronización | Convergencia con entrega fuera de orden, duplicados y reconexión; política de conflictos documentada | Cerrada | Ninguno |
| 4. Rendimiento | Presupuestos de runtime y 1,000 filas medidos en la ruta nativa; diff por dependencias y carga diferida | Cerrada | Ninguno |
| 5. Funciones | Temporizadores, validación, comandos y persistencia con paridad y límites | Abierta | Temporizadores y paridad de efectos |
| 6. Experiencia | Auditoría, test, telemetría, documentación de migración e instalador verificados en otra app | En espera de 5 | Medición antes de optar, inspector e instalación completa |
| 7 y 1.0 | Seguridad y compatibilidad verificadas; dos apps reales; revisión cruzada; API estable | En espera de 6 | Revisión externa, apps piloto y política de versiones |

**Regla de ejecución:** terminar la primera puerta abierta antes de ampliar el
alcance de otra fase. Una casilla adelantada sigue siendo válida como evidencia,
pero la puerta permanece abierta hasta verificar su conjunto completo.

**Registro de trabajo adelantado:** la fase 2 ya tiene listas nativas con clave,
eventos dinámicos y formularios con mapas anidados acotados; la fase 3 tiene snapshots y reconexión
básica; la fase 4 tiene benchmarks de 1,000 filas; las fases 6 y 7 tienen tareas
de auditoría, paridad, pruebas de accesibilidad y límites. Los detalles y las
limitaciones están en cada fase y en `docs/liveview-api-spikes.md`. Ninguno de
estos avances sustituye la puerta anterior.

## Principios

1. **LiveView-shaped.** Nada de sintaxis nueva donde LiveView ya tiene una (`~H`,
   `phx-*`, `:if`, `:for`, `attr`/`slot`, `handle_event/3`, `assign`/`update`).
2. **No tocar LiveView.** Solo API pública, hooks y eventos. Sin forks ni parches.
3. **Presupuesto de conceptos nuevos:** idealmente `use LiveLift` y `@client true`.
4. **Reversible.** Subir o bajar de nivel es añadir o quitar una marca.
5. **El servidor es la autoridad.** Nunca acepta estado del cliente, solo parámetros
   que valida como cualquier `handle_event`.
6. **Lo no soportado falla al compilar** con un mensaje que dice qué hacer.
7. **Paridad Elixir/JavaScript probada**, no supuesta.

## Escalera de migración

| Nivel | Qué corre en el cliente | Activación |
|---|---|---|
| 0 | Nada (LiveView puro) | Estado actual de la app |
| 1 | Comandos `JS` y hooks | Ya existe en LiveView |
| 2 | Un handler con predicción optimista | `@client true` sobre `handle_event` |
| 3 | Un componente con estado local | `@client` en el componente |
| 4 | Una región con varios componentes, contexto y navegación local | Post-1.0 |
| 5 | Página completa cliente-primero, datos locales y offline | Post-1.0, opcional |

API objetivo:

```elixir
defmodule MyAppWeb.Counter do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns) do
    ~H"""
    <button phx-click="inc" phx-target={@myself}>{@count}</button>
    """
  end

  @client true
  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end
end
```

## Fase S: Spikes de viabilidad (1 semana)

Resolver estas preguntas antes de construir sobre la API objetivo. Documentar
cada resultado en `docs/`.

- [x] **S1.** `use LiveLift` lee `@client true` con `@on_definition` y extrae el `~H`
  del cuerpo de `render/1` para construir la plantilla del cliente.
- [x] **S2.** La frontera `phx-update="ignore"` se genera alrededor de `render/1`
  sin que el usuario cambie cómo escribe sus componentes.
- [x] **S3.** Se puede envolver `handle_event/3` con `defoverridable` para empujar el
  parche autoritativo sin depender de internos de LiveView.
- [x] **S4.** Un componente con el mismo `~H` y `handle_event/3` compila y renderiza
  con solo cambiar el `use` y añadir `@client true`. El spike corre en CI.
- [x] **S5 (puerta de migración).** El mismo componente funciona en Chromium en
  ambos modos: el clic optimista y la respuesta autoritativa convergen sin
  reescribir `~H`, `phx-*` ni `handle_event/3`. Bloquea el lanzamiento de la API
  nueva aunque S1–S4 pasen.

**Si alguno falla:** plan B con marca explícita (por ejemplo `<.client>` en el
template o macro propio). Se debilita la promesa de cero aprendizaje, no la idea.

Resultados y límites de los spikes: `docs/liveview-api-spikes.md`.

## Fase 0: Cimientos (1 a 2 semanas, v0.2)

- [x] Paridad de atributos con entidades HTML (`&amp;` y similares).
- [x] Sincronizar `checked`, `select` y `textarea` en el reconciliador.
- [x] Quitar el `<span>` que envuelve cada `{@x}` (anclas de texto).
- [x] Higiene: `.gitignore` completo, sacar `docs/release.md` del paquete Hex, una sola
  copia del runtime, CI con la versión real de Elixir/OTP.
- [x] Documento de **semántica formal** (números, igualdad, truthiness, errores).
- [x] **Arnés de paridad con propiedades** (StreamData + Node): expresiones y plantillas
  aleatorias, servidor contra cliente.

**Listo cuando:** el arnés corre miles de casos en CI sin diferencias.

## Fase 1: Superficie LiveView (3 a 4 semanas, v0.3)

- [x] `use LiveLift` y `@client true` sobre `Phoenix.LiveComponent` para el
  subconjunto inicial de `phx-click` y un `assign/update`.
- [x] El servidor renderiza con el `~H` real en la API nueva (el renderizador de
  strings permanece para compatibilidad con la API anterior).
- [x] Frontera `phx-update="ignore"` generada automáticamente.
- [x] `phx-click`, `phx-change`, `phx-submit`, `phx-value-*` en lugar de `$click`
  en el subconjunto inicial de eventos con parámetros planos.
- [x] Deprecar `client_template`, `defclient`, `$click` y `island` con avisos
  al usar `LiveLift.Client` o llamar `LiveLift.View.island/1`.
- [x] `mix live_lift.migrate` para convertir el subconjunto anterior. Convierte
  plantillas literales con `$click`, `$input` de texto y textarea, `$change` de select
  y `$submit` de formularios con mapas anidados acotados, junto con acciones de actualización de mapa,
  incluso varios campos que leen el estado original, a un componente nuevo.
  Rechaza explícitamente el resto. El spike S6 mostró que `$server` envía
  estado y revisión al LiveView padre y que sustituirlo por `phx-click` cambia
  el contrato. La guía manual y el rechazo se verificaron en una app Phoenix
  generada de cero con `test/integration/phoenix_consumer.sh`.
- [x] Aislar el parser interno de Phoenix tras un módulo adaptador; CI contra LiveView
  `main` (fallo permitido); parser propio de respaldo para el subconjunto
  publicado, comparado con el parser de LiveView en las plantillas del demo y
  ejecutado por CI al compilar la librería y el demo.

**Listo cuando:** el mismo módulo corre en modo servidor y en modo cliente con HTML
equivalente, y el diff entre ambas versiones es `use LiveLift` y `@client true`.
La API no se anuncia como lista hasta pasar S5 en el navegador.
S5 pasó para el contador inicial. Los formularios `phx-change` y
`phx-submit` con mapas anidados acotados tienen paridad Elixir/JavaScript y
una prueba en Chromium, Firefox y WebKit. `$server` requiere la migración
manual documentada; los componentes anidados y handlers más
amplios pertenecen al cierre del subconjunto de la fase 2.

**Evidencia de cierre:** `test/integration/phoenix_consumer.sh` genera una app
Phoenix independiente, instala LiveLift desde el checkout local, verifica el
rechazo de `$server` sin archivo parcial, prueba un guardado con estado
autoritativo y ejecuta `mix live_lift.test`, `mix assets.build` y
`mix assets.deploy`. Los tests de navegador S5 cubren ambos modos del
componente. Este gate valida la integración local; la instalación desde Hex sin
ruta al checkout pertenece a la fase 6 y espera la publicación humana.

## Fase 2: Compilador v2 (4 a 6 semanas, v0.4)

Introducir una **representación intermedia (IR)**: AST de Elixir, normalización
(pipes, `if`), tipos mínimos, emisión de JavaScript. Errores con archivo y línea.

Orden de funcionalidades:

1. Pattern matching en cabeceras de función (necesario para `handle_event("x", _, socket)`).
2. `socket`, `assign`, `update`, `assign_new`.
3. Plantilla: `:if`, `:for`, componentes de función con `attr` y slots,
   `class={[...]}`, `phx-debounce`.
4. Números decimales (decidir el modelo numérico antes de implementarlos).
5. `case`, `cond`, `defp` con varias cláusulas, `|>`.
6. `Enum`: `find`, `reduce`, `sort_by`, `count`, `take`, `drop`, `uniq`, `join`,
   `flat_map`, `with_index`.
7. `String`: `trim`, `length`, `downcase`, `contains?`, `split`, `replace`.
8. `Map` y `List`: `merge`, `delete`, `take`, `keys`, `values`.

El subconjunto inicial ya acepta patrones anidados como
`%{"profile" => %{"note" => note}}` y cadenas
de `assign/update`, tanto por pipe como por llamadas anidadas. La matriz
documenta qué patrones de handlers y callbacks de `assign_new` quedan en el
servidor. El módulo `LiveLift.Client.IR` baja pipes a llamadas y representa
cada `if` con sus dos ramas antes de emitir JavaScript. Distingue condiciones
booleanas de valores que requieren las reglas de verdad de Elixir. El
compilador mantiene el diagnóstico del handler con archivo y línea.
El modelo para literales decimales está documentado en
`docs/decimal-model-spike.md`: floats binarios finitos con un escalar etiquetado
en el protocolo de estado. La sintaxis decimal ya compila; 5,000 patrones de
bits finitos, operaciones mixtas, paridad de handler nativo y render de
plantilla en DOM simulado pasaron. El demo `/native-float` verificó render
inicial, predicción y respuesta autoritativa en Chromium, Firefox y WebKit. El
benchmark reproducible `LIVE_LIFT_BENCH=1 npx playwright test -g 'benchmark native float action' --project=chromium`
midió cinco lotes de 50 clics: mediana de 16 µs por acción flotante en esta
máquina, frente a 40 µs para el contador entero de otra plantilla; son cargas
distintas y no una comparación de velocidad de tipos. El paquete de referencia
subió 511 bytes gzip respecto del commit anterior (`53,539` a `54,050` bytes).
`cond` compila en handlers marcados: el corpus de 1,000 estados, un caso de
ausencia de rama verdadera y un caso de evaluación perezosa pasan en
Elixir/JavaScript. El botón «Minimum one» lo verifica en tres navegadores.
El paquete de referencia conservó `54,050` bytes gzip tras este cambio; el
helper de `cond` no se incluye cuando ninguna acción lo utiliza.
`case` compila patrones sin guarda de literales, listas, mapas parciales,
variables y `_`, con distinción entre `1` y `1.0`, y entre `-0.0` y `0.0`.
Dos acciones con 1,000
estados generados cada una, errores por falta de coincidencia, dos casos de
paridad de la app y un handler nativo en tres navegadores verifican el alcance.
Guardas, pins, tuplas y variables repetidas se rechazan antes de emitir JS.
El benchmark de paquete de referencia permaneció en `54,050` bytes gzip al
no usar `case` en esa app; el benchmark DOM de 1,000 filas y el de evento
Phoenix se ejecutaron de nuevo sin regresión funcional.
Los `defp` locales con varias cláusulas sin guarda compilan aunque se declaren
después del handler. Tres componentes de prueba verifican listas, mapas, `nil`,
varios argumentos, llamadas entre helpers y errores sin cláusula; la app demo
añade 2 casos de paridad y un flujo de navegador en Chromium, Firefox y WebKit.
Recursión, guardas y expansión excesiva se rechazan con ubicación de origen.
El paquete de referencia conservó `54,050` bytes gzip cuando no usa helpers;
los benchmarks de render, DOM y evento Phoenix se repitieron.
`|>` en expresiones compila hacia llamadas admitidas, incluidas funciones
locales: el corpus de 1,000 estados ahora cubre dos cadenas y el handler
`helper_step` del demo pasa paridad y navegador con una llamada por pipe.
El paquete de referencia siguió en `54,050` bytes gzip; se repitieron los
benchmarks de render, DOM y evento Phoenix.
`assign_new/3` con clave átomo y callback sin argumentos admite campos ausentes
en el snapshot inicial. Un valor presente, incluso `nil`, evita evaluar el
callback. El demo `/native-optional` y dos casos de paridad comprueban creación
y conservación; tres navegadores comprueban render inicial y convergencia.
La plantilla nativa ya admite atributos `class`, `title`, `aria-label` y
`value` con expresiones de asignaciones, y listas de clase con `&&` condicional.
También acepta `:for` nativo con `id={item.id}` como clave estable y conserva
la fila enfocada al reordenarla. Los componentes de función locales con props
explícitas y `~H` literal se expanden para el cliente; el demo usa uno para
el error de validación y otro para un botón con evento del padre. El slot
predeterminado funciona una vez con `render_slot(@inner_block)` y contenido
en el ámbito del llamador. Los demás casos sin ID estable quedan en el servidor;
slots con nombre y componentes remotos se rechazan con ubicación de origen y
permanecen en el servidor en esta versión.
Los eventos nativos ya admiten `phx-value-id={item.id}` y el demo añade y quita
filas con handlers `@client true`. Una acción que quita el botón pulsado se envía
al servidor mediante la raíz estable del componente.
El demo ahora edita una fila con un formulario plano `phx-change`/`phx-submit`
y un handler `Enum.map/2`, sin sintaxis de componentes nueva. El hook evita que
el segundo evento `change` genere una petición nativa duplicada con `_target`.
Los formularios con parámetros de mapa anidados hasta cuatro segmentos ya pasan
paridad y navegador; los arrays y controles especiales siguen pendientes.
`Map.take/2` ya acepta una lista literal de claves átomo; la paridad se comprueba
con estados generados. El [spike de mapas](docs/map-iteration-spike.md)
demostró que el orden observado al extraer claves o valores depende de la
representación del mapa. Se admiten las proyecciones bajo `length/1` o
`Enum.count/1`, y los nombres de claves si se convierten a texto y se ordenan
de forma explícita. Las proyecciones sin ordenar ni contar se rechazan con
ubicación de origen.
`String.contains?/2`, `String.trim/1` y `String.length/1` ya tienen paridad
en el corpus probado, incluidos espacios Unicode y grafemas complejos. La
segmentación de grafemas depende de `Intl.Segmenter` y de la versión Unicode del
navegador.
El spike `docs/downcase-spike.md` comparó todos los valores escalares Unicode:
1,488 cambian al bajar de caja y la conversión por carácter en JavaScript tuvo
cero diferencias con Elixir en este toolchain. `String.downcase/1` ya compila;
el corpus de 1,000 estados y el demo con sigma griega comprueban paridad y
convergencia en tres navegadores. El paquete de referencia, que no usa
`downcase`, midió `54,049` bytes gzip; se repitieron los benchmarks de render,
evento Phoenix y DOM.
El spike `docs/split-spike.md` fijó 22 caracteres de espacio para `split/1`,
la separación por grafemas cuando el patrón es vacío, la precedencia de
patrones solapados y las opciones `trim`/`parts`. `String.split/1,2,3` ya
compila en ese alcance; el corpus de 1,000 estados y el demo verifican
paridad. Los regex y las opciones dinámicas se rechazan con ubicación de
origen. La prueba de navegador pasó en Chromium, Firefox y WebKit. El paquete
de referencia permaneció en `54,049` bytes gzip; se repitieron los benchmarks
de render, evento Phoenix y DOM.
El spike `docs/replace-spike.md` fijó patrones solapados, reemplazo vacío por
grafemas, callback con iodata y la opción literal `global`. `String.replace/3,4`
pasó el corpus de 1,000 estados, casos de rechazo y el demo en Chromium,
Firefox y WebKit. `mix assets.build` y `mix assets.deploy` pasaron. El paquete
de referencia midió `54,050` bytes gzip, un byte más que la medición anterior;
se repitieron los benchmarks de render, evento Phoenix y DOM. Sigue `Map`/`List`.
`Enum.take/2`, `Enum.drop/2` y `Enum.uniq/1` también tienen paridad para listas
seguras. `Enum.find/2,3` ya tiene paridad con 1,000 estados y un handler nativo
que converge en tres navegadores. El paquete de referencia, que no usa esta
operación, mide `54,049` bytes gzip; los benchmarks de render, evento Phoenix
y DOM se ejecutaron de nuevo.
`Enum.reduce/2,3` compila con callback anónimo de dos argumentos. El corpus de
1,000 estados cubre acumuladores numéricos, `nil`, `false` y listas vacías;
`reduce/2` vacío falla en ambos runtimes. El demo concatena las etiquetas de
filas propias de la app y converge en Chromium, Firefox y WebKit.
El paquete de referencia, que tampoco usa `reduce`, conservó `54,049` bytes
gzip; se repitieron los benchmarks de render, evento Phoenix y DOM. La
mediana DOM de inversión de 1,000 filas fue 55.4 ms en linkedom; este
benchmark no mide `reduce` directamente.
El spike `docs/sort-by-spike.md` confirma el orden de términos para valores
seguros y la diferencia UTF-8/UTF-16. `Enum.sort_by/2` ya pasa 1,000 listas
mixtas y 302 listas numéricas con floats etiquetados; el demo verifica orden,
foco y convergencia en tres navegadores. En 25 inversiones y ordenamientos
locales de 1,000 filas, Chromium midió mediana de 10.9 ms y p95 de 18.3 ms:
el p95 supera el presupuesto de un frame. El bundle de referencia, que no usa
`sort_by`, midió `54,050` bytes gzip con LiveLift y `47,221` sin él.
`Enum.count/1,2` ya compila para listas; el corpus de 1,000 estados comprueba
longitud, listas vacías y predicados con verdad de Elixir. El demo cuenta filas
propias de la app. El paquete de referencia, que no usa `count`, conservó `54,050` bytes
gzip; se repitieron los benchmarks de render, evento Phoenix y DOM.
`Enum.join/1,2` compila para listas de valores convertibles según el subconjunto
publicado de `String.Chars`, con separador de string. El corpus de 1,000 estados
cubre `nil`, booleanos, enteros, Unicode y chardata; otro test cubre floats y
`-0.0`, y se rechazan mapas y puntos Unicode inválidos. El demo concatena
etiquetas con separador propio y converge en tres navegadores. El bundle de
referencia, que no usa `join`, conservó `54,050` bytes gzip; se repitieron los
benchmarks de render, evento Phoenix y DOM.
`Enum.flat_map/2` compila callbacks anónimos que devuelven listas. El corpus
de 1,000 estados prueba expansión, filtrado y lista vacía; los resultados
escalares se rechazan y la salida se limita a 10,000 elementos. El demo
expande etiquetas de filas propias de la app. El paquete de referencia, que no usa `flat_map`, midió
`54,049` bytes gzip; se repitieron los benchmarks de render, evento Phoenix y
DOM.
`Enum.with_index/2` con callback anónimo compila y pasa el corpus de 1,000
estados; el demo numera etiquetas sin cambiar la sintaxis de LiveView. Las
variantes que devuelven tuplas (`/1` y `/2` con offset) fallan al compilar con
una alternativa explícita porque el estado de LiveLift no admite tuplas. Con
esta decisión, el bloque `Enum` de la fase queda resuelto. El paquete de referencia,
que no usa `with_index`, midió `54,049` bytes gzip; se repitieron los benchmarks
de render, evento Phoenix y DOM.
`Map.merge/2` y `Map.delete/2` ya tienen paridad para mapas seguros.
`List.delete/2` borra la primera coincidencia exacta, incluso con números dentro
de mapas y listas. El corpus compara índices negativos, positivos y fuera de
rango en `List.insert_at/3`, `List.replace_at/3` y `List.delete_at/2`. El demo
usa estas operaciones para añadir, reemplazar y quitar filas. Las funciones
de listas que requieren tuplas se mantienen en el servidor.

Trampas de paridad a probar a propósito: `String.length` por grafemas (`Intl.Segmenter`),
orden de strings fuera del plano básico, `downcase` con Unicode, redondeo y formato de
decimales, representación de átomos como valores.

**Listo cuando:** tres casos de aceptación compilan sin escapes: todo optimista,
validación de formulario en vivo, lista ordenable.

**Tablero de cierre de la fase 2** (se sigue de arriba abajo):

| Bloque | Estado | Evidencia o salida requerida |
|---|---|---|
| Componentes locales con props y slot predeterminado | Verificado | Tests de compilación y formulario con slot en Chromium, Firefox y WebKit |
| Slots con nombre y componentes remotos | Alcance decidido | Rechazo accionable con origen; quedan en LiveView servidor |
| `class={[...]}` | Verificado | Comparación de render inicial y actualización para listas condicionales |
| `phx-debounce` | Verificado para input/textarea | HTML inicial, temporizador y `blur` en tres navegadores; otras formas se rechazan |
| Alcance de handlers | Verificado | Operaciones publicadas y formas rechazadas en la matriz de handlers |
| IR y normalización | Verificado | Corpus de paridad incluye pipes hacia `if` y ramas que no se deben evaluar. Los rechazos conservan archivo y línea |
| Tres casos completos | Verificado | Contador, formulario anidado y lista ordenable; detalles abajo |
| Regresión final de fase | Verificado | 120 tests de librería, 27 del runtime, 7 del demo, paridad y 126 pruebas en tres navegadores |

"Pendiente" no implica que toda forma vaya a implementarse. Un rechazo preciso
es una decisión de alcance válida para esta versión; la documentación debe
explicar qué queda en el servidor. Una forma implementada requiere semántica
publicada y prueba Elixir/JavaScript antes de cambiar su estado a "Verificado".

| Caso de aceptación | Estado | Evidencia que falta |
|---|---|---|
| Contador optimista con guardado del servidor | Verificado | Ninguna: demo y app Phoenix generada, con paridad y navegador |
| Validación de formulario en vivo con mapa anidado | Verificado | Ninguna: casos válidos e inválidos en Elixir/JS y Chromium, Firefox y WebKit |
| Lista ordenable con filas editables y foco estable | Verificado | Ninguna: `move_to_top` elige una fila, conserva foco e identidad en tres navegadores; paridad Elixir/JS |

El gate también requiere cerrar o rechazar explícitamente con ubicación de
origen los componentes de función, slots y las formas del compilador indicadas
arriba. Los checks de fases posteriores no cuentan para este cierre.

**Evidencia de cierre (commit de código `2d0a086`).** La suite de Playwright
ejecutó los tres casos de aceptación en Chromium, Firefox y WebKit. El arnés
compara el mismo corpus de 1,006 estados en Elixir, Node y los tres navegadores,
incluidos grafemas, mapas y listas, control de flujo y aritmética. La
comparación en memoria detectó un `-0` entero oculto por JSON y verificó su
corrección. El demo pasó `mix live_lift.test`, `mix assets.build` y
`mix assets.deploy`. La app Phoenix generada por
`sh test/integration/phoenix_consumer.sh` pasó su integración desde checkout
local al verificar la normalización del compilador.

`mix run bench/benchmark.exs`, `bench/phoenix_bundle.sh`,
`bench/phoenix_event.sh` y `cd bench && npm run dom` se ejecutaron de nuevo. El
paquete de referencia midió 47,351 bytes gzip con Phoenix y 54,179 con LiveLift.
La inversión de 1,000 filas en linkedom midió 57.8 ms de mediana y 68.1 ms p95.
El presupuesto de un frame se verifica en navegador real en la fase 4.

## Fase 3: Sincronización optimista (4 a 6 semanas, v0.5)

El [spike de orden de acciones](docs/action-order-spike.md) reprodujo pérdida
de una acción al entregar la secuencia 2 antes que la 1. La primera entrega
de esta fase debe distinguir una secuencia faltante de un duplicado y
reintentar sin ejecutar dos veces un handler.

- **Previo:** El evento viaja por el canal normal de LiveView; el servidor ejecuta el mismo
  `handle_event` sobre **sus propios assigns**.
- **Previo:** Si el resultado difiere de la predicción, parche versionado con el estado
  autoritativo; el cliente reaplica las acciones pendientes.
- **Hecho:** Confirmación de secuencia contigua, detección de huecos y
  reintentos ordenados. El servidor no ejecuta duplicados y conserva la
  confirmación al recibir eventos LiveView sin secuencia. Chromium, Firefox y
  WebKit entregaron 2 antes de 1 por el WebSocket real, duplicaron la primera
  acción y verificaron dos incrementos en el servidor.
- **Hecho:** Reconexión con identidad por montaje. Se reintentan las acciones
  pendientes para la misma instancia conservando sus IDs. Un montaje nuevo
  conserva su snapshot y descarta acciones enviadas al anterior. Las acciones
  creadas sin conexión caducan a los 30 segundos y la cola se conserva mientras
  el hook siga montado.
- **Previo:** Límites de tamaño de estado, listas y parámetros.
- **Hecho:** `:reconnect_conflict` permite reproducir acciones nunca enviadas
  o descartarlas tras un montaje nuevo.

**Listo cuando:** pruebas caóticas (corte de red, reordenamiento, duplicados) con
Playwright y una propiedad de **convergencia**: en reposo, cliente y servidor tienen el
mismo estado.

**Evidencia de cierre (código hasta `dddcd98`).** Dos arneses con 1,000
semillas comprobaron respuestas reordenadas y duplicadas, y entrega alterada
en ambas direcciones con una solicitud perdida. Las secuencias usan acciones
que producen resultados distintos si se invierte su orden. Playwright
confirmó los huecos y duplicados en el WebSocket real y la reconexión con
acciones offline en Chromium, Firefox y WebKit. La reanudación de la misma
instancia se comprobó en Node, y los tres navegadores comprobaron que una
reconexión que monta otra instancia usa su snapshot. El almacenamiento entre
recargas de página se desarrolla en la fase 5.

Pasaron 122 pruebas Elixir, 31 del runtime, 7 del demo y 129 en navegador.
La paridad del demo y la compilación de assets también pasaron. Se repitieron
las cuatro mediciones del repositorio. El paquete Phoenix de referencia
midió 54,545 bytes gzip con LiveLift y 47,351 bytes sin LiveLift.

## Fase 4: Rendimiento (3 a 4 semanas, v0.6)

- **Hecho:** Los planes de dependencias conservan filas y subárboles cuando las
  rutas que leen se mantienen iguales. Los controles de formulario sin clave
  siguen pasando por su reconciliación de valor y selección.
- **Hecho:** El diff mueve filas con clave con un cursor entre hermanos y
  preserva identidad y foco. Las respuestas autoritativas se agrupan con
  `requestAnimationFrame`, con temporizador de respaldo. La predicción y
  recuperación de huecos siguen siendo inmediatas.
- **Hecho:** Carga diferida mediante `mix live_lift.compile --split`. El
  [spike de assets](docs/island-loading-spike.md) verificó los chunks
  digeridos. Los tres navegadores confirmaron la descarga por ruta, la
  interacción durante una espera y el error de descarga.
- **Previo:** Benchmarks en navegador real, no solo en linkedom (contador nativo en
  Chromium, con latencia simulada y comandos reproducibles).

La omisión de renders sin cambios ya funciona para acciones y respuestas
autoritativas. Las filas con clave que dependen solo del elemento conservan su
DOM al cambiar de orden; un benchmark anterior del demo con 1,000 filas
midió 3.3 ms de mediana y 7.5 ms p95 en Chromium.
La lista nativa con formularios por fila midió 10.5 ms de mediana y 15.8 ms p95
en 25 inversiones locales de 1,000 filas en Chromium. Está cerca del presupuesto
de un frame; el benchmark reproduce el caso con `/native-list?rows=1000`.
El ordenamiento nativo de esas filas midió 10.9 ms de mediana y 18.3 ms p95
en 25 ciclos antes de las optimizaciones de esta fase.

El [spike de asignaciones del DOM](docs/keyed-row-render-spike.md) observó
1,020 elementos creados al invertir 1,000 filas. Las referencias a las filas
existentes redujeron ese total a 20 y mantuvieron la identidad del input.
En la misma máquina, el p95 de inversión bajó de 17.4 a 13.3 ms y el de
ordenamiento de 19.5 a 15.1 ms. La edición de una fila midió 2.5 ms de
mediana y 8.3 ms p95. Las filas ahora comparan las rutas de estado que leen.
Una corrección autoritativa con 1,000 filas conservó los inputs y creó
como máximo dos elementos de fila entre predicción y corrección en los
tres navegadores. La reutilización de subárboles fuera de listas redujo los
elementos creados en la inversión a dos. La medición aislada de 25 muestras
dio p95 de 13.5 ms para invertir, 17.7 ms para ordenar y 8.3 ms para editar.
La regresión completa pasó 132 pruebas en los tres navegadores.
El siguiente cambio sustituyó el acceso a la lista viva de hijos por un
cursor entre hermanos. En la corrida de 25 muestras, el p95 fue 13.1 ms al
invertir, 16.2 ms al ordenar y 7.3 ms al editar. Con la agrupación por frame,
la corrida nativa dio p95 de 12.9, 15.8 y 7.7 ms respectivamente. Pasaron
24 pruebas dirigidas a sincronización y correcciones en los tres navegadores.
El núcleo minificado antes de la carga diferida pesó 7,721 bytes gzip.

Presupuestos de partida (a afinar con mediciones): runtime núcleo por debajo de unos
8 KB gzip; actualizar 1,000 filas en menos de un frame.

**Evidencia de cierre (código hasta `086c74b`).** Pasaron 122 pruebas
Elixir, 33 de Node, 7 del demo, 39 casos de paridad y 141 pruebas en
Chromium, Firefox y WebKit. La prueba de carga pasó también sus nueve
casos contra la entrada digerida. La medición de 25 muestras en Chromium
con 1,000 filas dio 12.1 ms p95 al invertir, 14.9 ms al ordenar y 8.0 ms al
editar, con conservación del foco y de los inputs en el caso de edición.
El runtime minificado midió 8,119 bytes gzip, por debajo de 8 KiB. En el
demo, el paquete inicial bajó de 61,600 a 55,162 bytes gzip con la carga
por isla. El comando reproducible es `python3 bench/island_bundle.py`.

## Fase 5: Funciones con la sintaxis de siempre (3 a 4 semanas, v0.7)

- **Falta:** `Process.send_after(self(), ...)` y `handle_info` en el cliente (temporizadores).
- **Falta:** Validación de formularios con la forma de `Ecto.Changeset`
  (`validate_required`, `validate_length`, `validate_format`), compartida entre cliente
  y servidor.
- **Falta:** Comandos `JS` locales y una puerta controlada (lista permitida) hacia JavaScript.
- **Falta:** Persistencia local opcional (`sessionStorage`).

## Fase 6: Migración y experiencia de desarrollo (puerta posterior a fase 5)

- **Previo:** `mix live_lift.audit`: qué handlers ya son compatibles con el cliente y por qué
  (auditoría de fuente para `use Phoenix.LiveComponent` y `use AppWeb, :live_component`).
- **Falta:** Telemetría de latencia y frecuencia por evento, para decidir qué migrar con datos.
  Los componentes con `use LiveLift` ya emiten duración y resultado por evento
  marcado o no marcado. Falta medir componentes antes de optar y el tramo del
  navegador para comparar latencia completa.
- **Previo:** `mix live_lift.test`: ejecuta los handlers marcados en Elixir y en Node
  con casos declarativos; exige cobertura de eventos y componentes de la app.
  El demo ejecuta casos de Unicode, `nil` y el límite de entero seguro en CI.
- **Falta:** Documentación en formato diff ("versión servidor contra versión cliente"),
  entendible en una o dos lecturas.
- **Falta:** Errores accionables ("esto no se soporta en `@client`, muévelo a un handler de
  servidor").
- **Falta:** Inspector de estado con viaje en el tiempo en desarrollo.
- **Falta:** Instalador con Igniter, tipos TypeScript, paquete npm versionado, verificación de
  que el JavaScript generado y el runtime coinciden.

## Fase 7: Seguridad y operación (4 semanas, v0.9)

- **Previo:** Modelo de amenazas escrito: el estado va visible en el HTML (sin secretos), el
  estado del cliente no es de fiar, compatibilidad con CSP sin `eval`.
- **Previo:** Auditoría interna de XSS y de los usos de `innerHTML` en el runtime.
- **Previo:** Pruebas de prototype pollution y fuzzing del compilador para el subconjunto
  actual (1,000 expresiones generadas con semilla y comprobación sintáctica en Node).
- **Falta:** Telemetría (`:telemetry` en servidor, reporte de errores del cliente).
- **Previo:** **Interruptor de emergencia** por componente y global: vuelve al servidor
  en nuevas cargas; clientes ya montados recargan al siguiente evento marcado.
- **Previo:** Accesibilidad: foco al re-renderizar y axe WCAG A/AA del demo en Chromium,
  Firefox y WebKit. No equivale a una auditoría con lector de pantalla.
- **Falta:** Política de versiones: rango de LiveView soportado, deprecaciones, changelog
  automatizado, publicación firmada en Hex y npm.
- **Previo:** Pruebas de carga con 100 islas por página: eventos independientes en
  Chromium, Firefox y WebKit, más benchmark reproducible de montaje en Chromium.

La revisión interna bloquea esquemas de URL codificados con entidades y
`xlink:href`; las pruebas cubren las tres claves de prototype pollution,
1,000 variantes generadas de `javascript:` y 1,000 expresiones de acción
generadas. El fuzzing de todas las formas HEEx y una revisión de seguridad
externa siguen pendientes.

## Criterios para 1.0

- API congelada durante al menos un ciclo de LiveView.
- Cero diferencias en el arnés de paridad.
- Al menos dos aplicaciones reales en producción, no solo el demo.
- Auditoría de seguridad externa o, como mínimo, revisión cruzada.
- Documentación entendible en una o dos lecturas para quien conoce LiveView.

## Fase 8: Escalera avanzada (post-1.0, opcional)

Decidir con datos de usuarios reales. Es un salto de costo, no un peldaño más.

- [ ] **Nivel 4:** router de cliente, contexto compartido, sub-vistas sin viaje al
  servidor, carga diferida.
- [ ] **Nivel 5:** página cliente-primero, datos locales (IndexedDB), cola offline,
  mucha más cobertura de Elixir. Evaluar antes si se puede reutilizar el transpilador de
  Hologram, o si conviene Elixir en WASM.
- [ ] Proponer al equipo de Phoenix las mejoras que solo se pueden hacer bien desde
  dentro (parser público de HEEx, frontera de DOM propia).

## Qué no hacer

- Traducir Elixir arbitrario (procesos, macros, protocolos, structs generales).
- Inventar sintaxis de plantilla que LiveView ya resuelve.
- Fusión automática de estado (CRDT) antes de que la sincronización básica sea estable.
- Fallback silencioso a servidor: usar aviso explícito o el interruptor de emergencia.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Los spikes fallan | Plan B con marca explícita en el template |
| El parser interno de LiveView cambia | Adaptador, CI contra `main`, tokenizador propio de respaldo |
| Deriva semántica entre runtimes | Arnés de propiedades y semántica formal |
| Un solo mantenedor | Decisiones documentadas, tests como especificación, contribuciones acotadas |
| Hologram avanza más rápido | Diferenciarse por integración con LiveView, no por cobertura de Elixir |
| Sin usuarios reales | Publicar casos concretos (todo optimista, validación compartida) y buscar dos o tres apps piloto |

## Métricas de seguimiento

- Diferencias en el arnés de paridad (objetivo: 0).
- Tamaño del runtime en KB gzip.
- Tiempo de actualización con 1,000 filas.
- Porcentaje de handlers de apps piloto que `mix live_lift.audit` marca como migrables.
- Número de aplicaciones en producción.
