public event EventHandler<PriceEventArgs> PriceChanged;
protected virtual void OnPriceChanged(PriceEventArgs e) => PriceChanged?.Invoke(this, e);