import bpy, os
OUT = "/Users/majorm/HMG/MaP/export/ladder"
def shoot(camname, fname):
    sc = bpy.context.scene; sc.camera = bpy.data.objects[camname]
    sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = 1600, 900, 100
    sc.render.image_settings.file_format = 'PNG'; sc.render.filepath = os.path.join(OUT, fname)
    for area in bpy.context.screen.areas:
        if area.type == 'VIEW_3D':
            sp = area.spaces.active; sp.region_3d.view_perspective = 'CAMERA'; sp.overlay.show_overlays = False; sp.shading.type = 'MATERIAL'
            region = [r for r in area.regions if r.type == 'WINDOW'][0]
            with bpy.context.temp_override(area=area, region=region):
                bpy.ops.render.opengl(write_still=True, view_context=True)
            break
