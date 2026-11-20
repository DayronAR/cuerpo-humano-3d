class_name GestorCapas
extends Node
## Retira y restaura capas (sistemas) del cuerpo con animación, una por una.
##
## Cada capa tiene un "progreso" entre 0 (en su sitio) y 1 (retirada). Las animaciones solo
## cambian ese número con un Tween, y _aplicar() traduce el progreso a posición, escala y
## transparencia de cada pieza. Así una animación se puede interrumpir en cualquier momento y
## la siguiente arranca desde donde quedó.
##
## Modo normal:   la pieza se aleja del eje del cuerpo, se encoge y se desvanece hasta ocultarse.
## Modo fantasma: la pieza queda en su sitio, semitransparente.
##
## Transparencia: al empezar a desvanecerse, cada superficie recibe una COPIA de su material con
## transparencia alfa (no se tocan los materiales originales, que pueden estar compartidos).
## Al restaurarse por completo se devuelve el material original, opaco y más barato de dibujar.
##
## No sabe nada de colisiones ni de la interfaz: avisa con señales y el BodyViewer reacciona.

signal capa_retirada(id_sistema: String)      ## La capa dejó de estar completa (ya no se puede seleccionar)
signal capa_restaurada(id_sistema: String)    ## La capa volvió por completo a su sitio
signal secuencia_terminada

## Estado de animación de una capa (un sistema completo)
class Capa:
	var id := ""
	var piezas: Array[Pieza] = []
	var progreso := 0.0     ## Valor actual (0 = en su sitio, 1 = retirada)
	var destino := 0.0      ## Valor hacia el que se está animando
	var retirada := false   ## Último estado avisado por señal
	var tween: Tween
	var fantasma_propio := -1.0     ## >= 0: esta capa queda fantasma con esa transparencia (la pide un escenario)
	var desplazamiento_actual := 0.0
	var escala_actual := 1.0

## Una parte que se mueve como bloque: un órgano o una parte de un órgano compuesto
class Pieza:
	var nodo: Node3D
	var id_capa := ""                    ## (id y no referencia: evita un ciclo Capa <-> Pieza que no se libera)
	var escala_extra := Vector3.ONE      ## Escala adicional (latido, respiración) que piden las visualizaciones
	var transform_original: Transform3D
	var pivote := Vector3.ZERO           ## Centro de la pieza en el espacio del padre
	var direccion := Vector3.ZERO        ## Hacia dónde se aleja, en el espacio del padre
	var usar_vista := false              ## true si está sobre el eje del cuerpo: se aleja hacia la cámara
	var mallas: Array[MeshInstance3D] = []
	var sombras: Array[int] = []
	var materiales_originales: Array = []   ## Por malla: Array de materiales override originales
	var materiales_transparentes: Array = [] ## Por malla: Array de copias transparentes (o vacío)

var _capas: Dictionary = {}       ## id -> Capa
var _piezas_por_nodo: Dictionary = {}   ## Node3D -> Pieza
var _orden: Array = []            ## ids de afuera hacia adentro
var _camara: Camera3D
var _generacion := 0              ## Se incrementa en cada secuencia nueva para cancelar la anterior
var _mezcla_fantasma := 0.0       ## 0 = modo normal, 1 = modo fantasma (se anima para cambiar suave)
var _tween_fantasma: Tween

# Parámetros (vienen de Datos.animacion_capas)
var _duracion := 0.45
var _pausa := 0.06
var _desplazamiento := 0.12
var _escala_final := 0.82
var _transparencia_fantasma := 0.82
var _duracion_fantasma := 0.3


## sistemas: id -> Node3D del sistema. eje: punto del eje vertical del cuerpo (mundo).
func configurar(sistemas: Dictionary, orden: Array, cfg: Dictionary, camara: Camera3D, eje: Vector3) -> void:
	_orden = orden
	_camara = camara
	_duracion = cfg.get("duracion", _duracion)
	_pausa = cfg.get("pausa_entre_capas", _pausa)
	_desplazamiento = cfg.get("desplazamiento", _desplazamiento)
	_escala_final = cfg.get("escala_final", _escala_final)
	_transparencia_fantasma = cfg.get("transparencia_fantasma", _transparencia_fantasma)
	_duracion_fantasma = cfg.get("duracion_cambio_fantasma", _duracion_fantasma)
	for id in sistemas:
		var capa := Capa.new()
		capa.id = id
		for organo in sistemas[id].get_children():
			var nodos := []
			if organo is MeshInstance3D:
				nodos = [organo]
			elif organo is Node3D:
				nodos = organo.get_children().filter(func(n): return n is Node3D)
			for n in nodos:
				var pieza := _crear_pieza(n, eje)
				pieza.id_capa = id
				capa.piezas.append(pieza)
				_piezas_por_nodo[n] = pieza
		_capas[id] = capa


## Deja retiradas exactamente las capas indicadas (y restaura las demás), con animación en secuencia.
## fantasmas: id -> transparencia (0-1) de capas que quedan semitransparentes en su sitio
## aunque el modo fantasma global esté apagado (lo usan los escenarios).
## simultaneas: capas que se retiran todas juntas al final (sin ir una por una), p. ej. los
## sistemas que quedan dentro del sistema elegido.
func retirar_solo(ids_retirar: Array, fantasmas: Dictionary = {}, simultaneas: Array = []) -> void:
	_generacion += 1
	var generacion := _generacion
	var ids := ids_retirar.duplicate()
	for id in fantasmas:
		if _capas.has(id) and not id in ids:
			ids.append(id)
	for id in ids:
		if not _capas.has(id):
			continue
		var capa: Capa = _capas[id]
		var nuevo: float = fantasmas.get(id, -1.0)
		if nuevo != capa.fantasma_propio:
			capa.fantasma_propio = nuevo
			if capa.progreso > 0.0:
				_aplicar(capa.progreso, capa)   # Cambio de modo en una capa ya retirada
	# Restaurar primero, de adentro hacia afuera
	var restaurar := _ordenados(_capas.keys().filter(func(id): return _capas[id].destino > 0.0 and not id in ids))
	restaurar.reverse()
	# Luego retirar, de afuera hacia adentro
	var retirar := _ordenados(ids.filter(func(id): return _capas.has(id) and _capas[id].destino < 1.0))

	# Las capas que se retiran de verdad van una por una; las de contexto (fantasma) se
	# desvanecen todas juntas al final, para no alargar la secuencia.
	var de_contexto := retirar.filter(func(id): return fantasmas.has(id) or id in simultaneas)
	var en_orden := restaurar + retirar.filter(func(id): return not de_contexto.has(id))
	for id in en_orden:
		var destino := 0.0 if id in restaurar else 1.0
		var duracion := _animar(_capas[id], destino)
		await get_tree().create_timer(duracion + _pausa).timeout
		if generacion != _generacion:
			return   # Otra secuencia empezó mientras tanto: esta se abandona
	var mayor := 0.0
	for id in de_contexto:
		mayor = maxf(mayor, _animar(_capas[id], 1.0))
	if mayor > 0.0:
		await get_tree().create_timer(mayor).timeout
		if generacion != _generacion:
			return
	secuencia_terminada.emit()


func restaurar_todo() -> void:
	retirar_solo([])


## Escala adicional de una pieza (en su espacio local), compatible con la animación de capas.
func fijar_escala_extra(nodo: Node3D, escala: Vector3) -> void:
	var pieza: Pieza = _piezas_por_nodo.get(nodo)
	if pieza == null:
		return
	pieza.escala_extra = escala
	_transformar(pieza)


func capas_retiradas() -> Array:
	return _capas.keys().filter(func(id): return _capas[id].destino > 0.0)


func establecer_modo_fantasma(activo: bool) -> void:
	if _tween_fantasma and _tween_fantasma.is_valid():
		_tween_fantasma.kill()
	_tween_fantasma = create_tween()
	_tween_fantasma.tween_method(_cambiar_mezcla_fantasma, _mezcla_fantasma, 1.0 if activo else 0.0,
			_duracion_fantasma)


# --- Animación -----------------------------------------------------------------

## Inicia la animación de una capa hacia el destino. Devuelve su duración (0 si no hace falta).
func _animar(capa: Capa, destino: float) -> float:
	if capa.tween and capa.tween.is_valid():
		capa.tween.kill()
	capa.destino = destino
	var duracion := _duracion * absf(destino - capa.progreso)
	if duracion <= 0.001:
		_aplicar(destino, capa)
		return 0.0
	capa.tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	capa.tween.tween_method(_aplicar.bind(capa), capa.progreso, destino, duracion)
	return duracion


func _cambiar_mezcla_fantasma(valor: float) -> void:
	_mezcla_fantasma = valor
	for capa in _capas.values():
		if capa.progreso > 0.0:
			_aplicar(capa.progreso, capa)


## Traduce el progreso de una capa a transformaciones y transparencia de sus piezas.
func _aplicar(progreso: float, capa: Capa) -> void:
	capa.progreso = progreso
	var mezcla := 1.0 if capa.fantasma_propio >= 0.0 else _mezcla_fantasma
	var transparencia_fantasma := capa.fantasma_propio if capa.fantasma_propio >= 0.0 else _transparencia_fantasma
	var normal := 1.0 - mezcla
	capa.desplazamiento_actual = progreso * _desplazamiento * normal
	capa.escala_actual = lerpf(1.0, _escala_final, progreso * normal)
	var transparencia := lerpf(progreso, progreso * transparencia_fantasma, mezcla)
	var oculta := progreso >= 0.999 and normal >= 0.999

	for pieza in capa.piezas:
		_transformar(pieza)
		pieza.nodo.visible = not oculta
		for i in pieza.mallas.size():
			_fijar_transparencia(pieza, i, transparencia)
			# Las piezas semitransparentes no proyectan sombra (evita sombras "fantasma")
			pieza.mallas[i].cast_shadow = pieza.sombras[i] if progreso <= 0.0 \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var retirada := progreso > 0.0
	if retirada != capa.retirada:
		capa.retirada = retirada
		if retirada:
			capa_retirada.emit(capa.id)
		else:
			capa_restaurada.emit(capa.id)


## Posición final de una pieza: transform original (con su escala extra), encogida alrededor de
## su centro y desplazada hacia afuera según el estado de su capa.
func _transformar(pieza: Pieza) -> void:
	var capa: Capa = _capas[pieza.id_capa]
	var escala := capa.escala_actual
	var direccion := pieza.direccion
	if pieza.usar_vista and _camara:
		direccion = _direccion_vista(pieza)
	var ajuste := Transform3D(Basis.from_scale(Vector3.ONE * escala),
			pieza.pivote - pieza.pivote * escala + direccion * capa.desplazamiento_actual)
	pieza.nodo.transform = ajuste * pieza.transform_original.scaled_local(pieza.escala_extra)


## Aplica la transparencia (0 = opaco, 1 = invisible) a todas las superficies de una malla.
func _fijar_transparencia(pieza: Pieza, indice: int, transparencia: float) -> void:
	var malla := pieza.mallas[indice]
	var originales: Array = pieza.materiales_originales[indice]
	if transparencia <= 0.0:
		# Volver a los materiales originales (opacos)
		for s in originales.size():
			malla.set_surface_override_material(s, originales[s])
		return
	var copias: Array = pieza.materiales_transparentes[indice]
	if copias.is_empty():
		for s in originales.size():
			var base := malla.get_active_material(s)
			var copia: Material = null
			if base is BaseMaterial3D:
				copia = base.duplicate()
				copia.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
				copia.set_meta("alfa_original", base.albedo_color.a)
			copias.append(copia)
	for s in copias.size():
		var copia: Material = copias[s]
		if copia == null:
			continue   # Material de shader propio: no se puede desvanecer de esta forma
		var color: Color = copia.albedo_color
		color.a = copia.get_meta("alfa_original") * (1.0 - transparencia)
		copia.albedo_color = color
		malla.set_surface_override_material(s, copia)


# --- Preparación ------------------------------------------------------------------

func _crear_pieza(nodo: Node3D, eje: Vector3) -> Pieza:
	var pieza := Pieza.new()
	pieza.nodo = nodo
	pieza.transform_original = nodo.transform
	pieza.mallas = BodyViewer.mallas_de(nodo)
	for m in pieza.mallas:
		pieza.sombras.append(m.cast_shadow)
		var originales := []
		for s in m.get_surface_override_material_count():
			originales.append(m.get_surface_override_material(s))
		pieza.materiales_originales.append(originales)
		pieza.materiales_transparentes.append([])

	var padre := nodo.get_parent() as Node3D
	var aabb := _aabb_en(nodo, padre)
	pieza.pivote = aabb.get_center()
	var centro_mundo := padre.global_transform * pieza.pivote
	var horizontal := Vector3(centro_mundo.x - eje.x, 0.0, centro_mundo.z - eje.z)
	if horizontal.length() < 0.04:
		pieza.usar_vista = true   # Pieza centrada en el eje (p. ej. el torso): se aleja hacia la cámara
	else:
		pieza.direccion = (padre.global_basis.inverse() * horizontal.normalized()).normalized()
	return pieza


func _direccion_vista(pieza: Pieza) -> Vector3:
	var padre := pieza.nodo.get_parent() as Node3D
	var hacia_camara: Vector3 = _camara.global_position - padre.global_transform * pieza.pivote
	hacia_camara.y = 0.0
	if hacia_camara.length() < 0.001:
		return Vector3.ZERO
	return (padre.global_basis.inverse() * hacia_camara.normalized()).normalized()


## Caja envolvente de todas las mallas de un nodo, expresada en el espacio de "referencia".
static func _aabb_en(nodo: Node3D, referencia: Node3D) -> AABB:
	var inversa := referencia.global_transform.affine_inverse()
	var resultado := AABB()
	var primero := true
	for malla in BodyViewer.mallas_de(nodo):
		var caja: AABB = (inversa * malla.global_transform) * malla.get_aabb()
		resultado = caja if primero else resultado.merge(caja)
		primero = false
	return resultado


func _ordenados(ids: Array) -> Array:
	var resultado := ids.duplicate()
	resultado.sort_custom(func(a, b): return _orden.find(a) < _orden.find(b))
	return resultado
