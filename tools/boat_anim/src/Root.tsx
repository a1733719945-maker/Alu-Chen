import React from 'react';
import {Composition} from 'remotion';
import {Voyage, W, H} from './Voyage';
import {Ending} from './Ending';

// 1280x720，30 帧/秒。开船 6 秒，成神结局 10 秒。游戏里全屏拉伸播放
export const RemotionRoot: React.FC = () => (
  <>
    <Composition id="Voyage" component={Voyage} durationInFrames={180} fps={30} width={W} height={H} />
    <Composition id="Ending" component={Ending} durationInFrames={300} fps={30} width={W} height={H} />
  </>
);
