#version 300 es

precision mediump float;

// --- Utility Functions (Noise, Bayer) ---
float random (in vec2 st) {
return fract(sin(dot(st.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

float noise (in vec2 st) {
vec2 i = floor(st);
vec2 f = fract(st);

float a = random(i);
float b = random(i + vec2(1.0, 0.0));
float c = random(i + vec2(0.0, 1.0));
float d = random(i + vec2(1.0, 1.0));

vec2 u = f*f*(3.0-2.0*f);
return mix(a, b, u.x) + (c - a)* u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Fractional Brownian Motion (fBm) for more complex noise
float fbm(vec2 st, float time) {
float value = 0.0;
float amplitude = 0.5;
float totalAmp = 0.0; // For proper normalization

// Create turbulent flow effect with more chaotic movement
// Base turbulence vectors that change direction over time with bounded sine/cosine
vec2 shift = vec2(
sin(time * 0.1) * 3.0 + cos(time * 0.15) * 2.0,
cos(time * 0.12) * 3.0 - sin(time * 0.08) * 2.0
);

// Initial flow direction varies across the image - using stable bounded functions
vec2 flow = vec2(
sin(st.y * 0.8 + time * 0.2) * 1.5,
cos(st.x * 0.7 + time * 0.15) * 1.5
);

// Add vortex-like rotations at various scales
for (int i = 0; i < 6; i++) {
// Each octave has its own time-varying flow direction
float octaveTime = time * (0.4 + float(i) * 0.15);

// Create vortex effect by varying movement direction by position
float angle = noise(st * 0.2 + float(i)) * 6.28 + octaveTime;
vec2 vortex = vec2(cos(angle), sin(angle)) * (1.0 + float(i) * 0.3);

// Temporal variation for each octave (fade in/out patterns)
// Use stable circular functions instead of accumulating ones
float temporalNoise = 0.5 + 0.5 * sin(time * 0.2 + float(i) * 3.5);
float temporalMask = 1.;

// Sample noise at current position with flow and vortex influence
value += amplitude * noise(st + vortex + flow) * temporalMask;

// Track total amplitude for normalization
totalAmp += amplitude * min(max(temporalMask, 0.7), 2.0); // Use max to prevent dark spots

// Prepare for next octave
st *= 1.8 + temporalNoise * 0.2; // Reduced temporal influence on lacunarity
st += shift * 0.3;               // Global flow shift
flow *= 0.5;                     // Flow diminishes at smaller scales
amplitude *= 0.55;               // Persistence
}

// Proper normalization to prevent brightness/darkness issues
float normalizedValue = value / max(totalAmp, 0.001);

// Safety clamp to ensure we stay in reasonable range
return clamp(normalizedValue, 0.0, 1.0);
}

float bayer8x8Value(vec2 coord) {
int x = int(mod(coord.x, 8.0));
int y = int(mod(coord.y, 8.0));

const float bayerMatrix[64] = float[](
0.0, 32.0,  8.0, 40.0,  2.0, 34.0, 10.0, 42.0,
48.0, 16.0, 56.0, 24.0, 50.0, 18.0, 58.0, 26.0,
12.0, 44.0,  4.0, 36.0, 14.0, 46.0,  6.0, 38.0,
60.0, 28.0, 52.0, 20.0, 62.0, 30.0, 54.0, 22.0,
3.0, 35.0, 11.0, 43.0,  1.0, 33.0,  9.0, 41.0,
51.0, 19.0, 59.0, 27.0, 49.0, 17.0, 57.0, 25.0,
15.0, 47.0,  7.0, 39.0, 13.0, 45.0,  5.0, 37.0,
63.0, 31.0, 55.0, 23.0, 61.0, 29.0, 53.0, 21.0
);

int index = y * 8 + x;
return bayerMatrix[index];
}

float getNormalizedBayer8x8(vec2 coord) {
float val = bayer8x8Value(coord);
return val / 63.0;
}

// --- Uniforms ---
uniform vec2 iResolution;
uniform vec4 iMouse;
uniform float iTime;

// Multi-click support (up to 10 simultaneous clicks)
const int MAX_CLICKS = 10;
uniform vec2 iClickPositions[MAX_CLICKS];  // Position of each click
uniform float iClickTimes[MAX_CLICKS];     // Time of each click
uniform int iClickCount;                   // Number of active clicks

// --- Main Shader ---
void mainImage(out vec4 fragColor, in vec2 fragCoord) {

// --- Resolution Handling (Fixed Width, Variable Height) ---
float targetWidth = iResolution.x / 4.0; // Target internal width
float screenAspect = iResolution.x / iResolution.y;
float targetHeight = targetWidth / screenAspect;
vec2 targetRes = vec2(targetWidth, targetHeight);

// Calculate coordinates within the target resolution space
// Adjust fragCoord to center the fixed resolution area
vec2 centerOffset = (iResolution.xy - targetRes * (iResolution.y / targetHeight)) * 0.5;
vec2 scaledCoord = (fragCoord - centerOffset) / (iResolution.y / targetHeight);

// Discard fragments outside the target area
if (scaledCoord.x < 0.0 || scaledCoord.x >= targetWidth || scaledCoord.y < 0.0 || scaledCoord.y >= targetHeight) {
fragColor = vec4(0.0, 0.0, 0.0, 1.0);
return;
}

// --- Parameters ---
float noiseBaseScale = 4.0; // Base scale for fBm
float spread = 0.5;
float pixelSize = 8.0;

// Input image controls
float brightness = -0.65;
float contrast = 1.2;

vec3 colorFirst = vec3(0.0, 0.0, 0.0) / 255.0;
vec3 colorSecond = vec3(57.0, 179.0, 67.0) / 255.0;

// --- Pixelation ---
vec2 pixelatedCoord = floor(scaledCoord / pixelSize) * pixelSize;
vec2 uv = pixelatedCoord / targetRes; // Use UV within target resolution

// --- Generate Base Noise using fBm (Increased time multiplier) ---
float baseNoiseValue = fbm(uv * noiseBaseScale, iTime * 0.5); // Increased iTime multiplier from 0.5 to 1.0
// Normalize fBm output roughly to [0, 1]
baseNoiseValue = (baseNoiseValue + 1.0) * 0.5;

// --- Parameters for Wave Effect ---
float waveDuration = 3.5;  // How long each ripple lasts
float waveSpeed = 3.0;
float waveFrequency = 15.0;
float waveAmplitude = 0.45;  // Reduced from 0.6 to make effect weaker
float waveFalloff = 3.5;     // Reduced from 6.0 to increase max radius

// --- Accumulate wave effects from all active clicks ---
float totalWaveEffect = 0.0;

for (int i = 0; i < MAX_CLICKS; i++) {
if (i >= iClickCount) break; // Only process active clicks

float clickTime = iClickTimes[i];
vec2 clickPos = iClickPositions[i];

// Convert click position to UV space
vec2 clickUV = (clickPos - centerOffset) / (iResolution.y / targetHeight);
clickUV /= targetRes;

float timeSinceClick = iTime - clickTime;

if (timeSinceClick >= 0.0 && timeSinceClick < waveDuration) {
float distToClick = length(uv - clickUV);

// Calculate base wave signal
float wave = sin(distToClick * waveFrequency - timeSinceClick * waveSpeed);
wave = wave * 0.5 + 0.5; // Normalize [0, 1]

// Apply falloffs BEFORE sharpening
float temporalFalloff = smoothstep(waveDuration, 0.0, timeSinceClick);
float spatialFalloff = exp(-distToClick * waveFalloff);
wave *= spatialFalloff * temporalFalloff;

// Sharpen the peaks of the faded wave
wave = pow(wave, 2.5);

// Add this click's wave effect to the total
totalWaveEffect += wave * waveAmplitude;
}
}

// Combine noise and accumulated wave effects
float finalNoise = baseNoiseValue + totalWaveEffect;

// Apply brightness and contrast
finalNoise = (finalNoise - 0.5) * contrast + 0.5 + brightness;
finalNoise += totalWaveEffect * 0.5; // Direct brightness boost
finalNoise = clamp(finalNoise, 0.0, 1.0);

vec3 baseColor = vec3(finalNoise);

// --- Apply Ordered Dithering ---
// Use scaledCoord for Bayer pattern to match fixed resolution
float bayerValue = getNormalizedBayer8x8(scaledCoord);
float ditherOffset = spread * (bayerValue - 0.5);

vec3 ditheredColor = baseColor + ditherOffset;
ditheredColor = clamp(ditheredColor, 0.0, 1.0);

// --- Find Nearest Palette Color with Smooth Transition ---
float distSqBlack = dot(ditheredColor, ditheredColor);
float distSqGreen = dot(ditheredColor - 1., ditheredColor - 1.);

// Calculate a blend factor based on relative distances
float ratio = distSqBlack / (distSqBlack + distSqGreen);

// Apply a sigmoid-like function with increased steepness for a sharper transition
float blendFactor = 1.0 / (1.0 + exp(-(ratio - 0.5) * 9000.0));

// Interpolate between colors
vec3 finalColor = mix(colorFirst, colorSecond, blendFactor);

fragColor = vec4(finalColor, 1.0);
}

out vec4 outColor;

void main() {
    // 使用自定义的 outColor 替代 gl_FragColor
    mainImage(outColor, gl_FragCoord.xy);
}