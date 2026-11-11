#version 460 core
#include <flutter/runtime_effect.glsl>

// A slow silky flow made by bending space with layered sine waves (no noise or hashing).
//
// Phones run fragment shaders at half precision, which wrecks the usual noise tricks: hashes
// become blocky polygons. Sine warps stay smooth at any precision, so the same picture comes out
// on every device. Everything here keeps numbers small, and time arrives as ready-wrapped phases
// from the app instead of one ever-growing number.
precision highp float;

uniform vec2 uSize;
uniform float uLight; // 0 for dark theme, 1 for light theme (washed toward white)
uniform vec3 uDeep;
uniform vec3 uMid;
uniform vec3 uBright;
uniform vec3 uGlow;
uniform float uOctaves; // layers of bending: 3 (fast) to 6 (finest)
uniform vec4 uPh;       // four wrapped phases, each 0 to 2*pi

out vec4 fragColor;

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 s = frag / max(uSize, vec2(1.0));
  float aspect = uSize.x / max(uSize.y, 1.0);
  // The short side always spans the same amount of flow, so a tall phone shows plenty of waves
  // down its length instead of a few big ones.
  vec2 p = vec2((s.x - 0.5) * max(aspect, 1.0), (s.y - 0.5) * max(1.0 / aspect, 1.0)) * 3.4;

  // Bend space again and again; each layer is finer and weaker than the one before.
  for (int i = 1; i < 7; i++) {
    if (float(i) > uOctaves) break;
    float fi = float(i);
    float a = (mod(fi, 2.0) < 0.5) ? uPh.x : uPh.z;
    float b = (mod(fi, 2.0) < 0.5) ? uPh.y : uPh.w;
    p.x += (1.05 / fi) * sin(fi * 1.25 * p.y + a);
    p.y += (1.05 / fi) * sin(fi * 1.05 * p.x + b);
  }

  float f = 0.5 + 0.5 * sin(p.x * 1.7 + p.y * 1.1 + uPh.w);
  float g = 0.5 + 0.5 * sin(p.y * 2.1 - p.x * 0.8 + uPh.x);
  float body = clamp(0.62 * f + 0.38 * g, 0.0, 1.0);
  body = smoothstep(0.12, 0.88, body);

  // Bright veins along the ridges, like light through polished stone.
  float vein = pow(1.0 - abs(sin(p.x * 1.3 + p.y * 1.9 + uPh.y)), 6.0);

  vec3 col = mix(uDeep, uMid, smoothstep(0.0, 0.6, body));
  col = mix(col, uBright, smoothstep(0.5, 1.0, body) * 0.85);
  col += uGlow * vein * 0.55 * (0.35 + 0.65 * body);

  col *= mix(0.62, 1.0, smoothstep(1.25, 0.15, length(s - 0.5)));
  col = mix(col, mix(vec3(1.0), col, 0.5), uLight);
  fragColor = vec4(col, 1.0);
}
