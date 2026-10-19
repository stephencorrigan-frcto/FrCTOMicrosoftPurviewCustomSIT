public synchronized void add(Trade t) {
    trades.add(t);
    notifyAll();
}