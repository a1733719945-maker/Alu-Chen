import React from 'react';
import {useCurrentFrame} from 'remotion';
import {rnd} from './lib';

// 画剪影的办法：沿一条脊线放一串圆（前面大后面小），先画一层偏移的亮边（逆光），再画暗色本体，看起来像被背后的光勾了边
type P = [number, number];

const bez = (p0: P, p1: P, p2: P, p3: P, t: number): P => {
	const u = 1 - t;
	return [
		u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
		u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1],
	];
};

const Tube: React.FC<{pts: P[]; r0: number; r1: number; body: string; rim: string; rimOff?: P}> = ({pts, r0, r1, body, rim, rimOff = [-3, -3]}) => (
	<g>
		<g opacity={0.9}>
			{pts.map((p, i) => {
				const r = r0 + (r1 - r0) * (i / (pts.length - 1));
				return <circle key={`r${i}`} cx={p[0] + rimOff[0]} cy={p[1] + rimOff[1]} r={r + 1.5} fill={rim} />;
			})}
		</g>
		{pts.map((p, i) => {
			const r = r0 + (r1 - r0) * (i / (pts.length - 1));
			return <circle key={i} cx={p[0]} cy={p[1]} r={r} fill={body} />;
		})}
	</g>
);

const spine = (a: P, b: P, c: P, d: P, n: number): P[] => Array.from({length: n}).map((_, i) => bez(a, b, c, d, i / (n - 1)));

// ---------------------------------------------------------------- 碧鳞蛟：从湖里 S 形升起，头上两只短角、两根长须
export const Jiao: React.FC<{x: number; y: number; s: number; shard: string}> = ({x, y, s, shard}) => {
	const f = useCurrentFrame();
	const sw = Math.sin(f * 0.05) * 14;
	const pts = spine([60, 260], [180 + sw, 120], [-160 - sw, 40], [20, -170], 70);
	const head = pts[pts.length - 1];
	return (
		<g transform={`translate(${x} ${y}) scale(${s})`}>
			<Tube pts={pts.slice().reverse()} r0={16} r1={38} body="#0b1a1a" rim="#6fe3b8" rimOff={[-4, -3]} />
			{/* 背鳍：一排小三角 */}
			{pts.filter((_, i) => i % 5 === 0 && i > 8).map((p, i) => (
				<path key={i} d={`M ${p[0] - 6} ${p[1] - 20} L ${p[0]} ${p[1] - 40 + (i % 2) * 6} L ${p[0] + 6} ${p[1] - 20} Z`} fill="#0b1a1a" stroke="#6fe3b8" strokeWidth={1} opacity={0.9} />
			))}
			{/* 头 */}
			<g transform={`translate(${head[0]} ${head[1]}) rotate(-20)`}>
				<ellipse cx={24} cy={0} rx={46} ry={22} fill="#0b1a1a" stroke="#6fe3b8" strokeWidth={2} />
				<path d="M -6 -16 Q -20 -52 -2 -64" stroke="#6fe3b8" strokeWidth={4} fill="none" />
				<path d="M 12 -18 Q 8 -52 26 -60" stroke="#6fe3b8" strokeWidth={4} fill="none" />
				<path d={`M 60 8 Q 110 ${20 + sw} 150 ${-10 + sw}`} stroke="#9ff5d5" strokeWidth={1.6} fill="none" opacity={0.8} />
				<path d={`M 60 12 Q 100 ${50 - sw} 140 ${40 - sw}`} stroke="#9ff5d5" strokeWidth={1.6} fill="none" opacity={0.8} />
				<circle cx={40} cy={-6} r={5} fill="#d8ffb0" filter="url(#glow)" />
			</g>
			{/* 腹中的天枢碎片 */}
			<circle cx={pts[34][0]} cy={pts[34][1]} r={22} fill={shard} opacity={0.8} filter="url(#b10)" />
			<circle cx={pts[34][0]} cy={pts[34][1]} r={6} fill="#fff" filter="url(#b2)" />
		</g>
	);
};

// ---------------------------------------------------------------- 千目蛛母：大肚子、八条腿、头上一堆发光的眼睛
export const SpiderMother: React.FC<{x: number; y: number; s: number; shard: string}> = ({x, y, s, shard}) => {
	const f = useCurrentFrame();
	const legs: React.ReactNode[] = [];
	for (let side = -1; side <= 1; side += 2) {
		for (let k = 0; k < 4; k++) {
			const a = (-0.9 + k * 0.55) * side;
			const tw = Math.sin(f * 0.08 + k + side) * 6;
			const kx = side * (90 + k * 26);
			const ky = -60 + k * 30 + tw;
			const fx = side * (170 + k * 30);
			const fy = 120 + k * 12;
			legs.push(
				<g key={`${side}${k}`}>
					<path d={`M ${side * 30} ${a * 10} L ${kx} ${ky} L ${fx} ${fy}`} stroke="#ff7b93" strokeWidth={9} fill="none" strokeLinejoin="round" transform="translate(-2 -2)" opacity={0.7} />
					<path d={`M ${side * 30} ${a * 10} L ${kx} ${ky} L ${fx} ${fy}`} stroke="#140a10" strokeWidth={8} fill="none" strokeLinejoin="round" />
				</g>,
			);
		}
	}
	return (
		<g transform={`translate(${x} ${y}) scale(${s})`}>
			{legs}
			<ellipse cx={0} cy={40} rx={96} ry={84} fill="#ff7b93" transform="translate(-3 -3)" opacity={0.7} />
			<ellipse cx={0} cy={40} rx={96} ry={84} fill="#140a10" />
			<ellipse cx={0} cy={-40} rx={52} ry={40} fill="#ff7b93" transform="translate(-3 -3)" opacity={0.7} />
			<ellipse cx={0} cy={-40} rx={52} ry={40} fill="#140a10" />
			{/* 花纹：肚子上一张脸似的纹 */}
			<path d="M -40 30 Q 0 70 40 30" stroke="#5a1a2a" strokeWidth={4} fill="none" />
			{Array.from({length: 14}).map((_, i) => {
				const ex = -34 + (i % 7) * 11 + (i >= 7 ? 5 : 0);
				const ey = -52 + (i >= 7 ? 12 : 0) + Math.sin(i) * 3;
				const blink = Math.sin(f * 0.1 + i * 1.7) > -0.8 ? 1 : 0.2;
				return <circle key={i} cx={ex} cy={ey} r={i % 3 === 0 ? 4 : 2.6} fill="#ff3150" opacity={blink} filter="url(#glow)" />;
			})}
			<circle cx={0} cy={50} r={26} fill={shard} opacity={0.75} filter="url(#b10)" />
			<circle cx={0} cy={50} r={6} fill="#fff" filter="url(#b2)" />
		</g>
	);
};

// 一团带毛刺的轮廓（椭圆边上一圈尖刺）
const furBlob = (cx: number, cy: number, rx: number, ry: number, n: number, amp: number, seed: number, a0 = 0, a1 = Math.PI * 2) => {
	let d = '';
	for (let i = 0; i <= n; i++) {
		const a = a0 + ((a1 - a0) * i) / n;
		const out = i % 2 === 0 ? 1 : 1 + amp * (0.6 + rnd(seed + i) * 0.8);
		const x = cx + Math.cos(a) * rx * out;
		const y = cy + Math.sin(a) * ry * out;
		d += `${i ? 'L' : 'M'} ${x.toFixed(1)} ${y.toFixed(1)} `;
	}
	return d + 'Z';
};

// ---------------------------------------------------------------- 朱厌：《山海经》"其状如猿，白首赤足"。弓着背、头压低，张嘴咆哮，两只赤足、两拳撑地
export const Zhuyan: React.FC<{x: number; y: number; s: number; shard: string}> = ({x, y, s, shard}) => {
	const f = useCurrentFrame();
	const br = Math.sin(f * 0.07) * 4;
	const roar = 0.7 + 0.3 * Math.abs(Math.sin(f * 0.05));
	const rim = '#ffb46a';
	const body = '#140b08';
	const torso = furBlob(0, 20, 190, 150, 70, 0.08, 3, Math.PI, Math.PI * 2) + ' M 190 20 L 150 170 L -150 170 L -190 20 Z';
	return (
		<g transform={`translate(${x} ${y}) scale(${s})`}>
			{/* 两条粗臂：肩膀往外、往下撑到地上，拳头着地 */}
			{[-1, 1].map((sd) => (
				<g key={sd}>
					<path d={`M ${sd * 150} -40 Q ${sd * 280} 40 ${sd * 250} 200`} stroke={rim} strokeWidth={78} strokeLinecap="round" fill="none" transform="translate(-4 -4)" opacity={0.55} />
					<path d={`M ${sd * 150} -40 Q ${sd * 280} 40 ${sd * 250} 200`} stroke={body} strokeWidth={72} strokeLinecap="round" fill="none" />
					<path d={furBlob(sd * 215, 30, 40, 70, 18, 0.25, 11 + sd)} fill={body} />
					<ellipse cx={sd * 250} cy={214} rx={46} ry={22} fill="#0d0705" stroke={rim} strokeWidth={1.5} />
				</g>
			))}
			{/* 身子：弓着的背，边上一圈毛刺 */}
			<path d={torso} fill={rim} transform="translate(-5 -5)" opacity={0.55} />
			<path d={torso} fill={body} transform={`translate(0 ${br})`} />
			{/* 赤足 */}
			{[-1, 1].map((sd) => (
				<g key={`l${sd}`}>
					<rect x={sd * 90 - 34} y={150} width={68} height={60} rx={20} fill={body} />
					<path d={`M ${sd * 90 - 44} 222 Q ${sd * 90} 196 ${sd * 90 + 44} 222 Z`} fill="#d23a1e" />
					<ellipse cx={sd * 90} cy={214} rx={40} ry={10} fill="#ff5a2a" opacity={0.35} filter="url(#b6)" />
				</g>
			))}
			{/* 白首：头压在两肩之间，一圈尖刺状的白鬃，脸黑，嘴张着露出獠牙 */}
			<g transform={`translate(0 ${-88 + br})`}>
				<path d={furBlob(0, 0, 96, 84, 44, 0.32, 21)} fill="#f0ebdf" opacity={0.25} filter="url(#b10)" />
				<path d={furBlob(0, 0, 92, 80, 44, 0.3, 21)} fill="#ebe5d8" />
				<path d={furBlob(0, 6, 62, 56, 30, 0.18, 33)} fill="#d8d0c0" />
				<ellipse cx={0} cy={16} rx={44} ry={46} fill={body} />
				{/* 眉骨和怒目 */}
				<path d="M -34 -6 L -8 4 M 34 -6 L 8 4" stroke="#ebe5d8" strokeWidth={6} strokeLinecap="round" />
				<path d="M -30 6 L -12 10" stroke="#ff5a2a" strokeWidth={5} strokeLinecap="round" filter="url(#glow)" />
				<path d="M 30 6 L 12 10" stroke="#ff5a2a" strokeWidth={5} strokeLinecap="round" filter="url(#glow)" />
				{/* 张开的嘴 */}
				<ellipse cx={0} cy={38} rx={24} ry={18 * roar} fill="#5a0e08" />
				{[-14, -5, 5, 14].map((tx) => (
					<path key={tx} d={`M ${tx - 3} ${38 - 16 * roar} L ${tx} ${38 - 6 * roar} L ${tx + 3} ${38 - 16 * roar} Z`} fill="#f4efe4" />
				))}
				<path d={`M -12 ${38 + 16 * roar} L -9 ${38 + 7 * roar} L -6 ${38 + 16 * roar} Z M 6 ${38 + 16 * roar} L 9 ${38 + 7 * roar} L 12 ${38 + 16 * roar} Z`} fill="#f4efe4" />
			</g>
			{/* 胸口的天枢碎片 */}
			<circle cx={0} cy={40} r={30} fill={shard} opacity={0.8} filter="url(#b10)" />
			<circle cx={0} cy={40} r={7} fill="#fff" filter="url(#b2)" />
			{/* 咆哮的气浪 */}
			{[0, 1, 2].map((k) => {
				const t = ((f + k * 14) % 42) / 42;
				return <ellipse key={k} cx={0} cy={-50} rx={60 + t * 260} ry={24 + t * 90} fill="none" stroke="#ffcf9a" strokeWidth={2} opacity={(1 - t) * 0.35} />;
			})}
		</g>
	);
};

// ---------------------------------------------------------------- 冰螭：无角之龙，身子在冰雾里盘着，背上一排冰刺
export const IceChi: React.FC<{x: number; y: number; s: number; shard: string}> = ({x, y, s, shard}) => {
	const f = useCurrentFrame();
	const sw = Math.sin(f * 0.045) * 18;
	const pts = spine([-260, 120], [-60, -160 + sw], [120, 200 - sw], [240, -60], 80);
	const head = pts[pts.length - 1];
	return (
		<g transform={`translate(${x} ${y}) scale(${s})`}>
			<Tube pts={pts} r0={10} r1={34} body="#08121c" rim="#9fe6ff" rimOff={[-3, -4]} />
			{pts.filter((_, i) => i % 4 === 0 && i > 6).map((p, i) => (
				<path key={i} d={`M ${p[0] - 5} ${p[1] - 18} L ${p[0] + 2} ${p[1] - 42 - (i % 3) * 6} L ${p[0] + 7} ${p[1] - 18} Z`} fill="#bff2ff" opacity={0.85} />
			))}
			{/* 四条腿：粗的前后腿，爪子张开 */}
			{[18, 30, 52, 64].map((k, i) => {
				const p = pts[k];
				const dx = i % 2 === 0 ? -18 : 14;
				const kx = p[0] + dx;
				const ky = p[1] + 40;
				const fx2 = p[0] + dx * 1.6;
				const fy2 = p[1] + 78;
				return (
					<g key={i}>
						<path d={`M ${p[0]} ${p[1]} Q ${kx - 10} ${ky - 10} ${kx} ${ky} L ${fx2} ${fy2}`} stroke="#9fe6ff" strokeWidth={16} strokeLinecap="round" fill="none" transform="translate(-2 -2)" opacity={0.6} />
						<path d={`M ${p[0]} ${p[1]} Q ${kx - 10} ${ky - 10} ${kx} ${ky} L ${fx2} ${fy2}`} stroke="#08121c" strokeWidth={13} strokeLinecap="round" fill="none" />
						{[-10, 0, 10].map((cdx) => (
							<path key={cdx} d={`M ${fx2} ${fy2} q ${cdx * 0.6} 8 ${cdx * 1.2} 14`} stroke="#dff8ff" strokeWidth={3} fill="none" strokeLinecap="round" />
						))}
					</g>
				);
			})}
			<g transform={`translate(${head[0]} ${head[1]}) rotate(-35)`}>
				<path d="M -10 -24 Q 60 -30 90 0 Q 60 26 -10 24 Z" fill="#08121c" stroke="#9fe6ff" strokeWidth={2.5} />
				<path d="M 20 10 L 88 4" stroke="#9fe6ff" strokeWidth={2} />
				<circle cx={40} cy={-8} r={5} fill="#e6fbff" filter="url(#glow)" />
				<path d={`M 90 0 Q 150 ${-20 + sw} 210 ${10 + sw}`} stroke="#dff8ff" strokeWidth={10} fill="none" opacity={0.25} filter="url(#b6)" />
			</g>
			<circle cx={pts[44][0]} cy={pts[44][1]} r={22} fill={shard} opacity={0.8} filter="url(#b10)" />
			<circle cx={pts[44][0]} cy={pts[44][1]} r={6} fill="#fff" filter="url(#b2)" />
		</g>
	);
};

// ---------------------------------------------------------------- 玄鲲：深海里一条大到看不见边的鱼，只看得到一只眼睛和轮廓；旁边一条小船比着
export const Kun: React.FC<{x: number; y: number; s: number; shard: string}> = ({x, y, s, shard}) => {
	const f = useCurrentFrame();
	const sway = Math.sin(f * 0.03) * 8;
	return (
		<g transform={`translate(${x} ${y + sway}) scale(${s})`}>
			<path d="M -520 0 Q -300 -170 120 -150 Q 380 -120 470 -10 Q 380 120 120 150 Q -300 170 -520 0 Z" fill="#7aa6ff" transform="translate(-4 -4)" opacity={0.35} />
			<path d="M -520 0 Q -300 -170 120 -150 Q 380 -120 470 -10 Q 380 120 120 150 Q -300 170 -520 0 Z" fill="#060a18" />
			{/* 尾 */}
			<path d={`M -500 0 L -700 ${-120 + sway * 2} Q -640 0 -700 ${120 + sway * 2} Z`} fill="#060a18" stroke="#7aa6ff" strokeWidth={2} opacity={0.9} />
			{/* 鳍 */}
			<path d="M 40 60 Q 0 190 -120 210 Q -40 130 -40 70 Z" fill="#060a18" stroke="#7aa6ff" strokeWidth={1.5} opacity={0.8} />
			<path d="M -80 -120 Q -160 -240 -280 -250 Q -200 -170 -210 -120 Z" fill="#060a18" stroke="#7aa6ff" strokeWidth={1.5} opacity={0.8} />
			{/* 鳞：一道道弧 */}
			{Array.from({length: 26}).map((_, i) => {
				const xx = -400 + (i % 13) * 60;
				const yy = i < 13 ? -40 : 40;
				return <path key={i} d={`M ${xx} ${yy} q 20 ${yy < 0 ? -26 : 26} 40 0`} stroke="#28407a" strokeWidth={2} fill="none" opacity={0.7} />;
			})}
			<circle cx={330} cy={-40} r={30} fill="#9fd0ff" opacity={0.5} filter="url(#b10)" />
			<circle cx={330} cy={-40} r={14} fill="#e6f3ff" filter="url(#glow)" />
			<circle cx={330} cy={-40} r={5} fill="#060a18" />
			<circle cx={-20} cy={10} r={40} fill={shard} opacity={0.75} filter="url(#b16)" />
			<circle cx={-20} cy={10} r={8} fill="#fff" filter="url(#b2)" />
		</g>
	);
};

// ---------------------------------------------------------------- 天门：一座发光的牌坊（两柱、两道横梁、翘檐的顶），中间是光
export const Gate: React.FC<{x: number; y: number; s: number; open?: number; crack?: number; light?: string; alpha?: number}> = ({x, y, s, open = 0, crack = 0, light = '#fff1c8', alpha = 1}) => {
	const stroke = '#f7dfa0';
	const cracks = Array.from({length: 14}).map((_, i) => {
		let d = `M 0 ${-60 + rnd(i) * 40}`;
		let px = 0;
		let py = -60 + rnd(i) * 40;
		const a = (i / 14) * Math.PI * 2;
		for (let k = 1; k <= 6; k++) {
			px += Math.cos(a + (rnd(i * 9 + k) - 0.5) * 1.2) * 34;
			py += Math.sin(a + (rnd(i * 5 + k) - 0.5) * 1.2) * 34;
			d += ` L ${px.toFixed(1)} ${py.toFixed(1)}`;
		}
		return d;
	});
	return (
		<g transform={`translate(${x} ${y}) scale(${s})`} opacity={alpha}>
			{/* 门里的光 */}
			<rect x={-120} y={-150} width={240} height={330} fill={light} opacity={0.25 + open * 0.75} filter="url(#b26)" />
			<rect x={-100 * (0.2 + open * 0.8)} y={-140} width={200 * (0.2 + open * 0.8)} height={320} fill={light} opacity={0.5 + open * 0.5} filter="url(#b6)" />
			{/* 柱子 */}
			{[-150, 150].map((px) => (
				<g key={px}>
					<rect x={px - 18} y={-180} width={36} height={360} fill="#140f08" stroke={stroke} strokeWidth={2} />
					<rect x={px - 30} y={172} width={60} height={14} fill="#140f08" stroke={stroke} strokeWidth={2} />
				</g>
			))}
			{/* 横梁 */}
			<rect x={-200} y={-190} width={400} height={26} fill="#140f08" stroke={stroke} strokeWidth={2} />
			<rect x={-176} y={-150} width={352} height={16} fill="#140f08" stroke={stroke} strokeWidth={2} />
			{/* 翘檐的顶 */}
			{/* 斗拱：横梁上一排小木块托着檐 */}
			{Array.from({length: 11}).map((_, i) => (
				<rect key={`dg${i}`} x={-165 + i * 31} y={-206} width={16} height={14} fill="#140f08" stroke={stroke} strokeWidth={1} />
			))}
			<path d="M -250 -196 Q -200 -210 -150 -230 L 150 -230 Q 200 -210 250 -196 Q 200 -220 170 -262 L -170 -262 Q -200 -220 -250 -196 Z" fill="#140f08" stroke={stroke} strokeWidth={2.5} />
			{/* 瓦垄 */}
			{Array.from({length: 17}).map((_, i) => {
				const tx = -160 + i * 20;
				return <line key={`w${i}`} x1={tx} y1={-258} x2={tx * 1.08} y2={-232} stroke={stroke} strokeWidth={0.8} opacity={0.5} />;
			})}
			{/* 正脊和两头的吻兽（卷起来的尾） */}
			<rect x={-176} y={-270} width={352} height={10} fill="#140f08" stroke={stroke} strokeWidth={1.5} />
			{[-1, 1].map((sd) => (
				<path key={`o${sd}`} d={`M ${sd * 170} -266 q ${sd * 10} -30 ${sd * 30} -26 q ${sd * 12} 4 ${sd * 2} 16`} fill="none" stroke={stroke} strokeWidth={3} />
			))}
			{/* 翘角上挂的小铃 */}
			{[-1, 1].map((sd) => (
				<circle key={`b${sd}`} cx={sd * 246} cy={-190} r={4} fill={stroke} filter="url(#glow)" />
			))}
			<rect x={-60} y={-300} width={120} height={30} fill="#140f08" stroke={stroke} strokeWidth={2} />
			<text x={0} y={-278} textAnchor="middle" fontSize={20} fill={stroke} fontFamily="'Noto Serif SC', serif" fontWeight={900} letterSpacing={6}>
				天门
			</text>
			{/* 裂纹 */}
			{crack > 0 && (
				<g opacity={crack}>
					{cracks.map((d, i) => (
						<path key={i} d={d} stroke="#fff" strokeWidth={2.5} fill="none" filter="url(#glow)" strokeDasharray={400} strokeDashoffset={400 * (1 - crack)} />
					))}
				</g>
			)}
		</g>
	);
};

// ---------------------------------------------------------------- 人的剪影：老猎人（拄杖、独眼、斗笠）和孩子
export const Elder: React.FC<{x: number; y: number; s: number; rim?: string}> = ({x, y, s, rim = '#ffcf8a'}) => (
	<g transform={`translate(${x} ${y}) scale(${s})`}>
		<path d="M -34 0 L -22 -110 Q 0 -122 22 -110 L 34 0 Z" fill={rim} transform="translate(-2 -2)" opacity={0.7} />
		<path d="M -34 0 L -22 -110 Q 0 -122 22 -110 L 34 0 Z" fill="#0a0806" />
		<circle cx={0} cy={-128} r={15} fill="#0a0806" stroke={rim} strokeWidth={1.2} />
		<path d="M -38 -132 L 0 -156 L 38 -132 Z" fill="#0a0806" stroke={rim} strokeWidth={1.2} />
		<line x1={40} y1={0} x2={52} y2={-150} stroke="#0a0806" strokeWidth={5} />
		<line x1={38} y1={0} x2={50} y2={-150} stroke={rim} strokeWidth={1} opacity={0.8} />
	</g>
);

export const Child: React.FC<{x: number; y: number; s: number; rim?: string}> = ({x, y, s, rim = '#ffcf8a'}) => (
	<g transform={`translate(${x} ${y}) scale(${s})`}>
		<path d="M -18 0 L -12 -58 Q 0 -64 12 -58 L 18 0 Z" fill={rim} transform="translate(-2 -2)" opacity={0.7} />
		<path d="M -18 0 L -12 -58 Q 0 -64 12 -58 L 18 0 Z" fill="#0a0806" />
		<circle cx={0} cy={-72} r={11} fill="#0a0806" stroke={rim} strokeWidth={1} />
	</g>
);

// 一只小船（渡云海）：船身、帆、船头一盏灯
export const Boat: React.FC<{x: number; y: number; s: number; lamp?: string}> = ({x, y, s, lamp = '#ffc46a'}) => {
	const f = useCurrentFrame();
	const rock = Math.sin(f * 0.07) * 2.5;
	return (
		<g transform={`translate(${x} ${y}) scale(${s}) rotate(${rock})`}>
			<path d="M -120 0 Q -100 34 -40 40 L 60 40 Q 120 34 150 -6 Z" fill="#120c08" stroke="#e9b36e" strokeWidth={1.5} />
			<line x1={0} y1={0} x2={0} y2={-170} stroke="#120c08" strokeWidth={5} />
			<path d="M 4 -160 Q 80 -110 86 -20 L 4 -20 Z" fill="#241a12" stroke="#e9b36e" strokeWidth={1.2} opacity={0.95} />
			<path d="M -4 -150 Q -60 -100 -66 -24 L -4 -24 Z" fill="#1b140e" stroke="#e9b36e" strokeWidth={1} opacity={0.9} />
			{/* 船上的人 */}
			<rect x={-60} y={-30} width={12} height={30} fill="#120c08" />
			<circle cx={-54} cy={-36} r={7} fill="#120c08" />
			<line x1={-50} y1={-20} x2={-90} y2={36} stroke="#120c08" strokeWidth={3} />
			{/* 灯 */}
			<line x1={130} y1={-6} x2={150} y2={-44} stroke="#120c08" strokeWidth={3} />
			<circle cx={152} cy={-38} r={7} fill={lamp} filter="url(#glow)" />
			<circle cx={152} cy={-38} r={26} fill={lamp} opacity={0.25} filter="url(#b10)" />
		</g>
	);
};
