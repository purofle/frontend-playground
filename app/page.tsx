"use client";

import {useEffect, useRef} from "react";

const MAX_CLICKS = 10;

export default function Home() {
    const canvasRef = useRef<HTMLCanvasElement | null>(null);

    useEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas) return;

        const gl = canvas.getContext("webgl2");
        if (!gl) return;

        let frameId = 0;
        const startTime = performance.now();
        const clickPositions = new Float32Array(MAX_CLICKS * 2);
        const clickTimes = new Float32Array(MAX_CLICKS);
        let clickCount = 0;
        let mouse = {x: 0, y: 0, down: 0};
        let disposed = false;

        const resize = () => {
            const dpr = window.devicePixelRatio || 1;
            const width = Math.max(1, Math.floor(canvas.clientWidth * dpr));
            const height = Math.max(1, Math.floor(canvas.clientHeight * dpr));
            if (canvas.width !== width || canvas.height !== height) {
                canvas.width = width;
                canvas.height = height;
            }
            gl.viewport(0, 0, canvas.width, canvas.height);
        };

        const createShader = (type: number, source: string) => {
            const shader = gl.createShader(type);
            if (!shader) return null;
            gl.shaderSource(shader, source);
            gl.compileShader(shader);
            if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
                console.error(gl.getShaderInfoLog(shader));
                gl.deleteShader(shader);
                return null;
            }
            return shader;
        };

        const createProgram = (vertexSource: string, fragmentSource: string) => {
            const vertexShader = createShader(gl.VERTEX_SHADER, vertexSource);
            const fragmentShader = createShader(gl.FRAGMENT_SHADER, fragmentSource);
            if (!vertexShader || !fragmentShader) return null;

            const program = gl.createProgram();
            if (!program) return null;
            gl.attachShader(program, vertexShader);
            gl.attachShader(program, fragmentShader);
            gl.linkProgram(program);

            if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
                console.error(gl.getProgramInfoLog(program));
                gl.deleteProgram(program);
                return null;
            }

            return program;
        };

        const pushClick = (x: number, y: number, time: number) => {
            let index = clickCount;
            if (clickCount < MAX_CLICKS) {
                clickCount += 1;
            } else {
                for (let i = 1; i < MAX_CLICKS; i += 1) {
                    clickPositions[(i - 1) * 2] = clickPositions[i * 2];
                    clickPositions[(i - 1) * 2 + 1] = clickPositions[i * 2 + 1];
                    clickTimes[i - 1] = clickTimes[i];
                }
                index = MAX_CLICKS - 1;
            }
            clickPositions[index * 2] = x;
            clickPositions[index * 2 + 1] = y;
            clickTimes[index] = time;
        };

        const updatePointer = (event: PointerEvent) => {
            const rect = canvas.getBoundingClientRect();
            const dpr = window.devicePixelRatio || 1;
            const x = (event.clientX - rect.left) * dpr;
            const y = (rect.bottom - event.clientY) * dpr;
            mouse = {...mouse, x, y};
        };

        const onPointerMove = (event: PointerEvent) => {
            updatePointer(event);
        };

        const onPointerDown = (event: PointerEvent) => {
            updatePointer(event);
            mouse = {...mouse, down: 1};
            const time = (performance.now() - startTime) / 1000;
            pushClick(mouse.x, mouse.y, time);
        };

        const onPointerUp = () => {
            mouse = {...mouse, down: 0};
        };

        canvas.addEventListener("pointermove", onPointerMove);
        canvas.addEventListener("pointerdown", onPointerDown);
        window.addEventListener("pointerup", onPointerUp);

        const setup = async () => {
            try {
                const response = await fetch("/fragmentShader.glsl");
                const fragmentSource = await response.text();
                const vertexSource = `#version 300 es
        in vec2 position;
        void main() {
          gl_Position = vec4(position, 0.0, 1.0);
        }`;

                const program = createProgram(vertexSource, fragmentSource);
                if (!program) return;

                gl.useProgram(program);

                const buffer = gl.createBuffer();
                gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
                gl.bufferData(
                    gl.ARRAY_BUFFER,
                    new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]),
                    gl.STATIC_DRAW
                );

                const positionLocation = gl.getAttribLocation(program, "position");
                gl.enableVertexAttribArray(positionLocation);
                gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

                const iResolutionLocation = gl.getUniformLocation(program, "iResolution");
                const iMouseLocation = gl.getUniformLocation(program, "iMouse");
                const iTimeLocation = gl.getUniformLocation(program, "iTime");
                const iClickPositionsLocation = gl.getUniformLocation(program, "iClickPositions[0]");
                const iClickTimesLocation = gl.getUniformLocation(program, "iClickTimes[0]");
                const iClickCountLocation = gl.getUniformLocation(program, "iClickCount");

                const render = (now: number) => {
                    if (disposed) return;
                    resize();

                    const time = (now - startTime) / 1000;
                    if (iResolutionLocation) {
                        gl.uniform2f(iResolutionLocation, canvas.width, canvas.height);
                    }
                    if (iMouseLocation) {
                        gl.uniform4f(iMouseLocation, mouse.x, mouse.y, mouse.down, 0);
                    }
                    if (iTimeLocation) {
                        gl.uniform1f(iTimeLocation, time);
                    }
                    if (iClickPositionsLocation) {
                        gl.uniform2fv(iClickPositionsLocation, clickPositions);
                    }
                    if (iClickTimesLocation) {
                        gl.uniform1fv(iClickTimesLocation, clickTimes);
                    }
                    if (iClickCountLocation) {
                        gl.uniform1i(iClickCountLocation, clickCount);
                    }

                    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
                    frameId = requestAnimationFrame(render);
                };

                frameId = requestAnimationFrame(render);
            } catch (error) {
                console.error(error);
            }
        };

        setup().catch(console.error);

        return () => {
            disposed = true;
            cancelAnimationFrame(frameId);
            canvas.removeEventListener("pointermove", onPointerMove);
            canvas.removeEventListener("pointerdown", onPointerDown);
            window.removeEventListener("pointerup", onPointerUp);
        };
    }, []);

    return (
        <div className="relative min-h-screen overflow-hidden bg-gray-900">
            <canvas ref={canvasRef} className="absolute inset-0 h-full w-full"/>

            <main
                className="pointer-events-none relative mx-auto flex min-h-screen w-full max-w-7xl flex-col items-center justify-center gap-8 text-center">
                <h1 className="text-green-300 text-4xl font-['Cubic11']">
                    akana.moe 前端试验田
                    <span className="cursor px-2">:)</span>
                </h1>
                {/*translate-x 为了维持视觉中心*/}
                <p className="text-gray-300 text-xl font-mono translate-x-[-2vh]">
                    <text>Maybe there's nothing...</text>
                </p>

                {/*translate-x 为了维持视觉中心*/}
                <div className="flex flex-row gap-4 font-mono text-xl text-gray-400 translate-x-[-3vh]">
                    <a
                        href="https://blog.archlinux.tech"
                        className="pointer-events-auto font-mono text-gray-400
                        bg-[linear-gradient(currentColor,currentColor)]
                        bg-size-[0%_1px] bg-position-[0_100%]
                        bg-no-repeat
                        transition-[background-size,color] duration-300
                        hover:text-green-300 hover:bg-size-[100%_1px]"
                    >
                        [ Blog ]
                    </a>
                    <span className="text-gray-600">|</span>
                    <a
                        href="https://github.com/purofle/frontend-playground"
                        className="pointer-events-auto font-mono text-gray-400
                        bg-[linear-gradient(currentColor,currentColor)]
                        bg-size-[0%_1px] bg-position-[0_100%]
                        bg-no-repeat
                        transition-[background-size,color] duration-300
                        hover:text-green-300 hover:bg-size-[100%_1px]"
                    >
                        [ GitHub ]
                    </a>
                </div>
            </main>
        </div>
    )
}
