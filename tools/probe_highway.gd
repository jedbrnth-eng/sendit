# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

extends SceneTree
## Debug probe: build the highway around z=0 and report what exists.

func _init() -> void:
	var h := Highway.new()
	root.add_child(h)
	await process_frame
	h.update_stream(0.0)
	print("chunks: ", h.chunks.keys())
	for k in h.chunks:
		var c: Node3D = h.chunks[k]
		print(k, " pos=", c.position, " children=", c.get_child_count(), " inside_tree=", c.is_inside_tree(), " visible=", c.is_visible_in_tree())
		break
	quit()
