import React from 'react';
import {Composition} from 'remotion';
import {Voyage} from './Voyage';

// 960x540，30 帧/秒，5 秒。游戏里全屏拉伸播放
export const RemotionRoot: React.FC = () => (
  <Composition id="Voyage" component={Voyage} durationInFrames={150} fps={30} width={960} height={540} />
);