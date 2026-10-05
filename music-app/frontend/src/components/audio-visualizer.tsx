"use client";

import { useEffect, useRef } from "react";

type Props = {
  isPlaying: boolean;
  className?: string;
};

export function AudioVisualizer({ isPlaying, className = "" }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animFrameRef = useRef<number | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let width = (canvas.width = canvas.parentElement?.clientWidth || 600);
    let height = (canvas.height = 140);

    const handleResize = () => {
      if (!canvas.parentElement) return;
      width = canvas.width = canvas.parentElement.clientWidth;
      height = canvas.height = 140;
    };
    window.addEventListener("resize", handleResize);

    const barCount = 48;
    const bars = Array.from({ length: barCount }, (_, i) => ({
      height: 10,
      targetHeight: 10,
      speed: 0.15 + (i % 5) * 0.03,
      phase: i * 0.2,
    }));

    let tick = 0;

    const render = () => {
      ctx.clearRect(0, 0, width, height);

      tick += 0.05;
      const barWidth = Math.max(3, (width / barCount) - 3);

      for (let i = 0; i < barCount; i++) {
        const b = bars[i];
        if (isPlaying) {
          // Dynamic organic waveform motion
          const wave1 = Math.sin(tick * 1.5 + b.phase) * 35;
          const wave2 = Math.cos(tick * 2.2 + b.phase * 1.5) * 25;
          const beat = (Math.sin(tick * 3) > 0.7 ? 20 : 0);
          b.targetHeight = Math.max(12, Math.min(height - 10, 30 + wave1 + wave2 + beat));
        } else {
          b.targetHeight = 6;
        }

        b.height += (b.targetHeight - b.height) * 0.18;

        const x = i * (barWidth + 3);
        const y = height - b.height;

        // Gradient for each bar
        const grad = ctx.createLinearGradient(0, y, 0, height);
        grad.addColorStop(0, "#00F0FF");
        grad.addColorStop(0.5, "#9D4EDD");
        grad.addColorStop(1, "rgba(157, 78, 221, 0.2)");

        ctx.fillStyle = grad;
        ctx.beginPath();
        ctx.roundRect(x, y, barWidth, b.height, [4, 4, 0, 0]);
        ctx.fill();
      }

      animFrameRef.current = requestAnimationFrame(render);
    };

    render();

    return () => {
      window.removeEventListener("resize", handleResize);
      if (animFrameRef.current) cancelAnimationFrame(animFrameRef.current);
    };
  }, [isPlaying]);

  return (
    <div className={`w-full overflow-hidden flex items-center justify-center ${className}`}>
      <canvas ref={canvasRef} className="w-full h-24 block opacity-85" />
    </div>
  );
}
