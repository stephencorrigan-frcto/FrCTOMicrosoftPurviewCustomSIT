def test_total():
    cart = ShoppingCart()
    cart.add_item("pen", 2.5)
    assert cart.calculate_total() == 2.5