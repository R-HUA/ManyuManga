import { SourceEntry, SourceKind } from '../Sources';
import { definitionFor, sourceDefinitions } from './SourceRegistry';

/** 图源列表的分组归属，由注册表声明，页面不再按 kind 分支。 */
export type SourceSection = 'remote' | 'online' | 'local';

/** 分组自上而下的固定顺序与标题。 */
export const SOURCE_SECTIONS: Array<SourceSection> = ['remote', 'online', 'local'];

export function sourceSectionTitle(section: SourceSection): string {
  if (section === 'remote') {
    return '远程媒体库';
  }
  return section === 'local' ? '本地存储' : '在线画廊';
}

/** 列表分组容器，仅承载"分区 + 该分区条目"。 */
export class SourceSectionBucket {
  section: SourceSection;
  title: string;
  items: Array<SourceEntry> = [];
  constructor(section: SourceSection, title: string) {
    this.section = section;
    this.title = title;
  }
}

/** 声明式界面入口，由 kind 注册表统一发布。 */
export class SourcePresentation {
  kind: SourceKind | null = null;
  shortLabel: string = '';
  description: string = '';
  iconToken: string = 'cloud';
  useAccent: boolean = false;
  section: SourceSection = 'online';
  idJumpPlaceholder: string = '';
  idJumpLabel: string = '';
  registrable: boolean = false;
  defaultName: string = '';
  settingsToken: string = '';
}

export type SourceActionKind = 'route' | 'import' | 'settings' | 'connect' | 'remove';

export class SourceAction {
  label: string;
  kind: SourceActionKind;
  route: string;
  primary: boolean;
  danger: boolean;
  requiresEnabled: boolean;
  constructor(label: string, kind: SourceActionKind, route: string = '', primary: boolean = false,
    danger: boolean = false, requiresEnabled: boolean = false) {
    this.label = label;
    this.kind = kind;
    this.route = route;
    this.primary = primary;
    this.danger = danger;
    this.requiresEnabled = requiresEnabled;
  }
}

export function presentationFor(kind: SourceKind | null): SourcePresentation {
  return kind === null ? new SourcePresentation() : definitionFor(kind).presentation;
}

export function registrablePresentation(): SourcePresentation | null {
  for (const definition of sourceDefinitions()) {
    if (definition.presentation.registrable) {
      return definition.presentation;
    }
  }
  return null;
}

export function sourceActions(entry: SourceEntry): Array<SourceAction> {
  return definitionFor(entry.kind).actions;
}
