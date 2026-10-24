# Sistema de Diseño UI — Mitos y Leyendas: Arena de Leyendas

Este documento establece la **regla de diseño mandatoria** para todas las interfaces de usuario del proyecto (menús principales, paneles de pausa, modales de configuración, selectores de mazo/cartas, inspección de cartas y avisos).

Toda interfaz debe seguir los principios visuales reflejados en `Configuracion.jpg` / `ControlsDialog.gd`.

---

## 1. Paleta de Colores y Superficies

| Elemento | Código Color | Representación en Godot | Propósito |
| :--- | :--- | :--- | :--- |
| **Fondo Modal** | `#121721` / `#0B0E14` | `Color(0.07, 0.09, 0.13, 0.96)` | Fondo del contenedor central / tarjeta |
| **Borde Dorado** | `#C7A652` | `Color(0.78, 0.65, 0.32, 0.90)` | Marco exterior medieval de 2px |
| **Separador** | `#C7A65259` | `Color(0.78, 0.65, 0.32, 0.35)` | Línea fina horizontal de 1px |
| **Sombra Panel** | `#000000D9` | `Color(0, 0, 0, 0.85)` | Sombra exterior `shadow_size = 28` |
| **Telón / Backdrop** | `#05080DF2` | `Color(0.02, 0.03, 0.05, 0.88)` | Oscurecimiento de pantalla completa |

---

## 2. Tipografía

1. **Títulos y Encabezados**:
   - Fuente: `res://assets/fonts/Cinzel-Bold.ttf`
   - Color principal: `Color(0.92, 0.80, 0.38, 1.0)` / `Color(0.96, 0.88, 0.60, 1.0)`
   - Sombra: `Color(0, 0, 0, 0.95)`, offset X=0/2, Y=2/3
2. **Subtítulos y Textos Secundarios**:
   - Fuente: `res://assets/fonts/Marcellus-Regular.ttf`
   - Color: `Color(0.65, 0.70, 0.80, 1.0)`
3. **Etiquetas de Botones**:
   - Fuente: `res://assets/fonts/Cinzel-Bold.ttf`
   - Tamaño: 13px a 17px según jerarquía
   - Alineación: Centrada

---

## 3. Botones y Estados Interactivos

### Botón Estándar (Acción Normal)
- **Normal**:
  - `bg_color = Color(0.12, 0.15, 0.22, 0.95)`
  - `border_color = Color(0.50, 0.45, 0.35, 0.80)`
  - `border_width = 1px` a `1.5px`
  - `corner_radius = 6px` a `8px`
  - `font_color = Color(0.96, 0.90, 0.75, 1.0)`
- **Hover**:
  - `bg_color = Color(0.18, 0.24, 0.34, 1.0)`
  - `border_color = Color(1.0, 0.88, 0.48, 1.0)` (borde oro radiante 2px)
  - `shadow_color = Color(0.88, 0.74, 0.28, 0.35)`, `shadow_size = 8`
  - `font_color = Color(1.0, 1.0, 1.0, 1.0)`
- **Pressed**:
  - `bg_color = Color(0.20, 0.17, 0.10, 0.98)`
  - `border_color = Color(0.88, 0.74, 0.28, 0.90)`
  - `border_width = 2px`

### Botón Primario (Acción Destacada, ej. "JUGAR")
- **Normal**:
  - `bg_color = Color(0.16, 0.14, 0.10, 0.96)`
  - `border_color = Color(0.88, 0.74, 0.28, 0.95)` (2px)
  - `font_color = Color(1.0, 0.92, 0.65, 1.0)`
- **Hover**:
  - `bg_color = Color(0.25, 0.21, 0.12, 1.0)`
  - `border_color = Color(1.0, 0.92, 0.55, 1.0)`
  - `shadow_color = Color(0.88, 0.74, 0.28, 0.45)`, `shadow_size = 10`
  - `font_color = Color.WHITE`

### Botón de Cancelar / Salir / Conceder
- **Normal**:
  - `bg_color = Color(0.14, 0.11, 0.13, 0.95)`
  - `border_color = Color(0.65, 0.35, 0.35, 0.75)`
  - `font_color = Color(0.95, 0.80, 0.80, 1.0)`
- **Hover**:
  - `bg_color = Color(0.22, 0.14, 0.16, 1.0)`
  - `border_color = Color(0.95, 0.50, 0.50, 1.0)`
  - `shadow_color = Color(0.80, 0.25, 0.25, 0.35)`, `shadow_size = 8`
  - `font_color = Color.WHITE`

---

## 4. Reglas Funcionales y de Accesibilidad

1. **Cursor del Ratón**: Todo botón debe tener `mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND`.
2. **Navegación por Teclado y Foco**: Los estilos `focus` deben heredar la apariencia de `hover` con borde dorado sutil, evitando el marco punteado por defecto de Godot.
3. **Manejo de Tecla Escape (`ESC`)**: Cualquier diálogo modal o popup debe implementar el cierre seguro mediante la tecla `ESC`.
4. **100% Funcionalidad**: Ningún botón puede ser un elemento decorativo sin acción asignada; todos deben estar conectados a señales o métodos reales del flujo de juego.

