class_name CoreRegistry
extends RefCounted
## The libretro cores VRT ships, and how content is matched to them.
##
## Content is matched by folder name first (so ambiguous extensions like .bin,
## .iso or .chd go to the right core), then by extension alone when only one
## core claims it. Folder names are compared lowercased.

const CORES := {
	"fceumm": {
		"system": "NES",
		"exts": ["nes", "fds", "unf", "unif"],
		"folders": ["nes", "famicom", "fds"],
	},
	"snes9x": {
		"system": "SNES",
		"exts": ["sfc", "smc", "swc", "fig", "bs"],
		"folders": ["snes", "super nintendo", "super famicom", "sfc"],
	},
	"genesis_plus_gx": {
		"system": "Sega",
		"exts": ["md", "gen", "smd", "bin", "sms", "gg", "sg", "68k", "cue", "chd", "iso"],
		"folders": ["genesis", "mega drive", "megadrive", "master system", "game gear", "sg-1000", "sega cd", "mega cd"],
	},
	"mednafen_pce_fast": {
		"system": "PC Engine",
		"exts": ["pce", "sgx", "cue", "ccd", "chd"],
		"folders": ["pce", "pc engine", "turbografx-16", "turbografx", "tg16", "pce-cd"],
	},
	"deevee": {
		"system": "DVD",
		"exts": ["iso", "ifo", "img", "chd"],
		"folders": ["video", "dvd", "movies"],
	},
}


## Core for a folder name, or "" if no core claims it.
static func core_for_folder(folder: String) -> String:
	var f := folder.to_lower()
	for core in CORES:
		if f in CORES[core].folders:
			return core
	return ""


## Core for a file, using its folder as the tie-breaker. "" if unknown.
static func core_for_file(path: String, folder_core: String = "") -> String:
	var ext := path.get_extension().to_lower()
	if folder_core != "" and ext in CORES[folder_core].exts:
		return folder_core
	var found := ""
	for core in CORES:
		if ext in CORES[core].exts:
			if found != "":
				return ""  # ambiguous without a folder hint
			found = core
	return found


static func accepts(core: String, path: String) -> bool:
	return core in CORES and path.get_extension().to_lower() in CORES[core].exts
