#version 330

// === INPUT: Vertex attributes (from mesh) ===
// These come automatically from Raylib's mesh format
in vec3 vertexPosition;   // Where is this vertex?
in vec2 vertexTexCoord;   // UV coordinates for texturing
in vec3 vertexNormal;     // Which way does the surface point?
in vec4 vertexColor;      // Per-vertex color (often white)

// === INPUT: Uniforms (set by Raylib automatically) ===
uniform mat4 mvp;         // Model-View-Projection: transforms vertex to screen space
uniform mat4 matModel;    // Model matrix: transforms to world space
uniform mat4 matNormal;   // Normal matrix: transforms normals correctly

// === OUTPUT: Data passed to fragment shader ===
out vec3 fragPosition;    // World-space position (for point light distance)
out vec2 fragTexCoord;    // Pass through UV coords
out vec4 fragColor;       // Pass through vertex color
out vec3 fragNormal;      // World-space normal (for lighting calc)

void main()
{
    // Transform vertex position from model space to world space
    // This is needed for point lights (distance calculation)
    fragPosition = vec3(matModel * vec4(vertexPosition, 1.0));

    // Pass texture coordinates unchanged
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;

    // Transform normal to world space
    // matNormal handles non-uniform scaling correctly
    // normalize() ensures unit length after transformation
    fragNormal = normalize(vec3(matNormal * vec4(vertexNormal, 1.0)));

    // Final screen position (required output)
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
