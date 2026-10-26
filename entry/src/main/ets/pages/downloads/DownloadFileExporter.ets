import { DownloadTask } from '../../data/DownloadManager';
import { ExportJob, saveExportJob } from '../../data/BatchExport';

/** 保留任务卡片的保存入口，所有导出行为统一由同一服务完成。 */
export function saveDownload(task: DownloadTask): Promise<boolean> {
  const job: ExportJob = new ExportJob();
  job.albumId = task.albumId;
  job.title = task.title;
  job.taskId = task.id;
  job.sourcePath = task.savedTo;
  return saveExportJob(job);
}
