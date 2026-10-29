/** 单章下载状态：none 未下载 / queued 排队 / running 下载中 / done 已完成 / failed 失败 */
export class ChapterDownloadInfo {
  state: string = 'none';
  done: number = 0;
  total: number = 0;

  constructor(state: string = 'none', done: number = 0, total: number = 0) {
    this.state = state;
    this.done = done;
    this.total = total;
  }
}
