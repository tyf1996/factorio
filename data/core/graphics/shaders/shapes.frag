#version 330

layout(location = 0) out vec4 fragColor;
in vec4 vColor;

void main()
{
    fragColor = vColor;
}

