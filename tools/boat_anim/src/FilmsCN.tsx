import React from 'react';
import {Film, Label, Shot, Sub, VTitle} from './cine';

// 国风版过场（画面是用户用 AI 生成的图，ai/NN → public/art/aiNN.jpg，prep_ai.py 裁水印）。
// 先做一段试片看感觉：第 1 张（九重天）+ 流云 + 天光 + 竖排题字和印章。
export const CNTEST_FRAMES = 240;
export const CNTest: React.FC = () => (
	<Film total={CNTEST_FRAMES} fadeIn={20} fadeOut={14}>
		<Shot art="ai01" from={0} to={240} fadeIn={0} fadeOut={0} a={[0.46, 0.6, 1.0]} b={[0.62, 0.4, 1.24]} fx="clouds" grade={{sat: 1.0, con: 1.04, bri: 0.97, sepia: 0.0, warm: 0.12}} rays={{x: 0.2, y: 0.28, a: 0.45}} glow={{x: 0.2, y: 0.28, r: 360, color: 'rgba(255,236,190,1)', a: 0.35}} />
		<Label top="太 初" sub="九重天 · 天门" from={16} to={150} />
		<Sub zh="上古之时，天有九重。" en="In the beginning, the heavens rose in nine tiers." from={20} to={100} />
		<Sub zh="人间与九天之间，立着一座天门。" en="Between the mortal world and the heavens stood a single gate." from={104} to={168} />
		<VTitle text="苍墟" sub="猎灵 · 炼环 · 破境 · 叩天" x={1660} y={150} size={140} from={164} to={240} seal="猎灵" />
	</Film>
);
