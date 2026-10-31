extends Node
## Constantes del juego basadas en el DAR de Mitos y Leyendas
## Revisión Septiembre 2025 - Imperio

# =============================================================================
# LOGGING
# =============================================================================
# Los prints "[DIAG]" (gui_input de cada click, estado del botón ¿Paso? en cada cambio de prioridad,
# etc.) sirvieron para cazar bugs de la Guerra de Talismanes (arquitectura.md §12/§13.4/§13.6).
# Están apagados por defecto; poner esto en `true` para volver a verlos.
const VERBOSE_DIAG_LOGS: bool = false

# =============================================================================
# CONSTRUCCIÓN DE MAZO
# =============================================================================
const DECK_SIZE: int = 50
const MAX_COPIES_PER_CARD: int = 3
const MAX_COPIES_UNIQUE: int = 1

# =============================================================================
# MANO Y ROBO
# =============================================================================
const MAX_HAND_SIZE: int = 8
const CARDS_DRAWN_PER_TURN: int = 1

## Escala de las cartas de Oro en Reserva y Oro Pagado (0.88 = más presencia y legibilidad)
const GOLD_CARD_SCALE: Vector2 = Vector2(0.88, 0.88)

## Escala de los Tótems en la Línea de Apoyo (0.88 = más presencia y legibilidad que el 0.80 previo)
const TOTEM_CARD_SCALE: Vector2 = Vector2(0.88, 0.88)

## Desplazamiento vertical para Armas equipadas a un Aliado (asoman discretamente por abajo)
const WEAPON_OFFSET_Y: float = 48.0
const WEAPON_STACK_STEP_Y: float = 20.0

# =============================================================================
# TIPOS DE CARTA
# =============================================================================
enum CardType {
	ORO,
	ALIADO,
	ARMA,
	TALISMAN,
	TOTEM
}

const CARD_TYPE_NAMES: Dictionary = {
	CardType.ORO: "Oro",
	CardType.ALIADO: "Aliado",
	CardType.ARMA: "Arma",
	CardType.TALISMAN: "Talismán",
	CardType.TOTEM: "Tótem"
}

# =============================================================================
# ZONAS DE JUEGO
# =============================================================================
enum Zone {
	# Zonas dentro del juego (públicas)
	RESERVA_ORO,
	ORO_PAGADO,
	LINEA_DEFENSA,
	LINEA_ATAQUE,
	LINEA_APOYO,
	# Zonas fuera del juego
	CASTILLO,      # Privada (mazo)
	MANO,          # Privada
	CEMENTERIO,    # Pública
	DESTIERRO      # Pública
}

const ZONE_NAMES: Dictionary = {
	Zone.RESERVA_ORO: "Reserva de Oro",
	Zone.ORO_PAGADO: "Oro Pagado",
	Zone.LINEA_DEFENSA: "Línea de Defensa",
	Zone.LINEA_ATAQUE: "Línea de Ataque",
	Zone.LINEA_APOYO: "Línea de Apoyo",
	Zone.CASTILLO: "Castillo",
	Zone.MANO: "Mano",
	Zone.CEMENTERIO: "Cementerio",
	Zone.DESTIERRO: "Destierro"
}

# Zonas que están "en juego"
const ZONES_IN_PLAY: Array = [
	Zone.RESERVA_ORO,
	Zone.ORO_PAGADO,
	Zone.LINEA_DEFENSA,
	Zone.LINEA_ATAQUE,
	Zone.LINEA_APOYO
]


# =============================================================================
# FASES DEL TURNO (DAR Septiembre 2025 - Sección 5)
# =============================================================================
enum Phase {
	AGRUPACION,          # 5.1 - Aliados pasan a defensa, oros a reserva
	VIGILIA,             # 5.2 - Jugar cartas, poner oro, usar habilidades
	ATAQUE,              # 5.3.1 - Declarar atacantes
	BLOQUEO,             # 5.3.2 - Declarar bloqueadores
	GUERRA_TALISMANES,   # 5.3.3 - Jugar talismanes y habilidades de combate
	ASIGNACION_DANIO,    # 5.3.4 - Resolver daño de combate
	FINAL                # 5.4 - Robar carta, descartar exceso
}

const PHASE_NAMES: Dictionary = {
	Phase.AGRUPACION: "Fase de Agrupación",
	Phase.VIGILIA: "Fase de Vigilia",
	Phase.ATAQUE: "Paso de Ataque",
	Phase.BLOQUEO: "Paso de Bloqueo",
	Phase.GUERRA_TALISMANES: "Guerra de Talismanes",
	Phase.ASIGNACION_DANIO: "Asignación de Daño",
	Phase.FINAL: "Fase Final"
}


# =============================================================================
# HABILIDADES KEYWORD (DAR Sección 7-8)
# =============================================================================
enum Keyword {
	# Keywords reales de Mitos y Leyendas.
	FURIA,              # Puede atacar sin esperar Agrupación
	IMBLOQUEABLE,       # No puede ser bloqueado (sin excepción por keyword —
	                    # si algo puede bloquearlo, lo dice su propio texto)
	INDESTRUCTIBLE,     # No puede ser destruido
	INDESTERRABLE,      # No puede ser desterrado
	UNICA,              # Solo 1 copia en el mazo
	EXHUMAR,            # Puede jugarse desde Cementerio
	ERRANTE,            # Solo puede haber 1 copia de esta carta EN JUEGO a
	                    # la vez (a diferencia de Única, que limita el mazo)
	RETADOR,            # El atacante elige qué Aliado enemigo debe bloquearlo
}


# NOTA: "Inmune a X" y "portar múltiples armas" NO son keywords fijas en Mitos y Leyendas — son
# texto libre de cada carta ("no puede ser afectada por talismanes", "tus aliados pueden portar un
# arma adicional"). Se detectan por texto donde hace falta (ver TriggerSystem._target_text_denies y
# GoldManager._player_has_ally_in_play/lógica de Armas), no como Keyword.

# =============================================================================
# TIPOS DE HABILIDAD
# =============================================================================
enum AbilityType {
	ACTIVADA,      # Se puede usar a voluntad
	DISPARADA,     # Se dispara por un evento
	CONTINUA,      # Efecto permanente mientras está en juego
	CONSTRUCCION   # Afecta la construcción del mazo
}

# =============================================================================
# RAREZAS
# =============================================================================
enum Rarity {
	COMUN,
	POCO_COMUN,
	RARA,
	ULTRA_RARA,
	SECRETA
}


# =============================================================================
# SEÑALES GLOBALES (eventos del juego)
# =============================================================================
# Estas se usarán para el sistema de habilidades disparadas

