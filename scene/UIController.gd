extends Node

@export var Grid:Node

@onready var InfoPanel: PanelContainer = $InfoPanel
@onready var ToolPanel: PanelContainer = $ToolPanel
@onready var LoadingPanel: PanelContainer = $LoadingPanel
@onready var MsgPanel: PanelContainer = $MessagePanel
@onready var MsgLabel: Label = $MessagePanel/MarginContainer/Label
@onready var Row: VBoxContainer = $InfoPanel/MarginContainer/Row
@onready var CbWireframe: CheckBox = $ToolPanel/MarginContainer/Row/CbWireframe
@onready var CbExplode: CheckBox = $ToolPanel/MarginContainer/Row/CbExplode
@onready var CbHideGrid: CheckBox = $ToolPanel/MarginContainer/Row/CbHideGrid

const TextureViewer = preload("res://scene/TextureViewer.tscn")
var texViewer

const MaterialViewer = preload("res://scene/MaterialViewer.tscn")
var matViewer

var animationPlayers: Array[Node]

const DYNAMIC_CONTROL_GROUP = "dynamic control"

var maxAabb:AABB

class MeshInfo:
	var name:String
	var faceCount:int
	var mesh:MeshInstance3D

func _ready():
	GlobalSignal.trigger_texture_viewer.connect(_show_texture_viewer)

func _process(_delta):
	if Input.is_action_just_pressed("toggle_wireframe"):
		CbWireframe.button_pressed = not CbWireframe.button_pressed

	if Input.is_action_just_pressed("explode_meshes"):
		CbExplode.button_pressed = not CbExplode.button_pressed

	if Input.is_action_just_pressed("toggle_grid"):
		CbHideGrid.button_pressed = not CbHideGrid.button_pressed

func _on_root_gltf_start_to_load():
	InfoPanel.visible = false
	ToolPanel.visible = false
	MsgPanel.visible = false
	LoadingPanel.visible = true

	var dyna_controls = get_tree().get_nodes_in_group(DYNAMIC_CONTROL_GROUP)
	for ctl in dyna_controls:
		ctl.queue_free()

func _on_root_gltf_is_loaded(success, gltf : Node):
	if not success:
		MsgLabel.text = "Failed to load model..."
		MsgPanel.visible = true
		return

	InfoPanel.visible = true
	ToolPanel.visible = true
	LoadingPanel.visible = false

	animationPlayers = gltf.find_children("*", "AnimationPlayer")

	var meshes:Array[Node] = gltf.find_children("*", "MeshInstance3D")

	if meshes.size() > 0:
		# Create tree panel
		var meshInfoTree:Tree = Tree.new()
		meshInfoTree.add_to_group(DYNAMIC_CONTROL_GROUP)
		meshInfoTree.columns = 1
		meshInfoTree.column_titles_visible = true
		meshInfoTree.hide_root = true
		meshInfoTree.mouse_filter = Control.MOUSE_FILTER_PASS
		meshInfoTree.size_flags_vertical = Control.SIZE_EXPAND_FILL

		meshInfoTree.item_activated.connect(_on_mesh_item_double_clicked.bind(meshInfoTree))

		meshInfoTree.set_column_title(0, "Mesh (%d)" % meshes.size())

		var meshParent:TreeItem = meshInfoTree.create_item()

		# Mesh section
		var meshArray:Array[MeshInfo]
		
		const MAX_NAME_LENGTH = 20
		for mesh in meshes:
			mesh = mesh as MeshInstance3D

			# Calculate max aabb
			var aabb = mesh.mesh.get_aabb()
			if maxAabb.position > aabb.position:
				maxAabb.position = aabb.position
			if maxAabb.end < aabb.end:
				maxAabb.end = aabb.end

			var short_name = String(mesh.name)

			if short_name.length() > MAX_NAME_LENGTH:
				short_name = short_name.substr(0, MAX_NAME_LENGTH) + "..."

			var meshItem:TreeItem = meshInfoTree.create_item(meshParent)

			meshItem.set_text(0, short_name)
			meshItem.set_tooltip_text(0, mesh.name)
			meshItem.set_metadata(0, mesh)

		Row.add_child(meshInfoTree)
		
		var material_array: Array[Material]
		var texture_array: Array[Variant]
			
		var add_texture_to_array = func(texture):
			if texture != null and not texture_array.has(texture):
				texture_array.append(texture)

		for mesh in meshes:
			for si in mesh.mesh.get_surface_count():
				var mat = mesh.get_active_material(si) as Material
				if not material_array.has(mat):
					material_array.append(mat)

				if mat is BaseMaterial3D:
					# Gather texture
					add_texture_to_array.call(mat.albedo_texture)
					add_texture_to_array.call(mat.roughness_texture)
					add_texture_to_array.call(mat.metallic_texture)
					add_texture_to_array.call(mat.emission_texture)
					add_texture_to_array.call(mat.heightmap_texture)
					add_texture_to_array.call(mat.ao_texture)
					add_texture_to_array.call(mat.rim_texture)
					add_texture_to_array.call(mat.refraction_texture)
					add_texture_to_array.call(mat.heightmap_texture)
					add_texture_to_array.call(mat.normal_texture)
					add_texture_to_array.call(mat.clearcoat_texture)
					add_texture_to_array.call(mat.subsurf_scatter_texture)
				elif mat is ShaderMaterial:
					var parameters : Array[String] = [
						"_MainTex",
						"_ShadeTexture",
						"_ReceiveShadowTexture",
						"_ShadingGradeTexture",
						"_RimTexture",
						"_SphereAdd",
						"_EmissionMap",
					]
					for parameter_name in parameters:
						var parameter = (mat as ShaderMaterial).get_shader_parameter(parameter_name)
						add_texture_to_array.call(parameter)

		# Material section
		if material_array.size() > 0:
			var materialInfoTree:Tree = Tree.new()
			materialInfoTree.add_to_group(DYNAMIC_CONTROL_GROUP)
			materialInfoTree.columns = 1
			materialInfoTree.column_titles_visible = true
			materialInfoTree.hide_root = true
			materialInfoTree.mouse_filter = Control.MOUSE_FILTER_PASS
			materialInfoTree.size_flags_vertical = Control.SIZE_EXPAND_FILL

			materialInfoTree.item_activated.connect(_on_material_item_double_clicked.bind(materialInfoTree))

			materialInfoTree.set_column_title(0, "Material (%d)" % material_array.size())

			var matParent:TreeItem = materialInfoTree.create_item()

			for mat in material_array:
				var matItem:TreeItem = materialInfoTree.create_item(matParent)
				matItem.set_text(0, mat.resource_name)
				matItem.set_metadata(0, mat)

				if mat is StandardMaterial3D:
					var img:Image
					if mat.albedo_texture != null:
						matItem.set_text(0, mat.resource_name)

						img = mat.albedo_texture.get_image()
						img.resize(32, 32)
					else:
						img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
						img.fill(mat.albedo_color)

					matItem.set_icon(0, ImageTexture.create_from_image(img))
				elif mat is ShaderMaterial:
					var parameters : Array[String] = [
						"_MainTex",
						"_ShadeTexture",
						"_ReceiveShadowTexture",
						"_ShadingGradeTexture",
						"_RimTexture",
						"_SphereAdd",
						"_EmissionMap",
					]
					var img:Image
					for parameter_name in parameters:
						var parameter : Variant = (mat as ShaderMaterial).get_shader_parameter(parameter_name)
						if parameter is Image and parameter_name == "_MainTex":
							matItem.set_text(0, parameter_name.trim_prefix("_").capitalize())
							img = mat.albedo_texture.get_image()
							img.resize(32, 32)
						elif parameter is Image:
							img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
							img.fill(parameter)
					matItem.set_icon(0, ImageTexture.create_from_image(img))

			Row.add_child(materialInfoTree)

		# Texture section
		if texture_array.size() > 0:
			var textureInfoTree:Tree = Tree.new()
			textureInfoTree.add_to_group(DYNAMIC_CONTROL_GROUP)
			textureInfoTree.columns = 1
			textureInfoTree.column_titles_visible = true
			textureInfoTree.hide_root = true
			textureInfoTree.mouse_filter = Control.MOUSE_FILTER_PASS
			textureInfoTree.size_flags_vertical = Control.SIZE_EXPAND_FILL

			textureInfoTree.item_activated.connect(_on_texture_double_clicked.bind(textureInfoTree))

			textureInfoTree.set_column_title(0, "Texture (%d)" % texture_array.size())

			var texParent = textureInfoTree.create_item()

			for tex in texture_array:
				if tex is Texture2D:
					var img = (tex as Texture2D).get_image()
					img.resize(50, 50)

					var texItem:TreeItem = textureInfoTree.create_item(texParent)
					texItem.set_icon(0, ImageTexture.create_from_image(img))
					texItem.set_text(0, "[%d x %d] %s" % [tex.get_width(), tex.get_height(), calc_data_size(tex.get_image().get_data().size())])
					texItem.set_metadata(0, tex)
				elif tex is Image:
					var img : Image = tex
					img.resize(50, 50)

					var texItem:TreeItem = textureInfoTree.create_item(texParent)
					texItem.set_icon(0, ImageTexture.create_from_image(img))
					texItem.set_text(0, "[%d x %d] %s" % [tex.get_width(), tex.get_height(), calc_data_size(tex.get_image().get_data().size())])
					texItem.set_metadata(0, tex)
				


			Row.add_child(textureInfoTree)

	for animationPlayer in animationPlayers:
		if animationPlayer == null:
			continue
		var animationArray:Array[Array]

		var animLibList:Array[StringName] = animationPlayer.get_animation_library_list()
		for animLibName in animLibList:
			var animLib:AnimationLibrary = animationPlayer.get_animation_library(animLibName)
			var animList:Array[StringName] = animLib.get_animation_list()
			for animName in animList:
				if String(animLibName).is_empty():
					animationArray.append([String(animName), animationPlayer])
				else:
					animationArray.append(["%s/%s" % [animLibName, animName], animationPlayer])

		if animationArray.size() > 0:
			var animationTree:Tree = Tree.new()
			animationTree.add_to_group(DYNAMIC_CONTROL_GROUP)
			animationTree.columns = 2
			animationTree.column_titles_visible = true
			animationTree.hide_root = true
			animationTree.mouse_filter = Control.MOUSE_FILTER_PASS
			animationTree.size_flags_vertical = Control.SIZE_EXPAND_FILL

			animationTree.item_activated.connect(_on_animation_item_double_clicked.bind(animationTree))

			animationTree.set_column_title(0, "Animation (%d)" % animationArray.size())
			animationTree.select_mode = Tree.SELECT_ROW

			var animRoot = animationTree.create_item()

			for anim in animationArray:
				var animItem:TreeItem = animationTree.create_item(animRoot)
				animItem.set_text(0, anim[0])
				animItem.set_metadata(1, anim)

			Row.add_child(animationTree)

	# Create convex collision
	for mesh in meshes:
		mesh = mesh as MeshInstance3D
		mesh.create_convex_collision()

		var staticBody:StaticBody3D = mesh.find_child("%s_col" % mesh.name)
		staticBody.mouse_entered.connect(_on_mesh_mouse_entered.bind(mesh))
		staticBody.mouse_exited.connect(_on_mesh_mouse_exited.bind(mesh))

func calc_data_size(byte_size:int) -> String:
	var unit = "KB"

	# KB
	var size = byte_size / 1024.0

	# MB
	if size > 1024:
		size /= 1024.0
		unit = "MB"

	# GB
	if size > 1024:
		size /= 1024.0
		unit = "GB"

	return "%.2f %s" % [size, unit]

func _on_cb_wireframe_toggled(button_pressed):
	if button_pressed:
		get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	else:
		get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED

func _on_mesh_item_double_clicked(tree:Tree):
	var meshItem:TreeItem = tree.get_selected()
	var mesh:MeshInstance3D = meshItem.get_metadata(0)
	if mesh != null:
#		var uvLines = MeshExt.draw_uv_texture(mesh.mesh)
#		if uvLines.size() > 0:
#			GlobalSignal.trigger_texture_viewer.emit(uvLines)

		GlobalSignal.reposition_camera.emit(mesh.mesh.get_aabb())

func _on_material_item_double_clicked(tree:Tree):
	var matItem:TreeItem = tree.get_selected()
	var mat:Material = matItem.get_metadata(0)
	if mat != null and mat is Material:
		if matViewer != null:
			matViewer.queue_free()

		matViewer = MaterialViewer.instantiate()
		matViewer.set_material_view(mat)
		add_child(matViewer)

func _on_texture_double_clicked(tree:Tree):
	var texItem:TreeItem = tree.get_selected()
	var tex:Texture2D = texItem.get_metadata(0)
	if tex != null:
		GlobalSignal.trigger_texture_viewer.emit(tex)

func _on_animation_item_double_clicked(tree:Tree):
	var animItem:TreeItem = tree.get_selected()
	var anim:String = animItem.get_text(0)
	var animationPlayer:AnimationPlayer = animItem.get_metadata(1)[1]
	if animationPlayer != null and animationPlayer.has_animation(anim):
		var player : AnimationPlayer = animationPlayer
		var callable : Callable = Callable(self, "_on_animation_item_finished")
		callable = callable.bind(player, animationPlayers)
		if not player.animation_finished.is_connected(callable):
			player.animation_finished.connect(callable)
		player.queue(anim)


func _on_animation_item_finished(animation_name : StringName, player : AnimationPlayer, players : Array[Node]):
	for animationPlayer in animationPlayers:
		if animationPlayer == null:
			continue
		for animation in (animationPlayer as AnimationPlayer).get_animation_list():
			animationPlayer.assigned_animation = animation
			animationPlayer.seek(0)
			animationPlayer.advance(0)
	player.assigned_animation = animation_name

func _show_texture_viewer(tex):
	if texViewer != null:
		texViewer.queue_free()

	texViewer = TextureViewer.instantiate()
	texViewer.set_draw_data(tex)
	add_child(texViewer)


func _on_cb_explode_toggled(button_pressed):
	var nodes = get_tree().get_nodes_in_group(GlobalSignal.GLTF_GROUP)

	for n in nodes:
		var meshes:Array[Node] = n.find_children("*", "MeshInstance3D")
		for m in meshes:
			m = m as MeshInstance3D

			if button_pressed:
				m.position = m.mesh.get_aabb().get_center() - maxAabb.get_center()
			else:
				m.position = Vector3.ZERO


func _on_cb_hide_grid_toggled(button_pressed):
	if Grid != null:
		Grid.visible = not button_pressed

func _on_mesh_mouse_entered(mesh: MeshInstance3D):
	MeshExt.mesh_create_outline(mesh)
	
func _on_mesh_mouse_exited(mesh: MeshInstance3D):
	MeshExt.mesh_remove_outline(mesh)
