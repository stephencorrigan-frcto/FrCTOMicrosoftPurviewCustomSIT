@RestController
@RequestMapping("/api/prices")
public class PriceController {
    @GetMapping("/{symbol}")
    public ResponseEntity<Double> latest(@PathVariable String symbol) {
        return ResponseEntity.ok(service.latest(symbol));
    }
}