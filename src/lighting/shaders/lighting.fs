#version 330

// === INPUT: From vertex shader (interpolated across triangle) ===
in vec3 fragPosition;     // World-space position of this pixel
in vec2 fragTexCoord;     // Texture coordinates
in vec4 fragColor;        // Vertex color
in vec3 fragNormal;       // Surface normal at this pixel

// === INPUT: Textures and material ===
uniform sampler2D texture0;   // Diffuse texture (white if none)
uniform vec4 colDiffuse;      // Material base color

// === OUTPUT ===
out vec4 finalColor;

// === LIGHTING SYSTEM ===
#define MAX_LIGHTS 4
#define LIGHT_DIRECTIONAL 0
#define LIGHT_POINT 1

// Light data structure - must match CPU-side Light struct
struct Light {
    int enabled;      // Is this light active?
    int type;         // DIRECTIONAL (sun) or POINT (lamp)
    vec3 position;    // Where is the light?
    vec3 target;      // Where is it pointing? (for directional)
    vec4 color;       // Light color and intensity
};

// === INPUT: Lighting uniforms (set from Zig) ===
uniform Light lights[MAX_LIGHTS];
uniform vec4 ambient;         // Global ambient light level
uniform vec3 viewPos;         // Camera position (for specular)

void main()
{
    // Sample texture (defaults to white 1x1 if no texture bound)
    vec4 texelColor = texture(texture0, fragTexCoord);

    // Combine material color with vertex color
    vec4 tint = colDiffuse * fragColor;

    // Get normalized surface normal
    vec3 normal = normalize(fragNormal);

    // View direction: from this pixel toward the camera
    vec3 viewDir = normalize(viewPos - fragPosition);

    // Accumulate lighting contributions
    vec3 diffuseSum = vec3(0.0);   // Matte lighting
    vec3 specularSum = vec3(0.0);  // Shiny highlights

    // === PROCESS EACH LIGHT ===
    for (int i = 0; i < MAX_LIGHTS; i++)
    {
        if (lights[i].enabled == 1)
        {
            vec3 lightDir;

            // Calculate light direction based on type
            if (lights[i].type == LIGHT_DIRECTIONAL)
            {
                // DIRECTIONAL LIGHT (Sun):
                // Light rays are parallel, coming from position toward target
                // We negate because we want direction TO the light source
                lightDir = -normalize(lights[i].target - lights[i].position);
            }
            else // LIGHT_POINT
            {
                // POINT LIGHT (Lamp):
                // Light radiates from a position - direction varies per pixel
                lightDir = normalize(lights[i].position - fragPosition);
            }

            // === ATTENUATION (Point lights only) ===
            // Light intensity decreases with distance squared
            float attenuation = 1.0;
            if (lights[i].type == LIGHT_POINT)
            {
                float distance = length(lights[i].position - fragPosition);
                // Quadratic falloff: 1 / (1 + 0.09*d + 0.032*d²)
                // These constants control how quickly light fades
                attenuation = 1.0 / (1.0 + 0.09 * distance + 0.032 * distance * distance);
            }

            // === DIFFUSE (Lambertian) ===
            // How directly does light hit this surface?
            // dot(normal, lightDir) = cos(angle between them)
            // max(_, 0) clamps negative values (back-facing surfaces)
            float NdotL = max(dot(normal, lightDir), 0.0);
            diffuseSum += lights[i].color.rgb * NdotL * attenuation;

            // === SPECULAR (Blinn-Phong) ===
            // Shiny highlight when light reflects toward camera
            if (NdotL > 0.0)
            {
                // Reflect light direction around normal
                vec3 reflectDir = reflect(-lightDir, normal);

                // How aligned is reflection with view direction?
                float spec = pow(max(dot(viewDir, reflectDir), 0.0), 16.0);
                // 16.0 = shininess (higher = tighter highlight)

                specularSum += lights[i].color.rgb * spec * 0.5 * attenuation;
            }
        }
    }

    // === COMBINE EVERYTHING ===
    // Base color from texture and material
    vec3 baseColor = texelColor.rgb * tint.rgb;

    // Ambient: constant minimum light (so shadows aren't pure black)
    vec3 ambientContrib = baseColor * ambient.rgb;

    // Diffuse: matte lighting
    vec3 diffuseContrib = baseColor * diffuseSum;

    // Specular: shiny highlights (added on top, not multiplied by base)
    vec3 specularContrib = specularSum;

    // Final combination
    finalColor = vec4(ambientContrib + diffuseContrib + specularContrib, texelColor.a * tint.a);

    // Gamma correction (linear to sRGB for display)
    finalColor.rgb = pow(finalColor.rgb, vec3(1.0 / 2.2));
}
