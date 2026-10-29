/**
 * entry/src/main/ets/data/ReaderTapGuard.ets
 * 阅读器点按判定：只有「单指、位移小、按压短、画面未在滚动/翻页动画」的触摸才算点按，
 * 滑动、拖拽、甩动、捏合、长按以及翻页动画刚结束时的余波都不会触发热区动作。
 */

/** 按下到抬起的最大位移（vp），超过即视为滑动。 */
export const TAP_SLOP_VP: number = 10;
/** 按下到抬起的最长时长（ms），超过即视为长按。 */
export const TAP_MAX_MS: number = 300;
/** 滚动或翻页动画结束后的静默期（ms），期间到达的点按一律忽略。 */
export const TAP_SETTLE_MS: number = 150;
/** 左右翻页热区各占宽度比例，中间呼出菜单区域占其余部分。 */
export const TAP_SIDE_RATIO: number = 0.25;

/** 热区动作：0 呼出菜单、1 左侧（按阅读方向翻页）、2 右侧。 */
export function tapZoneAction(x: number, width: number, tapTurn: boolean): number {
  if (!tapTurn || width <= 0) {
    return 0;
  }
  if (x < width * TAP_SIDE_RATIO) {
    return 1;
  }
  if (x > width * (1 - TAP_SIDE_RATIO)) {
    return 2;
  }
  return 0;
}

export class ReaderTapGuard {
  private downAt: number = -1;
  private upAt: number = -1;
  private startX: number = 0;
  private startY: number = 0;
  private maxMove: number = 0;
  private maxFingers: number = 0;
  private moving: boolean = false;
  private motionEndAt: number = -1;

  /** 手指按下：新序列开始；多指按下时只累加指数，不重置起点。 */
  down(x: number, y: number, fingers: number, now: number): void {
    if (this.downAt < 0 || this.upAt >= 0) {
      this.downAt = now;
      this.upAt = -1;
      this.startX = x;
      this.startY = y;
      this.maxMove = 0;
      this.maxFingers = 0;
    }
    this.maxFingers = Math.max(this.maxFingers, fingers);
  }

  move(x: number, y: number, fingers: number): void {
    if (this.downAt < 0) {
      return;
    }
    const dx: number = x - this.startX;
    const dy: number = y - this.startY;
    this.maxMove = Math.max(this.maxMove, Math.sqrt(dx * dx + dy * dy));
    this.maxFingers = Math.max(this.maxFingers, fingers);
  }

  up(x: number, y: number, now: number): void {
    this.move(x, y, 0);
    this.upAt = now;
  }

  /** 触摸被系统取消（如被父级手势抢占）时整段作废。 */
  cancel(): void {
    this.maxFingers = 99;
  }

  /** 列表滚动 / 翻页动画开始或结束；结束时间用于静默期判断。 */
  motion(active: boolean, now: number): void {
    this.moving = active;
    this.motionEndAt = now;
  }

  /** 动画/滚动中的每一帧：持续刷新静默期起点。 */
  motionTick(now: number): void {
    this.motionEndAt = now;
  }

  accept(now: number): boolean {
    if (this.downAt < 0 || this.moving) {
      return false;
    }
    if (this.motionEndAt >= 0 && now - this.motionEndAt < TAP_SETTLE_MS) {
      return false;
    }
    if (this.maxFingers > 1 || this.maxMove >= TAP_SLOP_VP) {
      return false;
    }
    const end: number = this.upAt >= 0 ? this.upAt : now;
    return end - this.downAt <= TAP_MAX_MS;
  }

  /** 双击只排除多指与滑动，时长由系统双击识别器约束。 */
  acceptDouble(): boolean {
    return !this.moving && this.maxFingers <= 1 && this.maxMove < TAP_SLOP_VP;
  }
}
