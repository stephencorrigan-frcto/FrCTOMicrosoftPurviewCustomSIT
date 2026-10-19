class Trade {
    [string]$Symbol
    [int]$Qty
    Trade([string]$s, [int]$q) { $this.Symbol = $s; $this.Qty = $q }
}