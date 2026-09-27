import React from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame} from 'remotion';

// 开船过场（6 秒，三个镜头）：
//   1. 远景：黄昏的海，船离开身后的岛，天上有云、光束、海鸥
//   2. 近景：船从镜头前划过，船上的魂师剪影、灯笼、桨划起的水花、飘起的魂光
//   3. 目的地：远处的岛慢慢推近，岛上空亮起一圈魂环光，光柱冲天，白光转场
// 全部是 SVG（渐变、模糊滤镜、视差），上下加电影黑边。不放文字（章节名由游戏叠在上面）。

export const W = 1280;
export const H = 720;
const HORIZON = 390;

const clamp = {extrapolateLeft: 'clamp' as const, extrapolateRight: 'clamp' as const};

// 带两层正弦的波浪线
const wave = (y: number, amp: number, len: number, phase: number, x0 = -40, x1 = W + 40) => {
	let d = `M ${x0} ${y}`;
	for (let x = x0; x <= x1; x += 10) {
		const yy = y + Math.sin((x / len) * Math.PI * 2 + phase) * amp + Math.sin((x / (len * 0.43)) * Math.PI * 2 - phase * 1.7) * amp * 0.35;
		d += ` L ${x} ${yy.toFixed(1)}`;
	}
	return d;
};

// 伪随机（固定种子，每帧一样）
const rnd = (i: number) => {
	const s = Math.sin(i * 127.1 + 311.7) * 43758.5453;
	return s - Math.floor(s);
};

const Ridge: React.FC<{y: number; h: number; seed: number; color: string; shift: number; step?: number}> = ({y, h, seed, color, shift, step = 48}) => {
	let d = `M -60 ${y}`;
	for (let i = 0; i <= Math.ceil((W + 200) / step); i++) {
		const x = -60 + i * step + shift;
		const n = Math.sin(i * 1.7 + seed) * 0.5 + Math.sin(i * 0.63 + seed * 2.1) * 0.35 + Math.sin(i * 3.1 + seed) * 0.15;
		d += ` L ${x.toFixed(1)} ${(y - h * (0.3 + 0.7 * Math.abs(n))).toFixed(1)}`;
	}
	d += ` L ${W + 200} ${y} Z`;
	return <path d={d} fill={color} />;
};

const Gull: React.FC<{x: number; y: number; s: number; flap: number; color?: string}> = ({x, y, s, flap, color = '#1a1418'}) => {
	const w = Math.sin(flap) * 6 * s;
	return (
		<path
			d={`M ${x - 12 * s} ${y - w} Q ${x - 5 * s} ${y - 7 * s - w} ${x} ${y} Q ${x + 5 * s} ${y - 7 * s - w} ${x + 12 * s} ${y - w}`}
			stroke={color}
			strokeWidth={1.8 * s}
			fill="none"
			strokeLinecap="round"
		/>
	);
};

// 天上的云：几团模糊的椭圆，边缘被夕阳照亮
const Clouds: React.FC<{t: number; shift: number}> = ({t, shift}) => (
	<g filter="url(#blur14)">
		{Array.from({length: 9}).map((_, i) => {
			const x = ((rnd(i) * 1800 - t * (6 + i * 1.5) + shift * (0.3 + rnd(i + 9) * 0.4)) % 1800) - 200;
			const y = 60 + rnd(i + 3) * 200;
			const rx = 120 + rnd(i + 5) * 200;
			const ry = 18 + rnd(i + 7) * 26;
			return (
				<g key={i}>
					<ellipse cx={x} cy={y} rx={rx} ry={ry} fill="#3a2b4a" opacity={0.75} />
					<ellipse cx={x + 20} cy={y + ry * 0.5} rx={rx * 0.8} ry={ry * 0.35} fill="#ff9a62" opacity={0.35 + (y / 260) * 0.3} />
				</g>
			);
		})}
	</g>
);

// 夕阳的光束：从太阳放射出去的几条半透明扇形，慢慢转
const GodRays: React.FC<{cx: number; cy: number; t: number; o: number}> = ({cx, cy, t, o}) => (
	<g opacity={o} filter="url(#blur6)" style={{mixBlendMode: 'screen'}}>
		{Array.from({length: 12}).map((_, i) => {
			const a0 = (i / 12) * Math.PI * 2 + t * 0.05;
			const a1 = a0 + 0.08 + rnd(i) * 0.06;
			const r = 900;
			return (
				<path
					key={i}
					d={`M ${cx} ${cy} L ${cx + Math.cos(a0) * r} ${cy + Math.sin(a0) * r} L ${cx + Math.cos(a1) * r} ${cy + Math.sin(a1) * r} Z`}
					fill="url(#ray)"
					opacity={0.35 + 0.25 * Math.sin(t * 1.3 + i)}
				/>
			);
		})}
	</g>
);

// 远处的岛：山、塔、大树
const Isle: React.FC<{color: string; lit?: number; t: number}> = ({color, lit = 0, t}) => (
	<g>
		<path d="M -260 0 Q -200 -40 -130 -52 Q -60 -90 10 -70 Q 80 -120 150 -64 Q 220 -40 280 0 Z" fill={color} />
		{/* 塔 */}
		<g transform="translate(40 -84)">
			{[0, 1, 2, 3, 4].map((k) => (
				<g key={k} transform={`translate(0 ${-k * 22})`}>
					<rect x={-16 + k * 2} y={-14} width={32 - k * 4} height={14} fill={color} />
					<path d={`M ${-28 + k * 3} -14 L ${28 - k * 3} -14 L ${18 - k * 3} -22 L ${-18 + k * 3} -22 Z`} fill={color} />
					<circle cx={0} cy={-7} r={2.6} fill="#ffb35c" opacity={(0.5 + 0.4 * Math.sin(t * 4 + k)) * (1 - lit * 0.5)} />
				</g>
			))}
			<path d="M -2 -110 L 2 -110 L 0 -140 Z" fill={color} />
		</g>
		{/* 大树 */}
		<g transform="translate(-140 -44) scale(0.7)">
			<path d="M -7 6 L -4 -60 L 4 -60 L 7 6 Z" fill={color} />
			<ellipse cx={0} cy={-80} rx={60} ry={34} fill={color} />
			<ellipse cx={-34} cy={-66} rx={34} ry={20} fill={color} />
			<ellipse cx={36} cy={-64} rx={36} ry={22} fill={color} />
		</g>
	</g>
);

// 船：侧面的乌篷船，船上三个魂师剪影，一个撑篙、一个提灯、一个坐着；桨一下下划
const Boat: React.FC<{frame: number; detail: number}> = ({frame, detail}) => {
	const stroke = Math.sin(frame / 9);
	const glow = 0.8 + Math.sin(frame / 3.3) * 0.12 + Math.sin(frame / 1.7) * 0.06;
	return (
		<g>
			<circle cx={96} cy={-58} r={70} fill="url(#lanternGlow)" opacity={glow} />
			{/* 船身 */}
			<path d="M -130 -12 Q -80 26 0 28 Q 90 28 142 -22 L 130 -22 Q 80 6 0 8 Q -75 8 -118 -16 Z" fill="#1e1611" />
			<path d="M -130 -12 Q -80 18 0 19 Q 90 18 142 -22" stroke="#7a5532" strokeWidth={2.4} fill="none" />
			<path d="M -118 -16 Q -75 4 0 5 Q 80 4 130 -22" stroke="#3a2a1c" strokeWidth={1.4} fill="none" />
			{/* 黑篷 */}
			<path d="M -64 -8 Q -62 -60 -10 -64 Q 44 -62 52 -8 Z" fill="#0d0b0e" />
			<path d="M -56 -12 Q -52 -52 -10 -56 Q 36 -54 43 -12" stroke="#40342c" strokeWidth={2} fill="none" />
			{detail > 0.5 &&
				[-40, -20, 0, 20].map((x) => <path key={x} d={`M ${x} -10 Q ${x + 2} -38 ${x + 4} -58`} stroke="#2a2220" strokeWidth={1.4} fill="none" />)}
			{/* 船尾撑篙的人 */}
			<g transform={`translate(-96 -14) rotate(${stroke * 6})`}>
				<path d="M -7 0 L -4 -34 L 6 -34 L 9 0 Z" fill="#141013" />
				<circle cx={1} cy={-40} r={6.5} fill="#141013" />
				<path d="M -12 -42 L 14 -42 L 1 -52 Z" fill="#2c231d" />
				<line x1={2} y1={-28} x2={-34} y2={56} stroke="#3b2a1c" strokeWidth={2.6} />
			</g>
			{/* 船头提灯的人 */}
			<g transform="translate(70 -16)">
				<path d="M -7 0 L -5 -36 L 7 -36 L 9 0 Z" fill="#141013" />
				<circle cx={1} cy={-43} r={6.5} fill="#141013" />
				<path d="M 4 -30 L 22 -40" stroke="#141013" strokeWidth={4} strokeLinecap="round" />
				<line x1={22} y1={-40} x2={26} y2={-30} stroke="#2a1f18" strokeWidth={1.5} />
				<ellipse cx={26} cy={-24} rx={7} ry={9} fill="#ff9a3c" opacity={glow} />
				<ellipse cx={26} cy={-24} rx={3.5} ry={5.5} fill="#ffe2a6" />
			</g>
			{/* 坐在篷前的人 */}
			<g transform="translate(34 -12)">
				<path d="M -9 0 Q -10 -20 0 -24 Q 10 -20 9 0 Z" fill="#141013" />
				<circle cx={0} cy={-30} r={6} fill="#141013" />
			</g>
			{/* 侧桨 */}
			<g transform={`translate(-30 2) rotate(${20 + stroke * 22})`}>
				<line x1={0} y1={0} x2={0} y2={46} stroke="#3b2a1c" strokeWidth={3} />
				<ellipse cx={0} cy={50} rx={4} ry={9} fill="#3b2a1c" />
			</g>
		</g>
	);
};

// 飘起来的蓝色魂光
const SoulMotes: React.FC<{t: number; n: number; y0: number; spread: number; x0: number}> = ({t, n, y0, spread, x0}) => (
	<g style={{mixBlendMode: 'screen'}}>
		{Array.from({length: n}).map((_, i) => {
			const life = (t * (0.25 + rnd(i) * 0.3) + rnd(i + 2)) % 1;
			const x = x0 + (rnd(i + 4) - 0.5) * spread + Math.sin(t * 2 + i) * 14;
			const y = y0 - life * 260;
			const o = Math.sin(life * Math.PI) * 0.9;
			return <circle key={i} cx={x} cy={y} r={2 + rnd(i + 6) * 3} fill={i % 3 === 0 ? '#ffd78a' : '#8fd6ff'} opacity={o} filter="url(#blur2)" />;
		})}
	</g>
);

const Defs: React.FC = () => (
	<defs>
		<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
			<stop offset="0" stopColor="#0d1330" />
			<stop offset="0.4" stopColor="#3e2d52" />
			<stop offset="0.78" stopColor="#d66f45" />
			<stop offset="1" stopColor="#ffbd72" />
		</linearGradient>
		<linearGradient id="sea" x1="0" y1="0" x2="0" y2="1">
			<stop offset="0" stopColor="#8a5a52" />
			<stop offset="0.2" stopColor="#3a3656" />
			<stop offset="1" stopColor="#0a1024" />
		</linearGradient>
		<radialGradient id="sun">
			<stop offset="0" stopColor="#fff6d8" />
			<stop offset="0.2" stopColor="#ffd07a" stopOpacity="0.95" />
			<stop offset="0.55" stopColor="#ff8a3d" stopOpacity="0.35" />
			<stop offset="1" stopColor="#ff6a2a" stopOpacity="0" />
		</radialGradient>
		<linearGradient id="ray" x1="0" y1="0" x2="1" y2="0">
			<stop offset="0" stopColor="#ffd9a0" stopOpacity="0.6" />
			<stop offset="1" stopColor="#ffd9a0" stopOpacity="0" />
		</linearGradient>
		<radialGradient id="lanternGlow">
			<stop offset="0" stopColor="#ffb760" stopOpacity="0.8" />
			<stop offset="1" stopColor="#ff7a2a" stopOpacity="0" />
		</radialGradient>
		<radialGradient id="vignette" cx="0.5" cy="0.5" r="0.75">
			<stop offset="0.55" stopColor="#000" stopOpacity="0" />
			<stop offset="1" stopColor="#000" stopOpacity="0.7" />
		</radialGradient>
		<linearGradient id="mist" x1="0" y1="0" x2="1" y2="0">
			<stop offset="0" stopColor="#fff" stopOpacity="0" />
			<stop offset="0.5" stopColor="#ffe9d6" stopOpacity="0.25" />
			<stop offset="1" stopColor="#fff" stopOpacity="0" />
		</linearGradient>
		<linearGradient id="pillar" x1="0" y1="0" x2="1" y2="0">
			<stop offset="0" stopColor="#ffe6a8" stopOpacity="0" />
			<stop offset="0.5" stopColor="#fff4d6" stopOpacity="0.95" />
			<stop offset="1" stopColor="#ffe6a8" stopOpacity="0" />
		</linearGradient>
		<filter id="blur2"><feGaussianBlur stdDeviation="2" /></filter>
		<filter id="blur6"><feGaussianBlur stdDeviation="6" /></filter>
		<filter id="blur14"><feGaussianBlur stdDeviation="14" /></filter>
		<filter id="blur30"><feGaussianBlur stdDeviation="30" /></filter>
		<filter id="grain">
			<feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="3" />
			<feColorMatrix type="saturate" values="0" />
		</filter>
	</defs>
);

// 镜头 1：远景
const ShotWide: React.FC<{frame: number}> = ({frame}) => {
	const t = frame / 30;
	const pan = interpolate(frame, [0, 80], [0, -120], {easing: Easing.inOut(Easing.sin)});
	const boatX = interpolate(frame, [0, 80], [300, 620]);
	const bob = Math.sin(frame / 11) * 3;
	return (
		<g>
			<rect width={W} height={HORIZON + 4} fill="url(#sky)" />
			{Array.from({length: 60}).map((_, i) => {
				const x = rnd(i) * W;
				const y = rnd(i + 30) * 200;
				const o = 0.2 + 0.4 * Math.abs(Math.sin(t * 1.3 + i));
				return <circle key={i} cx={x} cy={y} r={i % 7 === 0 ? 1.5 : 0.8} fill="#fff" opacity={o * (1 - y / 220)} />;
			})}
			<GodRays cx={860 + pan * 0.2} cy={330} t={t} o={0.7} />
			<circle cx={860 + pan * 0.2} cy={330} r={170} fill="url(#sun)" />
			<circle cx={860 + pan * 0.2} cy={330} r={34} fill="#fff4d4" />
			<Clouds t={t} shift={pan} />
			<Ridge y={HORIZON} h={90} seed={1.3} color="#3a2a40" shift={pan * 0.25} />
			<Ridge y={HORIZON} h={52} seed={4.1} color="#281e32" shift={pan * 0.45} step={40} />
			{/* 身后的岛（左边，慢慢远去） */}
			<g transform={`translate(${130 + pan * 0.7} ${HORIZON}) scale(0.7)`}>
				<Isle color="#1d1624" t={t} />
			</g>
			<rect y={HORIZON} width={W} height={H - HORIZON} fill="url(#sea)" />
			{Array.from({length: 22}).map((_, i) => {
				const y = HORIZON + 6 + i * 11;
				const w = 120 - i * 4 + Math.sin(t * 4 + i * 1.3) * 26;
				const o = 0.6 - i * 0.025;
				return <rect key={i} x={860 + pan * 0.2 - w / 2 + Math.sin(t * 2 + i) * 8} y={y} width={Math.max(w, 6)} height={2.6} rx={1.3} fill="#ffcf92" opacity={Math.max(o, 0)} />;
			})}
			{Array.from({length: 10}).map((_, i) => {
				const y = HORIZON + 16 + i * i * 3.4;
				return <path key={i} d={wave(y, 1 + i * 0.9, 110 + i * 34, t * (1.2 + i * 0.25) + i)} stroke={i < 4 ? '#8a6a7a' : '#4b5e86'} strokeOpacity={0.22 + i * 0.05} strokeWidth={1 + i * 0.28} fill="none" />;
			})}
			{/* 小小的船和水痕 */}
			{Array.from({length: 8}).map((_, i) => (
				<path key={i} d={`M ${boatX - 50 - i * 16} ${472 + bob * 0.2} q 8 ${-(3 + i)} 16 0`} stroke="#cfd8ff" strokeOpacity={Math.max(0.5 - i * 0.06, 0)} strokeWidth={1.4} fill="none" />
			))}
			<g transform={`translate(${boatX} ${468 + bob}) scale(0.45)`}>
				<Boat frame={frame} detail={0} />
			</g>
			<path d={wave(560, 6, 260, t * 2.2) + ` L ${W + 40} ${H} L -40 ${H} Z`} fill="#0e1730" opacity={0.85} />
			<path d={wave(560, 6, 260, t * 2.2)} stroke="#9fb4ff" strokeOpacity={0.3} strokeWidth={1.5} fill="none" />
			<Gull x={200 + t * 90} y={190 - Math.sin(t) * 12} s={1.3} flap={t * 9} />
			<Gull x={120 + t * 80} y={220 - Math.sin(t + 1) * 9} s={1.0} flap={t * 9 + 1.2} />
			<Gull x={60 + t * 95} y={170 - Math.sin(t + 2) * 8} s={0.8} flap={t * 10 + 2.4} />
			<rect x={-300 + ((t * 50) % 900)} y={HORIZON - 36} width={900} height={50} fill="url(#mist)" />
		</g>
	);
};

// 镜头 2：近景，船从左往右划过镜头
const ShotClose: React.FC<{frame: number}> = ({frame}) => {
	const t = frame / 30;
	const boatX = interpolate(frame, [0, 70], [380, 820], {easing: Easing.inOut(Easing.cubic)});
	const bob = Math.sin(frame / 10) * 6;
	const tilt = Math.sin(frame / 12 + 0.6) * 2.5;
	const stroke = Math.sin(frame / 9);
	return (
		<g>
			<rect width={W} height={H} fill="url(#sky)" />
			<circle cx={1050} cy={300} r={240} fill="url(#sun)" opacity={0.8} />
			<Clouds t={t + 5} shift={-t * 60} />
			<Ridge y={420} h={60} seed={2.2} color="#2c2138" shift={-t * 30} />
			<rect y={418} width={W} height={H - 418} fill="url(#sea)" />
			{Array.from({length: 8}).map((_, i) => (
				<path key={i} d={wave(430 + i * i * 4.5, 2 + i, 140 + i * 40, t * (2 + i * 0.3) + i)} stroke="#6e6c96" strokeOpacity={0.25 + i * 0.04} strokeWidth={1.2 + i * 0.3} fill="none" />
			))}
			{/* 船尾拖出的白浪 */}
			{Array.from({length: 10}).map((_, i) => {
				const back = 40 + i * 34;
				const spread = 8 + i * 7;
				return (
					<path
						key={i}
						d={`M ${boatX - 150 - back} ${560 + bob * 0.3 - spread * 0.2} q 16 ${-spread * 0.5} 32 0 M ${boatX - 150 - back} ${572 + bob * 0.3 + spread * 0.3} q 16 ${spread * 0.4} 32 0`}
						stroke="#dfe6ff"
						strokeOpacity={Math.max(0.6 - i * 0.06, 0)}
						strokeWidth={2.2}
						fill="none"
					/>
				);
			})}
			<g transform={`translate(${boatX} ${556 + bob}) rotate(${tilt}) scale(1.9)`}>
				<Boat frame={frame} detail={1} />
			</g>
			{/* 桨划起的水花 */}
			{stroke > 0.6 &&
				Array.from({length: 14}).map((_, i) => {
					const k = (stroke - 0.6) / 0.4;
					return <circle key={i} cx={boatX - 60 + (rnd(i) - 0.5) * 60 + k * 30} cy={610 - k * 40 * rnd(i + 3) + k * k * 30} r={2 + rnd(i + 5) * 2.5} fill="#e6eeff" opacity={1 - k * 0.6} />;
				})}
			<SoulMotes t={t} n={26} y0={560} spread={260} x0={boatX + 40} />
			{/* 前景的浪（很快地从镜头前滑过） */}
			<path d={wave(640, 12, 300, t * 4.5) + ` L ${W + 40} ${H} L -40 ${H} Z`} fill="#0c1428" opacity={0.92} />
			<path d={wave(640, 12, 300, t * 4.5)} stroke="#a9bcff" strokeOpacity={0.4} strokeWidth={2} fill="none" />
			<path d={wave(690, 16, 380, t * 5.5 + 2) + ` L ${W + 40} ${H} L -40 ${H} Z`} fill="#070c1c" />
		</g>
	);
};

// 镜头 3：目的地的岛，天上一圈魂环光，光柱冲天
const ShotIsle: React.FC<{frame: number}> = ({frame}) => {
	const t = frame / 30;
	const push = interpolate(frame, [0, 60], [1.0, 1.35], {easing: Easing.inOut(Easing.sin)});
	const ring = interpolate(frame, [8, 34], [0, 1], clamp);
	const pillar = interpolate(frame, [24, 40], [0, 1], clamp);
	return (
		<g transform={`translate(${W / 2} ${HORIZON}) scale(${push}) translate(${-W / 2} ${-HORIZON})`}>
			<rect width={W} height={HORIZON + 4} fill="url(#sky)" />
			<Clouds t={t + 11} shift={0} />
			<rect y={HORIZON} width={W} height={H - HORIZON} fill="url(#sea)" />
			{/* 光柱 */}
			<rect x={W / 2 + 40 - 60 * pillar} y={-100} width={120 * pillar} height={HORIZON - 40} fill="url(#pillar)" opacity={pillar} filter="url(#blur6)" />
			{/* 魂环光：几圈颜色不同的椭圆在岛上空转 */}
			<g transform={`translate(${W / 2 + 40} ${HORIZON - 190})`} opacity={ring} style={{mixBlendMode: 'screen'}}>
				{['#ffffff', '#ffd23f', '#b25cff', '#b25cff', '#c0141e'].map((c, i) => (
					<ellipse key={i} cx={0} cy={i * 22 - 40} rx={(90 + i * 26) * ring} ry={(16 + i * 4) * ring} fill="none" stroke={c} strokeWidth={5} opacity={0.85} filter="url(#blur2)" transform={`rotate(${Math.sin(t * 1.5 + i) * 4})`} />
				))}
				<circle cx={0} cy={0} r={160 * ring} fill="url(#sun)" opacity={0.35} />
			</g>
			<g transform={`translate(${W / 2 + 40} ${HORIZON + 4}) scale(1.6)`}>
				<Isle color="#150f1b" lit={ring} t={t} />
			</g>
			{Array.from({length: 8}).map((_, i) => (
				<path key={i} d={wave(HORIZON + 20 + i * i * 4, 1 + i, 120 + i * 36, t * (1.4 + i * 0.3) + i)} stroke="#6b6a90" strokeOpacity={0.25 + i * 0.05} strokeWidth={1 + i * 0.3} fill="none" />
			))}
			<SoulMotes t={t} n={40} y0={HORIZON} spread={700} x0={W / 2} />
		</g>
	);
};

export const Voyage: React.FC = () => {
	const frame = useCurrentFrame();
	// 三个镜头：0~80、72~142、134~180，中间 8 帧交叉淡入
	const a = interpolate(frame, [72, 80], [1, 0], clamp);
	const b = interpolate(frame, [72, 80, 134, 142], [0, 1, 1, 0], clamp);
	const c = interpolate(frame, [134, 142], [0, 1], clamp);
	const flash = interpolate(frame, [166, 173, 180], [0, 0.9, 1], clamp);
	const fadeIn = interpolate(frame, [0, 10], [1, 0], clamp);
	return (
		<AbsoluteFill style={{backgroundColor: '#05070f'}}>
			<svg width={W} height={H} viewBox={`0 0 ${W} ${H}`}>
				<Defs />
				{a > 0 && (
					<g opacity={a}>
						<ShotWide frame={frame} />
					</g>
				)}
				{b > 0 && (
					<g opacity={b}>
						<ShotClose frame={frame - 72} />
					</g>
				)}
				{c > 0 && (
					<g opacity={c}>
						<ShotIsle frame={frame - 134} />
					</g>
				)}
				<rect width={W} height={H} fill="url(#vignette)" />
				<rect width={W} height={H} filter="url(#grain)" opacity={0.06} />
				{/* 电影黑边 */}
				<rect width={W} height={62} fill="#000" />
				<rect y={H - 62} width={W} height={62} fill="#000" />
				<rect width={W} height={H} fill="#fff6e0" opacity={flash * 0.8} />
				<rect width={W} height={H} fill="#000" opacity={Math.max(fadeIn, interpolate(frame, [174, 180], [0, 1], clamp))} />
			</svg>
		</AbsoluteFill>
	);
};
