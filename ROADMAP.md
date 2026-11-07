# ROADMAP de LiveLift

Objetivo: que quien ya usa Phoenix LiveView pueda **mover partes de su interfaz al
cliente, a elección**, escribiendo lo mismo que ya sabe, y llegar por etapas a
capacidades parecidas a las de Hologram sin reescribir su aplicación.

Las duraciones son estimaciones gruesas para una sola persona y son muy inciertas.
Orden de magnitud hasta 1.0: 7 a 10 meses.

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
- [ ] Deprecar `client_template`, `defclient`, `$click` y `island` con avisos.
- [ ] `mix live_lift.migrate` para convertir la API anterior.
- [ ] Aislar el parser interno de Phoenix tras un módulo adaptador; CI contra LiveView
  `main` (fallo permitido); plan B de tokenizador propio. (Adaptador y CI listos;
  tokenizador de respaldo pendiente.)

**Listo cuando:** el mismo módulo corre en modo servidor y en modo cliente con HTML
equivalente, y el diff entre ambas versiones es `use LiveLift` y `@client true`.
La API no se anuncia como lista hasta pasar S5 en el navegador.
S5 pasó para el contador inicial; formularios, componentes anidados y handlers
más amplios siguen pendientes antes de cerrar toda la fase 1.

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

El subconjunto inicial ya acepta un patrón plano `%{"name" => name}` y una
llamada directa o pipe simple de `assign/update`. Faltan patrones anidados,
varias operaciones encadenadas y `assign_new`; por eso la fase 2 sigue abierta.

Trampas de paridad a probar a propósito: `String.length` por grafemas (`Intl.Segmenter`),
orden de strings fuera del plano básico, `downcase` con Unicode, redondeo y formato de
decimales, representación de átomos como valores.

**Listo cuando:** tres casos de aceptación compilan sin escapes: todo optimista,
validación de formulario en vivo, lista ordenable.

## Fase 3: Sincronización optimista (4 a 6 semanas, v0.5)

- [x] El evento viaja por el canal normal de LiveView; el servidor ejecuta el mismo
  `handle_event` sobre **sus propios assigns**.
- [x] Si el resultado difiere de la predicción, parche versionado con el estado
  autoritativo; el cliente reaplica las acciones pendientes.
- [ ] Cola de acciones pendientes, claves de idempotencia, ordenamiento, duplicados.
- [ ] Reconexión: pedir snapshot, vaciar la cola, cola offline con caducidad.
- [x] Límites de tamaño de estado, listas y parámetros.
- [ ] Política de conflictos configurable.

**Listo cuando:** pruebas caóticas (corte de red, reordenamiento, duplicados) con
Playwright y una propiedad de **convergencia**: en reposo, cliente y servidor tienen el
mismo estado.

La reconciliación aplica la respuesta de forma atómica. Un arnés con 1,000
órdenes de respuesta y correcciones generadas prueba convergencia; Chromium
prueba eventos pendientes intercalados con un reset de servidor. Falta cubrir
interrupciones y duplicados de transporte con una prueba caótica completa.

## Fase 4: Rendimiento (3 a 4 semanas, v0.6)

- [ ] Partes estáticas y dinámicas: cada binding declara sus dependencias y solo se
  actualiza lo que cambió.
- [ ] Diff de listas con clave, omitir renders si el estado no cambió, agrupar con
  `requestAnimationFrame`.
- [ ] Carga diferida de vistas por isla.
- [x] Benchmarks en navegador real, no solo en linkedom (contador nativo en
  Chromium, con latencia simulada y comandos reproducibles).

Presupuestos de partida (a afinar con mediciones): runtime núcleo por debajo de unos
8 KB gzip; actualizar 1,000 filas en menos de un frame.

## Fase 5: Funciones con la sintaxis de siempre (3 a 4 semanas, v0.7)

- [ ] `Process.send_after(self(), ...)` y `handle_info` en el cliente (temporizadores).
- [ ] Validación de formularios con la forma de `Ecto.Changeset`
  (`validate_required`, `validate_length`, `validate_format`), compartida entre cliente
  y servidor.
- [ ] Comandos `JS` locales y una puerta controlada (lista permitida) hacia JavaScript.
- [ ] Persistencia local opcional (`sessionStorage`).

## Fase 6: Migración y experiencia de desarrollo (continua desde v0.4)

- [ ] `mix live_lift.audit`: qué handlers ya son compatibles con el cliente y por qué.
- [ ] Telemetría de latencia y frecuencia por evento, para decidir qué migrar con datos.
- [ ] `mix live_lift.test`: ejecuta los handlers del usuario en Elixir y en Node.
- [ ] Documentación en formato diff ("versión servidor contra versión cliente"),
  entendible en una o dos lecturas.
- [ ] Errores accionables ("esto no se soporta en `@client`, muévelo a un handler de
  servidor").
- [ ] Inspector de estado con viaje en el tiempo en desarrollo.
- [ ] Instalador con Igniter, tipos TypeScript, paquete npm versionado, verificación de
  que el JavaScript generado y el runtime coinciden.

## Fase 7: Seguridad y operación (4 semanas, v0.9)

- [ ] Modelo de amenazas escrito: el estado va visible en el HTML (sin secretos), el
  estado del cliente no es de fiar, compatibilidad con CSP sin `eval`.
- [ ] Auditoría de XSS y de los usos de `innerHTML` en el runtime.
- [ ] Pruebas de prototype pollution y fuzzing del compilador.
- [ ] Telemetría (`:telemetry` en servidor, reporte de errores del cliente).
- [x] **Interruptor de emergencia** por componente y global: vuelve al servidor
  en nuevas cargas; clientes ya montados recargan al siguiente evento marcado.
- [ ] Accesibilidad: foco al re-renderizar, axe en Chromium, Firefox y WebKit.
- [ ] Política de versiones: rango de LiveView soportado, deprecaciones, changelog
  automatizado, publicación firmada en Hex y npm.
- [ ] Pruebas de carga con muchas islas por página.

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
