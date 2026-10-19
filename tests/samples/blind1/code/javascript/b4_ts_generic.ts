function first<T>(items: T[]): T | undefined {
  return items.length ? items[0] : undefined;
}