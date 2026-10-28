import { SourceKind } from '../Sources';
import { SourceCapabilities, SourceStrategy } from './SourceContracts';
import { SourceAction, SourcePresentation } from './SourceCatalog';
import { jmStrategy } from './JmStrategy';
import { ehStrategy } from './EhStrategy';
import { localStrategy } from './LocalStrategy';
import { suwayomiStrategy } from './SuwayomiStrategy';
import { ROUTE_EH_BROWSE, ROUTE_JM_BROWSE, ROUTE_JM_SETTINGS, ROUTE_BLOCK_RULES, ROUTE_SOURCE_BROWSE } from '../../common/Route';

export class SourceDefinition {
  kind: SourceKind;
  strategy: SourceStrategy;
  capabilities: SourceCapabilities = new SourceCapabilities();
  presentation: SourcePresentation = new SourcePresentation();
  actions: Array<SourceAction> = [];
  constructor(kind: SourceKind, strategy: SourceStrategy) {
    this.kind = kind;
    this.strategy = strategy;
    this.capabilities.kind = kind;
    this.presentation.kind = kind;
  }
}

let registry: Map<SourceKind, SourceDefinition> | null = null;

function createRegistry(): Map<SourceKind, SourceDefinition> {
  const definitions: Map<SourceKind, SourceDefinition> = new Map();
  const jm: SourceDefinition = new SourceDefinition('jm', jmStrategy);
  jm.capabilities.comments = true;
  jm.capabilities.idJump = true;
  jm.capabilities.idJumpNumeric = true;
  jm.capabilities.pageRestore = true;
  jm.capabilities.computedCover = true;
  jm.capabilities.latest = true;
  jm.capabilities.random = true;
  jm.capabilities.ranking = true;
  jm.capabilities.categories = true;
  jm.capabilities.domainTest = true;
  jm.presentation.shortLabel = '禁漫天堂';
  jm.presentation.description = '精选推荐、分类检索与镜像测速';
  jm.presentation.useAccent = true;
  jm.presentation.idJumpPlaceholder = '输入 JM 纯数字车号直达详情…';
  jm.presentation.idJumpLabel = '车号直达';
  jm.presentation.defaultName = '禁漫';
  jm.presentation.section = 'online';
  jm.actions = [new SourceAction('进入发现', 'route', ROUTE_JM_BROWSE, true, false, true),
    new SourceAction('节点设置', 'route', ROUTE_JM_SETTINGS)];
  definitions.set(jm.kind, jm);

  const eh: SourceDefinition = new SourceDefinition('eh', ehStrategy);
  eh.capabilities.comments = true;
  eh.capabilities.idJump = true;
  eh.capabilities.signedCover = true;
  eh.presentation.shortLabel = 'E-Hentai';
  eh.presentation.description = '画廊广场、排行榜与标签汉化';
  eh.presentation.iconToken = 'gallery';
  eh.presentation.useAccent = true;
  eh.presentation.idJumpPlaceholder = '粘贴画廊链接或 GID/Token…';
  eh.presentation.idJumpLabel = '画廊直达';
  eh.presentation.defaultName = 'E-Hentai / ExHentai';
  eh.presentation.section = 'online';
  eh.presentation.settingsToken = 'eh.site';
  eh.actions = [new SourceAction('进入画廊广场', 'route', ROUTE_EH_BROWSE, true, false, true),
    new SourceAction('站点与账号', 'settings')];
  definitions.set(eh.kind, eh);

  const local: SourceDefinition = new SourceDefinition('local', localStrategy);
  local.capabilities.searchPaging = false;
  local.capabilities.importPackage = true;
  local.presentation.shortLabel = '本地';
  local.presentation.description = '本地 CBZ / ZIP 归档与目录';
  local.presentation.iconToken = 'folder';
  local.presentation.defaultName = '本地漫画';
  local.presentation.section = 'local';
  local.actions = [new SourceAction('本地漫画', 'route', ROUTE_SOURCE_BROWSE, true, false, true),
    new SourceAction('导入漫画包', 'import', '', false, false, true), new SourceAction('本源屏蔽规则', 'route', ROUTE_BLOCK_RULES)];
  definitions.set(local.kind, local);

  const remote: SourceDefinition = new SourceDefinition('suwayomi', suwayomiStrategy);
  remote.capabilities.signedCover = true;
  remote.presentation.shortLabel = '扩展';
  remote.presentation.iconToken = 'drive';
  remote.presentation.registrable = true;
  remote.presentation.defaultName = 'Suwayomi';
  remote.presentation.section = 'remote';
  remote.actions = [new SourceAction('浏览漫画', 'route', ROUTE_SOURCE_BROWSE, true, false, true),
    new SourceAction('连接配置', 'connect'), new SourceAction('移除', 'remove', '', false, true),
    new SourceAction('本源屏蔽规则', 'route', ROUTE_BLOCK_RULES)];
  definitions.set(remote.kind, remote);
  return definitions;
}

export function sourceDefinitions(): Array<SourceDefinition> {
  if (registry === null) {
    registry = createRegistry();
  }
  return Array.from(registry.values());
}

export function definitionFor(kind: SourceKind): SourceDefinition {
  sourceDefinitions();
  const definition: SourceDefinition | undefined = registry === null ? undefined : registry.get(kind);
  if (definition === undefined) {
    throw new Error(`未注册的图源类型：${kind}`);
  }
  return definition;
}

export function registeredSourceKind(value: string): SourceKind | null {
  for (const definition of sourceDefinitions()) {
    if (definition.kind === value) {
      return definition.kind;
    }
  }
  return null;
}

export function isRegisteredSourceKind(value: string): boolean {
  return registeredSourceKind(value) !== null;
}
