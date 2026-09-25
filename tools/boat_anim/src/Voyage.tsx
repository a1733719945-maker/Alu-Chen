import React from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';

// 开船过场：黄昏的海面，一条乌篷船挂着灯笼从左往右划向远处的岛。
// 全部用 SVG 画：天空渐变、落日、远山、目的地的岛和塔、层层海浪、日光倒影、船、船尾水痕、海鸥、雾。
// 不放文字（章节名由游戏叠在上面，一段动画五章通用）。

const W = 960;
const H = 540;
const HORIZON = 300;

const wave = (y: number, amp: number, len: number, phase: number, x0 = -20, x1 = W + 20) => {
	let d = `M ${x0} ${y}`;
	for (let x = x0; x <= x1; x += 8) {
		const yy = y + Math.sin((x / len) * Math.PI * 2 + phase) * amp + Math.sin((x / (len * 0.43)) * Math.PI * 2 - phase * 1.7) * amp * 0.35;
		d += ` L ${x} ${yy.toFixed(1)}`;
	}
	return d;
};

const Mountains: React.FC<{y: number; h: number; seed: number; color: string; shift: number}> = ({y, h, seed, color, shift}) => {
	let d = `M -40 ${y}`;
	for (let i = 0; i <= 26; i++) {
		const x = -40 + i * 42 + shift;
		const n = Math.sin(i * 1.7 + seed) * 0.5 + Math.sin(i * 0.63 + seed * 2.1) * 0.35 + Math.sin(i * 3.1 + seed) * 0.15;
		d += ` L ${x} ${y - h * (0.35 + 0.65 * Math.abs(n))}`;
	}
	d += ` L ${W + 80} ${y} Z`;
	return <path d={d} fill={color} />;
};

const Gull: React.FC<{x: number; y: number; s: number; flap: number}> = ({x, y, s, flap}) => {
	const w = Math.sin(flap) * 5 * s;
	return (
		<path
			d={`M ${x - 10 * s} ${y - w} Q ${x - 4 * s} ${y - 6 * s - w} ${x} ${y} Q ${x + 4 * s} ${y - 6 * s - w} ${x + 10 * s} ${y - w}`}
			stroke="#1a1418"
			strokeWidth={1.6 * s}
			fill="none"
			strokeLinecap="round"
		/>
	);
};

// 乌篷船：弯弯的船身、黑色拱形篷、船尾一个撑篙的人、船头一盏灯笼
const Boat: React.FC<{frame: number}> = ({frame}) => {
	const pole = Math.sin(frame / 14) * 0.25;
	const glow = 0.8 + Math.sin(frame / 3.3) * 0.12 + Math.sin(frame / 1.7) * 0.06;
	return (
		<g>
			{/* 灯笼的光晕 */}
			<circle cx={78} cy={-38} r={46} fill="url(#lanternGlow)" opacity={glow} />
			{/* 船身 */}
			<path d="M -95 -8 Q -60 18 0 20 Q 70 20 105 -14 L 96 -14 Q 60 4 0 6 Q -55 6 -86 -12 Z" fill="#241a14" />
			<path d="M -95 -8 Q -60 12 0 13 Q 70 12 105 -14" stroke="#6b4a2c" strokeWidth={2} fill="none" />
			{/* 黑篷 */}
			<path d="M -50 -6 Q -48 -44 -8 -48 Q 34 -46 40 -6 Z" fill="#0f0d10" />
			<path d="M -44 -10 Q -40 -38 -8 -41 Q 28 -40 33 -10" stroke="#3a2f2a" strokeWidth={2} fill="none" />
			{[-30, -12, 6, 22].map((x) => (
				<path key={x} d={`M ${x} -8 Q ${x + 2} -30 ${x + 4} -44`} stroke="#2a2220" strokeWidth={1.4} fill="none" />
			))}
			{/* 船尾撑篙的人 */}
			<g transform={`translate(-72 -10) rotate(${pole * 20})`}>
				<path d="M -5 0 L -3 -26 L 5 -26 L 7 0 Z" fill="#171214" />
				<circle cx={1} cy={-31} r={5} fill="#171214" />
				<path d="M -9 -33 L 11 -33 L 1 -40 Z" fill="#2c231d" />
				<line x1={2} y1={-22} x2={-26} y2={40} stroke="#3b2a1c" strokeWidth={2.2} />
			</g>
			{/* 船头灯笼 */}
			<line x1={70} y1={-12} x2={78} y2={-44} stroke="#2a1f18" strokeWidth={2} />
			<ellipse cx={78} cy={-38} rx={6} ry={8} fill="#ff9a3c" opacity={glow} />
			<ellipse cx={78} cy={-38} rx={3} ry={5} fill="#ffe2a6" />
		</g>
	);
};

export const Voyage: React.FC = () => {
	const frame = useCurrentFrame();
	const {durationInFrames} = useVideoConfig();
	const t = frame / 30;
	const boatX = interpolate(frame, [0, durationInFrames], [150, 700], {easing: Easing.inOut(Easing.cubic)});
	const bob = Math.sin(frame / 11) * 3.5;
	const tilt = Math.sin(frame / 13 + 0.6) * 2.2;
	const sunY = interpolate(frame, [0, durationInFrames], [238, 262]);
	const islandScale = interpolate(frame, [0, durationInFrames], [0.8, 1.15]);
	const fade = interpolate(frame, [0, 10, durationInFrames - 14, durationInFrames], [1, 0, 0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});

	return (
		<AbsoluteFill style={{backgroundColor: '#0c1020'}}>
			<svg width={W} height={H} viewBox={`0 0 ${W} ${H}`}>
				<defs>
					<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
						<stop offset="0" stopColor="#141b36" />
						<stop offset="0.45" stopColor="#4a3552" />
						<stop offset="0.8" stopColor="#d9784a" />
						<stop offset="1" stopColor="#f6b36a" />
					</linearGradient>
					<linearGradient id="sea" x1="0" y1="0" x2="0" y2="1">
						<stop offset="0" stopColor="#6d4a4e" />
						<stop offset="0.25" stopColor="#2f3350" />
						<stop offset="1" stopColor="#0d1428" />
					</linearGradient>
					<radialGradient id="sun">
						<stop offset="0" stopColor="#fff2c8" />
						<stop offset="0.25" stopColor="#ffc56e" stopOpacity="0.95" />
						<stop offset="0.6" stopColor="#ff8a3d" stopOpacity="0.35" />
						<stop offset="1" stopColor="#ff6a2a" stopOpacity="0" />
					</radialGradient>
					<radialGradient id="lanternGlow">
						<stop offset="0" stopColor="#ffb760" stopOpacity="0.85" />
						<stop offset="1" stopColor="#ff7a2a" stopOpacity="0" />
					</radialGradient>
					<radialGradient id="vignette" cx="0.5" cy="0.5" r="0.75">
						<stop offset="0.6" stopColor="#000" stopOpacity="0" />
						<stop offset="1" stopColor="#000" stopOpacity="0.65" />
					</radialGradient>
					<linearGradient id="mist" x1="0" y1="0" x2="1" y2="0">
						<stop offset="0" stopColor="#fff" stopOpacity="0" />
						<stop offset="0.5" stopColor="#ffe9d6" stopOpacity="0.22" />
						<stop offset="1" stopColor="#fff" stopOpacity="0" />
					</linearGradient>
				</defs>

				{/* 天空、星星、落日 */}
				<rect width={W} height={HORIZON + 4} fill="url(#sky)" />
				{Array.from({length: 40}).map((_, i) => {
					const x = (i * 197.3) % W;
					const y = (i * 61.7) % 150;
					const o = 0.25 + 0.35 * Math.abs(Math.sin(t * 1.3 + i));
					return <circle key={i} cx={x} cy={y} r={i % 5 === 0 ? 1.4 : 0.8} fill="#fff" opacity={o * (1 - y / 170)} />;
				})}
				<circle cx={640} cy={sunY} r={120} fill="url(#sun)" />
				<circle cx={640} cy={sunY} r={26} fill="#fff1cf" />

				{/* 远山（两层，慢慢往左移，有纵深） */}
				<Mountains y={HORIZON} h={70} seed={1.3} color="#3b2a3e" shift={-t * 4} />
				<Mountains y={HORIZON} h={42} seed={4.1} color="#2a2033" shift={-t * 9} />

				{/* 目的地的岛：一座塔 + 几棵树，越划越近 */}
				<g transform={`translate(820 ${HORIZON}) scale(${islandScale})`}>
					<path d="M -120 0 Q -80 -26 -30 -30 Q 20 -44 60 -28 Q 100 -18 130 0 Z" fill="#1b1522" />
					<path d="M 10 -30 L 10 -78 M 0 -52 L 20 -52 M -3 -64 L 23 -64 M 2 -76 L 18 -76" stroke="#1b1522" strokeWidth={6} />
					<path d="M -6 -42 L 26 -42 L 10 -50 Z M -8 -56 L 28 -56 L 10 -64 Z M -4 -70 L 24 -70 L 10 -80 Z" fill="#1b1522" />
					<circle cx={-60} cy={-34} r={14} fill="#1b1522" />
					<circle cx={-44} cy={-40} r={11} fill="#1b1522" />
					<circle cx={70} cy={-30} r={12} fill="#1b1522" />
					<circle cx={10} cy={-60} r={3} fill="#ffb35c" opacity={0.6 + 0.3 * Math.sin(t * 5)} />
				</g>

				{/* 海 */}
				<rect y={HORIZON} width={W} height={H - HORIZON} fill="url(#sea)" />
				{/* 落日倒影：一条条闪烁的光 */}
				{Array.from({length: 18}).map((_, i) => {
					const y = HORIZON + 6 + i * 9;
					const w = 80 - i * 3 + Math.sin(t * 4 + i * 1.3) * 18;
					const o = 0.55 - i * 0.028;
					return <rect key={i} x={640 - w / 2 + Math.sin(t * 2 + i) * 6} y={y} width={Math.max(w, 6)} height={2.2} rx={1} fill="#ffc98a" opacity={Math.max(o, 0)} />;
				})}
				{/* 一层层海浪（越近越大越快） */}
				{Array.from({length: 9}).map((_, i) => {
					const y = HORIZON + 14 + i * i * 3.2;
					const amp = 1 + i * 0.9;
					const len = 90 + i * 30;
					return (
						<path key={i} d={wave(y, amp, len, t * (1.2 + i * 0.25) + i)} stroke={i < 4 ? '#8a6a7a' : '#4b5e86'} strokeOpacity={0.25 + i * 0.05} strokeWidth={1 + i * 0.25} fill="none" />
					);
				})}

				{/* 船后面的水痕 */}
				{Array.from({length: 7}).map((_, i) => {
					const back = 24 + i * 22;
					const o = 0.5 - i * 0.065;
					const spread = 6 + i * 5;
					return (
						<path
							key={i}
							d={`M ${boatX - 90 - back} ${412 + bob * 0.3 - spread * 0.2} q 10 ${-spread * 0.5} 20 0 M ${boatX - 90 - back} ${420 + bob * 0.3 + spread * 0.3} q 10 ${spread * 0.4} 20 0`}
							stroke="#cfd8ff"
							strokeOpacity={Math.max(o, 0)}
							strokeWidth={1.6}
							fill="none"
						/>
					);
				})}

				{/* 船 */}
				<g transform={`translate(${boatX} ${410 + bob}) rotate(${tilt}) scale(1.35)`}>
					<Boat frame={frame} />
				</g>
				{/* 船身在水里的倒影 */}
				<g transform={`translate(${boatX} ${440 + bob}) scale(1.35 -0.55)`} opacity={0.18}>
					<Boat frame={frame} />
				</g>

				{/* 前景的大浪，挡住一点船底 */}
				<path d={wave(446, 5, 220, t * 2.2) + ` L ${W + 20} ${H} L -20 ${H} Z`} fill="#0f1830" opacity={0.85} />
				<path d={wave(470, 7, 260, t * 2.6 + 1.5) + ` L ${W + 20} ${H} L -20 ${H} Z`} fill="#0b1226" />
				<path d={wave(446, 5, 220, t * 2.2)} stroke="#9fb4ff" strokeOpacity={0.35} strokeWidth={1.4} fill="none" />

				{/* 海鸥 */}
				<Gull x={120 + t * 70} y={150 - Math.sin(t) * 10} s={1.2} flap={t * 9} />
				<Gull x={60 + t * 62} y={175 - Math.sin(t + 1) * 8} s={0.9} flap={t * 9 + 1.2} />
				<Gull x={20 + t * 75} y={132 - Math.sin(t + 2) * 7} s={0.8} flap={t * 10 + 2.4} />

				{/* 雾带 */}
				<rect x={-300 + ((t * 40) % 600)} y={HORIZON - 30} width={700} height={40} fill="url(#mist)" />
				<rect x={600 - ((t * 25) % 800)} y={HORIZON + 20} width={600} height={30} fill="url(#mist)" opacity={0.7} />

				<rect width={W} height={H} fill="url(#vignette)" />
				<rect width={W} height={H} fill="#000" opacity={fade} />
			</svg>
		</AbsoluteFill>
	);
};
