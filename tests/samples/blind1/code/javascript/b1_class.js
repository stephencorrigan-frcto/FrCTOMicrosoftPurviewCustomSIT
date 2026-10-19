class Cache {
  constructor(ttl) { this.ttl = ttl; this.store = new Map(); }
  get(key) { return this.store.get(key); }
}