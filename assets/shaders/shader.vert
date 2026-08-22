#version 450
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_scalar_block_layout : enable
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

struct Instance {
    vec4 dest;
    vec4 src;
    uint color;
    uint index;
    float radius;
    uint _pad;
};

layout(buffer_reference, scalar) readonly buffer InstanceBuffer {
    Instance instances[];
};

layout(push_constant) uniform PushConstants {
    vec2 screen_size;
    uint64_t instances_addr;
    uint64_t curves_addr;
    uint64_t stripes_addr;
} pc;

layout(location = 0) out vec2 out_pos;
layout(location = 1) out vec4 out_color;
layout(location = 2) out flat uint out_index;
layout(location = 3) out flat vec4 out_uv;

void main() {
    InstanceBuffer instance_buf = InstanceBuffer(pc.instances_addr);
    Instance inst = instance_buf.instances[gl_InstanceIndex];
    uint vid = gl_VertexIndex & 3u;

    vec2 corner = vec2(
        (vid & 1u) != 0u ? 1.0 : 0.0,
        (vid & 2u) != 0u ? 1.0 : 0.0
    );

    vec2 pixel_pos = mix(inst.dest.xy, inst.dest.zw, corner);
    gl_Position = vec4(pixel_pos / pc.screen_size * 2.0 - 1.0, 0.0, 1.0);

    vec2 half_size = (inst.dest.zw - inst.dest.xy) * 0.5;

    if (inst.index == 0u) {
        out_pos = (corner * 2.0 - 1.0) * half_size;
        out_uv = vec4(half_size - inst.radius, inst.radius, 0.0);
    } else {
        out_pos = mix(inst.src.xy, inst.src.zw, corner);
        out_uv = inst.src;
    }

    out_color = unpackUnorm4x8(inst.color);
    out_index = inst.index;
}
