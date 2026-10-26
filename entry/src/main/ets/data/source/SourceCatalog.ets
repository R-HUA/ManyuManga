import { SourceEntry, SourceKind } from '../Sources';
import { definitionFor, sourceDefinitions } from './SourceRegistry';

/** 声明式界面入口，由 kind 注册表统一发布。 */
export class SourcePresentation {
  kind: SourceKind | null = null;
  shortLabel: string = '';
  description: string = '';
  describeEndpoint: boolean = false;
  iconToken: string = 'cloud';
  useAccent: boolean = false;
  idJumpPlaceholder: string = '';
  idJumpLabel: string = '';
  registrable: boolean = false;
  defaultName: string = '';
  settingsToken: string = '';
}

export type SourceActionKind = 'route' | 'search' | 'import' | 'settings' | 'connect' | 'remove';

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

export function sourceSubtitle(entry: SourceEntry): string {
  const pres: SourcePresentation = presentationFor(entry.kind);
  return pres.describeEndpoint ? `${entry.language === '' ? '' : entry.language + ' · '}${entry.endpoint}` : pres.description;
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
