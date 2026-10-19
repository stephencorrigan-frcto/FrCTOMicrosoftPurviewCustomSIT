[ApiController]
[Route("api/[controller]")]
public class PricesController : ControllerBase
{
    [HttpGet("{symbol}")]
    public IActionResult Get(string symbol) => Ok(_svc.Latest(symbol));
}