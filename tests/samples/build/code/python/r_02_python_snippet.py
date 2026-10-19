# Sample Python Script: Simple Shopping Cart Simulator

class ShoppingCart:
    def __init__(self):
        # Initialize an empty dictionary to store items and their prices
        self.cart = {}

    def add_item(self, item_name, price):
        """Add an item to the cart or update its price."""
        self.cart[item_name] = price
        print(f"Added '{item_name}' for ${price:.2f}.")

    def calculate_total(self):
        """Calculate the total cost of all items in the cart."""
        # Using the sum() function with a generator expression
        return sum(self.cart.values())

    def display_cart(self):
        """Display all items and the final total."""
        print("\n--- Your Shopping Cart ---")
        if not self.cart:
            print("Your cart is empty.")
            return

        for item, price in self.cart.items():
            print(f"- {item}: ${price:.2f}")