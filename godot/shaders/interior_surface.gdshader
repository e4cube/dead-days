shader_type spatial;
render_mode diffuse_burley;
uniform vec4 base_color : source_color = vec4(0.4,0.3,0.2,1.0);
uniform int surface_kind = 0;
uniform float base_roughness : hint_range(0.0,1.0) = 0.85;
uniform int grain_axis = 0;
varying vec3 local_point;
varying vec3 local_normal;
void vertex() { local_point = VERTEX; local_normal = NORMAL; }
void fragment() {
    vec3 p = local_point;
    float variation = 0.0;
    if (surface_kind == 0) {
        float across = grain_axis == 0 ? p.x : p.z;
        float along = grain_axis == 0 ? p.z : p.y;
        float wave = across*180.0 + sin(along*8.0+sin(along*3.0))*4.0;
        float fine = sin(wave)*0.5 + sin(wave*2.17+p.x*8.0)*0.25;
        float fade = 1.0-smoothstep(0.5,2.0,fwidth(wave));
        variation = fine*0.05*fade;
    } else if (surface_kind == 1) {
        vec3 weave = p*900.0;
        vec3 weights = pow(abs(local_normal),vec3(4.0));
        weights /= max(weights.x+weights.y+weights.z,0.001);
        float pattern = sin(weave.y)*sin(weave.z)*weights.x+sin(weave.x)*sin(weave.z)*weights.y+sin(weave.x)*sin(weave.y)*weights.z;
        float fade = 1.0-smoothstep(0.5,2.5,max(max(fwidth(weave.x),fwidth(weave.y)),fwidth(weave.z)));
        variation = pattern*0.035*fade;
    } else if (surface_kind == 2) {
        variation = sin(p.x*47.0+p.z*19.0)*sin(p.y*31.0+p.z*7.0)*0.025;
    } else {
        float brush = p.z*650.0;
        variation = sin(brush)*0.035*(1.0-smoothstep(0.5,2.5,fwidth(brush)));
    }
    ALBEDO = base_color.rgb*(1.0+variation);
    ROUGHNESS = clamp(base_roughness+variation*0.3,0.0,1.0);
    METALLIC = surface_kind == 3 ? 0.65 : 0.0;
}
