import React from 'react';
import {AbsoluteFill} from 'remotion';
import {Defs, rnd} from './lib';

// ================================================================ 灵相立绘：灵葫（替换原来那张图）
export const Gourd: React.FC = () => (
	<AbsoluteFill style={{background: '#000'}}>
		<svg width={384} height={384}>
			<Defs />
			<defs>
				<radialGradient id="gd_bg" cx="50%" cy="55%" r="70%">
					<stop offset="0%" stopColor="#3a1e08" />
					<stop offset="100%" stopColor="#050302" />
				</radialGradient>
				<radialGradient id="gd_body" cx="38%" cy="35%" r="70%">
					<stop offset="0%" stopColor="#fff0b8" />
					<stop offset="35%" stopColor="#f0a33a" />
					<stop offset="100%" stopColor="#7a3a0c" />
				</radialGradient>
			</defs>
			<rect width={384} height={384} fill="url(#gd_bg)" />
			{Array.from({length: 7}).map((_, i) => (
				<path
					key={i}
					d={`M ${192 + Math.cos(i) * 20} 200 C ${60 + i * 30} ${80 + i * 20}, ${300 - i * 20} ${40 + i * 25}, ${150 + i * 18} ${380}`}
					stroke="#ffc25a"
					strokeWidth={1.4 + (i % 3)}
					fill="none"
					opacity={0.35}
					filter="url(#b2)"
				/>
			))}
			<circle cx={192} cy={220} r={150} fill="#ffb040" opacity={0.25} filter="url(#b40)" />
			<g transform="translate(192 205) rotate(-18)">
				<ellipse cx={0} cy={48} rx={78} ry={74} fill="url(#gd_body)" />
				<ellipse cx={0} cy={-38} rx={48} ry={44} fill="url(#gd_body)" />
				<rect x={-18} y={-6} width={36} height={16} fill="#8a3e0e" />
				<rect x={-10} y={-96} width={20} height={16} rx={4} fill="#5a2a0a" />
				<path d="M -12 -2 Q -40 30 -30 70" stroke="#c0301c" strokeWidth={5} fill="none" />
				<ellipse cx={-26} cy={20} rx={16} ry={30} fill="#fff" opacity={0.25} filter="url(#b4)" />
				<path d="M 0 -96 Q 20 -150 60 -160" stroke="#fff2c0" strokeWidth={3} fill="none" filter="url(#glow)" />
			</g>
			{Array.from({length: 40}).map((_, i) => (
				<circle key={i} cx={rnd(i) * 384} cy={rnd(i * 3) * 384} r={0.8 + rnd(i * 7) * 2.2} fill="#ffe0a0" opacity={0.3 + rnd(i * 9) * 0.7} filter="url(#b1)" />
			))}
		</svg>
	</AbsoluteFill>
);
