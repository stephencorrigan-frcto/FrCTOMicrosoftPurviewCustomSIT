class ShoppingCart:
def __init__(self):
self.cart = {}
def add_item(self, item_name, price):
self.cart[item_name] = price
print(f"Added {item_name}")
def calculate_total(self):
return sum(self.cart.values())