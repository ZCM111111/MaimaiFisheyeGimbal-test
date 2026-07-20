// Shaders/StabilizerShader.metal
#include <metal_stdlib>
using namespace metal;

// ---- 顶点着色器：全屏四边形 ----

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertex_main(uint vid [[vertex_id]]) {
    const float2 positions[6] = {
        float2(-1, -1), float2( 1, -1), float2(-1,  1),
        float2( 1, -1), float2( 1,  1), float2(-1,  1)
    };
    const float2 texCoords[6] = {
        float2(0, 1), float2(1, 1), float2(0, 0),
        float2(1, 1), float2(1, 0), float2(0, 0)
    };
    VertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.texCoord = texCoords[vid];
    return out;
}

// ---- Uniforms ----

struct Uniforms {
    // 镜头参数
    float2 opticalCenter;   // 归一化 0~1
    float  focalLength;     // 等效焦距（相对于纹理宽度）
    float  k1, k2, k3;      // 径向畸变系数

    // 稳定角度（弧度）
    float  roll, pitch, yaw;

    // 输出参数
    float  outputFovX;      // 输出水平 FOV（弧度）

    // 输入纹理尺寸
    float2 inputSize;       // 像素
};

// ---- 3D 旋转矩阵（ZYX 内旋）----

float3x3 rotation_zyx(float roll, float pitch, float yaw) {
    float cr = cos(roll);
    float sr = sin(roll);
    float cp = cos(pitch);
    float sp = sin(pitch);
    float cy = cos(yaw);
    float sy = sin(yaw);

    return float3x3(
        float3(cy * cp,  cy * sp * sr - sy * cr,  cy * sp * cr + sy * sr),
        float3(sy * cp,  sy * sp * sr + cy * cr,  sy * sp * cr - cy * sr),
        float3(-sp,      cp * sr,                  cp * cr)
    );
}

// ---- 主片元着色器 ----

fragment float4 fragment_main(
    VertexOut            in            [[stage_in]],
    texture2d<float>     inputTex      [[texture(0)]],
    constant Uniforms&   u             [[buffer(0)]]
) {
    constexpr sampler sam(address::clamp_to_edge, filter::linear);

    float2 uv     = in.texCoord;
    float  aspect = u.inputSize.x / u.inputSize.y;

    // ──  Step 1: 输出 UV → 直线投影方向向量 ──
    float flPx   = 0.5 / tan(u.outputFovX * 0.5);
    float2 center = float2(0.5, 0.5);
    float3 dir = normalize(float3(
        (uv.x - center.x),
        (uv.y - center.y) / aspect,
        flPx
    ));

    // ──  Step 2: 反向旋转（补偿手机运动）──
    float3x3 R = rotation_zyx(-u.roll, -u.pitch, -u.yaw);
    float3 stabilizedDir = R * dir;

    // ──  Step 3: 方向向量 → 鱼眼 UV（等距投影 + 径向畸变）──
    float theta = acos(clamp(stabilizedDir.z, -1.0, 1.0));
    float phi   = atan2(stabilizedDir.y, stabilizedDir.x);
    float r = u.focalLength * theta;

    float theta2 = theta * theta;
    float theta4 = theta2 * theta2;
    float theta6 = theta2 * theta4;
    float distortion = 1.0 + u.k1 * theta2 + u.k2 * theta4 + u.k3 * theta6;
    r *= distortion;

    float2 sampleUV = u.opticalCenter + float2(r * cos(phi), r * sin(phi));

    // ──  Step 4: 采样 ──
    if (sampleUV.x < 0.0 || sampleUV.x > 1.0 ||
        sampleUV.y < 0.0 || sampleUV.y > 1.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    return inputTex.sample(sam, sampleUV);
}
