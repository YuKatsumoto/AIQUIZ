extends RefCounted

## Where the KEY=VALUE settings file (.env) is read from. Shared by GameManager._load_env and
## ApiStatus._load_env so both always read the same file.
##   1. Desktop exports: `.env` next to the executable (lets a build be re-pointed without
##      re-exporting). Skipped on Android and iOS: there the executable path is the app's
##      native library, not a folder anyone can put a file in.
##   2. `res://.env` (editor runs, and exports that pack it).
##   3. `res://config/app_env.cfg`: the same file under a name without a leading dot, for
##      exports whose filters drop dot files. Same KEY=VALUE format.

const RES_ENV_PATH := "res://.env"
const RES_ENV_COPY_PATH := "res://config/app_env.cfg"


## The first settings file that exists, or "" when there is none.
static func resolve_path() -> String:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		var external_env := OS.get_executable_path().get_base_dir().path_join(".env")
		if FileAccess.file_exists(external_env):
			return external_env
	if FileAccess.file_exists(RES_ENV_PATH):
		return RES_ENV_PATH
	if FileAccess.file_exists(RES_ENV_COPY_PATH):
		return RES_ENV_COPY_PATH
	return ""
