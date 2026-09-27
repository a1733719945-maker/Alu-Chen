import React from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame} from 'remotion';
import {W, H} from './Voyage';

// 成神结局（10 秒）：
//   夜空和山巅，一个魂师的背影；十个魂环从脚下一个接一个升起；
//   天上打下一道神光，身后展开六对光翼、头顶光轮，天空变成金色，最后白光。
// 文字（"成神"）由游戏叠在上面。

const clamp = {extrapolateLeft: 'clamp' as const, extrapolateRight: 'clamp' as const};
const rnd = (i: number) => {
	const s = Math.sin(i * 127.1 + 311.7) * 43758.5453;
	return s - Math.floor(s);
};

// 和游戏里一样：第一环十年（白）、二三环百年（黄）、四五环千年（紫）、六到九环万年（黑，发暗红光）、第十环十万年（红）
const RINGS = ['#f2f2ea', '#ffd23f', '#ffd23f', '#b25cff', '#b25cff', '#1a0f14', '#1a0f14', '#1a0f14', '#1a0f14', '#ff1a14'];
const GLOWS = ['#ffffff', '#ffd23f', '#ffd23f', '#b25cff', '#b25cff', '#c0141e', '#c0141e', '#c0141e', '#c0141e', '#ff3a20'];

const CX = W / 2;
const FOOT = 560;

export const Ending: React.FC = () => {
	const f = useCurrentFrame();
	const t = f / 30;
	const gold = interpolate(f, [190, 250], [0, 1], clamp);
	const pillar = interpolate(f, [180, 200], [0, 1], clamp);
	const wings = interpolate(f, [200, 245], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
	const halo = interpolate(f, [215, 240], [0, 1], clamp);
	const flash = interpolate(f, [272, 290, 300], [0, 1, 1], clamp);
	const fadeIn = interpolate(f, [0, 20], [1, 0], clamp);
	const cam = interpolate(f, [0, 300], [1.0, 1.18], {easing: Easing.inOut(Easing.sin)});
	return (
		<AbsoluteFill style={{backgroundColor: '#03040a'}}>
			<svg width={W} height={H} viewBox={`0 0 ${W} ${H}`}>
				<defs>
					<linearGradient id="night" x1="0" y1="0" x2="0" y2="1">
						<stop offset="0" stopColor="#04061a" />
						<stop offset="0.7" stopColor="#1a1638" />
						<stop offset="1" stopColor="#3a2a4a" />
					</linearGradient>
					<linearGradient id="heaven" x1="0" y1="0" x2="0" y2="1">
						<stop offset="0" stopColor="#fff3c4" />
						<stop offset="0.5" stopColor="#ffc86a" />
						<stop offset="1" stopColor="#c7743a" />
					</linearGradient>
					<linearGradient id="beam" x1="0" y1="0" x2="1" y2="0">
						<stop offset="0" stopColor="#fff2c0" stopOpacity="0" />
						<stop offset="0.5" stopColor="#ffffff" stopOpacity="1" />
						<stop offset="1" stopColor="#fff2c0" stopOpacity="0" />
					</linearGradient>
					<radialGradient id="aura">
						<stop offset="0" stopColor="#fff6d0" stopOpacity="0.9" />
						<stop offset="0.4" stopColor="#ffcf6a" stopOpacity="0.45" />
						<stop offset="1" stopColor="#ff9a3a" stopOpacity="0" />
					</radialGradient>
					<linearGradient id="feather" x1="0" y1="0" x2="1" y2="0">
						<stop offset="0" stopColor="#fffbe8" stopOpacity="0.95" />
						<stop offset="1" stopColor="#ffd07a" stopOpacity="0.1" />
					</linearGradient>
					<filter id="b2"><feGaussianBlur stdDeviation="2" /></filter>
					<filter id="b6"><feGaussianBlur stdDeviation="6" /></filter>
					<filter id="b20"><feGaussianBlur stdDeviation="20" /></filter>
				</defs>
				<g transform={`translate(${CX} ${FOOT}) scale(${cam}) translate(${-CX} ${-FOOT})`}>
					<rect width={W} height={H} fill="url(#night)" />
					<rect width={W} height={H} fill="url(#heaven)" opacity={gold} />
					{/* 星星 */}
					{Array.from({length: 90}).map((_, i) => (
						<circle key={i} cx={rnd(i) * W} cy={rnd(i + 50) * 420} r={i % 9 === 0 ? 1.6 : 0.8} fill="#fff" opacity={(0.3 + 0.5 * Math.abs(Math.sin(t * 1.5 + i))) * (1 - gold)} />
					))}
					{/* 云海 */}
					<g filter="url(#b20)">
						{Array.from({length: 10}).map((_, i) => (
							<ellipse key={i} cx={((rnd(i) * 1600 + t * (8 + i * 2)) % 1600) - 160} cy={560 + rnd(i + 20) * 90} rx={220 + rnd(i + 3) * 160} ry={40 + rnd(i + 7) * 30} fill={gold > 0.5 ? '#ffe2a8' : '#3b3358'} opacity={0.7} />
						))}
					</g>
					{/* 山巅 */}
					<path d={`M ${CX - 420} ${H} L ${CX - 150} ${FOOT + 40} L ${CX - 40} ${FOOT + 4} L ${CX + 40} ${FOOT + 6} L ${CX + 170} ${FOOT + 50} L ${CX + 460} ${H} Z`} fill="#0b0912" />
					{/* 天上打下来的神光 */}
					<rect x={CX - 90 * pillar} y={-40} width={180 * pillar} height={FOOT + 40} fill="url(#beam)" opacity={pillar} filter="url(#b6)" />
					<circle cx={CX} cy={FOOT - 90} r={260 * (0.4 + gold * 0.8)} fill="url(#aura)" opacity={0.4 + pillar * 0.6} />
					{/* 六对光翼 */}
					{[0, 1, 2].map((k) =>
						[-1, 1].map((s) => {
							const a = (-12 - k * 28) * wings;
							return (
								<g key={`${k}${s}`} transform={`translate(${CX + s * 14} ${FOOT - 170 + k * 26}) scale(${s} 1) rotate(${a})`} opacity={wings}>
									{Array.from({length: 8}).map((_, j) => (
										<path key={j} d={`M 0 0 Q ${90 + j * 30} ${-44 + j * 10} ${(330 - k * 50) * wings} ${-14 + j * 18} Q ${120 + j * 14} ${14 + j * 8} 0 8 Z`} fill="url(#feather)" opacity={0.8 - j * 0.07} />
									))}
								</g>
							);
						}),
					)}
					{/* 光轮 */}
					<ellipse cx={CX} cy={FOOT - 262} rx={52 * halo} ry={14 * halo} fill="none" stroke="#fff3c0" strokeWidth={6} opacity={halo} filter="url(#b2)" />
					{/* 魂师背影 */}
					<g transform={`translate(${CX} ${FOOT}) scale(1.9)`}>
						<path d="M -22 0 Q -26 -60 -16 -100 L 16 -100 Q 26 -60 22 0 Z" fill="#07060a" />
						<path d="M -16 -100 Q -30 -96 -34 -60 L -26 -58 Q -24 -86 -14 -92 Z M 16 -100 Q 30 -96 34 -60 L 26 -58 Q 24 -86 14 -92 Z" fill="#07060a" />
						<circle cx={0} cy={-114} r={13} fill="#07060a" />
						<path d={`M -22 -8 Q ${-44 + Math.sin(t * 2) * 6} 20 ${-60 + Math.sin(t * 2.3) * 8} 30 L -18 0 Z`} fill="#07060a" />
					</g>
					{/* 十个魂环一个接一个升起 */}
					{RINGS.map((c, i) => {
						const start = 40 + i * 13;
						const k = interpolate(f, [start, start + 18], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
						if (k <= 0) return null;
						const y = FOOT - 6 - k * (6 + i * 22);
						const rx = 78 + i * 3;
						const pulse = interpolate(f, [start, start + 6, start + 20], [0, 1, 0], clamp);
						return (
							<g key={i}>
								<ellipse cx={CX} cy={y} rx={rx} ry={rx * 0.24} fill="none" stroke={GLOWS[i]} strokeWidth={9} opacity={0.5 * k} filter="url(#b6)" />
								<ellipse cx={CX} cy={y} rx={rx} ry={rx * 0.24} fill="none" stroke={c} strokeWidth={4} opacity={k} />
								<ellipse cx={CX} cy={FOOT} rx={rx * (1 + pulse * 3)} ry={rx * 0.24 * (1 + pulse * 3)} fill="none" stroke={GLOWS[i]} strokeWidth={2} opacity={pulse * 0.8} />
							</g>
						);
					})}
					{/* 金色光点往上飘 */}
					{Array.from({length: 70}).map((_, i) => {
						const life = (t * (0.18 + rnd(i) * 0.25) + rnd(i + 1)) % 1;
						const x = CX + (rnd(i + 2) - 0.5) * 900 + Math.sin(t + i) * 20;
						const y = H - life * 700;
						return <circle key={i} cx={x} cy={y} r={1.5 + rnd(i + 3) * 2.5} fill="#ffe3a0" opacity={Math.sin(life * Math.PI) * (0.4 + gold * 0.6)} filter="url(#b2)" />;
					})}
				</g>
				<rect width={W} height={62} fill="#000" />
				<rect y={H - 62} width={W} height={62} fill="#000" />
				<rect width={W} height={H} fill="#fffaf0" opacity={flash} />
				<rect width={W} height={H} fill="#000" opacity={fadeIn} />
			</svg>
		</AbsoluteFill>
	);
};
