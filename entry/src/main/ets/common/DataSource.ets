/** LazyForEach 共享数据源，统一维护监听器与逐项追加通知。 */
export class BasicDataSource<T> implements IDataSource {
  private items: Array<T> = [];
  private listeners: Array<DataChangeListener> = [];
  totalCount(): number { return this.items.length; }
  getData(index: number): T { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) { this.listeners.push(listener); }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener) => item !== listener);
  }
  setList(items: Array<T>): void {
    this.items = items.slice();
    for (const listener of this.listeners) { listener.onDataReloaded(); }
  }
  appendItems(items: Array<T>): void {
    const start: number = this.items.length;
    this.items = this.items.concat(items);
    for (const listener of this.listeners) {
      for (let index: number = start; index < this.items.length; index++) { listener.onDataAdd(index); }
    }
  }
}
