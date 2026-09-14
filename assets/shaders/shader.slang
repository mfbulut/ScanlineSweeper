struct Instance {
    float4 dest;
    float4 src;
    uint color;
    uint index;
    float radius;
    uint _pad;
};

struct Curve {
    float2 p0;
    float2 p1;
    float2 p2;
};

struct Stripe {
    uint curve_start;
    uint curve_count;
};

struct PushConstants {
    float2 screen_size;
    uint64_t instances_addr;
    uint64_t curves_addr;
    uint64_t stripes_addr;
};

[vk::push_constant] PushConstants pc;

struct VSOutput {
    float4 sv_pos : SV_Position;
    float2 out_pos;
    float4 out_color;
    nointerpolation uint out_index;
    nointerpolation float4 out_uv;
};

float4 unpack_color(uint c) {
    return float4(
        float(c & 0xFFu),
        float((c >> 8u) & 0xFFu),
        float((c >> 16u) & 0xFFu),
        float((c >> 24u) & 0xFFu)
    ) / 255.0;
}

[shader("vertex")]
VSOutput vs_main(uint vid_raw : SV_VertexID, uint instance_idx : SV_InstanceID) {
    Instance* instance_buf = (Instance*)pc.instances_addr;
    Instance inst = instance_buf[instance_idx];
    uint vid = vid_raw & 3u;

    float2 corner = float2(
        (vid & 1u) != 0u ? 1.0 : 0.0,
        (vid & 2u) != 0u ? 1.0 : 0.0
    );

    float2 pixel_pos = lerp(inst.dest.xy, inst.dest.zw, corner);
    float4 gl_Position = float4(pixel_pos / pc.screen_size * 2.0 - 1.0, 0.0, 1.0);

    float2 half_size = (inst.dest.zw - inst.dest.xy) * 0.5;

    VSOutput output;
    output.sv_pos = gl_Position;

    if (inst.index == 0u) {
        output.out_pos = (corner * 2.0 - 1.0) * half_size;
        output.out_uv = float4(half_size - inst.radius, inst.radius, 0.0);
    } else {
        output.out_pos = lerp(inst.src.xy, inst.src.zw, corner);
        output.out_uv = inst.src;
    }

    output.out_color = unpack_color(inst.color);
    output.out_index = inst.index;
    return output;
}

float2 evaluate_bezier(float2 p0, float2 p1, float2 p2, float t) {
    float2 a = lerp(p0, p1, t);
    float2 b = lerp(p1, p2, t);
    return lerp(a, b, t);
}

float intersect_monotonic(float qa, float c0, float c1, float c2, float target) {
    if (abs(qa) < 1e-6) {
        return (target - c0) / (c2 - c0);
    }
    float qb = fma(2.0, c1, -2.0 * c0);
    float qc = c0 - target;
    float d = fma(qb, qb, -4.0 * qa * qc);
    float sqrt_d = d < 0.0 ? 0.0 : sqrt(d);
    float inv_2a = 0.5 / qa;
    return fma(-qb, inv_2a, sign(c2 - c0) * sqrt_d * inv_2a);
}

float scanline_sweep(float2 size, float2 offset, float2 p0, float2 p1, float2 p2) {
    if (max(p0.y, p2.y) <= offset.y || min(p0.y, p2.y) >= offset.y + size.y) {
        return 0.0;
    }

    p0 -= offset;
    p1 -= offset;
    p2 -= offset;

    float qa = fma(-2.0, p1.y, p0.y + p2.y);
    float bt = intersect_monotonic(qa, p0.y, p1.y, p2.y, 0.0);
    float tt = intersect_monotonic(qa, p0.y, p1.y, p2.y, size.y);

    float2 delta = p2 - p0;
    float v_min_t = delta.y > 0.0 ? bt : tt;
    float v_max_t = delta.y > 0.0 ? tt : bt;

    float2 v_min = evaluate_bezier(p0, p1, p2, clamp(v_min_t, 0.0, 1.0));
    float2 v_max = evaluate_bezier(p0, p1, p2, clamp(v_max_t, 0.0, 1.0));

    if (max(v_min.x, v_max.x) <= 0.0) {
        return (v_max.y - v_min.y) * size.x;
    }

    if (min(v_min.x, v_max.x) >= size.x) {
        return 0.0;
    }

    qa = fma(-2.0, p1.x, p0.x + p2.x);

    float h_min_t;
    float h_max_t;

    float4 h_check = delta.x > 0.0 ? float4(p0.x, p2.x, 0.0, 0.0) : float4(p2.x, p0.x, size.x, 1.0);

    if (h_check.x >= h_check.z) {
        h_min_t = h_check.w;
    } else if (h_check.y <= h_check.z) {
        h_min_t = 1.0 - h_check.w;
    } else {
        h_min_t = intersect_monotonic(qa, p0.x, p1.x, p2.x, h_check.z);
    }

    h_check.z = size.x - h_check.z;

    if (h_check.x >= h_check.z) {
        h_max_t = h_check.w;
    } else if (h_check.y <= h_check.z) {
        h_max_t = 1.0 - h_check.w;
    } else {
        h_max_t = intersect_monotonic(qa, p0.x, p1.x, p2.x, h_check.z);
    }

    float min_t = clamp(max(v_min_t, h_min_t), 0.0, 1.0);
    float max_t = clamp(min(v_max_t, h_max_t), 0.0, 1.0);

    float2 q0 = v_min_t >= h_min_t ? v_min : evaluate_bezier(p0, p1, p2, min_t);
    float2 q1 = v_max_t <= h_max_t ? v_max : evaluate_bezier(p0, p1, p2, max_t);

    float coverage = 0.0;

    if (min_t > 0.0 && delta.x > 0.0) {
        float h = delta.y > 0.0 ? q0.y - max(0.0, p0.y) : min(size.y, p0.y) - q0.y;
        coverage = sign(delta.y) * h * size.x;
    }

    if (max_t < 1.0 && delta.x < 0.0) {
        float h = delta.y > 0.0 ? min(size.y, p2.y) - q1.y : q1.y - max(0.0, p2.y);
        coverage += sign(delta.y) * h * size.x;
    }

    float h = q1.y - q0.y;
    float b = fma(-0.5, q0.x + q1.x, size.x);
    coverage += b * h;

    return coverage;
}

[shader("fragment")]
float4 fs_main(VSOutput input) : SV_Target {
    float alpha = 1.0;

    if (input.out_index == 0u) {
        float2 q = abs(input.out_pos) - input.out_uv.xy;
        float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - input.out_uv.z;
        alpha = clamp(0.5 - dist, 0.0, 1.0);
    } else {
        float2 pixel_size = fwidth(input.out_pos);
        float2 pixel_offset = input.out_pos - 0.5 * pixel_size;

        float y_min = input.out_uv.y;
        float y_max = input.out_uv.w;
        float y_range = max(y_max - y_min, 1e-6);
        float t = clamp((input.out_pos.y - y_min) / y_range, 0.0, 0.9999);
        uint stripe_idx = uint(t * 8.0);

        Stripe* stripe_buf = (Stripe*)pc.stripes_addr;
        Stripe s = stripe_buf[input.out_index + stripe_idx];

        Curve* curve_buf = (Curve*)pc.curves_addr;
        float total_coverage = 0.0;
        for (uint i = 0u; i < s.curve_count; i++) {
            Curve c = curve_buf[s.curve_start + i];
            total_coverage += scanline_sweep(pixel_size, pixel_offset, c.p0, c.p1, c.p2);
        }

        float area = pixel_size.x * pixel_size.y;
        alpha = clamp(abs(total_coverage) / area, 0.0, 1.0);
    }

    float4 out_color = input.out_color;
    out_color.a *= alpha;
    return out_color;
}
