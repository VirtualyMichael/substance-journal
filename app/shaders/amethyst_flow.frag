#version 460 core
#include <flutter/runtime_effect.glsl>

// A slow marbled flow (domain-warped noise) in four palette colours. Cheap enough to run behind
// the whole app: three noise passes of four octaves each.
uniform vec2 uSize;
uniform float uTime;
uniform float uLight; // 0 for dark theme, 1 for light theme (washed toward white)
uniform vec3 uDeep;
uniform vec3 uMid;
uniform vec3 uBright;
uniform vec3 uGlow;

out vec4 fragColor;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  mat2 rot = mat2(0.8, -0.6, 0.6, 0.8);
  for (int i = 0; i < 4; i++) {
    v += a * noise(p);
    p = rot * p * 2.02 + 7.1;
    a *= 0.5;
  }
  return v;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / max(uSize.y, 1.0) * 1.7;
  float t = uTime * 0.05;

  vec2 q = vec2(fbm(uv + vec2(0.0, t)), fbm(uv + vec2(5.2, 1.3) - t));
  vec2 r = vec2(
    fbm(uv + 3.0 * q + vec2(1.7, 9.2) + 0.6 * t),
    fbm(uv + 3.0 * q + vec2(8.3, 2.8) - 0.5 * t)
  );
  float f = fbm(uv + 3.5 * r);

  // Bright veins along the ridges of the flow, like light through polished stone.
  float vein = pow(1.0 - abs(2.0 * f - 1.0), 5.0);
  float body = smoothstep(0.22, 0.78, f); // spread the values out so the dark and light areas read clearly

  vec3 col = mix(uDeep, uMid, smoothstep(0.0, 0.6, body));
  col = mix(col, uBright, smoothstep(0.55, 1.0, body) * 0.8);
  col += uGlow * vein * 0.9 * (0.4 + 0.6 * length(q));

  vec2 s = frag / max(uSize, vec2(1.0));
  col *= mix(0.62, 1.0, smoothstep(1.25, 0.15, length(s - 0.5)));

  col = mix(col, mix(vec3(1.0), col, 0.5), uLight);
  fragColor = vec4(col, 1.0);
}
