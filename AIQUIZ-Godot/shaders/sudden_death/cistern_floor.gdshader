shader_type spatial;
// Cistern floor (CIS_Floor): wet concrete with puddles (near-mirror roughness so SSR and the reflection
// probes show the lamps) and GGX glints of the floodlights. Lighting model in cistern_common.gdshaderinc.

#define CISTERN_FLOOR
#include "res://shaders/sudden_death/cistern_surface.gdshaderinc"
