private decimal _price;
public decimal Price
{
    get => _price;
    set { _price = value; OnPropertyChanged(); }
}