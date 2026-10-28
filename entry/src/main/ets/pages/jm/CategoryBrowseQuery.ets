/** 筛选条件整体替换，避免分类与默认排序分次触发列表重载。 */
export class CategoryBrowseQuery {
  readonly categoryId: string;
  readonly categoryName: string;
  readonly categorySlug: string;
  readonly order: string;
  readonly customQuery: string;

  constructor(categoryId: string = '', categoryName: string = '', categorySlug: string = '',
    order: string = 'mr', customQuery: string = '') {
    this.categoryId = categoryId;
    this.categoryName = categoryName;
    this.categorySlug = categorySlug;
    this.order = order;
    this.customQuery = customQuery;
  }
}
