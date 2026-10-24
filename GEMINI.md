# Reglas del Proyecto Mitos y Leyendas (NosTaw / MitosOnline)

## 1. REGLA OBLIGATORIA DE DISEÑO DE INTERFAZ (UI DESIGN SYSTEM)
Todo menú, panel, diálogo modal, overlay, selector, popup o componente de interfaz de usuario que se cree, rediseñe o modifique en este proyecto DEBE construirse obligatoriamente sobre la base visual del sistema medieval oscuro y dorado ("Configuracion.jpg" / "ControlsDialog"):

### Base Visual de Contenedores y Modales (Paneles)
- **Fondo / Lienzo**: Obsidiana / Azul marino pizarra muy oscuro (`#0B0E14` a `#121721` o `Color(0.07, 0.09, 0.13, 0.96)`).
- **Borde Principal**: Oro antiguo / Ámbar medieval (`#C7A652` o `Color(0.78, 0.65, 0.32, 0.90)`), grosor 2px, esquinas redondeadas (`corner_radius` 12px a 14px).
- **Sombra y Profundidad**: Sombra profunda suave para flotar sobre el fondo (`shadow_color = Color(0, 0, 0, 0.85)`, `shadow_size = 24 a 28`).
- **Separadores**: Líneas horizontales finas doradas y translúcidas (`Color(0.78, 0.65, 0.32, 0.35)`, grosor 1px).
- **Telón de fondo**: `ColorRect` oscuro translúcido (`Color(0.02, 0.03, 0.05, 0.85)`) para desenfocar/oscurecer el fondo durante modales.

### Tipografía y Jerarquía Visual
- **Títulos y Encabezados**: Fuente `res://assets/fonts/Cinzel-Bold.ttf`, color dorado cálido (`Color(0.92, 0.80, 0.38, 1.0)` o `Color(0.96, 0.88, 0.60, 1.0)`) con sutil sombra negra (`Color(0, 0, 0, 0.9)`, offset Y=2).
- **Subtítulos y Descripciones**: Fuente `res://assets/fonts/Marcellus-Regular.ttf`, color beige/pizarra suave (`Color(0.65, 0.70, 0.80, 1.0)` o `Color(0.85, 0.80, 0.70, 1.0)`).
- **Textos de Botón**: Fuente `Cinzel-Bold.ttf` centrada, tamaño proporcionado (13px a 18px).

### Botones y Elementos Interactivos
- **Estado Normal**:
  - Relleno pizarra oscuro: `Color(0.12, 0.15, 0.22, 0.95)`
  - Borde oro/bronce sutil: `Color(0.50, 0.45, 0.35, 0.80)` (o color acento * 0.8), grosor 1px a 1.5px
  - Radio de esquina: 6px a 8px
  - Color de texto: Dorado claro `Color(0.96, 0.90, 0.75, 1.0)`
- **Estado Hover (Cursor encima)**:
  - Relleno pizarra iluminado: `Color(0.18, 0.24, 0.34, 1.0)`
  - Borde oro radiante: `Color(1.0, 0.88, 0.48, 1.0)`, grosor 2px
  - Resplandor / Halo dorado: `shadow_color = Color(0.88, 0.74, 0.28, 0.35)`, `shadow_size = 8 a 10`
  - Color de texto: Blanco puro / Oro brillante `Color(1.0, 1.0, 1.0, 1.0)`
- **Estado Pressed (Pulsado)**:
  - Tono cálido ámbar oscuro: `Color(0.20, 0.17, 0.10, 0.98)`
  - Borde dorado firme: `Color(0.88, 0.74, 0.28, 0.90)`, grosor 2px
- **Botón Primario (Destacado / Acción Principal como "JUGAR")**:
  - Relleno con matiz dorado oscuro: `Color(0.16, 0.14, 0.10, 0.96)`
  - Borde oro intenso 2px: `Color(0.88, 0.74, 0.28, 0.95)`
  - Hover con halo expandido: `shadow_color = Color(0.88, 0.74, 0.28, 0.45)`, `shadow_size = 10`
- **Botón de Peligro / Salir / Conceder**:
  - Borde y texto en carmesí apagado / bronce rojizo (`Color(0.65, 0.35, 0.35, 0.75)` / Hover `Color(0.95, 0.50, 0.50, 1.0)` con halo rojizo).

## 2. REGLA OBLIGATORIA DE FUNCIONALIDAD
- **100% de Botones Funcionales**: Todo botón debe tener su conexión `pressed` funcional, respuesta a clics, cursor `Control.CURSOR_POINTING_HAND`, navegación por teclado / `grab_focus()`, y tecla `ESC` para cerrar modales.
- **Sin botones placebo ni estilos rotos**: Jamás dejar botones sin conectar ni usar texturas desalineadas o fuentes genéricas del sistema.

## 3. REGLAS DE DESARROLLO Y WORKFLOW
- **NO TEST RUNS**: Nunca ejecutar tests CLI ni GUT sin permiso explícito del usuario.
- **GIT COMMITS**: Cada cambio funcional completado se commitea con un mensaje limpio en español o inglés siguiendo conventional commits.
- **COMUNICACIÓN**: Enlaces cliqueables en formato `file:///...` para todos los archivos modificados.

