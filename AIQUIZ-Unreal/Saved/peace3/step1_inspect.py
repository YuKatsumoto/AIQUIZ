import unreal, json, traceback

OUT = r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3/result_step1.json"
res = {"ok": False}


def vec_to_list(v):
    try:
        return [round(v.x, 3), round(v.y, 3), round(v.z, 3)]
    except Exception:
        return None


try:
    info = {}
    info["engine_version"] = unreal.SystemLibrary.get_engine_version()

    les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)

    # Current level / world
    try:
        world = ues.get_editor_world()
        info["world"] = world.get_path_name() if world else None
    except Exception as e:
        info["world_err"] = str(e)

    # Viewport camera
    try:
        cam_loc, cam_rot = ues.get_level_viewport_camera_info()
        info["viewport_camera"] = {"loc": vec_to_list(cam_loc),
                                   "rot": [round(cam_rot.roll, 2), round(cam_rot.pitch, 2), round(cam_rot.yaw, 2)]}
    except Exception as e:
        info["viewport_camera_err"] = str(e)

    actors = eas.get_all_level_actors()
    info["actor_count"] = len(actors)
    alist = []
    for a in actors:
        entry = {
            "name": a.get_actor_label(),
            "class": a.get_class().get_name(),
            "loc": vec_to_list(a.get_actor_location()),
            "rot": None,
            "scale": vec_to_list(a.get_actor_scale3d()),
        }
        try:
            r = a.get_actor_rotation()
            entry["rot"] = [round(r.roll, 2), round(r.pitch, 2), round(r.yaw, 2)]
        except Exception:
            pass

        # Static mesh details
        smc = a.get_component_by_class(unreal.StaticMeshComponent)
        if smc:
            sm = smc.static_mesh
            if sm:
                entry["mesh"] = sm.get_path_name()
                try:
                    b = sm.get_bounds()  # may not exist; fallback below
                except Exception:
                    b = None
                try:
                    bb = sm.get_bounding_box()
                    entry["mesh_bounds"] = {"min": vec_to_list(bb.min), "max": vec_to_list(bb.max)}
                except Exception as e:
                    entry["mesh_bounds_err"] = str(e)
            mats = []
            try:
                for i in range(smc.get_num_materials()):
                    m = smc.get_material(i)
                    mats.append(m.get_path_name() if m else None)
            except Exception as e:
                entry["mat_err"] = str(e)
            entry["materials"] = mats

        # Light details
        if isinstance(a, unreal.DirectionalLight):
            entry["is_directional_light"] = True

        alist.append(entry)
    info["actors"] = alist

    # Asset existence checks
    eal = unreal.EditorAssetLibrary
    assets_to_check = [
        "/Game/AiQuiz/Materials/M_ConveyorFloor",
        "/Game/AiQuiz/Materials/M_Magma",
        "/Game/AiQuiz/Maps/L_Game",
    ]
    info["assets"] = {p: eal.does_asset_exist(p) for p in assets_to_check}

    # Inspect M_ConveyorFloor material params (if it's a UMaterial)
    try:
        mat = eal.load_asset("/Game/AiQuiz/Materials/M_ConveyorFloor")
        mi = {"class": mat.get_class().get_name() if mat else None}
        if mat:
            try:
                mi["scalar_params"] = list(unreal.MaterialEditingLibrary.get_scalar_parameter_names(mat))
            except Exception as e:
                mi["scalar_params_err"] = str(e)
            try:
                mi["vector_params"] = list(unreal.MaterialEditingLibrary.get_vector_parameter_names(mat))
            except Exception as e:
                mi["vector_params_err"] = str(e)
        info["M_ConveyorFloor"] = mi
    except Exception as e:
        info["M_ConveyorFloor_err"] = str(e)

    # List assets under /Game/AiQuiz/Materials and /Game/AiQuiz/Maps
    try:
        info["materials_dir"] = list(eal.list_assets("/Game/AiQuiz/Materials", recursive=True, include_folder=False))
    except Exception as e:
        info["materials_dir_err"] = str(e)

    res = {"ok": True, "info": info}
except Exception as e:
    res = {"ok": False, "err": str(e), "tb": traceback.format_exc()}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=2)

unreal.log("PEACE3_STEP1_DONE ok=%s" % res.get("ok"))
